#!/usr/bin/env bash
##############################################################################
# scripts/_pipeline_banner.sh
#
# Pipeline progress banner helper — v0.14.0
#
# CLI contract (executable mode):
#   _pipeline_banner.sh start <gate> <feature>   → start banner (AC2)
#   _pipeline_banner.sh end   <gate> <feature>   → end banner   (AC3)
#
# Sourceable mode: source this file to get _pipeline_banner_start and
#   _pipeline_banner_end functions directly.
#
# Behaviour summary:
#   - Reads pipeline_path from docs/specs/<feature>/spec.md frontmatter.
#   - Computes denominator (feature→5, small→2, bugfix→1) via case.
#   - Stage number from planned-gates-list keyed by pipeline_path.
#   - ETA from python3 scripts/_pipeline_eta.py; falls back to hardcoded
#     table if helper absent/errors.
#   - Cumulative cost from python3 ~/.claude/scripts/session-cost.py
#     --cumulative-only 2>/dev/null; omitted on error.
#   - Step-away marker: ☕ for 3-6 min, 🌅 for ≥6 min, none for <3 min.
#   - stdout vs stderr: if AUTORUN is truthy, writes to stderr (AC18).
#   - Null-guard: when no spec.md, emits standalone mode line + exits 0.
#   - ~/.claude/.banner-disabled: suppresses ALL output including /compact.
#   - docs/specs/<feature>/.compact-mode: literal "probe" or "suppress".
#   - Throttle sentinel: docs/specs/<feature>/.last-compact-suggestion JSON.
#
# Bash 3.2 compatible (macOS 10.15+, /bin/bash 3.2.57). Forbidden constructs:
#   ${arr[-1]}, declare -A, local -n, mapfile, read -a,
#   (?<name>...) named-group regex, $'\Q...\E'.
#   Denominator and all branching done via case statements + plain indexed
#   arrays (with ${arr[N]} only, never negative subscripts).
##############################################################################
# This file may be sourced OR executed. Declare functions; gate execution
# with the __main guard at the bottom.
# shellcheck disable=SC2034,SC2155

# ---------------------------------------------------------------------------
# Internal: emit to stdout or stderr depending on AUTORUN env var.
# ---------------------------------------------------------------------------
_pb_emit() {
  if [ "${AUTORUN:-0}" = "1" ] || [ "${AUTORUN:-0}" = "true" ] || [ "${AUTORUN:-0}" = "yes" ]; then
    printf '%s\n' "$1" >&2
  else
    printf '%s\n' "$1"
  fi
}

# ---------------------------------------------------------------------------
# Internal: parse a field from YAML frontmatter.
# Args: $1 = file path, $2 = field name
# Stdout: field value (trimmed) or empty
# ---------------------------------------------------------------------------
_pb_frontmatter_field() {
  _pbf_path="$1"
  _pbf_field="$2"
  if [ ! -f "$_pbf_path" ]; then
    return 0
  fi
  awk -v field="$_pbf_field" '
    BEGIN { in_fm = 0; seen = 0 }
    /^---[[:space:]]*$/ {
      if (seen == 0) { in_fm = 1; seen = 1; next }
      else if (in_fm == 1) { in_fm = 0; exit }
    }
    in_fm == 1 {
      if (match($0, "^[[:space:]]*" field "[[:space:]]*:[[:space:]]*")) {
        v = substr($0, RSTART + RLENGTH)
        sub(/[[:space:]]+#.*$/, "", v)
        sub(/^"/, "", v); sub(/"$/, "", v)
        sub(/^'\''/, "", v); sub(/'\''$/, "", v)
        sub(/[[:space:]]+$/, "", v)
        print v
        exit
      }
    }
  ' "$_pbf_path"
}

# ---------------------------------------------------------------------------
# Internal: get ETA in seconds for a given gate.
# Tries _pipeline_eta.py; falls back to hardcoded table.
# Args: $1 = gate name, $2 = feature slug
# Stdout: integer seconds
# ---------------------------------------------------------------------------
_pb_get_eta() {
  _pb_gate="$1"
  _pb_feature="${2:-}"

  # Locate the eta script relative to this file's directory.
  _pb_self_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
  # When sourced, $0 is the sourcing script — try REPO_ROOT env or script dir.
  _pb_eta_script="${REPO_ROOT:-$_pb_self_dir}/scripts/_pipeline_eta.py"
  # If invoked as the script itself, _pb_self_dir is scripts/; try parent.
  if [ ! -f "$_pb_eta_script" ]; then
    _pb_eta_script="$_pb_self_dir/_pipeline_eta.py"
  fi

  _pb_eta_result=""
  if [ -f "$_pb_eta_script" ]; then
    _pb_eta_result=$(python3 "$_pb_eta_script" --gate "$_pb_gate" --feature "$_pb_feature" 2>/dev/null) || true
  fi

  if [ -n "$_pb_eta_result" ] && printf '%s' "$_pb_eta_result" | grep -qE '^[0-9]+$'; then
    printf '%s' "$_pb_eta_result"
    return
  fi

  # Hardcoded fallback table (seconds) — must match _pipeline_eta.py defaults.
  case "$_pb_gate" in
    spec)         printf '480' ;;
    spec-review)  printf '360' ;;
    blueprint)    printf '180' ;;
    check)        printf '300' ;;
    build)        printf '900' ;;
    *)            printf '300' ;;
  esac
}

