#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$REPO_DIR}"
source "$REPO_DIR/scripts/autorun/defaults.sh"

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
# plan.sh runs as a single synthesis call (no parallel persona dispatch),
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
  RESOLVER_ERR="$(mktemp "${TMPDIR:-/tmp}/autorun-plan-resolver-XXXXXX.err")"
  trap 'rm -f "$RESOLVER_ERR"' EXIT
  RESOLVER_EXIT=0
  SELECTED_RAW="$(bash "$REPO_DIR/scripts/resolve-personas.sh" plan \
                    --feature "$SLUG" --with-tier --emit-selection-json 2>"$RESOLVER_ERR")" \
    || RESOLVER_EXIT=$?
  if [ "$RESOLVER_EXIT" -ne 0 ]; then
    echo "[autorun] plan: ERROR — resolver exited $RESOLVER_EXIT" >&2
    if [ -s "$RESOLVER_ERR" ]; then
      sed 's/^/  /' "$RESOLVER_ERR" >&2
    fi
    exit 1
  fi

  # Parse "<persona>:<tier>" lines from resolver stdout. Tier-aware dispatch
  # (dynamic-roster-per-gate Slice 4). Bare lines:
  #   codex-adversary  → skip (Codex at /plan currently disabled; run.sh
  #                      handles any Codex dispatch separately)
  #   anything else    → resolver contract violation; halt.
  SELECTED_PERSONAS=()
  SELECTED_TIERS=()
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    if [ "$line" = "codex-adversary" ]; then
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
        echo "[autorun:plan] resolver emitted bare persona '$line'; expected '<persona>:<tier>' — refusing to dispatch" >&2
        exit 1
        ;;
    esac
  done <<< "$SELECTED_RAW"

  if [ "${#SELECTED_TIERS[@]}" -eq 0 ]; then
    echo "[autorun] plan: ERROR — resolver emitted zero Claude personas" >&2
    exit 1
  fi

  # Validate every tier + derive synthesis tier (opus dominates).
  SYNTHESIS_TIER="sonnet"
  for t in "${SELECTED_TIERS[@]}"; do
    case "$t" in
      opus)   SYNTHESIS_TIER="opus" ;;
      sonnet) : ;;
      *)
        echo "[autorun:plan] unknown tier '$t'; expected 'opus' or 'sonnet'" >&2
        exit 1
        ;;
    esac
  done
  case "$SYNTHESIS_TIER" in
    opus)   SYNTHESIS_MODEL="claude-opus-4-5" ;;
    sonnet) SYNTHESIS_MODEL="claude-sonnet-4-6" ;;
  esac
  echo "[autorun] plan: resolver selected: ${SELECTED_PERSONAS[*]} | synthesis tier=$SYNTHESIS_TIER → $SYNTHESIS_MODEL"
fi

# ---------------------------------------------------------------------------
# Dependency: review-findings.md must exist (written by run.sh after risk merge)
# ---------------------------------------------------------------------------
if [ ! -f "$ARTIFACT_DIR/review-findings.md" ]; then
  echo "[autorun] plan: ERROR — $ARTIFACT_DIR/review-findings.md not found"
  echo "[autorun] plan: run.sh must merge risk-findings.md into review-findings.md before calling plan.sh"
  exit 1
fi

# ---------------------------------------------------------------------------
# AUTORUN_DRY_RUN stub mode
# ---------------------------------------------------------------------------
if [ "${AUTORUN_DRY_RUN:-0}" = "1" ]; then
  echo "[autorun] plan: DRY RUN mode — skipping claude -p invocation"

  cat > "$ARTIFACT_DIR/plan.md" <<'EOF'
# Plan (DRY RUN)
**Note:** Dry-run stub.
EOF

  echo "[autorun] plan: dry-run artifact written; exiting 0"
  exit 0
fi

# ---------------------------------------------------------------------------
# Autonomy directive (injected via --system-prompt)
# ---------------------------------------------------------------------------
AUTONOMY_DIRECTIVE="You are running in fully autonomous overnight mode. Generate the implementation plan now. Do not ask for approval. Write plan.md to docs/specs/$SLUG/plan.md and stop."

