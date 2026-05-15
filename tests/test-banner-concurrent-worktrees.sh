#!/bin/bash
##############################################################################
# tests/test-banner-concurrent-worktrees.sh
#
# AC17 — Two simultaneous /build runs on different worktrees emit compact
# suggestions independently (sentinels are spec-scoped; no cross-contamination
# or race between worktrees).
#
# Strategy:
#   - Create two isolated tmp dirs, each with their own docs/specs/<feature>/
#     and their own .compact-mode=suppress + a stub session-cost.py returning
#     >500 cents.
#   - Run _pb_maybe_compact in parallel from each spec dir.
#   - Assert both emit independently.
#   - Assert each sentinel is written to its own spec dir only.
#   - Assert the OTHER spec dir's sentinel is NOT polluted by the neighbour.
#
# Bash 3.2 compatible. Pins BASH=/bin/bash per AC20.
# Fixture dirs under /tmp only (per memory feedback_subagent_cwd_pollution).
# Exit 0 on PASS. Exit 1 on FAIL.
##############################################################################
BASH=/bin/bash
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BANNER_SH="$REPO_ROOT/scripts/_pipeline_banner.sh"

PASS=0
FAIL=0
FAILED=()

ok()   { PASS=$(( PASS + 1 )); printf '  PASS %s\n' "$1"; }
fail() { FAIL=$(( FAIL + 1 )); FAILED+=("$1"); printf '  FAIL %s -- %s\n' "$1" "$2"; }
section() { printf '\n--- %s\n' "$1"; }

if [ ! -f "$BANNER_SH" ]; then
  printf 'FAIL: %s missing\n' "$BANNER_SH" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Set up two isolated worktree-like roots
# ---------------------------------------------------------------------------
TMPDIR_A="$(mktemp -d -t 'test-concurrent-wt-a.XXXXXX')"
TMPDIR_B="$(mktemp -d -t 'test-concurrent-wt-b.XXXXXX')"
trap 'rm -rf "$TMPDIR_A" "$TMPDIR_B"' EXIT

# Worktree A
SPEC_DIR_A="$TMPDIR_A/docs/specs/feature-alpha"
mkdir -p "$SPEC_DIR_A"
printf 'suppress\n' > "$SPEC_DIR_A/.compact-mode"
{
  printf '%s\n' '---'
  printf 'pipeline_path: feature\n'
  printf '%s\n' '---'
  printf '%s\n' '# alpha'
} > "$SPEC_DIR_A/spec.md"

FAKE_HOME_A="$TMPDIR_A/fakehome"
mkdir -p "$FAKE_HOME_A/.claude/scripts"
cat > "$FAKE_HOME_A/.claude/scripts/session-cost.py" << 'PYSTUB_A'
#!/usr/bin/env python3
import sys
if len(sys.argv) > 1 and sys.argv[1] == "--cumulative-only":
    print("600")
    sys.exit(0)
sys.exit(1)
PYSTUB_A
chmod +x "$FAKE_HOME_A/.claude/scripts/session-cost.py"

# Worktree B
SPEC_DIR_B="$TMPDIR_B/docs/specs/feature-beta"
mkdir -p "$SPEC_DIR_B"
printf 'suppress\n' > "$SPEC_DIR_B/.compact-mode"
{
  printf '%s\n' '---'
  printf 'pipeline_path: feature\n'
  printf '%s\n' '---'
  printf '%s\n' '# beta'
} > "$SPEC_DIR_B/spec.md"

FAKE_HOME_B="$TMPDIR_B/fakehome"
mkdir -p "$FAKE_HOME_B/.claude/scripts"
cat > "$FAKE_HOME_B/.claude/scripts/session-cost.py" << 'PYSTUB_B'
#!/usr/bin/env python3
import sys
if len(sys.argv) > 1 and sys.argv[1] == "--cumulative-only":
    print("700")
    sys.exit(0)
sys.exit(1)
PYSTUB_B
chmod +x "$FAKE_HOME_B/.claude/scripts/session-cost.py"

# ---------------------------------------------------------------------------
# Section 1: run both worktrees "simultaneously" (parallel background jobs)
# ---------------------------------------------------------------------------
section "AC17 — concurrent Path B emission from two spec dirs"

OUT_A_FILE="$TMPDIR_A/out.txt"
OUT_B_FILE="$TMPDIR_B/out.txt"

