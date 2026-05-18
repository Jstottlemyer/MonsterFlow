# Implementation Plan — autonomous-shipping-defaults

**Date:** 2026-05-17
**Designers:** api:opus · integration:sonnet · data-model:sonnet (+ codex-adversary Phase 2b)
**Gate mode:** permissive (frontmatter)
**Spec input:** V3 (`docs/specs/autonomous-shipping-defaults/spec.md`)

---

## Architecture Summary

Path B chain-invoke implemented via three mechanisms working together:

1. **Helper script** `scripts/_goal_autoship_render.py` with 2 subcommands (`render`, `log-event`). Stdlib-only. Owns: spec parsing, suitability scoring, stdout render blocks, JSONL row writes with `fcntl.flock`.
2. **Skill-prompt edits** to 6 gate skill files. Each gate gains an *autoship-detection block* at gate-entry (after Phase 0c) and a *chain-invoke block* at gate-end (after artifact write). Blocks are copy-paste-identical across files, wrapped in splice sentinels for drift detection.
3. **/spec Phase 4 render block** — first-touchpoint that emits the suitability indicator + `/goal` line via the helper.

Detection is LLM-driven (scans session user messages for trigger substring); helper invocations are deterministic shell calls. Chain hops via `Skill(skill="<next>", args="<slug>")` at end-of-skill — proven single-hop pattern from `commands/spec.md` Phase 4 Auto-Run, extended to 4-hop here (multi-hop = R1, S4 smoke validates).

---

## Design Decisions

### D1. Helper CLI: argparse subparsers, not flag-distinguished modes
Per api designer recommendation (Option A). Layout:
```python
parser = argparse.ArgumentParser()
sub = parser.add_subparsers(dest='subcommand', required=True)

render = sub.add_parser('render')
render.add_argument('--spec-path', required=True)
render.add_argument('--gate', required=True, choices=GATE_ENUM)
render.add_argument('--surface', choices=SURFACE_ENUM)  # validated in code: only for render-bearing gates
render.add_argument('--no-log', action='store_true')

log_event = sub.add_parser('log-event')
log_event.add_argument('--spec-path', required=True)
log_event.add_argument('--gate', required=True, choices=GATE_ENUM)
log_event.add_argument('--event-type', required=True, choices=['halt', 'outcome'])
log_event.add_argument('--reason', required=True)
log_event.add_argument('--stage-at-halt', choices=GATE_ENUM)  # only meaningful for halt events
log_event.add_argument('--pr', type=int)  # only meaningful for outcome events
```

Constants:
```python
GATE_ENUM = ['spec-exit', 'spec-review', 'blueprint', 'check-go', 'check-go-with-fixes', 'build', 'merge']
SURFACE_ENUM = ['spec-exit', 'spec-review-option', 'check-go-option', 'check-go-with-fixes-option']
RENDER_BEARING_GATES = {'spec-exit', 'spec-review', 'check-go', 'check-go-with-fixes'}
SCHEMA_VERSION = 1
OUTCOME_REASONS = {'shipped', 'failed', 'cancelled'}
```

`--surface` validated post-parse: exit 2 if `--surface` set on gate not in `RENDER_BEARING_GATES`.

### D2. `stage_at_halt` enum reuses `--gate` enum verbatim
Per data-model designer C1. Resolves the V3 spec's unspecified enum gap.

### D3. Skill-prompt canonical blocks with splice sentinels
Per api designer Q1 + integration designer. Each gate skill carries two blocks wrapped in HTML-comment sentinels:

