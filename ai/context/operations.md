# envshare — operating contract (for humans and agents)

This is the standing guide to how this site is deployed and operated.
Instance facts (live URLs, workspace, the secrets it uses) live in
[deployment.md](deployment.md), rendered from probed reality by the
bootstrap's `02-docs` phase; this file is the contract that stays true
between deployments. It is written to give an agent with repository read
access enough context to reason about and operate the site without any
other source.

## What this system is

EnvShare — share environment variables through a link only its holder can
read: the browser encrypts with AES-GCM and keeps the key in the link's
fragment, and each link is limited to a number of reads and a TTL — on
Cloudflare, expressed as an Orun component-native desired-state repo.

- **`infra/terraform/cloudflare-d1`** — one Cloudflare D1 database per
  deployed environment (`stage`, `prod`), applied by Terraform. After each
  apply it publishes a wiring document — `{d1_database_id, d1_database_name}`
  — as the Orun secret `WIRING_CLOUDFLARE_D1` on that environment.
- **`infra/terraform/cloudflare-kv`** — one Workers KV namespace per deployed
  environment, where the shared documents' ciphertext is kept, each value
  written with its TTL. After each apply it publishes
  `{app_kv_id, app_kv_title}` as `WIRING_CLOUDFLARE_KV`.
- **`packages/db`** — the schema as migrations (`src/migrations/*/up.sql`,
  listed with their checksums in `src/manifest.ts`) and the runner that
  applies them to D1 over the REST API, recording each in a
  `_migrations_applied` table. `010_secrets` is the `secrets` table (each
  document's remaining reads and expiry) and the `metrics` table (the read
  and write counters on the home page).
- **`infra/db-migrate`** — runs that runner per environment: it plans offline
  on a pull request and applies on a merge, finding the database through
  `WIRING_CLOUDFLARE_D1`.
- **`apps/web`** — the site, a Next.js app built by `@opennextjs/cloudflare`
  into one Worker plus Static Assets. `/share` encrypts in the browser and
  posts only the ciphertext and IV to `/api/v1/store`, which writes the D1
  row, then the KV value with `expirationTtl`. `/unseal#<id + key>` reads
  `/api/v1/load`, which reads the KV value first, then spends one read with
  a single atomic D1 `UPDATE … RETURNING`; the read that spends the last
  one deletes both. `/api/v1/secret` is the same store as an HTTP API.
- **`tests/web`**, **`tests/db`** — the encryption and link encoding, the
  store's read limit, TTL and last-read race, the routes and the migrations
  applied through the runner into real SQLite (vitest), verified on the
  `dev` rung.
- **`tooling/*`** — shared TypeScript and ESLint configuration, the wrangler
  renderer that turns `wrangler.template.jsonc` plus the wiring documents
  into `wrangler.jsonc`, and the migration helpers.

Environments: **`stage`** and **`prod`** are deployed; **`dev` is
verify-only by design** — lanes build and test, nothing deploys, and no
database or namespace exists for it (its build renders the committed
fixture).

## Identity and tenancy

Every remote operation runs against ONE Orun workspace, declared in
`intent.yaml` under `execution.state.workspace` — committed, enforced, and
what CI uses. Do not remove it; headless credentials depend on it. If it
reads `ws_SET_ME`, the bootstrap had no workspace to write: set the real one
before anything else.

## How deployment works

