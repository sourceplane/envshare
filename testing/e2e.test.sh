#!/usr/bin/env bash
# TIER 2 — the product a bootstrap produces builds, migrates, deploys (dry)
# and serves.
#
# placement.test.sh proves the tree a bootstrap ends with is the right tree.
# This proves it WORKS, by doing to it what its own pipelines will:
#
#   1. at the 01-product landing (the commit its one pull request merges),
#      install with the lockfile the product ships, render the wrangler
#      fixture and check the committed config IS that render, typecheck,
#      lint, test, build. The landing's own PR runs `plan` alone (an
#      `orun/BASE-*` branch), so THIS is where a product those steps refuse
#      is caught: before the tag, not after a build has merged it;
#   2. the stage lanes' own steps, rendered by `orun plan` in the product and
#      run IN THE TREE THE RUNNER STAGES for each job (testing/lib/stage-job.py),
#      with the dependency layout the pinned composition produces and with the
#      job's secrets in its environment as the platform resolves them (the
#      component's secretEnv):
#      - web, from a pull request's plan (the verify profile: the deploy
#        profile has no dry run) — `verify-app-structure` (which checks the
#        wrangler config exists BEFORE anything is built), `build-app` (the
#        component's buildCommand: the live wiring render, then the build),
#        `verify-build-output` and `deploy-dry-run` (`wrangler deploy
#        --dry-run --name <reponame>-web-stage`), the database id and the
#        namespace id in the built config asserted to be the stage
#        documents', not the fixture's, and the origin built in;
#      - db-migrate: its install and build, the pull request's `plan` (offline,
#        every checksum verified), then the merge's `apply` — the step a push
#        to main runs — against a stand-in for D1's REST API over real SQLite
#        (testing/lib/d1-api.py), which refuses any account, database or token
#        but the ones the job resolves: the `secrets` and `metrics` tables
#        created and every migration recorded; then the apply again, which
#        applies nothing;
#   3. serve the built Worker with `wrangler dev` (local D1 and KV behind the
#      same bindings): with no schema the site cannot count its documents and
#      the component's OWN `smokeCommand` REFUSES it; after the product's own
#      `db:migrate:local` the smoke passes, verbatim — the check the real
#      deploy ends with. Then the site as a browser uses it, through a
#      recording proxy (testing/lib/recording-proxy.py) that keeps every
#      request the Worker is sent, by a client bundled from the PRODUCT's
#      own encryption and link modules (testing/lib/share-client.ts):
#      the page carries the product's name and links its repository and the
#      template's credit; a document is shared, read to its limit, deleted
#      by its last read and then 404; an unlimited one stays; of concurrent
#      last reads exactly one is served; the HTTP API answers under the
#      product's own header names; a document past its D1 expiry is refused
#      though KV still holds it; a TTL under KV's floor is raised to 60
#      seconds, and when it runs out the documents are gone from KV and
#      answer 404; and no request the Worker was sent, and nothing it stored,
#      holds any document's key.
#
# What it cannot do is the platform's half: create the repository, mint the
# brokered Cloudflare tokens, apply the database, migrate it and deploy for
# real, and probe workers.dev. The D1 and KV roots are verified to
# `terraform validate` and their plans are part of every pull request's lanes;
# the applies need an account.
#
# Needs: orun, node, pnpm, python3 (+PyYAML), git, curl, and the network for
# `pnpm install` (or a warm store). A few minutes: three installs, two builds
# and a TTL of 60 seconds run out.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
# shellcheck source=lib/bootstrap.sh
source "$here/lib/bootstrap.sh"

for bin in orun node pnpm python3 git curl; do
  command -v "$bin" >/dev/null || { echo "e2e.test.sh needs $bin on PATH" >&2; exit 1; }
done

scratch="$(mktemp -d)"
dev_pid=""
api_pid=""
px_pid=""
# wrangler dev runs under pnpm, node and two workerd processes; a TERM to the
# first does not reach the rest, and waiting on it then never returns. So it is
# started as its own process group (setsid) and the whole group is stopped.
stop_group() {
  kill -TERM -- "-$1" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 -- "-$1" 2>/dev/null || break; sleep 0.5; done
  kill -KILL -- "-$1" 2>/dev/null || true
}
cleanup() {
  [ -z "$dev_pid" ] || stop_group "$dev_pid"
  [ -z "$api_pid" ] || stop_group "$api_pid"
  [ -z "$px_pid" ] || stop_group "$px_pid"
  rm -rf "$scratch"
}
trap cleanup EXIT
values="$here/fixtures/acme.json"
repo="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['reponame'])" "$values")"
export CI=1 WRANGLER_SEND_METRICS=false NEXT_TELEMETRY_DISABLED=1 TURBO_TELEMETRY_DISABLED=1

