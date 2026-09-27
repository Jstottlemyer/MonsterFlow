#!/usr/bin/env bash
# Thin wrapper: appends a wiki-graph-weekly event to dashboard data for project=wiki-graph.
set -euo pipefail
# Repo root: $MONSTERFLOW_REPO_DIR if set, else the checkout holding this script
# (following the ~/.claude/scripts symlink), matching _resolve_personas.py.
_self="$0"; [ -L "$_self" ] && _self="$(readlink "$_self")"
WORKFLOW_ROOT="${MONSTERFLOW_REPO_DIR:-$(cd "$(dirname "$_self")/.." && pwd -P)}"
"$WORKFLOW_ROOT/scripts/dashboard-append.sh" \
  --event wiki-graph-weekly \
  --project wiki-graph \
  --cwd "$HOME/Projects/wiki-graph"
