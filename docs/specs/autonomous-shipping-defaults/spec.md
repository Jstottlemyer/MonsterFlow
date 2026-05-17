---
tags: [api, data, docs, integration, pipeline, refactor, scalability, security, ux]
tags_provenance:
  baseline: [api, data, integration, scalability, security, ux]
  llm_added: [docs, pipeline, refactor]
  user_overrides: []
gate_mode: permissive
---

# autonomous-shipping-defaults Spec

**Created:** 2026-05-16
**Constitution:** none — MonsterFlow personal-tooling repo uses pipeline-default personas
**Confidence:** Scope 0.95 · UX 0.92 · Data 0.92 · Integration 0.92 · Edge 0.88 · Acceptance 0.92 · **avg 0.92**

---

## Summary

Bundles four backlog items that together make autonomous shipping the natural default for autorun-suitable specs rather than a power-user incantation. At `/spec` exit, an autorun-suitability indicator (HIGH/MED/LOW) and a copy-pasteable `/goal` line render automatically. The same `/goal` line surfaces as a 3rd option at `/spec-review` Phase 3 approval and `/check` GO verdict. Gate skills treat an active `/goal` containing the literal `shipped via merged PR` as implicit `AUTORUN=1` (single user gesture, no env-var step). Autoship's `gh pr merge` invocation drops `--delete-branch` so branches remain recoverable when no human audited the merge.

## Backlog Routing

| Item | Source | Routing |
|------|--------|---------|
| `pipeline-goal-wrap-default` (S) | BACKLOG.md:29 | (a) in scope — bundle core |
| `flow-goal-autoship-pattern` (XS) | BACKLOG.md:23 | (a) in scope — bundle core |
| `autorun-suitability-indicator` (S) | BACKLOG.md:19 | (a) in scope — bundle core |
| `autoship-merge-preserves-branch` (NEW, S) | This session's Q6 discussion | (a) in scope — 4th item |
| `pipeline-user-wait-time-metric` (S-M) | BACKLOG.md:17 | (b) stays — Bundle B sibling |
| `resolver-recovery-shell-owned` (S-M) | BACKLOG.md:40 | (b) stays — different domain |
| `dashboard-actionable-surface` (S-M) | BACKLOG.md:15 | (b) stays — dashboard work |

## Scope

**In scope:**
- New helper script `scripts/_goal_autoship_render.py` — computes feature slug, AC count, tag-based suitability score (HIGH/MED/LOW), emits the per-gate render block.
- Skill edits to `commands/spec.md` Phase 4 (autorun-suitability indicator + /goal line at spec exit).
- Skill edits to `commands/spec-review.md` Phase 3 (add **c) Ship autonomously** option to approval prompt).
- Skill edits to `commands/check.md` GO and GO_WITH_FIXES verdict blocks (add **c) Ship autonomously** option).
- Gate-skill detection of active `/goal` in conversation context as implicit `AUTORUN=1` — applies to `commands/spec-review.md`, `commands/blueprint.md`, `commands/check.md`, `commands/build.md` (4 skills).
- `commands/flow.md` reference card update — one-paragraph addition documenting the autoship pattern.
- Autoship merge command change — when `/goal` drives the merge, omit `--delete-branch` from the `gh pr merge` invocation. Manual merges (no /goal context) retain `--delete-branch`.
- Constitution schema extension — `autorun_suitability:` block with per-tag overrides (e.g., `ux: MEDIUM`). Constitution-absent specs use the permissive default mapping.
- Instrumentation log — `dashboard/data/autorun-suitability-outcomes.jsonl` append-only JSONL with predicted suitability, chosen path (autoship/manual), outcome (shipped/halted/failed), and divergence reasons.
- New test `tests/test-goal-autoship-render.sh` — deterministic shell asserts on helper output, log schema, merge-command flags.
- Manual smoke playbook (T-final) — non-mutating render verification at each gate, like spec-qa-terminal-formatting's T12.

**Out of scope:**
- Multi-signal suitability scoring (AC count, LoC, gate-count) — v1 is tag-based only; future `/spec autorun-suitability-v2` will be evidence-based after instrumentation has data.
- Wrapper script `scripts/ship-now.sh` or `/ship-now` skill — Q4 chose gate-skill detection of active /goal instead.
- Wait-time metric (`pipeline-user-wait-time-metric`) — sibling spec, separate.
- Auto-attempt `--admin` merge inside /goal — your standing memory `never-bypass-main-branch-protection` + `goal-mode-doesnt-imply-admin-merge` is preserved. Branch-protection block halts the autoship with a user prompt.
- Existing manual `gh pr merge` invocations (not /goal-driven) — keep `--delete-branch` default.

