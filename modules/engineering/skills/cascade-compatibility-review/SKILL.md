---
name: cascade-compatibility-review
description: Review a proposed multi-step landing when migrations, durable contracts, or separately deployed consumers make intermediate release states matter.
license: MIT
metadata:
  version: 0.3.1-draft
---

# Cascade compatibility review

Read-only by default. Use the proposed landing order, pinned source revisions, actual release hooks, and available evidence. Review the user's chosen sequence; do not redesign the stack or impose a wave template.

Follow what each landing actually triggers: migrations, seeds, generated clients, application releases, and independently deployed consumers. PR dependency order alone does not establish deployment order. Identify which old and new processes can coexist after each durable change, including when a later landing never happens.

For an invariant used to justify a safe intermediate state, inspect the concrete writes reachable through existing consumers. A named service or guarded endpoint is not evidence that all writers obey its policy. Trace only boundaries material to the release claim, and identify a reachable counterexample before reporting a defect.

Read checked-in migration SQL alongside datamodel and generated-client changes; they can have different deployment effects. Determine what a compatibility guard actually checks and what an override justifies. A fresh empty-database migration pass does not establish compatibility with existing rows or concurrent old writers. Schema-diff checks may omit SQL-only constraints, functions, or seed effects.

Check recovery at the durable boundary: application rollback does not undo completed migrations or seeds. Inspect transaction boundaries, partial-failure behavior, and migration retry prerequisites rather than assuming failure restored the previous state. Missing operational evidence is an explicit limitation, not permission to query or repair production.

Return a compact table for material transitions: source revisions, durable change, coexisting consumers/writers, supporting evidence or counterexample, and the condition to stop before the next step. Reuse existing review/evidence records; refresh only affected claims. End with the smallest unresolved decision and a short handoff naming the release observer, revision/outcome to record, and first meaningful verification signal.

Use PASS / FAIL / BLOCKED / NA for the reviewed compatibility claim: FAIL requires a concrete incompatible transition; BLOCKED means necessary evidence or a prerequisite is missing; NA requires an applicability reason. Preserve explicit holds. This review grants no merge, deploy, provider, or database authority and provides judgment, not deterministic enforcement.

Adaptation attribution and policy differences: [source note](../engineering-index/references/provenance.md). MIT notice: [LICENSE](LICENSE).

## Native-derived review coverage

Before assessing the selected dimensions, read [native criteria and selection](../engineering-index/references/native-criteria.md) and its applicable references. Use the routing row for this skill; structural design changes require the design-quality lens, and persisted shape changes require data-model criteria. Record actual loaded reference hashes, the current intent/plan revision, applicability, findings and limits. These are model review questions, not execution authority.
