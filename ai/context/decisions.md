# envshare — decisions

The choices that shape this repository, one line each, with where the full
reasoning lives. Superseded decisions stay listed, marked, so the history
reads in order.

| # | Decision | Why | Source |
|---|---|---|---|
| 1 | The ciphertext is a KV value (`SECRETS`, key `secret:<id>`) written with `expirationTtl` | The template's Redis EXPIRE, on a binding Terraform provisions; KV drops the value when the TTL runs out | design.md §3 |
| 2 | The read limit and the expiry are a D1 row (`secrets`), spent by one `UPDATE … SET remaining_reads = remaining_reads - 1 WHERE … remaining_reads > 0 RETURNING` | KV is eventually consistent: a count kept there could serve the last read twice in two places. One D1 statement serves exactly one of two concurrent last reads | design.md §3, risk ES-C |
| 3 | The ciphertext is read before the count is spent; a KV miss spends nothing | A write not yet visible where a read runs costs the reader nothing, and the link works on a retry | design.md §3 |
| 4 | The read that spends the last one deletes the KV value and the D1 row at once | The template deleted lazily, on the next read; nothing of a spent document should outlive its last read | design.md §3 |
| 5 | A TTL under 60 seconds is raised to 60, KV's floor, and the API reports the TTL stored | KV refuses a shorter `expirationTtl`; the share form's shortest choice is already one minute | design.md §3, risk ES-D |
| 6 | The expiry is kept in D1 as well, and a read past it is refused even if KV still answers | KV's expiry is not instantaneous everywhere; D1 is the clock a read trusts | design.md §3 |
| 7 | Each write sweeps D1 rows whose TTL has passed | The table holds only live documents without a cron | design.md §3 |
| 8 | The read and write counters are a D1 `metrics` table | The template's `envshare:metrics:*` Redis keys; atomic increments | design.md §3 |
| 9 | The encryption, the link encoding and the pages are the template's, unchanged in substance | The security of the product is the browser's AES-GCM and the fragment; the port touches only where documents are kept | design.md §2 |
| 10 | The API moved from `pages/api` Edge routes to App Router route handlers at the same URLs; `/api/v1/store` validates its body | Next 16 with OpenNext; no route keeps `runtime = "edge"` (OpenNext answers 500 on it) | IMPLEMENTATION-STATUS |
| 11 | The HTTP API's headers are named for the product (`<repo>-ttl`, `<repo>-reads`) | The template named them for itself; the rebrand renames them with the slug | IMPLEMENTATION-STATUS |
| 12 | The Open Graph image stays dynamic (`next/og`), its font read from Static Assets; twemoji dropped | The Worker stays well under the free plan's size; no third-party fetch at render | IMPLEMENTATION-STATUS |
| 13 | The GitHub stars counter, the testimonials and Vercel Analytics are dropped; the deploy page describes this repository | They are the template's own site; the stars counter called GitHub on every render | IMPLEMENTATION-STATUS |
| 14 | `next build --webpack` on Next 16.3.8; Inter self-hosted through `next/font/local` | OpenNext 1.20.11 accepts 16.3; Google Fonts fail on the runners | IMPLEMENTATION-STATUS |
| 15 | The schema is migrations (`packages/db`), applied by `infra/db-migrate` between the D1 apply and the Worker's deploy | The convergence's order then includes the schema | design.md §4 |
| 16 | `wrangler.jsonc` is rendered from the two roots' wiring documents per environment, and the fixture render is committed; dev renders the fixture | The deploy lane checks the config exists before the build; no root applies in dev | design.md §4 |
| 17 | One landing (`01-product`) then the record (`02-docs`); edges `mode: enforced` on main, advisory on a pull request | The plan, not a landing boundary, orders the database and namespace, the schema and the Worker | design.md §4 |
| 18 | The D1 apply and the migrations use a `d1-edit` key; the KV root applies with the deploy token | The `workers-deploy` token covers Workers and KV but not D1 | design.md §4 |
| 19 | The smoke requires `</html>` on `/` and `"ok":true` from `/api/health` | Only a Worker that reached its migrated database and its namespace answers the health route; it stores nothing and spends no read | IMPLEMENTATION-STATUS |
| 20 | The migrations package is named `@saas/db` | stack-tectonic's db-migrate composition builds `--filter=@saas/db` | turso-starter's shape |
| 21 | Component docs are generated from the manifests and checked in CI | A hand-written copy of the dependency graph, bindings and migrations drifts silently | `tooling/catalog/gen-component-docs.py` |