## Approach

User-directed via Q&A (Q1-Q7). All seven architectural decisions made through tradeoff questions with rationale. No separate "approach proposal" phase needed — the Q&A IS the approach exploration.

Summary of decisions:
- **Q1 — gate surface (b):** Tailored per gate. `/spec` exit shows suitability + /goal line; `/spec-review` Phase 3 adds **c) Ship autonomously**; `/check` GO/GO_WITH_FIXES adds **c) Ship autonomously**.
- **Q2 — suitability inputs (a):** Tag-based only. Instrumented for future evidence-based tightening.
- **Q3 — implementation shape (a):** Single shared Python helper `scripts/_goal_autoship_render.py`.
- **Q4 — env var collapse (a):** Gate skills treat active /goal as implicit AUTORUN. No env-var step.
- **Q5 — tag mapping (a):** Permissive — LOW only if `gate_mode: strict` frontmatter is set; MEDIUM only if `security` + `migration` both present; HIGH otherwise. Constitution-tunable per-tag.
- **Q6 — state divergence (c):** Strict halt on divergence + audit log to the same JSONL.
- **Q7 — test surface (c):** Two-tier — deterministic shell tests for helper/schema/flags; manual smoke playbook for LLM-detection paths.

## Roster Changes

No roster changes. Pipeline-internal work (skills + scripts + tests) covered by the default 27 personas.

## UX / User Flow

### Happy path — autoship a HIGH-suitability spec

1. User runs `/spec my-new-feature`, completes Q&A, spec written.
2. `/spec` Phase 4 renders:
   ```
   === Spec Written: my-new-feature (11 ACs) ===
   Autorun suitability: HIGH (no security/migration combo, no gate_mode: strict)

   Ship autonomously? Copy + paste:
     /goal docs/specs/my-new-feature/spec.md is shipped via merged PR with verifier reporting 11/11 ACs PASS

   Or proceed manually: /spec-review my-new-feature
   ```
3. User pastes the `/goal` line into the prompt. Claude Code sets the goal condition.
4. `/spec-review` fires next (user-initiated or autorun-driven). Phase 0c sees an active /goal containing `shipped via merged PR` → treats as implicit AUTORUN=1 → skips approval prompt → writes review artifacts → proceeds.
5. `/blueprint` same — autorun-driven by /goal detection.
6. `/check` same — autorun-driven, emits verdict, proceeds to /build on GO or GO_WITH_FIXES.
7. `/build` runs waves autonomously, opens PR.
8. Autoship's `gh pr merge` invocation omits `--delete-branch` (branch preserved for forensics).
9. Branch protection blocks non-admin merge → halt, surface "needs --admin auth, reply 'yes admin-merge N'" → wait for human.
10. Human authorizes admin merge → PR merges → /goal verifier confirms ACs PASS → goal auto-clears.

### Suitability MEDIUM example

Spec has `security` AND `migration` tags. `/spec` Phase 4 renders:
```
Autorun suitability: MEDIUM (security + migration combo — review before autoship)

Recommended: proceed with /spec-review my-new-feature (manual gates)

If autonomous shipping is acceptable, copy + paste:
  /goal docs/specs/my-new-feature/spec.md is shipped via merged PR with verifier reporting 11/11 ACs PASS
```

User still gets the option, just with explicit note that the heuristic recommends caution.

### Suitability LOW example

Spec has `gate_mode: strict` frontmatter. `/spec` Phase 4 renders:
```
Autorun suitability: LOW (gate_mode: strict)

Proceed manually: /spec-review my-new-feature
```

No `/goal` line rendered. Strict mode means the author explicitly opted out of permissive automation.

### `/spec-review` Phase 3 — new option

```
Approve to proceed to /blueprint?

- **a)** Approve — accept the review and continue
- **b)** Refine — name what to change (`b tighten AC4 wording`)
- **c)** Ship autonomously — paste this:
       /goal docs/specs/my-new-feature/spec.md is shipped via merged PR with verifier reporting 11/11 ACs PASS
       (suitability: HIGH)

Reply with `a`, `b <change>`, or `c` + Enter.
```

### `/check` GO verdict — new option

```
[If GO]: Ready for /build.

- **a)** Go — proceed to /build
- **b)** Hold — pause and discuss before /build
- **c)** Ship autonomously — paste this:
       /goal docs/specs/my-new-feature/spec.md is shipped via merged PR with verifier reporting 11/11 ACs PASS
       (suitability: HIGH)

Reply with `a`, `b`, or `c` + Enter.
```

