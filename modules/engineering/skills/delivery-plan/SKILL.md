---
name: delivery-plan
description: Turn a feature design into ordered, verifiable work and review plan readiness against requirements, dependencies, testability, and recovery; avoid mandatory wave templates.
license: MIT
metadata:
  version: 0.3.1-draft
---

# Delivery plan

Use for feature implementation planning or a requested plan-readiness check. Input: current spec/acceptance criteria, design contracts, accepted review dispositions, repository rules, actual validation capabilities, and execution constraints. A small task can be one verifiable step.

Map every required outcome and accepted must-fix finding to concrete work and a verification signal. Include enabling migrations, configuration, wiring, user documentation, and fixtures only where the affected behavior needs them. Distinguish code-inspectable requirements from those needing execution, user observation, or an external environment. The planned evidence must be obtainable through permitted tools; do not require stdout inside a commit to establish a runtime result.

For each material task, name its outcome, dependencies, affected contract, and done signal. Expose prerequisites absent from the plan. Prefer coherent slices with stable handoffs. MF's data → behavior → hardening sequence is a useful prior, not a mandated three-wave pipeline: a single atomic change may be safer than separate landings. Plan behavior-critical tests with the work they protect; do not defer all verification to a final polish wave.

If splitting delivery, explain which contract closes at each step and which consumers rely on it. Identify intermediate states, including indefinite deferral of later work. Task execution order and deployment order may differ. Route a material durable/release overlap to cascade compatibility review when available; if missing, disclose the unresolved compatibility claim rather than asserting safety.

Review the plan for missing requirements, ambiguous bundled tasks, dependency cycles, inaccessible specialist/tool prerequisites, untestable acceptance criteria, and the riskiest irreversible step. Assess realistic blast radius and recovery. Proposed parallel work needs independent contracts and nonconflicting ownership; skill loading does not authorize delegation or supply workers. Serial execution remains valid.

Return a requirement → task → evidence mapping, ordered steps or waves, key dependencies, risk/recovery notes, and explicit unresolved decisions. A requested readiness verdict uses PASS / FAIL / BLOCKED / NA: FAIL for an evidenced coverage or sequencing defect; BLOCKED for a prerequisite needed to decide/execute; NA with a reason. Optional improvements remain separate. Review readiness does not approve a scope change, execution, commit, merge, or deployment. After a material change, reconcile one current authoritative plan across all downstream assumptions; recheck affected dimensions and preserve valid unaffected decisions.

For a material changed boundary, inspect the relevant cues in [specialist applicability](../engineering-index/references/applicability.md); directly invoking this skill does not waive applicable specialist checks. For material review dispositions and stage transitions, use the [decision and handoff contract](../engineering-index/references/decisions-and-handoffs.md), preserving accepted risks and unresolved disagreements in the returned artifact.

Adapted from MF; see [provenance](../engineering-index/references/provenance.md) for source mappings and policy differences. [MIT notice](LICENSE).

## Native-derived review coverage

Before assessing the selected dimensions, read [native criteria and selection](../engineering-index/references/native-criteria.md) and its applicable references. Use the routing row for this skill; structural design changes require the design-quality lens, and persisted shape changes require data-model criteria. Record actual loaded reference hashes, the current intent/plan revision, applicability, findings and limits. These are model review questions, not execution authority.

A material change in intended outcome or architectural premise requires the whole-plan reconciliation described in the native selection reference before dependent implementation resumes. Keep prior evidence historical, not competing active guidance.

Before accepting dependent implementation topology, apply the external-premise and lifecycle-receipt trigger in native-criteria.md. Expose critical unproved prerequisites, obtain the smallest permitted proof before dependent implementation, and publish applicable review evidence early with the plan and every PR.

## Repair the current plan

When review establishes a factual, coverage or sequencing defect and plan editing is already authorized, repair the current plan within that authority instead of returning only a grade. For a read-only readiness review, return the concrete proposed repair and affected recheck instead of mutating the plan. Update affected design decisions, tasks, dependencies and verification together, then recheck the dimensions the repair changes; retain valid unaffected evidence. Stop at an unresolved product decision or an effect outside the current authority and identify the smallest decision needed. Record the before/after defect and the reviewed revision. This adapts native commands/check.md:375–389 and blueprint.md:280–282; it supplies neither a generic execution loop nor new permission.
