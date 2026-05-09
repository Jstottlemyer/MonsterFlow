#!/usr/bin/env bash
##############################################################################
# tests/test-gate-helpers.sh
#
# Unit tests for scripts/_gate_helpers.sh (pipeline-gate-permissiveness W3.4).
# Bash 3.2 compatible.
##############################################################################
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HELPERS="$REPO_ROOT/scripts/_gate_helpers.sh"

if [ ! -f "$HELPERS" ]; then
  printf "FAIL: %s missing\n" "$HELPERS" >&2
  exit 1
fi

# Source under test (must not abort the test runner).
# shellcheck source=/dev/null
. "$HELPERS"

TMPROOT="$(mktemp -d -t "gate-helpers-test.XXXXXX")"
trap 'rm -rf "$TMPROOT"' EXIT

PASS=0
FAIL=0
FAILED=()

ok()    { PASS=$(( PASS + 1 )); printf "  PASS %s\n" "$1"; }
fail()  { FAIL=$(( FAIL + 1 )); FAILED+=("$1"); printf "  FAIL %s -- %s\n" "$1" "$2"; }
case_() { printf "\n--- %s\n" "$1"; }

# ---------------------------------------------------------------------------
# Fixture builders
# ---------------------------------------------------------------------------
mk_spec() {
  # mk_spec <out-path> <gate_mode-or-empty> <gate_max_recycles-or-empty>
  out="$1"; mode="$2"; recycles="$3"
  d=$(dirname "$out")
  mkdir -p "$d"
  {
    printf '%s\n' '---'
    printf '%s\n' 'feature: test-fixture'
    [ -n "$mode" ]     && printf 'gate_mode: %s\n' "$mode"
    [ -n "$recycles" ] && printf 'gate_max_recycles: %s\n' "$recycles"
    printf '%s\n' '---'
    printf '%s\n' ''
    printf '%s\n' '# Fixture'
  } > "$out"
}

mk_spec_no_frontmatter() {
  out="$1"
  d=$(dirname "$out")
  mkdir -p "$d"
  printf '# Fixture without frontmatter\n' > "$out"
}

# ---------------------------------------------------------------------------
# Test 1: gate_max_recycles_clamp HARDCODED returns 3 (DEPRECATED 2026-05-09 —
# frontmatter value ignored; was clamp range [1,5] with default 2)
# ---------------------------------------------------------------------------
case_ "gate_max_recycles_clamp absent field -> hardcoded 3, no warning, no sentinel"
SPEC1_DIR="$TMPROOT/t1"
SPEC1="$SPEC1_DIR/spec.md"
mk_spec "$SPEC1" "permissive" ""

OUT=$(gate_max_recycles_clamp "$SPEC1" 2>"$TMPROOT/t1.err")
ERR=$(cat "$TMPROOT/t1.err")
if [ "$OUT" = "3" ]; then ok "hardcoded 3 returned"; else fail "hardcoded 3 returned" "got '$OUT'"; fi
if [ -z "$ERR" ];   then ok "no warning when field absent"; else fail "no warning when field absent" "stderr='$ERR'"; fi
if [ ! -f "$SPEC1_DIR/.recycles-deprecated" ]; then ok "no deprecation sentinel"; else fail "no deprecation sentinel" "sentinel exists"; fi

# ---------------------------------------------------------------------------
# Test 2: deprecated frontmatter value -> still returns 3 + emits one-time warning
# ---------------------------------------------------------------------------
case_ "gate_max_recycles_clamp deprecated frontmatter value -> 3 + deprecation warning + sentinel suppresses"
SPEC2_DIR="$TMPROOT/t2"
SPEC2="$SPEC2_DIR/spec.md"
mk_spec "$SPEC2" "permissive" "10"

