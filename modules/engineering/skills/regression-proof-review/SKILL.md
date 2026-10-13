---
name: regression-proof-review
description: Review whether repair evidence demonstrates the reported defect and its correction, and whether mocks and boundary tests support the claims being made.
license: MIT
metadata:
  version: 0.3.1-draft
---

# Regression-proof review

Trigger: a reported defect/proposed repair, or a changed behavior whose test claims need scrutiny. Independently usable and read-only by default. Inputs: original request and affected contract, raw baseline and candidate artifacts, reported symptoms if any, test sources, exact commands/results, and runtime/dependency context. Preserve the original scope; neither add features nor silently cut requirements.

1. Label the mode. **Reported defect:** state the symptom, first violated invariant, and targeted repair claim. **Discovery/general review:** inspect the changed boundary for concrete failures; do not pretend a prior report or reproduction exists. A newly discovered issue becomes a repair target only within existing scope/authorization or an approved amendment.
2. For a repair, seek causal evidence: the same relevant test fails against the pre-fix implementation for the defect-specific assertion, then passes with the fix under comparable conditions. An import/setup/infrastructure failure is not a defect reproduction. If execution is unavailable or unauthorized, inspect the test and describe the predicted mechanism as unverified; BLOCKED applies to a required causal-proof claim. Do not fabricate red/green results or require new tests for low-impact changes without a meaningful behavior risk.
3. Trace real boundaries that can invalidate the proof. For identity, compare mocked users/tokens/ownership and denial behavior with the actual auth/client contract. For concurrency, control initiating versus current context, response ordering, sign-out/unmount, and applicable failure paths. For side effects, follow browser and server requests through same-origin proxies, middleware, and SDK behavior to the external destination. A flag read or intercepted browser hostname does not by itself prove all activity is read-only or isolated.
4. Check assertions observe affected behavior and would fail if the defect returned. Identify what each mock replaces and what remains real. Prefer a small deterministic schedule and faithful boundary over sleeps or a large mock that guarantees success. Inspect relevant negative/boundary cases, not every conceivable state. Preserve useful unchanged-path coverage.

When material tests are added or moved, verify collection/registration in the project’s normal CI/default command with actual runner list/collection/run evidence. A direct test pass or causal red/green result is separate from suite integration; a passing default suite does not prove it discovered that test. Auto-discovery needs evidence, not necessarily a runner edit. No new test is required for a low-impact change without meaningful behavior risk.

Output: PASS / FAIL / BLOCKED / NA; mode, revision/fingerprint, concrete failure scenario or repair invariant, causal evidence, mock fidelity, covered boundaries, and limitations. Distinguish observed results from code-based inference. PASS supports only the stated claims. FAIL requires a concrete defective behavior or invalid proof claim; BLOCKED means necessary artifacts/execution are missing. NA means no applicable repair/behavior-proof claim, with rationale.

Stop a repair-complete claim when required proof fails or is blocked. Do not weaken assertions, bypass auth, or execute provider/payment/production activity merely to obtain evidence. Keep unexpected issues separate and escalate the smallest missing prerequisite; do not expand scope to production architecture or unrelated cleanup. This review itself authorizes no edits or external actions.

Draft `0.3.1-draft`: causal proof and explicit side-effect/mocking limits are proposed refinements of MF test-quality/testability reviews. [Provenance](../engineering-index/references/provenance.md) is optional source context; [MIT notice](LICENSE).

## Native-derived review coverage

Before assessing the selected dimensions, read [native criteria and selection](../engineering-index/references/native-criteria.md) and its applicable references. Use the routing row for this skill; structural design changes require the design-quality lens, and persisted shape changes require data-model criteria. Record actual loaded reference hashes, the current intent/plan revision, applicability, findings and limits. These are model review questions, not execution authority.
