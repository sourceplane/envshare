#!/usr/bin/env node
// Applies packages/db's migrations, in manifest order, to wrangler's LOCAL D1
// — the database `next dev` (through wrangler's platform proxy) and
// `wrangler dev` bind as DB. Deployed environments never run this: the
// db-migrate component applies the same files to stage and prod over the D1
// REST API, before the Worker deploys.
//
//   pnpm --filter @app/web db:migrate:local      # runs this from apps/web
//
// Every migration is written idempotently (IF NOT EXISTS), so running it again
// is a no-op. Needs the rendered wrangler.jsonc (committed; `pnpm run
// wire:fixture` re-renders it) and wrangler on PATH (a package script has it).
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const db = resolve(dirname(fileURLToPath(import.meta.url)), "../../packages/db/src");
const paths = [...readFileSync(resolve(db, "manifest.ts"), "utf8").matchAll(/path:\s*"([^"]+)"/g)].map((m) => m[1]);
if (paths.length === 0) {
  console.error("migrations: packages/db/src/manifest.ts lists no migrations");
  process.exit(1);
}
const config = process.argv[2] ?? "wrangler.jsonc";
for (const rel of paths) {
  console.log(`migrations: ${rel} → local D1 (DB)`);
  const r = spawnSync(
    "wrangler",
    ["d1", "execute", "DB", "--local", "--config", config, "--file", resolve(db, "migrations", rel)],
    { stdio: "inherit" },
  );
  if (r.status !== 0) {
    console.error(`migrations: ${rel} failed${r.error ? ` (${r.error.message})` : ""}`);
    process.exit(r.status ?? 1);
  }
}
console.log(`migrations: ${paths.length} applied to the local D1`);
