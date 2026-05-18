#!/usr/bin/env python3
"""
_goal_autoship_render.py — Autoship suitability render helper.

Two subcommands:
  render    Emit stdout block + append JSONL render row (unless --no-log).
  log-event Append JSONL event row only (halt or outcome), no stdout.

Exit codes: 0 success, 1 missing/malformed spec.md, 2 invalid argument/enum.

Frontmatter parsing: NARROW regex-based (stdlib only, NO yaml import).
Handles `tags: [a, b]` inline-list form and `gate_mode: strict|permissive`
string form only. Multi-line YAML block scalars, anchors, and other YAML
features are NOT supported. If tags are in an unsupported form, defaults to
[] with a stderr warning. Document narrow scope per D9 + Codex finding #9.

Schema bump policy (D8): schema_version bumps to 2 ONLY on breaking
field-type change or required-field removal. Additive changes (new optional
fields, new enum values) do NOT bump the version.

AUTOSHIP_EVENTS_PATH env var: overrides the default JSONL path
(dashboard/data/autorun-suitability-events.jsonl) for test isolation (D15).
"""

import argparse
import fcntl
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

GATE_ENUM = [
    "spec-exit",
    "spec-review",
    "blueprint",
    "check-go",
    "check-go-with-fixes",
    "build",
    "merge",
]

SURFACE_ENUM = [
    "spec-exit",
    "spec-review-option",
    "check-go-option",
    "check-go-with-fixes-option",
]

RENDER_BEARING_GATES = {"spec-exit", "spec-review", "check-go", "check-go-with-fixes"}

SCHEMA_VERSION = 1

OUTCOME_REASONS = {"shipped", "failed", "cancelled"}

SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,63}$")

# ---------------------------------------------------------------------------
# JSONL path resolution (D15)
# ---------------------------------------------------------------------------

def _events_path() -> Path:
    override = os.environ.get("AUTOSHIP_EVENTS_PATH", "")
    if override:
        return Path(override)
    return Path("dashboard/data/autorun-suitability-events.jsonl")


# ---------------------------------------------------------------------------
# Frontmatter parsing (narrow regex-based, D9 + Codex #9)
# ---------------------------------------------------------------------------

def _parse_frontmatter(text: str) -> dict:
    """
    Extract `tags` and `gate_mode` from YAML frontmatter delimited by `---`.
    Handles only inline-list tags (`tags: [a, b]`) and string gate_mode.
    Returns dict with keys 'tags' (list) and 'gate_mode' (str, default 'permissive').
    """
    result = {"tags": [], "gate_mode": "permissive"}

    # Locate frontmatter block
    fm_match = re.match(r"^---\s*\n(.*?)\n---\s*\n", text, re.DOTALL)
    if not fm_match:
        return result
    fm = fm_match.group(1)

    # gate_mode
    gm_match = re.search(r"^gate_mode:\s*(\S+)", fm, re.MULTILINE)
    if gm_match:
        result["gate_mode"] = gm_match.group(1).strip().strip('"\'')

    # tags — handle inline list form: tags: [a, b, c] or tags: []
    tags_line_match = re.search(r"^tags:\s*(.*)", fm, re.MULTILINE)
    if tags_line_match:
        raw = tags_line_match.group(1).strip()
        if raw.startswith("[") and raw.endswith("]"):
            # Inline list: parse comma-separated items stripped of whitespace/quotes
            inner = raw[1:-1].strip()
            if inner:
                items = [t.strip().strip('"\'') for t in inner.split(",") if t.strip()]
                result["tags"] = items
            else:
                result["tags"] = []
        elif raw in ("null", "~", ""):
            result["tags"] = []
        elif raw and not raw.startswith("["):
            # String scalar — normalize to single-element list with warning
            print(
                f"[autoship] warning: tags is a scalar string '{raw}' — normalizing to [{raw}]",
                file=sys.stderr,
            )
            result["tags"] = [raw.strip().strip('"\'')]
        else:
            print(
                f"[autoship] warning: unsupported tags format '{raw}' — defaulting to []",
                file=sys.stderr,
            )
            result["tags"] = []

    return result


# ---------------------------------------------------------------------------
# Spec loading and slug derivation
# ---------------------------------------------------------------------------

