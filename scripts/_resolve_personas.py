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
  lock-write, 5=internal error.

Bash 3.2 portability is irrelevant here (Python). The wrapper handles bash
edge cases (PATH stub for codex, tilde expansion).
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path
from typing import Any

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
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
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

    return run(args, repo_dir, project_dir)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
    except Exception as e:  # noqa: BLE001
        warn(f"internal error: {type(e).__name__}: {e}")
        sys.exit(5)
