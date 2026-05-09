# Spec Review — token-economics

**Reviewed:** 2026-05-09
**Reviewers:** ambiguity docs-clarity feasibility gaps requirements scope stakeholders

---

## ambiguity

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

---

## docs-clarity

# Docs Clarity Review — token-economics spec v4.2

## Critical Gaps

```yaml
- persona: docs-clarity
  finding_id: dc-01-no-elevator-pitch
  severity: major
  class: documentation
  title: "Summary buries the elevator pitch under five clauses of qualification"
  body: |
    First sentence runs 50+ words and fronts the mechanism ("Measure per-persona cost
    and per-persona value along three independent axes") before the reader knows what
    "persona," "gate," "judge-retention," "uniqueness," or "downstream-survival" mean.
    A stranger landing on this spec cannot answer "what is it?" without reading the
    Backlog Routing table and Phase 0 Spike. The 30-second test fails on Q1.
  suggested_fix: |
    Open Summary with: "This adds a dashboard tab and `/wrap-insights` text section
    that show how many tokens each reviewer persona costs and how often its findings
    survive into the next pipeline stage. Measurement only — no automatic pruning."
    Then keep the existing paragraph as the second paragraph.
```

```yaml
- persona: docs-clarity
  finding_id: dc-02-jargon-undefined-on-first-use
  severity: major
  class: documentation
  title: "Domain terms used before definition: gate, persona, judge, sidecar, fence, axis, Δ, M-prefix"
  body: |
    Summary uses "gate," "Judge," "personas," "sidecar," "axis" as if defined.
    "Δ1–Δ6" and "M1–M8" appear in the revision header and recur throughout with no
    legend until §Spec Must-Fixes (line ~250) and §Spec Deltas (line ~270). A reader
    encountering "v4.2 applies 8 must-fix items from `/check`" in the header has no
    way to know M-items are check findings and Δ-items are plan findings.
  suggested_fix: |
    Add a one-line glossary block right after the YAML frontmatter:
    "Terms: gate = pipeline stage (spec-review/plan/check). Persona = reviewer agent
    invoked at a gate. Judge = clustering step that dedupes parallel reviewer output.
    M# = must-fix from /check. Δ# = delta from /plan."
```

## Important Considerations

```yaml
- persona: docs-clarity
  finding_id: dc-03-revision-header-noise
  severity: minor
  class: documentation
  title: "Revision line is a 60-word changelog where the reader expects a one-line status"
  body: |
    The `Revised:` field smashes four revision histories into one sentence with em-dash
    chains. Project memory `feedback_no_em_dashes.md` flags em-dashes as an AI tell;
    this header has 6+ of them.
  suggested_fix: |
    Move the per-revision change list into a `## Revision History` section at the
    bottom. Keep `Revised:` as a date only.
```

```yaml
- persona: docs-clarity
  finding_id: dc-04-no-first-command
  severity: minor
  class: documentation
  title: "No 'first command an adopter would run' anywhere in the spec"
  body: |
    Spec is implementation-facing, but the §Summary promises a dashboard tab and a
    `/wrap-insights` section a user will see. There's no concrete "after build, run
    `/wrap-insights` and look for the Persona Insights row" callout. The 30-second
    test Q4 fails for any non-builder reader.
  suggested_fix: |
    Add an "Adopter-visible surface" subsection under Summary with the literal command
    and the literal banner text the adopter sees on first render.
```

```yaml
- persona: docs-clarity
  finding_id: dc-05-cost-vs-value-window-confusion
  severity: minor
  class: documentation
  title: "M3 'two honestly separated signals' is the most important concept and the hardest to find"
  body: |
    The single biggest user-facing semantic in v4.2 is that cost-window and value-window
    have different denominators. Currently disclosed in Summary parenthetical, restated
    in §Data row schema comments, and again in §Run state machine note. A reader
    skimming will misinterpret `total_tokens / runs_in_window` as the avg cost.
  suggested_fix: |
    Promote to a 3-line callout block under §Summary: "Cost denominator ≠ value
    denominator. `avg_tokens_per_invocation = total_tokens / cost_runs_in_window`,
    NOT `/ runs_in_window`. They count different things."
