#!/bin/bash
##############################################################################
# tests/test-compact-prompt-path-b.sh
#
# AC5 Path B — when .compact-mode=suppress (or absent) and cumulative session
# cost exceeds $5 (500 cents), end-banner emits the cost-boundary /compact
# one-liner. When cost < $5, nothing is emitted.
#
# Strategy:
#   - Use a stub session-cost.py that returns a controlled value (cents).
#   - Write .compact-mode=suppress into a fixture spec dir under /tmp.
#   - Call _pb_maybe_compact directly in source mode.
#   - Assert emission / non-emission based on the stub return value.
#   - Verify .last-compact-suggestion sentinel is written with path=B.
#   - Verify throttle: second call within 600s is suppressed.
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

TMPDIR_TEST="$(mktemp -d -t 'test-compact-path-b.XXXXXX')"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

SPEC_DIR="$TMPDIR_TEST/docs/specs/compact-path-b-test"
mkdir -p "$SPEC_DIR"

# Write minimal spec.md
{
  printf '%s\n' '---'
  printf 'pipeline_path: feature\n'
  printf '%s\n' '---'
  printf '%s\n' '# path-b test'
} > "$SPEC_DIR/spec.md"

# Set .compact-mode = suppress
printf 'suppress\n' > "$SPEC_DIR/.compact-mode"

# ---------------------------------------------------------------------------
# Build stub HOME directory with a fake session-cost.py
# The stub prints a given cost (cents) controlled by STUB_COST_CENTS env var.
# ---------------------------------------------------------------------------
FAKE_HOME="$TMPDIR_TEST/fakehome"
mkdir -p "$FAKE_HOME/.claude/scripts"

cat > "$FAKE_HOME/.claude/scripts/session-cost.py" << 'PYSTUB'
#!/usr/bin/env python3
"""Stub session-cost.py for test-compact-prompt-path-b.sh"""
import os, sys

flag = sys.argv[1] if len(sys.argv) > 1 else ""
if flag == "--cumulative-only":
    val = os.environ.get("STUB_COST_CENTS", "")
    if val == "":
        sys.exit(1)
    print(val)
    sys.exit(0)
sys.exit(1)
PYSTUB
chmod +x "$FAKE_HOME/.claude/scripts/session-cost.py"

# ---------------------------------------------------------------------------
# Section 1: cost >= 500 cents ($5) → emit cost-boundary line
# ---------------------------------------------------------------------------
section "Path B cost >= \$5: emits cost-boundary /compact line"

rm -f "$SPEC_DIR/.last-compact-suggestion"

OUT_HIGH=$(cd "$TMPDIR_TEST" && HOME="$FAKE_HOME" STUB_COST_CENTS=600 AUTORUN=0 /bin/bash -c "
  source '$BANNER_SH'
  _pb_maybe_compact 'compact-path-b-test' '$SPEC_DIR'
" 2>/dev/null)

if printf '%s' "$OUT_HIGH" | grep -q 'session cost crossed'; then
  ok "cost=600c (>\$5): emits 'session cost crossed' line"
else
  fail "cost=600c (>\$5): emits 'session cost crossed' line" "got: [$OUT_HIGH]"
fi

if printf '%s' "$OUT_HIGH" | grep -q '/compact'; then
  ok "cost=600c: output mentions /compact"
else
  fail "cost=600c: output mentions /compact" "got: [$OUT_HIGH]"
fi

# ---------------------------------------------------------------------------
# Section 2: cost < 500 cents → no emission
# ---------------------------------------------------------------------------
section "Path B cost < \$5: no emission"

rm -f "$SPEC_DIR/.last-compact-suggestion"

OUT_LOW=$(cd "$TMPDIR_TEST" && HOME="$FAKE_HOME" STUB_COST_CENTS=200 AUTORUN=0 /bin/bash -c "
  source '$BANNER_SH'
  _pb_maybe_compact 'compact-path-b-test' '$SPEC_DIR'
" 2>/dev/null)

if [ -z "$OUT_LOW" ]; then
  ok "cost=200c (<\$5): no output"
else
  fail "cost=200c (<\$5): no output" "got: [$OUT_LOW]"
fi

# ---------------------------------------------------------------------------
# Section 3: sentinel is written with path=B after emission
# ---------------------------------------------------------------------------
section "Path B sentinel: .last-compact-suggestion written with path=B"

rm -f "$SPEC_DIR/.last-compact-suggestion"

cd "$TMPDIR_TEST" && HOME="$FAKE_HOME" STUB_COST_CENTS=600 AUTORUN=0 /bin/bash -c "
  source '$BANNER_SH'
  _pb_maybe_compact 'compact-path-b-test' '$SPEC_DIR'
" >/dev/null 2>/dev/null

if [ -f "$SPEC_DIR/.last-compact-suggestion" ]; then
  ok "sentinel created after Path B emission"
  SENTINEL_PATH=$(python3 -c "
import json, sys
try:
    d = json.loads(open(sys.argv[1]).read())
    print(d.get('path', ''))
except Exception:
    print('')
" "$SPEC_DIR/.last-compact-suggestion" 2>/dev/null)
  if [ "$SENTINEL_PATH" = "B" ]; then
    ok "sentinel path field = B"
  else
    fail "sentinel path field = B" "got: '$SENTINEL_PATH'"
  fi
else
  fail "sentinel created after Path B emission" "file absent"
fi

# ---------------------------------------------------------------------------
# Section 4: throttle — second call within 600s is suppressed
# ---------------------------------------------------------------------------
section "Path B throttle: second call within 600s → no re-emission"

# Sentinel already written from Section 3 (just seconds ago)
OUT_THROTTLED=$(cd "$TMPDIR_TEST" && HOME="$FAKE_HOME" STUB_COST_CENTS=600 AUTORUN=0 /bin/bash -c "
  source '$BANNER_SH'
  _pb_maybe_compact 'compact-path-b-test' '$SPEC_DIR'
" 2>/dev/null)

if [ -z "$OUT_THROTTLED" ]; then
  ok "throttle: second call within 600s produces no output"
else
  fail "throttle: second call within 600s produces no output" "got: [$OUT_THROTTLED]"
fi

# ---------------------------------------------------------------------------
# Section 5: cost script absent → no emission (fail-open)
# ---------------------------------------------------------------------------
section "Path B: session-cost.py absent → no emission (fail-open)"

FAKE_HOME_NO_COST="$TMPDIR_TEST/fakehome-nocost"
mkdir -p "$FAKE_HOME_NO_COST/.claude"
rm -f "$SPEC_DIR/.last-compact-suggestion"

set +e
OUT_NO_COST=$(cd "$TMPDIR_TEST" && HOME="$FAKE_HOME_NO_COST" AUTORUN=0 /bin/bash -c "
  source '$BANNER_SH'
  _pb_maybe_compact 'compact-path-b-test' '$SPEC_DIR'
" 2>/dev/null)
NO_COST_RC=$?
set -e

if [ "$NO_COST_RC" -eq 0 ]; then
  ok "session-cost.py absent: exits 0 (fail-open)"
else
  fail "session-cost.py absent: exits 0 (fail-open)" "rc=$NO_COST_RC"
fi

if [ -z "$OUT_NO_COST" ]; then
  ok "session-cost.py absent: no spurious output"
else
  fail "session-cost.py absent: no spurious output" "got: [$OUT_NO_COST]"
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
