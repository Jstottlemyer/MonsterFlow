#!/usr/bin/env bash
##############################################################################
# scripts/_gate_helpers.sh
#
# Shared helper library sourced by the three interactive gate commands
# (/spec-review, /plan, /check) per pipeline-gate-permissiveness Wave 3 Task 3.4.
#
# Contracts (see docs/specs/pipeline-gate-permissiveness/spec.md Edge Case 11,
# A11b, A13, A16; commands/_gate-mode.md when present):
#
#   gate_max_recycles_clamp <spec.md>
#       Reads `gate_max_recycles:` from YAML frontmatter of the given spec.md;
#       clamps the integer into [1, 5]; emits a once-per-session-per-spec
#       stderr warning when clamping occurs (suppressed by sentinel
#       <spec-dir>/.recycles-clamped).
#       stdout: clamped integer (1..5)
#
#   gate_mode_resolve <spec.md> <flag>
#       Resolves effective gate mode given frontmatter `gate_mode:` plus a
#       single CLI flag string ("--strict" | "--permissive" |
#       "--force-permissive=<reason>" | "").
#       stdout (success): "<mode>:<mode_source>"
#       stderr: banners / errors
#       exit:   0 ok, 2 rejected (conflict, ambiguity, or CI/AUTORUN refusal)
#
#   is_ci_env
#       Returns 0 iff $CI or $AUTORUN_STAGE is set to a truthy value
#       (whitelist: true | 1 | yes | TRUE | YES). Anything else -> 1.
#
#   force_permissive_audit <spec-dir> <iteration> <gate> <reason>
#       Appends one JSONL row to <spec-dir>/.force-permissive-log. Reason is
#       JSON-escaped via python3 to survive embedded quotes/backslashes.
#
# Bash 3.2 compatible (macOS default). NO ${arr[-1]}, NO mapfile, NO
# [[ =~ ]], NO &>. Tilde-expand path inputs before any mkdir/write
# (per ~/CLAUDE.md feedback_tilde_expansion_in_bash_config_reads).
#
# This file is sourced, not executed. It declares functions only and does NOT
# call `set -e` (callers manage their own errexit).
##############################################################################
# shellcheck disable=SC2034

# ---------------------------------------------------------------------------
# Internal: parse a single field value from YAML frontmatter
# Args: $1 = path to spec.md, $2 = field name (e.g. "gate_mode")
# Stdout: raw field value (trimmed) OR empty string if not present
# Exit: 0 always (absence is not an error)
# ---------------------------------------------------------------------------
_gh_frontmatter_field() {
  _gh_path="$1"
  _gh_field="$2"
  if [ ! -f "$_gh_path" ]; then
    return 0
  fi
  # awk: capture lines strictly between the first two "---" delimiter lines
  # at column 1. If the file lacks a frontmatter block, awk emits nothing.
  awk -v field="$_gh_field" '
    BEGIN { in_fm = 0; seen = 0 }
    /^---[[:space:]]*$/ {
      if (seen == 0) { in_fm = 1; seen = 1; next }
      else if (in_fm == 1) { in_fm = 0; exit }
    }
    in_fm == 1 {
      # match "field: value" allowing optional leading spaces
      if (match($0, "^[[:space:]]*" field "[[:space:]]*:[[:space:]]*")) {
        v = substr($0, RSTART + RLENGTH)
        # strip trailing comment "# ..." if present
        sub(/[[:space:]]+#.*$/, "", v)
        # strip surrounding quotes
        sub(/^"/, "", v); sub(/"$/, "", v)
        sub(/^'\''/, "", v); sub(/'\''$/, "", v)
        # strip trailing whitespace
        sub(/[[:space:]]+$/, "", v)
        print v
        exit
      }
    }
  ' "$_gh_path"
}

# ---------------------------------------------------------------------------
# is_ci_env
# Returns 0 (true) if $CI or $AUTORUN_STAGE is one of: true, 1, yes, TRUE, YES.
# All other values (including unset, empty, "false", "0") return 1.
# ---------------------------------------------------------------------------
is_ci_env() {
  _gh_v="${CI-}"
  case "$_gh_v" in
    true|1|yes|TRUE|YES) return 0 ;;
  esac
  _gh_v="${AUTORUN_STAGE-}"
  case "$_gh_v" in
    true|1|yes|TRUE|YES) return 0 ;;
  esac
  return 1
}