OUT=$(gate_max_recycles_clamp "$SPEC2" 2>"$TMPROOT/t2.err1")
ERR=$(cat "$TMPROOT/t2.err1")
if [ "$OUT" = "3" ]; then ok "deprecated value still returns 3"; else fail "deprecated value still returns 3" "got '$OUT'"; fi
case "$ERR" in
  *DEPRECATED*) ok "deprecation warning emitted on first call" ;;
  *) fail "deprecation warning emitted on first call" "stderr='$ERR'" ;;
esac
if [ -f "$SPEC2_DIR/.recycles-deprecated" ]; then ok "deprecation sentinel created"; else fail "deprecation sentinel created" "no sentinel"; fi

# Second call: warning must be silent
OUT=$(gate_max_recycles_clamp "$SPEC2" 2>"$TMPROOT/t2.err2")
ERR=$(cat "$TMPROOT/t2.err2")
if [ "$OUT" = "3" ]; then ok "second call still returns 3"; else fail "second call still returns 3" "got '$OUT'"; fi
if [ -z "$ERR" ]; then ok "second call silent"; else fail "second call silent" "stderr='$ERR'"; fi

# ---------------------------------------------------------------------------
# Test 3: is_ci_env truthy values for $CI
# ---------------------------------------------------------------------------
case_ "is_ci_env (CI)"
for v in true 1 yes TRUE YES; do
  ( CI="$v" AUTORUN_STAGE='' is_ci_env ) && ok "CI=$v truthy" || fail "CI=$v truthy" "expected 0"
done
for v in false 0; do
  ( CI="$v" AUTORUN_STAGE='' is_ci_env ) && fail "CI=$v falsy" "expected non-zero" || ok "CI=$v falsy"
done
( CI='' AUTORUN_STAGE='' is_ci_env ) && fail "CI='' falsy" "expected non-zero" || ok "CI='' falsy"
( unset CI; unset AUTORUN_STAGE; is_ci_env ) && fail "CI unset falsy" "expected non-zero" || ok "CI unset falsy"

# ---------------------------------------------------------------------------
# Test 4: is_ci_env truthy values for $AUTORUN_STAGE
# ---------------------------------------------------------------------------
case_ "is_ci_env (AUTORUN_STAGE)"
for v in true 1 yes TRUE YES; do
  ( unset CI; AUTORUN_STAGE="$v" is_ci_env ) && ok "AUTORUN_STAGE=$v truthy" || fail "AUTORUN_STAGE=$v truthy" "expected 0"
done
( unset CI; AUTORUN_STAGE='false' is_ci_env ) && fail "AUTORUN_STAGE=false falsy" "expected non-zero" || ok "AUTORUN_STAGE=false falsy"

# ---------------------------------------------------------------------------
# Test 5: gate_mode_resolve frontmatter=permissive + no flag -> permissive:frontmatter
# Plus: no frontmatter line at all -> permissive:default
# ---------------------------------------------------------------------------
case_ "gate_mode_resolve (frontmatter / default)"
SPEC5="$TMPROOT/t5/spec.md"
mk_spec "$SPEC5" "permissive" ""
OUT=$(gate_mode_resolve "$SPEC5" "" 2>/dev/null); RC=$?
if [ "$RC" = "0" ] && [ "$OUT" = "permissive:frontmatter" ]; then ok "permissive frontmatter"
else fail "permissive frontmatter" "rc=$RC out='$OUT'"; fi

SPEC5B="$TMPROOT/t5b/spec.md"
mk_spec "$SPEC5B" "strict" ""
OUT=$(gate_mode_resolve "$SPEC5B" "" 2>/dev/null); RC=$?
if [ "$RC" = "0" ] && [ "$OUT" = "strict:frontmatter" ]; then ok "strict frontmatter"
else fail "strict frontmatter" "rc=$RC out='$OUT'"; fi

SPEC5C="$TMPROOT/t5c/spec.md"
mk_spec "$SPEC5C" "" ""   # frontmatter block exists but no gate_mode line
OUT=$(gate_mode_resolve "$SPEC5C" "" 2>/dev/null); RC=$?
if [ "$RC" = "0" ] && [ "$OUT" = "permissive:default" ]; then ok "default when gate_mode absent"
else fail "default when gate_mode absent" "rc=$RC out='$OUT'"; fi