**Autoship-detection block** (inserted after Phase 0c in each of /spec-review, /blueprint, /check, /build):
```markdown
<!-- BEGIN autoship-detection -->
## Autoship Detection (V3 Path B)

Before this gate's work begins, scan all user messages in the current session for the literal substring:

  `is shipped via merged PR with verifier reporting`

If found AND no subsequent `/goal clear` invocation since the most recent trigger:

1. Extract the spec slug from the matched /goal line (regex: `docs/specs/([a-z0-9][a-z0-9-]{0,63})/spec\.md`).
2. If the extracted slug matches this gate's `--feature` argument:
   - Emit exactly: `[autoship] active goal detected — proceeding autonomously through pipeline`
   - Set internal flag: autoship-active = true
   - Skip the manual approval prompt for this gate
3. If slug mismatches:
   - Emit: `[autoship] /goal active for <other-slug>, current gate is <this-slug> — manual mode`
   - autoship-active = false

Otherwise: autoship-active = false; existing AUTORUN=1 env-var check, then existing approval prompt.
<!-- END autoship-detection -->
```

**Chain-invoke block** (inserted at end of each gate skill's normal-completion path):
```markdown
<!-- BEGIN autoship-chain-invoke -->
## Autoship Chain-Invoke (V3 Path B)

If autoship-active = true at this gate's completion:
- /spec-review final action: `Skill(skill="blueprint", args="<feature-slug>")`
- /blueprint final action: `Skill(skill="check", args="<feature-slug>")`
- /check final action on GO or GO_WITH_FIXES: `Skill(skill="build", args="<feature-slug>")`
- /check final action on NO_GO: STOP, emit halt-surface block (do not chain)
- /build final action: existing PR-open path; halt-surface block on branch-protection-block

This MUST be the final action — no further work after the Skill invocation.
<!-- END autoship-chain-invoke -->
```

AC9 grep targets the sentinel boundaries to enforce drift detection.

### D4. flow.md is a `!cat` shim — locked paragraph goes in flow-card.txt
Per integration designer C7. `commands/flow.md` is 6 lines that just `cat` `~/.claude/commands/flow-card.txt`. The locked paragraph (V3 spec §Integration "Locked flow.md paragraph") must be appended to `flow-card.txt`, not `flow.md`. AC9 anchor grep changes target file from `commands/flow.md` to `~/.claude/commands/flow-card.txt` (or via symlink chain — confirm at build time).

Actually wait — `flow-card.txt` lives in `~/.claude/commands/`, not in the repo. The MonsterFlow repo's source-of-truth is `commands/flow-card.txt` (if it exists) which install.sh symlinks to `~/.claude/commands/flow-card.txt`. Check at build time. AC9 grep target: `commands/flow-card.txt` (repo source).

### D5. `/check` Phase 3 needs full AUTORUN MODE block added
Per integration designer C1. `/check` currently has no `[AUTORUN MODE: ...]` block in Phase 3. V3 needs to:
- Add the canonical AUTORUN MODE block from scratch (not just modify existing language)
- Include the autoship-active OR-clause

### D6. `outcome` event row writer pinned
Per data-model designer OQ3. The `outcome` event row (`shipped`/`failed`/`cancelled`) is emitted by:
- `commands/build.md` post-PR-merge — when the autoship chain completes successfully and the verifier confirms ACs PASS. Build invokes: `_goal_autoship_render.py log-event --gate merge --event-type outcome --reason shipped --pr <N>` after detecting the merge.

For `failed` (e.g., autorun max-retries exhausted) or `cancelled` (user interrupt), the gate that detects the terminal state writes the row.

### D7. JSONL atomic-append with directory-creation
Per data-model designer C8. Helper writes:
```python
import fcntl, json, os
from pathlib import Path
from datetime import datetime, timezone

def append_event(row: dict, path: Path = Path('dashboard/data/autorun-suitability-events.jsonl')):
    """Atomic append with fcntl.flock advisory lock."""
    path.parent.mkdir(parents=True, exist_ok=True)  # C8 fix
    line = json.dumps(row, separators=(',', ':')) + '\n'
    with open(path, 'a') as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        try:
            f.write(line)
            f.flush()
            os.fsync(f.fileno())
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)
```

ts format pinned: `datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')` (no fractional seconds in v1; bump policy below).

### D8. Schema bump policy (one-sentence rule)
Per data-model designer C6: "`schema_version` bumps to 2 only on breaking field-type change or required-field removal; additive changes (new optional fields, new enum values) do not bump." Documented in helper docstring.

### D9. `tags` field normalization
Per data-model designer C3:
- `tags: []` → `[]`
- `tags: null` or absent → `[]`
- `tags: "security"` (string) → `["security"]` with stderr warning
- `tags:` non-list other type → `[]` with stderr warning

Defensive against malformed YAML frontmatter.

### D10. Helper invocation pattern: Bash tool, capture stdout, embed in skill response
Per api + integration designers. Skill prompts contain Bash invocations like:
```bash
python3 ~/Projects/MonsterFlow/scripts/_goal_autoship_render.py render \
  --spec-path docs/specs/$FEATURE/spec.md \
  --gate spec-exit
```
LLM captures stdout (the render block) and emits it verbatim to the user.

For `log-event` (no stdout): LLM emits the bash invocation, ignores zero-stdout result.

### D11. Chain-invoke args payload: slug-only
Per api designer Q4. `Skill(skill="check", args="my-feature-slug")` — no additional state passed. Each gate re-detects autoship via conversation scan (idempotent).

### D12. /spec Phase 4 render placement
Per integration designer. Insert the render-block invocation immediately before the existing "Ready for /spec-review (budget-selected PRD reviewer agents will analyze this spec)." closing line. The render adds suitability + /goal line; existing closing line stays unchanged.

### D13. /spec-review and /check `**c)** Ship autonomously` option suppression on LOW
Per V3 §Edge case 3. Helper's `render --gate spec-review --surface spec-review-option` exits with empty stdout when suitability is LOW; skill checks for empty stdout and omits the option-c bullet entirely. Same for /check.

### D14. Halt-surface contract — emitted at every halt site
Per V3 §Halt-surface contract. Each gate skill embeds the box-drawing template inline at each halt branch (NO_GO at /check, malformed spec, branch protection, etc.). Plus the `[AUTOSHIP-HALT]` ASCII marker on a separate line. Followed by the `log-event --event-type halt` call.

The block is small (~7 lines); copy-pasted inline at each halt site rather than wrapped in a helper. Each occurrence is grep-verified by AC9.

---

## Implementation Tasks

| # | Task | Depends On | Size | Wave | Parallel? |
|---|------|------------|------|------|-----------|
| T1 | Write `scripts/_goal_autoship_render.py` (helper, ~180 LoC) | — | M | 1 | yes (with T2) |
| T2 | Write `tests/test-goal-autoship-render.sh` (13 ACs, ~180 LoC) | T1 contract | M | 1 | yes (with T1) |
| T3 | Edit `commands/spec.md` Phase 4 — add render block + `/goal` line emission | T1 contract | S | 2 | yes (T3-T8) |
| T4 | Edit `commands/spec-review.md` — autoship-detect (Phase 0c+), **c)** option in Phase 3, chain-invoke at end | T1 contract | M | 2 | yes |
| T5 | Edit `commands/blueprint.md` — autoship-detect (Phase 0c+), chain-invoke at end (no **c)** option per D5) | T1 contract | S | 2 | yes |
| T6 | Edit `commands/check.md` — add full AUTORUN MODE block (Phase 3), autoship-detect, **c)** in GO + GO_WITH_FIXES, chain-invoke in both branches | T1 contract | M | 2 | yes |
| T7 | Edit `commands/build.md` — autoship-detect (Phase 0c+), terminus (no chain forward), `outcome` event row emission post-merge | T1 contract | M | 2 | yes |
| T8 | Edit `commands/flow-card.txt` — append locked paragraph (per D4) | — | XS | 2 | yes |
| T9 | Wire `test-goal-autoship-render.sh` into `tests/run-tests.sh` TESTS array | T2 | XS | 3 | — |
| T10 | Update `.gitignore` — add `_smoke-*` pattern + explicit `dashboard/data/autorun-suitability-events.jsonl` anchor | — | XS | 3 | yes (with T9) |
| T11 | Add `CHANGELOG.md` `[Unreleased]` entry | T1-T8 | XS | 3 | yes |
| T12 | Remove 3 consumed BACKLOG entries (pipeline-goal-wrap-default, flow-goal-autoship-pattern, autorun-suitability-indicator) | — | XS | 3 | yes |
| T13 | Run `bash tests/run-tests.sh` — verify full suite green | T1-T12 | S | 4 | — |
| T14 | Manual S1-S6 smoke playbook (deferred to user post-PR if time-bounded) | T13 | M | 5 | — |

