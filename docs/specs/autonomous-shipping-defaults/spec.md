---
tags: [api, data, docs, integration, pipeline, refactor, scalability, security, ux]
tags_provenance:
  baseline: [api, data, integration, scalability, security, ux]
  llm_added: [docs, pipeline, refactor]
  user_overrides: []
gate_mode: permissive
---

# autonomous-shipping-defaults Spec (V3 — Path B: assistant-auto-invoke chained mechanism)

**Created:** 2026-05-16 (V1) · **Revised:** 2026-05-17 (V2 → V3 — same session, after V2 /spec-review)
**Constitution:** none — MonsterFlow personal-tooling repo uses pipeline-default personas
**Confidence:** Scope 0.95 · UX 0.94 · Data 0.95 · Integration 0.94 · Edge 0.92 · Acceptance 0.95 · **avg 0.94**

---

## V2 → V3 revision context

V2 received PASS_WITH_NOTES from gaps/requirements/scope (V1 FAIL→V2 PASS) but FAIL from Codex on one architectural concern: the "last-user-message scan" mechanism doesn't actually drive a multi-gate autoship pipeline when the user types each gate manually. V3 commits to **Path B — assistant-auto-invoke**: gate skills detect autoship-active state from conversation scan, complete their work, and invoke the next gate via the Skill tool as their final action. The pipeline runs end-to-end in one assistant turn.

| ID | Source | Finding | V3 Resolution |
|----|--------|---------|---------------|
| V2-Codex#1 | codex | last-user-message scan breaks multi-gate autoship | **Path B adopted:** conversation-scope scan + assistant chain-invokes next gate via Skill tool. Pipeline genuinely runs end-to-end after one /goal paste. |
| V2-B1 | requirements | AC3 regex contradicts "first-level only" rule | Regex tightened: `^(?:[-*]\s+|\d+\.\s+)` (no leading whitespace) — nested bullets correctly excluded. |
| V2-B2 | requirements + codex | AC7/AC8 examples omit required `--gate` arg | AC7/AC8 fixture calls now include `--gate` explicitly. Helper `--gate` enum expanded (see V2-B3). |
| V2-B3 | codex | Helper `--gate` enum missing build/merge stages | Enum expanded: `{spec-exit, spec-review, blueprint, check-go, check-go-with-fixes, build, merge}`. Render surface distinguished via new `--surface` flag (only meaningful for spec-exit/spec-review/check-go/check-go-with-fixes). |
| V2-B4 | gaps + codex | "Last user message" operationally undefined | Replaced with **full-session-scope scan** for the literal trigger substring. Detection rule pinned (see §Data & State). |
| V2-B5 | requirements + scope | AC9 halt-block anchor disjunction | Changed from "at least one of {4 files}" to **all four gate skill files MUST contain the halt-surface anchor**. |
| V2-I-file-count | scope | Integration header says 10, list has 12 | Header corrected to 12. |
| V2-I-render-multi-resp | scope | Render still does 4 jobs after split | Honestly relabeled: render owns parse+score+emit+log (coupled by design); only merge-command oracle was carved. |
| V2-I-jsonl-filename | gaps | V1 vs V2 filename mismatch | V2 name (`autorun-suitability-events.jsonl`) is canonical; V1 file never shipped (no migration concern). |
| V2-I-schema-strict | codex | Schema is examples not contract | Strict table added with conditional-required + extra-keys policy + UTC-Z format. |
| V2-I-gitignore-redundant | codex | `dashboard/data/*.jsonl` already gitignored | Anchor line kept as explicit AC13 grep target; not redundant in the AC sense. |
| V2-I-ac6-scope | requirements | AC6 universal claim false for --no-log | Scoped: "without --no-log, exactly one row; with --no-log, zero rows." |
| V2-I-render-event-scope | codex | UX says "each gate writes render row" but blueprint/build have no render UI | Clarified: render rows fire only at render-bearing gates (spec-exit, spec-review, check-go, check-go-with-fixes). Blueprint/build/merge stages emit ONLY halt or outcome events when relevant. |
| V2-I-ac5-wording | requirements | "exact-match on first non-empty line" includes variable slug | Changed to prefix-match: assertion is "first non-empty line begins with `- **c)** Ship autonomously`." |

