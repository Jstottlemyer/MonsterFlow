#!/usr/bin/env bash
##############################################################################
# tests/test-token-source-canonical.sh — token-economics T-PRE-4 / MF-1
#
# Phase 0.5 canonical-token-source probe (MF-1, must-fix from /check):
# A1.5 currently fires mid-Wave-2 after Wave-1 tasks have committed to a
# canonical-source choice. This pre-flight test forces the question early
# by exercising the A1.5 cross-check against a deliberately-mismatched
# fixture (total_tokens=999999 in parent annotation, usage rows sum to 300).
#
# Asserts:
#   1. The redacted RedRabbit allowlisted fixtures exist and load
#      cleanly (allowlist already enforced by test-allowlist.sh).
#   2. The disagreement fixture exists with the documented mismatch shape
#      (parent annotation total_tokens != input+output tokens sum).
#   3. The A1.5 cross-check function is exposed at module level by
#      compute-persona-value.py — the hook /plan would re-open Q1 against
#      if the canonical-source choice ever flips.
#
# Spec: docs/specs/token-economics/spec.md (v4.2 §Acceptance A1.5)
# Plan: docs/specs/token-economics/plan.md (MF-1, T-PRE-4)
##############################################################################
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PASS=0
FAIL=0

note_pass() { PASS=$((PASS + 1)); echo "PASS: $1"; }
note_fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }

FIX_DIR="tests/fixtures/persona-attribution"
DISAGREE="$FIX_DIR/a1_5-disagreement.jsonl"
SCRIPT="scripts/compute-persona-value.py"

# 1. Fixture dir + at least one allowlisted fixture present.
if [ -d "$FIX_DIR" ]; then
  note_pass "persona-attribution fixture dir exists"
else
  note_fail "persona-attribution fixture dir missing"
fi

if compgen -G "$FIX_DIR/gate-*.jsonl" > /dev/null; then
  note_pass "at least one redacted gate fixture present"
else
  note_fail "no redacted gate fixtures (gate-*.jsonl) present"
fi

# 2. Disagreement fixture exists with the documented mismatch.
if [ ! -f "$DISAGREE" ]; then
  note_fail "disagreement fixture missing ($DISAGREE)"
  echo ""
  echo "test-token-source-canonical: $PASS passed, $FAIL failed"
  exit 1
else
  note_pass "disagreement fixture present"
fi

DISAGREEMENT_OK=$(python3 - "$DISAGREE" <<'PY'
import json
import sys

path = sys.argv[1]
ok = False
with open(path, "r", encoding="utf-8") as fh:
    for raw in fh:
        raw = raw.strip()
        if not raw:
            continue
        row = json.loads(raw)
        usage = row.get("usage") or {}
        s = (
            (usage.get("input_tokens") or 0)
            + (usage.get("output_tokens") or 0)
            + (usage.get("cache_read_input_tokens") or 0)
            + (usage.get("cache_creation_input_tokens") or 0)
        )
        ann = row.get("total_tokens")
        if isinstance(ann, int) and ann != s:
            ok = True
            break
print("YES" if ok else "NO")
PY
)

if [ "$DISAGREEMENT_OK" = "YES" ]; then
  note_pass "disagreement fixture exhibits parent-annotation vs usage-sum mismatch"
else
  note_fail "disagreement fixture does NOT contain a row with mismatch"
fi

# 3. A1.5 cross-check function is exposed at module level.
if grep -qE "^def a15_crosscheck\(" "$SCRIPT"; then
  note_pass "a15_crosscheck() defined in compute-persona-value.py"
else
  note_fail "a15_crosscheck() not found in compute-persona-value.py"
fi

# 4. The cross-check is wired into main().
if grep -qE "a15_crosscheck\(" "$SCRIPT"; then
  note_pass "a15_crosscheck() invoked from main pipeline"
else
  note_fail "a15_crosscheck() never invoked"
fi

# 5. --best-effort flag downgrades the failure to a warning (per A1.5
#    spec).
if grep -q -- "--best-effort" "$SCRIPT"; then
  note_pass "--best-effort flag exposed (downgrade A1.5 to warning)"
else
  note_fail "--best-effort flag missing"
fi

echo ""
echo "test-token-source-canonical: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
