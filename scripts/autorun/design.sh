#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$REPO_DIR}"
source "$REPO_DIR/scripts/autorun/defaults.sh"
# shellcheck disable=SC1091
source "$REPO_DIR/scripts/_pipeline_banner.sh"

# ---------------------------------------------------------------------------
# Validate required env vars (set by run.sh before calling this script)
# ---------------------------------------------------------------------------
: "${SLUG:?SLUG must be set by run.sh}"
: "${QUEUE_DIR:?QUEUE_DIR must be set by run.sh}"
: "${ARTIFACT_DIR:?ARTIFACT_DIR must be set by run.sh}"
: "${SPEC_FILE:?SPEC_FILE must be set by run.sh}"

mkdir -p "$ARTIFACT_DIR"

# ---------------------------------------------------------------------------
# Resolver pre-flight (account-type-agent-scaling + dynamic-roster-per-gate)
# design.sh runs as a single synthesis call (no parallel persona dispatch),
# but the resolver still emits the full selected roster so we can:
#   (a) write selection.json for the audit trail (persona-metrics validator
#       + /wrap-insights drift baseline)
#   (b) derive a synthesis tier (dynamic-roster-per-gate Slice 4): if ANY
#       selected persona is `opus`, the synthesis call uses opus; otherwise
#       sonnet. Rationale: planning synthesis benefits from the strongest
#       model whenever any design axis was opus-tier.
#
# Per spec AC #8: AUTORUN aborts on resolver non-zero. No silent fallback.
# ---------------------------------------------------------------------------
SYNTHESIS_TIER=""
SYNTHESIS_MODEL=""
if [ "${AUTORUN_DRY_RUN:-0}" != "1" ]; then
  RESOLVER_ERR="$(mktemp "${TMPDIR:-/tmp}/autorun-design-resolver-XXXXXX.err")"
  trap 'rm -f "$RESOLVER_ERR"' EXIT
  RESOLVER_EXIT=0
  SELECTED_RAW="$(bash "$REPO_DIR/scripts/resolve-personas.sh" design \
                    --feature "$SLUG" --with-tier --emit-selection-json 2>"$RESOLVER_ERR")" \
    || RESOLVER_EXIT=$?
  if [ "$RESOLVER_EXIT" -ne 0 ]; then
    echo "[autorun] design: ERROR — resolver exited $RESOLVER_EXIT" >&2
    if [ -s "$RESOLVER_ERR" ]; then
      sed 's/^/  /' "$RESOLVER_ERR" >&2
    fi
    exit 1
  fi

  # Parse "<persona>:<tier>" lines from resolver stdout. Tier-aware dispatch
  # (dynamic-roster-per-gate Slice 4). Bare lines:
  #   codex-adversary  → flag CODEX_REQUESTED=1; the Claude synthesis loop
  #                      still skips this line (Codex runs as a separate
  #                      post-synthesis adversarial pass below, after
  #                      design.md is written).
  #   anything else    → resolver contract violation; halt.
  SELECTED_PERSONAS=()
  SELECTED_TIERS=()
  CODEX_REQUESTED=0
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    if [ "$line" = "codex-adversary" ]; then
      CODEX_REQUESTED=1
      continue
    fi
    case "$line" in
      *:*)
        persona_name="${line%%:*}"
        tier_name="${line#*:}"
        SELECTED_PERSONAS+=("$persona_name")
        SELECTED_TIERS+=("$tier_name")
        ;;
      *)
        echo "[autorun:design] resolver emitted bare persona '$line'; expected '<persona>:<tier>' — refusing to dispatch" >&2
        exit 1
        ;;
    esac
  done <<< "$SELECTED_RAW"

  if [ "${#SELECTED_TIERS[@]}" -eq 0 ]; then
    echo "[autorun] design: ERROR — resolver emitted zero Claude personas" >&2
    exit 1
  fi

  # Validate every tier + derive synthesis tier (opus dominates).
  SYNTHESIS_TIER="sonnet"
  for t in "${SELECTED_TIERS[@]}"; do
    case "$t" in
      opus)   SYNTHESIS_TIER="opus" ;;
      sonnet) : ;;
      *)
        echo "[autorun:design] unknown tier '$t'; expected 'opus' or 'sonnet'" >&2
        exit 1
        ;;
    esac
  done
  case "$SYNTHESIS_TIER" in
    opus)   SYNTHESIS_MODEL="claude-opus-4-5" ;;
    sonnet) SYNTHESIS_MODEL="claude-sonnet-4-6" ;;
  esac
  echo "[autorun] design: resolver selected: ${SELECTED_PERSONAS[*]} | synthesis tier=$SYNTHESIS_TIER → $SYNTHESIS_MODEL"
fi

# ---------------------------------------------------------------------------
# Dependency: review-findings.md must exist (written by run.sh after risk merge)
# ---------------------------------------------------------------------------
if [ ! -f "$ARTIFACT_DIR/review-findings.md" ]; then
  echo "[autorun] design: ERROR — $ARTIFACT_DIR/review-findings.md not found"
  echo "[autorun] design: run.sh must merge risk-findings.md into review-findings.md before calling design.sh"
  exit 1
