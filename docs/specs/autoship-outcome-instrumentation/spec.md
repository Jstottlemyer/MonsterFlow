---
tags: [api, data, integration, pipeline, security, ux]
tags_provenance:
  baseline: [api, data, integration, security, ux]
  llm_added: [pipeline]
  user_overrides: []
gate_mode: permissive
---

# autoship-outcome-instrumentation Spec (V2 — post /spec-review refinement)

**Created:** 2026-06-02 (V1) · **Revised:** 2026-06-02 (V2 — same session, after V1 /spec-review surfaced 5 blockers)
**Constitution:** none — MonsterFlow personal-tooling repo uses pipeline-default personas
**Confidence:** Scope 0.96 · Data 0.96 · Integration 0.95 · Edge 0.94 · Acceptance 0.95 · **avg 0.95**

> Session roster only — run `/kickoff` later to make this a persistent constitution.

---

## V1 → V2 revision context

V1 /spec-review surfaced 5 architectural/contract blockers (full review at `review.md`). Three Claude reviewers + Codex independently converged on the central finding: `scripts/autorun/run.sh` has 10+ early-exit paths before the proposed terminal call site, making V1's "exactly one row per autorun terminal" guarantee unsatisfiable. Codex additionally caught: silent JSONL write failure in helper (AC6 vacuous), wrong variable name `pr_url` (actual: `PR_URL_VAL`), existing canonical PR extractor at `run.sh:1418-1424` unused, `gate=build` mislabels early halts, and `pr-awaiting-review → cancelled` mismaps `pr_only`/`fell_back`/`merge_failed` substates that can still ship.

| ID | Source | V1 issue | V2 resolution |
|----|--------|----------|---------------|
| B1 | gaps F1 + scope S1 + Codex CX-1 (3-way) | Single terminal call site misses 10+ early-exit paths | **`trap '_emit_outcome_event' EXIT`** installed at run.sh top; trap is the only mechanism reachable from every exit. Defensive default: if `FINAL_STATE` is empty at trap time, treat as `failed`. |
| B2 | Codex CX-2 | Helper silently swallows JSONL write failures (returns 0) → AC6 vacuous | **Helper brought into scope.** `_goal_autoship_render.py:214-229,369` modified to re-raise JSONL append failures as non-zero exit. Helper test updated to assert non-zero on simulated write failure. |
| B3 | Codex CX-3 | Spec uses `pr_url` (run.sh uses `PR_URL_VAL`); existing extractor at run.sh:1418-1424 unused | **Reuse existing `$PR_NUMBER`** variable already populated at run.sh:1418-1424 via the robust extractor. Pass `--pr "$PR_NUMBER"` when non-empty; omit otherwise. |
| B4 | gaps F2 + scope S2 (2-way) | `--spec-path` is required by helper but missing from spec's invocation | **Pass `--spec-path "$CANONICAL_SPEC"`** (run.sh:740 — repo-canonical path, stable across runs). |
| B5 | Codex CX-5 + CX-6 | `gate=build` mislabels early-stage halts; `pr-awaiting-review → cancelled` undercounts ship-rate | **New 4-reason enum:** `{shipped, pr-open, failed, cancelled}` (`pr-open` added to helper). `--gate` varies by FINAL_STATE — `merge` for merged/pr-awaiting-review, actual halt-stage extracted from `run.log` JSONL for halted-at-stage, `build` for completed-no-pr. |
| N1 | Codex CX-7 | Autoship-active deferral pollutes ship-rate dataset | **Acknowledged in §Data & State.** Consumers (suitability-v2) own the filtering semantics — either via `/goal` substring presence in adjacent session logs OR via a future `autoship_active` field. This spec ships data; v2 spec decides what counts. |

V2 also folds the V1 review's tightening items (AC1 append semantics, AC8 grep target, structural anchor over line numbers, `schema_version` int).

---

## Summary

