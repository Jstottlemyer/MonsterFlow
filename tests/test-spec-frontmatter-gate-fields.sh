#!/usr/bin/env bash
##############################################################################
# tests/test-spec-frontmatter-gate-fields.sh
#
# Validates that commands/spec.md's Phase 3 frontmatter schema includes the
# pipeline-gate-permissiveness knob `gate_mode` AND that `gate_max_recycles`
# is documented as DEPRECATED (hardcoded to 3 since 2026-05-09).
#
# Bash 3.2 compatible. Pure grep assertions on the file contents.
##############################################################################
set -uo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SPEC_CMD="$ENGINE_DIR/commands/spec.md"

PASS=0
FAIL=0

assert_grep() {
  # $1 = pattern (fixed string), $2 = description
  local pattern="$1"
  local desc="$2"
  if grep -F -q -- "$pattern" "$SPEC_CMD"; then
    echo "  ok — $desc"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL — $desc (missing: $pattern)"
    FAIL=$(( FAIL + 1 ))
  fi
}

assert_grep_ext() {
  # extended regex variant for clamp range alternation
  local pattern="$1"
  local desc="$2"
  if grep -E -q -- "$pattern" "$SPEC_CMD"; then
    echo "  ok — $desc"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL — $desc (missing pattern: $pattern)"
    FAIL=$(( FAIL + 1 ))
  fi
}

if [ ! -f "$SPEC_CMD" ]; then
  echo "✗ commands/spec.md not found at $SPEC_CMD"
  exit 1
fi

echo "test-spec-frontmatter-gate-fields"
echo "  target: $SPEC_CMD"

# 1. gate_mode field present
assert_grep "gate_mode" "Phase 3 frontmatter declares gate_mode"

# 2. gate_max_recycles documented as DEPRECATED (the field name still appears
#    so authors searching for it find the deprecation note rather than nothing)
assert_grep "gate_max_recycles" "gate_max_recycles deprecation note present"
assert_grep "DEPRECATED" "gate_max_recycles flagged as DEPRECATED"

# 3. References commands/_gate-mode.md (CLI flag truth table)
assert_grep "commands/_gate-mode.md" "Phase 3 references commands/_gate-mode.md"

# 4. Enum values for gate_mode
assert_grep "permissive" "gate_mode enum value 'permissive' documented"
assert_grep "strict" "gate_mode enum value 'strict' documented"

# 5. Hardcoded value 3 documented
assert_grep "hardcoded to 3" "gate_max_recycles hardcoded value 3 documented"

echo ""
echo "  passed: $PASS"
echo "  failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
