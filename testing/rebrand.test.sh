#!/usr/bin/env bash
# THE REBRAND WRITES EACH VALUE ONCE, AND WHAT IT WROTE STAYS WRITTEN.
#
# Drives the real tooling/rebrand/rebrand.mjs over one-file trees and compares
# the file. Each case is a shape this baseline's identity actually takes in the
# tree — the source link, the site-name seam, the worker name in the component
# and the wrangler config, the D1 database names and the terraform `repo` they
# are built from, the migration runner's `repo`, the placeholder domain, a
# secret ref — and the
# survival cases run through three passes, so a value an earlier rebrand
# wrote (a re-run phase re-runs the rebrand over everything placed) comes
# out of every later one unchanged.
#
# The identity is PINNED (fixtures/baseline-identity.envshare.json)
# rather than read from .baseline/identity.json: what this tests is the engine,
# and its fixtures spell the identity out literally.
#
# Needs: node, git. No network.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
rebrand="$here/../tooling/rebrand/rebrand.mjs"
identity="$here/fixtures/baseline-identity.envshare.json"

fail=0
# check NAME VALUES-JSON FILE CONTENT WANT [PASSES]
check() {
  local name="$1" values="$2" file="$3" content="$4" want="$5" passes="${6:-1}"
  local tmp got out i
  tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  mkdir -p "$tmp/$(dirname "$file")" "$tmp/.rebrand"
  printf '%s\n' "$content" > "$tmp/$file"
  printf '%s\n' "$values" > "$tmp/.rebrand/values.json"
  for ((i = 1; i <= passes; i++)); do
    git -C "$tmp" add -A
    if ! out="$(cd "$tmp" && node "$rebrand" --baseline-identity "$identity" --values .rebrand/values.json --allow-dirty 2>&1)"; then
      echo "   ✕  $name: rebrand pass $i failed:" >&2
      printf '%s\n' "$out" | sed 's/^/        /' >&2
      fail=1
      rm -rf "$tmp"
      return
    fi
  done
  got="$(cat "$tmp/$file")"
  rm -rf "$tmp"
  if [ "$got" = "$want" ]; then
    echo "   ok  $name"
  else
    echo "   ✕  $name:" >&2
    echo "        got:  $got" >&2
    echo "        want: $want" >&2
    fail=1
  fi
}

acme='{"reponame":"acme-docs","productname":"Acme Docs","productdomain":"acme.dev","githuborg":"acme-inc","subdomain":"acme","orunWorkspace":"ws_79BDXAZQ"}'

echo "── rebrand: the site's own identity"
check "the source link names the product's owner and repository" \
  "$acme" apps/web/lib/site.ts \
  'export const SOURCE_URL = "https://github.com/sourceplane/envshare";' \
  'export const SOURCE_URL = "https://github.com/acme-inc/acme-docs";'
check "the site-name seam takes the product's name" \
  "$acme" apps/web/lib/site.ts 'export const SITE_NAME = "EnvShare";' \
  'export const SITE_NAME = "Acme Docs";'
check "…and stays a valid string for a name with an apostrophe and an ampersand" \
  '{"reponame":"sams-todos","productname":"Sam'"'"'s Todos & Lists","productdomain":"sam.dev"}' \
  apps/web/lib/site.ts 'export const SITE_NAME = "EnvShare";' \
  'export const SITE_NAME = "Sam'"'"'s Todos & Lists";'
check "the display name elsewhere is content, and is left alone" \
  "$acme" apps/web/README.md 'EnvShare, on KV and D1. EnvShare.' \
  'EnvShare, on KV and D1. EnvShare.'
check "the worker name is re-prefixed, the environment suffix kept" \
  "$acme" apps/web/component.yaml 'workerName: envshare-web' \
  'workerName: acme-docs-web'
check "the wrangler config's worker name, template and render alike" \
  "$acme" apps/web/wrangler.template.jsonc '  "name": "envshare-web",' \
  '  "name": "acme-docs-web",'
check "the environment URLs: worker name and subdomain" \
  "$acme" intent.yaml '    url: https://envshare-web-stage.your-workers-subdomain.workers.dev' \
  '    url: https://acme-docs-web-stage.acme.workers.dev'
check "the D1 root's terraform repo — every database name is built on it" \
  "$acme" infra/terraform/cloudflare-d1/terraform/main.tf '  default = "envshare"' \
  '  default = "acme-docs"'
