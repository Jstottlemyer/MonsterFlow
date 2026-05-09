#!/usr/bin/env python3
"""compute-persona-value.py — Wave 1 engine (Stage 1A skeleton + Stage 1B engine).

Walks discovered MonsterFlow projects and emits per-(persona, gate) rows to
dashboard/data/persona-rankings.jsonl + sidecar bundles.

Stage 1B engine (this file):
  - Task 1.3 cost walk        — ~/.claude/projects/*/*.jsonl mtime-pruned scan
                                 of Agent dispatches (parent-annotation cost).
  - Task 1.4 A1.5 cross-check — parent annotation vs subagent final-row broad
                                 sum, tolerance 0 (forcing function for Q1).
  - Task 1.5 value walk       — 7-state run_state classification per
                                 docs/specs/<feature>/<gate>/ artifact dir.
  - Task 1.6 45-window cap +   — rolling cap, per-machine salt with
              soft-cap +        validate-on-read, salted finding IDs with
              salted IDs        gate prefix, soft-cap most-recent 50.
  - Task 1.8 emit + bundle     — atomic JSONL emit, sibling JS bundle for
                                 file:// dashboard load, roster sidecar.

Stage 1A skeleton (kept):
  - argparse with all 6 locked flags (decision #16).
  - Project Discovery 3-tier cascade (cwd / config / --scan-projects-root).
  - --confirm-scan-roots non-interactive companion (M6).
  - validate_project_root() path-traversal + symlink-escape hardening.
  - importlib.util import of session-cost.py (M1 — hyphenated filename).

Spec: docs/specs/token-economics/spec.md (v4.2)
Plan: docs/specs/token-economics/plan.md (v1.2 — decisions #15, #16, M1-M8)

Privacy gates active in this file:
  - All stderr flows through scripts/_safe_log.safe_log() — no raw print()
    or sys.stderr.write() except in __main__ help/argparse output (which
    argparse itself writes; not our code) and the explicit non-tty
    self-diagnostics already grandfathered in Stage 1A.
  - --help cascade text is the ONLY place adopter-facing path conventions
    appear; everything else is counts-only.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import hashlib
import importlib.util
import json
import os
import re
import sys
import tempfile
from pathlib import Path

# Stage 1A imports the safe_log helper (Task 1.2 — sibling file).
_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE))
from _safe_log import safe_log  # noqa: E402
import _allowlist_validator  # noqa: E402
import _roster  # noqa: E402

# M1 — import PRICING + entry_cost from session-cost.py via importlib.util
# because the hyphenated filename can't be bound to a Python module name via
# `sys.path` alone.  Bare `from session_cost import …` fails.
_SESSION_COST_PATH = _HERE / "session-cost.py"
_spec = importlib.util.spec_from_file_location(
    "session_cost", str(_SESSION_COST_PATH)
)
if _spec is None or _spec.loader is None:
    raise ImportError(
        "compute-persona-value: cannot load session-cost.py from {}".format(
            _SESSION_COST_PATH
        )
    )
session_cost = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(session_cost)
PRICING = session_cost.PRICING
entry_cost = session_cost.entry_cost


# --------------------------------------------------------------------------
# Path validation (decision #15)
# --------------------------------------------------------------------------

def _allowed_roots():
    """Return list of Path roots a project must live under.

    Default: $HOME. Override with MONSTERFLOW_ALLOWED_ROOTS (`:`-separated).
    """
    env = os.environ.get("MONSTERFLOW_ALLOWED_ROOTS")
    if env:
        return [Path(p).resolve() for p in env.split(":") if p]
    home = os.environ.get("HOME")
    if not home:
        return []
    return [Path(home).resolve()]


def _is_under(child: Path, parent: Path) -> bool:
    try:
        child.relative_to(parent)
        return True
    except ValueError:
        return False


def validate_project_root(path):
    """Validate a candidate project-root path.

    Rejects (and returns None for):
      - non-absolute paths
      - paths containing `..` segments after normalization
      - paths whose resolved (symlink-followed) location is outside any
        allowed root (default $HOME, override via MONSTERFLOW_ALLOWED_ROOTS)
      - non-existent paths (we cannot honor them safely)

    Returns the resolved Path on success.
    """
    if not isinstance(path, (str, os.PathLike)):
        return None
    raw = Path(path)
    if not raw.is_absolute():
        safe_log("rejected_config_entry", reason_code=1)
        return None
    # Reject any literal `..` in the path *before* resolution — refusing to
    # let a config file say `/Users/foo/../../etc`.
    if any(part == ".." for part in raw.parts):
        safe_log("rejected_config_entry", reason_code=2)
        return None
    try:
        resolved = raw.resolve(strict=True)
    except (OSError, RuntimeError):
        safe_log("missing_artifact", reason_code=3)
        return None
    roots = _allowed_roots()
    if roots and not any(_is_under(resolved, r) for r in roots):
        safe_log("rejected_symlink_escape", reason_code=4)
        return None
    return resolved


# --------------------------------------------------------------------------
# Config file locations (XDG)
# --------------------------------------------------------------------------

def _xdg_config_home():
    xdg = os.environ.get("XDG_CONFIG_HOME")
    if xdg:
        return Path(xdg)
    home = os.environ.get("HOME")
    if not home:
        # No HOME, no XDG default — caller must handle absent config.
        return None
    return Path(home) / ".config"


def _projects_config_path():
    base = _xdg_config_home()
    if base is None:
        return None
    return base / "monsterflow" / "projects"


def _scan_roots_confirmed_path():
    base = _xdg_config_home()
    if base is None:
        return None
    return base / "monsterflow" / "scan-roots.confirmed"


def _salt_path() -> Path | None:
    base = _xdg_config_home()
    if base is None:
        return None
    return base / "monsterflow" / "finding-id-salt"


# --------------------------------------------------------------------------
# Project Discovery cascade
# --------------------------------------------------------------------------

def _read_config_projects():
    """Tier 2 — read the explicit projects config.

    One absolute path per line; `#` comments and blank lines ignored.
    Missing-path entries are logged via safe_log and skipped.

    SEC-3 — re-chmod the file to 0o600 if found with looser perms (e.g.
    user accidentally `chmod 644` it). The config can list private
    project paths; world-readable parity with finding-id-salt and
    scan-roots.confirmed.
    """
    cfg = _projects_config_path()
    out = []
    if cfg is None or not cfg.exists():
        return out
    try:
        st = os.stat(cfg)
        if (st.st_mode & 0o777) != 0o600:
            try:
                os.chmod(str(cfg), 0o600)
                safe_log("config_perms_tightened", reason_code=11)
            except OSError:
                pass
    except OSError:
        pass
    try:
        text = cfg.read_text(encoding="utf-8")
    except OSError:
        safe_log("missing_artifact", reason_code=10)
        return out
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        validated = validate_project_root(line)
        if validated is None:
            # validate_project_root already logged the rejection reason.
            continue
        out.append(validated)
    return out


def _read_confirmed_scan_roots():
    """Return the set of `<dir>` strings (resolved) the adopter has
    pre-confirmed via either an interactive y/N prompt or
    --confirm-scan-roots.

    SEC-3 — re-chmod the file to 0o600 if found with looser perms
    (parity with finding-id-salt and the projects config).
    """
    p = _scan_roots_confirmed_path()
    out = set()
    if p is None or not p.exists():
        return out
    try:
        st = os.stat(p)
        if (st.st_mode & 0o777) != 0o600:
            try:
                os.chmod(str(p), 0o600)
                safe_log("config_perms_tightened", reason_code=12)
            except OSError:
                pass
    except OSError:
        pass
    try:
        text = p.read_text(encoding="utf-8")
    except OSError:
        return out
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        try:
            out.add(str(Path(line).resolve()))
        except (OSError, RuntimeError):
            continue
    return out


def _has_docs_specs(p: Path) -> bool:
    return (p / "docs" / "specs").is_dir()


def _has_no_scan_sentinel(p: Path) -> bool:
    return (p / ".monsterflow-no-scan").exists()


def _walk_scan_root(scan_root: Path):
    """Yield each `<scan_root>/<child>` that has a `docs/specs/` directory.

    Honors the per-project `.monsterflow-no-scan` sentinel.
    """
    try:
        children = sorted(scan_root.iterdir())
    except OSError:
        return
    for child in children:
        if not child.is_dir():
            continue
        if _has_no_scan_sentinel(child):
            continue
        if _has_docs_specs(child):
            yield child


def discover_projects(scan_roots, confirmed_only=False):
    """Run the 3-tier Project Discovery cascade.

    Args:
      scan_roots: list[Path] from --scan-projects-root args (already
        validated by the caller via validate_project_root() — entries that
        failed validation should be filtered out before this call).
      confirmed_only: when True (non-tty path), tier-3 entries that are NOT
        in scan-roots.confirmed are silently skipped with a safe_log
        non_interactive_scan_refused event. When False (tty path), the
        caller is expected to handle the y/N prompt before calling
        discover_projects (or to pass confirmed_only=True after handling).

    Returns deduped list of resolved Paths (worktree-safe via realpath).
    Emits a single counts-only `discovered_projects` event before returning.
    """
    seen = set()  # set of str(realpath)
    ordered = []  # preserve cascade order for stable output
    cwd_count = 0
    cfg_count = 0
    scan_count = 0

    def _add(p: Path) -> bool:
        try:
            r = str(p.resolve())
        except (OSError, RuntimeError):
            return False
        if r in seen:
            return False
        seen.add(r)
        ordered.append(Path(r))
        return True

    # Tier 1 — cwd if it has docs/specs/
    cwd = Path.cwd()
    if _has_docs_specs(cwd) and not _has_no_scan_sentinel(cwd):
        if _add(cwd):
            cwd_count += 1

    # Tier 2 — explicit config
    for p in _read_config_projects():
        if _has_no_scan_sentinel(p):
            continue
        if not _has_docs_specs(p):
            continue
        if _add(p):
            cfg_count += 1

    # Tier 3 — --scan-projects-root cascade
    confirmed = _read_confirmed_scan_roots()
    refused = 0
    for scan_root in scan_roots:
        if str(scan_root) not in confirmed:
            if confirmed_only:
                refused += 1
                continue
            # tty branch is handled by main() before we get here; if a
            # caller forgets to handle it, we err on the side of skipping.
            refused += 1
            continue
        for proj in _walk_scan_root(scan_root):
            if _add(proj):
                scan_count += 1

    if refused:
        safe_log("non_interactive_scan_refused", count=refused)

    safe_log(
        "discovered_projects",
        cwd=cwd_count,
        config=cfg_count,
        scan=scan_count,
    )
    return ordered


# --------------------------------------------------------------------------
# --confirm-scan-roots (M6)
# --------------------------------------------------------------------------

def confirm_scan_roots(dirs):
    """Append each validated dir to scan-roots.confirmed (idempotent).

    File is created chmod 600 if absent. Atomic append via tmp + os.replace
    so a SIGINT mid-write cannot corrupt the file.

    Returns 0 on success, non-zero if any dir failed validation (still
    appends the ones that DID validate — partial success is honest).
    """
    target = _scan_roots_confirmed_path()
    if target is None:
        sys.stderr.write(
            "[persona-value] cannot resolve XDG_CONFIG_HOME or $HOME; "
            "refusing to write scan-roots.confirmed\n"
        )
        return 2
    target.parent.mkdir(parents=True, exist_ok=True)

    existing = _read_confirmed_scan_roots()
    new_lines = []
    failed = 0
    added = 0
    for d in dirs:
        validated = validate_project_root(d)
        if validated is None:
            failed += 1
            continue
        key = str(validated)
        if key in existing:
            continue  # idempotent
        new_lines.append(key)
        existing.add(key)
        added += 1

    if new_lines:
        # Read existing content, append, atomic replace.
        prior = ""
        if target.exists():
            try:
                prior = target.read_text(encoding="utf-8")
                if prior and not prior.endswith("\n"):
                    prior += "\n"
            except OSError:
                prior = ""
        body = prior + "\n".join(new_lines) + "\n"
        tmp = target.with_suffix(target.suffix + ".tmp")
        # Create with restrictive perms; if file pre-existed, preserve 600.
        flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC
        fd = os.open(str(tmp), flags, 0o600)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                fh.write(body)
        except Exception:
            try:
                os.unlink(str(tmp))
            except OSError:
                pass
            raise
        os.replace(str(tmp), str(target))
        try:
            os.chmod(str(target), 0o600)
        except OSError:
            pass

    safe_log("confirmed_scan_root", count=added)
    return 0 if failed == 0 else 1


# ==========================================================================
# Stage 1B — Engine (tasks 1.3, 1.4, 1.5, 1.6, 1.8)
# ==========================================================================

# Persona-prompt regex applied to Agent dispatch input.prompt strings.
# Persona DIR is `review`; gate name is `spec-review` (we remap below).
_PERSONA_PROMPT_RE = re.compile(
    r"personas/(review|plan|check)/([a-z0-9][a-z0-9-]{0,63})\.md"
)
# Annotations on the parent's tool_result trailing text.
_AGENT_ID_RE = re.compile(r"agentId:\s*([0-9a-f]{17})")
_TOTAL_TOKENS_RE = re.compile(r"total_tokens:\s*(\d+)")

# review (persona dir) -> spec-review (gate name).
_DIR_TO_GATE = {"review": "spec-review", "plan": "plan", "check": "check"}
# Reverse for cost-walk attribution sanity (not currently needed but documented).

# Gate -> short prefix used by salt_finding_id().
_GATE_PREFIX = {"spec-review": "sr", "plan": "pl", "check": "ck"}


# --------------------------------------------------------------------------
# Task 1.6 — Salt management (M7)
# --------------------------------------------------------------------------

def get_or_create_salt(accept_salt_reset: bool = False) -> bytes:
    """M7 + MF-3 — validate-on-read 32-byte salt with destructive-regen
    gated behind an explicit opt-in flag.

    Read path validates:
      - file exists
      - exactly 32 bytes
      - not all-zero
      - chmod 0o600 (mode bits == 600)

    First-run path (file missing) generates fresh salt automatically — no
    flag required, nothing to preserve.

    Corruption path (file exists but fails validation) requires
    `accept_salt_reset=True` (CLI: --accept-salt-reset). Without the flag we
    refuse and exit non-zero with a stderr explanation; with the flag we
    regenerate atomically and CLEAR dashboard/data/persona-rankings.jsonl
    + persona-rankings-bundle.js + persona-insights-bundle.js (drill-down
    continuity reset is the only honest behavior — old salted IDs no longer
    link). MF-3 closes the silent-data-loss default the /check verdict
    flagged as a blocker.

    Returns the 32-byte salt.
    """
    target = _salt_path()
    if target is None:
        # No XDG/HOME — fall back to in-memory random salt for this run.
        # Persistence not possible; safe_log not called because the failure
        # mode is environmental, not a config rejection.
        return os.urandom(32)

    target.parent.mkdir(parents=True, exist_ok=True)

    needs_regen = False
    is_corruption = False  # MF-3: distinguish first-run vs destructive regen
    if target.exists():
        try:
            st = os.stat(target)
            if st.st_size != 32 or (st.st_mode & 0o777) != 0o600:
                needs_regen = True
                is_corruption = True
            else:
                with open(target, "rb") as fh:
                    data = fh.read()
                if len(data) != 32 or data == b"\x00" * 32:
                    needs_regen = True
                    is_corruption = True
                else:
                    return data
        except OSError:
            needs_regen = True
            is_corruption = True
    else:
        needs_regen = True
        # is_corruption stays False — first-run, no rankings to lose.

    if not needs_regen:
        # Defensive: shouldn't reach here.
        return os.urandom(32)

    # MF-3 — destructive regen requires explicit opt-in.
    if is_corruption and not accept_salt_reset:
        sys.stderr.write(
            "[persona-value] finding-id-salt at {p} failed validation "
            "(size != 32 / perms != 0o600 / all-zero / unreadable). "
            "Regenerating would clear dashboard/data/persona-rankings.jsonl "
            "and break drill-down continuity. Refusing to regenerate "
            "without explicit consent. Re-run with --accept-salt-reset to "
            "proceed.\n".format(p=target)
        )
        raise SystemExit(2)

    # Regenerate.
    new_salt = os.urandom(32)
    # Try atomic O_CREAT|O_EXCL first (race detection); if file appeared
    # underneath us, re-validate and either accept or overwrite via tmp.
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    try:
        fd = os.open(str(target), flags, 0o600)
        try:
            os.write(fd, new_salt)
        finally:
            os.close(fd)
    except FileExistsError:
        # Race or pre-existing invalid file → overwrite via tmp + os.replace.
        tmp = target.with_suffix(".tmp")
        fd = os.open(
            str(tmp), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600
        )
        try:
            os.write(fd, new_salt)
        finally:
            os.close(fd)
        os.replace(str(tmp), str(target))
    try:
        os.chmod(str(target), 0o600)
    except OSError:
        pass

    # Continuity reset — clear the rankings file AND any derived render-side
    # artifacts so downstream readers do not try to link old salted IDs
    # against the new salt namespace. SEC-5 (check verdict): the bundle is a
    # derived render-side mirror that outlives the JSONL — wipe it in lockstep.
    data_dir = Path.cwd() / "dashboard" / "data"
    for derived in (
        data_dir / "persona-rankings.jsonl",
        data_dir / "persona-rankings-bundle.js",
        data_dir / "persona-insights-bundle.js",  # forward-compat for D1
    ):
        try:
            if derived.exists():
                # Truncate (don't delete — keeps file presence stable for the
                # dashboard's existence check; an empty file is treated as
                # "no rows yet" by readers; an empty bundle .js no-ops on
                # eval since the file is empty).
                with open(derived, "w", encoding="utf-8") as fh:
                    fh.write("")
        except OSError:
            pass

    safe_log("regenerated_salt_cleared_rankings")
    return new_salt


def salt_finding_id(
    salt: bytes, normalized_signature: str, gate_prefix: str
) -> str:
    """ID = <gate_prefix>-sha256(salt || normalized_signature)[:10] (Δ3)."""
    h = hashlib.sha256(salt + normalized_signature.encode("utf-8")).hexdigest()
    return "{}-{}".format(gate_prefix, h[:10])


def cap_45_window(
    rows: list[dict], by_field: str = "last_artifact_created_at"
) -> list[dict]:
    """Most-recent-45 by `by_field`; truncate older rows.

    `rows` is a list of dicts each carrying `by_field` as ISO-8601 string.
    Sort descending by that field; keep first 45.
    """
    if len(rows) <= 45:
        return list(rows)
    sorted_desc = sorted(
        rows, key=lambda r: r.get(by_field, ""), reverse=True
    )
    return sorted_desc[:45]


def soft_cap_finding_ids(
    ids: list[str], cap: int = 50
) -> tuple[list[str], int]:
    """Return (most_recent_<=cap_ids_sorted_lex, truncated_count).

    Caller passes ids in most-recent-first order (already pre-sorted by the
    creation timestamp of the contributing artifact directory). We retain
    the first `cap`, then sort lexicographically for byte-stable diff.
    """
    if len(ids) <= cap:
        return sorted(ids), 0
    kept = ids[:cap]
    truncated = len(ids) - cap
    return sorted(kept), truncated


# --------------------------------------------------------------------------
# Task 1.3 — Cost walk (M1 + M3 + spike Q1 trap)
# --------------------------------------------------------------------------

def _maybe_extract_persona_gate(prompt_text: str):
    """Return (persona, gate) or (None, None) if no match."""
    if not prompt_text:
        return None, None
    m = _PERSONA_PROMPT_RE.search(prompt_text)
    if not m:
        return None, None
    dir_name = m.group(1)
    persona = m.group(2)
    gate = _DIR_TO_GATE.get(dir_name, dir_name)
    return persona, gate


def _extract_tool_result_text(content) -> str:
    """tool_result `content` may be a list of {type, text} blocks or a bare
    string. Concatenate all text fragments."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for block in content:
            if isinstance(block, dict):
                t = block.get("text")
                if isinstance(t, str):
                    parts.append(t)
        return "\n".join(parts)
    return ""


