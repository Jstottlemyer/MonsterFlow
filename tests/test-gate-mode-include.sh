#!/usr/bin/env bash
# test-gate-mode-include.sh
#
# Smoke test for commands/_gate-mode.md (W3.3 deliverable).
# Verifies the canonical shared reference contains the load-bearing strings
# that the 3 interactive gate commands (spec-review, plan, check) will quote.
#
# Bash 3.2 compatible (macOS default). No bashisms past 3.2.

set -e
set -u

# Resolve repo root from this script's location: tests/ → repo root.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

REF_FILE="$REPO_ROOT/commands/_gate-mode.md"

PASS=0
FAIL=0

assert_grep() {
  local label="$1"
  local pattern="$2"
  local file="$3"
  if grep -qF "$pattern" "$file"; then
    echo "  PASS  $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL  $label"
    echo "        pattern not found: $pattern"
    FAIL=$((FAIL + 1))
  fi
}

echo "test-gate-mode-include.sh"
echo "  ref: $REF_FILE"

# Test 1: file exists.
if [ ! -f "$REF_FILE" ]; then
  echo "  FAIL  commands/_gate-mode.md does not exist at $REF_FILE"
  exit 1
fi
echo "  PASS  commands/_gate-mode.md exists"
PASS=$((PASS + 1))

# Test 2: precedence string matches personas/judge.md (single source of truth).
assert_grep \
  "precedence string matches personas/judge.md" \
  "architectural > security > unclassified > contract > tests > documentation > scope-cuts" \
  "$REF_FILE"

# Test 3: all 4 sentinel paths present (one grep per sentinel).
assert_grep \
  "sentinel: per-user default-flip v0.9.0" \
  "~/.claude/.gate-mode-default-flip-warned-v0.9.0" \
  "$REF_FILE"
assert_grep \
  "sentinel: per-spec gate-mode warned" \
  "docs/specs/<feature>/.gate-mode-warned" \
  "$REF_FILE"
assert_grep \
  "sentinel: per-spec recycles-deprecated" \
  "docs/specs/<feature>/.recycles-deprecated" \
  "$REF_FILE"
assert_grep \
  "sentinel: per-user migration shown" \
  "~/.claude/.gate-permissiveness-migration-shown" \
  "$REF_FILE"

# Test 4: per-user banner first line verbatim.
assert_grep \
  "per-user banner first line verbatim" \
  "First gate run on v0.9.0+ — pipeline gate defaults changed." \
  "$REF_FILE"

# Test 5: --force-permissive warning first line verbatim.
assert_grep \
  "--force-permissive warning first line verbatim" \
  "WARNING: --force-permissive overriding gate_mode: strict on <spec-path>." \
  "$REF_FILE"

# Test 6: truthy-value whitelist phrase.
assert_grep \
  "truthy-value whitelist phrase" \
  "{true, 1, yes" \
  "$REF_FILE"

# Test 7: .force-permissive-log JSONL row contains verdict_sidecar field.
assert_grep \
  "JSONL row format includes verdict_sidecar" \
  "verdict_sidecar" \
  "$REF_FILE"

# Test 8: truth table column headers (active mode + mode_source).
assert_grep \
  "truth table header: active mode" \
  "active mode" \
  "$REF_FILE"
assert_grep \
  "truth table header: mode_source" \
  "mode_source" \
  "$REF_FILE"

echo ""
echo "  total: $((PASS + FAIL))    pass: $PASS    fail: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
