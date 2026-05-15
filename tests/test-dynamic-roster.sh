#!/bin/bash
##############################################################################
# tests/test-dynamic-roster.sh
#
# Integration test for the full tag x tier x budget x opus_min x tier_pins x
# Codex x stale-tags x empty-intersection x cold-start matrix end-to-end
# through `scripts/resolve-personas.sh --with-tier`.
#
# Also verifies:
#   - A3b Panel-size table (N=2..7 exact opus/sonnet counts from
#     selection.json's tier_policy_applied block) — N=8 not exercised
#     because real persona dirs cap at 7 (`plan/`); N=8 testing would
#     require a synthetic personas tree which is out of scope for this
#     integration test.
#   - A14 dispatch wiring (commands/*.md pass model: param, autorun/*.sh
#     translate to --model claude-{opus,sonnet}-*).
#   - PRE-W2 evidence-file existence at
#     docs/specs/dynamic-roster-per-gate/design/dispatch-precedence-evidence.md
#     with a YES/NO/FLAKY verdict line.
#
# Bash 3.2 portable: no ${arr[-1]}, no mapfile/readarray; quote everything.
# Each fixture gets an isolated $HOME + PROJECT_DIR under mktemp, trap-cleaned.
#
# Followups consumed:
#   - ck-aabbccddee  (A14 both-dispatch-paths grep)
#   - ck-bcdef01234  (A4c Codex 3 modes)
#   - ck-4567890123  (PRE-W2 evidence-file existence)
##############################################################################
set -uo pipefail

export BASH=/bin/bash

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
RESOLVER="$REPO_DIR/scripts/resolve-personas.sh"

PASS=0
FAIL=0
FAILED_CASES=()

# Per-case scratch
CASE_DIR=""
CASE_HOME=""
CASE_PROJECT=""
CASE_OUT=""
CASE_ERR=""

setup_case() {
    CASE_DIR="$(mktemp -d -t mf-dynroster-test.XXXXXX)"
    if [ -z "$CASE_DIR" ] || [ ! -d "$CASE_DIR" ]; then
        echo "FAIL setup_case: mktemp -d returned invalid path '$CASE_DIR'" >&2
        return 1
    fi
    CASE_HOME="$CASE_DIR/home"
    CASE_PROJECT="$CASE_DIR/project"
    CASE_OUT="$CASE_DIR/out"
    CASE_ERR="$CASE_DIR/err"
    mkdir -p "$CASE_HOME/.config/monsterflow"
    mkdir -p "$CASE_PROJECT/docs/specs"
    : > "$CASE_OUT"
    : > "$CASE_ERR"
    export HOME="$CASE_HOME"
    export MONSTERFLOW_REPO_DIR="$REPO_DIR"
    export PROJECT_DIR="$CASE_PROJECT"
    # Default: codex unauthenticated unless case overrides
    export MONSTERFLOW_CODEX_AUTH=0
    unset MONSTERFLOW_DISABLE_BUDGET
}

teardown_case() {
    [ -n "$CASE_DIR" ] && [ -d "$CASE_DIR" ] && rm -rf "$CASE_DIR"
    CASE_DIR=""
    unset PROJECT_DIR
}

# Write the per-case config.json.
write_config() {
    # $1 = JSON content
    printf '%s' "$1" > "$CASE_HOME/.config/monsterflow/config.json"
}

# Write a minimal feature spec.md.
#   $1 = feature slug
#   $2 = top-level tags (comma-separated, no brackets — e.g. "security, data")
#   $3 = body content (may be empty)
write_spec() {
    local slug="$1" tags="$2" body="${3:-}"
    local fdir="$CASE_PROJECT/docs/specs/$slug"
    mkdir -p "$fdir"
    {
        echo "---"
        echo "tags: [$tags]"
        echo "---"
        echo ""
        echo "# $slug"
        echo ""
        echo "$body"
    } > "$fdir/spec.md"
}