def cost_walk(
    claude_projects_root: Path | None = None,
    mtime_floor: float | None = None,
) -> list[dict]:
    """Walk ~/.claude/projects/*/*.jsonl (parent sessions), extract per-
    Agent-dispatch cost attributions.

    spike-q1: parent annotation `total_tokens: N` == final subagent row's
    broad usage (input + output + cache_read + cache_creation). Naive
    inter-row sum overcounts by ~2.66x due to cumulative cache re-billing
    per turn. Use the annotation as canonical; cross-check via A1.5.
    See docs/specs/token-economics/plan/raw/spike-q1-result.md.

    Returns a list of dispatch dicts with keys:
      parent_session_uuid, parent_proj_dir, agentId, persona, gate, tokens

    Only sessions whose mtime >= mtime_floor are walked (mtime pruning).
    Lines that don't contain BOTH `"Agent"` and `"tool_use"` are skipped
    before json.loads (substring pre-filter).
    """
    if claude_projects_root is None:
        claude_projects_root = Path.home() / ".claude" / "projects"
    out: list[dict] = []
    if not claude_projects_root.is_dir():
        return out

    # Collect candidate session JSONLs across all project dirs, mtime-pruned.
    candidates: list[Path] = []
    try:
        proj_dirs = sorted(claude_projects_root.iterdir())
    except OSError:
        return out
    for proj_dir in proj_dirs:
        if not proj_dir.is_dir():
            continue
        try:
            for jf in proj_dir.glob("*.jsonl"):
                try:
                    mt = jf.stat().st_mtime
                except OSError:
                    continue
                if mtime_floor is not None and mt < mtime_floor:
                    continue
                candidates.append(jf)
        except OSError:
            continue

    # First pass: per-session, build {tool_use_id -> (persona, gate)}
    # from `Agent` tool_use blocks. Then second pass on same session pulls
    # tool_result rows that match those ids and parses the trailing text.
    for session_path in candidates:
        parent_proj = session_path.parent.name
        parent_uuid = session_path.stem
        agent_dispatches: dict[str, dict] = {}  # tool_use_id -> row

        try:
            with open(session_path, "r", encoding="utf-8") as fh:
                # First pass — find Agent tool_use blocks.
                lines = fh.readlines()
        except OSError:
            continue

        # Pass 1: tool_use Agent invocations.
        for raw in lines:
            if "Agent" not in raw or "tool_use" not in raw:
                continue
            try:
                entry = json.loads(raw)
            except json.JSONDecodeError:
                continue
            msg = entry.get("message") or {}
            content = msg.get("content")
            if not isinstance(content, list):
                continue
            for block in content:
                if not isinstance(block, dict):
                    continue
                if block.get("type") != "tool_use":
                    continue
                if block.get("name") != "Agent":
                    continue
                tool_use_id = block.get("id")
                if not isinstance(tool_use_id, str):
                    continue
                inp = block.get("input") or {}
                prompt = inp.get("prompt") or ""
                persona, gate = _maybe_extract_persona_gate(prompt)
                # MF-2: track whether the prompt mentions personas/ at all so
                # a16_attribution_match_rate can split (a) description-invoked
                # subagents (no personas/, expected unknown) from (b) regex
                # drift (personas/ present but no extraction).
                prompt_has_personas = "personas/" in prompt
                agent_dispatches[tool_use_id] = {
                    "persona": persona or "<unknown>",
                    "gate": gate or "<unknown>",
                    "agentId": None,
                    "tokens": 0,
                    "prompt_has_personas": prompt_has_personas,
                }

        if not agent_dispatches:
            continue

        # Pass 2: tool_result rows for those ids.
        for raw in lines:
            if "tool_result" not in raw:
                continue
            try:
                entry = json.loads(raw)
            except json.JSONDecodeError:
                continue
            msg = entry.get("message") or {}
            content = msg.get("content")
            if not isinstance(content, list):
                continue
            for block in content:
                if not isinstance(block, dict):
                    continue
                if block.get("type") != "tool_result":
                    continue
                tu_id = block.get("tool_use_id")
                if tu_id not in agent_dispatches:
                    continue
                txt = _extract_tool_result_text(block.get("content"))
                aid_m = _AGENT_ID_RE.search(txt)
                tok_m = _TOTAL_TOKENS_RE.search(txt)
                d = agent_dispatches[tu_id]
                if aid_m:
                    d["agentId"] = aid_m.group(1)
                if tok_m:
                    try:
                        # spike-q1: parent annotation == final subagent row's
                        # broad usage (in+out+cache_r+cache_c). Naive
                        # inter-row sum overcounts by ~2.66x due to
                        # cumulative cache re-billing per turn.
                        # See docs/specs/token-economics/plan/raw/
                        # spike-q1-result.md.
                        d["tokens"] = int(tok_m.group(1))
                    except ValueError:
                        pass

        for tu_id, d in agent_dispatches.items():
            # MF-2: keep dispatches with `gate == "<unknown>"` so a16 can
            # compute the attribution match-rate. aggregate_rankings drops
            # them downstream. Comment-vs-code mismatch in v0.6.0 fixed.
            out.append({
                "parent_session_uuid": parent_uuid,
                "parent_proj_dir": parent_proj,
                "agentId": d["agentId"],
                "persona": d["persona"],
                "gate": d["gate"],
                "tokens": d["tokens"],
                "prompt_has_personas": d.get(
                    "prompt_has_personas", False
                ),
            })

    return out


