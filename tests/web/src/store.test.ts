import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { d1, kv, sqlite, type Sqlite } from "./support/bindings";

// lib/store.ts over D1 (real SQLite, the migrations applied) and KV: where a
// document's ciphertext and its read limit live, and why the limit holds.
let db: Sqlite;
let secrets: ReturnType<typeof kv>;
const env: Record<string, unknown> = {};
vi.mock("@opennextjs/cloudflare", () => ({ getCloudflareContext: () => ({ env }) }));

const row = (id: string) => db.prepare("SELECT * FROM secrets WHERE id = ?").all(id)[0];
const metric = (name: string) => db.prepare("SELECT value FROM metrics WHERE name = ?").all(name)[0]?.value;

beforeEach(() => {
  db = sqlite();
  secrets = kv();
  for (const k of Object.keys(env)) delete env[k];
  Object.assign(env, { DB: d1(db), SECRETS: secrets });
  vi.resetModules();
});
afterEach(() => vi.useRealTimers());

describe("putSecret", () => {
  it("keeps the ciphertext in KV and the read limit and expiry in D1", async () => {
    const { putSecret } = await import("lib/store");
    const out = await putSecret("doc1", { encrypted: "c1pher", iv: "1v" }, { ttl: 3600, reads: 3 });
    expect(out.ttl).toBe(3600);
    expect(JSON.parse(secrets.values.get("secret:doc1")!.value)).toEqual({ encrypted: "c1pher", iv: "1v" });
    expect(secrets.values.get("secret:doc1")!.ttl).toBe(3600);
    expect(row("doc1")).toMatchObject({ remaining_reads: 3 });
    expect(row("doc1")!.expires_at).toBe(out.expiresAt);
    expect(metric("writes")).toBe(1);
  });

  it("raises a TTL under KV's 60-second floor to it, and stores none for 0", async () => {
    const { putSecret, KV_MIN_TTL_SECONDS } = await import("lib/store");
    expect(KV_MIN_TTL_SECONDS).toBe(60);
    expect((await putSecret("a", { secret: "x" }, { ttl: 30, reads: null })).ttl).toBe(60);
    expect(secrets.values.get("secret:a")!.ttl).toBe(60);
    expect((await putSecret("b", { secret: "x" }, { ttl: 0, reads: null })).ttl).toBeNull();
    expect(secrets.values.get("secret:b")!.ttl).toBeUndefined();
    expect(row("b")!.expires_at).toBeNull();
  });

  it("treats 0 or no reads as unlimited (the template's rule)", async () => {
    const { putSecret } = await import("lib/store");
    await putSecret("u", { secret: "x" }, { ttl: 60, reads: 0 });
    expect(row("u")!.remaining_reads).toBeNull();
  });

  it("sweeps the rows whose TTL ran out on the next write", async () => {
    vi.useFakeTimers();
    const { putSecret } = await import("lib/store");
    await putSecret("old", { secret: "x" }, { ttl: 60, reads: 1 });
    vi.setSystemTime(Date.now() + 61_000);
    await putSecret("new", { secret: "y" }, { ttl: 60, reads: 1 });
    expect(row("old")).toBeUndefined();
    expect(row("new")).toBeDefined();
  });
});

describe("takeSecret", () => {
  it("spends one read each time, deletes both halves on the last, and finds nothing after", async () => {
    const { putSecret, takeSecret } = await import("lib/store");
    await putSecret("doc", { encrypted: "c", iv: "i" }, { ttl: 600, reads: 2 });
    expect(await takeSecret("doc")).toEqual({ value: { encrypted: "c", iv: "i" }, remainingReads: 1 });
    expect(await takeSecret("doc")).toEqual({ value: { encrypted: "c", iv: "i" }, remainingReads: 0 });
    expect(secrets.values.has("secret:doc")).toBe(false);
    expect(row("doc")).toBeUndefined();
    expect(await takeSecret("doc")).toBeNull();
    expect(metric("reads")).toBe(3);
  });

  it("reads an unlimited document as often as asked", async () => {
    const { putSecret, takeSecret } = await import("lib/store");
    await putSecret("u", { secret: "s" }, { ttl: 0, reads: null });
    for (let i = 0; i < 5; i++) expect(await takeSecret("u")).toEqual({ value: { secret: "s" }, remainingReads: null });
  });

  it("serves exactly one of two concurrent last reads", async () => {
    const { putSecret, takeSecret } = await import("lib/store");
    await putSecret("last", { encrypted: "c", iv: "i" }, { ttl: 600, reads: 1 });
    const [a, b] = await Promise.all([takeSecret("last"), takeSecret("last")]);
    expect([a, b].filter((r) => r !== null)).toHaveLength(1);
    expect(secrets.values.has("secret:last")).toBe(false);
    expect(row("last")).toBeUndefined();
  });

  it("refuses an expired document, even while a stale copy is still in KV", async () => {
    vi.useFakeTimers();
    const { putSecret, takeSecret } = await import("lib/store");
    await putSecret("exp", { secret: "s" }, { ttl: 60, reads: 5 });
    vi.setSystemTime(Date.now() + 61_000);
    // KV has expired it too (the fake honours the TTL); force the stale case:
    secrets.values.set("secret:exp", { value: JSON.stringify({ secret: "s" }) });
    expect(await takeSecret("exp")).toBeNull();
    expect(row("exp")).toBeUndefined();
    expect(secrets.values.has("secret:exp")).toBe(false);
  });

  it("spends no read when the ciphertext is not visible yet, so a retry still works", async () => {
    const { putSecret, takeSecret } = await import("lib/store");
    await putSecret("lag", { secret: "s" }, { ttl: 600, reads: 1 });
    secrets.hide("secret:lag");
    expect(await takeSecret("lag")).toBeNull();
    expect(row("lag")!.remaining_reads).toBe(1);
    expect(await takeSecret("lag")).toEqual({ value: { secret: "s" }, remainingReads: 0 });
  });
});

describe("metrics", () => {
  it("counts documents written and loads asked for", async () => {
    const { putSecret, takeSecret, metrics } = await import("lib/store");
    expect(await metrics()).toEqual({ reads: 0, writes: 0 });
    await putSecret("m", { secret: "s" }, { ttl: 60, reads: null });
    await takeSecret("m");
    await takeSecret("missing");
    expect(await metrics()).toEqual({ reads: 2, writes: 1 });
  });
});
