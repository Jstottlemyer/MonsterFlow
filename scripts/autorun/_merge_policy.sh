#!/usr/bin/env bash
##############################################################################
# scripts/autorun/_merge_policy.sh
#
# Helper library for autorun-merge-policy (v0.11.0).
#
# Spec: docs/specs/autorun-merge-policy/spec.md (29 ACs + AC-R1/R2/R3)
# Plan: docs/specs/autorun-merge-policy/plan.md
#
# This file is sourced (NOT executed). It declares functions only and does NOT
# call `set -e` (callers manage their own errexit).
#
# Bash 3.2 compatible. NO ${arr[-1]}, NO mapfile, NO [[ =~ ]], NO &>.
# Tilde-expand path inputs before any mkdir/write.
#
# ---------------------------------------------------------------------------
# Public API (functions the caller may invoke):
#
#   merge_policy_resolve <spec_path> <cli_flag>
#       Resolves merge policy via precedence: CLI > spec > constitution > default(pr).
#       stdout: "<source>:<value>" e.g. "spec:clean", "default:pr"
#       exit:   0 ok, 2 invalid value (validate-then-store per D7)
#
#   merge_policy_validate <value>
#       Pure check against closed enum {pr, clean, validated}.
#       exit: 0 ok, 2 invalid (caller may stderr-warn).
#
#   is_clean_for_merge <merge_capable> <verdict> <gate_mode> <followups_added> [codex_ran]
#       Mode-aware predicate refining the merge gate's verdict axis.
#       Refines four-axis gate at run.sh:1069-1102 — does NOT replace it.
#       Returns 0 if merge is permitted under `clean` policy semantics; else 1.
#       Never exits the shell. Per D2 / D21 / SA-1.
#
#   merge_policy_render_banner <slug> <policy> <resolved_from> <gate_mode> <gate_mode_source> <agent_budget> <agent_budget_source> <max_recycles> <max_recycles_source>
#       Emits 4-knob runtime-config banner to STDOUT (per R7 — banner is
#       intentional output; stderr is reserved for actual errors).
#       ANSI color on warning line gated by `[ -t 1 ]`. 78-col wide cap.
#
#   queue_copy_drift_check <canonical_path> <queue_path>
#       Asymmetric drift detector (D6): halts (exit 2) when queue ELEVATES
#       policy above canonical; warns on downward drift; silent-skip when
#       canonical absent (cross-project / hand-queued).
#       Partial order: pr ≡ validated_today < clean.
#
#   merge_policy_field_state <spec_path>
#       Three-state wrapper (R5). Echoes one of: "absent" | "empty" | "<value>".
#       Eliminates missing-vs-empty ambiguity in drift detection.
#
#   merge_policy_dispatch <slug> <pr_url> <policy> <resolved_from> <gate_mode> <merge_capable> <verdict> <followups_added> <run_id> <spec_sha> <pr_number> [codex_ran]
#       SOLE caller of log_merge_action_completed. Routes to one of:
#         dispatch_pr_only / dispatch_clean_merge / dispatch_validated_merge
#       Honors $MERGE_POLICY_DISPATCH_OVERRIDE only when MONSTERFLOW_TEST_MODE=1
#       (SA-2 hardening). Wraps `gh pr create`/`gh pr merge` calls in error
#       capture per D23 / R3.
#
#   log_merge_policy_resolved <run_log_path> <slug> <policy> <resolved_from> <gate_mode> <spec_sha> <run_id>
#       Writes the START event row. Called from run.sh at run start.
#
#   log_merge_action_completed <run_log_path> <slug> <action> <reason> <pr_number> <merge_sha> <run_id>
#       Writes the END event row. Called by merge_policy_dispatch only.
#
# ---------------------------------------------------------------------------
# YAML-subset semantics inherited from _gh_frontmatter_field
# (scripts/_gate_helpers.sh:49-79). Pinned per Codex source-grounded read:
#
#   - Reads only between first two `---` lines at column 1.
#   - Matches `field: value` with optional leading spaces. First match wins;
#     duplicate keys resolve to first.
#   - Strips trailing comments only when preceded by whitespace.
#   - Strips one pair of surrounding quotes (single OR double).
#   - Does NOT support block/multiline values (`|`, `>`).
#   - Quoted `#` values can be mangled in edge cases (documented limitation).
#
# Resolver halts (exit 2) on any non-enum value the parser returns
# (validate-then-store per D7).
#
# ---------------------------------------------------------------------------
# JSONL row schemas (additive event types on queue/run.log).
#
# event=merge_policy_resolved   { ts, slug, run_id, event, policy,
#                                 resolved_from, gate_mode, spec_sha,
#                                 pr_number=null, action=null, reason=null,
#                                 merge_sha=null }
#                              # written immediately after policy resolution
#
# event=merge_action_completed  { ts, slug, run_id, event, action, reason,
#                                 pr_number, merge_sha }
#                              # written at merge-call site (end of dispatch)
#
# Join key: (slug, run_id). Both consecutive runs of the same slug yield two
# pairable (start, end) tuples. `merge_sha` MAY be null when action=auto_merged
# (R6: `gh --auto` queues the merge for a future moment).
#
# ---------------------------------------------------------------------------
# `validated` policy contract (forward-compat sentinel — see autorun-runtime-validation-gate)
#
# Until autorun-runtime-validation-gate ships, `validated` falls back to `pr`
# (NOT `clean`) per Codex H1. Banner stderr-warns once at run start; run.log
# records `action=fell_back, reason=validated_fallback`. The
# `runtime_not_pass` reason and `details.runtime_status` field are RESERVED
# for that future spec; they MUST NOT be emitted from this version.
##############################################################################
# shellcheck disable=SC2034,SC2155

