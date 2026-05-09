#!/bin/bash
##############################################################################
# scripts/autorun/run.sh — single-slug autorun orchestrator (v6 contract)
#
# Contract: docs/specs/autorun-overnight-policy/spec.md (v5, 26 ACs)
# Plan:     docs/specs/autorun-overnight-policy/plan.md (v6, Task 3.1)
# API:      docs/specs/autorun-overnight-policy/API_FREEZE.md
#
# Usage:
#   scripts/autorun/run.sh --mode=overnight|supervised [--dry-run] <slug>
#   scripts/autorun/run.sh --help
#
# Pipeline: spec-review → risk-analysis → plan → check → branch-setup → build
#           → pr-creation → codex-review → merging → complete
#
# Exit codes:
#   0   success / clean halt
#   1   run halted by policy block (caller halts batch processing on this)
#   2   invalid invocation / config (fail-fast)
#   3   STOP-file detected (clean halt; bubble to autorun-batch.sh)
#
# Bash 3.2 compatible. Quoted path expansions everywhere. No ${arr[-1]}.
##############################################################################
set -uo pipefail

ENGINE_DIR="${ENGINE_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
PROJECT_DIR="${PROJECT_DIR:-$PWD}"

# ---------------------------------------------------------------------------
# Help text (AC#25 R18 visibility — verbatim language required)
# ---------------------------------------------------------------------------
print_help() {
  cat <<'HELP'
Usage: run.sh --mode=overnight|supervised [--dry-run] <slug>
       run.sh --help

Process exactly ONE queue spec slug through the autorun pipeline:
spec-review → risk-analysis → plan → check → build → PR → codex-review → merge.

Flags:
  --mode=overnight    Set verdict/branch/codex_probe/verify_infra policies to
                      "warn" (run-degraded mode; PR created, auto-merge gated
                      on RUN_DEGRADED=0 AND CODEX_HIGH_COUNT=0).
  --mode=supervised   Set the four overrideable axes to "block" (halts on any
                      non-clean outcome; default semantics for cron'd legacy).
  --dry-run           Stage scripts emit minimal stub artifacts; no Claude/
                      Codex API calls. Synthesis stub includes a check-verdict
                      fence so downstream extractors hit the happy path.
  --help              This message.

Per-axis env vars override the --mode preset:
  AUTORUN_VERDICT_POLICY      AUTORUN_BRANCH_POLICY
  AUTORUN_CODEX_PROBE_POLICY  AUTORUN_VERIFY_INFRA_POLICY
  (Values: "warn" or "block". Invalid values fail-fast at startup.)

Slug must match: ^[a-z0-9][a-z0-9-]{0,63}$  (lowercase alphanumeric + hyphens).

KNOWN v1 LIMITATION (R18):
  v1 fence extraction rejects multi-fence injection but does not authenticate
  a single check-verdict fence quoted from reviewed content. Do not use
  unattended auto-merge on untrusted prompt-bearing content until
  autorun-verdict-deterministic ships. See BACKLOG.md.

For multi-slug queue processing, use scripts/autorun/autorun-batch.sh.
HELP
}

# ---------------------------------------------------------------------------
# Argument parsing — fail-fast on invalid forms (AC#16)
# ---------------------------------------------------------------------------
MODE=""
DRY_RUN=0
SLUG=""
MODE_FROM_FLAG=0
CLI_MERGE_POLICY=""   # autorun-merge-policy v0.11.0 — empty unless --merge-policy / --auto-merge passed

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h)
      print_help
      exit 0
      ;;
    --mode=*)
      MODE="${1#--mode=}"
      MODE_FROM_FLAG=1
      shift
      ;;
    --mode)
      shift
      if [ "$#" -eq 0 ]; then
        echo "INVALID_FLAG: --mode requires a value (overnight|supervised)" >&2
        exit 2
      fi
      MODE="$1"
      MODE_FROM_FLAG=1
      shift
      ;;
    # autorun-merge-policy v0.11.0 — canonical CLI flag.
    --merge-policy=*)
      CLI_MERGE_POLICY="${1#--merge-policy=}"
      shift
      ;;
    --merge-policy)
      shift
      if [ "$#" -eq 0 ]; then
        echo "INVALID_FLAG: --merge-policy requires a value (pr|clean|validated)" >&2
        exit 2
      fi
      CLI_MERGE_POLICY="$1"
      shift
      ;;
    # Deprecated alias — emits stderr deprecation notice once at run start (D3).
    --auto-merge=*)
      CLI_MERGE_POLICY="${1#--auto-merge=}"
      echo "[autorun] DEPRECATED: --auto-merge= is the legacy spelling; prefer --merge-policy= (will be removed in a future major release)" >&2
      shift
      ;;
    --auto-merge)
      shift
      if [ "$#" -eq 0 ]; then
        echo "INVALID_FLAG: --auto-merge requires a value (pr|clean|validated)" >&2
        exit 2
      fi
      CLI_MERGE_POLICY="$1"
      echo "[autorun] DEPRECATED: --auto-merge is the legacy spelling; prefer --merge-policy (will be removed in a future major release)" >&2
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --)
      shift
      if [ "$#" -gt 0 ]; then SLUG="$1"; shift; fi
      break
      ;;
    -*)
      echo "INVALID_FLAG: unknown flag \"$1\"" >&2
      exit 2
      ;;
    *)
      if [ -z "$SLUG" ]; then
        SLUG="$1"
      else
        echo "INVALID_INVOCATION: multiple positional args; only one slug allowed (got \"$SLUG\" and \"$1\")" >&2
        echo "For multi-slug queue runs, use scripts/autorun/autorun-batch.sh" >&2
        exit 2
      fi
      shift
      ;;
  esac
done

# Validate --mode (allow empty when not supplied; D39 banner handles defaulting)
if [ -n "$MODE" ]; then
  case "$MODE" in
    overnight|supervised) : ;;
    *)
      echo "INVALID_FLAG: --mode=\"$MODE\" — must be \"overnight\" or \"supervised\"" >&2
      exit 2
      ;;
  esac
fi

# ---------------------------------------------------------------------------
# D39 startup banner — non-TTY + --mode absent.
# (SF-T4: emit BEFORE slug validation so adopters running cron'd run.sh with
#  no args get a visible nudge that semantics defaulted to supervised, even
#  when the slug arg is missing or malformed.)
# ---------------------------------------------------------------------------
if [ "$MODE_FROM_FLAG" -eq 0 ] && ! [ -t 0 ]; then
  cat >&2 <<'BANNER'
[autorun] WARNING: --mode not set; defaulting to supervised semantics.
                   For overnight cron, use --mode=overnight or autorun-batch.sh.
                   See CHANGELOG.md "External adopters: action required".
BANNER
fi

# Default mode when not specified — supervised (block-by-default)
if [ -z "$MODE" ]; then
  MODE="supervised"
fi

# ---------------------------------------------------------------------------
# Slug validation (AC#13-adjacent — slug shape per spec)
# ---------------------------------------------------------------------------
if [ -z "$SLUG" ]; then
  echo "INVALID_INVOCATION: missing required <slug> arg" >&2
  echo "Usage: run.sh --mode=overnight|supervised [--dry-run] <slug>" >&2
  exit 2
fi

if ! printf "%s" "$SLUG" | grep -Eq '^[a-z0-9][a-z0-9-]{0,63}$'; then
  echo "INVALID_INVOCATION: slug \"$SLUG\" does not match ^[a-z0-9][a-z0-9-]{0,63}\$" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# RUN_ID — uuidgen MUST be lowercased BEFORE AC#13 regex match (SF3)
