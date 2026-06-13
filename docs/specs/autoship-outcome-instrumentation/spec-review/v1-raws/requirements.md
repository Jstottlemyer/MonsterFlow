# Requirements Completeness Review — autoship-outcome-instrumentation

## Critical Gaps (block /blueprint)

None. The spec is a tight wiring change with a well-bounded helper API contract, explicit mapping table, and per-state ACs.

## Important Considerations (address but non-blocking)

- **AC1 ambiguity on the "any FINAL_STATE" universe.** AC1 says "any FINAL_STATE" produces exactly one outcome row, but only four states are enumerated in the mapping table. If `run.sh` can resolve `FINAL_STATE` to a value outside {`merged`, `pr-awaiting-review`, `halted-at-stage`, `completed-no-pr`}, AC1 is untestable for those cases. The Edge Cases section partially covers this ("empty FINAL_STATE → treat as failed"), but the AC list does not include a fifth AC pinning down "unknown/unexpected FINAL_STATE → `reason=failed`, no `pr`, still exactly one row." Suggestion: add **AC10** asserting the defensive default, or tighten AC1 to "any FINAL_STATE in {the four enumerated} OR an unrecognized value."

- **AC8 is weakly testable as written.** "Grep test in the test file (or a comment marker) verifies the implementation uses the `rc=$?; if [ $rc -ne 0 ]` pattern" — a grep over the implementation file (`scripts/autorun/run.sh`) is a real check; a "comment marker" in the test file is not (it proves nothing about the implementation). Suggestion: drop the "(or a comment marker)" alternative; require `grep -F 'rc=$?' scripts/autorun/run.sh` against the new emission block specifically, or assert the absence of `| tee` / `|| true` patterns in the added block via a line-range grep.

- **AC6 stderr assertion regex is anchored loosely.** The pattern `^\[autorun\] WARN: outcome-event emission failed` matches the prefix but doesn't pin down whether the `rc=<N>` suffix is present. Repo memory `feedback_unverified_commands.md` favors verifying the actual emitted string. Suggestion: assert the full format including `(rc=<N>)` substring, so a regression that drops the exit code from the WARN line is caught.

- **No AC pins the JSONL append semantics.** The spec says emissions append to `dashboard/data/autorun-suitability-events.jsonl` and that "multiple invocations" produce duplicate rows by design. But no AC asserts that the row count *increases by exactly one* (vs. overwrites the file, or appends multiple). AC1 says "exactly one new row" but doesn't pin "and prior rows are preserved." Suggestion: tighten AC1 to "row count of the JSONL increases by exactly 1 from pre-run baseline" rather than "produces exactly one new row" — the former is unambiguously testable, the latter could be read as "the file contains one row."

- **`--gate build` is asserted in AC2–AC5 but the rationale ("last stage actually reached in modal case") doesn't generalize.** For `halted-at-stage`, the last stage reached could be `spec`, `spec-review`, `blueprint`, or `check` — never `build`. The spec acknowledges this is intentional ("outcome events are a closing-the-loop signal, not a gate-specific verdict"), which is fine, but the field name `gate` then misrepresents what it carries. Non-blocking because the helper contract is locked, but worth a note: downstream `autorun-suitability-v2` consumers may need to know `gate=build` on an outcome row means "outcome marker," not "halted at build."

## Observations (non-blocking notes)

- **Pitfall guards section is excellent** — explicit callouts to the four relevant memory entries (PIPESTATUS, cwd pollution, GNU mktemp, bash 3.2 array subscript) shows the implementation will dodge known traps. This is the right level of paranoia for shell work on macOS.

- **Out-of-scope list is appropriately defensive** — explicitly carving out `autoship_active` field, STOP-file-halt handling, and autoship-active detection prevents scope creep and matches the V2 carve-out pattern.

- **AC9 is exemplary** — concrete extraction command, specific assertion (`"pr" not in json.loads(...)`), tied to a specific edge case. This is the AC quality bar the others should reach.

- **"Helper API contract already tested" claim is load-bearing** — worth verifying once at implementation start that `_goal_autoship_render.py log-event --event-type outcome` accepts the exact flag set described (`--reason`, `--pr`, `--gate`, omittable `--pr`). The spec relies on this contract but does not cite the helper's test file. Suggestion for the implementer: open `scripts/_goal_autoship_render.py:335-369` and the corresponding test file before writing the wiring.

## Verdict

**PASS WITH NOTES**

The spec is unambiguous, scoped tight, and the AC list covers the four enumerated FINAL_STATE values with concrete pass/fail checks. The four "important" items are tightening opportunities — AC1's append semantics, AC8's grep target, AC6's regex specificity, and a missing AC for the defensive-default path — none of which block `/blueprint`. The author can fold these in during design or hold them as test-writing notes.
