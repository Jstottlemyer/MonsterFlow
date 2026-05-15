---
created: 2026-05-14
revised: 2026-05-14 (post-/spec-review iter1, 9 amendments)
constitution: absent (proceeded without; session-roster default)
gate_mode: permissive
pipeline_path: feature
tags: [ux, integration, docs]
confidence:
  scope: 0.98
  ux_flow: 0.95
  data: 0.92
  integration: 0.88
  edge_cases: 0.90
  acceptance: 0.95
predecessor: gate-consolidation-exploration (deferred per Q1; this spec is the cheap-test hypothesis)
---

# pipeline-pacing-and-prefill Spec

## Summary

Ship four small, mechanically-related UX fixes that address the user feedback batch
of 2026-05-14 (input-grammar inconsistency, "feels endless," `/compact` cluelessness,
mobile-builds-that-don't-launch). No gate-count change. Cross-cutting helpers —
banner emitter `scripts/_pipeline_banner.sh` shared across `commands/*.md` and
`scripts/autorun/*.sh`, plus mobile-verify dispatch in `commands/build.md`
Phase 3 — are scope of v0.14. The bundle validates the "consolidation isn't
needed if pacing is legible" hypothesis. If shipping these dissolves the
endless feeling, the larger gate-consolidation work (spec'd in memory
`gate-consolidation-exploration`) stays deferred.

The original Item 4 (tab-prefill affordance) was DROPPED post-/blueprint
spike (2026-05-14): the mechanism the user observed is Claude Code's
built-in prompt-suggestion system, which is already-on and not under
slash-command authoring control. Empty-Enter is harness-blocked. v0.14
instead documents the existing Tab-accept-suggestion pattern in `CLAUDE.md`
as a "pro tip" — no code, just discoverability.

The original Item 6 (launchd plist cleanup) was carved off per /spec-review
B5 to `docs/runbooks/launchd-rebrand-cleanup.md` as a standalone local-only
task.

## Backlog Routing

Unchanged from initial spec. Scanned `BACKLOG.md`; no items in scope.
Adjacent items (`pipeline-autorun-heartbeat-and-restart-loop-detection`,
`pipeline-iterative-resolution-loops`) stay in BACKLOG.

## Scope

**In scope:**

1. **Input grammar normalize** — all approval prompts in `commands/*.md` use
   `a/b/c` + Enter format. Free-text augment after letter selection
   preserved (`b also add logging<Enter>`).
2. **Pipeline progress banners** — every gate emits a start banner before
   work and an end banner after work. Format includes stage-of-total, ETA
   from rankings history, cumulative session cost, work-size-adaptive
   denominator (computed from planned-gate list, not pipeline category),
   step-away marker for waits ≥3min. **Null-guard:** when invoked outside a
   pipeline context (no `spec.md`, no `pipeline_path`), banner emits
   `[pipeline] /build · standalone mode` and proceeds. **Autorun:** when
   `AUTORUN=1` is set, banner emits to stderr (not stdout) prefixed
   `[pipeline]` so verdict-sidecar fence parsers reading stdout are
   unaffected.
3. **`/compact` prompting (two-path)** — end-of-gate banner appends a
   `/compact` suggestion based on context-fill mechanism availability:
   - **Path A** (Claude Code context% probe exists; verified at /blueprint
     pre-flight via `claude-code-guide`): two-tier prompt — soft at >50%,
     "strongly recommended" wording at >75%. Includes impact info
     (estimated savings, time cost, "no work lost").
   - **Path B** (probe absent): suppress the `/compact` line entirely. At
     each end-banner, if cumulative session cost has crossed $5 since the
     last `/compact` or fresh session, emit a single one-liner:
     `[pipeline] 💾 session cost crossed $5 · consider /compact between major work`.
   Sentinel for suppression is spec-scoped at
   `docs/specs/<feature>/.last-compact-suggestion` (not user-global) to
   avoid racing across concurrent worktrees.
4. **CLAUDE.md "pro tip" entry on Claude Code's prompt-suggestion system** —
   `claude-code-guide` spike (2026-05-14) confirmed the TAB-prefill the
   user observed is Claude Code's built-in prompt-suggestion system:
   suggestions appear as grayed-out text after Claude's responses; user
   accepts via Tab or Right-arrow. NOT under slash-command authoring
   control. v0.14 adds one paragraph to `CLAUDE.md` documenting this so
   adopters know the affordance exists and how to disable it
   (`export CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false`). No code changes
   to commands or scripts.
5. **Mobile build+launch verify** — new `~/.claude/skills/mobile-verify/`
   hub-and-spoke skill. `commands/build.md` Phase 3 detects mobile via:
   (i) `*.xcodeproj` OR `*.xcworkspace` in repo root, OR (ii)
   `constitution.md` `stack:` tag includes `mobile`, OR (iii)
   `Package.swift` that explicitly declares an iOS/macOS app product
   (parse the manifest's `.products` for `.executableTarget` with iOS
   platform). **Naked `Package.swift` does NOT trigger detection.**
   Dispatch is wrapped in a fix-loop that splits retry semantics:
   - **Code failures** (compile error, runtime crash on launch) → fix-attempt
     subagent path; up to 3 attempts; halt with summary on 3rd.
   - **Infra failures** (simulator unbootable, xcrun missing, runtime
     mismatch) → reset simulator state (`xcrun simctl erase all` + boot)
     and retry once. If still failing, halt with `INFRA error` (distinct
     from CODE failure) so /build doesn't burn its retry budget on stuck
     simulator state.

**Out of scope:**

- Gate consolidation (`/check` retirement, persona roster merge) — deferred
  per Q1 to validate pacing-fixes-it hypothesis first.
- Auto-fire-on-single-keystroke input grammar — rejected per Q2 in favor of
  letter+Enter (preserves compound input).
- Persistent bottom-bar TUI widget — not possible without a TUI library;
  banners are stderr text instead per Q3.
- Slash-command-authored tab-prefill / empty-Enter-default — DROPPED post-spike
  2026-05-14. No authoring mechanism exists. Claude Code's built-in
  prompt-suggestion system already provides Tab-accept naturally and is
  documented in CLAUDE.md per Item 4.
- `_pipeline_input.sh` empty-Enter parser helper — moot with Item 4 dropped.
- `web-verify`, `cli-verify`, `mcp-verify` spokes — slot in via same
  hub-and-spoke pattern when needed; not part of v0.14.
- **launchd plist cleanup** — carved to `docs/runbooks/launchd-rebrand-cleanup.md`
  per /spec-review B5. Local-only task; runs separately tonight; memory
  `project_monsterflow_rebrand` marked resolved on completion.
- `claude-workflow` compat symlink at `~/Projects/claude-workflow` —
  removal deferred until launchd plists confirmed running on new path for
  one week.

## Approach

**Chosen approach (per Q1):** *Defer gate consolidation, ship UX P0 first.*
Memory `gate-consolidation-exploration` captures the full design pass for
later revisit.

**Alternatives considered:** Full consolidation (1-2 wk) and Lite
consolidation (~2 days) both rejected for cost/risk vs UX-first hypothesis
test. See memory.

## Roster Changes

No specialist additions. `mobile-verify` is a Skill (Hub-and-spoke), not a
Persona — invoked from `/build` Phase 3, not at any review gate.

## UX / User Flow

### Item 1 — Input grammar normalize

**Before** (mixed):
```
Approve to proceed to /blueprint? (1 approve / 2 refine X)        ← auto-fires on 1
Pick work size: (a/b/c/d/e)                                       ← requires Enter
```

**After** (uniform):
```
Approve to proceed to /blueprint? (a approve [default] / b refine X)  ← Enter accepts
Pick work size: (a/b/c/d/e)                                           ← unchanged
```

**Compound-input pattern preserved:** user types `b need to revise the data
section<Enter>` — letter is the choice, free text after is the augment.
Commands parse `^[a-z]\s*(.*)$` as `<choice>` + `<augment>`.

**Files touched:** every `commands/*.md` with approval prompts. ~12
prompt-emission sites.

### Item 2 — Pipeline progress banners

**Start banner** (before each gate begins work, emits to stderr in autorun):
```
[pipeline] Stage 2 of 5 — /spec-review starting · ~6min ETA · ☕ good step-away
```

**End banner** (after each gate completes, emits to stderr in autorun):
```
[pipeline] Stage 2 of 5 ✓ /spec-review done (5m 23s · $0.42 cumulative)
           next: /blueprint · ~3min · 2 gates remaining
```

**Work-size-adaptive denominator computed from planned-gate list:**
- `pipeline_path: feature` standard flow → "Stage X of 5" + "N gates remaining"
- `pipeline_path: small` → "Stage X of 2"
- `pipeline_path: bugfix` → "Stage 1 of 1"
- Gates that get skipped on a given run (e.g., user invokes `/build`
  directly) recompute the denominator at gate-emit time. Source: a
  computed planned-gate list, not just the frontmatter category.

**Null-guard for non-pipeline invocations:** if `/build` is invoked in a
cwd with no `docs/specs/<cwd-or-feature>/spec.md`, banner emits
`[pipeline] /build · standalone mode` and skips the ETA/cumulative-cost
fields. No crash; no `pipeline_path` read.

**Autorun emission:** when `$AUTORUN=1`, banner writes to stderr (not
stdout), prefixed `[pipeline]`. This keeps stdout clean for fence-extractor
post-processors that parse verdict sidecars.

**ETA source:** per-gate medians from `dashboard/data/persona-rankings.jsonl`
if present. Fallback to documented defaults: `/spec ~8min`, `/spec-review
~6min`, `/blueprint ~3min`, `/check ~5min`, `/build varies`. Helper
`scripts/_pipeline_eta.py` computes the ETA at gate-start.

**Cumulative cost:** from `~/.claude/scripts/session-cost.py` running total
(same source `/wrap` Phase 1 uses).

**Step-away marker logic:**
- `☕` when upcoming wait is ≥3min and <6min
- `🌅` when upcoming wait is ≥6min
- No marker for <3min stages

### Item 3 — `/compact` prompting (two-path)

**Mechanism resolution at /blueprint pre-flight:** invoke `claude-code-guide`
subagent to verify whether Claude Code exposes a context-fill probe surface
(env-var, stderr channel, status-line API). Pick exactly one path; do NOT
fall back across paths at runtime.

**Path A — probe exists:**

Soft threshold (>50% context):
```
[pipeline] 💾 Context 55% · /compact recommended before /blueprint
           (saves ~$1.50 on next gate · ~30sec · no work lost — artifacts on disk)
```

Hard threshold (>75% context):
```
[pipeline] 💾 Context 78% · /compact strongly recommended before /build
           (context approaching limit · ~30sec · no work lost)
```

**Path B — probe absent (suppression mode):**

Suppress `/compact` percentage-driven line entirely. Replace with a
cost-boundary one-liner emitted only when cumulative session cost has
crossed $5 since the last `/compact` or fresh session:
```
[pipeline] 💾 session cost crossed $5 · consider /compact between major work
```

**Suppression sentinel:** to prevent banner fatigue from the
percentage-driven path under Path A, write
`docs/specs/<feature>/.last-compact-suggestion` after each emission. Same
context% within the same spec → suppress. This is **spec-scoped, not
user-global**, so concurrent /build runs on different worktrees each emit
independently.

**User-global opt-out:** `~/.claude/.banner-disabled` (intentionally
machine-wide) suppresses ALL banner emission, including the `/compact`
line. This file IS user-global on purpose.

### Item 4 — CLAUDE.md "pro tip" on Claude Code's prompt-suggestion system

Append to `CLAUDE.md` (project-level) one paragraph under a new section
titled `## Tab-accept suggestions`:

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
— they are inferred from Claude's response context. MonsterFlow's pipeline
commands benefit from this automatically when prompts end conversationally
(e.g., questions, "Approve to proceed?" patterns).
```

That's the entire deliverable. No code, no scripts, no commands/*.md
changes for Item 4.

### Item 5 — Mobile build+launch verify (hub-and-spoke)

**Hub:** `commands/build.md` Phase 3 gains a detection + dispatch step.

**Detection (tightened per /spec-review M1):**
1. `*.xcodeproj` OR `*.xcworkspace` present in repo root, OR
2. `docs/specs/constitution.md` exists AND `stack:` tag includes `mobile`, OR
3. `Package.swift` present AND parses to declare an iOS/macOS app product
   (i.e., `.executableTarget` with iOS platform, or `iOSApplication` /
   `Catalyst` product). Naked `Package.swift` (Swift CLI tools, servers,
   libraries) does NOT match.

If detection fires, invoke the `mobile-verify` skill via deterministic
path-based call (not skill-discovery — discovery is for human-facing
affordances; pipeline calls require determinism per Codex CDX-10).

**Retry semantics split (per /spec-review M1):**

Verify result categorized as:
- `PASS` — proceed
- `CODE failure` — compile error, runtime crash on launch, smoke-check
  detected SIGABRT / fatal error / exception. Dispatch fix-attempt
  subagent with verify output. Retry up to 3 times. Halt with summary on
  3rd consecutive code failure.
- `INFRA failure` — simulator unbootable, `xcrun` missing, runtime
  mismatch, no matching destination. Reset simulator state via `xcrun
  simctl erase all && xcrun simctl boot <UDID>` and retry **once**. If
  still INFRA failure, halt with `INFRA error: <reason>`. **Does NOT
  consume the 3-attempt CODE-retry budget.**

**Spoke:** `~/.claude/skills/mobile-verify/SKILL.md` (new):
```yaml
---
name: mobile-verify
description: Use when /build Phase 3 detects an iOS/macOS Swift app project. Runs xcodebuild + simulator launch + crash-log scan; reports PASS / CODE / INFRA with details.
---
```

Skill body steps:
1. Resolve scheme (project CLAUDE.md `## Build` section, else
   `xcodebuild -list` first scheme)
