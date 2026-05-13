# Scalability Analysis — autorun-merge-policy

## Summary

Per-slug overhead is bounded constants (1 frontmatter read × 3 sources, 1 git hash-object, 1 banner render, 1 drift-check, 1 stat). None recurse, none touch network, none scale with spec content size. All sub-millisecond against autorun's `claude -p` calls (4-5 orders of magnitude larger).

The interesting questions: **noise floor**, **PR backlog ergonomics**, **audit retention**.

## Recommendation: ship as designed + 4 plan-level pins

Two scalability changes for /plan:
1. **Pin `spec_sha` capture to once-at-run-start** (cache in shell var, reuse at merge-call site)
2. **Coordinate release sequencing with `pipeline-autorun-final-status-render`** — either ship together or document triage-wall gap with soft batch-size ceiling

One scope-cuts deferral:
- Banner-noise reduction (Option B abbreviated banner) is a real-world annoyance at N≥50 but premature for v0.11.0; tag for follow-up after one month telemetry

## Constraints Identified

- **C1 (architectural):** `queue/<slug>/.manual-review` path assumes per-slug subdirectory; existing autorun layout may be flat (`queue/<slug>.spec.md`). Plan must verify.
- **C2 (contract):** `_gh_frontmatter_field` must short-circuit on closing `---` fence to keep per-slug cost bounded.
- **C3 (contract):** `spec_sha` capture once-at-run-start, cached, reused. AC#9's "at merge-call site" prose conflicts with body's "once at run start" — pin to once.
- **C4 (scope-cuts):** PR-backlog triage UX depends on `pipeline-autorun-final-status-render`. Sequence-coordinate or document gap.

## Open Questions

- **OQ1:** Is `queue/<slug>/` an actual directory in live autorun, or spec-side assumption? If flat layout, change touch-file path to `queue/.manual-review-<slug>`.
- **OQ2:** v0.11.0 hold for `pipeline-autorun-final-status-render` (combined release), or ship with documented gap? Lean: combine.

## Integration Points

- `_merge_policy.sh` inherits scale characteristics of `_gh_frontmatter_field` (must remain frontmatter-bounded).
- `autorun-batch.sh` drift-detector loop bounded by N.
- `run.sh` banner + `.manual-review` check + `git hash-object` once per run.
- `queue/run.log` +1 row/slug. No retention strategy today; flag separately as `run-log-rotation` backlog item.
- `pipeline-autorun-final-status-render` (sibling backlog) — actual mitigation for PR-backlog UX.

## Findings (v2 schema)

```yaml
- persona: scalability
  finding_id: scal-001
  severity: major
  class: architectural
  title: ".manual-review path assumes per-slug subdir; live layout is flat"
  body: "AC#14 + spec body specify queue/<slug>/.manual-review (subdirectory file). Existing autorun convention at run.sh:667 uses flat queue/<slug>.spec.md. If queue/<slug>/ is not created elsewhere, the touch-file existence check never fires and the escape hatch silently no-ops."
  suggested_fix: "Plan verifies whether queue/<slug>/ exists as a per-slug dir. If not, change touch-file path to queue/.manual-review-<slug> (flat) or have run.sh mkdir -p queue/<slug>/ before the dispatch check."

- persona: scalability
  finding_id: scal-002
  severity: minor
  class: contract
  title: "spec_sha capture site ambiguous between AC#9 and spec body"
  body: "AC#9 says forensic fields captured 'at merge-call site'. Spec body Definitions says 'taken once at run start (immutable for the run)'. Conflict."
  suggested_fix: "Pin to once-at-run-start. Cache in shell var SPEC_SHA at top of run.sh after $SPEC_FILE is set. Update AC#9: 'spec_sha captured once at run start; pr_number and merge_sha captured at merge-call site'."

- persona: scalability
  finding_id: scal-003
  severity: minor
  class: contract
  title: "drift detector + resolver scaling depends on _gh_frontmatter_field short-circuit"
  body: "Per-slug cost bounded only if helper stops at closing --- fence. Plan verifies existing behavior; one-line awk/sed fix if not."
  suggested_fix: "Plan verifies _gh_frontmatter_field at scripts/_gate_helpers.sh:49 short-circuits on closing fence."

- persona: scalability
  finding_id: scal-004
  severity: major
  class: scope-cuts
  title: "PR-backlog triage wall on first overnight after default flip"
  body: "Default flipped to pr means 10-100 slug overnight produces 10-100 open PRs with no morning summary tool. pipeline-autorun-final-status-render is in backlog but not in this spec. User hits a triage wall on first big overnight after v0.11.0 ships."
  suggested_fix: "Sequence-coordinate v0.11.0 with pipeline-autorun-final-status-render — ship together OR document the gap in CHANGELOG with soft batch-size ceiling (≤10) until summary lands. Add commands/autorun.md recipe: gh pr list -l autorun --json number,title,isDraft for interim manual triage."

- persona: scalability
  finding_id: scal-005
  severity: nit
  class: scope-cuts
  title: "Banner noise at N≥50 — abbreviated form a follow-up candidate"
  suggested_fix: "Defer. Tag for follow-up after one month of telemetry."

- persona: scalability
  finding_id: scal-006
  severity: nit
  class: scope-cuts
  title: "queue/run.log has no rotation strategy"
  suggested_fix: "Out of scope for this spec. Add to BACKLOG.md as run-log-rotation."
```