All V2 findings closed. V3 introduces the chain-invoke mechanism cleanly.

---

## Summary

Bundles three backlog items that together make autonomous shipping the natural default for autorun-suitable specs. At `/spec` exit, a HIGH/MED/LOW suitability indicator + copy-pasteable `/goal` line render. The same `/goal` line appears as a **c)** option at `/spec-review` Phase 3 and `/check` GO/GO_WITH_FIXES verdicts. When the literal trigger substring `is shipped via merged PR with verifier reporting` appears in any user message in the current session (and no subsequent `/goal clear`), gate skills:
1. Skip the manual approval prompt (treated as implicit AUTORUN=1 for this gate's run)
2. After completing gate work, invoke the next gate in the pipeline via the Skill tool as their final action

This produces a genuine end-to-end autonomous chain: `/spec-review → /blueprint → /check → /build → PR open → halt for admin auth`. User pastes one line; pipeline drives itself until human-required signal (admin merge).

## Backlog Routing

| Item | Source | V3 Routing |
|------|--------|------------|
| `pipeline-goal-wrap-default` (S) | BACKLOG.md:29 | (a) in scope |
| `flow-goal-autoship-pattern` (XS) | BACKLOG.md:23 | (a) in scope |
| `autorun-suitability-indicator` (S) | BACKLOG.md:19 | (a) in scope |
| `autoship-merge-preserves-branch` | V1 4th item | (c) new spec — `/spec autoship-merge-hygiene` (created in V2) |
| `constitution autorun_suitability:` knob | V1 inclusion | (c) new spec — `/spec autorun-suitability-v2` (created in V2) |

## Scope

**In scope (V3):**
- New helper `scripts/_goal_autoship_render.py` with TWO subcommands:
  - `render --spec-path <p> --gate <g> [--surface <s>] [--no-log]` — emit render block; append `render` event row (unless `--no-log`)
  - `log-event --spec-path <p> --gate <g> --event-type <halt|outcome> --reason <r> [--stage-at-halt <s>] [--pr <n>]` — append event row only
- Skill edits to `commands/spec.md` Phase 4 (suitability indicator + /goal line at spec exit)
- Skill edits to `commands/spec-review.md`, `commands/blueprint.md`, `commands/check.md`, `commands/build.md`:
  - Add autoship-detection block at start of skill (after pre-flight)
  - On detection: emit `[autoship]` acknowledgment, skip manual approval prompt
  - At end of skill: if autoship-active, invoke next-gate Skill tool as final action
- `commands/spec-review.md` Phase 3 + `commands/check.md` GO/GO_WITH_FIXES — add **c) Ship autonomously** option (suppressed when LOW)
- `commands/flow.md` reference card update — locked paragraph wording
- Halt-surface contract — stdout block printed at every halt point (4 fields: feature, stage, reason, next)
- `tests/test-goal-autoship-render.sh` — deterministic shell asserts (~150 LoC, 13 cases)
- Manual smoke playbook S1-S6 (Tier-2 verification)
- `.gitignore` — `_smoke-*` fixture pattern + explicit anchor for events JSONL

**Out of scope (V3):**
- Item 4 (autoship-merge-preserves-branch) — carved to `/spec autoship-merge-hygiene`
- Constitution `autorun_suitability:` extension — folded into `/spec autorun-suitability-v2`
- Deterministic state file (Path C) — superseded by Path B's chain-invoke
- Multi-signal suitability (AC count, LoC, gate-count) — instrumentation-driven v2
- Wait-time metric — sibling spec
- Auto-attempt `--admin` merge — standing memory preserved

## Approach

Path B — gate skills detect autoship-active and chain-invoke the next gate via the Skill tool. Codex-recommended path: "Use /goal as the durable authorization signal." V3 adopts this by treating the user's pasted /goal as session-scope authorization — any gate skill that sees the trigger substring in the session's user messages (and no /goal clear since) is authorized to (a) skip approval, (b) chain to next gate.

The Skill tool is available to the assistant. A gate skill's final action — when autoship-active — is to invoke `Skill(skill="<next-gate>", args="<feature>")`. The chain: `/spec-review → /blueprint → /check → /build`. /build's final action is to open the PR (existing behavior); the chain stops at PR-open and halts for admin auth.

