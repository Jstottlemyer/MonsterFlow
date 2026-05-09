OVERALL_VERDICT: GO_WITH_FIXES

# Plan Checkpoint Synthesis — token-economics v4.2

All six reviewers independently converged on **PASS WITH NOTES**. The plan is structurally sound, AC→task mapping is complete, parallel-agent constraints are honored, and risk de-risking is correctly front-loaded. Eight non-security blockers and five security blockers are surgical edits — none reshape the architecture.

## Reviewer Verdicts

| Persona | Verdict | Must Fix | Should Fix |
|---|---|---|---|
| completeness | PASS WITH NOTES | 0 | 5 |
| risk | PASS WITH NOTES | 3 | 6 |
| scope-discipline | PASS WITH NOTES | 0 | 6 |
| security-architect | PASS WITH NOTES | 5 (all sev:security) | 2 |
| sequencing | PASS WITH NOTES | 2 | 3 |
| testability | PASS WITH NOTES | 3 | 5 |

## Must Fix (blockers — apply inline before /build dispatches Wave 0)

**Architectural / sequencing**
1. **S1 — Circular dep T-CORE-10 ↔ T-CORE-15** (sequencing). T-CORE-10 emits the bundle that includes the roster T-CORE-15 produces, but T-CORE-15 is declared as depending on T-CORE-10. Flip the arrow: T-CORE-10 must depend on T-CORE-15.
2. **S2 — T-TEST-9 leaks Wave 2 into Wave 3** (sequencing). T-TEST-9 depends on T-UI-2 (Wave 3). Either re-bucket to Wave 3 or split into compute-side recovery (Wave 2) + dashboard render assertion (Wave 3).

**Risk-handling tightening**
3. **MF-1 — Promote A1.5 to Phase 0.5 probe** (risk). A1.5 currently fires mid-Wave-2 after ~15 Wave-1 tasks have committed to a canonical-source choice. Carve `tests/test-token-source-canonical.sh` as T-PRE-4 against redacted RedRabbit fixture before T-CORE-5 starts.
4. **MF-2 — Quantified persona-regex match-rate AC** (risk). Promote Open Q #6 to hard AC A1.6 in T-CORE-6: ≥95% of Agent dispatches whose prompts contain `personas/` resolve to a non-`<unknown>` (persona, gate). Below threshold → exit non-zero unless `--best-effort`.
5. **MF-3 — Salt corruption default to warn-and-refuse** (risk). T-CORE-3 currently silently regenerates and clears `persona-rankings.jsonl`. Default to refuse + require explicit `--accept-salt-reset` flag for the destructive path. Add to T-TEST-6.

**Test-coverage gaps**
6. **tv-1 — A1.5 failure-path fixture** (testability). Add `tests/fixtures/persona-attribution/a1_5-disagreement.jsonl` with deliberate parent-vs-subagent token mismatch. Assert non-zero exit. Without it, A1.5 can silently regress.
7. **tv-2 — Bullet-regex edge-case fixtures** (testability). Add `tests/fixtures/persona-attribution/raw-edge-cases.md` covering the four exclusion categories (## Verdict bullets, numbered lists, nested bullets, unrelated headings). Silent regex drift corrupts every retention number.
8. **tv-3 — T-TEST-10 perf must hard-fail at 15s** (testability). Soft-fail-only ships regressions silently. Hard-fail at 3× budget; warn at 1×.

**Security blockers (sev:security — listed in `security_findings[]` only, per array-disjointness rule)**
- **SEC-1** — `--explain` TTY check must gate on `isatty(stdout)`, not stdin (redirect leaks finding titles).
- **SEC-2** — tmux pipe-pane defeats Δ4 paths-only-in-prompt contract; T-CORE-2 must detect pipe-pane and refuse or redact.
- **SEC-3** — `scan-roots.confirmed` and `monsterflow/projects` config files lack `chmod 600` parity with `finding-id-salt`.
- **SEC-4** — Allowlist validation must run pre-write (in-memory before tmp materialization), not post-write.
- **SEC-5** — Salt regeneration must wipe `persona-insights-bundle.js` alongside `persona-rankings.jsonl`; bundle currently outlives the rotation.

## Should Fix (apply inline if cheap; otherwise carve as followups.jsonl)

- **SF-1..SF-6** (scope) — Cut T-DOC-4, defer T-CORE-13 `--explain`, drop `--quiet`, fold T-TEST-9 into T-TEST-6, defer T-CORE-11 schema-version guard, trim T-DOC-2 to two essentials.
- **SF-1..SF-6** (risk) — `session-cost.py` caller enumeration, T-TEST-10 hard ceiling, `--explain` TTY test, `validate_project_root()` contract, v1.0.x corrective-regen lever, persona-author defensive default (hide bottom-3 unless ≥10 runs).
- **Completeness 1–5** — e6 stale-cache banner ownership, `MONSTERFLOW_DEBUG_PATHS=1` task ownership, counts-only stderr literal-format test, `/wrap-insights` Phase 1c rendered-format check, A4 fixture pre-conditions.
- **N1, N3–N7** (sequencing) — `run.json` historical-absence enumeration, T-CORE-6 persona-name extractability assertion, promote T-DOC-1 to Wave 0, e8 `unique_to_persona` legacy gap, D7 fall-through sub-assertion.
- **tv-4..tv-8** (testability) — Concurrent-case test, stale + all-insufficient banner tests, T-CORE-6 threshold assertion, `<unknown>` toggle test, dashboard tab regression test.
- **SEC-6, SEC-7** (security, non-blocking) — `--confirm-scan-roots` audit trail (promote Open Q4); extend T-TEST-8 grep-ban to imported `session-cost.py`.

## Decision Path

GO_WITH_FIXES because: (1) all six reviewers independently returned PASS WITH NOTES; (2) the eight non-security blockers are surgical (one arrow flip, one re-bucket, three risk-default tightenings, three test-fixture additions); (3) the five security blockers are seam-closing edits, not architectural reshapes (write-time validation ordering, derived-artifact rotation coupling, file-perm parity, redirect-aware TTY gates, pipe-pane awareness) and do not auto-halt the pipeline per `feedback_security_n_attempts_before_block.md`; (4) Codex round-3 plan-vs-codebase verification is recommended before /build per `feedback_codex_catches_plan_vs_reality_drift.md`. Apply Must-Fix inline; carve Should-Fix items above the cap into `followups.jsonl` for /build to consume verdict-gated.

