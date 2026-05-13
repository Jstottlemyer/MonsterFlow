#!/bin/bash
##############################################################################
# scripts/autorun/build.sh
#
# Autorun build stage. Runs the build prompt under claude -p; on retry
# exhaustion, rolls back the autorun branch via `git reset --hard`.
#
# Task 3.3 (autorun-overnight-policy v6): branch-owned check + 4-artifact
# reset capture before any destructive `git reset --hard` on the autorun
# branch. Per spec AC#14:
#   (a) pre-reset.sha
#   (b) pre-reset.patch (5 MB cap with truncation marker)
#   (c) pre-reset-untracked.tgz (git ls-files -z + tar --null -T - + filters
#       + 100 MB cap with .SKIPPED marker on overflow)
#   (d) recovery_ref via `git update-ref refs/autorun-recovery/<run-id>`
#       when `git stash create` returns non-empty.
#
# Branch invariant: the destructive reset is gated on
#   BRANCH == "autorun/<slug>" AND run-state.branch_owned == "autorun/<slug>"
# Failure is a HARDCODED integrity block (no policy axis applies).
#
# Bash 3.2 compatible. NO ${arr[-1]}. Quoted expansions everywhere.
##############################################################################
set -euo pipefail

# Resolve REPO_DIR from this script's path (works under both `bash build.sh`
# and `source build.sh` for tests). BASH_SOURCE[0] is the script when sourced;
# falls back to $0 when invoked directly.
_BUILD_SH_SELF="${BASH_SOURCE[0]:-$0}"
REPO_DIR="$(cd "$(dirname "$_BUILD_SH_SELF")/../.." && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$REPO_DIR}"
source "$REPO_DIR/scripts/autorun/defaults.sh"

# ---------------------------------------------------------------------------
# Source _policy.sh (v6 D37 if-not-policy_act pattern + atomic-append helpers)
# ---------------------------------------------------------------------------
# shellcheck disable=SC1090
source "$REPO_DIR/scripts/autorun/_policy.sh"

# ---------------------------------------------------------------------------
# Validate required env vars (set by run.sh before calling this script)
# ---------------------------------------------------------------------------
: "${SLUG:?SLUG must be set by run.sh}"
: "${QUEUE_DIR:?QUEUE_DIR must be set by run.sh}"
: "${ARTIFACT_DIR:?ARTIFACT_DIR must be set by run.sh}"
: "${SPEC_FILE:?SPEC_FILE must be set by run.sh}"

mkdir -p "$ARTIFACT_DIR"

# ---------------------------------------------------------------------------
# Stage marker (consumed by policy_act via $AUTORUN_CURRENT_STAGE)
# ---------------------------------------------------------------------------
export AUTORUN_CURRENT_STAGE="${AUTORUN_CURRENT_STAGE:-build}"

# ---------------------------------------------------------------------------
# Resolve RUN_ID + RUN_DIR + STATE_FILE
#
# run.sh (Task 3.1) is the canonical writer of these. While 3.1 is
# in-flight, build.sh accepts env-var overrides and falls back to
# queue/runs/current/. Tests pin RUN_ID + RUN_DIR explicitly.
# ---------------------------------------------------------------------------
RUN_DIR="${AUTORUN_RUN_DIR:-$REPO_DIR/queue/runs/current}"
mkdir -p "$RUN_DIR"

# RUN_ID resolution order: env > run-state.json > zero-uuid placeholder.
RUN_ID="${AUTORUN_RUN_ID:-}"
if [ -z "$RUN_ID" ] && [ -f "$RUN_DIR/run-state.json" ]; then
  RUN_ID="$(python3 "$REPO_DIR/scripts/autorun/_policy_json.py" get "$RUN_DIR/run-state.json" "/run_id" --default "" 2>/dev/null || true)"
fi
if [ -z "$RUN_ID" ]; then
  # Synthesize a deterministic placeholder so refs/autorun-recovery/<id> stays
  # well-formed even when run.sh hasn't seeded RUN_ID yet. Tests override.
  RUN_ID="00000000-0000-0000-0000-000000000000"
fi

STATE_FILE="${AUTORUN_RUN_STATE:-$RUN_DIR/run-state.json}"
export AUTORUN_RUN_STATE="$STATE_FILE"

