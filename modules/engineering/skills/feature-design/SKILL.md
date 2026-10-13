---
name: feature-design
description: Design a feature against its spec and existing architecture, resolving interface, durable-state, user-flow, integration, and failure contracts before implementation planning.
license: MIT
metadata:
  version: 0.3.1-draft
---

# Feature design

Use when feature-sized work needs design or when a changed contract creates a material architectural decision. Input: current intent/spec, relevant code and constraints, review dispositions, chosen approach, and open decisions. Keep ordinary local implementation choices proportional to their actual risk.

Start with the existing extension points and the user's chosen direction. Compare alternatives only for unresolved decisions; record why the chosen option fits present requirements. Reviewers' recommendations are proposals, not new product requirements. Resolve contradictions using the affected contract and evidence; retain unresolved product tradeoffs for the user. Multiple reviewers agreeing is corroboration, not proof or authority.

Close the contracts other work will rely on:

- **Interfaces:** callers, request/response or command shape, errors, defaults, validation, authorization ownership, and compatibility with current consumers. Ergonomics matter where misuse would be likely.
- **Durable state:** identifiers, lifecycle/state transitions, invariants, persistence and access patterns, existing-row migration, concurrent writers, and deletion/retention when relevant. Distinguish logical rollback from irreversible data changes.
- **User flow:** entry/exit paths, success, loading/empty/error states, recovery, and applicable accessibility behavior. Define behavior rather than prescribing visual polish outside scope.
- **Integration:** existing modules, release/configuration hooks, independently deployed consumers, and what remains valid when a dependency or later stage is unavailable.
- **Risk:** changed trust boundaries, realistic scale/resource constraints, side effects, and partial failure. Choose supporting evidence or a small spike for the highest uncertainty when authorized; a proposed experiment is not a result.

Give each material decision a rationale, consequence, and unresolved assumption. Do not fill a category that has no bearing on the feature. A useful design enables another implementer to work from the documented contracts without rediscovering hidden dependencies.

Return a compact architecture/contract note, decisions and alternatives considered, risks with consequences, and remaining prerequisites. Use the project's existing design artifact when writing is authorized. Design readiness is distinct from execution authorization and runtime validation. If the chosen design changes approved scope or removes acceptance criteria, surface the smallest decision before dependent implementation.

For a material changed boundary, inspect the relevant cues in [specialist applicability](../engineering-index/references/applicability.md); directly invoking this skill does not waive applicable specialist checks. For material review dispositions and stage transitions, use the [decision and handoff contract](../engineering-index/references/decisions-and-handoffs.md), preserving accepted risks and unresolved disagreements in the returned artifact.

Adapted from MF; see [provenance](../engineering-index/references/provenance.md) for source mappings and policy differences. [MIT notice](LICENSE).

## Native-derived review coverage

Before assessing the selected dimensions, read [native criteria and selection](../engineering-index/references/native-criteria.md) and its applicable references. Use the routing row for this skill; structural design changes require the design-quality lens, and persisted shape changes require data-model criteria. Record actual loaded reference hashes, the current intent/plan revision, applicability, findings and limits. These are model review questions, not execution authority.

A material change in intended outcome or architectural premise requires the whole-plan reconciliation described in the native selection reference before dependent implementation resumes. Keep prior evidence historical, not competing active guidance.

Before accepting dependent implementation topology, apply the external-premise and lifecycle-receipt trigger in native-criteria.md. Expose critical unproved prerequisites, obtain the smallest permitted proof before dependent implementation, and publish applicable review evidence early with the plan and every PR.
