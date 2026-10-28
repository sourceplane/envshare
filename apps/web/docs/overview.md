# web

The secret-sharing site (Next.js on Cloudflare Workers + Static Assets via @opennextjs/cloudflare, per environment; the shared documents' ciphertext in KV, their read limits and expiries in D1)

A Cloudflare Worker with Static Assets (server rendering plus static files), deployed per environment by its CI lane.

|              |                                                                                                                    |
| ------------ | ------------------------------------------------------------------------------------------------------------------ |
| Type         | `cloudflare-workers-assets-turbo`                                                                                  |
| Source       | `apps/web`                                                                                                         |
| Package      | `@app/web`                                                                                                         |
| Environments | `dev`: `verify` · `stage`: `verify`, `deploy` on a push to `main` · `prod`: `verify`, `deploy` on a push to `main` |

## Depends on

- **cloudflare-d1** — Provisions the Cloudflare D1 database for stage and prod — the shared documents' read limits and expiries, and the site's counters
- **cloudflare-kv** — Provisions the Cloudflare KV namespace the shared documents' ciphertext is kept in (stage and prod)
- **db-migrate** — Applies the site's schema (packages/db's migrations) to the stage and prod Cloudflare D1 databases

## Depended on by

- (none)