# ---------------------------------------------------------------------------
if ! command -v uuidgen >/dev/null 2>&1; then
  echo "INVALID_INVOCATION: uuidgen required (install util-linux or BSD uuidgen)" >&2
  exit 2
fi
RUN_ID="$(uuidgen | tr 'A-Z' 'a-z')"

# AC#13 regex (lowercase hex uuid4 form)
if ! printf "%s" "$RUN_ID" | grep -Eq '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'; then
  echo "INVALID_INVOCATION: generated RUN_ID \"$RUN_ID\" failed AC#13 regex" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Common paths + sourced helpers
# ---------------------------------------------------------------------------
QUEUE_DIR="$PROJECT_DIR/queue"
CONFIG_FILE="$QUEUE_DIR/autorun.config.json"
RUNS_DIR="$QUEUE_DIR/runs"
RUN_DIR="$RUNS_DIR/$RUN_ID"
LOCKS_DIR="$RUNS_DIR/.locks"
LOCKFILE="$LOCKS_DIR/$SLUG.lock"
CURRENT_SYMLINK="$RUNS_DIR/current"
STATE_FILE="$RUN_DIR/run-state.json"
MORNING_JSON="$RUN_DIR/morning-report.json"
MORNING_MD="$RUN_DIR/morning-report.md"

mkdir -p "$RUN_DIR" "$LOCKS_DIR"

AUTORUN=1
AUTORUN_DRY_RUN="$DRY_RUN"
AUTORUN_VERSION="$(tr -d '[:space:]' < "$ENGINE_DIR/VERSION" 2>/dev/null || echo 'unknown')"
AUTORUN_RUN_STATE="$STATE_FILE"
AUTORUN_RUN_DIR="$RUN_DIR"
AUTORUN_RUN_ID="$RUN_ID"
AUTORUN_MODE="$MODE"
export QUEUE_DIR CONFIG_FILE AUTORUN AUTORUN_DRY_RUN AUTORUN_VERSION
export ENGINE_DIR PROJECT_DIR AUTORUN_RUN_STATE AUTORUN_RUN_DIR AUTORUN_RUN_ID AUTORUN_MODE
export SLUG

# Apply --mode preset BEFORE sourcing _policy.sh so policy_for_axis sees the
# right env hints for cli-mode resolution. Per-axis env vars set by the caller
# already take precedence (we don't overwrite if set).
apply_mode_preset() {
  local target="warn"
  case "$MODE" in
    overnight) target="warn" ;;
    supervised) target="block" ;;
  esac
  : "${AUTORUN_VERDICT_POLICY:=$target}"
  : "${AUTORUN_BRANCH_POLICY:=$target}"
  : "${AUTORUN_CODEX_PROBE_POLICY:=$target}"
  : "${AUTORUN_VERIFY_INFRA_POLICY:=$target}"
  export AUTORUN_VERDICT_POLICY AUTORUN_BRANCH_POLICY \
         AUTORUN_CODEX_PROBE_POLICY AUTORUN_VERIFY_INFRA_POLICY
}
apply_mode_preset

# Validate any env-var policies BEFORE sourcing helpers (fail-fast).
for v in AUTORUN_VERDICT_POLICY AUTORUN_BRANCH_POLICY \
         AUTORUN_CODEX_PROBE_POLICY AUTORUN_VERIFY_INFRA_POLICY; do
  val="$(eval "printf %s \"\${$v:-}\"")"
  case "$val" in
    warn|block) : ;;
    *)
      echo "INVALID_CONFIG: $v=\"$val\" — must be \"warn\" or \"block\"" >&2
      exit 2
      ;;
  esac
done

# AUTORUN_INTEGRITY_POLICY / AUTORUN_SECURITY_POLICY do NOT exist (hardcoded).
if [ -n "${AUTORUN_INTEGRITY_POLICY:-}" ] || [ -n "${AUTORUN_SECURITY_POLICY:-}" ]; then
  echo "INVALID_CONFIG: AUTORUN_INTEGRITY_POLICY and AUTORUN_SECURITY_POLICY are hardcoded \"block\" and cannot be overridden" >&2
  exit 2
fi

# Source defaults (timeouts, test-cmd, etc.). This is sourced for downstream stages.
# shellcheck disable=SC1090
source "$ENGINE_DIR/scripts/autorun/defaults.sh"

# Source policy helper. _policy.sh fails fast if python3 missing (R14).
# shellcheck disable=SC1090
source "$ENGINE_DIR/scripts/autorun/_policy.sh"

# ---------------------------------------------------------------------------
# Source-of-truth state init helpers (Python — atomic via os.replace)
# ---------------------------------------------------------------------------
init_run_state() {
  local started_at
  started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  # Resolve every axis via policy_for_axis (single source of truth for source).
  # Source detection: prefer env > cli-mode > config > hardcoded.
  resolve_source() {
    local axis="$1" upper env_var
    upper="$(printf "%s" "$axis" | tr 'a-z' 'A-Z')"
    env_var="AUTORUN_${upper}_POLICY"
    # If env var set BEFORE we applied the preset (caller-set), it's "env".
    # We can't easily tell apart env-set-by-caller vs apply_mode_preset since
    # we used := to assign defaults. Approximation: if MODE_FROM_FLAG and the
    # current value matches the mode preset, label "cli-mode"; otherwise "env".
    # For integrity/security, always "hardcoded".
    case "$axis" in
      integrity|security_findings) printf "hardcoded"; return 0 ;;
    esac
    # Heuristic: $_AUTORUN_AXIS_PRESOURCE_<UPPER> stamped before apply_mode_preset
    local pre_var="_AUTORUN_AXIS_PRESOURCE_${upper}"
    local pre_val
    pre_val="$(eval "printf %s \"\${$pre_var:-}\"")"
    if [ -n "$pre_val" ]; then
      printf "env"
      return 0
    fi
    if [ "$MODE_FROM_FLAG" -eq 1 ]; then
      printf "cli-mode"
      return 0
    fi
    # Could be config or hardcoded; we let policy_for_axis distinguish via lookup.
    if [ -f "$CONFIG_FILE" ]; then
      local cfg_val
      cfg_val="$(python3 "$ENGINE_DIR/scripts/autorun/_policy_json.py" get "$CONFIG_FILE" "/policies/$axis" --default "" 2>/dev/null || true)"
      case "$cfg_val" in
        warn|block) printf "config"; return 0 ;;
      esac
    fi
    printf "hardcoded"
  }

  local v_verdict v_branch v_codex v_verify v_integrity v_security
  v_verdict="$(policy_for_axis verdict)"
  v_branch="$(policy_for_axis branch)"
  v_codex="$(policy_for_axis codex_probe)"
  v_verify="$(policy_for_axis verify_infra)"
  v_integrity="block"
  v_security="block"

  local s_verdict s_branch s_codex s_verify
  s_verdict="$(resolve_source verdict)"
  s_branch="$(resolve_source branch)"
  s_codex="$(resolve_source codex_probe)"
  s_verify="$(resolve_source verify_infra)"

  # Hand-write atomically via python (stdlib).
  python3 - "$STATE_FILE" \
    "$RUN_ID" "$SLUG" "$started_at" "autorun/$SLUG" \
    "$v_verdict" "$s_verdict" \
    "$v_branch" "$s_branch" \
    "$v_codex" "$s_codex" \
    "$v_verify" "$s_verify" \
    "$v_integrity" \
    "$v_security" <<'PY'