# The landing's own checks, step for step: what a pull request in the product
# verifies through its lanes, run here at once on the whole tree.
LANDING_CHECKS=(
  "pnpm install --frozen-lockfile"
  "pnpm run wire:fixture"
  "git diff --exit-code"
  "pnpm typecheck"
  "pnpm lint"
  "pnpm test"
  "pnpm build"
)
checks() { # DIR LOG
  local dir="$1" log="$2" cmd
  for cmd in "${LANDING_CHECKS[@]}"; do
    echo "   \$ $cmd" | tee -a "$log"
    if ! (cd "$dir" && bash -c "$cmd") >> "$log" 2>&1; then
      echo "FAIL: \`$cmd\` failed in $dir" >&2; tail -40 "$log" >&2; return 1
    fi
  done
}

# A job's steps out of a plan, by component and environment: each step's
# script (named by its id, or by a fixed name for the composition steps this
# file runs), the job's path, its env and the names of its secrets.
extract() { # PLAN COMPONENT ENV OUTDIR
  python3 - "$@" <<'PY'
import json, pathlib, re, sys
plan, comp, env, out = json.load(open(sys.argv[1])), sys.argv[2], sys.argv[3], pathlib.Path(sys.argv[4])
out.mkdir(parents=True, exist_ok=True)
job = next(j for j in plan["jobs"] if j["component"] == comp and j["environment"] == env)
for s in job["steps"]:
    run = s.get("run") or ""
    if not run:
        continue
    sid = s["id"]
    if "dist/runner/cli.js apply" in run:
        sid = "migrate-apply"
    elif "dist/runner/cli.js plan" in run:
        sid = "migrate-plan"
    (out / f"{re.sub(r'[^A-Za-z0-9_-]', '_', sid)}.sh").write_text(run)
    if s["id"] in ("install-workspace-dependencies", "install-dependencies"):
        (out / "install.sh").write_text(run)
        (out / "install.wd").write_text(s.get("working-directory") or ".")
        (out / "install.scope").write_text(s.get("scope") or "job")
(out / "path").write_text(job.get("path") or ".")
(out / "env").write_text("".join(f"export {k}={json.dumps(v)}\n" for k, v in (job.get("env") or {}).items()))
(out / "secrets").write_text("\n".join(r["asEnv"] for r in job.get("secretRefs") or []))
PY
}

# A job's private tree, staged as orun stages it. The source checkout carries
# no build output (nothing was built in it), and its dependencies are what the
# pinned composition says: a lane-scoped install ran once in the source tree
# and is linked in, or the job installs its own.
stage_job() { # STEPS-DIR WORK-DIR LOG
  local steps="$1" work="$2" log="$3"
  [ -f "$steps/install.sh" ] || { echo "FAIL: the lane has no install step" >&2; return 1; }
  if [ "$(cat "$steps/install.scope")" = lane ]; then
    (cd "$tree" && bash -e "$steps/install.sh") > "$log" 2>&1 \
      || { echo "FAIL: the lane's install step" >&2; tail -30 "$log" >&2; return 1; }
    python3 "$here/lib/stage-job.py" "$tree" "$work" --shared-deps
    [ -L "$work/node_modules" ] || { echo "FAIL: the staged tree's node_modules is not the lane's symlink" >&2; return 1; }
    echo "   staged: $(realpath --relative-to="$tree" "$work"); install scope: lane — node_modules → the source tree's"
  else
    python3 "$here/lib/stage-job.py" "$tree" "$work"
    echo "   staged: $(realpath --relative-to="$tree" "$work"); install scope: job — installing inside it"
    (cd "$work/$(cat "$steps/path")/$(cat "$steps/install.wd")" && bash -e "$steps/install.sh") > "$log" 2>&1 \
      || { echo "FAIL: the lane's install step" >&2; tail -30 "$log" >&2; return 1; }
    [ -d "$work/node_modules" ] && [ ! -L "$work/node_modules" ] \
      || { echo "FAIL: the job's install did not land inside its own tree" >&2; return 1; }
  fi
}

# One step, in the runner's per-job environment: the job's env (intent
# environment `env:`), its resolved secrets (exported by the caller) and
# ORUN_ENVIRONMENT; the step runs in the component's directory.
run_step() { # STEPS-DIR WORK-DIR STEP LOG
  local steps="$1" work="$2" step="$3" log="$4"
  [ -f "$steps/$step.sh" ] || { echo "FAIL: the stage lane has no $step step" >&2; return 1; }
  echo "   ▸ $step"
  if ! (cd "$work/$(cat "$steps/path")" && source "$steps/env" && export ORUN_ENVIRONMENT=stage \
        && bash -e "$steps/$step.sh") > "$log" 2>&1; then
    echo "FAIL: the lane's $step step" >&2; tail -40 "$log" >&2; return 1
  fi
}