fi

# ---------------------------------------------------------------------------
# AUTORUN_DRY_RUN stub mode
# ---------------------------------------------------------------------------
if [ "${AUTORUN_DRY_RUN:-0}" = "1" ]; then
  echo "[autorun] design: DRY RUN mode — skipping claude -p invocation"

  cat > "$ARTIFACT_DIR/design.md" <<'EOF'
# Design (DRY RUN)
**Note:** Dry-run stub.
EOF

  echo "[autorun] design: dry-run artifact written; exiting 0"
  exit 0
fi

# ---------------------------------------------------------------------------
# Autonomy directive (injected via --system-prompt)
# ---------------------------------------------------------------------------
AUTONOMY_DIRECTIVE="You are running in fully autonomous overnight mode. Generate the implementation plan now. Do not ask for approval. Write design.md to docs/specs/$SLUG/design.md and stop."

# ---------------------------------------------------------------------------
# Build the user-message prompt
# ---------------------------------------------------------------------------
PROMPT="$(cat "$REPO_DIR/commands/design.md")

---
AUTORUN_CONTEXT:
- SLUG: $SLUG
- SPEC_FILE: $SPEC_FILE
- REVIEW_FINDINGS_FILE: $ARTIFACT_DIR/review-findings.md
- AUTORUN: 1
- MODE: headless autonomous — generate the implementation plan, write design.md, then stop. Do not ask for approval.

## Spec
$(cat "$SPEC_FILE")

## Review Findings (includes risk analysis)
$(cat "$ARTIFACT_DIR/review-findings.md")"

# Banner: stage start (T7 — AC18) — gate name is "blueprint" (slash-command name)
_pipeline_banner_start "blueprint" "$SLUG"

# ---------------------------------------------------------------------------
# Invoke claude -p with timeout; capture stderr for diagnostics
# ---------------------------------------------------------------------------
STDERR_LOG="$(mktemp "${TMPDIR:-/tmp}/autorun-design-XXXXXX.log")"
STDOUT_LOG="$(mktemp "${TMPDIR:-/tmp}/autorun-design-stdout-XXXXXX.log")"
# Extend the early RESOLVER_ERR trap to also clean the synthesis logs. The
# resolver-block trap was set at line ~34 and would otherwise be replaced
# (bash traps are last-wins). Re-include "$RESOLVER_ERR" so its cleanup
# survives. Empty variable in DRY-RUN mode is harmless to `rm -f`.
trap 'rm -f "$RESOLVER_ERR" "$STDERR_LOG" "$STDOUT_LOG"' EXIT

echo "[autorun] design: starting claude -p (timeout=${TIMEOUT_STAGE}s, slug=$SLUG, model=$SYNTHESIS_MODEL)"
# No --add-dir: spec + review-findings are passed inline; removing 400-file context load

CLAUDE_EXIT=0
printf '%s' "$PROMPT" | timeout "$TIMEOUT_STAGE" claude -p \
    --dangerously-skip-permissions \
    --model "$SYNTHESIS_MODEL" \
    --system-prompt "$AUTONOMY_DIRECTIVE" \
    >"$STDOUT_LOG" \
    2>"$STDERR_LOG" || CLAUDE_EXIT=$?

if [ "$CLAUDE_EXIT" -ne 0 ]; then
  echo "[autorun] design: FAILED (claude -p exit $CLAUDE_EXIT)"
  echo "[autorun] design: last 50 lines of stderr:"
  tail -n 50 "$STDERR_LOG" | sed 's/^/  /'
  exit 1
fi

echo "[autorun] design: claude -p exited 0"

# ---------------------------------------------------------------------------
# Artifact verification: check docs/specs/$SLUG/design.md first,
# then fall back to stdout capture
# ---------------------------------------------------------------------------
PLAN_CANONICAL="$PROJECT_DIR/docs/specs/$SLUG/design.md"

if [ -f "$PLAN_CANONICAL" ]; then
  cp "$PLAN_CANONICAL" "$ARTIFACT_DIR/design.md"
  echo "[autorun] design: design.md copied from $PLAN_CANONICAL"
else
  echo "[autorun] design: WARN — $PLAN_CANONICAL not found; capturing stdout as plan content"
  if [ -s "$STDOUT_LOG" ]; then
    cp "$STDOUT_LOG" "$ARTIFACT_DIR/design.md"
    echo "[autorun] design: design.md written from stdout capture ($(wc -l < "$ARTIFACT_DIR/design.md") lines)"
  else
    echo "[autorun] design: ERROR — stdout was also empty; design.md not written"
    exit 1
  fi
fi

# Final verification
if [ ! -f "$ARTIFACT_DIR/design.md" ]; then
  echo "[autorun] design: ERROR — $ARTIFACT_DIR/design.md was not written"
  exit 1
fi

