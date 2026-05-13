#!/bin/bash
##############################################################################
# scripts/autorun/verify.sh
#
# Post-build spec compliance verifier. Runs INSIDE the build.sh retry loop
# after tests pass. Checks that every explicit spec requirement is present
# in the committed code changes — not just that routes load.
#
# Outcome classification (Task 3.4 — autorun-overnight-policy v6):
#   - INFRA ERROR  iff exit ∈ {124, 127, 130}  (timeout / missing-binary /
#                  signal-killed)  OR  (exit==0 AND len(strip(body)) < 16).
#                  These mean "verifier didn't actually run". Routed via
#                  policy_act verify_infra "<reason>"  — warn-eligible in
#                  overnight, block in supervised.
#   - SUBSTANTIVE FAILURE = test fail / gap detected / exit nonzero with
#                  content. The verifier is asserting "build is incorrect".
#                  Always blocks via policy_block verify verify_infra "<reason>"
#                  (NOT subject to verify_infra_policy — see spec line 360,
#                  edge case 8).
#   - COMPLIANT  = exit 0 with body containing a VERDICT line.
#
# Exit codes (after policy resolution):
#   0 — COMPLIANT, or warn-eligible infra error in overnight mode (RUN_DEGRADED
#       set sticky via policy_warn).
#   1 — INCOMPLETE (substantive failure) or blocked infra error (supervised).
#
# Writes: $ARTIFACT_DIR/verify-gaps.md
##############################################################################
set -uo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$REPO_DIR}"
# shellcheck disable=SC1091
source "$REPO_DIR/scripts/autorun/defaults.sh"
# shellcheck disable=SC1091
source "$REPO_DIR/scripts/autorun/_policy.sh"

: "${SLUG:?SLUG must be set by build.sh}"
: "${QUEUE_DIR:?QUEUE_DIR must be set by build.sh}"
: "${ARTIFACT_DIR:?ARTIFACT_DIR must be set by build.sh}"
: "${SPEC_FILE:?SPEC_FILE must be set by build.sh}"

# Stage marker for policy_act (D37). build.sh's update_stage() should have
# already exported this, but pin it defensively for direct invocation.
export AUTORUN_CURRENT_STAGE="${AUTORUN_CURRENT_STAGE:-verify}"

mkdir -p "$ARTIFACT_DIR"

# render_morning_report — placeholder hook used at policy_act block sites
# per the D37 pattern. run.sh owns the real implementation; verify.sh only
# needs to ensure it's defined (no-op if absent) before calling exit 1.
if ! command -v render_morning_report >/dev/null 2>&1; then
  render_morning_report() { :; }
fi

# ---------------------------------------------------------------------------
# DRY RUN stub
# ---------------------------------------------------------------------------
if [ "${AUTORUN_DRY_RUN:-0}" = "1" ]; then
  echo "[autorun] verify: DRY RUN mode — writing stub COMPLIANT result"
  printf '## Spec Compliance (DRY RUN)\n\nVERDICT: COMPLIANT\n' > "$ARTIFACT_DIR/verify-gaps.md"
  exit 0
fi

# ---------------------------------------------------------------------------
# Test hook: VERIFY_TEST_MODE=1 lets tests inject a canned (exit, body) pair
# without spinning up `claude -p`. The override is intentionally narrow —
# it skips git-state preflight + the verifier invocation; everything else
# (classifier predicate, policy routing) runs unchanged.
# ---------------------------------------------------------------------------
if [ "${VERIFY_TEST_MODE:-0}" = "1" ]; then
  VERIFY_EXIT="${VERIFY_TEST_EXIT:-0}"
  VERIFY_BODY="${VERIFY_TEST_BODY:-}"
  printf '%s' "$VERIFY_BODY" > "$ARTIFACT_DIR/verify-gaps.md"
