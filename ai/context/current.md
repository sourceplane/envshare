# envshare — where this repository stands

The entry page for anyone (or any agent) picking this repository up. It is
this repository's own state and does not ship to a product built from it;
the two pages that do are [operations.md](operations.md) and
[deployment.md](deployment.md).

## What it is

EnvShare (chronark/envshare) — share environment variables through a link
only its holder can read: AES-GCM in the browser, the key in the link's
fragment, each link limited to a number of reads and a TTL — on Cloudflare
Workers + Static Assets, the ciphertext in a Workers KV namespace written
with the document's TTL, the read limits and expiries in a D1 database, both
provisioned by Terraform. Packaged as an Orun baseline:
`orun new --blueprint repo-blueprint.yaml` builds a new product in its own
repository and takes it to live on stage and prod in one landing
(`01-product`: cloudflare-d1, cloudflare-kv → db-migrate → web per
environment), then records what went live (`02-docs`).

## Release

| | |
|---|---|
| Latest tag | `baseline-v1` (ES0–ES2: the spec, the secret share on Workers with its documents on KV and D1 and the atomic last read, a baseline) |
| Proven live | No. Everything short of the platform is proven offline in Baseline CI: the migration lane against a stand-in D1 API, and the built Worker served under `wrangler dev` — a share read to its limit and gone, a TTL kept, two concurrent last reads of which one is served, no request carrying the key. A live bootstrap from a tag is still to come (risk ES-A) |

## Where to read

| Question | Page |
|---|---|
| What shipped, and every departure from upstream | `specs/epics/envshare/IMPLEMENTATION-STATUS.md` |
| Why it is built this way | [decisions.md](decisions.md), then `specs/epics/envshare/design.md` |
| What could still go wrong | [open-risks.md](open-risks.md), then `specs/epics/envshare/risks-and-open-questions.md` |
| How to instantiate it | `BOOTSTRAP.md`, `docs/phases/` |
| What each component is | `<component>/docs/` beside each `component.yaml` — `apps/web`, `packages/db`, `infra/db-migrate`, `infra/terraform/cloudflare-{d1,kv}`, `tests/{web,db}` (generated; `python3 tooling/catalog/gen-component-docs.py`) |

## Next

1. Bootstrap one product from `baseline-v1` against a workspace whose
   Cloudflare token can mint D1 Edit as well as Workers Scripts and KV,
   share and read one document on stage, and record the timings (closes
   ES-A).