import json, os, sys

(state_file, run_id, slug, started_at, branch_owned,
 v_verdict, s_verdict,
 v_branch, s_branch,
 v_codex, s_codex,
 v_verify, s_verify,
 v_integrity,
 v_security) = sys.argv[1:]

state = {
    "schema_version": 1,
    "run_id": run_id,
    "slug": slug,
    "started_at": started_at,
    "branch_owned": branch_owned,
    "current_stage": "spec-review",
    "warnings": [],
    "blocks": [],
    "policy_resolution": {
        "verdict":            {"value": v_verdict,    "source": s_verdict},
        "branch":             {"value": v_branch,     "source": s_branch},
        "codex_probe":        {"value": v_codex,      "source": s_codex},
        "verify_infra":       {"value": v_verify,     "source": s_verify},
        "integrity":          {"value": v_integrity,  "source": "hardcoded"},
        "security_findings":  {"value": v_security,   "source": "hardcoded"},
    },
    "codex_high_count": 0,
}

tmp = state_file + ".tmp"
with open(tmp, "w") as f:
    json.dump(state, f, indent=2)
    f.write("\n")
os.replace(tmp, state_file)
PY
}

# Stamp pre-source for env-policy detection (so cli-mode vs env resolves correctly).
# Done BEFORE apply_mode_preset would overwrite — but that already ran. We
# capture explicitly here from the original env names if they were set ahead
# of the script. Since apply_mode_preset uses :=, the caller-set values are
# preserved; we approximate "was-set-by-caller" by checking whether the
# pre-mode resolution differs from the mode preset.
# (For test-correctness, this heuristic is acceptable; full attribution is
# deferred to the explicit precedence test in 5.2.)

# ---------------------------------------------------------------------------
# Atomic symlink rotation (spike finding 2 — mv -fh BSD / mv -fT GNU)
# ---------------------------------------------------------------------------
rotate_current_symlink() {
  local tmp="$CURRENT_SYMLINK.tmp.$$.$RANDOM"
  ln -s "$RUN_ID" "$tmp"
  if mv -fh "$tmp" "$CURRENT_SYMLINK" 2>/dev/null; then
    return 0
  fi
  if mv -fT "$tmp" "$CURRENT_SYMLINK" 2>/dev/null; then
    return 0
  fi
  rm -f "$tmp" 2>/dev/null || true
  echo "[autorun] error: symlink rotation requires mv -fh (BSD) or mv -fT (GNU)" >&2
  exit 2
}

# ---------------------------------------------------------------------------
# Slug-scoped lockfile (D20: PID + lstart). flock file-form (spike finding 1),
# fall back to mkdir-based lock if flock unavailable.
# ---------------------------------------------------------------------------
LOCK_HELD=0
LOCK_KIND=""