# ---------------------------------------------------------------------------
# gate_max_recycles_clamp <spec.md>
#
# Returns the per-gate re-cycle ceiling. As of 2026-05-09 this is HARDCODED to
# 3 (matching build_max_retries and SECURITY_MAX_FIX_ATTEMPTS — the uniform
# "3 attempts before halt" pipeline contract).
#
# Function name preserved for caller ABI compatibility. Emits a one-time
# deprecation warning to stderr if the spec still pins gate_max_recycles in
# frontmatter (silenced via per-spec sentinel). The frontmatter value is
# IGNORED — author intent is preserved as a comment, but the runtime value
# is always 3.
#
# stdout: 3
# stderr: deprecation warning iff frontmatter sets the field AND sentinel absent
# ---------------------------------------------------------------------------
gate_max_recycles_clamp() {
  _gh_spec="$1"
  _gh_spec="${_gh_spec/#\~/$HOME}"
  _gh_dir=$(dirname "$_gh_spec")
  _gh_raw=$(_gh_frontmatter_field "$_gh_spec" "gate_max_recycles")

  if [ -n "$_gh_raw" ]; then
    _gh_sentinel="$_gh_dir/.recycles-deprecated"
    if [ ! -f "$_gh_sentinel" ]; then
      printf '[gate] DEPRECATED: gate_max_recycles=%s in frontmatter is ignored — pipeline hardcoded to 3 since 2026-05-09. Strip the field from frontmatter to silence this. (silenced after first run)\n' \
        "$_gh_raw" >&2
      mkdir -p "$_gh_dir" 2>/dev/null || true
      : > "$_gh_sentinel" 2>/dev/null || true
    fi
  fi

  printf '3\n'
}

