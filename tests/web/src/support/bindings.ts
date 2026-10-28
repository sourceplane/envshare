import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import * as path from "node:path";

// The Worker's bindings for the app's server modules, over real engines where
// one exists: D1 over node:sqlite (D1's engine) with packages/db's migrations
// applied, KV over a Map that honours each key's TTL against the clock.
type Row = Record<string, unknown>;
export interface Sqlite {
  exec(sql: string): void;
  prepare(sql: string): { all(...params: unknown[]): Row[]; run(...params: unknown[]): unknown };
}
const { DatabaseSync } = createRequire(import.meta.url)("node:sqlite") as {
  DatabaseSync: new (file: string) => Sqlite;
};
const migrationsDir = path.resolve(__dirname, "../../../../packages/db/src/migrations");
export const MIGRATIONS = ["010_secrets"];

export function sqlite(names = MIGRATIONS): Sqlite {
  const db = new DatabaseSync(":memory:");
  for (const name of names) db.exec(readFileSync(path.join(migrationsDir, name, "up.sql"), "utf8"));
  return db;
}

/** The D1 binding's shape (prepare → bind → first/all/run, batch) over a SQLite database. */
export function d1(db: Sqlite) {
  const statement = (sql: string, params: unknown[] = []) => ({
    bind: (...values: unknown[]) => statement(sql, values),
    async first<T>() {
      return (db.prepare(sql).all(...params)[0] as T | undefined) ?? null;
    },
    async all<T>() {
      return { results: db.prepare(sql).all(...params).map((r) => ({ ...r })) as T[] };
    },
    async run() {
      db.prepare(sql).run(...params);
      return { success: true };
    },
  });
  return {
    prepare: (sql: string) => statement(sql),
    async batch(statements: { run(): Promise<unknown> }[]) {
      const out = [];
      for (const s of statements) out.push(await s.run());
      return out;
    },
  };
}

/**
 * KV's get/put/delete over a Map. A key PUT with `expirationTtl` stops being
 * returned once the clock (Date.now, which the tests may fake) passes it, as
 * KV expires it; `hide` makes one read miss, as a write not yet visible where
 * a request runs would.
 */
export function kv() {
  const values = new Map<string, { value: string; ttl?: number; expiresAt?: number }>();
  const hidden = new Set<string>();
  return {
    values,
    hide(key: string) {
      hidden.add(key);
    },
    async get(key: string) {
      if (hidden.delete(key)) return null;
      const v = values.get(key);
      if (!v) return null;
      if (v.expiresAt !== undefined && Date.now() >= v.expiresAt) {
        values.delete(key);
        return null;
      }
      return v.value;
    },
    async put(key: string, value: string, opts?: { expirationTtl?: number }) {
      const ttl = opts?.expirationTtl;
      values.set(key, { value, ttl, expiresAt: ttl === undefined ? undefined : Date.now() + ttl * 1000 });
    },
    async delete(key: string) {
      values.delete(key);
    },
  };
}