### `/check` GO_WITH_FIXES — same shape

Same **c)** option as GO. Permissive-mode GO_WITH_FIXES already proceeds to /build with inline-fix followups; autoship is consistent with that.

## Data & State

### `scripts/_goal_autoship_render.py` contract

Inputs (CLI):
- `--spec-path <path>` — path to spec.md (required)
- `--gate <name>` — one of: `spec-exit`, `spec-review`, `check-go`, `check-go-with-fixes` (required)
- `--render-mode <mode>` — `block` (full render with header+/goal-line+manual-fallback) or `option-line` (just the option-c snippet for spec-review/check) (default: `block`)

Outputs:
- stdout — the render block, formatted per `--render-mode`
- exit code — 0 success, 1 if spec.md missing/malformed, 2 if `--gate` invalid

Internal logic:
- Parse spec.md frontmatter `tags:` array.
- Parse `## Acceptance Criteria` section, count items (numbered list or bulleted list at first level).
- Read `gate_mode:` from frontmatter (default `permissive`).
- Read constitution (if `docs/specs/constitution.md` exists), parse `autorun_suitability:` block for per-tag overrides.
- Compute suitability:
  - `LOW` if `gate_mode == "strict"` OR any constitution override forces `low`
  - `MEDIUM` if (`security` AND `migration` both in tags) OR any constitution override forces `medium`
  - `HIGH` otherwise
- Emit render block per `--gate` + `--render-mode` template.
- Append one row to `dashboard/data/autorun-suitability-outcomes.jsonl`:
  ```json
  {
    "schema_version": 1,
    "ts": "<UTC-ISO8601>",
    "feature": "<slug>",
    "gate": "<gate>",
    "predicted_suitability": "<HIGH|MEDIUM|LOW>",
    "tags": [...],
    "ac_count": <N>,
    "gate_mode": "<permissive|strict>",
    "constitution_overrides_applied": [...]
  }
  ```

Gate-skill autorun detection (in `commands/{spec-review,blueprint,check,build}.md`):
- LLM scans recent conversation messages for a `/goal` invocation.
- If found AND the goal condition contains the literal `shipped via merged PR` AND no subsequent `/goal clear` invocation, treat as implicit `AUTORUN=1`.
- Render a one-line acknowledgment: `[autoship] /goal active — proceeding autonomously (no approval prompt)`.
- On any of these state-divergence cases, write a `divergence` row to the same JSONL (Q6 c):
  ```json
  {
    "schema_version": 1,
    "ts": "<UTC-ISO8601>",
    "feature": "<slug>",
    "gate": "<gate>",
    "event": "autoship-halt",
    "reason": "<goal-cleared|condition-changed|user-interrupt|malformed-spec|branch-protection-block>",
    "stage_at_halt": "<spec-review|blueprint|check|build|merge>"
  }
  ```

### Autoship merge command change

When the autoship flow reaches PR-merge stage AND the merge is /goal-driven (LLM detects active goal in conversation), the `gh pr merge` invocation drops `--delete-branch`:
- /goal-driven: `gh pr merge <N> --squash --admin` (no `--delete-branch`)
- Manual interactive: `gh pr merge <N> --squash --admin --delete-branch` (current behavior)

A weekly/monthly housekeeping skill `/branch-cleanup` (out of scope for this spec; flag as follow-up backlog if useful) could sweep merged-and-aged branches.

## Integration