2. Pre-flight: probe `xcrun simctl list devices booted` to detect INFRA
   readiness BEFORE compile (catch missing runtime early)
3. `xcodebuild -scheme <scheme> -destination 'generic/platform=iOS Simulator' build` — fail = CODE
4. Boot simulator if needed: `xcrun simctl boot <auto-select>` — fail = INFRA
5. `xcrun simctl install booted <built-app-path>` — fail = INFRA
6. `xcrun simctl launch --console-pty booted <bundle-id>` with 5sec timeout — fail = INFRA
7. Scan console for `SIGABRT | fatal error | crashed | _NSExceptionHandler` — found = CODE
8. Capture screenshot at `.build-verify/launch.png`
9. Report PASS / CODE: <excerpt> / INFRA: <reason>

**Future spokes** (out of scope): `web-verify` (npm build + curl), `cli-verify`
(compile + --help smoke), `mcp-verify` (server boot + handshake). Same hub
call-site pattern; no changes to hub when adding.

## Data & State

**New files:**
- `scripts/_pipeline_eta.py` — computes per-gate ETA; takes `--gate <name>` + `--feature <slug>`; returns seconds-int
- `scripts/_pipeline_banner.sh` — emits start/end banners; shared sourceable helper called from `scripts/autorun/*.sh` and each `commands/<gate>.md`'s autorun section
- `~/.claude/skills/mobile-verify/SKILL.md` — new spoke skill
- `~/.claude/skills/mobile-verify/scripts/verify.sh` — implementation
- `docs/runbooks/launchd-rebrand-cleanup.md` — standalone runbook (carved off Item 6)

