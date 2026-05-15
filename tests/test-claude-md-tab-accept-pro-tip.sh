#!/usr/bin/env bash
##############################################################################
# tests/test-claude-md-tab-accept-pro-tip.sh
#
# AC7 enforcement (pipeline-pacing-and-prefill Item 4).
#
# Asserts that the project CLAUDE.md contains the "Tab-accept suggestions"
# section that documents Claude Code's built-in prompt-suggestion system
# AND the global opt-out env var.
##############################################################################
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLAUDE_MD="$REPO_ROOT/CLAUDE.md"

if [ ! -f "$CLAUDE_MD" ]; then
  printf '[FAIL] CLAUDE.md not found: %s\n' "$CLAUDE_MD" >&2
  exit 1
fi

fail_count=0

if ! grep -qF '## Tab-accept suggestions' "$CLAUDE_MD"; then
  printf '[FAIL] CLAUDE.md is missing the "## Tab-accept suggestions" heading\n' >&2
  fail_count=$((fail_count + 1))
fi

if ! grep -qF 'CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false' "$CLAUDE_MD"; then
  printf '[FAIL] CLAUDE.md is missing the CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false opt-out string\n' >&2
  fail_count=$((fail_count + 1))
fi

if [ "$fail_count" -gt 0 ]; then
  printf '[FAIL] test-claude-md-tab-accept-pro-tip.sh: %d assertion(s) failed\n' "$fail_count" >&2
  exit 1
fi

printf '[PASS] test-claude-md-tab-accept-pro-tip.sh: heading + opt-out string both present\n'
exit 0
