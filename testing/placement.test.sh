#!/usr/bin/env bash
# TIER 1 — the tree is placed, branded, and made to answer.
#
# A real bootstrap is `orun new --run-hooks --resume` against a workspace: it
# places each phase, runs that phase's hooks, lands a pull request and watches
# the convergence. Everything in that sentence except the platform can run
# here, offline, and this file runs it:
#
#   1. the whole blueprint placed in one go — orun runs `validate` and
#      `plan --dry-run` inside the produced tree and says so; asserted, because
#      a future orun that stopped running them would weaken this tier in silence;
#   2. THE OFFLINE BOOTSTRAP (testing/lib/bootstrap.sh) — both phases placed in
#      order onto what the previous one landed, finished by the blueprint's OWN
#      `run:` hooks (retouch, rebrand, re-tenant, work-tree strip, the
#      deferrals and their restore, the deployment record), each
#      landing a commit;
#   3. the product it ends with: branded with no residue — the page, the
#      Worker, the D1 database and KV namespace names, the
#      migration runner and every secret ref its own — carrying nothing of the factory and naming none of it,
#      re-tenanted, its gates restored, its record rendered;
#   4. what the product's own CI does with the 01-product merge: `orun plan`
#      for a push to main over exactly that commit — INFRA BEFORE APP, three
#      levels per environment: the D1 database and the KV namespace applied,
#      then the migrations (waiting on that environment's D1 apply alone),
#      then the Worker deploy (waiting on that environment's two applies and
#      migrations alone), stage and prod side by side, nothing on
#      dev; the build rendering the
#      environment's wiring, the Worker, smoke and secret refs the product's
#      own. Then the same edges on a pull request, where they are advisory and
#      nothing waits; and the 02-docs merge, which plans nothing at all;
#   5. a `--resume` over the finished site places nothing and un-brands nothing.
#
# testing/e2e.test.sh goes on from here: it installs, builds and serves the
# product and runs its smoke against it.
#
# Needs: orun, node, pnpm, python3 (+PyYAML), git. No credential. The
# deployment-record probes reach the network if they can, and pass without it.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
# shellcheck source=lib/bootstrap.sh
source "$here/lib/bootstrap.sh"

for bin in orun node pnpm python3 git; do
  command -v "$bin" >/dev/null || { echo "placement.test.sh needs $bin on PATH" >&2; exit 1; }
done
# Step 4 is the PRODUCT's own plan, so it must be planned by the orun the
# product's CI runs (ci.yml's pin) or newer: an older orun (v2.58.11, the
# bootstrap's floor before v2.87.0) does not apply a dependsOn edge's
# `modeRules`, and would plan a pull request with the site waiting on the D1
# plan and the migrations' plan.
pin="$(sed -n 's/^ *version: *v\([0-9.]*\) *$/\1/p' "$root/.github/workflows/ci.yml" | head -1)"
have="$(orun --version | sed -n 's/.*version \([0-9.]*\).*/\1/p')"
python3 -c "import sys; v=lambda s: tuple(map(int, s.split('.'))); sys.exit(0 if v(sys.argv[1]) >= v(sys.argv[2]) else 1)" "$have" "$pin" \
  || { echo "placement.test.sh plans as the product's CI does: run it with orun >= v$pin (ci.yml's pin), not v$have" >&2; exit 1; }

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
fails=0
fail() { echo "  ✕ $*" >&2; fails=$((fails + 1)); }
values="$here/fixtures/acme.json"
repo="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['reponame'])" "$values")"

sets=()
while IFS=$'\t' read -r k v; do sets+=( --set "$k=$v" ); done < <(
  python3 - "$values" <<'PY'
import json, sys
for k, v in json.load(open(sys.argv[1])).items():
    if not k.startswith("_"):
        print(f"{k}\t{'true' if v is True else 'false' if v is False else v}")
PY
)

