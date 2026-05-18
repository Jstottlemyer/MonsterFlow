OVERALL_VERDICT: GO

# CHECK: Plot Layer — Narrative Context for MonsterFlow

**Spec:** `docs/specs/plot-document/spec.md`
**Plan:** `docs/specs/plot-document/plan.md`
**Review:** `docs/specs/plot-document/spec-review/review.md`
**Gate mode:** permissive (frontmatter)
**Date:** 2026-05-11
**Reviewers:** completeness, sequencing, risk, scope-discipline, testability, security-architect (6 agents)

---

## Reviewer Verdicts

| Dimension | Verdict | Key Finding |
|-----------|---------|-------------|
| Completeness | PASS WITH NOTES | Phase 4 deferral undocumented; task done-criteria underspecified for edge cases |
| Sequencing | PASS WITH NOTES | Task 7 parallel/dependency contradiction; Tasks 8-10 unnecessarily delayed |
| Risk | PASS WITH NOTES | Diff-scope cold-start trust problem; annotation compliance has no runtime enforcement |
| Scope Discipline | PASS WITH NOTES | D7 path containment is future-proofing for deferred Phase 4; Task 3 on critical path without AC |
| Testability | PASS WITH NOTES | Missing scripted tests for status, [!DRAFT] ops, and Tier 1 diff-scope fast path |
| Security Architect | PASS WITH NOTES | Minor: chapter content as LLM input is prompt-injection surface; helper should validate section headings |

**6 of 6 reviewers passed.** No FAIL verdicts. Strong consensus on plan quality with targeted refinements needed.

---

## Must Fix Before Building (3 items — all resolved)

### MF1. Expand Task 2 test coverage to match helper surface area
**Sources:** testability (ck-a1b3c5d7e9, ck-b2d4f6a8c0), risk (ck-e4f6b72a09)
**Class:** tests | **Severity:** major

Task 2 enumerates tests for inject-stale, dedup, cap, remove, extract-links, and path traversal — but omits:
- **`status` sub-command** — data source for `/spec` Phase 0.2c callout and `/wrap` report line
- **`inject-draft` and `remove-draft`** — distinct code paths from stale operations
- **Dual-annotation scenario (D6)** — section with both `[!STALE]` and `[!DRAFT]`
- **Tier 1 diff-scope fast path** — the deterministic intersection of extract-links output with git diff paths

All four are pure deterministic logic, trivially testable, and high-impact if broken. AC26 promises scripted test coverage for annotation mechanics — the plan should enumerate all mechanics.

**Fix:** Expand Task 2 description to include: `status` validation, `inject-draft`/`remove-draft`, dual-annotation injection, and a Tier 1 diff-scope intersection test case (fixture chapter + mock diff → correct chapter selection).

### MF2. Demote D7 path containment to deferred TODO
**Sources:** scope-discipline (ck-b82f4c9a10), security-architect (ck-1a2b3c4d5e, ck-6f7e8d9c0b)
**Class:** scope-cuts | **Severity:** major

D7 adds path containment (absolute path rejection, `..` traversal, `realpath` symlink check, URL-scheme rejection) to the link extraction helper. The plan's own rationale says this "future-proofs for Phase 4 CI gate" — but Phase 4 is explicitly deferred. The current threat model is a single developer running locally on their own repo. This inflates Task 1 size, adds a dedicated test case in Task 2, and creates a design decision requiring documentation, all for a feature that may never ship.

**Fix:** Remove D7 scope from Task 1. Add a one-line comment `# TODO: add path containment when Phase 4 CI gate ships` in `extract-links`. Remove the path-traversal test case from Task 2. If retained despite this recommendation, at minimum anchor containment to `git rev-parse --show-toplevel` (not cwd) and reject URL-scheme links.

### MF3. Fix Task 7 parallel/dependency contradiction and merge into Task 6
**Sources:** sequencing (ck-a3e7f10b21), risk (ck-f103de8c56)
**Class:** contract | **Severity:** major

Task 7 has `Depends On: 6` and `Parallel: Yes (with 6)` — these are contradictory. Task 7 modifies the same file (wrap.md) that Task 6 modifies and needs the Phase 2d section to exist first. The line-number references ("wrap.md lines 13/19/22") will be stale after Task 6's edits.

**Fix:** Merge Task 7 into Task 6. Replace line-number references with semantic anchors ("the phase enumeration in the wrap.md header block" and "the quick-mode skip list"). Also cover wrap-quick.md, wrap-full.md, and wrap-insights.md if they reference phase lists.

---

## Should Fix (5 items)

### SF1. Remove Task 3 from Task 4's critical path
**Sources:** scope-discipline (ck-a3d1e7f021)
**Class:** scope-cuts | **Severity:** minor

Task 3 (staleness calibration examples) traces to a review watchlist suggestion, not an AC. It's on the critical path because Task 4 depends on it. If Task 3 slips, the entire `/plot` command is delayed.

**Suggested fix:** Fold calibration examples into Task 4 as part of normal prompt-writing work. Remove the dependency arrow.

### SF2. Decouple W3/W4 development from W2b dogfood gate
**Sources:** risk (ck-c9d1ae5320)
**Class:** scope-cuts | **Severity:** minor

