#!/usr/bin/env bash
##############################################################################
# tests/test-dashboard-recovery.sh — token-economics T-TEST-9 (A12)
#
# Asserts the salt-corruption recovery path produces a "fresh-install"
# dashboard state (per e12) — NOT a blank table or a JS error. The full
# behavioral contract (per `compute-persona-value.py` get_or_create_salt):
#
#   On any salt-file failure (truncated, world-readable, all-zero, missing):
#     - regenerate atomically via O_CREAT|O_EXCL with chmod 0o600,
#     - WIPE three derived artifacts (lockstep w/ SEC-5):
#         dashboard/data/persona-rankings.jsonl
#         dashboard/data/persona-rankings-bundle.js
#         dashboard/data/persona-insights-bundle.js
#     - emit `[persona-value] regenerated_salt_cleared_rankings` to stderr.
#
# Test plan:
#   1. In an isolated XDG_CONFIG_HOME, place a 5-byte (truncated) salt.
#   2. Pre-create the three derived artifacts with known content.
#   3. Run compute-persona-value.py --dry-run --best-effort with the
#      isolated XDG_CONFIG_HOME.
#   4. Assert the salt was regenerated to exactly 32 bytes, chmod 600.
#   5. Assert all three derived artifacts were truncated to zero bytes
#      (presence stable, content cleared — dashboard renders empty/fresh).
#   6. Assert stderr contains the regenerate signal.
#
# Spec: docs/specs/token-economics/spec.md (v4.2 §Privacy salt section M7,
#       SEC-5 from /check)
# Plan: docs/specs/token-economics/plan.md (T-TEST-9, A12)
##############################################################################
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PASS=0
FAIL=0
note_pass() { PASS=$((PASS + 1)); echo "PASS: $1"; }
note_fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }

SCRIPT="scripts/compute-persona-value.py"
if [ ! -f "$SCRIPT" ]; then
  note_fail "compute-persona-value.py missing"
  echo ""
  echo "test-dashboard-recovery: $PASS passed, $FAIL failed"
  exit 1
fi

# Sandbox XDG_CONFIG_HOME so we don't touch the real ~/.config.
SANDBOX=$(mktemp -d -t monsterflow-recovery.XXXXXX)
trap 'rm -rf "$SANDBOX"' EXIT
SALT_DIR="$SANDBOX/monsterflow"
SALT_FILE="$SALT_DIR/finding-id-salt"
mkdir -p "$SALT_DIR"

# Plant a truncated (5-byte) salt — the validate-on-read should reject it.
printf 'short' > "$SALT_FILE"
chmod 0600 "$SALT_FILE"

# Pre-create derived artifacts with sentinel content.
DATA_DIR="$REPO_ROOT/dashboard/data"
mkdir -p "$DATA_DIR"

JSONL_BACKUP=""
RBUNDLE_BACKUP=""
IBUNDLE_BACKUP=""
JSONL="$DATA_DIR/persona-rankings.jsonl"
RBUNDLE="$DATA_DIR/persona-rankings-bundle.js"
IBUNDLE="$DATA_DIR/persona-insights-bundle.js"

# Save existing content (if any) to restore at end of test.
[ -f "$JSONL" ]   && JSONL_BACKUP=$(mktemp) && cp "$JSONL" "$JSONL_BACKUP"
[ -f "$RBUNDLE" ] && RBUNDLE_BACKUP=$(mktemp) && cp "$RBUNDLE" "$RBUNDLE_BACKUP"
[ -f "$IBUNDLE" ] && IBUNDLE_BACKUP=$(mktemp) && cp "$IBUNDLE" "$IBUNDLE_BACKUP"

restore_artifacts() {
  if [ -n "$JSONL_BACKUP" ];   then mv "$JSONL_BACKUP" "$JSONL";     fi
  if [ -n "$RBUNDLE_BACKUP" ]; then mv "$RBUNDLE_BACKUP" "$RBUNDLE"; fi
  if [ -n "$IBUNDLE_BACKUP" ]; then mv "$IBUNDLE_BACKUP" "$IBUNDLE"; fi
}
trap 'restore_artifacts; rm -rf "$SANDBOX"' EXIT

# Plant sentinel content.
printf '{"persona":"sentinel"}\n' > "$JSONL"
printf 'window.__PERSONA_RANKINGS = "SENTINEL";\n' > "$RBUNDLE"
printf 'window.__PERSONA_INSIGHTS = "SENTINEL";\n' > "$IBUNDLE"

# Run with the isolated XDG_CONFIG_HOME. Disable real-data scanning by
# using --dry-run + --best-effort; the salt regeneration path executes
# regardless because it's in main() before the dry-run early-return.
STDERR_LOG=$(mktemp)
trap 'restore_artifacts; rm -rf "$SANDBOX" "$STDERR_LOG"' EXIT

XDG_CONFIG_HOME="$SANDBOX" python3 "$SCRIPT" --dry-run --best-effort \
  > /dev/null 2> "$STDERR_LOG" || true

# 1. Salt was regenerated to exactly 32 bytes.
SALT_SIZE=$(wc -c < "$SALT_FILE" | tr -d ' ')
if [ "$SALT_SIZE" = "32" ]; then
  note_pass "salt regenerated to 32 bytes (was 5)"
else
  note_fail "salt size after regen: $SALT_SIZE (expected 32)"
fi

# 2. Salt is chmod 0600.
SALT_MODE=$(stat -f '%Lp' "$SALT_FILE" 2>/dev/null || stat -c '%a' "$SALT_FILE")
if [ "$SALT_MODE" = "600" ]; then
  note_pass "salt chmod 600 after regen"
else
  note_fail "salt chmod is $SALT_MODE (expected 600)"
fi

# 3. JSONL was wiped (truncated to zero bytes).
JSONL_SIZE=$(wc -c < "$JSONL" | tr -d ' ')
if [ "$JSONL_SIZE" = "0" ]; then
  note_pass "persona-rankings.jsonl truncated to zero bytes"
else
  note_fail "persona-rankings.jsonl size: $JSONL_SIZE (expected 0)"
fi

# 4. Rankings bundle was wiped.
RB_SIZE=$(wc -c < "$RBUNDLE" | tr -d ' ')
if [ "$RB_SIZE" = "0" ]; then
  note_pass "persona-rankings-bundle.js truncated to zero bytes"
else
  note_fail "persona-rankings-bundle.js size: $RB_SIZE (expected 0)"
fi

# 5. Insights bundle was wiped (SEC-5 lockstep).
IB_SIZE=$(wc -c < "$IBUNDLE" | tr -d ' ')
if [ "$IB_SIZE" = "0" ]; then
  note_pass "persona-insights-bundle.js truncated to zero bytes (SEC-5)"
else
  note_fail "persona-insights-bundle.js size: $IB_SIZE (expected 0)"
fi

# 6. Stderr contains the regenerate-cleared signal.
if grep -q "regenerated_salt_cleared_rankings" "$STDERR_LOG"; then
  note_pass "stderr emitted regenerated_salt_cleared_rankings signal"
else
  note_fail "stderr missing regenerate signal (see $STDERR_LOG)"
fi

echo ""
echo "test-dashboard-recovery: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
