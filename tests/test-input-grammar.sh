#!/usr/bin/env bash
##############################################################################
# tests/test-input-grammar.sh
#
# AC1 enforcement (pipeline-pacing-and-prefill T6).
#
# Asserts zero matches for legacy approval-prompt grammars in active
# prompt-emission lines across commands/*.md:
#   (1/2/3), (1/2), (yes/no), (y/n)
#
# Scope:
#   - All commands/*.md EXCEPT:
#     * commands/preship.md — does not exist (it's a skill, not a command).
#   - commands/build.md is now included (T8 normalized grammar).
#
# False-positive guard:
#   - Skip lines starting with `#` outside fenced code blocks (markdown
#     comments / headings — neither emits prompts).
#   - Skip lines INSIDE fenced code blocks (```...```), since example
#     output / historical fixture text isn't an active prompt.
#   - Skip lines INSIDE HTML comments (<!-- ... -->) for the same reason.
#
# The regex matches the literal forbidden tokens; bash 3.2-safe BRE.
##############################################################################
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMMANDS_DIR="$REPO_ROOT/commands"

if [ ! -d "$COMMANDS_DIR" ]; then
  printf '[FAIL] commands/ directory not found: %s\n' "$COMMANDS_DIR" >&2
  exit 1
fi

# Files excluded from grammar scan (nonexistent only; build.md cleaned by T8).
exclude_basename() {
  case "$1" in
    preship.md) return 0 ;;
    *) return 1 ;;
  esac
}

fail_count=0
scanned_files=0

for md in "$COMMANDS_DIR"/*.md; do
  [ -f "$md" ] || continue
  base="$(basename "$md")"
  if exclude_basename "$base"; then
    continue
  fi
  scanned_files=$((scanned_files + 1))

  # State machine: skip fenced code blocks (``` toggles) and HTML comments.
  in_fence=0
  in_html_comment=0
  lineno=0

  while IFS= read -r raw || [ -n "$raw" ]; do
    lineno=$((lineno + 1))
    # Trim leading whitespace for fence-toggle detection only.
    stripped="$raw"
    # Toggle fenced block on lines that begin with ```.
    case "$stripped" in
      '```'*)
        if [ "$in_fence" -eq 0 ]; then in_fence=1; else in_fence=0; fi
        continue
        ;;
    esac
    # HTML comment open/close detection (single-line OR multi-line).
    case "$raw" in
      *'<!--'*'-->'*) ;;  # single-line comment — fall through to other guards
      *'<!--'*) in_html_comment=1; continue ;;
      *'-->'*)
        if [ "$in_html_comment" -eq 1 ]; then
          in_html_comment=0
          continue
        fi
        ;;
    esac
    if [ "$in_fence" -eq 1 ] || [ "$in_html_comment" -eq 1 ]; then
      continue
    fi
    # Skip markdown comments / pure-heading lines that start with `#`.
    case "$raw" in
      '#'*) continue ;;
    esac

    # Forbidden grammars: (1/2), (1/2/3), (yes/no), (y/n)
    # Use grep -E for the union pattern.
    if printf '%s\n' "$raw" | grep -qE '\((1/2|1/2/3|yes/no|y/n)\)'; then
      printf '[FAIL] %s:%d uses legacy prompt grammar: %s\n' \
        "$base" "$lineno" "$raw" >&2
      fail_count=$((fail_count + 1))
    fi
  done < "$md"
done

if [ "$fail_count" -gt 0 ]; then
  printf '[FAIL] test-input-grammar.sh: %d violation(s) across %d file(s)\n' \
    "$fail_count" "$scanned_files" >&2
  exit 1
fi

printf '[PASS] test-input-grammar.sh: 0 legacy-grammar matches across %d command file(s)\n' \
  "$scanned_files"
exit 0