echo "── the offline bootstrap (testing/lib/bootstrap.sh)"
tree="$scratch/$repo"
bootstrap_offline "$root" "$tree" "$values" "$scratch/logs" > "$scratch/bootstrap.log" 2>&1 || {
  echo "FAIL: the offline bootstrap stopped" >&2; tail -40 "$scratch/bootstrap.log" >&2; exit 1; }
echo "   2 phases placed and landed"
s01="$(git -C "$tree" rev-parse HEAD~1)"

# ── 1. the product's one pull request ──────────────────────────────────────
echo "── 01-product's landing: install, the fixture render, typecheck, lint, test, build"
git -C "$tree" worktree add -q "$scratch/at-01" "$s01"
checks "$scratch/at-01" "$scratch/checks-01.log"
# The landing's build is done; its tree is not needed again, and the disk is shared.
git -C "$tree" worktree remove --force "$scratch/at-01"

# ── 2. the stage lanes' steps, in each job's own tree ─────────────────────
# A pull request that changes the site and the migration component: the lanes
# `orun plan` gives it. And the merge's plan, for the step only a merge runs.
git -C "$tree" checkout -q -b e2e-pr
echo "// a change to the site's component" >> "$tree/apps/web/app/page.tsx"
echo "# a change to the migration component" >> "$tree/infra/db-migrate/component.yaml"
git -C "$tree" -c user.email=e2e@example.invalid -c user.name=e2e commit -qam "a pull request"
(cd "$tree" && orun plan --intent intent.yaml --trigger github-pull-request --changed \
   --base main --head HEAD --env stage --output "$scratch/plan.json") > "$scratch/plan.log" 2>&1 \
  || { echo "FAIL: orun plan (pull request)" >&2; tail -15 "$scratch/plan.log" >&2; exit 1; }
(cd "$tree" && orun plan --intent intent.yaml --trigger github-push-main --env stage \
   --output "$scratch/plan-main.json") > "$scratch/plan-main.log" 2>&1 \
  || { echo "FAIL: orun plan (push to main)" >&2; tail -15 "$scratch/plan-main.log" >&2; exit 1; }
extract "$scratch/plan.json" web stage "$scratch/web"
extract "$scratch/plan.json" db-migrate stage "$scratch/mig"
extract "$scratch/plan-main.json" db-migrate stage "$scratch/mig-main"

# What the platform resolves into the jobs before their first step: the
# wiring documents the D1 and KV roots lease-published (the components'
# secretEnv), with a database id and a namespace id no fixture carries, so
# the built config and the migrated database prove which documents they came
# from.
d1_id="5ca1ab1e-0000-4000-8000-00000000a001"
kv_id="5ca1ab1e00004000800000000000a001"
export WIRING_CLOUDFLARE_D1_STAGE='{"d1_database_id":"'"$d1_id"'","d1_database_name":"stg-'"$repo"'-stage"}'
export WIRING_CLOUDFLARE_D1_PROD='{"d1_database_id":"5ca1ab1e-0000-4000-8000-00000000a003","d1_database_name":"prod-'"$repo"'-prod"}'
export WIRING_CLOUDFLARE_KV_STAGE='{"app_kv_id":"'"$kv_id"'","app_kv_title":"'"$repo"'-app-kv-stage"}'
export WIRING_CLOUDFLARE_KV_PROD='{"app_kv_id":"5ca1ab1e00004000800000000000a003","app_kv_title":"'"$repo"'-app-kv-prod"}'
# The origin this environment's build is for (intent.yaml's SITE_URL — here
# the wrangler dev it is served from in step 3): its metadata and Open Graph
# links are built on it.
port=$(python3 -c "import socket;s=socket.socket();s.bind(('127.0.0.1',0));print(s.getsockname()[1]);s.close()")
url="http://127.0.0.1:$port"
export SITE_URL="$url"

echo "── the stage web lane: verify-app-structure, build-app, verify-build-output, deploy-dry-run"
for key in WIRING_CLOUDFLARE_D1_STAGE WIRING_CLOUDFLARE_D1_PROD WIRING_CLOUDFLARE_KV_STAGE WIRING_CLOUDFLARE_KV_PROD; do
  grep -qx "$key" "$scratch/web/secrets" || { echo "FAIL: the stage web lane does not resolve $key" >&2; exit 1; }
done
work="$tree/.orun/runs/e2e/web.stage.verify-deploy/work"
stage_job "$scratch/web" "$work" "$scratch/install-web.log"
[ ! -e "$work/apps/web/.open-next" ] || { echo "FAIL: the staged tree carries build output" >&2; exit 1; }
for step in verify-app-structure build-app verify-build-output deploy-dry-run; do
  run_step "$scratch/web" "$work" "$step" "$scratch/$step.log"
done
for want in "\"$d1_id\"" "\"$kv_id\""; do
  grep -q "$want" "$work/apps/web/wrangler.jsonc" \
    || { echo "FAIL: the lane's build did not render $want from its wiring document" >&2; exit 1; }
