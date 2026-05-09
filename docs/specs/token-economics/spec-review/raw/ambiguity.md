# Ambiguity Analysis — token-economics v4.2

## Critical Gaps

**1. Flag count contradiction in §Project Discovery / CLI surface (M5).**
The paragraph header reads "**CLI surface (post-M5 fold): 5 flags total** — `--scan-projects-root`, `--confirm-scan-roots`, `--best-effort`, `--out`, `--dry-run`, `--explain`". That enumerates **6** flags, not 5. M8's table summary says "CLI now 5 flags + the new `--confirm-scan-roots` from M6 = 6 total." Build will hit this on day one (test for flag count, `--help` text, docs). Pick one count and fix prose, or two engineers will disagree on whether `--confirm-scan-roots` is part of the M5 cut or the M6 add.

**2. Persona count: "28 pipeline personas" vs "27 default personas".**
Frontmatter says `Session Roster: defaults-only (28 pipeline personas)`. Repo-level CLAUDE.md and user CLAUDE.md both say "27 default personas." A11's success criterion ("≥1 row per distinct (persona, gate) pair") and A5's "(never run)" rendering depend on the canonical roster count. Reconcile before build, or the roster sidecar emit will produce a count nobody can verify against expectations.

**3. Cost-window cap is asserted in summary but never restated as a hard rule.**
Summary says "cost metrics windowed over 45 most-recent observed Agent dispatches per (persona, gate)." The §Data row schema shows `cost_runs_in_window: 22` and `window_size: 45` but `window_size` is documented as the value-window cap. There is no explicit `cost_window_size` field and no explicit "the cost window also caps at 45" sentence in §Data or §Approach. Implementer could plausibly write an unbounded cost window. State explicitly: cost window cap = 45 dispatches per (persona, gate); add `cost_window_size: 45` to the schema OR reuse `window_size` and document that it governs both.

**4. `silent` state requires `participation.jsonl`, but its presence is never made a precondition.**
M4 silent state trigger reads "persona has `participation.jsonl` row with `status: ok` AND `findings_emitted: 0`." `participation.jsonl` is not listed in §Integration "Existing systems leveraged," and not in any acceptance criterion's preconditions. Behavior when `participation.jsonl` is missing or malformed is undefined — does the row fall through to `complete_value`? `malformed`? Get silently dropped? This decides whether legacy artifact directories (pre-persona-metrics-v0.2.0) get mis-bucketed as `complete_value` and pollute retention denominators with phantom-zero rows.

**5. A1 vs A1.5 token-source contradiction.**
A1 says "Per-persona cost = sum of subagent rows (exact equality)... `sum(per_persona_tokens across all gates) == sum(usage rows from subagents/agent-*.jsonl)` exactly." A1.5 says on agreement, parent annotation is canonical (cheap, used by `compute-persona-value.py`). If A1.5 passes (annotation == subagent sum), then A1 is satisfied trivially. If A1.5 fails, A1.5 fails the build first and A1 doesn't run. So A1's "exact equality" is either redundant or unreachable — there is no scenario where A1 fails but A1.5 passes. Clarify whether A1 reads the **output** column (`per_persona_tokens`) which uses `canonical_token_source()` (annotation on agreement) — that's the test that matters and the wording undersells it.

## Important Considerations

**6. "Best-effort" is used as a load-bearing term without an operational definition.**
Appears in: scope ("best-effort aggregate, no roster scaling"), e2 ("Best-effort window reset"), A4 ("best-effort"), `--best-effort` CLI flag (spike-failure abort threshold). Each usage has a different meaning: aggregate = artifact-directory granularity instead of dispatch; window reset = transient pre-edit data persists; CLI flag = downgrade A1.5 disagreement to warning. Define each at first use, or reviewers will conflate them.

**7. "Transient" / "may persist" in e2 + A4 has no bound.**
e2: "historical data may persist transiently in the window denominator until rolled out by 45 new invocations." Forty-five invocations on a low-traffic persona could mean months. Stakeholder reading the dashboard at week 2 will not understand why a persona's retention didn't reset after they edited the prompt. Either (a) state explicitly "ratios for edited personas are unreliable until the next 45 invocations replace the window," or (b) document a UI affordance (a `hash_changed_within_window: true` flag + dashboard tooltip).

**8. "v1.1" vs "v1.1+" inconsistency for the per-dispatch join key.**
M3 calls per-dispatch capture "v1.1+ scope." Backlog table calls #3 (account-type-agent-scaling) "committed v1.1 fast-follow." Open Question 3 says "v1.1+." Per-dispatch persona-content-hash is "v1.1+ scope" in §Out of scope but "Required for invocation-level metrics" in the backlog routing table. Reader can't tell whether per-dispatch capture lands in the immediate v1.1 or some later "v1.1+" wave. Pick "v1.1" or "v1.2" and stop using "+".

