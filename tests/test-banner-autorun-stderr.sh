#!/bin/bash
##############################################################################
# tests/test-banner-autorun-stderr.sh
#
# AC18 + T7 integration test:
#   1. Each modified autorun script sources scripts/_pipeline_banner.sh.
#   2. Each script calls _pipeline_banner_start and _pipeline_banner_end.
#   3. With AUTORUN=1 set, _pb_emit routes to stderr (not stdout).
#
# Strategy:
#   - Grep-based presence checks: assert source + call statements exist.
#   - Functional stub invocation: source _pipeline_banner.sh directly with
#     AUTORUN=1, call _pipeline_banner_start/_pipeline_banner_end, capture
#     stdout vs stderr separately, assert banner goes to stderr only.
#
# Bash 3.2 compatible (macOS /bin/bash). No ${arr[-1]}, no declare -A.
# Exit 0 on PASS. Exit 1 on FAIL.
##############################################################################
BASH=/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== test-banner-autorun-stderr ==="

# ---------------------------------------------------------------------------
# Section 1: source-statement presence in each autorun script
# ---------------------------------------------------------------------------
echo ""
echo "-- Section 1: source _pipeline_banner.sh present in autorun scripts --"

for script in spec-review.sh design.sh check.sh build.sh; do
  script_path="$REPO_DIR/scripts/autorun/$script"
  if [ ! -f "$script_path" ]; then
    fail "$script: file not found at $script_path"
    continue
  fi
  if grep -q '_pipeline_banner.sh' "$script_path"; then
    pass "$script: sources _pipeline_banner.sh"
  else
    fail "$script: missing 'source \$REPO_DIR/scripts/_pipeline_banner.sh'"
  fi
done

# ---------------------------------------------------------------------------
# Section 2: _pipeline_banner_start call present in each autorun script
# ---------------------------------------------------------------------------
echo ""
echo "-- Section 2: _pipeline_banner_start call present --"

for script in spec-review.sh design.sh check.sh build.sh; do
  script_path="$REPO_DIR/scripts/autorun/$script"
  [ -f "$script_path" ] || continue
  if grep -q '_pipeline_banner_start' "$script_path"; then
    pass "$script: _pipeline_banner_start call present"
  else
    fail "$script: missing _pipeline_banner_start call"
  fi
done

# ---------------------------------------------------------------------------
# Section 3: _pipeline_banner_end call present in each autorun script
# ---------------------------------------------------------------------------
echo ""
echo "-- Section 3: _pipeline_banner_end call present --"

for script in spec-review.sh design.sh check.sh build.sh; do
  script_path="$REPO_DIR/scripts/autorun/$script"
  [ -f "$script_path" ] || continue
  if grep -q '_pipeline_banner_end' "$script_path"; then
    pass "$script: _pipeline_banner_end call present"
  else
    fail "$script: missing _pipeline_banner_end call"
  fi
done

# ---------------------------------------------------------------------------
# Section 4: gate-name mapping assertions
# ---------------------------------------------------------------------------
echo ""
echo "-- Section 4: gate-name mapping correct --"

# spec-review.sh must use "spec-review"
if grep -q '_pipeline_banner_start "spec-review"' "$REPO_DIR/scripts/autorun/spec-review.sh" 2>/dev/null && \
   grep -q '_pipeline_banner_end "spec-review"' "$REPO_DIR/scripts/autorun/spec-review.sh" 2>/dev/null; then
  pass "spec-review.sh: gate name is 'spec-review'"
else
  fail "spec-review.sh: gate name must be 'spec-review'"
fi

# design.sh must use "blueprint" (slash-command name per spec)
if grep -q '_pipeline_banner_start "blueprint"' "$REPO_DIR/scripts/autorun/design.sh" 2>/dev/null && \
   grep -q '_pipeline_banner_end "blueprint"' "$REPO_DIR/scripts/autorun/design.sh" 2>/dev/null; then
  pass "design.sh: gate name is 'blueprint'"
else
  fail "design.sh: gate name must be 'blueprint' (slash-command name)"
fi

# check.sh must use "check"
if grep -q '_pipeline_banner_start "check"' "$REPO_DIR/scripts/autorun/check.sh" 2>/dev/null && \
   grep -q '_pipeline_banner_end "check"' "$REPO_DIR/scripts/autorun/check.sh" 2>/dev/null; then
  pass "check.sh: gate name is 'check'"
else
  fail "check.sh: gate name must be 'check'"
fi

# build.sh must use "build"
if grep -q '_pipeline_banner_start "build"' "$REPO_DIR/scripts/autorun/build.sh" 2>/dev/null && \
   grep -q '_pipeline_banner_end "build"' "$REPO_DIR/scripts/autorun/build.sh" 2>/dev/null; then
  pass "build.sh: gate name is 'build'"
else
  fail "build.sh: gate name must be 'build'"
fi

