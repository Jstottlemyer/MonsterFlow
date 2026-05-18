---
tags: [api, data, docs, integration, pipeline, refactor, scalability, security, ux]
tags_provenance:
  baseline: [api, data, integration, scalability, security, ux]
  llm_added: [docs, pipeline, refactor]
  user_overrides: []
gate_mode: permissive
---

# autonomous-shipping-defaults Spec (V2 — post-spec-review revision)

**Created:** 2026-05-16 (V1) · **Revised:** 2026-05-17 (V2 — same session, after /spec-review FAIL)
**Constitution:** none — MonsterFlow personal-tooling repo uses pipeline-default personas
**Confidence:** Scope 0.95 · UX 0.94 · Data 0.94 · Integration 0.94 · Edge 0.92 · Acceptance 0.95 · **avg 0.94**

---

## V1 → V2 revision context

The plan went through `/spec-review` with 3 reviewers + Codex. Verdicts: gaps PASS WITH NOTES, scope PASS WITH NOTES, requirements FAIL, Codex de facto FAIL. 7 blockers + 8 important findings — all folded inline below.

| ID | Source | Finding | Resolution |
|----|--------|---------|------------|
| B1 | scope + codex (convergent) | LLM-scan /goal detection is fragile across compacted contexts; quoted spec content could trigger | Narrowed scan to "literal trigger substring in the most-recent user message only." Security framing dialed back — single-user repo, narrow surface; narrowing reduces false-positives on quoted content. |
| B2 | requirements + scope + codex | AC8 references non-existent `--gate manual-merge` value | Item 4 (autoship-merge-preserves-branch) **carved to BACKLOG** as `/spec autoship-merge-hygiene`. AC8 removed. |
| B3 | requirements + codex | AC9 references non-existent `--event/--reason` CLI flags | Helper CLI now has `log-event` subcommand; AC9 rewritten against it. |
| B4 | requirements | AC6 schema content unspecified | Schema content inlined as normative spec text below (§Data & State). |
| B5 | requirements | AC4 grep pattern unspecified | AC4 now lists 4 exact anchor strings. |
| B6 | gaps + requirements | flow.md wording unspecified | Locked paragraph wording inlined below (§Integration). |
| B7 | requirements + scope | AC10 anchor strings not enumerated | AC10 now contains exhaustive anchor-string table. |
| I1 | gaps + codex | Post-compact /goal recovery | Dissolves via B1 narrowing (last-user-message only — compaction can't move that message). |
| I2 | gaps | Halt-needs-human surface beyond JSONL unspecified | Explicit stdout contract added (§Data & State "Halt-surface contract"). |
| I3 | scope | Bundle is L, not M | Carved items 4 + constitution → clean M with 11 ACs. |
| I4 | codex | Helper does 5 jobs | Split CLI into 2 subcommands: `render` and `log-event`. Merge-command oracle responsibility removed (item 4 carved). |
| I5 | codex | JSONL pollution from every render | Renamed `autorun-suitability-events.jsonl` with `event_type: render \| outcome \| halt` discriminator. Render writes are best-effort, opt-out via `--no-log` for test mode. |
| I6 | gaps | Constitution migration path | Dissolves (constitution extension carved). |
| I7 | codex | AC count parsing semantics | Locked rule below (§Data & State "AC count parsing"). |
| I8 | requirements | Constitution-path flag missing from CLI | Dissolves (constitution extension carved). |

Other Important findings folded: spec slug derivation pinned (§Data & State); LOW rendering downstream gates resolved (suppress option-c everywhere when LOW); GO_WITH_FIXES autoship semantics clarified; `shipped via merged PR` substring tightened to anchored regex; smoke-fixture isolation (`_smoke-*` in `.gitignore`); JSONL atomic-append via `fcntl.flock`.

---

## Summary

Bundles three backlog items that together make autonomous shipping the natural default for autorun-suitable specs rather than a power-user incantation. At `/spec` exit, an autorun-suitability indicator (HIGH/MED/LOW) and a copy-pasteable `/goal` line render automatically. The same `/goal` line surfaces as a 3rd option at `/spec-review` Phase 3 approval and `/check` GO verdict. Gate skills detect the literal `/goal docs/specs/<slug>/spec.md is shipped via merged PR with verifier reporting <N>/<N> ACs PASS` substring in the **most-recent user message** and treat it as implicit `AUTORUN=1` (single user gesture, no env-var step).

## Backlog Routing

| Item | Source | V2 Routing |
|------|--------|------------|
| `pipeline-goal-wrap-default` (S) | BACKLOG.md:29 | (a) in scope |
| `flow-goal-autoship-pattern` (XS) | BACKLOG.md:23 | (a) in scope |
| `autorun-suitability-indicator` (S) | BACKLOG.md:19 | (a) in scope |
| `autoship-merge-preserves-branch` | V1 4th item | **(c) new spec** — `/spec autoship-merge-hygiene` follow-up (per scope + codex carve) |
| `constitution autorun_suitability:` knob | V1 inclusion | **(c) new spec** — fold into future `/spec autorun-suitability-v2` after instrumentation has data |
| Others | unchanged | unchanged from V1 |

## Scope

**In scope (V2):**
- New helper `scripts/_goal_autoship_render.py` with TWO subcommands:
  - `render --spec-path <p> --gate <g> --render-mode <m> [--no-log]` — emit render block, append render event row (unless `--no-log`)
  - `log-event --spec-path <p> --gate <g> --event-type <halt|outcome> --reason <r> [--stage-at-halt <s>] [--pr <n>]` — append event row only, no stdout render
- Skill edits to `commands/spec.md` Phase 4 (suitability indicator + /goal line at spec exit)
- Skill edits to `commands/spec-review.md` Phase 3 (add **c) Ship autonomously** option to approval prompt, suppressed when LOW)
- Skill edits to `commands/check.md` GO and GO_WITH_FIXES verdict blocks (add **c) Ship autonomously**, suppressed when LOW)
- Gate-skill detection of autoship trigger substring in last-user-message — applies to `commands/spec-review.md`, `commands/blueprint.md`, `commands/check.md`, `commands/build.md` (4 skills)
- `commands/flow.md` reference card update — locked paragraph wording (§Integration B6)
- Halt-surface contract — stdout marker block printed at every halt point (§Data & State)
- `tests/test-goal-autoship-render.sh` — deterministic shell asserts (~150 LoC, 11 cases)
- Manual smoke playbook S1-S5 (Tier-2 verification)
- `.gitignore` update — `_smoke-*` fixture artifacts + `dashboard/data/autorun-suitability-events.jsonl`
- Inline JSON schema content for the events JSONL (no separate schema file; helper validates rows before append)