check "the per-environment terraform repo parameter" \
  "$acme" intent.yaml '        repo: envshare' \
  '        repo: acme-docs'
check "the D1 root's own repo parameter" \
  "$acme" infra/terraform/cloudflare-d1/component.yaml '    repo: envshare' \
  '    repo: acme-docs'
check "the migration runner's repo parameter" \
  "$acme" infra/db-migrate/component.yaml '    repo: envshare' \
  '    repo: acme-docs'
check "a fixture's database name follows the same rule" \
  "$acme" apps/web/wiring.fixture.json '    "d1_database_name": "stg-envshare-stage"' \
  '    "d1_database_name": "stg-acme-docs-stage"'
check "the placeholder domain is the product's domain, not a renamed slug" \
  "$acme" intent.yaml '      BASE_DOMAIN: envshare.example.com' \
  '      BASE_DOMAIN: acme.dev'
check "no domain given: the reserved placeholder, for an owner to replace later" \
  '{"reponame":"acme-docs","productname":"Acme Docs","githuborg":"acme-inc","subdomain":"acme"}' \
  intent.yaml '      BASE_DOMAIN: envshare.example.com' \
  '      BASE_DOMAIN: acme-docs.example.com'
check "an empty domain is no domain" \
  '{"reponame":"acme-docs","productname":"Acme Docs","productdomain":""}' \
  intent.yaml '      BASE_DOMAIN: envshare.example.com' \
  '      BASE_DOMAIN: acme-docs.example.com'
check "the repo slug" \
  "$acme" package.json '  "name": "envshare",' \
  '  "name": "acme-docs",'
check "a wiring secret ref names the product's workspace and project" \
  "$acme" apps/web/component.yaml \
  '    WIRING_CLOUDFLARE_D1_STAGE: "secret://envshare/envshare/stage/WIRING_CLOUDFLARE_D1"' \
  '    WIRING_CLOUDFLARE_D1_STAGE: "secret://ws_79BDXAZQ/acme-docs/stage/WIRING_CLOUDFLARE_D1"'
check "a templated provider secret ref too (the D1 token the root and the runner bind)" \
  "$acme" infra/db-migrate/component.yaml \
  '    CLOUDFLARE_API_TOKEN: "secret://envshare/envshare/{{ .environment }}/CLOUDFLARE_D1_TOKEN"' \
  '    CLOUDFLARE_API_TOKEN: "secret://ws_79BDXAZQ/acme-docs/{{ .environment }}/CLOUDFLARE_D1_TOKEN"'
check "the credit to the template keeps the template's repository and deployment" \
  "$acme" apps/web/app/layout.tsx '<Link href="https://github.com/chronark/envshare">EnvShare</Link> (envshare.dev)' \
  '<Link href="https://github.com/chronark/envshare">EnvShare</Link> (envshare.dev)'
check "…and its contributors' page" \
  "$acme" apps/web/app/layout.tsx 'href="https://github.com/chronark/envshare/graphs/contributors"' \
  'href="https://github.com/chronark/envshare/graphs/contributors"'
check "the HTTP API's headers are named after the product" \
  "$acme" apps/web/app/api/v1/secret/route.ts 'ttl: req.headers.get("envshare-ttl"), reads: req.headers.get("envshare-reads"),' \
  'ttl: req.headers.get("acme-docs-ttl"), reads: req.headers.get("acme-docs-reads"),'
check "the site's keywords name the product" \
  "$acme" apps/web/app/layout.tsx 'keywords: ["envshare", "secure", "secrets"],' \
  'keywords: ["acme-docs", "secure", "secrets"],'
check "org-owned identity is not renamed" \
  "$acme" intent.yaml 'apiVersion: sourceplane.io/v1 # mail ops@sourceplane.ai' \
  'apiVersion: sourceplane.io/v1 # mail ops@sourceplane.ai'
check "without githuborg the source link keeps the baseline's owner" \
  '{"reponame":"acme-docs","productname":"Acme Docs","productdomain":"acme.dev"}' \
  apps/web/lib/site.ts 'const SOURCE_URL = "https://github.com/sourceplane/envshare";' \
  'const SOURCE_URL = "https://github.com/sourceplane/acme-docs";'

echo "── rebrand: a written value is not rewritten, in any later pass"
contains='{"reponame":"envshare-2","productname":"EnvShare 2","productdomain":"envshare.example.com.au","githuborg":"sourceplane","subdomain":"your-workers-subdomain-2"}'
check "a repo slug containing the baseline's slug survives three passes" \
  "$contains" package.json '  "name": "envshare",' \
  '  "name": "envshare-2",' 3
