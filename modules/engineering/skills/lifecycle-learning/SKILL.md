---
name: lifecycle-learning
description: Close an engineering session or review release observations with a useful handoff, non-obvious learning triage, and affected documentation drift checks; avoid automatic global updates.
license: MIT
metadata:
  version: 0.3.3-draft
---

# Lifecycle learning

Use for session wrap-up, a feature handoff, or a requested retrospective of observed release behavior. Summarize what changed, evidence supporting the current outcome, remaining work/holds, and the smallest useful next entry point. Keep a quick wrap short; a larger review is justified by actual unresolved work or new observations.

If release observations are available, compare them with the feature's acceptance and observation plan. Distinguish measured outcomes from expectations and unobserved runtime behavior. Record regressions, accepted risks that materialized, recovery limits, and open followups within the user's scope. Without observations, produce a handoff and disclose the gap; do not invent a successful release or require production access. MF supplies readiness and wrap disciplines, not a dedicated post-release orchestration stage.

Triage learnings using MF's reconstructibility filter: skip facts a future session could recover with a quick search or one source file. Capture non-obvious environment pitfalls, cross-cutting workflows, lost decision rationale, and useful behavioral corrections. Separate reusable lessons from temporary status and project-specific facts. One incident does not establish a universal rule. Nothing worth capturing is a valid result.

Before BOTH durable raw capture and lesson promotion, apply a goal/spec and repository scope/provenance filter. Every retained observation and lesson must tie to the specific local goal/spec implementation, appropriate source evidence and repository audience. Apply the same filter to coordinator input. Cross-project experience may prompt investigation but cannot be recorded as this project's observed experience; intentional cross-repo transfer requires separately approved, clearly attributed scope and destination. Omit excluded cross-project details from durable raw files and rejection logs.

Preserve capture → distillation → subsequent retrieval using the repo's existing knowledge conventions. When no convention exists, a portable default beside the relevant spec is `_raw/observations.md` for concise evidence-linked observations and `lessons.md` for distilled useful lessons. Capture observations during work when warranted; at wrap, inspect them before distilling. For a retrospective, reconstruct from existing reviews, fixes/tests, receipts and owner decisions, explicitly label retrospective sourcing and disclose missing contemporaneous capture. Do not invent raw history or duplicate transcripts/GitHub logs. Durable notes should omit secrets, personal context, operational task IDs and metering; retain context/applicability, uncertainty, evidence/version and decision rationale. Distilled lessons should cite observations and original evidence, distinguish retained/rejected candidates and remain discoverable from the spec/closeout. Nothing worth retaining is valid; do not create empty ceremony.

Optional coordinator input may add cross-task observations and candidate insights alongside worker/task evidence. Attribute owner decisions, coordinator observations/inferences and worker-verified facts separately; corroborate synthesis against source evidence, retain uncertainty and exclude unrelated/private orchestration. This is not a dependency on a supervisor, private chat or knowledge store.

Default to repo-local knowledge. External promotion to a developer-selected knowledge system requires explicit authorization for that destination and content; an available private store is not a required plugin dependency or an automatic export target. Local knowledge is informative and cannot authorize work. Do not introduce a wiki service, graph engine or logging framework. When requested, demonstrate bounded retrieval for a likely follow-up topic with citations and applicability limits; label it a test, not a real future spec invocation.

Choose the narrowest appropriate destination: decision rationale in project documentation, project conventions in applicable instructions, temporary status in the handoff, reusable procedure in a skill, personal preferences only in an available authorized memory mechanism. Preserve traceability to the observation and affected version. Prepare concrete proposed diffs before seeking any needed approval; apply already authorized local documentation updates. Never use wrap-up as authority to install hooks, change permissions/global instructions, write a vault, or publish/send messages.

Inspect affected docs for behavioral/default/configuration drift, dead references, and upgrade guidance needed by the actual change. Mark stale or unverified narrative clearly; do not reauthor the whole project story by default. Existing worktrees, uncommitted/stashed work, dependencies, and loose ends may be reported when they matter to continuation. Do not clean, reset, commit, push, close, archive, or remove them without applicable authorization.

Return draft lessons and source links, plus a concise request to the invoking coordinator or standalone developer for additional scope decisions, cross-task observations or contradictory evidence. If such input was already supplied, reconcile it without asking again. Record whether input was incorporated, explicitly had nothing to add, or was unavailable. Use one bounded reconciliation pass; unavailable input does not create a supervisor dependency or an endless loop.

Return a concise outcome/evidence handoff, unresolved decisions, useful learning candidates with destination and rationale, and affected doc changes or proposed diffs. Keep implementation facts and evaluation answers out of general skills. This skill adds no automatic telemetry, scheduled checks or external communication; requested repo-local capture and distillation are ordinary documentation updates.

Adapted from MF; see [provenance](../engineering-index/references/provenance.md) for source mappings and policy differences. [MIT notice](LICENSE).

## Native-derived review coverage

Before assessing the selected dimensions, read [native criteria and selection](../engineering-index/references/native-criteria.md) and its applicable references. Use the routing row for this skill; structural design changes require the design-quality lens, and persisted shape changes require data-model criteria. Record actual loaded reference hashes, the current intent/plan revision, applicability, findings and limits. These are model review questions, not execution authority.