**Total estimated effort:** Wave 1 ~30 min (parallel) · Wave 2 ~45 min (parallel) · Waves 3-4 ~15 min · Wave 5 deferred = ~90 min net.

## Wave Sequencing

| Wave | Tasks | Order | Time |
|------|-------|-------|------|
| Wave 1 | T1 + T2 | parallel | 30 min |
| Wave 2 | T3, T4, T5, T6, T7, T8 | parallel (all skill-file edits + flow-card) | 45 min |
| Wave 3 | T9, T10, T11, T12 | parallel (housekeeping) | 10 min |
| Wave 4 | T13 (test suite) | sequential after waves 1-3 | 5 min |
| Wave 5 | T14 (manual smoke) | sequential after wave 4 | deferred to user |

## Open Questions

- **OQ1 (R5 mitigation):** Token-budget exhaustion risk on 4-gate chain — what's the recovery story when chain breaks mid-stream? Plan documents "user re-pastes /goal and resumes from next gate manually." Acceptable for v1.
- **OQ2 (D4 ambiguity):** Is `commands/flow-card.txt` the actual source-of-truth file in the MonsterFlow repo, or does it live elsewhere? Build wave 2 should `ls commands/flow*` to confirm before T8.

## Risks (from spec V3 + design analysis)

- **R1 (medium):** Multi-hop Skill-tool chain-invoke not previously exercised in this codebase. Mitigation: S4 smoke test validates dynamically; chain breaks at any hop fall back to user re-invoking next gate manually (graceful degradation).
- **R5 (medium):** Token-budget exhaustion on long chains. Documented in spec + /flow.
- **R-new (low, from integration designer):** GO_WITH_FIXES followups.jsonl ordering — followups MUST be written before chain-invoke to /build. Helper not involved; build wave should add explicit ordering note in `commands/check.md`.

