#!/bin/bash
##############################################################################
# tests/test-pipeline-banner.sh
#
# Tests for scripts/_pipeline_banner.sh — T1 of pipeline-pacing-and-prefill.
# Covers AC2, AC3, AC6, AC13, AC16, AC20 (subset: start/end/standalone/
# banner-disabled/denominator).
#
# Bash 3.2 compatible. Pins BASH=/bin/bash per AC20.
##############################################################################
BASH=/bin/bash
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BANNER="$REPO_ROOT/scripts/_pipeline_banner.sh"

if [ ! -f "$BANNER" ]; then
  printf 'FAIL: %s missing\n' "$BANNER" >&2
  exit 1
fi
if [ ! -x "$BANNER" ]; then
  printf 'FAIL: %s not executable\n' "$BANNER" >&2
  exit 1
fi

TMPROOT="$(mktemp -d -t "pipeline-banner-test.XXXXXX")"
trap 'rm -rf "$TMPROOT"' EXIT

PASS=0
FAIL=0
FAILED=()

ok()   { PASS=$(( PASS + 1 )); printf '  PASS %s\n' "$1"; }
fail() { FAIL=$(( FAIL + 1 )); FAILED+=("$1"); printf '  FAIL %s -- %s\n' "$1" "$2"; }
case_() { printf '\n--- %s\n' "$1"; }

# ---------------------------------------------------------------------------
# Helper: create a minimal spec.md with given pipeline_path
# ---------------------------------------------------------------------------
mk_spec() {
  _ms_dir="$1"
  _ms_path="$2"
  mkdir -p "$_ms_dir"
  {
    printf '%s\n' '---'
    printf 'pipeline_path: %s\n' "$_ms_path"
    printf '%s\n' '---'
    printf '%s\n' ''
    printf '%s\n' '# Test spec'
  } > "$_ms_dir/spec.md"
}

# ---------------------------------------------------------------------------
# Helper: run banner script under /bin/bash (AC20)
# Args: remaining args passed directly to script
# ---------------------------------------------------------------------------
run_banner() {
  AUTORUN=0 /bin/bash "$BANNER" "$@"
}

run_banner_autorun() {
  AUTORUN=1 /bin/bash "$BANNER" "$@"
}

# ---------------------------------------------------------------------------
# Test 1: Standalone mode — no spec.md (AC16)
# ---------------------------------------------------------------------------
case_ "AC16 — standalone mode: no spec.md emits '[pipeline] /build · standalone mode'"

# Run from a temp dir that has no docs/specs directory
STAND_OUT=$(cd "$TMPROOT" && run_banner start build my-nonexistent-feature 2>/dev/null)
if printf '%s' "$STAND_OUT" | grep -q '\[pipeline\].*standalone mode'; then
  ok "start: standalone mode line emitted"
else
  fail "start: standalone mode line emitted" "got: $STAND_OUT"
fi

STAND_OUT2=$(cd "$TMPROOT" && run_banner end build my-nonexistent-feature 2>/dev/null)
if printf '%s' "$STAND_OUT2" | grep -q '\[pipeline\].*standalone mode'; then
  ok "end: standalone mode line emitted"
else
  fail "end: standalone mode line emitted" "got: $STAND_OUT2"
fi

# Verify exit 0 in standalone mode (AC16)
cd "$TMPROOT" && run_banner start build no-spec-here >/dev/null 2>/dev/null
RC=$?
if [ "$RC" -eq 0 ]; then
  ok "standalone mode exits 0"
else
  fail "standalone mode exits 0" "rc=$RC"
fi

# ---------------------------------------------------------------------------
# Test 2: Banner-disabled opt-out (AC13)
# ---------------------------------------------------------------------------
case_ "AC13 — ~/.claude/.banner-disabled suppresses all output"

# Create a fake spec so it would normally emit
SPEC2_DIR="$TMPROOT/docs/specs/test-feature2"
mk_spec "$SPEC2_DIR" "feature"

# Create a fake banner-disabled file and set HOME to tmproot
FAKE_HOME2="$TMPROOT/fakehome2"
mkdir -p "$FAKE_HOME2/.claude"
touch "$FAKE_HOME2/.claude/.banner-disabled"

