# Review V2 — autonomous-shipping-defaults

**Date:** 2026-05-17
**Reviewers:** gaps:opus · requirements:sonnet · scope:sonnet · codex-adversary
**Gate mode:** permissive (frontmatter)
**Overall health:** **Concerns** — V2 closes V1's mechanical gaps cleanly, but Codex surfaced one load-bearing architectural question

---

## Verdict summary

| Reviewer | V1 | V2 | Delta |
|---|---|---|---|
| gaps | PASS WITH NOTES | **PASS WITH NOTES** | 3 of 4 V1 blockers closed; 2 new contract gaps (last-user-message operational def + read mechanism) |
| requirements | **FAIL** | **PASS WITH NOTES** | All 5 V1 blockers closed; 2 new surgical blockers (AC3 regex vs "first-level" contradiction; AC7/AC8 missing required `--gate`) |
| scope | PASS WITH NOTES | **PASS WITH NOTES** | Carves clean; 2 documentation issues (file count 10 vs 12; AC9 "at least one" should be "all four") |
| codex | de facto FAIL | **FAIL** | New architectural concern: last-user-message scan breaks the multi-gate autoship promise in interactive mode |

**Consolidated verdict: PASS_WITH_NOTES with one architectural caveat.** V2 is a big improvement and most findings are surgical, but Codex's #1 raises a real question about whether the autoship UX as described can actually drive the pipeline autonomously.

---

## The Load-Bearing Question (Codex #1)

The spec's happy path describes:
1. User pastes `/goal docs/specs/<slug>/spec.md is shipped via merged PR ...`
2. `/spec-review` fires next, detects trigger in last-user-message, autoship
3. `/blueprint`, `/check`, `/build` each detect trigger in last-user-message, autoship
4. PR opens, halt for admin auth, user authorizes, merge

**What's the actual mechanism for steps 2-3 to fire?** Claude Code skills don't auto-invoke each other. Three real scenarios:

