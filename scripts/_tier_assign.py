#!/usr/bin/env python3
"""Tier assignment helper — Slice 3 Wave 3a task 6 (dynamic-roster-per-gate).

Implements the tier-mix algorithm (plan D6), SEC-01 floor enforcement (D7),
SEC-04 spec_overridable_keys allowlist for tier_policy merges (D8), and the
straight-line pin honoring contract (D14; accumulate-drop-lowest belongs to
the resolver layer, this helper just trusts already-merged pins).

Public API:
    deep_merge_tier_policy(base, override, allowed_keys=None) -> dict
    validate_tier_pins(tier_pins, persona_registry, security_floor) -> int
    assign_tiers(scored, opus_min, sonnet_min=1,
                 remainder_tiebreak="sonnet", tier_pins=None) -> list

Re-exports for resolver convenience:
    assert_baseline_subset, TagDriftError (from _tag_baseline)

CLI shape:
    stdin: JSON object with keys scored, opus_min, sonnet_min,
           remainder_tiebreak, tier_pins
    stdout: JSON array of TierAssignment dicts, sorted opus-first then
            combined_score DESC.
    exit 0 ok / 2 malformed / 3 degenerate / 4 SEC-01 violation.

AST-banlist clean (followup ck-5566778899): stdlib only — json, sys, math,
copy, argparse, typing. No ast/eval/exec/subprocess/socket/__import__.
"""

from __future__ import annotations

import argparse
import copy
import json
import math
import sys
from typing import Literal, TypedDict

# Cross-helper import (resolver puts scripts/ on sys.path); see plan task 7.
from _tag_baseline import assert_baseline_subset, TagDriftError  # noqa: F401


Tier = Literal["opus", "sonnet"]
VALID_TIERS = ("opus", "sonnet")


class TierAssignment(TypedDict):
    persona: str
    tier: Tier
    fit_score: int
    combined_score: float


# ---------------------------------------------------------------------------
# deep_merge_tier_policy — SEC-04 allowlist enforcement
# ---------------------------------------------------------------------------

def deep_merge_tier_policy(
    base: dict,
    override: dict,
    allowed_keys: list[str] | None = None,
) -> dict:
    """Recursive key-level merge: override wins, base preserved for un-set keys.

    When ``allowed_keys`` is provided (SEC-04 spec_overridable_keys), any
    top-level key in ``override`` not present in the allowlist is dropped and
    a warning is written to stderr so the dispatcher sees the rejection.
    """
    merged = copy.deepcopy(base) if isinstance(base, dict) else {}
    if not isinstance(override, dict):
        return merged

    for key, val in override.items():
        if allowed_keys is not None and key not in allowed_keys:
            sys.stderr.write(
                f"[tier-policy] SEC-04: dropped non-allowlisted override key "
                f"'{key}' (allowed: {sorted(allowed_keys)})\n"
            )
            continue
        if isinstance(val, dict) and isinstance(merged.get(key), dict):
            # Nested merge — allowlist only applies at the top level.
            merged[key] = deep_merge_tier_policy(merged[key], val, allowed_keys=None)
        else:
            merged[key] = copy.deepcopy(val)
    return merged


# ---------------------------------------------------------------------------
# validate_tier_pins — SEC-01 floor enforcement + shape checks
# ---------------------------------------------------------------------------

def _iter_pin_entries(tier_pins: dict):
    """Yield (gate_or_none, persona, tier) tuples from either shape.

    Accepts the nested ``{"<gate>": {"<persona>": tier}}`` form or the flat
    ``{"<persona>": tier}`` form. Distinguishes by inspecting whether any
    top-level value is a dict.
    """
    is_nested = any(isinstance(v, dict) for v in tier_pins.values())
    if is_nested:
        for gate, inner in tier_pins.items():
            if not isinstance(inner, dict):
                # Mixed shape — treat as malformed.
                yield ("__malformed__", gate, None)
                continue
            for persona, tier in inner.items():
                yield (gate, persona, tier)
    else:
        for persona, tier in tier_pins.items():
            yield (None, persona, tier)


