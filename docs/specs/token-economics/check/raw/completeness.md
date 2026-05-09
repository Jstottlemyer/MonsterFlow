# Plan Completeness Review — token-economics v4.2

## Must Fix

None. All 11 spec ACs (A0–A11) plus the 3 plan-added ACs (A12–A14) have explicit task mappings, fixtures are planned, and the wave structure respects the parallel-agent shared-file rules from project memory.

## Should Fix

1. **e6 stale-cache banner (14+ days) not explicitly enumerated in T-UI-2.** Spec §Edge Cases e6 requires "Dashboard shows stale-cache banner with last refresh timestamp." T-UI-2 lists multiple banners (warning banner, fresh-install banner, insufficient-sample banner via T-UI-3) but does not call out the 14-day stale-cache banner. Without it, e6 ships unverified. Either add to T-UI-2's enumeration or carve as T-UI-4. A7 (e1–e12 coverage) only tests the data-layer side; the UI surface for e6 has no dedicated check.

2. **`MONSTERFLOW_DEBUG_PATHS=1` env-var path-logging behavior unassigned.** Spec §Project Discovery (Δ4) mandates: paths emitted only behind this env var, logged to `~/.cache/monsterflow/debug.log`. No task in T-CORE-1..15 explicitly owns this implementation, and no test in T-TEST-1..10 verifies the gating. Suggest folding into T-CORE-12 (telemetry) and adding an assertion in T-TEST-8 or a dedicated case in T-TEST-7.

3. **Counts-only stderr telemetry format not verified by any test.** Spec Δ4 pins the literal format `[persona-value] discovered N projects (sources: cwd:1, config:M, scan:K)`. T-TEST-8 grep-bans raw `print()`/`sys.stderr.write()` (discipline), but no test asserts the literal one-line format renders correctly under each cascade tier. Without this, Δ4 regresses silently. Add a single assertion to T-TEST-7 (it already exercises cascade flows).

4. **`/wrap-insights` Phase 1c rendered-format match has no automated check.** T-WRAP-1 modifies `commands/wrap.md` and A6 verifies "output includes 'Persona insights (last 45 …)' …" but no test in Wave 2 captures `/wrap-insights` text-section output and asserts the top/bottom-3-per-gate-per-dimension structure. T-VERIFY-1 covers this manually only. For a deterministic gate, consider a fixture-driven test that runs the rendering function (refactored out of `wrap.md` into a Python helper if needed) and asserts shape.

5. **A4 fixture pre-conditions not made explicit.** T-TEST-2 lists A4 as covered, but A4 requires "(1) seed N invocations; (2) modify persona file body; (3) run one fresh dispatch; (4) re-run compute." That's a four-step fixture choreography. Worth carving as an explicit sub-step inside T-TEST-2's task description so the build agent doesn't ship a thin assertion.

## Notes

- **All 11 spec ACs map to ≥1 task and ≥1 verification path** per the §Verification & Acceptance Mapping table. No spec requirement is orphaned.
- **All 8 must-fix items (M1–M8) and all 6 deltas (Δ1–Δ6) are present** in either Wave 0 or Wave 1 tasks.
- **Operational readiness is appropriate for the spec's scope**: no rollback plan, no monitoring, no error-budget — but this is measurement-only/additive, no production runtime path, so the omission is intentional and correct.
- **Test orchestrator wiring (T-WIRE-1) is correctly carved as a single-owner sequential post-step**, addressing the recurring `feedback_test_orchestrator_wiring_gap.md` pattern.
- **Subagent invocation post-build (T-VERIFY-2 → `persona-metrics-validator`) is explicitly listed**, matching spec §Integration "Subagents to invoke during/after build."
- **`tests/fixtures/cross-project/` for A3 is explicitly named** (T-TEST-2 task description). Good — it would otherwise be implied work.
- **Schema-migration policy (D6) and `<unknown>` bucket contract (D4) are net-new design decisions added by the plan**, both warranted, both with verification (A12 + T-TEST-9; UI toggle in T-UI-2).
- **Linux-untested disclaimer is folded into T-DOC-2** per Open Question #3 — appropriate.
- **T-DOC-1 modifies the spec itself** to append a "Build-time clarifications" appendix codifying D5–D13. Unusual but defensible since these are pin-downs of underspecified items, not re-litigation. Worth flagging to the build agent so it understands this is intentional and not scope creep.
- **`install.sh` wiring for `~/.config/monsterflow/README.md` is correctly deferred** per spec; T-DOC-4 stages content at `docs/specs/token-economics/config-readme.md` for future copy-in. BACKLOG note is acknowledged.
- **R6 (CC subagent layout drift)** is well-handled by T-CORE-6 runtime probe; format-drift will produce a stderr warning rather than a silent miss.
- **D1 single-bundle architecture is a strict simplification** of the spec's two-file design — risk #2 is fully mitigated and no spec AC depends on the two-file shape.

## Verdict

**PASS WITH NOTES** — Plan covers every spec AC with explicit task mappings, fixtures are enumerated, wave structure respects parallel-agent constraints, and risks are itemized; a handful of edge-case banners and telemetry-format checks need explicit task ownership before `/build` to avoid silent regression.
