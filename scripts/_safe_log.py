#!/usr/bin/env python3
"""safe_log() — output-side privacy gate for compute-persona-value.py.

All stderr/stdout in compute-persona-value.py MUST flow through this helper.
Raw print() and sys.stderr.write() are banned by tests/test-no-raw-print.sh
(grep gate, A10 enforcement).

Two allowlists:
  - SAFE_EVENTS: the only event names safe_log() will emit.
  - SAFE_VALUE_PATTERNS: the only kinds of kwarg values that may be passed
    through. Anything else (e.g., a path, a finding title, a UUID with extra
    structure) raises ValueError at the call site so the violation is loud
    and local rather than silent in the dashboard.

Spec: docs/specs/token-economics/spec.md (v4.2 §Privacy)
Plan: docs/specs/token-economics/plan.md (decisions #3, M4, M6, M7)
"""

import re
import sys


SAFE_EVENTS = frozenset({
    "discovered_projects",
    "malformed_artifact",
    "missing_artifact",
    "window_rolled",
    "wrote_rankings",
    "truncated_finding_ids",
    "rejected_config_entry",
    "rejected_symlink_escape",
    "regenerated_salt_cleared_rankings",
    "silent_persona_observed",
    "non_interactive_scan_refused",
    "confirmed_scan_root",
    "subagent_mismatch_best_effort",
    "config_perms_tightened",
    "attribution_match_rate_best_effort",
    "tmux_pipe_pane_refused",
})

# Compiled value patterns. Order matters only for clarity; any-match wins.
_PERSONA_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,63}$")
_GATE_RE = re.compile(r"^(spec-review|plan|check)$")
_RUN_STATE_RE = re.compile(
    r"^(complete_value|silent|missing_survival|missing_findings|"
    r"missing_raw|malformed|cost_only)$"
)
_SHA256_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
_ISO_DATE_RE = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$")


def _value_is_safe(value):
    """Return True iff value matches one of the allowed shapes."""
    # Non-negative int (bool is a subclass of int — exclude explicitly).
    if isinstance(value, bool):
        return False
    if isinstance(value, int):
        return value >= 0
    if isinstance(value, str):
        return bool(
            _PERSONA_RE.match(value)
            or _GATE_RE.match(value)
            or _RUN_STATE_RE.match(value)
            or _SHA256_RE.match(value)
            or _ISO_DATE_RE.match(value)
        )
    return False


def safe_log(event, **counts_only):
    """Emit `[persona-value] {event}: k=v k=v` to stderr.

    Raises ValueError if `event` is not in SAFE_EVENTS or if any kwarg value
    fails the SAFE_VALUE_PATTERNS check. Callers should NOT catch the
    ValueError — it's a programming error, not runtime data.
    """
    if event not in SAFE_EVENTS:
        raise ValueError(
            "safe_log: event {!r} not in SAFE_EVENTS".format(event)
        )
    parts = []
    for k, v in counts_only.items():
        if not _value_is_safe(v):
            raise ValueError(
                "safe_log: value for {!r} is not allowlist-safe "
                "(got {!r})".format(k, v)
            )
        parts.append("{}={}".format(k, v))
    suffix = (": " + " ".join(parts)) if parts else ""
    sys.stderr.write("[persona-value] {}{}\n".format(event, suffix))
