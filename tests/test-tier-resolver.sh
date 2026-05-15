#!/bin/bash
##############################################################################
# tests/test-tier-resolver.sh
#
# Focused unit tests for scripts/_tier_assign.py (Slice 3) and the resolver's
# --with-tier / --tier-pin SEC-01 enforcement (D7).
#
# Coverage (dynamic-roster-per-gate Slice 5 task 18):
#   - Panel-size table N=2..8 (D6 base_opus = max(opus_min, floor(N/2)))
#   - fit_score invariant (ck-3344556677): == |spec_tags ∩ persona_fit_tags|
#   - SEC-01 spec-level tier_pins rejection (validate_tier_pins exit 4)
#   - SEC-01 CLI tier-pin rejection (D7 second enforcement site)
#   - --tier-pin accumulation (ck-ff00112233): 3-pin batch idempotent
#   - Tier-pin promotion drops lowest combined_score non-pinned non-security
#   - Alphabetical tiebreak on equal combined_score
#
# Bash 3.2 portable (no ${array[-1]}, pin BASH=/bin/bash).
##############################################################################
set -uo pipefail

export BASH=/bin/bash

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
RESOLVER="$REPO_DIR/scripts/resolve-personas.sh"
TIER_PY="$REPO_DIR/scripts/_tier_assign.py"

PASS=0
FAIL=0
FAILED_CASES=()

# Per-case scratch
CASE_DIR=""
CASE_HOME=""
CASE_OUT=""
CASE_ERR=""

setup_case() {
    CASE_DIR="$(mktemp -d -t mf-tier-test.XXXXXX)"
    if [ -z "$CASE_DIR" ] || [ ! -d "$CASE_DIR" ]; then
        echo "FAIL setup_case: mktemp -d returned invalid path '$CASE_DIR'" >&2
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
    export MONSTERFLOW_CODEX_AUTH=0
    unset MONSTERFLOW_DISABLE_BUDGET
    unset PROJECT_DIR
}

teardown_case() {
    [ -n "$CASE_DIR" ] && [ -d "$CASE_DIR" ] && rm -rf "$CASE_DIR"
    CASE_DIR=""
}

record_fail() {
    # $1 = case name, $2 = reason
    FAIL=$(( FAIL + 1 ))
    FAILED_CASES+=("$1: $2")
    echo "    ✗ $2" >&2
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
# Helper — build a JSON payload for N personas with given scores; pipe to
# _tier_assign.py and echo "<opus_count> <sonnet_count>" to stdout.
##############################################################################
tier_counts() {
    # $1 = N (2..8), $2 = opus_min, $3 = sonnet_min
    local n="$1" opus_min="$2" sonnet_min="$3"
    python3 - "$n" "$opus_min" "$sonnet_min" "$TIER_PY" <<'PY'
import sys, json, subprocess
n = int(sys.argv[1]); opus_min = int(sys.argv[2]); sonnet_min = int(sys.argv[3])
tier_py = sys.argv[4]
# Build N rows with distinct combined_scores (descending) so ordering is
# deterministic. Persona slugs p01..pNN keep alphabetical sort stable.
scored = []
for i in range(n):
    scored.append({
        "persona": f"p{i:02d}",
        "fit_score": 1,
        "combined_score": float(n - i),  # p00=highest
    })
payload = {
    "scored": scored,
    "opus_min": opus_min,
    "sonnet_min": sonnet_min,
    "remainder_tiebreak": "sonnet",
    "tier_pins": {},
}
r = subprocess.run(
    ["python3", tier_py],
    input=json.dumps(payload).encode(),
    capture_output=True,
)
if r.returncode != 0:
    sys.stderr.write(r.stderr.decode())
    sys.exit(r.returncode)
out = json.loads(r.stdout.decode())
opus = sum(1 for row in out if row["tier"] == "opus")
sonnet = sum(1 for row in out if row["tier"] == "sonnet")
print(f"{opus} {sonnet}")
PY
}

##############################################################################
# Cases
##############################################################################

# Panel-size table: N → (opus, sonnet) with opus_min=1, sonnet_min=1.
# Per D6: base_opus = max(1, floor(N/2))
expected_for_n() {
    # echoes "<opus> <sonnet>" for N in 2..8
    case "$1" in
        2) echo "1 1" ;;
        3) echo "1 2" ;;
        4) echo "2 2" ;;
        5) echo "2 3" ;;
        6) echo "3 3" ;;
        7) echo "3 4" ;;
        8) echo "4 4" ;;
    esac
}

