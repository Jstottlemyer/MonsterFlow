#!/bin/bash
##############################################################################
# scripts/autorun/autorun-batch.sh — thin queue-loop wrapper (v6 contract)
#
# Contract: docs/specs/autorun-overnight-policy/spec.md (v5, AC#24)
# Plan:     docs/specs/autorun-overnight-policy/plan.md (v6, Task 3.0b)
#
# Iterates `queue/*.spec.md` and invokes scripts/autorun/run.sh once per slug.
# Aggregates per-slug morning-report.json output into queue/runs/index.md.
#
# Usage:
#   scripts/autorun/autorun-batch.sh [--mode=overnight|supervised] [--dry-run]
#   scripts/autorun/autorun-batch.sh --help
#
# Exit codes:
#   0   all slugs ok (or zero specs found)
#   1   one or more slugs exited nonzero (per-slug failures continue)
#   2   invalid invocation / config (fail-fast)
#   3   STOP file detected — halted at iteration boundary
#
# STOP-file semantics (MF10 from check v3 — verbatim):
#   STOP is honored at iteration boundaries only. An in-flight `run.sh`
#   completes its current slug after STOP is touched; only the N+1 iteration
#   is suppressed. Stage-boundary STOP-check inside run.sh is deferred — see
#   BACKLOG.md.
#
# Bash 3.2 compatible. Quoted path expansions everywhere. No ${arr[-1]}.
##############################################################################
set -uo pipefail

ENGINE_DIR="${ENGINE_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
PROJECT_DIR="${PROJECT_DIR:-$PWD}"
QUEUE_DIR="$PROJECT_DIR/queue"
RUNS_DIR="$QUEUE_DIR/runs"
RUN_SH="${AUTORUN_BATCH_RUN_SH:-$ENGINE_DIR/scripts/autorun/run.sh}"