## Roster Changes

No roster changes.

## UX / User Flow

### Happy path — autoship a HIGH-suitability spec

1. User runs `/spec my-new-feature`, completes Q&A, spec written.
2. `/spec` Phase 4 renders:
   ```
   === Spec Written: my-new-feature (11 ACs) ===
   Autorun suitability: HIGH (no security/migration combo, gate_mode: permissive)

   Ship autonomously? Copy + paste this exact line:
     /goal docs/specs/my-new-feature/spec.md is shipped via merged PR with verifier reporting 11/11 ACs PASS

   Or proceed manually: /spec-review my-new-feature
   ```
3. User pastes the `/goal` line. Claude Code sets the goal condition.
4. User types `/spec-review my-new-feature` (or any subsequent message that invokes `/spec-review`).
5. `/spec-review` autoship-detection block fires:
   - Scans session user messages for literal `is shipped via merged PR with verifier reporting`
   - Confirms no subsequent `/goal clear`
   - Emits `[autoship] active goal detected — proceeding autonomously through pipeline`
   - Runs gate work (resolver, persona dispatch, synthesis, write review.md)
   - Final action: `Skill(skill="blueprint", args="my-new-feature")`
6. `/blueprint` runs: same autoship-detection check, gate work, then `Skill(skill="check", args="my-new-feature")`.
7. `/check` runs: gate work, on GO or GO_WITH_FIXES → `Skill(skill="build", args="my-new-feature")`.
8. `/build` runs: waves execute, PR opened, halt-surface block emitted asking for admin auth.
9. Human authorizes admin merge → PR merges → /goal verifier confirms ACs PASS → goal auto-clears → write `outcome` event row.

### `/spec-review` Phase 3 — new option (HIGH or MEDIUM suitability)

```
Approve to proceed to /blueprint?

- **a)** Approve — accept the review and continue
- **b)** Refine — name what to change (`b tighten AC4 wording`)
- **c)** Ship autonomously — paste this exact line:
       /goal docs/specs/my-new-feature/spec.md is shipped via merged PR with verifier reporting 11/11 ACs PASS
       (suitability: HIGH)

Reply with `a`, `b <change>`, or `c` + Enter.
```

