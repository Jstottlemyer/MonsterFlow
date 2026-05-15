---
created: 2026-05-14
revised: 2026-05-14 (post-/check iter1, mobile-verify carved to v0.14.1 + 11 mechanical fixes)
constitution: absent
gate_mode: permissive
pipeline_path: feature
tags: [ux, integration, docs]
confidence:
  scope: 0.98
  ux_flow: 0.95
  data: 0.95
  integration: 0.92
  edge_cases: 0.90
  acceptance: 0.95
predecessor: gate-consolidation-exploration
follow_up: mobile-verify-skill (v0.14.1; carved per /check ck-pacing-005)
---

# pipeline-pacing-and-prefill Spec

## Summary

Ship four small, mechanically-related UX fixes addressing the 2026-05-14 user
feedback batch: input-grammar inconsistency, "feels endless," `/compact`
cluelessness, and a documentation entry on Claude Code's built-in
prompt-suggestion system. No gate-count change. Cross-cutting helpers
(`scripts/_pipeline_banner.sh`, `scripts/_pipeline_eta.py`, a small
`session-cost.py` flag) are scope of v0.14.

The bundle validates the "consolidation isn't needed if pacing is legible"
hypothesis. If shipping these dissolves the endless feeling, the larger
gate-consolidation work (memory `gate-consolidation-exploration`) stays
deferred.

**Three items carved during gate review** (all to standalone artifacts):
- **Item 4 (tab-prefill)** dropped post-/blueprint spike — mechanism unauthored;
  replaced with `CLAUDE.md` documentation paragraph.
- **Item 5 (mobile-verify)** carved to **v0.14.1** post-/check — convergent
  signal (codex C4/C6 + risk SF-4 + scope SD-1) showed disproportionate risk
  + architectural rework needed (skill location, classification, sim reset).
  Will get its own /spec → /build cycle once Items 1-4 ship.
- **Item 6 (launchd cleanup)** carved to `docs/runbooks/launchd-rebrand-cleanup.md`
  per /spec-review.

## Backlog Routing

Routed during /spec; unchanged by gate reviews. BACKLOG additions during T10:
- `mobile-verify-skill` (v0.14.1 candidate — carved from this spec)
- `pipeline-eta-from-timing-data` (v0.15 candidate — per /blueprint OQ7)

## Scope

**In scope (4 items):**

1. **Input grammar normalize** — all approval prompts in `commands/*.md` use
   `a/b/c` + Enter format. Free-text augment after letter selection preserved.
2. **Pipeline progress banners** — every gate emits a start banner before
   work and an end banner after work. Format: stage-of-total + ETA from
   documented defaults (per D4 ship-state) + cumulative session cost +
   work-size-adaptive denominator + step-away marker for waits ≥3min.
   Null-guard for non-pipeline invocations (`standalone mode`). Autorun
   emission to stderr only.
3. **`/compact` prompting (two-path)** — end-of-gate banner appends a
   `/compact` suggestion based on context-fill probe availability:
   - **Path A** (`scripts/statusline-command.sh:42` reads
     `.context_window.used_percentage` from the same JSON stdin Claude Code
     passes to status-line scripts — **a real probe surface**, verified by
     /check Codex): two-tier prompt at >50% (soft) and >75% (strongly
     recommended).
   - **Path B** (probe absent on a given Claude Code version): suppress the
     percentage-driven line; emit a cost-boundary one-liner when cumulative
     session cost has crossed $5 since the last `/compact` or fresh session.
   Path selection recorded in `docs/specs/<feature>/.compact-mode` (bare
   literal `probe` or `suppress`), written by `/blueprint` pre-flight.
   Throttle sentinel at `docs/specs/<feature>/.last-compact-suggestion`
   (JSON; spec-scoped to avoid worktree races).
4. **CLAUDE.md "pro tip" on Claude Code's prompt-suggestion system** — one
   paragraph documenting the built-in Tab/Right-arrow accept-suggestion
   pattern + `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false` opt-out env-var.
   No commands or scripts touched.

**Out of scope (carved for follow-up):**

- **Mobile build+launch verify** — carved to **v0.14.1** as a standalone
  `mobile-verify-skill` spec. Will live as repo-versioned `.claude/skills/mobile-verify/`,
  with narrowed CODE/INFRA classification, targeted UDID erase on infra
  failure, and explicit install.sh integration. NOT in v0.14.
- **launchd plist cleanup** — `docs/runbooks/launchd-rebrand-cleanup.md`.
- **Slash-command-authored tab-prefill / empty-Enter-default** — dropped
  post-spike; Claude Code's built-in system covers the affordance.
- **`_pipeline_input.sh` empty-Enter parser helper** — moot with tab-prefill
  carved.