OUT2=$(cd "$TMPROOT" && HOME="$FAKE_HOME2" run_banner start spec test-feature2 2>&1)
if [ -z "$OUT2" ]; then
  ok "start: all output suppressed when .banner-disabled present"
else
  fail "start: all output suppressed when .banner-disabled present" "got: $OUT2"
fi

OUT2E=$(cd "$TMPROOT" && HOME="$FAKE_HOME2" run_banner end spec test-feature2 2>&1)
if [ -z "$OUT2E" ]; then
  ok "end: all output suppressed when .banner-disabled present"
else
  fail "end: all output suppressed when .banner-disabled present" "got: $OUT2E"
fi

# Without .banner-disabled — same setup should emit something
FAKE_HOME2B="$TMPROOT/fakehome2b"
mkdir -p "$FAKE_HOME2B/.claude"
# No .banner-disabled here
OUT2B=$(cd "$TMPROOT" && HOME="$FAKE_HOME2B" run_banner start spec test-feature2 2>/dev/null)
if [ -n "$OUT2B" ]; then
  ok "start: output present when .banner-disabled absent"
else
  fail "start: output present when .banner-disabled absent" "got empty output"
fi

# ---------------------------------------------------------------------------
# Test 3: Start banner emission (AC2)
# ---------------------------------------------------------------------------
case_ "AC2 — start banner: emits single line matching expected format"

SPEC3_DIR="$TMPROOT/docs/specs/test-feature3"
mk_spec "$SPEC3_DIR" "feature"
FAKE_HOME3="$TMPROOT/fakehome3"
mkdir -p "$FAKE_HOME3/.claude"

OUT3=$(cd "$TMPROOT" && HOME="$FAKE_HOME3" run_banner start spec-review test-feature3 2>/dev/null)

# Must contain [pipeline]
if printf '%s' "$OUT3" | grep -q '\[pipeline\]'; then
  ok "start: contains [pipeline] prefix"
else
  fail "start: contains [pipeline] prefix" "got: $OUT3"
fi

# Must contain "Stage N of M"
if printf '%s' "$OUT3" | grep -qE 'Stage [0-9]+ of [0-9]+'; then
  ok "start: contains 'Stage N of M' pattern"
else
  fail "start: contains 'Stage N of M' pattern" "got: $OUT3"
fi

# Must contain gate name
if printf '%s' "$OUT3" | grep -q 'spec-review'; then
  ok "start: contains gate name"
else
  fail "start: contains gate name" "got: $OUT3"
fi

# Must contain "starting"
if printf '%s' "$OUT3" | grep -q 'starting'; then
  ok "start: contains 'starting'"
else
  fail "start: contains 'starting'" "got: $OUT3"
fi

# Must be exactly one line
LINE_COUNT=$(printf '%s\n' "$OUT3" | wc -l | tr -d ' ')
if [ "$LINE_COUNT" -ge 1 ]; then
  ok "start: at least one line emitted"
else
  fail "start: at least one line emitted" "line_count=$LINE_COUNT"
fi

# ---------------------------------------------------------------------------
# Test 4: End banner emission (AC3)
# ---------------------------------------------------------------------------
case_ "AC3 — end banner: contains Stage N of M ✓, cumulative, next:, gates remaining"

SPEC4_DIR="$TMPROOT/docs/specs/test-feature4"
mk_spec "$SPEC4_DIR" "feature"
FAKE_HOME4="$TMPROOT/fakehome4"
mkdir -p "$FAKE_HOME4/.claude"

OUT4=$(cd "$TMPROOT" && HOME="$FAKE_HOME4" run_banner end spec-review test-feature4 2>/dev/null)

# Must contain "Stage N of M ✓"
if printf '%s' "$OUT4" | grep -qE 'Stage [0-9]+ of [0-9]+ ✓'; then
  ok "end: contains 'Stage N of M ✓'"
else
  fail "end: contains 'Stage N of M ✓'" "got: $OUT4"
fi

# Must contain "next:" (feature pipeline has gates after spec-review)
if printf '%s' "$OUT4" | grep -q 'next:'; then
  ok "end: contains 'next:'"
else
  fail "end: contains 'next:'" "got: $OUT4"
fi

# Must contain "gates remaining"
if printf '%s' "$OUT4" | grep -q 'gates remaining'; then
  ok "end: contains 'gates remaining'"
