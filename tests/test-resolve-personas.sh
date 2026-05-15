#!/bin/bash
##############################################################################
# tests/test-resolve-personas.sh
#
# Unit tests for scripts/resolve-personas.sh — the per-gate persona resolver
# introduced by docs/specs/account-type-agent-scaling/spec.md.
#
# Mocking model (per memory feedback_path_stub_over_export_f):
#   - PATH-stub for `codex` binary; export -f doesn't survive subshells.
#   - MONSTERFLOW_CODEX_AUTH={1,0} hard-overrides the probe for cases where
#     the cache state would interfere.
#   - Each subtest gets an isolated $HOME under $TMPDIR; ~/.config/monsterflow/
#     and ~/.cache/monsterflow/ are clean per case.
#   - MONSTERFLOW_REPO_DIR pin keeps disk discovery stable across cwd.
#
# Bash 3.2 portability:
#   - No ${array[-1]} (memory feedback_negative_array_subscript_bash32).
#   - Pin BASH=/bin/bash.
#   - Tilde expansion: always ${VAR/#\~/$HOME} before any write.
##############################################################################
set -uo pipefail

export BASH=/bin/bash

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
RESOLVER="$REPO_DIR/scripts/resolve-personas.sh"
RANKINGS="$REPO_DIR/dashboard/data/persona-rankings.jsonl"

PASS=0
FAIL=0
FAILED_CASES=()

# Per-case scratch
CASE_DIR=""
CASE_HOME=""
CASE_OUT=""
CASE_ERR=""

setup_case() {
    CASE_DIR="$(mktemp -d -t mf-resolve-test.XXXXXX)"
    if [ -z "$CASE_DIR" ] || [ ! -d "$CASE_DIR" ]; then
        echo "FAIL: mktemp -d returned invalid path '$CASE_DIR'" >&2
        return 1
    fi
    CASE_HOME="$CASE_DIR/home"
    CASE_OUT="$CASE_DIR/out"
    CASE_ERR="$CASE_DIR/err"
    mkdir -p "$CASE_HOME/.config/monsterflow"
    : > "$CASE_OUT"
    : > "$CASE_ERR"
    export HOME="$CASE_HOME"
    export MONSTERFLOW_REPO_DIR="$REPO_DIR"
    # Default: codex unauthenticated unless case overrides
    export MONSTERFLOW_CODEX_AUTH=0
    unset MONSTERFLOW_DISABLE_BUDGET
    # Isolate from inherited env (friend's shell had PROJECT_DIR pointing at
    # another project, making --with-tier look in the wrong docs/specs/).
    unset PROJECT_DIR
}

teardown_case() {
    [ -n "$CASE_DIR" ] && [ -d "$CASE_DIR" ] && rm -rf "$CASE_DIR"
    CASE_DIR=""
}

write_config() {
    # $1 = JSON content
    printf '%s' "$1" > "$CASE_HOME/.config/monsterflow/config.json"
}

# Run resolver, capture stdout/stderr/exit. Args: gate [extra...]
run_resolver() {
    local exit_code=0
    bash "$RESOLVER" "$@" >"$CASE_OUT" 2>"$CASE_ERR" || exit_code=$?
    echo "$exit_code"
}

# Assertion helpers
assert_exit() {
    # $1 = case name, $2 = expected exit, $3 = actual exit
    local name="$1" expected="$2" actual="$3"
    if [ "$actual" != "$expected" ]; then
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("$name: expected exit=$expected got=$actual")
        echo "    ✗ exit=$actual (expected $expected)" >&2
        if [ -s "$CASE_ERR" ]; then
            echo "    --- stderr ---" >&2
            sed 's/^/      /' < "$CASE_ERR" >&2
        fi
        return 1
    fi
    return 0
}

assert_stdout_lines() {
    # $1 = case name, $2 = expected line count
    local name="$1" expected="$2"
    local actual
    actual=$(grep -c . "$CASE_OUT" 2>/dev/null || echo 0)
    if [ "$actual" != "$expected" ]; then
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("$name: expected $expected stdout lines, got $actual")
        echo "    ✗ stdout lines=$actual (expected $expected)" >&2
        echo "    --- stdout ---" >&2
        sed 's/^/      /' < "$CASE_OUT" >&2
        return 1
    fi
    return 0
}