# ── 1. the whole blueprint, one placement ──────────────────────────────────
echo "── placing the whole blueprint at once (offline, no credential)"
whole="$scratch/whole"
mkdir -p "$whole"/{apps,infra,packages,tests}
for d in apps infra packages tests; do touch "$whole/$d/.gitkeep"; done
if ! orun new --blueprint "$root/repo-blueprint.yaml" --out "$whole" "${sets[@]}" > "$scratch/whole.log" 2>&1; then
  echo "FAIL: the placement did not run" >&2; tail -20 "$scratch/whole.log" >&2; exit 1
fi
# The line's wording moved between orun releases (v2.58: `repo gate: validate +
# plan --dry-run passed`; v2.79: `Verified  intent valid · N components …`).
grep -Eq "repo gate: validate \+ plan --dry-run passed|Verified +intent valid" "$scratch/whole.log" \
  || fail "the placement did not report the repo-scale gate (orun validate + plan --dry-run inside the tree)"
n="$(find "$whole" -type f -not -path '*/.orun/*' | wc -l | tr -d ' ')"
[ "$n" -ge 50 ] || fail "only $n files placed — that is not a product"
[ "$fails" -eq 0 ] && echo "   $n files placed; the repo-scale gate ran"

# ── 2. the offline bootstrap ───────────────────────────────────────────────
echo "── the offline bootstrap: both phases, their own hooks, a landing each"
tree="$scratch/$repo"     # named as the repository is: orun names the project after it
bootstrap_offline "$root" "$tree" "$values" "$scratch/logs" > "$scratch/bootstrap.log" 2>&1 || {
  echo "FAIL: the offline bootstrap stopped" >&2; tail -40 "$scratch/bootstrap.log" >&2; exit 1; }
grep -E '^── ' "$scratch/bootstrap.log" | sed 's/^/  /'
commits="$(git -C "$tree" rev-list --count HEAD)"
[ "$commits" = 2 ] || fail "the bootstrap landed $commits commits, not one per phase (2)"

# ── 3. the product it ends with ────────────────────────────────────────────
echo "── the product it produced"
(cd "$tree" && node "$root/tooling/rebrand/rebrand.mjs" --verify --values .rebrand/values.json) > "$scratch/verify.log" 2>&1 \
  || { fail "rebrand --verify found the baseline's identity in the product:"; sed 's/^/      /' "$scratch/verify.log" >&2; }

python3 - "$tree" "$values" "$root" <<'PY' || fails=$((fails + 1))
import json, pathlib, re, subprocess, sys
import yaml
tree, values, root = pathlib.Path(sys.argv[1]), json.load(open(sys.argv[2])), pathlib.Path(sys.argv[3])
problems = []
def bad(m): problems.append(m)
repo, org, name, sub, ws = (values[k] for k in ("reponame", "githuborg", "productname", "subdomain", "orunWorkspace"))

tracked = subprocess.run(["git", "ls-files"], cwd=tree, capture_output=True, text=True, check=True).stdout.split()

# Nothing of the factory, nothing local, exactly the two context pages…
NEVER = (".baseline/", "specs/", "tasks/", "testing/", "hooks/", "docs/phases/",
         "tooling/rebrand/", "tooling/bootstrap/", ".github/workflows/baseline.yml",
         ".github/workflows/tag.yml", "BOOTSTRAP.md", "repo-blueprint.yaml", "blueprint.yaml")
for p in tracked:
    if any(p == n or p.startswith(n) for n in NEVER):
        bad(f"{p} is in the product — it is the factory")
    if re.search(r"(^|/)(\.env(\.local)?|\.dev\.vars|node_modules|\.orun|\.next|\.open-next|\.terraform)(/|$)|\.tfstate$", p):
        bad(f"{p} is in the product — a local or built file")
ai = {p for p in tracked if p.startswith("ai/")}
if ai != {"ai/context/deployment.md", "ai/context/operations.md"}:
    bad(f"ai/ in the product is {sorted(ai)}")
