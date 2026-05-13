#!/usr/bin/env bash
##############################################################################
# tests/autorun-dryrun.sh
#
# Smoke test for the autorun pipeline in DRY_RUN mode.
# Stages a fixture spec, runs the pipeline against an isolated TMPDIR queue,
# asserts every expected artifact landed, then cleans up.
#
# Exit codes:
#   0 — all assertions passed
#   1 — at least one assertion failed
#   2 — setup failure (missing fixture, can't create temp dir, etc.)
##############################################################################
set -uo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE="$ENGINE_DIR/tests/fixtures/autorun-dryrun/sample.spec.md"

if [ ! -f "$FIXTURE" ]; then
  echo "✗ setup: fixture not found at $FIXTURE" >&2
  exit 2
fi

# Isolated project dir so we don't pollute the engine's queue/.
PROJECT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/autorun-dryrun-XXXXXX")"
trap 'rm -rf "$PROJECT_DIR"' EXIT

# Initialize a real git repo so run.sh's branch operations work.
git -C "$PROJECT_DIR" init -q -b main
git -C "$PROJECT_DIR" config user.email "dryrun@local"
git -C "$PROJECT_DIR" config user.name "Dry Run"
echo "# dryrun" > "$PROJECT_DIR/README.md"
git -C "$PROJECT_DIR" add README.md
git -C "$PROJECT_DIR" commit -q -m "init"

mkdir -p "$PROJECT_DIR/queue"
cp "$FIXTURE" "$PROJECT_DIR/queue/sample.spec.md"

echo "[dryrun] running autorun in $PROJECT_DIR"

# Run the pipeline. AUTORUN_DRY_RUN=1 makes every stage write stub artifacts.
# We disable the codex review step's gh push by NOT having a remote configured.
START="$(date +%s)"
RUN_LOG="$(mktemp "${TMPDIR:-/tmp}/autorun-dryrun-log-XXXXXX.txt")"
export ENGINE_DIR PROJECT_DIR
RUN_EXIT=0
# v6: run.sh is single-slug; queue-loop migrated to autorun-batch.sh (Task 3.0b).
# Pass --mode=supervised + slug; --dry-run flag preferred over env var.
bash "$ENGINE_DIR/scripts/autorun/run.sh" --mode=supervised --dry-run sample >"$RUN_LOG" 2>&1 || RUN_EXIT=$?
END="$(date +%s)"
ELAPSED=$(( END - START ))

# In DRY_RUN, the build/verify/notify/codex steps stub out — pipeline should
# proceed through review-findings, risk-findings, plan, check, build (stub
# wave), verify (stub COMPLIANT), and PR creation will fail because there's
# no remote. PR-creation failure is expected in dry-run; we just want to
# confirm the pre-PR artifacts all landed.

ART="$PROJECT_DIR/queue/sample"
PASS=0
FAIL=0

assert_file() {
  local path="$1" label="${2:-$1}"
  if [ -f "$path" ]; then
    echo "✓ $label"
    PASS=$(( PASS + 1 ))
  else
    echo "✗ missing: $label"
    FAIL=$(( FAIL + 1 ))
  fi
}

assert_grep() {
  local path="$1" pattern="$2" label="$3"
  if [ -f "$path" ] && grep -iq "$pattern" "$path" 2>/dev/null; then
    echo "✓ $label"
    PASS=$(( PASS + 1 ))
  else
    echo "✗ $label (pattern '$pattern' not found in $path)"
    FAIL=$(( FAIL + 1 ))
  fi
}

echo ""
echo "=== Asserting artifacts under $ART ==="
assert_file "$ART/review-findings.md"
assert_file "$ART/risk-findings.md"
assert_file "$ART/design.md"
assert_file "$ART/check.md"
assert_file "$ART/build-log.md"
assert_file "$ART/verify-gaps.md"
assert_file "$ART/pre-build-sha.txt"
assert_grep "$ART/verify-gaps.md" "VERDICT: COMPLIANT" "verify-gaps.md contains VERDICT: COMPLIANT"