(If autoship is already active when this prompt would render, it's skipped — gate auto-proceeds.)

### `/check` GO and GO_WITH_FIXES — same shape

For GO_WITH_FIXES under autoship: the inline-fix followups (`target_phase: build-inline`) are picked up by /build wave 1 per existing permissive-mode behavior. Autoship simply removes the manual gate; fixes still apply.

## Data & State

### Helper subcommands

```
scripts/_goal_autoship_render.py render --spec-path <p> --gate <g> [--surface <s>] [--no-log]
scripts/_goal_autoship_render.py log-event --spec-path <p> --gate <g> --event-type <halt|outcome> --reason <r> [--stage-at-halt <s>] [--pr <n>]
```

**Expanded `--gate` enum (V2-B3 fix):**
```
spec-exit | spec-review | blueprint | check-go | check-go-with-fixes | build | merge
```

**New `--surface` flag (render only, optional):**
```
spec-exit | spec-review-option | check-go-option | check-go-with-fixes-option
```

Only meaningful for gates that have a render UI surface. Helper rejects `--surface` for `blueprint`, `build`, `merge` gates (exit 2).

**Subcommand contracts:**

- `render`: emit render block to stdout, append one `render` event row (unless `--no-log`).
  - Required: `--spec-path`, `--gate`
  - Optional: `--surface`, `--no-log`
- `log-event`: append one event row to JSONL, no stdout output.
  - Required: `--spec-path`, `--gate`, `--event-type`, `--reason`
  - Optional: `--stage-at-halt` (for halt events), `--pr` (for outcome events)
  - `--event-type halt`: requires `--reason` (free-form string)
  - `--event-type outcome`: requires `--reason` ∈ `{shipped, failed, cancelled}`

Exit codes: 0 success, 1 missing/malformed spec.md, 2 invalid argument or enum value.

### Spec slug derivation rule

Slug is the **parent directory name** of the spec.md path. For `docs/specs/my-new-feature/spec.md`, slug is `my-new-feature`. Validated against `^[a-z0-9][a-z0-9-]{0,63}$`. Helper exits 1 on validation failure.

### AC count parsing rule

Count items under `## Acceptance Criteria` heading using regex `^(?:[-*]\s+|\d+\.\s+)` — NO leading whitespace allowed. Matches `- text`, `* text`, or `N. text` at column 0 only. Nested/indented bullets correctly excluded. Checkbox items `- [ ]` and `- [x]` DO count (leading `- ` matches). Parser stops at next `##`-level heading. If section is missing OR returns 0 matches, AC count is `null` (rendered as `?` in /goal line).

### Suitability scoring rule (hardcoded permissive defaults in V3)

```
1. Parse spec frontmatter: tags, gate_mode (default: permissive).
2. If gate_mode == "strict": return LOW.
3. If "security" IN tags AND "migration" IN tags: return MEDIUM.
4. Otherwise: return HIGH.
```

### Autoship trigger detection rule (V3 Path B)

In each gate skill (`commands/{spec-review,blueprint,check,build}.md`), after pre-flight but before gate work begins:

```
1. Scan ALL user messages in the current Claude Code session for the literal substring:
   "is shipped via merged PR with verifier reporting"
   (anchored regex: \bis shipped via merged PR with verifier reporting\b)
2. If found, scan for any subsequent /goal clear invocation since the most recent trigger.
3. If trigger present AND no subsequent /goal clear:
   - autoship-active = true
   - Emit one stdout line: "[autoship] active goal detected — proceeding autonomously through pipeline"
   - Skip the manual approval prompt for this gate
4. Otherwise:
   - autoship-active = false
   - existing AUTORUN=1 env-var check, then existing approval prompt
```

**Why full-session scope (not last-user-message):** the user pastes /goal once. Subsequent gates fire from user inputs like `/spec-review` whose last-user-message is the gate invocation itself — not the /goal. Full-session scope keeps the /goal visible across the chain.

**False-positive defense:** the literal substring is uncommon in normal prose. The "no subsequent /goal clear" rule lets the user opt out mid-flow. The chain-invoke mechanism makes the trigger's effect visible (each gate emits the `[autoship]` acknowledgment).

### Chain-invoke rule (V3 Path B)

When a gate skill completes its work AND autoship-active is true, its final action is:

```
Skill(skill="<next-gate>", args="<feature-slug>")
```

Chain map:
- `/spec-review` final action → `Skill(skill="blueprint", args="<slug>")`
- `/blueprint` final action → `Skill(skill="check", args="<slug>")`
- `/check` final action on GO or GO_WITH_FIXES → `Skill(skill="build", args="<slug>")`
- `/check` final action on NO_GO → STOP, emit halt-surface block (don't chain)
- `/build` final action → existing PR-open path; halt-surface block emitted for admin auth

This propagates the autoship state through the pipeline within a single assistant turn. Each invoked gate re-detects the trigger (idempotent — same substring still present) and continues the chain.

### Halt-surface contract

When any gate skill halts under autoship (NO_GO at /check, state divergence, branch protection, malformed spec, user interrupt, etc.):

1. Emit a visible stdout block:
   ```
   ╔══ autoship halt ══════════════════════════════════════════════╗
   ║ feature: <slug>
   ║ stage:   <spec-review|blueprint|check|build|merge>
   ║ reason:  <free-form reason string>
   ║ next:    <user action required, free-form>
   ╚══════════════════════════════════════════════════════════════════╝
   ```
2. Call `_goal_autoship_render.py log-event --spec-path <p> --gate <stage> --event-type halt --reason <r> --stage-at-halt <s>`.
3. Do NOT chain-invoke the next gate. Wait for user.

The stdout block + the `[AUTOSHIP-HALT]` ASCII marker (separate line for terminal-capture tooling) are the load-bearing user-visible signals.

### JSONL event schema (strict, inlined)

File: `dashboard/data/autorun-suitability-events.jsonl` (gitignored, append-only, `fcntl.flock` advisory lock per write).

**Strict field contract (extra keys allowed; missing required keys = row dropped + stderr warning):**

| Field | Required | Type | Notes |
|-------|----------|------|-------|
| `schema_version` | always | integer | Currently `1` |
| `ts` | always | string | ISO-8601 UTC with `Z` suffix only (e.g., `2026-05-17T03:42:00Z`) |
| `event_type` | always | enum | `render` \| `halt` \| `outcome` |
| `feature` | always | string | Spec slug |
| `gate` | always | enum | Helper `--gate` enum value |
| `predicted_suitability` | when `event_type == render` | enum | `HIGH` \| `MEDIUM` \| `LOW` |
| `tags` | when `event_type == render` | array | Spec frontmatter tags |
| `ac_count` | when `event_type == render` | integer \| null | null on parse failure |
| `gate_mode` | when `event_type == render` | enum | `permissive` \| `strict` |
| `reason` | when `event_type == halt` or `outcome` | string | Free-form for halt; enum `{shipped, failed, cancelled}` for outcome |
| `stage_at_halt` | when `event_type == halt` | enum | Pipeline stage where halt occurred |
| `pr` | optional when `event_type == outcome` | integer \| null | PR number if known |

**Extra-keys policy:** unknown keys are allowed and preserved. Reader tooling MUST tolerate unknown keys (forward-compat).

**Render rows fire ONLY at render-bearing gates** (`spec-exit`, `spec-review`, `check-go`, `check-go-with-fixes`). Blueprint/build/merge stages emit only halt or outcome events.

## Integration

Files touched (V3 — 12 files, V2's count corrected):

- `scripts/_goal_autoship_render.py` — NEW, ~180 LoC
- `commands/spec.md` Phase 4 — add suitability+/goal block
- `commands/spec-review.md` — autoship-detection at start, **c)** option in Phase 3, chain-invoke to blueprint at end
- `commands/blueprint.md` — autoship-detection at start, chain-invoke to check at end
- `commands/check.md` GO + GO_WITH_FIXES — autoship-detection, **c)** option, chain-invoke to build at end (on GO/GO_WITH_FIXES)
- `commands/build.md` — autoship-detection at start (no UI option; chain terminus is PR open)
- `commands/flow.md` — locked paragraph wording (below)
- `tests/test-goal-autoship-render.sh` — NEW, ~180 LoC, 13 cases
- `tests/run-tests.sh` — wire-in (1 LoC)
- `.gitignore` — add `_smoke-*` pattern + explicit `dashboard/data/autorun-suitability-events.jsonl` anchor
- `CHANGELOG.md` — `[Unreleased]` entry
- `BACKLOG.md` — remove the 3 entries this spec consumes (item 4 + constitution already carved in V2)

### Locked flow.md paragraph

Append to `commands/flow.md` (anchor: before `## Reference cards` section if exists, else end-of-file):

```markdown
## Autonomous Shipping (autoship via /goal)

When `/spec` exits with HIGH or MEDIUM suitability, it emits a copy-pasteable
`/goal` line. Paste it as your next message; the next gate skill you invoke
detects the active /goal in session context, skips approval, completes its
work, and chain-invokes the next gate. The pipeline runs end-to-end through
/spec-review → /blueprint → /check → /build → PR open in a single assistant
turn.

Halts surface as a visible stdout block with `feature`, `stage`, `reason`,
and `next` fields. Branch-protection blocks require explicit per-PR `--admin`
authorization from you. `/goal clear` opts out mid-flow.

Suitability: HIGH (no security+migration combo, no strict gate); MEDIUM
(security AND migration both tagged); LOW (gate_mode: strict — autoship
suppressed; /goal line not rendered at any gate).
```

AC9 will grep for the anchor `## Autonomous Shipping (autoship via /goal)`.

## Edge Cases

1. **Spec has no tags** — fallback HIGH with stderr warning. JSONL records `tags: []`.
2. **`## Acceptance Criteria` missing/empty** — `ac_count: null`, /goal line renders `?/?`. User edits manually.
3. **`gate_mode: strict`** — suitability LOW. /goal line NOT rendered at any gate. **c)** option suppressed at /spec-review + /check.
4. **No /goal in session** — autoship-active = false, normal approval prompts fire at every gate.
5. **/goal pasted, then `/goal clear` invoked later** — autoship-detection sees the clear, autoship-active = false from that point.
6. **/goal pasted for spec A, user runs gate against spec B** — autoship trigger substring detected, but slug mismatch. Per V3 D8: detection checks that the slug in the active /goal matches the current gate's `--feature` argument. If mismatch, autoship-active = false; emit `[autoship] /goal active for <other-slug>, current gate is <this-slug> — manual mode` warning.
7. **Branch protection blocks merge** — halt-surface emitted, JSONL halt row, "needs --admin auth" prompt. Never auto-admin.
8. **User interrupt mid-chain** — current gate writes halt event, halt-surface emitted. Subsequent gates do NOT auto-fire because chain-invoke was at the END of each gate, and the interrupted gate didn't reach that step.
9. **Helper Python error** — `/spec` Phase 4 emits existing "Ready for /spec-review" line; indicator block skipped with stderr warning. Non-blocking.
10. **JSONL unwritable** — helper logs to stderr, continues. Instrumentation best-effort.
11. **Trigger substring appears only in Claude reply or tool result (not in user messages)** — detection scans ONLY user messages, not assistant/tool content. False-positive defense.
12. **LOW suitability but user manually pastes /goal anyway** — gate still detects trigger, autoship runs. LOW score is informational; user override respected.
13. **Test invocations** — `--no-log` suppresses JSONL writes. Tests redirect to `TMPDIR/autorun-suitability-events.jsonl` for schema validation.
14. **Skill tool fails mid-chain** (next gate skill not found, transient error) — current gate emits halt-surface block with reason `chain-invoke-failed`, log halt event, stops chain.
15. **Same /goal trigger triggers chain twice** — idempotency: each gate detects the trigger, but each gate runs once per chain (no infinite loop). Chain terminates at /build's PR-open.

