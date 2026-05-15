#!/usr/bin/env bash
##############################################################################
# tests/test-pipeline-eta-fallback.sh
#
# AC4: _pipeline_eta.py returns documented defaults exact:
#   spec=480, spec-review=360, blueprint=180, check=300, build=900
# Unknown gate returns 300 (median fallback).
# --feature flag is accepted and does not change output (v0.14 fallback-only).
# Exit 0 always.
##############################################################################
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
ETA="$REPO/scripts/_pipeline_eta.py"

PASS=0
FAIL=0

_check() {
  local desc="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc — expected '$expected', got '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

_check_exit() {
  local desc="$1"
  local code="$2"
  if [ "$code" -eq 0 ]; then
    echo "PASS: $desc exits 0"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc exited $code (expected 0)"
    FAIL=$((FAIL + 1))
  fi
}

# ── 1. Known gates return exact defaults ─────────────────────────────────────

out=$(python3 "$ETA" --gate spec)
_check "spec default 480" "480" "$out"

out=$(python3 "$ETA" --gate spec-review)
_check "spec-review default 360" "360" "$out"

out=$(python3 "$ETA" --gate blueprint)
_check "blueprint default 180" "180" "$out"

out=$(python3 "$ETA" --gate check)
_check "check default 300" "300" "$out"

out=$(python3 "$ETA" --gate build)
_check "build default 900" "900" "$out"

# ── 2. Unknown gate returns 300 ───────────────────────────────────────────────

out=$(python3 "$ETA" --gate totally-unknown-gate)
_check "unknown gate returns 300" "300" "$out"

# ── 3. --feature flag accepted, output unchanged ──────────────────────────────

out=$(python3 "$ETA" --gate spec --feature my-feature-slug)
_check "--feature flag accepted, spec still 480" "480" "$out"

out=$(python3 "$ETA" --gate build --feature another-slug)
_check "--feature flag accepted, build still 900" "900" "$out"

# ── 4. Exit 0 always (known and unknown gates) ───────────────────────────────

python3 "$ETA" --gate spec > /dev/null 2>&1
_check_exit "spec exits 0" "$?"

python3 "$ETA" --gate no-such-gate > /dev/null 2>&1
_check_exit "unknown gate exits 0" "$?"

# ── 5. Output is exactly one line (integer only) ──────────────────────────────

linecount=$(python3 "$ETA" --gate spec | wc -l | tr -d ' ')
_check "spec output is exactly 1 line" "1" "$linecount"

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -eq 0 ]; then
  exit 0
else
  exit 1
fi
