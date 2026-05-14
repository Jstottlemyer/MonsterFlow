# Review — pipeline-pacing-and-prefill

**Stage:** /spec-review · iteration 1 · gate_mode: permissive (frontmatter)
**Dispatched:** requirements:opus, gaps:sonnet, scope:sonnet, codex-adversary (budget=3)
**Verdict:** **GO_WITH_FIXES** — 5 blocker findings require inline spec amendments before /blueprint; 1 major needs architectural refinement; 4 minor/nit items can be addressed during /build or carried as followups.

## Overall health: Concerns

The spec's foundation is sound (6 mechanically-related UX items with clear ACs). But four agents converged on three issues that make the spec un-buildable as written:

1. **OQ1 (tab-prefill mechanism) and OQ2 (context% probe)** are not "verify during /blueprint" deferrals — they are blocking design decisions. AC5 and AC7 are non-testable until pinned.
2. **launchd cleanup (Item 6)** is unrelated scope-creep with a partial-failure rollback gap that escalates to architectural under the irreversible-migration carve-out.
3. **Banner emitter assumes pipeline-context** with no null-guard, and shares global sentinels that race across worktree-based concurrent invocations.

These are all fixable inline. None require restructuring the spec's six-item bundle (minus Item 6, which moves to a runbook). The recommended fix set is below.

## Before You Build (5 blockers)

### B1 — Replace tab-prefill with empty-Enter-default semantics (OQ1 RESOLVED)
**Convergence:** requirements / scope / codex-adversary

Tab-prefill assumes a Claude Code structured marker that may not exist. Codex recommends — and I agree — switching to a pattern that works without mechanism verification: every binary approval prompt is phrased so the DEFAULT action is the empty Enter response.

**Pattern:**
```
Approve to proceed to /blueprint? (a approve [default] / b refine X)
```
Enter alone selects `a`. The `[default]` annotation is a documentation hint, not a structural marker. Works regardless of harness support.

**Spec change:** rewrite Item 4. Rename to "Empty-Enter default on binary approvals." Update AC7 to assert the `[default]` annotation is present on the 5 listed prompts. Mark OQ1 RESOLVED.

### B2 — Pin context% mechanism (OQ2 RESOLVED at /blueprint pre-flight)
**Convergence:** requirements / scope / codex-adversary

Cumulative-cost heuristic is unreliable across spec sizes. Codex's recommendation: don't fall back. If the harness probe doesn't exist, *suppress* the `/compact` line; emit a session-cost-based one-liner at major boundaries instead.

**Spec change:** AC5 amended to two-path contract:
- Path A (probe exists, verified at /blueprint pre-flight via claude-code-guide): emit two-tier `/compact` line per current AC.
- Path B (probe absent): suppress `/compact` line; emit a single end-banner suffix when cumulative cost crosses $5 since the last `/compact`-or-fresh-session: `[pipeline] 💾 session cost crossed $5 · consider /compact between major work`.

OQ2 is RESOLVED — both paths are specified; /blueprint picks one based on /blueprint's claude-code-guide consultation.

### B3 — Banner null-guard for non-pipeline invocations
**Source:** gaps

`/build` is invokable outside a pipeline (no spec.md, no `pipeline_path` frontmatter). Banner emitter must not crash or produce malformed output.

**Spec change:** add AC16: "When invoked with no `docs/specs/<cwd>/spec.md`, banner emits `[pipeline] /build · standalone mode` and proceeds. No crash, no `pipeline_path` frontmatter read." Update Item 2 implementation note to describe the fallback.

### B4 — Sentinel namespacing for concurrent worktrees
**Source:** gaps

`~/.claude/.last-compact-suggestion-context-pct` is user-global. Two worktrees running concurrent `/build` mutually suppress each other's compact suggestions.

**Spec change:** sentinel moves to `docs/specs/<feature>/.last-compact-suggestion-context-pct` (spec-scoped, per-feature). `~/.claude/.banner-disabled` STAYS user-global because the opt-out is intentionally machine-wide. Add AC17: "Two simultaneous /build runs on different worktrees each emit their own compact-suggestion line independently."

### B5 — Remove launchd cleanup (Item 6) from spec
**Convergence:** requirements / gaps / scope / codex-adversary (4-way)

Item 6 has zero code overlap with Items 1-5, no rollback contract for partial failure, and muddies v0.14's changelog narrative. Under the irreversible-migration carve-out (silent launchd failure → graphify benchmark stops undetected), it escalates to architectural.

**Spec change:** delete Section "Item 6 — launchd plist cleanup." Remove AC12. Update Summary, Scope (in/out), and Acceptance Criteria sections accordingly. Move the cleanup to a standalone artifact:

- `docs/runbooks/launchd-rebrand-cleanup.md` — one-page MD with the find/grep/sed/launchctl recipe + revert-on-failure path. Run locally tonight, mark `project_monsterflow_rebrand` memory RESOLVED. Out of `pipeline-pacing-and-prefill` entirely.

## Important But Non-Blocking (1 major + 2 majors deferred to /blueprint)

### M1 — Mobile-verify needs detection tightening + split retry semantics
**Convergence:** scope / codex-adversary

Two issues bundled:

