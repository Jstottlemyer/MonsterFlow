#!/usr/bin/env bash
##############################################################################
# tests/run-tests.sh
#
# Top-level test runner for MonsterFlow. Runs every test script under tests/,
# captures their pass/fail, and reports a summary. CI-friendly: exits non-zero
# if any test failed.
#
# Usage:
#   bash tests/run-tests.sh [test-name]
#
# Without args, runs all tests. With a name (e.g. "hooks"), runs just
# tests/test-hooks.sh.
##############################################################################
set -uo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TESTS_DIR="$ENGINE_DIR/tests"
ONLY="${1:-}"

# Tests in execution order. Cheapest first so failures surface fast.
TESTS=(
  test-hooks.sh
  test-agents.sh
  test-skills.sh
  test-bump-version.sh
  # token-economics tests (cheapest first per code-review rec)
  test-no-raw-print.sh
  test-phase-0-artifact.sh
  test-allowlist.sh
  test-allowlist-inverted.sh        # M8: must exit non-zero (handled below)
  test-path-validation.sh
  test-finding-id-salt.sh
  test-scan-confirmation.sh
  test-wrap-insights-text.sh
  test-dashboard-render.sh
  test-compute-persona-value.sh
  test-build-final.sh
  autorun-dryrun.sh
  # install-rewrite W4 — supply-chain gate first (cheap), then full install harness
  test-config-content.sh
  test-install.sh
  # account-type-agent-scaling — per-gate persona resolver
  test-resolve-personas.sh
  # autorun-overnight-policy — Codex availability + auth probe (Task 2.2)
  test-codex-probe.sh
  # autorun-overnight-policy — _policy_json.py stdlib backend (Task 2.1b)
  test-policy-json.sh
  # pipeline-gate-permissiveness — _policy_json.py v2 schema additions (W1.4)
  test-policy-json-v2.sh
  # autorun-overnight-policy — _policy.sh shell helper API (Task 2.1)
  test-policy-sh.sh
  # autorun-overnight-policy — verify.sh infra-error classifier (Task 3.4)
  # pipeline-gate-permissiveness W1.8 — autorun lockstep CI guard appended below
  test-autorun-policy.sh
  # autorun-overnight-policy — integration smoke (Task 3.10)
  test-autorun-smoke.sh
  # autorun-overnight-policy — doctor.sh diagnostic surface (Task 5.4)
  test-doctor.sh
  # pipeline-gate-permissiveness — render-followups.py JSONL→MD renderer (W1.6)
  test-render-followups.sh
  # pipeline-gate-permissiveness — check.sh v2 verdict field handling (W1.x)
  test-check-sh-v2-fields.sh
  # pipeline-gate-permissiveness — install.sh followups gitignore block (W1.x)
  test-install-followups-gitignore.sh
  # pipeline-gate-permissiveness W2.1 — class-tagging template canonical content
  test-class-tagging-template.sh
  # pipeline-gate-permissiveness W2.2 — proof-point splice into scope.md
  test-w2-scope-discipline-spliced.sh
  # pipeline-gate-permissiveness W2.3 — judge.md class-aware-dedup section
  test-judge-class-aware-dedup.sh
  # pipeline-gate-permissiveness W2.4 — synthesis v2 (check-verdict@2.0) contract
  test-synthesis-v2-contract.sh
  # pipeline-gate-permissiveness W2.5 — class-tagging splice coverage dry-run
  test-dry-run-class-coverage.sh
  # pipeline-gate-permissiveness W3.1 — class-tagging splice script (dry-run + real)
  test-class-tagging-spliced.sh
  # pipeline-gate-permissiveness W3.3 — _gate-mode.md shared include canonical contents
  test-gate-mode-include.sh
  # pipeline-gate-permissiveness W3.4 — _gate_helpers.sh function library
  test-gate-helpers.sh
  # pipeline-gate-permissiveness W3.8b — build-mark-addressed.py state:addressed write-back
  test-build-mark-addressed.sh
  # pipeline-gate-permissiveness W3.10 — persona-insights renderer class back-fill
  test-render-persona-insights-class-backfill.sh
  # pipeline-gate-permissiveness W3.2b — independent post-splice structural validator
  test-personas-post-splice.sh
  # pipeline-gate-permissiveness W3.5 — commands/spec-review.md gate-mode Phase 0c
  test-spec-review-gate-mode.sh
  # pipeline-gate-permissiveness W3.6 — commands/plan.md gate-mode Phase 0c
  test-plan-gate-mode.sh
  # pipeline-gate-permissiveness W3.7 — commands/check.md gate-mode Phase 0c + cap-reached
  test-check-gate-mode.sh
  # pipeline-gate-permissiveness W3.8 — commands/build.md verdict-gated followups consumer + Phase 4
  test-build-followups-consumer.sh
  # pipeline-gate-permissiveness W3.9 — commands/spec.md frontmatter gate fields
  test-spec-frontmatter-gate-fields.sh
  # pipeline-gate-permissiveness W4.1 — docs/index.html three-tier verdict mermaid
  test-docs-index-three-tier-verdict.sh
  # pipeline-gate-permissiveness W4.2 — CHANGELOG.md v0.9.0 entry
  test-changelog-v0.9.0-entry.sh
  # pipeline-gate-permissiveness W4.3 — install.sh v0.9.0 upgrade banner
  test-install-upgrade-banner.sh
  # pipeline-gate-permissiveness W5.1+5.2 — (mode × class) matrix fixture suite
  test-permissiveness.sh
  # pipeline-gate-permissiveness W5.5 — Edge Case 16 spec.md additions
  test-spec-edge-case-16.sh
  # dynamic-roster-1-tags — persona tag-schema integrity validation
  test-persona-fit-tags.sh
  # autorun-merge-policy v0.11.0 — PR-by-default + opt-in clean/validated merge
  test-autorun-merge-policy.sh
)

