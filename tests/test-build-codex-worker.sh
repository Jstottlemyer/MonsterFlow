#!/bin/bash
# Bash 3.2 compatible.
BASH=/bin/bash
##############################################################################
# tests/test-build-codex-worker.sh
#
# Functional tests for scripts/build-codex-worker.sh and
# scripts/build-codex-review.sh (/build Codex workers + Phase 3 review),
# plus anchors in commands/build.md. A PATH-stub fake `codex` records its
# arguments and stdin; the real Codex CLI is never invoked.
##############################################################################
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
WORKER="$REPO_ROOT/scripts/build-codex-worker.sh"
REVIEW="$REPO_ROOT/scripts/build-codex-review.sh"
BUILD_MD="$REPO_ROOT/commands/build.md"

TMP="$(mktemp -d -t mf-codex-worker-test.XXXXXX)"
if [ -z "$TMP" ] || [ ! -d "$TMP" ]; then echo "FAIL: mktemp -d returned invalid path" >&2; exit 1; fi
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ok   $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL $1" >&2; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# Run a command with a hard 20 s deadline (macOS has no `timeout`). A worker
# or review that leaves stdin open would block here and fail the case.
with_deadline() { perl -e 'alarm shift; exec @ARGV' 20 "$@"; }

# --- fake codex --------------------------------------------------------------
STUB="$TMP/bin"
mkdir -p "$STUB"
cat > "$STUB/codex" <<'FAKE'
#!/bin/bash
# FAKE_DIR: where to record; FAKE_LOGIN: exit code for `login status`;
# FAKE_EXIT: exit code for `exec`; FAKE_REPORT: report text ("" = none).
if [ "${1:-}" = "login" ]; then exit "${FAKE_LOGIN:-0}"; fi
printf '%s\n' "$@" > "$FAKE_DIR/args"
# Capped read: an open endless stdin fills 64 KB and the case fails, not hangs.
head -c 65536 > "$FAKE_DIR/stdin"
out=""
while [ $# -gt 0 ]; do
  if [ "$1" = "-o" ]; then out="$2"; shift 2; continue; fi
  shift
done
echo '{"type":"thread.started"}'
if [ -n "$out" ] && [ -n "${FAKE_REPORT-DONE fake report}" ]; then
  printf '%s\n' "${FAKE_REPORT-DONE fake report}" > "$out"
fi
exit "${FAKE_EXIT:-0}"
FAKE
chmod +x "$STUB/codex"

reset_case() {
  CASE="$TMP/case-$1"
  rm -rf "$CASE"
  mkdir -p "$CASE/tasks" "$CASE/repo" "$CASE/record"
  git -C "$CASE/repo" init -q
  printf 'TASK CONTRACT %s\n' "$1" > "$CASE/tasks/T1.prompt.md"
  export FAKE_DIR="$CASE/record"
  unset FAKE_LOGIN FAKE_EXIT FAKE_REPORT MONSTERFLOW_CODEX_WORKER_MODEL
  export MONSTERFLOW_CONFIG="$CASE/config.json"   # absent unless a case writes it
  export MONSTERFLOW_CODEX_BIN="$STUB/codex"
}
arg_present() { grep -qx -- "$1" "$FAKE_DIR/args"; }

echo "build-codex-worker.sh"

reset_case missing
MONSTERFLOW_CODEX_BIN="$TMP/no-such-codex" with_deadline bash "$WORKER" "$CASE/tasks" T1 2>/dev/null
check "exit 3 when codex is not installed" '[ $? -eq 3 ]'

reset_case unauth
FAKE_LOGIN=1 with_deadline bash "$WORKER" "$CASE/tasks" T1 2>/dev/null
check "exit 3 when codex is not authenticated" '[ $? -eq 3 ]'

reset_case nocontract
with_deadline bash "$WORKER" "$CASE/tasks" T9 2>/dev/null
check "exit 2 when the task contract is missing" '[ $? -eq 2 ]'

reset_case happy
out="$(cd "$CASE/repo" && with_deadline bash "$WORKER" "$CASE/tasks" T1 2>&1 < <(yes))"; rc=$?
check "happy path exits 0" '[ $rc -eq 0 ]'
check "reports the worker status line" 'printf "%s" "$out" | grep -q "T1: DONE fake report"'
check "writes the report file" '[ -s "$CASE/tasks/T1.last.md" ]'
check "writes the events log" 'grep -q thread.started "$CASE/tasks/T1.events.jsonl"'
check "sandbox is workspace-write" 'arg_present workspace-write && arg_present --sandbox'
check "network access is off" 'arg_present sandbox_workspace_write.network_access=false'
check "ephemeral and json" 'arg_present --ephemeral && arg_present --json'
check "runs in the target repo" 'arg_present --cd && grep -qx -- "$(cd "$CASE/repo" && pwd -P)" "$FAKE_DIR/args"'
check "prompt is read from stdin (-)" '[ "$(tail -1 "$FAKE_DIR/args")" = "-" ]'
check "no model flag by default" '! arg_present -m'
check "stdin starts with the generic preamble" 'head -1 "$FAKE_DIR/stdin" | grep -q "implementation worker in a MonsterFlow"'
check "stdin ends with the task contract" '[ "$(tail -1 "$FAKE_DIR/stdin")" = "TASK CONTRACT happy" ]'

# Task paths: nested/relative inputs work, but no file operations may
# traverse outside TASK_DIR through ../ or symlinked input/output files.
reset_case nested-task
mkdir -p "$CASE/tasks/wave2"
printf 'NESTED CONTRACT\n' > "$CASE/tasks/wave2/task-17.prompt.md"
(cd "$CASE/repo" && with_deadline bash "$WORKER" "$CASE/tasks" wave2/task-17 >/dev/null 2>&1); rc=$?
check "nested task ID works" '[ "$rc" -eq 0 ] && [ -s "$CASE/tasks/wave2/task-17.last.md" ] && [ -s "$CASE/tasks/wave2/task-17.events.jsonl" ]'

reset_case relative-dir
mkdir -p "$CASE/tasks/wave2"
printf 'RELATIVE CONTRACT\n' > "$CASE/tasks/wave2/task-17.prompt.md"
(cd "$CASE" && with_deadline bash "$WORKER" tasks wave2/task-17 >/dev/null 2>&1); rc=$?
check "relative task directory with nested task ID works" '[ "$rc" -eq 0 ] && [ -s "$CASE/tasks/wave2/task-17.last.md" ]'

reset_case in-root-relative
mkdir -p "$CASE/tasks/wave2"
(cd "$CASE/repo" && with_deadline bash "$WORKER" "$CASE/tasks" wave2/../T1 >/dev/null 2>&1); rc=$?
check "in-root parent component is allowed" '[ "$rc" -eq 0 ] && [ -s "$CASE/tasks/T1.last.md" ]'

reset_case in-root-symlink
mkdir -p "$CASE/tasks/wave2"
printf 'IN ROOT\n' > "$CASE/tasks/wave2/task-17.prompt.md"
ln -s wave2 "$CASE/tasks/alias"
(cd "$CASE/repo" && with_deadline bash "$WORKER" "$CASE/tasks" alias/task-17 >/dev/null 2>&1); rc=$?
check "nested symlink resolving inside task directory works" '[ "$rc" -eq 0 ] && [ -s "$CASE/tasks/wave2/task-17.last.md" ]'

reset_case task-traversal
mkdir -p "$CASE/outside"
printf 'OUTSIDE CONTRACT\n' > "$CASE/outside/T1.prompt.md"
printf 'DO NOT DELETE\n' > "$CASE/outside/T1.last.md"
(cd "$CASE/repo" && with_deadline bash "$WORKER" "$CASE/tasks" ../outside/T1 >/dev/null 2>&1); rc=$?
check "task traversal is rejected before report cleanup" '[ "$rc" -eq 2 ] && [ "$(cat "$CASE/outside/T1.last.md")" = "DO NOT DELETE" ] && [ ! -e "$FAKE_DIR/args" ]'

reset_case task-symlink-dir
mkdir -p "$CASE/outside"
printf 'OUTSIDE CONTRACT\n' > "$CASE/outside/T1.prompt.md"
ln -s "$CASE/outside" "$CASE/tasks/link"
(cd "$CASE/repo" && with_deadline bash "$WORKER" "$CASE/tasks" link/T1 >/dev/null 2>&1); rc=$?
check "task parent symlink escape is rejected" '[ "$rc" -eq 2 ] && [ ! -e "$FAKE_DIR/args" ]'

reset_case contract-symlink
printf 'OUTSIDE CONTRACT\n' > "$CASE/outside-contract"
rm "$CASE/tasks/T1.prompt.md"
ln -s "$CASE/outside-contract" "$CASE/tasks/T1.prompt.md"
(cd "$CASE/repo" && with_deadline bash "$WORKER" "$CASE/tasks" T1 >/dev/null 2>&1); rc=$?
check "contract symlink escape is rejected" '[ "$rc" -eq 2 ] && [ ! -e "$FAKE_DIR/args" ]'

reset_case report-symlink
printf 'DO NOT DELETE\n' > "$CASE/outside-report"
ln -s "$CASE/outside-report" "$CASE/tasks/T1.last.md"
(cd "$CASE/repo" && with_deadline bash "$WORKER" "$CASE/tasks" T1 >/dev/null 2>&1); rc=$?
check "report symlink escape cannot delete external data" '[ "$rc" -eq 2 ] && [ -L "$CASE/tasks/T1.last.md" ] && [ "$(cat "$CASE/outside-report")" = "DO NOT DELETE" ]'

reset_case events-symlink
printf 'DO NOT WRITE\n' > "$CASE/outside-events"
ln -s "$CASE/outside-events" "$CASE/tasks/T1.events.jsonl"
(cd "$CASE/repo" && with_deadline bash "$WORKER" "$CASE/tasks" T1 >/dev/null 2>&1); rc=$?
check "event-log symlink escape is rejected" '[ "$rc" -eq 2 ] && [ "$(cat "$CASE/outside-events")" = "DO NOT WRITE" ]'

reset_case stderr-symlink
printf 'DO NOT WRITE\n' > "$CASE/outside-stderr"
ln -s "$CASE/outside-stderr" "$CASE/tasks/T1.stderr.log"
(cd "$CASE/repo" && with_deadline bash "$WORKER" "$CASE/tasks" T1 >/dev/null 2>&1); rc=$?
check "stderr symlink escape is rejected" '[ "$rc" -eq 2 ] && [ "$(cat "$CASE/outside-stderr")" = "DO NOT WRITE" ]'

reset_case dangling-symlink
ln -s "$CASE/nonexistent-external-target" "$CASE/tasks/T1.last.md"
(cd "$CASE/repo" && with_deadline bash "$WORKER" "$CASE/tasks" T1 >/dev/null 2>&1); rc=$?
check "dangling report symlink outside root is rejected" '[ "$rc" -eq 2 ] && [ -L "$CASE/tasks/T1.last.md" ]'

reset_case overlay
mkdir -p "$CASE/repo/.monsterflow"
printf 'PROJECT RULE: never run pnpm\n' > "$CASE/repo/.monsterflow/build-worker-preamble.md"
(cd "$CASE/repo" && with_deadline bash "$WORKER" "$CASE/tasks" T1 >/dev/null 2>&1)
check "project overlay is included" 'grep -q "PROJECT RULE: never run pnpm" "$FAKE_DIR/stdin"'
p_pre="$(grep -n "implementation worker in a MonsterFlow" "$FAKE_DIR/stdin" | head -1 | cut -d: -f1)"
p_ovl="$(grep -n "PROJECT RULE" "$FAKE_DIR/stdin" | head -1 | cut -d: -f1)"
p_task="$(grep -n "TASK CONTRACT overlay" "$FAKE_DIR/stdin" | head -1 | cut -d: -f1)"
check "order is preamble, overlay, contract" '[ "$p_pre" -lt "$p_ovl" ] && [ "$p_ovl" -lt "$p_task" ]'

reset_case model-config
printf '{"codex_worker_model": "cfg-model"}\n' > "$MONSTERFLOW_CONFIG"
(cd "$CASE/repo" && with_deadline bash "$WORKER" "$CASE/tasks" T1 >/dev/null 2>&1)
check "model comes from config" 'arg_present -m && arg_present cfg-model'
(cd "$CASE/repo" && MONSTERFLOW_CODEX_WORKER_MODEL=env-model with_deadline bash "$WORKER" "$CASE/tasks" T1 >/dev/null 2>&1)
check "env overrides config" 'arg_present env-model && ! arg_present cfg-model'
(cd "$CASE/repo" && MONSTERFLOW_CODEX_WORKER_MODEL=env-model with_deadline bash "$WORKER" --model flag-model "$CASE/tasks" T1 >/dev/null 2>&1)
check "--model overrides env" 'arg_present flag-model && ! arg_present env-model'
check "one model flag and one model argument" '[ "$(grep -cFx -- "-m" "$FAKE_DIR/args")" -eq 1 ] && [ "$(grep -cFx -- "flag-model" "$FAKE_DIR/args")" -eq 1 ]'

reset_case model-safe-punct
(cd "$CASE/repo" && with_deadline bash "$WORKER" --model 'vendor:gpt-6/mini+fast' "$CASE/tasks" T1 >/dev/null 2>&1); rc=$?
check "valid punctuation remains a single model token" '[ "$rc" -eq 0 ] && [ "$(grep -cFx -- "vendor:gpt-6/mini+fast" "$FAKE_DIR/args")" -eq 1 ]'

reset_case model-injected
(cd "$CASE/repo" && with_deadline bash "$WORKER" --model 'gpt-6 --sandbox danger-full-access' "$CASE/tasks" T1 >/dev/null 2>&1); rc=$?
check "CLI model cannot inject arguments" '[ "$rc" -eq 2 ] && [ ! -e "$FAKE_DIR/args" ]'

reset_case model-leading-dash
(cd "$CASE/repo" && with_deadline bash "$WORKER" --model '--dangerously-bypass-approvals-and-sandbox' "$CASE/tasks" T1 >/dev/null 2>&1); rc=$?
check "leading dash model is rejected" '[ "$rc" -eq 2 ] && [ ! -e "$FAKE_DIR/args" ]'

reset_case model-env-injected
(cd "$CASE/repo" && MONSTERFLOW_CODEX_WORKER_MODEL='gpt-6 --json' with_deadline bash "$WORKER" "$CASE/tasks" T1 >/dev/null 2>&1); rc=$?
check "environment model cannot inject arguments" '[ "$rc" -eq 2 ] && [ ! -e "$FAKE_DIR/args" ]'

reset_case model-config-injected
printf '{"codex_worker_model": "gpt-6 --json"}\n' > "$MONSTERFLOW_CONFIG"
(cd "$CASE/repo" && with_deadline bash "$WORKER" "$CASE/tasks" T1 >/dev/null 2>&1); rc=$?
check "config model cannot inject arguments" '[ "$rc" -eq 2 ] && [ ! -e "$FAKE_DIR/args" ]'

reset_case codexfail
(cd "$CASE/repo" && FAKE_EXIT=1 with_deadline bash "$WORKER" "$CASE/tasks" T1 >/dev/null 2>&1)
check "exit 4 when codex fails" '[ $? -eq 4 ]'

reset_case noreport
(cd "$CASE/repo" && FAKE_REPORT="" with_deadline bash "$WORKER" "$CASE/tasks" T1 >/dev/null 2>&1)
check "exit 5 when codex writes no report" '[ $? -eq 5 ]'

reset_case probe-ok
with_deadline bash "$WORKER" --probe-model --model good-model >/dev/null 2>&1
check "probe succeeds for a usable model" '[ $? -eq 0 ] && arg_present good-model && arg_present read-only'
reset_case probe-bad
FAKE_EXIT=1 with_deadline bash "$WORKER" --probe-model --model gpt-unavailable >/dev/null 2>&1
check "probe exits 6 for an unusable model" '[ $? -eq 6 ]'

echo "build-codex-review.sh"

reset_case review
git -C "$CASE/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
BASE_SHA="$(git -C "$CASE/repo" rev-parse --short HEAD)"
git -C "$CASE/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m change
# `< <(yes)` keeps an open, endless stdin: a script that did not close stdin would
# hand it to codex, which would block until the deadline.
(cd "$CASE/repo" && with_deadline bash "$REVIEW" --base "$BASE_SHA" --output "$CASE/review.txt" >/dev/null 2>&1 < <(yes)); rc=$?
check "review exits 0" '[ $rc -eq 0 ]'
check "review writes the output file" '[ -s "$CASE/review.txt" ]'
check "review sandbox is read-only" 'arg_present read-only'
check "review covers commits since the base" 'grep -q "$BASE_SHA..HEAD" "$FAKE_DIR/args"'
check "review does not use --uncommitted" '! arg_present --uncommitted'
check "review stdin is closed (empty)" '[ ! -s "$FAKE_DIR/stdin" ]'

reset_case review-skip
(cd "$CASE/repo" && MONSTERFLOW_CODEX_BIN="$TMP/no-such-codex" with_deadline bash "$REVIEW" --base HEAD --output "$CASE/review.txt" >/dev/null 2>&1)
check "review silently skips without codex" '[ $? -eq 0 ] && [ ! -e "$CASE/review.txt" ]'

reset_case review-fail
git -C "$CASE/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
(cd "$CASE/repo" && FAKE_EXIT=1 with_deadline bash "$REVIEW" --base HEAD --output "$CASE/review.txt" >/dev/null 2>&1)
check "review exits 4 when codex fails" '[ $? -eq 4 ]'
reset_case review-model-safe
git -C "$CASE/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
(cd "$CASE/repo" && with_deadline bash "$REVIEW" --base HEAD --model 'vendor:gpt-6/mini+fast' --output "$CASE/review.txt" >/dev/null 2>&1); rc=$?
check "review passes valid model as one token" '[ "$rc" -eq 0 ] && [ "$(grep -cFx -- "vendor:gpt-6/mini+fast" "$FAKE_DIR/args")" -eq 1 ]'

reset_case review-model-injected
git -C "$CASE/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
(cd "$CASE/repo" && with_deadline bash "$REVIEW" --base HEAD --model 'gpt-6 --sandbox danger-full-access' --output "$CASE/review.txt" >/dev/null 2>&1); rc=$?
check "review rejects injected model before invoking Codex" '[ "$rc" -eq 2 ] && [ ! -e "$FAKE_DIR/args" ]'

echo "commands/build.md"
check "Phase 2 documents Codex workers" 'grep -q "^### Implementation workers: Claude subagents or Codex" "$BUILD_MD"'
check "Phase 2 dispatches through the adapter" 'grep -q "<REPO_DIR>/scripts/build-codex-worker.sh <task-dir> <task-id>" "$BUILD_MD"'
check "Phase 3 uses the branch review script" 'grep -q "<REPO_DIR>/scripts/build-codex-review.sh" "$BUILD_MD"'
check "Phase 3 no longer reviews only uncommitted changes" '! grep -q "codex exec review --uncommitted" "$BUILD_MD"'
check "Phase 4 resolves mark-addressed from the MonsterFlow checkout" 'grep -q "python3 <REPO_DIR>/scripts/build-mark-addressed.py" "$BUILD_MD"'

check "Codex workers are opt-in; Claude subagents stay the default" 'grep -q "\`claude\` (the default" "$BUILD_MD"'
check "Codex unavailable falls back to Claude subagents" 'grep -q "Exit 3 (Codex not installed or not authenticated): use Claude subagents" "$BUILD_MD"'

echo "config schema and docs"
SCHEMA="$(python3 "$REPO_ROOT/scripts/_resolve_personas.py" --print-schema 2>/dev/null)"
check "schema declares build_workers as claude|codex" 'printf "%s" "$SCHEMA" | python3 -c "import json,sys; p=json.load(sys.stdin)[\"properties\"]; sys.exit(0 if p[\"build_workers\"][\"enum\"]==[\"claude\",\"codex\"] and p[\"codex_worker_model\"][\"type\"]==\"string\" else 1)"'
check "budget.md documents both keys" 'grep -q "^| \`build_workers\`" "$REPO_ROOT/docs/budget.md" && grep -q "^| \`codex_worker_model\`" "$REPO_ROOT/docs/budget.md"'
check "QUICKSTART has the opt-in section" 'grep -q "^## 6c. Codex implementation workers for \`/build\` (optional, opt-in)" "$REPO_ROOT/QUICKSTART.md"'
check "QUICKSTART links the full reference" 'grep -q "(docs/build-workers.md)" "$REPO_ROOT/QUICKSTART.md"'
check "reference doc covers enabling, probing and disabling" 'grep -q "build_workers" "$REPO_ROOT/docs/build-workers.md" && grep -q -- "--probe-model" "$REPO_ROOT/docs/build-workers.md" && grep -q "Turn it off" "$REPO_ROOT/docs/build-workers.md"'
check "generic worker preamble ships" 'grep -q "^Final message" "$REPO_ROOT/templates/build-worker-preamble.md"'
check "test is wired into run-tests.sh" 'grep -q "test-build-codex-worker.sh" "$REPO_ROOT/tests/run-tests.sh"'

echo
echo "build-codex-worker: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