assert_stdout_contains() {
    # $1 = case name, $2 = literal line that must appear
    local name="$1" needle="$2"
    if ! grep -qxF "$needle" "$CASE_OUT" 2>/dev/null; then
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("$name: stdout missing '$needle'")
        echo "    ✗ stdout missing '$needle'" >&2
        sed 's/^/      /' < "$CASE_OUT" >&2
        return 1
    fi
    return 0
}

assert_stdout_lacks() {
    # $1 = case name, $2 = line that must NOT appear
    local name="$1" needle="$2"
    if grep -qxF "$needle" "$CASE_OUT" 2>/dev/null; then
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("$name: stdout unexpectedly contains '$needle'")
        echo "    ✗ stdout has '$needle' (should be absent)" >&2
        return 1
    fi
    return 0
}

assert_first_line() {
    # $1 = case name, $2 = expected first line
    local name="$1" expected="$2"
    local actual
    actual=$(head -1 "$CASE_OUT" 2>/dev/null || echo "")
    if [ "$actual" != "$expected" ]; then
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("$name: first line='$actual' (expected '$expected')")
        echo "    ✗ first line='$actual' (expected '$expected')" >&2
        return 1
    fi
    return 0
}

case_done() {
    local name="$1" status="$2"
    if [ "$status" = "ok" ]; then
        PASS=$(( PASS + 1 ))
        echo "  ✓ $name"
    fi
    teardown_case
}

##############################################################################
# Cases (numbered to match plan §10.1 where possible)
##############################################################################

case_1_no_config_full_roster() {
    setup_case
    local name="1: no config → full roster"
    local exit_code; exit_code=$(run_resolver check)
    local status=ok
    assert_exit "$name" 0 "$exit_code" || status=fail
    # check has 6 personas on disk (incl security-architect added in autorun-overnight-policy v6)
    assert_stdout_lines "$name" 6 || status=fail
    assert_stdout_lacks "$name" "codex-adversary" || status=fail
    case_done "$name" "$status"
}

case_2_budget_absent_full_roster() {
    setup_case
    local name="2: agent_budget absent → full roster"
    write_config '{"persona_pins": {"check": ["risk"]}}'
    local exit_code; exit_code=$(run_resolver check)
    local status=ok
    assert_exit "$name" 0 "$exit_code" || status=fail
    assert_stdout_lines "$name" 6 || status=fail
    case_done "$name" "$status"
}

case_3_budget_3_no_pins_no_rankings() {
    setup_case
    local name="3: budget=3, no pins, no rankings → seed[0:3]"
    write_config '{"agent_budget": 3}'
    # Move rankings file aside so resolver sees it absent
    local saved=""
    if [ -f "$RANKINGS" ]; then
        saved="$RANKINGS.test-$$.bak"
        mv "$RANKINGS" "$saved"
    fi
    local exit_code; exit_code=$(run_resolver check)
    local status=ok
    [ -n "$saved" ] && mv "$saved" "$RANKINGS"
    assert_exit "$name" 0 "$exit_code" || status=fail
    assert_stdout_lines "$name" 3 || status=fail
    assert_first_line "$name" "scope-discipline" || status=fail
    case_done "$name" "$status"
}

case_6_budget_1() {
    setup_case
    local name="6: budget=1 → exactly 1 persona"
    write_config '{"agent_budget": 1}'
    local exit_code; exit_code=$(run_resolver spec-review)
    local status=ok
    assert_exit "$name" 0 "$exit_code" || status=fail
    assert_stdout_lines "$name" 1 || status=fail
    case_done "$name" "$status"
}

case_7_budget_8_plan_only_7() {
    setup_case
    local name="7: budget=8 plan (only 7 on disk) → 7 lines"
    write_config '{"agent_budget": 8}'
    local exit_code; exit_code=$(run_resolver design)
    local status=ok
    assert_exit "$name" 0 "$exit_code" || status=fail
    assert_stdout_lines "$name" 7 || status=fail
    case_done "$name" "$status"
}