# …and no file it carries NAMES the factory: those paths do not exist here.
FACTORY = re.compile(r"repo-blueprint|BOOTSTRAP\.md|(?<![\w-])(testing|specs|tasks|docs/phases|"
                     r"tooling/rebrand|tooling/bootstrap)/|(?<![\w/])\.baseline/")
for p in tracked:
    try:
        text = (tree / p).read_text()
    except UnicodeDecodeError:
        continue
    for n, line in enumerate(text.splitlines(), 1):
        if FACTORY.search(line):
            bad(f"{p}:{n} names a factory path: {line.strip()[:80]}")

# The identity, where the product carries it.
site = (tree / "apps/web/lib/site.ts").read_text()
if f"SITE_NAME = {json.dumps(name)}" not in site:
    bad(f"apps/web/lib/site.ts does not name the site {name!r}")
if f'SOURCE_URL = "https://github.com/{org}/{repo}"' not in site:
    bad(f"apps/web/lib/site.ts does not link github.com/{org}/{repo}")
# The credit to the template survives the rename (the template's repository
# is masked), and the HTTP API's headers are the product's own.
layout = (tree / "apps/web/app/layout.tsx").read_text()
if 'href="https://github.com/chronark/envshare"' not in layout:
    bad("the footer no longer credits the template's repository")
api = (tree / "apps/web/app/api/v1/secret/route.ts").read_text()
if f'req.headers.get("{repo}-ttl")' not in api or f'req.headers.get("{repo}-reads")' not in api:
    bad(f"the HTTP API's headers are not named {repo}-ttl and {repo}-reads")
web = yaml.safe_load((tree / "apps/web/component.yaml").read_text())["spec"]
if web["parameters"]["workerName"] != f"{repo}-web":
    bad(f"workerName is {web['parameters']['workerName']}, not {repo}-web")
if web["parameters"]["workersDevSubdomain"] != sub:
    bad(f"workersDevSubdomain is {web['parameters']['workersDevSubdomain']}, not {sub}")
for cfg in ("wrangler.jsonc", "wrangler.template.jsonc"):
    if f'"name": "{repo}-web"' not in (tree / "apps/web" / cfg).read_text():
        bad(f"apps/web/{cfg} does not name the Worker {repo}-web")
if json.loads((tree / "package.json").read_text())["name"] != repo:
    bad("package.json is not named for the product")

# The D1 database and the KV namespace: their names are built on the product's
# repo slug, so two products in one account never collide (each is unique per
# account).
d1 = yaml.safe_load((tree / "infra/terraform/cloudflare-d1/component.yaml").read_text())["spec"]
kv = yaml.safe_load((tree / "infra/terraform/cloudflare-kv/component.yaml").read_text())["spec"]
mig = yaml.safe_load((tree / "infra/db-migrate/component.yaml").read_text())["spec"]
for root_ in ("cloudflare-d1", "cloudflare-kv"):
    if f'default = "{repo}"' not in (tree / f"infra/terraform/{root_}/terraform/main.tf").read_text():
        bad(f"the {root_} root's terraform `repo` default is not the product's slug")
for label, spec in (("cloudflare-d1", d1), ("db-migrate", mig)):
    if (spec.get("parameters") or {}).get("repo") != repo:
        bad(f"{label}'s repo parameter is {(spec.get('parameters') or {}).get('repo')}, not {repo}")
fixture = json.loads((tree / "apps/web/wiring.fixture.json").read_text())
for env, prefix in (("dev", "dev-"), ("stage", "stg-"), ("prod", "prod-")):
    want = f"{prefix}{repo}-{env}"
    if (fixture.get(f"cloudflare-d1/{env}") or {}).get("d1_database_name") != want:
        bad(f"the fixture's {env} database name is not {want}")
# Every secret ref names the product's workspace and project.
for label, refs in (("apps/web", web.get("secretEnv") or {}), ("cloudflare-d1", d1.get("secretEnv") or {}),
                    ("cloudflare-kv", kv.get("secretEnv") or {}),
                    ("db-migrate", mig.get("secretEnv") or {})):
    for k, ref in refs.items():
        if not ref.startswith(f"secret://{ws}/{repo}/"):
            bad(f"{label} secretEnv {k} is {ref} — not the product's workspace and project")