SPEC5D="$TMPROOT/t5d/spec.md"
mk_spec_no_frontmatter "$SPEC5D"
OUT=$(gate_mode_resolve "$SPEC5D" "" 2>/dev/null); RC=$?
if [ "$RC" = "0" ] && [ "$OUT" = "permissive:default" ]; then ok "default when no frontmatter block"
else fail "default when no frontmatter block" "rc=$RC out='$OUT'"; fi

# ---------------------------------------------------------------------------
# Test 6: gate_mode_resolve strict + --permissive -> exit 2 + ERROR
# ---------------------------------------------------------------------------
case_ "gate_mode_resolve strict frontmatter rejects --permissive"
SPEC6="$TMPROOT/t6/spec.md"
mk_spec "$SPEC6" "strict" ""
set +e
OUT=$(gate_mode_resolve "$SPEC6" "--permissive" 2>"$TMPROOT/t6.err"); RC=$?
set -e
ERR=$(cat "$TMPROOT/t6.err")
if [ "$RC" = "2" ]; then ok "exit 2 on rejection"; else fail "exit 2 on rejection" "rc=$RC"; fi
case "$ERR" in
  *ERROR*strict*--force-permissive*) ok "ERROR mentions --force-permissive" ;;
  *) fail "ERROR mentions --force-permissive" "stderr='$ERR'" ;;
esac

# ---------------------------------------------------------------------------
# Test 7: --force-permissive=<reason> on strict, CI unset -> permissive:cli-force + WARNING
# ---------------------------------------------------------------------------
case_ "gate_mode_resolve --force-permissive on strict (CI unset)"
SPEC7="$TMPROOT/t7/spec.md"
mk_spec "$SPEC7" "strict" ""
set +e
OUT=$( unset CI; unset AUTORUN_STAGE; gate_mode_resolve "$SPEC7" "--force-permissive=test reason" 2>"$TMPROOT/t7.err" ); RC=$?
set -e
ERR=$(cat "$TMPROOT/t7.err")
if [ "$RC" = "0" ] && [ "$OUT" = "permissive:cli-force" ]; then ok "cli-force resolved"
else fail "cli-force resolved" "rc=$RC out='$OUT'"; fi
case "$ERR" in
  *WARNING*--force-permissive*) ok "WARNING emitted" ;;
  *) fail "WARNING emitted" "stderr='$ERR'" ;;
esac

# ---------------------------------------------------------------------------
# Test 8: --force-permissive in CI env -> exit 2
# ---------------------------------------------------------------------------
case_ "gate_mode_resolve --force-permissive refused in CI"
SPEC8="$TMPROOT/t8/spec.md"
mk_spec "$SPEC8" "strict" ""
set +e
OUT=$( CI=true gate_mode_resolve "$SPEC8" "--force-permissive=anything" 2>"$TMPROOT/t8.err" ); RC=$?
set -e
ERR=$(cat "$TMPROOT/t8.err")
if [ "$RC" = "2" ]; then ok "refused in CI=true"; else fail "refused in CI=true" "rc=$RC out='$OUT'"; fi
case "$ERR" in
  *ERROR*CI*AUTORUN_STAGE*) ok "ERROR mentions CI/AUTORUN_STAGE" ;;
  *) fail "ERROR mentions CI/AUTORUN_STAGE" "stderr='$ERR'" ;;
esac

# AUTORUN_STAGE variant
set +e
OUT=$( unset CI; AUTORUN_STAGE=1 gate_mode_resolve "$SPEC8" "--force-permissive=x" 2>/dev/null ); RC=$?
set -e
if [ "$RC" = "2" ]; then ok "refused in AUTORUN_STAGE=1"; else fail "refused in AUTORUN_STAGE=1" "rc=$RC"; fi

