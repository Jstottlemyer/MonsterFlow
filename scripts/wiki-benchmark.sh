#!/usr/bin/env bash
# wiki-benchmark.sh — measure token-reduction for wiki-query vs naive full-vault
# read. Simulates the three retrieval modes the wiki-query skill escalates
# through (index_only → section_grep → full_read) and reports reduction_ratio
# for each.
#
# Output:
#   $OBSIDIAN_VAULT_PATH/wiki-export/last-benchmark.json
#   dashboard event: project=obsidian-wiki, event=wiki-benchmark-weekly
#
# Called by: benchmarks-all.sh (tail), or manually.

set -euo pipefail

# Repo root: $MONSTERFLOW_REPO_DIR if set, else the checkout holding this script
# (following the ~/.claude/scripts symlink), matching _resolve_personas.py.
_self="$0"; [ -L "$_self" ] && _self="$(readlink "$_self")"
WORKFLOW_ROOT="${MONSTERFLOW_REPO_DIR:-$(cd "$(dirname "$_self")/.." && pwd -P)}"
LOG="$WORKFLOW_ROOT/dashboard/data/.wiki-benchmark.log"
mkdir -p "$(dirname "$LOG")"

# Resolve vault path
VAULT=""
if [ -f "$HOME/.obsidian-wiki/config" ]; then
  # shellcheck disable=SC1091
  VAULT=$(grep '^OBSIDIAN_VAULT_PATH=' "$HOME/.obsidian-wiki/config" | cut -d= -f2- | tr -d '"'"'")
  VAULT="${VAULT/#\~/$HOME}"
fi

exec >>"$LOG" 2>&1
echo "--- $(date -u +%Y-%m-%dT%H:%M:%SZ) wiki-benchmark start ---"

if [ -z "$VAULT" ] || [ ! -d "$VAULT" ]; then
  echo "ERROR: OBSIDIAN_VAULT_PATH not resolvable (got '$VAULT'); skipping"
  exit 0
fi

OUT="$VAULT/wiki-export/last-benchmark.json"
mkdir -p "$(dirname "$OUT")"

python3 - "$VAULT" "$OUT" <<'PY'
import json, re, sys, os
from pathlib import Path
from datetime import datetime, timezone

VAULT = Path(sys.argv[1])
OUT   = Path(sys.argv[2])

CHARS_PER_TOKEN = 4
SKIP_DIRS = {"_raw", "_archives", "wiki-export", ".obsidian", ".git"}
FRONTMATTER = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.DOTALL)

# Canonical questions — mirror graphify's shape but target knowledge-synthesis not code
QUESTIONS = [
    "what is my current thinking on the knowledge pipeline",
    "how does graphify relate to obsidian wiki",
    "what projects touch the workflow pipeline",
    "what do I know about agent personas",
    "what are the key architectural decisions",
]

def est(s): return max(1, len(s) // CHARS_PER_TOKEN)

def parse_fm(text):
    m = FRONTMATTER.match(text)
    if not m: return {}, text
    body = text[m.end():]
    fm = {}
    for line in m.group(1).splitlines():
        if ":" in line and not line.startswith(" "):
            k, _, v = line.partition(":")
            fm[k.strip()] = v.strip()
    return fm, body

# Scan vault
pages = []
for md in VAULT.rglob("*.md"):
    if any(part in SKIP_DIRS for part in md.parts): continue
    if md.name in ("log.md",): continue
    try:
        text = md.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue
    fm, body = parse_fm(text)
    pages.append({
        "path": str(md.relative_to(VAULT)),
        "title": fm.get("title", md.stem).strip(">-").strip(),
        "tags": fm.get("tags", ""),
        "summary": fm.get("summary", "")[:200],
        "body_tokens": est(body),
        "full_tokens": est(text),
        "fm_line": f'{md.stem} | {fm.get("summary","")[:120]} | {fm.get("tags","")}',
    })

if not pages:
    OUT.write_text(json.dumps({"error": "no pages in vault"}, indent=2))
    print("ERROR: vault has no pages")
    raise SystemExit(0)

index_path = VAULT / "index.md"
index_tokens = est(index_path.read_text(encoding="utf-8", errors="replace")) if index_path.exists() else 0

# Naive: read every page in full
naive_tokens = sum(p["full_tokens"] for p in pages)

# For each question, score pages by term overlap in title+tags+summary+fm_line
def score(page, question):
    terms = [t.lower() for t in question.split() if len(t) > 3]
    hay = (page["title"] + " " + page["tags"] + " " + page["summary"] + " " + page["fm_line"]).lower()
    return sum(1 for t in terms if t in hay)

per_question = []
for q in QUESTIONS:
    scored = sorted(((score(p, q), p) for p in pages), key=lambda x: -x[0])
    top_hits = [p for s, p in scored if s > 0][:10]
    if not top_hits:
        top_hits = [p for _, p in scored[:10]]

    # index_only: index.md + top-10 frontmatter summaries (≈150 chars/entry)
    index_only = index_tokens + sum(est(p["fm_line"]) for p in top_hits)

    # section_grep: index_only + 10 section reads (~30 lines × 80 chars ≈ 2400 chars ≈ 600 tokens each)
    section_grep = index_only + 10 * 600

    # full_read: index_only + top-3 full page bodies
    full_read = index_only + sum(p["body_tokens"] for p in top_hits[:3])

    per_question.append({
        "question": q,
        "index_only_tokens": index_only,
        "section_grep_tokens": section_grep,
        "full_read_tokens": full_read,
        "naive_tokens": naive_tokens,
        "reduction_vs_naive": {
            "index_only": round(naive_tokens / max(1, index_only), 1),
            "section_grep": round(naive_tokens / max(1, section_grep), 1),
            "full_read": round(naive_tokens / max(1, full_read), 1),
        },
    })

def avg(key):
    return sum(p[key] for p in per_question) // len(per_question)

result = {
    "vault_path": str(VAULT),
    "pages_total": len(pages),
    "naive_tokens": naive_tokens,
    "index_tokens": index_tokens,
    "avg_index_only_tokens": avg("index_only_tokens"),
    "avg_section_grep_tokens": avg("section_grep_tokens"),
    "avg_full_read_tokens": avg("full_read_tokens"),
    "reduction_ratio": {
        "index_only":  round(naive_tokens / max(1, avg("index_only_tokens")), 1),
        "section_grep": round(naive_tokens / max(1, avg("section_grep_tokens")), 1),
        "full_read":    round(naive_tokens / max(1, avg("full_read_tokens")), 1),
    },
    "per_question": per_question,
    "computed_at": datetime.now(timezone.utc).isoformat(),
}

OUT.write_text(json.dumps(result, indent=2))
print(f"Wiki benchmark: {len(pages)} pages, naive={naive_tokens:,} tok")
print(f"  index_only reduction:  {result['reduction_ratio']['index_only']}x  (avg {result['avg_index_only_tokens']:,} tok)")
print(f"  section_grep reduction: {result['reduction_ratio']['section_grep']}x  (avg {result['avg_section_grep_tokens']:,} tok)")
print(f"  full_read reduction:    {result['reduction_ratio']['full_read']}x  (avg {result['avg_full_read_tokens']:,} tok)")
PY

# Append a dashboard record
"$WORKFLOW_ROOT/scripts/dashboard-append.sh" \
  --event wiki-benchmark-weekly \
  --project "obsidian-wiki" \
  --cwd "$VAULT" || true

echo "--- done ---"