# --------------------------------------------------------------------------
# Task 1.4b — A1.6 attribution match-rate threshold (MF-2)
# --------------------------------------------------------------------------

def a16_attribution_match_rate(
    cost_dispatches: list[dict],
    threshold: float = 0.95,
    best_effort: bool = False,
) -> float:
    """MF-2 — quantified persona-regex match-rate AC.

    Denominator: dispatches whose parent prompt contained `personas/`.
    Numerator: those that resolved to a non-`<unknown>` (persona, gate).
    Description-invoked subagents (e.g. persona-metrics-validator) whose
    prompts never mention `personas/` are excluded from the denominator —
    expected misses, not regex drift.

    Returns the computed match rate (0.0 - 1.0).
    Below threshold: exit non-zero unless `best_effort=True`.
    """
    candidate = 0
    matched = 0
    for d in cost_dispatches:
        if not d.get("prompt_has_personas"):
            continue
        candidate += 1
        if d.get("persona") and d["persona"] != "<unknown>":
            matched += 1
    if candidate == 0:
        return 1.0  # vacuously true — no candidate dispatches yet
    rate = matched / candidate
    if rate < threshold:
        if best_effort:
            safe_log(
                "attribution_match_rate_best_effort",
                rate_basis_points=int(rate * 10000),
            )
            return rate
        sys.stderr.write(
            "[persona-value] A1.6 attribution match rate {:.3f} below "
            "threshold {:.3f} ({}/{} dispatches with personas/ in prompt "
            "resolved to a (persona, gate)). Re-run with --best-effort "
            "to downgrade to a warning, or fix the persona-prompt regex "
            "/ CC subagent format drift.\n".format(
                rate, threshold, matched, candidate
            )
        )
        raise SystemExit(1)
    return rate