done
# wrangler's dry run names a D1 binding's database by name, not id.
grep -Eq "env\.DB \(stg-$repo-stage\) +D1 Database" "$scratch/deploy-dry-run.log" \
  || { echo "FAIL: the dry run does not bind DB to the stage database" >&2; tail -20 "$scratch/deploy-dry-run.log" >&2; exit 1; }
grep -Eq "env\.SECRETS \($kv_id\) +KV Namespace" "$scratch/deploy-dry-run.log" \
  || { echo "FAIL: the dry run does not bind SECRETS to the stage namespace" >&2; tail -20 "$scratch/deploy-dry-run.log" >&2; exit 1; }
# The environment's origin, built into the Worker: its metadata's links.
grep -rqF "$url" "$work/apps/web/.open-next/server-functions" \
  || { echo "FAIL: the lane's build did not build the environment's origin ($url) into the Worker" >&2; exit 1; }
echo "   the built config binds DB and SECRETS to the stage documents' database ($d1_id) and namespace"
echo "   ($kv_id), built for its origin; the dry run accepts it"

echo "── the stage db-migrate lane: install, build, the PR's plan, the merge's apply (a stand-in D1 API)"
for key in CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID WIRING_CLOUDFLARE_D1; do
  grep -qx "$key" "$scratch/mig-main/secrets" || { echo "FAIL: the stage db-migrate lane does not resolve $key" >&2; exit 1; }
done
[ -f "$scratch/mig/migrate-plan.sh" ] && [ ! -f "$scratch/mig/migrate-apply.sh" ] \
  || { echo "FAIL: a pull request's db-migrate lane must plan and not apply" >&2; ls "$scratch/mig" >&2; exit 1; }
[ -f "$scratch/mig-main/migrate-apply.sh" ] && [ ! -f "$scratch/mig-main/migrate-plan.sh" ] \
  || { echo "FAIL: the merge's db-migrate lane must apply" >&2; ls "$scratch/mig-main" >&2; exit 1; }
mwork="$tree/.orun/runs/e2e/db-migrate.stage.migrate/work"
stage_job "$scratch/mig" "$mwork" "$scratch/install-mig.log"
run_step "$scratch/mig" "$mwork" build-db-package "$scratch/mig-build.log"
run_step "$scratch/mig" "$mwork" migrate-plan "$scratch/mig-plan.log"
for id in 010_secrets; do
  grep -q "\"$id\"" "$scratch/mig-plan.log" \
    || { echo "FAIL: the plan does not list $id as pending" >&2; cat "$scratch/mig-plan.log" >&2; exit 1; }
done
# The stand-in D1 API: only this account, this database (the stage
# document's id) and this token are answered.
(exec setsid python3 "$here/lib/d1-api.py" "$scratch/d1.sqlite" "$scratch/d1.port" \
   --account e2e-account --database "$d1_id" --token e2e-d1-token) > "$scratch/d1-api.log" 2>&1 < /dev/null &
api_pid=$!
for _ in $(seq 1 50); do [ -s "$scratch/d1.port" ] && break; sleep 0.1; done
[ -s "$scratch/d1.port" ] || { echo "FAIL: the stand-in D1 API did not start" >&2; cat "$scratch/d1-api.log" >&2; exit 1; }
export CLOUDFLARE_API_BASE_URL="http://127.0.0.1:$(cat "$scratch/d1.port")/client/v4"
# The job's own secrets: the D1 token as CLOUDFLARE_API_TOKEN, the account id,
# and this environment's wiring document.
for pass in first again; do
  (export CLOUDFLARE_API_TOKEN=e2e-d1-token CLOUDFLARE_ACCOUNT_ID=e2e-account \
          WIRING_CLOUDFLARE_D1="$WIRING_CLOUDFLARE_D1_STAGE" \
   && run_step "$scratch/mig-main" "$mwork" migrate-apply "$scratch/mig-apply-$pass.log") || exit 1
done
python3 - "$scratch/d1.sqlite" "$scratch/mig-apply-first.log" "$scratch/mig-apply-again.log" <<'PY'
import json, re, sqlite3, sys
db = sqlite3.connect(sys.argv[1])
def result(path):
    text = open(path).read()
    return json.loads(text[text.index("{"):text.rindex("}") + 1])
first, again = result(sys.argv[2]), result(sys.argv[3])
problems = []
ALL = ["000_control_baseline", "010_secrets"]
if first["applied"] != ALL:
    problems.append(f"the first apply applied {first['applied']}")
if again["applied"] or again["skipped"] != ALL:
    problems.append(f"the second apply applied {again['applied']} and skipped {again['skipped']} — it must apply nothing")