# Tests whose passing condition is exit non-zero (M8 inverted-assertion contract).
INVERTED_TESTS=(
  test-allowlist-inverted.sh
)

PASS=0
FAIL=0
FAILED_TESTS=()

for t in "${TESTS[@]}"; do
  # Filter if user passed a name fragment
  if [ -n "$ONLY" ] && [[ "$t" != *"$ONLY"* ]]; then
    continue
  fi

  if [ ! -x "$TESTS_DIR/$t" ]; then
    echo "✗ $t — not executable or missing"
    FAIL=$(( FAIL + 1 ))
    FAILED_TESTS+=("$t")
    continue
  fi

  # Determine if this is an inverted test (passes when exit is non-zero per M8)
  IS_INVERTED=0
  for inv in "${INVERTED_TESTS[@]}"; do
    if [ "$t" = "$inv" ]; then IS_INVERTED=1; break; fi
  done

  echo "=== $t ==="
  TEST_EXIT=0
  bash "$TESTS_DIR/$t" || TEST_EXIT=$?

  if [ "$IS_INVERTED" -eq 1 ]; then
    # Inverted contract: pass = non-zero exit
    if [ "$TEST_EXIT" -ne 0 ]; then
      echo "→ $t PASSED (inverted: exit $TEST_EXIT as designed)"
      PASS=$(( PASS + 1 ))
    else
      echo "→ $t FAILED (inverted: should have exited non-zero, got 0)"
      FAIL=$(( FAIL + 1 ))
      FAILED_TESTS+=("$t")
    fi
  else
    if [ "$TEST_EXIT" -eq 0 ]; then
      echo "→ $t PASSED"
      PASS=$(( PASS + 1 ))
    else
      echo "→ $t FAILED (exit $TEST_EXIT)"
      FAIL=$(( FAIL + 1 ))
      FAILED_TESTS+=("$t")
    fi
  fi
  echo ""
done

echo "=========================================="
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo "Failed:"
  for t in "${FAILED_TESTS[@]}"; do
    echo "  - $t"
  done
  exit 1
fi
exit 0
