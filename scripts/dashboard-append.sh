#!/usr/bin/env bash
# dashboard-append.sh — append one JSONL record to dashboard/data/<slug>.jsonl
#
# Usage:
#   dashboard-append.sh --event <kind> --project <Name> --cwd <path> \
#                       [--duration-min N] [--commits N] [--spec-created 0|1] \
#                       [--plan-executed 0|1] [--wiki-ingested N] [--raw-pending N]
#
# Called by: bootstrap-graphify.sh, /wrap phase 1 tail, benchmarks-all.sh,
#            wiki-graph.sh. Self-contained — no external Python imports beyond stdlib.

set -euo pipefail

# Repo root: $MONSTERFLOW_REPO_DIR if set, else the checkout holding this script
# (following the ~/.claude/scripts symlink), matching _resolve_personas.py.
_self="$0"; [ -L "$_self" ] && _self="$(readlink "$_self")"
WORKFLOW_ROOT="${MONSTERFLOW_REPO_DIR:-$(cd "$(dirname "$_self")/.." && pwd -P)}"
DATA_DIR="$WORKFLOW_ROOT/dashboard/data"
mkdir -p "$DATA_DIR"

EVENT=""
PROJECT=""
CWD=""
DURATION_MIN=0
COMMITS=0
SPEC_CREATED=0
PLAN_EXECUTED=0
WIKI_INGESTED=0
RAW_PENDING=0

while [ $# -gt 0 ]; do
  case "$1" in
    --event) EVENT="$2"; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    --cwd) CWD="$2"; shift 2 ;;
    --duration-min) DURATION_MIN="$2"; shift 2 ;;
    --commits) COMMITS="$2"; shift 2 ;;
    --spec-created) SPEC_CREATED="$2"; shift 2 ;;
    --plan-executed) PLAN_EXECUTED="$2"; shift 2 ;;
    --wiki-ingested) WIKI_INGESTED="$2"; shift 2 ;;
    --raw-pending) RAW_PENDING="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -n "$EVENT" ] && [ -n "$PROJECT" ] && [ -n "$CWD" ] || {
  echo "--event, --project, --cwd are required" >&2; exit 2; }

SLUG=$(echo "$PROJECT" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | sed 's/--*/-/g; s/^-//; s/-$//')
OUT="$DATA_DIR/$SLUG.jsonl"

python3 - "$EVENT" "$PROJECT" "$CWD" "$DURATION_MIN" "$COMMITS" \
            "$SPEC_CREATED" "$PLAN_EXECUTED" "$WIKI_INGESTED" "$RAW_PENDING" "$OUT" <<'PY'
import json, os, sys, datetime, pathlib

event, project, cwd, duration_min, commits, spec_created, \
    plan_executed, wiki_ingested, raw_pending, out = sys.argv[1:]

cwd = os.path.expanduser(cwd)
rec = {
    "ts": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "event": event,
    "project": project,
    "graph": {"nodes": 0, "edges": 0, "communities": 0, "god_nodes_top3": []},
    "benchmark": {"corpus_tokens": 0, "avg_query_tokens": 0,
                  "reduction_ratio": 0.0, "stale_days": None},
    "wiki": {"pages_total": 0,
             "pages_ingested_this_session": int(wiki_ingested),
             "raw_pending": int(raw_pending)},
    "session": {"duration_min": int(duration_min),
                "commits": int(commits),
                "spec_created": bool(int(spec_created)),
                "plan_executed": bool(int(plan_executed))},
}

# --- graph.json: nodes/edges/communities
gj = pathlib.Path(cwd) / "graphify-out" / "graph.json"
if gj.exists():
    try:
        data = json.loads(gj.read_text())
        nodes = data.get("nodes", [])
        edges = data.get("links", data.get("edges", []))
        rec["graph"]["nodes"] = len(nodes)
        rec["graph"]["edges"] = len(edges)
        comms = {n.get("community") for n in nodes if n.get("community") is not None}
        rec["graph"]["communities"] = len(comms)
        # god nodes: top-3 by degree
        from collections import Counter
        deg = Counter()
        for e in edges:
            s = e.get("source"); t = e.get("target")
            if s is not None: deg[s] += 1
            if t is not None: deg[t] += 1
        id_to_label = {n.get("id"): n.get("label", n.get("id")) for n in nodes}
        top = [id_to_label.get(nid, str(nid)) for nid, _ in deg.most_common(3)]
        rec["graph"]["god_nodes_top3"] = top
    except Exception as e:
        rec["graph"]["error"] = f"parse: {e}"

# --- benchmark: last-benchmark.json
bj = pathlib.Path(cwd) / "graphify-out" / "last-benchmark.json"
if bj.exists():
    try:
        b = json.loads(bj.read_text())
        rec["benchmark"]["corpus_tokens"] = int(b.get("corpus_tokens", 0))
        rec["benchmark"]["avg_query_tokens"] = int(b.get("avg_query_tokens", 0))
        rec["benchmark"]["reduction_ratio"] = float(b.get("reduction_ratio", 0.0))
        # staleness: compare file mtime to now
        mtime = datetime.datetime.fromtimestamp(bj.stat().st_mtime, datetime.timezone.utc)
        age = (datetime.datetime.now(datetime.timezone.utc) - mtime).days
        rec["benchmark"]["stale_days"] = age
    except Exception as e:
        rec["benchmark"]["error"] = f"parse: {e}"

# --- wiki: read vault manifest for pages_total
vault = os.environ.get("OBSIDIAN_VAULT_PATH", "")
if not vault:
    # try ~/.obsidian-wiki/config
    cfg = pathlib.Path.home() / ".obsidian-wiki" / "config"
    if cfg.exists():
        for line in cfg.read_text().splitlines():
            line = line.strip()
            if line.startswith("OBSIDIAN_VAULT_PATH="):
                vault = line.split("=", 1)[1].strip().strip('"').strip("'")
                vault = os.path.expanduser(vault)
                break
if vault and os.path.isdir(vault):
    manifest = pathlib.Path(vault) / ".manifest.json"
    if manifest.exists():
        try:
            m = json.loads(manifest.read_text())
            if isinstance(m, dict):
                # count non-underscore sources or pages_created entries
                pages = set()
                for v in m.values():
                    if isinstance(v, dict):
                        for p in v.get("pages_created", []) + v.get("pages_updated", []):
                            pages.add(p)
                rec["wiki"]["pages_total"] = len(pages)
            elif isinstance(m, list):
                rec["wiki"]["pages_total"] = len(m)
        except Exception:
            pass
    # raw_pending: count files in _raw/
    raw_dir = pathlib.Path(vault) / "_raw"
    if raw_dir.exists():
        rec["wiki"]["raw_pending"] = sum(1 for _ in raw_dir.glob("*.md"))

with open(out, "a") as f:
    f.write(json.dumps(rec) + "\n")

print(f"appended to {out}")
PY

# Rebuild bundles so the dashboard reflects the new record immediately
# without needing a local http server (file:// fetch is blocked by CORS).
# Both modes (Graphify + Judge) share the same dashboard page, so refresh
# both whenever any event lands.
"$WORKFLOW_ROOT/scripts/dashboard-bundle.sh" >/dev/null 2>&1 || true
"$WORKFLOW_ROOT/scripts/judge-dashboard-bundle.sh" >/dev/null 2>&1 || true

# Print a clickable launch link when run interactively (most terminals
# render file:// URLs as clickable). Hook callers redirect stdout to
# /dev/null, so this stays silent there.
echo "Dashboard: file://$WORKFLOW_ROOT/dashboard/index.html  (Graphify | Judge)"