**Out of scope (V2):**
- **Item 4 — autoship-merge-preserves-branch** — carved to `/spec autoship-merge-hygiene` BACKLOG follow-up. Includes the `/branch-cleanup` housekeeping idea.
- **Constitution `autorun_suitability:` extension** — folded into future `/spec autorun-suitability-v2` (evidence-driven). V2 ships hardcoded permissive defaults.
- **Deterministic state file** (`.monsterflow/state/active-goal.json`) — Codex's preferred architectural solution. V2 ships narrowed LLM-scan instead; reconsider in `autorun-suitability-v2` if false-positive rate from real usage is high.
- **Multi-signal suitability** (AC count, LoC, gate-count) — instrumentation-driven; v2 of suitability indicator.
- **Wait-time metric** (`pipeline-user-wait-time-metric`) — sibling spec, separate.
- Auto-attempt `--admin` merge — your standing memory preserved. Branch-protection halt surfaces to user.
- `--delete-branch` behavior changes — item 4 carve.

## Approach

User-directed via Q&A (Q1-Q7) + V2 revision after /spec-review. Same approach as V1, with V2 incorporating reviewer findings.

Summary of locked decisions:
- **Q1 (b):** Tailored render per gate
- **Q2 (a):** Tag-based suitability + instrumented
- **Q3 (a):** Single shared Python helper (V2: with 2 subcommands per I4)
- **Q4 (a):** Gate skills detect active /goal as implicit AUTORUN (V2: narrowed to last-user-message)
- **Q5 (a):** Permissive mapping (V2: constitution-tunable deferred)
- **Q6 (c):** Strict halt + audit log on divergence
- **Q7 (c):** Two-tier — deterministic shell tests + manual smoke playbook
- **V2-X1:** Carve item 4 + constitution per scope + codex convergence

## Roster Changes

