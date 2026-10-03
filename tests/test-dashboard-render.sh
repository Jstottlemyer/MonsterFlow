#!/usr/bin/env bash
##############################################################################
# tests/test-dashboard-render.sh
#
# A5 (Dashboard tab renders correctly) — static analysis only.
#
# Headless DOM testing under file:// is hard without a real browser. Pragmatic
# approach: parse dashboard/index.html via Python's html.parser (structure +
# attribute checks), then grep dashboard/persona-insights.js as text for the
# load-bearing branches/tokens. Optionally run `node --check` for a syntax
# smoke if node is present.
#
# Read-only: never modifies dashboard/ or persona-insights.js.
#
# Maps to plan.md Wave 3 task 3.2 (v1.2):
#   - explicit e12 fresh-install branch presence
#   - CSS class scaffolding present
#   - color-band thresholds 0.20/0.50 (retention/survival), 0.05/0.20 (unique)
#   - banner copy = CSS class + load-bearing word (NOT full equality)
#   - no-fetch invariant: 0 occurrences of fetch( in persona-insights.js
##############################################################################
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HTML_FILE="$ROOT_DIR/dashboard/index.html"
JS_FILE="$ROOT_DIR/dashboard/persona-insights.js"
JUDGE_JS_FILE="$ROOT_DIR/dashboard/judge.js"

PASS_COUNT=0
FAIL_COUNT=0

note_pass() { echo "PASS: $1"; PASS_COUNT=$((PASS_COUNT+1)); }
note_fail() { echo "FAIL: $1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# Setup checks -----------------------------------------------------------------
if [ ! -f "$HTML_FILE" ]; then
  echo "FAIL: setup — missing $HTML_FILE"
  exit 2
fi
if [ ! -f "$JS_FILE" ]; then
  echo "FAIL: setup — missing $JS_FILE"
  exit 2
fi

# ------------------------------------------------------------------------------
# 1. node --check (syntax smoke) — skip cleanly if node not installed
# ------------------------------------------------------------------------------
if command -v node >/dev/null 2>&1; then
  if node --check "$JS_FILE" 2>/dev/null; then
    note_pass "node --check dashboard/persona-insights.js"
  else
    note_fail "node --check dashboard/persona-insights.js"
  fi
else
  echo "SKIP: node not available; using textual JS source checks only"
fi

if grep -qF 's.outcome === "addressed"' "$JUDGE_JS_FILE"; then
  note_pass "Judge survival panel counts current schema outcome=addressed"
else
  note_fail "Judge survival panel ignores current schema outcome=addressed"
fi

# ------------------------------------------------------------------------------
# 2. HTML structure checks (Python html.parser, no JS execution)
# ------------------------------------------------------------------------------
# Runs once, emits one PASS:/FAIL: line per assertion to stdout.
HTML_RESULT=$(HTML_FILE="$HTML_FILE" python3 - <<'PY'
import os, sys, re
from html.parser import HTMLParser

path = os.environ["HTML_FILE"]
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

# Parse-clean check via html.parser (it is forgiving but errors on truly
# malformed structure when strict=False — we just confirm no exception).
class Probe(HTMLParser):
    def __init__(self):
        super().__init__()
        self.scripts = []   # ordered list of src= attrs (in document order)
        self.persona_button_found = False
    def handle_starttag(self, tag, attrs):
        d = dict(attrs)
        if tag == "script" and d.get("src"):
            self.scripts.append(d["src"])
        if tag == "button" and d.get("data-mode") == "personas":
            self.persona_button_found = True

p = Probe()
try:
    p.feed(src)
    print("PASS: html.parser — index.html parses cleanly")
except Exception as e:
    print(f"FAIL: html.parser — index.html parse error: {e}")

# Persona Insights mode button
if p.persona_button_found:
    # Confirm visible label too.
    if re.search(
        r'<button[^>]*data-mode="personas"[^>]*>\s*Persona Insights\s*</button>',
        src,
    ):
        print('PASS: button[data-mode="personas"] present with label "Persona Insights"')
    else:
        print('FAIL: button[data-mode="personas"] present but label is not "Persona Insights"')
else:
    print('FAIL: button[data-mode="personas"] not found')

# Three required script tags
required = [
    "./data/persona-roster.js",
    "./data/persona-rankings-bundle.js",
    "./persona-insights.js",
]
for src_path in required:
    if src_path in p.scripts:
        print(f"PASS: <script src=\"{src_path}\"> present")
    else:
        print(f"FAIL: <script src=\"{src_path}\"> missing")

# Strict load order: roster → rankings-bundle → persona-insights
indices = []
ok = True
for src_path in required:
    try:
        indices.append(p.scripts.index(src_path))
    except ValueError:
        ok = False
        break
if ok and indices == sorted(indices) and len(set(indices)) == len(indices):
    print("PASS: persona script tags appear in load-strict order (roster → rankings-bundle → persona-insights)")
else:
    print(f"FAIL: persona script tag load order incorrect: indices={indices}")

# CSS scaffolding selectors — must all be present in <style> block.
required_css = [
    ".row-low-sample",
    ".banner-privacy",
    ".banner-stale",
    ".banner-empty-state",
    ".band-low",
    ".band-mid",
    ".band-high",
    ".badge.silent",
    ".badge.never-run",
    ".badge.deleted",
]
missing_css = [sel for sel in required_css if sel not in src]
if not missing_css:
    print("PASS: CSS scaffolding present (.row-low-sample, banners, bands, badges)")
else:
    print(f"FAIL: CSS scaffolding missing: {missing_css}")
PY
)
HTML_EXIT=$?
echo "$HTML_RESULT"
while IFS= read -r line; do
  case "$line" in
    PASS:*) PASS_COUNT=$((PASS_COUNT+1)) ;;
    FAIL:*) FAIL_COUNT=$((FAIL_COUNT+1)) ;;
  esac