# Sourcing guard — idempotent.
if [ "${_MERGE_POLICY_SH_SOURCED:-0}" = "1" ]; then
  return 0 2>/dev/null || exit 0
fi
_MERGE_POLICY_SH_SOURCED=1

# Source _gate_helpers.sh for _gh_frontmatter_field.
# ENGINE_DIR is exported by run.sh and autorun-batch.sh.
if [ -z "${ENGINE_DIR:-}" ]; then
  # Best-effort fallback: assume helper lives 2 levels under engine root.
  _MP_HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
  ENGINE_DIR="$(cd "$_MP_HERE/../.." && pwd)"
fi

# shellcheck disable=SC1090
. "$ENGINE_DIR/scripts/_gate_helpers.sh"

# ---------------------------------------------------------------------------
# Closed enums — readonly arrays (schema authority — tests grep these).
# ---------------------------------------------------------------------------
_MP_POLICIES=(pr clean validated)
_MP_ACTIONS=(pr_only auto_merged fell_back merge_failed)
# 10 reasons (8 from spec + recycle_demoted_findings (D21/R1) + pr_create_failed (D23/R3))
# + codex_absent (SA-1)
_MP_REASONS=(
  warnings_present
  verdict_no_go
  codex_high_severity
  run_degraded
  validated_fallback
  branch_protection
  merge_call_failed
  manual_review_requested
  recycle_demoted_findings
  pr_create_failed
  codex_absent
)
_MP_RESOLVED_FROM=(cli spec constitution default)

readonly _MP_POLICIES _MP_ACTIONS _MP_REASONS _MP_RESOLVED_FROM 2>/dev/null || true

# ---------------------------------------------------------------------------
# merge_policy_validate — pure closed-enum check.
# Args: $1 = candidate value
# Exit: 0 valid, 2 invalid
# ---------------------------------------------------------------------------
merge_policy_validate() {
  case "${1-}" in
    pr|clean|validated) return 0 ;;
    *) return 2 ;;
  esac
}