- **Real-data ETA** — `pipeline-eta-from-timing-data` is a v0.15 candidate
  in BACKLOG.
- **Gate consolidation** (`/check` retirement) — deferred per Q1.

## Approach

Defer gate consolidation, ship UX P0 first. Memory `gate-consolidation-exploration`
captures the design pass for later revisit.

## Roster Changes

None.

## UX / User Flow

### Item 1 — Input grammar normalize

Uniform `(a/b/c)` + Enter across all approval prompts. Free-text augment
preserved (`b also do X<Enter>`). Files: 12 prompt-emission sites across 8
`commands/*.md` (kickoff, spec, spec-review, blueprint, check, build, wrap*,
autorun, flow — verified via inventory pass per /check F1). **NOT** preship
(which is a skill at `~/.claude/skills/preship/`, not a slash command).

### Item 2 — Pipeline progress banners

**Start banner:**
```
[pipeline] Stage 2 of 5 — /spec-review starting · ~6min · ☕ good step-away
```

**End banner:**
```
[pipeline] Stage 2 of 5 ✓ /spec-review done (5m 23s · $0.42 cumulative)
           next: /blueprint · ~3min · 2 gates remaining
```

ETA: **documented defaults only** in v0.14 (per /check F11 wording fix —
no "rankings history" language). Real-data ETA is v0.15 BACKLOG.

Defaults: `/spec ~8min`, `/spec-review ~6min`, `/blueprint ~3min`,
`/check ~5min`, `/build varies`. `_pipeline_eta.py` returns these
hardcoded values.

Denominator: computed from planned-gates-list per `pipeline_path`
frontmatter. Bash 3.2-compat `case` statement.

Step-away markers: `☕` for 3-6min, `🌅` for ≥6min, none for <3min.

**Null-guard:** `[pipeline] /build · standalone mode` when no spec.md /
no frontmatter.

**Autorun:** banner writes to stderr (not stdout) when `$AUTORUN=1`.

### Item 3 — `/compact` prompting (two-path)

`/blueprint` pre-flight (in `commands/blueprint.md`, folded into T6) probes
for `scripts/statusline-command.sh`'s `.context_window.used_percentage`
reachability. Writes `docs/specs/<feature>/.compact-mode` with literal
`probe` or `suppress`.

**Path A — probe configured:**
- >50%: `[pipeline] 💾 Context 55% · /compact recommended before /blueprint (saves ~$1.50 · ~30sec · no work lost — artifacts on disk)`
- >75%: `[pipeline] 💾 Context 78% · /compact strongly recommended before /build`

**Path B — probe absent:**
- Suppress the percentage line. Emit cost-boundary one-liner when cumulative > $5 since last /compact: `[pipeline] 💾 session cost crossed $5 · consider /compact between major work`

**Throttle sentinel:** `docs/specs/<feature>/.last-compact-suggestion`
(JSON: `{"last_context_pct": int, "last_emit_ts": iso8601, "path": "A"|"B"}`).
Spec-scoped. Fail-open on parse error. Both Path A and Path B throttle
through it; `path` field distinguishes A vs B emissions.

**User-global opt-out:** `~/.claude/.banner-disabled` (empty marker)
suppresses ALL banner emission including /compact line.

### Item 4 — CLAUDE.md prompt-suggestion documentation

One paragraph appended to project `CLAUDE.md`:

```markdown
## Tab-accept suggestions (Claude Code built-in)

After Claude responds in an interactive session, Claude Code may show a
grayed-out follow-up suggestion in your input box (based on conversation
context). Press **Tab** or **Right arrow** to accept it, then **Enter** to
submit. Suggestions skip after turn 1, in non-interactive mode, in plan
mode, and when the prompt cache is cold.

To disable globally:
`export CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false`

Or toggle via `/config`. Slash commands cannot author suggestions directly
— they are inferred from Claude's response context.
```

No code, no scripts. Documentation only.

## Data & State

**New files:**
- `scripts/_pipeline_banner.sh` — start/end subcommands; sourceable+executable
- `scripts/_pipeline_eta.py` — fallback-only ETA
- (No new skill in v0.14 — mobile-verify carved)

