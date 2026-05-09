# Risk Assessment — token-economics v4.2 Plan

## Must Fix

### MF-1 — A1.5 forcing function fires too late in build sequence
- **persona:** risk
- **severity:** major
- **class:** architectural
- **title:** A1.5 disagreement triggers mid-build rewrite, not a Phase 0.5 gate

A1.5 (parent-annotation vs subagent-transcript token agreement) lives in `tests/test-compute-persona-value.sh` (Wave 2, T-TEST-2). On disagreement, the spec says the build fails and `/plan` re-opens Q1, switching `compute-persona-value.py` to subagent-canonical reads. By that point T-CORE-5 (Wave 1, sized "L") has already been written assuming parent-annotation canonical. This isn't a clean re-plan — it's a partial rewrite of the cost-side walker after ~15 Wave 1 tasks complete.

**Fix:** Promote A1.5 to a Phase 0.5 probe (`tests/test-token-source-canonical.sh`) that runs against the existing redacted RedRabbit fixture *before* T-CORE-5 starts. Walls off the Q1 decision behind a 5-minute test; rest of Wave 1 builds against a known-canonical source. Add T-PRE-4 to plan.

### MF-2 — Persona-regex extraction has no quantified match-rate AC
- **persona:** risk
- **severity:** major
- **class:** tests

T-CORE-5 hinges on regex-extracting `personas/<gate>/<name>.md` from `Agent.input.prompt`. T-CORE-6 (R6 mitigation) probes for ≥80% parseability of the *subagent layout*, but the persona-name regex inside the prompt is a *separate* failure mode. If Anthropic ever adjusts the dispatch prompt template (or a future MonsterFlow change introduces a new prompt shape), persona attribution silently degrades to `<unknown>` for all rows — the dashboard renders, the JSONL validates, but every value rate becomes meaningless.