Files touched:
- `scripts/_goal_autoship_render.py` (new, ~200 LoC)
- `commands/spec.md` Phase 4 (add suitability+/goal block before existing "Ready for /spec-review" line)
- `commands/spec-review.md` Phase 3 approval prompt (add **c)** option, render via helper `--gate spec-review --render-mode option-line`)
- `commands/check.md` GO + GO_WITH_FIXES verdict blocks (add **c)** option, helper invocations)
- `commands/spec-review.md`, `commands/blueprint.md`, `commands/check.md`, `commands/build.md` autorun detection blocks (add /goal-active check to existing `AUTORUN=1` env-var check at each gate's approval phase)
- `commands/flow.md` reference card (~10-line paragraph documenting autoship pattern)
- `schemas/autorun-suitability-outcomes.schema.json` (new, JSON schema for the JSONL log rows)
- `dashboard/data/autorun-suitability-outcomes.jsonl` (gitignored if private; tracked otherwise — decide at write time per `feedback_public_repo_data_audit.md` memory)
- `tests/test-goal-autoship-render.sh` (new, deterministic shell tests, ~150 LoC, ~12 cases)
- `tests/run-tests.sh` (wire-in)
- `CHANGELOG.md` (Unreleased entry)
- `BACKLOG.md` (remove the 3 entries this spec consumes)
- `docs/specs/constitution.md` template — if `/kickoff`'s constitution template lives at `~/.claude/templates/constitution.md`, add the `autorun_suitability:` block as a documented optional knob

Constitutional knob shape:
```yaml
autorun_suitability:
  # Override per-tag suitability ceiling. Defaults to permissive (HIGH for most).
  # Keys: any of the 10 enum tags. Values: HIGH | MEDIUM | LOW.
  # Effect: if a spec has the tag, suitability is clamped to this ceiling.
  ux: MEDIUM        # example: mobile-games project where device testing matters
  data: MEDIUM      # example: data-intensive project where schema changes need review
```

## Edge Cases

1. **Spec has no `tags:` frontmatter** — fallback to `HIGH` with one-line warning rendered to user: `[autoship] spec has no tags — suitability defaults to HIGH; consider adding tags for better routing`. Log row records `tags: []`.
2. **`## Acceptance Criteria` section missing or unparseable** — render `(N/?)` in the goal-line; suitability still scores; do NOT block the /goal-line emission. User can manually correct the count in their pasted line. Log row records `ac_count: null`.
3. **`gate_mode: strict` frontmatter** — suitability is `LOW`, /goal-line is NOT rendered, only manual fallback shown. Strict mode means the author explicitly opted out.
4. **Active /goal with different condition** (e.g., `/goal "ship by 3pm"`, not "shipped via merged PR") — gate skill does NOT treat as implicit AUTORUN. Manual approval prompt fires.
5. **Active /goal then `/goal clear`** — gate skill respects the clear; falls back to manual prompts on subsequent gates.
6. **Mid-flow user interrupt** (`[Request interrupted]`) — halt current wave, write `autoship-halt` JSONL row with `reason: user-interrupt`, surface manual prompt on resume.
7. **Branch protection blocks non-admin merge** (tonight's case) — autoship halts at PR-open, writes `autoship-halt` row with `reason: branch-protection-block`, surfaces "needs explicit per-PR --admin auth" prompt. Never auto-attempts `--admin` (your standing memory).
8. **Constitution exists but no `autorun_suitability:` block** — permissive defaults apply, no warning.
9. **Constitution `autorun_suitability:` references unknown tag** — helper warns to stderr, ignores the unknown tag mapping. Closed-enum guard.
10. **Helper script itself fails** (Python error, missing dep) — `/spec` Phase 4 still emits the existing "Ready for /spec-review" line; the indicator block is skipped with one-line stderr warning. Non-blocking.
11. **Spec has `security` but NOT `migration`** — suitability is `HIGH` (per Q5 (a) mapping: requires both). User can opt-in to MEDIUM-ceiling via constitution `autorun_suitability.security: MEDIUM`.
12. **Multiple `/goal` invocations in session** — most recent unresolved goal wins. If most recent doesn't match shipped-via-PR semantics, prior goals are ignored.
13. **/spec exit during AUTORUN=1 env var** — already auto-proceeds per existing Phase 4 logic; indicator block still renders (informational) but no manual prompt suppressed (was already going to skip).
14. **Outcomes JSONL file missing or unwritable** — helper logs to stderr and continues; never blocks render. Instrumentation is best-effort.

## Acceptance Criteria

Two-tier (per Q7 c):

### Tier 1 — Deterministic shell tests (in `tests/test-goal-autoship-render.sh`)

1. **AC1 — helper exit codes** — `_goal_autoship_render.py` exits 0 on valid input, 1 on missing/malformed spec.md, 2 on invalid `--gate` value.
2. **AC2 — suitability mapping** — fixture specs with tags `[ux]` → HIGH; `[security, migration]` → MEDIUM; `gate_mode: strict` frontmatter → LOW.
3. **AC3 — AC count parser** — fixture spec with 11 items under `## Acceptance Criteria` returns 11; 0 items returns 0; malformed section returns null (rendered as `?`).
4. **AC4 — render-mode `block`** — output includes header, suitability line, /goal line with correct slug+count, manual fallback line. Verified by grep on output.
5. **AC5 — render-mode `option-line`** — output is just the **c) Ship autonomously** bullet (single block, no header).
6. **AC6 — instrumentation log row schema** — every helper invocation appends exactly one JSONL row matching `schemas/autorun-suitability-outcomes.schema.json`. Verified by `python3 -c "import json; json.load(...)"` per row.
7. **AC7 — constitution override** — fixture constitution with `autorun_suitability.ux: MEDIUM` clamps `[ux]`-tagged spec to MEDIUM (default would be HIGH).
8. **AC8 — autoship merge command flag** — render-mode `block` output for the merge step omits `--delete-branch`; render-mode `block` with `--gate manual-merge` includes `--delete-branch`. (Two fixture invocations.)
9. **AC9 — divergence log row** — fixture invocation with `--event autoship-halt --reason branch-protection-block` writes a row with the expected `event` and `reason` fields.
10. **AC10 — skill-prompt anchor strings** — `tests/test-goal-autoship-render.sh` greps `commands/spec.md`, `commands/spec-review.md`, `commands/check.md` for required anchor strings (e.g., literal `Ship autonomously` in the option-c line). Catches accidental removal during future edits.
11. **AC11 — orchestrator wiring** — `tests/run-tests.sh` contains `test-goal-autoship-render.sh` in its TESTS array.
12. **AC12 — full test suite green** — running `bash tests/run-tests.sh` passes all existing tests + new test (regression bar).

### Tier 2 — Manual smoke playbook (T-final, deferred to user)

Non-mutating render verification at each gate (mirrors spec-qa-terminal-formatting's T12):
- **S1** — `/spec _smoke-DELETE-ME` in fresh session, complete Q&A, verify Phase 4 emits HIGH-suitability block with correct format. Cancel before any commit.
- **S2** — `/spec-review wiki-write-conventions` against existing shipped spec, verify Phase 3 approval prompt renders **c) Ship autonomously** option with correct /goal line. Cancel before reply.
- **S3** — `/check wiki-write-conventions`, verify GO_WITH_FIXES block renders **c)** option. Cancel before reply.
- **S4** — set `/goal docs/specs/wiki-write-conventions/spec.md is shipped via merged PR with verifier reporting X/X ACs PASS`, then run `/spec-review`, verify gate skill detects active goal and skips approval prompt (emits `[autoship] /goal active — proceeding autonomously`). `/goal clear` after.
- **S5** — `/goal clear` mid-flow, verify subsequent `/check` or `/build` reverts to manual prompts.