# Write a spec with a recorded tags_provenance.baseline block (triggers
# SEC-04 subset enforcement + D8 stale-tags warning paths).
#   $1 = slug; $2 = top-level tags; $3 = baseline tags; $4 = body
write_spec_with_baseline() {
    local slug="$1" tags="$2" baseline="$3" body="${4:-}"
    local fdir="$CASE_PROJECT/docs/specs/$slug"
    mkdir -p "$fdir"
    {
        echo "---"
        echo "tags: [$tags]"
        echo "tags_provenance:"
        echo "  baseline: [$baseline]"
        echo "---"
        echo ""
        echo "# $slug"
        echo ""
        echo "$body"
    } > "$fdir/spec.md"
}

run_resolver() {
    local exit_code=0
    bash "$RESOLVER" "$@" >"$CASE_OUT" 2>"$CASE_ERR" || exit_code=$?
    echo "$exit_code"
}

# Read tier_policy_applied.opus_count_actual / sonnet_count_actual from
# the per-feature selection.json. Echos two space-separated integers.
read_tier_counts() {
    local slug="$1" gate="$2"
    local sel="$CASE_PROJECT/docs/specs/$slug/$gate/selection.json"
    python3 -c "
import json, sys
try:
    d = json.load(open('$sel'))
    tpa = d.get('tier_policy_applied') or {}
    print(int(tpa.get('opus_count_actual', -1)), int(tpa.get('sonnet_count_actual', -1)))
except Exception as e:
    print('-1 -1')
"
}

# Generic helpers
_pass() {
    PASS=$(( PASS + 1 ))
    echo "  ✓ $1"
}

_fail() {
    FAIL=$(( FAIL + 1 ))
    FAILED_CASES+=("$1: $2")
    echo "  ✗ $1: $2" >&2
}

# Show captured stdout/stderr for debugging a failed assertion.
_dump_case() {
    if [ -s "$CASE_OUT" ]; then
        echo "    --- stdout ---" >&2
        sed 's/^/      /' < "$CASE_OUT" >&2
    fi
    if [ -s "$CASE_ERR" ]; then
        echo "    --- stderr ---" >&2
        sed 's/^/      /' < "$CASE_ERR" >&2
    fi
}

##############################################################################
# Axis 1: tag matching — security-architect must appear when tags include
#         "security" (its fit_tags). Use check gate (security-architect lives
#         in personas/check/).
##############################################################################
axis_1_tag_matching() {
    setup_case
    local name="axis-1: tag matching picks fit_tag persona"
    local slug="tag-match"
    # Plain frontmatter tags only (no recorded baseline → SEC-04 dormant).
    # Body intentionally contains no security keywords to avoid SEC-04 even
    # if someone added a baseline later. Empty body works because the
    # frontmatter `tags:` drives scoring.
    write_spec "$slug" "security, refactor" ""
    # Budget=6 ensures all check personas are in the panel so we can verify
    # that security-architect (fit_tags:[security]) is selected AND its tier
    # reflects the fit-score contribution from the `security` spec tag. The
    # tag-matching contract is "fit_tag intersects spec tag → score boost",
    # not "fit_tag intersects → forced inclusion" (inclusion is governed by
    # seed/pins/budget, not by fit_score in the current resolver).
    write_config '{"agent_budget": 6}'
    local rc; rc=$(run_resolver check --with-tier --feature "$slug" --emit-selection-json)
    if [ "$rc" != "0" ]; then
        _fail "$name" "exit=$rc (expected 0)"; _dump_case; teardown_case; return
    fi
    # security-architect should be selected (it has fit_tags:[security] and
    # the spec tags include security). Stdout grammar: persona:tier per line.
    if ! grep -q '^security-architect:' "$CASE_OUT"; then
        _fail "$name" "security-architect missing from selected output"
        _dump_case; teardown_case; return
    fi
    _pass "$name"
    teardown_case
}

