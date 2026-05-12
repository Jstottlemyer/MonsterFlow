OVERALL_VERDICT: GO_WITH_FIXES

# CHECK: dynamic-roster-per-gate (Revision 2)

**Verdict:** GO_WITH_FIXES — 6 must-fix items (3 architectural + 3 security), all tractable as inline plan edits. No architecture rework required.

**Mode:** permissive (frontmatter) • **Iteration:** 1/3 • **Recycle cap reached:** no

## Reviewer Verdicts

| Dimension | Verdict | Key Finding |
|-----------|---------|-------------|
| Completeness | PASS WITH NOTES | All 23 ACs + 23 edge cases covered; 6 should-fix gaps (mostly test fixtures). |
| Sequencing | PASS WITH NOTES | M2 fix clean; **PRE-W2 over-blocks W2** (must-fix), **W4 tasks 9/11/13 missing task 0 dep** (must-fix). |
| Risk | PASS WITH NOTES | **PRE-W2 probe is single-context** (must-fix); top-3 risks: probe blind-spot, CLI response-shape drift, fresh-adopter `persona-rankings.jsonl` missing. |
| Scope-Discipline | PASS WITH NOTES | 5 scope-cut candidates (should-fix): task 22 redundant, Open Q#1 over-designed, task 23 legacy fixture speculative, D14 accumulate over-engineered, PRE-W2 artifact heavy. |
| Testability | PASS WITH NOTES | All block-class assertions mapped; 5 contract/test gaps (SEC-04 drift, wrapper, PRE-W2 evidence, fit_score identity, dashboard sentinel). |
| Security-Architect | PASS WITH NOTES | **3 sev:security findings** (must-fix): SEC-04 untested, wrapper-pivot fail-fast under-specified, `fit_tags` enum rejection untested. |

## Must Fix Before /build (6 items)

### Architectural (3)

1. **PRE-W2 gate over-blocks W2** — plan.md L78 says "tasks 0+1+2+3 must complete before W2" but Open Q#1 branched policy + wave-sequencer raw both say "W2 unaffected by PRE-W2." False serial dep idles ≈4 tasks.
   **Fix:** change L78 to "tasks 1+2+3 must complete before W2; task 0 must complete before W4."

2. **W4 command-file tasks (9, 11, 13) missing task 0 as explicit dep** — Open Q#1 + D5 both say PRE-W2 blocks "any dispatch code," but the dep table lists only `7`.
   **Fix:** change tasks 9, 11, 13 deps from `7` to `0, 7`.

3. **PRE-W2 probe is single-context** — Task 0 probes from one parent session. The entire D4-vs-pivot decision rests on one probe; if Agent `model:` is honored from Opus parent but not Sonnet parent (or vice versa), wrapper-pivot ships against incomplete evidence.
   **Fix:** Task 0 runs a 3-cell verdict matrix (Opus parent || Sonnet parent || `claude -p` headless); flaky-detection logic classifies "works from X, not Y" as flaky → halt, not YES.

### Security (3) [sev:security]

4. **[sev:security] SEC-04 has no dedicated test file** — Task 7 implements `assert_baseline_subset` recompute; no test asserts the drift-halt path (recorded ⊂ recomputed → distinct exit code → resolver refuses dispatch). This is the sole defense against post-write `tags_provenance.baseline` shrinking by attacker or careless author.
   **Fix:** add task 21a `tests/test-baseline-drift.sh` with paired fixtures (drift → halt-with-doc-string; equality → exit 0); wire into task 24.

5. **[sev:security] Wrapper-pivot fail-fast assertion is under-specified** — Open Q#1 (a) says wrapper parses response and fail-fasts on `model-id` mismatch, but: (i) absent `model` field behavior undefined (silent-pass = bypass), (ii) partial-match semantics undefined (substring vs byte-for-byte).
   **Fix:** extend Open Q#1 (a) to specify: (i) absent field → halt exit 5 with `[dispatch-precedence] response missing model field`; (ii) exact-string match OR documented alias table; (iii) every outcome appends to `plan/dispatch-precedence-evidence.md`.

6. **[sev:security] `fit_tags` enum rejection not tested** — Tasks 1+3 reference `$ref: tag-enum.schema.json` but no task exercises the rejection path. Adversarial author writing `fit_tags: ["; rm -rf /"]` or unknown `fit_tags: [auth]` is uncaught until runtime.
   **Fix:** extend task 3 (or add `tests/test-fit-tags-enum.sh`) asserting (a) unknown values fail schema, (b) shell-meta fails enum, (c) tag-enum schema change without persona-schema bump trips lockstep.

