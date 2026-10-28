import { beforeEach, describe, expect, it, vi } from "vitest";
import { d1, kv, sqlite, type Sqlite } from "./support/bindings";

// The Worker's API routes, called as the Worker calls them, over the fake
// bindings: the share page's /api/v1/store and /api/v1/load, the HTTP API's
// /api/v1/secret, and the deploy's /api/health.
let db: Sqlite;
let secrets: ReturnType<typeof kv>;
const env: Record<string, unknown> = {};
vi.mock("@opennextjs/cloudflare", () => ({ getCloudflareContext: () => ({ env }) }));

beforeEach(() => {
  db = sqlite();
  secrets = kv();
  for (const k of Object.keys(env)) delete env[k];
  Object.assign(env, { DB: d1(db), SECRETS: secrets });
  vi.resetModules();
});

const site = "https://site.test";

describe("POST /api/v1/store and GET /api/v1/load (the share and unseal pages)", () => {
  it("stores ciphertext, then serves it until its reads run out", async () => {
    const { POST } = await import("@web/app/api/v1/store/route");
    const { GET } = await import("@web/app/api/v1/load/route");
    const res = await POST(
      new Request(`${site}/api/v1/store`, { method: "POST", body: JSON.stringify({ encrypted: "c", iv: "i", ttl: 3600, reads: 2 }) }),
    );
    expect(res.status).toBe(200);
    const { id } = (await res.json()) as { id: string };
    expect(id).toMatch(/^[1-9A-HJ-NP-Za-km-z]+$/);

    const first = await GET(new Request(`${site}/api/v1/load?id=${id}`));
    expect(await first.json()).toEqual({ iv: "i", encrypted: "c", remainingReads: 1 });
    const second = await GET(new Request(`${site}/api/v1/load?id=${id}`));
    expect(await second.json()).toEqual({ iv: "i", encrypted: "c", remainingReads: 0 });
    const third = await GET(new Request(`${site}/api/v1/load?id=${id}`));
    expect(third.status).toBe(404);
    expect(await third.text()).toBe("Not Found");
  });

  it("refuses a body without ciphertext and IV, storing nothing", async () => {
    const { POST } = await import("@web/app/api/v1/store/route");
    for (const body of ["not json", JSON.stringify({ encrypted: "c" }), JSON.stringify({ iv: "i" }), JSON.stringify({ encrypted: "", iv: "i" })]) {
      const res = await POST(new Request(`${site}/api/v1/store`, { method: "POST", body }));
      expect(res.status, body).toBe(400);
    }
    expect(secrets.values.size).toBe(0);
  });

  it("asks for the id", async () => {
    const { GET } = await import("@web/app/api/v1/load/route");
    const res = await GET(new Request(`${site}/api/v1/load`));
    expect(res.status).toBe(400);
    expect(await res.text()).toBe("id param is missing");
  });
});

describe("POST /api/v1/secret and GET /api/v1/secret/:id (the HTTP API)", () => {
  it("stores an already-encrypted secret with the template's defaults, and reads it back", async () => {
    const { POST } = await import("@web/app/api/v1/secret/route");
    const { GET } = await import("@web/app/api/v1/secret/[id]/route");
    const res = await POST(new Request(`${site}/api/v1/secret`, { method: "POST", body: "already-encrypted" }));
    expect(res.status).toBe(200);
    const { data } = (await res.json()) as { data: { id: string; ttl: number; reads?: number; expiresAt: string; url: string } };
    expect(data.ttl).toBe(43260);
    expect(data.reads).toBeUndefined();
    expect(data.url).toBe(`${site}/api/v1/secret/${data.id}`);
    expect(new Date(data.expiresAt).getTime()).toBeGreaterThan(Date.now());

    const read = await GET(new Request(data.url), { params: Promise.resolve({ id: data.id }) });
    expect(await read.json()).toEqual({ data: { secret: "already-encrypted" } });
  });

  it("honours the ttl and reads headers, with KV's floor on the ttl", async () => {
    const { POST } = await import("@web/app/api/v1/secret/route");
    const { GET } = await import("@web/app/api/v1/secret/[id]/route");
    const res = await POST(
      new Request(`${site}/api/v1/secret`, { method: "POST", body: "s", headers: { "envshare-ttl": "10", "envshare-reads": "1" } }),
    );
    const { data } = (await res.json()) as { data: { id: string; ttl: number; reads: number } };
    expect(data).toMatchObject({ ttl: 60, reads: 1 });
    const params = { params: Promise.resolve({ id: data.id }) };
    expect(await (await GET(new Request(`${site}/x`), params)).json()).toEqual({ data: { secret: "s", remainingReads: 0 } });
    expect((await GET(new Request(`${site}/x`), params)).status).toBe(404);
  });

  it("stores no expiry for a ttl of 0", async () => {
    const { POST } = await import("@web/app/api/v1/secret/route");
    const res = await POST(new Request(`${site}/api/v1/secret`, { method: "POST", body: "s", headers: { "envshare-ttl": "0" } }));
    const { data } = (await res.json()) as { data: { ttl?: number; expiresAt?: string } };
    expect(data.ttl).toBeUndefined();
    expect(data.expiresAt).toBeUndefined();
  });

  it("refuses an empty secret, a negative ttl and zero reads", async () => {
    const { POST } = await import("@web/app/api/v1/secret/route");
    const bad: { body: string; headers: Record<string, string> }[] = [
      { body: "", headers: {} },
      { body: "s", headers: { "envshare-ttl": "-1" } },
      { body: "s", headers: { "envshare-ttl": "30758401" } },
      { body: "s", headers: { "envshare-reads": "-2" } },
    ];
    for (const b of bad) {
      const res = await POST(new Request(`${site}/api/v1/secret`, { method: "POST", body: b.body, headers: b.headers }));
      expect(res.status, JSON.stringify(b)).toBe(400);
    }
    expect(secrets.values.size).toBe(0);
  });

  it("answers 404 for an unknown id", async () => {
    const { GET } = await import("@web/app/api/v1/secret/[id]/route");
    const res = await GET(new Request(`${site}/x`), { params: Promise.resolve({ id: "nope" }) });
    expect(res.status).toBe(404);
  });
});

describe("GET /api/health", () => {
  it("counts the documents through the DB binding and touches KV, spending no read", async () => {
    const { putSecret } = await import("lib/store");
    await putSecret("h", { secret: "s" }, { ttl: 60, reads: 1 });
    const { GET } = await import("@web/app/api/health/route");
    expect(await (await GET()).json()).toEqual({ ok: true, documents: 1 });
    expect(db.prepare("SELECT remaining_reads FROM secrets WHERE id = 'h'").all()[0]!.remaining_reads).toBe(1);
  });
});
