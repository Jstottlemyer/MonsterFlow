---
name: engineering-index
description: Route engineering lifecycle tasks to focused feature-definition, design, planning, build, review, landing, or learning skills; preserve proportionate scope and existing authority.
license: MIT
metadata:
  version: 0.3.2-draft
---

# Engineering index

Use at task entry, after a material change in approach, and before claiming completion. Inputs: the original request and acceptance criteria, explicit exclusions, project instructions, current stage, base/candidate revision or working diff, and available evidence. Missing requirements or artifacts needed for a decision mean BLOCKED for the affected claim; do independent work within the known scope. A concise task can route directly from intent: do not require a full lifecycle for an ordinary small change.

Record a short route: stage, affected behavior, realistic risk, selected reviews, and required validation commands with their source. Read project rules and actual scripts; do not invent a universal build/test/lint command or treat MF's self-tests as another project's suite.

| Stage / applicability | Selected skill or required review |
|---|---|
| New/changed external integration, platform availability or UI-to-API premise | [feature-definition](../feature-definition/SKILL.md) requirements/ambiguity/gaps/feasibility, then applicable design integration and plan sequencing/risk/testability before dependent readiness |
| Define a feature or review a material spec | [feature-definition](../feature-definition/SKILL.md) |
| Resolve feature architecture and affected contracts | [feature-design](../feature-design/SKILL.md) |
| Plan feature delivery or assess plan readiness | [delivery-plan](../delivery-plan/SKILL.md) |
| Implement an authorized feature plan | [feature-build](../feature-build/SKILL.md) |
| Requested review or changed material structural design, trust, wiring, failure, capacity, dependency boundary | [boundary-risk-review](../boundary-risk-review/SKILL.md) |
| Explicitly selected independent design/plan challenge | [adversarial-review](../adversarial-review/SKILL.md) |
| Reconcile separately performed review reports | [review-synthesis](../review-synthesis/SKILL.md) |
| Proposed landing/release or rollout handoff | [landing-readiness](../landing-readiness/SKILL.md) |
| Session wrap, observed release retrospective, or affected documentation handoff | [lifecycle-learning](../lifecycle-learning/SKILL.md) |
| Every code change: planned approach and final diff | [scope-review](../scope-review/SKILL.md) |
| Reported defect or proposed repair; risky behavior changes whose test evidence needs scrutiny | [regression-proof-review](../regression-proof-review/SKILL.md) |
| Before any claim that a repair or code change is complete | [repair-completion-review](../repair-completion-review/SKILL.md) |
| Proposed multi-step landing with migrations, durable contracts, or separately deployed consumers | [cascade-compatibility-review](../cascade-compatibility-review/SKILL.md) |

Read only skills relevant to the current stage and claim, reusing existing artifacts. Missing optional planning artifacts are not grounds to block a well-defined small change. Select only additional lenses justified by the changed boundary: identity/authorization, concurrent state, payments/side effects, persisted data/contracts, or UI behavior. Use applicable project skills when available; record their exact paths and why selected. A missing required skill or necessary expertise is BLOCKED, never silently waived. Optional absent lenses are disclosed; do not manufacture new skills or run every review by default.

Use [specialist applicability](references/applicability.md) when a material boundary changes and [decision continuity](references/decisions-and-handoffs.md) at material review/stage handoffs. The focused definition/design/plan modules also expose these contracts for direct use.

Baseline: preserve the original scope without expansion or silent cuts; inspect the whole task diff; run project-required and proportionate affected checks; verify original acceptance criteria with fresh evidence. Use the runtime's native read, diff, test, and reporting tools. A model review adds judgment, not an executable test result. Loading this index grants no install, provider-write, commit, merge, or deploy authority and does not make invocation automatic.

For review findings, require an intended-contract violation and reachable path, persisted cohort, or concrete version overlap before calling a blocker. Record necessary missing evidence separately; neither unchecked absence nor reviewer silence proves PASS. Preserve resolved policy decisions unless current evidence contradicts their premise.

Output: route and evidence ledger; each selected review's PASS / FAIL / BLOCKED / NA and rationale. PASS requires all applicable required reviews and checks to pass. FAIL records confirmed unmet requirements; BLOCKED records missing required evidence/resources. NA needs a concrete applicability reason and cannot waive baseline scope review for code changes. Stop the completion claim on any required FAIL/BLOCKED; surface the smallest unresolved decision without broadening the assignment.

Draft provenance and proposed policy differences: [source note](references/provenance.md). Bundle version: `0.3.2-draft`.

## Native-derived review coverage

Before assessing the selected dimensions, read [native criteria and selection](references/native-criteria.md) and its applicable references. Use the routing row for this skill; structural design changes require the design-quality lens, and persisted shape changes require data-model criteria. Record actual loaded reference hashes, the current intent/plan revision, applicability, findings and limits. These are model review questions, not execution authority.