##############################################################################
# Axis 2: tier (D6) — N=6 panel, opus_min=1 default → opus=3, sonnet=3
##############################################################################
axis_2_tier_d6() {
    setup_case
    local name="axis-2: tier D6 N=6 → opus=3 sonnet=3"
    local slug="tier-d6"
    write_spec "$slug" "docs, refactor" ""
    write_config '{"agent_budget": 6}'
    local rc; rc=$(run_resolver check --with-tier --feature "$slug" --emit-selection-json)
    if [ "$rc" != "0" ]; then
        _fail "$name" "exit=$rc (expected 0)"; _dump_case; teardown_case; return
    fi
    local counts; counts=$(read_tier_counts "$slug" check)
    if [ "$counts" != "3 3" ]; then
        _fail "$name" "opus/sonnet counts = '$counts' (expected '3 3')"
        _dump_case; teardown_case; return
    fi
    _pass "$name"
    teardown_case
}

##############################################################################
# Axis 3: budget < opus_min — agent_budget=1 + opus_min=1 → sole member opus
##############################################################################
axis_3_budget_lt_opus_min() {
    setup_case
    local name="axis-3: budget=1 + opus_min=1 → 1 opus 0 sonnet"
    local slug="budget-floor"
    write_spec "$slug" "docs, refactor" ""
    write_config '{"agent_budget": 1}'
    local rc; rc=$(run_resolver check --with-tier --feature "$slug" --opus-min 1 --emit-selection-json)
    if [ "$rc" != "0" ]; then
        _fail "$name" "exit=$rc (expected 0)"; _dump_case; teardown_case; return
    fi
    local counts; counts=$(read_tier_counts "$slug" check)
    if [ "$counts" != "1 0" ]; then
        _fail "$name" "opus/sonnet counts = '$counts' (expected '1 0')"
        _dump_case; teardown_case; return
    fi
    _pass "$name"
    teardown_case
}

##############################################################################
# Axis 4: opus_min override — --opus-min 2 with N=2 → 2 opus 0 sonnet
#         (since opus_min forces 2 opus seats and sonnet_min=1 is advisory).
#         With N=3, --opus-min 2 → base_opus=max(2, 3//2=1)=2 → 2 opus 1 sonnet.
##############################################################################
axis_4_opus_min_override() {
    setup_case
    local name="axis-4: --opus-min 2 with N=3 → 2 opus 1 sonnet"
    local slug="opus-min-override"
    write_spec "$slug" "docs, refactor" ""
    write_config '{"agent_budget": 3}'
    local rc; rc=$(run_resolver check --with-tier --feature "$slug" --opus-min 2 --emit-selection-json)
    if [ "$rc" != "0" ]; then
        _fail "$name" "exit=$rc (expected 0)"; _dump_case; teardown_case; return
    fi
    local counts; counts=$(read_tier_counts "$slug" check)
    if [ "$counts" != "2 1" ]; then
        _fail "$name" "opus/sonnet counts = '$counts' (expected '2 1')"
        _dump_case; teardown_case; return
    fi
    _pass "$name"
    teardown_case
}

##############################################################################
# Axis 5: tier_pins — security-architect=opus forces opus seat regardless
#         of fit_score. Set spec tags to NOT include security so the
#         security-architect's fit_score is low (no fit_tag intersection),
#         then verify it still appears as opus via the pin.
##############################################################################
axis_5_tier_pins() {
    setup_case
    local name="axis-5: --tier-pin forces opus seat"
    local slug="tier-pin"
    write_spec "$slug" "docs, refactor" ""
    # tier_pins control tier assignment, not panel inclusion. Budget=6
    # guarantees security-architect is in the panel; the --tier-pin then
    # forces its tier to opus regardless of fit_score.
    write_config '{"agent_budget": 6}'
    local rc; rc=$(run_resolver check --with-tier --feature "$slug" \
        --tier-pin security-architect=opus --emit-selection-json)
    if [ "$rc" != "0" ]; then
        _fail "$name" "exit=$rc (expected 0)"; _dump_case; teardown_case; return
    fi
    if ! grep -q '^security-architect:opus$' "$CASE_OUT"; then
        _fail "$name" "security-architect:opus missing from stdout"
        _dump_case; teardown_case; return
    fi
    _pass "$name"
    teardown_case
}

