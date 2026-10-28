# db-migrate

Applies the site's schema (packages/db's migrations) to the stage and prod Cloudflare D1 databases

Applies this repository's ordered database migrations per environment: plan on pull requests, apply on merge to `main`.

|              |                                                                                            |
| ------------ | ------------------------------------------------------------------------------------------ |
| Type         | `db-migrate`                                                                               |
| Source       | `infra/db-migrate`                                                                         |
| Environments | `stage`: `plan`, `apply` on a push to `main` · `prod`: `plan`, `apply` on a push to `main` |

## Depends on

- **db** — The site's schema (the shared documents' read limits and expiries, the counters) as migrations, and the runner that applies them to D1 (built by the db-migrate component before it plans or applies)
- **cloudflare-d1** — Provisions the Cloudflare D1 database for stage and prod — the shared documents' read limits and expiries, and the site's counters

## Depended on by

- **web** — The secret-sharing site (Next.js on Cloudflare Workers + Static Assets via @opennextjs/cloudflare, per environment; the shared documents' ciphertext in KV, their read limits and expiries in D1)
