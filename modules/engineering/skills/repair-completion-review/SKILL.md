---
name: repair-completion-review
description: Review completion claims for a repair or code change against the final revision, original acceptance criteria, required checks, and fresh evidence.
license: MIT
metadata:
  version: 0.3.1-draft
---

# Repair completion review

Trigger: before claiming a repair or code change is complete; repeat after subsequent edits that affect the evidence. Independently usable and read-only by default. Inputs: original request/acceptance criteria and exclusions, approved amendments, final task diff, review findings and dispositions, required checks from project rules/risk, and full available command evidence. Preserve original scope without expansion or silent cuts.

1. Bind the claim to the final state with evidence proportionate to the change. For a clean tracked tree, exact HEAD and base plus check context are normally sufficient; disclose relevant untracked/ignored inputs. For a dirty tree, identify relevant staged, unstaged, and untracked task changes and fingerprint that scope, including inputs that materially affect checks. Use full content-hash manifests, binary diff digests, or detailed tool/configuration records only when needed for material risk or reproducibility. A copy-only fix needs no elaborate ledger. If the evidence cannot identify the state supporting the claim, narrow it or report BLOCKED; do not expose secret values.
2. Verify each original acceptance criterion against behavior or a specific observable artifact. Passing tests do not automatically prove the whole request. Audit the final scope and findings: confirmed required defects must be resolved with evidence; rejected findings need reasons. Record unrelated discoveries separately without adding them to the assignment.
3. For every required check record command, cwd, tool/environment context, snapshot, exit status, result summary and output location. Use distinct execution states: **passed**, **failed**, **not run**, **skipped** (reason). Optional skips stay visible; required failed checks prevent PASS, and required not-run/skipped checks mean BLOCKED. Do not translate a missing tool, reviewer silence, cached log, or an agent's assertion into success.
4. Reconcile evidence with the final snapshot after writers settle. Any later edit makes affected checks stale; rerun them on the final state. Retain unaffected evidence only with a stated dependency rationale. No model guesses about execution. For a repair, verify required regression causality and relevant integration boundaries, alongside project-required build/type/lint/test checks where applicable.

When material tests are added or moved, verify collection/registration in the project’s normal CI/default command with actual runner list/collection/run evidence. A direct test pass or causal red/green result is separate from suite integration; a passing default suite does not prove it discovered that test. Auto-discovery needs evidence, not necessarily a runner edit. No new test is required for a low-impact change without meaningful behavior risk.

Output: PASS / FAIL / BLOCKED / NA, final-state identifier/fingerprint (and manifest location if needed), acceptance-criterion evidence, proportionate validation ledger, scope verdict, finding dispositions, and remaining limitations. PASS means applicable required checks, scope, and acceptance criteria are supported for that state. FAIL means confirmed unmet requirements/failed checks; BLOCKED means missing required evidence or prerequisites. NA needs a reason and cannot waive completion review for a code-change completion claim.

Stop on required FAIL/BLOCKED. If authorized to repair, work within the original scope with an explicit attempt bound (default three unsuccessful substantive fix/verify attempts for the same defect), then stop and report the last evidence and smallest unresolved decision. Do not count infrastructure retries as root-cause fixes or use them to evade the bound. This is a reporting stop, not permission to reset, discard work, redesign, merge, deploy, or write to providers.

Draft `0.3.1-draft`: freshness, explicit missing-evidence outcomes, and bounded repair are proposed policies; MF's current prompts/scripts do not uniformly enforce them. [Provenance](../engineering-index/references/provenance.md) is optional source context; [MIT notice](LICENSE).

## Native-derived review coverage

Before assessing the selected dimensions, read [native criteria and selection](../engineering-index/references/native-criteria.md) and its applicable references. Use the routing row for this skill; structural design changes require the design-quality lens, and persisted shape changes require data-model criteria. Record actual loaded reference hashes, the current intent/plan revision, applicability, findings and limits. These are model review questions, not execution authority.
