#!/usr/bin/env bash
# Weekly Obsidian graph indexing via pinned official graphifyy 0.9.102.
# Headless semantic extraction can send vault content to an LLM provider.
# The existing scheduler supplies no approval flag, so it MUST fail closed.
set -euo pipefail

_self="$0"; [ -L "$_self" ] && _self="$(readlink "$_self")"
WORKFLOW_ROOT="${MONSTERFLOW_REPO_DIR:-$(cd "$(dirname "$_self")/.." && pwd -P)}"
LOG="$WORKFLOW_ROOT/dashboard/data/.wiki-graph.log"
mkdir -p "$(dirname "$LOG")"
exec >>"$LOG" 2>&1
echo "--- $(date -u +%Y-%m-%dT%H:%M:%SZ) wiki-graph start ---"

if [ "$#" -ne 1 ] || [ "$1" != "--allow-semantic" ]; then
  echo "SKIPPED: graphify semantic extraction requires explicit --allow-semantic authorization"
  exit 3
fi

GRAPHIFY="$HOME/.local/bin/graphify"
[ -x "$GRAPHIFY" ] || { echo "graphify executable missing"; exit 2; }
"$GRAPHIFY" --version | grep -Eq '(^|[^0-9])0\.9\.102([^0-9]|$)' || {
  echo "Pinned graphifyy 0.9.102 not installed; refusing automatic upgrade"; exit 2;
}

VAULT="${OBSIDIAN_VAULT_PATH:-}"
if [ -z "$VAULT" ] && [ -f "$HOME/.obsidian-wiki/config" ]; then
  VAULT=$(awk -F= '/^OBSIDIAN_VAULT_PATH=/{gsub(/"|'\''/, "", $2); print $2}' \
            "$HOME/.obsidian-wiki/config" | head -1)
  VAULT="${VAULT/#\~/$HOME}"
fi
[ -n "$VAULT" ] && [ -d "$VAULT" ] || { echo "No valid OBSIDIAN_VAULT_PATH"; exit 2; }

OUT="$HOME/Projects/wiki-graph"
mkdir -p "$OUT/backups"
STAGE=$(mktemp -d "$OUT/.graphify-stage.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT

# Do not mutate the working graph, source symlink or cache until both passes succeed.
"$GRAPHIFY" extract "$VAULT" --out "$STAGE"
NEXT="$STAGE/graphify-out"
[ -s "$NEXT/graph.json" ] || { echo "Missing extracted graph"; exit 2; }
"$GRAPHIFY" cluster-only "$STAGE" --graph "$NEXT/graph.json" --no-label
[ -f "$NEXT/GRAPH_REPORT.md" ] || { echo "Missing cluster report"; exit 2; }

BACKUP=""
if [ -d "$OUT/graphify-out" ]; then
  BACKUP=$(mktemp -d "$OUT/backups/graphify-out.$(date -u +%Y%m%dT%H%M%SZ).XXXXXX")
  rmdir "$BACKUP"
  mv "$OUT/graphify-out" "$BACKUP"
fi
if ! mv "$NEXT" "$OUT/graphify-out"; then
  [ -z "$BACKUP" ] || mv "$BACKUP" "$OUT/graphify-out"
  echo "Graph promotion failed; restored old graph"
  exit 2
fi

date -u +"%Y-%m-%dT%H:%M:%SZ" > "$OUT/last-run.txt"
echo "SUCCESS: graph updated; prior graph backup=${BACKUP:-none}"
"$WORKFLOW_ROOT/scripts/dashboard-append-wiki-graph.sh" || true
echo "--- done ---"