# ---------------------------------------------------------------------------
# Internal: format seconds as human-readable "~Nmin" string.
# Args: $1 = seconds (integer)
# ---------------------------------------------------------------------------
_pb_fmt_eta() {
  _pb_secs="$1"
  _pb_mins=$(( _pb_secs / 60 ))
  if [ "$_pb_mins" -le 0 ]; then
    printf '<1min'
  else
    printf '~%dmin' "$_pb_mins"
  fi
}

# ---------------------------------------------------------------------------
# Internal: step-away marker based on ETA seconds.
# Args: $1 = seconds (integer)
# Stdout: "☕ good step-away" / "🌅 long wait" / "" (empty for <3min)
# ---------------------------------------------------------------------------
_pb_step_away_marker() {
  _pb_sa_secs="$1"
  _pb_sa_mins=$(( _pb_sa_secs / 60 ))
  if [ "$_pb_sa_mins" -ge 6 ]; then
    printf '🌅 long wait'
  elif [ "$_pb_sa_mins" -ge 3 ]; then
    printf '☕ good step-away'
  else
    printf ''
  fi
}

# ---------------------------------------------------------------------------
# Internal: compute planned-gates list for a pipeline_path value.
# Uses plain indexed arrays (bash 3.2 safe: only non-negative subscripts).
# Args: $1 = pipeline_path value (feature|small|bugfix|<anything else>)
# Sets globals: _PB_GATES (array), _PB_TOTAL (integer)
# ---------------------------------------------------------------------------
_pb_compute_gates() {
  _pb_pp="$1"
  case "$_pb_pp" in
    feature)
      _PB_GATES=(spec spec-review blueprint check build)
      _PB_TOTAL=5
      ;;
    small)
      _PB_GATES=(spec build)
      _PB_TOTAL=2
      ;;
    bugfix)
      _PB_GATES=(build)
      _PB_TOTAL=1
      ;;
    *)
      # Default to feature if unknown
      _PB_GATES=(spec spec-review blueprint check build)
      _PB_TOTAL=5
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Internal: find the 1-based index of gate in _PB_GATES.
# Args: $1 = gate name
# Stdout: integer (1-based), or 1 if not found
# ---------------------------------------------------------------------------
_pb_gate_index() {
  _pb_gi_gate="$1"
  _pb_gi_idx=0
  _pb_gi_found=0
  while [ "$_pb_gi_idx" -lt "$_PB_TOTAL" ]; do
    if [ "${_PB_GATES[$_pb_gi_idx]}" = "$_pb_gi_gate" ]; then
      printf '%d' $(( _pb_gi_idx + 1 ))
      _pb_gi_found=1
      break
    fi
    _pb_gi_idx=$(( _pb_gi_idx + 1 ))
  done
  if [ "$_pb_gi_found" -eq 0 ]; then
    printf '1'
  fi
}