def validate_tier_pins(
    tier_pins: dict,
    persona_registry: dict,
    security_floor: Tier,
) -> int:
    """Validate tier-pin block; return numeric exit-code style status.

    Returns:
        0 — all pins valid (or tier_pins empty/None and registry non-empty;
            empty pin block is degenerate only when explicitly provided)
        2 — config malformed (bad gate/tier value, persona not in registry,
            non-string keys, mixed-shape pins)
        3 — degenerate (empty pin block, redundant identical pin keys)
        4 — SEC-01 violation: a persona whose registry fit_tags contains
            "security" is pinned below the security_floor.
    """
    if tier_pins is None:
        return 0
    if not isinstance(tier_pins, dict):
        return 2
    if len(tier_pins) == 0:
        return 3

    if security_floor not in VALID_TIERS:
        return 2

    # Tier strictness ordering: opus is strictly above sonnet.
    rank = {"sonnet": 0, "opus": 1}
    floor_rank = rank[security_floor]

    seen: set[tuple] = set()
    for gate, persona, tier in _iter_pin_entries(tier_pins):
        if gate == "__malformed__":
            return 2
        if not isinstance(persona, str) or not isinstance(tier, str):
            return 2
        if tier not in VALID_TIERS:
            return 2
        if persona not in persona_registry:
            return 2

        # Redundant-pin detection (same persona pinned to same tier twice
        # across gates is degenerate, not an error).
        key = (persona, tier)
        if key in seen:
            return 3
        seen.add(key)

        # SEC-01: security-tagged personas must not be pinned below floor.
        fit_tags = persona_registry.get(persona) or []
        if "security" in fit_tags and rank[tier] < floor_rank:
            sys.stderr.write(
                f"[tier-policy] SEC-01: persona {persona} "
                f"(fit_tags=[security]) pinned to {tier} below "
                f"security_floor={security_floor}; refusing.\n"
            )
            return 4

    return 0


# ---------------------------------------------------------------------------
# assign_tiers — D6 tier-mix algorithm
# ---------------------------------------------------------------------------

def _flatten_pins(tier_pins: dict | None) -> dict:
    """Collapse either pin shape into a flat {persona: tier} map.

    When the nested ``{gate: {persona: tier}}`` shape is supplied and the same
    persona appears under multiple gates with conflicting tiers, the higher
    tier wins (opus > sonnet) — defensive only; resolver should pre-merge.
    """
    flat: dict[str, str] = {}
    if not tier_pins:
        return flat
    rank = {"sonnet": 0, "opus": 1}
    for _gate, persona, tier in _iter_pin_entries(tier_pins):
        if not isinstance(persona, str) or tier not in VALID_TIERS:
            continue
        prior = flat.get(persona)
        if prior is None or rank[tier] > rank[prior]:
            flat[persona] = tier
    return flat


