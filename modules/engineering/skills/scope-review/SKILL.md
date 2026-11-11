---
name: scope-review
description: Check a code-change plan or final diff against the original request, flagging unjustified additions and silent removal of required behavior.
license: MIT
metadata:
  version: 0.3.1-draft
---

# Scope review

Trigger: every code change, before implementation choices settle and again on the final diff. Independently usable. Inputs: original request, acceptance criteria and exclusions, approved clarifications, project rules, proposed approach or full base-to-candidate diff including uncommitted/untracked task files. If these cannot establish the intended boundary, report BLOCKED for the uncertain part.

1. Restate the original outcome and explicit exclusions briefly. Treat later approved changes as amendments with their source; a review suggestion is not approval. Preserve all requested behavior. Do not redefine the assignment as a smaller MVP or add reasonable-sounding features.
2. Map each changed behavior and dependency to a requirement or an indispensable enabling fix. For an enabling fix, explain the concrete failure that prevents the original outcome, why this change is needed, and the smallest practical boundary. File count alone does not prove scope creep; required callers, fixtures, and migration steps can be in scope.
3. Flag bundled cleanup/refactors, speculative abstraction/configuration, unrelated dependencies, and optimization without an in-scope need. Also check missing acceptance criteria, weakened tests, disabled behavior, and compatibility obligations. Do not cut proportionate tests, documentation, or necessary correctness to make a diff look smaller.
4. Distinguish a confirmed blocker to the original task from an independently discovered issue. Record unrelated findings separately for later consideration; do not repair them or turn them into new completion requirements. Necessary correctness follows the affected contract, not an imagined product roadmap.

Output: PASS / FAIL / BLOCKED / NA; request-to-change mapping; each finding with file/line or plan step, requirement, concrete consequence, and narrow disposition. PASS means the reviewed boundary satisfies the original scope with justified enabling work. FAIL means evidenced expansion or omission. BLOCKED means the boundary or necessary evidence is unresolved. NA applies only to an independently invoked task with no proposed or actual code change, with a reason.

Stop before implementing an unresolved scope change or declaring completion on FAIL/BLOCKED. Surface the smallest decision when satisfying the original outcome needs added work, a changed contract, or removal of a requirement; elapsed time and model recommendations are not approval. Existing authorization for a necessary in-scope fix remains valid.

Proposed policy: explicit non-expansion **and** no silent scope cuts. This strengthens MF's scope-cut-oriented persona; it is not a claim about current `/build` enforcement. Draft `0.3.1-draft`; source attribution: [provenance](../engineering-index/references/provenance.md). Local [MIT notice](LICENSE) applies; source note is optional context, not a runtime dependency.

## Native-derived review coverage

Before assessing the selected dimensions, read [native criteria and selection](../engineering-index/references/native-criteria.md) and its applicable references. Use the routing row for this skill; structural design changes require the design-quality lens, and persisted shape changes require data-model criteria. Record actual loaded reference hashes, the current intent/plan revision, applicability, findings and limits. These are model review questions, not execution authority.