# ---------------------------------------------------------------------------
# Internal: compute "next gate" name after current gate in _PB_GATES.
# Args: $1 = current gate name
# Stdout: next gate name, or "" if at last gate
# ---------------------------------------------------------------------------
_pb_next_gate() {
  _pb_ng_gate="$1"
  _pb_ng_idx=0
  while [ "$_pb_ng_idx" -lt "$_PB_TOTAL" ]; do
    if [ "${_PB_GATES[$_pb_ng_idx]}" = "$_pb_ng_gate" ]; then
      _pb_ng_next=$(( _pb_ng_idx + 1 ))
      if [ "$_pb_ng_next" -lt "$_PB_TOTAL" ]; then
        printf '%s' "${_PB_GATES[$_pb_ng_next]}"
      fi
      return
    fi
    _pb_ng_idx=$(( _pb_ng_idx + 1 ))
  done
}

# ---------------------------------------------------------------------------
# Internal: gates remaining AFTER current gate (not counting current).
# Args: $1 = current 1-based stage number
# Stdout: integer (may be 0)
# ---------------------------------------------------------------------------
_pb_gates_remaining() {
  _pb_gr_stage="$1"
  printf '%d' $(( _PB_TOTAL - _pb_gr_stage ))
}

# ---------------------------------------------------------------------------
# Internal: get cumulative cost from session-cost.py --cumulative-only.
# Stdout: integer cents, or "" if unavailable.
# ---------------------------------------------------------------------------
_pb_get_cost() {
  _pb_cost_script="${HOME}/.claude/scripts/session-cost.py"
  if [ ! -f "$_pb_cost_script" ]; then
    printf ''
    return
  fi
  _pb_cost_result=$(python3 "$_pb_cost_script" --cumulative-only 2>/dev/null) || true
  if [ -n "$_pb_cost_result" ] && printf '%s' "$_pb_cost_result" | grep -qE '^[0-9]+$'; then
    printf '%s' "$_pb_cost_result"
  else
    printf ''
  fi
}

# ---------------------------------------------------------------------------
# Internal: format cents as "$N.NN"
# Args: $1 = cents (integer)
# Stdout: formatted string like "$0.42"
# ---------------------------------------------------------------------------
_pb_fmt_cost() {
  _pb_fc_cents="$1"
  _pb_fc_dollars=$(( _pb_fc_cents / 100 ))
  _pb_fc_remainder=$(( _pb_fc_cents % 100 ))
  printf '$%d.%02d' "$_pb_fc_dollars" "$_pb_fc_remainder"
}

# ---------------------------------------------------------------------------
# Internal: read context percentage for Path A.
# Probes statusline-command.sh JSON stdin format.
# Stdout: integer 0-100, or "" if unavailable.
# ---------------------------------------------------------------------------
_pb_get_context_pct() {
  # The context_window.used_percentage is available only if Claude Code passes
  # JSON on stdin to status-line scripts. We cannot invoke that directly —
  # instead, /blueprint pre-flight writes .compact-mode=probe if available.
  # Here we just check if stdin has something useful (non-interactive invocation).
  # When called from banner context, we can't probe live; rely on .compact-mode.
  printf ''
}

