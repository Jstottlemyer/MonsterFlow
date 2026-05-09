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