# ---------------------------------------------------------------------------
# gate_mode_resolve <spec.md> <flag-string>
#
# Truth table (mode | mode_source):
#   no flag, frontmatter=permissive       -> permissive | frontmatter
#   no flag, frontmatter=strict           -> strict     | frontmatter
#   no flag, frontmatter absent           -> permissive | default
#   --strict                              -> strict     | cli      (any frontmatter)
#   --permissive, frontmatter=permissive  -> permissive | cli      (no-op)
#   --permissive, frontmatter absent      -> permissive | cli
#   --permissive, frontmatter=strict      -> EXIT 2     (refused; needs --force-permissive)
#   --force-permissive=<reason>, strict   -> permissive | cli-force (warn)
#   --force-permissive=<reason>, other    -> permissive | cli       (no-op; no audit)
#   --force-permissive in CI/AUTORUN env  -> EXIT 2     (refused)
#   --strict --permissive (combined)      -> EXIT 2     (ambiguity)
# ---------------------------------------------------------------------------
gate_mode_resolve() {
  _gh_spec="$1"
  _gh_flag="${2-}"
  _gh_spec="${_gh_spec/#\~/$HOME}"

  _gh_fm=$(_gh_frontmatter_field "$_gh_spec" "gate_mode")
  case "$_gh_fm" in
    permissive|strict) : ;;
    '') : ;;
    *)
      printf '[gate] WARNING: unrecognized gate_mode value in frontmatter: %s (treating as absent)\n' "$_gh_fm" >&2
      _gh_fm=''
      ;;
  esac

  # Detect combined --strict + --permissive ambiguity. Caller passes a single
  # flag string; if the literal contains both tokens, reject.
  case "$_gh_flag" in
    *--strict*--permissive*|*--permissive*--strict*)
      printf '[gate] ERROR: --strict and --permissive on the same invocation is ambiguous; pick one.\n' >&2
      return 2
      ;;
  esac

  # Classify the flag.
  _gh_force_reason=''
  case "$_gh_flag" in
    '')
      _gh_kind='none'
      ;;
    --strict)
      _gh_kind='strict'
      ;;
    --permissive)
      _gh_kind='permissive'
      ;;
    --force-permissive)
      _gh_kind='force'
      _gh_force_reason=''
      ;;
    --force-permissive=*)
      _gh_kind='force'
      _gh_force_reason="${_gh_flag#--force-permissive=}"
      ;;
    *)
      printf '[gate] ERROR: unrecognized flag: %s\n' "$_gh_flag" >&2
      return 2
      ;;
  esac

  # Resolve.
  case "$_gh_kind" in
    none)
      if [ -z "$_gh_fm" ]; then
        printf 'permissive:default\n'
      else
        printf '%s:frontmatter\n' "$_gh_fm"
      fi
      return 0
      ;;
    strict)
      printf 'strict:cli\n'
      return 0
      ;;
    permissive)
      if [ "$_gh_fm" = "strict" ]; then
        printf '[gate] ERROR: spec declares gate_mode: strict; cannot override without --force-permissive\n' >&2
        return 2
      fi
      printf 'permissive:cli\n'
      return 0
      ;;
    force)
      if is_ci_env; then
        printf '[gate] ERROR: --force-permissive is refused when $CI or $AUTORUN_STAGE is set (interactive escape hatch only).\n' >&2
        return 2
      fi
      if [ "$_gh_fm" = "strict" ]; then
        printf '[gate] WARNING: --force-permissive overriding gate_mode: strict on a strict-flagged spec.\n' >&2
        printf '[gate]          This is auditable: a row will be appended to <spec-dir>/.force-permissive-log\n' >&2
        printf '[gate]          with timestamp + iteration + user. Verdict will record mode_source: cli-force.\n' >&2
        if [ -n "$_gh_force_reason" ]; then
          printf '[gate]          reason: %s\n' "$_gh_force_reason" >&2
        fi
        printf 'permissive:cli-force\n'
        return 0
      fi
      # No strict to escape; degrade to plain --permissive semantics.
      printf 'permissive:cli\n'
      return 0
      ;;
  esac
}

# ---------------------------------------------------------------------------
# force_permissive_audit <spec-dir> <iteration> <gate> <reason>
# Appends a JSONL row to <spec-dir>/.force-permissive-log. JSON-escapes the
# reason string via python3 to handle quotes/backslashes/newlines.
# ---------------------------------------------------------------------------
force_permissive_audit() {
  _gh_dir="$1"
  _gh_iter="$2"
  _gh_gate="$3"
  _gh_reason="${4-}"
  _gh_dir="${_gh_dir/#\~/$HOME}"

  _gh_user=$(git config user.email 2>/dev/null || true)
  if [ -z "$_gh_user" ]; then
    _gh_user="${USER-unknown}"
  fi
  _gh_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  _gh_spec_path="$_gh_dir/spec.md"
  _gh_verdict="${_gh_gate}-verdict.json"

  if [ ! -d "$_gh_dir" ]; then
    mkdir -p "$_gh_dir" 2>/dev/null || true
  fi

  # Build the JSON via python3 — single source of truth for escaping.
  _gh_json=$(python3 -c '
import json, sys
row = {
    "timestamp":        sys.argv[1],
    "iteration":        sys.argv[2],
    "gate":             sys.argv[3],
    "user":             sys.argv[4],
    "spec":             sys.argv[5],
    "verdict_sidecar":  sys.argv[6],
    "reason":           sys.argv[7],
}
# Coerce iteration to int when possible (post-hoc analytics friendlier).
try:
    row["iteration"] = int(row["iteration"])
except (TypeError, ValueError):
    pass
sys.stdout.write(json.dumps(row, sort_keys=True))
' "$_gh_ts" "$_gh_iter" "$_gh_gate" "$_gh_user" "$_gh_spec_path" "$_gh_verdict" "$_gh_reason") || return 1

  printf '%s\n' "$_gh_json" >> "$_gh_dir/.force-permissive-log"
}