# Ensure run-state.json exists with the minimum shape policy_warn/policy_block
# need for atomic append. Idempotent: leaves existing file untouched.
if [ ! -f "$STATE_FILE" ]; then
  python3 - "$STATE_FILE" "$RUN_ID" "$SLUG" <<'PYINIT'
import json, os, sys
state_file, run_id, slug = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(os.path.dirname(state_file), exist_ok=True)
seed = {
    "schema_version": 1,
    "run_id": run_id,
    "slug": slug,
    "started_at": "1970-01-01T00:00:00Z",
    "branch_owned": f"autorun/{slug}",
    "current_stage": "build",
    "warnings": [],
    "blocks": [],
}
tmp = state_file + ".tmp"
with open(tmp, "w") as fh:
    json.dump(seed, fh, indent=2)
os.replace(tmp, state_file)
PYINIT
fi

# ---------------------------------------------------------------------------
# render_morning_report — minimal fallback. If run.sh has exported a richer
# implementation (function or env-overridable command), prefer that. Otherwise
# write a marker file so tests can assert the D37 path fired.
# ---------------------------------------------------------------------------
if ! command -v render_morning_report >/dev/null 2>&1; then
  render_morning_report() {
    local report="$RUN_DIR/morning-report.json"
    # Don't clobber a richer report already on disk.
    if [ -f "$report" ]; then return 0; fi
    local rec_json
    rec_json="$(cat "$RUN_DIR/.pre-reset-recovery.json" 2>/dev/null || printf '%s' '{"occurred":false,"sha":null,"patch_path":null,"untracked_archive":null,"untracked_archive_size_bytes":null,"recovery_ref":null,"partial_capture":false}')"
    python3 - "$report" "$RUN_ID" "$SLUG" "$rec_json" <<'PYREP'
import json, os, sys
report, run_id, slug, rec_json = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
try:
    rec = json.loads(rec_json)
except Exception:
    rec = {"occurred": False, "sha": None, "patch_path": None, "untracked_archive": None, "untracked_archive_size_bytes": None, "recovery_ref": None, "partial_capture": False}
doc = {
    "schema_version": 1,
    "run_id": run_id,
    "slug": slug,
    "branch_owned": f"autorun/{slug}",
    "started_at": "1970-01-01T00:00:00Z",
    "completed_at": "1970-01-01T00:00:00Z",
    "final_state": "halted-at-stage",
    "pr_url": None,
    "pr_created": False,
    "merged": False,
    "merge_capable": False,
    "run_degraded": True,
    "warnings": [],
    "blocks": [],
    "policy_resolution": {},
    "pre_reset_recovery": rec,
}
os.makedirs(os.path.dirname(report), exist_ok=True)
tmp = report + ".tmp"
with open(tmp, "w") as fh:
    json.dump(doc, fh, indent=2)
os.replace(tmp, report)
PYREP
  }
fi

# ---------------------------------------------------------------------------
# AUTORUN_DRY_RUN stub mode
# ---------------------------------------------------------------------------
if [ "${AUTORUN_DRY_RUN:-0}" = "1" ]; then
  echo "[autorun] build: DRY RUN mode — skipping claude -p invocation"

  {
    echo "## Wave 1 — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
    echo "Build wave 1 (DRY RUN) — stub commit"
    echo ""
  } > "$ARTIFACT_DIR/build-log.md"

  # Write pre-build-sha.txt and trigger verify.sh dry-run stub so the full
  # artifact graph (build-log.md + pre-build-sha.txt + verify-gaps.md) lands.
  # tests/autorun-dryrun.sh asserts on all three.
  if [ ! -f "$ARTIFACT_DIR/pre-build-sha.txt" ]; then
    git -C "$PROJECT_DIR" rev-parse HEAD > "$ARTIFACT_DIR/pre-build-sha.txt" 2>/dev/null \
      || echo "0000000000000000000000000000000000000000" > "$ARTIFACT_DIR/pre-build-sha.txt"
  fi
  if [ -x "$REPO_DIR/scripts/autorun/verify.sh" ]; then
    bash "$REPO_DIR/scripts/autorun/verify.sh" || true
  fi

  echo "[autorun] build: dry-run stub artifact written; exiting 0"
  exit 0
fi

# ---------------------------------------------------------------------------
# Autonomy directive (injected via --system-prompt)
# ---------------------------------------------------------------------------
AUTONOMY_DIRECTIVE="You are running in fully autonomous overnight mode. At every decision point, pick the safest reversible option and execute. Do not ask for approval. Do not pause for user input. Implement all tasks from the plan and commit each wave."