acquire_lock() {
  local lstart
  lstart="$(ps -o lstart= -p $$ 2>/dev/null | sed -E 's/^[ ]+|[ ]+$//g; s/[ ]+/ /g')"
  local payload
  payload="pid=$$ lstart=\"$lstart\" run_id=$RUN_ID started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  # If lockfile exists, check liveness.
  if [ -f "$LOCKFILE" ]; then
    local prev
    prev="$(cat "$LOCKFILE" 2>/dev/null || true)"
    local prev_pid
    prev_pid="$(printf "%s" "$prev" | sed -nE 's/^pid=([0-9]+).*/\1/p')"
    if [ -n "$prev_pid" ] && kill -0 "$prev_pid" 2>/dev/null; then
      # Verify lstart matches to avoid PID-recycle false-positives (D20).
      local prev_lstart cur_lstart
      prev_lstart="$(printf "%s" "$prev" | sed -nE 's/.*lstart="([^"]+)".*/\1/p')"
      cur_lstart="$(ps -o lstart= -p "$prev_pid" 2>/dev/null | sed -E 's/^[ ]+|[ ]+$//g; s/[ ]+/ /g')"
      if [ -n "$prev_lstart" ] && [ "$prev_lstart" = "$cur_lstart" ]; then
        echo "[autorun] another run in progress (pid=$prev_pid, started=$prev_lstart); aborting" >&2
        exit 2
      fi
      echo "[autorun] WARN: lockfile pid=$prev_pid alive but lstart mismatch (PID recycle) — acquiring" >&2
    else
      echo "[autorun] WARN: stale lockfile (pid=$prev_pid not alive) — acquiring" >&2
    fi
  fi

  # Atomic write of lockfile contents.
  if command -v flock >/dev/null 2>&1; then
    LOCK_KIND=flock
    PAYLOAD="$payload" LOCKFILE_PATH="$LOCKFILE" \
      flock -nx "$LOCKFILE.flock" -c \
      'printf "%s\n" "$PAYLOAD" > "$LOCKFILE_PATH"' \
      || {
        echo "[autorun] failed to acquire lockfile lock at $LOCKFILE.flock" >&2
        exit 2
      }
  else
    LOCK_KIND=mkdir
    local lockdir="$LOCKFILE.d"
    if ! mkdir "$lockdir" 2>/dev/null; then
      echo "[autorun] another run holds $lockdir (no flock available); aborting" >&2
      exit 2
    fi
    printf "%s\n" "$payload" > "$LOCKFILE"
  fi
  LOCK_HELD=1
}

release_lock() {
  [ "$LOCK_HELD" -eq 1 ] || return 0
  rm -f "$LOCKFILE" 2>/dev/null || true
  rm -f "$LOCKFILE.flock" 2>/dev/null || true
  if [ "$LOCK_KIND" = "mkdir" ]; then
    rmdir "$LOCKFILE.d" 2>/dev/null || true
  fi
  LOCK_HELD=0
}

# ---------------------------------------------------------------------------
# Stage tracking — exports AUTORUN_CURRENT_STAGE per AC#26 (SF-T3)
# ---------------------------------------------------------------------------
update_stage() {
  local stage="$1"
  AUTORUN_CURRENT_STAGE="$stage"
  export AUTORUN_CURRENT_STAGE
  printf "%s\n" "$stage" > "$RUN_DIR/.current-stage"
  log_run "$stage" 0
  # Best-effort update of run-state.json's current_stage (ignore failure).
  python3 - "$STATE_FILE" "$stage" 2>/dev/null <<'PY' || true
import json, os, sys
fp, stage = sys.argv[1], sys.argv[2]
try:
    with open(fp) as f:
        d = json.load(f)
    d["current_stage"] = stage
    tmp = fp + ".tmp"
    with open(tmp, "w") as f:
        json.dump(d, f, indent=2)
        f.write("\n")
    os.replace(tmp, fp)
except Exception:
    pass
PY
}

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log_run() {
  local stage="$1" exit_code="$2"
  echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"run_id\":\"$RUN_ID\",\"slug\":\"$SLUG\",\"stage\":\"$stage\",\"exit_code\":$exit_code}" \
    >> "$QUEUE_DIR/run.log" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Morning report renderer (D21 — inlined)
# ---------------------------------------------------------------------------
FINAL_STATE=""        # "merged" | "pr-awaiting-review" | "halted-at-stage" | "completed-no-pr"
PR_URL_VAL=""
PR_CREATED=0
MERGED=0
MERGE_CAPABLE=0
CODEX_HIGH_COUNT=0

render_morning_report() {
  # Defensive: if state file missing (very early failure), write a minimal one.
  if [ ! -f "$STATE_FILE" ]; then
    return 0
  fi

  local completed_at
  completed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  # Derive RUN_DEGRADED from warnings count (sticky, len > 0).
  local warnings_count
  warnings_count="$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(len(d.get('warnings',[])))" 2>/dev/null || echo 0)"
  local blocks_count
  blocks_count="$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(len(d.get('blocks',[])))" 2>/dev/null || echo 0)"

  local run_degraded=false
  if [ "$warnings_count" -gt 0 ]; then run_degraded=true; fi

  # Default final_state derivation when caller didn't set it explicitly.
  if [ -z "$FINAL_STATE" ]; then
    if [ "$blocks_count" -gt 0 ]; then
      FINAL_STATE="halted-at-stage"
    elif [ "$PR_CREATED" -eq 1 ] && [ "$MERGED" -eq 1 ]; then
      FINAL_STATE="merged"
    elif [ "$PR_CREATED" -eq 1 ]; then
      FINAL_STATE="pr-awaiting-review"
    else
      FINAL_STATE="completed-no-pr"
    fi
  fi

  python3 - "$STATE_FILE" "$MORNING_JSON" "$MORNING_MD" \
    "$completed_at" "$FINAL_STATE" \
    "$PR_URL_VAL" "$PR_CREATED" "$MERGED" "$MERGE_CAPABLE" \
    "$run_degraded" "$CODEX_HIGH_COUNT" <<'PY'
import json, os, sys

(state_path, json_out, md_out,
 completed_at, final_state,
 pr_url, pr_created, merged, merge_capable,
 run_degraded, codex_high_count) = sys.argv[1:]

with open(state_path) as f:
    state = json.load(f)

def b(s):
    return str(s).lower() in ("1", "true", "yes")

report = {
    "schema_version": 1,
    "run_id": state.get("run_id"),
    "slug": state.get("slug"),
    "branch_owned": state.get("branch_owned"),
    "started_at": state.get("started_at"),
    "completed_at": completed_at,
    "final_state": final_state,
    "pr_url": pr_url if pr_url else None,
    "pr_created": b(pr_created),
    "merged": b(merged),
    "merge_capable": b(merge_capable),
    "run_degraded": b(run_degraded),
    "warnings": state.get("warnings", []),
    "blocks": state.get("blocks", []),
    "policy_resolution": state.get("policy_resolution", {}),
    "pre_reset_recovery": state.get("pre_reset_recovery", {
        "occurred": False,
        "sha": None,
        "patch_path": None,
        "untracked_archive": None,
        "untracked_archive_size_bytes": None,
        "recovery_ref": None,
        "partial_capture": False,
    }),
}

# Atomic write of JSON.
tmp = json_out + ".tmp"
with open(tmp, "w") as f:
    json.dump(report, f, indent=2)
    f.write("\n")
os.replace(tmp, json_out)

# Render markdown companion.
def fmt_event(e):
    return "- [{}/{}] {} ({})".format(
        e.get("stage", "?"), e.get("axis", "?"),
        e.get("reason", ""), e.get("ts", ""),
    )

lines = []
lines.append("# Morning Report — {}".format(report["slug"] or "?"))
lines.append("")
lines.append("- **Run ID:** `{}`".format(report["run_id"]))
lines.append("- **Branch:** `{}`".format(report["branch_owned"] or "(none)"))
lines.append("- **Started:** {}".format(report["started_at"]))
lines.append("- **Completed:** {}".format(report["completed_at"]))
lines.append("- **Final state:** **{}**".format(report["final_state"]))
lines.append("- **PR:** {}".format(report["pr_url"] or "(not created)"))
lines.append("- **Merged:** {}".format(report["merged"]))
lines.append("- **Merge-capable gate:** {}".format(report["merge_capable"]))
lines.append("- **Run degraded:** {}".format(report["run_degraded"]))
lines.append("")
lines.append("## Policy resolution")
for axis, resolved in (report.get("policy_resolution") or {}).items():
    lines.append("- **{}:** {} (source: {})".format(axis, resolved.get("value"), resolved.get("source")))
lines.append("")
warns = report.get("warnings") or []
lines.append("## Warnings ({})".format(len(warns)))
if warns:
    for e in warns:
        lines.append(fmt_event(e))
else:
    lines.append("(none)")
lines.append("")
blocks = report.get("blocks") or []
lines.append("## Blocks ({})".format(len(blocks)))
if blocks:
    for e in blocks:
        lines.append(fmt_event(e))
else:
    lines.append("(none)")
lines.append("")
recovery = report.get("pre_reset_recovery") or {}
if recovery.get("occurred"):
    lines.append("## Pre-reset recovery")
    lines.append("- **SHA:** `{}`".format(recovery.get("sha") or "(none)"))
    lines.append("- **Patch:** `{}`".format(recovery.get("patch_path") or "(none)"))
    lines.append("- **Untracked archive:** `{}`".format(recovery.get("untracked_archive") or "(none)"))
    lines.append("- **Recovery ref:** `{}`".format(recovery.get("recovery_ref") or "(none)"))
    if recovery.get("partial_capture"):
        lines.append("")
        lines.append("> WARNING: partial capture — some artifacts missing")
    lines.append("")

tmp_md = md_out + ".tmp"
with open(tmp_md, "w") as f:
    f.write("\n".join(lines))
    f.write("\n")
os.replace(tmp_md, md_out)
PY
}

# ---------------------------------------------------------------------------
# Trap — render morning-report on any exit (clean, error, STOP, signal).
# ---------------------------------------------------------------------------
RENDERED=0
on_exit() {
  local rc=$?
  if [ "$RENDERED" -eq 0 ]; then
    RENDERED=1
    render_morning_report || true
  fi
  release_lock
  exit "$rc"
}
trap on_exit EXIT INT TERM

# ---------------------------------------------------------------------------
# Acquire lock + create initial state + rotate symlink
# ---------------------------------------------------------------------------
acquire_lock
init_run_state
rotate_current_symlink

echo "[autorun] run.sh started (run_id=$RUN_ID slug=$SLUG mode=$MODE dry_run=$DRY_RUN version=$AUTORUN_VERSION)"

# ---------------------------------------------------------------------------
# write_failure_item — preserved from legacy run.sh for stage-failure paths
# (build.sh / spec-review.sh write their own failure.md; this is a safety net)
# ---------------------------------------------------------------------------
SPEC_FILE="$QUEUE_DIR/${SLUG}.spec.md"
ARTIFACT_DIR="$QUEUE_DIR/$SLUG"
mkdir -p "$ARTIFACT_DIR"
export SPEC_FILE ARTIFACT_DIR

# ---------------------------------------------------------------------------
# autorun-merge-policy v0.11.0 — policy resolution + drift check + banner.
#
# Order is load-bearing per the plan (W3.1-W3.4b):
#   1. Source helper (idempotent guard inside).
#   2. Drift check at run start (D5: NOT in autorun-batch.sh).
#   3. Resolve policy (CLI > spec > constitution > default(pr)).
#   4. Capture spec_sha (D8: git hash-object — once per run, immutable).
#   5. Capture FOLLOWUPS_BASELINE for slug (R1 guard's anchor — must be
#      sampled BEFORE any wave runs, so follow-ups added during this run
#      can be detected at merge dispatch).
#   6. Emit start-event row to queue/run.log (D22 / R2 — start row survives
#      mid-run crash).
#   7. Render the runtime-config banner (before Phase 0b dispatch).
# ---------------------------------------------------------------------------
# shellcheck disable=SC1090
source "$ENGINE_DIR/scripts/autorun/_merge_policy.sh"

# Drift check (D5/D6 + AC#13).
QUEUE_COPY="$SPEC_FILE"
CANONICAL_SPEC="$PROJECT_DIR/docs/specs/$SLUG/spec.md"
DRIFT_RC=0
queue_copy_drift_check "$CANONICAL_SPEC" "$QUEUE_COPY" || DRIFT_RC=$?
if [ "$DRIFT_RC" -eq 2 ]; then
  echo "[autorun] $SLUG: halted by queue-copy drift detector (privilege elevation)" >&2
  write_failure_item "drift-check" "queue elevates auto_merge_policy above canonical"
  exit 2
fi

# Policy resolution (CLI > spec > constitution > default).
RESOLVED=""
RESOLVED="$(merge_policy_resolve "$SPEC_FILE" "$CLI_MERGE_POLICY")" || {
  echo "[autorun] $SLUG: invalid auto_merge_policy — halting" >&2
  exit 2
}
RESOLVED_FROM="${RESOLVED%%:*}"
RESOLVED_POLICY="${RESOLVED#*:}"
export RESOLVED_FROM RESOLVED_POLICY

# Spec SHA — immutable for this run (D8).
SPEC_SHA="$(git -C "$PROJECT_DIR" hash-object "$SPEC_FILE" 2>/dev/null || echo "unknown")"
export SPEC_SHA

# gate_mode for banner + dispatch — read from spec frontmatter directly (D14).
GATE_MODE=""
GATE_MODE_SOURCE="default"
GATE_MODE_FM="$(_gh_frontmatter_field "$SPEC_FILE" gate_mode 2>/dev/null || true)"
case "$GATE_MODE_FM" in
  strict|permissive) GATE_MODE="$GATE_MODE_FM"; GATE_MODE_SOURCE="frontmatter" ;;
  *) GATE_MODE="permissive" ;;