# ---------------------------------------------------------------------------
# Build the user-message prompt
# ---------------------------------------------------------------------------
PROMPT="$(cat "$REPO_DIR/commands/plan.md")

---
AUTORUN_CONTEXT:
- SLUG: $SLUG
- SPEC_FILE: $SPEC_FILE
- REVIEW_FINDINGS_FILE: $ARTIFACT_DIR/review-findings.md
- AUTORUN: 1
- MODE: headless autonomous — generate the implementation plan, write plan.md, then stop. Do not ask for approval.

## Spec
$(cat "$SPEC_FILE")

## Review Findings (includes risk analysis)
$(cat "$ARTIFACT_DIR/review-findings.md")"

# ---------------------------------------------------------------------------
# Invoke claude -p with timeout; capture stderr for diagnostics
# ---------------------------------------------------------------------------
STDERR_LOG="$(mktemp "${TMPDIR:-/tmp}/autorun-plan-XXXXXX.log")"
STDOUT_LOG="$(mktemp "${TMPDIR:-/tmp}/autorun-plan-stdout-XXXXXX.log")"
# Extend the early RESOLVER_ERR trap to also clean the synthesis logs. The
# resolver-block trap was set at line ~34 and would otherwise be replaced
# (bash traps are last-wins). Re-include "$RESOLVER_ERR" so its cleanup
# survives. Empty variable in DRY-RUN mode is harmless to `rm -f`.
trap 'rm -f "$RESOLVER_ERR" "$STDERR_LOG" "$STDOUT_LOG"' EXIT

echo "[autorun] plan: starting claude -p (timeout=${TIMEOUT_STAGE}s, slug=$SLUG, model=$SYNTHESIS_MODEL)"
# No --add-dir: spec + review-findings are passed inline; removing 400-file context load

CLAUDE_EXIT=0
printf '%s' "$PROMPT" | timeout "$TIMEOUT_STAGE" claude -p \
    --dangerously-skip-permissions \
    --model "$SYNTHESIS_MODEL" \
    --system-prompt "$AUTONOMY_DIRECTIVE" \
    >"$STDOUT_LOG" \
    2>"$STDERR_LOG" || CLAUDE_EXIT=$?

if [ "$CLAUDE_EXIT" -ne 0 ]; then
  echo "[autorun] plan: FAILED (claude -p exit $CLAUDE_EXIT)"
  echo "[autorun] plan: last 50 lines of stderr:"
  tail -n 50 "$STDERR_LOG" | sed 's/^/  /'
  exit 1
fi

echo "[autorun] plan: claude -p exited 0"

# ---------------------------------------------------------------------------
# Artifact verification: check docs/specs/$SLUG/plan.md first,
# then fall back to stdout capture
# ---------------------------------------------------------------------------
PLAN_CANONICAL="$PROJECT_DIR/docs/specs/$SLUG/plan.md"

if [ -f "$PLAN_CANONICAL" ]; then
  cp "$PLAN_CANONICAL" "$ARTIFACT_DIR/plan.md"
  echo "[autorun] plan: plan.md copied from $PLAN_CANONICAL"
else
  echo "[autorun] plan: WARN — $PLAN_CANONICAL not found; capturing stdout as plan content"
  if [ -s "$STDOUT_LOG" ]; then
    cp "$STDOUT_LOG" "$ARTIFACT_DIR/plan.md"
    echo "[autorun] plan: plan.md written from stdout capture ($(wc -l < "$ARTIFACT_DIR/plan.md") lines)"
  else
    echo "[autorun] plan: ERROR — stdout was also empty; plan.md not written"
    exit 1
  fi
fi

# Final verification
if [ ! -f "$ARTIFACT_DIR/plan.md" ]; then
  echo "[autorun] plan: ERROR — $ARTIFACT_DIR/plan.md was not written"
  exit 1
fi

echo "[autorun] plan: $ARTIFACT_DIR/plan.md written ($(wc -l < "$ARTIFACT_DIR/plan.md") lines)"
echo "[autorun] plan: complete"