tables = {r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
if not {"secrets", "metrics"} <= tables:
    problems.append(f"the database holds the tables {sorted(tables)}")
if db.execute("SELECT count(*) FROM secrets").fetchone()[0] != 0:
    problems.append("a fresh database holds documents")
counters = dict(db.execute("SELECT name, value FROM metrics").fetchall())
if counters != {"reads": 0, "writes": 0}:
    problems.append(f"a fresh database's counters are {counters}")
ledger = [r[0] for r in db.execute("SELECT id FROM _migrations_applied ORDER BY id")]
if ledger != ALL:
    problems.append(f"the ledger records {ledger}")
for p in problems:
    print(f"  ✕ {p}", file=sys.stderr)
sys.exit(1 if problems else 0)
PY
grep -q 'POST /client/v4/accounts/e2e-account/d1/database/'"$d1_id"'/query' "$scratch/d1-api.log" \
  || { echo "FAIL: the runner did not call the stage database's query endpoint" >&2; exit 1; }
echo "   the stage document's database: the secrets and metrics tables, the counters at zero, every"
echo "   migration recorded; the second apply applied nothing"
stop_group "$api_pid"; api_pid=""
unset CLOUDFLARE_API_BASE_URL


# ── 3. serve it, and smoke it as the deploy does ───────────────────────────
# On the port the build was given as its origin (step 2).
start_dev() { # LOG
  (cd "$work/apps/web" && exec setsid pnpm exec wrangler dev --config wrangler.jsonc --ip 127.0.0.1 --port "$port" \
     --name "$repo-web-stage" --show-interactive-dev-session=false) > "$scratch/$1.log" 2>&1 < /dev/null &
  dev_pid=$!
  for _ in $(seq 1 90); do
    curl -s -o /dev/null "$url/fonts/Inter-OFL.txt" && break
    kill -0 "$dev_pid" 2>/dev/null || { echo "FAIL: wrangler dev exited" >&2; tail -30 "$scratch/$1.log" >&2; exit 1; }
    sleep 1
  done
  curl -s -o /dev/null "$url/fonts/Inter-OFL.txt" || { echo "FAIL: wrangler dev never answered" >&2; tail -30 "$scratch/$1.log" >&2; exit 1; }
}
echo "── wrangler dev over the built Worker (local D1 and KV behind DB and SECRETS)"
start_dev dev
smoke="$(python3 -c "import yaml,sys;print(yaml.safe_load(open(sys.argv[1]))['spec']['parameters']['smokeCommand'])" "$tree/apps/web/component.yaml")"

echo "   ▸ no schema yet: no secrets table — the health route fails, and the deploy's smoke refuses it"
code="$(curl -s -o /dev/null -w '%{http_code}' "$url/api/health")"
[ "$code" = 500 ] || { echo "FAIL: /api/health answered $code without the secrets table, not 500" >&2; exit 1; }
if DEPLOYED_URL="$url" bash -c "$smoke"; then
  echo "FAIL: the deploy's smoke passed a site that could not read its database" >&2; exit 1
fi

echo "   ▸ the product's own db:migrate:local, then the component's own smokeCommand, DEPLOYED_URL=$url"
(cd "$work/apps/web" && pnpm run db:migrate:local) > "$scratch/migrate-local.log" 2>&1 \
  || { echo "FAIL: db:migrate:local" >&2; tail -20 "$scratch/migrate-local.log" >&2; exit 1; }
DEPLOYED_URL="$url" bash -c "$smoke" || { echo "FAIL: the deploy's smoke refused the migrated site" >&2; exit 1; }

# The browser's side: the product's own encryption and link modules, bundled
# with the esbuild the site's own toolchain carries (wrangler's).
client="$scratch/share-client.mjs"
(cd "$work/apps/web" && node --input-type=module - "$here/lib/share-client.ts" "$work/apps/web" "$client") <<'JS' \
  > "$scratch/client-build.log" 2>&1 || { echo "FAIL: bundling the share client" >&2; cat "$scratch/client-build.log" >&2; exit 1; }
import { createRequire } from "node:module";
const [entry, web, outfile] = process.argv.slice(2);
const fromWeb = createRequire(`${web}/package.json`);
const esbuild = createRequire(fromWeb.resolve("wrangler/package.json"))("esbuild");
await esbuild.build({ entryPoints: [entry], outfile, bundle: true, platform: "node", format: "esm",
                      target: "node22", alias: { WEB: web }, nodePaths: [`${web}/node_modules`], logLevel: "warning" });
JS

# Every request the client sends goes through the recording proxy.
(exec setsid python3 "$here/lib/recording-proxy.py" "$url" "$scratch/px.port" "$scratch/requests.jsonl") \
  > "$scratch/proxy.log" 2>&1 < /dev/null &
px_pid=$!
for _ in $(seq 1 50); do [ -s "$scratch/px.port" ] && break; sleep 0.1; done
[ -s "$scratch/px.port" ] || { echo "FAIL: the recording proxy did not start" >&2; cat "$scratch/proxy.log" >&2; exit 1; }
front="http://127.0.0.1:$(cat "$scratch/px.port")"

echo "   ▸ the site as a browser uses it, through a recording proxy ($front → $url)"
python3 - "$front" "$values" "$client" "$work/apps/web" "$scratch/requests.jsonl" "$scratch/dev.log" <<'PY' \
  || { echo "FAIL: the site, served" >&2; tail -20 "$scratch/dev.log" >&2; exit 1; }
import base64, calendar, html, json, os, re, subprocess, sys, threading, time, urllib.error, urllib.parse, urllib.request
base, values, client, web, reqlog, devlog = sys.argv[1], json.load(open(sys.argv[2])), *sys.argv[3:]
name, repo, org = values["productname"], values["reponame"], values["githuborg"]
problems = []
def bad(m): problems.append(m)
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k): return None
plain = urllib.request.build_opener(NoRedirect())
def get(path, data=None, headers=None):
    req = urllib.request.Request(base + path, data=data, headers=headers or {})
    try:
        with plain.open(req, timeout=60) as r:
            return r.status, r.headers, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.headers, e.read()