esac
export GATE_MODE GATE_MODE_SOURCE

# gate_max_recycles — read via existing helper (clamped 1..5).
MAX_RECYCLES_RAW="$(_gh_frontmatter_field "$SPEC_FILE" gate_max_recycles 2>/dev/null || true)"
case "$MAX_RECYCLES_RAW" in
  ''|*[!0-9]*) MAX_RECYCLES=2; MAX_RECYCLES_SOURCE="default" ;;
  *)           MAX_RECYCLES="$MAX_RECYCLES_RAW"; MAX_RECYCLES_SOURCE="spec" ;;
esac

# Agent budget — read existing config or default. account-type-agent-scaling owns this.
AGENT_BUDGET="${AGENT_BUDGET:-6}"
AGENT_BUDGET_SOURCE="default"
if [ -f "$CONFIG_FILE" ]; then
  AB_FROM_CFG="$(python3 "$ENGINE_DIR/scripts/autorun/_policy_json.py" get "$CONFIG_FILE" "/agent_budget" --default "" 2>/dev/null || true)"
  if [ -n "$AB_FROM_CFG" ]; then
    AGENT_BUDGET="$AB_FROM_CFG"
    AGENT_BUDGET_SOURCE="config"
  fi
fi

# Run log path (project-wide, slug-shared file).
RUN_LOG_PATH="$QUEUE_DIR/run.log"
export RUN_LOG_PATH

# Followups baseline — slug-scoped count BEFORE any wave runs (R1 anchor).
FOLLOWUPS_PATH="$PROJECT_DIR/docs/specs/$SLUG/followups.jsonl"
FOLLOWUPS_BASELINE="$(merge_policy_followups_count "$FOLLOWUPS_PATH" "$SLUG")"
export FOLLOWUPS_PATH FOLLOWUPS_BASELINE

# Validated → pr stderr-warn (one-line, banner-adjacent — AC#21).
if [ "$RESOLVED_POLICY" = "validated" ]; then
  echo "[autorun] $SLUG: WARN — validated policy not yet shipped; falling back to PR-only" >&2
fi

# Start-event row — written before any work runs (D22 / R2).
log_merge_policy_resolved "$RUN_LOG_PATH" "$SLUG" "$RESOLVED_POLICY" "$RESOLVED_FROM" \
  "$GATE_MODE" "$SPEC_SHA" "$RUN_ID"

# Banner — to stdout (R7); fires before Phase 0b dispatch (AC#10 ordering).
merge_policy_render_banner "$SLUG" \
  "$RESOLVED_POLICY" "$RESOLVED_FROM" \
  "$GATE_MODE" "$GATE_MODE_SOURCE" \
  "$AGENT_BUDGET" "$AGENT_BUDGET_SOURCE" \
  "$MAX_RECYCLES" "$MAX_RECYCLES_SOURCE"

write_failure_item() {
  local stage="$1" reason="$2"
  [ -f "$ARTIFACT_DIR/failure.md" ] && return 0
  cat > "$ARTIFACT_DIR/failure.md" <<FAIL_EOF
<!-- autorun:stage=$stage slug=$SLUG run_id=$RUN_ID -->
# Failure: $SLUG

**Stage:** $stage
**Reason:** $reason
**Timestamp:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
FAIL_EOF
}

# ---------------------------------------------------------------------------
# STOP file handling — render morning report and exit 3
# ---------------------------------------------------------------------------
check_stop() {
  if [ -f "$QUEUE_DIR/STOP" ]; then
    echo "[autorun] STOP file detected — halting cleanly" >&2
    FINAL_STATE="halted-at-stage"
    render_morning_report || true
    RENDERED=1
    release_lock
    exit 3
  fi
}

# ---------------------------------------------------------------------------
# DRY RUN notice
# ---------------------------------------------------------------------------
if [ "$DRY_RUN" -eq 1 ]; then
  echo "[autorun] DRY RUN mode — stage scripts emit stubs (no API calls)"
fi

# ---------------------------------------------------------------------------
# Stage 1: spec-review
# ---------------------------------------------------------------------------
check_stop
if [ -f "$ARTIFACT_DIR/review-findings.md" ]; then
  echo "[autorun] $SLUG: review-findings.md present — resuming past spec-review"
else
  update_stage "spec-review"
  STAGE_EXIT=0
  bash "$ENGINE_DIR/scripts/autorun/spec-review.sh" || STAGE_EXIT=$?
  log_run "spec-review" "$STAGE_EXIT"

  if [ "$STAGE_EXIT" -ne 0 ]; then
    echo "[autorun] $SLUG: spec-review failed (exit $STAGE_EXIT)" >&2
    write_failure_item "spec-review" "exit $STAGE_EXIT"
    FINAL_STATE="halted-at-stage"
    exit 1
  fi

  if [ ! -f "$ARTIFACT_DIR/review-findings.md" ]; then
    echo "[autorun] $SLUG: spec-review exited 0 but review-findings.md missing — failing" >&2
    write_failure_item "spec-review" "review-findings.md not produced"
    FINAL_STATE="halted-at-stage"
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Stage 1b: risk-analysis (non-fatal)
# ---------------------------------------------------------------------------
check_stop
if [ -f "$ARTIFACT_DIR/risk-findings.md" ]; then
  echo "[autorun] $SLUG: risk-findings.md present — resuming"
