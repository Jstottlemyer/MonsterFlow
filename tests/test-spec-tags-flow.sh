#!/bin/bash
##############################################################################
# tests/test-spec-tags-flow.sh
#
# Contract test for /spec Phase 3 tag-inference flow.
#
# This is a documentation/contract test — it does NOT run an actual /spec
# session (no LLM call). Instead it greps commands/spec.md for the documented
# Phase 3 sub-steps + verifies SEC-02 baseline-not-removable via direct call
# to scripts/_tag_baseline.py.compute_baseline().
#
# Plan: docs/specs/dynamic-roster-per-gate/plan.md task 19 (Slice 5 Wave 5a).
# Source of truth: commands/spec.md Phase 3 (extended in Slice 4 task 8).
# ACs: A12 (Phase 3 wiring), A22 (SEC-02 baseline-not-removable).
#
# This test is intentionally brittle to commands/spec.md prose changes:
# Phase 3 is a stable contract and prose drift should be caught here before
# silently breaking the tag-inference flow.
#
# Bash 3.2 portable (memory: feedback_negative_array_subscript_bash32).
##############################################################################
set -uo pipefail

export BASH=/bin/bash

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
SPEC_MD="$REPO_DIR/commands/spec.md"
TAG_BASELINE_PY="$REPO_DIR/scripts/_tag_baseline.py"

PASS=0
FAIL=0
FAILED_CASES=()

_fail() {
    # $1 = case name, $2 = reason
    FAIL=$(( FAIL + 1 ))
    FAILED_CASES+=("$1: $2")
    echo "  ✗ $1" >&2
    echo "    reason: $2" >&2
}

_pass() {
    PASS=$(( PASS + 1 ))
    echo "  ✓ $1"
}

##############################################################################
# Preflight
##############################################################################
echo "=== test-spec-tags-flow.sh ==="
echo "REPO_DIR=$REPO_DIR"
echo ""

if [ ! -f "$SPEC_MD" ]; then
    echo "FATAL: commands/spec.md not found at $SPEC_MD" >&2
    exit 2
fi
if [ ! -f "$TAG_BASELINE_PY" ]; then
    echo "FATAL: scripts/_tag_baseline.py not found at $TAG_BASELINE_PY" >&2
    exit 2
fi

##############################################################################
# Case 1: Phase 3 includes a tag-inference step
##############################################################################
case_1_tag_inference_step_present() {
    local name="1: Phase 3 references tag inference"
    if grep -qi 'tag.*infer\|infer.*tag\|baseline.*tag\|_tag_baseline' "$SPEC_MD"; then
        _pass "$name"
    else
        _fail "$name" "Phase 3 missing tag-inference step"
    fi
}

##############################################################################
# Case 2: User-confirm prompt assembled correctly
##############################################################################
case_2_user_confirm_prompt() {
    local name="2: user-confirm prompt present"
    local missing=""
    grep -qE 'Tags: \[.*\*' "$SPEC_MD" || missing="$missing 'Tags: [...*'"
    grep -qE 'Enter to accept' "$SPEC_MD" || missing="$missing 'Enter to accept'"
    grep -qE 'type list to override|override' "$SPEC_MD" || missing="$missing 'override'"
    grep -qE 'empty to skip|skip' "$SPEC_MD" || missing="$missing 'empty to skip'"
    if [ -z "$missing" ]; then
        _pass "$name"
    else
        _fail "$name" "Phase 3 user-confirm prompt missing pieces:$missing"
    fi
}

##############################################################################
# Case 3: Baseline-locked rejection message present
##############################################################################
case_3_baseline_locked_rejection() {
    local name="3: baseline-locked rejection message"
    if grep -qE '\[security\] is baseline-detected and cannot be removed|baseline-locked|baseline.*cannot be removed' "$SPEC_MD"; then
        _pass "$name"
    else
        _fail "$name" "Phase 3 baseline-locked rejection message missing"
    fi
}

##############################################################################
# Case 4: AUTORUN auto-accept branch
##############################################################################
case_4_autorun_branch() {
    local name="4: AUTORUN=1 auto-accept branch"
    if grep -qE 'AUTORUN=1.*auto.accept|auto.accept.*AUTORUN' "$SPEC_MD"; then
        _pass "$name"
    else
        _fail "$name" "Phase 3 AUTORUN auto-accept branch missing"
    fi
}

##############################################################################
# Case 5: Provenance frontmatter shape
##############################################################################
case_5_provenance_frontmatter() {
    local name="5: tags_provenance frontmatter shape"
    local missing=""
    grep -qE 'tags_provenance' "$SPEC_MD" || missing="$missing 'tags_provenance'"
    grep -qE 'baseline:.*\[' "$SPEC_MD" || missing="$missing 'baseline: [...'"
    grep -qE 'llm.added|llm_added' "$SPEC_MD" || missing="$missing 'llm_added'"
    if [ -z "$missing" ]; then
        _pass "$name"
    else
        _fail "$name" "Phase 3 provenance fields missing:$missing"
    fi
}

##############################################################################
# Case 6: Grandfathered-spec offer
##############################################################################
case_6_grandfathered_offer() {
    local name="6: grandfathered-spec offer present"
    # case-insensitive: prose uses capitalized "Grandfathered"
    if grep -qiE 'grandfather|grandfathered' "$SPEC_MD"; then
        _pass "$name"
    else
        _fail "$name" "Phase 3 missing grandfathered-spec offer"
    fi
}

##############################################################################
# Case 7: Closed-enum citation (10 values per v1.1)
##############################################################################
case_7_closed_enum_citation() {
    local name="7: closed 10-value enum cited"
    if grep -qE 'tag-enum\.schema\.json|api.*data.*docs.*integration.*migration.*pipeline.*refactor.*scalability.*security.*ux' "$SPEC_MD"; then
        _pass "$name"
    else
        _fail "$name" "Phase 3 doesn't cite the closed 10-value enum"
    fi
}

##############################################################################
# Case 8: SEC-02 adversarial fixture — baseline includes security from oauth/rbac/auth
##############################################################################
case_8_sec02_baseline_floor() {
    local name="8: SEC-02 baseline floor (oauth/rbac → security)"
    local out
    out=$(cd "$REPO_DIR" && python3 - <<'PY' 2>&1
import sys
sys.path.insert(0, 'scripts')
from _tag_baseline import compute_baseline
text = "# Spec\nThis flow uses oauth tokens and rbac permissions for auth checks."
bl = compute_baseline(text)
assert 'security' in bl, f"SEC-02 baseline missed security: {sorted(bl)}"
print('OK')
PY
)
    if [ "$out" = "OK" ]; then
        _pass "$name"
    else
        _fail "$name" "SEC-02 fixture failed: $out"
    fi
}

##############################################################################
# Case 9: Cannot manually remove baseline tag (text-level invariant)
##############################################################################
case_9_cannot_manually_remove() {
    local name="9: 'cannot manually remove baseline' invariant"
    if grep -qiE 'cannot.*manually.*remove|cannot.*remove.*baseline|edit spec content|baseline.*re.trigger' "$SPEC_MD"; then
        _pass "$name"
    else
        _fail "$name" "Phase 3 missing 'cannot manually remove baseline' invariant"
    fi
}

##############################################################################
# Run all cases
##############################################################################
case_1_tag_inference_step_present
case_2_user_confirm_prompt
case_3_baseline_locked_rejection
case_4_autorun_branch
case_5_provenance_frontmatter
case_6_grandfathered_offer
case_7_closed_enum_citation
case_8_sec02_baseline_floor
case_9_cannot_manually_remove

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
