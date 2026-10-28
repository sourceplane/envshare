#!/usr/bin/env bash
# THE LEAK GATE — what a site carries, and what stays in the factory.
#
# A site built from this baseline is somebody's site, not a copy of this
# repository. It gets the product: the app, its D1 root and migrations, its
# tests, its CI, its tooling, its README and its two context pages. It does
# NOT get the factory: the blueprints, the bootstrap and rebrand tooling, the
# test gates, the task contracts and identity under `.baseline/`, this
# repository's own epic and task tree, or BOOTSTRAP.md — and no file it does
# get may so much as NAME one of those paths, because in the product they do
# not exist.
#
# This asks orun to DERIVE the placement — every file every phase would write
# — and gates that set and the sources it is copied from. Derivation runs no
# hooks, contacts nothing and writes nothing. testing/placement.test.sh gates
# the same rules over a tree that is actually placed and branded.
#
# Needs: orun + python3. No network, no credential.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"

command -v orun >/dev/null || { echo "leak.test.sh needs orun on PATH" >&2; exit 1; }

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

echo "── deriving what every phase would place"
sets=()
while IFS=$'\t' read -r k v; do sets+=( --set "$k=$v" ); done < <(
  python3 - "$here/fixtures/acme.json" <<'PY'
import json, sys
for k, v in json.load(open(sys.argv[1])).items():
    if not k.startswith("_"):
        print(f"{k}\t{'true' if v is True else 'false' if v is False else v}")
PY
)
orun new --blueprint "$root/repo-blueprint.yaml" --status --json \
  --out "$scratch/empty" "${sets[@]}" > "$scratch/status.json"

# intent.yaml's `work:` block names this repository's epic and task tree; the
# product's copy has it stripped by a 01-product hook before it lands, so the
# source is gated as the product receives it.
cp "$root/intent.yaml" "$scratch/intent.yaml"
node "$root/tooling/bootstrap/work-tree.mjs" --strip --file "$scratch/intent.yaml" >/dev/null

python3 - "$scratch/status.json" "$root" "$scratch/intent.yaml" <<'PY'
import json, pathlib, re, sys
import yaml

status = json.load(open(sys.argv[1]))
root = pathlib.Path(sys.argv[2])
stripped_intent = pathlib.Path(sys.argv[3])
problems = []
def bad(m): problems.append(m)

# Against an empty output directory every file a phase places is "missing", so
# the union of those lists IS the site's file set.
placed = sorted({f for ph in status["phases"] for f in (ph.get("missing") or [])})
if len(placed) < 50:
    sys.exit(f"only {len(placed)} files derived — the tree is not a site")

# ── the context pack, exactly ─────────────────────────────────────────────
ALLOWED_AI = {"ai/context/deployment.md", "ai/context/operations.md"}
shipped_ai = {p for p in placed if p.startswith("ai/")}
for extra in sorted(shipped_ai - ALLOWED_AI):
    bad(f"{extra} ships to the site and is this repository's own state")
for missing in sorted(ALLOWED_AI - shipped_ai):
    bad(f"{missing} is declared a product file and would not ship")

# ── the factory never ships ───────────────────────────────────────────────
NEVER = (".baseline/", "specs/", "tasks/", "testing/", "hooks/", "docs/phases/",
         "tooling/rebrand/", "tooling/bootstrap/", ".github/workflows/baseline.yml",
         ".github/workflows/tag.yml", "BOOTSTRAP.md", "repo-blueprint.yaml",
         "blueprint.yaml", "flows/", "agents/")
for p in placed:
    for never in NEVER:
        if p == never or p.startswith(never):
            bad(f"{p} would ship — it is the factory, not the site")

# ── nothing local and nothing built ───────────────────────────────────────
LOCAL = re.compile(r"(^|/)(\.env(\.[^/]*\.local|\.local)?|\.dev\.vars(\..*)?|node_modules|\.next|"
                   r"\.open-next|\.wrangler|\.turbo|\.orun|\.terraform|next-env\.d\.ts|[^/]*\.tsbuildinfo|"
                   r"[^/]*\.tfstate(\.backup)?|\.terraform\.lock\.hcl)(/|$)")
for p in placed:
    if LOCAL.search(p):
        bad(f"{p} would ship — a local or built file of whoever ran the bootstrap")

# ── the site's README, not this repository's ──────────────────────────────
if "README.md" not in placed:
    bad("README.md would not ship")