else
  update_stage "spec-review"  # remains under spec-review umbrella per STAGE enum
  STAGE_EXIT=0
  bash "$ENGINE_DIR/scripts/autorun/risk-analysis.sh" || STAGE_EXIT=$?
  log_run "risk-analysis" "$STAGE_EXIT"

  if [ "$STAGE_EXIT" -ne 0 ]; then
    echo "[autorun] $SLUG: risk-analysis failed (exit $STAGE_EXIT) — continuing without"
    printf '# Risk Analysis\n(risk-analysis failed — skipped)\n' > "$ARTIFACT_DIR/risk-findings.md" || true
  fi

  if [ -f "$ARTIFACT_DIR/risk-findings.md" ]; then
    {
      echo ""
      echo "---"
      echo "## Risk Analysis"
      echo ""
      cat "$ARTIFACT_DIR/risk-findings.md"
    } >> "$ARTIFACT_DIR/review-findings.md"
  fi
fi

# ---------------------------------------------------------------------------
# Stage 2: plan
# ---------------------------------------------------------------------------
check_stop
if [ -f "$ARTIFACT_DIR/plan.md" ]; then
  echo "[autorun] $SLUG: plan.md present — resuming"
else
  update_stage "plan"
  STAGE_EXIT=0
  bash "$ENGINE_DIR/scripts/autorun/plan.sh" || STAGE_EXIT=$?
  log_run "plan" "$STAGE_EXIT"
  if [ "$STAGE_EXIT" -ne 0 ]; then
    echo "[autorun] $SLUG: plan failed (exit $STAGE_EXIT)" >&2
    write_failure_item "plan" "exit $STAGE_EXIT"
    FINAL_STATE="halted-at-stage"
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Stage 3: check (gate)
# ---------------------------------------------------------------------------
check_stop
if [ -f "$ARTIFACT_DIR/check.md" ] && ! grep -qi "NO-GO\|NO_GO" "$ARTIFACT_DIR/check.md" 2>/dev/null; then
  echo "[autorun] $SLUG: check.md present (GO) — resuming"
else
  update_stage "check"
  STAGE_EXIT=0
  bash "$ENGINE_DIR/scripts/autorun/check.sh" || STAGE_EXIT=$?
  log_run "check" "$STAGE_EXIT"

  if [ "$STAGE_EXIT" -eq 2 ]; then
    echo "[autorun] $SLUG: check returned NO-GO" >&2
    write_failure_item "check" "NO-GO verdict"
    FINAL_STATE="halted-at-stage"
    exit 1
  elif [ "$STAGE_EXIT" -ne 0 ]; then
    echo "[autorun] $SLUG: check failed (exit $STAGE_EXIT)" >&2
    write_failure_item "check" "exit $STAGE_EXIT"
    FINAL_STATE="halted-at-stage"
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Stage 4: branch-setup + build
# (Branch reset is a destructive operation — gate under branch_policy with
#  pre-reset backup capture. Full four-artifact capture machinery is
#  implemented in build.sh per Task 3.3; here we only enforce the policy
#  gate around the reset call so the trigger sits under the policy axis.)
# ---------------------------------------------------------------------------
PRE_BUILD_SHA=""
WAVE_COUNT="0"

if [ -f "$ARTIFACT_DIR/build-log.md" ]; then
  echo "[autorun] $SLUG: build-log.md present — resuming"
  PRE_BUILD_SHA="$(cat "$ARTIFACT_DIR/pre-build-sha.txt" 2>/dev/null || echo "unknown")"
  WAVE_COUNT="$(grep -c "^## Wave" "$ARTIFACT_DIR/build-log.md" 2>/dev/null || true)"
  WAVE_COUNT="${WAVE_COUNT:-0}"
else
  check_stop
  update_stage "branch-setup"
  BRANCH_NAME="autorun/$SLUG"
  if [ "$DRY_RUN" -eq 0 ]; then
    git -C "$PROJECT_DIR" fetch origin main 2>/dev/null \
      && BASE_REF="origin/main" \
      || { echo "[autorun] $SLUG: WARN — could not fetch origin/main — using local main"; BASE_REF="main"; }

    if git -C "$PROJECT_DIR" rev-parse --verify "$BRANCH_NAME" >/dev/null 2>&1; then
      # Destructive reset gated under branch_policy. Build.sh (Task 3.3) is
      # responsible for the four-artifact backup capture; we set the policy
      # gate here so the gate sits at the trigger site.
      if ! policy_act branch "reset existing branch $BRANCH_NAME to $BASE_REF"; then
        echo "[autorun] $SLUG: branch_policy=block — refusing to reset existing branch" >&2
        write_failure_item "branch-setup" "branch_policy blocked reset of $BRANCH_NAME"
        FINAL_STATE="halted-at-stage"
        exit 1
      fi
      git -C "$PROJECT_DIR" checkout "$BRANCH_NAME"
      git -C "$PROJECT_DIR" reset --hard "$BASE_REF"
      echo "[autorun] $SLUG: reset existing branch $BRANCH_NAME to $BASE_REF"
    else
      git -C "$PROJECT_DIR" checkout -b "$BRANCH_NAME" "$BASE_REF"
      echo "[autorun] $SLUG: created branch $BRANCH_NAME from $BASE_REF"
    fi
  else
    echo "[autorun] $SLUG: DRY RUN — skipping branch setup"
  fi

  update_stage "build"
  STAGE_EXIT=0
  bash "$ENGINE_DIR/scripts/autorun/build.sh" || STAGE_EXIT=$?
  log_run "build" "$STAGE_EXIT"

  if [ "$STAGE_EXIT" -eq 3 ]; then
    echo "[autorun] $SLUG: build requested clean halt (STOP file)"
    FINAL_STATE="halted-at-stage"
    exit 3
  elif [ "$STAGE_EXIT" -ne 0 ]; then
    echo "[autorun] $SLUG: build failed (exit $STAGE_EXIT)" >&2
    FINAL_STATE="halted-at-stage"
    exit 1
  fi

  PRE_BUILD_SHA="$(cat "$ARTIFACT_DIR/pre-build-sha.txt" 2>/dev/null || echo "unknown")"
  WAVE_COUNT="$(grep -c "^## Wave" "$ARTIFACT_DIR/build-log.md" 2>/dev/null || true)"
  WAVE_COUNT="${WAVE_COUNT:-0}"
fi

# ---------------------------------------------------------------------------
# Stage 5: PR creation
# ---------------------------------------------------------------------------
check_stop
if [ -f "$ARTIFACT_DIR/pr-url.txt" ]; then
  echo "[autorun] $SLUG: pr-url.txt present — resuming"
  PR_URL_VAL="$(cat "$ARTIFACT_DIR/pr-url.txt")"
  PR_CREATED=1
elif [ "$DRY_RUN" -eq 1 ]; then
  echo "[autorun] $SLUG: DRY RUN — skipping PR creation"
