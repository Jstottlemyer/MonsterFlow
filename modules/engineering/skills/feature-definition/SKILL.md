---
name: feature-definition
description: Discover and define a feature or review its spec for ambiguous requirements, missing acceptance criteria, and feasibility before design; use a short path for small changes.
license: MIT
metadata:
  version: 0.3.3-draft
---

# Feature definition

Use for a new feature, a material feature revision, or a requested spec-readiness review. An ordinary bug fix or small well-defined edit does not need a feature interview. A missing MF constitution is context to disclose, not a prerequisite to invent.

Inspect relevant project instructions, existing behavior, related specs, supplied artifacts, and current work before asking questions. Ground stack and constraints in concrete files. Reconcile stale narrative with current code and approved decisions; a draft or old document is evidence of intent, not automatically the current contract. Keep unrelated backlog items separate. If several products are described, establish whether they share one outcome or need separate specs instead of forcing them into one lifecycle.

Before definition, make a bounded topic-based search of existing repo-local lessons at established spec/knowledge locations (including `lessons.md` beside related specs). Read relevant cited observations/evidence, assess context, age and applicability, and surface only useful prior lessons with citations. Do not scan all history or require a knowledge plugin. If an explicitly authorized external knowledge destination is available, it may supplement local retrieval; absence or lookup failure does not invent a prerequisite. Prior lessons inform questions and risks, never override the current contract or grant execution authority. Distinguish a retrieval demonstration from actual spec intake; no relevant knowledge is a valid result.

For **definition**, resolve only decisions that would materially change implementation or acceptance. Track what is known, assumed, or unresolved across scope, user flow, data/state, integration, failure cases, and acceptance. MF's numeric confidence gates are adapted here to explicit uncertainty; confidence is not measured probability or permission to advance. Use concise questions with recommendations when tradeoffs need user input; do independent work within the known scope. Respect an already chosen approach. Offer alternatives only when there is a real unresolved choice. Do not interview again about supplied answers.

Write or update a proportionate persistent spec at the project's established location when artifact creation is in scope. Capture the intended outcome, affected users, in/out boundaries, chosen approach and rationale, user-visible states, durable data, integration points, relevant failure/recovery behavior, and observable acceptance criteria. Number criteria when later traceability benefits. Separate requirements, assumptions, and open decisions. Do not turn every nonfunctional category into a requirement: add performance, accessibility, observability, or abuse constraints when required by the product or the affected boundary.

For **readiness review**, check which statements two implementers could interpret differently; missing defaults, state transitions, conflicting requirements, unavailable platform capabilities, and prerequisite work. Include affected operators or consumers when they materially change launch behavior. Map each critical gap to the requirement or concrete consequence. Optional future enhancements stay optional. Remove duplicates and concerns already resolved by the authoritative spec or approved decision; do not silently resolve a product conflict yourself.

Return the spec path or reviewed version, ready portions, decisions needed before design, and nonblocking assumptions. Use PASS / FAIL / BLOCKED / NA for a requested readiness claim: FAIL for an evidenced contradiction or unsatisfied requirement; BLOCKED for a decision or source necessary to judge it; NA with a reason. A draft with open questions may be useful without being approved. Definition or review grants no build, install, merge, or deploy authority; continue authorized work and preserve explicit holds.

For a material changed boundary, inspect the relevant cues in [specialist applicability](../engineering-index/references/applicability.md); directly invoking this skill does not waive applicable specialist checks. For material review dispositions and stage transitions, use the [decision and handoff contract](../engineering-index/references/decisions-and-handoffs.md), preserving accepted risks and unresolved disagreements in the returned artifact.

Adapted from MF; see [provenance](../engineering-index/references/provenance.md) for source mappings and policy differences. [MIT notice](LICENSE).

## Native-derived review coverage

Before assessing the selected dimensions, read [native criteria and selection](../engineering-index/references/native-criteria.md) and its applicable references. Use the routing row for this skill; structural design changes require the design-quality lens, and persisted shape changes require data-model criteria. Record actual loaded reference hashes, the current intent/plan revision, applicability, findings and limits. These are model review questions, not execution authority.