# ---------------------------------------------------------------------------
# Test 8b: ambiguity — --strict --permissive together
# ---------------------------------------------------------------------------
case_ "gate_mode_resolve ambiguity rejection"
SPEC8B="$TMPROOT/t8b/spec.md"
mk_spec "$SPEC8B" "permissive" ""
set +e
OUT=$(gate_mode_resolve "$SPEC8B" "--strict --permissive" 2>"$TMPROOT/t8b.err"); RC=$?
set -e
if [ "$RC" = "2" ]; then ok "exit 2 on ambiguity"; else fail "exit 2 on ambiguity" "rc=$RC out='$OUT'"; fi

# ---------------------------------------------------------------------------
# Test 8c: --force-permissive on permissive frontmatter -> permissive:cli (no force)
# ---------------------------------------------------------------------------
case_ "gate_mode_resolve --force-permissive on permissive (no-op)"
SPEC8C="$TMPROOT/t8c/spec.md"
mk_spec "$SPEC8C" "permissive" ""
set +e
OUT=$( unset CI; unset AUTORUN_STAGE; gate_mode_resolve "$SPEC8C" "--force-permissive=hi" 2>/dev/null ); RC=$?
set -e
if [ "$RC" = "0" ] && [ "$OUT" = "permissive:cli" ]; then ok "no-op force on permissive"
else fail "no-op force on permissive" "rc=$RC out='$OUT'"; fi

# ---------------------------------------------------------------------------
# Test 9: force_permissive_audit appends a JSONL row with required keys
# ---------------------------------------------------------------------------
case_ "force_permissive_audit appends JSONL with required keys"
AUD_DIR="$TMPROOT/t9"
mkdir -p "$AUD_DIR"
force_permissive_audit "$AUD_DIR" "1" "check" "releasing hotfix"
LOG="$AUD_DIR/.force-permissive-log"
if [ -f "$LOG" ]; then ok "log file created"; else fail "log file created" "missing"; fi
ROW=$(head -n1 "$LOG")
for key in timestamp iteration gate user spec verdict_sidecar reason; do
  case "$ROW" in
    *"\"$key\""*) ok "key '$key' present" ;;
    *)            fail "key '$key' present" "row='$ROW'" ;;
  esac
done

# Validate JSON parses
if printf '%s' "$ROW" | python3 -c 'import json,sys; json.loads(sys.stdin.read())' >/dev/null 2>&1; then
  ok "row 1 parses as JSON"
else
  fail "row 1 parses as JSON" "row='$ROW'"
fi

# Append a second row; verify two lines present.
force_permissive_audit "$AUD_DIR" "2" "check" "second"
COUNT=$(wc -l < "$LOG" | tr -d ' ')
if [ "$COUNT" = "2" ]; then ok "two rows appended"; else fail "two rows appended" "count=$COUNT"; fi

# ---------------------------------------------------------------------------
# Test 10: reason containing quotes -> JSON valid
# ---------------------------------------------------------------------------
case_ "force_permissive_audit JSON-escapes embedded quotes/backslashes"
AUD2_DIR="$TMPROOT/t10"
mkdir -p "$AUD2_DIR"
force_permissive_audit "$AUD2_DIR" "1" "check" 'hot"fix with \backslash and "quotes"'
LOG2="$AUD2_DIR/.force-permissive-log"
ROW=$(cat "$LOG2")
if printf '%s' "$ROW" | python3 -c 'import json,sys; json.loads(sys.stdin.read())' >/dev/null 2>&1; then
  ok "tricky reason still valid JSON"
else
  fail "tricky reason still valid JSON" "row='$ROW'"
fi

# Verify reason round-trips
ROUND=$(printf '%s' "$ROW" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["reason"])')
EXPECTED='hot"fix with \backslash and "quotes"'
if [ "$ROUND" = "$EXPECTED" ]; then ok "reason round-trips"; else fail "reason round-trips" "got='$ROUND'"; fi

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