# The schema reaches D1 through the migration runner, with the D1 token.
if not (mig.get("secretEnv") or {}).get("CLOUDFLARE_API_TOKEN", "").endswith("/CLOUDFLARE_D1_TOKEN"):
    bad("db-migrate does not bind the D1 token as its CLOUDFLARE_API_TOKEN")
# The namespace applies with the deploy token.
if not (kv.get("secretEnv") or {}).get("CLOUDFLARE_API_TOKEN", "").endswith("/CLOUDFLARE_API_TOKEN"):
    bad("cloudflare-kv does not bind the deploy token as its CLOUDFLARE_API_TOKEN")

# The intent: re-tenanted, no work tree, both gates back, the D1 parameters its own.
intent_text = (tree / "intent.yaml").read_text()
intent = yaml.safe_load(intent_text)
if intent["metadata"]["name"] != repo:
    bad(f"intent metadata.name is {intent['metadata']['name']}")
if intent["execution"]["state"]["workspace"] != ws:
    bad(f"intent workspace is {intent['execution']['state']['workspace']}, not the product's")
if "work" in intent:
    bad("intent.yaml still declares the baseline's work tree")
if "promotion" not in intent["environments"]["prod"] or "@promotion-deferred" in intent_text:
    bad("prod's promotion gate was not restored by 02-docs")
if "github-push-main" not in intent["environments"]["dev"]["activation"]["triggerRefs"] or "@dev-lanes-deferred" in intent_text:
    bad("dev's push activation was not restored by 02-docs")
for env in ("stage", "prod"):
    want = f"https://{repo}-web-{env}.{sub}.workers.dev"
    if intent["environments"][env].get("url") != want:
        bad(f"environments.{env}.url is {intent['environments'][env].get('url')}, not {want}")
    tf = ((intent["environments"][env].get("parameterDefaults") or {}).get("terraform") or {})
    if tf.get("repo") != repo:
        bad(f"environments.{env} terraform repo is {tf.get('repo')}, not {repo}")
for page in (intent.get("repo") or {}).get("docs", {}).get("pages", []):
    if not (tree / page["path"]).exists():
        bad(f"intent repo.docs names {page['path']}, which the product does not have")

# The landings, as the phases made them: one marker per component the
# product's contract names, and the record 02-docs rendered.
for rel in ("infra/terraform/cloudflare-d1/component.yaml",
            "infra/terraform/cloudflare-kv/component.yaml", "packages/db/component.yaml", "infra/db-migrate/component.yaml",
            "apps/web/component.yaml", "tests/web/component.yaml", "tests/db/component.yaml"):
    if not re.search(r"^# orun: redeploy 01-product \S+$", (tree / rel).read_text(), re.M):
        bad(f"{rel} carries no 01-product redeploy marker")
dep = (tree / "ai/context/deployment.md").read_text()
if "GENERATED by the `02-docs` phase" not in dep or f"https://{repo}-web-prod.{sub}.workers.dev" not in dep:
    bad("ai/context/deployment.md was not rendered for the product")
readme = (tree / "README.md").read_text()
if not readme.startswith(f"# {repo}\n") or "This site is **live**" not in readme:
    bad("README.md is not the product's, or its live-deployment section was not rendered")

# Provenance prose, over the BRANDED files.
PROV = re.compile(r"\bfork(ed)? (of|from)\b|\bbaseline (repo|repository|commit|tag)\b|repo-blueprint|BOOTSTRAP\.md", re.I)
for rel in ("README.md", "ai/context/operations.md", "ai/context/deployment.md"):
    for n, line in enumerate((tree / rel).read_text().splitlines(), 1):
        if PROV.search(line):
            bad(f"{rel}:{n} speaks of the factory: {line.strip()[:70]}")

