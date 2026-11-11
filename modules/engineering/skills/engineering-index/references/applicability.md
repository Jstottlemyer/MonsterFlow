# Conditional specialist applicability

Use this when the affected requirement or contract changes a material boundary. Select only relevant categories; NA needs a concrete reason, not a full checklist artifact. A local copy edit normally needs no specialist review. Use existing project expertise and evidence. Missing material decisions or project-required review are BLOCKED for the affected claim; an optional absent specialist is a disclosed limitation.

- **Trust, identity and tenancy:** threat actors and incentives, new inputs/outputs/permissions, authorization at the actual action and tenant/resource boundary, bypasses, fail-open/closed behavior, validation/encoding and abuse. Inspect sensitive data in storage, transit, responses and logs; secrets storage/rotation, sessions/cookies/lifetime/revocation, relevant cryptography, transport/certificate validation and at-rest protection. Require only safeguards justified by the threat, data and project policy.
- **Durable state:** existing-row migration, old/concurrent writers, invariants, retention/deletion, partial failure and recovery. A clean empty database does not settle an existing-cohort compatibility claim.
- **Users and operators:** applicable accessibility, offline/degraded states, support/diagnostics, audit/compliance obligations and affected documentation/examples, deprecation and launch coordination. Do not invent a regulatory obligation without relevant data or policy.
- **Interfaces and resources:** affected consumer/version contracts, language-specific state/time/type edges, realistic capacity and third-party capability/license/security risks.

For a changed security boundary, include suitable security review/evidence in the plan. Preserve project-required independent judgment; label self-review, fresh independent review, and supplied prior review honestly. Skill loading neither supplies reviewers nor authorizes delegation. No universal roster or full threat-model ceremony is required.