check "a worker name built on it survives three passes" \
  "$contains" apps/web/component.yaml 'workerName: envshare-web' \
  'workerName: envshare-2-web' 3
check "a database name built on it survives three passes" \
  "$contains" apps/web/wiring.fixture.json '"d1_database_name": "prod-envshare-prod"' \
  '"d1_database_name": "prod-envshare-2-prod"' 3
check "a domain containing the baseline's domain survives three passes" \
  "$contains" intent.yaml 'BASE_DOMAIN: envshare.example.com' \
  'BASE_DOMAIN: envshare.example.com.au' 3
check "a subdomain containing the placeholder survives three passes" \
  "$contains" apps/web/component.yaml 'workersDevSubdomain: your-workers-subdomain' \
  'workersDevSubdomain: your-workers-subdomain-2' 3
check "a site name containing the baseline's name survives three passes" \
  "$contains" apps/web/lib/site.ts 'export const SITE_NAME = "EnvShare";' \
  'export const SITE_NAME = "EnvShare 2";' 3

# --verify runs in every phase. Without the product's values it cannot tell
# the product's own identity from a leftover; with them it can. A real
# leftover must fail it either way.
verify() { # NAME VALUES FILE CONTENT WANT(pass|fail) [--values]
  local name="$1" values="$2" file="$3" content="$4" want="$5" withvalues="${6:-}" tmp got
  tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  mkdir -p "$tmp/$(dirname "$file")" "$tmp/.rebrand"
  printf '%s\n' "$content" > "$tmp/$file"
  printf '%s\n' "$values" > "$tmp/.rebrand/values.json"
  git -C "$tmp" add -A
  if (cd "$tmp" && node "$rebrand" --baseline-identity "$identity" --verify ${withvalues:+--values .rebrand/values.json} >/dev/null 2>&1); then got=pass; else got=fail; fi
  rm -rf "$tmp"
  if [ "$got" = "$want" ]; then echo "   ok  $name"; else echo "   ✕  $name: --verify ${got}ed, want $want" >&2; fail=1; fi
}
echo "── rebrand --verify: the product's own identity is not residue"
verify "given the values, a slug containing the baseline's passes" \
  "$contains" package.json '"name": "envshare-2"' pass --values
verify "without them it cannot know, and fails" \
  "$contains" package.json '"name": "envshare-2"' fail
verify "given the values, a real leftover still fails" \
  "$acme" package.json '"name": "envshare"' fail --values
verify "a leftover worker name fails" \
  "$acme" apps/web/wrangler.jsonc '"name": "envshare-web",' fail --values
verify "a leftover database name fails" \
  "$acme" apps/web/wiring.fixture.json '"d1_database_name": "stg-envshare-stage"' fail --values
verify "a leftover runner parameter fails" \
  "$acme" infra/db-migrate/component.yaml '    repo: envshare' fail --values
verify "a leftover API header fails" \
  "$acme" apps/web/app/api/v1/secret/route.ts 'req.headers.get("envshare-ttl")' fail --values
verify "the credit to the template is not residue" \
  "$acme" apps/web/app/layout.tsx 'href="https://github.com/chronark/envshare" (envshare.dev)' pass --values
verify "a leftover code identifier fails (no rule renames it — so nothing may spell it)" \
  "$acme" apps/web/app/x.ts 'export class Envshare {}' fail --values
verify "a clean product passes" \
  "$acme" package.json '"name": "acme-docs"' pass --values

echo "── rebrand: a residue it cannot rename fails the rebrand itself"
tmp="$(mktemp -d)"; git -C "$tmp" init -q; mkdir -p "$tmp/.rebrand" "$tmp/apps/web"
printf '%s\n' "$acme" > "$tmp/.rebrand/values.json"
printf 'const x = "ENVSHARE_TOKEN"\n' > "$tmp/apps/web/x.ts"
git -C "$tmp" add -A
if (cd "$tmp" && node "$rebrand" --baseline-identity "$identity" --values .rebrand/values.json --allow-dirty >/dev/null 2>&1); then
  echo "   ✕  an unrenamable env-var prefix passed the rebrand" >&2; fail=1
else
  echo "   ok  an unrenamable env-var prefix fails the rebrand, naming the file"
fi
rm -rf "$tmp"

[ "$fail" -eq 0 ] || exit 1
echo "rebrand.test.sh: ok"