## Acceptance Criteria

Two-tier (per Q7).

### Tier 1 — Deterministic shell tests (`tests/test-goal-autoship-render.sh`)

1. **AC1 — Helper exit codes** — `render` exits 0 on valid input, 1 on missing spec.md, 2 on invalid `--gate` or `--surface` enum. `log-event` exits 0 on valid input, 2 on missing required arg (`--reason`, `--gate`) or invalid `--event-type`.

2. **AC2 — Suitability mapping (3 fixtures)** — spec with `tags: [ux]` → HIGH; `tags: [security, migration]` → MEDIUM; `gate_mode: strict` frontmatter → LOW.

3. **AC3 — AC count parser (5 fixtures)** — section with 11 numbered items at column 0 → 11; with 5 `- ` bullets at column 0 → 5; missing section → null; section with only nested/indented bullets (4 spaces leading) → null; section with checkbox items `- [ ]` and `- [x]` mixed → counts each.

4. **AC4 — Render-mode block output (4 anchors)** — output contains: `=== Spec Written:`, `Autorun suitability:`, `Ship autonomously? Copy + paste this exact line:`, `Or proceed manually:`. Per-anchor `grep -q` assertion.

5. **AC5 — Render-mode option-line output** — first non-empty line of output begins with `- **c)** Ship autonomously` (prefix-match, not exact-match — slug + AC count vary).