def text(fragment): return html.unescape(re.sub(r"<[^>]+>", " ", fragment))
def run(*args):
    r = subprocess.run(["node", client, *args], capture_output=True, text=True)
    lines = r.stdout.strip().splitlines()
    if r.returncode != 0 or not lines:
        bad(f"share-client {args[0]} failed: {r.stderr.strip()[-300:]}")
        return {}
    return json.loads(lines[-1])
KEYS = []
stores = 0
def share(plaintext, ttl, reads):
    global stores
    doc = run("share", base, plaintext, str(ttl), str(reads))
    if doc.get("status") != 200 or not re.fullmatch(r"[1-9A-HJ-NP-Za-km-z]+", doc.get("id", "")):
        bad(f"sharing {plaintext!r} answered {doc}")
        return None
    if not doc["link"].startswith(base + "/unseal#"):
        bad(f"the link is {doc['link']}")
    KEYS.append(doc)
    stores += 1
    return doc
def unseal(doc): return run("unseal", doc["link"])
def wrangler(*args):
    r = subprocess.run(["pnpm", "exec", "wrangler", *args, "--local", "--config", "wrangler.jsonc"],
                       cwd=web, capture_output=True, text=True)
    return r.returncode, r.stdout, r.stderr
def d1(sql):
    code, out, err = wrangler("d1", "execute", "DB", "--command", sql, "--json")
    if code != 0:
        bad(f"wrangler d1 execute {sql!r}: {err.strip()[-300:]}")
        return []
    return json.loads(out[out.index("["):])[0]["results"]
def kv_has(key):
    code, out, err = wrangler("kv", "key", "get", key, "--binding", "SECRETS")
    return code == 0 and "Value not found" not in out + err and out.strip() != ""
def row(doc_id): return d1(f"SELECT remaining_reads, expires_at FROM secrets WHERE id = '{doc_id}'")
H_TTL, H_READS = f"{repo}-ttl", f"{repo}-reads"

health = json.loads(get("/api/health")[2])
if health != {"ok": True, "documents": 0}:
    bad(f"a fresh site's health is {health}")

# THE TTL CLOCK STARTS FIRST, so its minute runs while the rest is checked:
# a TTL under KV's floor through the API, raised to 60 seconds and said so,
# and the share page's shortest TTL, one minute.
t0 = time.time()
s, _, b = get("/api/v1/secret", data=b"already-encrypted-and-short-lived", headers={H_TTL: "5", H_READS: "3"})
api_short = json.loads(b).get("data", {}) if s == 200 else {}
stores += s == 200
if s != 200 or api_short.get("ttl") != 60 or api_short.get("reads") != 3:
    bad(f"a 5-second TTL through the API answered {s} {b[:200]!r}, not ttl 60 (KV's floor)")
else:
    left = calendar.timegm(time.strptime(api_short["expiresAt"][:19], "%Y-%m-%dT%H:%M:%S")) - t0
    if not 50 <= left <= 70:
        bad(f"the API's expiresAt {api_short['expiresAt']} is {left:.0f}s away, not about 60")
short = share("SHORT_LIVED=1", 60, 999)
if short and not kv_has(f"secret:{short['id']}"):
    bad("the one-minute document is not in KV")

# THE SITE, BRANDED: the product's name and repository, and the template's credit.
s, _, b = get("/")
home = b.decode(errors="replace")
if s != 200:
    bad(f"/ answered {s}")
title = re.search(r"<title>(.*?)</title>", home, re.S)
if not title or text(title.group(1)).strip() != name:
    bad(f"the page's <title> is {title and title.group(1)!r}, not {name!r}")
links = sorted(set(re.findall(r'href="(https://github\.com/[^"]*)"', home)))
want = sorted({f"https://github.com/{org}/{repo}", "https://github.com/chronark/envshare",
               "https://github.com/chronark/envshare/graphs/contributors"})
if links != want:
    bad(f"the page's GitHub links are {links}, not {want}")
