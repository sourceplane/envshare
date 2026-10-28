# envshare — EnvShare on Cloudflare Workers, KV and D1

**The template shares environment variables through a link only its holder
can read: the browser encrypts with AES-GCM, sends only the ciphertext, and
keeps the key in the link's fragment; each link has a read limit and a TTL.
The port runs it as one Cloudflare Worker and splits each Upstash Redis hash
in two — the ciphertext in Workers KV under the document's TTL, the read
limit and expiry in D1, spent by one atomic statement because KV is
eventually consistent — and the baseline makes a copy of it somebody else's
in one landing.**

| | |
|---|---|
| Status | ✅ Shipped (`baseline-v1`) — proven offline in Baseline CI; not yet live (risk ES-A) |
| Upstream | [chronark/envshare](https://github.com/chronark/envshare) (MIT), at `b8ea7c7` |
| Reference | [turso-starter](https://github.com/sourceplane/turso-starter) — Next.js on OpenNext with D1, its migrations and bootstrap; [kv-redis-starter](https://github.com/sourceplane/kv-redis-starter) — a KV root |
| Key | `ES` |

## Read in this order

1. [design.md](design.md) — the template, how each Vercel piece maps to
   Cloudflare, the documents on KV and D1, the repository and the build, and
   the alternatives rejected.
2. [implementation-plan.md](implementation-plan.md) — the milestones and
   what each one lands.
3. [risks-and-open-questions.md](risks-and-open-questions.md) — what is not
   proven, and what was accepted.
4. [IMPLEMENTATION-STATUS.md](IMPLEMENTATION-STATUS.md) — what shipped, and
   every departure from the upstream template.

## Milestones

| Milestone | What it lands | Task |
|---|---|---|
| ES0 — the spec | the repository, its intent, CI, tooling and spec index; this doc set | ES-1 |
| ES1 — the secret share on Workers | the template in `apps/web`, its documents on KV and D1 with the atomic last read, the migrations, its tests, the README | ES-2 |
| ES2 — a baseline | the console card, the build document, the context pack and the baseline's tests | ES-3 |
