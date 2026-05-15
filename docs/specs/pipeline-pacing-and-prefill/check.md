# Check — pipeline-pacing-and-prefill

**Stage:** /check · iteration 2 (post-fix) · gate_mode: permissive (frontmatter) · max_recycles: 3
**Dispatched (iter1):** completeness:opus, risk:sonnet, scope-discipline:sonnet, codex-adversary
**Iter1 verdict:** NO_GO (8 architectural blockers); user approved fix-now path with mobile-verify carved to v0.14.1
**Iter2 verdict:** **GO_WITH_FIXES** — all 8 architectural findings resolved inline; 5 non-architectural findings routed to followups.jsonl (4 build-inline + 1 deferred to v0.14.1)

OVERALL_VERDICT: GO_WITH_FIXES

## Reviewer verdicts

| Dimension | Verdict | Key finding |
|---|---|---|
| Completeness | PASS WITH NOTES | AC5 .compact-mode has no write-site task; AC9 exit-code contract not directly tested |
| Risk | PASS WITH NOTES | bash 3.2 enumeration incomplete; --cumulative-only output contract not pinned; simctl erase all too broad |
| Scope Discipline | PASS WITH NOTES | Mobile-verify disproportionate — carve to v0.14.1? Path A unconfirmed mechanism |
| Codex Adversarial | **NO-GO** | T6 already drifting (preship.md nonexistent + missing kickoff/autorun/wrap); /build has no orchestrator hook for autorun-shell-reviewer; skill location outside repo versioning |

## Why NO_GO under permissive

Permissive mode halts on `architectural` and `security` findings. This iteration found **8 architectural** items. None are security. Under the class-precedence rule (`architectural > security > unclassified > contract > tests > documentation > scope-cuts`), architectural halts even when individual reviewer verdicts are PASS_WITH_NOTES.

This is iteration 1 of 3 (`cap_reached: false`). Inline fix path is available.

## Must Fix Before Building (8 blockers)

### ck-pacing-001 — T6 scope inventory wrong; T6+T8 collide on build.md
**class: architectural · severity: blocker** · Source: codex-adversary

- T6 targets `commands/preship.md` which doesn't exist (preship is a skill at `~/.claude/skills/preship/`, not a slash command).
- T6 misses real prompt sites: `kickoff.md`, `autorun.md`, `wrap-quick.md`, `wrap-insights.md`, `wrap-full.md`.
- T6 and T8 both touch `commands/build.md` — same-file collision even with single-agent execution.
- Template-first is insufficient because prompts are semantically different across commands (approval vs wave launch vs kickoff domain-agent choices).

**Inline fix:** Rewrite T6 as **inventory-first pass**: enumerate all active prompt lines across `commands/*.md` (excluding preship.md; including kickoff/autorun/wrap-*). T6 splices grammar normalize into all commands EXCEPT build.md. **Serialize T6 → T8.** T8 owns all `commands/build.md` edits exclusively (grammar + Phase 3 mobile-verify dispatch + autorun-shell-reviewer hook). Add `test-prompt-inventory.sh` enforcing the inventory.

### ck-pacing-002 — Path A /compact has no implementation task; statusline probe surface available
**class: architectural · severity: blocker** · 3-way convergence (codex-C3, completeness-MF1, scope-SD2)

D3 says `/blueprint` pre-flight writes `.compact-mode` via `claude-code-guide` consultation, but no task owns the write. Without a write-site, every fresh feature silently defaults to Path B. Codex also surfaced a concrete probe surface already in MonsterFlow: `scripts/statusline-command.sh:42` reads `.context_window.used_percentage` from JSON stdin.