case_8_pin_missing_persona() {
    setup_case
    local name="8: pin missing on disk → skipped + warned"
    write_config '{"agent_budget": 2, "persona_pins": {"check": ["nonexistent-persona", "risk"]}}'
    local exit_code; exit_code=$(run_resolver check)
    local status=ok
    assert_exit "$name" 0 "$exit_code" || status=fail
    assert_stdout_contains "$name" "risk" || status=fail
    assert_stdout_lacks "$name" "nonexistent-persona" || status=fail
    if ! grep -q "nonexistent-persona" "$CASE_ERR"; then
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("$name: stderr missing warning about missing pin")
        status=fail
    fi
    case_done "$name" "$status"
}

case_12_budget_zero() {
    setup_case
    local name="12: agent_budget=0 → floor 1"
    write_config '{"agent_budget": 0}'
    local exit_code; exit_code=$(run_resolver check)
    local status=ok
    assert_exit "$name" 0 "$exit_code" || status=fail
    assert_stdout_lines "$name" 1 || status=fail
    case_done "$name" "$status"
}

case_13_budget_99_clamp() {
    setup_case
    local name="13: agent_budget=99 → clamp to 8"
    write_config '{"agent_budget": 99}'
    local exit_code; exit_code=$(run_resolver design)
    local status=ok
    assert_exit "$name" 0 "$exit_code" || status=fail
    # plan only has 7 personas, so we get 7 lines (clamp doesn't add nonexistent)
    assert_stdout_lines "$name" 7 || status=fail
    case_done "$name" "$status"
}

case_14_malformed_json() {
    setup_case
    local name="14: malformed JSON → exit 2"
    write_config '{ this is not valid json'
    local exit_code; exit_code=$(run_resolver check)
    local status=ok
    assert_exit "$name" 2 "$exit_code" || status=fail
    case_done "$name" "$status"
}

case_17_codex_authenticated() {
    setup_case
    local name="17: codex authenticated → codex-adversary appended last"
    write_config '{"agent_budget": 2}'
    export MONSTERFLOW_CODEX_AUTH=1
    local exit_code; exit_code=$(run_resolver check)
    local status=ok
    assert_exit "$name" 0 "$exit_code" || status=fail
    # 2 Claude personas + 1 codex line = 3
    assert_stdout_lines "$name" 3 || status=fail
    # codex must be the last line
    local last_line; last_line=$(tail -1 "$CASE_OUT" 2>/dev/null)
    if [ "$last_line" != "codex-adversary" ]; then
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("$name: last line='$last_line' (expected 'codex-adversary')")
        status=fail
    fi
    case_done "$name" "$status"
}

case_18_codex_not_authenticated() {
    setup_case
    local name="18: codex not authenticated → no codex line"
    write_config '{"agent_budget": 2}'
    export MONSTERFLOW_CODEX_AUTH=0
    local exit_code; exit_code=$(run_resolver check)
    local status=ok
    assert_exit "$name" 0 "$exit_code" || status=fail
    assert_stdout_lines "$name" 2 || status=fail
    assert_stdout_lacks "$name" "codex-adversary" || status=fail
    case_done "$name" "$status"
}

case_20_codex_disabled_in_config() {
    setup_case
    local name="20: codex_disabled=true → codex never appears"
    write_config '{"agent_budget": 2, "codex_disabled": true}'
    export MONSTERFLOW_CODEX_AUTH=1   # would be appended without flag
    local exit_code; exit_code=$(run_resolver check)
    local status=ok
    assert_exit "$name" 0 "$exit_code" || status=fail
    assert_stdout_lines "$name" 2 || status=fail
    assert_stdout_lacks "$name" "codex-adversary" || status=fail
    case_done "$name" "$status"
}

case_22_lock_honored() {
    setup_case
    local name="22: .budget-lock.json honored over live config"
    write_config '{"agent_budget": 5}'
    # Pre-create lock with budget=2 for a synthetic feature; need a real
    # docs/specs/<slug>/ dir for the lock writer path, but here we're testing
    # READ behavior so the parent must exist.
    local feature="test-lock-feature-$$"
    local fdir="$REPO_DIR/docs/specs/$feature"
    mkdir -p "$fdir"
    cat > "$fdir/.budget-lock.json" <<EOF
{
  "schema_version": 1,
  "agent_budget": 2,
  "persona_pins": {},
  "codex_disabled": false,
  "locked_at": "2026-05-04T00:00:00Z"
}
EOF
    local exit_code; exit_code=$(run_resolver check --feature "$feature")
    local status=ok
    rm -rf "$fdir"
    assert_exit "$name" 0 "$exit_code" || status=fail
    assert_stdout_lines "$name" 2 || status=fail
    case_done "$name" "$status"
}