```

## Observations

- Frontmatter `confidence` block uses 6 axes with no legend; reader can't tell if 0.93 is good.
- "Best-effort aggregate, no roster scaling" in `description:` reads as engineering self-soothing, not user value.
- §Spec Review Round 1+2+3 Resolved Concerns section (~80 lines) is provenance, not specification; consider moving to a sibling `review-history.md`.
- "Δ" character renders inconsistently across terminals; spelling "Delta" in body would survive copy-paste.

## The 30-Second Test

Reading only the YAML frontmatter + Summary + first scroll (through Backlog Routing):

1. **What is it?** Partial — "per-persona cost + retention + downstream-survival + uniqueness instrumentation" requires knowing what those four nouns mean in context. Reader can guess "tracking how reviewers perform" but cannot picture the artifact.
2. **Who is it for?** Fails — never stated. Implicit: MonsterFlow maintainers + adopters who see the dashboard. The "friend on Pro" clue in para 2 hints at audience but doesn't name it.
3. **Why would I install it?** Partial — "Pro-tier relief comes in v1.1" is the closest framing of user pain. The spec itself is measurement-only; the why is "so v1.1 has data to act on," which requires reading paragraph 3.
4. **What's the first command I'd run?** Fails — no command is named in the first scroll. Reader has to infer from §Approach Phase 1 that `/wrap-insights` triggers it.

Two of four answers fail the skim test. Both are recoverable with the suggested fixes above.

## Verdict

**PASS WITH NOTES** — content is rigorous and review-cycle-honest, but the document is written for the next reviewer in the pipeline rather than a stranger; a 6-line opener (elevator pitch + glossary + adopter-visible surface) would close the comprehension gap without changing scope.

---

## feasibility

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

---

## gaps

# Missing Requirements — Review of token-economics v4.2

## Critical Gaps

**1. `--explain PERSONA[:GATE]` flag is listed in CLI surface but never specified.**
- `class: contract`, `severity: major`
- §Project Discovery / CLI surface (post-M5 fold) names six flags including `--explain PERSONA[:GATE]`. No section defines what it outputs, what schema it follows, or which sources it joins. Future engineer / adopter trying to debug "why does scope-discipline show 0.42 retention?" has no documented path. Either spec the output (drill-down rendering of `contributing_finding_ids[]` resolved against current `findings.jsonl`?) or remove from CLI surface.

**2. Schema migration path for `schema_version: 1` → v1.1+ is undefined.**
- `class: architectural`, `severity: major`
- v1.1 is "committed fast-follow" and will add `agent_tool_use_id` + per-dispatch `persona_content_hash`. The JSONL is rolling — when v1.1 ships, do existing v1 rows get migrated, regenerated, dropped on read, or coexist? Adopters with months of v1 data on disk will hit this immediately. Add a one-paragraph migration contract: e.g., "v1.1 reader treats v1 rows as `cost_only` until next `compute-persona-value.py` regenerates" — or "v1.1 release notes instruct `rm dashboard/data/persona-rankings.jsonl` before upgrade."

**3. The `<unknown>` persona bucket has no defined rendering / exclusion contract.**
- `class: contract`, `severity: major`
- Pseudocode at §Data: `if not persona: persona = "<unknown>"`. Description-invoked subagents (e.g. `persona-metrics-validator`, `autorun-shell-reviewer`) hit this path. Does a `<unknown>` row render in the dashboard table? Is it excluded from `/wrap-insights` top/bottom 3? Counted toward cost-window for which gate? Without a contract, this row will silently bias rankings. At minimum: spec that `<unknown>` rows are excluded from value-rate rendering and sort-bottomed in cost columns, OR aggregated under a single `<unknown>:<unknown>` row that's hidden behind a toggle.

**4. Window rollover mechanism is asserted but not specified.**
- `class: contract`, `severity: major`
- §Edge Cases e2 + Window section say "old data may persist transiently in the window denominator until rolled out by 45 new invocations." There is no defined pruning step. Is the JSONL re-emitted from scratch each `compute-persona-value.py` run by walking the most-recent-45 directories per (persona, gate)? Or is it append-with-cap? A8 idempotency requires the former, but the spec never says so. State explicitly: **JSONL is fully rebuilt every run from the rolling-45 source window; no append path exists.**

## Important Considerations

**5. Historical artifacts predating persona-metrics v0.2.0 have undefined treatment.**
- `class: tests`, `severity: minor`
- Adopters with `docs/specs/<feature>/<gate>/` directories from before `findings.jsonl` / `survival.jsonl` existed will have artifact dirs that fail every state. Spec says `missing_findings` for these — fine — but they still consume window slots, displacing valid recent data. Consider: skip directories whose `run.json` predates `findings-emit` directive, OR exclude `missing_findings` from the 45-window denominator entirely (currently they count). A2 should test this.

**6. Telemetry stderr line has no opt-out.**
- `class: documentation`, `severity: minor`
- Δ4 mandates `[persona-value] discovered N projects (sources: ...)` on every invocation. CI / `/autorun` logs accumulate this on every `/wrap-insights`. No `--quiet` flag, no `MONSTERFLOW_QUIET=1` env, no documented suppression. Counts-only is privacy-safe but noisy. Add a `--quiet` flag or document that `2>/dev/null` is the supported suppression.

**7. Adopter discoverability of cross-project aggregation is left as "opens an issue in onboarding."**
- `class: documentation`, `severity: minor`
- §Project Discovery / Lifecycle: "Discoverable via the stderr telemetry plus a one-line README at `~/.config/monsterflow/README.md` written by `install.sh` if absent (out of scope here; opens an issue in onboarding)." This is a deferred-to-nowhere — no BACKLOG entry, no tracking. Either add to BACKLOG with a link, or spec the README content here (the spec already knows what it should say).

**8. Dashboard accessibility is unspecified for a sortable data table.**
- `class: documentation`, `severity: minor`
- The "Persona Insights" tab adds sortable columns + collapsible drill-down. No mention of keyboard nav, ARIA roles, or screen-reader semantics. MonsterFlow is OSS; some adopters will need this. Acknowledge in scope-cuts or add a one-line A5 sub-criterion ("table headers carry `role="columnheader"` + `aria-sort`").

**9. Salt rotation has no operator-facing procedure.**
- `class: documentation`, `severity: minor`
- M7 specifies auto-regenerate-and-clear on validation failure. There is no documented manual rotation: an adopter who suspects salt compromise (e.g., they accidentally `cat ~/.config/monsterflow/finding-id-salt` in a screenshot) needs to know to `rm` it and accept drill-down reset. Add a one-liner to the privacy section: "To rotate salt: `rm ~/.config/monsterflow/finding-id-salt`. Next run regenerates and clears rankings."

**10. `personas/` directory absence is not in the edge-case table.**
- `class: tests`, `severity: minor`
- Roster sidecar emit walks `personas/{review,plan,check}/*.md` in cwd. If an adopter clones MonsterFlow as a library / partial install, this glob may be empty. Behavior? Empty `persona-roster.js`? Crash? Should join e9 (deleted persona) and e12 (fresh install) as e13: "personas/ directory missing → emit `window.PERSONA_ROSTER = []` and dashboard shows empty roster + JSONL-only data rows."

**11. Subagent transcript missing-but-parent-annotation-present case is undefined.**
- `class: tests`, `severity: minor`
- §Cost attribution pseudocode reads `subagents/agent-<agentId>.jsonl`. What if the user has run `~/.claude/projects/` cleanup tooling that deletes `subagents/` subdirs but leaves parent JSONLs? Falls back to parent annotation? Skips the dispatch entirely? A1.5 disagreement path is specified, but the *missing* path is not. Add an edge case: missing subagent transcript → trust parent annotation, log allowlist-scrubbed warning, count toward cost-window.

## Observations

**12. Audit-trail field for the `--confirm-scan-roots` action is absent.**
- `class: scope-cuts`, `severity: nit`
- M6 appends to `scan-roots.confirmed`. Useful but no audit (when, what version added it). Future "why does this scan ~/old-project?" debugging will require git-log archaeology that doesn't exist (file is gitignored). A comment header on the file (`# added by --confirm-scan-roots on 2026-05-09 by monsterflow vX.Y.Z`) is essentially free. Defer or accept.

**13. Time-of-day collision in `last_artifact_created_at` minute-truncation.**
- `class: tests`, `severity: nit`
- Two `/wrap-insights` runs within the same minute produce identical truncated timestamps; A8 holds. Cross-machine clock skew can produce out-of-order MAX values. Not a defect — the field is informational — but the doc should acknowledge "clock-monotonic across machines is not guaranteed; multi-machine adopters see this field on whichever machine wrote last." 

**14. Test-fixture assumption: `~/.claude/projects/` accessible during test.**
- `class: tests`, `severity: nit`
- A1, A1.5, and A3 all reference real `~/.claude/projects/` paths or fixtures shaped like them. CI runners (if MonsterFlow ever adds GitHub Actions for tests) will not have this layout. The `compute-persona-value.py` cost-root override is implicit. Adding `--cost-root <dir>` for testability (or env var) is cheap and would let A3's cross-project fixture exercise both halves.

**15. Persona file with non-ASCII or hyphen-only basenames.**
- `class: tests`, `severity: nit`
- Persona-name regex extraction from `personas/<gate>/<name>.md` is mentioned but not specified. Existing personas all use lowercase-hyphen — if a future persona uses underscores, dots, or unicode (unlikely but allowed by filesystem), regex behavior is unstated. Pin the regex literal in the spec or A0 fixture.

**16. `persona-metrics-validator` post-build invocation has no triggering contract.**
- `class: documentation`, `severity: nit`
- §Integration says "invoke after first `/wrap-insights` run that produces `persona-rankings.jsonl`." Not wired into `commands/wrap.md` Phase 1c, not a build-step in any `tests/run-tests.sh` lane. It's a hand-prompt-the-user note. Either spec it as a manual one-time step (with the exact `Agent(...)` invocation in `docs/specs/token-economics/notes.md`) or wire it into `/wrap-insights` Phase 1c as a one-shot conditional on first-emit.

## Verdict

**PASS WITH NOTES** — the spec is implementation-ready; the four Critical Gaps (`--explain` undefined, schema migration unspecified, `<unknown>` bucket contract, window-rollover mechanism) are tightenings around contracts already implied by the design and can be folded inline before `/build` without re-running `/check`.

---

## requirements

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

---

## scope

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

---

## stakeholders

# Stakeholder Analysis Review — token-economics v4.2

## Critical Gaps

- **Persona authors as data subjects are unrepresented.** The spec treats personas as roster entries but a persona has a human author (in MonsterFlow defaults: Justin; in adopter forks: anyone who edits/adds a persona). The dashboard renders "highest/lowest" rankings per persona by name, and the warning banner only addresses *adopters who screenshot*. Nothing addresses *the persona author whose work shows up bottom-3 in someone else's screenshot*. For a public-release repo accepting persona PRs, this is a contributor-ranking surface and the spec doesn't say so. Add: who owns persona-quality narratives, and what's the contributor-facing message when "your persona ranks low on judge-retention."

- **The motivating stakeholder (Pro-tier friend) gets nothing in v1.** Spec opens with "Pro-tier relief comes in v1.1 (BACKLOG #3) immediately after this lands." The person whose pain motivated the work ships measurement only — no cost reduction. There's no commitment in the spec on what "immediately after" means (1 week? 1 month? after ≥10 validated runs — which could be slow on a single user). The "≥10 validated runs" gate could leave the friend on Pro indefinitely if they're not the one accumulating runs. Add an explicit timeline or a fallback (e.g., if 10 runs not reached in 30 days, revisit BACKLOG #3 unblocked).

- **Customer-support / triage path missing.** First adopter question after this ships: "my persona is bottom-3 on every gate — is it broken, or is the metric noise?" There's no documented path from a low score to a diagnosis. The dashboard shows numbers, the wrap-insights text shows top/bottom 3, but no runbook ("low judge-retention with high uniqueness usually means…", "if downstream-survival is null and runs ≥3, check survival.jsonl freshness"). Spec assumes adopters self-interpret; given the ratios are statistically tricky (compression vs survival, machine-local windows, content-hash transients), this is optimistic.

## Important Considerations

- **Non-tty adopters beyond Justin.** M6 added `--confirm-scan-roots` because Justin's tmux pipe-pane defeats the prompt. Other adopters running under CI, cron, `nohup`, or the `/autorun` scheduled-agent path hit the same wall. The stderr message is good, but installing adopters won't see it on first `/wrap-insights` until they trip it. Consider surfacing this in `install.sh` post-install banner or in `commands/wrap.md` itself ("if you run /wrap-insights from a non-interactive context, see…").

- **Linux adopters silently excluded.** Out-of-scope says "Linux support for new scripts (macOS-only)." MonsterFlow's audience isn't documented as macOS-only elsewhere — `os.replace` is cross-platform, the cascade is POSIX, the dashboard is `file://`-loadable everywhere. What specifically is macOS-only? If nothing is, drop the exclusion. If something is (e.g., `~/.claude/projects/` path discovery on Linux Claude Code), name it so Linux adopters know what to fork.

- **Dashboard mental-model shift unaddressed.** Adding a third top-level mode tab ("Persona Insights") changes the dashboard from a single-pane view to a multi-mode tool. Existing dashboard users (who's the population?) get a UI re-org without notice. If the dashboard has any active users beyond Justin, they need a one-line changelog entry. If the population is "Justin only," say so and we can drop this concern.

- **Conflict: privacy strictness vs debuggability.** Counts-only telemetry (Δ4) plus salted finding IDs (Δ3) plus stderr scrubbing (privacy gate 3) means when a real adopter hits a bug ("my row counts look wrong"), they can't share logs with you without the `MONSTERFLOW_DEBUG_PATHS=1` ritual. Consider a `--diagnostic-bundle` flag that produces a redacted-but-shareable artifact deliberately, so support tickets have a path that doesn't require adopters to know about a hidden env var.

- **Persona-metrics-validator subagent owner.** Spec says "invoke `persona-metrics-validator` after first `/wrap-insights` run that produces `persona-rankings.jsonl`." Who is "the invoker"? If this is meant to be automatic, it's not wired. If it's manual, the build instruction needs to say where in the pipeline that invocation lives (post-merge? at /preship? in commands/wrap.md Phase 1c after the compute step?).

- **Conflict: A11 outcome bar vs e12 fresh-install reality.** A11 requires "at least one source row exists" and e12 covers zero-data. But the in-between case — adopter who has run `/spec-review` once, has 1 finding, no `/plan` yet, no `/check` yet — produces a row with `runs_in_window: 1`, `insufficient_sample: true`, all rates rendered "—". Adopter sees a dashboard that looks broken. Banner copy ("No data yet…") doesn't trigger because data does exist; it's just unrenderable. Add a second banner or merge the e12 banner condition to also fire when all rows are insufficient-sample.

## Observations

- **Persona-prompt-author churn signal lost.** Best-effort content-hash reset (A4, e2) is honest about transient pre-edit residue, but if a persona author iterates rapidly during a `/spec` cycle, their score is noise for ~45 invocations. Worth a one-liner in the dashboard tooltip: "score may include pre-edit data for ~45 runs after persona changes."

- **Onboarding stakeholder underserved.** Cascade tier 2 config file is created lazily — adopter must read `docs/specs/token-economics/spec.md` §Project Discovery to know it exists. `install.sh` writing a one-line README at `~/.config/monsterflow/README.md` is mentioned as "out of scope here; opens an issue in onboarding." File the issue in this spec's wake explicitly so it doesn't drop. Onboarding (BACKLOG #2) is named as separate but this is a concrete onboarding-debt item.

- **Multi-machine adopter conflict ack'd but not signposted.** "Cross-machine aggregation is OUT OF SCOPE for v1 — adopters running MonsterFlow on multiple machines see machine-local data on each." Good. Where does this surface to a multi-machine user before they're confused? Suggest: dashboard banner shows the machine hostname and a one-liner ("data is machine-local; other machines maintain separate windows").

- **Notification needs at launch:** existing dashboard users (banner change), persona-PR contributors (new ranking surface), `/wrap-insights` users (new sub-section format), Linux adopters (macOS-only call-out). None of these are currently in a "launch comms" list because there isn't one. For a spec that adds adopter-visible UI surfaces, a 3-bullet "what changes for whom" should sit near the spec's status field.

- **The "never run this window" rendering is a silent contributor-shaming surface.** Dashboard renders deleted personas as strikethrough, "(never run)" personas as a separate row, and bottom-3 rankings name personas explicitly. For a public-release dashboard, all three states tell a story about persona authors. Consider whether "(never run)" should be silenced or surfaced only behind a flag — if a persona is in roster but no one's invoking it, that's roster-design feedback for Justin, not necessarily a public ranking.

## Verdict

**PASS WITH NOTES** — stakeholder coverage is strong on adopter privacy and operator (Justin) ergonomics, but persona authors as a stakeholder class are missing, the motivating Pro-tier user gets no v1 value with no concrete v1.1 timeline, and there's no support runbook for the most likely first adopter question. None block build; all should be addressed in launch comms or a docs follow-up before the public-release sticker goes on.