for must in (".github/workflows/ci.yml",
             "apps/web/component.yaml", "apps/web/lib/site.ts", "tests/web/component.yaml",
             # the template's licence (and the self-hosted fonts'), and what
             # makes it run here: the browser's encryption and share link, the
             # ciphertext on KV and the read limit on D1, the API routes the
             # pages and the HTTP API call, and the deploy's smoke route
             "apps/web/LICENSE.md", "apps/web/app/fonts/Inter-OFL.txt", "apps/web/public/fonts/Inter-OFL.txt",
             "apps/web/public/fonts/Inter-SemiBold.ttf",
             "apps/web/pkg/encryption.ts", "apps/web/pkg/encoding.ts", "apps/web/pkg/id.ts",
             "apps/web/lib/store.ts", "apps/web/lib/env.ts", "apps/web/lib/secret-api.ts",
             "apps/web/app/api/v1/store/route.ts", "apps/web/app/api/v1/load/route.ts",
             "apps/web/app/api/v1/secret/route.ts", "apps/web/app/api/v1/secret/[id]/route.ts",
             "apps/web/app/api/v1/og/route.tsx", "apps/web/app/api/health/route.ts",
             "tests/web/src/store.test.ts", "tests/web/src/crypto.test.ts",
             ".rebrand/values.json", "apps/web/.env.example", "packages/.gitkeep",
             # the wiring path: the template, its fixture, the committed render
             # the deploy lane checks for, and the renderer the build calls
             "apps/web/wrangler.template.jsonc", "apps/web/wiring.fixture.json",
             "apps/web/wrangler.jsonc", "tooling/wire/live.mjs", "tooling/wire/render.mjs",
             # the D1 and KV roots the site binds
             "infra/terraform/cloudflare-d1/component.yaml",
             "infra/terraform/cloudflare-d1/terraform/main.tf",
             "infra/terraform/cloudflare-d1/terraform/adopt.tf",
             "infra/terraform/cloudflare-kv/component.yaml",
             "infra/terraform/cloudflare-kv/terraform/main.tf",
             # the schema: its migrations, their runner, the component that
             # applies them, the helpers and their tests
             "packages/db/component.yaml", "packages/db/package.json",
             "packages/db/src/manifest.ts", "packages/db/src/runner/cli.ts",
             "packages/db/src/runner/d1-api-adapter.ts",
             "packages/db/src/migrations/000_control/up.sql",
             "packages/db/src/migrations/010_secrets/up.sql",
             "infra/db-migrate/component.yaml",
             "tooling/migrations/manifest.mjs", "tooling/migrations/local.mjs",
             "tests/db/component.yaml", "tests/db/src/migrations.test.ts"):
    if must not in placed:
        bad(f"{must} would not ship, and a site needs it")

# ── no shipped file names the factory ─────────────────────────────────────
# Read from the SOURCE each placed file is copied from (the module's `from`).
# A product's file that points a reader at `testing/` or `repo-blueprint.yaml`
# points at nothing: those paths do not exist in the product.
FACTORY = re.compile(r"repo-blueprint|BOOTSTRAP\.md|(?<![\w-])(testing|specs|tasks|docs/phases|"
                     r"tooling/rebrand|tooling/bootstrap)/|(?<![\w/])\.baseline/")
bp = yaml.safe_load((root / "repo-blueprint.yaml").read_text())
sources = []
for m in bp.get("modules") or []:
    if m.get("mode") != "copy":
        continue
    frm, to = (m.get("from") or "").rstrip("/"), (m.get("to") or "").rstrip("/")
    for p in placed:
        if p == to or p.startswith(to + "/"):
            sources.append((p, frm + p[len(to):]))
scanned = 0
for shipped, src in sources:
    path = stripped_intent if src == "intent.yaml" else root / src
    try:
        text = path.read_text()
    except (UnicodeDecodeError, FileNotFoundError):
        continue
    scanned += 1
    for n, line in enumerate(text.splitlines(), 1):
        if FACTORY.search(line):
            bad(f"{shipped} (from {src}:{n}) names a factory path: {line.strip()[:90]}")
if scanned < 40:
    bad(f"only {scanned} shipped sources scanned for factory paths — this check has gone blind")

# ── PROVENANCE, which rebrand has no rule for ─────────────────────────────
# Not a search for this baseline's name: the rebrand rewrites that, and this
# gate reads the sources before it runs. What the rebrand cannot rewrite is a
# sentence about where the site CAME FROM, or one about being a baseline.
PROVENANCE = re.compile(
    r"\bfork(ed)? (of|from)\b|\bbaseline (repo|repository|commit|tag)\b|\bthis baseline\b"
    r"|BOOTSTRAP\.md|repo-blueprint|specs/epics|\.baseline/",
    re.I,
)
SOURCES = {"README.md": ".baseline/product/README.md",
           "ai/context/operations.md": "ai/context/operations.md",
           "ai/context/deployment.md": "ai/context/deployment.md"}
for shipped, src in SOURCES.items():
    for n, line in enumerate((root / src).read_text(errors="replace").splitlines(), 1):
        if PROVENANCE.search(line):
            bad(f"{shipped} (from {src}:{n}) tells the site about the factory: {line.strip()[:80]}")

if problems:
    print("FAIL: the site would carry the baseline:", file=sys.stderr)
    for p in problems:
        print(f"  - {p}", file=sys.stderr)
    sys.exit(1)

print(f"   {len(placed)} files derived across every phase")
print(f"   ai/context is exactly {len(ALLOWED_AI)} declared file(s); none of the "
      f"{len(NEVER)} factory paths; nothing local or built; no provenance prose")
print(f"   {scanned} shipped sources name no factory path")
PY

echo "leak.test.sh: ok"
