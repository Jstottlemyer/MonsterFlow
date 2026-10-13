---
name: adversarial-review
description: Independently challenge a proposed engineering design or delivery plan against frozen intent, repository contracts and evidence; identify actionable failures and unsupported assumptions.
license: MIT
metadata:
  version: 0.3.2-draft
---

# Adversarial review

Use for an explicitly selected independent pressure test of a design or plan. Review the candidate as written against the same frozen intent, accepted decisions, exclusions, constraints, revision and evidence supplied to other reviewers. Establish those inputs before reviewing; a missing load-bearing input blocks only the affected conclusion. Keep the initial pass independent of other reviewers' conclusions where the review setup permits. If reports were already seen, disclose that limit.

Read [native criteria and selection](../engineering-index/references/native-criteria.md), the applicable stage/boundary references it selects, and [judge criteria](../engineering-index/references/native/judge.md) for evidence and severity calibration. Reuse these definitions; the adversarial role does not add a new persona roster.

Challenge load-bearing assumptions, contract-to-code mismatches, missing dependencies, unsafe task order, untestable verifier claims and algorithms that cannot satisfy the intended outcome. Trace a candidate defect to the relevant requirement and concrete source path, reachable behavior, persisted cohort or deployment overlap. A plausible risk without enough evidence remains an unresolved premise with the smallest useful proof, rather than a confirmed defect. Compare simpler approaches only within the same required outcomes and constraints; an alternate preference alone is not a blocker.

Return the reviewed intent/plan/source identities and loaded reference hashes; confirmed findings with consequence, evidence, smallest repair and affected readiness claim; necessary missing evidence; and rejected concerns or scope changes with reasons. If a supplied prior report exists, distinguish unique findings from independently corroborated duplicates after the initial pass. State when there are no additional findings. Preserve limitations, accepted decisions and unresolved disagreements. Do not strengthen acceptance or require later release evidence for a narrower review transition.

This wrapper adapts MF's optional separate adversarial design/plan check in commands/blueprint.md:191–229 and commands/check.md:172–180,254–272 at the pinned source in [provenance](../engineering-index/references/provenance.md). It performs judgment with the current host's tools; it copies no provider/authentication calls, native orchestration, wire schemas or automatic dispatch. Missing optional adversarial execution is disclosed as not run; it does not independently block unrelated delivery. Skill availability is not invocation, and a model verdict is neither executable proof nor permission for effects.