## Should Fix (24 items, summarized)

Non-blocking under permissive mode; defer to /build or carry into a follow-up cleanup. Grouped:

- **Tests (12):** A14 end-to-end dispatch grep, A11 stale-tags fixture, A4c three Codex modes, drift negative test, wrapper-script test, PRE-W2 evidence assertion, fit_score integer identity, dashboard sentinel exact-string, `fit_tags` author-drift CI lint, SEC-04 latency perf fixture, `persona-rankings.jsonl` file-absent test, AST-banlist scope to other helpers.
- **Contract (5):** task 17 numeric deps (not `W4`), task 23 add dep on task 16, task 8 doc-only clarification, wrapper response-shape parsing pinned, `tier_pin` batch-apply idempotence, mid-pipeline spec.md edit clause.
- **Docs (2):** PRE-W2 evidence file schema (header columns), A15 sibling-spec verification note.
- **Scope-cuts (5):** task 22 cut (`--explain` carved), task 23 legacy fixture trim, Open Q#1 wrapper-pivot pre-design trim, D14 accumulate simplify, PRE-W2 artifact lighten.

## Observations

- Plan is fundamentally sound — prior /check blockers (SEC-01..04, M1, M2) are addressed at architecture level. The 6 must-fix items are all task-additive or one-line dep-graph corrections, not redesigns.
- Permissive-mode classification applied: architectural + security are block-class; scope-cuts/contract/tests/docs are warn-class. Under strict mode, the 24 should-fix items would block; current mode treats them as carryable to /build with verdict-gated consumption.
- No `check-verdict` fences or reviewer-targeted directives detected in spec/plan content. No prompt-injection signal.
- Codex adversarial check: skipped this run (context budget; non-blocking per workflow).

## Recommended Path

Apply the 6 must-fix items inline to plan.md (≤1 hour of edits — 4 are one-line table changes, 2 are paragraph clarifications). Re-check is NOT required for these classes of fix under permissive mode; proceed directly to /build slice 2 (PRE-W2 + W1 schemas) once must-fix items land.

```check-verdict
{
  "schema_version": 2,
  "prompt_version": "check-verdict@2.0",
  "verdict": "GO_WITH_FIXES",
  "blocking_findings": [
    { "persona": "sequencing", "finding_id": "ck-a1b2c3d4e5", "summary": "PRE-W2 gate over-blocks W2 (plan.md L78 contradicts Open Q#1 branched policy)" },
    { "persona": "sequencing", "finding_id": "ck-f6a7b8c9d0", "summary": "W4 command-file tasks 9/11/13 missing task 0 (PRE-W2) as explicit dep" },
    { "persona": "risk", "finding_id": "ck-1a2b3c4d5e", "summary": "PRE-W2 probe is single-context; needs 3-cell verdict matrix (Opus || Sonnet || claude -p)" },
    { "persona": "security-architect", "finding_id": "ck-6f7a8b9c0d", "summary": "SEC-04 baseline-recompute drift-halt has no dedicated test file", "tag": "sev:security" },
    { "persona": "security-architect", "finding_id": "ck-2e3f4a5b6c", "summary": "PRE-W2 wrapper-pivot fail-fast assertion under-specified", "tag": "sev:security" },
    { "persona": "security-architect", "finding_id": "ck-7d8e9f0a1b", "summary": "fit_tags enum rejection path not asserted in any task", "tag": "sev:security" }
  ],
  "security_findings": [
    { "persona": "security-architect", "finding_id": "ck-6f7a8b9c0d", "summary": "SEC-04 baseline-recompute drift-halt has no dedicated test file", "tag": "sev:security" },
    { "persona": "security-architect", "finding_id": "ck-2e3f4a5b6c", "summary": "PRE-W2 wrapper-pivot fail-fast assertion under-specified", "tag": "sev:security" },
    { "persona": "security-architect", "finding_id": "ck-7d8e9f0a1b", "summary": "fit_tags enum rejection path not asserted in any task", "tag": "sev:security" }
  ],
  "generated_at": "2026-05-12T18:50:00Z",
  "iteration": 1,
  "iteration_max": 3,
  "mode": "permissive",
  "mode_source": "frontmatter",
  "class_breakdown": {
    "architectural": 3,
    "security": 3,
    "contract": 5,
    "documentation": 2,
    "tests": 12,
    "scope-cuts": 5,
    "unclassified": 0
  },
  "class_inferred_count": 0,
  "followups_file": null,
  "cap_reached": false,
  "stage": "check"
}
```
