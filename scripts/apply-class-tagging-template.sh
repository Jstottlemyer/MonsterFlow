#!/usr/bin/env bash
##############################################################################
# scripts/apply-class-tagging-template.sh
#
# Splice the canonical class-tagging block (personas/_templates/class-tagging.md)
# into reviewer / plan / check personas. W3.1 of the
# pipeline-gate-permissiveness implementation plan.
#
# Usage:
#   apply-class-tagging-template.sh [--dry-run] <persona-path>
#   apply-class-tagging-template.sh [--dry-run] --batch
#
# Single-file mode:
#   <persona-path> is a path under personas/{review,plan,check}/.
#
# --batch mode:
#   Walks personas/{review,plan,check}/*.md and applies to every file that
#   is not already spliced (no BEGIN sentinel) and not in the
#   NOT-APPLICABLE skip list (judge.md, synthesis.md, _templates/...).
#
# --dry-run:
#   Emits a unified diff to stdout. Modifies no files. The orchestrator
#   captures via `>` redirect for human review (W3.2).
#
# Exit codes:
#   0 — success (splice applied, idempotent skip, or dry-run emitted)
#   1 — generic failure (unreadable file, missing template, etc.)
#   2 — malformed input (BEGIN sentinel present without END)
#   3 — eligibility refused (judge.md / synthesis.md / _templates/)
#
# Race-safe atomic writes are performed in scripts/_class_tagging_splice.py
# (mkstemp + os.replace, same-FS rename).
#
# Bash 3.2 compatible (macOS default). No mapfile, no `${arr[-1]}`,
# no `[[ =~ ]]`, no `&>`.
##############################################################################
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SPLICER="$SCRIPT_DIR/_class_tagging_splice.py"
TEMPLATE="$REPO_ROOT/personas/_templates/class-tagging.md"

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") [--dry-run] <persona-path>
  $(basename "$0") [--dry-run] --batch
USAGE
}

DRY_RUN=0
BATCH=0
TARGET=""

# Parse args (POSIX-friendly; no getopt(1)).
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --batch)
      BATCH=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "error: unknown flag: $1" 1>&2
      usage 1>&2
      exit 1
      ;;
    *)
      if [ -z "$TARGET" ]; then
        TARGET="$1"
      else
        echo "error: unexpected extra argument: $1" 1>&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [ ! -f "$SPLICER" ]; then
  echo "error: splicer helper missing: $SPLICER" 1>&2
  exit 1
fi
if [ ! -f "$TEMPLATE" ]; then
  echo "error: template missing: $TEMPLATE" 1>&2
  exit 1
fi

# Honor literal ~/ if the user passed it (not common, but safe).
if [ -n "$TARGET" ]; then
  case "$TARGET" in
    "~/"*) TARGET="$HOME/${TARGET#~/}" ;;
    "~")   TARGET="$HOME" ;;
  esac
fi

if [ "$BATCH" -eq 1 ] && [ -n "$TARGET" ]; then
  echo "error: --batch and <persona-path> are mutually exclusive" 1>&2
  exit 1
fi
if [ "$BATCH" -eq 0 ] && [ -z "$TARGET" ]; then
  echo "error: missing <persona-path> (or pass --batch)" 1>&2
  usage 1>&2
  exit 1
fi

run_one() {
  # $1 = path; uses outer $DRY_RUN
  _path="$1"
  if [ "$DRY_RUN" -eq 1 ]; then
    python3 "$SPLICER" --dry-run "$_path"
  else
    python3 "$SPLICER" "$_path"
  fi
  return $?
}

# --- single-file mode ---
if [ "$BATCH" -eq 0 ]; then
  run_one "$TARGET"
  rc=$?
  # In batch we add a one-line summary; in single-file mode the
  # splicer's stderr is sufficient (skip / error / silent on splice).
  if [ "$rc" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
    # Determine whether it spliced or skipped by re-reading the file.
    # The splicer already emits its own stderr line on skip; on real
    # splice, mirror a one-liner to stdout so callers see something.
    # (We only print on real-splice; skip already wrote to stderr.)
    # Check by scanning the file for the sentinel.
    if grep -q '<!-- BEGIN class-tagging -->' "$TARGET"; then
      # If the splicer already printed "skip (already spliced)" earlier
      # in stderr, we can't tell from here whether THIS run did the work.
      # Keep the surface minimal: don't double-announce.
      :
    fi
  fi
  exit "$rc"
fi

# --- batch mode ---
overall_rc=0
spliced_count=0
skipped_count=0

# bash 3.2 friendly enumeration; sorted for deterministic output.
for gate in review design check; do
  dir="$REPO_ROOT/personas/$gate"
  if [ ! -d "$dir" ]; then
    continue
  fi
  # `find ... -print | sort` keeps output deterministic on macOS BSD find.
  for f in $(find "$dir" -maxdepth 1 -type f -name "*.md" | LC_ALL=C sort); do
    base="$(basename "$f")"
    # Guard the never-splice list at the wrapper level too.
    case "$base" in
      judge.md|synthesis.md)
        echo "skip: $f (not-applicable: hand-written class-aware)"
        skipped_count=$(( skipped_count + 1 ))
        continue
        ;;
    esac
    # Idempotent pre-check (avoids spawning python on already-spliced).
    if grep -q '<!-- BEGIN class-tagging -->' "$f"; then
      echo "skip: $f (already spliced)"
      skipped_count=$(( skipped_count + 1 ))
      continue
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
      printf '\n# === %s ===\n' "$f"
      python3 "$SPLICER" --dry-run "$f"
      rc=$?
    else
      python3 "$SPLICER" "$f"
      rc=$?
      if [ "$rc" -eq 0 ]; then
        echo "splice: $f"
        spliced_count=$(( spliced_count + 1 ))
      fi
    fi
    if [ "$rc" -ne 0 ]; then
      overall_rc=1
    fi
  done
done

if [ "$DRY_RUN" -eq 0 ]; then
  echo "---"
  echo "batch: $spliced_count spliced, $skipped_count skipped"
fi

exit "$overall_rc"