**Modified files:**
- `commands/spec.md`, `spec-review.md`, `blueprint.md`, `check.md`, `build.md`, `wrap.md`, `preship.md`, `flow.md` — input grammar normalize, banner emission, `/compact` line emission (Path A or B). NO `[default]` annotations (Item 4 dropped post-spike).
- `scripts/autorun/spec-review.sh`, `design.sh`, `check.sh`, `build.sh` — banner emission to stderr for autorun paths
- `CLAUDE.md` — append `## Tab-accept suggestions` paragraph (Item 4)
- `VERSION` — bump to `0.14.0`
- `CHANGELOG.md` — `## [0.14.0] - 2026-05-14` entry

**Sentinel files (per /spec-review B4):**
- `docs/specs/<feature>/.last-compact-suggestion` — **spec-scoped**; written by end-banner emitter on Path A to prevent percentage-driven banner fatigue
- `~/.claude/.banner-disabled` — **user-global** opt-out for ALL banner emission (intentional machine-wide override)

**No new schemas, no new JSONL, no new gate metadata.**

## Integration

**Touches but doesn't change:**
- `dashboard/data/persona-rankings.jsonl` — read-only for ETA
- `~/.claude/scripts/session-cost.py` — read-only for cumulative cost
- `docs/specs/<feature>/spec.md` frontmatter `pipeline_path` — read-only for stage denominator
- Existing autorun stage scripts — banner helper is sourceable, doesn't replace existing logic