- **Interactive (user typing each gate):** User pastes `/goal`. User then types `/spec-review`. Last-user-message is now `/spec-review`, NOT the /goal paste. Trigger detection fails. Manual mode resumes. ❌ Autoship promise broken.
- **Assistant auto-invokes next gate within one response:** Assistant invokes `/spec-review` → during that invocation, scans context, sees /goal as the user's prior message, treats as AUTORUN, runs gate. Then invokes `/blueprint` within same response. ✓ But the spec doesn't pin this mechanism.
- **Autorun overnight (scripts/autorun/*.sh driven):** External script invokes `claude -p` for each gate. Each invocation's "user message" is whatever the script sent. Script must include the trigger substring in its prompt. ✓ Works if scripts know to do this.

V2's spec describes the detection rule but doesn't pin which mechanism actually advances the pipeline between gates. Codex called this "the autoship state model is underspecified."

**Three resolution paths for V3:**

- **Path A — Narrow scope, ship UX only (recommended for tonight):** V3 drops the "implicit AUTORUN=1 from /goal detection" mechanism entirely. The bundle ships items 1-3 as pure UX: render the /goal line at gates, render suitability indicator, document the pattern in /flow. Gate skills still require `export AUTORUN=1` for autorun semantics. The /goal line is a copy-paste convenience for the *condition*, not a privilege transition. Future spec `autoship-pipeline-driver` (or similar) handles the actual sequential gate-advance mechanism. This makes V3 honest about what it ships, dissolves Codex #1 entirely, and is the cleanest path to a finished, tested feature tonight.
- **Path B — Document the assistant-auto-invoke mechanism, AC-enforce it:** V3 commits to scenario 2 above. Gate skills (when detecting trigger in conversation context, NOT last-user-message-only) auto-invoke the next gate via the Skill tool in the same response. AC adds "skill X invokes skill Y within same turn when autoship is active." More architectural surface but matches the original bundle intent.
- **Path C — State file:** Codex's original recommendation. `/ship-now <slug>` skill (new) writes `.monsterflow/state/active-goal.json` + emits the /goal line. Gate skills check file, not conversation. Cleanest semantics, most code surface.

---

## Before You Build (V2 blockers — only if V3 doesn't carve)

### B1. AC3 regex contradicts "first-level only" rule [contract — requirements]
Parsing rule says `^[[:space:]]*(?:[-*]\s+|\d+\.\s+)` which matches ANY leading whitespace including nested bullets. AC3 fixture 4 ("section with only nested bullets → null") fails under that regex. **Fix:** drop `[[:space:]]*` from the regex OR drop "first-level only" from the prose. Either is a 1-line edit.

### B2. AC7/AC8 examples omit required `--gate` arg [contract — requirements + codex]
The `log-event` CLI signature requires `--spec-path` and `--gate`, but AC7's example call is `log-event --event-type halt --reason ... --stage-at-halt merge` (no --gate). Same for AC8. Per Codex: "exactly the V1 class of problem: ACs that cannot be run as written." **Fix:** add `--gate <value>` to AC7/AC8 example calls. The `--gate` enum also needs to expand to include `build` and `merge` (halt-surface mentions `merge`; helper enum doesn't list it).

### B3. Helper `--gate` enum missing pipeline stages [contract — codex]
Halt-surface contract says halts can happen at `spec-review|blueprint|check|build|merge`, but the helper `--gate` enum is `{spec-exit, spec-review, check-go, check-go-with-fixes}`. A `build` halt can't call `log-event --gate build`. **Fix:** expand `--gate` enum OR split `--gate` (render-surface) from `--stage` (pipeline-stage).

### B4. "Last user message" is not operationally defined [contract — gaps + codex]
The detection rule is imperative prose but the gate-skill scan mechanism is ambiguous. Does it mean: (a) the message that triggered the current skill, (b) the immediately-preceding user message, or (c) the most recent user message of any kind in the session? Each yields different behavior. **Fix:** pin to scenario (b) explicitly OR document the auto-invoke mechanism (Path B above).

### B5. AC9 halt-block anchor disjunction [tests — requirements + scope, convergent]
AC9 row 10 says "at least one of `commands/{spec-review,blueprint,check,build}.md`" but halt-surface §Data & State says "every gate skill MUST emit the block." **Fix:** change AC9 to assert presence in all four files.

---

## Important But Non-Blocking

- **File count error (scope):** Integration header says "10 files total" but lists 12. Fix the header.
- **Render subcommand still multi-responsibility (scope):** the I4 "split into 2 subcommands" claim overstates — render still parses frontmatter + scores + emits + logs. Not blocking; honestly relabel as "split merge-command oracle out; render and logging remain coupled within render."
- **JSONL filename mismatch (gaps):** V1 was `autorun-suitability-outcomes.jsonl`, V2 is `autorun-suitability-events.jsonl`. If any V1 partial run left rows under the old name, /build orphans them. Add migration note OR document as new file (since V1 never shipped).
- **JSONL schema strictness (codex):** "examples, not contract" — extra-keys policy, conditional required fields, `ts` format. Tighten to a strict table.
- **`.gitignore` redundancy (codex):** `dashboard/data/*.jsonl` already covered by existing `.gitignore:12`. Drop the redundant line OR keep as anchor.
- **AC6 universal vs `--no-log` (requirements):** "every invocation appends exactly one row" is false when `--no-log` is set. Scope the AC.
- **Render-event scope (codex):** UX says "each gate writes a render row" but render UI only exists for spec-exit/spec-review/check. Blueprint/build don't render — what do they log? Resolve.
- **AC5 exact-match wording (requirements):** option-line includes variable slug + AC count; "exact-match on first non-empty line" should be "prefix-match."

---

## Observations

- The V1→V2 closure table at the top of the spec is excellent. Reviewers can verify each finding without searching.
- Codex's recommendation table near the end of its review (`--gate`, `--surface`, expanded enums, conditional fields) is implementation-ready — V3 can adopt it wholesale.
- 3-wave shape for /build still holds: helper + tests → skill edits → housekeeping.
- The narrowed scope (3 items, 11 ACs, ~180 LoC helper) is genuinely a clean M when measured by *code* surface. The remaining issues are spec-clarity, not feature scope.

---

## Codex Adversarial View (cumulative V1+V2)

Codex's full output is at `spec-review/raw/codex-adversary.md`. Highlights:

> "V2 is closer than V1, but I would not send it to /blueprint until the autoship state model and helper enums are corrected."

Codex's specific implementation-ready recommendations:
- `--gate`: `spec-exit|spec-review|blueprint|check|build|merge`
- `--surface`: optional `spec-exit|spec-review-option|check-go-option|check-go-with-fixes-option`
- AC7/AC8 include `--gate merge`
- JSONL schema with strict conditional required/optional fields + extra-key policy

Codex's architectural recommendation (path B/C above): "Use `/goal` as the durable authorization signal, not last-user-message as the whole state model. If V2 refuses a state file, define this precisely: 'the trigger check only bootstraps AUTORUN for the current assistant turn; subsequent gate invocations in that same assistant turn inherit an in-memory autoship flag.'"

---

## Reviewer Verdicts Table

| Dimension | Verdict | Key Finding |
|-----------|---------|-------------|
| gaps | PASS WITH NOTES | 3 of 4 V1 blockers closed; 2 new contract gaps on last-user-message scan |
| requirements | PASS WITH NOTES | All 5 V1 blockers closed; AC3 regex contradicts prose; AC7/AC8 missing --gate |
| scope | PASS WITH NOTES | Carves clean; file count mistake; AC9 disjunction; render still multi-responsibility |
| codex | FAIL | Autoship state model underspecified for multi-gate; helper enum missing stages; ACs reference unsupported gate values |

---

## Recommended Path Forward — V3

Given the interview tomorrow, **Path A (narrow scope to UX-only)** is the highest-EV move:
- Drops Codex #1 (the architectural concern) by NOT claiming autoship implies AUTORUN
- V3 ships items 1-3 as pure render UX: /goal-line at gates + suitability indicator + /flow doc
- Existing `export AUTORUN=1` env-var path remains the autorun mechanism (unchanged)
- The /goal copy-paste is a *convenience* for the goal-condition syntax, not a privilege transition
- All remaining V2 findings (B1-B5 + Important) become small inline fixes in V3 — 15-20 min total
- Permissive-mode handles the rest as build-inline followups

**Path B (commit to auto-invoke mechanism)** is the most ambitious but the highest-value-when-shipped. It would actually deliver the "paste one line, walk away" promise. Probably ~2-3 more hours of design + build.

**Path C (state file)** is the most architecturally correct but requires writing a new `/ship-now` skill. Out of scope for tonight.

---

[AUTORUN MODE: If AUTORUN=1 is set, skip this approval prompt.]

Approve to proceed?

- **a)** Refine to V3 with Path A (UX-only, drop AUTORUN-collapse claim) — fast path to ship tonight
- **b)** Refine to V3 with Path B (commit to auto-invoke mechanism) — full original promise, more work
- **c)** Refine to V3 with Path C (state file via /ship-now skill) — cleanest architecture, more work
- **d)** Accept V2 as-is, proceed to /blueprint — permissive mode lets remaining findings flow as build-inline followups (will rediscover at /check)

Reply with `a`, `b`, `c`, or `d` + Enter.