# ---------------------------------------------------------------------------
# Internal: check and emit /compact suggestion (both Path A and Path B).
# Args: $1 = feature slug, $2 = spec_dir path
# Emits to the appropriate stream (respects AUTORUN).
# ---------------------------------------------------------------------------
_pb_maybe_compact() {
  _pb_mc_feature="$1"
  _pb_mc_spec_dir="$2"
  _pb_mc_compact_file="$_pb_mc_spec_dir/.compact-mode"
  _pb_mc_sentinel="$_pb_mc_spec_dir/.last-compact-suggestion"

  _pb_mc_mode="suppress"
  if [ -f "$_pb_mc_compact_file" ]; then
    _pb_mc_mode=$(cat "$_pb_mc_compact_file" 2>/dev/null | tr -d '[:space:]') || _pb_mc_mode="suppress"
    case "$_pb_mc_mode" in
      probe|suppress) ;;
      *) _pb_mc_mode="suppress" ;;
    esac
  fi

  # --- Path A: probe configured ---
  if [ "$_pb_mc_mode" = "probe" ]; then
    # Read context pct from statusline-command.sh stdin format if available.
    # In practice, this runs after gate work; we attempt to read from stdin
    # only if it appears to be a JSON blob (non-interactive).
    _pb_mc_ctx_pct=""
    if [ ! -t 0 ]; then
      # stdin is not a tty — may be piped JSON from Claude Code
      _pb_mc_stdin=$(cat 2>/dev/null) || true
      if [ -n "$_pb_mc_stdin" ]; then
        _pb_mc_ctx_pct=$(printf '%s' "$_pb_mc_stdin" | python3 -c '
import sys, json
try:
    d = json.loads(sys.stdin.read())
    v = d.get("context_window", {}).get("used_percentage", None)
    if v is not None:
        print(int(v))
except Exception:
    pass
' 2>/dev/null) || true
      fi
    fi

    if [ -n "$_pb_mc_ctx_pct" ] && printf '%s' "$_pb_mc_ctx_pct" | grep -qE '^[0-9]+$'; then
      # Determine tier
      _pb_mc_tier=""
      if [ "$_pb_mc_ctx_pct" -ge 75 ]; then
        _pb_mc_tier="strong"
      elif [ "$_pb_mc_ctx_pct" -ge 50 ]; then
        _pb_mc_tier="soft"
      fi

      if [ -n "$_pb_mc_tier" ]; then
        # Check throttle sentinel
        _pb_mc_skip=0
        if [ -f "$_pb_mc_sentinel" ]; then
          _pb_mc_last_pct=$(python3 -c '
import sys, json
try:
    d = json.loads(open(sys.argv[1]).read())
    if d.get("path") == "A":
        print(d.get("last_context_pct", ""))
except Exception:
    pass
' "$_pb_mc_sentinel" 2>/dev/null) || true
          _pb_mc_last_ts=$(python3 -c '
import sys, json
try:
    d = json.loads(open(sys.argv[1]).read())
    if d.get("path") == "A":
        print(d.get("last_emit_ts", ""))
except Exception:
    pass
' "$_pb_mc_sentinel" 2>/dev/null) || true
          if [ -n "$_pb_mc_last_pct" ] && [ "$_pb_mc_last_pct" = "$_pb_mc_ctx_pct" ]; then
            # Same pct — check elapsed time
            _pb_mc_elapsed=$(python3 -c '
import sys, datetime
try:
    ts = sys.argv[1]
    then = datetime.datetime.fromisoformat(ts.replace("Z", "+00:00"))
    now = datetime.datetime.now(datetime.timezone.utc)
    print(int((now - then).total_seconds()))
except Exception:
    print(9999)
' "$_pb_mc_last_ts" 2>/dev/null) || _pb_mc_elapsed=9999
            if [ "$_pb_mc_elapsed" -lt 600 ] 2>/dev/null; then
              _pb_mc_skip=1
            fi
          fi
        fi

        if [ "$_pb_mc_skip" -eq 0 ]; then
          if [ "$_pb_mc_tier" = "strong" ]; then
            _pb_emit "[pipeline] 💾 Context ${_pb_mc_ctx_pct}% · /compact strongly recommended before next gate"
          else
            _pb_emit "[pipeline] 💾 Context ${_pb_mc_ctx_pct}% · /compact recommended before next gate (saves ~\$1.50 · ~30sec · no work lost — artifacts on disk)"
          fi
          # Write throttle sentinel
          _pb_mc_now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
          python3 -c '
import sys, json
data = {"last_context_pct": int(sys.argv[1]), "last_emit_ts": sys.argv[2], "path": "A"}
open(sys.argv[3], "w").write(json.dumps(data))
' "$_pb_mc_ctx_pct" "$_pb_mc_now" "$_pb_mc_sentinel" 2>/dev/null || true
        fi
      fi
    fi
    return
  fi

  # --- Path B: suppress (default) ---
  # Emit cost-boundary one-liner when cumulative crossed $5 since last emission.
  _pb_mc_cost_cents=$(_pb_get_cost)
  if [ -z "$_pb_mc_cost_cents" ]; then
    return
  fi
  # $5 = 500 cents
  if [ "$_pb_mc_cost_cents" -lt 500 ] 2>/dev/null; then
    return
  fi

  # Check throttle sentinel for Path B
  _pb_mc_skip=0
  if [ -f "$_pb_mc_sentinel" ]; then
    _pb_mc_b_last_ts=$(python3 -c '
import sys, json
try:
    d = json.loads(open(sys.argv[1]).read())
    if d.get("path") == "B":
        print(d.get("last_emit_ts", ""))
except Exception:
    pass
' "$_pb_mc_sentinel" 2>/dev/null) || true
    if [ -n "$_pb_mc_b_last_ts" ]; then
      _pb_mc_b_elapsed=$(python3 -c '
import sys, datetime
try:
    ts = sys.argv[1]
    then = datetime.datetime.fromisoformat(ts.replace("Z", "+00:00"))
    now = datetime.datetime.now(datetime.timezone.utc)
    print(int((now - then).total_seconds()))
except Exception:
    print(9999)
' "$_pb_mc_b_last_ts" 2>/dev/null) || _pb_mc_b_elapsed=9999
      if [ "$_pb_mc_b_elapsed" -lt 600 ] 2>/dev/null; then
        _pb_mc_skip=1
      fi
    fi
  fi

  if [ "$_pb_mc_skip" -eq 0 ]; then
    _pb_emit "[pipeline] 💾 session cost crossed \$5 · consider /compact between major work"
    _pb_mc_now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    python3 -c '
import sys, json
data = {"last_context_pct": 0, "last_emit_ts": sys.argv[1], "path": "B"}
open(sys.argv[2], "w").write(json.dumps(data))
' "$_pb_mc_now" "$_pb_mc_sentinel" 2>/dev/null || true
  fi
}

# ---------------------------------------------------------------------------
# _pipeline_banner_start <gate> <feature>
#
# Emits the start banner line for a pipeline gate.
# ---------------------------------------------------------------------------
_pipeline_banner_start() {
  _pb_s_gate="$1"
  _pb_s_feature="$2"

  # User-global opt-out
  if [ -f "${HOME}/.claude/.banner-disabled" ]; then
    return 0
  fi

  # Null-guard: no spec.md → standalone mode
  _pb_s_spec_dir="docs/specs/${_pb_s_feature}"
  _pb_s_spec_md="${_pb_s_spec_dir}/spec.md"
  if [ ! -f "$_pb_s_spec_md" ]; then
    _pb_emit "[pipeline] /${_pb_s_gate} · standalone mode"
    return 0
  fi

  # Read pipeline_path from frontmatter
  _pb_s_pipeline_path=$(_pb_frontmatter_field "$_pb_s_spec_md" "pipeline_path")
  if [ -z "$_pb_s_pipeline_path" ]; then
    _pb_s_pipeline_path="feature"
  fi

  # Compute gates list and find stage number
  _pb_compute_gates "$_pb_s_pipeline_path"
  _pb_s_stage=$(_pb_gate_index "$_pb_s_gate")

  # Get ETA
  _pb_s_eta_secs=$(_pb_get_eta "$_pb_s_gate" "$_pb_s_feature")
  _pb_s_eta_str=$(_pb_fmt_eta "$_pb_s_eta_secs")

  # Step-away marker
  _pb_s_marker=$(_pb_step_away_marker "$_pb_s_eta_secs")

  # Build line
  _pb_s_line="[pipeline] Stage ${_pb_s_stage} of ${_PB_TOTAL} — /${_pb_s_gate} starting · ${_pb_s_eta_str}"
  if [ -n "$_pb_s_marker" ]; then
    _pb_s_line="${_pb_s_line} · ${_pb_s_marker}"
  fi

  _pb_emit "$_pb_s_line"
}

# ---------------------------------------------------------------------------
# _pipeline_banner_end <gate> <feature>
#
# Emits the end banner line for a pipeline gate, plus /compact suggestion.
# ---------------------------------------------------------------------------
_pipeline_banner_end() {
  _pb_e_gate="$1"
  _pb_e_feature="$2"

  # User-global opt-out (suppresses ALL output including /compact)
  if [ -f "${HOME}/.claude/.banner-disabled" ]; then
    return 0
  fi

  # Null-guard: no spec.md → standalone mode
  _pb_e_spec_dir="docs/specs/${_pb_e_feature}"
  _pb_e_spec_md="${_pb_e_spec_dir}/spec.md"
  if [ ! -f "$_pb_e_spec_md" ]; then
    _pb_emit "[pipeline] /${_pb_e_gate} · standalone mode"
    return 0
  fi

  # Read pipeline_path from frontmatter
  _pb_e_pipeline_path=$(_pb_frontmatter_field "$_pb_e_spec_md" "pipeline_path")
  if [ -z "$_pb_e_pipeline_path" ]; then
    _pb_e_pipeline_path="feature"
  fi

  # Compute gates list and find stage number
  _pb_compute_gates "$_pb_e_pipeline_path"
  _pb_e_stage=$(_pb_gate_index "$_pb_e_gate")
  _pb_e_remaining=$(_pb_gates_remaining "$_pb_e_stage")

  # Get next gate name
  _pb_e_next=$(_pb_next_gate "$_pb_e_gate")

  # Get ETA for next gate (for "next:" hint)
  _pb_e_next_eta_str=""
  if [ -n "$_pb_e_next" ]; then
    _pb_e_next_eta_secs=$(_pb_get_eta "$_pb_e_next" "$_pb_e_feature")
    _pb_e_next_eta_str=$(_pb_fmt_eta "$_pb_e_next_eta_secs")
  fi

  # Get cumulative cost
  _pb_e_cost_cents=$(_pb_get_cost)
  _pb_e_cost_str=""
  if [ -n "$_pb_e_cost_cents" ]; then
    _pb_e_cost_str="$(_pb_fmt_cost "$_pb_e_cost_cents") cumulative"
  fi

  # Build cost section
  _pb_e_cost_section=""
  if [ -n "$_pb_e_cost_str" ]; then
    _pb_e_cost_section=" · ${_pb_e_cost_str}"
  fi

  # First line: stage N of M ✓ /gate done (cost)
  _pb_e_line1="[pipeline] Stage ${_pb_e_stage} of ${_PB_TOTAL} ✓ /${_pb_e_gate} done${_pb_e_cost_section}"
  _pb_emit "$_pb_e_line1"

  # Second line: next gate + remaining count
  if [ -n "$_pb_e_next" ] && [ "$_pb_e_remaining" -gt 0 ]; then
    _pb_e_line2="           next: /${_pb_e_next} · ${_pb_e_next_eta_str} · ${_pb_e_remaining} gates remaining"
    _pb_emit "$_pb_e_line2"
  elif [ "$_pb_e_remaining" -eq 0 ]; then
    _pb_emit "           pipeline complete"
  fi

  # /compact suggestion (both paths throttled via sentinel)
  _pb_maybe_compact "$_pb_e_feature" "$_pb_e_spec_dir"
}

# ---------------------------------------------------------------------------
# __main: only runs when script is executed directly (not sourced).
# ---------------------------------------------------------------------------
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  if [ $# -lt 3 ]; then
    printf 'Usage: %s start|end <gate> <feature>\n' "$0" >&2
    exit 1
  fi
  _pb_subcommand="$1"
  _pb_gate_arg="$2"
  _pb_feature_arg="$3"

  case "$_pb_subcommand" in
    start)
      _pipeline_banner_start "$_pb_gate_arg" "$_pb_feature_arg"
      ;;
    end)
      _pipeline_banner_end "$_pb_gate_arg" "$_pb_feature_arg"
      ;;
    *)
      printf 'Error: unknown subcommand "%s". Use start or end.\n' "$_pb_subcommand" >&2
      exit 1
      ;;
  esac
fi