case_panel_n() {
    # $1 = N
    local n="$1"
    setup_case
    local name="panel size N=$n (opus_min=1)"
    local expected actual status=ok
    expected="$(expected_for_n "$n")"
    actual="$(tier_counts "$n" 1 1 2>"$CASE_ERR" || true)"
    if [ "$actual" != "$expected" ]; then
        record_fail "$name" "got '$actual' expected '$expected'"
        if [ -s "$CASE_ERR" ]; then
            sed 's/^/      /' < "$CASE_ERR" >&2
        fi
        status=fail
    fi
    case_done "$name" "$status"
}

_run_fit_score_row() {
    # $1 = case name
    # $2 = persona_fit_tags JSON list
    # $3 = spec_tags JSON list
    # $4 = expected fit_score
    # $5 = expected combined_score (lbr fixed at 0.6 in payload)
    local name="$1" pft="$2" stags="$3" exp_fit="$4" exp_comb="$5"
    setup_case
    local status=ok
    if ! MF_PFT="$pft" MF_STAGS="$stags" MF_EXP_FIT="$exp_fit" MF_EXP_COMB="$exp_comb" \
        python3 - <<'PY' 2>"$CASE_ERR"
import os, sys, json
sys.path.insert(0, os.environ["MONSTERFLOW_REPO_DIR"] + "/scripts")
from _persona_score import score_persona

pft = json.loads(os.environ["MF_PFT"])
stags = json.loads(os.environ["MF_STAGS"])
exp_fit = int(os.environ["MF_EXP_FIT"])
exp_comb = float(os.environ["MF_EXP_COMB"])
r = score_persona("persona-x", pft, stags, 0.6)
assert r["fit_score"] == exp_fit, (r, exp_fit)
assert abs(r["combined_score"] - exp_comb) < 1e-9, (r, exp_comb)
PY
    then
        record_fail "$name" "fit_score assertion failed"
        if [ -s "$CASE_ERR" ]; then
            sed 's/^/      /' < "$CASE_ERR" >&2
        fi
        status=fail
    fi
    case_done "$name" "$status"
}

case_fit_score_partial() {
    _run_fit_score_row \
        "fit_score=2 partial overlap (ck-3344556677)" \
        '["security","api"]' \
        '["security","data","api"]' \
        2 1.2
}

case_fit_score_disjoint() {
    _run_fit_score_row \
        "fit_score=0 disjoint (ck-3344556677)" \
        '["ux","docs"]' \
        '["security"]' \
        0 0.0
}

case_fit_score_full() {
    _run_fit_score_row \
        "fit_score=2 full overlap (ck-3344556677)" \
        '["security","data"]' \
        '["security","data"]' \
        2 1.2
}

case_sec01_validate_helper() {
    setup_case
    local name="SEC-01 spec-level pin: validate_tier_pins → exit 4"
    local status=ok
    if ! python3 - <<'PY' 2>"$CASE_ERR"
import sys
sys.path.insert(0, __import__("os").environ["MONSTERFLOW_REPO_DIR"] + "/scripts")
from _tier_assign import validate_tier_pins

# Nested {gate: {persona: tier}} shape — spec-level form (D7 site 1).
registry = {"security-architect": ["security"], "scope-discipline": []}
rc = validate_tier_pins(
    {"check": {"security-architect": "sonnet"}},
    persona_registry=registry,
    security_floor="opus",
)
assert rc == 4, f"expected 4, got {rc}"
print("OK")
PY
    then
        record_fail "$name" "validate_tier_pins did not return 4"
        if [ -s "$CASE_ERR" ]; then
            sed 's/^/      /' < "$CASE_ERR" >&2
        fi
        status=fail
    fi
    case_done "$name" "$status"
}

