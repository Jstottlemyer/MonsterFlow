---
name: boundary-risk-review
description: Review changed code or a design for concrete structural-design, trust-boundary, wiring, partial-failure, capacity, or dependency risks; select only lenses justified by the affected behavior.
license: MIT
metadata:
  version: 0.3.1-draft
---

# Boundary risk review

Read-only by default. Use for a requested code/design review or a material changed boundary. Inputs: intended contract and approved policy decisions, current source/diff and revisions, enabled paths/configuration, affected consumers, and available evidence. This supplements scope, regression-proof, and release compatibility reviews; it does not require every specialist lens on every change.

Select relevant lenses from [boundary lenses](references/boundary-lenses.md): structural design, trust/access, wiring/contracts, failure/recovery, capacity, or dependencies. For structural changes, load the native design-quality reference reached through the selection contract below; the short boundary-lens summaries do not replace its criteria. Read only the applicable sections. Trace the changed entry path to the real behavior and side effects, including adapters and independently versioned consumers that matter to the claim. A package/configuration entry alone proves neither correct wiring nor a defect; establish its intended use. A harmless version update need not adopt a new API.

Before promoting a blocker, identify the intended contract, a concrete violation, its realistic consequence, and an enabled path, persisted cohort, or actual version overlap that makes it reachable. A conditional mechanism may still be important: name the condition and supporting evidence. Unchecked absence is not PASS, and missing operational evidence is not a confirmed runtime defect. Classify necessary missing proof as BLOCKED for that claim; retain useful hypotheses as unverified questions. Do not reopen an explicitly resolved policy choice using stale narrative unless current behavior violates the approved contract or materially new evidence changes the premise.

Deduplicate by failure mechanism and next action. Adjudicate conflicting recommendations against evidence and user intent; distinguish evidence from reviewer consensus. Keep severity proportional to exploitability, affected users/data, reversibility, and contract impact. A topic label such as security or tests does not determine severity by itself. Do not demote an evidenced required defect merely because its fix is small, or promote optional hardening into a requirement.

Preserve material disagreements, both positions, source references, and resolution rationale under the [decision and handoff contract](../engineering-index/references/decisions-and-handoffs.md). Label self-review versus independent or supplied review honestly.

Return selected lenses and revisions, prioritized findings with file/line or design-step evidence, contract, reachability/condition, impact, confidence, and narrow disposition. A clean review states inspected boundaries and limitations. PASS / FAIL / BLOCKED / NA describes only the reviewed claim: FAIL for an evidenced violation, BLOCKED for required missing evidence, NA with a concrete reason. Review grants no edits or external actions; preserve scope and explicit holds.

Adapted from MF; see [provenance](../engineering-index/references/provenance.md) for source mappings and policy differences. [MIT notice](LICENSE).

## Native-derived review coverage

Before assessing the selected dimensions, read [native criteria and selection](../engineering-index/references/native-criteria.md) and its applicable references. Use the routing row for this skill; structural design changes require the design-quality lens, and persisted shape changes require data-model criteria. Record actual loaded reference hashes, the current intent/plan revision, applicability, findings and limits. These are model review questions, not execution authority.