# --------------------------------------------------------------------------
# Task 1.4 — A1.5 cross-check
# --------------------------------------------------------------------------

def a15_crosscheck(
    cost_dispatches: list[dict],
    best_effort: bool,
    claude_projects_root: Path | None = None,
) -> bool:
    """For each dispatch with an agentId, locate the linked subagent JSONL:
        ~/.claude/projects/<parent_proj>/<parent_uuid>/subagents/agent-<aid>.jsonl
    Read FINAL assistant row's usage block; compute broad sum
    (input + output + cache_read + cache_creation). Compare with parent
    annotation `tokens` (tolerance 0).

    On any mismatch: if `best_effort` log + proceed; else SystemExit(1) with
    a stderr pointer at /plan to re-open Q1.

    Missing transcripts are skipped (still cheap path; cost_only stays
    cheap). Returns True iff every present transcript matched.
    """
    if claude_projects_root is None:
        claude_projects_root = Path.home() / ".claude" / "projects"
    mismatches = 0
    checked = 0
    for d in cost_dispatches:
        aid = d.get("agentId")
        if not aid:
            continue
        sub_path = (
            claude_projects_root
            / d["parent_proj_dir"]
            / d["parent_session_uuid"]
            / "subagents"
            / "agent-{}.jsonl".format(aid)
        )
        if not sub_path.is_file():
            continue
        # Read final assistant row.
        final_usage = None
        try:
            with open(sub_path, "r", encoding="utf-8") as fh:
                for raw in fh:
                    raw = raw.strip()
                    if not raw:
                        continue
                    try:
                        entry = json.loads(raw)
                    except json.JSONDecodeError:
                        continue
                    msg = entry.get("message") or {}
                    if msg.get("role") != "assistant":
                        continue
                    u = msg.get("usage") or {}
                    if not u:
                        continue
                    final_usage = u
        except OSError:
            continue
        if final_usage is None:
            continue
        broad = (
            int(final_usage.get("input_tokens", 0))
            + int(final_usage.get("output_tokens", 0))
            + int(final_usage.get("cache_read_input_tokens", 0))
            + int(final_usage.get("cache_creation_input_tokens", 0))
        )
        checked += 1
        if broad != int(d.get("tokens", 0)):
            mismatches += 1

    if mismatches:
        if best_effort:
            safe_log("subagent_mismatch_best_effort", count=mismatches)
            return False
        sys.stderr.write(
            "[persona-value] A1.5 cross-check failed: {n} dispatch(es) had "
            "parent-annotation total_tokens != final-subagent-row broad "
            "sum. Spike Q1 must be re-opened via /plan before this build "
            "can ship. Re-run with --best-effort to downgrade to a "
            "warning.\n".format(n=mismatches)
        )
        raise SystemExit(1)
    _ = checked  # silence unused — we may surface in stage 1C diagnostics.
    return True


