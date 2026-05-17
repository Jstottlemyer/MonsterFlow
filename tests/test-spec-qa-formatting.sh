#!/usr/bin/env bash
# spec-qa-terminal-formatting — verifies pipeline Q&A blocks use canonical
# - **a)** Text — desc form (V3). 3 anti-pattern checks.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_DIR"

SCOPE_FILES=(commands/spec.md commands/spec-review.md commands/blueprint.md commands/check.md commands/build.md commands/kickoff.md)
FAIL=0

# Discovery: every lettered-choice line in any scope file — 3 anti-pattern checks.
for f in "${SCOPE_FILES[@]}"; do
  [ -f "$f" ] || continue
  # Anti-pattern 1: old bold-bullet form "- **a) Text**" (bold extends past close-paren).
  # Discriminator: canonical form has NO space after the close-paren (`a)**`);
  # old form has a space (`a) `). Portable BSD-grep BRE.
  OLD_FORM=$(grep -nE '^[[:space:]]*-[[:space:]]*\*\*[a-z]\)[[:space:]]' "$f" || true)
  if [ -n "$OLD_FORM" ]; then
    echo "FAIL: $f contains old-form lettered-choice blocks (bold spans option text):"
    echo "$OLD_FORM" | sed 's/^/  /'
    FAIL=1
  fi
  # Anti-pattern 2: paren-bolded form "- **(a) text**" or "- **(a)** text".
  PAREN_FORM=$(grep -nE '^[[:space:]]*-[[:space:]]*\*\*\([a-z]\)' "$f" || true)
  if [ -n "$PAREN_FORM" ]; then
    echo "FAIL: $f contains paren-bolded lettered-choice blocks:"
    echo "$PAREN_FORM" | sed 's/^/  /'
    FAIL=1
  fi
  # Anti-pattern 3: raw indented form "  a) text" (no bullet, no bold).
  # Limited to scope files only (CHANGELOG, README etc. are NOT in SCOPE_FILES).
  RAW_FORM=$(grep -nE '^[[:space:]]+[a-z]\)[[:space:]]' "$f" || true)
  if [ -n "$RAW_FORM" ]; then
    echo "FAIL: $f contains raw indented lettered-choice blocks (missing bullet + bold):"
    echo "$RAW_FORM" | sed 's/^/  /'
    FAIL=1
  fi
done

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: all lettered-choice blocks in pipeline commands use V3 canonical form."
fi
exit "$FAIL"