else
  # -------------------------------------------------------------------------
  # Collect build context
  # -------------------------------------------------------------------------
  PRE_BUILD_SHA="$(cat "$ARTIFACT_DIR/pre-build-sha.txt" 2>/dev/null || echo "")"

  if [ -z "$PRE_BUILD_SHA" ]; then
    echo "[autorun] verify: WARN — no pre-build SHA found; skipping compliance check"
    exit 0
  fi

  CURRENT_SHA="$(git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null || echo "")"
  if [ -z "$CURRENT_SHA" ] || [ "$CURRENT_SHA" = "$PRE_BUILD_SHA" ]; then
    echo "[autorun] verify: FAIL — no commits since pre-build SHA; build agent produced nothing"
    printf 'VERDICT: INCOMPLETE — build agent produced no commits\n' > "$ARTIFACT_DIR/verify-gaps.md"
    # Substantive failure (build produced nothing) — block-by-default, NOT subject to verify_infra_policy.
    # Per audit Medium finding: an agent producing zero commits is substantive, not infra.
    policy_block verify verify_infra "no commits since pre-build SHA (substantive)" || true
    render_morning_report
    exit 1
  fi

  EXPECTED_BRANCH="autorun/$SLUG"
  CURRENT_BRANCH="$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
  if [ "$CURRENT_BRANCH" != "$EXPECTED_BRANCH" ]; then
    echo "[autorun] verify: FAIL — agent on '$CURRENT_BRANCH', expected '$EXPECTED_BRANCH'"
    printf 'VERDICT: INCOMPLETE — build agent committed to wrong branch (%s != %s)\n' \
      "$CURRENT_BRANCH" "$EXPECTED_BRANCH" > "$ARTIFACT_DIR/verify-gaps.md"
    if ! policy_block verify verify_infra "build agent on wrong branch ($CURRENT_BRANCH != $EXPECTED_BRANCH)"; then
      render_morning_report
      exit 1
    fi
    exit 1
  fi

  # Compute the true diff line count BEFORE truncating, so an exact-3000-line
  # diff isn't falsely flagged as truncated. The 3000-line cap still applies to
  # what we pass to the verifier prompt.
  GIT_DIFF_RAW="$(git -C "$PROJECT_DIR" diff "$PRE_BUILD_SHA" HEAD -- . 2>/dev/null || echo "(diff unavailable)")"
  TRUE_DIFF_LINES="$(printf '%s\n' "$GIT_DIFF_RAW" | wc -l | tr -d ' ')"
  GIT_DIFF="$(printf '%s\n' "$GIT_DIFF_RAW" | head -3000)"
  DIFF_LINE_COUNT="$(printf '%s\n' "$GIT_DIFF" | wc -l | tr -d ' ')"

  TRUNCATION_NOTE=""
  if [ "$TRUE_DIFF_LINES" -gt 3000 ]; then
    TRUNCATION_NOTE="
WARNING: diff was truncated at 3000 lines (true size: ${TRUE_DIFF_LINES} lines). Requirements implemented after line 3000 are NOT visible — mark any requirement without clear diff evidence as [FAIL]."
  fi

  echo "[autorun] verify: checking compliance for $SLUG (diff: ~${DIFF_LINE_COUNT} lines)"

  # -------------------------------------------------------------------------
  # Build verification prompt
  # -------------------------------------------------------------------------
  VERIFY_PROMPT="You are a post-build spec compliance verifier. Your job is to check whether every explicit requirement in the spec is present in the committed code changes.

## Critical Rules
- 'A route exists' or 'a page renders' is NOT compliance for a requirement that specifies UI elements, access gates, or specific data fields.
- 'A file was created' is NOT compliance unless the spec's specific content or behavior is present in the diff.
- If there is no clear diff evidence for a requirement, mark it [FAIL].
- Be strict. If in doubt, mark [FAIL].
- Do NOT judge code quality — only whether the requirement is present.

## Spec
$(head -1000 "$SPEC_FILE")

## Plan
$(head -500 "$ARTIFACT_DIR/design.md" 2>/dev/null || echo "(plan not available)")

## Committed Changes (git diff since pre-build SHA, capped at 3000 lines — ${DIFF_LINE_COUNT} actual lines shown)
${TRUNCATION_NOTE}
$GIT_DIFF

## Output Format
For each explicit spec requirement, output exactly one line:
[PASS] <requirement summary>
or
[FAIL] <requirement summary> — <specific reason: what is missing from the diff>