case_24_unlock_budget() {
    setup_case
    local name="24: --unlock-budget removes lock"
    local feature="test-unlock-$$"
    local fdir="$REPO_DIR/docs/specs/$feature"
    mkdir -p "$fdir"
    echo '{"schema_version":1,"agent_budget":2,"persona_pins":{},"codex_disabled":false,"locked_at":"2026-05-04T00:00:00Z"}' \
        > "$fdir/.budget-lock.json"
    local exit_code; exit_code=$(run_resolver check --feature "$feature" --unlock-budget)
    local status=ok
    if [ -f "$fdir/.budget-lock.json" ]; then
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("$name: lock file still present after --unlock-budget")
        status=fail
    fi
    rm -rf "$fdir"
    assert_exit "$name" 0 "$exit_code" || status=fail
    case_done "$name" "$status"
}

case_25_why_to_stderr() {
    setup_case
    local name="25: --why prints to stderr; stdout still strict"
    write_config '{"agent_budget": 2}'
    local exit_code; exit_code=$(run_resolver check --why)
    local status=ok
    assert_exit "$name" 0 "$exit_code" || status=fail
    assert_stdout_lines "$name" 2 || status=fail
    if ! grep -q "selected:" "$CASE_ERR"; then
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("$name: --why didn't write reasoning to stderr")
        status=fail
    fi
    case_done "$name" "$status"
}

case_26_print_schema() {
    setup_case
    local name="26: --print-schema emits valid JSON"
    local exit_code; exit_code=$(run_resolver --print-schema)
    local status=ok
    assert_exit "$name" 0 "$exit_code" || status=fail
    if ! python3 -c "import json,sys; json.load(open('$CASE_OUT'))" 2>/dev/null; then
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("$name: --print-schema output is not valid JSON")
        status=fail
    fi
    case_done "$name" "$status"
}

case_29_disable_budget_kill_switch() {
    setup_case
    local name="29: MONSTERFLOW_DISABLE_BUDGET=1 → full roster"
    write_config '{"agent_budget": 1}'
    export MONSTERFLOW_DISABLE_BUDGET=1
    local exit_code; exit_code=$(run_resolver check)
    local status=ok
    unset MONSTERFLOW_DISABLE_BUDGET
    assert_exit "$name" 0 "$exit_code" || status=fail
    assert_stdout_lines "$name" 6 || status=fail
    case_done "$name" "$status"
}

case_30_emit_selection_json() {
    setup_case
    local name="30: --emit-selection-json writes audit row"
    write_config '{"agent_budget": 2}'
    local feature="test-emit-$$"
    local fdir="$REPO_DIR/docs/specs/$feature"
    mkdir -p "$fdir"
    local exit_code; exit_code=$(run_resolver check --feature "$feature" --emit-selection-json)
    local status=ok
    if [ ! -f "$fdir/check/selection.json" ]; then
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("$name: selection.json not written")
        status=fail
    else
        # Validate schema
        if ! python3 -c "
import json, sys
d = json.load(open('$fdir/check/selection.json'))
required = ['schema_version','feature','gate','ran_at','selection_method','selected','dropped','codex_status','budget_used','budget_source','locked_from','resolver_exit']
missing = [k for k in required if k not in d]
sys.exit(1 if missing else 0)
" 2>/dev/null; then
            FAIL=$(( FAIL + 1 ))
            FAILED_CASES+=("$name: selection.json missing required keys")
            status=fail
        fi
    fi
    rm -rf "$fdir"
    assert_exit "$name" 0 "$exit_code" || status=fail
    case_done "$name" "$status"
}

case_31_invalid_gate() {
    setup_case
    local name="31: invalid gate → exit 5"
    local exit_code; exit_code=$(run_resolver bogus-gate)
    local status=ok
    assert_exit "$name" 5 "$exit_code" || status=fail
    case_done "$name" "$status"
}

case_32_emit_json_no_feature() {
    setup_case
    local name="32: --emit-selection-json without --feature → exit 4"
    local exit_code; exit_code=$(run_resolver check --emit-selection-json)
    local status=ok
    assert_exit "$name" 4 "$exit_code" || status=fail
    case_done "$name" "$status"
}

