# The phases — one blueprint, two selections

`repo-blueprint.yaml` declares two phases that take a site from **nothing**
to **live on stage and prod, documented**. Run them one at a time with
`--phase <name>`, or the whole sequence unattended with `--resume`. There is
no umbrella workflow and no per-phase document: a phase is a selection on one
artifact, which is what makes running one alone, months later, from a fresh
container the same operation as running them all.

The product phase follows the contract every deploying phase does:

> **place its modules → brand them → check them in the box and land them as
> one pull request → watch the convergence that merge triggers
> (auto-resumed) → verify the outcome over HTTP.**

The run's task set-up — the epic, a milestone per phase, a task per landing
— runs in the background from the start; the first hook that needs it, the
phase's `task`, waits for it.

Run from the baseline checkout (the blueprint's source is `path: .`); the
site's repository is wherever `--out` points.

## Execution order

| phase | lands | verified by |
|---|---|---|
| [`01-product`](01-product.md) | **the GitHub repo created** and the whole product in ONE pull request: intent, CI, tooling, identity, the D1 and KV roots, the migrations, the site and its tests | the convergence green (D1 and KV applied, then migrated, then the site built, deployed and smoke-tested), both URLs answering |
| [`02-docs`](02-docs.md) | the live-deployment record; the promotion gate and dev's lanes put back | committed manifest matches probed reality |

**One landing, not three.** Before the one-landing shape a site like this
landed its scaffold, its data plane and its app as separate pull requests,
because the database had to exist — and carry its schema — before the
Worker that binds it. The plan carries that order now, per environment:
`infra/db-migrate` declares `dependsOn: cloudflare-d1`, and `apps/web`
declares `dependsOn` on it, on `cloudflare-kv` and `db-migrate`, each with
`mode: enforced` on a push to main. So the convergence that follows the one
merge applies the database and the namespace, then the migrations, then
deploys the site — and a job
resolves its secrets when it starts, so the ids the applies published are
there for both. On a
pull request the edges are advisory: nothing applies or deploys.
`testing/phases.test.sh` checks the edges; `testing/placement.test.sh`
checks the product's own plan honours them.

Every landing is a pull request on a branch named for its task
(`orun/BASE-<n>-<phase>`), checked before it is pushed: `orun validate`, then
`orun plan` as the pull request and as the merge would plan it, in the box,
in under a second (`checks: local`). Then it merges; nothing waits for the
PR's CI. On those branches `ci.yml` runs `plan` only and skips the lanes,
because the merge runs them on main a minute later, for real, and that
convergence is what the phase watches. The product carries no other
workflow: the baseline's own CI (Tier 2) installs, renders the fixture,
type-checks, lints, tests and builds this landing before a tag is cut, and
every later pull request in the product runs `ci.yml`'s verify lanes.

There is no custom-domain phase. Attaching a domain to a Worker needs zone
permissions the platform's brokered `workers-deploy` token does not carry, so
it is an owner's step after the bootstrap — the site's README, "Custom
domain", says how. Nothing in the repository changes for it: the page
renders no absolute link to itself.

## Inputs

`01-product` takes the site's identity once and writes it into the repo
(`.rebrand/values.json`); `02-docs` reads it back from the placed tree. But
the blueprint's **required** inputs — `reponame`, `productname`,
`githuborg` — are validated before any phase runs, so they must be supplied
on every invocation, single-phase ones included. A `--values` file is easier
than repeating `--set`.

- `productdomain` — NOT ASKED, default empty. The site goes live on
  workers.dev; empty brands the reserved placeholder `<reponame>.example.com`
  into `BASE_DOMAIN`, for an owner to replace when they attach a domain (the
  site's README, "Custom domain"). Pass it only for a site that already has
  its domain.

- `subdomain` — the workers.dev subdomain of the Cloudflare account you
  deploy into. It is in every URL the phases probe. A console or
  `--from bst_…` build reads it from the Cloudflare connection; pass it only
  for a hand-run build.
- `orunWorkspace` — workspace id (`ws_…`). Unset, it is the workspace the
  build runs in (`from: workspace`); with none anywhere, a placeholder that
  fails loudly rather than silently claiming another tenant's workspace.
- `epicSlug` (default `docs-baselining`) — the epic every phase clubs
  its task under. Found by slug, so a fresh run and a resumed run find the
  same work.
- `repoPrivate` (default `true`) — the repository's visibility at creation.

```bash
orun new --blueprint repo-blueprint.yaml \
  --out $HOME/sites/acme-docs --run-hooks --phase 01-product \
  --values ~/acme-docs.values.yaml
```

Drop `--run-hooks` (or add `--status`) to preview. Without it a phase places
files and stops: no repo, no landing, no convergence watch, and no probe —
which is exactly what makes a dry instantiation of this baseline possible in
CI with no workspace and no provider (`testing/placement.test.sh`,
`testing/e2e.test.sh`).

## What the product phase does after it places

Placement writes the baseline's files as they are here. Before the phase
lands, its `post` hooks make them the site's:

1. `retouch` — one `# orun: redeploy 01-product <stamp>` line at the end of
   each component.yaml its task contract names (`cloudflare-d1`,
   `cloudflare-kv`, `db`, `db-migrate`, `db-tests`, `web`, `web-tests`), so a re-run after a failed
   convergence still has a diff to land and re-plans exactly those
   components.
2. `git init`, stage, `rebrand`, the workspace rewrite, the work-tree strip,
   the two bootstrap deferrals (prod's promotion gate, dev's push lanes),
   restage, `rebrand --verify` — the identity rename over the whole tree,
   then a sweep that fails on any of this baseline's identity left behind.
3. `pnpm install --lockfile-only` — confirms the baseline's complete
   lockfile against the placed tree, so `--frozen-lockfile` installs pass.
4. `repo`, `link`, the brokered Cloudflare credentials (the deploy token,
   the D1 token, the account id), `land`.

## When a phase fails

- **Before it lands** (a probe that timed out, a rebrand residue, a refused
  link): nothing was merged. Fix what the message names and re-run the phase.
- **After it lands** (the convergence went red): the files are on main.
  `orun.run/watch@v1` has already resumed the run up to three times. Re-run
  the phase (`--phase 01-product`, `--redo 01-product` under `--resume`, or
  the console's Retry): its `retouch` hook gives the landing a diff and the
  D1 and KV roots, the migrations and the site re-plan. Migrations already applied
  are recorded and skipped.
