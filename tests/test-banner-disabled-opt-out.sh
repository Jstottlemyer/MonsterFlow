#!/bin/bash
##############################################################################
# tests/test-banner-disabled-opt-out.sh
#
# AC13 (dedicated, focused) — ~/.claude/.banner-disabled opt-out suppresses
# ALL banner emission, including the /compact suggestion line.
#
# NOTE: AC13 is also covered by test-pipeline-banner.sh Test 2 (3 assertions).
# This file is the AC22-enumerated dedicated focused test for AC13 — a tight
# focused set of assertions on the exact suppression contract, independently
# verifiable. Documented redundancy for enumeration completeness.
#
# Bash 3.2 compatible. Pins BASH=/bin/bash per AC20.
# Exit 0 on PASS. Exit 1 on FAIL.
##############################################################################
BASH=/bin/bash
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BANNER="$REPO_ROOT/scripts/_pipeline_banner.sh"

PASS=0
FAIL=0
FAILED=()

ok()   { PASS=$(( PASS + 1 )); printf '  PASS %s\n' "$1"; }
fail() { FAIL=$(( FAIL + 1 )); FAILED+=("$1"); printf '  FAIL %s -- %s\n' "$1" "$2"; }

if [ ! -f "$BANNER" ]; then
  printf 'FAIL: %s missing\n' "$BANNER" >&2
  exit 1
fi

TMPDIR_TEST="$(mktemp -d -t 'test-banner-disabled.XXXXXX')"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# Spec dir with real spec.md (so banner would normally emit)
SPEC_DIR="$TMPDIR_TEST/docs/specs/opt-out-test"
mkdir -p "$SPEC_DIR"
{
  printf '%s\n' '---'
  printf 'pipeline_path: feature\n'
  printf '%s\n' '---'
  printf '%s\n' '# opt-out test'
} > "$SPEC_DIR/spec.md"

# ---------------------------------------------------------------------------
# Setup: fake HOME with .banner-disabled present
# ---------------------------------------------------------------------------
FAKE_HOME_DISABLED="$TMPDIR_TEST/home-disabled"
mkdir -p "$FAKE_HOME_DISABLED/.claude"
touch "$FAKE_HOME_DISABLED/.claude/.banner-disabled"

# ---------------------------------------------------------------------------
# Setup: fake HOME without .banner-disabled (control)
# ---------------------------------------------------------------------------
FAKE_HOME_ENABLED="$TMPDIR_TEST/home-enabled"
mkdir -p "$FAKE_HOME_ENABLED/.claude"

# ---------------------------------------------------------------------------
# Test 1: start suppressed when .banner-disabled present
# ---------------------------------------------------------------------------
printf '\n--- AC13: start suppressed when .banner-disabled present ---\n'

OUT_START_DISABLED=$(cd "$TMPDIR_TEST" && HOME="$FAKE_HOME_DISABLED" AUTORUN=0 \
  /bin/bash "$BANNER" start spec opt-out-test 2>&1)

if [ -z "$OUT_START_DISABLED" ]; then
  ok "start: suppressed (empty output with .banner-disabled)"
else
  fail "start: suppressed with .banner-disabled" "got: $OUT_START_DISABLED"
fi

# ---------------------------------------------------------------------------
# Test 2: end suppressed when .banner-disabled present
# ---------------------------------------------------------------------------
printf '\n--- AC13: end suppressed when .banner-disabled present ---\n'

OUT_END_DISABLED=$(cd "$TMPDIR_TEST" && HOME="$FAKE_HOME_DISABLED" AUTORUN=0 \
  /bin/bash "$BANNER" end spec opt-out-test 2>&1)

if [ -z "$OUT_END_DISABLED" ]; then
  ok "end: suppressed (empty output with .banner-disabled)"
else
  fail "end: suppressed with .banner-disabled" "got: $OUT_END_DISABLED"
fi

# ---------------------------------------------------------------------------
# Test 3: /compact line also suppressed (not just the stage banner)
# ---------------------------------------------------------------------------
printf '\n--- AC13: /compact suggestion suppressed when .banner-disabled present ---\n'

# Write .compact-mode=suppress + set cost stub so Path B WOULD fire if not disabled
FAKE_HOME_DISABLED2="$TMPDIR_TEST/home-disabled2"
mkdir -p "$FAKE_HOME_DISABLED2/.claude"
touch "$FAKE_HOME_DISABLED2/.claude/.banner-disabled"
mkdir -p "$FAKE_HOME_DISABLED2/.claude/scripts"
cat > "$FAKE_HOME_DISABLED2/.claude/scripts/session-cost.py" << 'PYSTUB'
#!/usr/bin/env python3
import sys
if len(sys.argv) > 1 and sys.argv[1] == "--cumulative-only":
    print("600")
    sys.exit(0)
sys.exit(1)
PYSTUB
chmod +x "$FAKE_HOME_DISABLED2/.claude/scripts/session-cost.py"

printf 'suppress\n' > "$SPEC_DIR/.compact-mode"

OUT_COMPACT_DISABLED=$(cd "$TMPDIR_TEST" && HOME="$FAKE_HOME_DISABLED2" AUTORUN=0 \
  /bin/bash "$BANNER" end spec opt-out-test 2>&1)

if [ -z "$OUT_COMPACT_DISABLED" ]; then
  ok "/compact line also suppressed with .banner-disabled"
else
  fail "/compact line also suppressed with .banner-disabled" "got: $OUT_COMPACT_DISABLED"
fi

# ---------------------------------------------------------------------------
# Test 4: control — without .banner-disabled, banner DOES emit
# ---------------------------------------------------------------------------
printf '\n--- AC13 control: banner emits when .banner-disabled absent ---\n'

OUT_ENABLED=$(cd "$TMPDIR_TEST" && HOME="$FAKE_HOME_ENABLED" AUTORUN=0 \
  /bin/bash "$BANNER" start spec opt-out-test 2>/dev/null)

if [ -n "$OUT_ENABLED" ]; then
  ok "control: banner emits when .banner-disabled absent"
else
  fail "control: banner emits when .banner-disabled absent" "got empty output"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'Failed:\n'
  for f in "${FAILED[@]}"; do printf '  - %s\n' "$f"; done
  exit 1
fi
exit 0
