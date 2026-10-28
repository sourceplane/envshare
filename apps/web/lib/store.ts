import "server-only"
import { env } from "./env"

/**
 * Where a shared document lives, and how it is counted.
 *
 * The template kept each document as one Redis hash — the ciphertext, the
 * IV and `remainingReads` — with Redis's own EXPIRE, and decremented the
 * count with HINCRBY. Here the two halves go where each is honest:
 *
 * - the CIPHERTEXT goes to Workers KV (`SECRETS`), written with KV's
 *   `expirationTtl`, so it disappears when the document's TTL runs out;
 * - the READ LIMIT and the EXPIRY go to D1 (`DB`, table `secrets`). KV is
 *   eventually consistent: two reads of a document's last remaining read in
 *   two places could each see "1 left" and each be served. D1 decrements
 *   in one statement — `… SET remaining_reads = remaining_reads - 1 WHERE
 *   … remaining_reads > 0 RETURNING` — so of two concurrent last reads
 *   exactly one gets a row back, and the other is told the document is gone.
 *
 * The server only ever holds ciphertext: the browser encrypts with AES-GCM
 * and keeps the key in the link's fragment, which is never sent (pkg/).
 */

/** KV's floor for `expirationTtl`, in seconds. A shorter TTL is raised to it. */
export const KV_MIN_TTL_SECONDS = 60

/** What a document is stored as: the share page's ciphertext and IV, or the API's opaque secret. */
export type Stored = { encrypted: string; iv: string } | { secret: string }

const kvKey = (id: string) => `secret:${id}`

/**
 * The TTL a document is stored with, in whole seconds: none for 0, negative
 * or missing (the template's "0 means no TTL"), else at least KV's floor.
 */
export function effectiveTtl(ttl: number | null | undefined): number | null {
  if (typeof ttl !== "number" || !Number.isFinite(ttl) || ttl <= 0) return null
  return Math.max(KV_MIN_TTL_SECONDS, Math.ceil(ttl))
}

/**
 * Store a document under `id`. The D1 row goes first: if the KV write then
 * fails, a read finds no ciphertext and answers "not found" — never a
 * document without its limit. Each write also sweeps rows whose TTL has run
 * out, so the table holds only live documents.
 */
export async function putSecret(
  id: string,
  value: Stored,
  options: { ttl: number | null | undefined; reads: number | null | undefined },
): Promise<{ ttl: number | null; reads: number | null; expiresAt: number | null }> {
  const { DB, SECRETS } = env()
  const ttl = effectiveTtl(options.ttl)
  const reads = typeof options.reads === "number" && options.reads > 0 ? Math.floor(options.reads) : null
  const now = Date.now()
  const expiresAt = ttl === null ? null : now + ttl * 1000
  await DB.batch([
    DB.prepare("DELETE FROM secrets WHERE expires_at IS NOT NULL AND expires_at <= ?").bind(now),
    DB.prepare("INSERT INTO secrets (id, remaining_reads, expires_at, created_at) VALUES (?, ?, ?, ?)").bind(
      id,
      reads,
      expiresAt,
      now,
    ),
    DB.prepare("UPDATE metrics SET value = value + 1 WHERE name = 'writes'"),
  ])
  await SECRETS.put(kvKey(id), JSON.stringify(value), ttl === null ? undefined : { expirationTtl: ttl })
  return { ttl, reads, expiresAt }
}

/**
 * Read a document once: its stored value and the reads left after this one
 * (`null` when unlimited), or `null` when there is none to read — never
 * stored, expired, or its last read already taken.
 *
 * The ciphertext is read BEFORE the count is spent: a KV read that misses
 * (an expired key, or a write not yet visible where this request runs) costs
 * the reader nothing, and the link still works on a retry. The last read
 * deletes both halves at once.
 */
export async function takeSecret(id: string): Promise<{ value: Stored; remainingReads: number | null } | null> {
  const { DB, SECRETS } = env()
  const now = Date.now()
  // The template counted every load, found or not.
  await DB.prepare("UPDATE metrics SET value = value + 1 WHERE name = 'reads'").run()

  const raw = await SECRETS.get(kvKey(id))
  if (raw === null) {
    await DB.prepare("DELETE FROM secrets WHERE id = ? AND expires_at IS NOT NULL AND expires_at <= ?")
      .bind(id, now)
      .run()
    return null
  }

  const row = await DB.prepare(
    "UPDATE secrets SET remaining_reads = remaining_reads - 1 " +
      "WHERE id = ? AND (expires_at IS NULL OR expires_at > ?) AND (remaining_reads IS NULL OR remaining_reads > 0) " +
      "RETURNING remaining_reads",
  )
    .bind(id, now)
    .first<{ remaining_reads: number | null }>()

  if (!row) {
    // Expired, exhausted by a concurrent read, or never counted: nothing to serve.
    await Promise.all([SECRETS.delete(kvKey(id)), DB.prepare("DELETE FROM secrets WHERE id = ?").bind(id).run()])
    return null
  }
  if (row.remaining_reads === 0) {
    await Promise.all([SECRETS.delete(kvKey(id)), DB.prepare("DELETE FROM secrets WHERE id = ?").bind(id).run()])
  }
  return { value: JSON.parse(raw) as Stored, remainingReads: row.remaining_reads }
}

/** The home page's two counters (the template's metrics:{reads,writes} Redis counters). */
export async function metrics(): Promise<{ reads: number; writes: number }> {
  const { results } = await env()
    .DB.prepare("SELECT name, value FROM metrics WHERE name IN ('reads', 'writes')")
    .all<{ name: string; value: number }>()
  const of = (name: string) => results.find((r) => r.name === name)?.value ?? 0
  return { reads: of("reads"), writes: of("writes") }
}
