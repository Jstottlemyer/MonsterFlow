# Scope Review — autoship-outcome-instrumentation

## Critical Gaps (block /blueprint)

### Finding S1
- **class:** architectural
- **severity:** blocker
- **title:** Early `exit 0` paths in PR-creation block bypass the emission site

**Body:** The spec places the emission block immediately before the single `exit 0` at line 1507. However four `exit 0` paths in the PR-creation block (lines 1112, 1138, 1165, 1182) set `FINAL_STATE="completed-no-pr"` and bail out before reaching that site. Any run that fails at PR body sanitization, stale-base guard, URL extraction, or `gh pr create` itself will silently produce zero outcome rows — the opposite of the "exactly one row per terminal" guarantee in AC1 and AC5. The spec's own line count (~25 LoC at one call site) is wrong: correct coverage requires either (a) moving the emission call to a shared cleanup function, (b) a `trap EXIT` handler, or (c) injecting the call at each early-exit site. Option (a) or (b) is the clean path; option (c) spreads LoC significantly and is the creep risk.

**Suggested fix:** Wrap the emission in a `_emit_outcome_event()` function defined once, then call it at every `exit 0` path. Alternatively use `trap '_emit_outcome_event' EXIT` filtered on exit code 0. Either approach keeps the logic in one place and makes AC1 satisfiable.

### Finding S2
- **class:** contract
- **severity:** major
- **title:** `--spec-path` is required by the helper but the spec never resolves it

**Body:** The helper's `log-event` subcommand requires `--spec-path` (helper:402 `required=True`). The spec shows no invocation line that includes `--spec-path`. `CANONICAL_SPEC` exists at line 740 of `run.sh` (`$PROJECT_DIR/docs/specs/$SLUG/spec.md`), so the value is available — but the spec omits it from the command-line fragment, the mapping table, and the edge-case discussion. A /build agent will either guess at the variable name or invoke the helper without the flag (causing a hard failure, not a WARN). This converges with the same finding from the gaps reviewer.

**Suggested fix:** Add `--spec-path "$CANONICAL_SPEC"` to the example invocation in the spec's Data & State section.

## Important Considerations (non-blocking)

### Finding S3
- **class:** contract
- **severity:** minor
- **title:** `--gate build` choice validated against GATE_ENUM

**Body:** `GATE_ENUM` contains `"build"` (helper:44). Confirmed valid.

### Finding S4
- **class:** tests
- **severity:** minor
- **title:** AC6 fixture needs to stub the helper, but the helper is invoked as `python3 <path>`

**Body:** PATH-stub mocking (preferred per `feedback_path_stub_over_export_f.md`) works for binary names; `python3 scripts/...` with a hardcoded path requires a different intercept. The test will need to either temporarily replace the script file or use a wrapper variable. Worth noting in the spec's pitfall guards.

**Suggested fix:** Add a `HELPER_OVERRIDE` env-var hook to the emission block: `python3 "${OUTCOME_HELPER_OVERRIDE:-scripts/_goal_autoship_render.py}" log-event ...`. Tests set the override; production uses the default.

## Observations (notes)

- The `exit 1` paths (`halted-at-stage`) are all excluded from emission by the spec's design decision ("outcome row fires unconditionally" but only at the terminal block). Given S1, this design decision needs to be made explicit: does "unconditionally" mean "on every non-error exit" or "on every exit"?
- LoC estimate of ~25 will grow to ~40-50 if a shared function or trap is added. Still "small change" in spirit, but the count in the spec is off.
- AC9 (empty `pr_url` guard) is buildable as specified.

## Verdict: PASS WITH NOTES

Two issues need resolution before /blueprint: the early-exit coverage gap (architectural — the spec's central guarantee is unsatisfiable at the stated call site) and the missing `--spec-path` argument (contract — will cause a hard failure, not a best-effort warn). Both are addressable with a sentence or two of spec amendment; neither requires rethinking the design.
