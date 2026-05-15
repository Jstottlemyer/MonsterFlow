#!/bin/bash
##############################################################################
# tests/test-bash32-compat.sh
#
# AC20 (dedicated, focused) — _pipeline_banner.sh runs cleanly under
# BASH=/bin/bash (macOS bash 3.2) and contains no forbidden bash 4+ constructs.
#
# NOTE: test-pipeline-banner.sh Tests 7+8 also exercise AC20 at a high level.
# This dedicated file provides a tighter, standalone AC20 gate: static source
# scan + runtime execution under /bin/bash. Documented redundancy for AC22
# enumeration completeness.
#
# Forbidden constructs checked (per spec D1 + AC20):
#   ${arr[-1]}, declare -A, local -n, mapfile, readarray, read -a,
#   (?<name>...) named-group regex.
#
# Bash 3.2 compatible (this test file itself must not use bash 4+ syntax).
# Pins BASH=/bin/bash per AC20.
# Exit 0 on PASS. Exit 1 on FAIL.
##############################################################################
# Pins BASH=/bin/bash per AC20 — must appear before line 15 for self-check.
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
  printf 'FAIL: _pipeline_banner.sh missing at %s\n' "$BANNER" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Section 1: static source scan — no forbidden bash 4+ constructs in
# non-comment code lines.
# ---------------------------------------------------------------------------
printf '\n--- AC20 static: no forbidden bash 4+ constructs in non-comment lines ---\n'

# Strip comment lines (lines starting with optional whitespace then #)
NONCOMMENT=$(grep -v '^[[:space:]]*#' "$BANNER")

# 1a. No negative array subscripts ${arr[-N]}
if printf '%s' "$NONCOMMENT" | grep -qE '\$\{[a-zA-Z_][a-zA-Z_0-9]*\[-[0-9]+\]\}'; then
  fail "no \${arr[-N]} negative array subscripts" "found in non-comment code"
else
  ok "no \${arr[-N]} negative array subscripts"
fi

# 1b. No associative arrays (declare -A)
if printf '%s' "$NONCOMMENT" | grep -q 'declare -A'; then
  fail "no 'declare -A'" "found in non-comment code"
else
  ok "no 'declare -A' (associative arrays)"
fi

# 1c. No nameref (local -n)
if printf '%s' "$NONCOMMENT" | grep -q 'local -n'; then
  fail "no 'local -n'" "found in non-comment code"
else
  ok "no 'local -n' (nameref locals)"
fi

# 1d. No mapfile
if printf '%s' "$NONCOMMENT" | grep -q 'mapfile'; then
  fail "no 'mapfile'" "found in non-comment code"
else
  ok "no 'mapfile'"
fi

# 1e. No readarray
if printf '%s' "$NONCOMMENT" | grep -q 'readarray'; then
  fail "no 'readarray'" "found in non-comment code"
else
  ok "no 'readarray'"
fi

# 1f. No read -a (array read; avoid false-positive on read -r/-d etc.)
if printf '%s' "$NONCOMMENT" | grep -qE 'read[[:space:]]+-[a-z]*a'; then
  fail "no 'read -a'" "found in non-comment code"
else
  ok "no 'read -a'"
fi

# 1g. No named-group regex (?<name>...)
if printf '%s' "$NONCOMMENT" | grep -q '(?<'; then
  fail "no '(?<name>...)' named-group regex" "found in non-comment code"
else
  ok "no '(?<name>...)' named-group regex"
fi

# ---------------------------------------------------------------------------
# Section 2: runtime — script executes without error under /bin/bash
# ---------------------------------------------------------------------------
printf '\n--- AC20 runtime: script executes cleanly under /bin/bash ---\n'

TMPDIR_TEST="$(mktemp -d -t 'test-bash32.XXXXXX')"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

FAKE_HOME="$TMPDIR_TEST/fakehome"
mkdir -p "$FAKE_HOME/.claude"

# Run start in standalone mode (no spec.md needed) under /bin/bash
set +e
/bin/bash "$BANNER" start build nonexistent-feature-zzz >/dev/null 2>/dev/null
RC_START=$?
set -e

if [ "$RC_START" -eq 0 ]; then
  ok "runtime: 'start' exits 0 under /bin/bash"
else
  fail "runtime: 'start' exits 0 under /bin/bash" "rc=$RC_START"
fi

# Run end in standalone mode under /bin/bash
set +e
/bin/bash "$BANNER" end check nonexistent-feature-zzz >/dev/null 2>/dev/null
RC_END=$?
set -e

if [ "$RC_END" -eq 0 ]; then
  ok "runtime: 'end' exits 0 under /bin/bash"
else
  fail "runtime: 'end' exits 0 under /bin/bash" "rc=$RC_END"
fi

# Verify this test file itself pins BASH=/bin/bash (self-referential check)
if head -15 "$0" | grep -q 'BASH=/bin/bash'; then
  ok "this test file sets BASH=/bin/bash per AC20"
else
  fail "this test file sets BASH=/bin/bash" "not found in first 15 lines"
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
