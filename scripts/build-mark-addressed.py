#!/usr/bin/env python3
"""build-mark-addressed.py — /build wave-final follow-up state-transition writer.

Spec:  docs/specs/pipeline-gate-permissiveness/spec.md
       (Lifecycle section + A14d regression transition)
Plan:  docs/specs/pipeline-gate-permissiveness/plan.md
       (Wave 3 Task 3.8b — added inline by /check completeness MF2 fix)
Schema: schemas/followups.schema.json (version 1)

Why this exists
---------------
After a /build wave commits a fix that resolves one or more `state: open`
follow-up findings, this helper records that fact back into the authoritative
`followups.jsonl` for the spec. It transitions matching rows from
`state: open` → `state: addressed`, sets `addressed_by` to the wave's commit
SHA (or PR ref), and stamps `updated_at` to the current ISO-8601 UTC second.

Idempotent on already-addressed rows (preserves the FIRST writer's
`addressed_by`, refreshes `updated_at`). Refuses to mutate rows in
`state: superseded` — those have left the active set by construction.

CLI
---
    build-mark-addressed.py --feature <slug> \\
                            --finding-ids <id1,id2,...> \\
                            --commit-sha <SHA-or-PR-ref>

Exit codes
----------
- 0  success (all input ids processed; some may have been skipped)
- 1  refuse (a target row is in state:superseded)
- 2  bad input (commit-sha regex, finding-id regex, missing arg)
- 4  followups.jsonl does not exist for the requested feature

Hard constraints
----------------
- Python 3.9+ stdlib only (json, argparse, os, tempfile, pathlib, sys, datetime).
- `from _followups_lock import followups_lock` (sibling helper).
- AST-banlist clean: no eval/exec/compile/__import__/subprocess/socket.
- Does NOT validate rows against the JSON schema (that's _policy_json.py's
  job at write-time). Unknown fields round-trip through unchanged.
- Does NOT touch `previously_addressed_by` or `regression` — those are
  Synthesis-side writes during the addressed→open regression transition.
"""
from __future__ import annotations

# Exit code constants (also documented in --help epilog).
EXIT_OK = 0
EXIT_REFUSE = 1
EXIT_BAD_INPUT = 2
EXIT_NO_FOLLOWUPS = 4

import argparse
import json
import os
import re
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

# Make `from _followups_lock import followups_lock` resolve when run as a
# script. Mirrors render-followups.py's pattern.
_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

from _followups_lock import followups_lock, FollowupsLockTimeout  # noqa: E402


COMMIT_SHA_RE = re.compile(r"^[0-9a-f]{7,40}$|^PR#[0-9]+$")
FINDING_ID_RE = re.compile(r"^(sr|pl|ck)-[0-9a-z][0-9a-z-]{2,}$")
LOCK_TIMEOUT_SECONDS = 60