No roster changes. Pipeline-internal work covered by default 27 personas.

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
4. `/spec-review` fires next. Its Phase 0c-style autorun check scans the **last user message** for the literal trigger substring `is shipped via merged PR with verifier reporting`. Substring present → treats as implicit `AUTORUN=1` → emits `[autoship] /goal trigger detected in last user message — proceeding autonomously` → skips approval prompt → writes review artifacts → proceeds.
5. `/blueprint`, `/check`, `/build` same — but each gate re-checks the last user message in the current turn. If the user has since sent a non-trigger message (interrupt, refine, etc.), autorun does NOT carry over — manual mode resumes.
6. Each gate writes a `render` event row to `dashboard/data/autorun-suitability-events.jsonl`.
7. Branch protection blocks non-admin merge → halt at PR-open, emit halt-surface stdout block (see §Data & State), write `halt` event row, surface "needs explicit per-PR --admin auth" prompt. Never auto-attempts `--admin` (standing memory).
8. Human authorizes admin merge → PR merges → /goal verifier confirms ACs PASS → goal auto-clears → write `outcome` event row.

### Suitability MEDIUM example (security + migration both present)

```
Autorun suitability: MEDIUM (security + migration combo — review before autoship)

Recommended: proceed with /spec-review my-new-feature (manual gates)

If autonomous shipping is acceptable, copy + paste this exact line:
  /goal docs/specs/my-new-feature/spec.md is shipped via merged PR with verifier reporting 11/11 ACs PASS
```

### Suitability LOW example (`gate_mode: strict`)

```
Autorun suitability: LOW (gate_mode: strict — author opted out of permissive automation)

Proceed manually: /spec-review my-new-feature
```

No /goal line. `/spec-review` Phase 3 + `/check` GO/GO_WITH_FIXES blocks also suppress option **c)** for LOW-scoring specs (consistency — LOW means "don't suggest autoship at any gate").

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

### `/check` GO and GO_WITH_FIXES — same shape

For GO_WITH_FIXES specifically, the autoship-via-/goal semantics are: the inline-fix followups (`target_phase: build-inline`) are picked up by /build wave 1 automatically per existing permissive-mode behavior. The `/goal` autoship simply removes the manual approval gate between `/check` and `/build` — fixes are still applied; nobody skips them.

## Data & State

### Helper subcommands

```
scripts/_goal_autoship_render.py render --spec-path <p> --gate <g> [--render-mode <m>] [--no-log]
scripts/_goal_autoship_render.py log-event --spec-path <p> --gate <g> --event-type <halt|outcome> --reason <r> [--stage-at-halt <s>] [--pr <n>]
```

- `render` — emit render block to stdout, append one `event_type: render` row to JSONL (skipped if `--no-log`).
  - `--gate` ∈ `{spec-exit, spec-review, check-go, check-go-with-fixes}` (closed enum, exit 2 on other values)
  - `--render-mode` ∈ `{block, option-line}` (default `block`)
- `log-event` — append one row to JSONL with `event_type ∈ {halt, outcome}`, no stdout output.
  - `--event-type halt`: requires `--reason` (free-form string), optional `--stage-at-halt`
  - `--event-type outcome`: requires `--reason` (one of `shipped|failed|cancelled`), optional `--pr <N>`

Exit codes for both subcommands: 0 success, 1 if spec.md missing/malformed, 2 if argument invalid.

### Spec slug derivation rule

Slug is the **parent directory name** of the spec.md path. For `docs/specs/my-new-feature/spec.md`, slug is `my-new-feature`. Validated against `^[a-z0-9][a-z0-9-]{0,63}$`. Helper exits 1 if validation fails.

### AC count parsing rule

Count items under `## Acceptance Criteria` heading using regex `^[[:space:]]*(?:[-*]\s+|\d+\.\s+)` (matches `- text`, `* text`, or `N. text` at any indent). First-level only — nested bullets do not count. Checkbox items `- [ ]` and `- [x]` DO count (the leading `- ` matches). Parser stops at next `##`-level heading. If section is missing OR returns 0 matches, AC count is `null` (rendered as `?` in /goal line).

### Suitability scoring rule

```
1. Parse spec frontmatter: tags, gate_mode (default: permissive).
2. If gate_mode == "strict": return LOW.
3. If "security" IN tags AND "migration" IN tags: return MEDIUM.
4. Otherwise: return HIGH.
```