**Constitution touches:** none. Skill is at `~/.claude/skills/`.

**install.sh touches:** add `mobile-verify` symlink installation step
(one new entry in the skills symlink wave).

## Edge Cases

- **No constitution + no probe match** — `/build` Phase 3 skips
  mobile-verify cleanly; banner falls back to standalone mode (per B3).
- **constitution says mobile but probe says not** — log one-line warning;
  use constitution as authoritative.
- **rankings JSONL empty / missing** — fall back to documented ETA
  defaults; banner still emits.
- **session-cost.py errors out** — emit banner without cost field; never
  crash the gate.
- **Context% probe unavailable AND Path A is configured** —
  `claude-code-guide` returns "no probe surface"; spec falls into Path B
  configuration permanently (don't degrade silently into "no banner").
- **Empty-Enter on a non-default-marked prompt** — re-prompt with the
  options listed; do NOT pick arbitrarily.
- **`xcodebuild` exits non-zero before simulator boot** → CODE failure
  (compile error); fix-attempt subagent path normally.
- **Simulator boot fails** (no simulators installed, runtime mismatch) →
  INFRA failure; reset attempt; if still fails, halt with INFRA error.
- **Concurrent /build across worktrees** — sentinel for compact-suggestion
  is spec-scoped (per B4); each invocation emits independently.
- **User has `~/.claude/.banner-disabled`** — banners suppressed at all
  gate sites; `/compact` line also suppressed.
- **Autorun stage emitting banner to stderr collides with stderr error
  messages** — banner prefix `[pipeline]` is distinctive; verify
  fence-extractor doesn't read stderr (it reads stdout only — confirmed by
  current implementation).