# ---------------------------------------------------------------------------
# Pre-build SHA capture (write-once invariant)
# ---------------------------------------------------------------------------
PRE_BUILD_SHA_FILE="$ARTIFACT_DIR/pre-build-sha.txt"
if [ ! -f "$PRE_BUILD_SHA_FILE" ]; then
  git -C "$PROJECT_DIR" rev-parse HEAD > "$PRE_BUILD_SHA_FILE"
fi
PRE_BUILD_SHA="$(cat "$PRE_BUILD_SHA_FILE")"

echo "[autorun] build: pre-build SHA = $PRE_BUILD_SHA"

# ---------------------------------------------------------------------------
# Timestamps and paths
# ---------------------------------------------------------------------------
BUILD_STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
STDERR_LOG="$(mktemp "${TMPDIR:-/tmp}/autorun-build-XXXXXX.log")"
trap 'rm -f "$STDERR_LOG"' EXIT

# ---------------------------------------------------------------------------
# State JSON helper (atomic write — local build/state.json, NOT run-state.json)
# ---------------------------------------------------------------------------
update_state() {
  local stage="$1" wave="$2"
  local tmp
  tmp="$(mktemp "$ARTIFACT_DIR/state.XXXXXX.json")"
  cat > "$tmp" << STATE_EOF
{"stage": "$stage", "wave": $wave, "pre_build_sha": "$PRE_BUILD_SHA", "started_at": "$BUILD_STARTED_AT", "pid": $$}
STATE_EOF
  mv "$tmp" "$ARTIFACT_DIR/state.json"
}