if problems:
    for p in problems:
        print(f"  ✕ {p}", file=sys.stderr)
    sys.exit(1)
print(f"   {len(tracked)} tracked files; branded (page, Worker, D1/KV names, runner, secret refs), "
      f"no factory path named, re-tenanted, gates restored, record rendered")
PY

# ── 4. the product's own CI, over the 01-product merge ─────────────────────
echo "── orun plan in the product, for the push that merged 01-product"
s01="$(git -C "$tree" rev-parse HEAD~1)"; s02="$(git -C "$tree" rev-parse HEAD)"
git -C "$tree" checkout -q "$s01"
(cd "$tree" && orun validate --intent intent.yaml) > "$scratch/validate.log" 2>&1 \
  || { fail "orun validate refused the product's intent at 01-product"; tail -10 "$scratch/validate.log" >&2; }
# The first push to main: every file is new, so the changed set is everything
# and the plan is the full one.
(cd "$tree" && orun plan --intent intent.yaml --trigger github-push-main --output "$scratch/plan.json") \
  > "$scratch/plan.log" 2>&1 || { fail "orun plan failed in the product at 01-product"; tail -15 "$scratch/plan.log" >&2; }
git -C "$tree" checkout -q main
python3 - "$scratch/plan.json" "$values" <<'PY' || fails=$((fails + 1))
import json, sys
plan, values = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
repo, sub, ws = values["reponame"], values["subdomain"], values["orunWorkspace"]
problems = []
def bad(m): problems.append(m)
jobs = {(j["component"], j["environment"]): j for j in plan["jobs"]}
want = {(c, e) for c in ("cloudflare-d1", "cloudflare-kv", "db-migrate", "web") for e in ("stage", "prod")}
if set(jobs) != want:
    bad(f"the 01-product merge plans {sorted(jobs)}; it must apply cloudflare-d1 and cloudflare-kv, "
        f"migrate (db-migrate) and deploy web on stage and prod, and nothing else (dev's push lanes are deferred)")

def refs(j):
    return {r["asEnv"]: r["ref"] for r in j.get("secretRefs") or []}
def ours(ref):
    return ref.startswith(f"secret://{ws}/") and (f"/{repo}/" in ref or f"project:{repo}" in ref)

