#!/usr/bin/env bash
##############################################################################
# tests/test-no-raw-print.sh — Wave 3 Task 3.5 (token-economics, A10)
#
# Output-side privacy gate — verify scripts/compute-persona-value.py contains
# NO raw print(), sys.stdout.write(), or sys.stderr.write() calls outside the
# small grandfathered allowlist (Stage 1A diagnostics that pre-date the
# safe_log gate). All new output must flow through scripts/_safe_log.safe_log().
#
# Implementation note (testability tightening): we use Python's `tokenize`
# module to walk the source AST-token-by-token, which avoids false positives
# from comments and string literals (a naive `grep print(` would flag
# docstrings and any `print(` literal inside the help epilog).
#
# Scope: ONLY scripts/compute-persona-value.py.
#
# Spec: docs/specs/token-economics/spec.md (v4.2 §Privacy)
# Plan: docs/specs/token-economics/plan.md (v1.2 — Wave 3 task 3.5, A10)
##############################################################################
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

TARGET="scripts/compute-persona-value.py"

if [ ! -f "$TARGET" ]; then
  echo "FAIL: target file missing: $TARGET"
  exit 1
fi

# Run the AST-aware scanner. Combined stdout+stderr printed below; exit
# non-zero on any non-grandfathered violation.
SCAN_OUT="$(python3 - "$TARGET" 2>&1 <<'PY'
import io
import sys
import tokenize

target = sys.argv[1]
with open(target, "r", encoding="utf-8") as fh:
    src = fh.read()

toks = list(tokenize.tokenize(io.BytesIO(src.encode("utf-8")).readline))

violations = []
for i, t in enumerate(toks):
    if t.type == tokenize.NAME and t.string == "print":
        if (i + 1 < len(toks)
                and toks[i + 1].type == tokenize.OP
                and toks[i + 1].string == "("):
            violations.append((t.start[0], "print("))
    if t.type == tokenize.NAME and t.string == "sys":
        if (i + 4 < len(toks)
                and toks[i + 1].type == tokenize.OP
                and toks[i + 1].string == "."
                and toks[i + 2].type == tokenize.NAME
                and toks[i + 2].string in ("stdout", "stderr")
                and toks[i + 3].type == tokenize.OP
                and toks[i + 3].string == "."
                and toks[i + 4].type == tokenize.NAME
                and toks[i + 4].string == "write"):
            stream = toks[i + 2].string
            violations.append((t.start[0], "sys.{}.write".format(stream)))

# Grandfathered: per Stage 1A comment in the engine, four diagnostic stderr
# call sites pre-date the safe_log gate. Match by keyword in the surrounding
# 5-line snippet so the test is not locked to specific line numbers.
GRANDFATHERED_KEYWORDS = (
    "non-interactive stdin detected",
    "unconfirmed scan-root(s) provided",
    "A1.5 cross-check failed",
    "cannot resolve XDG_CONFIG_HOME or $HOME",
    # MF-3 (--accept-salt-reset) refusal: explanatory diagnostic on the
    # destructive-regen path. User-actionable error message; falls under
    # the same "operator-facing diagnostic, not data leakage" exemption
    # as the other grandfathered sites.
    "finding-id-salt at",
    # MF-2 (A1.6) match-rate threshold: explanatory diagnostic when the
    # persona-attribution regex misses too often (CC subagent format
    # drift). Counts only — no paths or finding contents.
    "A1.6 attribution match rate",
)

src_lines = src.splitlines()
real = []
grand = []
for line_no, label in violations:
    snippet = "\n".join(src_lines[line_no - 1: line_no + 5])
    if any(kw in snippet for kw in GRANDFATHERED_KEYWORDS):
        grand.append((line_no, label, src_lines[line_no - 1].strip()[:80]))
    else:
        real.append((line_no, label, src_lines[line_no - 1].strip()[:80]))

if grand:
    sys.stdout.write(
        "INFO: grandfathered raw stderr.write sites (refactor target):\n"
    )
    for ln, lbl, ctx in grand:
        sys.stdout.write(
            "  {}:{}: {} -- {}\n".format(target, ln, lbl, ctx)
        )

if real:
    for ln, lbl, ctx in real:
        sys.stdout.write(
            "VIOLATION {}:{}: {} -- {}\n".format(target, ln, lbl, ctx)
        )
    sys.exit(1)
sys.exit(0)
PY
)"
RC=$?

if [ "$RC" -eq 0 ]; then
  if [ -n "$SCAN_OUT" ]; then
    printf '%s\n' "$SCAN_OUT"
  fi
  echo "PASS: no raw print/write in $TARGET (beyond grandfathered allowlist)"
  exit 0
fi

printf '%s\n' "$SCAN_OUT"
echo ""
echo "FAIL: raw print/write sites found in $TARGET"
exit 1