# ---------------------------------------------------------------------------
# failure.md writer
# ---------------------------------------------------------------------------
write_failure_md() {
  local exit_code="${1:-1}"
  cat > "$ARTIFACT_DIR/failure.md" << FAIL_EOF
<!-- autorun:stage=build slug=$SLUG wave=$ATTEMPT exit_code=$exit_code -->
# Failure: $SLUG

**Stage:** build (attempt $ATTEMPT of $BUILD_MAX_RETRIES)
**Branch:** autorun/$SLUG
**Pre-build SHA:** $PRE_BUILD_SHA
**Retry count:** $ATTEMPT of $BUILD_MAX_RETRIES
**Timestamp:** $(date -u +%Y-%m-%dT%H:%M:%SZ)

## Error
$(tail -n 50 "$STDERR_LOG" 2>/dev/null || echo "(no stderr captured)")

## Re-queue
\`\`\`
rm $ARTIFACT_DIR/failure.md && cp docs/specs/$SLUG/spec.md queue/$SLUG.spec.md
\`\`\`
FAIL_EOF
}

# ---------------------------------------------------------------------------
# capture_pre_reset_artifacts (Task 3.3 / spec AC#14)
#
# Emits, atomically, the four artifacts before any `git reset --hard` on the
# autorun branch:
#   (a) pre-reset.sha          — git rev-parse HEAD
#   (b) pre-reset.patch        — git diff (5 MB cap with truncation marker)
#   (c) pre-reset-untracked.tgz — `git ls-files -z + tar --null -T -` per the
#       canonical command emitted by spike 1.1; capture-side path filter on
#       NUL stream; 100 MB hard cap → on overflow delete tarball + write
#       pre-reset-untracked.SKIPPED marker.
#   (d) recovery_ref           — refs/autorun-recovery/<run-id> via
#       update-ref iff `git stash create` returns non-empty.
#
# Writes a JSON sidecar at $RUN_DIR/.pre-reset-recovery.json with the morning-
# report shape so render_morning_report can consume it.
#
# Partial-failure detection (Codex SF / SF-T1): if (c) succeeds but (d)
# update-ref fails (e.g. disk full, ref-name collision), emit
# `partial_capture: true`.
#
# Args: <branch-name>
# Returns: 0 always. Capture is best-effort; integrity-class failures (e.g.
#   tar exhausting disk) are surfaced via partial_capture=true; the caller
#   then proceeds to the policy_act branch decision.
# ---------------------------------------------------------------------------
capture_pre_reset_artifacts() {
  local branch_name="$1"
  local sha_file="$RUN_DIR/pre-reset.sha"
  local patch_file="$RUN_DIR/pre-reset.patch"
  local untracked_file="$RUN_DIR/pre-reset-untracked.tgz"
  local untracked_skipped_marker="$RUN_DIR/pre-reset-untracked.SKIPPED"
  local sidecar="$RUN_DIR/.pre-reset-recovery.json"

  # (a) HEAD SHA — always captured first.
  local head_sha=""
  if head_sha="$(git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null)"; then
    printf "%s\n" "$head_sha" > "$sha_file"
  else
    printf "0000000000000000000000000000000000000000\n" > "$sha_file"
    head_sha=""
  fi

  # (b) Diff with 5 MB cap. tee through head -c then check for overflow.
  local patch_cap_bytes=5242880  # 5 MB
  local patch_size=0
  if git -C "$PROJECT_DIR" diff > "$patch_file.full" 2>/dev/null; then
    patch_size=$(wc -c < "$patch_file.full" | tr -d ' ')
    if [ "$patch_size" -gt "$patch_cap_bytes" ]; then
      # Truncate to cap, append marker.
      head -c "$patch_cap_bytes" "$patch_file.full" > "$patch_file"
      printf "\n[truncated; full recovery via refs/autorun-recovery/%s stash ref]\n" "$RUN_ID" >> "$patch_file"
    else
      mv -f "$patch_file.full" "$patch_file"
    fi
    rm -f "$patch_file.full" 2>/dev/null || true
  else
    : > "$patch_file"
  fi

  # (c) Untracked tarball — read canonical command from spike output.
  local untracked_size=0
  local untracked_path_for_report="null"
  local untracked_size_for_report="null"
  local cap_bytes="${untracked_capture_max_bytes:-104857600}"  # 100 MB default

  # Determine whether any untracked files exist after capture-side filter.
  # The filter rejects: paths starting with `/`, containing `..`, control
  # chars (other than NUL), and symlinks pointing outside the worktree.
  local filtered_list raw_list
  # NOTE on suffix: BSD mktemp on macOS rejects templates with chars AFTER the
  # X-run in some TMPDIRs (saw "mkstemp failed: File exists" with `.lst`).
  # Stick to the canonical `name.XXXXXX` form (X-run at end).
  filtered_list="$(mktemp "${TMPDIR:-/tmp}/autorun-untracked.XXXXXX")"
  raw_list="$(mktemp "${TMPDIR:-/tmp}/autorun-untracked-raw.XXXXXX")"
  (
    cd "$PROJECT_DIR"
    git ls-files -z --others --exclude-standard 2>/dev/null
  ) > "$raw_list"
  # NOTE: do NOT pipe NUL data through python heredoc stdin (python rejects
  # NUL in source). We pass the raw list as a file path and read it in binary.
  python3 - "$PROJECT_DIR" "$filtered_list" "$raw_list" <<'PYFILT'
import os, sys
project, out, raw = sys.argv[1], sys.argv[2], sys.argv[3]
with open(raw, "rb") as fh:
    data = fh.read()
parts = [p for p in data.split(b"\0") if p]
kept = []
project_real = os.path.realpath(project)
for p in parts:
    try:
        s = p.decode("utf-8", errors="strict")
    except UnicodeDecodeError:
        continue  # reject non-utf-8 names defensively
    # Reject absolute or traversal-style paths (capture-side path filter).
    if s.startswith("/"):
        continue
    # Path traversal: any segment equal to "..".
    segs = s.split("/")
    if any(seg == ".." for seg in segs):
        continue
    # Control chars beyond NUL (NUL is the delimiter, already split).
    if any(ord(c) < 0x20 and c != "\n" for c in s):
        # Allow embedded newline (SF5 contract: ls-files -z preserves it).
        if any(ord(c) < 0x20 for c in s if c != "\n"):
            continue
    full = os.path.join(project, s)
    # Symlink-escape rejection: realpath must stay inside project.
    try:
        real = os.path.realpath(full)
        if not (real == project_real or real.startswith(project_real + os.sep)):
            continue
    except OSError:
        continue
    kept.append(s.encode("utf-8"))

with open(out, "wb") as fh:
    for p in kept:
        fh.write(p)
        fh.write(b"\0")
PYFILT

  if [ -s "$filtered_list" ]; then
    # Canonical tar invocation per spike output (queue/.spike-output/tar-untracked.cmd).
    # We expand --exclude flags here to add the project-tree exclusions called
    # for in spec AC#14 (node_modules, .venv, venv, target, build, dist, .next,
    # .nuxt, __pycache__).
    local tar_rc=0
    (
      cd "$PROJECT_DIR"
      tar --null -T "$filtered_list" \
          --exclude='node_modules' \
          --exclude='.venv' \
          --exclude='venv' \
          --exclude='target' \
          --exclude='build' \
          --exclude='dist' \
          --exclude='.next' \
          --exclude='.nuxt' \
          --exclude='__pycache__' \
          -czf "$untracked_file" 2>/dev/null
    ) || tar_rc=$?

    if [ "$tar_rc" -eq 0 ] && [ -f "$untracked_file" ]; then
      untracked_size=$(wc -c < "$untracked_file" | tr -d ' ')
      if [ "$untracked_size" -gt "$cap_bytes" ]; then
        # Overflow: delete tarball, write SKIPPED marker.
        rm -f "$untracked_file"
        printf "skipped: untracked archive %d bytes > cap %d bytes\n" "$untracked_size" "$cap_bytes" > "$untracked_skipped_marker"
        untracked_path_for_report="null"
        untracked_size_for_report="null"
      else
        untracked_path_for_report="\"$untracked_file\""
        untracked_size_for_report="$untracked_size"
      fi
    else
      # tar failed — leave nothing behind.
      rm -f "$untracked_file" 2>/dev/null || true
    fi
  fi
  rm -f "$filtered_list" "$raw_list" 2>/dev/null || true

  # (d) Recovery ref — only if `git stash create` returns non-empty.
  local stash_sha=""
  local recovery_ref_for_report="null"
  local partial_capture="false"

  stash_sha="$(git -C "$PROJECT_DIR" stash create 2>/dev/null || true)"
  if [ -n "$stash_sha" ]; then
    local ref_name="refs/autorun-recovery/$RUN_ID"
    # Allow tests to inject failures via env hook (SF-T1).
    if [ "${AUTORUN_FORCE_UPDATE_REF_FAIL:-0}" = "1" ] || \
       ! git -C "$PROJECT_DIR" update-ref "$ref_name" "$stash_sha" 2>/dev/null; then
      # tar succeeded (or had nothing to do) but ref capture failed.
      partial_capture="true"
      recovery_ref_for_report="null"
    else
      recovery_ref_for_report="\"$ref_name\""
    fi
  fi

  # Sidecar JSON shape consumed by render_morning_report.
  python3 - "$sidecar" "$head_sha" "$patch_file" "$untracked_path_for_report" "$untracked_size_for_report" "$recovery_ref_for_report" "$partial_capture" <<'PYSIDE'
import json, os, sys
sidecar, sha, patch, untracked_lit, size_lit, recovery_lit, partial = sys.argv[1:8]

def lit(s):
    s = s.strip()
    if s == "null":
        return None
    if s.startswith("\"") and s.endswith("\""):
        return s[1:-1]
    # numeric
    try:
        return int(s)
    except Exception:
        return s

doc = {
    "occurred": True,
    "sha": sha if sha else None,
    "patch_path": patch if os.path.exists(patch) else None,
    "untracked_archive": lit(untracked_lit),
    "untracked_archive_size_bytes": lit(size_lit),
    "recovery_ref": lit(recovery_lit),
    "partial_capture": (partial.strip() == "true"),
}
tmp = sidecar + ".tmp"
with open(tmp, "w") as fh:
    json.dump(doc, fh, indent=2)
os.replace(tmp, sidecar)
PYSIDE

  return 0
}

# ---------------------------------------------------------------------------
# guarded_branch_reset
#
# Replaces the bare `git reset --hard $PRE_BUILD_SHA` with the branch-owned
# check + 4-artifact capture + D37 policy_act gate.
#
# Hardcoded block (no policy axis) when:
#   - Current branch != autorun/<slug>, OR
#   - run-state.branch_owned mismatches autorun/<slug>.
#
# The branch-owned check is INTEGRITY class — there is no overrideable axis
# for "we're somehow on main".
# ---------------------------------------------------------------------------
guarded_branch_reset() {
  local target_sha="$1"
  local expected_branch="autorun/$SLUG"
  local current_branch=""
  current_branch="$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"

  if [ "$current_branch" != "$expected_branch" ]; then
    # Hardcoded integrity block — never auto-resetting off-branch trees.
    if ! policy_block build integrity "refusing to reset: current branch '$current_branch' != expected '$expected_branch'"; then :; fi
    render_morning_report
    exit 1
  fi

  local branch_owned=""
  branch_owned="$(python3 "$REPO_DIR/scripts/autorun/_policy_json.py" get "$STATE_FILE" "/branch_owned" --default "" 2>/dev/null || true)"
  if [ "$branch_owned" != "$expected_branch" ]; then
    if ! policy_block build integrity "refusing to reset: run-state.branch_owned='$branch_owned' != expected '$expected_branch'"; then :; fi
    render_morning_report
    exit 1
  fi

  # 4-artifact capture BEFORE any destructive action.
  capture_pre_reset_artifacts "$expected_branch"

  # D37 if-not-policy_act pattern. branch is the overrideable axis.
  if ! policy_act branch "reset autorun branch (4 artifacts captured)"; then
    render_morning_report
    exit 1
  fi

  # All gates cleared — perform the reset.
  git -C "$PROJECT_DIR" reset --hard "$target_sha"
}

# ---------------------------------------------------------------------------
# BUILD_SOURCE_ONLY hook (test-only): when sourced with this env var set, the
# script defines all helper functions and returns BEFORE the retry-loop body,
# letting tests exercise capture_pre_reset_artifacts / guarded_branch_reset
# in isolation. Production callers never set this.
# ---------------------------------------------------------------------------
if [ "${BUILD_SOURCE_ONLY:-0}" = "1" ]; then
  return 0 2>/dev/null || exit 0
fi

# ---------------------------------------------------------------------------
# Build retry loop
# ---------------------------------------------------------------------------
ATTEMPT=1
BUILD_SUCCESS=0

while [ "$ATTEMPT" -le "$BUILD_MAX_RETRIES" ]; do

  # -- STOP file check (before each attempt) ---------------------------------
  if [ -f "$QUEUE_DIR/STOP" ]; then
    echo "[autorun] build: STOP file detected — halting after clean state"
    exit 3
  fi

  # -- Compliance gaps from previous attempt (empty on attempt 1) -----------
  GAPS_CONTEXT=""
  if [ -f "$ARTIFACT_DIR/verify-gaps.md" ] && grep -iq '^\[FAIL\]' "$ARTIFACT_DIR/verify-gaps.md" 2>/dev/null; then
    GAPS_CONTEXT="

## IMPORTANT: Spec Requirements NOT Implemented in Previous Attempt (Implement These This Attempt)
The verifier confirmed the following requirements were missing from the committed code.
Do NOT commit until every [FAIL] item below is implemented:

$(grep -i '^\[FAIL\]' "$ARTIFACT_DIR/verify-gaps.md")"
  fi

  # -- State update ----------------------------------------------------------
  update_state "build" "$ATTEMPT"

  # -- Wave header in build-log.md ------------------------------------------
  {
    echo "## Wave $ATTEMPT — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
  } >> "$ARTIFACT_DIR/build-log.md"

  echo "[autorun] build: starting attempt $ATTEMPT of $BUILD_MAX_RETRIES (timeout=${TIMEOUT_STAGE}s, slug=$SLUG)"

  # -- Build prompt ----------------------------------------------------------
  BUILD_PROMPT="$(cat "$REPO_DIR/commands/build.md")

---
AUTORUN_CONTEXT:
- SLUG: $SLUG
- SPEC_FILE: $SPEC_FILE
- PLAN_FILE: $ARTIFACT_DIR/design.md
- CHECK_FILE: $ARTIFACT_DIR/check.md
- AUTORUN: 1
- BUILD_ATTEMPT: $ATTEMPT of $BUILD_MAX_RETRIES
- MODE: headless autonomous — implement all tasks and commit each wave. Do not ask for approval.

$(cat "$ARTIFACT_DIR/check.md" 2>/dev/null || echo "(no check.md found)")${GAPS_CONTEXT}"

  # -- Invoke claude -p -------------------------------------------------------
  # Clear stderr log before each attempt so failure.md shows the latest errors.
  > "$STDERR_LOG"

  # PIPESTATUS[1] is claude's exit (PIPESTATUS[0] is printf, which is always 0).
  CLAUDE_EXIT=0
  printf '%s' "$BUILD_PROMPT" | timeout "$TIMEOUT_STAGE" claude -p \
    --dangerously-skip-permissions \
    --system-prompt "$AUTONOMY_DIRECTIVE" \
    --add-dir "$PROJECT_DIR" \
    2>"$STDERR_LOG" | tee -a "$ARTIFACT_DIR/build-log.md" || CLAUDE_EXIT=${PIPESTATUS[1]}

  if [ "$CLAUDE_EXIT" -ne 0 ]; then
    echo "[autorun] build: claude -p exited $CLAUDE_EXIT on attempt $ATTEMPT"
    ATTEMPT=$(( ATTEMPT + 1 ))
    continue
  fi

  echo "[autorun] build: claude -p exited 0 on attempt $ATTEMPT"

  # -- Test command (if configured) ------------------------------------------
  TESTS_PASSED=1
  TEST_CMD="${TEST_CMD:-}"
  if [ -n "$TEST_CMD" ]; then
    echo "[autorun] build: running test_cmd in $PROJECT_DIR: $TEST_CMD"
    # NOTE: TEST_CMD is arbitrary shell from queue/autorun.config.json — by
    # design (e.g. `npm test`, `pytest`). Run it inside the project dir so
    # adopters' tests aren't accidentally executed against the engine repo.
    if (cd "$PROJECT_DIR" && eval "$TEST_CMD"); then
      echo "[autorun] build: tests PASSED"
      TESTS_PASSED=1
    else
      echo "[autorun] build: tests FAILED (attempt $ATTEMPT)"
      TESTS_PASSED=0
    fi
  else
    echo "[autorun] build: no test_cmd configured — skipping tests"
    TESTS_PASSED=1
  fi

  # -- Spec compliance check (only if tests passed) --------------------------
  COMPLIANCE_PASSED=1
  if [ "$TESTS_PASSED" -eq 1 ] && [ -x "$REPO_DIR/scripts/autorun/verify.sh" ]; then
    echo "[autorun] build: running spec compliance check (attempt $ATTEMPT)"
    VERIFY_EXIT=0
    bash "$REPO_DIR/scripts/autorun/verify.sh" || VERIFY_EXIT=$?
    if [ "$VERIFY_EXIT" -ne 0 ]; then
      echo "[autorun] build: spec compliance FAILED on attempt $ATTEMPT"
      COMPLIANCE_PASSED=0
    fi
  fi

  if [ "$TESTS_PASSED" -eq 1 ] && [ "$COMPLIANCE_PASSED" -eq 1 ]; then
    # Re-check STOP after a successful wave — catches the race where STOP
    # was created mid-wave; otherwise run.sh would proceed to PR creation.
    if [ -f "$QUEUE_DIR/STOP" ]; then
      echo "[autorun] build: STOP file detected after successful wave — halting before PR creation"
      exit 3
    fi
    BUILD_SUCCESS=1
    break
  fi

  ATTEMPT=$(( ATTEMPT + 1 ))

done

# ---------------------------------------------------------------------------
# Handle exhausted retries
# ---------------------------------------------------------------------------
if [ "$BUILD_SUCCESS" -ne 1 ]; then
  echo "[autorun] build: exhausted $BUILD_MAX_RETRIES retries — rolling back to pre-build SHA $PRE_BUILD_SHA"

  # Branch-owned check + 4-artifact reset capture + D37 policy_act gate.
  guarded_branch_reset "$PRE_BUILD_SHA"

  # Remote cleanup — close any open PR
  if [ -f "$ARTIFACT_DIR/pr-url.txt" ]; then
    PR_URL="$(cat "$ARTIFACT_DIR/pr-url.txt")"
    gh pr close "$PR_URL" 2>/dev/null \
      && echo "[autorun] build: closed PR $PR_URL" \
      || echo "[autorun] build: WARN — could not close PR $PR_URL (may already be closed)"
  fi

  # Delete remote branch
  git -C "$PROJECT_DIR" push origin --delete "autorun/$SLUG" 2>/dev/null \
    && echo "[autorun] build: deleted remote branch autorun/$SLUG" \
    || true

  write_failure_md 1
  echo "[autorun] build: failure.md written to $ARTIFACT_DIR/failure.md"
  exit 1
fi

# ---------------------------------------------------------------------------
# Success path
# ---------------------------------------------------------------------------
update_state "build_complete" "$ATTEMPT"
echo "[autorun] build: complete (attempt $ATTEMPT of $BUILD_MAX_RETRIES)"