for env in ("stage", "prod"):
    d1, mig, web = jobs.get(("cloudflare-d1", env)), jobs.get(("db-migrate", env)), jobs.get(("web", env))
    kvj = jobs.get(("cloudflare-kv", env))
    if not d1 or not mig or not web or not kvj:
        continue
    # INFRA BEFORE APP, in three steps: the migrations wait for their
    # environment's D1 apply alone; the Worker's deploy for its two applies
    # and those migrations alone — not the other environment, not stage.
    for label, root_ in (("cloudflare-d1", d1), ("cloudflare-kv", kvj)):
        if not root_["profile"].endswith(".apply"):
            bad(f"{label}@{env} plans profile {root_['profile']}, not an apply")
        if root_.get("dependsOn"):
            bad(f"{label}@{env} waits on {root_['dependsOn']} — during the bootstrap stage and prod apply side by side")
    if not mig["profile"].endswith(".apply"):
        bad(f"db-migrate@{env} plans profile {mig['profile']}, not an apply")
    if (mig.get("dependsOn") or []) != [d1["id"]]:
        bad(f"db-migrate@{env} waits on {mig.get('dependsOn')}; it must wait on {d1['id']} alone (the database before its schema)")
    if not web["profile"].endswith(".deploy"):
        bad(f"web@{env} plans profile {web['profile']}, not a deploy")
    if sorted(web.get("dependsOn") or []) != sorted([d1["id"], kvj["id"], mig["id"]]):
        bad(f"web@{env} waits on {web.get('dependsOn')}; it must wait on {d1['id']}, {kvj['id']} and "
            f"{mig['id']} alone (infra before app)")
    # (The plan names the composition's migrate step by its title, so it is
    # found by what it runs.)
    mruns = [s.get("run") or "" for s in mig["steps"]]
    applies = [r for r in mruns if "dist/runner/cli.js apply" in r]
    if len(applies) != 1 or any("dist/runner/cli.js plan" in r for r in mruns):
        bad(f"db-migrate@{env} runs {[s['id'] for s in mig['steps']]}; a merge applies the migrations, once")
    elif f'--env "{env}"' not in applies[0]:
        bad(f"db-migrate@{env}'s apply is not the runner's apply for {env}: {applies[0].strip()}")
    if not any("--filter=@saas/db" in r for r in mruns):
        bad(f"db-migrate@{env} does not build the package it runs (@saas/db)")
    steps = {s["id"]: s.get("run") or "" for s in web["steps"]}
    for need in ("verify-app-structure", "build-app", "deploy", "smoke"):
        if need not in steps:
            bad(f"web@{env} has no {need} step")
    if "tooling/wire/live.mjs" not in steps.get("build-app", "") \
            or "--components cloudflare-d1,cloudflare-kv" not in steps.get("build-app", ""):
        bad(f"web@{env}'s build does not render the D1 and KV wiring: {steps.get('build-app','').strip()}")
    origin = f'NEXT_PUBLIC_SITE_URL="${{SITE_URL:-https://{repo}-web-${{ORUN_ENVIRONMENT}}.{sub}.workers.dev}}"'
    if origin not in steps.get("build-app", ""):
        bad(f"web@{env}'s build does not set the environment's origin (the Open Graph links are built on it)")
    if f'EFFECTIVE_WORKER_NAME="{repo}-web-{env}"' not in steps.get("deploy", ""):
        bad(f"web@{env} deploys a Worker not named {repo}-web-{env}")
    smoke = steps.get("smoke", "").replace('\\"', '"')
    if "/api/health" not in smoke or '"ok":true' not in smoke:
        bad(f"web@{env}'s smoke does not check the health route the Worker answers from D1")
    # The site holds no key of its own: the browser encrypts. Its job resolves
    # its deploy token, the account id and the two wiring documents — and
    # nothing a bootstrap does not store, optional or not.
    if "worker-secrets" in steps.get("build-app", "") or "wrangler secret" in steps.get("build-app", ""):
        bad(f"web@{env}'s build pushes a Worker secret; the site has none")
    r = refs(web)
    allowed = {"CLOUDFLARE_API_TOKEN", "CLOUDFLARE_ACCOUNT_ID", f"WIRING_CLOUDFLARE_D1_{env.upper()}",
               f"WIRING_CLOUDFLARE_KV_{env.upper()}"}
    extra = sorted(k for k in r if k not in allowed and not k.startswith("WIRING_CLOUDFLARE_"))
    if extra:
        bad(f"web@{env} resolves {extra} — the site needs no secret beyond its deploy token and wiring")
    for key in ("CLOUDFLARE_API_TOKEN", "CLOUDFLARE_ACCOUNT_ID", f"WIRING_CLOUDFLARE_D1_{env.upper()}",
                f"WIRING_CLOUDFLARE_KV_{env.upper()}"):
        if not ours(r.get(key, "")):
            bad(f"web@{env} resolves {key} from {r.get(key) or 'nowhere'} — not the product's workspace and project")
    if r.get("CLOUDFLARE_API_TOKEN", "").endswith("CLOUDFLARE_D1_TOKEN"):
        bad(f"web@{env} deploys with the D1 token; its deploy token is workers-deploy's")
    for label, job in (("cloudflare-d1", d1), ("db-migrate", mig)):
        r = refs(job)
        for key in ("CLOUDFLARE_API_TOKEN", "CLOUDFLARE_ACCOUNT_ID"):
            if not ours(r.get(key, "")):
                bad(f"{label}@{env} resolves {key} from {r.get(key) or 'nowhere'} — not the product's")
        if not r.get("CLOUDFLARE_API_TOKEN", "").endswith("/CLOUDFLARE_D1_TOKEN"):
            bad(f"{label}@{env} binds {r.get('CLOUDFLARE_API_TOKEN')} as its token — it needs the D1 token (d1-edit)")
    for label, job, token in (("cloudflare-kv", kvj, "/CLOUDFLARE_API_TOKEN"),):
        r = refs(job)
        for key in ("CLOUDFLARE_API_TOKEN", "CLOUDFLARE_ACCOUNT_ID"):
            if not ours(r.get(key, "")):
                bad(f"{label}@{env} resolves {key} from {r.get(key) or 'nowhere'} — not the product's")
        if not r.get("CLOUDFLARE_API_TOKEN", "").endswith(token):
            bad(f"{label}@{env} binds {r.get('CLOUDFLARE_API_TOKEN')} as its token — want …{token}")
    wiring = refs(mig).get("WIRING_CLOUDFLARE_D1", "")
    if not ours(wiring) or f"/{env}/" not in wiring:
        bad(f"db-migrate@{env} does not resolve its own environment's WIRING_CLOUDFLARE_D1: {wiring or 'nowhere'}")