**Modified files:**
- `commands/*.md` (full inventory: spec.md, spec-review.md, blueprint.md, check.md, build.md, wrap.md, wrap-quick.md, wrap-insights.md, wrap-full.md, kickoff.md, autorun.md, flow.md — minus preship which is not a command)
- `scripts/autorun/spec-review.sh`, `design.sh`, `check.sh`, `build.sh`
- `commands/blueprint.md` — pre-flight `.compact-mode` write step (T6)
- `commands/build.md` — Phase 3 autorun-shell-reviewer hook (per ck-003 F3)
- `~/.claude/scripts/session-cost.py` — `--cumulative-only` flag (no `--session-only` per F13)
- `CLAUDE.md` — append Item 4 paragraph
- `.gitignore` — `docs/specs/*/.compact-mode`, `docs/specs/*/.last-compact-suggestion` (per F8)
- `tests/run-tests.sh` — pin `BASH=/bin/bash` for shell tests touching helpers (per F7)
- `VERSION` — bump to `0.14.0`
- `CHANGELOG.md` — `## [0.14.0]` entry
- `BACKLOG.md` — add `mobile-verify-skill` (v0.14.1) and `pipeline-eta-from-timing-data` (v0.15)

**Sentinel files:**
- `docs/specs/<feature>/.compact-mode` (bare literal, spec-scoped, gitignored)
- `docs/specs/<feature>/.last-compact-suggestion` (JSON, spec-scoped, gitignored)
- `~/.claude/.banner-disabled` (empty marker, user-global)

## Integration

**Touches but doesn't change:**
- `dashboard/data/persona-rankings.jsonl` — read-only access from `_pipeline_eta.py` (only fallback path in v0.14; real-data path lives in v0.15 spec)
- `scripts/statusline-command.sh` — read-only reuse of JSON stdin format for `_pipeline_banner.sh` context-pct read

**Install:** `scripts/_pipeline_banner.sh` + `_pipeline_eta.py` auto-symlinked
by install.sh's existing `scripts/*.sh` glob. No new install.sh entries.

## Edge Cases

- No constitution + no pipeline context — banner falls to `standalone mode`.
- rankings JSONL empty — ETA uses documented defaults; banner still emits.
- session-cost.py errors — banner omits cost field.
- Context% probe path A unavailable on the user's CC version — Path B kicks
  in (suppress + $5 boundary).
- Empty-Enter on banner-disabled state — banners suppressed.
- Concurrent /build across worktrees — sentinels spec-scoped; no race.
- /build invoked from outside any spec dir — standalone mode; sentinel
  writes skipped.
- session-cost.py --cumulative-only flag returns single integer (cents)
  on stdout; exits 0 success / 1 on session-data-absent.
- statusline-command.sh probe surface absent on older CC — /blueprint
  pre-flight writes `.compact-mode: suppress`.

## Acceptance Criteria

(19 total after /check amendments: AC8/8b/9/10/10b/11 dropped with
mobile-verify carve; AC15 amended; AC19-AC23 added for fixes.)

**AC1** — every approval prompt in `commands/*.md` uses `(a/b/c)` + Enter.
Test in `tests/test-input-grammar.sh` scopes grep to active prompt-emission
lines only (regex `^.*\?.*\([a-z](?:[ /]+[a-z])*\b`). Zero matches for
`(1/2/3)`, `(yes/no)`, `(y/n)` in active prompt emission. **AC1b:** the
inventory test `tests/test-prompt-inventory.sh` (per F1) enumerates every
prompt across `commands/*.md` and asserts the inventory matches a locked
manifest in `tests/fixtures/prompt-inventory.txt`.

**AC2** — `scripts/_pipeline_banner.sh start <gate> <feature>` emits a
single line matching the start-banner regex within 100ms.

**AC3** — `scripts/_pipeline_banner.sh end <gate> <feature>` emits a
single line containing `Stage \d+ of \d+ ✓`, `cumulative`, `next:`,
`gates remaining`.

**AC4** — `_pipeline_eta.py` returns documented defaults exact:
spec=480, spec-review=360, blueprint=180, check=300, build=900. No
"rankings history" code path in v0.14 (per F11). Test in
`tests/test-pipeline-eta-fallback.sh` (per F12).

**AC5 (two-path; per F2 amendment)** — `/blueprint` pre-flight probes
`scripts/statusline-command.sh` reachability for `.context_window.used_percentage`
JSON-stdin format. Writes `docs/specs/<feature>/.compact-mode` with literal
`probe` or `suppress`. End-banner reads the file; emits per Path A (>50%/>75%)
or Path B ($5-boundary). Both paths throttle via
`docs/specs/<feature>/.last-compact-suggestion` JSON (`path` field
distinguishes A vs B). Tests: `test-compact-mode-pre-flight.sh`,
`test-compact-prompt-path-a.sh`, `test-compact-prompt-path-b.sh`.

**AC6** — work-size denominator: feature → `of 5` + computed
`N gates remaining` from planned-gates list. small → `of 2`. bugfix → `of 1`.

**AC7** — `CLAUDE.md` contains a `## Tab-accept suggestions` section with
the `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION` opt-out string. Test:
`test-claude-md-tab-accept-pro-tip.sh` greps for both.

