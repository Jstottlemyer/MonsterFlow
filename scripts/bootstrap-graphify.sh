#!/usr/bin/env bash
# bootstrap-graphify.sh — one-shot init across ~/Projects
#
# Usage:
#   bootstrap-graphify.sh                  # dry-run (default, safe)
#   bootstrap-graphify.sh --dry-run        # explicit dry-run
#   bootstrap-graphify.sh --apply          # execute (LLM spend!)
#   bootstrap-graphify.sh --apply --yes    # skip y/N confirmation
#
# Enumerates ~/Projects/*, classifies each as owned|upstream|sensitive|skip,
# writes .graphifyignore per classification, runs `graphify .` on targets,
# installs post-commit hooks on owned repos, seeds dashboard baseline JSONL,
# and installs the two weekly launchd agents.

set -euo pipefail

# Repo root: $MONSTERFLOW_REPO_DIR if set, else the checkout holding this script
# (following the ~/.claude/scripts symlink), matching _resolve_personas.py.
_self="$0"; [ -L "$_self" ] && _self="$(readlink "$_self")"
WORKFLOW_ROOT="${MONSTERFLOW_REPO_DIR:-$(cd "$(dirname "$_self")/.." && pwd -P)}"
TEMPLATES="$WORKFLOW_ROOT/templates"
DASHBOARD_DATA="$WORKFLOW_ROOT/dashboard/data"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
GRAPHIFY="$HOME/.local/bin/graphify"
PROJECTS_ROOT="$HOME/Projects"

MODE="dry-run"
ASSUME_YES="no"

for arg in "$@"; do
  case "$arg" in
    --apply) MODE="apply" ;;
    --dry-run) MODE="dry-run" ;;
    --yes|-y) ASSUME_YES="yes" ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

[ -x "$GRAPHIFY" ] || { echo "graphify not found at $GRAPHIFY" >&2; exit 1; }
[ -d "$TEMPLATES" ] || { echo "templates/ missing at $TEMPLATES" >&2; exit 1; }
mkdir -p "$DASHBOARD_DATA"

classify_project() {
  local name="$1"
  case "$name" in
    graphify|obsidian-wiki)   echo "upstream-readonly" ;;
    _archive)                 echo "skip" ;;
    security)                 echo "security" ;;
    career)                   echo "career" ;;
    Mobile)                   echo "ios-swift" ;;
    *)                        echo "default" ;;
  esac
}

# Is this dir a real codebase we should bootstrap?
#   - has at least one tracked-style file (not just dotfiles)
#   - not a symlink
should_include() {
  local dir="$1"
  [ -d "$dir" ] || return 1
  [ -L "$dir" ] && return 1
  local count
  count=$(find "$dir" -maxdepth 2 -type f ! -name ".*" 2>/dev/null | head -5 | wc -l | tr -d ' ')
  [ "$count" -ge 1 ]
}

# Fast, rough: count non-ignored files to estimate size. Underestimates
# tokens wildly but gives a relative-size signal.
estimate_files() {
  local dir="$1"
  find "$dir" -type f \
    -not -path "*/node_modules/*" \
    -not -path "*/.venv/*" \
    -not -path "*/venv/*" \
    -not -path "*/__pycache__/*" \
    -not -path "*/dist/*" \
    -not -path "*/build/*" \
    -not -path "*/graphify-out/*" \
    -not -path "*/.git/*" \
    2>/dev/null | wc -l | tr -d ' '
}

# Very rough: assume 1500 tokens/file average for a mixed corpus. Graphify's
# AST pass is deterministic (no LLM), so only docs/PDFs/images cost tokens.
# The bootstrap's extract pass runs Claude subagents on those. We guess
# ~0.3 * file_count * 0.002 USD as an order-of-magnitude ceiling.
estimate_cost_usd() {
  local files="$1"
  # Use awk to avoid bc dependency: 0.3 * files * 0.002 = files * 0.0006
  awk -v f="$files" 'BEGIN { printf "%.2f", f * 0.0006 }'
}

printf "\n=== bootstrap-graphify (%s mode) ===\n\n" "$MODE"
printf "Root: %s\n" "$PROJECTS_ROOT"
printf "Graphify: %s\n\n" "$GRAPHIFY"

total_files=0
declare -a PLAN_ROWS=()
declare -a APPLY_TARGETS=()

