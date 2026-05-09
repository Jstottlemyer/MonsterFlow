#!/usr/bin/env bash
##############################################################################
# tests/test-session-cost-import-clean.sh — token-economics T-PRE-1 (Phase 0.5)
#
# Phase 0.5 import-cleanliness gate (D2): asserts that
# `scripts/session-cost.py` can be loaded via importlib WITHOUT producing any
# stdout/stderr, calling sys.exit, or doing any I/O. This is the
# precondition for M1 — `compute-persona-value.py` imports `PRICING` and
# `entry_cost` from `session_cost` via importlib.util.spec_from_file_location.
#
# If this gate fails, the M1 strategy collapses (the import would emit CLI
# noise on every compute-persona-value run); fix path is to push CLI logic
# in session-cost.py under `if __name__ == "__main__":`.
#
# Spec: docs/specs/token-economics/spec.md (v4.2 §Integration M1)
# Plan: docs/specs/token-economics/plan.md (D2, T-PRE-1)
##############################################################################
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PASS=0
FAIL=0

note_pass() { PASS=$((PASS + 1)); echo "PASS: $1"; }
note_fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }

TARGET="scripts/session-cost.py"

if [ ! -f "$TARGET" ]; then
  note_fail "session-cost.py missing at $TARGET"
  echo ""
  echo "test-session-cost-import-clean: $PASS passed, $FAIL failed"
  exit 1
fi

# Drive the import via a Python child; capture all three streams.
RESULT=$(python3 - <<'PY' 2>&1
import importlib.util
import io
import sys
import contextlib

spec = importlib.util.spec_from_file_location(
    "session_cost", "scripts/session-cost.py"
)
mod = importlib.util.module_from_spec(spec)
buf_o, buf_e = io.StringIO(), io.StringIO()
exit_code = "ok"
try:
    with contextlib.redirect_stdout(buf_o), contextlib.redirect_stderr(buf_e):
        spec.loader.exec_module(mod)
except SystemExit as e:
    exit_code = "sys.exit({!r})".format(e.code)
except Exception as e:
    exit_code = "raised {}: {}".format(type(e).__name__, e)

# Verify expected symbols are accessible.
have_pricing = hasattr(mod, "PRICING") and isinstance(
    getattr(mod, "PRICING"), dict
)

print("STDOUT_LEN={}".format(len(buf_o.getvalue())))
print("STDERR_LEN={}".format(len(buf_e.getvalue())))
print("EXIT_PATH={}".format(exit_code))
print("HAS_PRICING={}".format(have_pricing))
PY
)

stdout_len=$(echo "$RESULT" | sed -n 's/^STDOUT_LEN=\(.*\)$/\1/p')
stderr_len=$(echo "$RESULT" | sed -n 's/^STDERR_LEN=\(.*\)$/\1/p')
exit_path=$(echo "$RESULT" | sed -n 's/^EXIT_PATH=\(.*\)$/\1/p')
has_pricing=$(echo "$RESULT" | sed -n 's/^HAS_PRICING=\(.*\)$/\1/p')

if [ "${stdout_len:-x}" = "0" ]; then
  note_pass "import emits zero stdout"
else
  note_fail "import emitted stdout (len=$stdout_len)"
fi

if [ "${stderr_len:-x}" = "0" ]; then
  note_pass "import emits zero stderr"
else
  note_fail "import emitted stderr (len=$stderr_len)"
fi

if [ "${exit_path:-x}" = "ok" ]; then
  note_pass "import does not call sys.exit / raise"
else
  note_fail "import path: $exit_path"
fi

if [ "${has_pricing:-x}" = "True" ]; then
  note_pass "PRICING attribute is accessible after import"
else
  note_fail "PRICING attribute missing after import"
fi

# Verify the CLI body lives under `if __name__ == "__main__":` (the
# structural check that matters even if a future refactor changes the
# import side effect surface).
if grep -q "^if __name__ == .__main__.:" "$TARGET"; then
  note_pass "session-cost.py CLI guarded by __name__ == '__main__'"
else
  note_fail "session-cost.py is missing __name__ == '__main__' guard"
fi

echo ""
echo "test-session-cost-import-clean: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
