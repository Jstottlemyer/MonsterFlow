# Technical Feasibility Review — token-economics v4.2

## Critical Gaps

**None blocking.** All previously-identified critical feasibility risks (cost↔value join, hyphen-import, jsonschema dep, salt corruption, non-tty refusal) have been resolved in M1–M8. No remaining items rise to "must answer before build can start."

## Important Considerations

- **`class: architectural` — Phase 0 spike Q1 still open at build start.** A1.5 is the forcing function, but if disagreement fires mid-build, `/plan` re-opens and `compute-persona-value.py` switches to subagent-canonical reads. That's a non-trivial re-architecture (per-row JSONL walk vs. single annotation parse) discovered after code lands. Mitigation: front-load A1.5 as the *first* test written, not the last.
  - `suggested_fix`: Add an explicit "Phase 0.5" build step — run A1.5 against the existing RedRabbit fixture before any production code is written. If it fails, treat as a spec-revision event, not a build event.

- **`class: contract` — `subagents/agent-<id>.jsonl` path is undocumented Anthropic CLI internals.** Spec relies on (a) the directory existing, (b) the `agentId` trailing-text format in tool_results, and (c) `agent-<id>.meta.json` schema. None of these are versioned APIs. A single Claude Code release can break the whole pipeline silently. A1.5 catches *value drift* but not *path/format drift*.
  - `suggested_fix`: Add a startup probe in `compute-persona-value.py` that asserts at least one expected `subagents/` directory exists under `~/.claude/projects/*/` and emits a single stderr line `[persona-value] CC subagent layout v? detected` with the structural shape it found. Fail soft (`run_state: cost_only` for everything) rather than hard, so a CC update degrades gracefully.

- **`class: contract` — regex extraction of `personas/<gate>/<name>.md` from `Agent.input.prompt` is fragile.** Spike says the regex worked across 73 fixtures from one project. Other projects may template the prompt differently (constitution-based rosters, custom dispatchers, future `/build` parallel-agent prompts that cite multiple personas). Spec acknowledges `<unknown>` fallback but doesn't bound the unknown rate.
  - `suggested_fix`: Add an A1.6 that asserts `unattributed_dispatch_rate < 5%` across the fixture set, with `--best-effort` lowering the bar. Otherwise the cost column quietly under-counts.

- **`class: tests` (carve-out: changed trust boundary) — salt regeneration clears `persona-rankings.jsonl`.** M7's "regenerate-and-clear" is correct but destructive. There's no test for the *recovery path*: what does the dashboard render in the gap between salt regen and the next `/wrap-insights`? Empty file? Stale file? An empty dashboard right after a privacy event will look like a bug to the adopter and trigger a support cycle.
  - `suggested_fix`: A12 — after simulated salt corruption + regen, dashboard renders the e12 fresh-install banner ("No data yet…"), not a blank table or JS error.

- **`class: tests` — A1 asserts exact equality `sum(per_persona_tokens) == sum(usage rows)`.** This will fail any time the parent session has Agent dispatches whose persona regex didn't match (orchestrator dispatches, ad-hoc subagents like `persona-metrics-validator`, future `Agent` calls in `/build`). Spec calls these out via `<unknown>` and `orchestrator_tokens` diagnostic columns, but A1's "exact equality" wording contradicts the `<unknown>` allowance.
  - `suggested_fix`: Reword A1 to `sum(per_persona_tokens) + sum(unknown_tokens) + sum(orchestrator_tokens) == sum(usage rows from subagents/)`. The exact-equality semantic moves to the *partition*, not the persona bucket alone.

## Observations

- `class: documentation` — The 7-state run-state table is thorough but the `silent` row's "numerator = 0, denominator includes emitted bullets" is contradictory: if a persona emitted 0 bullets (`findings_emitted: 0`), the denominator should also be 0, which makes `judge_retention_ratio` null per e10. Either silent contributes (0,0) → null, or it contributes (0,N) → 0. Pick one and update e10 cross-reference.

- `class: documentation` — The `persona_content_hash` is described as "NFC + LF-normalized" sha256. Spec doesn't say whether trailing whitespace, BOM, or Markdown frontmatter changes count. Adopters editing personas in different editors will see spurious window resets. Worth one sentence pinning the normalization (e.g., `unicodedata.normalize('NFC', text).encode().rstrip(b'\n') + b'\n'`).

- `class: scope-cuts` — `--explain PERSONA[:GATE]` flag is in the §Project Discovery CLI surface but never described in §Approach or covered by an AC. Either spec it or drop it; a flag without behavior is build-time ambiguity.

- `class: documentation` — §Multi-machine sync says JSONL is gitignored, machine-local. But §Privacy says `tests/fixtures/persona-attribution/` is *committed*. If an adopter runs the redaction helper against their own machine's data and commits a fixture, the salted IDs leak the salt's effect (though not the salt itself). Worth a one-line warning in the redaction helper.

- `class: tests` — A8 idempotency check excludes `last_artifact_created_at` (minute-truncated). Within the same minute, two runs are byte-identical; across a minute boundary they're not. Test needs to either freeze time or assert idempotency *modulo* that field. Current wording is ambiguous.

- `class: documentation` — The 45-window unit changed from "Agent dispatches" (cost) to "artifact directories" (value) in v4 — M3 makes this explicit, but the §Summary still says "windowed over 45 most-recent (persona, gate) artifact directories" for value and "45 most-recent observed Agent dispatches" for cost without surfacing that these are *different* 45s. The data row schema clarifies via `cost_runs_in_window`, but the prose intro should make the dual-window explicit on first read.

## Verdict

**PASS WITH NOTES** — All previously-blocking technical infeasibilities (CC subagent linkage, schema validation, salt handling, cost↔value join) are now spec'd to the level a competent build can execute against. Remaining concerns are contract-fragility (undocumented CC internals) and test-precision tightening, both addressable inline during `/plan` or as M9-class deltas without re-litigating scope.
