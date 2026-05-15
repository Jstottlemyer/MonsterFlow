#!/usr/bin/env bash
##############################################################################
# tests/test-build-md-autorun-shell-reviewer-hook.sh
#
# AC15 enforcement (pipeline-pacing-and-prefill T8 / D10 / spec AC15).
#
# Verifies that commands/build.md Phase 3 contains the explicit instruction
# to dispatch autorun-shell-reviewer before pre-commit when
# scripts/autorun/*.sh has uncommitted changes, including:
#   1. The literal string "autorun-shell-reviewer" in Phase 3 area
#   2. A reference to scripts/autorun/*.sh detection (git diff --name-only)
#   3. A reference to "3 attempts" or "iterative-resolution" (halt policy)
##############################################################################
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_MD="$REPO_ROOT/commands/build.md"

fail_count=0

check() {
  local label="$1"
  local pattern="$2"
  if grep -qE "$pattern" "$BUILD_MD"; then
    printf '[PASS] %s\n' "$label"
  else
    printf '[FAIL] %s — pattern not found: %s\n' "$label" "$pattern" >&2
    fail_count=$((fail_count + 1))
  fi
}

if [ ! -f "$BUILD_MD" ]; then
  printf '[FAIL] commands/build.md not found: %s\n' "$BUILD_MD" >&2
  exit 1
fi

# 1. Literal "autorun-shell-reviewer" appears in Phase 3 area
check \
  'autorun-shell-reviewer literal present in build.md' \
  'autorun-shell-reviewer'

# 2. Detection of scripts/autorun/*.sh changes via git diff --name-only
check \
  'git diff --name-only detection for scripts/autorun/' \
  'git diff --name-only.*scripts/autorun'

# 3. 3-attempt iterative-resolution halt policy referenced
check \
  '3-attempt halt policy referenced' \
  '3 attempt(s|s total)?|iterative.resolution'

if [ "$fail_count" -gt 0 ]; then
  printf '[FAIL] test-build-md-autorun-shell-reviewer-hook.sh: %d check(s) failed\n' \
    "$fail_count" >&2
  exit 1
fi

printf '[PASS] test-build-md-autorun-shell-reviewer-hook.sh: all 3 checks passed\n'
exit 0