# AC #7 — recovery prompt support: --print-seed lets the recovery fragment's
# "(2) continue with seed" option fetch the canonical per-gate seed list
# without re-implementing it in shell. Coverage:
#   - happy path: each gate emits its full seed list (newline-separated)
#   - exit code: 0 on success, 4 on missing/invalid gate
#   - codex never appears (Codex is owned by the resolver's auth probe)

case_33_print_seed_spec_review() {
    setup_case
    local name="33: --print-seed spec-review emits 6 names"
    local exit_code; exit_code=$(run_resolver spec-review --print-seed)
    local status=ok
    assert_exit "$name" 0 "$exit_code" || status=fail
    assert_stdout_lines "$name" 6 || status=fail
    assert_first_line "$name" "requirements" || status=fail
    assert_stdout_lacks "$name" "codex-adversary" || status=fail
    case_done "$name" "$status"
}

case_34_print_seed_plan() {
    setup_case
    local name="34: --print-seed plan emits 7 names (wave-sequencer present)"
    local exit_code; exit_code=$(run_resolver design --print-seed)
    local status=ok
    assert_exit "$name" 0 "$exit_code" || status=fail
    assert_stdout_lines "$name" 7 || status=fail
    assert_stdout_contains "$name" "wave-sequencer" || status=fail
    case_done "$name" "$status"
}

case_35_print_seed_check() {
    setup_case
    local name="35: --print-seed check emits 6 names"
    local exit_code; exit_code=$(run_resolver check --print-seed)
    local status=ok
    assert_exit "$name" 0 "$exit_code" || status=fail
    assert_stdout_lines "$name" 6 || status=fail
    assert_first_line "$name" "scope-discipline" || status=fail
    case_done "$name" "$status"
}

case_36_print_seed_invalid_gate() {
    setup_case
    local name="36: --print-seed without gate → exit 4"
    local exit_code; exit_code=$(run_resolver --print-seed)
    local status=ok
    assert_exit "$name" 4 "$exit_code" || status=fail
    case_done "$name" "$status"
}

case_37_print_seed_unknown_gate() {
    setup_case
    local name="37: --print-seed bogus-gate → exit 4"
    local exit_code; exit_code=$(run_resolver bogus-gate --print-seed)
    local status=ok
    assert_exit "$name" 4 "$exit_code" || status=fail
    case_done "$name" "$status"
}

# AC #7 — recovery-fragment wiring: the canonical fragment file exists and is
# referenced by all three gate command files. Without these references, AC #7
# has no callable surface in interactive mode.
case_38_recovery_fragment_exists() {
    setup_case
    local name="38: _resolver-recovery.md fragment exists and is referenced"
    local fragment="$REPO_DIR/commands/_prompts/_resolver-recovery.md"
    local status=ok
    if [ ! -f "$fragment" ]; then
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("$name: fragment $fragment missing")
        status=fail
    fi
    # Note: "blueprint" replaces /design (which replaced /plan); /design
    # collided with the frontend-design skill, so the slash command moved
    # to /blueprint. Internal gate id stays "design".
    for cmd in spec-review blueprint check; do
        if ! grep -q "_resolver-recovery.md" "$REPO_DIR/commands/$cmd.md"; then
            FAIL=$(( FAIL + 1 ))
            FAILED_CASES+=("$name: commands/$cmd.md does not reference _resolver-recovery.md")
            status=fail
        fi
    done
    # Fragment must enumerate the three options and explicitly forbid silent
    # full-roster restoration (per AC #7 + plan D6 / SP3).
    for needle in "reconfigure now" "continue with seed" "abort gate"; do
        if ! grep -qF "$needle" "$fragment"; then
            FAIL=$(( FAIL + 1 ))
            FAILED_CASES+=("$name: fragment missing recovery option text '$needle'")
            status=fail
        fi
    done
    case_done "$name" "$status"
}

