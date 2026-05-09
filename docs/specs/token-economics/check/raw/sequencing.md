# Findings — Sequencing and Dependencies

## Must Fix

**S1. Circular dependency between T-CORE-10 (bundle emit) and T-CORE-15 (roster walk).**
T-CORE-10 says it emits `persona-insights-bundle.js` containing "rankings + roster + generated_at". T-CORE-15 says it walks `personas/{review,plan,check}/*.md` and emits the roster *into the combined bundle's `PERSONA_ROSTER`* — but lists T-CORE-10 as its dependency. This is inverted: T-CORE-10 cannot emit a bundle that includes the roster until T-CORE-15 has produced it. Either:
- T-CORE-10 must depend on T-CORE-15 (correct fix — flip the arrow), or
- T-CORE-15 mutates the already-written bundle (violates D1's "atomic by construction" rationale)

This breaks Wave 1's atomic-bundle promise that resolves R2. Fix the dependency arrow before /build dispatches.

**S2. T-TEST-9 leaks Wave 2 into Wave 3.**
T-TEST-9 (dashboard recovery test) depends on T-UI-2, which is Wave 3. The plan declares Waves 2 → 3 → 4, but T-TEST-9 cannot start until Wave 3 is partially built. Either re-bucket T-TEST-9 to Wave 3 explicitly, or split it into "compute side recovery" (Wave 2) + "dashboard render assertion" (Wave 3). As written, the wave model is dishonest and the orchestrator may dispatch T-TEST-9 too early and fail.

## Should Fix

**S3. A1.5 forcing function fires after T-CORE-5 already commits to a canonical-source path.**
T-CORE-5 implements the canonical-token-source choice in Wave 1. A1.5 (the disagreement detector) runs in T-TEST-2 in Wave 2. If A1.5 detects disagreement, the spec halts the build and `/plan` re-opens Q1 — but by then T-CORE-5/8/10 are already written against the wrong assumption. Recommend a one-shot A1.5 micro-probe at the end of Wave 0 (or as a sub-task of T-CORE-1) that runs the equality check against the redacted fixtures BEFORE T-CORE-5 commits a code path. Reduces blast radius from ~6 Wave-1 tasks down to one probe.

**S4. `run.json` historical-absence is not an enumerated `run_state`.**
T-CORE-7 reads `run.json.created_at` for window ordering. The 7-state machine doesn't enumerate "run.json missing." Old artifact directories pre-dating the persona-metrics directive will silently drop out of the window — no warning, no state. Either add `missing_run` to the state enum (preferred) or document that pre-directive directories are intentionally invisible (pin in T-DOC-1).

**S5. T-CORE-6 (CC layout drift probe) only checks parse rate, not persona-name regex extractability.**
The Phase 0 spike validated `personas/<gate>/<name>.md` regex extraction across 73 RedRabbit fixtures — single project. T-CORE-6 samples 10 dispatches and checks ≥80% parseable, but parseable ≠ persona-name extractable. Add an explicit assertion: of those 10, ≥80% have a recoverable `(persona, gate)` pair via the regex. Otherwise cross-project drift could silently dump rows into `<unknown>`.

## Notes

**N1. Critical-path depth ~12 tasks.** Longest chain: T-PRE-1 → T-CORE-1 → T-CORE-2 → T-CORE-7 → T-CORE-8 → T-CORE-9 → T-CORE-10 → T-CORE-15 → T-TEST-2 → T-WIRE-1 → T-VERIFY-1 → T-VERIFY-2. With L-sized T-CORE-5/7 and T-TEST-2, this is the realistic floor. Acceptable for a v1.

**N2. Wave-3 UI chain is fully serial (T-UI-1 → T-UI-2 → T-UI-3).** Could parallelize header/tab scaffolding (T-UI-1) with module skeleton (T-UI-2) if that becomes a bottleneck — currently sized OK because T-UI-1/3 are S.

**N3. High-risk de-risking is correctly front-loaded.** T-PRE-1 (import cleanliness, R1) is first; T-CORE-6 (CC drift, R6) is in Wave 1. Good ordering for the two highest-uncertainty items. (S3 above tightens this further for A1.5.)

**N4. T-WIRE-1 is correctly single-owner sequential** per project memory `feedback_test_orchestrator_wiring_gap.md` and `feedback_parallel_agents_shared_file_race.md`. Wave 4 dependency on T-TEST-1..10 is correct.

**N5. T-DOC-* tasks have no dependencies and run in Wave 3 in parallel.** This is fine, but T-DOC-1 (build-time clarifications) pins design decisions D5–D13 that influence T-CORE-* implementations. Consider promoting T-DOC-1 to Wave 0 so build agents have it as reference. Currently the design decisions live in the plan body and are passed to agents that way — workable but T-DOC-1 in Wave 0 would be cleaner.

**N6. e8 covers legacy `findings.jsonl` missing `personas[]`, but does NOT cover legacy missing `unique_to_persona`.** T-CORE-7 computes `unique_count` by reading `findings.jsonl.unique_to_persona`. If that field is absent on legacy rows, the count is silently zero. Either add an explicit `missing_uniqueness_field` warning + treat as `malformed`, or pin in T-DOC-1.

**N7. D7 fall-through (missing `participation.jsonl`) has no dedicated test.** T-TEST-2 A14 covers silent state's retention semantics, but the fall-through case (silent persona without participation.jsonl falls through to complete_value with total_emitted=0) deserves a sub-assertion — easy add to T-TEST-2.

## Verdict: PASS WITH NOTES

The plan is executable. The sequencing is mostly sound, risk de-risking is correctly front-loaded, and the wave structure honors parallel-agent constraints from project memory. **Two real fixes required** (S1 circular dep, S2 wave-leak) before /build dispatches; the rest are tightening recommendations that improve robustness without blocking the build.