**~~AC8, AC8b, AC9, AC10, AC10b, AC11~~** — DROPPED with mobile-verify
carve to v0.14.1.

**AC13** — `~/.claude/.banner-disabled` opt-out suppresses all banner
emission including `/compact` line. Test in
`tests/test-banner-disabled-opt-out.sh` (per F12).

**AC14** — `VERSION` bumped to `0.14.0`; `CHANGELOG.md` has
`## [0.14.0] - 2026-05-14` section with 4 items + 3 carve-out notes
(tab-prefill / mobile-verify / launchd).

**AC15 (per F3 amendment)** — `commands/build.md` Phase 3 contains an
explicit instruction to dispatch `autorun-shell-reviewer` subagent BEFORE
the pre-commit step when `scripts/autorun/*.sh` has uncommitted changes.
3-attempt iterative-resolution loop if subagent flags High findings.
Test: `test-build-md-autorun-shell-reviewer-hook.sh` greps build.md for
the instruction text.

**AC16** — `/build` standalone-mode (no spec.md in cwd) emits
`[pipeline] /build · standalone mode` and proceeds without crash.

**AC17** — Two simultaneous `/build` runs on different worktrees each emit
their own compact-suggestion line independently (sentinels spec-scoped).

**AC18** — Under `$AUTORUN=1`, banner emissions go to stderr; stdout
remains clean for verdict-sidecar fence parsing.

**AC19 (new per F8)** — `.gitignore` contains patterns
`docs/specs/*/.compact-mode` and `docs/specs/*/.last-compact-suggestion`.
Test: `tests/test-install-followups-gitignore.sh` extends to assert these
patterns.

**AC20 (new per F7)** — `tests/run-tests.sh` (or per-test) pins
`BASH=/bin/bash` for any test executing `scripts/_pipeline_banner.sh`.
Banner helper enumerates and forbids: `${arr[-1]}`, `declare -A`,
`local -n`, `mapfile`, `read -a`, `(?<name>...)` named-group regex.
Test: `tests/test-bash32-compat.sh` runs the helper under
`BASH=/bin/bash` and asserts no error.

**AC21 (new per F10)** — `session-cost.py --cumulative-only` outputs
exactly one integer (cents) on stdout; exit 0 on success / 1 on
session-data-absent. No `--session-only` flag (per F13). Test:
`tests/test-session-cost-cumulative-only.sh` asserts both contracts.

**AC22 (new per F12 — test enumeration sweep)** — `T9` enumerates exactly:
`test-pipeline-banner.sh`, `test-prompt-inventory.sh`, `test-input-grammar.sh`,
`test-pipeline-eta-fallback.sh`, `test-compact-mode-pre-flight.sh`,
`test-compact-prompt-path-a.sh`, `test-compact-prompt-path-b.sh`,
`test-banner-standalone-mode.sh`, `test-banner-concurrent-worktrees.sh`,
`test-banner-autorun-stderr.sh`, `test-banner-disabled-opt-out.sh`,
`test-claude-md-tab-accept-pro-tip.sh`, `test-bash32-compat.sh`,
`test-session-cost-cumulative-only.sh`, `test-build-md-autorun-shell-reviewer-hook.sh`,
`test-changelog-v0.14.0-entry.sh`. **16 new test files** (computed, not
hardcoded count).

**AC23** — `BACKLOG.md` gains two entries during T10: `mobile-verify-skill`
(v0.14.1, with entry points: skill location at repo `.claude/skills/`,
narrowed CODE/INFRA classification, targeted UDID erase, install.sh skills
wave) and `pipeline-eta-from-timing-data` (v0.15, with entry points:
session-cost.py stage timing, dashboard/data/gate-timing.jsonl,
_pipeline_eta.py real-data branch).

## Open Questions

None remaining. All four /blueprint OQs resolved during /check:
- OQ4 (skill discovery) — N/A with mobile-verify carved
- OQ5 (input parser location) — moot
- OQ6 (Path B throttling) — yes, same sentinel with `path` field
- OQ7 (v0.15 ETA carve) — RESOLVED via T10 BACKLOG entry

## Changes from initial spec (revision history)

- 2026-05-14 iter1 → iter2 (/spec-review): 9 amendments per `review.md`
- 2026-05-14 iter2 → iter3 (/blueprint Q&A): Item 4 dropped, T5 retired,
  R2 mitigation amended
- 2026-05-14 iter3 → iter4 (/check): mobile-verify carved to v0.14.1, 11
  mechanical fixes applied (F1, F2, F3, F7, F8, F10, F11, F12, F13;
  F4/F6/F9 N/A with carve)
