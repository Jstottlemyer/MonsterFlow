---
created: 2026-05-14
constitution: present (docs/specs/constitution.md — will be re-read at /spec-review)
gate_mode: permissive
pipeline_path: feature
tags: [ux, integration, docs]
confidence:
  scope: 0.95
  ux_flow: 0.95
  data: 0.85
  integration: 0.85
  edge_cases: 0.75
  acceptance: 0.85
predecessor: gate-consolidation-exploration (deferred per Q1; this spec is the cheap-test hypothesis)
---

# pipeline-pacing-and-prefill Spec

## Summary

Ship six small, mechanically-related UX fixes that address the user feedback batch
of 2026-05-14 (input-grammar inconsistency, "feels endless," `/compact` cluelessness,
missing tab-prefill, mobile-builds-that-don't-launch, rebrand-debt launchd plists).
All six are author-time changes to existing prompt-emission sites plus one new
hub-and-spoke skill; no architectural change to the gate pipeline. The bundle
validates the "consolidation isn't needed if pacing is legible" hypothesis. If
shipping these dissolves the endless feeling, the larger gate-consolidation work
(spec'd in memory `gate-consolidation-exploration`) stays deferred.

## Backlog Routing

Scanned `BACKLOG.md` for items overlapping UX P0 scope (grep terms: progress,
compact, tab-prefill, input-grammar, mobile-verify, launchd, pause, step-away,
banner, pacing, endless). Findings:

| Item | Source | Routing | Reason |
|---|---|---|---|
| `pipeline-autorun-heartbeat-and-restart-loop-detection` | BACKLOG.md:153 | **(b) stays** | autorun observer signal, different audience from human-in-loop pacing banners |
| `pipeline-iterative-resolution-loops` | BACKLOG.md:183 | **(b) stays** | already established convention — this spec just applies it inline at Phase 3 for mobile-verify |
| `monsterflow-pipeline-config-rename` | BACKLOG.md:191 | **(b) stays** | unrelated rename initiative |
| `install-sh-backup-uninstall` | BACKLOG.md:241 | **(b) stays** | already shipped as v0.13.0 uninstall-sh MVP |
| All other backlog items | — | **(b) stays** | unrelated to UX scope |

No items routed (a) into this spec, (c) new spec later, or (d) drop.

## Scope

**In scope:**

1. **Input grammar normalize** — all approval prompts in `commands/*.md` use
   `a/b/c` + Enter format. Free-text augment after letter selection preserved
   (e.g., user can type `b also add logging<Enter>`).
2. **Pipeline progress banners** — every gate emits a start banner before work
   and an end banner after work. Format includes stage-of-total, ETA from
   rankings history, cumulative session cost, work-size-adaptive denominator,
   step-away marker for waits ≥3min.
3. **`/compact` prompting** — end-of-gate banner appends a `/compact` suggestion
   line when context% exceeds 50% (soft) or 75% (hard escalation). Includes
   impact info (estimated savings, time cost, "no work lost — artifacts on
   disk" confirmation).
4. **Tab-prefill on binary approvals** — every "approve to proceed" / "ready
   for next stage" gate prefills the default go answer for one-Enter submit.
   Multi-option decisions and refinement prompts do NOT prefill.
5. **Mobile build+launch verify** — new `~/.claude/skills/mobile-verify/`
   hub-and-spoke skill. `commands/build.md` Phase 3 detects mobile via
   `*.xcodeproj` / `Package.swift` / `*.xcworkspace` file probe AND constitution
   `stack:` tag, dispatches to the skill, wraps in 3-attempt fix loop, halts on
   3rd consecutive failure.
6. **launchd plist cleanup** — find and rewrite all
   `~/Library/LaunchAgents/*.plist` referencing `claude-workflow` paths to
   `MonsterFlow`. `launchctl bootout` + `bootstrap` reload. Mark memory
   `project_monsterflow_rebrand` resolved. **Local-machine only; not in repo.**

**Out of scope:**

- Gate consolidation (`/check` retirement, persona roster merge) — deferred
  per Q1 to validate pacing-fixes-it hypothesis first.
- Auto-fire-on-single-keystroke input grammar — rejected per Q2 in favor of
  letter+Enter (preserves compound input).
- Persistent bottom-bar TUI widget — not possible without a TUI library;
  banners are stderr text instead per Q3.
- Tab-prefill on multi-option decisions or refinement prompts — rejected per Q5.
- `web-verify`, `cli-verify`, `mcp-verify` spokes — slot in via same
  hub-and-spoke pattern when needed; not part of v0.14.
- `claude-workflow` compat symlink at `~/Projects/claude-workflow` — removal
  deferred until launchd plists confirmed running on new path for one week.

## Approach

**Chosen approach (per Q1):** *Defer gate consolidation, ship UX P0 first.* The
original 2026-05-14 user feedback was about pacing, prompt inconsistency, and
`/compact` cluelessness — not gate count. Consolidation was our hypothesis for
the root cause; pacing fixes are the literal feedback. Ship pacing, observe
whether "endless" feeling persists, then decide on consolidation as v0.15+ work.

**Alternatives considered:**

- **Option A — Full consolidation now:** 1-2 week project, ~25 tier-1 surface
  items including building `/spec-review`'s first machine-readable verdict
  sidecar. Sized like the v0.9.0 permissiveness work. Rejected for cost +
  risk given user has an interview imminent.
- **Option B — Lite consolidation now:** ~2 days, default `agent_budget: 2`,
  merge duplicate personas in-place across `personas/review/` and
  `personas/check/`. ~30% review-cost cut. Rejected because it doesn't
  address the literal pacing feedback.

The memory `gate-consolidation-exploration` captures the full design pass and
the 7-merged-persona roster decision in case we revisit Option A or B later.

## Roster Changes

No specialist additions needed. Existing personas suffice. The new
`mobile-verify` skill is a Skill, not a Persona — it doesn't dispatch at any
gate, it's invoked from `/build` Phase 3 directly.

## UX / User Flow

### Item 1 — Input grammar normalize

**Before** (mixed):
```
Approve to proceed to /blueprint? (1 approve / 2 refine X)        ← auto-fires on 1
Pick work size: (a/b/c/d/e)                                       ← requires Enter
```

**After** (uniform):
```
Approve to proceed to /blueprint? (a approve / b refine X)        ← always Enter
Pick work size: (a/b/c/d/e)                                       ← unchanged
```

**Compound-input pattern preserved:** user types `b need to revise the data
section<Enter>` — the letter is the choice, free text after is the augment.
Commands parse `^[a-z]\s*(.*)$` as `<choice>` + `<augment>`.

**Files touched:** every `commands/*.md` with approval prompts. Estimated:
`spec.md`, `spec-review.md`, `blueprint.md`, `check.md`, `build.md`, `wrap.md`,
`flow.md`, `preship.md`. ~12 prompt-emission sites total.

### Item 2 — Pipeline progress banners

**Start banner** (before each gate begins work):
```
[pipeline] Stage 2 of 5 — /spec-review starting · ~6min ETA · ☕ good step-away
```

**End banner** (after each gate completes):
```
[pipeline] Stage 2 of 5 ✓ /spec-review done (5m 23s · $0.42 cumulative)
           next: /blueprint · ~3min
```

**Work-size-adaptive denominator:**
- `pipeline_path: feature` → "Stage X of 5" (`/spec`, `/spec-review`,
  `/blueprint`, `/check`, `/build`)
- `pipeline_path: small` → "Stage X of 2" (`/spec`, `/build`)
- `pipeline_path: bugfix` → "Stage 1 of 1" (just `/build`)
- Frontmatter field already exists per `commands/spec.md`; no new state.

**ETA source:** per-gate medians from `dashboard/data/persona-rankings.jsonl`
if present. Fallback to documented defaults if no history: `/spec ~8min`,
`/spec-review ~6min`, `/blueprint ~3min`, `/check ~5min`, `/build varies`.
A new helper `scripts/_pipeline_eta.py` computes the ETA at gate-start.

**Cumulative cost:** from `~/.claude/scripts/session-cost.py` running total
(same source `/wrap` Phase 1 uses).

**Step-away marker logic:**
- `☕` when upcoming wait is ≥3min and <6min
- `🌅` when upcoming wait is ≥6min
- No marker for <3min stages

### Item 3 — `/compact` prompting

**Soft threshold** (50% context): end banner appends
```
[pipeline] 💾 Context 55% · /compact recommended before /blueprint
           (saves ~$1.50 on next gate · ~30sec · no work lost — artifacts on disk)
```

**Hard threshold** (75% context):
```
[pipeline] 💾 Context 78% · /compact REQUIRED before /build — context will overflow next gate
```

**Context% source:** Claude Code harness exposes context fill via env-var or
output channel. **OPEN QUESTION** (see below) — need to verify mechanism with
claude-code-guide before authoring the probe. Fallback: heuristic based on
session-cost.py cumulative spend vs an "approaching wall" threshold (e.g.,
`>$3.00 cumulative` ≈ 50% for typical specs).

**Frequency throttle:** if a `/compact` suggestion fired at the previous
end-banner and context% hasn't dropped since, suppress the next one to avoid
banner fatigue. Sentinel: `~/.claude/.last-compact-suggestion-context-pct`.

### Item 4 — Tab-prefill on binary approvals

**Mechanism — OPEN QUESTION** (see below): need to verify whether Claude Code
supports a structured `<suggested-input>` marker, parses "Approve to proceed?"
text patterns, or uses another path. Sub-spec at `/spec-review` time.

**Prompts that get prefill:**
- `/spec-review` end: "Approve to proceed to /blueprint?" → prefill `approve`
- `/check` end: "Ready for /build?" → prefill `go` (today's `/check`; survives
  until gate-consolidation lands)
- `/build` end: "All waves complete. Run /preship?" → prefill `yes`
- `/wrap` Phase 2 end: "Apply these updates?" → prefill `all`
- `/spec` end: "Proceed to /spec-review?" → prefill `approve`

**Prompts that do NOT get prefill** (multi-option / refinement):
- `/spec` work-size selector
- `/spec` Phase 2 approach proposal
- `/check` NO_GO escape paths
- Persona-roster confirmation
- Any `refine X` follow-up

### Item 5 — Mobile build+launch verify (hub-and-spoke)

**Hub:** `commands/build.md` Phase 3 gains a detection-and-dispatch step:

```
1. Detect platform:
   - constitution.md `stack:` tag includes "mobile" (authoritative), OR
   - file probe: *.xcodeproj OR Package.swift OR *.xcworkspace in repo root
   - (i)+(ii); probe is fallback when constitution absent

2. If mobile detected, invoke Skill: mobile-verify

3. Wrap in 3-attempt fix loop:
   - Attempt 1 fails → dispatch fix-attempt subagent with verify output
   - Attempt 2 fails → repeat
   - Attempt 3 fails → halt /build with summary, exit non-zero
   - Per existing security-N-attempts pattern (memory
     feedback_security_n_attempts_before_block.md)
```

**Spoke:** new `~/.claude/skills/mobile-verify/SKILL.md`:
```yaml
---
name: mobile-verify
description: Use when /build Phase 3 detects an iOS/macOS Swift project. Runs xcodebuild + simulator launch + crash-log scan; reports PASS/FAIL with line excerpts on failure.
---
```

Skill body steps:
1. Resolve scheme: from project CLAUDE.md `## Build` section if present, else
   `xcodebuild -list` first scheme
2. `xcodebuild -scheme <scheme> -destination 'generic/platform=iOS Simulator' build`
3. Boot simulator if needed: `xcrun simctl boot <auto-select-iPhone-15-or-similar>`
4. `xcrun simctl install booted <built-app-path>`
5. `xcrun simctl launch --console-pty booted <bundle-id>` with 5sec timeout
6. Scan console output for `SIGABRT | fatal error | crashed | _NSExceptionHandler` —
   FAIL if found
7. Capture screenshot: `xcrun simctl io booted screenshot .build-verify/launch.png`
8. Report PASS or FAIL with excerpted lines

**Future spokes** (out of scope): `web-verify` (npm build + curl localhost),
`cli-verify` (compile + `--help` smoke), `mcp-verify` (server boot + handshake).
Same hub call-site pattern; no changes to hub when adding.

### Item 6 — launchd plist cleanup

Local-machine cleanup, not in repo. Steps:

1. `find ~/Library/LaunchAgents -name '*.plist' -exec grep -l claude-workflow {} \;`
2. For each match, show user the current `<ProgramArguments>` block
3. Rewrite paths: `s|claude-workflow|MonsterFlow|g` (sed in place with `.bak`)
4. `launchctl bootout gui/$UID <plist-path>` + `launchctl bootstrap gui/$UID <plist-path>` to reload
5. Verify next-run timestamp via `launchctl list | grep monsterflow`
6. Update memory `project_monsterflow_rebrand` → `STATUS: RESOLVED 2026-05-14`

Estimated: 2 plist files (graphify weekly benchmark, vault re-index). ~10 minutes total.

## Data & State

**New files:**
- `scripts/_pipeline_eta.py` — computes per-gate ETA from rankings history; takes `--gate <name>` + `--feature <slug>`, returns seconds-int
- `scripts/_pipeline_banner.sh` — emits start/end banners; shared sourceable helper called from `scripts/autorun/*.sh` and each `commands/<gate>.md`'s autorun section
- `~/.claude/skills/mobile-verify/SKILL.md` — new spoke skill
- `~/.claude/skills/mobile-verify/scripts/verify.sh` — implementation called by the skill

**Modified files:**
- `commands/spec.md`, `spec-review.md`, `blueprint.md`, `check.md`, `build.md`, `wrap.md`, `preship.md`, `flow.md` — input grammar normalize, banner emission, tab-prefill markers, `/compact` line emission
- `scripts/autorun/spec-review.sh`, `design.sh`, `check.sh`, `build.sh` — banner emission for autorun paths
- `VERSION` — bump to `0.14.0`
- `CHANGELOG.md` — `## [0.14.0] - 2026-05-14` entry

**Sentinel files:**
- `~/.claude/.last-compact-suggestion-context-pct` — written by end-banner emitter, prevents repeat-suggestion fatigue
- `~/.claude/.banner-disabled` — opt-out for users who want the old quiet behavior

**No new schemas, no new JSONL, no new gate metadata.**

## Integration

**Touches but doesn't change:**
- `dashboard/data/persona-rankings.jsonl` — read-only for ETA computation
- `~/.claude/scripts/session-cost.py` — read-only for cumulative cost
- `docs/specs/<feature>/spec.md` frontmatter `pipeline_path` — read-only for stage denominator
- Existing autorun stage scripts — banner helper is sourceable, doesn't replace existing logic

**Constitution touches:** none. The skill is at `~/.claude/skills/`, not the project agents dir.

**install.sh touches:** add `mobile-verify` symlink installation step (one new entry in the skills symlink wave).

## Edge Cases

- **No constitution + no probe match** — `/build` Phase 3 skips mobile-verify cleanly, falls through to default verify.
- **constitution says mobile but probe says not** — log a one-line warning; use constitution as authoritative (per Q6 sub-lean).
- **rankings JSONL empty / missing** — fall back to documented ETA defaults; banner still emits (no "?" ETA in output).
- **session-cost.py errors out** — emit banner without cost field; never crash the gate.
- **context% probe unavailable** — fall back to cumulative-cost heuristic; suppress `/compact` line if both unavailable.
- **Tab-prefill mechanism unsupported** — degrade gracefully; emit prompt without marker; user types as before.
- **`xcodebuild` exits non-zero before simulator boot** — fix-attempt subagent sees compile errors; routes through 3-attempt loop normally.
- **Simulator boot fails** (no simulators installed, runtime mismatch) — treat as INFRA error not BUILD error; emit clear message and skip mobile-verify rather than failing the build.
- **`launchctl bootstrap` fails** (already loaded, stale entry) — script catches and runs `bootout` first, retries once, surfaces remaining error.
- **User has `~/.claude/.banner-disabled`** — banners suppressed at all gate sites; `/compact` line also suppressed (it rides the end banner).

## Acceptance Criteria

**AC1** — every approval prompt in `commands/*.md` uses `^([a-z])(?:\s+(.+))?$`
format; grep test in `tests/test-input-grammar.sh` finds zero `(1/2/3)` or
`(yes/no)` patterns.

**AC2** — `scripts/_pipeline_banner.sh start <gate> <feature>` emits a single
line matching `^\[pipeline\] Stage \d+ of \d+ — /\S+ starting · ~\d+min ETA( · [☕🌅])?$`
within 100ms.

**AC3** — `scripts/_pipeline_banner.sh end <gate> <feature>` emits a single
line containing `Stage \d+ of \d+ ✓` and `cumulative` and `next:`. Test
in `tests/test-pipeline-banner.sh`.

**AC4** — `scripts/_pipeline_eta.py --gate spec-review --feature foo` returns
integer-seconds; falls back to documented default when rankings JSONL absent;
fallback values match exactly: spec=480, spec-review=360, blueprint=180,
check=300, build=900.

**AC5** — end-banner emits `/compact` line when context% >50%; escalates wording
at >75%. Suppressed when `.last-compact-suggestion-context-pct` sentinel matches
current context%. Test in `tests/test-compact-prompt.sh` with mocked context%
input.

**AC6** — work-size denominator: `pipeline_path: feature` → "of 5", `small` →
"of 2", `bugfix` → "of 1". Test by varying frontmatter and asserting banner
output.

**AC7** — tab-prefill marker present on exactly 5 prompts listed in Item 4; not
present on any multi-option decision prompt. Test via `grep` for the prefill
marker pattern (TBD pending Open Question resolution).

**AC8** — `/build` Phase 3 invokes `mobile-verify` skill when constitution
`stack:` includes mobile OR when `*.xcodeproj`/`Package.swift`/`*.xcworkspace`
present in repo root. Test by stubbing both detection sources and asserting
skill invocation in dry-run.

**AC9** — `mobile-verify` skill produces PASS with exit 0 on a known-good
fixture (synthetic Swift Hello-World) and FAIL with exit 1 on a known-bad
fixture (deliberately-crashing `init()`). Test fixtures live at
`tests/fixtures/mobile-verify/{good,bad}/`.

**AC10** — `/build` Phase 3 retries fix-attempt up to 3 times on verify FAIL;
halts after 3 with summary. Test in `tests/test-mobile-verify-attempts.sh`
asserting attempt counter and halt verdict.

**AC11** — Mobile-verify dispatch when constitution absent AND no probe match
results in clean no-op (no skill invocation, no error). Test with empty repo.

**AC12** — launchd plists in `~/Library/LaunchAgents/` matching grep
`claude-workflow` are rewritten to `MonsterFlow`; `launchctl list | grep
monsterflow` shows the new entries running. Memory
`project_monsterflow_rebrand` updated with `STATUS: RESOLVED 2026-05-14`.
(Local-only AC; verified by user at apply time, not in CI.)

**AC13** — `~/.claude/.banner-disabled` opt-out file suppresses all banner
emission cleanly. Test asserts zero `[pipeline]` lines in output when sentinel
present.

**AC14** — `VERSION` bumped to `0.14.0`; `CHANGELOG.md` has `## [0.14.0] -
2026-05-14` section with all six items enumerated. Tested by
`tests/test-changelog-v0.14.0-entry.sh`.

**AC15** — autorun-shell-reviewer subagent invoked on `scripts/autorun/*.sh`
modifications BEFORE the commit step (per memory
`feedback_build_subagent_invocations_must_fire`). Verified via `/build`
orchestrator log.

## Open Questions

**OQ1 (mechanism verification) — How does Claude Code's harness handle tab-prefill?**
Three possibilities: (a) structured marker in command output (e.g.,
`<suggested-input>approve</suggested-input>`), (b) pattern recognition on
"Approve to proceed?" text, (c) some other path. Spec assumes (a) but must
verify with `claude-code-guide` subagent during `/spec-review` before any
implementation. If unsupported, degrade gracefully (Item 4 still ships the
prompt text uniformly; only the prefill affordance is conditional).

**OQ2 (mechanism verification) — How is current context% surfaced to a slash command?**
Spec assumes Claude Code exposes context fill via env-var or stderr channel.
Must verify with `claude-code-guide` during `/spec-review`. If unsupported,
fall back to cumulative-cost heuristic (Item 3 still ships; only the trigger
source differs).

**OQ3 (autorun applicability) —** banners are useful for human-in-loop pipeline
runs. For autorun pipeline runs (background agents, no human watching the
stream), are banners noise or useful for log review? Spec assumes useful (logs
are read post-run); confirmed at `/spec-review`.

**OQ4 (skill discovery) —** `~/.claude/skills/mobile-verify/` requires Claude
Code to discover the skill. Verify discovery is automatic on skill creation,
or whether `install.sh` needs an explicit registration step.
