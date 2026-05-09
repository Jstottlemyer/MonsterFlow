## Critical Gaps

None. The spec defines acceptance criteria A0–A11 with binary, machine-verifiable assertions; success = "all tests pass + first `/wrap-insights` produces ≥1 row per (persona, gate) pair." A QA engineer could write a test plan from this alone.

## Important Considerations

- **Performance/scale targets absent.** No upper bound on `compute-persona-value.py` runtime, memory, or input size. With cross-project scanning over 45-directory windows × N projects × subagent JSONL walks, this could become slow. Suggest: target wall-time budget (e.g., "≤5s on 10 projects × 45 dirs each") and fail-loud above 2× budget. Relevant because `/wrap-insights` invokes it unconditionally — slow runs degrade end-of-session UX.
- **Recovery time / partial failure SLO undefined.** Spec covers *what* happens on malformed JSONL, missing artifacts, salt corruption — but not *how loudly* failures surface. E.g., if 40% of artifact dirs are `malformed`, does the dashboard still render? Should there be a `health_state` summary at the top of `persona-rankings.jsonl`? Adopters need a quick "is my data trustworthy right now" signal.
- **Observability is one-line stderr only.** No log file, no structured event for "scan completed, N dirs processed, M malformed, K skipped." `MONSTERFLOW_DEBUG_PATHS=1` writes to `~/.cache/monsterflow/debug.log` but only for path debugging. For a measurement system whose whole purpose is trustworthy numbers, an audit log of what was counted would help diagnose suspicious results — especially given the v3→v4 history of denominator confusion.
- **A1.5 "build fails on disagreement" path lacks a recovery plan.** If parent annotation diverges from subagent transcript sum on a real machine, the spec says "`/plan` re-opens Q1" — but this is a *spec* recovery, not a *runtime* recovery. What does an adopter see if A1.5 fires on their machine post-ship? A `--best-effort` flag exists for the spike-failure path (Open Q2) but it's unclear whether it also degrades A1.5 or only the 99% linkage threshold.
- **No A/B comparison criterion for the value signals themselves.** Spec ships three rates (judge_retention, downstream_survival, uniqueness) but defines no validity check — e.g., "if all three rates are perfectly correlated across personas, the system has redundant signals." Round-1/2 reviewers killed the composite score for being gameable; a sanity check that the three axes carry independent information would protect against the same critique post-ship.

## Observations

- "Done" definition is unusually well-bounded: A11 names the precondition explicitly ("at least one source row exists") and e12 carves out the fresh-install case so the criterion isn't ambiguous.
- Privacy gates are testable end-to-end (A9 + A10 with deliberate-failure fixture + inverted-assertion meta-runner per M8). This is stronger than typical spec-level privacy claims.
- `run_state` 7-state machine + per-state denominator table makes "what counts where" auditable — this is the right shape for a measurement spec where stakeholder trust depends on transparent arithmetic.
- The downstream-timing caveat (low survival ≠ rejected; may mean "not yet evaluated") is documented in the schema and tooltip — good defense against misinterpretation, but worth a one-line README note for adopters who export screenshots.
- M3 (cost vs value windows are independent) is correctly called out as the honest framing, but the dashboard tooltip is the *only* place adopters learn the two `runs_in_window` numbers mean different things. Consider a more visible UI affordance (separate column header groups, distinct iconography) — easy to miss in a sortable table.
- No explicit acceptance criterion that `dashboard/data/persona-rankings.jsonl` round-trips through `jq` cleanly — minor, but would catch JSON-vs-JSONL regressions cheaply.

## Verdict

**PASS WITH NOTES** — Acceptance criteria are binary and testable, edge cases are enumerated, privacy/idempotency contracts are sharp; remaining gaps are non-functional (perf budget, observability, A1.5 runtime recovery) and can be addressed inline without re-opening scope.
