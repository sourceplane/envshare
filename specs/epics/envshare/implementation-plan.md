# envshare — implementation plan

## ES0 — the spec (ES-1)

The repository is born with turso-starter's intent, CI, tooling and spec
index, renamed; this doc set and the three task contracts land on top.

## ES1 — the secret share on Workers (ES-2)

1. The template (at `b8ea7c7`) into `apps/web`, a pnpm workspace package;
   Next.js 13.1 → 16.3.8 and React 19 (awaited params, `metadata` for
   `head.tsx`, `next/og`, `next/font/local`).
2. OpenNext: standalone output, the static-assets incremental cache,
   `images.unoptimized`, webpack; the `pages/api` Edge routes as App Router
   route handlers at the same URLs.
3. The store (`lib/store.ts`): the ciphertext on KV with `expirationTtl`,
   the count and expiry on D1 (`010_secrets`), the atomic last read, both
   halves deleted by it; the counters in D1.
4. The KV Terraform root and its wiring beside D1's.
5. `/api/health`; the site seam (`lib/site.ts`); the API headers named for
   the product.
6. Tests: `tests/web` (the template's encryption and encoding tests, the
   store over real SQLite with the migrations and a TTL-honouring KV — the
   limit, the TTL and its floor, the expiry, the concurrent last read — the
   routes, the site seam), `tests/db` (the migrations through the runner).
7. The README: how it works, its API, how it deploys, how it maps to
   Vercel.

## ES2 — a baseline (ES-3)

The card (one Cloudflare provider, nothing to connect after), the build
document (one landing, then the record), the identity and the rename seam
(`SITE_NAME`), the context pack, the deployment record probing
`/api/health`, and the baseline's tests: contract tiers, generated component
docs, the leak gate (the template's licence and the new runtime files must
ship), placement (the KV root, no Worker secret, the origin, the renamed
headers), the offline bootstrap, and the e2e — the stage lanes in staged job
trees, the migrations against a stand-in D1 API, the Worker served under
`wrangler dev`: create → read → exhausted → 404, the TTL, two concurrent
last reads, and every request body checked for the key. Then
`baseline-v1`.