for entry in "$PROJECTS_ROOT"/*; do
  [ -d "$entry" ] || continue
  name=$(basename "$entry")
  if ! should_include "$entry"; then
    PLAN_ROWS+=("SKIP|$name|empty or not-a-codebase|0|-")
    continue
  fi
  kind=$(classify_project "$name")
  if [ "$kind" = "skip" ]; then
    PLAN_ROWS+=("SKIP|$name|skip-classified (_archive)|0|-")
    continue
  fi
  files=$(estimate_files "$entry")
  total_files=$((total_files + files))
  already="no"
  [ -f "$entry/graphify-out/graph.json" ] && already="yes"
  PLAN_ROWS+=("TARGET|$name|$kind|$files|$already")
  APPLY_TARGETS+=("$name|$kind|$entry|$already")
done

printf "%-8s %-18s %-22s %8s %8s\n" "Action" "Project" "Kind" "Files" "HasGraph"
printf "%-8s %-18s %-22s %8s %8s\n" "------" "-------" "----" "-----" "--------"
for row in "${PLAN_ROWS[@]}"; do
  IFS='|' read -r action name kind files already <<<"$row"
  printf "%-8s %-18s %-22s %8s %8s\n" "$action" "$name" "$kind" "$files" "$already"
done

est_cost=$(estimate_cost_usd "$total_files")
echo
printf "Totals: %d target projects, ~%d files to consider, rough ceiling ~\$%s LLM cost.\n" \
  "${#APPLY_TARGETS[@]}" "$total_files" "$est_cost"
echo "(Cost is a very rough ceiling — AST-only pass is free; only docs/PDFs/images cost.)"
echo

if [ "$MODE" = "dry-run" ]; then
  echo "Dry run complete. Re-run with --apply to execute."
  exit 0
fi

if [ "$ASSUME_YES" != "yes" ]; then
  read -r -p "Proceed with --apply across all targets? [y/N] " resp
  [ "$resp" = "y" ] || [ "$resp" = "Y" ] || { echo "Aborted."; exit 0; }
fi

echo
echo "=== Applying ==="
echo

for target in "${APPLY_TARGETS[@]}"; do
  IFS='|' read -r name kind entry already <<<"$target"
  printf -- "--- %s (%s) ---\n" "$name" "$kind"

  # 1. Write .graphifyignore from template
  template="$TEMPLATES/graphifyignore-$kind"
  if [ -f "$template" ]; then
    cp "$template" "$entry/.graphifyignore"
    echo "  .graphifyignore <- $kind template"
  else
    echo "  (no template for kind=$kind, skipping)"
  fi

  # 2. Index (AST-only, deterministic, no LLM — fast and free)
  # For full concept extraction (docs/images/PDFs → Claude subagents), run
  # `/graphify .` from inside Claude Code on a project-by-project basis.
  if [ "$already" = "yes" ]; then
    echo "  graphify-out/ exists — skipping initial index"
  else
    echo "  running: graphify update . (AST-only)"
    (cd "$entry" && "$GRAPHIFY" update . 2>&1 | tail -5 | sed 's/^/    /') || {
      echo "  !! graphify update failed for $name — continuing"
      continue
    }
  fi

  # 3. Hook install (owned repos only)
  if [ -d "$entry/.git" ] && [ "$kind" != "upstream-readonly" ]; then
    echo "  installing post-commit/post-checkout hooks"
    (cd "$entry" && "$GRAPHIFY" hook install >/dev/null 2>&1) || echo "    (hook install failed, non-fatal)"
  else
    echo "  hooks: skipped (not a git repo or upstream-readonly)"
  fi

  # 4. Benchmark + baseline JSONL
  # graphify CLI only prints human text; call Python API directly for JSON.
  echo "  running baseline benchmark"
  bench_json="$entry/graphify-out/last-benchmark.json"
  if (cd "$entry" && "$HOME/.local/venvs/graphify/bin/python3" - <<'PY' 2>/dev/null >"$bench_json"
import json, os
from graphify.benchmark import run_benchmark
try:
    result = run_benchmark("graphify-out/graph.json")
except Exception as e:
    result = {"error": str(e)}
print(json.dumps(result))
PY
  ); then
    echo "  wrote $bench_json"
  else
    echo '{}' >"$bench_json"
    echo "  (benchmark failed, wrote empty JSON)"
  fi

  # 5. Append baseline record to dashboard JSONL
  slug=$(echo "$name" | tr '[:upper:]' '[:lower:]')
  "$WORKFLOW_ROOT/scripts/dashboard-append.sh" \
    --event bootstrap \
    --project "$name" \
    --cwd "$entry" || echo "  (dashboard append failed, non-fatal)"

  echo
done

# 6. Install launchd agents
echo "=== Installing launchd agents ==="
mkdir -p "$LAUNCH_AGENTS"
for plist in com.jstottlemyer.graphify-benchmarks.weekly.plist \
             com.jstottlemyer.wiki-graph.weekly.plist; do
  src="$WORKFLOW_ROOT/settings/launchd/$plist"
  dst="$LAUNCH_AGENTS/$plist"
  if [ -f "$src" ]; then
    cp "$src" "$dst"
    launchctl unload "$dst" 2>/dev/null || true
    launchctl load "$dst"
    echo "  loaded $plist"
  else
    echo "  !! $src not found, skipping"
  fi
done

echo
echo "=== Bootstrap complete ==="
echo "Dashboard: open $WORKFLOW_ROOT/dashboard/index.html"
echo "Review with: /graph  (inside any indexed project)"
