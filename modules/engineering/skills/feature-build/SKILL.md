---
name: feature-build
description: Execute an authorized feature plan with explicit dependency handoffs, finding dispositions, per-step validation, and bounded recovery; adapt MF waves to available Codex tools.
license: MIT
metadata:
  version: 0.3.1-draft
---

# Feature build

Use to implement an authorized feature or resume its delivery plan. Read the current spec/plan, applicable project instructions, active holds, review dispositions, actual diff, and available checks. An implementation request can already authorize the work; do not add ritual approvals. Stop dependent work only on an unresolved required decision, explicit hold, or missing execution authority.

Keep one current task list tied to acceptance criteria. Distinguish followups that revise the plan, implement behavior, update documentation, or observe after build. A plan-revision item must be resolved before work that depends on it; a post-build observation is not automatically an extra feature. Do not consume stale MF sidecars as approval or fabricate pipeline artifacts to simulate orchestration.

Implement in dependency order and verify each meaningful handoff against its contract. Use native Codex tools and work serially unless delegation is available and authorized. If authorized workers are used, give them bounded tasks, relevant contracts, assigned writable scope, and a concrete verification signal. Settled writes and an inspected diff are needed before relying on their reports; a worker's DONE is not acceptance proof. Surface concerns, needed context, and blockers with the smallest next action.

After each material slice, compare actual behavior and diff with the intended outcome. Run the repository's required and proportionate affected checks using commands from its rules/scripts. MF's own test runner is not a universal project command. Missing tools, dry-run artifacts, or model review do not count as tests run. Record new evidence only for the state actually checked; later edits invalidate affected results.

When a required check fails, address the root cause within the authorized scope, then reverify affected behavior. Bound repeated unsuccessful substantive repairs (normally three for the same defect unless project/user instructions set a different bound), retain evidence, and report the unresolved prerequisite when exhausted. Do not weaken requirements to get green, reset/discard existing work, or escalate to provider/production access. Infrastructure retries are distinct from substantive fixes.

When material tests are added or moved, verify collection/registration in the project’s normal CI/default command with actual runner list/collection/run evidence. A direct test pass or causal red/green result is separate from suite integration; a passing default suite does not prove it discovered that test. Auto-discovery needs evidence, not necessarily a runner edit. No new test is required for a low-impact change without meaningful behavior risk.

For material stage handoffs, preserve the [decision and handoff contract](../engineering-index/references/decisions-and-handoffs.md) in the existing project/Dot record.

Return implementation status per required outcome, current revision/diff, checks actually run, findings resolved or still open, and remaining prerequisites. Reuse scope and completion reviews when available; disclose a missing required review instead of claiming it passed. Code completion, landing readiness, and deployment success are separate claims. Loading this skill grants no external publication, commit, merge, deploy, or rollback authority.

Adapted from MF; see [provenance](../engineering-index/references/provenance.md) for source mappings and policy differences. [MIT notice](LICENSE).

## Native-derived review coverage

Before assessing the selected dimensions, read [native criteria and selection](../engineering-index/references/native-criteria.md) and its applicable references. Use the routing row for this skill; structural design changes require the design-quality lens, and persisted shape changes require data-model criteria. Record actual loaded reference hashes, the current intent/plan revision, applicability, findings and limits. These are model review questions, not execution authority.

A material change in intended outcome or architectural premise requires the whole-plan reconciliation described in the native selection reference before dependent implementation resumes. Keep prior evidence historical, not competing active guidance.