def _now_iso_utc() -> str:
    """ISO-8601 UTC, second precision, trailing Z. Mirrors _followups_lock."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _parse_args(argv):
    parser = argparse.ArgumentParser(
        prog="build-mark-addressed.py",
        description=(
            "Mark follow-up findings as addressed by a /build wave commit. "
            "Reads docs/specs/<feature>/followups.jsonl, transitions matching "
            "rows from state:open -> state:addressed, atomically rewrites the "
            "file under the followups lock."
        ),
        epilog=(
            "Exit codes:\n"
            "  0  success\n"
            "  1  refuse (target row is state:superseded)\n"
            "  2  bad input (regex mismatch or missing arg)\n"
            "  4  no followups.jsonl at docs/specs/<feature>/\n"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--feature",
        required=True,
        help="feature slug, e.g. pipeline-gate-permissiveness",
    )
    parser.add_argument(
        "--finding-ids",
        required=True,
        help="comma-separated list of finding_ids to mark addressed",
    )
    parser.add_argument(
        "--commit-sha",
        required=True,
        help="commit SHA (7-40 hex) or PR ref (PR#<n>) to record as addressed_by",
    )
    parser.add_argument(
        "--repo-root",
        default=None,
        help=(
            "override the repo root for resolving docs/specs/<feature>/. "
            "Default: cwd. Tilde-expanded."
        ),
    )
    return parser.parse_args(argv)


def _resolve_followups_path(feature: str, repo_root):
    """Construct docs/specs/<feature>/followups.jsonl from feature slug."""
    if repo_root is None:
        root = Path.cwd()
    else:
        root = Path(repo_root).expanduser()
    return root / "docs" / "specs" / feature / "followups.jsonl"


def _validate_finding_ids(raw: str):
    """Parse comma-separated finding_ids; return list (preserves order, dedup'd).

    Returns (ids, error). error is None on success, else a stderr message.
    """
    parts = [p.strip() for p in raw.split(",") if p.strip()]
    if not parts:
        return None, "no finding_ids provided"
    seen = set()
    out = []
    for p in parts:
        if not FINDING_ID_RE.match(p):
            return None, "invalid finding_id: %s" % p
        if p in seen:
            continue
        seen.add(p)
        out.append(p)
    return out, None


def _read_jsonl(jsonl_path):
    """Parse the JSONL into a list of (lineno, raw_text, parsed_dict_or_None).

    Empty lines preserved as (lineno, "", None) so we can reproduce the file
    layout if we wanted to — but the writer collapses to one row per line
    with no empty lines, which is the canonical format. Malformed JSON
    raises with line context (exit 2 at the call site).
    """
    rows = []
    with open(jsonl_path, "r", encoding="utf-8") as fp:
        for lineno, raw in enumerate(fp, start=1):
            stripped = raw.strip()
            if not stripped:
                continue
            try:
                obj = json.loads(stripped)
            except json.JSONDecodeError as e:
                raise _RowParseError(lineno, str(e))
            if not isinstance(obj, dict):
                raise _RowParseError(lineno, "row is not a JSON object")
            rows.append(obj)
    return rows


class _RowParseError(Exception):
    def __init__(self, lineno, msg):
        super().__init__("line %d: %s" % (lineno, msg))
        self.lineno = lineno


def _write_jsonl_atomic(target_path, rows):
    """Write rows to target_path atomically via tempfile + os.replace.

    One JSON object per line, terminated with `\\n`. `sort_keys=False` so
    the writer preserves the row's existing field order where Python's
    dict insertion order persists (3.7+). Row-level field order matches the
    way the row was originally read (json.loads preserves insertion order
    on 3.7+), with our updated keys re-assigned in place — they keep their
    original position rather than being moved to the end.
    """
    target_path = Path(target_path)
    target_path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(
        prefix=".followups.jsonl.",
        suffix=".tmp",
        dir=str(target_path.parent),
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fp:
            for row in rows:
                fp.write(json.dumps(row, ensure_ascii=False) + "\n")
            fp.flush()
            os.fsync(fp.fileno())
        os.replace(tmp, str(target_path))
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def _process_rows(rows, target_ids, commit_sha, now_iso):
    """Apply the open→addressed transition in place.

    Returns (out_rows, results, refuse_msg). `results` is a list of
    (finding_id, status, detail) tuples for stdout reporting. `refuse_msg`
    is non-None iff a superseded row was hit; caller should exit 1.

    Behaviour per spec:
    - state:open       -> state:addressed; set addressed_by=commit_sha;
                          updated_at=now. previously_addressed_by + regression
                          UNCHANGED (Synthesis-side writes).
    - state:addressed  -> idempotent: preserve original addressed_by;
                          refresh updated_at to now. Emit "already addressed"
                          on stderr.
    - state:superseded -> refuse: leave row untouched; return refuse message.
    - finding_id not present in any row -> emit "not found" skip; not an
                          error (no-op exit 0).
    """
    # Build an index for O(1) lookup; finding_id should be unique per spec.
    id_to_idx = {}
    for i, r in enumerate(rows):
        fid = r.get("finding_id")
        if isinstance(fid, str):
            id_to_idx[fid] = i

    results = []
    seen_ids = set()
    for fid in target_ids:
        if fid in seen_ids:
            continue
        seen_ids.add(fid)
        idx = id_to_idx.get(fid)
        if idx is None:
            results.append((fid, "skip", "not found"))
            continue
        row = rows[idx]
        state = row.get("state")
        if state == "superseded":
            return rows, results, (
                "cannot mark superseded row addressed: %s" % fid
            )
        if state == "addressed":
            # Idempotent: keep original addressed_by, refresh updated_at.
            row["updated_at"] = now_iso
            results.append((fid, "skip", "already addressed"))
            continue
        if state == "open":
            row["state"] = "addressed"
            row["addressed_by"] = commit_sha
            row["updated_at"] = now_iso
            # previously_addressed_by + regression intentionally untouched.
            results.append((fid, "addressed", commit_sha))
            continue
        # Unknown state: skip with reason, do not crash.
        results.append((fid, "skip", "unknown state: %s" % state))

    return rows, results, None


def main(argv=None):
    args = _parse_args(argv)

    # 1. Validate --commit-sha
    if not COMMIT_SHA_RE.match(args.commit_sha):
        sys.stderr.write(
            "invalid --commit-sha: %s "
            "(expected 7-40 hex or PR#<n>)\n" % args.commit_sha
        )
        return EXIT_BAD_INPUT

    # 2. Validate --finding-ids
    target_ids, err = _validate_finding_ids(args.finding_ids)
    if err is not None:
        sys.stderr.write("invalid --finding-ids: %s\n" % err)
        return EXIT_BAD_INPUT

    # 3. Resolve followups path; bail if missing
    jsonl_path = _resolve_followups_path(args.feature, args.repo_root)
    if not jsonl_path.exists():
        sys.stderr.write("no followups.jsonl at %s\n" % jsonl_path)
        return EXIT_NO_FOLLOWUPS

    lock_path = jsonl_path.parent / ".followups.jsonl.lock"

    # 4. Acquire lock, read, mutate, atomic-write
    try:
        with followups_lock(lock_path, timeout=LOCK_TIMEOUT_SECONDS):
            try:
                rows = _read_jsonl(jsonl_path)
            except _RowParseError as e:
                sys.stderr.write("malformed followups.jsonl: %s\n" % e)
                return EXIT_BAD_INPUT

            now_iso = _now_iso_utc()
            out_rows, results, refuse_msg = _process_rows(
                rows, target_ids, args.commit_sha, now_iso
            )
            if refuse_msg is not None:
                sys.stderr.write(refuse_msg + "\n")
                return EXIT_REFUSE

            _write_jsonl_atomic(jsonl_path, out_rows)
    except FollowupsLockTimeout as e:
        sys.stderr.write("FollowupsLockTimeout: %s\n" % e)
        return EXIT_BAD_INPUT

    # 5. Emit per-finding stdout report; mirror "already addressed" on stderr
    for fid, status, detail in results:
        if status == "addressed":
            sys.stdout.write("addressed: %s by %s\n" % (fid, detail))
        else:
            sys.stdout.write("skip: %s (%s)\n" % (fid, detail))
            if detail == "already addressed":
                sys.stderr.write("already addressed: %s\n" % fid)
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
