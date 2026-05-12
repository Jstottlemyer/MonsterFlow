#!/usr/bin/env python3
"""
Walk ~/Projects/*/docs/specs/<feature>/{spec-review,plan,check}/ and emit a
script-tag JSON bundle for the Judge tab of the dashboard.

Output shape:

  window.__JUDGE_DATA = {
    "generated_at": "2026-05-02T...",
    "projects": {
      "<project-slug>": {
        "path": "/Users/.../Projects/<Project>",
        "features": {
          "<feature>": {
            "stages": {
              "spec-review": { ... },
              "plan":        { ... },
              "check":       { ... }
            }
          }
        }
      }
    }
  }

Per-stage object:
  {
    "timestamp":         "<from run.json or mtime>",
    "run_id":            "<run.json>",
    "prompt_version":    "findings-emit@1.0",
    "artifact_hash":     "...",
    "verdict":           "GO" | "GO WITH FIXES" | "NO-GO" | "PASS" | ... | null,
    "raw_finding_count": 17,         # lines across raw/*.md (rough proxy)
    "raw_files":         5,
    "findings":          [ {finding_id, title, severity, personas, ...}, ... ],
    "participation":     [ {persona, findings_emitted, status}, ... ],
    "survival":          [ {finding_id, survived, ...}, ... ] | [],
    "disagreements":     <int>,      # parsed from synthesized <stage>.md
    "personas_listed":   ["completeness", "risk", ...],
    "synth_path":        "<absolute path to docs/specs/<feature>/<stage>.md>",
    "stage_dir":         "<absolute path to docs/specs/<feature>/<stage>/>"
  }

Read-only — never writes into the source projects, only into the bundle file.
Skips test fixtures (paths containing /tests/fixtures/).
"""
from __future__ import annotations
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

STAGES = ("spec-review", "plan", "check")
SKIP_PATH_FRAGMENTS = ("/tests/fixtures/", "/node_modules/", "/.git/")
VERDICT_RE = re.compile(
    r"\b(NO[- ]GO|GO WITH FIXES|GO|PASS WITH NOTES|PASS|FAIL)\b",
    re.IGNORECASE,
)
DISAGREEMENT_HEADER_RE = re.compile(
    r"^#+\s*Agent Disagreements Resolved\s*$", re.IGNORECASE | re.MULTILINE
)
NEXT_HEADER_RE = re.compile(r"^#+\s+\S", re.MULTILINE)


def project_slug(project_dir: Path) -> str:
    return project_dir.name.lower()


def read_jsonl(path: Path) -> list[dict]:
    if not path.is_file():
        return []
    out = []
    try:
        with path.open() as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    out.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
    except OSError:
        pass
    return out


def read_json(path: Path) -> dict | None:
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return None


def parse_synth_md(path: Path) -> tuple[str | None, int]:
    """Return (verdict, disagreement_count). Both best-effort."""
    if not path.is_file():
        return (None, 0)
    try:
        text = path.read_text()
    except OSError:
        return (None, 0)

    verdict = None
    # Search the last 60 lines first — verdict typically lives near the bottom.
    tail = "\n".join(text.splitlines()[-80:])
    m = VERDICT_RE.search(tail)
    if not m:
        m = VERDICT_RE.search(text)
    if m:
        verdict = m.group(1).upper().replace(" ", " ")

    # Disagreements: count bullet lines inside the "Agent Disagreements
    # Resolved" section. The synthesis persona writes a "- None — no
    # contradictions surfaced." sentinel when there were zero merges; that
    # sentinel must NOT be counted as a disagreement, otherwise the metric
    # can't distinguish "Judge fired and merged 1 thing" from "Judge fired
    # and had nothing to merge."
    disagreements = 0
    section_match = DISAGREEMENT_HEADER_RE.search(text)
    if section_match:
        start = section_match.end()
        next_header = NEXT_HEADER_RE.search(text, start)
        end = next_header.start() if next_header else len(text)
        section = text[start:end]
        for line in section.splitlines():
            stripped = line.strip()
            if not stripped.startswith(("- ", "* ", "1.", "2.", "3.")):
                continue
            content = re.sub(r"^[-*]\s+|^\d+\.\s+", "", stripped).lstrip()
            # Sentinel forms: "None", "None.", "None — ...", "_None_", "(none)".
            if re.match(r"^[_*(]?none\b", content, re.IGNORECASE):
                continue
            disagreements += 1
    return (verdict, disagreements)


def count_raw(stage_dir: Path) -> tuple[int, int]:
    """(rough finding count across raw/*.md, file count)."""
    raw_dir = stage_dir / "raw"
    if not raw_dir.is_dir():
        return (0, 0)
    files = sorted(raw_dir.glob("*.md"))
    if not files:
        return (0, 0)
    bullets = 0
    for p in files:
        try:
            for line in p.read_text().splitlines():
                stripped = line.strip()
                if stripped.startswith(("- ", "* ")) and len(stripped) > 4:
                    bullets += 1
        except OSError:
            continue
    return (bullets, len(files))