if name not in text(home):
    bad("the page does not carry the product's name")
if "envshare" in home.replace(repo, "").replace("chronark/envshare", ""):
    bad("the page still carries the baseline's slug")
for path, code, ctype in (("/share", 200, "text/html"), ("/unseal", 200, "text/html"), ("/deploy", 200, "text/html"),
                          ("/no/such/page", 404, "text/html"), ("/fonts/Inter-SemiBold.ttf", 200, "font/ttf"),
                          ("/api/v1/og?title=Hello&subtitle=There", 200, "image/png")):
    s, h, _ = get(path)
    if s != code or not (h.get("content-type") or "").startswith(ctype):
        bad(f"{path} answered {s} {h.get('content-type')}, want {code} {ctype}")
if f"Deploy {name} for Free" not in " ".join(text(get("/deploy")[2].decode()).split()):
    bad("the deploy page does not name the product")
# An old link (/<compositeKey>) goes to the unseal page, the key kept in the fragment.
s, h, _ = get("/2Pr9VQq2CXRpFsEhnD4tTZ7nFL6aqLd6JJQkQ")
if s not in (302, 303, 307, 308) or h.get("location") != "/unseal#2Pr9VQq2CXRpFsEhnD4tTZ7nFL6aqLd6JJQkQ":
    bad(f"an old link answered {s} → {h.get('location')}")

# CREATE → READ → EXHAUSTED → 404, as the share and unseal pages do it.
plaintext = "API_KEY=sk_e2e_not_a_secret\nDATABASE_URL=postgres://e2e@localhost/e2e"
doc = share(plaintext, 3600, 2)
if doc:
    stored = row(doc["id"])
    if len(stored) != 1 or stored[0]["remaining_reads"] != 2 or not 3500e3 < stored[0]["expires_at"] - t0 * 1000 < 3700e3:
        bad(f"the stored row is {stored}, not two reads and an hour")
    first, second, third = unseal(doc), unseal(doc), unseal(doc)
    if first != {"status": 200, "text": plaintext, "remainingReads": 1}:
        bad(f"the first read answered {first}")
    if second != {"status": 200, "text": plaintext, "remainingReads": 0}:
        bad(f"the last read answered {second}")
    if third.get("status") != 404:
        bad(f"a read after the last answered {third}")
    if row(doc["id"]) or kv_has(f"secret:{doc['id']}"):
        bad("the last read left the document's row or its ciphertext behind")
# Unlimited reads, no TTL.
forever = share("FOREVER=1", 0, 0)
if forever:
    reads = [unseal(forever) for _ in range(3)]
    if any(r != {"status": 200, "text": "FOREVER=1", "remainingReads": None} for r in reads):
        bad(f"an unlimited document read {reads}")
    if row(forever["id"]) != [{"remaining_reads": None, "expires_at": None}]:
        bad(f"an unlimited document's row is {row(forever['id'])}")
# (The malformed store is marked, so the check below of what the share page
# sends leaves it out.)
for path, data, code in (("/api/v1/load", None, 400), ("/api/v1/load?id=NoSuchDocument1", None, 404),
                         ("/api/v1/store", b'{"ttl":60,"reads":1}', 400)):
    s, _, b = get(path, data=data, headers={"x-e2e": "malformed"})
    if s != code:
        bad(f"{path} answered {s} {b[:120]!r}, want {code}")

# CONCURRENT LAST READS: released together, exactly one is served.
def race(doc, n=8):
    gate, answers = threading.Barrier(n), []
    def one():
        gate.wait()
        s, _, b = get(f"/api/v1/load?id={doc['id']}")
        answers.append((s, b))
    threads = [threading.Thread(target=one) for _ in range(n)]
    for t in threads: t.start()
    for t in threads: t.join()
    return answers
for limit in (1, 1, 1, 2):
    doc = share(f"RACE_{limit}=1", 3600, limit)
    if not doc:
        continue
    if limit == 2 and unseal(doc).get("remainingReads") != 1:
        bad("the first of two reads did not leave one")
    answers = race(doc)
    served = [json.loads(b) for s, b in answers if s == 200]
    refused = [s for s, _ in answers if s != 200]
    if len(served) != 1 or set(refused) != {404}:
        bad(f"{len(answers)} concurrent last reads: {len(served)} served, the rest {sorted(refused)}")
    elif served[0].get("encrypted") != doc["encrypted"] or served[0].get("remainingReads") != 0:
        bad(f"the one served last read answered {served[0]}")

# THE HTTP API, under the product's header names.
s, _, b = get("/api/v1/secret", data=b"already-encrypted-api-secret", headers={H_TTL: "3600", H_READS: "2"})
api = json.loads(b).get("data", {}) if s == 200 else {}
stores += s == 200
if s != 200 or api.get("ttl") != 3600 or api.get("reads") != 2 or not api.get("url", "").endswith(f"/api/v1/secret/{api.get('id')}"):
    bad(f"the API's store answered {s} {b[:200]!r}")