# Build a minimal fixture spec at docs/specs/<slug>/spec.md inside the repo
# (because --with-tier reads feature_dir = repo_dir/docs/specs/<slug>).
# Use a slug guaranteed not to collide.
write_fixture_spec() {
    # $1 = slug
    local slug="$1"
    local fdir="$REPO_DIR/docs/specs/$slug"
    mkdir -p "$fdir"
    cat > "$fdir/spec.md" <<'EOF'
---
slug: tier-resolver-test-fixture
tags: [security]
tags_provenance:
  baseline: [security]
---

# Test Fixture

Minimal spec for tier-resolver unit tests. References auth and tokens so the
recomputed baseline matches the recorded `[security]` baseline (SEC-04 safe).
EOF
    echo "$fdir"
}

case_sec01_cli_tier_pin() {
    setup_case
    local name="SEC-01 CLI: --tier-pin security-architect=sonnet → exit 4"
    local slug="tier-resolver-sec01-$$"
    local fdir; fdir="$(write_fixture_spec "$slug")"
    local exit_code=0
    bash "$RESOLVER" check --feature "$slug" --with-tier \
        --tier-pin security-architect=sonnet \
        >"$CASE_OUT" 2>"$CASE_ERR" || exit_code=$?
    local status=ok
    rm -rf "$fdir"
    if [ "$exit_code" != "4" ]; then
        record_fail "$name" "expected exit 4, got $exit_code"
        sed 's/^/      stderr: /' < "$CASE_ERR" >&2
        status=fail
    fi
    if ! grep -q "SEC-01" "$CASE_ERR" 2>/dev/null; then
        record_fail "$name" "stderr missing 'SEC-01' marker"
        status=fail
    fi
    case_done "$name" "$status"
}

# Helper: extract opus-tier persona slugs from resolver stdout. Output rows
# are `<persona>:<tier>` (codex line is bare; ignored here).
opus_personas_from_out() {
    grep ':opus$' "$CASE_OUT" 2>/dev/null | sed 's/:opus$//' | sort
}

case_tier_pin_accumulation() {
    setup_case
    local name="--tier-pin accumulation (3-pin batch idempotent, ck-ff00112233)"
    local slug="tier-resolver-accum-$$"
    local fdir; fdir="$(write_fixture_spec "$slug")"
    # Force budget so the panel is large enough to include the three personas.
    printf '%s' '{"agent_budget": 6}' > "$CASE_HOME/.config/monsterflow/config.json"

    # Pin three personas that exist in personas/check/ on disk. Order #1.
    local run1_exit=0 run2_exit=0
    bash "$RESOLVER" check --feature "$slug" --with-tier \
        --tier-pin completeness=opus \
        --tier-pin risk=opus \
        --tier-pin testability=opus \
        >"$CASE_OUT" 2>"$CASE_ERR" || run1_exit=$?
    local opus_run1; opus_run1="$(opus_personas_from_out)"

    # Reorder pins — output should be identical.
    : > "$CASE_OUT"
    : > "$CASE_ERR"
    bash "$RESOLVER" check --feature "$slug" --with-tier \
        --tier-pin testability=opus \
        --tier-pin completeness=opus \
        --tier-pin risk=opus \
        >"$CASE_OUT" 2>"$CASE_ERR" || run2_exit=$?
    local opus_run2; opus_run2="$(opus_personas_from_out)"

    rm -rf "$fdir"
    local status=ok
    if [ "$run1_exit" != "0" ]; then
        record_fail "$name" "run1 exit=$run1_exit"
        status=fail
    fi
    if [ "$run2_exit" != "0" ]; then
        record_fail "$name" "run2 exit=$run2_exit"
        status=fail
    fi
    # All three pinned personas present in run1 opus output?
    for slug_name in completeness risk testability; do
        if ! printf '%s\n' "$opus_run1" | grep -qx "$slug_name"; then
            record_fail "$name" "run1 missing '$slug_name' in opus tier"
            status=fail
        fi
    done
    # Reorder idempotent: run1 == run2.
    if [ "$opus_run1" != "$opus_run2" ]; then
        record_fail "$name" "reorder not idempotent: run1='$opus_run1' run2='$opus_run2'"
        status=fail
    fi
    case_done "$name" "$status"
}

