#!/usr/bin/env bash
##############################################################################
# tests/test-prompt-inventory.sh
#
# AC1b enforcement (pipeline-pacing-and-prefill T6 / D9).
#
# Reads tests/fixtures/prompt-inventory.txt — the locked manifest of every
# active user-facing approval prompt across commands/*.md (excluding
# commands/build.md, which T8 owns, and commands/preship.md, which doesn't
# exist — it's a skill at ~/.claude/skills/preship/).
#
# For every row "<file>:<line>:<stable-substring>" the test asserts the
# stable substring still appears somewhere in <file>. The line number is
# documentation only — it shifts when prompts get expanded into a/b/c form.
# What matters is that the prompt SURVIVES the rewrite (didn't get accidentally
# deleted or so heavily reworded that its anchor phrase is gone).
##############################################################################
set -u

# Resolve repo root from this script's location (tests/ → repo root).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$REPO_ROOT/tests/fixtures/prompt-inventory.txt"

if [ ! -f "$MANIFEST" ]; then
  printf '[FAIL] manifest not found: %s\n' "$MANIFEST" >&2
  exit 1
fi

fail_count=0
check_count=0

while IFS= read -r line; do
  # Skip comments and blank lines.
  case "$line" in
    '#'*|'') continue ;;
  esac

  # Parse "file:lineno:substring" — substring may itself contain colons,
  # so only split on the first two.
  file_part="${line%%:*}"
  rest="${line#*:}"
  # rest is "lineno:substring"
  line_part="${rest%%:*}"
  substring="${rest#*:}"

  if [ -z "$file_part" ] || [ -z "$substring" ]; then
    printf '[FAIL] malformed manifest row: %s\n' "$line" >&2
    fail_count=$((fail_count + 1))
    continue
  fi

  target="$REPO_ROOT/$file_part"
  check_count=$((check_count + 1))

  if [ ! -f "$target" ]; then
    printf '[FAIL] manifest references missing file: %s\n' "$file_part" >&2
    fail_count=$((fail_count + 1))
    continue
  fi

  # grep -F (fixed string, no regex), exact substring match.
  if ! grep -qF "$substring" "$target"; then
    printf '[FAIL] %s no longer contains anchor: %s (was at line %s)\n' \
      "$file_part" "$substring" "$line_part" >&2
    fail_count=$((fail_count + 1))
  fi
done < "$MANIFEST"

if [ "$fail_count" -gt 0 ]; then
  printf '[FAIL] test-prompt-inventory.sh: %d/%d anchors missing\n' \
    "$fail_count" "$check_count" >&2
  exit 1
fi

printf '[PASS] test-prompt-inventory.sh: %d/%d anchors present\n' \
  "$check_count" "$check_count"
exit 0