## Self-Learning Loop

The `dashboard/data/autorun-suitability-outcomes.jsonl` instrumentation feeds a future evidence-based heuristic refinement. After N runs (suggest threshold: 20+ specs through the indicator), a `/spec autorun-suitability-v2` can analyze:
- Per-tag actual ship-rate (predicted HIGH → actually shipped autonomously? vs predicted HIGH → halted at some stage)
- Per-stage halt distribution — which divergence reasons fire most? (Branch-protection-block? Verifier convergence-stall? User-interrupt?)
- Per-project drift — if a constitution opts MEDIUM-ceiling on a tag, does that match outcome data, or is the project's bar actually different?

The v1 mapping (Q5 a) is deliberately permissive on the assumption that "discover errors to find the correct balance" beats speculative over-tightening. This spec ships the instrumentation that makes v2 evidence-based.

## Open Questions

None remaining. Q&A converged at avg confidence 0.92. OQ1 resolved at write-time:

- **OQ1 (RESOLVED 2026-05-16):** `dashboard/data/autorun-suitability-outcomes.jsonl` is **gitignored** by default per `feedback_public_repo_data_audit.md` memory. Add `dashboard/data/autorun-suitability-outcomes.jsonl` to `.gitignore`. Users can opt-in to tracking by removing the line.

## Risks

- **R1 (medium):** Gate-skill LLM detection of active /goal is prompt-time heuristic, not deterministic. False negatives (skill misses active goal, prompts manually) are recoverable — user just types `a` or the /goal line again. False positives (skill thinks goal is active when it isn't) skip approval prompts, which could surprise. Mitigation: explicit detection semantics in skill prompts ("most recent /goal invocation in session, condition contains literal 'shipped via merged PR', no subsequent /goal clear"), plus the `[autoship] /goal active — proceeding autonomously` acknowledgment line so the user sees what the skill decided.
- **R2 (low):** Helper script Python failure could break `/spec` Phase 4. Mitigation: edge case 10 — failure is non-blocking; existing "Ready for /spec-review" line still renders.
- **R3 (low):** Tag-baseline permissive mapping (Q5 a) under-recommends caution for some tag combinations not yet seen. Mitigation: instrumentation log + future v2 tightening.
- **R4 (very low):** Constitution override schema drift across projects. Mitigation: closed-enum tag list + ignore-unknown-keys guard with stderr warning.