# v6: per-run state lives under queue/runs/<run-id>/run-state.json (Task 3.1).
# Find the run dir (single-slug invocation produces exactly one).
RUN_DIR=""
for d in "$PROJECT_DIR/queue/runs"/*/; do
  [ -d "$d" ] || continue
  case "$(basename "${d%/}")" in
    .locks|current) continue ;;
  esac
  RUN_DIR="${d%/}"
  break
done

POLICY_JSON_PY="$ENGINE_DIR/scripts/autorun/_policy_json.py"

# Validate <file> against <schema_name> via _policy_json.py validate.
# v6 contract: the documented validator. Bash 3.2 compatible.
assert_schema_valid() {
  local file="$1" schema="$2" label="$3"
  if [ ! -f "$file" ]; then
    echo "✗ $label (file missing: $file)"
    FAIL=$(( FAIL + 1 ))
    return
  fi
  local err
  err="$(python3 "$POLICY_JSON_PY" validate "$file" "$schema" 2>&1 1>/dev/null)" || {
    echo "✗ $label (schema validation failed)"
    echo "$err" | sed 's/^/    /'
    FAIL=$(( FAIL + 1 ))
    return
  }
  echo "✓ $label"
  PASS=$(( PASS + 1 ))
}

if [ -n "$RUN_DIR" ]; then
  assert_file "$RUN_DIR/run-state.json"
  assert_file "$RUN_DIR/morning-report.json"
  if [ -f "$RUN_DIR/run-state.json" ] && python3 -c "import json; json.load(open('$RUN_DIR/run-state.json'))" 2>/dev/null; then
    echo "✓ run-state.json is valid JSON"
    PASS=$(( PASS + 1 ))
  else
    echo "✗ run-state.json missing or invalid"
    FAIL=$(( FAIL + 1 ))
  fi

  # ---------------------------------------------------------------------------
  # v6 contract assertions (Task 5.5)
  # ---------------------------------------------------------------------------

  # assert_run_state_valid — schema validation per v6 contract.
  assert_schema_valid "$RUN_DIR/run-state.json" run-state \
    "run-state.json validates against schemas/run-state.schema.json"

  # assert_morning_report_valid — schema validation per v6 contract.
  assert_schema_valid "$RUN_DIR/morning-report.json" morning-report \
    "morning-report.json validates against schemas/morning-report.schema.json"

  # assert_run_degraded_zero_when_no_warnings — happy dry-run with no
  # warnings → RUN_DEGRADED=0 derivation correct (read from final
  # morning-report). AC#7 / spec.md.
  if [ -f "$RUN_DIR/morning-report.json" ]; then
    RD="$(python3 "$POLICY_JSON_PY" get "$RUN_DIR/morning-report.json" /run_degraded --default unset 2>/dev/null || echo unset)"
    WARN_COUNT="$(python3 -c "import json,sys
d=json.load(open(sys.argv[1]))
print(len(d.get('warnings') or []))" "$RUN_DIR/morning-report.json" 2>/dev/null || echo unset)"
    # _policy_json.py get emits JSON-formatted scalars (lowercase 'false').
    if [ "$WARN_COUNT" = "0" ] && [ "$RD" = "false" ]; then
      echo "✓ run_degraded=false when warnings array is empty (AC#7)"
      PASS=$(( PASS + 1 ))
    else
      echo "✗ run_degraded derivation wrong (run_degraded=$RD warnings=$WARN_COUNT; expected false/0)"
      FAIL=$(( FAIL + 1 ))
    fi
  fi
fi

# -----------------------------------------------------------------------------
# Dry-run synthesis stub fence assertions (SF-O5 + Task 3.1 contract)
#
# The dry-run check.sh stub MUST emit a `check-verdict` fenced JSON block in
# its synthesis output. Without this, the post-processor would silently hit
# the legacy grep fallback path, giving false confidence in the smoke test.
# -----------------------------------------------------------------------------
DRYRUN_CHECK_STUB="$ART/check.md"

# assert_dry_run_emits_check_verdict_fence — one fence in the stub stream.
if [ -f "$DRYRUN_CHECK_STUB" ]; then
  EXTRACT_OUT="$(python3 "$POLICY_JSON_PY" extract-fence "$DRYRUN_CHECK_STUB" check-verdict 2>/dev/null || true)"
  FENCE_COUNT="$(printf '%s\n' "$EXTRACT_OUT" | sed -n '1p')"
  FENCE_COUNT="${FENCE_COUNT:-0}"
  if [ "$FENCE_COUNT" = "1" ]; then
    echo "✓ dry-run synthesis stub emits exactly one check-verdict fence (SF-O5)"
    PASS=$(( PASS + 1 ))
  else
    echo "✗ dry-run synthesis stub fence count = $FENCE_COUNT (expected 1; SF-O5)"
    FAIL=$(( FAIL + 1 ))
  fi

  # assert_check_verdict_extracted_to_sidecar — round-trip the fence through
  # the extractor and validate the JSON payload against check-verdict schema.
  # (Task 5.5 note: the dry-run stage script does not itself write the
  # canonical sidecar at docs/specs/<slug>/check-verdict.json — see wiring
  # gap in the task report. This test validates the round-trip via the
  # documented helper, which is what the post-processor would do.)
  SIDECAR_TMP="$(mktemp "${TMPDIR:-/tmp}/check-verdict-XXXXXX.json")"
  if [ "$FENCE_COUNT" = "1" ]; then
    printf '%s\n' "$EXTRACT_OUT" | sed '1d' > "$SIDECAR_TMP"
    if [ -s "$SIDECAR_TMP" ]; then
      # The dry-run stub in check.sh emits a v2-shape verdict (post-W6 + code-review C2 fix).
      # Round-trip integrity = "extractor produced a JSON payload that parses + matches
      # the live v2 schema". This validates the smoke-test path produces real v2 artifacts
      # per memory `feedback_dryrun_full_graph.md` (stub for stage N must produce all
      # artifacts stage N+1 reads). The v1-stub validator is now used as the negative
      # control (proves schema discriminates by version).
      V1_STUB="$ENGINE_DIR/tests/fixtures/permissiveness/partial-landing/v1-stub-validate.py"
      if python3 "$POLICY_JSON_PY" validate "$SIDECAR_TMP" check-verdict >/dev/null 2>&1; then
        echo "✓ extracted check-verdict payload validates against live v2 schema (dry-run stub at v2)"
        PASS=$(( PASS + 1 ))
      else
        echo "✗ extracted check-verdict payload failed v2 validation (dry-run stub may have drifted)"
        FAIL=$(( FAIL + 1 ))
      fi
      # Sanity: the v1-stub validator MUST reject the v2 stub payload (proves schema
      # discrimination works in reverse — schema_version: const 1 vs 2).
      if python3 "$V1_STUB" "$SIDECAR_TMP" >/dev/null 2>&1; then
        echo "✗ v1-stub schema unexpectedly accepted v2-shape payload (const-check broken)"
        FAIL=$(( FAIL + 1 ))
      else
        echo "✓ v1-stub schema rejects v2-shape payload (schema discriminates by version)"
        PASS=$(( PASS + 1 ))
      fi
    else
      echo "✗ extracted check-verdict payload empty"
      FAIL=$(( FAIL + 1 ))
    fi
  else
    echo "✗ skipping check-verdict extraction (fence count != 1)"
    FAIL=$(( FAIL + 1 ))
  fi
  rm -f "$SIDECAR_TMP"
else
  echo "✗ dry-run check.md stub not found at $DRYRUN_CHECK_STUB"
  FAIL=$(( FAIL + 1 ))
fi

if [ -z "$RUN_DIR" ]; then
  echo "✗ no queue/runs/<run-id>/ directory created"
  FAIL=$(( FAIL + 1 ))
fi

echo ""
echo "=== Summary ==="
echo "passed: $PASS"
echo "failed: $FAIL"
echo "elapsed: ${ELAPSED}s"
echo "run.sh exit code: $RUN_EXIT (PR creation failure expected in dry-run)"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "=== Run log (last 50 lines) ==="
  tail -50 "$RUN_LOG"
  rm -f "$RUN_LOG"
  echo ""
  echo "FAIL — $FAIL assertion(s) failed"
  exit 1
fi

rm -f "$RUN_LOG"
echo ""
echo "PASS — autorun dry-run complete in ${ELAPSED}s"
exit 0