## Acceptance Criteria

**AC1** — every approval prompt in `commands/*.md` uses
`(a/b/c)` + Enter format. Test in `tests/test-input-grammar.sh` scopes the
grep to active prompt-emission lines only (regex
`^.*\?\s*\([a-z]\b.*\)|^.*Approve to proceed`), NOT all markdown text. Zero
matches for `(1/2/3)`, `(yes/no)`, or `(y/n)` patterns in active prompt
emission.

**AC2** — `scripts/_pipeline_banner.sh start <gate> <feature>` emits a single
line matching `^\[pipeline\] Stage \d+ of \d+ — /\S+ starting · ~\d+min ETA( · [☕🌅])?$`
within 100ms.

**AC3** — `scripts/_pipeline_banner.sh end <gate> <feature>` emits a single
line containing `Stage \d+ of \d+ ✓`, `cumulative`, `next:`, and
`gates remaining`. Test in `tests/test-pipeline-banner.sh`.

**AC4** — `scripts/_pipeline_eta.py --gate spec-review --feature foo`
returns integer-seconds; falls back to documented defaults when rankings
JSONL absent. Fallback values exact: spec=480, spec-review=360, blueprint=180,
check=300, build=900.

**AC5 (two-path, per B2)** — `/compact` prompt behavior is exactly one of:
- **Path A:** end-banner emits `/compact` line at >50% (soft) and >75%
  (hard, with "strongly recommended" wording per O2). Test in
  `tests/test-compact-prompt-path-a.sh` with mocked context%.
