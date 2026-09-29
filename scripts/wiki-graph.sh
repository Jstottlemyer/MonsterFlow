#!/usr/bin/env bash
# wiki-graph.sh — weekly launchd target. Re-indexes the obsidian vault as
# its own graph under ~/Projects/wiki-graph/.

set -euo pipefail

# Repo root: $MONSTERFLOW_REPO_DIR if set, else the checkout holding this script
# (following the ~/.claude/scripts symlink), matching _resolve_personas.py.
_self="$0"; [ -L "$_self" ] && _self="$(readlink "$_self")"
WORKFLOW_ROOT="${MONSTERFLOW_REPO_DIR:-$(cd "$(dirname "$_self")/.." && pwd -P)}"
GRAPHIFY="$HOME/.local/bin/graphify"
LOG="$WORKFLOW_ROOT/dashboard/data/.wiki-graph.log"
mkdir -p "$(dirname "$LOG")"
exec >>"$LOG" 2>&1
echo "--- $(date -u +%Y-%m-%dT%H:%M:%SZ) wiki-graph start ---"

# Resolve vault path (env > ~/.obsidian-wiki/config)
VAULT="${OBSIDIAN_VAULT_PATH:-}"
if [ -z "$VAULT" ] && [ -f "$HOME/.obsidian-wiki/config" ]; then
  VAULT=$(awk -F= '/^OBSIDIAN_VAULT_PATH=/{gsub(/"|'\''/, "", $2); print $2}' \
            "$HOME/.obsidian-wiki/config" | head -1)
  VAULT="${VAULT/#\~/$HOME}"
fi

if [ -z "$VAULT" ] || [ ! -d "$VAULT" ]; then
  echo "No valid OBSIDIAN_VAULT_PATH; skipping"
  exit 0
fi

OUT="$HOME/Projects/wiki-graph"
mkdir -p "$OUT"
cd "$OUT"
if [ ! -L source ]; then
  ln -s "$VAULT" source
fi

"$GRAPHIFY" source
date -u +"%Y-%m-%dT%H:%M:%SZ" > last-run.txt

"$WORKFLOW_ROOT/scripts/dashboard-append-wiki-graph.sh" || true
echo "--- done ---"