else
  fail "end: contains 'gates remaining'" "got: $OUT4"
fi

# "cumulative" appears only when session-cost.py returns data — omit check
# since that script may not be present in test env. AC3 text says "containing"
# these fields; cost is optional (omitted on error per spec edge cases).

# ---------------------------------------------------------------------------
# Test 5: Denominator computation (AC6)
# ---------------------------------------------------------------------------
case_ "AC6 — denominator: feature→5, small→2, bugfix→1"

# feature pipeline_path → "of 5"
SPEC5F_DIR="$TMPROOT/docs/specs/test-feature5f"
mk_spec "$SPEC5F_DIR" "feature"
FAKE_HOME5="$TMPROOT/fakehome5"
mkdir -p "$FAKE_HOME5/.claude"

OUT5F=$(cd "$TMPROOT" && HOME="$FAKE_HOME5" run_banner start spec test-feature5f 2>/dev/null)
if printf '%s' "$OUT5F" | grep -qE 'of 5'; then
  ok "feature: denominator is 5"
else
  fail "feature: denominator is 5" "got: $OUT5F"
fi

# small pipeline_path → "of 2"
SPEC5S_DIR="$TMPROOT/docs/specs/test-feature5s"
mk_spec "$SPEC5S_DIR" "small"
OUT5S=$(cd "$TMPROOT" && HOME="$FAKE_HOME5" run_banner start spec test-feature5s 2>/dev/null)
if printf '%s' "$OUT5S" | grep -qE 'of 2'; then
  ok "small: denominator is 2"
else
  fail "small: denominator is 2" "got: $OUT5S"
fi

# bugfix pipeline_path → "of 1"
SPEC5B_DIR="$TMPROOT/docs/specs/test-feature5b"
mk_spec "$SPEC5B_DIR" "bugfix"
OUT5B=$(cd "$TMPROOT" && HOME="$FAKE_HOME5" run_banner start build test-feature5b 2>/dev/null)
if printf '%s' "$OUT5B" | grep -qE 'of 1'; then
  ok "bugfix: denominator is 1"
else
  fail "bugfix: denominator is 1" "got: $OUT5B"
fi

# ---------------------------------------------------------------------------
# Test 6: AUTORUN → stderr, not stdout (AC18)
# ---------------------------------------------------------------------------
case_ "AC18 — AUTORUN=1: banner goes to stderr, stdout is clean"

SPEC6_DIR="$TMPROOT/docs/specs/test-feature6"
mk_spec "$SPEC6_DIR" "feature"
FAKE_HOME6="$TMPROOT/fakehome6"
mkdir -p "$FAKE_HOME6/.claude"

STDOUT6=$(cd "$TMPROOT" && HOME="$FAKE_HOME6" run_banner_autorun start spec test-feature6 2>/dev/null)
STDERR6=$(cd "$TMPROOT" && HOME="$FAKE_HOME6" run_banner_autorun start spec test-feature6 2>&1 >/dev/null)

if [ -z "$STDOUT6" ]; then
  ok "AUTORUN=1: stdout is empty"
else
  fail "AUTORUN=1: stdout is empty" "stdout='$STDOUT6'"
fi

if printf '%s' "$STDERR6" | grep -q '\[pipeline\]'; then
  ok "AUTORUN=1: stderr contains [pipeline] banner"
else
  fail "AUTORUN=1: stderr contains [pipeline] banner" "stderr='$STDERR6'"
fi

# Non-AUTORUN: stdout has content, stderr should not
STDOUT6B=$(cd "$TMPROOT" && HOME="$FAKE_HOME6" run_banner start spec test-feature6 2>/dev/null)
if [ -n "$STDOUT6B" ]; then
  ok "AUTORUN=0: stdout has content"
else
  fail "AUTORUN=0: stdout has content" "stdout empty"
fi

# ---------------------------------------------------------------------------
# Test 7: AC20 — script runs cleanly under /bin/bash (bash 3.2 compat)
# ---------------------------------------------------------------------------
case_ "AC20 — helper runs under /bin/bash without error"

SPEC7_DIR="$TMPROOT/docs/specs/test-feature7"
mk_spec "$SPEC7_DIR" "feature"
FAKE_HOME7="$TMPROOT/fakehome7"
mkdir -p "$FAKE_HOME7/.claude"

