#!/usr/bin/env bash
##############################################################################
# scripts/build-codex-review.sh — /build Phase 3 Codex implementation review.
#
# Usage:
#   build-codex-review.sh [--base REF] [--output FILE] [--repo DIR] [--model M]
#
# Reviews everything this build changed: the commits since the base, plus any
# uncommitted changes. /build commits each wave, so a review of uncommitted
# changes alone (`codex exec review --uncommitted`) sees nothing by Phase 3.
# `codex exec review --base` cannot take custom instructions, so this runs
# `codex exec` with the review instructions in a read-only sandbox.
#
# Base: --base, else the merge-base of HEAD with origin's default branch,
# else with `main`. Output: --output (default /tmp/codex-build-review.txt).
# Stdin is closed (< /dev/null): with stdin left open, a backgrounded
# `codex exec` blocks on "Reading additional input from stdin" forever.
#
# Exit codes:
#   0  review written to the output file, or Codex unavailable (silent skip:
#      no output file is written, matching the other gates' Codex steps)
#   2  usage error / no base could be resolved
#   4  codex exited non-zero
#
# Bash 3.2 compatible.
##############################################################################
set -uo pipefail

_self="$0"; [ -L "$_self" ] && _self="$(readlink "$_self")"
CODEX="${MONSTERFLOW_CODEX_BIN:-codex}"

usage() {
  sed -n '6,7p' "$_self" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

BASE=""
OUT="/tmp/codex-build-review.txt"
REPO=""
MODEL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base) [ $# -ge 2 ] || usage; BASE="$2"; shift 2 ;;
    --output) [ $# -ge 2 ] || usage; OUT="$2"; shift 2 ;;
    --repo) [ $# -ge 2 ] || usage; REPO="$2"; shift 2 ;;
    --model) [ $# -ge 2 ] || usage; MODEL="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "build-codex-review: unknown argument $1" >&2; usage ;;
  esac
done

if ! command -v "$CODEX" >/dev/null 2>&1 || ! "$CODEX" login status >/dev/null 2>&1; then
  exit 0
fi

[ -n "$REPO" ] || REPO="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"
if [ -z "$BASE" ]; then
  default_ref="$(git -C "$REPO" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  for ref in $default_ref origin/main main; do
    BASE="$(git -C "$REPO" merge-base HEAD "$ref" 2>/dev/null || true)"
    [ -n "$BASE" ] && break
  done
fi
if [ -z "$BASE" ]; then
  echo "build-codex-review: could not resolve a base; pass --base" >&2
  exit 2
fi
BASE_SHA="$(git -C "$REPO" rev-parse --short "$BASE" 2>/dev/null || true)"
if [ -z "$BASE_SHA" ]; then
  echo "build-codex-review: unknown base $BASE" >&2
  exit 2
fi

MODEL_ARGS=""
[ -n "$MODEL" ] && MODEL_ARGS="-m $MODEL"

INSTRUCTIONS="You are reviewing the changes on the current branch of this repository: the commits since base $BASE_SHA (inspect them with git, e.g. \`git log $BASE_SHA..HEAD\` and \`git diff $BASE_SHA..HEAD -- <paths>\`) plus any uncommitted changes (\`git status\`, \`git diff\`). The feature's spec and implementation plan are under docs/specs/<feature>/ (spec.md, design.md). Challenge the implementation. Look for: security issues, deviations from the plan, better approaches that weren't taken, and correctness problems the tests might not catch. Do not modify files. Report concrete findings ranked by severity (High/Medium/Low), each with file:line, the failure scenario and a suggested fix. If you find nothing in a category, say so."

rm -f "$OUT"
# shellcheck disable=SC2086  # MODEL_ARGS is intentionally word-split
"$CODEX" exec --cd "$REPO" $MODEL_ARGS --sandbox read-only --ephemeral \
  -o "$OUT" "$INSTRUCTIONS" < /dev/null > /dev/null 2> "$OUT.stderr"
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "build-codex-review: codex exited $rc (see $OUT.stderr)" >&2
  exit 4
fi
rm -f "$OUT.stderr"
exit 0