def load_spec(spec_path_str: str) -> tuple:
    """
    Load spec.md, derive slug, parse frontmatter, count ACs.
    Returns (slug, tags, gate_mode, ac_count, text) or exits 1 on error.
    """
    spec_path = Path(spec_path_str)
    if not spec_path.exists():
        print(f"[autoship] error: spec.md not found: {spec_path}", file=sys.stderr)
        sys.exit(1)

    try:
        text = spec_path.read_text(encoding="utf-8")
    except Exception as exc:
        print(f"[autoship] error: cannot read spec.md: {exc}", file=sys.stderr)
        sys.exit(1)

    # Slug = parent directory name of spec.md
    slug = spec_path.resolve().parent.name
    if not SLUG_RE.match(slug):
        print(
            f"[autoship] error: slug '{slug}' does not match ^[a-z0-9][a-z0-9-]{{0,63}}$",
            file=sys.stderr,
        )
        sys.exit(1)

    fm = _parse_frontmatter(text)
    tags = fm["tags"]
    gate_mode = fm["gate_mode"]
    ac_count = _count_acs(text)

    return slug, tags, gate_mode, ac_count, text


# ---------------------------------------------------------------------------
# AC count parsing (spec V3 §Data & State AC count parsing rule)
# ---------------------------------------------------------------------------

def _count_acs(text: str) -> "int | None":
    """
    Count items under '## Acceptance Criteria' heading.
    Regex: ^(?:[-*]\\s+|\\d+\\.\\s+) — column 0 ONLY, no leading whitespace.
    Stops at next ## heading. Returns None if section missing or 0 matches.
    Checkbox items (- [ ] and - [x]) count (leading '- ' matches).
    """
    # Find the ## Acceptance Criteria section
    section_match = re.search(
        r"^## Acceptance Criteria\s*\n(.*?)(?=^##|\Z)",
        text,
        re.MULTILINE | re.DOTALL,
    )
    if not section_match:
        return None

    section = section_match.group(1)
    # Count lines at column 0 that start with bullet/numbered markers
    bullet_re = re.compile(r"^(?:[-*]\s+|\d+\.\s+)", re.MULTILINE)
    matches = bullet_re.findall(section)
    return len(matches) if matches else None


# ---------------------------------------------------------------------------
# Suitability scoring (spec V3 §Suitability scoring rule)
# ---------------------------------------------------------------------------

def score_suitability(tags: list, gate_mode: str) -> str:
    """
    Returns 'HIGH', 'MEDIUM', or 'LOW'.
    LOW if gate_mode == 'strict'.
    MEDIUM if both 'security' and 'migration' in tags.
    HIGH otherwise.
    """
    if gate_mode == "strict":
        return "LOW"
    if "security" in tags and "migration" in tags:
        return "MEDIUM"
    return "HIGH"


# ---------------------------------------------------------------------------
# JSONL atomic append (D7 + D15)
# ---------------------------------------------------------------------------

def append_event(row: dict) -> None:
    """Atomic append with fcntl.flock advisory lock (D7). Best-effort; logs to stderr on failure."""
    path = _events_path()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        line = json.dumps(row, separators=(",", ":")) + "\n"
        with open(path, "a", encoding="utf-8") as f:
            fcntl.flock(f, fcntl.LOCK_EX)
            try:
                f.write(line)
                f.flush()
                os.fsync(f.fileno())
            finally:
                fcntl.flock(f, fcntl.LOCK_UN)
    except Exception as exc:
        print(f"[autoship] warning: JSONL write failed: {exc}", file=sys.stderr)


def _now_ts() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# ---------------------------------------------------------------------------
# Render subcommand
# ---------------------------------------------------------------------------

def cmd_render(args: argparse.Namespace) -> None:
    """
    Emit render block to stdout. Append JSONL render row unless --no-log.
    --surface on a non-render-bearing gate exits 2.
    """
    gate = args.gate
    surface = args.surface

    # Validate surface vs gate
    if surface is not None and gate not in RENDER_BEARING_GATES:
        print(
            f"[autoship] error: --surface is not valid for gate '{gate}' "
            f"(only for: {sorted(RENDER_BEARING_GATES)})",
            file=sys.stderr,
        )
        sys.exit(2)

    slug, tags, gate_mode, ac_count, _text = load_spec(args.spec_path)
    suitability = score_suitability(tags, gate_mode)

    # Determine effective surface: default to gate name when in render-bearing gates
    effective_surface = surface if surface is not None else (gate if gate in RENDER_BEARING_GATES else None)

    # Build stdout output
    _emit_render_block(slug, suitability, ac_count, gate_mode, tags, effective_surface)

    # Append JSONL render event unless --no-log
    if not args.no_log:
        row = {
            "schema_version": SCHEMA_VERSION,
            "ts": _now_ts(),
            "event_type": "render",
            "feature": slug,
            "gate": gate,
            "predicted_suitability": suitability,
            "tags": tags,
            "ac_count": ac_count,
            "gate_mode": gate_mode,
        }
        append_event(row)