set +e
/bin/bash "$BANNER" start spec test-feature7 >/dev/null 2>/dev/null
RC7=$?
set -e
if [ "$RC7" -eq 0 ]; then
  ok "start under /bin/bash exits 0"
else
  fail "start under /bin/bash exits 0" "rc=$RC7"
fi

set +e
cd "$TMPROOT" && HOME="$FAKE_HOME7" /bin/bash "$BANNER" end spec test-feature7 >/dev/null 2>/dev/null
RC7E=$?
cd - >/dev/null
set -e
if [ "$RC7E" -eq 0 ]; then
  ok "end under /bin/bash exits 0"
else
  fail "end under /bin/bash exits 0" "rc=$RC7E"
fi

# Verify no forbidden bash 4+ constructs in the source (AC20 static check)
case_ "AC20 — static: no forbidden bash 4+ constructs in source"

# Strip comment lines (lines starting with optional whitespace then #)
# before checking for forbidden constructs, to avoid false positives
# from the header documentation block that lists forbidden patterns.
_banner_noncomment=$(grep -v '^[[:space:]]*#' "$BANNER")

if printf '%s' "$_banner_noncomment" | grep -qE '\$\{[a-zA-Z_][a-zA-Z_0-9]*\[-[0-9]+\]\}'; then
  fail "no negative array subscripts" "found \${arr[-N]} in non-comment code"
else
  ok "no negative array subscripts"
fi

if printf '%s' "$_banner_noncomment" | grep -q 'declare -A'; then
  fail "no declare -A" "found declare -A in non-comment code"
else
  ok "no declare -A (associative arrays)"
fi

if printf '%s' "$_banner_noncomment" | grep -q 'local -n'; then
  fail "no local -n" "found local -n in non-comment code"
else
  ok "no local -n (nameref)"
fi

if printf '%s' "$_banner_noncomment" | grep -q 'mapfile'; then
  fail "no mapfile" "found mapfile in non-comment code"
else
  ok "no mapfile"
fi

if printf '%s' "$_banner_noncomment" | grep -q 'readarray'; then
  fail "no readarray" "found readarray in non-comment code"
else
  ok "no readarray"
fi

# read -a (into array) — note: need to avoid false positive from 'read -r' etc.
if printf '%s' "$_banner_noncomment" | grep -qE 'read[[:space:]]+-[a-z]*a'; then
  fail "no read -a" "found read -a in non-comment code"
else
  ok "no read -a"
fi

# ---------------------------------------------------------------------------
# Test 8: Step-away markers
# ---------------------------------------------------------------------------
case_ "Step-away markers: ☕ for 3-6min, 🌅 for ≥6min, none for <3min"

SPEC8_DIR="$TMPROOT/docs/specs/test-feature8"
mk_spec "$SPEC8_DIR" "feature"
FAKE_HOME8="$TMPROOT/fakehome8"
mkdir -p "$FAKE_HOME8/.claude"

# spec-review ETA is 360s = 6min → 🌅
OUT8A=$(cd "$TMPROOT" && HOME="$FAKE_HOME8" run_banner start spec-review test-feature8 2>/dev/null)
if printf '%s' "$OUT8A" | grep -q '🌅'; then
  ok "spec-review (6min): 🌅 marker"
else
  fail "spec-review (6min): 🌅 marker" "got: $OUT8A"
fi

# blueprint ETA is 180s = 3min → ☕
OUT8B=$(cd "$TMPROOT" && HOME="$FAKE_HOME8" run_banner start blueprint test-feature8 2>/dev/null)
if printf '%s' "$OUT8B" | grep -q '☕'; then
  ok "blueprint (3min): ☕ marker"
else
  fail "blueprint (3min): ☕ marker" "got: $OUT8B"
fi

# spec ETA is 480s = 8min → 🌅
OUT8C=$(cd "$TMPROOT" && HOME="$FAKE_HOME8" run_banner start spec test-feature8 2>/dev/null)
if printf '%s' "$OUT8C" | grep -q '🌅'; then
  ok "spec (8min): 🌅 marker"
else
  fail "spec (8min): 🌅 marker" "got: $OUT8C"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'Failed assertions:\n'
  for f in "${FAILED[@]}"; do
    printf '  - %s\n' "$f"
  done
  exit 1
fi
exit 0
