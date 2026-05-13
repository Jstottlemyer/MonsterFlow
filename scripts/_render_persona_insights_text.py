#!/usr/bin/env python3
"""_render_persona_insights_text.py — token-economics Phase 1c text renderer.

Reads dashboard/data/persona-rankings.jsonl and prints the
"Persona insights" sub-section per ux.md spec lines 215-247.

Format (per ux.md, locked):

  Persona insights (last 45 (persona, gate) directories, all discovered projects)

    spec-review
      highest retention      ux-flow (0.89), scope-discipline (0.84), cost-and-quotas (0.78)
      lowest retention       legacy-formatter (0.18), gaps (0.22), ambiguity (0.31)
      highest survival       scope-discipline (62%), edge-cases (54%), feasibility (49%)
      lowest survival        ambiguity (8%), gaps (11%), stakeholders (15%)
      most unique            edge-cases (32%), scope-discipline (28%), codex (24%)
      least unique           feasibility (4%), requirements (6%), gaps (9%)
      cheapest per call      cost-and-quotas (8.2k tok), gaps (9.1k tok), ambiguity (10.4k tok)
      never run this window  legacy-reviewer

    plan                     (only 2 qualifying — need 3 runs each)

    check
      [continues per the same template]

  Note: "retention" is a compression ratio (Judge clustering density), not a true
  survival rate. "survival" is the addressed-downstream rate. See dashboard
  Persona Insights tab for full table + tooltips.

Standalone helper (NOT a heredoc — see memory feedback_hook_stdin_heredoc).
Reads `dashboard/data/persona-rankings.jsonl` relative to cwd by default;
override with --rankings PATH or env MONSTERFLOW_RANKINGS_PATH.

No-op (silent exit 0) when the rankings file is missing or empty — fresh
installs render no Phase 1c sub-section, per spec edge-case e12.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

# Render order is locked: spec-review first, then design, then check.
_GATE_ORDER = ["spec-review", "design", "check"]
_QUALIFY_MIN = 3   # "runs_in_window >= 3" per spec edge-case e1.
_TOP_N = 3

# pipeline-gate-permissiveness W3.10 — class back-fill for pre-v0.9.0 rows.
# Pre-v0.9.0 findings.jsonl rows lack the `class` field (added in spec
# §"Persona-metrics integration", line 339). Default to "unclassified" so
# the field is always present, and filter per-class survival aggregation to
# class != "unclassified" — historical rows don't pollute per-class stats.
# Overall counts still include them. String literal (no enum import) keeps
# us inside the AST-banlist constraints mirrored from _policy_json.py.
_CLASS_BACKFILL_DEFAULT = "unclassified"
_CLASS_KNOWN = (
    "architectural", "security", "contract",
    "documentation", "tests", "scope-cuts",
)


def backfill_class(row: dict) -> str:
    """Return row's `class` field, defaulting missing/None to 'unclassified'.

    Pre-v0.9.0 findings.jsonl rows lack the field entirely; v0.9.0+ rows
    always carry it. Caller decides whether to filter (per-class
    aggregation) or include (overall counts).
    """
    value = row.get("class")
    if not isinstance(value, str) or not value:
        return _CLASS_BACKFILL_DEFAULT
    return value


def aggregate_survival_by_class(rows: list) -> dict:
    """Group rows into per-class buckets, EXCLUDING 'unclassified'.

    Per spec line 339: survival joins filter to `class != 'unclassified'` so
    historical (pre-v0.9.0) rows don't pollute per-class survival rates.
    Returns {class_name: [row, ...]} for the 6 known v1 classes only; rows
    that back-fill to 'unclassified' are dropped from this view.
    """
    out: dict = {}
    for row in rows:
        cls = backfill_class(row)
        if cls == _CLASS_BACKFILL_DEFAULT:
            continue
        out.setdefault(cls, []).append(row)
    return out


def _load_rows(path: Path) -> list[dict]:
    rows: list[dict] = []
    if not path.exists():
        return rows
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return rows
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            # Lenient parse, per spec §Edge cases (e4 + line 320).
            sys.stderr.write(
                "[persona-metrics] skipped malformed row in "
                "persona-rankings.jsonl\n"
            )
            continue
    return rows


def _qualifying(rows: list[dict]) -> list[dict]:
    """Rows whose runs_in_window >= 3 (insufficient_sample == False)."""
    return [
        r for r in rows
        if not r.get("insufficient_sample", False)
        and int(r.get("runs_in_window", 0) or 0) >= _QUALIFY_MIN
    ]


def _fmt_ratio(v) -> str:
    """0.89 → '0.89'."""
    try:
        return "{:.2f}".format(float(v))
    except (TypeError, ValueError):
        return "—"


def _fmt_pct(v) -> str:
    """0.62 → '62%'."""
    try:
        return "{:.0f}%".format(float(v) * 100)
    except (TypeError, ValueError):
        return "—"


def _fmt_tokens(v) -> str:
    """8200 → '8.2k tok'."""
    try:
        n = float(v)
    except (TypeError, ValueError):
        return "— tok"
    if n >= 1000:
        return "{:.1f}k tok".format(n / 1000.0)
    return "{:.0f} tok".format(n)


def _top(rows: list[dict], key: str, n: int = _TOP_N, reverse: bool = True):
    """Return top-n rows by `key`, skipping rows whose key is None."""
    eligible = [r for r in rows if r.get(key) is not None]
    eligible.sort(key=lambda r: r[key], reverse=reverse)
    return eligible[:n]


def _join(rows: list[dict], key: str, fmt) -> str:
    return ", ".join(
        "{} ({})".format(r["persona"], fmt(r.get(key))) for r in rows
    )


def _render_gate(gate: str, gate_rows: list[dict]) -> list[str]:
    """Render one gate block. Returns list of lines (no trailing newline).

    When fewer than 3 rows qualify, returns a single "(only N qualifying)"
    line per ux.md format rule line 244.
    """
    qualifying = _qualifying(gate_rows)
    n_qual = len(qualifying)

    # Gate header line — pad to align the parenthetical when low-qualify.
    if n_qual < _QUALIFY_MIN:
        return [
            "  {gate:<25}(only {n} qualifying — need 3 runs each)".format(
                gate=gate, n=n_qual
            )
        ]

    lines = ["  {}".format(gate)]

    # Retention (judge_retention_ratio) — top + bottom.
    hi_ret = _top(qualifying, "judge_retention_ratio", reverse=True)
    lo_ret = _top(qualifying, "judge_retention_ratio", reverse=False)
    lines.append("    highest retention      " + _join(hi_ret, "judge_retention_ratio", _fmt_ratio))
    lines.append("    lowest retention       " + _join(lo_ret, "judge_retention_ratio", _fmt_ratio))

    # Survival (downstream_survival_rate) — top + bottom.
    hi_sur = _top(qualifying, "downstream_survival_rate", reverse=True)
    lo_sur = _top(qualifying, "downstream_survival_rate", reverse=False)
    lines.append("    highest survival       " + _join(hi_sur, "downstream_survival_rate", _fmt_pct))
    lines.append("    lowest survival        " + _join(lo_sur, "downstream_survival_rate", _fmt_pct))

    # Uniqueness (uniqueness_rate) — top + bottom.
    hi_uniq = _top(qualifying, "uniqueness_rate", reverse=True)
    lo_uniq = _top(qualifying, "uniqueness_rate", reverse=False)
    lines.append("    most unique            " + _join(hi_uniq, "uniqueness_rate", _fmt_pct))
    lines.append("    least unique           " + _join(lo_uniq, "uniqueness_rate", _fmt_pct))

    # Cost — top-3-CHEAPEST only (most actionable per ux.md line 243).
    cheap = _top(qualifying, "avg_tokens_per_invocation", reverse=False)
    lines.append("    cheapest per call      " + _join(cheap, "avg_tokens_per_invocation", _fmt_tokens))

    # "never run this window" — personas in any-gate rows but absent from
    # this gate's row set. Cross-gate scope keeps the line useful even when
    # roster sidecar is unavailable to this helper.
    return lines


def _never_run_for_gate(
    gate: str, all_rows: list[dict], roster_by_gate: dict[str, set[str]]
) -> list[str]:
    """Return personas in this gate's roster missing from this gate's rows.

    Codex P2 fix at /preship: roster is gate-scoped — plan-only personas must
    not show up as 'never run' in spec-review. roster_by_gate maps each gate
    name to the set of personas defined for it; we only consider personas
    that belong to the gate we're rendering.
    """
    present = {r["persona"] for r in all_rows if r.get("gate") == gate}
    eligible = roster_by_gate.get(gate, set())
    missing = sorted(eligible - present)
    return missing


def _load_roster_personas(path: Path) -> dict[str, set[str]]:
    """Best-effort parse of dashboard/data/persona-roster.js.

    Returns a mapping {gate: {persona, ...}}. Codex P2 fix: each persona is
    scoped to the gate(s) it actually belongs to (per the roster sidecar's
    {persona, gate, ...} entries). Empty mapping on failure (the "never run"
    line is silently omitted, per ux.md format rule line 245).
    """
    empty: dict[str, set[str]] = {}
    if not path.exists():
        return empty
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return empty
    # Find first '[' and matching last ']'; tolerant strip.
    lb = text.find("[")
    rb = text.rfind("]")
    if lb < 0 or rb <= lb:
        return empty
    try:
        arr = json.loads(text[lb:rb + 1])
    except json.JSONDecodeError:
        return empty
    out: dict[str, set[str]] = {}
    for entry in arr:
        if isinstance(entry, dict):
            p = entry.get("persona")
            g = entry.get("gate")
            if isinstance(p, str) and isinstance(g, str):
                out.setdefault(g, set()).add(p)
    return out


def render(rankings_path: Path, roster_path: Path | None = None) -> str:
    rows = _load_rows(rankings_path)
    if not rows:
        return ""  # Silent — fresh install, no Phase 1c sub-section.

    roster: dict[str, set[str]] = {}
    if roster_path is not None:
        roster = _load_roster_personas(roster_path)

    out_lines: list[str] = []
    out_lines.append(
        "Persona insights (last 45 (persona, gate) directories, all "
        "discovered projects)"
    )
    out_lines.append("")

    for gate in _GATE_ORDER:
        gate_rows = [r for r in rows if r.get("gate") == gate]
        block = _render_gate(gate, gate_rows)
        out_lines.extend(block)
        # "never run" line: only when roster data available + qualifying
        # gate (low-qualify gates already collapse to a single line).
        if (
            roster
            and len(block) > 1
            and len(_qualifying(gate_rows)) >= _QUALIFY_MIN
        ):
            missing = _never_run_for_gate(gate, rows, roster)
            if missing:
                out_lines.append(
                    "    never run this window  " + ", ".join(missing)
                )
        out_lines.append("")

    out_lines.append(
        "  Note: \"retention\" is a compression ratio (Judge clustering "
        "density), not a true"
    )
    out_lines.append(
        "  survival rate. \"survival\" is the addressed-downstream rate. "
        "See dashboard"
    )
    out_lines.append("  Persona Insights tab for full table + tooltips.")

    return "\n".join(out_lines) + "\n"


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        prog="_render_persona_insights_text.py",
        description=(
            "Render the /wrap-insights Phase 1c 'Persona insights' text "
            "section from dashboard/data/persona-rankings.jsonl."
        ),
    )
    parser.add_argument(
        "--rankings",
        default=None,
        help=(
            "Path to persona-rankings.jsonl (default: "
            "dashboard/data/persona-rankings.jsonl relative to cwd; or "
            "$MONSTERFLOW_RANKINGS_PATH if set)."
        ),
    )
    parser.add_argument(
        "--roster",
        default=None,
        help=(
            "Path to persona-roster.js sidecar (default: alongside "
            "rankings file)."
        ),
    )
    args = parser.parse_args(argv)

    if args.rankings:
        rankings = Path(args.rankings)
    elif os.environ.get("MONSTERFLOW_RANKINGS_PATH"):
        rankings = Path(os.environ["MONSTERFLOW_RANKINGS_PATH"])
    else:
        rankings = Path.cwd() / "dashboard" / "data" / "persona-rankings.jsonl"

    if args.roster:
        roster = Path(args.roster)
    else:
        roster = rankings.parent / "persona-roster.js"

    output = render(rankings, roster)
    if output:
        sys.stdout.write(output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