Wire the existing `scripts/_goal_autoship_render.py log-event --event-type outcome` helper into `scripts/autorun/run.sh` via an `EXIT` trap so every autorun run — regardless of which exit path it takes — emits exactly one outcome event row to `dashboard/data/autorun-suitability-events.jsonl`. Brings the helper into scope to fix its silent JSONL write failure (V1 had this out of scope; V2 review showed the boundary doesn't hold). Closes the self-learning loop opened by autonomous-shipping-defaults V3 (v0.17.1): without outcome rows, `autorun-suitability-v2` cannot compute per-tag ship-rate.

## Backlog Routing

| Item | Source | Routing |
|------|--------|---------|
| `autoship-outcome-instrumentation` | BACKLOG.md:25 (Captured 2026-05-15) | (a) in scope — this spec |
| `autoship-merge-hygiene` | BACKLOG.md:31 (V2 carve) | (b) stays — separate `/spec` next |
| `pipeline-goal-wrap-default` | BACKLOG.md:42 (V2 carve) | (b) stays — separate `/spec` next |
| `autorun-suitability-v2` | autonomous-shipping-defaults V3 carve | (b) stays — sequenced after this spec ships + data accrues |

## Scope

**In scope (V2):**
- Helper change: `scripts/_goal_autoship_render.py` — re-raise JSONL append failures as non-zero exit (lines 214-229); add `pr-open` to `OUTCOME_REASONS` enum.
- Helper tests: assert non-zero exit on simulated write failure; assert `pr-open` is accepted.
- `scripts/autorun/run.sh`:
  - New function `_emit_outcome_event()` defined near top, before trap install.
  - Install `trap '_emit_outcome_event' EXIT` at top-of-script (or fold into the existing trap at 673-683).
  - Function reads `FINAL_STATE`, `PR_NUMBER`, `CANONICAL_SPEC`, derives `--gate` + `--reason`, invokes helper with best-effort error wrap (`rc=$?` capture, never fail the autorun).
  - Halt-stage extraction for `halted-at-stage`: grep the last `"stage": "<name>"` line from `RUN_LOG_PATH`; fall back to `build` if grep fails.
  - `_emit_outcome_event` is idempotent within a single invocation (uses a once-only sentinel to avoid double-emission if signals stack).
- New `tests/test-autorun-outcome-instrumentation.sh` — fixtures for each FINAL_STATE + early-exit + helper failure + empty FINAL_STATE; wired into `tests/run-tests.sh`.
- `CHANGELOG.md` entry under `[Unreleased]`.

**Out of scope (V2):**
- Any change to dashboards or analyzers that consume the events JSONL (that's `autorun-suitability-v2`).
- `autoship_active` field on rows (deferred — requires exporting env var from `commands/*.md` autoship-chain-invoke surface; not this spec's scope).
- STOP-file-halt distinct `cancelled` mapping (folded into `failed` via halted-at-stage; revisit if signal warrants).
- Filtering data pollution at the consumer (suitability-v2's job).

## Approach

Single mechanism (`trap EXIT`) + single emission function (`_emit_outcome_event`) + minimal helper change (raise on write failure + 1 new enum value). All call-site complexity in `run.sh` collapses to "install trap once" — no per-exit-site call sprinkling.

## Roster Changes

No roster changes.

## Data & State

### Emission topology

Install in `run.sh`:

```bash
trap '_emit_outcome_event' EXIT
```

Or fold into the existing exit handler at `run.sh:673-683` (implementer's call — both achieve once-per-process emission). Function defined near top of script, after variable initialization but before any potential `exit`.

### `_emit_outcome_event()` function shape (pseudocode)

```bash
_emit_outcome_event() {
  # Idempotency: emit only once per process.
  [ -n "${_OUTCOME_EVENT_EMITTED:-}" ] && return
  _OUTCOME_EVENT_EMITTED=1

  # Defensive default if FINAL_STATE is empty at trap time.
  local state="${FINAL_STATE:-failed_unknown}"
  local reason gate

  case "$state" in
    merged)              reason="shipped";   gate="merge" ;;
    pr-awaiting-review)  reason="pr-open";   gate="merge" ;;
    halted-at-stage)     reason="failed";    gate="$(_extract_halt_stage)" ;;
    completed-no-pr)     reason="failed";    gate="build" ;;
    *)                   reason="failed";    gate="build" ;;  # unknown FINAL_STATE
  esac

  # PR number: reuse existing $PR_NUMBER set at run.sh:1418-1424.
  local pr_arg=""
  if [ -n "${PR_NUMBER:-}" ]; then
    pr_arg="--pr $PR_NUMBER"
  fi

  # Best-effort invocation — never fail the autorun on telemetry errors.
  local helper="${OUTCOME_HELPER_OVERRIDE:-$ENGINE_DIR/scripts/_goal_autoship_render.py}"
  python3 "$helper" log-event \
    --event-type outcome \
    --spec-path "$CANONICAL_SPEC" \
    --gate "$gate" \
    --reason "$reason" \
    $pr_arg \
    >/dev/null 2>&1
  local rc=$?
  if [ $rc -ne 0 ]; then
    echo "[autorun] WARN: outcome-event emission failed (rc=$rc)" >&2
  fi
}

_extract_halt_stage() {
  # Read last stage from run.log JSONL; fall back to "build" if grep fails.
  local stage
  stage="$(grep -o '"stage": *"[^"]*"' "$RUN_LOG_PATH" 2>/dev/null | tail -1 | sed -E 's/.*"stage": *"([^"]*)".*/\1/')"
  echo "${stage:-build}"
}
```

### FINAL_STATE → outcome reason + gate mapping

| FINAL_STATE | `--reason` | `--gate` | `--pr` |
|---|---|---|---|
| `merged` | `shipped` | `merge` | `<$PR_NUMBER>` |
| `pr-awaiting-review` | `pr-open` *(new helper enum value)* | `merge` | `<$PR_NUMBER>` |
| `halted-at-stage` | `failed` | `<extracted from RUN_LOG_PATH; fallback `build`>` | omitted (PR may not exist) |
| `completed-no-pr` | `failed` | `build` | omitted |
| empty / unknown | `failed` | `build` | omitted |

Rationale per Q12: `shipped` = landed in main; `pr-open` = autorun delivered a PR awaiting human merge; `failed` = didn't reach PR. Suitability-v2 ship-rate = `shipped / (shipped + pr-open + failed)`. `cancelled` reserved for explicit user-initiated cancellation (future refinement when detectable).

### Helper change (`scripts/_goal_autoship_render.py`)

1. **Lines 214-229** (`append_event` swallow): change the `try/except` around the JSONL write to re-raise the exception (or exit non-zero) instead of catching + warning + returning. The shell wrapper at `_emit_outcome_event` already handles non-zero rc gracefully.
2. **`OUTCOME_REASONS` enum** (currently `{shipped, failed, cancelled}`): add `pr-open`.
3. **Helper tests**: 1 new case for "write failure raises non-zero"; 1 new case for "`pr-open` is accepted by argparse + appended correctly."

### Variable references (V2 corrections)

- `$PR_NUMBER` — set at `run.sh:1418-1424` via robust `grep -Eo 'https://[^ ]+/pull/[0-9]+' | tail -1` + `sed` + numeric guard. Already in scope at trap time for any run that reached PR creation. Empty otherwise.
- `$CANONICAL_SPEC` — set at `run.sh:740` (`$PROJECT_DIR/docs/specs/$SLUG/spec.md`). Stable, repo-canonical, durable.
- `$RUN_LOG_PATH` — set at `run.sh` early; used for `log_run` JSONL writes. `_extract_halt_stage` greps this.
- `$ENGINE_DIR` — set at `run.sh` top; resolves to the MonsterFlow repo for helper invocation.

### Data pollution acknowledgement (N1)

Outcome rows fire on EVERY autorun terminal — dry-runs, supervised/manual invocations, queue retries, and autoship-driven runs are all in the same dataset. The `autoship_active` field is deferred to a future spec (requires exporting an env var from the autoship chain-invoke surface in `commands/*.md`). Consumers (`autorun-suitability-v2`) own the filtering semantics: either join against adjacent session logs for `/goal` substring presence, OR wait for the field.

### JSONL row shape (helper-owned; verified against actual code)

```json
{
  "schema_version": 1,
  "ts": "2026-06-02T03:14:15Z",
  "event_type": "outcome",
  "feature": "<slug>",
  "gate": "merge",
  "reason": "shipped",
  "pr": 42
}
```

`schema_version` is an integer (per `_goal_autoship_render.py:353-359`), not a string (V1 error corrected).

## Integration

**Files touched:**
- `scripts/_goal_autoship_render.py` — ~5 LoC change (raise on write failure + add `pr-open` to enum).
- `scripts/autorun/run.sh` — ~40 LoC: function definitions (`_emit_outcome_event`, `_extract_halt_stage`) + trap install. Single emission site via trap.
- `tests/test-autorun-outcome-instrumentation.sh` (new) — ~150 LoC, 6+ fixtures.
- `tests/run-tests.sh` — 1-2 line registration of the new test.
- Helper test file (probably `tests/test-goal-autoship-render.sh`) — 2 new cases.
- `CHANGELOG.md` — entry under `[Unreleased]`.

**Files NOT touched:**
- `commands/*.md` — no skill changes; this is shell + helper only.
- `dashboard/data/autorun-suitability-events.jsonl` — gitignored runtime data.
- Dashboard readers / suitability-v2 (consumers stay out of scope).

**Pitfall guards (per repo memory):**
- `feedback_pipestatus_or_true.md` — emission block captures `rc=$?` BEFORE any `||` fallback. Pattern: `python3 ... ; rc=$?; if [ $rc -ne 0 ]; then ...`.
- `feedback_subagent_cwd_pollution.md` — test fixtures use absolute paths inside the fixture's tmpdir.
- `feedback_gnu_mktemp_xxxxxx_suffix.md` — `mktemp -d -t <prefix>.XXXXXX` in tests.
- `feedback_negative_array_subscript_bash32.md` — no `${array[-1]}` on macOS bash 3.2.
- `feedback_path_stub_over_export_f.md` — `OUTCOME_HELPER_OVERRIDE` env var lets tests intercept the helper without PATH stubs (helper is invoked by explicit path).

## Edge Cases

- **Helper exit non-zero (missing file, malformed spec, JSONL write permission denied):** logged as `[autorun] WARN: outcome-event emission failed (rc=<N>)` to stderr; autorun still exits with its true status (trap doesn't override exit code).
- **`FINAL_STATE` empty at trap time:** defensive default — `reason=failed`, `gate=build`, no PR. One row still emitted.
- **`PR_NUMBER` empty/unset (no PR created):** `--pr` flag omitted entirely. Helper accepts the omission per its argparse default.
- **`CANONICAL_SPEC` missing on disk:** helper exits non-zero from `load_spec`; WARN path fires.
- **Trap fires multiple times** (e.g., SIGTERM during exit handler): `_OUTCOME_EVENT_EMITTED` sentinel ensures once-only emission per process.
- **`RUN_LOG_PATH` missing/empty when `halted-at-stage`:** `_extract_halt_stage` returns `build` fallback. Row still emitted with correct reason.
- **Helper raises on JSONL write failure (new behavior):** caller (`_emit_outcome_event`) sees non-zero rc, logs WARN, autorun exits 0. No regression to autorun success/fail status.
- **`pr-open` reason accepted but downstream consumer doesn't know about it:** suitability-v2 spec (not this one) handles the enum; this spec ships the value into the JSONL.

## Acceptance Criteria

1. **AC1 — emission fires from every exit path.** Test fixtures simulating each of {merged-success, pr-awaiting-review, halted-at-spec-review, halted-at-build, completed-no-pr, helper-fails} assert the JSONL row count increases by exactly 1 from pre-run baseline. (V1 review N2: tightened from "exactly one row" to "row count +1" — unambiguously testable.)
2. **AC2 — `merged` → `shipped`, `gate=merge`, `pr` field present.** Numeric `pr` matches `$PR_NUMBER` from the existing extractor.
3. **AC3 — `pr-awaiting-review` → `pr-open`, `gate=merge`, `pr` field present.**
4. **AC4 — `halted-at-stage` → `failed`, `gate=<extracted halt stage>`, no `pr` field.** Test fixture seeds `run.log` with `"stage": "spec-review"`; asserts emitted row has `gate=spec-review`.
5. **AC5 — `completed-no-pr` → `failed`, `gate=build`, no `pr` field.**
6. **AC6 — empty/unknown FINAL_STATE → `failed`, `gate=build`, no `pr` field, row still emitted.** (V1 review tightening.)
7. **AC7 — helper failure does not fail the autorun.** Test fixture stubs helper via `OUTCOME_HELPER_OVERRIDE` to exit non-zero; asserts `run.sh` exits with its true status (not propagated) AND stderr contains `[autorun] WARN: outcome-event emission failed (rc=<N>)`.
8. **AC8 — PIPESTATUS-safe wrap.** `grep -F 'rc=$?' scripts/autorun/run.sh` against the emission block returns ≥1 match; `grep -E '\|\| true' scripts/autorun/run.sh` against the emission block returns 0 matches. (V1 review tightening: real grep against implementation, not comment marker.)
9. **AC9 — `tests/test-autorun-outcome-instrumentation.sh` wired into `tests/run-tests.sh`** and runs by default.
10. **AC10 — idempotency.** Test fixture installs trap, then explicitly calls `_emit_outcome_event` twice; asserts only one row appended.
11. **AC11 — helper JSONL write failure raises non-zero.** Helper test (new case in `tests/test-goal-autoship-render.sh` or equivalent): simulate write failure (e.g., write target is a directory, or chmod 0 on parent), assert helper exits non-zero AND no row appended.
12. **AC12 — helper accepts `pr-open` reason.** Helper test: `log-event --event-type outcome --reason pr-open --spec-path <fixture> --gate merge` exits 0 and appends a row with `reason=pr-open`.

## Open Questions

None at write time. Confidence ≥ 0.94 on all 5 applicable dimensions (UX N/A — no UI surface).

## Notes for /blueprint

- Trap installation point: confirm at /blueprint whether to fold into existing `run.sh:673-683` handler vs install a separate trap. Both work; folding is one less trap; separate is clearer ownership.
- `_extract_halt_stage` grep pattern is tentative — at /blueprint, verify against actual `log_run` JSONL format in `run.sh` (search for the `log_run` helper definition).
- Helper test file path: confirm at /blueprint by reading `tests/` directory; existing helper tests likely at `tests/test-goal-autoship-render.sh` per the V3 spec.