- **Path B:** end-banner suppresses percentage-driven line entirely. Emits
  `session cost crossed $5` only when cumulative > $5 since last
  /compact-or-fresh-session boundary. Test in
  `tests/test-compact-prompt-path-b.sh`.

Path selection is recorded in `docs/specs/<feature>/.compact-mode`
(`probe` or `suppress`) at /blueprint pre-flight time, based on
`claude-code-guide` consultation.

**AC6** — work-size denominator: `pipeline_path: feature` → `of 5` AND `N
gates remaining` computed from planned-gate list. `small` → `of 2`,
`bugfix` → `of 1`. Test by varying frontmatter and asserting banner
output.

**AC7 (per /blueprint spike 2026-05-14; replaces B1)** — `CLAUDE.md`
contains a `## Tab-accept suggestions` section explaining Claude Code's
built-in prompt-suggestion system + the `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION`
opt-out env-var. Test in `tests/test-claude-md-tab-accept-pro-tip.sh`
greps for the section header + opt-out string.

**AC8 (per M1 + /blueprint R2 mitigation)** — `/build` Phase 3 invokes
`mobile-verify` skill when: (i) `*.xcodeproj` OR `*.xcworkspace` present,
OR (ii) constitution `stack:` includes mobile, OR (iii) `Package.swift`
parses to an iOS/macOS app product. Naked `Package.swift` (no iOS app
product declared) does NOT trigger detection. Test asserts each branch
independently with synthetic fixtures. **AC8b:** when detection returns
false BUT a Swift signal exists (any `.swift` file present OR
`Package.swift` present), `/build` Phase 3 emits a one-line warning:
`[mobile-verify] no app detected; if this should be mobile, set constitution stack: mobile`.
Test asserts the warning fires on swift-signal-without-app fixture.

**AC9** — `mobile-verify` skill produces:
- PASS exit 0 on known-good fixture (synthetic Swift Hello-World app)
- CODE exit 1 with crash-line excerpt on known-bad fixture (deliberately-crashing init)
- INFRA exit 2 with reason on simulator-unavailable fixture
Fixtures live at `tests/fixtures/mobile-verify/{good,bad,infra}/`.

**AC10** — `/build` Phase 3 retries CODE failures up to 3 times via
fix-attempt subagent. Halts after 3rd consecutive CODE failure.
`tests/test-mobile-verify-code-attempts.sh`.

**AC10b (per M1)** — `/build` Phase 3 on INFRA failure resets simulator
state (`xcrun simctl erase all`) and retries ONCE. INFRA retry does NOT
count against the 3-attempt CODE budget. Second INFRA failure halts with
`INFRA error: <reason>`. `tests/test-mobile-verify-infra-attempts.sh`.

**AC11** — Mobile-verify dispatch when constitution absent AND no probe
match results in clean no-op. Test with empty repo.

**~~AC12~~** — *DROPPED per /spec-review B5. launchd cleanup is no longer
in scope; runbook at `docs/runbooks/launchd-rebrand-cleanup.md`.*

