#!/usr/bin/env bash
##############################################################################
# tests/test-changelog-v0.14.0-entry.sh
#
# AC14 guard: assert CHANGELOG.md has a well-formed v0.14.0 entry with the
# four required items + three carve-out notes.
#
# Exit 0 = PASS; exit 1 = FAIL.
##############################################################################
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CL="$REPO/CHANGELOG.md"
FAIL=0

assert_grep() {
  local label="$1"
  local pattern="$2"
  if ! grep -qE "$pattern" "$CL"; then
    echo "FAIL: $label — pattern not found: $pattern"
    FAIL=1
  else
    echo "PASS: $label"
  fi
}

# Section header
assert_grep "v0.14.0 header"              "## \[0\.14\.0\] - 2026-05-14"

# Item 2 — pipeline progress banners
assert_grep "pipeline banners"            "Pipeline progress banners|_pipeline_banner\.sh"

# Item 3 — /compact two-path
assert_grep "compact prompting two-path"  "Two-path.*compact|compact.*two-path|/compact.*prompting|compact.*prompting"

# Item 1 — input grammar normalize
assert_grep "input grammar"               "Input grammar|input.grammar"

# Item 4 — CLAUDE.md tab-accept
assert_grep "tab-accept section"          "Tab-accept|CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION"

# Carve-out block: launchd
assert_grep "launchd carve-out"           "launchd|launchd-rebrand-cleanup"

# Carve-out block: tab-prefill dropped
assert_grep "tab-prefill dropped"         "tab-prefill|Tab-prefill"

# Carve-out block: mobile-verify → v0.14.1
assert_grep "mobile-verify carved"        "mobile.verify.*v0\.14\.1|v0\.14\.1.*mobile.verify"

if [ "$FAIL" -eq 0 ]; then
  echo ""
  echo "test-changelog-v0.14.0-entry.sh: ALL PASS"
  exit 0
else
  echo ""
  echo "test-changelog-v0.14.0-entry.sh: FAILED"
  exit 1
fi
