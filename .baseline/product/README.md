# envshare

[EnvShare](https://github.com/chronark/envshare) — paste environment
variables (or any text, or a file), get a link that reveals them, and only
the link's holder can read them: the browser encrypts with **AES-GCM**
before anything is sent, and the key stays in the link's `#` fragment,
which no browser sends to a server. Each link can be limited to a number of
reads and expires after a TTL. It runs on **Cloudflare Workers + Static
Assets** through [`@opennextjs/cloudflare`](https://opennext.js.org/cloudflare):
the ciphertext in a **Workers KV** namespace, written with the document's
TTL, and each document's read limit and expiry in a **Cloudflare D1**
database — both provisioned per environment by Terraform, the schema
applied by migrations before every deploy.

## Live deployment

<!-- 02-docs:begin -->
Not recorded yet. The bootstrap's last phase writes the live URLs, the
workspace and the secrets the site uses into
[ai/context/deployment.md](ai/context/deployment.md); how the site deploys
and how to operate it is in
[ai/context/operations.md](ai/context/operations.md).
<!-- 02-docs:end -->

## How a share works

1. **In the browser** (`/share`), the text is encrypted with a fresh
   128-bit AES-GCM key and a random IV (`apps/web/pkg/encryption.ts`). Only
   the ciphertext, the IV, the TTL and the read limit are posted to
   `/api/v1/store`.
2. **The Worker** keeps the ciphertext in KV, written with `expirationTtl`
   set to the TTL, and a row in D1 with the read limit and the expiry, and
   answers with an id. The browser builds the link `/unseal#<id + key>`;
   the key never reaches the server, its logs or its storage.
3. **Reading** (`/unseal`) asks `/api/v1/load?id=…` for the ciphertext and
   decrypts it in the browser. Each read takes one from the document's limit
   in a single D1 statement (`UPDATE … SET remaining_reads = remaining_reads
   - 1 WHERE id = ? AND remaining_reads > 0 RETURNING …`), so of two readers
   racing for the last read exactly one is served. The read that spends the
   last one deletes the document — the KV value and the D1 row — and every
   later read is a 404.

Two rules come from the platform:

- **The shortest TTL is 60 seconds**, KV's floor for `expirationTtl`. The
  share form's shortest choice is one minute; a shorter TTL through the API
  is raised to 60 seconds, and the API's answer says which TTL was stored.
  A TTL of 0 stores the document without one.
- **Counting is D1's, not KV's.** KV is eventually consistent, so a count
  kept there could serve the last read twice in two places. The ciphertext
  is read first: a read that finds none in KV spends nothing and answers
  404, and one that is served has already been counted. The expiry is kept
  in D1 too, so a document past its TTL is never served even where KV has
  not dropped it yet.

## The HTTP API

The API stores and returns opaque strings, kept exactly as they are sent:
**encrypt before you send.**

```bash
curl -XPOST -s https://envshare.example.com/api/v1/secret \
  -d "already-encrypted-secret" -H "envshare-ttl: 3600" -H "envshare-reads: 10"
```

- `envshare-ttl` is in seconds, at most 30758400; 0 disables expiry, under
  60 is raised to 60, and without the header the TTL is 43260 seconds (the
  template's value).
- Without `envshare-reads` the secret can be read any number of times.

It answers `{"data":{"id","ttl","reads","expiresAt","url"}}`; a `GET` of
that `url` (`/api/v1/secret/<id>`) answers
`{"data":{"secret","remainingReads"}}`, and 404 once the reads are spent or
the TTL has passed.

## What is here

| Surface | Where |
|---|---|
| The pages: home, share, unseal, deploy; the old `/<id+key>` link redirect | `apps/web/app` |
| Encryption and the link's encoding (in the browser) | `apps/web/pkg`, `apps/web/util` |
| The store: ciphertext on KV, read limits and expiries on D1 | `apps/web/lib/store.ts` |
| The share page's API and the HTTP API | `apps/web/app/api/v1/{store,load,secret}`, `apps/web/lib/secret-api.ts` |
| The Open Graph image | `apps/web/app/api/v1/og` |
| The site's name and source link, and its origin | `apps/web/lib/site.ts` |
| The health route the deploy smoke-tests | `apps/web/app/api/health/route.ts` |
| Workers build, bindings and deploy contract | `apps/web/next.config.mjs`, `open-next.config.ts`, `wrangler.template.jsonc` + `wiring.fixture.json` (→ `wrangler.jsonc`), `component.yaml` |
| The D1 database and the KV namespace (stage, prod) | `infra/terraform/cloudflare-d1`, `infra/terraform/cloudflare-kv` |
| The schema (migrations) and their runner | `packages/db`, applied by `infra/db-migrate` |
| Tests | `tests/web`, `tests/db` (vitest) |

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

Make the site yours in `apps/web/app`, and its name and the repository it
links to in `apps/web/lib/site.ts`. The site holds no secret of its own:
there is nothing to set before it works.

## How the bindings are wired

The Worker binds the database as `DB` and the namespace as `SECRETS`.
Neither id is hand-written: `apps/web/wrangler.template.jsonc` names them
as wiring tokens, and `wrangler.jsonc` is that template rendered — from
`wiring.fixture.json` (placeholders) for local work and verification, and on
every deploy from the documents the `cloudflare-d1` and `cloudflare-kv`
Terraform roots publish after their applies (`WIRING_CLOUDFLARE_D1`, `_KV`,
per environment). Edit the template, then `pnpm run wire:fixture` and commit
the render with the template.

The schema is `packages/db`'s migrations: each
`src/migrations/<NNN>_<name>/up.sql` is listed in `src/manifest.ts` with its
checksum, and the `db-migrate` component applies the pending ones to each
environment's database before the site deploys. To change the schema, add a
migration (never edit an applied one — its checksum is recorded), then
`pnpm --filter @saas/db run manifest:fix`. Locally,
`pnpm --filter @app/web db:migrate:local` applies the same files to
wrangler's local D1.

## How it deploys

Merges to `main` converge through [Orun](https://github.com/sourceplane/orun):
`.github/workflows/ci.yml` plans the changed components and runs each lane
against the workspace in `intent.yaml`. Per environment, the D1 database and
the KV namespace apply first, then the migrations, then the site builds with
that environment's bindings and origin and deploys — to `stage`, then to
`prod` once stage has converged on the same commit; `dev` only verifies. The
Worker is `envshare-web-<env>` on your account's workers.dev subdomain,
and every deploy is smoke-tested over HTTP: the home page must render to its
end, and `/api/health` must answer ok — which only a Worker that reached its
database and its namespace can. A pull request runs the same pipeline's
verify lanes: the packages type-checked, linted, tested and built, both test
suites, and the site built and dry-deployed for each environment, with
nothing deployed. (A push to `main` applies, migrates, builds and deploys.)

The pipeline holds one credential, GitHub's own `GITHUB_TOKEN`. The
Cloudflare tokens (one to deploy and apply the namespace, one scoped to D1)
and the account id are brokered per run from the workspace's Cloudflare
connection, and the binding ids travel as Orun secrets; nothing
provider-shaped is stored in the repository or in GitHub.

**Deploy by hand.** Orunbase's **Deploy** button on a component, or **Run
workflow** on the CI workflow in GitHub's Actions tab (on `main`), runs
`ci.yml` for the environment and components you pick, and each one deploys
exactly as a merge would deploy it. Leave the component blank to redeploy
every component in that environment, with nothing changed. A component with
nothing to run in that environment (a test suite in `prod`) is left out with
a notice.

## Custom domain

The site answers on workers.dev from its first deploy. To serve it on your
own domain:

1. Add the domain to the Cloudflare account the site deploys into, and attach
   it to the Worker (dashboard → Workers & Pages →
   `envshare-web-prod` → Settings → Domains & Routes → Add →
   Custom domain).
2. Set the environment's public origin in `intent.yaml`, so the next deploy
   builds the site for it — its metadata and Open Graph links (until then
   they use the workers.dev URL):

   ```yaml
   environments:
     prod:
       env:
         SITE_URL: https://envshare.example.com
   ```

   The site was born with the reserved placeholder
   `envshare.example.com` where its domain goes: that example, the API's
   example above, and `BASE_DOMAIN` under each environment in
   `intent.yaml`. Replace it with your domain in the same change, and land
   it with a change under `apps/web` so the merge rebuilds the site.

Share links are built from the address the page is served on, so they follow
the domain without a rebuild.

## Credits

The app is EnvShare by Andreas Thomas
([chronark/envshare](https://github.com/chronark/envshare), MIT —
`apps/web/LICENSE.md`); its footer credits the template and its
contributors. Inter is self-hosted (OFL-1.1 —
`apps/web/app/fonts/Inter-OFL.txt`, `apps/web/public/fonts/Inter-OFL.txt`).
