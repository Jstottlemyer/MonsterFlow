OVERALL_VERDICT: GO_WITH_FIXES

# Check — spec-qa-terminal-formatting

**Date:** 2026-05-16
**Reviewers:** risk (opus) · scope-discipline (sonnet) · completeness (sonnet) · codex-adversary
**Gate mode:** permissive (frontmatter)
**Iteration:** 1 of 3
**Verdict:** GO_WITH_FIXES — 9 substantive findings, ALL applied inline to `design.md` V3

## Reviewer Verdicts

| Dimension | Verdict | Key Finding |
|-----------|---------|-------------|
| Risk | PASS WITH NOTES | T12 smoke needs isolation strategy (avoid polluting repo mid-PR); regex fixtures needed for false-positive prevention |
| Scope Discipline | PASS WITH NOTES | Wide plan (38 lines, 3 forms) is correct — D2 belongs in scope; T12 over-broad cut to 2 commands suggested |
| Completeness | PASS WITH NOTES (2 must-fix) | T8 spec amendment too vague; T12 needs minimal-invocation guidance |
| Codex Adversary | PASS WITH NOTES (7 findings) | T11/T10 sequencing bug; T8 write-target ambiguity; regex portability; OQ1 still open |

## Findings → Resolution

All findings were applied inline to `design.md` (now V3). The corrections are mechanical:

### Must Fix — applied inline
- **M1 (completeness):** T8 now ships an explicit unified-diff against the spec AC4 bash block.
- **M2 (completeness):** T12 spelled out as a per-command smoke playbook against an existing committed spec (`wiki-write-conventions/`) to avoid mutating state.

### Should Fix — applied inline
- **S1 (risk):** T8 fixture list expanded to include canonical-with-nested-bold + paren-form + raw-form fixtures.
- **S2 (risk):** T12 uses throwaway `_smoke-test-DELETE-ME-*` slugs and cancels before any mutating action.
- **C1 (codex):** T11 (CHANGELOG) sequenced BEFORE T10 (test suite); T10 verifies the final tree.
- **C2 (codex):** T8 explicit: edits `docs/specs/spec-qa-terminal-formatting/spec.md`, NOT `commands/spec.md`.
- **C3 (codex):** Regex `[^]*?` fallback replaced with the space-after-paren discriminator (portable BRE; canonical form has no space after `a)` while old form does).
- **C4 (codex):** Scope accounting corrected: 6 command files + 1 feature spec + 1 new test + 1 test-runner edit + 1 CHANGELOG edit.
- **C5 (codex):** T12 sequenced AFTER T10 (non-mutating render-only smoke).
- **C6 (codex):** OQ1 resolved — apply D3 inline at T8 (path (a) chosen).
- **C7 (codex):** Raw-indented anti-pattern scoped to known choice contexts (SCOPE_FILES only — CHANGELOG, README, docs/specs/ are excluded from the test).

## Conflicts Resolved

- **scope-discipline ("cut T12 to 2 commands") vs completeness ("T12 should cover all 6 per AC7"):** completeness wins. AC7 in the spec explicitly says "running each command interactively once" — that's the binding contract. T12's smoke playbook now covers all 6 commands but is non-mutating (per Codex C5) so the cost is bounded.

- **risk ("future indented prose false-positive risk") vs scope-discipline ("3-form normalization is right"):** both accommodated. Raw-indented anti-pattern is scoped to SCOPE_FILES only (Codex C7) — won't fire on docs/specs/ or CHANGELOG markdown that happens to have indented `a)` examples.

## Codex Adversarial View

Codex ran twice on this design — Phase 2b at /blueprint (4 corrections, applied to V2) and Phase 2b at /check (7 corrections, applied to V3). The cumulative pattern is the `feedback_codex_catches_plan_vs_reality_drift.md` memory firing: Codex consistently catches plan-vs-codebase drift (write-target ambiguity, regex portability, file-edit-vs-test-suite ordering, scope-accounting drift) that Claude reviewers — verifying plan-against-itself — systematically miss.

For an XS-S formatting refactor, having Codex catch 11 substantive issues across two gates is high signal that this kind of work benefits from adversarial reality-check even when the surface looks trivial.

## Must Fix Before Building (0 remaining)

All blockers from M1/M2/C1-C7 have been applied to `design.md` V3 inline. The V3 plan is ready to ship as-is.

## Should Fix (0 remaining)

All should-fix items also applied inline. No deferred items.

## Observations (non-blocking)

- The 3 anti-pattern test design (V3 AC4) is genuinely better than V2's single anti-pattern. Worth carrying the pattern (one anti-pattern per old form, with the discriminator anchored at a divergent character) to future spec formatting tests.
- This session demonstrated the pipeline's value end-to-end: V1 spec made a fabricated claim → /spec-review V1 caught it → V2 pivot → /blueprint surfaced a discovery-count gap → V2 design → /check + Codex surfaced sequencing + ambiguity → V3 design. 3 revisions across 4 gates, ~50 minutes total, ending with a build-ready plan that's mechanically unambiguous.
- The `pipeline-user-wait-time-metric` and `autorun-suitability-indicator` backlog items captured earlier in this session would have produced concrete numbers for this exact case: ~50 min of /spec→/check time. Autorun would have spared most of it.

```check-verdict
{
  "schema_version": 2,
  "prompt_version": "check-verdict@2.0",
  "verdict": "GO_WITH_FIXES",
  "blocking_findings": [],
  "security_findings": [],
  "generated_at": "2026-05-16T07:35:00Z",
  "iteration": 1,
  "iteration_max": 3,
  "mode": "permissive",
  "mode_source": "frontmatter",
  "class_breakdown": {
    "architectural": 0,
    "security": 0,
    "contract": 4,
    "documentation": 2,
    "tests": 2,
    "scope-cuts": 1,
    "unclassified": 0
  },
  "class_inferred_count": 0,
  "followups_file": null,
  "cap_reached": false,
  "stage": "check"
}
```

All 9 findings were applied inline to `design.md` V3 in the same session, so `blocking_findings[]` is empty and `followups_file` is `null` — no findings deferred to /build.

## Next

Ready for `/build`. The V3 plan is mechanically unambiguous; a build agent can execute T1-T12 in the new wave order without further clarification.

```
Approve to proceed to /build?

- **a)** Go — proceed to /build with V3 plan as-is
- **b)** Hold — pause and discuss before /build
```

My lean: **(a) Go**. All blockers from /check have been folded into V3 inline. The plan is build-ready.