**Fix:** Add A1.6 (already mentioned as Open Q #6 with 5%/100% threshold proposal) as a hard AC, not an open question. Bake into T-CORE-6: assert ≥95% of Agent dispatches whose prompts contain the literal substring `personas/` resolve to a non-`<unknown>` (persona, gate). Below threshold → `compute-persona-value.py` exits non-zero unless `--best-effort`.

### MF-3 — Salt corruption clears all drill-down history with no warn-and-pause path
- **persona:** risk
- **severity:** major
- **class:** architectural

T-CORE-3 says salt validation failure "regenerates the salt atomically AND clears `dashboard/data/persona-rankings.jsonl`." A user with 30 days of accumulated rankings loses every `contributing_finding_ids[]` continuity in a silent recovery (only stderr line). The motivation is honest (old IDs can't be reproduced from new salt), but a `cp ~/.config/monsterflow/finding-id-salt /tmp/oops` mishap is a one-keystroke data-loss event for the rankings JSONL.

**Fix:** Default to **warn-and-refuse**: print stderr `[persona-value] salt file invalid; refusing to clear rankings. Pass --accept-salt-reset to regenerate (drill-down IDs will be discontinuous).` and exit non-zero. Require explicit `--accept-salt-reset` flag for the destructive path. Add to T-TEST-6.

---

## Should Fix

### SF-1 — T-PRE-1 refactor estimate ignores potential callers of `session-cost.py`
- **persona:** risk
- **severity:** minor
- **class:** documentation

If `session-cost.py` is not import-clean (Open Q #2), T-PRE-1 expands to "put CLI under `if __name__ == '__main__':`" with a +30 min estimate. But that script may have other consumers (other tests, hooks, manual `python3 scripts/session-cost.py …` invocations in `commands/wrap.md`). A naïve refactor could break them.

**Fix:** Pre-task: `grep -rn 'session-cost\.py\|session_cost\b' commands/ scripts/ tests/ .claude/` to enumerate callers before refactoring; document required signature stability in T-DOC-1.

### SF-2 — T-TEST-10 wall-time gate soft-fails forever
- **persona:** risk
- **severity:** minor
- **class:** tests

R5 mitigation: ≤5s on this machine, "soft-fail with warning, not hard-fail." After 6 months of accumulated history `compute-persona-value.py` could take 30s and the gate keeps logging warnings nobody reads, making `/wrap-insights` user-hostile.

**Fix:** Hard-fail at 10s ceiling; warn at 5s. Cache short-circuit (currently "deferred to v1.1") becomes a forced v1 task if hard-fail trips on this machine's current `~/.claude/projects/` size.

### SF-3 — `--explain` TTY gate has no test
- **persona:** risk
- **severity:** minor
- **class:** tests

D3 specifies non-TTY refusal (so finding titles never land in piped logs). No T-TEST-* covers the gate. A regression that drops the TTY check exfiltrates plaintext finding titles via tmux pipe-pane logs (project memory: that pipe is on by default).

**Fix:** Add T-TEST-11 `tests/test-explain-tty-gate.sh`: assert non-zero exit + zero stdout + specific stderr message when stdin is non-TTY.

### SF-4 — `validate_project_root()` contract not specified
- **persona:** risk
- **severity:** minor
- **class:** contract

T-CORE-2 references the function; T-TEST-5 lists the cases (symlink escape, `..` segments, non-absolute, sentinel) but no AC pins inputs/outputs. Implementor will guess; reviewer can't tell whether "rejected" means exit-1 vs warn-and-skip vs raise.

**Fix:** Codify in T-DOC-1: function signature, exception type, log shape on each rejection class.

### SF-5 — No v1.0.x in-version corrective-regen path
- **persona:** risk
- **severity:** minor
- **class:** documentation

D6 covers v1 → v1.1 ("`rm` before upgrade") but not v1.0.0 → v1.0.1 if a v1 bug requires a corrective regeneration. T-CORE-11 schema-version guard treats only `schema_version != 1` as cache miss. A v1.0.1 hot-fix that needs to invalidate v1.0.0 outputs has no clean lever.

**Fix:** Add a `regeneration_token` field at top of bundle; bumping it forces full rebuild. Document in T-DOC-1.

### SF-6 — Open Q #5 (persona-author public-ranking posture) deferred to "30 days from now"
- **persona:** risk
- **severity:** minor
- **class:** scope-cuts

The plan's recommendation is to ship T-DOC-2 statement and revisit UI gating after 30 days of data. But this is a *public-release repo*; persona-author exposure is highest-risk on day 1 (everybody who clones runs the dashboard immediately). A bottom-3 list calling out a contributor's persona by name on first run is the highest blast-radius UX outcome of this whole spec.

**Fix:** Add a defensive default: hide bottom-3 unless `runs_in_window ≥ 10` — easy to relax later, hard to retract a screenshot. Bake into T-UI-2 + T-WRAP-1 now.

---

## Notes

- The plan acknowledges 13 risks (R1–R13) and threads each into a specific task — unusually thorough. The 3 Must Fix items above are tightening specific behaviors, not flagging architectural problems.
- D1 (single-bundle dashboard) is the correct call; the two-file refresh race in the original spec was a real footgun.
- D5 (full-rebuild contract) is correct but should be wall-time-benchmarked on a multi-month dataset before ship — T-TEST-10 is the right hook, but 5s on *today's* `~/.claude/projects/` is not the same as 5s on month 6.
- The spec's repeated reference to "best-effort artifact-directory aggregation" + the plan's matching D-list shows good plan↔spec alignment. Codex round-3 review of the plan against the live codebase (per project memory `feedback_codex_catches_plan_vs_reality_drift.md`) is recommended before `/build` consumes this.
- Multi-machine sync ("machine-local v1") is honestly documented, but adopters running tmux session logs across SSH or syncing dotfiles via `chezmoi`/`stow` may not realize the JSONL is gitignored. T-DOC-2 should call this out explicitly.
- Open Q #2 (is `session-cost.py` import-clean today?) is answerable in 2 minutes; running T-PRE-1 *before* `/check` finalizes would convert one open question to a known fact.

---

## Verdict: **PASS WITH NOTES**

Plan is structurally sound, well-decomposed, and honestly enumerates its own risks. Must Fix items tighten three risk-handling behaviors (A1.5 timing, persona-regex match-rate AC, salt-corruption recovery default) without re-opening MVP scope. None blocks `/build`; all are inline edits to the plan + ~3 small task additions.