case_tier_pin_promotion_drops_lowest() {
    setup_case
    local name="tier-pin promotion drops lowest non-pinned non-security"
    local status=ok
    # Direct _tier_assign.py call with 4 personas, scores [3,2,1,0].
    # Without pins: top-2 → opus (N=4, base_opus=max(1, 2)=2).
    # Pin "delta" (score 0) → opus. Expected: opus = {alpha(3), delta(0)};
    # the formerly-2nd-place "bravo"(2) drops to sonnet.
    if ! python3 - <<'PY' 2>"$CASE_ERR"
import sys, json, subprocess, os
tier_py = os.environ["MONSTERFLOW_REPO_DIR"] + "/scripts/_tier_assign.py"

scored = [
    {"persona": "alpha",   "fit_score": 1, "combined_score": 3.0},
    {"persona": "bravo",   "fit_score": 1, "combined_score": 2.0},
    {"persona": "charlie", "fit_score": 1, "combined_score": 1.0},
    {"persona": "delta",   "fit_score": 1, "combined_score": 0.0},
]
payload = {
    "scored": scored,
    "opus_min": 1,
    "sonnet_min": 1,
    "remainder_tiebreak": "sonnet",
    "tier_pins": {"delta": "opus"},
}
r = subprocess.run(["python3", tier_py],
                   input=json.dumps(payload).encode(), capture_output=True)
assert r.returncode == 0, r.stderr.decode()
rows = json.loads(r.stdout.decode())
tiers = {row["persona"]: row["tier"] for row in rows}
assert tiers["alpha"] == "opus", tiers
assert tiers["delta"] == "opus", tiers
assert tiers["bravo"] == "sonnet", tiers   # demoted!
assert tiers["charlie"] == "sonnet", tiers
print("OK")
PY
    then
        record_fail "$name" "promotion-drop assertion failed"
        if [ -s "$CASE_ERR" ]; then
            sed 's/^/      /' < "$CASE_ERR" >&2
        fi
        status=fail
    fi
    case_done "$name" "$status"
}

case_alphabetical_tiebreak() {
    setup_case
    local name="alphabetical tiebreak on equal combined_score"
    local status=ok
    if ! python3 - <<'PY' 2>"$CASE_ERR"
import sys, json, subprocess, os
tier_py = os.environ["MONSTERFLOW_REPO_DIR"] + "/scripts/_tier_assign.py"

# N=2, both scores 0.5; alpha < zeta alphabetically → alpha gets opus.
scored = [
    {"persona": "alpha", "fit_score": 1, "combined_score": 0.5},
    {"persona": "zeta",  "fit_score": 1, "combined_score": 0.5},
]
payload = {"scored": scored, "opus_min": 1, "sonnet_min": 1,
           "remainder_tiebreak": "sonnet", "tier_pins": {}}
r = subprocess.run(["python3", tier_py],
                   input=json.dumps(payload).encode(), capture_output=True)
assert r.returncode == 0, r.stderr.decode()
rows = json.loads(r.stdout.decode())
tiers = {row["persona"]: row["tier"] for row in rows}
assert tiers["alpha"] == "opus", tiers
assert tiers["zeta"] == "sonnet", tiers
print("OK")
PY
    then
        record_fail "$name" "alphabetical tiebreak assertion failed"
        if [ -s "$CASE_ERR" ]; then
            sed 's/^/      /' < "$CASE_ERR" >&2
        fi
        status=fail
    fi
    case_done "$name" "$status"
}

##############################################################################
# Main
##############################################################################

echo "=== test-tier-resolver.sh ==="
echo "REPO_DIR=$REPO_DIR"
echo ""

# Panel-size table (7 cases)
case_panel_n 2
case_panel_n 3
case_panel_n 4
case_panel_n 5
case_panel_n 6
case_panel_n 7
case_panel_n 8

# fit_score invariant (3 cases — ck-3344556677)
case_fit_score_partial
case_fit_score_disjoint
case_fit_score_full

# SEC-01 helper
case_sec01_validate_helper

# SEC-01 CLI
case_sec01_cli_tier_pin

# Pin accumulation + idempotent
case_tier_pin_accumulation

# Promotion drops lowest
case_tier_pin_promotion_drops_lowest

# Alphabetical tiebreak
case_alphabetical_tiebreak

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