##############################################################################
# Slice 5 Wave 5a — tier-aware (`--with-tier`) end-to-end coverage.
#
# Plan: docs/specs/dynamic-roster-per-gate/plan.md task 23
# Followups consumed: ck-3456789012 (legacy-v1 selection.json → N/A sentinel)
#
# These cases dispatch against the live dynamic-roster-per-gate spec (already
# in docs/specs/). They DO mutate selection.json at
# docs/specs/dynamic-roster-per-gate/spec-review/ — that file is itself a
# build artifact regenerated by the autorun, so churn is acceptable.
# case_43 swaps dashboard/data/persona-rankings.jsonl out + back; failure
# during the swap is restored by a trap. case_45 writes its fixture under a
# tmpdir; no repo mutation.
##############################################################################

# Shared helpers for tier-aware cases. The existing harness uses run_resolver
# + assert_* helpers that all funnel through $CASE_OUT/$CASE_ERR. The new
# cases inspect the resolver's filesystem side-effects (selection.json), so
# they bypass run_resolver and call bash directly when needed.

TIER_FEATURE="dynamic-roster-per-gate"
TIER_SEL="$REPO_DIR/docs/specs/$TIER_FEATURE/spec-review/selection.json"

# --- 39: --with-tier emits <persona>:<tier> colon grammar --------------------
case_39_with_tier_grammar() {
    setup_case
    local name="39: --with-tier emits <persona>:<tier> grammar (no codex)"
    export MONSTERFLOW_CODEX_AUTH=0
    local exit_code; exit_code=$(run_resolver spec-review \
        --feature "$TIER_FEATURE" --with-tier)
    local status=ok
    assert_exit "$name" 0 "$exit_code" || status=fail
    # Every non-blank line must look like <name>:opus or <name>:sonnet.
    local bad
    bad=$(grep -vE '^$' "$CASE_OUT" | grep -cvE '^[a-z][a-z0-9-]*:(opus|sonnet)$' || true)
    if [ "$bad" != "0" ]; then
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("$name: $bad non-conforming stdout line(s)")
        echo "    --- stdout ---" >&2
        sed 's/^/      /' < "$CASE_OUT" >&2
        status=fail
    fi
    case_done "$name" "$status"
}

# --- 40: legacy mode (no --with-tier) emits bare names -----------------------
case_40_legacy_bare_names() {
    setup_case
    local name="40: legacy mode emits bare names (no colon)"
    export MONSTERFLOW_CODEX_AUTH=0
    local exit_code; exit_code=$(run_resolver spec-review \
        --feature "$TIER_FEATURE")
    local status=ok
    assert_exit "$name" 0 "$exit_code" || status=fail
    # No stdout line may contain ':opus' or ':sonnet'.
    if grep -qE ':(opus|sonnet)$' "$CASE_OUT"; then
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("$name: legacy stdout has tier suffix (regression)")
        echo "    --- stdout ---" >&2
        sed 's/^/      /' < "$CASE_OUT" >&2
        status=fail
    fi
    case_done "$name" "$status"
}

# --- 41: codex-adversary stays BARE under --with-tier ------------------------
case_41_codex_bare_under_with_tier() {
    setup_case
    local name="41: codex-adversary appears bare with --with-tier"
    export MONSTERFLOW_CODEX_AUTH=1
    local exit_code; exit_code=$(run_resolver check \
        --feature "$TIER_FEATURE" --with-tier)
    local status=ok
    assert_exit "$name" 0 "$exit_code" || status=fail
    # Exact bare line "codex-adversary" must appear; tier-suffixed must not.
    if ! grep -qxF "codex-adversary" "$CASE_OUT"; then
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("$name: codex-adversary bare line missing")
        status=fail
    fi
    if grep -qE '^codex-adversary:(opus|sonnet)$' "$CASE_OUT"; then
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("$name: codex-adversary erroneously got a tier suffix")
        status=fail
    fi
    case_done "$name" "$status"
}