**AC13** — `~/.claude/.banner-disabled` opt-out file suppresses all banner
emission AND the `/compact` line. Test asserts zero `[pipeline]` lines in
output when sentinel present.

**AC14** — `VERSION` bumped to `0.14.0`; `CHANGELOG.md` has
`## [0.14.0] - 2026-05-14` section with all five items enumerated.
Tested by `tests/test-changelog-v0.14.0-entry.sh`.

**AC15** — `autorun-shell-reviewer` subagent invoked on
`scripts/autorun/*.sh` modifications BEFORE the commit step. Verified via
`/build` orchestrator log.

**AC16 (per B3)** — `/build` invoked outside a pipeline context (no
`docs/specs/<cwd>/spec.md`, no `pipeline_path` frontmatter accessible)
emits `[pipeline] /build · standalone mode` and proceeds without crash.
No frontmatter read attempted. Test in
`tests/test-banner-standalone-mode.sh` with empty cwd.

**AC17 (per B4)** — Two simultaneous `/build` runs on different worktrees
each emit their own compact-suggestion line independently. Sentinel at
`docs/specs/<feature>/.last-compact-suggestion` does NOT race; user-global
`~/.claude/.banner-disabled` opt-out applies to both as expected. Test in
`tests/test-banner-concurrent-worktrees.sh` simulating two cwd contexts.

**AC18 (per M2)** — When `$AUTORUN=1`, banner emissions go to stderr
(prefix `[pipeline]`), and stdout remains clean for verdict-sidecar fence
parsing. Test in `tests/test-banner-autorun-stderr.sh` asserts no
`[pipeline]` text on stdout and matching lines on stderr.

## Open Questions

**~~OQ1~~** — *RESOLVED twice. First per /spec-review B1: replaced
tab-prefill with empty-Enter-default. Then per /blueprint spike 2026-05-14:
empty-Enter is harness-blocked AND no slash-command tab-prefill authoring
mechanism exists. Item 4 is now a CLAUDE.md documentation entry
explaining Claude Code's built-in (not-MonsterFlow-authored)
prompt-suggestion system. The user's original observation is honored, not
replicated by us.*

**~~OQ2~~** — *RESOLVED per /spec-review B2: two-path AC (A=probe, B=suppress
+ $5-boundary). Path selection at /blueprint pre-flight via
claude-code-guide consultation.*

**~~OQ3~~** — *RESOLVED per /spec-review M2: banners emit to stderr under
$AUTORUN=1. Autorun log readers see them; fence parsers reading stdout
are unaffected.*

**OQ4 (skill discovery, defers to /blueprint) —** `~/.claude/skills/mobile-verify/`
requires Claude Code to discover the skill. Verify discovery is automatic
on skill creation (no install.sh registration step needed) OR confirm the
install.sh skill-symlink wave handles it. /blueprint pre-flight resolves
via grepping current install.sh + observing existing skill behavior.

## Changes from initial spec (revision history)

- 2026-05-14 iter1 → iter2: 9 amendments applied per /spec-review review.md
  - **B1:** Tab-prefill → empty-Enter-default (OQ1 RESOLVED)
  - **B2:** `/compact` two-path (probe vs suppress + $5-boundary) (OQ2 RESOLVED)
  - **B3:** Banner null-guard for non-pipeline /build + AC16
  - **B4:** Compact-suggestion sentinel spec-scoped + AC17
  - **B5:** Item 6 (launchd) carved off to standalone runbook + AC12 dropped
  - **M1:** Mobile detection tightened (drop naked Package.swift) + split CODE/INFRA retries + AC10b
  - **M2:** Banner stderr in autorun + AC18 (OQ3 RESOLVED)
  - **M3:** Summary reframe ("cross-cutting helpers" instead of "no architectural change")
  - **O1-O4:** Denominator from planned-gates-list, "strongly recommended" wording, AC1 grep scope, prompt-emission-only matching
