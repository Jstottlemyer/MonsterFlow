---
name: review-synthesis
description: Judge and synthesize separate engineering review reports against shared intent and evidence, preserving actionable findings, false alarms and material disagreements.
license: MIT
metadata:
  version: 0.3.2-draft
---

# Review synthesis

Use after separately performed reviews of the same candidate, or when explicitly asked to reconcile supplied reports. Pin the original intent, accepted decisions, exclusions, constraints, candidate revision and evidence identity. Record each report's role, reviewed revision and independence limits; reports from incompatible revisions cannot jointly certify the current candidate. Missing reports remain not run, not inferred passes. This skill does not launch reviewers or require a particular roster.

Read [judge criteria](../engineering-index/references/native/judge.md), [synthesis criteria](../engineering-index/references/native/synthesis.md), [port policy](../engineering-index/references/native-criteria.md) and [decision continuity](../engineering-index/references/decisions-and-handoffs.md). Use the two responsibilities in order: first assess and filter the reports against source evidence, then produce the unified actionable result. A supplied judge output can be reused when its evidence and revision are current; retain access to raw findings for material traceability.

Merge duplicate issues when they have the same cause and corrective action, preserving contributors and independent convergence. Distinguish unique contributions, false alarms, accepted risks and proposed scope changes. Test contradictions against authoritative intent and inspected facts; preserve both sides and the smallest unresolved decision when evidence cannot resolve them. Model counts or stronger rhetoric are not proof. A single evidenced defect survives a majority's silence; convergent unsupported claims remain unsupported.

Keep all material blockers and recommendations in the result with evidence, consequence, owner/decision route and concrete next action. Do not let an alternative plan, a steelman, or a reassuring summary silently remove original requirements or weaken safety/correctness prerequisites. Record which suggestions repair the current plan within scope and which would require new scope or authority. An unavailable optional reviewer is a limitation; missing evidence required by the actual acceptance contract blocks the affected claim.

Return one current conclusion for the named readiness claim, its reviewed revision and loaded reference hashes, prioritized deduplicated findings, report-to-finding dispositions, resolved disagreements and their rationale, unresolved dissent, coverage gaps and next actions. State when no material disagreement arose. Keep model judgment separate from executed checks and not-run evidence. Refresh affected conclusions when intent, plan or revision changes. Persist the result at the project's existing review destination under existing authorization; no new ledger is required.

The judge/synthesis definitions are existing native-derived references; this is a portable entrypoint, not additional native coverage or MF machine-contract compatibility. Source and host-policy distinctions are in [provenance](../engineering-index/references/provenance.md). No provider calls, automatic invocation, installation or landing authority is supplied.