(a) Detection on `Package.swift` alone is overbroad — matches Swift CLI tools and servers. Tighten to: `*.xcodeproj` OR `*.xcworkspace` OR `constitution.md` `stack:` includes `mobile`. Drop naked `Package.swift` from the probe. (If a Swift Package Manager mobile project exists, the manifest declares iOS app products; check that explicitly — minor extra logic.)

(b) The 3-attempt loop conflates CODE failures (compile error, crash on launch) with INFRA failures (simulator unbootable, xcrun missing, runtime mismatch). Split: code-failure → existing fix-attempt subagent path; infra-failure → reset simulator state (erase + reboot) + retry once, then halt with infra error (not a CODE failure).

**Spec change:** amend Item 5. Add AC10b for infra-vs-code retry split. AC8 amended to drop naked `Package.swift`. Stays in v0.14 scope; do NOT carve to v0.14.1.

### M2 — Autorun-stage banner behavior (OQ3 RESOLVED)
**Source:** requirements

Autorun pipelines have no human-in-loop, but logs are post-run-read. Banners ARE useful there.

**Spec change:** add AC18: "When `AUTORUN=1` is set in environment, banner emission is on stderr (not stdout), prefixed `[pipeline]`, so verdict-sidecar fence parsers reading stdout are unaffected." OQ3 RESOLVED.

### M3 — Summary's "no architectural change" claim is overstated
**Source:** codex-adversary

Spec introduces a sourceable banner helper across commands + autorun, plus hub-and-spoke dispatch. Both are cross-cutting.

**Spec change:** reframe Summary sentence to: *"No gate-count change; cross-cutting helpers (banner emitter `scripts/_pipeline_banner.sh`, mobile-verify dispatch in build.md Phase 3) are scope of v0.14."* Cosmetic but accurate.

## Observations (non-blocking; minor/nit)

- **O1** (codex-adversary, minor) — Stage denominator should compute from planned-gates-list, not pipeline category default. `next: /blueprint · 2 gates remaining` is more honest than `Stage 3 of 5` when gates can be skipped. Implement at /blueprint design time; not blocking.
- **O2** (codex-adversary, nit) — `/compact REQUIRED` in hard-threshold banner is too strong. Use `strongly recommended` instead.
- **O3** (codex-adversary, minor) — AC1's grep for `(1/2/3)`/`(yes/no)` is too crude; scope to active prompt-emission lines (regex `^.*Approve to proceed` or similar) to avoid matching examples, comments, changelog text.
- **O4** (codex-adversary, observation) — Hub-and-spoke is fine as organizational pattern; `/build` should call the verify script via path-based invocation for determinism (skill-discovery is fine for human-facing affordances).

## Reviewer Verdicts

| Dimension | Verdict | Key Finding |
|---|---|---|
| Requirements | PASS WITH NOTES | OQ1/OQ2 wired into ACs make them non-testable; launchd rollback gap |
| Gaps | FAIL | Banner null-guard, sentinel race, launchd revert path — 3 architectural blockers |
| Scope | PASS WITH NOTES | Mobile-verify disproportionate; launchd unrelated; OQ1/OQ2 unresolved |
| Codex Adversarial | PASS WITH NOTES | Tab-prefill and context% mechanisms likely fictional; launchd is scope creep |

## Conflicts Resolved

- **Mobile-verify in v0.14 vs v0.14.1** — Scope persona suggested carving to v0.14.1; Codex agreed only insofar as detection + retry semantics need fixing. Judge resolution: keep in v0.14 with the M1 amendments (tighten detection, split retries). Carve-to-v0.14.1 reserved as escape if /build hits unexpected xcodebuild trouble.
- **launchd cleanup scope-cuts vs architectural** — Scope tagged scope-cuts; Requirements + Gaps tagged architectural via the irreversible-migration carve-out. Judge resolution: architectural wins (precedence rule), and the resolution is to REMOVE the item from the spec entirely rather than escalate it — both reviewers' intents satisfied.

## Proposed fix set (apply inline; user approval requested)

Five spec amendments + one runbook carve-off:

1. **B1** — Item 4: replace tab-prefill with empty-Enter-default; AC7 amended; OQ1 RESOLVED.
2. **B2** — Item 3: two-path AC5 (probe vs suppress + $5-boundary); OQ2 RESOLVED with branching.
3. **B3** — Item 2: add fallback for non-pipeline invocation; add AC16.
4. **B4** — Item 3: spec-scope the compact-suggestion sentinel; banner-disabled stays global; add AC17.
5. **B5** — DELETE Item 6 + AC12; create `docs/runbooks/launchd-rebrand-cleanup.md`; run separately tonight.
6. **M1** — Item 5: tighten mobile detection; split code/infra retries; AC8 amended; add AC10b.
7. **M2** — Item 2: autorun stderr emission; add AC18; OQ3 RESOLVED.
8. **M3** — Summary: reframe "no architectural change" claim.
9. **O1-O4** — minor/nit text edits to AC1, hard-threshold banner wording, denominator framing.

After amendments, the spec has 18 ACs (was 15: dropped AC12, added AC10b, AC16, AC17, AC18), 1 Open Question (OQ4 — skill-discovery registration, defers cleanly to /blueprint), Item count 5 (was 6).

---

**Approve to apply fix set + proceed to /blueprint? (a approve [default] / b refine X / c hold)**
