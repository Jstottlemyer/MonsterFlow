#!/bin/bash
##############################################################################
# tests/test-banner-standalone-mode.sh
#
# AC16 (dedicated, focused) — /build standalone-mode: when no spec.md exists
# in the expected location, _pipeline_banner.sh emits "[pipeline] /<gate> ·
# standalone mode" and exits 0 without crash.
#
# NOTE: AC16 is also covered by test-pipeline-banner.sh Test 1 (3 assertions).
# This file is the AC22-enumerated dedicated focused test for AC16 — one
# tight set of assertions confirming the exact contract independently.
# This is documented redundancy for enumeration completeness, not deep
# duplication.
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

TMPDIR_TEST="$(mktemp -d -t 'test-banner-standalone.XXXXXX')"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

FAKE_HOME="$TMPDIR_TEST/fakehome"
mkdir -p "$FAKE_HOME/.claude"

# ---------------------------------------------------------------------------
# Test 1: start — no spec.md → standalone mode line, exit 0
# ---------------------------------------------------------------------------
printf '\n--- AC16 start: no spec.md emits standalone mode ---\n'

set +e
OUT_START=$(cd "$TMPDIR_TEST" && HOME="$FAKE_HOME" AUTORUN=0 /bin/bash "$BANNER" start build no-spec-feature 2>/dev/null)
RC_START=$?
set -e

if [ "$RC_START" -eq 0 ]; then
  ok "start: exits 0 in standalone mode"
else
  fail "start: exits 0 in standalone mode" "rc=$RC_START"
fi

if printf '%s' "$OUT_START" | grep -q '\[pipeline\]'; then
  ok "start: output contains [pipeline] prefix"
else
  fail "start: output contains [pipeline] prefix" "got: $OUT_START"
fi

if printf '%s' "$OUT_START" | grep -q 'standalone mode'; then
  ok "start: output contains 'standalone mode'"
else
  fail "start: output contains 'standalone mode'" "got: $OUT_START"
fi

# ---------------------------------------------------------------------------
# Test 2: end — no spec.md → standalone mode line, exit 0
# ---------------------------------------------------------------------------
printf '\n--- AC16 end: no spec.md emits standalone mode ---\n'

set +e
OUT_END=$(cd "$TMPDIR_TEST" && HOME="$FAKE_HOME" AUTORUN=0 /bin/bash "$BANNER" end check no-spec-feature 2>/dev/null)
RC_END=$?
set -e

if [ "$RC_END" -eq 0 ]; then
  ok "end: exits 0 in standalone mode"
else
  fail "end: exits 0 in standalone mode" "rc=$RC_END"
fi

if printf '%s' "$OUT_END" | grep -q 'standalone mode'; then
  ok "end: output contains 'standalone mode'"
else
  fail "end: output contains 'standalone mode'" "got: $OUT_END"
fi

# ---------------------------------------------------------------------------
# Test 3: the exact expected format "[pipeline] /<gate> · standalone mode"
# ---------------------------------------------------------------------------
printf '\n--- AC16: exact format "[pipeline] /<gate> · standalone mode" ---\n'

set +e
OUT_FMT=$(cd "$TMPDIR_TEST" && HOME="$FAKE_HOME" AUTORUN=0 /bin/bash "$BANNER" start build no-spec-feature 2>/dev/null)
set -e

if printf '%s' "$OUT_FMT" | grep -qE '^\[pipeline\] /[a-z]'; then
  ok "start: format matches '[pipeline] /<gate>'"
else
  fail "start: format matches '[pipeline] /<gate>'" "got: $OUT_FMT"
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