V2 carries NO constitution lookup. V2's suitability mapping is hardcoded.

### LLM trigger-detection rule (gate-skill side)

In each of `commands/{spec-review,blueprint,check,build}.md`, before the approval prompt phase:

```
1. Inspect the most-recent user message in the current conversation turn.
2. If it contains the literal substring "is shipped via merged PR with verifier reporting" (regex anchored: \bis shipped via merged PR with verifier reporting\b),
   treat as implicit AUTORUN=1:
   - Emit one stdout line: "[autoship] /goal trigger detected in last user message — proceeding autonomously"
   - Skip approval prompt; proceed with gate work
3. Otherwise: existing AUTORUN=1 env-var check, then existing approval prompt
```

This narrowed scan dissolves I1 (post-compact recovery) because the last user message can't be compacted away — it's the current turn's input.

### Halt-surface contract

When any gate-skill autoship flow halts (state divergence, branch protection block, verifier convergence stall, malformed spec, etc.), the gate skill MUST:

1. Emit a visible stdout block of the form:
   ```
   ╔══ autoship halt ══════════════════════════════════════════════╗
   ║ feature: <slug>
   ║ stage:   <spec-review|blueprint|check|build|merge>
   ║ reason:  <free-form reason string>
   ║ next:    <user action required, free-form>
   ╚══════════════════════════════════════════════════════════════════╝
   ```
2. Call `scripts/_goal_autoship_render.py log-event --event-type halt --reason <r> --stage-at-halt <s>` (writes the event row).
3. Do NOT proceed to the next stage. Wait for user input.

The stdout block is the load-bearing user-visible signal. JSONL is for instrumentation; the stdout block is for "wake up, autoship needs you."

### JSONL row schema (inlined — no separate schema file in v2)

File: `dashboard/data/autorun-suitability-events.jsonl` (gitignored). Append-only. Atomic per-row write via `fcntl.flock` advisory lock.

**Required fields (all rows):**
```json
{
  "schema_version": 1,
  "ts": "<UTC-ISO8601>",
  "event_type": "render|halt|outcome",
  "feature": "<slug>",
  "gate": "spec-exit|spec-review|check-go|check-go-with-fixes"
}
```

**Render-event fields (when `event_type: render`):**
```json
{
  "predicted_suitability": "HIGH|MEDIUM|LOW",
  "tags": [...],
  "ac_count": <integer-or-null>,
  "gate_mode": "permissive|strict"
}
```

**Halt-event fields (when `event_type: halt`):**
```json
{
  "reason": "<string>",
  "stage_at_halt": "spec-review|blueprint|check|build|merge"
}
```

**Outcome-event fields (when `event_type: outcome`):**
```json
{
  "reason": "shipped|failed|cancelled",
  "pr": <integer-or-null>
}
```

Helper validates row shape before append; invalid rows are dropped with stderr warning, never block render.

## Integration

Files touched (V2 — 10 files total, down from V1's 13):

- `scripts/_goal_autoship_render.py` — NEW, ~180 LoC (down from ~200 — constitution lookup removed)
- `commands/spec.md` Phase 4 — add suitability+/goal block before existing "Ready for /spec-review"
- `commands/spec-review.md` Phase 3 — add **c)** option (suppressed when LOW) + autorun trigger-detection block
- `commands/blueprint.md` — add autorun trigger-detection block (no UI option)
- `commands/check.md` GO + GO_WITH_FIXES — add **c)** option (suppressed when LOW) + autorun trigger-detection block
- `commands/build.md` — add autorun trigger-detection block
- `commands/flow.md` — locked paragraph wording (see below)
- `tests/test-goal-autoship-render.sh` — NEW, ~150 LoC, 11 cases
- `tests/run-tests.sh` — wire-in (1 LoC)
- `.gitignore` — add `_smoke-*` and `dashboard/data/autorun-suitability-events.jsonl`
- `CHANGELOG.md` — `[Unreleased]` entry
- `BACKLOG.md` — remove the 3 entries this spec consumes; ADD `autoship-merge-hygiene` carve

### Locked flow.md paragraph (B6)

Append the following block to `commands/flow.md` under the existing pipeline section (anchor: just before the `## Reference cards` section, or at end-of-file if no such section exists):