else:
    path = urllib.parse.urlparse(api["url"]).path
    answers = [get(path) for _ in range(3)]
    want = [(200, {"data": {"secret": "already-encrypted-api-secret", "remainingReads": 1}}),
            (200, {"data": {"secret": "already-encrypted-api-secret", "remainingReads": 0}})]
    got = [(s, json.loads(b)) for s, _, b in answers[:2]]
    if got != want or answers[2][0] != 404:
        bad(f"the API's reads answered {got} then {answers[2][0]}")
if repo != "envshare":
    s, _, b = get("/api/v1/secret", data=b"x", headers={"envshare-reads": "1"})
    stores += s == 200
    if s != 200 or "reads" in json.loads(b).get("data", {}):
        bad(f"the template's own header name still sets the reads: {s} {b[:160]!r}")
for headers, data in (({H_TTL: "99999999"}, b"x"), ({H_READS: "0"}, b"x"), ({}, b"")):
    s, _, b = get("/api/v1/secret", data=data, headers=headers)
    if s != 400:
        bad(f"the API stored {headers} {data!r}: {s} {b[:120]!r}")

# THE CLOCK IS D1'S: a document past its D1 expiry is refused though KV still holds it.
stale = share("STALE=1", 3600, 5)
if stale:
    d1(f"UPDATE secrets SET expires_at = 1 WHERE id = '{stale['id']}'")
    if not kv_has(f"secret:{stale['id']}"):
        bad("the stale document's ciphertext is not in KV")
    if unseal(stale).get("status") != 404:
        bad("a document past its expiry in D1 was served")
    if row(stale["id"]) or kv_has(f"secret:{stale['id']}"):
        bad("a document refused for its expiry left its row or its ciphertext behind")

# THE TTL RUNS OUT: KV drops the ciphertext, and both documents answer 404.
time.sleep(max(0, t0 + 63 - time.time()))
for doc_id in (short and short["id"], api_short.get("id")):
    if doc_id and kv_has(f"secret:{doc_id}"):
        bad(f"KV still holds {doc_id} after its TTL")
if short and unseal(short).get("status") != 404:
    bad("a document past its one-minute TTL was served")
if api_short.get("id") and get(f"/api/v1/secret/{api_short['id']}")[0] != 404:
    bad("an API secret past its TTL was served")
if short and row(short["id"]):
    bad("an expired document's row outlived its read")

writes = d1("SELECT value FROM metrics WHERE name = 'writes'")
if writes != [{"value": stores}]:
    bad(f"the write counter is {writes}, after {stores} stores")

# NO REQUEST CARRIED A KEY, AND NOTHING STORED HOLDS ONE.
forms = {f for d in KEYS for f in (d["compositeKey"], *d["key"].values())}
raw = [base64.b64decode(d["key"]["b64"]) for d in KEYS]
requests = [json.loads(l) for l in open(reqlog)]
for r in requests:
    body = base64.b64decode(r["body"])
    seen = urllib.parse.unquote(r["path"]) + json.dumps(r["headers"]) + body.decode("latin-1")
    if any(f in seen for f in forms) or any(k in body for k in raw):
        bad(f"a request carried a document's key: {r['method']} {r['path']}")
    marked = any(k.lower() == "x-e2e" for k in r["headers"])
    if r["method"] == "POST" and r["path"] == "/api/v1/store" and not marked:
        sent = json.loads(body)
        if set(sent) != {"ttl", "reads", "encrypted", "iv"}:
            bad(f"the share page's store sent {sorted(sent)}")
if len([r for r in requests if r["path"] == "/api/v1/store"]) < len(KEYS):
    bad("the proxy did not see every share")
state = os.path.join(web, ".wrangler", "state")
for dirpath, _, files in os.walk(state):
    for fname in files:
        data = open(os.path.join(dirpath, fname), "rb").read()
        if any(k in data for k in raw) or any(form.encode() in data for form in forms):
            bad(f"the Worker's local storage holds a document's key ({os.path.relpath(os.path.join(dirpath, fname), state)})")
log = open(devlog, errors="replace").read()
if any(f in log for f in forms):
    bad("the Worker's log carries a document's key")

for p in problems:
    print(f"  ✕ {p}", file=sys.stderr)
print(f"   {len(KEYS)} documents shared and {len(requests)} requests recorded")
sys.exit(1 if problems else 0)
PY
echo "   the product's name, repository and the template's credit; a share read to its limit, deleted by its"
echo "   last read, then 404; unlimited reads; one of 8 concurrent last reads served, 4 times; the API under"
echo "   the product's headers; the D1 clock; a TTL raised to KV's 60 s and run out; no key sent or stored"
stop_group "$px_pid"; px_pid=""
stop_group "$dev_pid"; dev_pid=""

echo "e2e.test.sh: ok"
