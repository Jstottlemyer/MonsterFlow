#!/usr/bin/env bash
##############################################################################
# tests/test-build-final.sh — Wave 3 Task 3.5 (token-economics)
#
# Final telemetry + lint + A1.5 disagreement + A0 content sweep. Orchestrates:
#
#   1. Run tests/test-no-raw-print.sh — privacy gate (must pass)
#   2. Verify CLI flag surface in `python3 scripts/compute-persona-value.py
#      --help`:
#        - --scan-projects-root, --confirm-scan-roots, --best-effort, --out,
#          --dry-run, --explain ALL present
#        - --list-projects MUST NOT appear as a defined option (M5: removed)
#   3. A1.5 disagreement-path test (testability tightening #5):
#        Construct a tampered fixture where the parent annotation total_tokens
#        differs from the subagent JSONL final-row broad sum. Invoke engine
#        WITHOUT --best-effort → exits non-zero. Invoke WITH --best-effort →
#        exits 0 and emits safe_log("subagent_mismatch_best_effort").
#   4. A0 content checks (testability tightening #4): assert
#      docs/specs/token-economics/design/raw/spike-q1-result.md exists,
#      `wc -l > 10`, contains literal `total_tokens`, `subagents/agent-`,
#      and a `Verdict:` line. (Overlaps with test-phase-0-artifact.sh by
#      design — redundancy is OK.)
#
# Spec: docs/specs/token-economics/spec.md (v4.2 §Acceptance A0, A1.5, A10)
# Plan: docs/specs/token-economics/plan.md (v1.2 — Wave 3 task 3.5)
##############################################################################
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

SCRIPT="scripts/compute-persona-value.py"

PASS=0
FAIL=0
note_pass() { PASS=$((PASS + 1)); echo "PASS: $1"; }
note_fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }

TMP_ROOT="$(TMPDIR=/tmp mktemp -d /tmp/test-build-final-XXXXXX)"
TMP_ROOT_REAL="$(cd "$TMP_ROOT" && pwd -P)"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

# --------------------------------------------------------------------------
# 1. Run test-no-raw-print.sh.
# --------------------------------------------------------------------------
echo "=== Step 1: tests/test-no-raw-print.sh ==="
if bash "$REPO_ROOT/tests/test-no-raw-print.sh" >/dev/null 2>&1; then
  note_pass "test-no-raw-print.sh exits 0"
else
  note_fail "test-no-raw-print.sh failed"
  bash "$REPO_ROOT/tests/test-no-raw-print.sh" 2>&1 | head -20 | sed 's/^/  /'
fi

# --------------------------------------------------------------------------
# 2. CLI flag surface check (M5 + lock).
# --------------------------------------------------------------------------
echo ""
echo "=== Step 2: --help flag surface ==="
HELP_OUT="$(python3 "$SCRIPT" --help 2>&1)"

EXPECTED_FLAGS=(
  "--scan-projects-root"
  "--confirm-scan-roots"
  "--best-effort"
  "--out"
  "--dry-run"
  "--explain"
)
for flag in "${EXPECTED_FLAGS[@]}"; do
  # Match the flag at column-aligned start (argparse renders options indented).
  if printf '%s\n' "$HELP_OUT" | grep -qE "^\s*${flag}\b"; then
    note_pass "--help advertises $flag"
  else
    note_fail "--help is MISSING $flag"
  fi
done

# --list-projects must NOT appear as a defined option (it can appear inside
# help-text describing its removal — that's allowed; what we ban is it being
# listed as a flag itself).
if printf '%s\n' "$HELP_OUT" | grep -qE '^\s*--list-projects\b'; then
  note_fail "--list-projects is still a defined option (M5 says: remove)"
else
  note_pass "--list-projects NOT a defined option (M5 honored)"
fi

# --------------------------------------------------------------------------
# 3. A1.5 disagreement fixture: parent annotation says X, subagent says Y.
# --------------------------------------------------------------------------
echo ""
echo "=== Step 3: A1.5 disagreement fixture ==="