1. Merge (or push) to `main`.
2. CI (`.github/workflows/ci.yml`) runs `orun plan --changed` — only
   components whose files changed are planned — then runs each planned lane
   with `orun run --remote-state`, authenticated by GitHub OIDC (the
   exchange resolves this repository's linked workspace server-side).
3. **The database and namespace, then the schema, then the Worker**, per
   environment. `cloudflare-d1` and `cloudflare-kv` apply and publish their
   wiring documents. `db-migrate` declares an enforced `dependsOn` on
   `cloudflare-d1` for pushes to `main`, so it starts after that apply — a
   job resolves its secrets when it starts, so the document is there — and
   applies every pending migration. `apps/web` waits on all three the same
   way.
4. `apps/web` renders `wrangler.jsonc` from those documents (the real
   database id and namespace id), builds once per environment with
   `NEXT_PUBLIC_SITE_URL` set to that environment's `SITE_URL`
   (intent.yaml) or its workers.dev URL, `wrangler deploy` ships
   `envshare-web-<env>`, and a smoke test requires `/` to render to
   its end and `/api/health` to answer `"ok":true` — which only a Worker
   that counted the migrated `secrets` table and reached its namespace can.
5. `prod` deploys after `stage` has converged on the same commit
   (`environments.prod.promotion` in intent.yaml).
6. **The convergence run is the deployment.** A green run means every
   planned lane applied. Failed lanes are retried with
   `gh run rerun --failed`, which resumes the same execution.

On a pull request nothing applies or deploys: the two roots plan, the
migrations plan offline (their checksums verified), the site builds and
dry-deploys, and the edges in step 3 are advisory.

Caveats that matter:

- A push that touches no component files plans zero lanes — that run is
  green and deployed nothing. Never treat "latest run green" as "site
  converged"; probe the URLs instead.
- A change to `intent.yaml`'s `environments` maps to no component and
  redeploys nothing on its own. Land it with a change under `apps/web`.
- `wrangler.jsonc` is generated. Edit `wrangler.template.jsonc`, run
  `pnpm run wire:fixture` and commit both; the deploy renders its own
  config from the template, so a stale committed render misleads local work.
- An applied migration is immutable: its checksum is recorded, and the
  runner refuses to run while a file no longer matches it. Change the
  schema with a NEW migration.
- **The count is D1's, never KV's.** KV is eventually consistent; do not
  move the read limit into it. A read finds the ciphertext in KV first and
  spends nothing on a miss, so a link opened seconds after it was made, in
  another location, may answer "not found" once and work on a retry.
- **The shortest TTL is 60 seconds**, KV's floor for `expirationTtl`; a
  shorter one is raised to it.
- Never log a request body or a `#` fragment: the body is ciphertext, but
  the fragment is the key (browsers do not send it; keep any client-side
  analytics from reading it).

## Secrets model

- **Brokered provider secrets**, minted per run from the workspace's
  Cloudflare connection — no long-lived values at rest, nothing to rotate by
  hand:
  - `CLOUDFLARE_API_TOKEN` (`workers-deploy`: Workers Scripts and KV) — the
    site's deploy and the KV root's apply;
  - `CLOUDFLARE_D1_TOKEN` (`d1-edit`: D1) — the D1 root's apply and the
    migration runner, which bind it as their `CLOUDFLARE_API_TOKEN`; the
    deploy token cannot touch D1;
  - `CLOUDFLARE_ACCOUNT_ID` — a connection fact all of them bind.
- **Wiring**: `WIRING_CLOUDFLARE_D1` and `WIRING_CLOUDFLARE_KV` on `stage`
  and `prod`, written by the roots' applies (lease-published), read by the
  migration runner and by the Worker's build as `WIRING_CLOUDFLARE_*_<ENV>`.
  They hold ids and names, not credentials.
- **The site holds no secret of its own.** It never sees a document's key;
  there is no API key, session secret or Worker secret to set.
- Inspect by NAME only: `orun secrets list --org <ws> --project` and
  `--env stage|prod`. No tooling in this repository prints a secret value,
  and no document in `ai/context/` may contain one.

## Verifying the system

```bash
# the site on each environment (also recorded, probed, in deployment.md);
# the health route counts the live documents and touches the namespace
curl -s https://envshare-web-stage.your-workers-subdomain.workers.dev/api/health
curl -s -o /dev/null -w '%{http_code}\n' https://envshare-web-prod.your-workers-subdomain.workers.dev/

# the wiring the migrations and deploys read, and workspace readiness
orun secrets list --org <ws> --env stage && orun secrets list --org <ws> --env prod
orun integrations list --org <ws> --json && orun cloud check --org <ws>
```

## Common operations

| task | how |
|---|---|
| change the site | edit `apps/web/app/` (its name and source link: `apps/web/lib/site.ts`), merge |
| revoke a link | `wrangler d1 execute <name> --remote --command "DELETE FROM secrets WHERE id = '<id>'"` — the next read finds no row, answers 404 and deletes the KV value (an API secret's id is the one the API returned; a share link's fragment is its id and key base58-encoded together, and the id is what its unseal page sends to `/api/v1/load?id=`) |
| count live documents | `wrangler d1 execute <name> --remote --command "SELECT count(*) FROM secrets"` (the name is in the environment's `WIRING_CLOUDFLARE_D1`) |
| change the schema | add `packages/db/src/migrations/<NNN>_<name>/up.sql` (idempotent: `IF NOT EXISTS`), list it in `src/manifest.ts`, `pnpm --filter @saas/db run manifest:fix`, merge — db-migrate applies it before the site redeploys |
| try the schema locally | `pnpm --filter @app/web db:migrate:local` applies every migration to wrangler's local D1 |
| deploy a change | merge to `main`; watch the run; failed lanes → `gh run rerun --failed` |
| deploy by hand | Orunbase's Deploy button, or `gh workflow run ci.yml --ref main -f environment=<env> [-f component=<a,b>]` — the named components (blank: every one) run in that environment as a merge runs them; started off `main` it is refused |
| redeploy without a change | edit the last line of `apps/web/component.yaml` (`# orun: redeploy <reason> <stamp>`) and merge — it is a deploy trigger, nothing reads it |
| add a binding | a Terraform root under `infra/terraform/` that publishes `WIRING_<ROOT>`, a token in `wrangler.template.jsonc`, its fixture entry, the root in the build's `--components`, the `WIRING_<ROOT>_<ENV>` secretEnv and an enforced `dependsOn` on it in `apps/web/component.yaml` |
| serve a custom domain | attach it to the Worker in Cloudflare and set `SITE_URL` for the environment in `intent.yaml` (README, "Custom domain"), then replace the placeholder `envshare.example.com` in `intent.yaml`'s `BASE_DOMAIN` with it |
| add a runtime secret | `orun secrets set <KEY> --org <ws> --env <env>` |
| headless credentials | `ORUN_TOKEN` (workspace-scoped) + `GITHUB_TOKEN` |

The deployment record is the bootstrap's `02-docs` phase. Re-running it (the
Orun console's Retry on that phase, or `orun new … --phase 02-docs`)
re-probes the URLs and re-renders [deployment.md](deployment.md); it is
idempotent.

## Evolution

KV caps a value at 25 MiB and D1 a database's size; a shared document needs
neither (the share form reads a file into the browser and encrypts it
whole). Structural changes follow the same contract that deployed the site:
add a component under `apps/`, `infra/` or `packages/` with a
`component.yaml`, land it as a pull request, and the convergence run
applies it.