# ---------------------------------------------------------------------------
# merge_policy_field_state — three-state wrapper (R5 mitigation).
# Echoes "absent" if field key not present, "empty" if present-but-empty,
# else echoes the trimmed value. Eliminates missing-vs-empty ambiguity.
# ---------------------------------------------------------------------------
merge_policy_field_state() {
  _mp_path="$1"
  if [ ! -f "$_mp_path" ]; then
    printf 'absent\n'
    return 0
  fi
  # awk: distinguishes absent (no match) from empty (match with empty value).
  awk '
    BEGIN { in_fm = 0; seen = 0; found = 0 }
    /^---[[:space:]]*$/ {
      if (seen == 0) { in_fm = 1; seen = 1; next }
      else if (in_fm == 1) { in_fm = 0; exit }
    }
    in_fm == 1 {
      if (match($0, "^[[:space:]]*auto_merge_policy[[:space:]]*:[[:space:]]*")) {
        v = substr($0, RSTART + RLENGTH)
        sub(/[[:space:]]+#.*$/, "", v)
        sub(/^"/, "", v); sub(/"$/, "", v)
        sub(/^'\''/, "", v); sub(/'\''$/, "", v)
        sub(/[[:space:]]+$/, "", v)
        if (v == "") { print "empty" } else { print v }
        found = 1
        exit
      }
    }
    END { if (found == 0) print "absent" }
  ' "$_mp_path"
}

# ---------------------------------------------------------------------------
# merge_policy_warn_unknown_keys — AC#8 implementation.
#
# Scans frontmatter of the given file for keys that look like typos of
# `auto_merge_policy` (any frontmatter key that starts with `auto_merge` but
# is NOT exactly `auto_merge_policy`). Emits a stderr warning naming each
# offender and the source file. Never halts.
#
# Args:
#   $1 = file path (spec.md or constitution.md)
#   $2 = label used in warning (e.g. "queue/foo.spec.md")
#
# This is intentionally conservative — only `auto_merge_*` keys are flagged
# (Levenshtein typo-suggestion was demoted to BACKLOG per Definitions §
# "Levenshtein typo detector"). One warning per offending key.
# ---------------------------------------------------------------------------
merge_policy_warn_unknown_keys() {
  _mp_uk_path="$1"
  _mp_uk_label="${2:-$1}"
  [ -f "$_mp_uk_path" ] || return 0

  awk -v label="$_mp_uk_label" '
    BEGIN { in_fm = 0; seen = 0 }
    /^---[[:space:]]*$/ {
      if (seen == 0) { in_fm = 1; seen = 1; next }
      else if (in_fm == 1) { exit }
    }
    in_fm == 1 {
      # match indented YAML keys: optional leading space, key, colon
      if (match($0, "^[[:space:]]*auto_merge[A-Za-z0-9_]*[[:space:]]*:")) {
        key = substr($0, RSTART, RLENGTH)
        sub(/^[[:space:]]+/, "", key)
        sub(/[[:space:]]*:[[:space:]]*$/, "", key)
        if (key != "auto_merge_policy") {
          printf "[autorun] warning: unknown frontmatter key %c%s%c in %s (did you mean auto_merge_policy?)\n", \
            39, key, 39, label > "/dev/stderr"
        }
      }
    }
  ' "$_mp_uk_path"
}

# ---------------------------------------------------------------------------
# merge_policy_resolve — full precedence resolution.
#
# Precedence: CLI > spec > constitution > default("pr").
#
# Reads:
#   $1 = spec_path (queue/<slug>.spec.md)
#   $2 = cli_flag (raw value of --merge-policy or --auto-merge; empty if unset)
#   uses $PROJECT_DIR for constitution lookup
#
# Writes:
#   stdout: "<source>:<value>" — one of:
#     "cli:pr" "cli:clean" "cli:validated"
#     "spec:pr" "spec:clean" "spec:validated"
#     "constitution:pr" "constitution:clean" "constitution:validated"
#     "default:pr"
#   stderr: error message on invalid value (validate-then-store per D7)
# Exit: 0 ok, 2 invalid value at any layer
# ---------------------------------------------------------------------------
merge_policy_resolve() {
  _mp_spec="$1"
  _mp_cli="${2-}"

  if [ -n "$_mp_cli" ]; then
    if ! merge_policy_validate "$_mp_cli"; then
      printf '[autorun] error: invalid auto_merge_policy value via CLI: %s (allowed: pr, clean, validated)\n' "$_mp_cli" >&2
      return 2
    fi
    printf 'cli:%s\n' "$_mp_cli"
    return 0
  fi

  # AC#8 — warn (but never halt) on `auto_merge_*` typo-keys in spec frontmatter.
  if [ -f "$_mp_spec" ]; then
    merge_policy_warn_unknown_keys "$_mp_spec" "$_mp_spec"
  fi

  # Spec frontmatter
  _mp_spec_val="$(_gh_frontmatter_field "$_mp_spec" auto_merge_policy 2>/dev/null || true)"
  if [ -n "$_mp_spec_val" ]; then
    if ! merge_policy_validate "$_mp_spec_val"; then
      printf '[autorun] error: invalid auto_merge_policy in %s: %s (allowed: pr, clean, validated)\n' \
        "$_mp_spec" "$_mp_spec_val" >&2
      return 2
    fi
    printf 'spec:%s\n' "$_mp_spec_val"
    return 0
  fi

  # Constitution (project-local)
  _mp_const_path="${PROJECT_DIR:-$PWD}/docs/specs/constitution.md"
  if [ -f "$_mp_const_path" ]; then
    # AC#8 — also scan the constitution for typo-keys.
    merge_policy_warn_unknown_keys "$_mp_const_path" "$_mp_const_path"
    _mp_const_val="$(_gh_frontmatter_field "$_mp_const_path" auto_merge_policy 2>/dev/null || true)"
    if [ -n "$_mp_const_val" ]; then
      if ! merge_policy_validate "$_mp_const_val"; then
        printf '[autorun] error: invalid auto_merge_policy in %s: %s (allowed: pr, clean, validated)\n' \
          "$_mp_const_path" "$_mp_const_val" >&2
        return 2
      fi
      printf 'constitution:%s\n' "$_mp_const_val"
      return 0
    fi
  fi

  # Default — safe fallback (asymmetric-risk argument).
  printf 'default:pr\n'
}

# ---------------------------------------------------------------------------
# is_clean_for_merge — mode-aware predicate (D2 + D21 + SA-1).
#
# Args:
#   $1 merge_capable    "0" or "1" (output of existing four-axis gate)
#   $2 verdict          "GO" | "GO_WITH_FIXES" | "NO_GO"
#   $3 gate_mode        "strict" | "permissive"
#   $4 followups_added  integer (line-diff on followups.jsonl for this slug)
#   $5 codex_ran        "0" or "1" (optional; default "1" preserves backward compat)
#
# Returns 0 if `clean`-policy auto-merge is permitted; 1 otherwise.
# Never exits.
#
# Refines the verdict axis:
#   strict     — accepts {GO, GO_WITH_FIXES}
#   permissive — accepts {GO} only (asymmetric-risk thesis at the boundary)
#
# Additional axes (block on any failure):
#   - merge_capable must be 1 (composes four-axis gate)
#   - followups_added must be 0 (R1 — recycle laundering guard)
#   - codex_ran must be 1 unless gate_mode == strict (SA-1 — Codex-absent guard)
# ---------------------------------------------------------------------------
is_clean_for_merge() {
  _mp_capable="${1-}"
  _mp_verdict="${2-}"
  _mp_mode="${3-}"
  _mp_followups="${4-0}"
  _mp_codex_ran="${5-1}"

  [ "$_mp_capable" = "1" ] || return 1
  [ "$_mp_followups" = "0" ] || return 1
  # SA-1: codex outage MUST NOT silently bypass an entire reviewer axis.
  # Only `strict` mode (operator explicitly chose strict) accepts codex_ran=0.
  if [ "$_mp_codex_ran" != "1" ] && [ "$_mp_mode" != "strict" ]; then
    return 1
  fi

  case "$_mp_mode" in
    strict)
      case "$_mp_verdict" in
        GO|GO_WITH_FIXES) return 0 ;;
      esac
      return 1
      ;;
    permissive)
      [ "$_mp_verdict" = "GO" ] && return 0
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# _mp_partial_order — return numeric rank for partial-order comparison.
# Pin per check synthesis risk-MF3: pr ≡ validated_today < clean.
# Forward-compat: when validated activates (autorun-runtime-validation-gate),
# `validated` will rank between `pr` and `clean` (1.5).
#
# Args: $1 = policy value
# Stdout: integer rank (lower = safer)
# ---------------------------------------------------------------------------
_mp_partial_order() {
  case "${1-}" in
    pr) echo 1 ;;
    validated) echo 1 ;;   # validated_today ≡ pr (falls back to pr until gate ships)
    clean) echo 2 ;;
    *) echo 0 ;;            # unknown — treat as below pr (silent-skip case)
  esac
}