# ---------------------------------------------------------------------------
# Section 5: functional test — AUTORUN=1 routes banner to stderr
#
# Source _pipeline_banner.sh under BASH=/bin/bash (AC20 pin), call
# _pipeline_banner_start in a subshell, capture stdout and stderr separately,
# assert: stderr non-empty, stdout empty.
#
# We run without a real spec dir so the null-guard fires the "standalone mode"
# path — that is sufficient to exercise _pb_emit routing.
# ---------------------------------------------------------------------------
echo ""
echo "-- Section 5: AUTORUN=1 routes banner output to stderr (functional) --"

BANNER_SH="$REPO_DIR/scripts/_pipeline_banner.sh"

if [ ! -f "$BANNER_SH" ]; then
  fail "AUTORUN=1 stderr routing: _pipeline_banner.sh not found at $BANNER_SH"
else
  # Capture stdout and stderr into separate temp files.
  TMPOUT="$(mktemp "${TMPDIR:-/tmp}/banner-test-stdout.XXXXXX")"
  TMPERR="$(mktemp "${TMPDIR:-/tmp}/banner-test-stderr.XXXXXX")"
  trap 'rm -f "$TMPOUT" "$TMPERR"' EXIT

  # Run in a subshell so sourcing doesn't pollute the test process state.
  # Use BASH pin (AC20: tests touching the banner helper run under /bin/bash).
  # Pass AUTORUN=1 explicitly via env prefix so the subshell inherits it.
  AUTORUN=1 $BASH -c "
    source '$BANNER_SH'
    # Call start: no spec dir → standalone mode → _pb_emit fires
    _pipeline_banner_start 'check' 'no-such-feature-slug-xyz'
  " >"$TMPOUT" 2>"$TMPERR"

  STDOUT_CONTENT="$(cat "$TMPOUT")"
  STDERR_CONTENT="$(cat "$TMPERR")"

  if [ -n "$STDERR_CONTENT" ]; then
    pass "AUTORUN=1 via env prefix: banner emitted to stderr"
  else
    fail "AUTORUN=1: stderr was empty — banner did not emit to stderr"
  fi

  if [ -z "$STDOUT_CONTENT" ]; then
    pass "AUTORUN=1: stdout is clean (no banner on stdout)"
  else
    fail "AUTORUN=1: banner leaked to stdout: $STDOUT_CONTENT"
  fi

  # Also verify explicit AUTORUN=1 override works.
  TMPOUT2="$(mktemp "${TMPDIR:-/tmp}/banner-test-stdout2.XXXXXX")"
  TMPERR2="$(mktemp "${TMPDIR:-/tmp}/banner-test-stderr2.XXXXXX")"
  trap 'rm -f "$TMPOUT" "$TMPERR" "$TMPOUT2" "$TMPERR2"' EXIT

  AUTORUN=1 $BASH -c "
    source '$BANNER_SH'
    _pipeline_banner_start 'build' 'no-such-feature-slug-xyz'
  " >"$TMPOUT2" 2>"$TMPERR2"

  STDERR2="$(cat "$TMPERR2")"
  STDOUT2="$(cat "$TMPOUT2")"

  if [ -n "$STDERR2" ]; then
    pass "AUTORUN=1 explicit: banner emitted to stderr"
  else
    fail "AUTORUN=1 explicit: stderr was empty"
  fi

  if [ -z "$STDOUT2" ]; then
    pass "AUTORUN=1 explicit: stdout clean"
  else
    fail "AUTORUN=1 explicit: banner leaked to stdout: $STDOUT2"
  fi

  rm -f "$TMPOUT" "$TMPERR" "$TMPOUT2" "$TMPERR2" 2>/dev/null || true
  trap - EXIT
fi

# ---------------------------------------------------------------------------
# Section 6: AUTORUN=0 routes banner to stdout (not stderr)
# ---------------------------------------------------------------------------
echo ""
echo "-- Section 6: AUTORUN=0 routes banner output to stdout --"

if [ -f "$BANNER_SH" ]; then
  TMPOUT3="$(mktemp "${TMPDIR:-/tmp}/banner-test-stdout3.XXXXXX")"
  TMPERR3="$(mktemp "${TMPDIR:-/tmp}/banner-test-stderr3.XXXXXX")"
  trap 'rm -f "$TMPOUT3" "$TMPERR3"' EXIT

  AUTORUN=0 $BASH -c "
    source '$BANNER_SH'
    _pipeline_banner_start 'check' 'no-such-feature-slug-xyz'
  " >"$TMPOUT3" 2>"$TMPERR3"

  STDOUT3="$(cat "$TMPOUT3")"
  STDERR3="$(cat "$TMPERR3")"

  if [ -n "$STDOUT3" ]; then
    pass "AUTORUN=0: banner emitted to stdout"
  else
    fail "AUTORUN=0: stdout was empty (banner should go to stdout when not in autorun mode)"
  fi

  if [ -z "$STDERR3" ]; then
    pass "AUTORUN=0: stderr is clean"
  else
    fail "AUTORUN=0: unexpected stderr output: $STDERR3"
  fi

  rm -f "$TMPOUT3" "$TMPERR3" 2>/dev/null || true
  trap - EXIT
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
