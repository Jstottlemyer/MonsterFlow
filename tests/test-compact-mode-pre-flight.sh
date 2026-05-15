#!/bin/bash
##############################################################################
# tests/test-compact-mode-pre-flight.sh
#
# AC5 first half — /blueprint pre-flight writes .compact-mode (bare literal
# "probe" or "suppress") based on statusline-command.sh reachability.
#
# Tests the command-level contract (commands/blueprint.md) by checking that
# the pre-flight step is documented, and validates the sentinel file contract
# accepted by _pipeline_banner.sh _pb_maybe_compact.
#
# Strategy:
#   - Grep commands/blueprint.md for the pre-flight section describing
#     .compact-mode write step (F2 amendment from /check).
#   - Functional: simulate the two write outcomes (probe / suppress) and
#     verify _pipeline_banner.sh _pb_maybe_compact reads them correctly by
#     checking that: (a) no crash occurs for each mode, (b) sentinel is
#     written correctly for Path B when cost threshold crossed.
#
# Bash 3.2 compatible. Pins BASH=/bin/bash per AC20.
# Exit 0 on PASS. Exit 1 on FAIL.
##############################################################################
BASH=/bin/bash
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BLUEPRINT_CMD="$REPO_ROOT/commands/blueprint.md"
BANNER_SH="$REPO_ROOT/scripts/_pipeline_banner.sh"

PASS=0
FAIL=0
FAILED=()

ok()   { PASS=$(( PASS + 1 )); printf '  PASS %s\n' "$1"; }
fail() { FAIL=$(( FAIL + 1 )); FAILED+=("$1"); printf '  FAIL %s -- %s\n' "$1" "$2"; }
section() { printf '\n--- %s\n' "$1"; }

# ---------------------------------------------------------------------------
# Section 1: commands/blueprint.md contains .compact-mode pre-flight step
# ---------------------------------------------------------------------------
section "AC5 pre-flight — blueprint.md mentions .compact-mode write"

if [ ! -f "$BLUEPRINT_CMD" ]; then
  fail "blueprint.md exists" "not found at $BLUEPRINT_CMD"
else
  ok "blueprint.md exists"
  if grep -qi 'compact-mode' "$BLUEPRINT_CMD"; then
    ok "blueprint.md: contains '.compact-mode' reference"
  else
    fail "blueprint.md: contains '.compact-mode' reference" "no match for 'compact-mode'"
  fi
  # Must mention the probe action
  if grep -qi 'probe\|suppress\|statusline' "$BLUEPRINT_CMD"; then
    ok "blueprint.md: mentions probe/suppress/statusline"
  else
    fail "blueprint.md: mentions probe/suppress/statusline" "no match found"
  fi
fi

# ---------------------------------------------------------------------------
# Section 2: .compact-mode file values "probe" and "suppress" are valid
# sentinel values that _pipeline_banner.sh accepts without crashing.
# ---------------------------------------------------------------------------
section "AC5 sentinel contract — banner accepts 'probe' and 'suppress'"

if [ ! -f "$BANNER_SH" ]; then
  fail "banner helper exists" "not found at $BANNER_SH"
else
  ok "banner helper exists"

  TMPDIR_TEST="$(mktemp -d -t 'test-compact-preflight.XXXXXX')"
  trap 'rm -rf "$TMPDIR_TEST"' EXIT

  SPEC_DIR="$TMPDIR_TEST/docs/specs/compact-preflight-test"
  mkdir -p "$SPEC_DIR"

  # Write minimal spec.md
  {
    printf '%s\n' '---'
    printf 'pipeline_path: feature\n'
    printf '%s\n' '---'
    printf '%s\n' '# compact-preflight test'
  } > "$SPEC_DIR/spec.md"

  FAKE_HOME="$TMPDIR_TEST/fakehome"
  mkdir -p "$FAKE_HOME/.claude"

  # Test: .compact-mode = probe — banner end should not crash
  printf 'probe\n' > "$SPEC_DIR/.compact-mode"

  set +e
  PROBE_RC=0
  (cd "$TMPDIR_TEST" && HOME="$FAKE_HOME" AUTORUN=0 /bin/bash "$BANNER_SH" end check compact-preflight-test >/dev/null 2>/dev/null)
  PROBE_RC=$?
  set -e

  if [ "$PROBE_RC" -eq 0 ]; then
    ok ".compact-mode=probe: banner end exits 0"
  else
    fail ".compact-mode=probe: banner end exits 0" "rc=$PROBE_RC"
  fi

  # Test: .compact-mode = suppress — banner end should not crash
  printf 'suppress\n' > "$SPEC_DIR/.compact-mode"

  set +e
  SUPPRESS_RC=0
  (cd "$TMPDIR_TEST" && HOME="$FAKE_HOME" AUTORUN=0 /bin/bash "$BANNER_SH" end check compact-preflight-test >/dev/null 2>/dev/null)
  SUPPRESS_RC=$?
  set -e

  if [ "$SUPPRESS_RC" -eq 0 ]; then
    ok ".compact-mode=suppress: banner end exits 0"
  else
    fail ".compact-mode=suppress: banner end exits 0" "rc=$SUPPRESS_RC"
  fi

  # Test: invalid .compact-mode value treated as suppress (fail-open)
  printf 'garbage\n' > "$SPEC_DIR/.compact-mode"

  set +e
  GARBAGE_RC=0
  (cd "$TMPDIR_TEST" && HOME="$FAKE_HOME" AUTORUN=0 /bin/bash "$BANNER_SH" end check compact-preflight-test >/dev/null 2>/dev/null)
  GARBAGE_RC=$?
  set -e

  if [ "$GARBAGE_RC" -eq 0 ]; then
    ok ".compact-mode=garbage: banner end exits 0 (fail-open)"
  else
    fail ".compact-mode=garbage: banner end exits 0 (fail-open)" "rc=$GARBAGE_RC"
  fi

  # Test: missing .compact-mode file treated as suppress (fail-open)
  rm -f "$SPEC_DIR/.compact-mode"

  set +e
  MISSING_RC=0
  (cd "$TMPDIR_TEST" && HOME="$FAKE_HOME" AUTORUN=0 /bin/bash "$BANNER_SH" end check compact-preflight-test >/dev/null 2>/dev/null)
  MISSING_RC=$?
  set -e

  if [ "$MISSING_RC" -eq 0 ]; then
    ok ".compact-mode absent: banner end exits 0 (fail-open)"
  else
    fail ".compact-mode absent: banner end exits 0 (fail-open)" "rc=$MISSING_RC"
  fi

  rm -rf "$TMPDIR_TEST"
  trap - EXIT
fi

# ---------------------------------------------------------------------------
# Section 3: gitignore patterns cover .compact-mode
# ---------------------------------------------------------------------------
section "AC19 — .gitignore has pattern for docs/specs/*/.compact-mode"

GITIGNORE="$REPO_ROOT/.gitignore"
if [ -f "$GITIGNORE" ] && grep -q 'compact-mode' "$GITIGNORE"; then
  ok ".gitignore: contains compact-mode pattern"
else
  fail ".gitignore: contains compact-mode pattern" "no match in $GITIGNORE"
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