# ---------------------------------------------------------------------------
# queue_copy_drift_check — asymmetric (D6). Halts on elevation; warns on
# downward drift; silent-skip when canonical absent.
#
# Args:
#   $1 canonical (docs/specs/<slug>/spec.md)
#   $2 queue (queue/<slug>.spec.md)
#
# Exit codes:
#   0 — no drift, downward drift (warn-only), or silent-skip
#   2 — privilege elevation detected (queue > canonical) — caller halts
# ---------------------------------------------------------------------------
queue_copy_drift_check() {
  _mp_canon="$1"
  _mp_queue="$2"

  # Cross-project / missing-canonical: silent-skip (D6).
  [ -f "$_mp_canon" ] || return 0
  [ -f "$_mp_queue" ] || return 0

  _mp_canon_state="$(merge_policy_field_state "$_mp_canon")"
  _mp_queue_state="$(merge_policy_field_state "$_mp_queue")"

  # No-op when both states match identically.
  if [ "$_mp_canon_state" = "$_mp_queue_state" ]; then
    return 0
  fi

  # Resolve effective values (absent/empty → default).
  _mp_canon_eff="$_mp_canon_state"
  _mp_queue_eff="$_mp_queue_state"
  case "$_mp_canon_eff" in absent|empty) _mp_canon_eff=pr ;; esac
  case "$_mp_queue_eff" in absent|empty) _mp_queue_eff=pr ;; esac

  # Validate both — unknown values fall to silent-skip (caller's resolver
  # will halt on invalid downstream).
  merge_policy_validate "$_mp_canon_eff" || return 0
  merge_policy_validate "$_mp_queue_eff" || return 0

  if [ "$_mp_canon_eff" = "$_mp_queue_eff" ]; then
    return 0
  fi

  _mp_canon_rank="$(_mp_partial_order "$_mp_canon_eff")"
  _mp_queue_rank="$(_mp_partial_order "$_mp_queue_eff")"

  if [ "$_mp_queue_rank" -gt "$_mp_canon_rank" ]; then
    # Privilege elevation — halt (D6 + SA-style elevation guard).
    printf '[autorun] drift error: queue copy ELEVATES auto_merge_policy above canonical.\n' >&2
    printf '          canonical (%s): %s\n' "$_mp_canon" "$_mp_canon_eff" >&2
    printf '          queue     (%s): %s\n' "$_mp_queue" "$_mp_queue_eff" >&2
    printf '          Halting per AC#13 / D6. Edit queue file or re-queue from canonical.\n' >&2
    return 2
  fi

  # Downward drift — warn only (queue is SAFER than canonical).
  printf '[autorun] drift warning: queue copy de-escalates auto_merge_policy.\n' >&2
  printf '          canonical (%s): %s\n' "$_mp_canon" "$_mp_canon_eff" >&2
  printf '          queue     (%s): %s\n' "$_mp_queue" "$_mp_queue_eff" >&2
  printf '          Queue value will be used for this run.\n' >&2
  return 0
}