def _emit_render_block(
    slug: str,
    suitability: str,
    ac_count: "int | None",
    gate_mode: str,
    tags: list,
    surface: "str | None",
) -> None:
    """
    Emit appropriate render block to stdout based on surface.
    Surface 'spec-exit' → full block.
    Surface '*-option' → single option-c bullet (empty stdout if LOW).
    No surface → full block (default when gate is render-bearing).
    """
    ac_display = str(ac_count) if ac_count is not None else "?"

    if surface in ("spec-review-option", "check-go-option", "check-go-with-fixes-option"):
        # Option-line mode: single bullet; empty stdout on LOW
        if suitability == "LOW":
            # Empty stdout — caller omits option-c bullet
            return
        print(
            f"- **c)** Ship autonomously — paste this exact line:\n"
            f"       /goal docs/specs/{slug}/spec.md is shipped via merged PR"
            f" with verifier reporting {ac_display}/{ac_display} ACs PASS\n"
            f"       (suitability: {suitability})"
        )
    else:
        # Full block mode (spec-exit or default)
        print(f"=== Spec Written: {slug} ({ac_display} ACs) ===")
        print(
            f"Autorun suitability: {suitability}"
            + (
                " (security+migration combo)"
                if suitability == "MEDIUM"
                else (" (gate_mode: strict)" if suitability == "LOW" else "")
            )
        )
        print()
        if suitability != "LOW":
            print("Ship autonomously? Copy + paste this exact line:")
            print(
                f"  /goal docs/specs/{slug}/spec.md is shipped via merged PR"
                f" with verifier reporting {ac_display}/{ac_display} ACs PASS"
            )
            print()
        print(f"Or proceed manually: /spec-review {slug}")


# ---------------------------------------------------------------------------
# log-event subcommand
# ---------------------------------------------------------------------------

def cmd_log_event(args: argparse.Namespace) -> None:
    """
    Append one event row (halt or outcome) to JSONL. No stdout output.
    """
    event_type = args.event_type
    reason = args.reason

    # Validate outcome reason enum
    if event_type == "outcome" and reason not in OUTCOME_REASONS:
        print(
            f"[autoship] error: --reason '{reason}' invalid for outcome event; "
            f"must be one of {sorted(OUTCOME_REASONS)}",
            file=sys.stderr,
        )
        sys.exit(2)

    slug, _tags, _gate_mode, _ac_count, _text = load_spec(args.spec_path)

    row: dict = {
        "schema_version": SCHEMA_VERSION,
        "ts": _now_ts(),
        "event_type": event_type,
        "feature": slug,
        "gate": args.gate,
        "reason": reason,
    }

    if event_type == "halt":
        if args.stage_at_halt is not None:
            row["stage_at_halt"] = args.stage_at_halt
    elif event_type == "outcome":
        if args.pr is not None:
            row["pr"] = args.pr

    append_event(row)
    # No stdout output for log-event


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="_goal_autoship_render.py",
        description="Autoship suitability render helper.",
    )
    sub = parser.add_subparsers(dest="subcommand", required=True)

    # render subcommand
    render_p = sub.add_parser("render", help="Emit render block + append JSONL render row.")
    render_p.add_argument("--spec-path", required=True, help="Path to spec.md")
    render_p.add_argument("--gate", required=True, choices=GATE_ENUM, help="Pipeline gate")
    render_p.add_argument(
        "--surface",
        choices=SURFACE_ENUM,
        default=None,
        help="Render surface (only for render-bearing gates)",
    )
    render_p.add_argument(
        "--no-log",
        action="store_true",
        help="Suppress JSONL row write",
    )

    # log-event subcommand
    log_p = sub.add_parser("log-event", help="Append halt or outcome event row to JSONL.")
    log_p.add_argument("--spec-path", required=True, help="Path to spec.md")
    log_p.add_argument("--gate", required=True, choices=GATE_ENUM, help="Pipeline gate")
    log_p.add_argument(
        "--event-type",
        required=True,
        choices=["halt", "outcome"],
        help="Event type",
    )
    log_p.add_argument("--reason", required=True, help="Reason string (halt: free-form; outcome: shipped|failed|cancelled)")
    log_p.add_argument(
        "--stage-at-halt",
        choices=GATE_ENUM,
        default=None,
        help="Stage where halt occurred (halt events only)",
    )
    log_p.add_argument(
        "--pr",
        type=int,
        default=None,
        help="PR number (outcome events only)",
    )

    return parser


def main() -> None:
    parser = build_parser()
    # argparse exits 2 on unrecognized/missing args — correct per spec exit-code contract
    args = parser.parse_args()

    if args.subcommand == "render":
        cmd_render(args)
    elif args.subcommand == "log-event":
        cmd_log_event(args)
    else:
        parser.print_help()
        sys.exit(2)


if __name__ == "__main__":
    main()