After listing all requirements, output exactly one of these verdict lines:
VERDICT: COMPLIANT
VERDICT: INCOMPLETE — <N> requirement(s) not met"

  # -------------------------------------------------------------------------
  # Invoke claude -p
  # -------------------------------------------------------------------------
  VERIFY_STDERR="$(mktemp "${TMPDIR:-/tmp}/autorun-verify-XXXXXX.log")"
  trap 'rm -f "$VERIFY_STDERR"' EXIT

  # Capture claude's exit code (PIPESTATUS[1]) at failure time. `|| true`
  # would reset PIPESTATUS to reflect `true`'s exit, so we capture inside
  # the `||` branch where PIPESTATUS still reflects the pipeline.
  VERIFY_EXIT=0
  printf '%s' "$VERIFY_PROMPT" | timeout "${TIMEOUT_VERIFY:-600}" claude -p \
    --dangerously-skip-permissions \
    --system-prompt "You are a strict spec compliance verifier. Be precise and concise. Do not implement anything — only report what is and is not present in the diff." \
    2>"$VERIFY_STDERR" | tee "$ARTIFACT_DIR/verify-gaps.md" || VERIFY_EXIT=${PIPESTATUS[1]}

  VERIFY_BODY="$(cat "$ARTIFACT_DIR/verify-gaps.md" 2>/dev/null || echo "")"
fi

# ---------------------------------------------------------------------------
# Outcome classifier (Task 3.4 — v6 mandatory predicate)
#
# INFRA ERROR iff:
#   exit ∈ {124, 127, 130}                       — timeout, no-such-binary,
#                                                  signal-killed
#   OR (exit == 0 AND len(strip(body)) < 16)     — verifier returned 0 but
#                                                  produced essentially no
#                                                  content (truncated stdout,
#                                                  network blip, etc.)
#
# Either condition means "verifier didn't actually run / didn't produce a
# usable verdict". Distinct from the verifier saying "the build is wrong"
# (substantive failure) because we shouldn't BLOCK a run just because our
# verifier infra failed — that's what verify_infra_policy is for (warn in
# overnight, block in supervised).
# ---------------------------------------------------------------------------
VERIFY_BODY_STRIPPED="$(printf '%s' "${VERIFY_BODY:-}" | tr -d '[:space:]')"
VERIFY_BODY_STRIPPED_LEN="${#VERIFY_BODY_STRIPPED}"

IS_INFRA=0
INFRA_REASON=""
if [ "$VERIFY_EXIT" -eq 124 ]; then
  IS_INFRA=1
  INFRA_REASON="verifier timed out (exit 124)"
elif [ "$VERIFY_EXIT" -eq 127 ]; then
  IS_INFRA=1
  INFRA_REASON="verifier binary not found (exit 127)"
elif [ "$VERIFY_EXIT" -eq 130 ]; then
  IS_INFRA=1
  INFRA_REASON="verifier killed by signal (exit 130)"
elif [ "$VERIFY_EXIT" -eq 0 ] && [ "$VERIFY_BODY_STRIPPED_LEN" -lt 16 ]; then
  IS_INFRA=1
  INFRA_REASON="verifier produced empty body (len=$VERIFY_BODY_STRIPPED_LEN)"
fi

if [ "$IS_INFRA" -eq 1 ]; then
  echo "[autorun] verify: infra error — $INFRA_REASON"
  if ! policy_act verify_infra "$INFRA_REASON"; then
    render_morning_report
    exit 1
  fi
  # warn path: degrade run but continue; build/PR creation still proceed.
  exit 0
fi

# ---------------------------------------------------------------------------
# Substantive outcome: parse verdict from body. NOT subject to verify_infra
# policy — substantive failures always block (spec edge case 8 / line 360).
# ---------------------------------------------------------------------------
if printf '%s' "$VERIFY_BODY" | grep -iq "^VERDICT: INCOMPLETE"; then
  FAIL_COUNT="$(printf '%s\n' "$VERIFY_BODY" | grep -ic '^\[FAIL\]' || true)"
  FAIL_COUNT="${FAIL_COUNT:-0}"
  echo "[autorun] verify: INCOMPLETE — ${FAIL_COUNT} requirement(s) not met in $SLUG"
  policy_block verify verify_infra "verifier reported INCOMPLETE: ${FAIL_COUNT} requirement(s) not met" || true
  render_morning_report
  exit 1
fi

if [ "$VERIFY_EXIT" -ne 0 ]; then
  echo "[autorun] verify: verifier exited $VERIFY_EXIT with content — substantive failure"
  policy_block verify verify_infra "verifier exited $VERIFY_EXIT with content" || true
  render_morning_report
  exit 1
fi

PASS_COUNT="$(printf '%s\n' "$VERIFY_BODY" | grep -ic '^\[PASS\]' || true)"
PASS_COUNT="${PASS_COUNT:-0}"
echo "[autorun] verify: COMPLIANT — ${PASS_COUNT} requirement(s) verified for $SLUG"
exit 0
