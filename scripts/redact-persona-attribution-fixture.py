#!/usr/bin/env python3
"""Redact a raw ~/.claude/projects/<proj>/<uuid>.jsonl excerpt down to the
persona-attribution allowlist.

Single-purpose helper bound to schemas/persona-attribution.allowlist.json.
NOT a general-purpose redaction tool. Per spec docs/specs/token-economics/spec.md
v4.2 §Privacy and security design O1.

Behavior:
  * Reads --input <path> (line-delimited JSON; one row per line; blank lines skipped).
  * For each row, keeps ONLY the fields enumerated in the persona-attribution
    allowlist; everything else is dropped (including any nested keys not on the
    inner allowlists for `usage`).
  * Truncates `timestamp` to the hour boundary (YYYY-MM-DDTHH:00:00Z) per
    security O3.
  * `persona_path` MUST already match ^personas/(spec-review|plan|check)/
    [a-z0-9-]+\\.md$ — rows whose persona_path doesn't match are dropped (not
    rewritten — refusing to invent a "safe" path on the adopter's behalf).
  * Required fields missing from the input row → row dropped (with stderr
    note that includes the row index, never the row content).
  * Idempotent: re-running on already-redacted output produces byte-identical
    output (sort_keys=True, hour-truncated timestamps stay hour-truncated,
    no extra fields to strip).
  * Stdlib only (M2: no PyPI deps in this repo).

Output validates against schemas/persona-attribution.allowlist.json.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

# These mirror schemas/persona-attribution.allowlist.json. If you change one,
# change the other and re-run tests/test-allowlist.sh.
ALLOWED_TOP_LEVEL: tuple[str, ...] = (
    "type",
    "agentId",
    "tool_use_id",
    "parent_session_uuid",
    "model",
    "usage",
    "duration_ms",
    "tool_uses",
    "total_tokens",
    "persona_path",
    "gate",
    "timestamp",
)

ALLOWED_USAGE_KEYS: tuple[str, ...] = (
    "input_tokens",
    "output_tokens",
    "cache_read_input_tokens",
    "cache_creation_input_tokens",
)

REQUIRED_TOP_LEVEL: tuple[str, ...] = (
    "type",
    "agentId",
    "tool_use_id",
    "parent_session_uuid",
    "model",
    "usage",
    "duration_ms",
    "tool_uses",
    "total_tokens",
    "persona_path",
    "gate",
    "timestamp",
)

ALLOWED_TYPE_VALUES: frozenset[str] = frozenset({"agent_dispatch"})
ALLOWED_GATE_VALUES: frozenset[str] = frozenset({"spec-review", "design", "check"})

# Persona DIR is 'review' (for the spec-review gate); gate name is 'spec-review'.
# Coordinator-fixed at /build Stage 1A handoff; redactor brought into sync at /preship per Codex P2.
PERSONA_PATH_RE = re.compile(r"^personas/(review|design|check)/[a-z0-9][a-z0-9-]*\.md$")
AGENT_ID_RE = re.compile(r"^[0-9a-f]{17}$")
UUID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
)
MODEL_RE = re.compile(r"^[a-z][a-z0-9-]*[a-z0-9]$")
TIMESTAMP_PARSE_RE = re.compile(
    r"^(?P<date>[0-9]{4}-[0-9]{2}-[0-9]{2})T(?P<hour>[0-9]{2}):"
    r"[0-9]{2}:[0-9]{2}(?:\.[0-9]+)?(?:Z|[+\-][0-9]{2}:?[0-9]{2})?$"
)


def truncate_to_hour(ts: str) -> str | None:
    """Return the ISO-8601 UTC string truncated to the hour boundary, or None
    if the input doesn't parse. We only accept ISO-8601 strings that already
    name a date and an hour; anything else is dropped (we don't guess timezone).
    """
    m = TIMESTAMP_PARSE_RE.match(ts)
    if not m:
        return None
    return f"{m['date']}T{m['hour']}:00:00Z"


def redact_usage(raw: Any) -> dict[str, int] | None:
    """Keep only allowed integer keys from `usage`. Returns None if `usage` is
    not a dict or has no allowed keys with int values.
    """
    if not isinstance(raw, dict):
        return None
    out: dict[str, int] = {}
    for k in ALLOWED_USAGE_KEYS:
        if k in raw and isinstance(raw[k], int) and raw[k] >= 0:
            out[k] = raw[k]
    # required: input_tokens, output_tokens
    if "input_tokens" not in out or "output_tokens" not in out:
        return None
    return out


def redact_row(row: Any, idx: int) -> dict[str, Any] | None:
    """Project a raw row down to the allowlist. Return None if the row is
    structurally unfit (missing required fields, bad enum, bad pattern).
    Stderr notes are emitted with the row index only — never row content.
    """
    if not isinstance(row, dict):
        print(
            f"[redact] row {idx}: not a JSON object; dropped",
            file=sys.stderr,
        )
        return None

    out: dict[str, Any] = {}

    # type (enum)
    t = row.get("type")
    if t not in ALLOWED_TYPE_VALUES:
        print(f"[redact] row {idx}: type missing/invalid; dropped", file=sys.stderr)
        return None
    out["type"] = t

    # agentId
    aid = row.get("agentId")
    if not isinstance(aid, str) or not AGENT_ID_RE.match(aid):
        print(f"[redact] row {idx}: agentId missing/invalid; dropped", file=sys.stderr)
        return None
    out["agentId"] = aid

    # tool_use_id
    tuid = row.get("tool_use_id")
    if not isinstance(tuid, str) or not tuid:
        print(
            f"[redact] row {idx}: tool_use_id missing/invalid; dropped",
            file=sys.stderr,
        )
        return None
    out["tool_use_id"] = tuid

    # parent_session_uuid
    psu = row.get("parent_session_uuid")
    if not isinstance(psu, str) or not UUID_RE.match(psu):
        print(
            f"[redact] row {idx}: parent_session_uuid missing/invalid; dropped",
            file=sys.stderr,
        )
        return None
    out["parent_session_uuid"] = psu

    # model
    model = row.get("model")
    if not isinstance(model, str) or not MODEL_RE.match(model):
        print(f"[redact] row {idx}: model missing/invalid; dropped", file=sys.stderr)
        return None
    out["model"] = model

    # usage
    usage = redact_usage(row.get("usage"))
    if usage is None:
        print(
            f"[redact] row {idx}: usage missing/invalid; dropped",
            file=sys.stderr,
        )
        return None
    out["usage"] = usage

    # duration_ms
    dur = row.get("duration_ms")
    if not isinstance(dur, int) or dur < 0:
        print(
            f"[redact] row {idx}: duration_ms missing/invalid; dropped",
            file=sys.stderr,
        )
        return None
    out["duration_ms"] = dur

    # tool_uses
    tu = row.get("tool_uses")
    if not isinstance(tu, int) or tu < 0:
        print(
            f"[redact] row {idx}: tool_uses missing/invalid; dropped",
            file=sys.stderr,
        )
        return None
    out["tool_uses"] = tu

    # total_tokens
    tt = row.get("total_tokens")
    if not isinstance(tt, int) or tt < 0:
        print(
            f"[redact] row {idx}: total_tokens missing/invalid; dropped",
            file=sys.stderr,
        )
        return None
    out["total_tokens"] = tt

    # persona_path — must already match the public roster path; no rewriting.
    pp = row.get("persona_path")
    if not isinstance(pp, str) or not PERSONA_PATH_RE.match(pp):
        print(
            f"[redact] row {idx}: persona_path missing/not under personas/<gate>/; dropped",
            file=sys.stderr,
        )
        return None
    out["persona_path"] = pp

    # gate (enum)
    gate = row.get("gate")
    if gate not in ALLOWED_GATE_VALUES:
        print(f"[redact] row {idx}: gate missing/invalid; dropped", file=sys.stderr)
        return None
    out["gate"] = gate

    # timestamp — truncate to hour
    ts = row.get("timestamp")
    if not isinstance(ts, str):
        print(
            f"[redact] row {idx}: timestamp missing/invalid; dropped",
            file=sys.stderr,
        )
        return None
    truncated = truncate_to_hour(ts)
    if truncated is None:
        print(
            f"[redact] row {idx}: timestamp not parseable as ISO-8601; dropped",
            file=sys.stderr,
        )
        return None
    out["timestamp"] = truncated

    # Sanity: required fields all present (defense-in-depth; should be
    # guaranteed by checks above, but assert before emit).
    missing = [k for k in REQUIRED_TOP_LEVEL if k not in out]
    if missing:
        print(
            f"[redact] row {idx}: post-projection missing {missing}; dropped",
            file=sys.stderr,
        )
        return None

    return out


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="redact-persona-attribution-fixture",
        description=(
            "Redact a raw ~/.claude/projects/<proj>/<uuid>.jsonl excerpt down to "
            "the fields enumerated in schemas/persona-attribution.allowlist.json. "
            "Single-purpose; not a general-purpose redaction tool. "
            "Truncates timestamps to the hour boundary. Drops any row that fails "
            "the allowlist contract. Idempotent. Stdlib only."
        ),
        epilog=(
            "After running, validate the output with `bash tests/test-allowlist.sh` "
            "before committing the fixture. (M2 invariant: this repo is stdlib-only "
            "— do NOT install jsonschema; the in-tree validator at "
            "scripts/_allowlist_validator.py is the only supported check.)"
        ),
    )
    parser.add_argument(
        "--input",
        required=True,
        type=Path,
        help="Path to the raw JSONL excerpt (one JSON object per line).",
    )
    parser.add_argument(
        "--output",
        required=True,
        type=Path,
        help="Path to write the redacted JSONL. Overwritten if it exists.",
    )
    args = parser.parse_args()

    in_path: Path = args.input
    out_path: Path = args.output

    if not in_path.is_file():
        print(f"[redact] --input not found: {in_path}", file=sys.stderr)
        return 2

    kept = 0
    dropped = 0
    redacted_rows: list[dict[str, Any]] = []

    with in_path.open("r", encoding="utf-8") as fh:
        for idx, line in enumerate(fh, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                print(
                    f"[redact] row {idx}: not valid JSON; dropped",
                    file=sys.stderr,
                )
                dropped += 1
                continue
            redacted = redact_row(row, idx)
            if redacted is None:
                dropped += 1
                continue
            redacted_rows.append(redacted)
            kept += 1

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8") as fh:
        for r in redacted_rows:
            fh.write(json.dumps(r, sort_keys=True, separators=(",", ":")))
            fh.write("\n")

    print(
        f"[redact] kept {kept} dropped {dropped} -> {out_path}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
