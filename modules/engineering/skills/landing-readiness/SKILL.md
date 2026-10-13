---
name: landing-readiness
description: Assess an intended landing or release handoff using revision-bound acceptance evidence, prerequisites, migration/recovery limits, and post-launch observation; readiness does not authorize release.
license: MIT
metadata:
  version: 0.3.1-draft
---

# Landing readiness

Read-only unless the user has separately authorized an action. Use before a proposed PR landing, release, or feature rollout handoff. Inputs: intended sequence and holds, target revision/diff, acceptance evidence, unresolved findings and accepted risks, release configuration/hooks, and operational prerequisites. Code completion is one input, not proof of rollout success.

Establish what the next action actually changes: merge only, automatic release trigger, migration/seed, config switch, or consumer rollout. Confirm prerequisites from real project rules and hooks. Review compatibility of existing persisted state and old/new consumers when material; use cascade compatibility review if available. A PR order is not a deployment order, and an application rollback may leave durable changes intact.

Tie required checks and finding dispositions to the candidate state and target base. Identify a moved base, changed release inputs, missing reviewer/tool evidence, or stale results that invalidate the readiness claim. Preserve explicitly accepted optional risks and keep unrelated findings separate. Missing proof cannot be converted to approval by a model verdict, dry run, or absent reviewer.

For a material rollout, identify the observer, expected revision/cohort, first meaningful success/failure signal, observation point, and stop/recovery condition. Choose signals that establish requested behavior, not merely route/process availability. State migration retry and recovery limits when applicable, and what needs a separately authorized runtime or production check. This is a release observation plan; it does not query production, schedule monitoring, notify others, or execute rollback by itself.

If MF autorun artifacts are supplied, interpret them according to the pinned runtime and resolved policy. At source commit `53de60aa005126d5ee8a1b23ffc4f775c1cb5a25`, `validated` is reserved and falls back to PR-only; it is not a working runtime-validation gate. A requested/queued auto-merge is not a confirmed merge, and a successful merge is not deployment or runtime success. Do not copy MF's reset, token, notification, or merge machinery into a skill.

Return the next intended action, readiness verdict PASS / FAIL / BLOCKED / NA with evidence and limitations, prerequisites/holds, and a proportionate observation/recovery handoff. FAIL means an evidenced unmet requirement; BLOCKED means a required prerequisite or evidence is missing; NA needs a reason. Explicit merge/deploy/provider authority remains separate from the verdict; retain existing authorization without inventing a new approval gate. Record actual outcomes only after they are observed.

Adapted from MF; see [provenance](../engineering-index/references/provenance.md) for source mappings and policy differences. [MIT notice](LICENSE).

## Native-derived review coverage

Before assessing the selected dimensions, read [native criteria and selection](../engineering-index/references/native-criteria.md) and its applicable references. Use the routing row for this skill; structural design changes require the design-quality lens, and persisted shape changes require data-model criteria. Record actual loaded reference hashes, the current intent/plan revision, applicability, findings and limits. These are model review questions, not execution authority.
