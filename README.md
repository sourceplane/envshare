# envshare

[EnvShare](https://github.com/chronark/envshare) — share environment
variables through a link only its holder can read: the browser encrypts with
**AES-GCM** before anything is sent and keeps the key in the link's `#`
fragment, each link limited to a number of reads and expiring after a TTL —
running on **Cloudflare Workers + Static Assets** through
[`@opennextjs/cloudflare`](https://opennext.js.org/cloudflare). The
ciphertext is in a **Workers KV** namespace, written with the document's
TTL, and each document's read limit and expiry in a **Cloudflare D1**
database, both provisioned by Terraform through
[Orun](https://github.com/sourceplane/orun), the schema applied by
migrations, and packaged as an **Orun baseline**: one command takes a new
product from nothing to live on stage and prod, in its own repository, under
its own name — in ONE landing.

The template kept each document as one Upstash Redis hash with Redis's own
EXPIRE and decremented its read count with HINCRBY. Here the ciphertext is a
KV value with `expirationTtl` (so the shortest TTL is KV's 60 seconds), and
the count is D1's: KV is eventually consistent, so the read limit is spent
by one atomic `UPDATE … WHERE remaining_reads > 0 RETURNING` — two readers
racing for the last read cannot both be served. The read that spends the
last one deletes both halves. The encryption is the template's, unchanged,
in the browser. What the baseline adds is everything needed to make a copy
of it somebody else's, built the way
[cirrus-baseline](https://github.com/sourceplane/cirrus-baseline) is. See
[`specs/epics/envshare`](specs/epics/envshare/README.md) for the design,
the milestones and the as-built status.

## Instantiating a product

```bash
git clone --depth 1 --branch <baseline-tag> https://github.com/sourceplane/envshare
cd envshare
orun new --blueprint repo-blueprint.yaml --out ~/sites/acme-vault --run-hooks --resume \
  --set reponame=acme-vault --set productname="Acme Vault" \
  --set githuborg=acme-inc --set subdomain=<workers-dev-subdomain>
```

Or, once the platform's registry lists it, from the Orun console (Baselines →
`envshare` → Build). Two phases: **`01-product`** creates the
repository and lands the whole product as ONE pull request — intent, CI,
tooling, the D1 and KV roots, the migrations, the site and its tests — and
one convergence, per environment, applies the database and the namespace,
then the migrations, then deploys the site bound to them; **`02-docs`**
records the live deployment from probed facts.
**[BOOTSTRAP.md](BOOTSTRAP.md)** is the operator guide;
[docs/phases/](docs/phases/README.md) has a page per phase.

The new repository receives the **product only** — the app, its D1 and KV
roots, its migrations and their runner, its tests, its CI, its tooling, a
README of its own and its operating contract — renamed throughout to the
product's name, repository, Cloudflare Worker, database and namespace
names, and its HTTP API's headers. None of this repository's machinery
ships.

| What makes it a baseline | Where |
|---|---|
| The console card (inputs, secrets, programme) | `blueprint.yaml` |
| The build document (modules, phases, hooks) | `repo-blueprint.yaml` |
| This tree's identity, and the bootstrap's task contracts | `.baseline/` |
| The rename engine | `tooling/rebrand/rebrand.mjs` |
| The bootstrap's helpers (deferrals, redeploy marker, work-tree strip) | `tooling/bootstrap/` |
| The deployment-record renderer | `hooks/render-deployment-docs.sh` |
| The product's README and context pack | `.baseline/product/README.md`, `ai/context/` |
| The baseline's tests: contract, wiring, leak, offline bootstrap, end to end | `testing/`, `.github/workflows/baseline.yml` |
| Cutting a `baseline-vN` tag | `.github/workflows/tag.yml` |

## What is here (the product)

| Surface | Where |
|---|---|
| The pages: home (with the share and read counters), share, unseal, deploy; the old `/<id+key>` link redirect | `apps/web/app` |
| Encryption and the link's encoding, in the browser (the template's) | `apps/web/pkg`, `apps/web/util` |
| The store: ciphertext on KV with its TTL, read limits and expiries on D1, the atomic last read | `apps/web/lib/store.ts` |
| The share page's API and the HTTP API | `apps/web/app/api/v1/{store,load,secret}`, `apps/web/lib/secret-api.ts` |
| The Open Graph image (`next/og`, the font from Static Assets) | `apps/web/app/api/v1/og` |
| The site's name, source link and origin | `apps/web/lib/site.ts` |
| The health route the deploy smoke-tests | `apps/web/app/api/health/route.ts` |
| Workers build, bindings and deploy contract | `apps/web/next.config.mjs`, `open-next.config.ts`, `wrangler.template.jsonc` + `wiring.fixture.json` (→ the committed `wrangler.jsonc`), `component.yaml` |
| The D1 database and the KV namespace (stage, prod) | `infra/terraform/cloudflare-d1`, `cloudflare-kv` |
| The schema (migrations) and the runner that applies them over the D1 REST API | `packages/db`, run by `infra/db-migrate` |
| The wrangler renderer, the migration helpers | `tooling/wire`, `tooling/migrations` |
| Tests | `tests/web` (the template's encryption and link-encoding tests, the store's read limit, TTL and last-read race on real SQLite with the migrations applied and a TTL-honouring KV, the API routes, the site's name and source link), `tests/db` (the migrations through the runner, into real SQLite) |

## Getting started

```bash
pnpm install
pnpm run wire:fixture   # render apps/web/wrangler.jsonc from the offline fixture
pnpm typecheck
pnpm lint
pnpm test
pnpm build              # next build --webpack + opennextjs-cloudflare build → apps/web/.open-next
```

```bash
pnpm --filter @app/web db:migrate:local   # the schema in wrangler's local D1
pnpm --filter @app/web dev                # http://localhost:3000 — local D1 and KV through wrangler's platform proxy
pnpm --filter @app/web preview            # wrangler dev over the built Worker, the same local bindings
```

## How it maps to Vercel

| Vercel-side | Here |
|---|---|
| Next.js 13.1: `pages/api` Edge routes, the `app` directory beta, `@next/font` | Next.js 16.3 in one Cloudflare Worker (`.open-next/worker.js`) + Static Assets, built with webpack; the API as App Router route handlers at the same URLs, none keeping `runtime = "edge"` (OpenNext answers 500 on it); Inter self-hosted through `next/font/local` |
| Upstash Redis: one hash per document, EXPIRE for the TTL, HINCRBY for the reads | The ciphertext in KV with `expirationTtl` (60 s at least); the read limit and expiry in D1 (`010_secrets`), spent by one atomic `UPDATE … RETURNING`; the last read deletes both |
| The read and write counters in Redis | A `metrics` table in D1 |
| `@vercel/og` with twemoji | `next/og`, the font read from Static Assets |
| The GitHub stars counter, the testimonials, Vercel Analytics | Removed |
| The Vercel/Upstash deploy guide | A deploy page for this repository |
| Deploy on push | Orun applies the database and namespace, migrates and deploys `<repo>-web-{stage,prod}` on merge to `main` |
| "Deploy with Vercel" (clone the template) | `orun new --blueprint repo-blueprint.yaml` — a new repository, branded, deployed |

## How the bindings reach the Worker

```
infra/terraform/cloudflare-d1 ──apply──► orun secret WIRING_CLOUDFLARE_D1 (stage, prod)
infra/terraform/cloudflare-kv ──apply──► orun secret WIRING_CLOUDFLARE_KV
                                               │   (the landing's await checks they exist)
                                               ▼
infra/db-migrate  dependsOn cloudflare-d1 (enforced on main) · secretEnv WIRING_CLOUDFLARE_D1
  apply:  packages/db's runner → POST …/d1/database/<id>/query, each pending migration once
                                               ▼
apps/web  dependsOn cloudflare-d1, -kv + db-migrate (enforced on main) · secretEnv WIRING_CLOUDFLARE_*_<ENV>
  build:  tooling/wire/live.mjs → wrangler.jsonc with the environment's database and namespace
          (dev, verify-only, renders the fixture) → next build --webpack for the environment's origin
          → opennextjs-cloudflare
```

`wrangler.jsonc` is committed as the fixture render of
`wrangler.template.jsonc`, because the deploy lane's `verify-app-structure`
step checks the config exists before it builds; `testing/e2e.test.sh` fails
if the two disagree.

## CI

| Workflow | What it runs | Ships to a product |
|---|---|---|
| `ci.yml` | the Orun pipeline, and the only workflow a product carries: `orun plan --changed`, then one job per lane. A pull request runs the verify lanes (packages type-checked, linted, tested and built, both test suites, the site built and dry-deployed per environment), except the bootstrap's own landings (`orun/BASE-*`), where `plan` alone is the check; a merge applies the D1 database and the namespace, migrates, then deploys stage → prod. It plans nothing while `intent.yaml` names the placeholder workspace `ws_CHANGE_ME`, as this repository does. A manual run (Orunbase's Deploy button, or Run workflow on `main`) plans the environment and components it names under the push-to-main trigger, so they deploy as a merge deploys them | yes |
| `baseline.yml` | the baseline's own tiers: contract tests, the wiring path, the blueprint read by the pinned orun, the leak gate, the offline bootstrap with the product's own plan, the product built in the job tree, migrated, dry-deployed and served — a document shared, read to its limit and gone, the TTL kept, two concurrent last reads of which one is served, and no request carrying the key | no |
| `tag.yml` | cuts a `baseline-vN` tag (manual) | no |