# --------------------------------------------------------------------------
# Task 1.5 — Value walk + 7-state classification
# --------------------------------------------------------------------------

def _read_jsonl(path: Path) -> list[dict] | None:
    """Return list of parsed rows; None on parse error in any line."""
    rows: list[dict] = []
    try:
        with open(path, "r", encoding="utf-8") as fh:
            for raw in fh:
                raw = raw.strip()
                if not raw:
                    continue
                try:
                    rows.append(json.loads(raw))
                except json.JSONDecodeError:
                    return None
    except OSError:
        return None
    return rows


def _read_json(path: Path) -> dict | None:
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, json.JSONDecodeError):
        return None


# Bullet line: starts with '- ' or '* ' at column 0 (no leading whitespace).
_BULLET_RE = re.compile(r"^[\-\*]\s+\S")
# Section heading we count from.
_COUNTED_SECTIONS = {
    "Critical Gaps",
    "Important Considerations",
    "Observations",
}


def count_raw_bullets(raw_path: Path) -> int:
    """Count top-level bullets under ## Critical Gaps, ## Important
    Considerations, ## Observations. Excludes ## Verdict and any nested or
    numbered bullets (numbered bullets start with `1.` etc., not `- `)."""
    try:
        text = raw_path.read_text(encoding="utf-8")
    except OSError:
        return 0
    count = 0
    in_counted_section = False
    for line in text.splitlines():
        s = line.rstrip()
        if s.startswith("## "):
            heading = s[3:].split(":", 1)[0].strip()
            in_counted_section = heading in _COUNTED_SECTIONS
            continue
        if not in_counted_section:
            continue
        if _BULLET_RE.match(line):
            # Top-level only — already enforced by no leading whitespace.
            count += 1
    return count


def _classify_artifact_dir(
    artifact_dir: Path,
) -> tuple[str, dict | None, list[dict] | None,
            list[dict] | None, dict | None]:
    """Return (run_state_at_dir_level, run_json, findings, survival,
    participation_by_persona).

    The dir-level state is the WORST of the artifact set (raw missing /
    findings missing / etc.); per-persona refinement (e.g. silent) is
    applied later by value_walk per (persona, gate) row.
    """
    run_path = artifact_dir / "run.json"
    findings_path = artifact_dir / "findings.jsonl"
    survival_path = artifact_dir / "survival.jsonl"
    participation_path = artifact_dir / "participation.jsonl"
    raw_dir = artifact_dir / "raw"

    run_json = _read_json(run_path)
    findings = _read_jsonl(findings_path) if findings_path.exists() else None
    if findings_path.exists() and findings is None:
        return ("malformed", run_json, None, None, None)
    survival = _read_jsonl(survival_path) if survival_path.exists() else None
    if survival_path.exists() and survival is None:
        return ("malformed", run_json, findings, None, None)
    participation = (
        _read_jsonl(participation_path)
        if participation_path.exists()
        else None
    )
    if participation_path.exists() and participation is None:
        return ("malformed", run_json, findings, survival, None)

    # Index participation by persona for silent classification.
    participation_by_persona: dict[str, dict] = {}
    if participation:
        for row in participation:
            p = row.get("persona")
            if isinstance(p, str):
                participation_by_persona[p] = row

    has_raw = raw_dir.is_dir() and any(raw_dir.glob("*.md"))
    has_findings = findings is not None
    has_run = run_json is not None
    has_survival = survival is not None and len(survival) > 0

    if not has_run:
        # Without run.json we have no reliable created_at; treat as malformed
        # for window placement purposes.
        return ("malformed", run_json, findings, survival,
                participation_by_persona)

    if has_raw and has_findings and has_survival:
        state = "complete_value"
    elif has_raw and has_findings and not has_survival:
        state = "missing_survival"
    elif has_findings and not has_raw:
        state = "missing_raw"
    elif has_raw and not has_findings:
        state = "missing_findings"
    elif not has_raw and not has_findings:
        # Only run.json — also "missing_findings" (raw + findings both gone
        # is rare; bias toward findings being the more critical signal).
        state = "missing_findings"
    else:
        state = "malformed"

    return (state, run_json, findings, survival, participation_by_persona)


def _normalize_dt_minute(iso: str) -> str:
    """Parse ISO-8601, force UTC, truncate to minute (seconds = 00).

    Returns 'YYYY-MM-DDTHH:MM:00Z'. On parse failure returns iso unchanged
    (caller is expected to validate against the schema downstream)."""
    if not isinstance(iso, str):
        return ""
    try:
        s = iso.replace("Z", "+00:00")
        dt = _dt.datetime.fromisoformat(s)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=_dt.timezone.utc)
        else:
            dt = dt.astimezone(_dt.timezone.utc)
        return dt.strftime("%Y-%m-%dT%H:%M:00Z")
    except ValueError:
        return iso


