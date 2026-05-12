#!/bin/bash
# test-build-followups-consumer.sh
#
# Asserts that commands/build.md correctly wires the wave-1 followups consumer
# (Phase 0c) and the wave-final mark-addressed step (Phase 4) per
# docs/specs/pipeline-gate-permissiveness/plan.md task W3.8.
#
# Bash 3.2 compatible (macOS default).

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_MD="$REPO_ROOT/commands/build.md"

PASS=0
FAIL=0
FAILED_TESTS=""

assert_contains() {
    local label="$1"
    local needle="$2"
    if grep -qF -- "$needle" "$BUILD_MD"; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS="$FAILED_TESTS\n    - $label (missing: $needle)"
        echo "  FAIL: $label (missing: $needle)"
    fi
}

assert_not_contains() {
    local label="$1"
    local needle="$2"
    if grep -qF -- "$needle" "$BUILD_MD"; then
        FAIL=$((FAIL + 1))
        FAILED_TESTS="$FAILED_TESTS\n    - $label (unexpected: $needle)"
        echo "  FAIL: $label (unexpected presence of: $needle)"
    else
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    fi
}

assert_either() {
    local label="$1"
    local needle_a="$2"
    local needle_b="$3"
    if grep -qF -- "$needle_a" "$BUILD_MD" || grep -qF -- "$needle_b" "$BUILD_MD"; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS="$FAILED_TESTS\n    - $label (neither '$needle_a' nor '$needle_b' found)"
        echo "  FAIL: $label (neither '$needle_a' nor '$needle_b' found)"
    fi
}

echo "=== test-build-followups-consumer ==="

if [ ! -f "$BUILD_MD" ]; then
    echo "FATAL: $BUILD_MD not found"
    exit 1
fi

# 1. Phase 0c heading present
assert_contains "Phase 0c heading present" "Phase 0c: Verdict-Gated Followups Consumption"

# 2. Hardcoded check-verdict.json path
assert_contains "check-verdict.json path referenced" "check-verdict.json"

# 3. Legacy-detection ladder keywords (require at least 3 of 4)
echo "  Legacy ladder (need 3 of 4):"
LADDER_HITS=0
for kw in "Missing sidecar" "Malformed JSON" "v1 sidecar" "v2 sidecar"; do
    if grep -qF -- "$kw" "$BUILD_MD"; then
        LADDER_HITS=$((LADDER_HITS + 1))
        echo "    found: $kw"
    fi
done
if [ "$LADDER_HITS" -ge 3 ]; then
    PASS=$((PASS + 1))
    echo "  PASS: Legacy-detection ladder ($LADDER_HITS of 4 keywords)"
else
    FAIL=$((FAIL + 1))
    FAILED_TESTS="$FAILED_TESTS\n    - Legacy-detection ladder (only $LADDER_HITS of 4 keywords)"
    echo "  FAIL: Legacy-detection ladder (only $LADDER_HITS of 4 keywords)"
fi

# 4. state: open filter
assert_either "state: open filter present" 'state: open' 'state: "open"'

# 5. build-inline AND docs-only routing
assert_contains "build-inline target_phase" "build-inline"
assert_contains "docs-only target_phase" "docs-only"

# 6. plan-revision routing AND /design re-run abort
# (was "/plan re-run" before the 2026-05-12 cede-/plan-back-to-Claude-Code
# rename; the build error message now uses /design so adopters know to
# invoke MonsterFlow's design gate, not Claude Code's plan-mode.)
assert_contains "plan-revision target_phase" "plan-revision"
assert_contains "/design re-run abort message" "/design re-run"

# 7. Phase 4 + build-mark-addressed.py wiring
assert_contains "Phase 4 heading present" "Phase 4"
assert_contains "build-mark-addressed.py invocation" "build-mark-addressed.py"

# 8. Out-of-scope sidecars NOT consumed by build
assert_not_contains "spec-review-verdict.json not consumed by build" "spec-review-verdict.json"
assert_not_contains "plan-verdict.json not consumed by build" "plan-verdict.json"

# 9. pre-v0.9.0 backcompat acknowledged
assert_contains "pre-v0.9.0 backcompat acknowledged" "pre-v0.9.0"

echo ""
echo "=== RESULTS ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "Failures:"
    printf "$FAILED_TESTS\n"
    exit 1
fi

exit 0