# The lanes say the same: each step of an environment's chain runs after the
# one it waits on — in a later lane, or later in the same lane.
level = {l["id"]: l.get("level") for l in plan.get("lanes") or []}
lane_of = {jid: l["id"] for l in plan.get("lanes") or [] for jid in l["jobs"]}
order = {jid: i for l in plan.get("lanes") or [] for i, jid in enumerate(l["jobs"])}
chains = {}
for env in ("stage", "prod"):
    chain = [f"cloudflare-d1.{env}.terraform", f"db-migrate.{env}.migrate", f"web.{env}.verify-deploy"]
    pairs = list(zip(chain, chain[1:])) + [(f"cloudflare-kv.{env}.terraform", f"web.{env}.verify-deploy")]
    if not all(j in lane_of for pair in pairs for j in pair):
        bad(f"{env}: the plan's lanes do not hold {sorted({j for p in pairs for j in p})}: {sorted(lane_of)}")
        continue
    for a, b in pairs:
        la, lb = lane_of[a], lane_of[b]
        if la == lb:
            if order[a] > order[b]:
                bad(f"{env}: {b} runs before {a} in lane {la}")
        elif not (level.get(la) is not None and level.get(lb) is not None and level[la] < level[lb]):
            bad(f"{env}: {a} is in lane {la} (level {level.get(la)}) and {b} in {lb} (level {level.get(lb)}) — want it later")
    chains[env] = " → ".join(f"{j.split('.')[0]} [lane {lane_of[j]}, level {level.get(lane_of[j])}]" for j in chain)
if problems:
    for p in problems:
        print(f"  ✕ {p}", file=sys.stderr)
    sys.exit(1)
for env, line in chains.items():
    print(f"   {env}: {line}")
print("   each job waits on its own environment's chain alone (infra before app), stage and prod side by side;")
print("   Worker, wiring, smoke and tokens (the D1 token for its apply and the runner, the deploy token for the namespace) the product's own")
PY

echo "── …the same edges on a pull request: advisory, nothing waits"
git -C "$tree" worktree add -q "$scratch/pr" "$s01"
echo "// a change" >> "$scratch/pr/apps/web/app/page.tsx"
echo "# a change" >> "$scratch/pr/infra/terraform/cloudflare-d1/terraform/main.tf"
echo "-- a change" >> "$scratch/pr/packages/db/src/migrations/010_secrets/up.sql"
echo "# a change" >> "$scratch/pr/infra/terraform/cloudflare-kv/terraform/main.tf"
git -C "$scratch/pr" -c user.email=t@example.invalid -c user.name=t commit -qam "a pull request"
(cd "$scratch/pr" && orun plan --intent intent.yaml --trigger github-pull-request --changed \
   --base "$s01" --head HEAD --output "$scratch/plan-pr.json") > "$scratch/plan-pr.log" 2>&1 \
  || { fail "orun plan failed for a pull request"; tail -15 "$scratch/plan-pr.log" >&2; }