def extract_tier_mix(stage_dir: Path):
    """Read gate-scoped selection.json and return tier_mix dict, or the
    string sentinel "N/A" when the file is absent / unreadable / malformed
    / legacy-schema / missing required fields.

    Plan D8 (dynamic-roster-per-gate task 16): defensive read — legacy
    selection.json files from account-type-agent-scaling (v1 shape, no
    tier_policy_applied) MUST load without error. Render N/A for those.
    """
    sel = read_json(stage_dir / "selection.json")
    if not isinstance(sel, dict):
        return "N/A"
    if sel.get("schema_version") != 2:
        return "N/A"
    tier = sel.get("tier_policy_applied")
    if not isinstance(tier, dict):
        return "N/A"
    opus = tier.get("opus_count_actual")
    sonnet = tier.get("sonnet_count_actual")
    if not isinstance(opus, int) or not isinstance(sonnet, int):
        return "N/A"
    if opus < 0 or sonnet < 0:
        return "N/A"
    codex_block = sel.get("codex")
    codex_active = (
        isinstance(codex_block, dict)
        and codex_block.get("policy") == "additive"
    )
    return {"opus": opus, "sonnet": sonnet, "codex": codex_active}


def stage_blob(feature_dir: Path, stage: str) -> dict | None:
    stage_dir = feature_dir / stage
    if not stage_dir.is_dir():
        return None
    findings = read_jsonl(stage_dir / "findings.jsonl")
    participation = read_jsonl(stage_dir / "participation.jsonl")
    survival = read_jsonl(stage_dir / "survival.jsonl")
    run = read_json(stage_dir / "run.json") or {}
    tier_mix = extract_tier_mix(stage_dir)
    synth_md = feature_dir / f"{stage}.md"
    verdict, disagreements = parse_synth_md(synth_md)
    raw_count, raw_files = count_raw(stage_dir)

    timestamp = run.get("timestamp")
    if not timestamp:
        try:
            mtime = stage_dir.stat().st_mtime
            timestamp = datetime.fromtimestamp(mtime, tz=timezone.utc).isoformat()
        except OSError:
            timestamp = None

    if not (findings or participation or run or synth_md.is_file()):
        return None

    # Trim findings to the fields the dashboard needs (keeps bundle small).
    trimmed = []
    for f in findings:
        trimmed.append(
            {
                "finding_id": f.get("finding_id"),
                "title": f.get("title"),
                "severity": f.get("severity"),
                "personas": f.get("personas") or [],
                "unique_to_persona": f.get("unique_to_persona"),
                "mode": f.get("mode"),
            }
        )

    return {
        "timestamp": timestamp,
        "run_id": run.get("run_id"),
        "prompt_version": run.get("prompt_version"),
        "artifact_hash": run.get("artifact_hash"),
        "verdict": verdict,
        "raw_finding_count": raw_count,
        "raw_files": raw_files,
        "findings": trimmed,
        "participation": participation,
        "survival": survival,
        "disagreements": disagreements,
        "personas_listed": run.get("personas") or sorted(
            {p for f in findings for p in (f.get("personas") or [])}
        ),
        "synth_path": str(synth_md) if synth_md.is_file() else None,
        "stage_dir": str(stage_dir),
        "tier_mix": tier_mix,
    }


def walk_projects(root: Path) -> dict:
    projects: dict[str, dict] = {}
    if not root.is_dir():
        return projects
    for project_dir in sorted(root.iterdir()):
        if not project_dir.is_dir() or project_dir.name.startswith("."):
            continue
        specs_dir = project_dir / "docs" / "specs"
        if not specs_dir.is_dir():
            continue
        slug = project_slug(project_dir)
        features: dict[str, dict] = {}
        for feature_dir in sorted(specs_dir.iterdir()):
            if not feature_dir.is_dir():
                continue
            full_path = str(feature_dir)
            if any(frag in full_path for frag in SKIP_PATH_FRAGMENTS):
                continue
            stages: dict[str, dict] = {}
            for stage in STAGES:
                blob = stage_blob(feature_dir, stage)
                if blob is not None:
                    stages[stage] = blob
            if stages:
                features[feature_dir.name] = {"stages": stages}
        if features:
            projects[slug] = {"path": str(project_dir), "features": features}
    return projects


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: judge-dashboard-bundle.py <projects-root> <out-file>", file=sys.stderr)
        return 2
    projects_root = Path(sys.argv[1]).expanduser()
    out = Path(sys.argv[2])
    bundle = {
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "projects": walk_projects(projects_root),
    }
    payload = json.dumps(bundle, indent=2)
    out.write_text(
        "// Auto-generated by scripts/judge-dashboard-bundle.sh — do not edit.\n"
        f"window.__JUDGE_DATA = {payload};\n"
    )
    n_projects = len(bundle["projects"])
    n_features = sum(len(p["features"]) for p in bundle["projects"].values())
    n_stages = sum(
        len(f["stages"])
        for p in bundle["projects"].values()
        for f in p["features"].values()
    )
    print(f"bundled judge: {n_projects} projects, {n_features} features, {n_stages} stages → {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