```markdown
## Autonomous Shipping (autoship via /goal)

When `/spec` exits with HIGH or MEDIUM suitability, it emits a copy-pasteable
`/goal` line. Paste it as your next message; the pipeline drives /spec-review →
/blueprint → /check → /build → PR autonomously. Gate skills detect the
literal trigger `is shipped via merged PR with verifier reporting` in your
most-recent message and skip approval prompts for that turn's gate.

Halts surface as a visible stdout block with `feature`, `stage`, `reason`,
and `next` fields. Branch-protection blocks require explicit per-PR `--admin`
authorization from you. Suitability is LOW when `gate_mode: strict` —
autoship is suppressed.

Suitability: HIGH (no security+migration combo, no strict gate); MEDIUM
(both security AND migration tags present); LOW (gate_mode: strict).
```

AC10 will grep for the anchor `## Autonomous Shipping (autoship via /goal)` to verify this block was added.

## Edge Cases

1. **Spec has no `tags:` frontmatter** — fallback to `HIGH` with stderr warning. Render proceeds. JSONL records `tags: []`.
2. **`## Acceptance Criteria` section missing/empty** — AC count is `null`, /goal line renders `?/?`. User can correct the count in their paste. JSONL records `ac_count: null`.
3. **`gate_mode: strict`** — suitability is `LOW`. `/goal` line NOT rendered at any gate. Option-c suppressed at /spec-review + /check.
4. **Last user message doesn't contain the trigger substring** — gate skill does NOT auto-proceed. Normal approval prompt fires.
5. **User triggers autoship, then sends a non-trigger message before next gate** (interrupt, refine, etc.) — gate skill checks NEW last user message; trigger absent → manual mode resumes. Autoship does NOT carry over across turns.
6. **Mid-flow user interrupt** (`[Request interrupted]`) — gate writes `halt` event, surfaces halt-surface block, waits for user.
7. **Branch protection blocks non-admin merge** — halt-surface block emitted, JSONL `halt` row written with `reason: branch-protection-block`, surfaces "needs explicit per-PR --admin auth" prompt. Never auto-attempts `--admin`.
8. **Helper script Python error** — `/spec` Phase 4 still emits the existing "Ready for /spec-review" line; indicator block skipped with stderr warning. Non-blocking.
9. **JSONL file unwritable** (permission, disk full) — helper logs to stderr, continues. Instrumentation is best-effort.
10. **Trigger substring appears in conversation but NOT in last user message** (e.g., quoted in a Claude reply or in a tool result) — does NOT trigger autoship. Narrow scan = high precision.
11. **Suitability LOW at /spec but user manually pastes /goal line anyway** — gate skills still detect trigger and proceed autonomously. The LOW score is informational; user override is respected.
12. **Test invocations** — use `--no-log` flag to suppress JSONL writes. Tests use `TMPDIR/autorun-suitability-events.jsonl` redirect when validating row format.

## Acceptance Criteria

Two-tier (per Q7).

### Tier 1 — Deterministic shell tests (`tests/test-goal-autoship-render.sh`)

