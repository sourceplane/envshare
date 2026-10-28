# envshare — design

## 1. The template

EnvShare is a Next.js 13.1 app: a share page that encrypts text (or a file)
in the browser with AES-GCM under a fresh 128-bit key, posts the ciphertext
and IV with a TTL and a read limit to an Edge API route, and builds a link
`/unseal#<base58(version, id, key)>`; an unseal page that loads the
ciphertext and decrypts it; an HTTP API (`/api/v1/secret`) that stores and
returns opaque strings with `envshare-ttl` and `envshare-reads` headers; a
home page with read and write counters and the repository's GitHub stars;
an Open Graph image. Each document is one Upstash Redis hash — `data`, `iv`,
`remainingReads` — with Redis's EXPIRE for the TTL and HINCRBY to spend a
read; a document is deleted on the read after its last.

## 2. How each piece maps

| Template | Here | Why |
|---|---|---|
| Next.js 13.1, `pages/api` Edge routes, the `app` beta | Next.js 16.3.8 App Router, the API as route handlers at the same URLs, built by OpenNext into one Worker + Static Assets | OpenNext answers 500 on `runtime = "edge"`; the URLs are the template's contract |
| The browser's AES-GCM and the link encoding (`pkg/`, `util/`) | Unchanged | The product's security is the browser's; the port touches only storage |
| One Redis hash per document | The ciphertext in KV, the count and expiry in D1 | §3 |
| Redis counters `envshare:metrics:{reads,writes}` | A D1 `metrics` table | Atomic increments beside the documents |
| `@vercel/og` + twemoji, `@next/font/google` | `next/og` with Inter from Static Assets; `next/font/local` | No third-party fetch at render; Google Fonts fail on the runners |
| GitHub stars, testimonials, Vercel Analytics, the Vercel/Upstash deploy guide | Dropped; a deploy page for this repository | The template's own site |

## 3. The documents on KV and D1

A document is two halves:

- **The ciphertext** is a KV value (`SECRETS`, key `secret:<id>`), a JSON
  `{encrypted, iv}` (the share page) or `{secret}` (the API), written with
  `expirationTtl` equal to the TTL. KV refuses a TTL under 60 seconds, so a
  shorter one is raised to 60 (`effectiveTtl`) and the API answers with the
  TTL stored. A TTL of 0 writes no expiry.
- **The count and the clock** are a D1 row, `secrets(id, remaining_reads,
  expires_at, created_at)`; `remaining_reads` NULL is unlimited, `expires_at`
  NULL is no TTL.

**Writing** inserts the row first, then the KV value: a KV failure leaves a
row with no ciphertext, which reads as "not found" — never a document
without its limit. The same batch sweeps rows whose `expires_at` has passed
and counts the write.

**Reading** gets the KV value first. A miss — expired, never stored, or a
write not yet visible in this location — answers 404 and spends nothing (an
expired row is deleted). A hit spends one read with a single statement:

```sql
UPDATE secrets SET remaining_reads = remaining_reads - 1
 WHERE id = ? AND (expires_at IS NULL OR expires_at > ?)
   AND (remaining_reads IS NULL OR remaining_reads > 0)
RETURNING remaining_reads
```

No row back means expired or exhausted — possibly by a reader that won the
race a moment ago — and the reader gets 404 while both halves are deleted.
`0` back means this read was the last: both halves are deleted and the
document is served. D1 runs each statement serially against one primary, so
of any number of concurrent last reads exactly one gets a row. KV alone
could not give that: it is eventually consistent, and two locations could
each read "1 left".

The expiry lives in D1 as well as KV, so a document is never served past
its TTL even where KV has not yet dropped the value.

## 4. The repository and the build

turso-starter's shape: a pnpm workspace with `apps/web` (`@app/web`),
`packages/db` (`@saas/db`, the migrations and their runner), `infra/db-migrate`,
the `cloudflare-d1` and `cloudflare-kv` Terraform roots, `tests/web` and
`tests/db`. Per environment the two roots apply and lease-publish their
wiring documents, `db-migrate` waits on the D1 apply and applies
`010_secrets`, and the web lane waits on all three, renders `wrangler.jsonc`
from the documents and deploys `<repo>-web-<env>`. The D1 apply and the
migrations use a `d1-edit` key; the KV root and the deploy use
`workers-deploy`. The smoke requires `</html>` on `/` and `"ok":true` from
`/api/health`, which counts the `secrets` table and reads a probe key from
KV — it stores nothing and spends no read.

The baseline is cirrus's: `blueprint.yaml` (the card), `repo-blueprint.yaml`
(one landing, `01-product`, then the record, `02-docs`), the `SITE_NAME`
seam and the residue sweep, the context pack, and the tiers in `testing/`.

## 5. Alternatives rejected

| Alternative | Why not |
|---|---|
| The count in KV, next to the ciphertext | Eventually consistent: two concurrent last reads in two locations could both be served |
| Everything in D1 (ciphertext as a column, a sweep for expiry) | Loses KV's own expiry, so a document outlives its TTL until a sweep runs; the brief's split keeps each half where it is honest |
| A Durable Object per document | Strongly consistent, but a class, a migration and a binding per product for what one D1 statement does |
| Spending the read before reading KV | A KV miss (propagation) would burn a read the reader never got |
| Keeping the template's lazy delete (on the read after the last) | The spent ciphertext would outlive its last read |