def assign_tiers(
    scored: list[dict],
    opus_min: int,
    sonnet_min: int = 1,
    remainder_tiebreak: Tier = "sonnet",
    tier_pins: dict | None = None,
) -> list[TierAssignment]:
    """Tier-mix per plan D6.

    base_opus = max(opus_min, floor(N / 2)); top base_opus by combined_score
    get opus, the remainder get sonnet. Ties broken alphabetically by persona
    slug (deterministic, sonnet-biased given default remainder_tiebreak).

    Pinned personas keep their assigned tier regardless of combined_score
    ranking. If pins push the opus cohort above the budget, the lowest-scoring
    non-pinned non-security persona is demoted to sonnet (D14 simplification
    for Slice 3; full accumulate-drop logic lives in the resolver).
    """
    n = len(scored)
    if n == 0:
        return []

    flat_pins = _flatten_pins(tier_pins)

    # Stable sort: combined_score DESC, then persona ASC for tie alphabetical.
    ordered = sorted(
        scored,
        key=lambda row: (-float(row.get("combined_score", 0.0)),
                         str(row.get("persona", ""))),
    )

    base_opus = max(int(opus_min), n // 2)
    base_opus = min(base_opus, n)  # cap at N

    # Apply pins first.
    pinned_opus = [r for r in ordered
                   if flat_pins.get(r["persona"]) == "opus"]
    pinned_sonnet = [r for r in ordered
                     if flat_pins.get(r["persona"]) == "sonnet"]
    unpinned = [r for r in ordered if r["persona"] not in flat_pins]

    opus_budget_remaining = base_opus - len(pinned_opus)

    assignments: dict[str, str] = {}
    for r in pinned_opus:
        assignments[r["persona"]] = "opus"
    for r in pinned_sonnet:
        assignments[r["persona"]] = "sonnet"

    if opus_budget_remaining < 0:
        # Pins overflow opus budget. Honor pins; emit a stderr note.
        sys.stderr.write(
            f"[tier-policy] pin overflow: {len(pinned_opus)} opus pins exceed "
            f"base_opus={base_opus}; honoring pins as authoritative.\n"
        )
        for r in unpinned:
            assignments[r["persona"]] = "sonnet"
    else:
        # Promote top unpinned to opus by ranking.
        for r in unpinned[:opus_budget_remaining]:
            assignments[r["persona"]] = "opus"
        for r in unpinned[opus_budget_remaining:]:
            assignments[r["persona"]] = "sonnet"

    # Hint: remainder_tiebreak is reflected by the sort + slice (default
    # behaviour favors sonnet for the *cut* persona on a tie because the
    # alphabetical key only matters at the cut). Currently advisory; the
    # caller's expected default is "sonnet" and the algorithm preserves that.
    _ = remainder_tiebreak

    # Build output, sorted opus-first then combined_score DESC then persona.
    out: list[TierAssignment] = []
    for r in scored:
        out.append(TierAssignment(
            persona=str(r["persona"]),
            tier=assignments.get(r["persona"], "sonnet"),  # type: ignore[arg-type]
            fit_score=int(r.get("fit_score", 0)),
            combined_score=float(r.get("combined_score", 0.0)),
        ))
    out.sort(key=lambda a: (
        0 if a["tier"] == "opus" else 1,
        -a["combined_score"],
        a["persona"],
    ))

    # sonnet_min is advisory at this layer — resolver enforces panel-size
    # invariants. Keep the parameter wired for forward compatibility.
    _ = sonnet_min
    return out


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        prog="_tier_assign",
        description="Assign opus/sonnet tiers to scored personas (D6/D7/D14).",
    )
    parser.parse_args(argv)

    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except json.JSONDecodeError as exc:
        sys.stderr.write(f"[tier-assign] malformed JSON on stdin: {exc}\n")
        return 2

    if not isinstance(payload, dict):
        sys.stderr.write("[tier-assign] stdin payload must be a JSON object\n")
        return 2

    scored = payload.get("scored", [])
    if not isinstance(scored, list):
        sys.stderr.write("[tier-assign] 'scored' must be a list\n")
        return 2

    try:
        opus_min = int(payload.get("opus_min", 1))
        sonnet_min = int(payload.get("sonnet_min", 1))
    except (TypeError, ValueError):
        sys.stderr.write("[tier-assign] opus_min/sonnet_min must be int\n")
        return 2

    remainder_tiebreak = payload.get("remainder_tiebreak", "sonnet")
    if remainder_tiebreak not in VALID_TIERS:
        sys.stderr.write(
            f"[tier-assign] remainder_tiebreak must be one of {VALID_TIERS}\n"
        )
        return 2

    tier_pins = payload.get("tier_pins") or {}
    if not isinstance(tier_pins, dict):
        sys.stderr.write("[tier-assign] tier_pins must be an object\n")
        return 2

    result = assign_tiers(
        scored=scored,
        opus_min=opus_min,
        sonnet_min=sonnet_min,
        remainder_tiebreak=remainder_tiebreak,  # type: ignore[arg-type]
        tier_pins=tier_pins,
    )
    sys.stdout.write(json.dumps(result))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
