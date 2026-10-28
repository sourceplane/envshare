// The bindings wrangler.jsonc declares, as the Worker (and `next dev` through
// the platform proxy) sees them.
interface CloudflareEnv {
  /** The shared documents' read limits and expiries, and the site's counters (Cloudflare D1). */
  DB: D1Database;
  /** The shared documents' ciphertext, each with its TTL (Workers KV). */
  SECRETS: KVNamespace;
  ASSETS: Fetcher;
}
