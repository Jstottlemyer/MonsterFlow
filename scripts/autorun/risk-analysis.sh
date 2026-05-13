#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$REPO_DIR}"
source "$REPO_DIR/scripts/autorun/defaults.sh"

# ---------------------------------------------------------------------------
# Validate required env vars (set by run.sh before invoking this script)
# ---------------------------------------------------------------------------
: "${SLUG:?SLUG must be set by run.sh}"
: "${ARTIFACT_DIR:?ARTIFACT_DIR must be set by run.sh}"
: "${SPEC_FILE:?SPEC_FILE must be set by run.sh}"

mkdir -p "$ARTIFACT_DIR"

# ---------------------------------------------------------------------------
# Verify spec-review output exists — design.sh depends on it being present
# for the merge step that run.sh performs.
# ---------------------------------------------------------------------------
REVIEW_FINDINGS="$ARTIFACT_DIR/review-findings.md"
if [ ! -f "$REVIEW_FINDINGS" ]; then
  echo "[autorun] risk-analysis: ERROR — $REVIEW_FINDINGS not found; spec-review.sh must complete before risk-analysis.sh"
  exit 1
fi

# ---------------------------------------------------------------------------
# AUTORUN_DRY_RUN stub mode
# ---------------------------------------------------------------------------
if [ "${AUTORUN_DRY_RUN:-0}" = "1" ]; then
  echo "[autorun] risk-analysis: DRY RUN mode — skipping claude -p invocation"

  cat > "$ARTIFACT_DIR/risk-findings.md" <<EOF
# Risk Analysis: $SLUG

## Medium-Severity Risks

### 1. Dry Run Stub
**Severity:** Medium
**Failure mode:** This is a dry-run stub; no real risk analysis was performed.
**Mitigation:** Run without AUTORUN_DRY_RUN=1 to invoke the live risk analysis agent.

## Summary
Dry-run stub written; overall risk posture is unknown. Re-run in live mode before proceeding.
EOF

  echo "[autorun] risk-analysis: dry-run artifact written; exiting 0"
  exit 0
fi

# ---------------------------------------------------------------------------
# Autonomy directive (injected via --system-prompt, NOT in the user prompt)
# ---------------------------------------------------------------------------
AUTONOMY_DIRECTIVE="You are running in fully autonomous overnight mode. Produce the risk analysis artifact now. Do not ask for approval or confirmation. Write the complete risk analysis and stop."

# ---------------------------------------------------------------------------
# Build the inline user-message prompt
# ---------------------------------------------------------------------------
PROMPT="You are a senior software architect performing a pre-implementation risk analysis. You have the following context:

## Spec
$(cat "$SPEC_FILE")

## Spec Review Findings
$(cat "$REVIEW_FINDINGS")

## Your Task
Identify the top implementation risks for this feature. For each risk:
1. Name it concisely
2. Rate severity: **High**, **Medium**, or **Low**
3. State the most likely failure mode
4. Propose a concrete mitigation

Focus on risks not already captured in the spec review findings. Limit to 5-8 risks maximum.

Format your output as:
# Risk Analysis: $SLUG

## High-Severity Risks
...

## Medium-Severity Risks
...

## Low-Severity Risks
...

## Summary
[1-2 sentences: overall risk posture, go/no-go recommendation]"

# ---------------------------------------------------------------------------
# Invoke claude -p with timeout; capture stdout to risk-findings.md,
# stderr to temp file for error reporting.
# ---------------------------------------------------------------------------
STDERR_LOG="$(mktemp "${TMPDIR:-/tmp}/autorun-risk-analysis-XXXXXX.log")"
trap 'rm -f "$STDERR_LOG"' EXIT

echo "[autorun] risk-analysis: starting claude -p (timeout=${TIMEOUT_STAGE}s, slug=$SLUG)"

CLAUDE_EXIT=0
printf '%s' "$PROMPT" | timeout "$TIMEOUT_STAGE" claude -p \
    --dangerously-skip-permissions \
    --system-prompt "$AUTONOMY_DIRECTIVE" \
    --add-dir "$PROJECT_DIR" \
    > "$ARTIFACT_DIR/risk-findings.md" \
    2>"$STDERR_LOG" || CLAUDE_EXIT=$?

if [ "$CLAUDE_EXIT" -ne 0 ]; then
  echo "[autorun] risk-analysis FAILED (claude -p exit $CLAUDE_EXIT)"
  echo "[autorun] risk-analysis: last 50 lines of stderr:"
  tail -n 50 "$STDERR_LOG" | sed 's/^/  /'
  exit 1
fi

echo "[autorun] risk-analysis: claude -p exited 0"

# ---------------------------------------------------------------------------
# Verify risk-findings.md was written and is non-empty.
# If claude -p produced no output, write a minimal fallback so run.sh's
# merge step has something to work with.
# ---------------------------------------------------------------------------
RISK_FINDINGS="$ARTIFACT_DIR/risk-findings.md"

if [ ! -f "$RISK_FINDINGS" ] || [ ! -s "$RISK_FINDINGS" ]; then
  echo "[autorun] risk-analysis: WARN — risk-findings.md missing or empty after claude -p; writing fallback"
  cat > "$RISK_FINDINGS" <<EOF
# Risk Analysis: $SLUG

## Summary
Risk analysis agent produced no output. Review manually before proceeding to plan phase.
EOF
  echo "[autorun] risk-analysis: fallback risk-findings.md written"
else
  LINES="$(wc -l < "$RISK_FINDINGS")"
  echo "[autorun] risk-analysis: risk-findings.md written (${LINES} lines)"
fi

echo "[autorun] risk-analysis: complete"