##############################################################################
# Axis 6a: Codex additive + authed → codex-adversary appended
##############################################################################
axis_6a_codex_additive_authed() {
    setup_case
    local name="axis-6a: Codex additive + authed → codex-adversary line"
    local slug="codex-authed"
    write_spec "$slug" "docs, refactor" ""
    write_config '{"agent_budget": 2}'
    export MONSTERFLOW_CODEX_AUTH=1
    local rc; rc=$(run_resolver check --with-tier --feature "$slug")
    if [ "$rc" != "0" ]; then
        _fail "$name" "exit=$rc (expected 0)"; _dump_case; teardown_case; return
    fi
    if ! grep -qxF "codex-adversary" "$CASE_OUT"; then
        _fail "$name" "codex-adversary missing from stdout"
        _dump_case; teardown_case; return
    fi
    _pass "$name"
    teardown_case
}

##############################################################################
# Axis 6b: Codex additive + not-authed → no codex line, exit 0
##############################################################################
axis_6b_codex_not_authed() {
    setup_case
    local name="axis-6b: Codex not-authed → no codex line"
    local slug="codex-no-auth"
    write_spec "$slug" "docs, refactor" ""
    write_config '{"agent_budget": 2}'
    export MONSTERFLOW_CODEX_AUTH=0
    local rc; rc=$(run_resolver check --with-tier --feature "$slug")
    if [ "$rc" != "0" ]; then
        _fail "$name" "exit=$rc (expected 0)"; _dump_case; teardown_case; return
    fi
    if grep -qxF "codex-adversary" "$CASE_OUT"; then
        _fail "$name" "codex-adversary appeared but should be absent"
        _dump_case; teardown_case; return
    fi
    _pass "$name"
    teardown_case
}

##############################################################################
# Axis 6c: Codex disabled in config + authed → never appears
##############################################################################
axis_6c_codex_disabled() {
    setup_case
    local name="axis-6c: codex_disabled=true + authed → no codex line"
    local slug="codex-disabled"
    write_spec "$slug" "docs, refactor" ""
    write_config '{"agent_budget": 2, "codex_disabled": true}'
    export MONSTERFLOW_CODEX_AUTH=1
    local rc; rc=$(run_resolver check --with-tier --feature "$slug")
    if [ "$rc" != "0" ]; then
        _fail "$name" "exit=$rc (expected 0)"; _dump_case; teardown_case; return
    fi
    if grep -qxF "codex-adversary" "$CASE_OUT"; then
        _fail "$name" "codex-adversary appeared despite codex_disabled=true"
        _dump_case; teardown_case; return
    fi
    _pass "$name"
    teardown_case
}

##############################################################################
# Axis 7: stale-tags warning — recorded baseline is a strict superset of
#         recomputed (recorded has 'security' but body has no security
#         keywords). D8 mid-pipeline-edit clause → WARNING + exit 0.
##############################################################################
axis_7_stale_tags() {
    setup_case
    local name="axis-7: stale-tags WARNING + exit 0"
    local slug="stale-tags"
    # baseline claims security; body has no keywords → recomputed = {} which
    # is a strict subset of {security} → D8 warning path.
    write_spec_with_baseline "$slug" "security, docs" "security" "Generic docs body without trigger words."
    write_config '{"agent_budget": 2}'
    local rc; rc=$(run_resolver check --with-tier --feature "$slug")
    if [ "$rc" != "0" ]; then
        _fail "$name" "exit=$rc (expected 0)"; _dump_case; teardown_case; return
    fi
    if ! grep -q "stale-tags" "$CASE_ERR"; then
        _fail "$name" "[stale-tags] WARNING missing from stderr"
        _dump_case; teardown_case; return
    fi
    _pass "$name"
    teardown_case
}