def value_walk(project_roots: list[Path]) -> list[dict]:
    """Walk each <project_root>/docs/specs/<feature>/<gate>/ and return a
    list of per-(persona, gate, artifact_dir) records.

    Each record has:
      persona, gate, run_state, created_at (raw ISO from run.json),
      created_at_minute (normalized), emitted, judge_retained, unique,
      downstream_survived, contributing_finding_ids (list of normalized
      signatures pre-salt), is_silent (bool), artifact_dir (Path).
    """
    out: list[dict] = []

    for project_root in project_roots:
        specs_root = project_root / "docs" / "specs"
        if not specs_root.is_dir():
            continue
        try:
            features = sorted(p for p in specs_root.iterdir() if p.is_dir())
        except OSError:
            continue
        for feature_dir in features:
            try:
                gate_dirs = sorted(
                    p for p in feature_dir.iterdir() if p.is_dir()
                )
            except OSError:
                continue
            for gate_dir in gate_dirs:
                gate = gate_dir.name
                if gate not in _GATE_PREFIX:
                    continue
                state, run_json, findings, survival, participation = (
                    _classify_artifact_dir(gate_dir)
                )

                created_at = ""
                if run_json and isinstance(
                    run_json.get("created_at"), str
                ):
                    created_at = run_json["created_at"]

                # Personas to emit for this dir:
                #   - Personas in participation.jsonl (covers silent rows).
                #   - Personas appearing in any findings.jsonl personas[].
                personas_seen: set[str] = set()
                if participation:
                    personas_seen.update(participation.keys())
                if findings:
                    for row in findings:
                        for p in row.get("personas") or []:
                            if isinstance(p, str):
                                personas_seen.add(p)

                if state == "malformed":
                    safe_log("malformed_artifact", count=1)

                if not personas_seen:
                    # Nothing to attribute — skip the dir for value walk
                    # (still represented in safe_log warning above if
                    # malformed).
                    continue

                for persona in sorted(personas_seen):
                    # Per-persona refinement: silent overrides complete_value
                    # when participation row says ok + findings_emitted=0.
                    persona_state = state
                    is_silent = False
                    if state == "complete_value" and participation:
                        prow = participation.get(persona)
                        if (
                            prow
                            and prow.get("status") == "ok"
                            and int(prow.get("findings_emitted", 0) or 0) == 0
                        ):
                            persona_state = "silent"
                            is_silent = True
                            safe_log("silent_persona_observed", count=1)

                    # Bullet count from raw/<persona>.md (best-effort).
                    raw_path = gate_dir / "raw" / "{}.md".format(persona)
                    emitted = (
                        count_raw_bullets(raw_path)
                        if raw_path.is_file()
                        else 0
                    )

                    judge_retained = 0
                    unique = 0
                    contrib_sigs: list[tuple[str, str]] = []  # (sig, ts)
                    if findings:
                        for row in findings:
                            personas_field = row.get("personas") or []
                            if persona not in personas_field:
                                continue
                            judge_retained += 1
                            sig = row.get("normalized_signature")
                            if isinstance(sig, str):
                                contrib_sigs.append((sig, created_at))
                            if row.get("unique_to_persona") == persona:
                                unique += 1

                    downstream = 0
                    if survival and findings:
                        # Build set of finding_ids belonging to this persona.
                        my_ids = {
                            row.get("finding_id")
                            for row in findings
                            if persona in (row.get("personas") or [])
                            and isinstance(row.get("finding_id"), str)
                        }
                        for sr in survival:
                            if (
                                sr.get("outcome") == "addressed"
                                and sr.get("finding_id") in my_ids
                            ):
                                downstream += 1

                    out.append({
                        "persona": persona,
                        "gate": gate,
                        "run_state": persona_state,
                        "created_at": created_at,
                        "created_at_minute": _normalize_dt_minute(
                            created_at
                        ),
                        "emitted": emitted,
                        "judge_retained": judge_retained,
                        "unique": unique,
                        "downstream_survived": downstream,
                        "contributing_signatures": contrib_sigs,
                        "is_silent": is_silent,
                        "artifact_dir": str(gate_dir),
                    })

    return out


# --------------------------------------------------------------------------
# Aggregation: value records + cost dispatches -> ranking rows
# --------------------------------------------------------------------------

def _persona_content_hash(personas_root: Path, gate: str, persona: str):
    """Return current sha256 of personas/<dir>/<persona>.md or None.

    Maps gate -> dir via inverse of _DIR_TO_GATE.
    """
    inverse = {v: k for k, v in _DIR_TO_GATE.items()}
    dir_name = inverse.get(gate)
    if dir_name is None:
        return None
    persona_path = personas_root / dir_name / "{}.md".format(persona)
    if not persona_path.is_file():
        return None
    try:
        return _roster.compute_persona_content_hash(persona_path)
    except OSError:
        return None


def aggregate_rankings(
    value_records: list[dict],
    cost_dispatches: list[dict],
    salt: bytes,
    personas_root: Path | None = None,
) -> list[dict]:
    """Aggregate value records + cost dispatches into per-(persona, gate)
    ranking rows that conform to schemas/persona-rankings.allowlist.json.

    Cost-window and value-window are independent counts (M3).
    """
    if personas_root is None:
        personas_root = Path.home() / ".claude" / "personas"

    # Group value records by (persona, gate); apply 45-window cap on the
    # most-recent artifact dirs per group.
    by_key: dict[tuple[str, str], list[dict]] = {}
    for rec in value_records:
        by_key.setdefault((rec["persona"], rec["gate"]), []).append(rec)

    # Group cost dispatches by (persona, gate) for cost-window aggregation.
    cost_by_key: dict[tuple[str, str], list[dict]] = {}
    for d in cost_dispatches:
        if d["persona"] == "<unknown>" or d["gate"] == "<unknown>":
            continue
        cost_by_key.setdefault((d["persona"], d["gate"]), []).append(d)

    # Cost_only synthesis: for any (persona, gate) appearing in cost but
    # NOT in value, emit a cost-only ranking row (zero value contributions).
    all_keys = set(by_key.keys()) | set(cost_by_key.keys())

    rows_out: list[dict] = []

    for key in sorted(all_keys):
        persona, gate = key
        v_records = by_key.get(key, [])
        # 45-window cap on value side (by created_at, descending).
        v_capped = cap_45_window(
            v_records, by_field="created_at"
        )
        # Cost side: per-spec cost-window is "Agent dispatches" — use
        # most-recent 45 by parent_session ordering. We do not have a
        # per-dispatch timestamp without re-walking, so we treat all in-
        # window dispatches as cost-window contributions.
        cost_records = cost_by_key.get(key, [])

        run_state_counts = {
            "complete_value": 0,
            "silent": 0,
            "missing_survival": 0,
            "missing_findings": 0,
            "missing_raw": 0,
            "malformed": 0,
            "cost_only": 0,
        }
        total_emitted = 0
        total_judge_retained = 0
        total_downstream_survived = 0
        total_unique = 0
        silent_runs_count = 0
        max_created_at_min = ""
        sig_with_ts: list[tuple[str, str]] = []

        for rec in v_capped:
            st = rec["run_state"]
            if st in run_state_counts:
                run_state_counts[st] += 1
            else:
                run_state_counts["malformed"] += 1
            # judge-retention numerator: counts complete_value + silent +
            # missing_survival.
            if st in ("complete_value", "silent", "missing_survival"):
                total_emitted += rec["emitted"]
                total_judge_retained += rec["judge_retained"]
            # uniqueness numerator: complete_value + missing_survival.
            if st in ("complete_value", "missing_survival"):
                total_unique += rec["unique"]
            # downstream-survival numerator: complete_value only.
            if st == "complete_value":
                total_downstream_survived += rec["downstream_survived"]
            if st == "silent":
                silent_runs_count += 1
            ts_min = rec.get("created_at_minute") or ""
            if ts_min > max_created_at_min:
                max_created_at_min = ts_min
            for sig in rec.get("contributing_signatures", []):
                sig_with_ts.append(sig)

        # Cost-only synthesis when value side is empty for this key but
        # cost has dispatches.
        runs_in_window = sum(
            run_state_counts[s]
            for s in (
                "complete_value",
                "silent",
                "missing_survival",
                "missing_findings",
                "missing_raw",
                "malformed",
            )
        )
        if runs_in_window == 0 and cost_records:
            run_state_counts["cost_only"] = len(cost_records)

        # cost_runs_in_window is always the dispatch count — adding run_state_counts["cost_only"]
        # doubled it in the cost-only path (Codex P2 caught at /preship). Each cost record IS one
        # dispatch; the cost_only state is bookkeeping for the value-side denominator, not a separate
        # contributor to the cost denominator.
        cost_runs_in_window = len(cost_records)

        total_tokens = sum(int(d.get("tokens", 0) or 0) for d in cost_records)

        # Rates (value-window denominators).
        if total_emitted > 0:
            judge_retention_ratio = round(
                total_judge_retained / total_emitted, 6
            )
        else:
            judge_retention_ratio = None
        if total_judge_retained > 0:
            downstream_survival_rate = round(
                total_downstream_survived / total_judge_retained, 6
            )
            uniqueness_rate = round(
                total_unique / total_judge_retained, 6
            )
        else:
            downstream_survival_rate = None
            uniqueness_rate = None
        if cost_runs_in_window > 0:
            avg_tokens_per_invocation = round(
                total_tokens / cost_runs_in_window, 6
            )
        else:
            avg_tokens_per_invocation = None

        # Salted finding IDs (Δ3): most-recent 50 by ts; gate-prefixed.
        gate_prefix = _GATE_PREFIX.get(gate, gate[:2])
        sig_with_ts.sort(key=lambda x: x[1], reverse=True)
        salted_ids = [
            salt_finding_id(salt, sig, gate_prefix)
            for sig, _ts in sig_with_ts
        ]
        # De-dup while preserving most-recent-first order.
        seen_ids: set[str] = set()
        deduped: list[str] = []
        for sid in salted_ids:
            if sid in seen_ids:
                continue
            seen_ids.add(sid)
            deduped.append(sid)
        capped_ids, truncated = soft_cap_finding_ids(deduped, cap=50)
        if truncated:
            safe_log("truncated_finding_ids", count=truncated)

        # last_artifact_created_at: minute-truncated (Δ2).
        if max_created_at_min:
            last_artifact_created_at = max_created_at_min
        else:
            last_artifact_created_at = "1970-01-01T00:00:00Z"

        persona_hash = _persona_content_hash(personas_root, gate, persona)

        runs_in_window_for_schema = min(runs_in_window, 45)
        insufficient_sample = runs_in_window_for_schema < 3

        row = {
            "schema_version": 1,
            "persona": persona,
            "gate": gate,
            "runs_in_window": runs_in_window_for_schema,
            "window_size": 45,
            "cost_runs_in_window": cost_runs_in_window,
            "run_state_counts": run_state_counts,
            "total_emitted": total_emitted,
            "total_judge_retained": total_judge_retained,
            "total_downstream_survived": total_downstream_survived,
            "total_unique": total_unique,
            "silent_runs_count": silent_runs_count,
            "total_tokens": total_tokens,
            "judge_retention_ratio": judge_retention_ratio,
            "downstream_survival_rate": downstream_survival_rate,
            "uniqueness_rate": uniqueness_rate,
            "avg_tokens_per_invocation": avg_tokens_per_invocation,
            "last_artifact_created_at": last_artifact_created_at,
            "persona_content_hash": persona_hash,
            "contributing_finding_ids": capped_ids,
            "truncated_count": truncated,
            "insufficient_sample": insufficient_sample,
        }
        rows_out.append(row)

    return rows_out