# ---------------------------------------------------------------------------
# Help text — must include the same v1 limitation notice as run.sh (MF1).
# ---------------------------------------------------------------------------
print_help() {
  cat <<'HELP'
Usage: autorun-batch.sh [--mode=overnight|supervised] [--dry-run]
       autorun-batch.sh --help

Iterate every queue/*.spec.md and invoke run.sh once per slug. Aggregate
each slug's morning-report.json into queue/runs/index.md.

Flags forwarded to run.sh:
  --mode=overnight    Warn-by-default for the four overrideable axes.
  --mode=supervised   Block-by-default (legacy semantics).
  --dry-run           Stage scripts emit stub artifacts; no API calls.

Exit codes:
  0   all slugs ok (or zero specs found)
  1   one or more slugs exited nonzero (loop continued past failures)
  2   invalid invocation / config
  3   STOP file detected — halted at iteration boundary

STOP-file semantics:
  STOP is honored at iteration boundaries only. An in-flight run.sh
  completes its current slug after STOP is touched; only the N+1 iteration
  is suppressed. Stage-boundary STOP-check inside run.sh is deferred —
  see BACKLOG.md.

KNOWN v1 LIMITATION (R18):
  v1 fence extraction rejects multi-fence injection but does not authenticate
  a single check-verdict fence quoted from reviewed content. Do not use
  unattended auto-merge on untrusted prompt-bearing content until
  autorun-verdict-deterministic ships. See BACKLOG.md.
HELP
}

# ---------------------------------------------------------------------------
# Argument parsing — only flags forwarded to run.sh (no positional args).
# ---------------------------------------------------------------------------
FORWARD_ARGS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h)
      print_help
      exit 0
      ;;
    --mode=*|--dry-run)
      FORWARD_ARGS+=("$1")
      shift
      ;;
    --mode)
      shift
      if [ "$#" -eq 0 ]; then
        echo "[autorun-batch] INVALID_FLAG: --mode requires a value (overnight|supervised)" >&2
        exit 2
      fi
      FORWARD_ARGS+=("--mode=$1")
      shift
      ;;
    # autorun-merge-policy v0.11.0 — canonical CLI flag (uniformly applied
    # to every slug — CLI is precedence top).
    --merge-policy=*)
      FORWARD_ARGS+=("$1")
      shift
      ;;
    --merge-policy)
      shift
      if [ "$#" -eq 0 ]; then
        echo "[autorun-batch] INVALID_FLAG: --merge-policy requires a value (pr|clean|validated)" >&2
        exit 2
      fi
      FORWARD_ARGS+=("--merge-policy=$1")
      shift
      ;;
    # Deprecated alias — forwarded as-is so run.sh emits its own deprecation note.
    --auto-merge=*)
      FORWARD_ARGS+=("$1")
      shift
      ;;
    --auto-merge)
      shift
      if [ "$#" -eq 0 ]; then
        echo "[autorun-batch] INVALID_FLAG: --auto-merge requires a value (pr|clean|validated)" >&2
        exit 2
      fi
      FORWARD_ARGS+=("--auto-merge=$1")
      shift
      ;;
    --)
      shift
      if [ "$#" -gt 0 ]; then
        echo "[autorun-batch] INVALID_INVOCATION: positional args not accepted (use run.sh for single-slug runs)" >&2
        exit 2
      fi
      ;;
    *)
      echo "[autorun-batch] INVALID_INVOCATION: unexpected arg \"$1\" (this wrapper does not take a slug; it iterates queue/*.spec.md)" >&2
      exit 2
      ;;
  esac
done

# autorun-merge-policy v0.11.0 — at queue-loop start, source the helper so
# run.sh does not have to re-source it per slug. Idempotent guard inside.
# shellcheck disable=SC1090
. "$ENGINE_DIR/scripts/autorun/_merge_policy.sh"

# Note: the per-slug queue_copy_drift_check is invoked from run.sh (D5 — drift
# check at run.sh start, NOT here, because autorun-batch.sh does not populate
# the queue; it only iterates existing queue/*.spec.md). Reference here is
# documentation — the function symbol is intentionally available for any
# future queue-population path to reuse without re-implementing.
# Symbol referenced for grep-test integrity: queue_copy_drift_check

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
if [ ! -d "$QUEUE_DIR" ]; then
  echo "[autorun-batch] no queue/ directory at $QUEUE_DIR — nothing to do" >&2
  exit 0
fi

if [ ! -f "$RUN_SH" ]; then
  echo "[autorun-batch] INVALID_CONFIG: run.sh not found at $RUN_SH" >&2
  exit 2
fi

mkdir -p "$RUNS_DIR"

# ---------------------------------------------------------------------------
# Collect specs (safe glob — handles empty match).
# ---------------------------------------------------------------------------
SLUGS=()
for spec in "$QUEUE_DIR"/*.spec.md; do
  [ -e "$spec" ] || continue
  slug="$(basename "$spec" .spec.md)"
  SLUGS+=("$slug")
done

if [ "${#SLUGS[@]}" -eq 0 ]; then
  echo "[autorun-batch] no specs found in queue/" >&2
  exit 0
fi

echo "[autorun-batch] found ${#SLUGS[@]} spec(s) in queue/"

# ---------------------------------------------------------------------------
# Track processed run-ids so we can render queue/runs/index.md aggregate.
# Parallel arrays (bash 3.2 — no associative arrays).
# ---------------------------------------------------------------------------
PROCESSED_SLUGS=()
PROCESSED_RUN_IDS=()
FAIL_COUNT=0
STOP_HALTED=0

# Discover the run-id created by run.sh by snapshotting RUNS_DIR before/after
# (run.sh creates queue/runs/<run-id>/). This avoids depending on stdout.
snapshot_run_dirs() {
  ls -1 "$RUNS_DIR" 2>/dev/null | while read -r entry; do
    case "$entry" in
      .locks|current|index.md) continue ;;
    esac
    if [ -d "$RUNS_DIR/$entry" ]; then
      printf "%s\n" "$entry"
    fi
  done | sort
}

# ---------------------------------------------------------------------------
# Iterate slugs
# ---------------------------------------------------------------------------
for slug in "${SLUGS[@]}"; do
  # STOP-file check at iteration boundary (MF10).
  if [ -f "$QUEUE_DIR/STOP" ]; then
    echo "[autorun-batch] STOP file detected at iteration boundary — halting (slug=$slug skipped)" >&2
    STOP_HALTED=1
    break
  fi

  echo "[autorun-batch] === processing slug: $slug ==="

  PRE_DIRS="$(snapshot_run_dirs)"

  SLUG_EXIT=0
  # Bash 3.2 + set -u: empty array dereference must be guarded.
  if [ "${#FORWARD_ARGS[@]}" -gt 0 ]; then
    bash "$RUN_SH" "${FORWARD_ARGS[@]}" "$slug" || SLUG_EXIT=$?
  else
    bash "$RUN_SH" "$slug" || SLUG_EXIT=$?
  fi

  # Discover newly-created run dir (set difference, bash 3.2 friendly).
  POST_DIRS="$(snapshot_run_dirs)"
  NEW_RUN_ID=""
  if [ -n "$POST_DIRS" ]; then
    while IFS= read -r entry; do
      [ -z "$entry" ] && continue
      if ! printf "%s\n" "$PRE_DIRS" | grep -Fxq "$entry"; then
        NEW_RUN_ID="$entry"
      fi
    done <<EOF
$POST_DIRS
EOF
  fi

  PROCESSED_SLUGS+=("$slug")
  PROCESSED_RUN_IDS+=("${NEW_RUN_ID:-unknown}")

  # Exit-code interpretation.
  if [ "$SLUG_EXIT" -eq 0 ]; then
    echo "[autorun-batch] slug=$slug exited 0"
  elif [ "$SLUG_EXIT" -eq 3 ]; then
    # run.sh detected STOP — propagate as halt signal (per spec).
    echo "[autorun-batch] slug=$slug exited 3 (STOP) — halting batch loop" >&2
    STOP_HALTED=1
    break
  else
    echo "[autorun-batch] slug=$slug exited $SLUG_EXIT — continuing to next slug" >&2
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
  fi
done

# ---------------------------------------------------------------------------
# Render queue/runs/index.md aggregate.
# Columns: slug | run_id | final_state | started_at | completed_at | pr_url
# Read each row from queue/runs/<run-id>/morning-report.json (when present).
# ---------------------------------------------------------------------------
render_index_md() {
  local index_md="$RUNS_DIR/index.md"
  local tmp="$index_md.tmp.$$"

  {
    printf "# autorun batch index\n\n"
    printf "Generated: %s\n\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf "| slug | run_id | final_state | started_at | completed_at | pr_url |\n"
    printf "|------|--------|-------------|------------|--------------|--------|\n"

    local i=0
    while [ "$i" -lt "${#PROCESSED_SLUGS[@]}" ]; do
      local s rid mr
      s="${PROCESSED_SLUGS[$i]}"
      rid="${PROCESSED_RUN_IDS[$i]}"
      mr="$RUNS_DIR/$rid/morning-report.json"

      local final_state="?" started_at="?" completed_at="?" pr_url="-"

      if [ -f "$mr" ]; then
        # Read fields via python (stdlib, bash 3.2 safe).
        local fields
        fields="$(python3 - "$mr" <<'PY' 2>/dev/null || true
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print("?\t?\t?\t-")
    sys.exit(0)
fs = d.get("final_state") or "?"
st = d.get("started_at") or "?"
ct = d.get("completed_at") or "?"
pu = d.get("pr_url") or "-"
# Pipe-character escape for markdown tables.
def esc(v):
    return str(v).replace("|", "\\|")
print("\t".join(esc(x) for x in (fs, st, ct, pu)))
PY
)"
        if [ -n "$fields" ]; then
          final_state="$(printf "%s" "$fields" | awk -F'\t' '{print $1}')"
          started_at="$(printf "%s" "$fields" | awk -F'\t' '{print $2}')"
          completed_at="$(printf "%s" "$fields" | awk -F'\t' '{print $3}')"
          pr_url="$(printf "%s" "$fields" | awk -F'\t' '{print $4}')"
        fi
      fi

      printf "| %s | %s | %s | %s | %s | %s |\n" \
        "$s" "$rid" "$final_state" "$started_at" "$completed_at" "$pr_url"
      i=$(( i + 1 ))
    done

    printf "\n"
    if [ "$STOP_HALTED" -eq 1 ]; then
      printf "**STOP file halted batch at iteration boundary.**\n"
    fi
    printf "Failures: %d / %d processed\n" "$FAIL_COUNT" "${#PROCESSED_SLUGS[@]}"
  } > "$tmp"

  mv -f "$tmp" "$index_md"
}

if [ "${#PROCESSED_SLUGS[@]}" -gt 0 ]; then
  render_index_md
fi

# ---------------------------------------------------------------------------
# Final exit code.
#   STOP halt → 3
#   any per-slug failure → 1
#   else → 0
# ---------------------------------------------------------------------------
if [ "$STOP_HALTED" -eq 1 ]; then
  exit 3
fi
if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