# ---------------------------------------------------------------------------
# merge_policy_render_banner — runtime-config banner (D10 — stdout per R7).
#
# Args (all values + their resolved_from labels):
#   $1 slug
#   $2 policy            $3 policy_source
#   $4 gate_mode         $5 gate_mode_source
#   $6 agent_budget      $7 agent_budget_source
#   $8 max_recycles      $9 max_recycles_source
#
# Writes the banner to STDOUT (intentional output; stderr reserved for errors).
# ANSI color on warning line gated by `[ -t 1 ]` (banner stream).
# 78-col cap; right-padded with spaces for fixed-width alignment.
# ---------------------------------------------------------------------------
merge_policy_render_banner() {
  _mp_slug="$1"
  _mp_pol="$2"; _mp_pol_src="$3"
  _mp_gm="$4";  _mp_gm_src="$5"
  _mp_ab="$6";  _mp_ab_src="$7"
  _mp_mr="$8";  _mp_mr_src="$9"

  # Decide one-line summary based on resolved policy + gate_mode.
  _mp_summary=""
  case "$_mp_pol" in
    pr)        _mp_summary="open a PR but NOT auto-merge." ;;
    clean)     _mp_summary="open a PR and auto-merge if gates clean ($_mp_gm verdict)." ;;
    validated) _mp_summary="fall back to PR-only (runtime-validation-gate not shipped)." ;;
  esac

  # ANSI colors for warning line (only when stdout is a TTY — R7).
  _mp_warn_pre=""; _mp_warn_post=""
  if [ -t 1 ]; then
    _mp_warn_pre=$'\033[33m'
    _mp_warn_post=$'\033[0m'
  fi

  printf '=== autorun runtime config: %s ===\n' "$_mp_slug"
  printf 'auto_merge_policy: %-9s (resolved_from=%s)\n' "$_mp_pol" "$_mp_pol_src"
  printf 'agent_budget:      %-9s (resolved_from=%s)\n' "$_mp_ab"  "$_mp_ab_src"
  printf 'gate_mode:         %-9s (resolved_from=%s)\n' "$_mp_gm"  "$_mp_gm_src"
  printf 'gate_max_recycles: %-9s (resolved_from=%s)\n' "$_mp_mr"  "$_mp_mr_src"
  printf '\n'
  printf 'This run will: %s\n' "$_mp_summary"
  printf '\n'

  if [ "$_mp_pol_src" = "default" ]; then
    printf '%s⚠ Default flipped in v0.11.0 — auto-merge is now opt-in.%s\n' "$_mp_warn_pre" "$_mp_warn_post"
    printf '  See: docs/specs/autorun-merge-policy/spec.md\n'
    printf '\n'
  fi

  printf 'To override this run:  scripts/autorun/run.sh %s --merge-policy=clean\n' "$_mp_slug"
  printf 'To set per-spec:       add auto_merge_policy: <pr|clean|validated> to spec.md frontmatter\n'
  printf 'To set project-wide:   add auto_merge_policy to <project>/docs/specs/constitution.md\n'
  printf 'For gate-by-gate manual review instead, abort and invoke /spec-review interactively.\n'
}