**Inline fix:** Replace `claude-code-guide` consultation with reuse of the statusline probe. Add explicit `/blueprint` pre-flight step (folded into T6's `commands/blueprint.md` edit) that writes `.compact-mode` based on whether the probe is reachable. `_pipeline_banner.sh` reads `.compact-mode` AND the same JSON stdin format for `context_pct`. Path A becomes "use existing probe"; Path B becomes "suppress when probe absent." AC5 amends to assert the write happens at `/blueprint` pre-flight.

### ck-pacing-003 — AC15/T11 depends on /build orchestrator wiring that doesn't exist
**class: architectural · severity: blocker** · Source: codex-adversary

`commands/build.md` has generic wave dispatch + Phase 3 verification/preship. No hook to invoke `autorun-shell-reviewer` before pre-commit. CLAUDE.md's mention is guidance, not orchestrator wiring. T11 as currently scoped is unenforceable; AC15's "verified via /build orchestrator log" is not testable.

**Inline fix:** Bake autorun-shell-reviewer invocation into T8's `commands/build.md` edits. Add explicit Phase 3 detection: when `scripts/autorun/*.sh` has uncommitted changes, dispatch the subagent BEFORE the commit step. Halt on High findings (per iterative-resolution 3-attempt convention). AC15 amends to grep build.md for the explicit instruction text.

### ck-pacing-004 — mobile-verify skill at ~/.claude/skills/ is outside repo versioning + test path
**class: architectural · severity: major** · Source: codex-adversary

T4 creates files directly under `~/.claude/skills/mobile-verify/`. Outside repo = no git history, no `tests/test-skills.sh` coverage, no `install.sh` integration via existing patterns.

**Inline fix:** Move skill to repo `.claude/skills/mobile-verify/` (or `skills/mobile-verify/` per existing convention — investigate at T4). `install.sh` adds a skills-wave symlink to `~/.claude/skills/`. `tests/test-skills.sh` gains coverage. T4 amends to write the canonical location in-repo.

### ck-pacing-005 — Mobile-verify proportionality — carve to v0.14.1?
**class: architectural · severity: major** · Source: scope-discipline

After two scope cuts (launchd, tab-prefill), mobile-verify is the highest environment-risk piece in Wave 1. T4 + T8 + AC8/8b/9/10/10b/11 + 3 fixtures + 2 test scripts. If xcodebuild trouble appears, it holds the v0.14.0 tag while Items 1-4 sit ready.

**USER DECISION REQUIRED** (see Q-check-1 below).

### ck-pacing-006 — simctl erase all wipes all simulators (destructive vs active sessions)
**class: architectural · severity: major** · Source: risk

D5's `xcrun simctl erase all` is destructive — could hit an active CosmicExplorer simulator session.

**Inline fix:** Use targeted UDID: `xcrun simctl erase <UDID>` for the failing simulator only. Add safety AC asserting non-target simulators are untouched.

### ck-pacing-007 — bash 3.2 enumeration incomplete + test runner doesn't pin BASH
**class: architectural · severity: major** · Source: risk

D1 lists `case`-statement + no negative subscripts, but leaves `local -n`, `mapfile`, `read -a`, `(?<name>...)` named-group regex unaddressed. `tests/run-tests.sh` doesn't pin `BASH=/bin/bash`, so the compliance test runs under Homebrew bash 5 and passes silently.

**Inline fix:** Expand D1 to enumerate the full bash-3.2 incompat surface. Pin `BASH=/bin/bash` at the top of `tests/test-pipeline-banner.sh` (and any test touching the helper).

### ck-pacing-008 — Sentinel files not gitignored
**class: architectural · severity: major** · Source: risk

`.compact-mode` and `.last-compact-suggestion` land in tracked `docs/specs/<feature>/` territory but aren't gitignored. Accidental `git add` commits machine-specific config + leaks the path field (Path A vs B) per memory `feedback_public_repo_data_audit`.

**Inline fix:** Add patterns to `.gitignore`: `docs/specs/*/.compact-mode` and `docs/specs/*/.last-compact-suggestion`. Bake into T10.

## Should Fix (4 items — route to followups under permissive)

### ck-pacing-009 — Mobile CODE/INFRA classification too coarse
**class: contract · severity: major** · Source: codex-adversary

simctl install / entitlement / provisioning / bundle-id / signing failures may surface as simulator-command failures but are project-config CODE failures.

**Fix:** Narrow INFRA to host/tool/runtime/device-availability BEFORE app install. App install/launch failures = CODE unless stderr matches known host/runtime pattern. Add UNKNOWN exit code (3) that halts with classification text.

### ck-pacing-010 — --cumulative-only output contract not pinned
**class: contract · severity: major** · Source: risk

D5's `--cumulative-only --session-only` has no pinned output shape. "Run /wrap unchanged" doesn't catch flag-collision silenced by `|| true` or output drift.

**Fix:** Pin contract in D5: outputs exactly one integer (cents) on stdout, exits 0 on success / 1 on session-data-absent. Add `tests/test-session-cost-cumulative-only.sh`.

### ck-pacing-011 — ETA "from rankings history" wording misleading
**class: contract · severity: minor** · Source: codex-adversary

Spec frames ETA as history-derived in places; D4 ships fallback-only.

**Fix:** Change copy to "typical estimate" or "default estimate." Drop "from rankings history if present" language.

### ck-pacing-012 — 6 ACs not directly tested + T9 off-by-one count
**class: tests · severity: minor** · Source: completeness

Add: `test-pipeline-eta-fallback.sh`, `test-mobile-detection-branches.sh`, `test-mobile-soft-warning.sh`, `test-mobile-no-op-no-match.sh`, `test-banner-disabled-opt-out.sh`. AC15 amends to grep for explicit instruction. T9 count becomes computed, not hardcoded.

### ck-pacing-013 — --session-only flag scope-creep
**class: scope-cuts · severity: minor** · Source: scope-discipline + risk

Only `--cumulative-only` is needed. Drop `--session-only` from D5.

## Class breakdown

| Class | Count |
|---|---|
| architectural | 8 |
| contract | 3 |
| tests | 1 |
| scope-cuts | 1 |
| security | 0 |
| documentation | 0 |
| unclassified | 0 |

## Path forward

This is iteration 1 of 3. The 8 architectural blockers are all addressable inline — none require restructuring the spec. The "fix now" path consolidates 7 mechanical fixes + 1 user decision (mobile-verify carve).

**Proposed inline fix set** (apply on user approval, then re-emit verdict for iteration 2):

| Fix | Source finding | Effort |
|---|---|---|
| F1 | T6 inventory-first rewrite + serialize T6→T8 | ck-001 | M |
| F2 | Path A uses statusline probe; /blueprint pre-flight writes .compact-mode | ck-002 | S |
| F3 | T8 wires autorun-shell-reviewer dispatch in commands/build.md | ck-003 | S |
| F4 | Mobile-verify skill moves to repo .claude/skills/mobile-verify/ | ck-004 | S |
| F5 | **USER DECISION:** carve mobile-verify to v0.14.1 OR keep in v0.14 with all other fixes | ck-005 | strategic |
| F6 | Targeted simctl erase by UDID | ck-006 | XS |
| F7 | Expand bash 3.2 constraints + pin BASH=/bin/bash in tests | ck-007 | XS |
| F8 | Gitignore sentinel files | ck-008 | XS |
| F9 | Narrow INFRA classification + UNKNOWN exit code | ck-009 | S |
| F10 | Pin --cumulative-only output contract + test | ck-010 | XS |
| F11 | ETA wording change | ck-011 | XS |
| F12 | T9 add 5 missing tests + reconcile count | ck-012 | XS |
| F13 | Drop --session-only flag | ck-013 | XS |

After fixes apply: 18 ACs → ~20 ACs (added prompt-inventory + UDID safety + sentinel-gitignore + 5 missing tests; merged some). 10 tasks → 10-11 tasks (T6 split or serialize; T11 folds into T8).

## Question for user (single strategic decision)

The mobile-verify carve (F5) is the only fix that needs your judgment. All other fixes are mechanical and proposed inline.

---

**Q-check-1: Mobile-verify scope decision**

**a) Keep in v0.14** with all 12 other fixes applied. Mobile-verify rides Wave 2 alongside Items 1-4. Risk: xcodebuild/simctl environmental issues could hold the tag.

**b) Carve to v0.14.1.** v0.14.0 ships Items 1-4 (banners, /compact, input grammar, CLAUDE.md doc) only. Mobile-verify gets its own /spec → /build cycle as a follow-up. **Lower risk; faster v0.14.0 ship.**

**c) Keep in v0.14 but move to Wave 3** (after Items 1-4 lock). v0.14 still ships everything, but Items 1-4 hit `main` first; if Wave 3 stalls, v0.14.0 ships them without mobile-verify and mobile-verify becomes v0.14.1.

**My lean: (b).** Two scope cuts already happened this gate. The convergent signal (scope-SD1 + codex-C4 + codex-C6 + risk-SF4) is real architectural debt around mobile-verify — every reviewer who looked at it found a substantial issue. Carving to v0.14.1 lets the pacing-fixes-the-endless-feeling hypothesis (the entire point of v0.14) prove out cleanly. Items 1-4 are <2 days of work; mobile-verify is another 1-2 days minimum once we fix the location + classification + sim-reset issues.

Pick a, b, or c.
