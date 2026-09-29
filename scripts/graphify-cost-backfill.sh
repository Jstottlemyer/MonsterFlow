#!/usr/bin/env bash
# graphify-cost-backfill.sh — post-hoc fill graphify-out/cost.json when build-token
# counts are zero. Subagent chunks literally emit input_tokens:0/output_tokens:0
# (the skill template sets them to zero and Claude's parent loop does not sum
# real tool-response metadata back). This shim estimates real build cost from
# corpus_tokens + graph size so the dashboard can compute break-even.
#
# Estimation model (conservative):
#   input_tokens  ≈ corpus_tokens + num_batches × 600
#                    (corpus fed to subagents once + prompt overhead per batch)
#   output_tokens ≈ nodes × 30 + edges × 20 + hyperedges × 50
#                    (JSON emission cost per extracted entity)
#   break_even_queries = input_tokens / max(1, corpus_tokens - avg_query_tokens)
#
# Only backfills when cost.json exists, reports 0 tokens, has files>0, and the
# project has a last-benchmark.json with corpus_tokens>0. Marks source=estimated.
#
# Usage:
#   graphify-cost-backfill.sh [project-path]
#   (no args: walks ~/Projects/*)
#
# Called by: benchmarks-all.sh (tail), or manually per-project.

set -euo pipefail

# Repo root: $MONSTERFLOW_REPO_DIR if set, else the checkout holding this script
# (following the ~/.claude/scripts symlink), matching _resolve_personas.py.
_self="$0"; [ -L "$_self" ] && _self="$(readlink "$_self")"
WORKFLOW_ROOT="${MONSTERFLOW_REPO_DIR:-$(cd "$(dirname "$_self")/.." && pwd -P)}"
PROJECTS_ROOT="$HOME/Projects"
LOG="$WORKFLOW_ROOT/dashboard/data/.cost-backfill.log"
mkdir -p "$(dirname "$LOG")"

# Chunk-size assumption from graphify skill Step B1: "Split into chunks of 20-25 files"
FILES_PER_BATCH=22

backfill_one() {
  local proj_dir="$1"
  local proj_name
  proj_name=$(basename "$proj_dir")
  local cost="$proj_dir/graphify-out/cost.json"
  local bench="$proj_dir/graphify-out/last-benchmark.json"
  local graph="$proj_dir/graphify-out/graph.json"

  [ -f "$cost" ] && [ -f "$bench" ] && [ -f "$graph" ] || return 0

  python3 - "$cost" "$bench" "$graph" "$FILES_PER_BATCH" "$proj_name" <<'PY'
import json, sys
from pathlib import Path
from datetime import datetime, timezone

cost_path, bench_path, graph_path, files_per_batch, proj = sys.argv[1:]
files_per_batch = int(files_per_batch)

cost = json.loads(Path(cost_path).read_text())
bench = json.loads(Path(bench_path).read_text())
graph = json.loads(Path(graph_path).read_text())

total_in = cost.get("total_input_tokens", 0)
total_out = cost.get("total_output_tokens", 0)
runs = cost.get("runs", [])
total_files = sum(r.get("files", 0) for r in runs)

# Only backfill when BOTH totals are zero and there are files to estimate from.
# If either field has a real nonzero measurement, preserve it — partial data is
# still more accurate than a full estimate and should never be silently replaced.
already_measured_in  = total_in  > 0 and cost.get("source") != "estimated"
already_measured_out = total_out > 0 and cost.get("source") != "estimated"
if already_measured_in or already_measured_out:
    print(f"[{proj}] partial/full real measurements present (in={total_in}, out={total_out}); skip")
    raise SystemExit(0)

# Nothing to estimate from — no files processed
if total_files == 0:
    print(f"[{proj}] no files recorded in cost.json runs; skip")
    raise SystemExit(0)

# Skip if bench failed or is empty
corpus_tokens = int(bench.get("corpus_tokens", 0) or 0)
if corpus_tokens == 0:
    print(f"[{proj}] no corpus_tokens in benchmark; skip")
    raise SystemExit(0)

nodes = len(graph.get("nodes", []))
edges = len(graph.get("links", graph.get("edges", [])))
# hyperedges aren't stored in the final graph.json separately — use 0
hyperedges = 0

num_batches = max(1, (total_files + files_per_batch - 1) // files_per_batch)
est_input = corpus_tokens + num_batches * 600
est_output = nodes * 30 + edges * 20 + hyperedges * 50

avg_q = int(bench.get("avg_query_tokens", 0) or 0)
if avg_q > 0 and avg_q < corpus_tokens:
    break_even = int(round(est_input / max(1, corpus_tokens - avg_q)))
else:
    break_even = None

# Write via temp file + atomic rename so a crash mid-write can't corrupt the original
import tempfile
cost["total_input_tokens"] = est_input
cost["total_output_tokens"] = est_output
cost["source"] = "estimated"
cost["estimation"] = {
    "method": "corpus_tokens + batches*600 for input, nodes*30 + edges*20 for output",
    "corpus_tokens": corpus_tokens,
    "files_processed": total_files,
    "num_batches": num_batches,
    "nodes": nodes,
    "edges": edges,
    "break_even_queries": break_even,
    "computed_at": datetime.now(timezone.utc).isoformat(),
}

# Backfill each run proportionally if multiple; only touch runs that also have zero totals
if runs:
    weight_total = sum(r.get("files", 1) for r in runs) or 1
    for r in runs:
        if r.get("input_tokens", 0) == 0 and r.get("output_tokens", 0) == 0:
            w = (r.get("files", 1) or 1) / weight_total
            r["input_tokens"] = int(round(est_input * w))
            r["output_tokens"] = int(round(est_output * w))
            r["source"] = "estimated"

tmp = Path(cost_path).with_suffix(".tmp")
tmp.write_text(json.dumps(cost, indent=2))
tmp.replace(Path(cost_path))
be_str = f"break_even_queries={break_even}" if break_even is not None else "break_even=n/a"
print(f"[{proj}] backfilled: input={est_input:,} output={est_output:,} {be_str}")
PY
}

exec >>"$LOG" 2>&1
echo "--- $(date -u +%Y-%m-%dT%H:%M:%SZ) cost-backfill start ---"

if [ $# -ge 1 ]; then
  backfill_one "$1"
else
  for entry in "$PROJECTS_ROOT"/*; do
    [ -d "$entry" ] || continue
    backfill_one "$entry" || true
  done
fi

echo "--- done ---"