# ---------------------------------------------------------------------------
# log_merge_policy_resolved — START event writer (D22 / R2).
#
# Args:
#   $1 run_log_path  (typically queue/run.log)
#   $2 slug
#   $3 policy
#   $4 resolved_from (cli|spec|constitution|default)
#   $5 gate_mode     (strict|permissive)
#   $6 spec_sha
#   $7 run_id
#
# Atomic-ish append. Best-effort on failure.
# ---------------------------------------------------------------------------
log_merge_policy_resolved() {
  _mp_log="$1"; _mp_slug="$2"; _mp_pol="$3"
  _mp_rfrom="$4"; _mp_gm="$5"; _mp_sha="$6"; _mp_rid="$7"

  _mp_dir="$(dirname "$_mp_log")"
  if [ ! -d "$_mp_dir" ]; then
    mkdir -p "$_mp_dir" 2>/dev/null || true
  fi

  _mp_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  python3 -c '
import json, sys
row = {
  "ts": sys.argv[1],
  "slug": sys.argv[2],
  "run_id": sys.argv[3],
  "event": "merge_policy_resolved",
  "policy": sys.argv[4],
  "resolved_from": sys.argv[5],
  "gate_mode": sys.argv[6],
  "spec_sha": sys.argv[7],
  "pr_number": None,
  "action": None,
  "reason": None,
  "merge_sha": None,
}
sys.stdout.write(json.dumps(row, sort_keys=True))
' "$_mp_ts" "$_mp_slug" "$_mp_rid" "$_mp_pol" "$_mp_rfrom" "$_mp_gm" "$_mp_sha" >> "$_mp_log" 2>/dev/null
  printf '\n' >> "$_mp_log" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# log_merge_action_completed — END event writer (D22).
#
# Args:
#   $1 run_log_path
#   $2 slug
#   $3 action      (pr_only|auto_merged|fell_back|merge_failed)
#   $4 reason      (closed enum or empty for null)
#   $5 pr_number   (integer or empty for null)
#   $6 merge_sha   (string or empty for null)
#   $7 run_id
#
# Called ONLY by merge_policy_dispatch (preserves D4 single-emission invariant
# for action/reason enums).
# ---------------------------------------------------------------------------
log_merge_action_completed() {
  _mp_log="$1"; _mp_slug="$2"; _mp_act="$3"
  _mp_rsn="${4-}"; _mp_prn="${5-}"; _mp_msha="${6-}"; _mp_rid="$7"

  _mp_dir="$(dirname "$_mp_log")"
  if [ ! -d "$_mp_dir" ]; then
    mkdir -p "$_mp_dir" 2>/dev/null || true
  fi

  _mp_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  python3 -c '
import json, sys
def to_int_or_none(s):
    if not s: return None
    try: return int(s)
    except (TypeError, ValueError): return None
def or_none(s):
    return s if s else None
row = {
  "ts": sys.argv[1],
  "slug": sys.argv[2],
  "run_id": sys.argv[3],
  "event": "merge_action_completed",
  "action": sys.argv[4],
  "reason": or_none(sys.argv[5]),
  "pr_number": to_int_or_none(sys.argv[6]),
  "merge_sha": or_none(sys.argv[7]),
}
sys.stdout.write(json.dumps(row, sort_keys=True))
' "$_mp_ts" "$_mp_slug" "$_mp_rid" "$_mp_act" "$_mp_rsn" "$_mp_prn" "$_mp_msha" >> "$_mp_log" 2>/dev/null
  printf '\n' >> "$_mp_log" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# _mp_sanitize_pr_body_text — SA-3 hardening.
#
# Strips control chars + zero-width joiners; refuses any text containing the
# literal `check-verdict` substring (prompt-injection vector for downstream
# LLM consumers like /code-review skill).
#
# Args: $1 = input text (typically reviewer summary or spec excerpt)
# Stdout: sanitized text
# Exit: 0 ok, 2 if `check-verdict` substring found (caller MUST hard-fail)
# ---------------------------------------------------------------------------
_mp_sanitize_pr_body_text() {
  _mp_in="${1-}"
  case "$_mp_in" in
    *check-verdict*)
      printf '[autorun] error: PR body source contains forbidden literal "check-verdict" (prompt-injection guard SA-3).\n' >&2
      return 2
      ;;
  esac
  # Strip zero-width chars (U+200B-U+200D, U+FEFF) + ANSI escape sequences.
  printf '%s' "$_mp_in" | python3 -c '
import sys, unicodedata
data = sys.stdin.read()
# NFKC-normalize.
data = unicodedata.normalize("NFKC", data)
# Strip zero-width chars.
for cp in ("​", "‌", "‍", "﻿"):
    data = data.replace(cp, "")
# Strip ANSI CSI sequences (best-effort).
import re
data = re.sub(r"\x1b\[[0-9;?]*[ -/]*[@-~]", "", data)
sys.stdout.write(data)
'
}

# ---------------------------------------------------------------------------
# Internal sub-dispatchers — private to this helper.
# Each writes EXACTLY ONE merge_action_completed end-event row.
# ---------------------------------------------------------------------------

# _mp_dispatch_pr_only — open a PR (force-push branch), do not merge.
# Sets _MP_DISPATCH_RC and _MP_DISPATCH_OUT for caller diagnostics.
_mp_dispatch_pr_only() {
  _mp_slug="$1"; _mp_pr_url="$2"; _mp_run_log="$3"; _mp_run_id="$4"; _mp_pr_num="$5"

  # In this build, gh pr create is performed by run.sh's existing path.
  # Dispatcher is invoked AFTER PR creation succeeded. We only record the row.
  log_merge_action_completed "$_mp_run_log" "$_mp_slug" pr_only "" "$_mp_pr_num" "" "$_mp_run_id"
  return 0
}

# _mp_dispatch_clean_merge — call gh pr merge --squash --auto.
# On non-zero exit, record action=merge_failed reason=branch_protection.
_mp_dispatch_clean_merge() {
  _mp_slug="$1"; _mp_pr_url="$2"; _mp_run_log="$3"; _mp_run_id="$4"; _mp_pr_num="$5"

  if [ "${MONSTERFLOW_TEST_MODE:-0}" = "1" ] && [ -n "${MERGE_POLICY_DISPATCH_OVERRIDE:-}" ]; then
    # SA-2 hardening: only honored under explicit test-mode sentinel.
    log_merge_action_completed "$_mp_run_log" "$_mp_slug" auto_merged "" "$_mp_pr_num" "" "$_mp_run_id"
    return 0
  fi

  _mp_gh="${GH_BIN:-gh}"
  _mp_merge_out=""
  _mp_merge_rc=0
  _mp_merge_out="$("$_mp_gh" pr merge "$_mp_pr_url" --squash --auto 2>&1)" || _mp_merge_rc=$?

  if [ "$_mp_merge_rc" -ne 0 ]; then
    printf '[autorun] gh pr merge failed (exit %s): %s\n' "$_mp_merge_rc" "$_mp_merge_out" >&2
    log_merge_action_completed "$_mp_run_log" "$_mp_slug" merge_failed branch_protection "$_mp_pr_num" "" "$_mp_run_id"
    return 0
  fi

  # On success, gh --auto may merge immediately or queue. merge_sha may be null
  # at this point (R6 — schema honesty). Capture SHA via a follow-up gh pr view
  # best-effort; tolerate empty result.
  _mp_state="$("$_mp_gh" pr view "$_mp_pr_url" --json state -q .state 2>/dev/null || true)"
  _mp_sha=""
  if [ "$_mp_state" = "MERGED" ]; then
    _mp_sha="$("$_mp_gh" pr view "$_mp_pr_url" --json mergeCommit -q .mergeCommit.oid 2>/dev/null || true)"
  fi
  log_merge_action_completed "$_mp_run_log" "$_mp_slug" auto_merged "" "$_mp_pr_num" "$_mp_sha" "$_mp_run_id"
  return 0
}

# _mp_dispatch_validated_merge — until autorun-runtime-validation-gate ships,
# falls back to pr per Codex H1 (NOT to clean).
_mp_dispatch_validated_merge() {
  _mp_slug="$1"; _mp_pr_url="$2"; _mp_run_log="$3"; _mp_run_id="$4"; _mp_pr_num="$5"

  printf '[autorun] %s: validated policy — runtime-validation-gate not shipped; falling back to PR-only.\n' "$_mp_slug" >&2
  log_merge_action_completed "$_mp_run_log" "$_mp_slug" fell_back validated_fallback "$_mp_pr_num" "" "$_mp_run_id"
  return 0
}

# ---------------------------------------------------------------------------
# merge_policy_dispatch — single-entry dispatcher (D4).
#
# Args:
#   $1  slug
#   $2  pr_url
#   $3  policy            (pr|clean|validated)
#   $4  resolved_from     (cli|spec|constitution|default)
#   $5  gate_mode         (strict|permissive)
#   $6  merge_capable     (0|1 — output of existing four-axis gate)
#   $7  verdict           (GO|GO_WITH_FIXES|NO_GO)
#   $8  followups_added   (integer — line-diff for this slug)
#   $9  run_id
#   $10 run_log_path
#   $11 pr_number
#   $12 codex_ran         (0|1; default 1)
#
# Rules (precedence top-to-bottom — first match wins):
#   1. .manual-review touch file present → fell_back / manual_review_requested
#   2. policy == pr → pr_only (no merge)
#   3. policy == validated → fell_back / validated_fallback (until v0.12.0)
#   4. policy == clean → if is_clean_for_merge() → auto_merge; else categorize:
#       - verdict == NO_GO → fell_back / verdict_no_go
#       - codex_ran == 0 (and not strict) → fell_back / codex_absent (SA-1)
#       - merge_capable == 0 → fell_back / warnings_present
#       - followups_added > 0 → fell_back / recycle_demoted_findings (R1/D21)
#       - default → fell_back / warnings_present
#
# SOLE caller of log_merge_action_completed (D4 invariant).
# Always returns 0 — caller's exit code is unchanged (R3 — preserve branch).
# ---------------------------------------------------------------------------
merge_policy_dispatch() {
  _mp_slug="$1"; _mp_pr_url="$2"; _mp_pol="$3"; _mp_rfrom="$4"; _mp_gm="$5"
  _mp_capable="$6"; _mp_verdict="$7"; _mp_fua="$8"; _mp_rid="$9"
  _mp_log="${10}"; _mp_prnum="${11}"; _mp_codex_ran="${12-1}"

  # Invariant: log path must be set.
  if [ -z "$_mp_log" ]; then
    printf '[autorun] internal error: merge_policy_dispatch called without run_log path\n' >&2
    return 0
  fi

  # 1) Manual-review touch file (D17 — checked just before dispatch routing).
  _mp_touch="${QUEUE_DIR:-$PROJECT_DIR/queue}/${_mp_slug}/.manual-review"
  if [ -f "$_mp_touch" ]; then
    printf '[autorun] %s: .manual-review touch file detected — skipping merge dispatch\n' "$_mp_slug"
    log_merge_action_completed "$_mp_log" "$_mp_slug" fell_back manual_review_requested "$_mp_prnum" "" "$_mp_rid"
    return 0
  fi

  case "$_mp_pol" in
    pr)
      _mp_dispatch_pr_only "$_mp_slug" "$_mp_pr_url" "$_mp_log" "$_mp_rid" "$_mp_prnum"
      return 0
      ;;
    validated)
      _mp_dispatch_validated_merge "$_mp_slug" "$_mp_pr_url" "$_mp_log" "$_mp_rid" "$_mp_prnum"
      return 0
      ;;
    clean)
      if is_clean_for_merge "$_mp_capable" "$_mp_verdict" "$_mp_gm" "$_mp_fua" "$_mp_codex_ran"; then
        _mp_dispatch_clean_merge "$_mp_slug" "$_mp_pr_url" "$_mp_log" "$_mp_rid" "$_mp_prnum"
        return 0
      fi
      # Categorize fall-back reason.
      _mp_reason="warnings_present"
      if [ "$_mp_verdict" = "NO_GO" ]; then
        _mp_reason="verdict_no_go"
      elif [ "$_mp_codex_ran" != "1" ] && [ "$_mp_gm" != "strict" ]; then
        _mp_reason="codex_absent"
      elif [ "$_mp_fua" != "0" ]; then
        _mp_reason="recycle_demoted_findings"
      fi
      log_merge_action_completed "$_mp_log" "$_mp_slug" fell_back "$_mp_reason" "$_mp_prnum" "" "$_mp_rid"
      return 0
      ;;
    *)
      # Defensive — should never happen post-validate.
      log_merge_action_completed "$_mp_log" "$_mp_slug" fell_back warnings_present "$_mp_prnum" "" "$_mp_rid"
      return 0
      ;;
  esac
}

# ---------------------------------------------------------------------------
# merge_policy_followups_count — slug-scoped count of followups for this run.
#
# Args:
#   $1 followups_path (e.g. docs/specs/<slug>/followups.jsonl)
#   $2 slug
#
# Stdout: integer count (0 if file absent).
# Used at run start (baseline) and merge dispatch (delta = current - baseline).
# ---------------------------------------------------------------------------
merge_policy_followups_count() {
  _mp_path="$1"; _mp_slug="$2"
  if [ ! -f "$_mp_path" ]; then
    echo 0
    return 0
  fi
  # Slug-scoped grep: counts JSONL rows whose "slug": "<SLUG>" string is present.
  # (Tests rely on the canonical "slug": "<value>" JSON shape.)
  _mp_n="$(grep -c "\"slug\"[[:space:]]*:[[:space:]]*\"$_mp_slug\"" "$_mp_path" 2>/dev/null || true)"
  case "$_mp_n" in
    ''|*[!0-9]*) echo 0 ;;
    *) echo "$_mp_n" ;;
  esac
}

# Sentinel: end of _merge_policy.sh (sentinel header + literal contract:
# `validated` will activate when autorun-runtime-validation-gate ships.
# DO NOT remove this comment block without updating that spec.)