# Set up a fake $HOME with .claude/projects/<projdir>/<session>.jsonl that
# carries an Agent dispatch with the persona prompt + parent annotation
# total_tokens=100, plus the matching subagents/agent-<aid>.jsonl whose
# final assistant row's broad usage sums to 999 (deliberate mismatch).
FAKE_HOME="$TMP_ROOT/home"
mkdir -p "$FAKE_HOME"
PROJ_DIR_NAME="-tmp-a15-fixture-proj"
SESS_UUID="11111111-2222-3333-4444-555555555555"
AGENT_ID="0123456789abcdef0"  # 17 hex chars, matches _AGENT_ID_RE

CLAUDE_PROJ="$FAKE_HOME/.claude/projects/$PROJ_DIR_NAME"
SUB_DIR="$CLAUDE_PROJ/$SESS_UUID/subagents"
mkdir -p "$SUB_DIR"

PARENT_JSONL="$CLAUDE_PROJ/$SESS_UUID.jsonl"
SUB_JSONL="$SUB_DIR/agent-$AGENT_ID.jsonl"

# Build the parent JSONL — two rows: tool_use Agent dispatch + tool_result
# with the trailing annotation. We use Python to emit valid JSON.
python3 - "$PARENT_JSONL" "$AGENT_ID" <<'PY'
import json
import sys

out_path, agent_id = sys.argv[1], sys.argv[2]

tool_use_id = "toolu_test_a15_fixture_001"

# Row 1 — tool_use Agent dispatch (parent assistant message).
row1 = {
    "type": "assistant",
    "message": {
        "role": "assistant",
        "content": [
            {
                "type": "tool_use",
                "id": tool_use_id,
                "name": "Agent",
                "input": {
                    "subagent_type": "general-purpose",
                    "prompt": (
                        "You are persona personas/review/scope-discipline.md "
                        "doing a spec review. (test fixture)"
                    ),
                },
            }
        ],
    },
}
# Row 2 — tool_result with the parent annotation. Engine reads
# total_tokens: 100 from the trailing text.
row2 = {
    "type": "user",
    "message": {
        "role": "user",
        "content": [
            {
                "type": "tool_result",
                "tool_use_id": tool_use_id,
                "content": [
                    {
                        "type": "text",
                        "text": (
                            "Subagent finished.\n"
                            "agentId: {aid}\n"
                            "total_tokens: 100\n"
                        ).format(aid=agent_id),
                    }
                ],
            }
        ],
    },
}

with open(out_path, "w", encoding="utf-8") as fh:
    fh.write(json.dumps(row1) + "\n")
    fh.write(json.dumps(row2) + "\n")
PY

# Build the subagent JSONL whose final assistant row sums to 999 (deliberate
# mismatch with parent's 100).
python3 - "$SUB_JSONL" <<'PY'
import json
import sys

out_path = sys.argv[1]

# Final assistant row with usage broad-sum =
#   100 (input) + 200 (output) + 300 (cache_read) + 399 (cache_creation)
#   = 999 (mismatch with parent's 100).
row = {
    "type": "assistant",
    "message": {
        "role": "assistant",
        "content": [{"type": "text", "text": "done"}],
        "usage": {
            "input_tokens": 100,
            "output_tokens": 200,
            "cache_read_input_tokens": 300,
            "cache_creation_input_tokens": 399,
        },
    },
}
with open(out_path, "w", encoding="utf-8") as fh:
    fh.write(json.dumps(row) + "\n")
PY

# Isolated XDG so we don't touch the real config.
A15_XDG="$TMP_ROOT/xdg-a15"
mkdir -p "$A15_XDG"

# Run the engine WITHOUT --best-effort. Expect non-zero exit.
# Use a clean cwd that has NO docs/specs (so tier 1 contributes nothing) —
# we want cost_walk to find the dispatch but value_walk to be empty.
EMPTY_CWD="$TMP_ROOT/empty-cwd"
mkdir -p "$EMPTY_CWD"