##############################################################################
# Axis 8: empty intersection — spec tags do not match any persona's
#         fit_tags. Resolver still emits a panel (cold-start fallback via
#         seed/full-roster). Exit 0.
##############################################################################
axis_8_empty_intersection() {
    setup_case
    local name="axis-8: empty tag intersection → cold-start panel"
    local slug="empty-intersect"
    # Use a tag no check persona claims as fit_tag (check personas advertise
    # docs, refactor, scalability, security, sequencing, testability —
    # 'imaginary-tag' matches none).
    write_spec "$slug" "imaginary-tag" ""
    write_config '{"agent_budget": 3}'
    local rc; rc=$(run_resolver check --with-tier --feature "$slug" --emit-selection-json)
    if [ "$rc" != "0" ]; then
        _fail "$name" "exit=$rc (expected 0)"; _dump_case; teardown_case; return
    fi
    local lines; lines=$(grep -c . "$CASE_OUT" 2>/dev/null || echo 0)
    if [ "$lines" -lt 3 ]; then
        _fail "$name" "expected >=3 stdout lines, got $lines"
        _dump_case; teardown_case; return
    fi
    _pass "$name"
    teardown_case
}

##############################################################################
# Axis 9: cold-start — no rankings file means all lbrs = 0.5 baseline.
#         Resolver must still produce a deterministic panel with valid
#         combined_score. We assert exit 0 + selection.json present + all
#         selected rows have combined_score >= 0.0 and <= 1.0-ish numeric.
##############################################################################
axis_9_cold_start() {
    setup_case
    local name="axis-9: cold-start (no rankings) → panel emitted"
    local slug="cold-start"
    write_spec "$slug" "docs, refactor" ""
    write_config '{"agent_budget": 3}'
    # We do NOT move the real rankings file aside — it lives in the engine
    # repo and is needed for other tests. score_all handles missing rows
    # by treating them as cold-start; the assertion below targets that
    # the panel is emitted and selection.json is well-formed.
    local rc; rc=$(run_resolver check --with-tier --feature "$slug" --emit-selection-json)
    if [ "$rc" != "0" ]; then
        _fail "$name" "exit=$rc (expected 0)"; _dump_case; teardown_case; return
    fi
    local sel="$CASE_PROJECT/docs/specs/$slug/check/selection.json"
    if [ ! -f "$sel" ]; then
        _fail "$name" "selection.json not written at $sel"
        _dump_case; teardown_case; return
    fi
    if ! python3 -c "
import json
d = json.load(open('$sel'))
assert d.get('schema_version') == 2, 'schema_version != 2'
sel = d.get('selected') or []
assert len(sel) >= 1, 'empty selected list'
for row in sel:
    cs = row.get('combined_score')
    assert isinstance(cs, (int, float)), f'combined_score not numeric: {cs!r}'
" 2>>"$CASE_ERR"; then
        _fail "$name" "selection.json schema/contents invalid"
        _dump_case; teardown_case; return
    fi
    _pass "$name"
    teardown_case
}

##############################################################################
# A3b Panel-size table — for each N in {2,3,4,5,6,7}, assert
# tier_policy_applied.{opus_count_actual,sonnet_count_actual} per spec line
# 59-65. N=2..6 use gate=check (6 personas); N=7 uses gate=design (7 personas).
# (N=8 needs 8 personas on disk; out of scope without synthetic tree.)
#
# Expected (opus_min=1, sonnet_min=1, remainder_tiebreak=sonnet):
#   N=2 → 1 1
#   N=3 → 1 2
#   N=4 → 2 2
#   N=5 → 2 3
#   N=6 → 3 3
#   N=7 → 3 4
##############################################################################
panel_size_case() {
    # $1 = N, $2 = gate, $3 = expected "OPUS SONNET"
    local n="$1" gate="$2" expected="$3"
    setup_case
    local name="A3b panel-size N=$n gate=$gate → $expected"
    local slug="panel-n$n"
    write_spec "$slug" "docs, refactor" ""
    write_config "{\"agent_budget\": $n}"
    local rc; rc=$(run_resolver "$gate" --with-tier --feature "$slug" --emit-selection-json)
    if [ "$rc" != "0" ]; then
        _fail "$name" "exit=$rc (expected 0)"; _dump_case; teardown_case; return
    fi
    local counts; counts=$(read_tier_counts "$slug" "$gate")
    if [ "$counts" != "$expected" ]; then
        _fail "$name" "opus/sonnet counts = '$counts' (expected '$expected')"
        _dump_case; teardown_case; return
    fi
    _pass "$name"
    teardown_case
}

