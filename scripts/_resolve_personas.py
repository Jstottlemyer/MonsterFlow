#!/usr/bin/env python3
"""
_resolve_personas.py — selection algorithm for resolve-personas.sh

Invoked by scripts/resolve-personas.sh (the bash wrapper). The wrapper is the
public surface; this module is internal. Kept in Python because the algorithm
needs JSON parsing, sorting by float keys, and sentinel-bracketed schema
emission — bash + jq is the wrong tool.

Contract:
- stdout: persona names, one per line, then optional "codex-adversary" line
  (only when CODEX_AUTH=1 in env). Empty stdout is a violation; caller exits 2.
- stderr: human reasoning (only with --why or for warnings).
- exit codes: 0=ok, 2=config malformed, 3=degenerate, 4=missing --feature for
  lock-write / SEC-01 tier-pin violation, 5=internal error, 6=SEC-04 baseline
  drift halt (only emitted by the --with-tier flow; legacy path never returns
  6).

`--with-tier` (Slice 3 Wave 3b, this slice) is an opt-in flag that enables the
content-aware tier-mix flow (tag_baseline → persona_score → tier_assign) and
switches stdout to ``<persona>:<tier>`` per line. Default OFF so the 6 legacy
callers (commands/{spec-review,plan,check}.md, scripts/autorun/{...}.sh) keep
parsing bare-name stdout until Slice 4 (Wave W4) patches them. The opt-in flag
also gates `--opus-min` and `--tier-pin`: those args are accepted by argparse
without `--with-tier` so future call sites do not fail to parse, but they emit
a single stderr warning and have no behavioural effect.

Bash 3.2 portability is irrelevant here (Python). The wrapper handles bash
edge cases (PATH stub for codex, tilde expansion).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from pathlib import Path
from typing import Any

# Tier-mix helpers (D6/D7/D8 — only used when --with-tier is set). The sibling
# helpers live in the same scripts/ directory; insert that dir on sys.path so
# the absolute imports resolve when this module is invoked as a script.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _tag_baseline import compute_baseline, assert_baseline_subset, TagDriftError  # noqa: E402
from _persona_score import score_all, effective_lbr, read_rankings  # noqa: E402,F401
from _tier_assign import assign_tiers, validate_tier_pins, deep_merge_tier_policy  # noqa: E402,F401

SEED: dict[str, list[str]] = {
    "spec-review": ["requirements", "gaps", "scope", "ambiguity", "feasibility", "stakeholders"],
    "plan": ["integration", "api", "data-model", "security", "ux", "scalability", "wave-sequencer"],
    "check": ["scope-discipline", "risk", "completeness", "sequencing", "testability", "security-architect"],
}

VALID_GATES = set(SEED.keys())

# Gate name → persona directory name. Per CLAUDE.md: spec-review uses
# personas/review/; plan and check share their gate name as the directory.
GATE_TO_DIR: dict[str, str] = {
    "spec-review": "review",
    "plan": "plan",
    "check": "check",
}

CONFIG_SCHEMA: dict[str, Any] = {
    "$schema_version": 1,
    "type": "object",
    "properties": {
        "$schema_version": {"type": "integer", "const": 1},
        "agent_budget": {"type": "integer", "minimum": 1, "maximum": 8},
        "persona_pins": {
            "type": "object",
            "additionalProperties": {"type": "array", "items": {"type": "string"}},
        },
        "codex_disabled": {"type": "boolean"},
        "tier_hint": {"type": "string"},
    },
    "additionalProperties": True,
}


def expand(p: str) -> Path:
    return Path(os.path.expanduser(os.path.expandvars(p)))


def warn(msg: str) -> None:
    print(f"resolve-personas: {msg}", file=sys.stderr)


def read_json(path: Path) -> dict[str, Any] | None:
    """Atomic read with retry-once on absence (race with config rewrite)."""
    for attempt in (0, 1):
        try:
            with path.open("r") as f:
                return json.load(f)
        except FileNotFoundError:
            if attempt == 0:
                time.sleep(0.05)
                continue
            return None
        except json.JSONDecodeError:
            warn(f"malformed JSON at {path}")
            sys.exit(2)
        except OSError as e:
            warn(f"unreadable {path}: {e}")
            sys.exit(2)
    return None


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    if not path.is_file():
        return []
    rows = []
    try:
        with path.open("r") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    rows.append(json.loads(line))
                except json.JSONDecodeError:
                    # Skip malformed lines but don't fail — rankings file is
                    # produced asynchronously and may have partial writes.
                    continue
    except OSError:
        return []
    return rows


def disk_personas(repo_dir: Path, gate: str) -> list[str]:
    """Per CLAUDE.md: spec-review → personas/review/; plan and check share name."""
    dir_name = GATE_TO_DIR.get(gate, gate)
    d = repo_dir / "personas" / dir_name
    if not d.is_dir():
        return []
    return sorted(p.stem for p in d.glob("*.md"))


def codex_authenticated() -> bool:
    """Wrapper script sets CODEX_AUTH=1 if codex login status exited 0."""
    return os.environ.get("CODEX_AUTH") == "1"


def write_atomic(path: Path, content: str) -> None:
    # Per-PID tmp suffix: concurrent invocations writing the same selection.json
    # would otherwise stomp on each other's .tmp file between create and replace
    # (caught by tests/test-resolve-personas.sh case 44 — 7 parallel writes
    # produced FileNotFoundError on 1-3 of 7 children).
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(f"{path.suffix}.tmp.{os.getpid()}")
    with tmp.open("w") as f:
        f.write(content)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def emit_schema() -> None:
    print(json.dumps(CONFIG_SCHEMA, indent=2))


def run(args: argparse.Namespace, repo_dir: Path, project_dir: Path | None = None) -> int:
    # Backlog #46 fix (2026-05-09): when MonsterFlow is invoked from an
    # adopter project (RedRabbit, etc.), `repo_dir` resolves to MonsterFlow
    # (where personas + dashboard live) but `docs/specs/<feature>/` lives
    # in the adopter's repo — `project_dir` separates the two. When
    # `project_dir` is None we fall back to `repo_dir` so MonsterFlow's
    # own self-tests (which live under MonsterFlow/docs/specs/) keep
    # working unchanged.
    if project_dir is None:
        project_dir = repo_dir
    gate = args.gate
    if gate not in VALID_GATES:
        warn(f"unknown gate '{gate}' (expected one of: {', '.join(sorted(VALID_GATES))})")
        return 5

    feature_slug = args.feature
    why = args.why

    config_path = expand("~/.config/monsterflow/config.json")
    on_disk = disk_personas(repo_dir, gate)
    codex_avail = codex_authenticated()

    # MONSTERFLOW_DISABLE_BUDGET=1 — emergency kill switch (MF4)
    if os.environ.get("MONSTERFLOW_DISABLE_BUDGET") == "1":
        if not on_disk:
            warn(f"MONSTERFLOW_DISABLE_BUDGET=1 active but no personas found on disk for gate '{gate}' — aborting")
            return 2
        if why:
            print(f"kill-switch: MONSTERFLOW_DISABLE_BUDGET=1 — bypassing budget", file=sys.stderr)
            print(f"on_disk({gate}): {', '.join(on_disk)}", file=sys.stderr)
        return _emit(on_disk, codex_avail and not _codex_disabled_in_config(config_path),
                     method="full", config_path=str(config_path),
                     feature_slug=feature_slug, gate=gate, repo_dir=repo_dir, project_dir=project_dir,
                     budget_used=len(on_disk), budget_source="kill-switch",
                     pins_used=[], dropped_pins=[], dropped_over_budget=[],
                     selection_method="full", emit_json=args.emit_selection_json)

    # Lock check (per-feature snapshot)
    lock = None
    lock_path = None
    if feature_slug:
        lock_path = project_dir / "docs" / "specs" / feature_slug / ".budget-lock.json"
        if lock_path.is_file():
            lock = read_json(lock_path)

    # Live config
    config = read_json(config_path)

    # --unlock-budget: delete lock and exit 0
    if args.unlock_budget:
        if lock_path and lock_path.is_file():
            lock_path.unlink()
            warn(f"unlocked: removed {lock_path}")
        else:
            warn("unlock-budget: no lock file to remove")
        return 0

    # Determine config view (locked > live > absent)
    if lock is not None:
        config_view = lock
        selection_method_hint = "locked"
    elif config is None or "agent_budget" not in config:
        # Full-roster path — no behavior change for unconfigured users.
        if not on_disk:
            warn(f"no personas found at personas/{gate}/")
            return 3
        codex_disabled = bool((config or {}).get("codex_disabled", False))
        return _emit(on_disk, codex_avail and not codex_disabled,
                     method="full", config_path=str(config_path),
                     feature_slug=feature_slug, gate=gate, repo_dir=repo_dir, project_dir=project_dir,
                     budget_used=len(on_disk), budget_source="unconfigured",
                     pins_used=[], dropped_pins=[], dropped_over_budget=[],
                     selection_method="full", emit_json=args.emit_selection_json,
                     why=why, on_disk=on_disk)
    else:
        config_view = config
        selection_method_hint = None

    # Validate + clamp budget
    raw_budget = config_view.get("agent_budget")
    try:
        budget = int(raw_budget)
    except (TypeError, ValueError):
        warn(f"agent_budget must be an integer, got {raw_budget!r}")
        return 2
    if budget < 1:
        warn(f"agent_budget={budget} below floor; using 1")
        budget = 1
    if budget > 8:
        warn(f"agent_budget={budget} above ceiling; clamping to 8")
        budget = 8

    pins = (config_view.get("persona_pins") or {}).get(gate, []) or []
    if not isinstance(pins, list):
        warn(f"persona_pins.{gate} must be a list, got {type(pins).__name__}")
        return 2

    codex_disabled = bool(config_view.get("codex_disabled", False))

    # 1. Pins (validated against on_disk; missing pins skipped with warning)
    chosen: list[str] = []
    dropped_pins: list[str] = []
    for p in pins:
        if p in on_disk and p not in chosen:
            chosen.append(p)
        else:
            dropped_pins.append(p)
            warn(f"pin '{p}' not found in personas/{gate}/ — skipping")

    if len(chosen) > budget:
        # Pin overflow at runtime (install.sh validates but be defensive).
        warn(f"pins exceed budget ({len(chosen)} > {budget}); truncating")
        chosen = chosen[:budget]

    # 2. Rankings
    rankings_path = repo_dir / "dashboard" / "data" / "persona-rankings.jsonl"
    rows = [
        r for r in read_jsonl(rankings_path)
        if r.get("gate") == gate
        and r.get("insufficient_sample") is False
        and r.get("persona") in on_disk
        and r.get("persona") != "codex-adversary"
        and r.get("persona") not in chosen
    ]
    rows.sort(
        key=lambda r: (
            -float(r.get("downstream_survival_rate") or 0),
            -float(r.get("uniqueness_rate") or 0),
            -int(r.get("runs_in_window") or 0),
        )
    )
    used_rankings = False
    for r in rows:
        if len(chosen) >= budget:
            break
        chosen.append(r["persona"])
        used_rankings = True

    # 3. Seed fill
    for p in SEED.get(gate, []):
        if len(chosen) >= budget:
            break
        if p in on_disk and p not in chosen:
            chosen.append(p)

    # 4. Disk fill (alphabetical) — covers sparse seed
    for p in on_disk:
        if len(chosen) >= budget:
            break
        if p not in chosen:
            chosen.append(p)

    # Safety cap
    chosen = chosen[:budget]

    if not chosen:
        warn(f"no personas selected for gate '{gate}' (degenerate state)")
        return 3

    # 5. Lock for this feature on first budgeted run
    if selection_method_hint != "locked" and feature_slug:
        feature_dir = project_dir / "docs" / "specs" / feature_slug
        if feature_dir.is_dir():
            lock_data = {
                "schema_version": 1,
                "agent_budget": budget,
                "persona_pins": config.get("persona_pins", {}) if config else {},
                "tier_hint": (config or {}).get("tier_hint"),
                "codex_disabled": codex_disabled,
                "locked_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            }
            write_atomic(feature_dir / ".budget-lock.json",
                         json.dumps(lock_data, indent=2) + "\n")

    if selection_method_hint == "locked":
        method = "locked"
    elif used_rankings:
        method = "rankings"
    else:
        method = "seed"

    dropped_over_budget = [p for p in on_disk if p not in chosen]

    return _emit(chosen, codex_avail and not codex_disabled,
                 method=method, config_path=str(config_path),
                 feature_slug=feature_slug, gate=gate, repo_dir=repo_dir, project_dir=project_dir,
                 budget_used=budget,
                 budget_source=("lock" if selection_method_hint == "locked" else "config"),
                 pins_used=[p for p in pins if p in chosen],
                 dropped_pins=dropped_pins,
                 dropped_over_budget=dropped_over_budget,
                 selection_method=method,
                 emit_json=args.emit_selection_json,
                 why=why, on_disk=on_disk,
                 lock_path=str(lock_path) if lock_path else None,
                 codex_disabled=codex_disabled)


# ---------------------------------------------------------------------------
# --with-tier flow (Slice 3 Wave 3b). Lives behind opt-in flag; legacy run()
# above is unchanged. Functions are private (underscore prefix) per task spec.
# ---------------------------------------------------------------------------

_FRONTMATTER_RE = re.compile(r"\A---\n(.*?)\n---\n", re.DOTALL)
_FIT_TAGS_RE = re.compile(r"^fit_tags\s*:\s*\[([^\]]*)\]\s*$", re.MULTILINE)
_TAGS_RE = re.compile(r"^tags\s*:\s*\[([^\]]*)\]\s*$", re.MULTILINE)
_BASELINE_RE = re.compile(r"^\s*baseline\s*:\s*\[([^\]]*)\]\s*$", re.MULTILINE)
_TAGS_PROV_RE = re.compile(r"^tags_provenance\s*:\s*$(.*?)(?=^\S|\Z)", re.MULTILINE | re.DOTALL)
_TIER_POLICY_RE = re.compile(r"^tier_policy\s*:\s*$(.*?)(?=^\S|\Z)", re.MULTILINE | re.DOTALL)


def _parse_spec_tier_pins(fm: str) -> dict:
    """Extract tier_policy.tier_pins from spec.md frontmatter.

    Returns nested dict: {<gate>: {<persona>: <tier>}}. Empty dict when the
    block is absent (which is the normal case — `tier_policy` is optional).

    The schema (per schemas/spec-frontmatter.schema.json):

      tier_policy:
        tier_pins:
          spec-review:
            <persona>: opus|sonnet
          plan:
            <persona>: opus|sonnet
          check:
            <persona>: opus|sonnet

    Indent-aware parsing: walks lines after `tier_pins:` while indent is
    deeper than the `tier_pins:` key. Tolerates 2- or 4-space indent and
    extra blank lines. Stops at the first line whose indent ≤ the
    `tier_pins:` indent (next sibling key) or end of frontmatter.

    Stays regex-only (no YAML import) so adopters keep zero-deps and the
    AST-banlist holds across all _*.py helpers.
    """
    pins: dict = {}
    tp_match = _TIER_POLICY_RE.search(fm + "\n")
    if not tp_match:
        return pins
    tp_block = tp_match.group(1)
    # Find tier_pins: within the tier_policy block.
    tp_lines = tp_block.splitlines()
    tier_pins_indent = -1
    tier_pins_start = -1
    for i, line in enumerate(tp_lines):
        stripped = line.lstrip()
        if stripped.startswith("tier_pins:") or stripped.startswith("tier_pins :"):
            tier_pins_indent = len(line) - len(stripped)
            tier_pins_start = i + 1
            break
    if tier_pins_start < 0:
        return pins
    # Walk lines deeper than tier_pins_indent; track gate/persona indent.
    current_gate: str | None = None
    gate_indent: int = -1
    for line in tp_lines[tier_pins_start:]:
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip())
        if indent <= tier_pins_indent:
            # Out of the tier_pins block.
            break
        stripped = line.strip()
        # Comments are tolerated.
        if stripped.startswith("#"):
            continue
        if current_gate is None or indent <= gate_indent:
            # Gate-level row: <gate>:
            if stripped.endswith(":"):
                current_gate = stripped[:-1].strip()
                gate_indent = indent
                pins.setdefault(current_gate, {})
            # Else: malformed; skip silently (frontmatter schema validates).
        else:
            # Persona-level row: <persona>: <tier>
            if ":" in stripped:
                persona, _, tier = stripped.partition(":")
                persona = persona.strip()
                tier = tier.strip().strip('"').strip("'")
                if current_gate and persona and tier in ("opus", "sonnet"):
                    pins[current_gate][persona] = tier
    # Drop empty gate keys (no persona rows under them).
    return {g: m for g, m in pins.items() if m}


def _parse_list_literal(raw: str) -> list[str]:
    """Parse a YAML inline list body like 'a, b, c' → ['a','b','c']. Tolerant."""
    return [item.strip().strip('"').strip("'") for item in raw.split(",") if item.strip()]


def _read_frontmatter(path: Path) -> str:
    """Return frontmatter block content (between leading --- markers), or ''."""
    try:
        text = path.read_text(encoding="utf-8")
    except (FileNotFoundError, OSError, UnicodeDecodeError):
        return ""
    m = _FRONTMATTER_RE.match(text)
    return m.group(1) if m else ""


def _build_persona_registry(repo_dir: Path, gate: str) -> dict[str, list[str]]:
    """Read personas/<gate-dir>/*.md frontmatter; return {slug: fit_tags}."""
    dir_name = GATE_TO_DIR.get(gate, gate)
    d = repo_dir / "personas" / dir_name
    registry: dict[str, list[str]] = {}
    if not d.is_dir():
        return registry
    for p in sorted(d.glob("*.md")):
        fm = _read_frontmatter(p)
        m = _FIT_TAGS_RE.search(fm)
        registry[p.stem] = _parse_list_literal(m.group(1)) if m else []
    return registry


def _read_spec_tags(feature_dir: Path) -> tuple[list[str], set[str], list[str], dict]:
    """Return (recorded_baseline, recomputed_baseline, spec_tags, spec_tier_pins).

    recorded_baseline:
      - tags_provenance.baseline if present (the authoritative recorded baseline
        for SEC-04 subset checks)
      - else empty list (no baseline was ever recorded; SEC-04 subset trivially
        holds and we fall through to spec_tags for scoring)
    recomputed_baseline:
      - compute_baseline() over the full spec text
    spec_tags:
      - top-level frontmatter `tags:` list, used for persona scoring; may
        include LLM-added tags beyond the baseline
    spec_tier_pins:
      - tier_policy.tier_pins from frontmatter (nested {gate: {persona: tier}})
      - empty dict when absent
      - merged with CLI pins downstream; SEC-01 validated at the resolver
        (D7 site 1; CLI is site 2).
    """
    spec_path = feature_dir / "spec.md"
    try:
        spec_text = spec_path.read_text(encoding="utf-8")
    except (FileNotFoundError, OSError, UnicodeDecodeError) as e:
        warn(f"--with-tier: cannot read {spec_path}: {e}")
        raise

    fm = ""
    m_fm = _FRONTMATTER_RE.match(spec_text)
    if m_fm:
        fm = m_fm.group(1)

    recorded: list[str] = []
    spec_tags: list[str] = []
    spec_tier_pins: dict = {}
    if fm:
        prov_match = _TAGS_PROV_RE.search(fm + "\n")
        if prov_match:
            base_m = _BASELINE_RE.search(prov_match.group(1))
            if base_m:
                recorded = _parse_list_literal(base_m.group(1))
        tags_m = _TAGS_RE.search(fm)
        if tags_m:
            spec_tags = _parse_list_literal(tags_m.group(1))
        spec_tier_pins = _parse_spec_tier_pins(fm)

    recomputed = compute_baseline(spec_text)
    return recorded, recomputed, spec_tags, spec_tier_pins


def _emit_tier_aware_stdout(assignments: list[dict], codex_authed: bool) -> None:
    """Write `<persona>:<tier>\\n` for each Claude row, `codex-adversary\\n` bare."""
    for row in assignments:
        sys.stdout.write(f"{row['persona']}:{row['tier']}\n")
    if codex_authed:
        sys.stdout.write("codex-adversary\n")
    sys.stdout.flush()


def _emit_v2_selection_json(
    *,
    feature_dir: Path,
    gate: str,
    feature_slug: str,
    assignments: list[dict],
    dropped: list[dict],
    opus_min: int,
    tier_pins: dict,
    codex_authed: bool,
    codex_disabled: bool,
    cli_override_seen: bool,
) -> None:
    """Write selection.json v2 (schema_version:2, prompt_version selection-emit@2.0)."""
    gate_dir = feature_dir / gate
    gate_dir.mkdir(parents=True, exist_ok=True)
    opus_count = sum(1 for a in assignments if a["tier"] == "opus")
    sonnet_count = sum(1 for a in assignments if a["tier"] == "sonnet")

    # Source heuristic: in this slice, CLI is the only override layer plumbed
    # (constitution/spec layering lands in W4). Mark "cli" only when the user
    # explicitly passed an override flag; otherwise "constitution" as the
    # resolved-from default tier_policy source.
    source = "cli" if cli_override_seen else "constitution"

    tpa: dict[str, Any] = {
        "source": source,
        "opus_min": int(opus_min or 0),
        "opus_count_actual": opus_count,
        "sonnet_count_actual": sonnet_count,
        "security_floor": "opus",
    }
    if tier_pins:
        tpa["tier_pins"] = tier_pins

    codex_block: dict | None
    if codex_disabled:
        codex_block = {"persona": "codex-adversary", "policy": "disabled"}
    elif codex_authed:
        codex_block = {"persona": "codex-adversary", "policy": "additive"}
    else:
        codex_block = None

    selection = {
        "schema_version": 2,
        "prompt_version": "selection-emit@2.0",
        "feature": feature_slug,
        "gate": gate,
        "selected": [
            {
                "persona": a["persona"],
                "tier": a["tier"],
                "fit_score": int(a.get("fit_score", 0)),
                "combined_score": float(a.get("combined_score", 0.0)),
            }
            for a in assignments
        ],
        "dropped": sorted(
            [
                {
                    "persona": d["persona"],
                    "tier": d.get("tier", "sonnet"),
                    "fit_score": int(d.get("fit_score", 0)),
                    "combined_score": float(d.get("combined_score", 0.0)),
                }
                for d in dropped
            ],
            key=lambda r: -r["combined_score"],
        ),
        "codex": codex_block,
        "tier_policy_applied": tpa,
    }
    write_atomic(gate_dir / "selection.json", json.dumps(selection, indent=2) + "\n")


def run_with_tier(
    args: argparse.Namespace,
    repo_dir: Path,
    project_dir: Path,
) -> int:
    """Tier-mix flow: tag_baseline → persona_score → tier_assign → emit."""
    # MONSTERFLOW_DISABLE_BUDGET=1 — emergency kill switch. Honored in --with-tier
    # mode by delegating to the legacy run() path, which short-circuits to the
    # full-roster bypass. Without this delegation the kill switch is silently
    # bypassed because all autorun shells now invoke with --with-tier.
    if os.environ.get("MONSTERFLOW_DISABLE_BUDGET") == "1":
        sys.stderr.write(
            "kill-switch: MONSTERFLOW_DISABLE_BUDGET=1 — bypassing --with-tier; "
            "delegating to legacy full-roster path\n"
        )
        return run(args, repo_dir, project_dir)

    gate = args.gate
    if gate not in VALID_GATES:
        warn(f"unknown gate '{gate}' (expected one of: {', '.join(sorted(VALID_GATES))})")
        return 5

    feature_slug = args.feature
    if not feature_slug:
        warn("--with-tier requires --feature")
        return 4

    feature_dir = project_dir / "docs" / "specs" / feature_slug
    if not feature_dir.is_dir():
        warn(f"--with-tier: feature dir missing at {feature_dir}")
        return 4

    # 1. SEC-04 baseline recompute + drift halt + D8 mid-pipeline edit clause.
    try:
        recorded, recomputed, spec_tags, spec_tier_pins = _read_spec_tags(feature_dir)
    except (FileNotFoundError, OSError, UnicodeDecodeError):
        return 5

    recorded_set = set(recorded)
    # SEC-04 only fires when the spec actually CLAIMS a baseline. Grandfathered
    # specs (no tags_provenance.baseline block) and pre-feature specs are
    # exempt — there's nothing to drift against. The /spec Phase 3 flow is
    # what writes the provenance block; once it's present, SEC-04 enforces.
    if recorded_set and not recomputed.issubset(recorded_set):
        # SEC-04 attack: the resolver re-discovered a baseline keyword that
        # the recorded list does not acknowledge. The recorded list was
        # shrunk post-write to evade dispatch (e.g., author deletes
        # `security` from tags_provenance.baseline while body still contains
        # security keywords).
        rec_sorted = sorted(recorded_set)
        recom_sorted = sorted(recomputed)
        sys.stderr.write(
            "[tier-policy] SEC-04: tags_provenance.baseline drift detected; "
            "refusing to dispatch\n"
            f"  recorded={rec_sorted}; recomputed={recom_sorted}\n"
        )
        return 6
    if recorded_set and recorded_set != recomputed:
        # D8 mid-pipeline edit: recomputed is a strict subset of recorded —
        # recorded list has keywords the current body no longer contains
        # (author legitimately removed content that previously baselined).
        # Treat as benign drift and warn-and-proceed. The post-write
        # shrinking attack (recomputed has a keyword recorded doesn't) is
        # already halted above.
        sys.stderr.write(
            "[stale-tags] WARNING: tags_provenance.baseline drifted from "
            "current spec body; consider updating frontmatter\n"
        )

    # Tags used for scoring: prefer top-level `tags:` (which includes any
    # LLM-added tags beyond the baseline). Fall back to recorded or recomputed
    # so a spec with no tags at all still scores against the keyword baseline.
    scoring_tags = spec_tags or recorded or sorted(recomputed)

    # 2. Persona registry (slug → fit_tags).
    registry = _build_persona_registry(repo_dir, gate)
    if not registry:
        warn(f"no personas found at personas/{GATE_TO_DIR.get(gate, gate)}/")
        return 3

    # 3. Tier-pin merge + SEC-01 enforcement.
    #    Per spec L88 ("CLI > spec; key-level merge"): the FINAL EFFECTIVE
    #    tier_pins is what dispatches. SEC-01 floor is checked against the
    #    merged result so a malicious spec-layer pin can be overridden
    #    upward by CLI (intended escape hatch for operators), but neither
    #    layer alone can route a security-class persona below the floor.
    #
    #    D7 site 1 = spec frontmatter `tier_policy.tier_pins` (this resolver)
    #    D7 site 2 = CLI `--tier-pin` (same resolver, parsed below)
    #    Both contribute to the merged dict; validate_tier_pins runs once
    #    on the merger.

    # 3a. Filter the spec's nested pins to the active gate (spec pins are
    #     always nested by schema).
    spec_pins_gate_scoped: dict = {}
    for g, inner in spec_tier_pins.items():
        if g == gate and isinstance(inner, dict):
            spec_pins_gate_scoped.update(inner)

    # 3b. CLI --tier-pin parse.
    cli_tier_pins: dict = {}
    if args.tier_pin:
        for raw in args.tier_pin:
            if "=" not in raw:
                warn(f"--tier-pin: malformed entry '{raw}' (expected key=tier)")
                return 2
            key, tier_val = raw.split("=", 1)
            key = key.strip()
            tier_val = tier_val.strip()
            if "." in key:
                gate_part, persona_part = key.split(".", 1)
                gate_part, persona_part = gate_part.strip(), persona_part.strip()
                inner = cli_tier_pins.setdefault(gate_part, {})
                if isinstance(inner, dict):
                    inner[persona_part] = tier_val
                else:
                    warn(f"--tier-pin: gate '{gate_part}' has conflicting flat/nested shape")
                    return 2
            else:
                if key in cli_tier_pins and isinstance(cli_tier_pins[key], dict):
                    warn(f"--tier-pin: persona '{key}' conflicts with prior nested pin")
                    return 2
                cli_tier_pins[key] = tier_val

    # 3c. Filter CLI pins to the active gate (Codex P2). Flat pins apply to
    #     every gate; nested pins apply only to their gate.
    cli_pins_gate_scoped: dict = {}
    for k, v in cli_tier_pins.items():
        if isinstance(v, dict):
            if k == gate:
                cli_pins_gate_scoped.update(v)
        else:
            cli_pins_gate_scoped[k] = v

    # 3d. Merge spec + CLI per spec L88 (CLI > spec; key-level). CLI wins on
    #     persona collision. SEC-01 validated against the merged result so
    #     the CLI can override a malicious spec-layer pin upward (operator
    #     escape hatch) but neither layer alone can route security below
    #     the floor.
    tier_pins: dict = dict(spec_pins_gate_scoped)
    tier_pins.update(cli_pins_gate_scoped)

    if tier_pins:
        rc = validate_tier_pins(tier_pins, registry, "opus")  # TODO(slice4): read from constitution
        if rc != 0:
            return rc

    # 4. opus_min handling.
    opus_min_arg: int | None = args.opus_min
    if opus_min_arg is not None and opus_min_arg < 0:
        warn(f"--opus-min must be non-negative, got {opus_min_arg}")
        return 2
    # Default opus_min: 1 (matches plan D6 floor; constitution layering W4).
    opus_min_effective = int(opus_min_arg) if opus_min_arg is not None else 1

    # 5. Selection — reuse legacy selection scaffolding to pick the panel,
    #    then score+assign tiers for the chosen panel. We skip the lock-file
    #    machinery for the --with-tier flow; lock-aware tier flow lands in W4.
    config_path = expand("~/.config/monsterflow/config.json")
    config = read_json(config_path) or {}
    raw_budget = config.get("agent_budget")
    on_disk = sorted(registry.keys())
    try:
        budget = int(raw_budget) if raw_budget is not None else min(6, len(on_disk))
    except (TypeError, ValueError):
        warn(f"agent_budget must be an integer, got {raw_budget!r}")
        return 2
    budget = max(1, min(8, budget))

    pins = (config.get("persona_pins") or {}).get(gate, []) or []
    codex_disabled = bool(config.get("codex_disabled", False))
    codex_avail = codex_authenticated() and not codex_disabled

    chosen: list[str] = []
    for p in pins:
        if p in on_disk and p not in chosen:
            chosen.append(p)
    for p in SEED.get(gate, []):
        if len(chosen) >= budget:
            break
        if p in on_disk and p not in chosen:
            chosen.append(p)
    for p in on_disk:
        if len(chosen) >= budget:
            break
        if p not in chosen:
            chosen.append(p)
    chosen = chosen[:budget]

    if not chosen:
        warn(f"no personas selected for gate '{gate}' (degenerate state)")
        return 3

    # 6. Score: use rankings + cold-start defaults.
    rankings_path = repo_dir / "dashboard" / "data" / "persona-rankings.jsonl"
    panel = [(slug, registry[slug]) for slug in chosen]
    scored = score_all(panel, scoring_tags, rankings_path)

    # 7. Tier-assign.
    assignments = assign_tiers(
        scored=scored,
        opus_min=opus_min_effective,
        sonnet_min=1,
        remainder_tiebreak="sonnet",
        tier_pins=tier_pins or None,
    )

    # 8. Emit stdout (`<persona>:<tier>` + bare codex).
    name_re = re.compile(r"^[a-z][a-z0-9-]*$")
    for a in assignments:
        if not name_re.match(a["persona"]):
            warn(f"invalid persona name in output: {a['persona']!r}")
            return 5
    _emit_tier_aware_stdout(assignments, codex_avail)

    # 9. Optional v2 selection.json emit.
    if args.emit_selection_json:
        dropped = [
            {
                "persona": s["persona"],
                "tier": "sonnet",
                "fit_score": s.get("fit_score", 0),
                "combined_score": s.get("combined_score", 0.0),
            }
            for s in score_all(
                [(p, registry[p]) for p in on_disk if p not in chosen],
                scoring_tags,
                rankings_path,
            )
        ]
        _emit_v2_selection_json(
            feature_dir=feature_dir,
            gate=gate,
            feature_slug=feature_slug,
            assignments=[dict(a) for a in assignments],
            dropped=dropped,
            opus_min=opus_min_effective,
            tier_pins=tier_pins,
            codex_authed=codex_avail,
            codex_disabled=codex_disabled,
            cli_override_seen=(opus_min_arg is not None) or bool(tier_pins),
        )

    if args.why:
        print(f"feature: {feature_slug}", file=sys.stderr)
        print(f"gate:    {gate}", file=sys.stderr)
        print(f"tags(recorded):   {sorted(recorded_set)}", file=sys.stderr)
        print(f"tags(recomputed): {sorted(recomputed)}", file=sys.stderr)
        print(f"tags(scoring):    {scoring_tags}", file=sys.stderr)
        print(f"selected: {', '.join(a['persona'] + ':' + a['tier'] for a in assignments)}",
              file=sys.stderr)
        print(f"opus_min: {opus_min_effective}; tier_pins: {tier_pins or '(none)'}",
              file=sys.stderr)

    return 0


def _codex_disabled_in_config(config_path: Path) -> bool:
    cfg = read_json(config_path)
    if not cfg:
        return False
    return bool(cfg.get("codex_disabled", False))


def _emit(
    chosen: list[str],
    codex: bool,
    *,
    method: str,
    config_path: str,
    feature_slug: str | None,
    gate: str,
    repo_dir: Path,
    budget_used: int,
    budget_source: str,
    pins_used: list[str],
    dropped_pins: list[str],
    dropped_over_budget: list[str],
    selection_method: str,
    emit_json: bool,
    why: bool = False,
    on_disk: list[str] | None = None,
    lock_path: str | None = None,
    codex_disabled: bool = False,
    project_dir: Path | None = None,
) -> int:
    """Emit stdout grammar + (optionally) selection.json + (optionally) --why reasoning."""
    # Validate stdout grammar before write
    import re
    name_re = re.compile(r"^[a-z][a-z0-9-]*$")
    for p in chosen:
        if not name_re.match(p):
            warn(f"invalid persona name in output: {p!r}")
            return 5

    # codex_status for selection.json
    if codex:
        codex_status = "appended"
    elif codex_disabled:
        codex_status = "disabled"
    elif os.environ.get("CODEX_BINARY_MISSING") == "1":
        codex_status = "missing_binary"
    else:
        codex_status = "not_authenticated"

    # stdout: persona names + optional codex line
    for p in chosen:
        sys.stdout.write(p + "\n")
    if codex:
        sys.stdout.write("codex-adversary\n")
    sys.stdout.flush()

    if why:
        print(f"config: {config_path}", file=sys.stderr)
        print(f"feature: {feature_slug or '(none)'}", file=sys.stderr)
        print(f"lock:    {lock_path or '(none)'}", file=sys.stderr)
        if on_disk is not None:
            print(f"on_disk({gate}): {', '.join(on_disk)} ({len(on_disk)})", file=sys.stderr)
        print(f"selected: {', '.join(chosen)}", file=sys.stderr)
        if dropped_pins:
            print(f"dropped pins (not on disk): {', '.join(dropped_pins)}", file=sys.stderr)
        if dropped_over_budget:
            print(f"dropped (over budget): {', '.join(dropped_over_budget)}", file=sys.stderr)
        print(f"codex:   {codex_status}", file=sys.stderr)
        print(f"method:  {method}", file=sys.stderr)
        print(f"budget:  {budget_used} (source={budget_source})", file=sys.stderr)

    # Optional selection.json — written by the resolver itself (per check.md MF2:
    # eliminates 3-way contract drift across consumer commands). Backlog #46:
    # use project_dir (adopter project) for docs/specs lookups; falls back to
    # repo_dir when called without project_dir for self-test compatibility.
    if emit_json and feature_slug:
        emit_dir = project_dir if project_dir is not None else repo_dir
        feature_dir = emit_dir / "docs" / "specs" / feature_slug
        gate_dir = feature_dir / gate
        if feature_dir.is_dir():
            gate_dir.mkdir(parents=True, exist_ok=True)
            selection = {
                "schema_version": 1,
                "feature": feature_slug,
                "gate": gate,
                "ran_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "selection_method": selection_method,
                "selected": chosen,
                "dropped": dropped_over_budget,
                "dropped_pins": dropped_pins,
                "codex_status": codex_status,
                "budget_used": budget_used,
                "budget_source": budget_source,
                "locked_from": lock_path,
                "resolver_exit": 0,
            }
            write_atomic(gate_dir / "selection.json",
                         json.dumps(selection, indent=2) + "\n")
        elif emit_json:
            # --emit-selection-json with a non-existent feature dir is a contract
            # violation: consumer asked for an audit row we cannot write.
            warn(f"--emit-selection-json: feature dir missing at {feature_dir}")
            return 4

    return 0


def main() -> int:
    parser = argparse.ArgumentParser(prog="resolve-personas")
    parser.add_argument("gate", nargs="?")
    parser.add_argument("--feature", help="feature slug for per-feature lock + selection.json")
    parser.add_argument("--why", action="store_true", help="print reasoning to stderr")
    parser.add_argument("--print-schema", action="store_true",
                        help="emit canonical config.json schema and exit")
    parser.add_argument("--print-seed", action="store_true",
                        help="emit the per-gate seed list (newline-separated) and exit; "
                             "used by the recovery prompt's 'continue with seed' option")
    parser.add_argument("--unlock-budget", action="store_true",
                        help="delete the .budget-lock.json for the given --feature")
    parser.add_argument("--emit-selection-json", action="store_true",
                        help="write docs/specs/<feature>/<gate>/selection.json (requires --feature)")
    # --- Tier-mix flow (Slice 3 Wave 3b; opt-in) ---
    parser.add_argument("--with-tier", action="store_true",
                        help="enable tier-mix flow + '<persona>:<tier>' stdout grammar; "
                             "default OFF preserves legacy bare-name output for v1 callers")
    parser.add_argument("--opus-min", type=int, default=None,
                        help="override opus_min (int, >=0). Honored only with --with-tier.")
    parser.add_argument("--tier-pin", action="append", default=None, metavar="SPEC",
                        help="tier pin: '<persona>=<tier>' or '<gate>.<persona>=<tier>'. "
                             "Repeatable. SEC-01 validated at parse time. "
                             "Honored only with --with-tier.")
    args = parser.parse_args()

    if args.print_schema:
        emit_schema()
        return 0

    if args.print_seed:
        if not args.gate or args.gate not in VALID_GATES:
            warn("--print-seed requires gate (one of: spec-review, plan, check)")
            return 4
        for name in SEED[args.gate]:
            print(name)
        return 0

    if not args.gate:
        warn("missing gate argument (one of: spec-review, plan, check)")
        return 5

    repo_dir_env = os.environ.get("MONSTERFLOW_REPO_DIR")
    if repo_dir_env:
        repo_dir = Path(repo_dir_env).resolve()
    else:
        # Resolve from this script's location: scripts/_resolve_personas.py → repo root
        repo_dir = Path(__file__).resolve().parent.parent

    # Backlog #46 fix (2026-05-09): split engine dir (personas, dashboard,
    # configs — always MonsterFlow) from adopter project dir (docs/specs/
    # — RedRabbit / etc when MonsterFlow drives an autorun in another repo).
    # `PROJECT_DIR` is exported by autorun's run.sh; when absent we keep the
    # legacy behavior (repo_dir for both) so MonsterFlow's own self-tests
    # under MonsterFlow/docs/specs/ still resolve.
    project_dir_env = os.environ.get("PROJECT_DIR")
    project_dir: Path | None = None
    if project_dir_env:
        project_dir = Path(project_dir_env).resolve()

    if args.emit_selection_json and not args.feature:
        warn("--emit-selection-json requires --feature")
        return 4

    # --with-tier opt-in: dispatch to the tier-mix flow. Otherwise legacy run().
    if args.with_tier:
        return run_with_tier(args, repo_dir, project_dir or repo_dir)

    # Legacy path: --opus-min / --tier-pin without --with-tier is a no-op + warn.
    if args.opus_min is not None or args.tier_pin:
        warn("[tier-policy] --opus-min/--tier-pin requires --with-tier; ignored")

    return run(args, repo_dir, project_dir)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
    except Exception as e:  # noqa: BLE001
        warn(f"internal error: {type(e).__name__}: {e}")
        sys.exit(5)