**9. `silent` state retention numerator semantics not test-asserted.**
Table cell: "✓ (numerator = 0, denominator includes emitted bullets)." A persona that runs silently 10 times with 5 bullets each (50 emitted, 0 retained) gets `judge_retention_ratio = 0.0`. Is that the intended UX signal — "this persona is producing bullets that judge clusters into nothing"? Or should silent runs be excluded from retention entirely (the persona didn't "fail to retain," it ran but had nothing to say)? Plausible split between two engineers. A2 doesn't test the silent-with-bullets case explicitly.

**10. "Discovered MonsterFlow project" never defined.**
Used 4×: in §Approach ("Walks `findings.jsonl`... across all discovered projects"), §Data ("most-recent 45 (persona, gate) artifact directories per persona-gate pair"), A11. Project Discovery cascade defines *how* to discover, but not *what counts*. Is a directory a MonsterFlow project iff `docs/specs/` exists? Iff `personas/` exists? Iff at least one `<gate>/findings.jsonl` exists? Cascade tier 3 says "walks `<dir>/*/docs/specs/`" — implies presence of `docs/specs/`. State explicitly: "a project root P qualifies iff `P/docs/specs/` exists and is a directory" (with symlink + permission edge cases).

**11. Downstream survival counting when `personas[]` has multiple entries.**
"`downstream_survived_count = rows in survival.jsonl with outcome == addressed whose finding_id joins to findings.jsonl rows where persona ∈ personas[]`." A finding with `personas: [scope-discipline, edge-cases]` and `outcome: addressed` — does each persona get +1, or do they share +0.5, or only the `unique_to_persona` value gets credit? Likely +1 each (multi-persona findings reward all contributors), but two engineers could implement it differently. Single-sentence clarification needed.

**12. Deleted-persona strikethrough rows have no GC.**
e7: "Rows for that persona remain in JSONL until window rolls out." But for a deleted persona, no new dispatches accumulate, so the window never rolls. Strikethrough rows live forever. Either document this explicitly (a TODO for v1.1 GC) or add a "drop rows where `persona_content_hash: null` AND `last_artifact_created_at` > 90 days" rule to compute-persona-value.py.

**13. M6 non-tty refusal: which `/wrap-insights` invocations have a TTY?**
M6 lists tmux pipe-pane and `dev-session.sh` as non-tty examples. Justin's standard tmux session pipes the claude window to `~/.claude/session-logs/` (per CLAUDE.md). So `/wrap-insights` invoked from inside that pane likely has stdin redirected away from a TTY. Result: tier-3 scan silently skips on every `/wrap-insights` call until Justin learns to run `--confirm-scan-roots` from a fresh non-piped shell. This is documented as the failure mode but the spec says "without this Justin hits silent refusal day-one" — the spec acknowledges the problem but doesn't establish whether `--confirm-scan-roots` is documented in `commands/wrap.md` so adopters discover it before silent-refusal fatigue sets in. Worth a sentence in §Integration.

## Observations

**14. "Date-minute" truncation phrasing (Δ2).** Standard term is "minute precision" or "second-truncated." "Date-minute" is unique to this spec. Cosmetic; rename for grep-ability.

**15. "Nulls always sort to bottom (always — locked)."** Doubled "always" is intentional emphasis but reads odd. Consider "Sort places null cells at the bottom regardless of sort direction (locked behavior, not user-toggleable)."

**16. "Window: 45 (persona, gate) artifact directories" vs "global most-recent-by-`run.json.created_at` cap" in same section.** The "global" wording in §Approach reads as if 45 is a global cap, then "Window applies independently per (persona, gate)" clarifies. The two sentences should be merged or the word "global" struck — it's misleading.

**17. A0 verification `tests/fixtures/persona-attribution/ exists with ≥1 .jsonl validating against schemas/persona-rankings.allowlist.json`.** The persona-attribution fixture is a *raw subagent transcript excerpt*; the allowlist schema is for `persona-rankings.jsonl` *output*. These are different shapes. Either A0's check is wrong (should validate against a separate `persona-attribution.allowlist.json`), or the same allowlist covers both — needs explicit statement. Easy fix; high risk of being implemented inconsistently.

**18. "First-column indent" bullet definition.** Markdown allows `- bullet` and `  - bullet` (continuation/nested) and ` - bullet` (one-space lead, still considered top-level by some renderers). Define the regex precisely: `^[-*] ` (zero leading whitespace, dash or star, single space). Otherwise persona authors who happen to put one space before `-` get their bullets silently dropped from `total_emitted`.

**19. M3 example row has `cost_runs_in_window: 22` and `runs_in_window: 18` — the example is internally consistent (cost > value) but doesn't show the case where value > cost.** Could happen if the cost window expired (≥ 45 dispatches dropped pre-Anthropic-format-change) but value window still has older directories. Worth a second example or one sentence: "Either window may exceed the other depending on retention of source data."

**20. "Refresh hook in `/wrap-insights` Phase 1c — **unconditional**".** "Unconditional" is ambiguous — does it mean "runs every invocation regardless of cost-budget gates" or "runs even on errors"? Both readings are coherent. Suspect the first; clarify.

## Verdict

**PASS WITH NOTES** — spec is unusually precise on data semantics (run-state machine, denominator transparency, idempotency contract) but has two genuine contradictions (CLI flag count, persona count) and one schema/fixture-shape ambiguity (A0 allowlist target) that two engineers will implement differently. Resolve gaps 1–5 before `/build`; gaps 6–13 are answerable in `/plan` design synthesis.