# --------------------------------------------------------------------------
# Task 1.8 — Emit + bundle
# --------------------------------------------------------------------------

def _atomic_write_text(path: Path, body: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(
        prefix=".compute-persona-value.",
        suffix=".tmp",
        dir=str(path.parent),
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(body)
        os.replace(tmp_path, str(path))
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


def _load_allowlist_schema() -> dict:
    schema_path = _HERE.parent / "schemas" / "persona-rankings.allowlist.json"
    with open(schema_path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def emit_rankings(rows: list[dict], output_path: Path) -> None:
    """Validate + emit rankings JSONL atomically + sibling JS bundle.

    Validation: every row must satisfy persona-rankings.allowlist.json
    (additionalProperties: false at every level). On any violation, raise
    ValueError with the violation list — refuse to write a partially-valid
    file.

    Sort: rows are sorted by (gate, persona) before emit for byte-stable
    diff under idempotent re-runs.
    """
    schema = _load_allowlist_schema()
    for i, row in enumerate(rows):
        violations = _allowlist_validator.validate(row, schema)
        if violations:
            raise ValueError(
                "rankings row {} failed allowlist: {}".format(
                    i, "; ".join(violations)
                )
            )

    sorted_rows = sorted(rows, key=lambda r: (r["gate"], r["persona"]))

    # JSONL emit.
    lines = [
        json.dumps(r, sort_keys=True, ensure_ascii=False)
        for r in sorted_rows
    ]
    body = "\n".join(lines) + ("\n" if lines else "")
    _atomic_write_text(output_path, body)

    # Sibling JS bundle for file:// dashboard load.
    bundle_path = output_path.parent / "persona-rankings-bundle.js"
    generated_at = _dt.datetime.now(tz=_dt.timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )
    bundle_body = (
        "// AUTOGENERATED by scripts/compute-persona-value.py — do not "
        "edit.\n"
        "// Loaded via <script src> under file:// (no fetch).\n"
        "window.__PERSONA_RANKINGS = "
        + json.dumps(sorted_rows, indent=2, sort_keys=True, ensure_ascii=False)
        + ";\n"
        + 'window.__PERSONA_RANKINGS_GENERATED_AT = "{}";\n'.format(
            generated_at
        )
    )
    _atomic_write_text(bundle_path, bundle_body)

    # Roster sidecar refresh.
    roster_path = output_path.parent / "persona-roster.js"
    roster_rows = _roster.walk_roster()
    _roster.emit_roster_sidecar(roster_rows, roster_path)

    safe_log("wrote_rankings", count=len(sorted_rows))


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------

_HELP_EPILOG = """\
Project Discovery cascade (security tier 3 paths require confirmation):

  Tier 1 — current repo: always on if cwd has docs/specs/. No flag needed.

  Tier 2 — explicit config: ${XDG_CONFIG_HOME:-$HOME/.config}/monsterflow/projects
           One absolute path per line. `#` comments + blank lines ignored.
           Missing entries are logged (counts only) and skipped.

  Tier 3 — --scan-projects-root <dir>: walks <dir>/*/docs/specs/. First use
           prompts y/N to append <dir> to ${XDG_CONFIG_HOME:-$HOME/.config}/monsterflow/scan-roots.confirmed.
           Subsequent runs skip the prompt. Non-tty (tmux pipe-pane,
           dashboard-append.sh, autorun): refuses silently — use
           --confirm-scan-roots <dir> from a real terminal first.

           Per-project opt-out: place an empty `.monsterflow-no-scan` file
           at any project root to exclude it from tier 3 cascade.

  --confirm-scan-roots <dir>: non-interactive companion to tier 3. Appends
           <dir> to scan-roots.confirmed without prompting. Repeatable.
           Idempotent (re-adding is a no-op).

Telemetry: every invocation writes a counts-only stderr line. Set
MONSTERFLOW_DEBUG_PATHS=1 to log adopter-facing paths to
~/.cache/monsterflow/debug.log (machine-local; never gitignored because
it lives outside the repo).
"""


def _build_parser():
    p = argparse.ArgumentParser(
        prog="compute-persona-value.py",
        description=(
            "Compute per-(persona, gate) value + cost rankings across "
            "discovered MonsterFlow projects. Emits "
            "dashboard/data/persona-rankings.jsonl + sidecar bundles."
        ),
        epilog=_HELP_EPILOG,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument(
        "--scan-projects-root",
        action="append",
        default=[],
        metavar="<dir>",
        help=(
            "Repeatable. Walks <dir>/*/docs/specs/. First use prompts y/N "
            "to confirm; subsequent runs skip. Non-tty refuses — use "
            "--confirm-scan-roots first."
        ),
    )
    p.add_argument(
        "--confirm-scan-roots",
        action="append",
        default=[],
        metavar="<dir>",
        help=(
            "Repeatable. M6 non-interactive companion to --scan-projects-"
            "root. Appends <dir> to scan-roots.confirmed without "
            "prompting. Idempotent."
        ),
    )
    p.add_argument(
        "--best-effort",
        action="store_true",
        help=(
            "Downgrade A1.5 (parent-annotation vs subagent-sum) "
            "disagreement from a hard exit to a warning."
        ),
    )
    p.add_argument(
        "--out",
        default="dashboard/data/persona-rankings.jsonl",
        metavar="PATH",
        help="Output path for rankings JSONL (default: %(default)s).",
    )
    p.add_argument(
        "--dry-run",
        action="store_true",
        help=(
            "Compute discovery and walks; write nothing. Subsumes the "
            "removed --list-projects flag (per M5 — paths-in-stdout was a "
            "privacy contradiction with counts-only telemetry)."
        ),
    )
    p.add_argument(
        "--explain",
        metavar="PERSONA[:GATE]",
        default=None,
        help=(
            "Emit a per-row breakdown for one persona (optionally one "
            "gate) to stderr. Stage 1B+ implementation."
        ),
    )
    p.add_argument(
        "--accept-salt-reset",
        action="store_true",
        help=(
            "Opt-in: when the finding-id-salt fails validation "
            "(corruption, perm change, truncation), regenerate it and "
            "clear dashboard/data/persona-rankings.jsonl. Without this "
            "flag the script refuses to destroy drill-down history. "
            "MF-3 from /check verdict."
        ),
    )
    return p


def main(argv=None):
    parser = _build_parser()
    args = parser.parse_args(argv)

    # M6 — handle --confirm-scan-roots first; it can run standalone (no
    # discovery needed) or alongside other flags.
    if args.confirm_scan_roots:
        rc = confirm_scan_roots(args.confirm_scan_roots)
        # If the user ONLY passed --confirm-scan-roots (no scan/explain/
        # value-walk intent), exit here so the call is a clean
        # configuration-only operation.
        only_confirmed = (
            not args.scan_projects_root
            and not args.explain
            and not args.dry_run
        )
        if only_confirmed:
            return rc

    # Validate --scan-projects-root entries up front; drop invalid ones.
    scan_roots = []
    for raw in args.scan_projects_root:
        v = validate_project_root(raw)
        if v is not None:
            scan_roots.append(v)

    # Tier 3 confirmation flow: interactive vs non-interactive.
    # SEC-2 — tmux pipe-pane defeats the Δ4 paths-only-in-prompt contract.
    # Detect via TMUX_PANE / TMUX env vars combined with a session log
    # likely to be capturing this pane. Conservative: if TMUX is set AND
    # stdout/stderr is not a terminal, treat as captured and refuse the
    # path-bearing interactive prompt path.
    confirmed = _read_confirmed_scan_roots()
    is_tty = sys.stdin.isatty() if hasattr(sys.stdin, "isatty") else False
    in_tmux_pipe = bool(os.environ.get("TMUX")) and not (
        sys.stderr.isatty() if hasattr(sys.stderr, "isatty") else False
    )
    unconfirmed = [r for r in scan_roots if str(r) not in confirmed]
    if unconfirmed and in_tmux_pipe:
        safe_log("tmux_pipe_pane_refused", count=len(unconfirmed))
        is_tty = False  # force the non-interactive branch below
    if unconfirmed and not is_tty:
        # Non-tty: emit the self-diagnostic and treat all unconfirmed as
        # refused inside discover_projects().
        sys.stderr.write(
            "[persona-value] non-interactive stdin detected; cannot "
            "prompt to confirm scan-roots. Use --confirm-scan-roots "
            "<dir> from a real terminal first, or run interactively, "
            "then re-invoke /wrap-insights.\n"
        )
        confirmed_only = True
    elif unconfirmed and is_tty:
        # Interactive: paths-allowed bootstrap (per spec — interactive
        # bootstrap, not steady state). For Stage 1A we keep this minimal
        # and refuse-by-default; full prompt UX is part of Stage 1B work.
        # For now, surface what would be added and require the explicit
        # --confirm-scan-roots companion to actually persist the choice.
        sys.stderr.write(
            "[persona-value] {} unconfirmed scan-root(s) provided; "
            "skipping until you re-run with --confirm-scan-roots <dir>. "
            "(Interactive y/N prompt is wired in Stage 1B.)\n".format(
                len(unconfirmed)
            )
        )
        confirmed_only = True
    else:
        confirmed_only = False

    projects = discover_projects(scan_roots, confirmed_only=confirmed_only)

    # Cost walk — value walk dictates an mtime floor; pick a wide pad
    # (24h) below the earliest value-side run.json created_at.
    value_records = value_walk(projects)
    earliest_ts = ""
    for rec in value_records:
        ts = rec.get("created_at") or ""
        if ts and (not earliest_ts or ts < earliest_ts):
            earliest_ts = ts
    mtime_floor: float | None = None
    if earliest_ts:
        try:
            dt = _dt.datetime.fromisoformat(
                earliest_ts.replace("Z", "+00:00")
            )
            mtime_floor = dt.timestamp() - 86400
        except ValueError:
            mtime_floor = None

    cost_dispatches = cost_walk(mtime_floor=mtime_floor)

    # A1.5 cross-check (forcing function for spike Q1).
    a15_crosscheck(cost_dispatches, best_effort=args.best_effort)

    # A1.6 (MF-2) — persona-regex match-rate threshold.
    a16_attribution_match_rate(
        cost_dispatches, threshold=0.95, best_effort=args.best_effort
    )

    # Salt — required even on dry-run so any regen-induced reset happens
    # deterministically (otherwise a dry-run could mask a salt-corruption
    # signal). MF-3: destructive regen gated on --accept-salt-reset.
    salt = get_or_create_salt(accept_salt_reset=args.accept_salt_reset)

    rows = aggregate_rankings(value_records, cost_dispatches, salt)

    if args.dry_run:
        # Dry-run: discovery counts already emitted via safe_log; do not
        # write paths to stdout (privacy — that's why --list-projects was
        # removed per M5). Adopters who want path-level debug set
        # MONSTERFLOW_DEBUG_PATHS=1 (Stage 1B wires the debug log).
        return 0

    output_path = Path(args.out)
    if not output_path.is_absolute():
        output_path = Path.cwd() / output_path
    emit_rankings(rows, output_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
