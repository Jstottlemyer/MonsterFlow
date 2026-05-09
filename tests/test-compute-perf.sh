#!/usr/bin/env bash
##############################################################################
# tests/test-compute-perf.sh — token-economics T-TEST-10 (tv-3 hard ceiling)
#
# Non-functional perf gate. Asserts `compute-persona-value.py --dry-run`
# completes within a budget on this machine's `~/.claude/projects/`.
#
# tv-3 (must-fix from /check, testability): hard-fail at 3× budget,
# warn at 1× budget. Soft-fail-only ships regressions silently.
#   - WARN_BUDGET_S = 5
#   - HARD_BUDGET_S = 15
#
# A1.5 cross-check fails on real session data (the fixtures contain
# mismatches by design — see tests/test-token-source-canonical.sh), so we
# pass --best-effort to downgrade the cross-check to a warning. The script
# still does the full discovery + cost + value walks; we are timing those.
#
# Spec: docs/specs/token-economics/plan.md (T-TEST-10, R5)
# Plan: docs/specs/token-economics/check.md (tv-3)
##############################################################################
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

WARN_BUDGET_S=5
HARD_BUDGET_S=15

PASS=0
FAIL=0
note_pass() { PASS=$((PASS + 1)); echo "PASS: $1"; }
note_fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }

SCRIPT="scripts/compute-persona-value.py"

if [ ! -f "$SCRIPT" ]; then
  note_fail "compute-persona-value.py missing"
  echo ""
  echo "test-compute-perf: $PASS passed, $FAIL failed"
  exit 1
fi

# Time a --dry-run --best-effort invocation. Use python3's monotonic clock
# so we don't depend on /usr/bin/time output formatting.
ELAPSED=$(python3 - "$SCRIPT" <<'PY'
import subprocess
import sys
import time

script = sys.argv[1]
t0 = time.monotonic()
subprocess.run(
    ["python3", script, "--dry-run", "--best-effort"],
    capture_output=True,
    timeout=60,
)
elapsed = time.monotonic() - t0
print("{:.3f}".format(elapsed))
PY
)

# Floating-point compare in shell — use python3.
CLASSIFY=$(python3 - "$ELAPSED" "$WARN_BUDGET_S" "$HARD_BUDGET_S" <<'PY'
import sys

elapsed = float(sys.argv[1])
warn = float(sys.argv[2])
hard = float(sys.argv[3])

if elapsed >= hard:
    print("HARD")
elif elapsed >= warn:
    print("WARN")
else:
    print("OK")
PY
)

case "$CLASSIFY" in
  OK)
    note_pass "compute-persona-value --dry-run completed in ${ELAPSED}s (under ${WARN_BUDGET_S}s budget)"
    ;;
  WARN)
    # Soft warning — still passes the test but emits a stderr nudge.
    echo "WARN: compute-persona-value --dry-run took ${ELAPSED}s (>${WARN_BUDGET_S}s budget; <${HARD_BUDGET_S}s hard ceiling)" >&2
    note_pass "perf within hard ceiling (${ELAPSED}s)"
    ;;
  HARD)
    note_fail "compute-persona-value --dry-run took ${ELAPSED}s (>=${HARD_BUDGET_S}s hard ceiling)"
    ;;
  *)
    note_fail "unexpected classify output: $CLASSIFY"
    ;;
esac

echo ""
echo "test-compute-perf: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