# --- 42: --with-tier --emit-selection-json writes v2 selection.json ----------
case_42_v2_selection_json() {
    setup_case
    local name="42: --emit-selection-json writes schema_version:2 + selection-emit@2.x"
    export MONSTERFLOW_CODEX_AUTH=0
    local exit_code; exit_code=$(run_resolver spec-review \
        --feature "$TIER_FEATURE" --with-tier --emit-selection-json)
    local status=ok
    assert_exit "$name" 0 "$exit_code" || status=fail
    if [ ! -f "$TIER_SEL" ]; then
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("$name: selection.json not written at $TIER_SEL")
        status=fail
    else
        local sv pv
        sv=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("schema_version"))' "$TIER_SEL" 2>/dev/null)
        pv=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("prompt_version",""))' "$TIER_SEL" 2>/dev/null)
        if [ "$sv" != "2" ]; then
            FAIL=$(( FAIL + 1 ))
            FAILED_CASES+=("$name: schema_version expected 2, got '$sv'")
            status=fail
        fi
        if ! echo "$pv" | grep -qE '^selection-emit@2\.'; then
            FAIL=$(( FAIL + 1 ))
            FAILED_CASES+=("$name: prompt_version must be selection-emit@2.x, got '$pv'")
            status=fail
        fi
    fi
    case_done "$name" "$status"
}

# --- 43: cold-start fallback — empty rankings → combined = 0.5 * fit_score ---
case_43_cold_start_lbr_default() {
    setup_case
    local name="43: cold-start rankings → combined_score = 0.5 * fit_score"
    export MONSTERFLOW_CODEX_AUTH=0
    local rankings="$REPO_DIR/dashboard/data/persona-rankings.jsonl"
    local saved=""
    if [ -f "$rankings" ]; then
        saved="$rankings.test-$$.bak"
        mv "$rankings" "$saved"
    fi
    : > "$rankings"
    # Trap restore in case of unexpected exit during the case body.
    trap '[ -n "'"$saved"'" ] && [ -f "'"$saved"'" ] && mv "'"$saved"'" "'"$rankings"'"' EXIT
    local exit_code; exit_code=$(run_resolver spec-review \
        --feature "$TIER_FEATURE" --with-tier --emit-selection-json)
    local status=ok
    assert_exit "$name" 0 "$exit_code" || status=fail
    local verdict
    verdict=$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
rows = (d.get("selected") or []) + (d.get("dropped") or [])
bad = []
for r in rows:
    fit = r.get("fit_score", 0) or 0
    cs = r.get("combined_score", 0) or 0
    expected = 0.5 * fit
    if abs(cs - expected) > 1e-9:
        bad.append((r.get("persona"), fit, cs, expected))
print("OK" if not bad else "BAD:" + repr(bad))
' "$TIER_SEL" 2>/dev/null)
    if [ "$verdict" != "OK" ]; then
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("$name: cold-start lbr=0.5 violated: $verdict")
        status=fail
    fi
    # Restore rankings file + clear trap.
    if [ -n "$saved" ] && [ -f "$saved" ]; then
        mv "$saved" "$rankings"
    fi
    trap - EXIT
    case_done "$name" "$status"
}

# --- 44: 7 concurrent invocations don't corrupt selection.json ---------------
case_44_concurrent_reads() {
    setup_case
    local name="44: 7 concurrent --with-tier --emit invocations → valid JSON"
    export MONSTERFLOW_CODEX_AUTH=0
    local i pids=()
    for i in 1 2 3 4 5 6 7; do
        bash "$RESOLVER" spec-review --feature "$TIER_FEATURE" \
            --with-tier --emit-selection-json >/dev/null 2>&1 &
        # bash 3.2: avoid ${array[-1]}; capture $! per memory feedback.
        pids+=("$!")
    done
    local p rc=0
    for p in "${pids[@]}"; do
        wait "$p" || rc=$?
    done
    local status=ok
    if [ "$rc" != "0" ]; then
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("$name: at least one concurrent resolver exited non-zero (rc=$rc)")
        status=fail
    fi
    if ! python3 -c "import json,sys; json.load(open('$TIER_SEL'))" 2>/dev/null; then
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("$name: selection.json invalid JSON after concurrent writes")
        status=fail
    fi
    case_done "$name" "$status"
}

