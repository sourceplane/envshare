# 01-product — the product, built in one landing

**Places** every module: the root manifests, CI, tooling and the identity
file; `infra/terraform/cloudflare-d1` and `cloudflare-kv` (the D1 database
and the KV namespace per environment);
`packages/db` (the schema as migrations, and their runner) and
`infra/db-migrate` (which applies them); `apps/web` (the site, its OpenNext
build, its wrangler template and fixture, its deploy contract); `tests/web`
and `tests/db` (vitest). Then brands them, lands them as ONE pull request,
and watches the ONE convergence that merge triggers.

**Requires** both connections live — GitHub (the App installation on the
OWNER of the repository, the only way the platform sees its pull requests)
and Cloudflare (every deploy credential below is minted from it) — probed,
waited for up to ten minutes each, so the consent can be clicked while it
waits.

## What runs

The run's task set-up — the epic, both milestones, both tasks — runs in the
background from the start (`background: true`), so every hook up to `task`
runs beside it; `task` is the first that waits for it.

| hook | what it does |
|---|---|
| `retouch` | the redeploy marker on the components `.baseline/tasks/01-product.TaskContract.yaml` names: `cloudflare-d1`, `cloudflare-kv`, `db`, `db-migrate`, `db-tests`, `web`, `web-tests` |
| `git-init`, `stage`, `rebrand` | the tree becomes a repository, then the product's |
| `orun-workspace` | intent.yaml's `workspace:` becomes the product's (or `ws_SET_ME`, which fails loudly) |
| `work-tree` | intent.yaml's `work:` block — this repository's epics and tasks — is removed |
| `promotion`, `dev-lanes` | prod's promotion gate and dev's push-to-main activation deferred until `02-docs` |
| `restage`, `rebrand-verify` | the sweep: no identity of this baseline left anywhere |
| `repo` | `orun.repo/ensure@v1` creates `<githuborg>/<reponame>` (or finds it) |
| `link` | the repository becomes the workspace's; `orun cloud check` is the gate |
| `secrets` | `orun.integrations/reconcile@v1`, the three keys in one hook, created side by side: `CLOUDFLARE_API_TOKEN` from the `workers-deploy` template (Workers Scripts and KV, the site's deploy and the namespace's apply); `CLOUDFLARE_D1_TOKEN` from `d1-edit` (D1, for the database's apply and the migrations — the deploy token cannot touch D1); `CLOUDFLARE_ACCOUNT_ID`, the connection fact they all bind |
| `task` | finds the phase's task and yields its key — waiting, if it must, for the background set-up |
| `land` | one PR bound to the task, its commit checked in the box first (`checks: local`: `orun validate`, then `orun plan` as the PR and as the merge would plan it, under a second); merged without waiting for the PR's CI |
| `converge` (await) | `orun.run/watch@v1` on the merge commit's run, read every 5 s; resumes it up to three times |
| `verify` (await) | `orun.http/probe@v1` on both workers.dev URLs |

## What the convergence does

`orun plan --changed` on the merge plans, with dev's push activation and the
promotion gate deferred — three levels per environment, stage and prod side
by side:

| lane | waits on | does |
|---|---|---|
| `cloudflare-d1 · stage` / `· prod` | nothing | `terraform apply` of `stg-<reponame>-stage` / `prod-<reponame>-prod`, adopting a database of that name if one exists (`adopt.tf`), then lease-publishes `WIRING_CLOUDFLARE_D1` = `{d1_database_id, d1_database_name}` on that environment |
| `cloudflare-kv · stage` / `· prod` | nothing | `terraform apply` of the namespace `stg-<reponame>-app-kv-stage` / `prod-<reponame>-app-kv-prod`, then lease-publishes `WIRING_CLOUDFLARE_KV` = `{app_kv_id, app_kv_title}` |
| `db-migrate · stage` / `· prod` | that environment's D1 apply (`dependsOn: cloudflare-d1`, `mode: enforced` on main) | resolves `WIRING_CLOUDFLARE_D1` and the D1 token as it starts, builds `packages/db`, and applies every pending migration over the D1 REST API — the `secrets` and `metrics` tables on a fresh database — recording each in `_migrations_applied` |
| `stage · web` / `prod · web` | that environment's D1 and KV applies and its migrations (`dependsOn` all three, `mode: enforced` on main) | resolves `WIRING_CLOUDFLARE_{D1,KV}_<ENV>`, renders `wrangler.jsonc` with the real database id and namespace id, builds with OpenNext for the environment's origin, deploys `<reponame>-web-<env>`, and smoke-tests it: `/` must render to its end and `/api/health` answer `"ok":true`, which only the Worker reading its migrated database and its namespace can |

`web-tests`, `db-tests` and `db` verify on dev only, on a pull request. The
landing's own pull request runs `plan` alone, and nothing waits for it — the
same plan ran in the box before the push: the baseline's own CI ran the
lanes' checks on this exact tree before the tag was cut, and every later
pull request in the product runs them.

## Verified

The convergence run for the merge commit is green — its migrations and the
site resolved `WIRING_CLOUDFLARE_D1` and `_KV` from stage and prod, where every later
run reads it; `https://<reponame>-web-{stage,prod}.<subdomain>.workers.dev`
answer.

## Troubleshooting

| symptom | cause → fix |
|---|---|
| parks on the `providers` probe | GitHub (on the repository's owner) or Cloudflare is not connected to the workspace. Connect it (console → Integrations), then re-run the phase — the probe is a wait, not a failure |
| stops at `link` | the repository is not linked to the workspace and the credential cannot link it. Allow-list it (console → Settings → Git repos) and re-run the phase |
| D1 lane: a database with this name already exists | `adopt.tf` imports a database of the same name; if it was removed, restore it. Two products with the same `reponame` in one account share a name — use a distinct `reponame` |
| `land`: `the landing's own check failed — orun plan for …` | the placed tree does not plan; the next line is orun's error. Nothing was pushed. Fix it and re-run the phase |
| D1 or db-migrate lane: Authentication error (10000) | the connection's token cannot mint D1 Edit (`d1-edit`). Re-issue it with the permission groups the console's Connect recipe lists, re-connect, re-run the phase |
| deploy or KV lane: Authentication error (10000) | the connection's token lacks Workers Scripts or KV write (`workers-deploy`); same fix |
| db-migrate lane: `No D1 database id` | the job started without `WIRING_CLOUDFLARE_D1` — that environment's D1 apply failed or never ran, or the `dependsOn` edge is gone from `infra/db-migrate/component.yaml` |
| db-migrate lane: `Checksum mismatch for already-applied migrations` | an applied migration's file was edited. Restore it and put the change in a new migration |
| db-migrate lane: `Could not acquire migration advisory lock` | another run is migrating the same database; a lock older than fifteen minutes is reclaimed, so a resume clears a dead one |
| web lane fails resolving `WIRING_CLOUDFLARE_{D1,KV}_<ENV>` | that environment's apply of that root failed or never ran — read its lane; the web lane waits on both, so it shows as not run on a fresh failure |
| web lane `build-app`: `wire: missing wiring documents` | the job started without the document — the `dependsOn` edge is gone from `apps/web/component.yaml`, or the secretEnv names the wrong key |
| web lane `verify-app-structure`: `test -f wrangler.jsonc` fails | `apps/web/wrangler.jsonc` is not committed (an old `.gitignore` entry); render it with `pnpm run wire:fixture` and commit it |
| `build-app` fails: `Symlink apps/web/node_modules/next is invalid, it points out of the filesystem root` | the site's `intent.yaml` pins stack-tectonic ≥ 0.20.0 (lane-scoped install). Pin 0.19.0 — `intent.yaml`'s comment says why |
| smoke fails: `/api/health` answers 500 ("no such table") | the migrations did not reach the database the Worker binds — read the db-migrate lane for that environment |
| smoke fails right after the FIRST deploy | workers.dev route propagation; the composition retries the first deploy and the smoke with backoff (stack-tectonic ≥ 0.19.0). A convergence resume clears what is left |
| the watch says green, the probe says 404 | another workflow ran on the push and the watch took its run. Only `ci.yml` may run on a push to main |
| convergence failed AFTER the PR merged; re-running lands nothing | the hooks did not run (`--run-hooks`), or the contract names no component — `node tooling/bootstrap/retouch.mjs --check --affects .baseline/tasks/01-product.TaskContract.yaml` in the site's tree says which |