---

## Codex Adversarial View (Phase 2b)

Codex ran against the synthesized design.md + spec + codebase. Verdict: **9 findings (4 High + 5 Medium)** — most about plan-vs-reality drift between the spec's claims and what the codebase actually does. Raw output at `plan/raw/codex-adversary.md`.

### Findings folded inline as design adjustments

**D15 — Helper accepts `AUTOSHIP_EVENTS_PATH` env var override (Codex #8)**
Tests need to redirect JSONL writes to `TMPDIR/...` for isolation. Helper reads `AUTOSHIP_EVENTS_PATH` env var; falls back to `dashboard/data/autorun-suitability-events.jsonl` when unset. Added to D7 contract.

**D16 — Manual `/check` writes `check-verdict.json` and `followups.jsonl` (Codex #3)**
Codex flagged: `/build` Phase 0c reads `check-verdict.json` to consume followups, but `commands/check.md` Phase 3 (manual path) only writes `check.md`. Sidecar extraction is autorun-only (`scripts/autorun/check.sh`). Under autoship, /check chains directly to /build; /build sees no sidecar; followups silently lost.

**Fix:** add explicit task to `commands/check.md` Phase 3 to write `check-verdict.json` from the synthesized verdict block AND emit `followups.jsonl` from the architectural findings, BEFORE chain-invoke fires. Both files must exist when /build starts.

New task T6b added below.

**D17 — Outcome row writer carved (Codex #4)**
Codex correctly noted: `commands/build.md` has no post-PR-merge logic. Merge detection + outcome emission lives in `scripts/autorun/run.sh`. The V3 spec's claim that build.md emits the outcome row doesn't match reality.

**Fix:** outcome event row emission is **out of scope for v1**. The `log-event --event-type outcome` subcommand is built and tested (AC8), but no skill emits it in v1. Future spec `autoship-outcome-instrumentation` (NEW BACKLOG) will wire the post-merge hook into either `scripts/autorun/run.sh` or a new git-post-merge mechanism. Halt rows are still emitted in v1 (gate skills emit them at halt sites).

AC8 stays — tests the subcommand contract; just doesn't get exercised at runtime in v1.

**D18 — Chain-invoke graceful degradation (Codex #1 + #2)**
Codex's load-bearing concern: the multi-hop `Skill(...)` mechanism is unproven; the syntax may not match the actual Claude Code API. R1 already acknowledges this. Add explicit fallback to the chain-invoke block: if the Skill invocation fails (tool not found, returns error, or chain stalls), the gate skill emits a halt-surface block with `reason=chain-invoke-failed` and stops. User can resume manually.

This makes the chain robustly degradable rather than silently inert. Updated D3 chain-invoke block accordingly.

**D19 — /check Phase 3 branch-specific autoship behavior (Codex #7)**
The existing `/check` Phase 3 has 3 branches: GO, GO_WITH_FIXES, NO_GO. Autoship behavior differs per branch:
- **GO:** chain-invoke `/build`
- **GO_WITH_FIXES:** ensure followups.jsonl exists (per D16), then chain-invoke `/build` (build wave 1 picks up followups)
- **NO_GO:** halt-surface + halt event; do NOT chain (per V3 §Chain-invoke rule)

T6 now explicitly handles all 3 branches.

**D20 — AC9 grep target update (Codex #5)**
AC9 in V3 spec says target file is `commands/flow.md` for the `## Autonomous Shipping (autoship via /goal)` anchor. D4 in design.md correctly identified flow.md is a `!cat` shim and the source-of-truth is `commands/flow-card.txt`. The spec's AC9 needs the target file corrected to `commands/flow-card.txt`.

This is a 1-line spec edit (or a `commands/flow.md` could ALSO get a documentation block for adopter-discoverability — both feasible). T8 will edit `commands/flow-card.txt`; spec AC9 row updated as part of design closure.

### Findings deferred to /check or /build

**Codex #6 — Autoship detection is LLM-only, not testable in shell.** R1 + S4 are the validated mitigation. /check + /build will discover empirically whether the LLM consistently performs the detection correctly. If S4 reveals systematic failures, V3.1 may add the `AUTOSHIP_EVENTS_PATH`-style state file for deterministic detection.

**Codex #9 — Stdlib-only YAML parsing.** Spec's tag handling needs only `tags: [a, b]` array form and `gate_mode: strict|permissive` string. A narrow regex-based YAML reader handles both safely. Helper docstring will document the narrow parsing scope. Not blocking; /build implements narrow parser.

### Updated task list (V3-after-Codex)

Added: **T6b** — `/check` Phase 3 writes `check-verdict.json` + `followups.jsonl` before chain-invoke fires (D16).

T6b depends on T6's broader edit; can land in same wave. No new test ACs needed (AC9 anchor table covers via `check-verdict.json` filename grep in /check.md prose).

### Bottom line on Codex view

Codex's findings break into two categories:
- **Plan-vs-reality drift** (Codex #1-#5, #7) — 5 findings, all addressed by D15-D20 inline.
- **Architectural limitations of Path B** (Codex #6, #8 partially) — R1 already documents; S4 validates dynamically.

The /build wave 5 manual smoke is the load-bearing test for the architectural feasibility of multi-hop chain-invoke. If S4 reveals chain-invoke doesn't work end-to-end:
- The helper script + render UX + option-c additions still ship correctly (deterministic, AC9 grep verifies)
- Chain-invoke remains in the prompt files but no-ops at runtime
- Fallback to manual gate invocation is graceful (each gate's own AUTORUN=1 check still works)

This is a deliberate "ship what's deterministic + best-effort the architectural unknown" approach. V3.1 follow-up handles whatever S4 reveals.