1. **AC1 — helper exit codes** — `render` exits 0 on valid input, 1 on missing spec.md, 2 on invalid `--gate`. `log-event` exits 0 on valid input, 2 on missing `--reason` or invalid `--event-type`.
2. **AC2 — suitability mapping (3 fixtures)** — spec with `tags: [ux]` → HIGH; `tags: [security, migration]` → MEDIUM; `gate_mode: strict` frontmatter → LOW.
3. **AC3 — AC count parser (4 fixtures)** — section with 11 numbered items → 11; with 5 `- ` bullets → 5; missing section → null; section with only nested bullets → null.
4. **AC4 — render-mode `block` output** — must contain ALL 4 anchor strings: `=== Spec Written:`, `Autorun suitability:`, `Ship autonomously? Copy + paste this exact line:`, `Or proceed manually:`. Verified by per-anchor `grep -q`.
5. **AC5 — render-mode `option-line`** — output is just the **c)** bullet starting with `- **c)** Ship autonomously` (single block, no header). Verified by exact-match assertion on first non-empty line.
6. **AC6 — JSONL row schema (inline schema)** — every helper invocation appends exactly one row. Required fields present (`schema_version`, `ts`, `event_type`, `feature`, `gate`). `event_type` matches a discriminator's required fields. Validated by per-row `json.loads()` + key-presence assertion in test fixture.
7. **AC7 — `log-event` halt row** — `log-event --event-type halt --reason branch-protection-block --stage-at-halt merge` writes a row with `event_type: halt`, `reason: branch-protection-block`, `stage_at_halt: merge`. No stdout output.
8. **AC8 — `log-event` outcome row** — `log-event --event-type outcome --reason shipped --pr 22` writes a row with `event_type: outcome`, `reason: shipped`, `pr: 22`.
9. **AC9 — skill-prompt anchor table (B7/AC10 merged into one AC)** — grep each anchor in its target file:
    | Anchor | Target File |
    |--------|-------------|
    | `Autorun suitability:` | `commands/spec.md` |
    | `Ship autonomously? Copy + paste this exact line:` | `commands/spec.md` |
    | `- **c)** Ship autonomously` | `commands/spec-review.md` |
    | `- **c)** Ship autonomously` | `commands/check.md` |
    | `[autoship] /goal trigger detected` | `commands/spec-review.md` |
    | `[autoship] /goal trigger detected` | `commands/blueprint.md` |
    | `[autoship] /goal trigger detected` | `commands/check.md` |
    | `[autoship] /goal trigger detected` | `commands/build.md` |
    | `## Autonomous Shipping (autoship via /goal)` | `commands/flow.md` |
    | `╔══ autoship halt` | at least one of `commands/{spec-review,blueprint,check,build}.md` |
10. **AC10 — orchestrator wiring** — `tests/run-tests.sh` contains `test-goal-autoship-render.sh` in its TESTS array.
11. **AC11 — full test suite green** — `bash tests/run-tests.sh` exits 0; all existing tests + new test pass.

### Tier 2 — Manual smoke playbook

- **S1** — `/spec _smoke-DELETE-ME` in fresh session, complete Q&A, verify Phase 4 emits HIGH-suitability block with all 4 anchor strings. Cancel before any commit.
- **S2** — `/spec-review wiki-write-conventions` against existing shipped spec, verify Phase 3 prompt renders **c) Ship autonomously** option with correct /goal line. Cancel before reply.
- **S3** — `/check wiki-write-conventions`, verify GO_WITH_FIXES block renders **c)** option. Cancel before reply.
- **S4** — type a trigger message verbatim, then run `/spec-review`, verify gate skill emits `[autoship] /goal trigger detected in last user message — proceeding autonomously` and skips approval. After: type a non-trigger message, run another gate, verify autorun does NOT carry over.
- **S5** — manually trigger a halt (e.g., interrupt mid-build); verify halt-surface stdout block appears with the 4 required fields.

## Self-Learning Loop (read-only design intent for v2)

The `dashboard/data/autorun-suitability-events.jsonl` instrumentation feeds a future evidence-based heuristic refinement. After ~20+ specs through the indicator, a `/spec autorun-suitability-v2` can analyze:
- Per-tag actual ship-rate (predicted HIGH → shipped autonomously vs halted)
- Per-stage halt distribution
- Per-project drift (which projects need constitution-tunable bars)

**Per scope reviewer note:** this section is design intent for v2 only — /build should NOT build analysis tooling in this spec. v1 is instrumentation-only.

## Open Questions

None remaining. Q&A converged at avg confidence 0.94. All blockers from /spec-review folded inline.

## Risks

- **R1 (low):** Last-user-message LLM-scan detection — if Claude Code's session model evolves (e.g., multi-message interleaved input), "most-recent user message" may need re-defining. Mitigation: detection logic is a single anchored-regex check; trivial to update.
- **R2 (low):** JSONL write contention if multiple gate skills fire concurrently (e.g., parallel /build subagents). Mitigation: `fcntl.flock` advisory lock in helper.
- **R3 (very low):** Halt-surface stdout block could be missed if terminal output is captured by tooling (cmux, autorun). Mitigation: also emit ASCII `[AUTOSHIP-HALT]` marker on a separate line; tooling can grep for that.
- **R4 (low):** Carved follow-ups (`autoship-merge-hygiene`, constitution extension in v2) accumulate as unshipped scope. Mitigation: BACKLOG entries created with clear entry points.