else
  update_stage "pr-creation"

  PUSH_EXIT=0
  git -C "$PROJECT_DIR" push origin "autorun/$SLUG" 2>/dev/null || PUSH_EXIT=$?
  if [ "$PUSH_EXIT" -ne 0 ]; then
    echo "[autorun] $SLUG: WARN — failed to push branch (exit $PUSH_EXIT)" >&2
  fi

  TEST_CMD_DISPLAY="${TEST_CMD:-(empty — skipped)}"
  PR_REPO="$(cd "$PROJECT_DIR" && gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null \
    || git -C "$PROJECT_DIR" remote get-url origin 2>/dev/null \
       | sed -E 's|^git@github\.com:([^/]+/[^/]+)\.git$|\1|; s|^https://github\.com/([^/]+/[^/]+)\.git$|\1|; s|^https://github\.com/([^/]+/[^/]+)$|\1|')"

  # autorun-merge-policy v0.11.0 — PR conventions (D9):
  # - Title: [autorun] <slug>
  # - Body: includes verdict + run.log path + spec link
  # - Draft state: gated on verdict + dispatch outcome (decided AFTER PR body
  #   is constructed but BEFORE merge dispatch — see Stage 7).
  # - Label: `autorun`
  STAGE_EXIT=0
  PR_TITLE="[autorun] $SLUG"
  PR_URL_VAL="$(gh pr create \
      --repo "$PR_REPO" \
      --title "$PR_TITLE" \
      --label autorun \
      --body "$(cat <<PRBODY
## Summary
Automated implementation of \`$SLUG\` via autorun pipeline.

## Autorun Provenance
- **Run ID:** $RUN_ID
- **Slug:** $SLUG
- **Spec:** docs/specs/$SLUG/spec.md
- **Pre-build SHA:** $PRE_BUILD_SHA
- **Autorun version:** $AUTORUN_VERSION
- **Mode:** $MODE
- **Merge policy:** $RESOLVED_POLICY (resolved_from=$RESOLVED_FROM)
- **Gate mode:** $GATE_MODE (source=$GATE_MODE_SOURCE)
- **Wave count:** $WAVE_COUNT
- **Test cmd:** $TEST_CMD_DISPLAY
- **Timestamp (UTC):** $(date -u +%Y-%m-%dT%H:%M:%SZ)
- **Artifacts:** queue/$SLUG/{review-findings,plan,check,build-log}.md
- **Run log:** queue/run.log (audit JSONL)
PRBODY
)" \
      --base main \
      --head "autorun/$SLUG" \
      2>&1)" || STAGE_EXIT=$?

  if [ "$STAGE_EXIT" -eq 0 ] && [ -n "$PR_URL_VAL" ]; then
    echo "$PR_URL_VAL" > "$ARTIFACT_DIR/pr-url.txt"
    PR_CREATED=1
    echo "[autorun] $SLUG: PR created: $PR_URL_VAL"
    log_run "pr-creation" 0
  else
    # autorun-merge-policy D23 / R3 — gh pr create failure is now a
    # primary terminal action under default config. Record the failure
    # via the canonical end-event row + preserve branch + exit 0 to
    # match the contract for fell_back/branch_protection symmetry.
    echo "[autorun] $SLUG: PR creation failed (exit $STAGE_EXIT): $PR_URL_VAL" >&2
    log_run "pr-creation" 1
    log_merge_action_completed "$RUN_LOG_PATH" "$SLUG" merge_failed pr_create_failed "" "" "$RUN_ID"
    write_failure_item "pr-creation" "gh pr create failed (exit $STAGE_EXIT) — branch preserved"
    FINAL_STATE="completed-no-pr"
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# Stage 6: codex-review
#
# Codex availability + auth is delegated to _codex_probe.sh (AC#11 — single
# source for codex availability checks; no inline `command -v codex` allowed).
#
# Probe contract:
#   exit 0 — codex on PATH AND `codex login status` clean       → run review
#   exit 1 — codex binary not on PATH (unavailable)             → policy_act
#   exit 2 — codex present but `codex login status` non-zero    → policy_act
#
# Tests mock the probe via AUTORUN_CODEX_PROBE_BIN (one-line *_OVERRIDE env
# hook per feedback_path_stub_over_export_f memory).
# ---------------------------------------------------------------------------
check_stop
CODEX_OUTPUT_FILE="$ARTIFACT_DIR/codex-review.md"
CODEX_AVAILABLE=0
CODEX_PROBE_BIN="${AUTORUN_CODEX_PROBE_BIN:-$ENGINE_DIR/scripts/autorun/_codex_probe.sh}"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "[autorun] $SLUG: DRY RUN — skipping codex-review"
elif [ -f "$CODEX_OUTPUT_FILE" ]; then
  CODEX_AVAILABLE=1
  CODEX_HIGH_COUNT="$(grep -c '^\*\*High:\*\*' "$CODEX_OUTPUT_FILE" 2>/dev/null || true)"
  # Guard: integer-only (per autorun-shell-reviewer recommendation; matches
  # the canonical pattern in scripts/_gate_helpers.sh:111).
  case "$CODEX_HIGH_COUNT" in ''|*[!0-9]*) CODEX_HIGH_COUNT=0 ;; esac
else
  CODEX_PROBE_EXIT=0
  bash "$CODEX_PROBE_BIN" >/dev/null 2>&1 || CODEX_PROBE_EXIT=$?
  case "$CODEX_PROBE_EXIT" in
    0)
      update_stage "codex-review"
      echo "[autorun] $SLUG: running Codex review (timeout=${TIMEOUT_CODEX}s)"

      CODEX_EXIT=0
      CODEX_CONTEXT="$(mktemp -t "autorun-codex-ctx.XXXXXX")"
      {
        printf '## Git Diff (committed changes since pre-build SHA)\n'
        [ "$PRE_BUILD_SHA" != "unknown" ] && [ -n "$PRE_BUILD_SHA" ] && \
          git -C "$PROJECT_DIR" diff "$PRE_BUILD_SHA" HEAD -- . 2>/dev/null | head -2000 || \
          printf '(diff unavailable)\n'
        printf '\n## Build Log (last 100 lines)\n'
        tail -100 "$ARTIFACT_DIR/build-log.md" 2>/dev/null || true
      } > "$CODEX_CONTEXT"
      timeout "$TIMEOUT_CODEX" codex exec \
          --full-auto --ephemeral \
          --output-last-message "$CODEX_OUTPUT_FILE" \
          "Review this PR for correctness, security issues, and adherence to spec. For each finding, prefix with **High:**, **Medium:**, or **Low:**." \
          < "$CODEX_CONTEXT" \
          2>/dev/null || CODEX_EXIT=$?
      rm -f "$CODEX_CONTEXT"

      if [ "$CODEX_EXIT" -eq 0 ] && [ -f "$CODEX_OUTPUT_FILE" ]; then
        CODEX_AVAILABLE=1
        log_run "codex-review" 0
        CODEX_HIGH_COUNT="$(grep -c '^\*\*High:\*\*' "$CODEX_OUTPUT_FILE" 2>/dev/null || true)"
        case "$CODEX_HIGH_COUNT" in ''|*[!0-9]*) CODEX_HIGH_COUNT=0 ;; esac
        echo "[autorun] $SLUG: Codex High findings: $CODEX_HIGH_COUNT"
      else
        echo "[autorun] $SLUG: Codex review skipped/timed out (exit $CODEX_EXIT)" >&2
        log_run "codex-review" "$CODEX_EXIT"
        if ! policy_act codex_probe "codex review failed (exit $CODEX_EXIT)"; then
          FINAL_STATE="halted-at-stage"
          render_morning_report || true
          exit 1
        fi
      fi
      ;;
    1)
      echo "[autorun] $SLUG: codex unavailable: binary not on PATH" >&2
      log_run "codex-review" 1
      if ! policy_act codex_probe "codex unavailable: binary not on PATH"; then
        FINAL_STATE="halted-at-stage"
        render_morning_report || true
        exit 1
      fi
      ;;
    2)
      echo "[autorun] $SLUG: codex unavailable: auth-failed (codex login status non-zero)" >&2
      log_run "codex-review" 2
      if ! policy_act codex_probe "codex unavailable: auth-failed"; then
        FINAL_STATE="halted-at-stage"
        render_morning_report || true
        exit 1
      fi
      ;;
    *)
      echo "[autorun] $SLUG: codex probe returned unexpected exit $CODEX_PROBE_EXIT" >&2
      log_run "codex-review" "$CODEX_PROBE_EXIT"
      if ! policy_act codex_probe "codex unavailable: probe exit $CODEX_PROBE_EXIT"; then
        FINAL_STATE="halted-at-stage"
        render_morning_report || true
        exit 1
      fi
      ;;
  esac
fi

# Persist codex_high_count into run-state.json (best-effort).
if [ -f "$STATE_FILE" ]; then
  python3 - "$STATE_FILE" "$CODEX_HIGH_COUNT" 2>/dev/null <<'PY' || true
import json, os, sys
fp, hc = sys.argv[1], int(sys.argv[2])
with open(fp) as f:
    d = json.load(f)
d["codex_high_count"] = hc
tmp = fp + ".tmp"
with open(tmp, "w") as f:
    json.dump(d, f, indent=2)
    f.write("\n")
os.replace(tmp, fp)
PY
fi

# ---------------------------------------------------------------------------
# Auto-merge gate composition (AC#7):
#   merge_capable iff CODEX_HIGH_COUNT == 0 AND RUN_DEGRADED == 0
#                  AND verdict ∈ {GO, GO_WITH_FIXES}
# ---------------------------------------------------------------------------
check_stop

# RUN_DEGRADED derived from warnings count.
WARNINGS_COUNT="$(python3 -c "import json; print(len(json.load(open('$STATE_FILE')).get('warnings',[])))" 2>/dev/null || echo 0)"
RUN_DEGRADED=0
[ "$WARNINGS_COUNT" -gt 0 ] && RUN_DEGRADED=1

# Verdict from check-verdict.json (sidecar) when present; else from check.md first line.
VERDICT="GO"
SIDECAR="$PROJECT_DIR/docs/specs/$SLUG/check-verdict.json"
if [ -f "$SIDECAR" ]; then
  VERDICT="$(python3 "$ENGINE_DIR/scripts/autorun/_policy_json.py" get "$SIDECAR" "/verdict" --default "GO" 2>/dev/null || echo GO)"
elif [ -f "$ARTIFACT_DIR/check.md" ]; then
  if grep -qi "NO-GO\|NO_GO" "$ARTIFACT_DIR/check.md"; then
    VERDICT="NO_GO"
  fi
fi

MERGE_CAPABLE=0
if [ "$CODEX_HIGH_COUNT" -eq 0 ] && [ "$RUN_DEGRADED" -eq 0 ]; then
  case "$VERDICT" in
    GO|GO_WITH_FIXES) MERGE_CAPABLE=1 ;;
  esac
fi

# ---------------------------------------------------------------------------
# autorun-merge-policy v0.11.0 dispatch — replaces the legacy merge gate.
#
# Composition with existing four-axis gate (preserved):
#   merge_capable iff CODEX_HIGH_COUNT == 0 AND RUN_DEGRADED == 0
#                 AND verdict ∈ {GO, GO_WITH_FIXES}
#
# is_clean_for_merge() refines only the verdict portion under permissive mode
# (requires GO, not GO_WITH_FIXES) — see _merge_policy.sh.
# ---------------------------------------------------------------------------

# FOLLOWUPS_ADDED — line-diff on followups.jsonl for this slug between run-start
# baseline and merge dispatch (R1 anchor; D21).
FOLLOWUPS_NOW="$(merge_policy_followups_count "$FOLLOWUPS_PATH" "$SLUG")"
FOLLOWUPS_ADDED=$(( FOLLOWUPS_NOW - FOLLOWUPS_BASELINE ))
[ "$FOLLOWUPS_ADDED" -lt 0 ] && FOLLOWUPS_ADDED=0
export FOLLOWUPS_ADDED

# CODEX_RAN — SA-1 hardening. 1 iff probe exited 0 AND review file exists.
CODEX_RAN=0
if [ "$CODEX_AVAILABLE" = "1" ] && [ -f "$CODEX_OUTPUT_FILE" ]; then
  CODEX_RAN=1
fi

# Extract PR number for audit row (best-effort).
PR_NUMBER=""
if [ -n "${PR_URL_VAL:-}" ]; then
  PR_NUMBER="$(printf '%s' "$PR_URL_VAL" | sed -E 's|.*/pull/([0-9]+).*|\1|' | grep -E '^[0-9]+$' || true)"
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "[autorun] $SLUG: DRY RUN — skipping merge dispatch"
elif [ "$PR_CREATED" -ne 1 ]; then
  echo "[autorun] $SLUG: no PR — skipping merge dispatch"
else
  update_stage "merging"
  echo "[autorun] $SLUG: dispatching merge policy=$RESOLVED_POLICY resolved_from=$RESOLVED_FROM gate_mode=$GATE_MODE merge_capable=$MERGE_CAPABLE verdict=$VERDICT followups_added=$FOLLOWUPS_ADDED codex_ran=$CODEX_RAN"

  merge_policy_dispatch "$SLUG" "$PR_URL_VAL" "$RESOLVED_POLICY" "$RESOLVED_FROM" \
    "$GATE_MODE" "$MERGE_CAPABLE" "$VERDICT" "$FOLLOWUPS_ADDED" "$RUN_ID" \
    "$RUN_LOG_PATH" "$PR_NUMBER" "$CODEX_RAN"

  # Determine final-state from the just-written end-event (best-effort grep).
  LAST_ACTION="$(grep '"event": "merge_action_completed"' "$RUN_LOG_PATH" 2>/dev/null \
                  | grep "\"slug\": \"$SLUG\"" \
                  | grep "\"run_id\": \"$RUN_ID\"" \
                  | tail -1 \
                  | sed -E 's/.*"action": "([^"]+)".*/\1/' || echo "")"
  case "$LAST_ACTION" in
    auto_merged)
      MERGED=1
      echo "[autorun] $SLUG: auto-merged (or queued via gh --auto)"
      log_run "merge" 0
      ;;
    pr_only)
      echo "[autorun] $SLUG: PR opened (policy=$RESOLVED_POLICY) — no merge attempted"
      log_run "merge-skipped" 0
      ;;
    fell_back)
      echo "[autorun] $SLUG: merge fell back — PR left for manual review"
      log_run "merge-fell-back" 0
      FINAL_STATE="pr-awaiting-review"
      ;;
    merge_failed)
      echo "[autorun] $SLUG: merge failed — PR left open"
      log_run "merge-failed" 1
      FINAL_STATE="pr-awaiting-review"
      ;;
    *)
      echo "[autorun] $SLUG: WARN — could not parse final action from run.log"
      log_run "merge-unknown" 0
      ;;
  esac
fi

# ---------------------------------------------------------------------------
# Complete
# ---------------------------------------------------------------------------
update_stage "complete"
log_run "complete" 0

if [ -z "$FINAL_STATE" ]; then
  if [ "$MERGED" -eq 1 ]; then
    FINAL_STATE="merged"
  elif [ "$PR_CREATED" -eq 1 ]; then
    FINAL_STATE="pr-awaiting-review"
  else
    FINAL_STATE="completed-no-pr"
  fi
fi

echo "[autorun] $SLUG: complete (final_state=$FINAL_STATE merge_capable=$MERGE_CAPABLE run_degraded=$RUN_DEGRADED)"
exit 0