The dogfood (Task 5) is on the critical path. If it blocks, W3 and W4 wait indefinitely. Tasks 6 and 8 can develop against synthetic fixtures.

**Suggested fix:** Change Task 6 dependency from "1, 5" to "1" with a note "merge blocked on 5." Allow development to proceed in parallel with dogfood.

### SF3. Simplify D4 Layer 1 checking — drop graphify-specific branching
**Sources:** scope-discipline (ck-d9f283ab56), risk (ck-d5e8a31b44)
**Class:** scope-cuts | **Severity:** minor

D4 introduces graphify-specific conditional branching the spec does not require, and graphify-out/ doesn't exist in this repo. The "skip Layer 1 when graphify absent" behavior silently loses coverage.

**Suggested fix:** Let the LLM naturally use graphify if available — no branching logic needed. Reserve graphify-specific integration for a follow-up if dogfooding reveals issues.

### SF4. Add runtime annotation lint/validation step
**Sources:** risk (ck-b72e0d4f18)
**Class:** contract | **Severity:** minor

The annotation-as-state architecture hinges on format consistency, but enforcement is purely documentary. The LLM could free-form an annotation instead of calling the helper.

**Suggested fix:** Add a `lint` subcommand to `_plot_annotations.py` that validates annotation format. Wire as post-write check in `/plot` and first step of `/wrap` Phase 2d.

### SF5. Tighten Task 4 done-criteria for spec edge cases
**Sources:** completeness (ck-d4a61b2c55, ck-e5f7a83d67, ck-f9012ce4ab)
**Class:** contract | **Severity:** minor

Task 4 description omits: Edge Case 6 (feature-removed handling), the three-step broken link procedure, and the OQ3 bootstrap `[!DRAFT]` default. A builder relying only on the plan could miss these.

**Suggested fix:** Expand Task 4 description to enumerate these three items explicitly.

---

## Observations (non-blocking)

1. **Tasks 8-10 are unnecessarily delayed by wave assignment.** Task 8 (Phase 0.2c) depends only on Task 1 and could start in W2/W3. Tasks 9-10 depend only on Task 4 and could start in W3. Moving them earlier shortens the overall timeline. (sequencing)

2. **Phase 4 deferral should be stated explicitly in the plan.** AC21-AC25 are not covered and the plan never says why. A one-line "Deferred to follow-up" section makes the omission auditable. (completeness)

3. **Manual smoke tests (Task 11) would benefit from a brief checklist.** Currently just a list of areas. Defining 3-5 observable outcomes per flow improves reproducibility. (testability)

4. **CHANGELOG entry for Phase 2d.** Review watchlist flagged adopter communication. Add a sub-bullet to Task 10. (completeness, risk)

5. **Prompt-injection awareness for chapter content.** Low risk for single-developer tool, but Tasks 4 and 6 should note that chapter content is untrusted LLM input. (security-architect)

6. **D6 dual-annotation ordering rule is unnecessary specificity.** Mandating `[!STALE]` before `[!DRAFT]` adds complexity for no user-visible benefit. Let natural insertion order stand. (scope-discipline)

7. **Annotation helper should validate section heading exists.** Before injection, check the target heading is present in the file. Prevents misplaced annotations from LLM hallucination. (security-architect)

---

## Accepted Risks

- **R2 (diff-scope false negatives):** The cold-start trust problem — early Plot Documents with sparse link coverage will miss behavioral drift in unlinked files. Mitigated by editorial link improvement over time and unscoped `/plot` interactive checks. The plan's mitigation is adequate for v1.

- **R4 (Phase 2d false positives):** Staleness calibration examples and evaluation at prose abstraction level are the right mitigations. Dogfood (AC8) validates calibration.

- **R5 (context consumption in /spec):** Low probability, low impact. Keyword filtering is an adequate mitigation.

---

```check-verdict
{
  "schema_version": 2,
  "prompt_version": "check-verdict@2.0",
  "verdict": "GO",
  "blocking_findings": [],
  "security_findings": [],
  "generated_at": "2026-05-11T20:45:00Z",
  "iteration": 1,
  "iteration_max": 3,
  "mode": "permissive",
  "mode_source": "frontmatter",
  "class_breakdown": {
    "architectural": 5,
    "security": 5,
    "contract": 7,
    "documentation": 5,
    "tests": 10,
    "scope-cuts": 11,
    "unclassified": 0
  },
  "class_inferred_count": 0,
  "followups_file": null,
  "cap_reached": false,
  "stage": "check"
}
```

---

## Consolidated Assessment

The plan is well-structured and addresses all spec-review findings. The annotation-as-state architecture is sound, the deterministic Python helper approach has unanimous designer support, and the wave structure correctly front-loads risk. All 6 reviewers passed. The three must-fix items are concrete and bounded: expand test coverage to match the helper's full surface area, descope D7 path containment to match the current threat model, and fix a notation contradiction in Task 7. None require architectural redesign — they're refinements that tighten the plan before build.

**GO.** All 3 must-fix items resolved in plan.md. Ready for `/build`.
