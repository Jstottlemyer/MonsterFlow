#!/usr/bin/env bash
##############################################################################
# scripts/build-codex-worker.sh — run one /build implementation task on a
# Codex worker instead of a Claude Agent-tool subagent.
#
# Usage:
#   build-codex-worker.sh [--repo DIR] [--model M] <task-dir> <task-id>
#   build-codex-worker.sh --probe-model [--model M]
#
# Inputs:
#   <task-dir>/<task-id>.prompt.md   the task contract (the same text a Claude
#                                    subagent would receive)
# Outputs (in <task-dir>):
#   <task-id>.last.md        the worker's final report (DONE / DONE_WITH_CONCERNS /
#                            NEEDS_CONTEXT / BLOCKED first line)
#   <task-id>.events.jsonl   Codex's JSON event stream (progress / stall watch)
#   <task-id>.stderr.log     Codex's stderr
#
# The prompt is: templates/build-worker-preamble.md, then the target repo's
# optional .monsterflow/build-worker-preamble.md (project-specific rules), then
# the task contract. It is piped to `codex exec` on stdin; stdin is never left
# open, which would make a backgrounded `codex exec` wait forever.
#
# The orchestrator keeps the task graph, verification, commits and every
# remote action. The sandbox makes that structural: workspace-write (edits
# only inside the repo; .git is read-only), and network access off.
#
# Model: --model, else $MONSTERFLOW_CODEX_WORKER_MODEL, else
# `codex_worker_model` in ~/.config/monsterflow/config.json, else Codex's own
# default. --probe-model checks that the account can use that model before a
# wave is dispatched (some models are unavailable on some account types).
#
# Exit codes:
#   0  worker finished and wrote a report (read its first line for status)
#   2  usage error / missing task contract
#   3  codex not installed or not authenticated (fall back to Claude subagents)
#   4  codex exited non-zero
#   5  codex exited 0 but wrote no report
#   6  --probe-model: the model is not usable on this account
#
# Bash 3.2 compatible.
##############################################################################
set -uo pipefail

_self="$0"; [ -L "$_self" ] && _self="$(readlink "$_self")"
ENGINE_DIR="${MONSTERFLOW_REPO_DIR:-$(cd "$(dirname "$_self")/.." && pwd -P)}"
CODEX="${MONSTERFLOW_CODEX_BIN:-codex}"
CONFIG="${MONSTERFLOW_CONFIG:-$HOME/.config/monsterflow/config.json}"

usage() {
  sed -n '6,9p' "$_self" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

PROBE=0
REPO=""
MODEL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --probe-model) PROBE=1; shift ;;
    --repo) [ $# -ge 2 ] || usage; REPO="$2"; shift 2 ;;
    --model) [ $# -ge 2 ] || usage; MODEL="$2"; shift 2 ;;
    -h|--help) usage ;;
    --) shift; break ;;
    -*) echo "build-codex-worker: unknown option $1" >&2; usage ;;
    *) break ;;
  esac
done

if [ -z "$MODEL" ]; then
  MODEL="${MONSTERFLOW_CODEX_WORKER_MODEL:-}"
fi
if [ -z "$MODEL" ] && [ -f "$CONFIG" ]; then
  MODEL="$(python3 -c 'import json,sys
try:
    v = json.load(open(sys.argv[1])).get("codex_worker_model") or ""
except Exception:
    v = ""
print(v if isinstance(v, str) else "")' "$CONFIG" 2>/dev/null || true)"
fi
MODEL_ARGS=""
[ -n "$MODEL" ] && MODEL_ARGS="-m $MODEL"

if ! command -v "$CODEX" >/dev/null 2>&1; then
  echo "build-codex-worker: codex is not installed; use Claude subagents" >&2
  exit 3
fi
if ! "$CODEX" login status >/dev/null 2>&1; then
  echo "build-codex-worker: codex is not authenticated; use Claude subagents" >&2
  exit 3
fi

if [ "$PROBE" -eq 1 ]; then
  out="$(mktemp -t mf-codex-probe.XXXXXX)"
  err="$(mktemp -t mf-codex-probe-err.XXXXXX)"
  # shellcheck disable=SC2086  # MODEL_ARGS is intentionally word-split
  "$CODEX" exec $MODEL_ARGS --sandbox read-only --ephemeral -o "$out" \
    "Reply with exactly: OK" < /dev/null > /dev/null 2> "$err"
  rc=$?
  if [ "$rc" -eq 0 ] && [ -s "$out" ]; then
    echo "build-codex-worker: model ${MODEL:-<codex default>} is usable"
    rm -f "$out" "$err"
    exit 0
  fi
  echo "build-codex-worker: model ${MODEL:-<codex default>} is not usable on this account (exit $rc):" >&2
  tail -5 "$err" >&2
  rm -f "$out" "$err"
  exit 6
fi

[ $# -eq 2 ] || usage
TASK_DIR="$1"
TASK="$2"
CONTRACT="$TASK_DIR/$TASK.prompt.md"
if [ ! -s "$CONTRACT" ]; then
  echo "build-codex-worker: missing task contract $CONTRACT" >&2
  exit 2
fi
if [ -z "$REPO" ]; then
  REPO="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"
fi
PREAMBLE="$ENGINE_DIR/templates/build-worker-preamble.md"
OVERLAY="$REPO/.monsterflow/build-worker-preamble.md"
if [ ! -f "$PREAMBLE" ]; then
  echo "build-codex-worker: missing $PREAMBLE" >&2
  exit 2
fi

PROMPT="$(mktemp -t mf-codex-worker.XXXXXX)"
trap 'rm -f "$PROMPT"' EXIT
{
  cat "$PREAMBLE"
  if [ -f "$OVERLAY" ]; then
    printf '\nProject-specific rules (%s):\n\n' ".monsterflow/build-worker-preamble.md"
    cat "$OVERLAY"
    printf '\n---\n\n'
  fi
  cat "$CONTRACT"
} > "$PROMPT"

REPORT="$TASK_DIR/$TASK.last.md"
rm -f "$REPORT"
# shellcheck disable=SC2086  # MODEL_ARGS is intentionally word-split
"$CODEX" exec --cd "$REPO" $MODEL_ARGS \
  --sandbox workspace-write \
  -c sandbox_workspace_write.network_access=false \
  --ephemeral --json \
  -o "$REPORT" \
  - < "$PROMPT" > "$TASK_DIR/$TASK.events.jsonl" 2> "$TASK_DIR/$TASK.stderr.log"
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "build-codex-worker: codex exited $rc for $TASK (see $TASK_DIR/$TASK.stderr.log)" >&2
  exit 4
fi
if [ ! -s "$REPORT" ]; then
  echo "build-codex-worker: codex wrote no report for $TASK" >&2
  exit 5
fi
echo "build-codex-worker: $TASK: $(head -1 "$REPORT")"
exit 0