done <<<"$HTML_RESULT"
if [ "$HTML_EXIT" -ne 0 ]; then
  note_fail "HTML structure python harness exited non-zero ($HTML_EXIT)"
fi

# ------------------------------------------------------------------------------
# 3. JS source structural checks (read persona-insights.js as text)
# ------------------------------------------------------------------------------
JS_RESULT=$(JS_FILE="$JS_FILE" python3 - <<'PY'
import os, re

path = os.environ["JS_FILE"]
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

def check(name, cond, detail=""):
    if cond:
        print(f"PASS: {name}")
    else:
        msg = f"FAIL: {name}"
        if detail:
            msg += f" — {detail}"
        print(msg)

# Public entry-point registration
check(
    "registers window.__renderPersonaInsightsView",
    "window.__renderPersonaInsightsView" in src,
)

# Empty-state branches
check(
    "has 'bundles-not-loaded' empty-state branch",
    "bundles-not-loaded" in src or "__PERSONA_BUNDLES_LOADED" in src,
)
check(
    "has fresh-install (e12) 'empty' empty-state branch",
    '"empty"' in src or "'empty'" in src or "renderEmptyState(main, \"empty\"" in src,
)

# Deleted-persona detection
check(
    "has deleted-persona detection logic",
    '"deleted"' in src or "'deleted'" in src or "badge deleted" in src,
)

# Insufficient-sample handling
check(
    "has insufficient-sample handling",
    "insufficient_sample" in src or "row-low-sample" in src,
)

# Color band thresholds
# retention/survival: low 0.20, high 0.50
# unique: low 0.05, high 0.20
# Tolerate both 0.20 and .20 styles.
def has_threshold(value):
    # match e.g. 0.20 or .20 or 0.5 (rare) — but spec is explicit so we look for the exact literal.
    return value in src

for kind, lo, hi in [("retention", "0.20", "0.50"),
                     ("survival",  "0.20", "0.50"),
                     ("unique",    "0.05", "0.20")]:
    check(
        f"color band thresholds for {kind} (low {lo} / high {hi})",
        has_threshold(lo) and has_threshold(hi),
    )

# Banner copy assertions: CSS class + load-bearing word
def banner_check(name, css_class, keywords):
    """At least one keyword must appear in the source AND the CSS class must appear."""
    has_class = css_class in src
    has_word = any(kw.lower() in src.lower() for kw in keywords)
    check(
        f"banner copy: {name} (class + load-bearing word)",
        has_class and has_word,
        detail=f"class={has_class}, keyword={has_word}",
    )

banner_check("banner-privacy",     "banner-privacy",     ["screenshot", "screenshots"])
banner_check("banner-stale",       "banner-stale",       ["Last refreshed", "stale", "days ago"])
banner_check("banner-empty-state", "banner-empty-state", ["No persona data", "/wrap-insights"])

# Privacy banner is rendered ALWAYS unless __PERSONA_BUNDLES_LOADED === false.
# Look for the conditional gate on bundle-load failure.
gate_present = re.search(
    r"window\.__PERSONA_BUNDLES_LOADED\s*===\s*false",
    src,
)
check(
    "privacy-banner gate: __PERSONA_BUNDLES_LOADED === false short-circuits",
    bool(gate_present),
)

# No-fetch invariant — under file:// fetch silently fails.
fetch_count = len(re.findall(r"\bfetch\s*\(", src))
check(
    "no-fetch invariant (fetch( count == 0)",
    fetch_count == 0,
    detail=f"observed count={fetch_count}",
)
PY
)
JS_EXIT=$?
echo "$JS_RESULT"
while IFS= read -r line; do
  case "$line" in
    PASS:*) PASS_COUNT=$((PASS_COUNT+1)) ;;
    FAIL:*) FAIL_COUNT=$((FAIL_COUNT+1)) ;;
  esac
done <<<"$JS_RESULT"
if [ "$JS_EXIT" -ne 0 ]; then
  note_fail "JS source python harness exited non-zero ($JS_EXIT)"
fi

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
echo ""
if [ "$FAIL_COUNT" -gt 0 ]; then
  echo "test-dashboard-render.sh: $FAIL_COUNT failed, $PASS_COUNT passed"
  exit 1
fi
echo "test-dashboard-render.sh: $PASS_COUNT passed"
exit 0