# --- 45: legacy v1 selection.json → judge-dashboard-bundle.py renders N/A ----
# Followup ck-3456789012: tighten "loads without error" to the exact "N/A"
# sentinel string in the bundle output. Fixture-only — does not touch repo
# state outside the tmpdir.
case_45_legacy_v1_renders_na() {
    setup_case
    local name="45: legacy v1 selection.json → tier_mix:N/A in bundle output"
    local status=ok
    local fixture="$CASE_DIR/projects"
    local proj="$fixture/sampleproj"
    local feat="$proj/docs/specs/legacy-fix"
    mkdir -p "$feat/spec-review"
    # v1 shape — no prompt_version, no tier_policy_applied. Per
    # extract_tier_mix() in scripts/judge-dashboard-bundle.py, anything with
    # schema_version != 2 yields the literal "N/A" string sentinel.
    cat > "$feat/spec-review/selection.json" <<'JSON'
{
  "schema_version": 1,
  "feature": "legacy-fix",
  "gate": "spec-review",
  "selected": ["requirements", "scope"]
}
JSON
    # stage_blob() returns None unless ≥1 of findings/participation/run/synth_md
    # is present. Provide synth_md so the legacy-fix feature isn't skipped.
    cat > "$feat/spec-review.md" <<'MD'
# spec-review

(legacy fixture for tier_mix N/A regression test)
MD
    local out_file="$CASE_DIR/bundle.js"
    if ! python3 "$REPO_DIR/scripts/judge-dashboard-bundle.py" \
            "$fixture" "$out_file" 2>"$CASE_ERR"; then
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("$name: judge-dashboard-bundle.py exited non-zero")
        echo "    --- stderr ---" >&2
        sed 's/^/      /' < "$CASE_ERR" >&2
        status=fail
    fi
    if [ ! -f "$out_file" ]; then
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("$name: bundle file not written at $out_file")
        status=fail
    elif ! grep -qE '"tier_mix"[[:space:]]*:[[:space:]]*"N/A"' "$out_file"; then
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("$name: bundle missing literal tier_mix:N/A sentinel")
        echo "    --- bundle (head) ---" >&2
        head -50 "$out_file" | sed 's/^/      /' >&2
        status=fail
    fi
    case_done "$name" "$status"
}

# --- 46: SEC-09 — /tmp/monsterflow-resolve.* cleaned on natural exit ---------
case_46_sec09_trap_cleanup() {
    setup_case
    local name="46: SEC-09 trap cleans /tmp/monsterflow-resolve.* on exit"
    export MONSTERFLOW_CODEX_AUTH=0
    # Baseline count (other test infrastructure may leave dirs; we compare
    # delta against baseline rather than asserting absolute 0).
    local before after delta
    before=$(/bin/ls -d /tmp/monsterflow-resolve.* 2>/dev/null | wc -l | tr -d ' ')
    bash "$RESOLVER" spec-review --feature "$TIER_FEATURE" --with-tier \
        >/dev/null 2>&1
    after=$(/bin/ls -d /tmp/monsterflow-resolve.* 2>/dev/null | wc -l | tr -d ' ')
    delta=$(( after - before ))
    local status=ok
    if [ "$delta" -gt 0 ]; then
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("$name: SEC-09 trap leaked $delta tempdir(s) (before=$before after=$after)")
        status=fail
    fi
    case_done "$name" "$status"
}

##############################################################################
# Main
##############################################################################

echo "=== test-resolve-personas.sh ==="
echo "REPO_DIR=$REPO_DIR"
echo ""

case_1_no_config_full_roster
case_2_budget_absent_full_roster
case_3_budget_3_no_pins_no_rankings
case_6_budget_1
case_7_budget_8_plan_only_7
case_8_pin_missing_persona
case_12_budget_zero
case_13_budget_99_clamp
case_14_malformed_json
case_17_codex_authenticated
case_18_codex_not_authenticated
case_20_codex_disabled_in_config
case_22_lock_honored
case_24_unlock_budget
case_25_why_to_stderr
case_26_print_schema
case_29_disable_budget_kill_switch
case_30_emit_selection_json
case_31_invalid_gate
case_32_emit_json_no_feature
case_33_print_seed_spec_review
case_34_print_seed_plan
case_35_print_seed_check
case_36_print_seed_invalid_gate
case_37_print_seed_unknown_gate
case_38_recovery_fragment_exists
case_39_with_tier_grammar
case_40_legacy_bare_names
case_41_codex_bare_under_with_tier
case_42_v2_selection_json
case_43_cold_start_lbr_default
case_44_concurrent_reads
case_45_legacy_v1_renders_na
case_46_sec09_trap_cleanup

echo ""
echo "=========================================="
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    echo "Failed cases:"
    for c in "${FAILED_CASES[@]}"; do
        echo "  - $c"
    done
    exit 1
fi
exit 0
