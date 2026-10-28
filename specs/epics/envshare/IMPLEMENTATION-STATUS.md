# envshare — implementation status

| Milestone | State | Landed |
|---|---|---|
| ES0 — the spec | ✅ | ES-1 |
| ES1 — the secret share on Workers | ✅ | ES-2 |
| ES2 — a baseline | planned | ES-3 |

## Departures from the upstream template

Everything not listed here is the template as it is upstream at `b8ea7c7`.

| # | What | Why |
|---|---|---|
| 1 | The app lives in `apps/web` of a pnpm workspace (`@app/web`), its layout (`app/`, `pkg/`, `util/`) kept | turso-starter's shape |
| 2 | Next.js 13.1 → 16.3.8, React 19; `next build --webpack`; `output: "standalone"`, `images.unoptimized`; awaited `params`; `head.tsx` → `generateMetadata`; `JSX.Element` → `React.JSX.Element`; the key and IV wrapped as `Uint8Array` for TypeScript 5.9's `BufferSource` | OpenNext 1.20.11 accepts 16.3; webpack is the playbook's default |
| 3 | `pages/api/v1/{store,load,secret,secret/[id],og}` (Edge) → App Router route handlers at the same URLs; no `runtime = "edge"`; the API's zod schemas moved to `lib/secret-api.ts` | OpenNext answers 500 on Edge-runtime routes; Next 16 refuses a route module exporting anything but handlers |
| 4 | Upstash Redis → the ciphertext in KV (`SECRETS`) with `expirationTtl`, the read limit and expiry in D1 (`010_secrets`) spent by one atomic `UPDATE … RETURNING` | KV is eventually consistent; the count must be D1's (design §3) |
| 5 | A TTL under 60 seconds is raised to 60; the API answers with the TTL stored | KV's floor for `expirationTtl` |
| 6 | The last read deletes the document at once (upstream: on the next read, after `remainingReads` reached 0) | Nothing of a spent document outlives its last read |
| 7 | The ciphertext is read before a read is spent, and a KV miss spends nothing (upstream: one Redis round-trip) | A write not yet visible where a read runs must not burn a read |
| 8 | `/api/v1/store` answers 400 without `encrypted` and `iv` (upstream: stored whatever came) | No document without ciphertext |
| 9 | The API headers are `<repo>-ttl` and `<repo>-reads` in a product (`envshare-*` here) | The rebrand names them for the product |
| 10 | The read and write counters are a D1 `metrics` table | Beside the documents, atomic |
| 11 | The home page renders per request; the GitHub stars counter and the testimonials are removed; the stats grid is two columns | The stars called GitHub on every render; the testimonials are the template's own |
| 12 | The deploy page describes this repository (get the source, a Cloudflare account, the README) | The template's page described Vercel and Upstash |
| 13 | `@vercel/analytics` (`ENABLE_VERCEL_ANALYTICS`) removed | A Vercel service |
| 14 | `@vercel/og` + twemoji → `next/og`, Inter SemiBold read from Static Assets through `ASSETS`, the default font on a miss | No third-party fetch at render |
| 15 | `@next/font/google` → `next/font/local` (`app/fonts`, OFL-1.1) | Google Fonts fail on GitHub's runners |
| 16 | `lib/site.ts` (`SITE_NAME`, `SOURCE_URL`, `siteUrl()`): the header, the titles and the footer; the footer still credits the template and its contributors | One rename seam |
| 17 | `app/api/health/route.ts` added | The deploy's smoke and the record's probe |
| 18 | jest → vitest (`tests/web`); the template's encryption and encoding tests ported | One runner for the workspace |
| 19 | rome → ESLint 9's flat config of eslint-config-next 16, `react-hooks/set-state-in-effect` off; `tailwind.config.js` → `.ts` | `next lint` is gone in Next 16; the rule postdates the template's effects |
| 20 | `apps/web/LICENSE.md` is upstream's MIT text, and `package.json` says `MIT` | The product carries it |
| 21 | `wrangler.template.jsonc` (D1 and KV bindings), `component.yaml`, `cloudflare-env.d.ts`, `open-next.config.ts` | The Worker's config and the deploy contract replace Vercel's |
| 22 | The API's default TTL stays 43260 seconds, as the template's code has it (its README and comment say 30 days) | Kept as built; the README here says the value |

## Decisions the brief left open

| Question | Chosen |
|---|---|
| Delete on the last read, or lazily | On the last read (design §3) |
| The ciphertext in D1 too | No: KV, with its own expiry (design §5) |
| Keep the dynamic Open Graph image | Yes, the font from Static Assets |

## Verified

- `pnpm typecheck`, `lint`, `test` (tests/web 27, tests/db 14) and `build`
  green; the Worker is 1.78 MiB gzipped (Workers Free).
- `wrangler dev` over the built Worker: health, the home page, a share
  stored, read twice and gone, the HTTP API, the Open Graph image, an old
  link's redirect.
- Every Baseline CI tier passes locally, the end-to-end tier included.