python3 - "$scratch/plan-pr.json" <<'PY' || fails=$((fails + 1))
import json, sys
plan = json.load(open(sys.argv[1]))
jobs = {(j["component"], j["environment"]): j for j in plan["jobs"]}
problems = []
for env in ("stage", "prod"):
    web, d1, mig = jobs.get(("web", env)), jobs.get(("cloudflare-d1", env)), jobs.get(("db-migrate", env))
    kvj = jobs.get(("cloudflare-kv", env))
    if not web or not d1 or not mig or not kvj:
        problems.append(f"the pull request plans no web, cloudflare-d1, cloudflare-kv or db-migrate job on {env}")
        continue
    for label, root_ in (("cloudflare-kv", kvj),):
        if not root_["profile"].endswith(".plan-only"):
            problems.append(f"{env}: a pull request plans {label} as {root_['profile']} — it must plan only")
    if (not web["profile"].endswith(".verify") or not d1["profile"].endswith(".plan-only")
            or not mig["profile"].endswith(".plan")):
        problems.append(f"{env}: a pull request plans {web['profile']}, {d1['profile']} and {mig['profile']} — "
                        f"it must verify and plan only")
    if any("dist/runner/cli.js apply" in (s.get("run") or "") for s in mig["steps"]):
        problems.append(f"db-migrate@{env} applies migrations on a pull request")
    if not any("dist/runner/cli.js plan" in (s.get("run") or "") for s in mig["steps"]):
        problems.append(f"db-migrate@{env} does not plan the migrations on a pull request")
    for job, waits in ((web, (d1["id"], kvj["id"], mig["id"])), (mig, (d1["id"],))):
        held = sorted(set(job.get("dependsOn") or []) & set(waits))
        if held:
            problems.append(f"{job['id']} waits on {held} on a pull request — the edges must be advisory there")
for p in problems:
    print(f"  ✕ {p}", file=sys.stderr)
sys.exit(1 if problems else 0)
PY
[ "$fails" -eq 0 ] && echo "   web verifies beside the D1 and KV plans and the migrations' offline plan on stage and prod; none waits"
git -C "$tree" worktree remove --force "$scratch/pr"

echo "── …and the 02-docs merge plans nothing"
(cd "$tree" && orun plan --intent intent.yaml --trigger github-push-main --changed \
   --base "$s01" --head "$s02" --output "$scratch/plan-02.json") > "$scratch/plan-02.log" 2>&1 \
  || { fail "orun plan failed for the 02-docs merge"; tail -15 "$scratch/plan-02.log" >&2; }
jobs02="$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))['jobs']))" "$scratch/plan-02.json" 2>/dev/null || echo '?')"
[ "$jobs02" = 0 ] && echo "   0 jobs: restoring the gates and writing the record redeploys nothing" \
  || fail "the 02-docs merge plans $jobs02 job(s); it touches no component and must plan none"

# ── 5. a resume over the finished site ────────────────────────────────────
echo "── --resume over the finished product"
before="$(git -C "$tree" status --porcelain; git -C "$tree" rev-parse HEAD)"
orun new --blueprint "$root/repo-blueprint.yaml" --out "$tree" --resume "${sets[@]}" > "$scratch/resume.log" 2>&1 \
  || { fail "--resume did not run"; tail -10 "$scratch/resume.log" >&2; }
after="$(git -C "$tree" status --porcelain; git -C "$tree" rev-parse HEAD)"
[ "$before" = "$after" ] || { fail "--resume changed the finished product:"; git -C "$tree" status --short | head -10 >&2; }
grep -q "SITE_NAME = \"Sam's Secrets & Keys\"" "$tree/apps/web/lib/site.ts" \
  || fail "--resume reverted the product's identity"
[ "$fails" -eq 0 ] && echo "   nothing placed again, nothing un-branded"

[ "$fails" -eq 0 ] || { echo "placement.test.sh: $fails failure(s)" >&2; exit 1; }
echo "placement.test.sh: ok"
