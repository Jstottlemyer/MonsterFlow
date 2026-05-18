OVERALL_VERDICT: GO_WITH_FIXES

# Check — autonomous-shipping-defaults

**Date:** 2026-05-17
**Reviewers:** risk:opus · scope-discipline:sonnet · completeness:sonnet + codex-adversary (Phase 2b)
**Gate mode:** permissive (frontmatter)
**Iteration:** 1 of 3

## Verdict: GO_WITH_FIXES

3 Claude reviewers + Codex. All 4 converged on 3 architectural findings that need inline resolution at /build wave 1. Per permissive-mode routing, architectural findings flow as `target_phase: build-inline` followups — /build picks them up automatically.

### Reviewer verdicts

| Dimension | Verdict | Headline |
|-----------|---------|----------|
| risk (opus) | PASS WITH NOTES | 3 must-fix: AC9 spec-amendment task missing; Wave 2 canonical-block drift risk; D18 contradicts D3 |
| scope-discipline (sonnet) | PASS WITH NOTES | D17 outcome-row carve creates "tested-but-never-emitted" subcommand; Wave 5 deferral ambiguity |
| completeness (sonnet) | PASS WITH NOTES | AC9 grep table omits `[AUTOSHIP-HALT]` marker; D20 spec-edit task not assigned to any T |
| codex-adversary | NO_GO | Convergent on 3 highs: D18 unimplementable as written; AC9 spec mismatch; Wave 2 unsafe parallelism |

## Convergent Architectural Findings (3 — route as build-inline followups)

### ck-a92c75b0e1 — AC9 spec target mismatch (flow.md vs flow-card.txt)
**Convergence:** risk MF1 + completeness CMP-002 + codex #2.
**Problem:** Spec V3 line 369 AC9 row 6 target is `commands/flow.md`. D4 + D20 in design.md correctly identified the source-of-truth is `commands/flow-card.txt` (flow.md is a `!cat` shim). T8 edits flow-card.txt but no task amends the spec's AC9 row.
**Fix at build wave 1 (T15 NEW):** Add explicit task to amend `docs/specs/autonomous-shipping-defaults/spec.md` line 369 AC9 row 6: change `commands/flow.md` → `commands/flow-card.txt`. Must land before T13 (test suite). 1-line edit.

### ck-d18f3a7c45 — Wave 2 canonical-block drift risk
**Convergence:** risk MF2 + codex #3.
**Problem:** D3 requires the autoship-detection and chain-invoke blocks to be byte-identical across 4 gate-skill files. Wave 2 dispatches 4 parallel agents to edit these files. AC9 only greps anchor strings, not block content — semantic drift (different trigger regex, different fallback language) passes AC9 silently.
**Fix at build wave 1:**
- **Option A (recommended):** One single agent (Wave 1.5, between Wave 1 and Wave 2) writes the canonical block content to a fragment file (`commands/_prompts/autoship-detection.md` and `commands/_prompts/autoship-chain-invoke.md`). Wave 2 agents copy those fragments verbatim into their assigned skill file. Add a Tier-1 test: extract sentinel regions from all 4 files, compare byte-for-byte. T2 gains AC14.
- **Option B (acceptable):** Serialize T4-T7 (one after another, not parallel). Slower but eliminates drift risk.

### ck-7c4b8e9f12 — D18 contradicts D3 (chain-invoke final-action vs fallback)
**Convergence:** risk MF3 + codex #1.
**Problem:** D3 says `Skill(...)` MUST be the final action. D18 says "if Skill fails, emit halt-surface block + log halt event." Both can't be true — once Skill is the final action, there's no post-call opportunity to emit fallback.
**Fix at build wave 1:** Resolve via re-language. The chain-invoke pattern becomes: emit a "manual-resume" line as a visible stdout signal IMMEDIATELY BEFORE the Skill call, then invoke Skill. If Skill call returns control (tool not found, error), the next assistant turn will see the manual-resume marker as the last user-visible signal and the user can resume manually. Halt-row write happens at the NEXT gate's autoship-detection if it sees the chain didn't progress.

Update D3 block to:
```
If autoship-active = true at this gate's completion:
- Emit pre-handoff stdout marker: "[autoship] handing off to <next-gate> — if you see this without the next gate running, the Skill chain broke (paste /<next-gate> <slug> to resume)"
- Final action: Skill(skill="<next>", args="<feature-slug>")
```

The graceful-degradation guarantee is "visible failure signal before silence" not "logged halt event."

## Should-Fix Findings (routed as `target_phase: build-inline`, lower priority)

### ck-3e5d8a6f02 — T6b underspecified for /check artifact creation
codex #4 + completeness CMP-003. T6b says "write check-verdict.json + followups.jsonl" without naming the deterministic extractor or schema validation step. Build wave 1 should pin: `/check` manual path uses the same fence-extractor that `scripts/autorun/check.sh` already implements (or equivalent inline logic), validates schema, writes both files, then chains.

