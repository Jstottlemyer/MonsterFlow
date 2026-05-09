# Scope Analysis — token-economics v4.2

## Critical Gaps

None. Out-of-scope statements are explicit and well-bounded; v1.1 commitments and deferral targets are named. MVP boundary (measurement-only, no automatic action) is unambiguous.

## Important Considerations

- **"Two honestly separated signals" (M3) re-opens the MVP question.** The whole spec frames itself around per-persona cost ↔ value alignment, but v1 explicitly declines to align them — cost-window and value-window have different denominators, and the proper join is v1.1+. This is correct under "best-effort instrumentation," but a stakeholder reading the dashboard will instinctively compare `avg_tokens_per_invocation` against `judge_retention_ratio` per persona and assume those are aligned. Recommend the dashboard tooltip on the cost columns *and* the `/wrap-insights` text section explicitly state "cost and value are measured over different windows in v1; treat side-by-side comparison as directional, not arithmetic." This is a one-line UX change, not a re-scope, but it should be in scope here, not deferred.

- **v1.1 commitment ("immediately after this lands") risks becoming the real MVP.** BACKLOG #3 (account-type agent scaling) is what actually delivers Pro-tier relief, which is explicitly named as the original motivation. The spec is honest about this ("the friend-on-Pro who motivated the work gets actionable cost reduction once the next spec ships, not from this one"). Watch for: if `/wrap-insights` after first 10 runs shows the data is too noisy for #3 to act on (e.g., everyone's `insufficient_sample: true`), v1.1 stalls and v1 becomes orphan instrumentation. Worth a single sentence in the spec naming the success criterion for "v1.1 unblocked": e.g., "≥10 personas per gate have `runs_in_window ≥ 3` within 30 days of v1 ship."

- **Eight M-fixes + six Δ-deltas + three rounds of resolved concerns is a lot of scar tissue for one spec.** Each individual change is justified, but the cumulative effect is a spec where the MVP is hard to extract from the revision log. Consider folding M1–M8 and Δ1–Δ6 into the body of the spec at /build time and demoting the change tables to a CHANGELOG appendix — otherwise reviewers of v1.1 will re-litigate decisions that are buried in tables.

- **Dashboard "Persona Insights" tab is the third top-level mode tab.** Spec doesn't say what the existing two are or whether adding a third changes navigation hierarchy. Low-risk but worth a one-line confirmation that the existing tabs aren't being reshuffled.

- **`tests/fixtures/cross-project/` synthetic trees (A3) need a size budget.** Two synthetic project trees with `findings.jsonl` + `survival.jsonl` + `run.json` + `raw/<persona>.md` per gate per feature could grow large. If unbounded, fixture maintenance becomes a recurring tax. Recommend ≤5 features per synthetic project, ≤3 personas per gate.

## Observations

- **Phasing is clean.** Phase 0 spike → Phase 1 instrumentation → Phase 2 visualization is well-seamed. The A1.5 forcing function (build fails on Q1 disagreement, `/plan` re-opens) is a strong incremental gate.

- **Out-of-scope list is unusually thorough** (10 items, each with a clear deferral target). This is a sign of a well-bounded spec. The "logging-shim path if Phase 0 spike fails — separate spec, not in-flight expansion" line is exactly the right call.

- **Privacy carve-outs scale with the spec.** Allowlist enforcement (A10), salted finding IDs (Δ3), counts-only telemetry (Δ4), opt-in scan with non-tty refusal (M6), salt-corruption recovery (M7), inverted-assertion meta-runner (M8) — each addresses a real risk. Watch for adopter onboarding friction: a new user running `/wrap-insights` for the first time on a fresh install gets cwd-only data and a stderr nudge, but the path from "I see one project's data" to "I want all my projects" requires reading spec docs to find `--scan-projects-root` + interactive confirm. Consider whether `/wrap-insights` itself should print a one-line "want cross-project? run `compute-persona-value.py --scan-projects-root ~/Projects --confirm-scan-roots`" hint when it detects only cwd data. (Not blocking; UX nicety for v1.1.)

- **Window unit "(persona, gate) artifact directories" is unusual but defensible.** It's the right MVP choice given no per-dispatch join key, but it means `runs_in_window: 18` doesn't mean "this persona ran 18 times" — it means "18 directories where this persona contributed at least one bullet." That distinction matters for stakeholder interpretation and should be in the dashboard tooltip, not just the spec.

- **`scope-cuts` candidate already cut:** `/wrap-insights ranking` bare-arg full-table was correctly removed (one render surface fewer). No other obvious cuts available — the spec is already at MVP.

- **Natural seam for v1.1:** the `agent_tool_use_id` + `persona_content_hash` capture in `findings.jsonl` / `run.json` at emit time. Spec correctly names this as the unlock for invocation-level metrics. The `findings-emit` directive is explicitly NOT touched in v1, preserving the seam cleanly.

## Verdict

**PASS WITH NOTES** — scope is tight, MVP is well-bounded, deferrals are named with routing. The two-signal separation (M3) is the only structural risk, and it's a UX/framing concern (one tooltip + one text-section caveat), not a scope re-open.

class: scope-cuts | severity: minor — recommendation to add cost↔value alignment tooltip and v1.1-unblock success criterion are the only actionable items; neither blocks /plan.