echo "[autorun] design: $ARTIFACT_DIR/design.md written ($(wc -l < "$ARTIFACT_DIR/design.md") lines)"

# Banner: stage end (T7 — AC18) — emitted after design.md is persisted
_pipeline_banner_end "blueprint" "$SLUG"

# ---------------------------------------------------------------------------
# Codex adversarial design critique (post-synthesis pass)
#
# Activated when the resolver emitted `codex-adversary` for this gate (i.e.
# `agent_budget` is configured and Codex is authenticated). Runs after the
# Claude synthesis has produced design.md so Codex critiques the actual proposed
# design, not just the inputs.
#
# Failure is non-fatal: a probe/timeout/exec failure logs a warning and
# continues with the Claude-only design.md. The pipeline never halts here.
#
# Output: appends a labeled "## Adversarial Design Critique (Codex)" section
# to design.md (so /check sees it via its existing design.md read) AND writes a
# sibling `design-codex-findings.md` for downstream tooling / morning-report use.
# ---------------------------------------------------------------------------
if [ "${AUTORUN_DRY_RUN:-0}" != "1" ] && [ "${CODEX_REQUESTED:-0}" = "1" ]; then
  CODEX_PROBE_BIN="${AUTORUN_CODEX_PROBE_BIN:-$REPO_DIR/scripts/autorun/_codex_probe.sh}"
  CODEX_PROBE_EXIT=0
  bash "$CODEX_PROBE_BIN" >/dev/null 2>&1 || CODEX_PROBE_EXIT=$?

  if [ "$CODEX_PROBE_EXIT" -eq 0 ]; then
    echo "[autorun] design: running Codex adversarial design critique (timeout=${TIMEOUT_CODEX}s)"
    CODEX_DESIGN_OUT="$(mktemp -t "autorun-design-codex.XXXXXX")"
    CODEX_DESIGN_CTX="$(mktemp -t "autorun-design-codex-ctx.XXXXXX")"
    {
      printf '## Spec\n'
      cat "$SPEC_FILE"
      printf '\n## Review Findings\n'
      cat "$ARTIFACT_DIR/review-findings.md"
      printf '\n## Proposed Plan (Claude synthesis)\n'
      cat "$ARTIFACT_DIR/design.md"
    } > "$CODEX_DESIGN_CTX"

    CODEX_DESIGN_EXIT=0
    timeout "$TIMEOUT_CODEX" codex exec \
        --full-auto --ephemeral \
        --output-last-message "$CODEX_DESIGN_OUT" \
        "You are an adversarial design reviewer. The Claude synthesis above produced a Plan to satisfy the Spec. Identify design problems Claude missed.

For each finding, prefix with severity + axis class (same convention as /check):
  **High [architectural]:** | **High [security]:** | **High [contract]:** | **High [tests]:** | **High [documentation]:** | **High [scope-cuts]:**
  **Medium [...]:** (same axes)
  **Low [...]:** (same axes)

Focus on:
- Design gaps that violate spec invariants
- Implicit assumptions the plan depends on that are not called out
- Missing parallelization or wave-sequencing risk
- Data/schema choices that lock in a hard-to-reverse decision
- Test/verification coverage gaps before /build

Be terse. Aim for under 500 words total. No preamble; start with the first finding." \
        < "$CODEX_DESIGN_CTX" \
        2>/dev/null || CODEX_DESIGN_EXIT=$?

    if [ "$CODEX_DESIGN_EXIT" -eq 0 ] && [ -s "$CODEX_DESIGN_OUT" ]; then
      {
        printf '\n\n---\n\n## Adversarial Design Critique (Codex)\n\n'
        cat "$CODEX_DESIGN_OUT"
      } >> "$ARTIFACT_DIR/design.md"
      cp "$CODEX_DESIGN_OUT" "$ARTIFACT_DIR/design-codex-findings.md"
      # Mirror back to the canonical spec dir so re-reads stay consistent.
      PLAN_CANONICAL_DIR="$PROJECT_DIR/docs/specs/$SLUG"
      if [ -f "$PLAN_CANONICAL_DIR/design.md" ]; then
        cp "$ARTIFACT_DIR/design.md" "$PLAN_CANONICAL_DIR/design.md"
      fi
      echo "[autorun] design: Codex critique appended ($(wc -l < "$CODEX_DESIGN_OUT") lines)"
    else
      echo "[autorun] design: WARN — Codex critique skipped/failed (exit $CODEX_DESIGN_EXIT); continuing with Claude-only design.md" >&2
    fi
    rm -f "$CODEX_DESIGN_OUT" "$CODEX_DESIGN_CTX"
  else
    case "$CODEX_PROBE_EXIT" in
      1) echo "[autorun] design: Codex unavailable (binary not on PATH) — skipping critique" >&2 ;;
      2) echo "[autorun] design: Codex unavailable (auth-failed) — skipping critique" >&2 ;;
      *) echo "[autorun] design: Codex probe exit=$CODEX_PROBE_EXIT — skipping critique" >&2 ;;
    esac
  fi
fi

echo "[autorun] design: complete"
