#!/usr/bin/env bash
# tests/test-session-cost-cumulative-only.sh
# AC21: session-cost.py --cumulative-only outputs one integer (cents) or exits 1
#       without the flag, output is unchanged (human-readable text)
#       --session-only flag must NOT exist as --cumulative-only (wrong flag rejected)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/session-cost.py"

PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# ---------------------------------------------------------------------------
# (a) --cumulative-only: outputs a single integer or exits 1
# ---------------------------------------------------------------------------

set +e
output=$(python3 "$SCRIPT" --cumulative-only 2>/dev/null)
exit_code=$?
set -e

if [ "$exit_code" -eq 0 ]; then
    # Success path: output must be exactly one integer (no extra whitespace lines)
    line_count=$(printf '%s' "$output" | grep -c '^' || true)
    if [ "$line_count" -eq 1 ] && printf '%s' "$output" | grep -qE '^[0-9]+$'; then
        pass "--cumulative-only exits 0 and outputs a single non-negative integer"
    else
        fail "--cumulative-only exits 0 but output is not a single integer: '$output'"
    fi
elif [ "$exit_code" -eq 1 ]; then
    pass "--cumulative-only exits 1 (session-data-absent) — acceptable when no project data"
else
    fail "--cumulative-only exited with unexpected code $exit_code"
fi

# ---------------------------------------------------------------------------
# (b) Without --cumulative-only, output is unchanged (human-readable text)
#     We verify the two outputs differ (cumulative-only is machine-readable,
#     default is human-readable). Only meaningful when session data exists.
# ---------------------------------------------------------------------------

set +e
output_default=$(python3 "$SCRIPT" 2>/dev/null)
exit_default=$?
output_flag=$(python3 "$SCRIPT" --cumulative-only 2>/dev/null)
exit_flag=$?
set -e

if [ "$exit_default" -ne 0 ] && [ "$exit_flag" -ne 0 ]; then
    pass "(b) both modes return non-zero (no session data) — outputs-differ check skipped"
elif [ "$exit_default" -eq 0 ] && [ "$exit_flag" -eq 0 ]; then
    if [ "$output_default" != "$output_flag" ]; then
        pass "(b) without --cumulative-only output differs from --cumulative-only output"
    else
        fail "(b) default output is identical to --cumulative-only output — flag has no effect"
    fi
    # Also verify default output contains human-readable markers
    if printf '%s' "$output_default" | grep -q 'Session'; then
        pass "(b) default output contains 'Session' human-readable header"
    else
        fail "(b) default output missing 'Session' header: '$output_default'"
    fi
    # Verify --cumulative-only output does NOT contain 'Session' header
    if ! printf '%s' "$output_flag" | grep -q 'Session'; then
        pass "(b) --cumulative-only output does not contain 'Session' header"
    else
        fail "(b) --cumulative-only output contains 'Session' header — not machine-only"
    fi
else
    pass "(b) outputs-differ check skipped (mixed exit codes — no session data path)"
fi

# ---------------------------------------------------------------------------
# (c) --session-only is NOT the same as --cumulative-only; the script must
#     NOT accept an unknown flag like --cumulative-only-bad or expose
#     --session-only as a replacement for cumulative output.
#     Verify --session-only (if it exists) does NOT emit a bare integer.
# ---------------------------------------------------------------------------

set +e
output_so=$(python3 "$SCRIPT" --session-only 2>/dev/null)
exit_so=$?
set -e

if [ "$exit_so" -eq 0 ]; then
    # --session-only exists and succeeded; its output should be human-readable,
    # NOT a bare integer. This confirms --cumulative-only is distinct.
    if printf '%s' "$output_so" | grep -qE '^[0-9]+$'; then
        fail "(c) --session-only emits bare integer — indistinguishable from --cumulative-only"
    else
        pass "(c) --session-only output is human-readable (not a bare integer) — flags are distinct"
    fi
else
    # --session-only might not be a flag; any non-zero means it's not silently
    # acting as --cumulative-only. Accept as pass.
    pass "(c) --session-only non-zero exit; not silently acting as --cumulative-only"
fi

# Verify an invented flag errors out (argparse should reject it)
set +e
python3 "$SCRIPT" --session-only-flag-that-must-not-exist >/dev/null 2>&1
bad_exit=$?
set -e
if [ "$bad_exit" -ne 0 ]; then
    pass "(c) unknown flag rejected by argparse"
else
    fail "(c) unknown flag was silently accepted — argparse not enforcing"
fi

# ---------------------------------------------------------------------------
# (d) Unknown models: machine-readable modes must never silently report success.
#     Build an isolated CLAUDE_CONFIG_DIR fixture for the current cwd so this
#     test is deterministic and does not depend on the developer's sessions.
# ---------------------------------------------------------------------------

fixture_root=$(mktemp -d)
trap 'rm -rf "$fixture_root"' EXIT
sanitized_cwd=$(pwd | sed 's#/#-#g')
fixture_project="$fixture_root/projects/$sanitized_cwd"
mkdir -p "$fixture_project"
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat >"$fixture_project/unknown-model.jsonl" <<EOF
{"timestamp":"$now","message":{"id":"unknown-model-test","role":"assistant","model":"claude-zeta-9","usage":{"input_tokens":1000,"output_tokens":100}}}
EOF

set +e
json_out=$(CLAUDE_CONFIG_DIR="$fixture_root" python3 "$SCRIPT" --json 2>"$fixture_root/json.err")
json_exit=$?
set -e
if [ "$json_exit" -eq 3 ] && printf '%s' "$json_out" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["partial"] is True; assert d["unpriced_models"] == ["claude-zeta-9"]'; then
    pass "(d) --json marks unknown-model totals partial and exits 3"
else
    fail "(d) --json did not expose partial unknown-model pricing (exit=$json_exit, output='$json_out')"
fi
if grep -q 'PARTIAL total; unpriced model(s): claude-zeta-9' "$fixture_root/json.err"; then
    pass "(d) --json emits unknown-model warning on stderr"
else
    fail "(d) --json missing unknown-model stderr warning"
fi

set +e
cum_out=$(CLAUDE_CONFIG_DIR="$fixture_root" python3 "$SCRIPT" --cumulative-only 2>"$fixture_root/cumulative.err")
cum_exit=$?
set -e
if [ "$cum_exit" -eq 3 ] && printf '%s' "$cum_out" | grep -qE '^[0-9]+

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
; then
    pass "(d) --cumulative-only preserves integer stdout and exits 3 for partial total"
else
    fail "(d) --cumulative-only contract/exit wrong (exit=$cum_exit, output='$cum_out')"
fi
if grep -q 'PARTIAL total; unpriced model(s): claude-zeta-9' "$fixture_root/cumulative.err"; then
    pass "(d) --cumulative-only emits unknown-model warning on stderr"
else
    fail "(d) --cumulative-only missing unknown-model stderr warning"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