### ck-9f8c1b2d70 — Spec text still has outcome-row mention; D17 cleanup incomplete
codex #5 + scope-discipline SD-01 + completeness CMP-004. Spec lines 123 and 276 still say happy-path emits outcome rows. D17 carved this. Build wave 1 should:
- Edit spec.md happy path step 9 to clarify: "outcome event row deferred to v1.1 (`autoship-outcome-instrumentation` follow-up)"
- Edit spec.md §JSONL event schema to mark outcome rows as "subcommand contract only in v1"
- T12 must ALSO add `autoship-outcome-instrumentation` to BACKLOG.md (not just remove the 3 consumed entries)

### ck-4b2a9e8c61 — S4 only validates single-hop chain
codex #6. S4 verifies `/spec-review → /blueprint`. The 4-hop architecture (R1, R5) needs additional smoke beyond S4. Build wave 5 (manual smoke, deferred to user) should add S4b: paste /goal, wait for full chain, observe whether all 4 `[autoship]` markers appear in sequence.

### ck-additional-completeness items (fold into wave 1 with above):
- **`[AUTOSHIP-HALT]` marker missing from AC9 table** (completeness CMP-001) — add 4-file row to AC9 + grep assertion in T2
- **T6b missing test coverage** (completeness CMP-003) — add `check-verdict.json` filename grep to AC9 OR explicit fixture
- **AC3 checkbox fixture risk** (completeness CMP-005) — clarify in T2 prompt that checkbox fixture is required
- **OQ2 (flow-card.txt location) resolved** — mark done, remove from open questions

## Findings classification

- **architectural:** 3 (ck-a92c75b0e1, ck-d18f3a7c45, ck-7c4b8e9f12)
- **contract:** 1 (ck-3e5d8a6f02)
- **documentation:** 1 (ck-9f8c1b2d70)
- **tests:** 1 (ck-4b2a9e8c61) + completeness side-issues
- **security:** 0

Per permissive mode: architectural findings flow to followups.jsonl with `target_phase: build-inline`. /build wave 1 picks them up.

## Accepted risks (proceed-with-eyes-open)

- **R1/R5 (multi-hop chain-invoke):** the architectural validity of 4-hop Skill chain remains unverified at /check time. We're shipping deterministic UX (helper + render + option-c) PLUS best-effort chain-invoke. If chain doesn't work in practice, the deterministic UX still ships and the chain becomes a no-op (each gate's manual approval prompt fires normally). Graceful degradation is the design choice.

- **D17 outcome row writer carved:** v1 ships tested-but-never-emitted `log-event outcome` subcommand. AC8 documents this as "helper API contract." `autoship-outcome-instrumentation` BACKLOG entry tracks the runtime wiring.

- **S4 single-hop only:** multi-hop is post-merge user validation. If S4b reveals systematic failures, V3.1 fold adds deterministic state file (Path C from V1 review).

## /build prep checklist (carried into wave 1)

Build agent dispatching wave 1 MUST:
1. Add task T15: amend spec.md AC9 row 6 to `commands/flow-card.txt` (resolves ck-a92c75b0e1).
2. Insert Wave 1.5: write `commands/_prompts/autoship-detection.md` + `autoship-chain-invoke.md` canonical fragments. Wave 2 agents copy verbatim (resolves ck-d18f3a7c45 Option A).
3. Update D3 block per ck-7c4b8e9f12 fix language. Each gate skill's chain-invoke now emits pre-handoff marker line, then Skill() call.
4. Resolve all 6 findings inline in their wave. Mark addressed via `scripts/build-mark-addressed.py` post wave-final commit.

---

```check-verdict
{
  "schema_version": 2,
  "prompt_version": "check-verdict@2.0",
  "verdict": "GO_WITH_FIXES",
  "blocking_findings": [],
  "security_findings": [],
  "generated_at": "2026-05-17T05:30:00Z",
  "iteration": 1,
  "iteration_max": 3,
  "mode": "permissive",
  "mode_source": "frontmatter",
  "class_breakdown": {
    "architectural": 3,
    "security": 0,
    "contract": 1,
    "documentation": 1,
    "tests": 1,
    "scope-cuts": 0,
    "unclassified": 0
  },
  "class_inferred_count": 0,
  "followups_file": "docs/specs/autonomous-shipping-defaults/followups.jsonl",
  "cap_reached": false,
  "stage": "check"
}
```

[AUTORUN + /goal] GO_WITH_FIXES with 3 architectural + 3 should-fix findings — all addressable inline in /build wave 1. Proceeding to /build per autoship semantics.
