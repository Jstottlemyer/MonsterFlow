#!/usr/bin/env bash
##############################################################################
# tests/test-class-tagging-spliced.sh
#
# Validates scripts/apply-class-tagging-template.sh — the W3.1 splice tool.
#
# Tests (numbered to match the W3.1 task brief):
#   1. Dry-run on synthetic persona (no sentinel) emits a unified diff that
#      adds BOTH BEGIN and END sentinels.
#   2. Real splice on synthetic persona writes the sentinels into the file.
#   3. Byte-identity (load-bearing per /check completeness MF1): content
#      between BEGIN/END in the spliced file is byte-identical to the same
#      span in personas/_templates/class-tagging.md.
#   4. Idempotency: running splice a second time on the spliced file is a
#      no-op and stderr says "skip".
#   5. Splice-point: synthetic persona with `## Output Structure` h2 lands
#      the block ABOVE that heading (not at EOF).
#   6. EOF fallback: synthetic persona with no h2 Output/Verdict heading
#      lands the block at EOF.
#   7. Eligibility refusal: scripts target on personas/judge.md exits non-zero
#      and prints an error to stderr.
#   8. Live-tree idempotency: running on personas/review/scope.md (already
#      spliced in W2.2) exits 0 with stderr "skip".
#
# Bash 3.2 / BSD-tools compatible (macOS).
##############################################################################
set -uo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ENGINE_DIR/scripts/apply-class-tagging-template.sh"
TEMPLATE="$ENGINE_DIR/personas/_templates/class-tagging.md"

PASS=0
FAIL=0
FAILED=()

note_pass() {
  PASS=$(( PASS + 1 ))
  echo "  PASS — $1"
}
note_fail() {
  FAIL=$(( FAIL + 1 ))
  FAILED+=("$1")
  echo "  FAIL — $1"
}

# Each subtest gets its own tmpdir so personas/{review,plan,check} layout
# can be created and the splicer's repo-relative eligibility check can
# pass. The splicer locates REPO_ROOT relative to its own __file__, so we
# can't move the splicer; instead we create FIXTURE personas inside the
# real personas/{review,plan,check}/ tree under randomized basenames,
# clean up unconditionally on exit.
TMPROOT="$(mktemp -d -t classtag-test.XXXXXX)"
FIXTURES=()

cleanup() {
  # Remove fixture files we wrote into the real tree (idempotent).
  for f in "${FIXTURES[@]:-}"; do
    [ -n "$f" ] && [ -f "$f" ] && rm -f "$f"
  done
  rm -rf "$TMPROOT"
}
trap cleanup EXIT INT TERM

# Unique prefix so we never collide with real persona names.
SLUG="zztest-classtag-$$-$RANDOM"

mk_fixture_path() {
  # mk_fixture_path <gate> <suffix> — print the path; does not write.
  echo "$ENGINE_DIR/personas/$1/$SLUG-$2.md"
}
write_fixture() {
  # write_fixture <path> <body> — write body, register for cleanup.
  # Called from the parent shell so FIXTURES persists.
  printf '%s' "$2" > "$1"
  FIXTURES+=("$1")
}

extract_payload_from() {
  # Print the bytes between (and including) BEGIN/END in the given file.
  awk '/<!-- BEGIN class-tagging -->/,/<!-- END class-tagging -->/' "$1"
}

echo "== test-class-tagging-spliced =="

# ----- 1: dry-run emits a diff with the sentinels added -----
NOSENT_BODY='# Test Persona

## Role
A synthetic test fixture.

## Output Structure

### Verdict
PASS / FAIL.
'
F1="$(mk_fixture_path review nosentinel-h2)"
write_fixture "$F1" "$NOSENT_BODY"
DIFF1="$("$SCRIPT" --dry-run "$F1" 2>/dev/null)"
DR_RC=$?
if [ "$DR_RC" -eq 0 ] \
  && echo "$DIFF1" | grep -q '^+<!-- BEGIN class-tagging -->' \
  && echo "$DIFF1" | grep -q '^+<!-- END class-tagging -->'; then
  note_pass "1: --dry-run emits a unified diff adding both sentinels"
else
  note_fail "1: dry-run did not emit expected diff (rc=$DR_RC)"
fi
# Sub-assert: dry-run must not modify the file.
if ! grep -q 'BEGIN class-tagging' "$F1"; then
  note_pass "1b: --dry-run leaves the file unmodified"
else
  note_fail "1b: --dry-run mutated the file"
fi

# ----- 2: real splice writes the sentinels -----
"$SCRIPT" "$F1" >/dev/null 2>&1
RC2=$?
if [ "$RC2" -eq 0 ] \
  && grep -q '<!-- BEGIN class-tagging -->' "$F1" \
  && grep -q '<!-- END class-tagging -->' "$F1"; then
  note_pass "2: real splice writes both sentinels (rc=$RC2)"
else
  note_fail "2: real splice failed (rc=$RC2 or sentinels missing)"
fi

# ----- 3: byte-identity between BEGIN/END in spliced file vs template -----
TPL_PAYLOAD="$(extract_payload_from "$TEMPLATE")"
SPL_PAYLOAD="$(extract_payload_from "$F1")"
if [ "$TPL_PAYLOAD" = "$SPL_PAYLOAD" ]; then
  note_pass "3: spliced payload byte-identical to template payload"