6. **AC6 — JSONL row schema (with --no-log gating)** — without `--no-log`, every `render` invocation appends exactly one row matching the strict schema (required fields per `event_type`, ISO-8601-Z `ts`). With `--no-log`, zero rows written. Validated by `json.loads()` + per-field type/enum assertions on fixture rows.

7. **AC7 — log-event halt row** — `log-event --spec-path <p> --gate merge --event-type halt --reason branch-protection-block --stage-at-halt merge` writes a row with `event_type: halt`, `gate: merge`, `reason: branch-protection-block`, `stage_at_halt: merge`. No stdout output.

8. **AC8 — log-event outcome row** — `log-event --spec-path <p> --gate merge --event-type outcome --reason shipped --pr 23` writes a row with `event_type: outcome`, `reason: shipped`, `pr: 23`.

9. **AC9 — Skill-prompt anchor table (exhaustive, all gate files)** — grep each anchor in its target file:

    | Anchor | Target File(s) |
    |--------|----------------|
    | `Autorun suitability:` | `commands/spec.md` |
    | `Ship autonomously? Copy + paste this exact line:` | `commands/spec.md` |
    | `- **c)** Ship autonomously` | `commands/spec-review.md`, `commands/check.md` |
    | `[autoship] active goal detected` | `commands/spec-review.md`, `commands/blueprint.md`, `commands/check.md`, `commands/build.md` (ALL FOUR) |
    | `╔══ autoship halt` | `commands/spec-review.md`, `commands/blueprint.md`, `commands/check.md`, `commands/build.md` (ALL FOUR) |
    | `## Autonomous Shipping (autoship via /goal)` | `commands/flow-card.txt` |
    | `Skill(skill="blueprint"` | `commands/spec-review.md` |
    | `Skill(skill="check"` | `commands/blueprint.md` |
    | `Skill(skill="build"` | `commands/check.md` |

    All assertions use `grep -q` exit 0.