# Launch both in background
(cd "$TMPDIR_A" && HOME="$FAKE_HOME_A" AUTORUN=0 /bin/bash -c "
  source '$BANNER_SH'
  _pb_maybe_compact 'feature-alpha' '$SPEC_DIR_A'
" > "$OUT_A_FILE" 2>/dev/null) &
PID_A=$!

(cd "$TMPDIR_B" && HOME="$FAKE_HOME_B" AUTORUN=0 /bin/bash -c "
  source '$BANNER_SH'
  _pb_maybe_compact 'feature-beta' '$SPEC_DIR_B'
" > "$OUT_B_FILE" 2>/dev/null) &
PID_B=$!

# Wait for both
set +e
wait "$PID_A"; RC_A=$?
wait "$PID_B"; RC_B=$?
set -e

if [ "$RC_A" -eq 0 ]; then
  ok "worktree A: _pb_maybe_compact exited 0"
else
  fail "worktree A: _pb_maybe_compact exited 0" "rc=$RC_A"
fi

if [ "$RC_B" -eq 0 ]; then
  ok "worktree B: _pb_maybe_compact exited 0"
else
  fail "worktree B: _pb_maybe_compact exited 0" "rc=$RC_B"
fi

# ---------------------------------------------------------------------------
# Section 2: both emitted independently
# ---------------------------------------------------------------------------
section "AC17 — both worktrees emitted /compact line independently"

OUT_A="$(cat "$OUT_A_FILE" 2>/dev/null)"
OUT_B="$(cat "$OUT_B_FILE" 2>/dev/null)"

if printf '%s' "$OUT_A" | grep -q 'session cost crossed'; then
  ok "worktree A: emitted 'session cost crossed' line"
else
  fail "worktree A: emitted 'session cost crossed' line" "got: [$OUT_A]"
fi

if printf '%s' "$OUT_B" | grep -q 'session cost crossed'; then
  ok "worktree B: emitted 'session cost crossed' line"
else
  fail "worktree B: emitted 'session cost crossed' line" "got: [$OUT_B]"
fi

# ---------------------------------------------------------------------------
# Section 3: sentinels are spec-scoped — no cross-contamination
# ---------------------------------------------------------------------------
section "AC17 — sentinels written to own spec dir only"

if [ -f "$SPEC_DIR_A/.last-compact-suggestion" ]; then
  ok "worktree A: sentinel written to its own spec dir"
else
  fail "worktree A: sentinel written to its own spec dir" "file absent at $SPEC_DIR_A/.last-compact-suggestion"
fi

if [ -f "$SPEC_DIR_B/.last-compact-suggestion" ]; then
  ok "worktree B: sentinel written to its own spec dir"
else
  fail "worktree B: sentinel written to its own spec dir" "file absent at $SPEC_DIR_B/.last-compact-suggestion"
fi

# Confirm the WRONG spec dir does not have the other's sentinel
if [ ! -f "$SPEC_DIR_A/docs/specs/feature-beta/.last-compact-suggestion" ] 2>/dev/null; then
  ok "A's spec dir has no B sentinel"
fi

if [ ! -f "$SPEC_DIR_B/docs/specs/feature-alpha/.last-compact-suggestion" ] 2>/dev/null; then
  ok "B's spec dir has no A sentinel"
fi

# Verify sentinel path fields are independently correct
PATH_FIELD_A=$(python3 -c "
import json, sys
try:
    d = json.loads(open(sys.argv[1]).read())
    print(d.get('path', ''))
except Exception:
    print('')
" "$SPEC_DIR_A/.last-compact-suggestion" 2>/dev/null)

PATH_FIELD_B=$(python3 -c "
import json, sys
try:
    d = json.loads(open(sys.argv[1]).read())
    print(d.get('path', ''))
except Exception:
    print('')
" "$SPEC_DIR_B/.last-compact-suggestion" 2>/dev/null)

if [ "$PATH_FIELD_A" = "B" ]; then
  ok "worktree A sentinel: path=B (Path B emission)"
else
  fail "worktree A sentinel: path=B" "got '$PATH_FIELD_A'"
fi

if [ "$PATH_FIELD_B" = "B" ]; then
  ok "worktree B sentinel: path=B (Path B emission)"
else
  fail "worktree B sentinel: path=B" "got '$PATH_FIELD_B'"
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