A15_RC=0
A15_OUT="$(
  cd "$EMPTY_CWD" && \
  HOME="$FAKE_HOME" \
  XDG_CONFIG_HOME="$A15_XDG" \
  MONSTERFLOW_ALLOWED_ROOTS="$FAKE_HOME:$TMP_ROOT_REAL" \
  python3 "$REPO_ROOT/$SCRIPT" --dry-run </dev/null 2>&1
)" || A15_RC=$?

if [ "$A15_RC" -ne 0 ]; then
  note_pass "A1.5 mismatch — engine exits non-zero without --best-effort (rc=$A15_RC)"
else
  note_fail "A1.5 mismatch — engine should exit non-zero, got rc=0"
  printf '  output:\n%s\n' "$A15_OUT" | head -20 | sed 's/^/  /'
fi

# Confirm the failure mode messaging surfaced.
if printf '%s\n' "$A15_OUT" | grep -qiE 'A1\.5|cross-check'; then
  note_pass "A1.5 mismatch — failure message surfaces 'A1.5'/'cross-check'"
else
  note_fail "A1.5 mismatch — failure message does NOT mention 'A1.5'/'cross-check'"
  printf '  output:\n%s\n' "$A15_OUT" | head -10 | sed 's/^/  /'
fi

# Re-run WITH --best-effort. Expect exit 0 and the safe_log warning.
A15_BE_RC=0
A15_BE_OUT="$(
  cd "$EMPTY_CWD" && \
  HOME="$FAKE_HOME" \
  XDG_CONFIG_HOME="$A15_XDG" \
  MONSTERFLOW_ALLOWED_ROOTS="$FAKE_HOME:$TMP_ROOT_REAL" \
  python3 "$REPO_ROOT/$SCRIPT" --best-effort --dry-run </dev/null 2>&1
)" || A15_BE_RC=$?

if [ "$A15_BE_RC" -eq 0 ]; then
  note_pass "A1.5 mismatch + --best-effort — engine exits 0 (downgraded to warning)"
else
  note_fail "A1.5 mismatch + --best-effort — engine exit $A15_BE_RC (expected 0)"
  printf '  output:\n%s\n' "$A15_BE_OUT" | head -20 | sed 's/^/  /'
fi

if printf '%s\n' "$A15_BE_OUT" | grep -qF 'subagent_mismatch_best_effort'; then
  note_pass "A1.5 mismatch + --best-effort — emits safe_log('subagent_mismatch_best_effort')"
else
  note_fail "A1.5 mismatch + --best-effort — missing 'subagent_mismatch_best_effort' event"
  printf '  output:\n%s\n' "$A15_BE_OUT" | head -10 | sed 's/^/  /'
fi

# --------------------------------------------------------------------------
# 4. A0 content checks (overlap with test-phase-0-artifact.sh — intentional).
# --------------------------------------------------------------------------
echo ""
echo "=== Step 4: A0 spike artifact content ==="
A0_FILE="$REPO_ROOT/docs/specs/token-economics/design/raw/spike-q1-result.md"

if [ -f "$A0_FILE" ]; then
  note_pass "A0 spike artifact exists"
else
  note_fail "A0 spike artifact missing ($A0_FILE)"
fi

if [ -f "$A0_FILE" ]; then
  LINES="$(wc -l < "$A0_FILE" | tr -d '[:space:]')"
  if [ "${LINES:-0}" -gt 10 ]; then
    note_pass "A0 spike artifact line count > 10 (got $LINES)"
  else
    note_fail "A0 spike artifact line count <= 10 (got $LINES)"
  fi

  for needle in "total_tokens" "subagents/agent-"; do
    if grep -qF "$needle" "$A0_FILE"; then
      note_pass "A0 spike artifact contains literal '$needle'"
    else
      note_fail "A0 spike artifact missing literal '$needle'"
    fi
  done

  if grep -qE '^[Vv]erdict:' "$A0_FILE"; then
    note_pass "A0 spike artifact contains 'Verdict:' line"
  else
    note_fail "A0 spike artifact missing 'Verdict:' line"
  fi
fi

echo ""
echo "test-build-final: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