10. **AC10 — Orchestrator wiring** — `tests/run-tests.sh` contains `test-goal-autoship-render.sh` in TESTS array.

11. **AC11 — Full test suite green** — `bash tests/run-tests.sh` exits 0.

12. **AC12 — Chain-invoke present in all gate skills** — `commands/spec-review.md` contains `Skill(skill="blueprint"`. `commands/blueprint.md` contains `Skill(skill="check"`. `commands/check.md` contains `Skill(skill="build"` (in both GO and GO_WITH_FIXES branches). `commands/build.md` contains the existing PR-open invocation (no chain forward; terminus). Subsumed by AC9 rows.

13. **AC13 — Gitignore entries** — `.gitignore` contains a line matching `_smoke-*` AND a line matching `dashboard/data/autorun-suitability-events.jsonl` (or the wider `dashboard/data/*.jsonl` pattern).

### Tier 2 — Manual smoke playbook

- **S1** — `/spec _smoke-DELETE-ME` in fresh session, complete Q&A, verify Phase 4 emits HIGH-suitability block with all 4 anchor strings. Cancel before commit.
- **S2** — `/spec-review wiki-write-conventions` against existing spec, verify Phase 3 prompt renders **c)** with correct /goal line. Cancel before reply.
- **S3** — `/check wiki-write-conventions`, verify GO_WITH_FIXES renders **c)**. Cancel before reply.
- **S4** — paste a trigger /goal line in conversation, then run `/spec-review wiki-write-conventions`. Verify `[autoship] active goal detected` acknowledgment + skill chains forward to `/blueprint`. Type `/goal clear` after to halt chain.
- **S5** — manually trigger a halt at any gate; verify halt-surface stdout block appears with 4 required fields + `[AUTOSHIP-HALT]` marker.
- **S6** — paste /goal for one slug, run gate against a different slug; verify `[autoship] /goal active for <other-slug>` warning + manual mode for current gate.

## Self-Learning Loop (read-only design intent for v2)

The `autorun-suitability-events.jsonl` instrumentation feeds future evidence-based heuristic refinement. After ~20+ specs through the indicator, a `/spec autorun-suitability-v2` can analyze per-tag ship-rate, per-stage halt distribution, per-project drift.

**Per scope reviewer:** this section is design intent for v2 — /build should NOT build analysis tooling in this spec.

## Open Questions

None remaining. All V2 findings folded. avg confidence 0.94.

## Risks

- **R1 (medium):** Skill-tool-from-within-Skill semantics are not pinned in this codebase. Chain-invoke may have edge cases (token-budget on long chains, skill-tool failures, conversation-context handling). Mitigation: AC12 verifies static presence of chain calls; S4 verifies dynamic invocation; if dynamic test reveals issues at /build, document and fall back to documenting auto-invoke as a known-limitation.

- **R2 (low):** Full-session-scope LLM scan could surface stale /goal from earlier session work. Mitigation: `/goal clear` opts out; slug-match check (edge case 6) prevents cross-feature triggering.

- **R3 (low):** JSONL write contention if multiple gate skills fire concurrently (autorun parallel builds). Mitigation: `fcntl.flock`.

- **R4 (very low):** halt-surface stdout block missed by tooling capturing terminal output. Mitigation: also emit `[AUTOSHIP-HALT]` ASCII marker.

- **R5 (medium, new in V3):** Chain-invoke could create a very long single assistant turn (all 4 gates + waves + PR open). Token-budget exhaustion risk on large specs. Mitigation: each gate skill is independently bounded (resolver caps personas, individual subagents have their own context). If a single-turn chain exhausts budget, the chain breaks mid-stream — fallback is for user to re-paste /goal and resume from the next gate manually. Document in /flow.