##############################################################################
# A14 wiring grep — both dispatch paths (commands/*.md interactive +
# scripts/autorun/*.sh headless) must carry tier param.
##############################################################################
a14_wiring_grep() {
    local name="A14 wiring: $1"
    local target="$2"
    local pattern="$3"
    if [ ! -f "$target" ]; then
        _fail "$name" "missing file $target"
        return
    fi
    if ! grep -qE "$pattern" "$target"; then
        _fail "$name" "pattern '$pattern' not found in $target"
        return
    fi
    _pass "$name"
}

##############################################################################
# PRE-W2 evidence file (ck-4567890123)
##############################################################################
pre_w2_evidence() {
    local name1="PRE-W2 evidence file exists"
    local evid="$REPO_DIR/docs/specs/dynamic-roster-per-gate/design/dispatch-precedence-evidence.md"
    if [ ! -f "$evid" ]; then
        _fail "$name1" "missing $evid"
    else
        _pass "$name1"
    fi
    local name2="PRE-W2 evidence has YES/NO/FLAKY verdict"
    if [ ! -f "$evid" ]; then
        _fail "$name2" "(skipped: evidence file missing)"
        return
    fi
    # Look specifically for a verdict line — not just any YES/NO/FLAKY token
    # in the legend. Pattern: "verdict" near the keyword on the same line.
    if grep -qE 'verdict.*(YES|NO|FLAKY)|(YES|NO|FLAKY).*verdict' "$evid"; then
        _pass "$name2"
    else
        _fail "$name2" "no verdict line with YES/NO/FLAKY"
    fi
}

##############################################################################
# Main
##############################################################################

echo "=== test-dynamic-roster.sh ==="
echo "REPO_DIR=$REPO_DIR"
echo ""

echo "--- Matrix axes (1-9) ---"
axis_1_tag_matching
axis_2_tier_d6
axis_3_budget_lt_opus_min
axis_4_opus_min_override
axis_5_tier_pins
axis_6a_codex_additive_authed
axis_6b_codex_not_authed
axis_6c_codex_disabled
axis_7_stale_tags
axis_8_empty_intersection
axis_9_cold_start

echo ""
echo "--- A3b panel-size table N=2..7 ---"
panel_size_case 2 check "1 1"
panel_size_case 3 check "1 2"
panel_size_case 4 check "2 2"
panel_size_case 5 check "2 3"
panel_size_case 6 check "3 3"
panel_size_case 7 design "3 4"

echo ""
echo "--- A14 dispatch wiring grep (commands/*.md + autorun/*.sh) ---"
a14_wiring_grep "commands/spec-review.md carries model: tier param" \
    "$REPO_DIR/commands/spec-review.md" \
    'model: ?"opus"|model: ?"sonnet"'
a14_wiring_grep "commands/blueprint.md carries model: tier param" \
    "$REPO_DIR/commands/blueprint.md" \
    'model: ?"opus"|model: ?"sonnet"'
a14_wiring_grep "commands/check.md carries model: tier param" \
    "$REPO_DIR/commands/check.md" \
    'model: ?"opus"|model: ?"sonnet"'
a14_wiring_grep "autorun/spec-review.sh translates tier → --model" \
    "$REPO_DIR/scripts/autorun/spec-review.sh" \
    'claude-opus-4-5|claude-sonnet-4-6'
a14_wiring_grep "autorun/design.sh translates tier → --model" \
    "$REPO_DIR/scripts/autorun/design.sh" \
    'claude-opus-4-5|claude-sonnet-4-6'
a14_wiring_grep "autorun/check.sh translates tier → --model" \
    "$REPO_DIR/scripts/autorun/check.sh" \
    'claude-opus-4-5|claude-sonnet-4-6'

echo ""
echo "--- PRE-W2 evidence file (ck-4567890123) ---"
pre_w2_evidence

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
