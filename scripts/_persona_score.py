#!/usr/bin/env python3
"""Persona scoring helper — Slice 3 Wave 3a task 5 (dynamic-roster-per-gate).

Computes ``fit_score`` (pure tag-intersection cardinality, D1/spec A1) and
``combined_score = fit_score * lbr`` (D5) for personas at a given gate.

Cold-start rule: any persona with fewer than 3 records in
``persona-rankings.jsonl`` (or absent entirely, or empty/missing file) gets
``load_bearing_rate = 0.5``.

Lineage default (D9/M1 fix): rankings rows missing the ``lineage`` key default
to ``"claude"`` at read time. No backfill of the source file.

Aggregation choice: when a persona has >=3 rows, the recorded
``load_bearing_rate`` is the **mean** of all rows for that persona (simple,
order-independent, no recency bias). Documented here so callers can rely on it.

CLI shape:
    arg1: JSON array of spec_tags (e.g. '["security","data"]')
    arg2: path to persona-rankings.jsonl (may be empty or missing)
    stdin: JSON object {"personas": [["slug", ["fit_tag1", ...]], ...]}
    stdout: JSON array of PersonaScore dicts, sorted DESC by combined_score
            (stable; ties broken alphabetically by persona slug).
    exit 0 ok; exit 2 bad input.

AST-banlist clean (followup ck-5566778899): stdlib only, no ast/subprocess/
socket/eval/exec/__import__.
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
from collections import defaultdict
from pathlib import Path
from typing import TypedDict


COLD_START_LBR = 0.5
COLD_START_MIN_RUNS = 3
DEFAULT_LINEAGE = "claude"


class PersonaScore(TypedDict):
    persona: str
    fit_score: int
    combined_score: float
    lineage: str


def score_persona(
    persona_slug: str,
    persona_fit_tags: list[str] | set[str],
    spec_tags: list[str] | set[str],
    lbr: float | None,
    lineage: str = DEFAULT_LINEAGE,
) -> PersonaScore:
    """Compute fit_score + combined_score for one persona.

    ``lbr=None`` means cold-start → 0.5.
    """
    fit_tags = set(persona_fit_tags)
    s_tags = set(spec_tags)
    fit_score = len(fit_tags & s_tags)
    effective = COLD_START_LBR if lbr is None else float(lbr)
    combined = float(fit_score) * effective
    return PersonaScore(
        persona=persona_slug,
        fit_score=fit_score,
        combined_score=combined,
        lineage=lineage or DEFAULT_LINEAGE,
    )


def read_rankings(rankings_path: str | Path) -> dict[str, dict]:
    """Read JSONL rankings file. Returns per-persona aggregate.

    Output shape::

        {persona_slug: {"runs": int, "load_bearing_rate": float, "lineage": str}}

    - Missing/empty file → ``{}``.
    - Missing ``lineage`` in a row → ``"claude"`` (D9). Last non-default
      lineage seen wins; otherwise default.
    - ``load_bearing_rate`` is the mean across that persona's rows.
    - Cold-start gating (<3 runs) is the caller's responsibility — this fn
      returns the raw aggregate so callers can introspect run counts.
    """
    path = Path(rankings_path)
    if not path.exists():
        return {}

    by_persona_lbrs: dict[str, list[float]] = defaultdict(list)
    by_persona_lineage: dict[str, str] = {}

    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return {}

    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            # Skip malformed rows rather than blow up the gate.
            continue
        if not isinstance(row, dict):
            continue
        slug = row.get("persona")
        if not isinstance(slug, str) or not slug:
            continue
        lbr_val = row.get("load_bearing_rate")
        if isinstance(lbr_val, (int, float)):
            by_persona_lbrs[slug].append(float(lbr_val))
        lineage = row.get("lineage", DEFAULT_LINEAGE)
        if not isinstance(lineage, str) or not lineage:
            lineage = DEFAULT_LINEAGE
        by_persona_lineage[slug] = lineage

    out: dict[str, dict] = {}
    for slug, lbrs in by_persona_lbrs.items():
        out[slug] = {
            "runs": len(lbrs),
            "load_bearing_rate": statistics.fmean(lbrs) if lbrs else COLD_START_LBR,
            "lineage": by_persona_lineage.get(slug, DEFAULT_LINEAGE),
        }
    # Handle personas seen without a numeric lbr (lineage-only rows).
    for slug, lineage in by_persona_lineage.items():
        if slug not in out:
            out[slug] = {
                "runs": 0,
                "load_bearing_rate": COLD_START_LBR,
                "lineage": lineage,
            }
    return out


def effective_lbr(persona_slug: str, rankings: dict[str, dict]) -> float:
    """Return the load_bearing_rate to use for scoring.

    Cold-start (<3 runs, or absent) → 0.5. Else the recorded rate.
    """
    entry = rankings.get(persona_slug)
    if not entry:
        return COLD_START_LBR
    if entry.get("runs", 0) < COLD_START_MIN_RUNS:
        return COLD_START_LBR
    lbr = entry.get("load_bearing_rate")
    if not isinstance(lbr, (int, float)):
        return COLD_START_LBR
    return float(lbr)


def _lineage_for(persona_slug: str, rankings: dict[str, dict]) -> str:
    entry = rankings.get(persona_slug)
    if not entry:
        return DEFAULT_LINEAGE
    lineage = entry.get("lineage", DEFAULT_LINEAGE)
    if not isinstance(lineage, str) or not lineage:
        return DEFAULT_LINEAGE
    return lineage


def score_all(
    personas: list[tuple[str, list[str]]],
    spec_tags: list[str],
    rankings_path: str | Path | None,
) -> list[PersonaScore]:
    """Score every (slug, fit_tags) pair; sort DESC by combined_score.

    Stable sort; ties broken alphabetically by persona slug.
    """
    rankings: dict[str, dict] = {}
    if rankings_path is not None:
        rankings = read_rankings(rankings_path)

    scored: list[PersonaScore] = []
    for slug, fit_tags in personas:
        entry = rankings.get(slug)
        if entry and entry.get("runs", 0) >= COLD_START_MIN_RUNS:
            lbr: float | None = float(entry["load_bearing_rate"])
        else:
            lbr = None
        lineage = _lineage_for(slug, rankings)
        scored.append(score_persona(slug, fit_tags, spec_tags, lbr, lineage=lineage))

    # Stable sort: alphabetical first, then DESC combined_score.
    scored.sort(key=lambda r: r["persona"])
    scored.sort(key=lambda r: r["combined_score"], reverse=True)
    return scored


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Score personas by fit_score * load_bearing_rate."
    )
    parser.add_argument(
        "spec_tags_json",
        help='JSON array of spec tags, e.g. \'["security","data"]\'',
    )
    parser.add_argument(
        "rankings_path",
        help="Path to persona-rankings.jsonl (may be empty or missing).",
    )
    return parser.parse_args(argv)


def _main(argv: list[str]) -> int:
    args = _parse_args(argv)
    try:
        spec_tags = json.loads(args.spec_tags_json)
    except json.JSONDecodeError as exc:
        print(f"bad spec_tags JSON: {exc}", file=sys.stderr)
        return 2
    if not isinstance(spec_tags, list):
        print("spec_tags must be a JSON array", file=sys.stderr)
        return 2

    try:
        stdin_blob = json.loads(sys.stdin.read() or "{}")
    except json.JSONDecodeError as exc:
        print(f"bad stdin JSON: {exc}", file=sys.stderr)
        return 2
    raw_personas = stdin_blob.get("personas", []) if isinstance(stdin_blob, dict) else []
    personas: list[tuple[str, list[str]]] = []
    for item in raw_personas:
        if (
            isinstance(item, (list, tuple))
            and len(item) == 2
            and isinstance(item[0], str)
            and isinstance(item[1], list)
        ):
            personas.append((item[0], [t for t in item[1] if isinstance(t, str)]))

    # Allow stdin-supplied spec_tags to override argv when present.
    stdin_spec_tags = stdin_blob.get("spec_tags") if isinstance(stdin_blob, dict) else None
    if isinstance(stdin_spec_tags, list):
        spec_tags = stdin_spec_tags

    result = score_all(personas, spec_tags, args.rankings_path)
    json.dump(result, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(_main(sys.argv[1:]))