else
  note_fail "3: spliced payload diverged from template (LB MF1)"
  echo "    template bytes: $(printf '%s' "$TPL_PAYLOAD" | wc -c)"
  echo "    spliced bytes:  $(printf '%s' "$SPL_PAYLOAD" | wc -c)"
fi

# ----- 4: idempotency — second run is a skip with stderr message -----
SPLICED_HASH_BEFORE="$(shasum "$F1" | awk '{print $1}')"
ERR2="$("$SCRIPT" "$F1" 2>&1 >/dev/null)"
RC4=$?
SPLICED_HASH_AFTER="$(shasum "$F1" | awk '{print $1}')"
if [ "$RC4" -eq 0 ] \
  && [ "$SPLICED_HASH_BEFORE" = "$SPLICED_HASH_AFTER" ] \
  && echo "$ERR2" | grep -q "skip"; then
  note_pass "4: re-running on spliced file is a no-op and stderr says skip"
else
  note_fail "4: idempotency broken (rc=$RC4, hash-equal=$([ "$SPLICED_HASH_BEFORE" = "$SPLICED_HASH_AFTER" ] && echo Y || echo N))"
fi

# ----- 5: splice-point lands ABOVE `## Output Structure` -----
# Find line numbers; sentinel must come before heading.
LINE_BEGIN="$(grep -n '<!-- BEGIN class-tagging -->' "$F1" | head -1 | cut -d: -f1)"
LINE_HEADING="$(grep -n '^## Output Structure' "$F1" | head -1 | cut -d: -f1)"
if [ -n "$LINE_BEGIN" ] && [ -n "$LINE_HEADING" ] && [ "$LINE_BEGIN" -lt "$LINE_HEADING" ]; then
  note_pass "5: splice landed above ## Output Structure (line $LINE_BEGIN < $LINE_HEADING)"
else
  note_fail "5: splice did not land above ## Output Structure (begin=$LINE_BEGIN heading=$LINE_HEADING)"
fi

# ----- 6: EOF fallback when no h2 Output/Verdict heading -----
EOF_BODY='# Test Persona EOF
A persona with no Output or Verdict h2.

### Some h3 only
Body text.
'
F2="$(mk_fixture_path design nosentinel-eof)"
write_fixture "$F2" "$EOF_BODY"
"$SCRIPT" "$F2" >/dev/null 2>&1
RC6=$?
TOTAL_LINES="$(wc -l < "$F2" | tr -d ' ')"
LINE_END="$(grep -n '<!-- END class-tagging -->' "$F2" | head -1 | cut -d: -f1)"
if [ "$RC6" -eq 0 ] \
  && [ -n "$LINE_END" ] \
  && [ "$LINE_END" -ge "$(( TOTAL_LINES - 1 ))" ]; then
  note_pass "6: EOF fallback placed sentinels at end of file"
else
  note_fail "6: EOF fallback failed (rc=$RC6 end-line=$LINE_END total=$TOTAL_LINES)"
fi

# ----- 7: eligibility — judge.md is refused -----
ERR_JUDGE="$("$SCRIPT" --dry-run "$ENGINE_DIR/personas/judge.md" 2>&1 >/dev/null)"
RC7=$?
if [ "$RC7" -ne 0 ] && echo "$ERR_JUDGE" | grep -qi "refus\|ineligible\|hand-written"; then
  note_pass "7: personas/judge.md refused with non-zero exit + stderr error (rc=$RC7)"
else
  note_fail "7: judge.md was not refused (rc=$RC7, stderr=$ERR_JUDGE)"
fi

# ----- 8: live-tree idempotency on personas/review/scope.md -----
SCOPE_PATH="$ENGINE_DIR/personas/review/scope.md"
SCOPE_HASH_BEFORE="$(shasum "$SCOPE_PATH" | awk '{print $1}')"
ERR_SCOPE="$("$SCRIPT" "$SCOPE_PATH" 2>&1 >/dev/null)"
RC8=$?
SCOPE_HASH_AFTER="$(shasum "$SCOPE_PATH" | awk '{print $1}')"
if [ "$RC8" -eq 0 ] \
  && [ "$SCOPE_HASH_BEFORE" = "$SCOPE_HASH_AFTER" ] \
  && echo "$ERR_SCOPE" | grep -q "skip"; then
  note_pass "8: scope.md (already spliced) skipped without modification"
else
  note_fail "8: scope.md idempotency failed (rc=$RC8, modified=$([ "$SCOPE_HASH_BEFORE" = "$SCOPE_HASH_AFTER" ] && echo N || echo Y))"
fi

# ----- 9: byte-identity vs scope.md payload too (live-tree LB MF1) -----
SCOPE_PAYLOAD="$(extract_payload_from "$SCOPE_PATH")"
if [ "$TPL_PAYLOAD" = "$SCOPE_PAYLOAD" ]; then
  note_pass "9: scope.md payload byte-identical to template (live-tree)"
else
  note_fail "9: scope.md payload drifted from template (W2.2 regression)"
fi

# ----- summary -----
echo
echo "== summary =="
echo "  pass: $PASS"
echo "  fail: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  for f in "${FAILED[@]}"; do echo "    - $f"; done
  exit 1
fi
exit 0
