---
gate_mode: permissive
gate_max_recycles: 2
---

# Pipeline Per-Gate Confidence Spec

**Created:** 2026-05-08
**Constitution:** none — session roster only
**Confidence:** Scope 0.95 / UX 0.95 / Data 0.92 / Integration 0.88 / Edges 0.92 / Acceptance 0.95
**gate_mode:** permissive
**gate_max_recycles:** 2

## Summary

Each multi-agent gate (`/spec-review`, `/plan`, `/check`) emits a 6-dimension confidence score (overall + per-dimension breakdown) into the verdict sidecar and the user-facing summary. Autorun surfaces the per-gate confidence in `run.log` and the final-status render as **passive observability only** — no halt threshold, no automated decision-making on confidence values until distribution data exists. Confidence becomes the same powerful signal at every gate that `/spec` already provides at the front of the pipeline.

## Backlog Routing

Carved from in-conversation request 2026-05-08 (user feedback that per-gate confidence visibility is a powerful signal). No prior backlog entry. Companion to `pipeline-granular-commits` spec also drafted this session — independent surfaces; either can ship first.

## Scope

**In scope:**
- Persona Output Structure addition: every reviewer persona at `personas/review/` and `personas/check/` adds a `## Confidence` section with 6-dimension scoring (Scope / UX-or-Design / Data / Integration / Edges / Acceptance, mapped to gate context).
- Synthesis aggregation: `personas/synthesis.md` (used by `/spec-review`, `/plan` synthesis, `/check` Pass 2) aggregates per-persona confidence into overall + per-dimension by averaging non-null scores. Codex adversarial output participates when present.
- Verdict sidecar field: `confidence: { overall: <float>, dimensions: {scope: <float>, ...} }` added to `check-verdict.schema.json`. Schema bump v2 → v3.
- `findings-emit` directive: write `confidence` block to `run.json` alongside existing fields.
- User-facing rendering: each gate's summary block surfaces overall confidence + per-dimension list (matching the `[Spec | Confidence: 0.72 | Need: edge cases]` line pattern from `/spec`).
- Autorun observability: `scripts/autorun/_emit_progress.sh` (or equivalent) reads `verdict.json.confidence.overall` per gate and appends one line per gate per slug to `queue/run.log`. Final-status render (handled by separate spec `pipeline-autorun-final-status-render`) reads the same fields.

**Out of scope:**
- Confidence-based halt gates in autorun (no `--min-confidence` flag, no `gate_min_confidence` frontmatter key). Pure observability in v1; revisit after ≥10 runs of distribution data.
- `/spec` itself — its 0.95 manual gate is already shipped (commit d548141, 2026-05-08).
- Cross-gate confidence trend (e.g. "spec was 0.94, plan dropped to 0.83 — investigate"). May be a `/wrap-insights` extension later; not v1.
- Survival classifier integration (per-finding confidence × per-finding survival is a separate dimension; this spec is about per-gate aggregate).
- Dashboard tab. The verdict sidecar already feeds the dashboard; this spec extends the data, not the renderer.

## Approach

**Chosen:** prompt-only extension at the persona layer + schema-additive field at the sidecar layer + read-only consumption in autorun.

Persona changes are append-only (existing checklists, key questions, output structure, class-tagging block all unchanged). New `## Confidence` section appended at the end of each persona's prompt with the standard 6-dimension table. Synthesis prompt extended with one paragraph instructing it to compute the per-dimension average and emit the `confidence` JSON object inside its existing fenced verdict block.

Schema bump is additive — `confidence` is **optional** in v3 (consumers reading v2 sidecars must default to `null`, not crash). Validator scripts updated. No migration of existing sidecars.

Rejected alternatives:
- *Reviewer-emits-JSON sidecar (autorun-verdict-deterministic shape)* — that proposal was REJECTED 2026-05-07 due to load-bearing execution-model gap (CG-1: `claude -p` has stdout, not file-write). Same gap blocks this approach. Prose-with-aggregation-at-synthesis is the proven path.
- *Single overall score, no per-dimension breakdown* — loses the diagnostic value (`/spec` already shows per-dimension; users expect parity).
- *Confidence-as-halt-gate in v1* — premature; no distribution data yet. Asymmetric risk: false halts kill overnight runs that would have shipped.

## Roster Changes

No roster changes. Existing reviewer personas at `personas/review/`, `personas/check/`, plus `personas/synthesis.md` and `personas/judge.md`, all participate.

## UX / User Flow

**Today (manual /spec-review):**
```
=== REVIEW: feature-name ===
Overall health: Concerns
## Before You Build (3 items)
...
```

**With this spec (manual /spec-review):**
```
=== REVIEW: feature-name ===
Overall health: Concerns
Confidence: 0.84 (overall) | scope 0.95 | ux 0.78 | data 0.85 | integration 0.80 | edges 0.82 | acceptance 0.84
Lowest dimension: ux — flagged by ambiguity + stakeholders personas
## Before You Build (3 items)
...
```

**Today (autorun final summary):**
```
slug-1: shipped (PR #42)
slug-2: failed at /check (NO_GO)
```

**With this spec (autorun final summary):**
```
slug-1: shipped | spec-review 0.92 | plan 0.88 | check 0.96 | PR #42
slug-2: failed at /check (NO_GO) | spec-review 0.85 | plan 0.71 | check 0.62
```

The /plan run for slug-2 dropping to 0.71 is the diagnostic signal: the synthesis was less confident, and that's where investigation should focus on retry.

## Data & State

**Schema change (additive):** `schemas/check-verdict.schema.json` v2 → v3.

```json
{
  "schema_version": 3,
  "...existing v2 fields...": "...",
  "confidence": {
    "overall": 0.84,
    "dimensions": {
      "scope": 0.95,
      "ux": 0.78,
      "data": 0.85,
      "integration": 0.80,
      "edges": 0.82,
      "acceptance": 0.84
    },
    "lowest_dimension": "ux",
    "personas_flagging_lowest": ["ambiguity", "stakeholders"]
  }
}
```

`confidence` is OPTIONAL in v3 (consumers reading v2 sidecars must accept absence). Validator must accept v2 sidecars without `confidence` AND v3 sidecars with or without `confidence` (the latter happens during the v2→v3 transition window before all personas land).

`run.json` (existing per-gate metrics file) gains the same `confidence` block via the `findings-emit` directive.

No new files. No persistent state outside the existing sidecars.

## Integration

- `personas/review/{requirements,gaps,ambiguity,feasibility,scope,stakeholders}.md` — append `## Confidence` section to each (6 files; ~10 lines each).
- `personas/check/{completeness,risk,scope-discipline,security-architect,sequencing,testability}.md` — append same section (6 files).
- `personas/synthesis.md` — extend output instructions: aggregate per-persona scores; emit `confidence` JSON in fenced verdict block; surface in user-facing summary.
- `personas/judge.md` — no change (Judge dedups/contradicts but doesn't aggregate confidence).
- `commands/_prompts/findings-emit.md` — extend to copy `confidence` from synthesis output to `run.json`.
- `schemas/check-verdict.schema.json` — bump to v3, add `confidence` property, mark optional.
- `scripts/_validate_check_verdict.py` (or equivalent) — accept v2 absent + v3 absent + v3 present.
- `scripts/autorun/spec-review.sh`, `plan.sh`, `check.sh` — no changes (synthesis emits the field; sidecar extractor passes through).
- `commands/{spec-review,plan,check}.md` — extend "Phase 3 Present" sections with the user-facing rendering format shown above.
- Dashboard (`docs/dashboard.html` + `scripts/judge-dashboard-bundle.py`) — no changes required for v1 (sidecar already feeds it; new field is data, not renderer).

Touched files: ~14 markdown + 1 schema + 1 validator + 3 command skills. Estimated ~150-300 LoC delta.

## Edge Cases

- **Persona crashed before emitting confidence:** synthesis aggregates only personas that returned; if all crashed, emit `confidence: null`. Autorun render shows `—` instead of a number.
- **Persona emitted partial dimensions (some scored, some `null`):** synthesis averages only non-null entries per dimension. If a dimension has zero non-null entries across all personas, that dimension is `null` in aggregate; overall is computed from the non-null dimensions.
- **Codex skipped (not authenticated):** Codex's confidence omitted; synthesis aggregates Claude personas only. No degradation to the score (Codex absence is silent skip per existing pattern).
- **`/plan` synthesis emits prose without the JSON block:** existing fence-extraction logic handles this; `confidence` defaults to absent. v6's single-fence-spoof guard still applies.
- **Schema validator running on a mid-transition sidecar (v3 schema, v2 personas without confidence):** validator must accept absent `confidence` field at v3 — explicit `if "confidence" in obj` checks, not required-array enforcement.
- **Forged confidence values in spoofed fence:** same threat model as forged verdicts — multi-fence detection + integrity-block-on-count==0 already in place. Confidence values are observability, not policy, so spoofing them yields no automated downstream effect (passive observability is the right v1 design here).
- **Autorun's run.log line is truncated by terminal width:** render the gate's confidence as `0.84` (4 chars) plus dimension shortcuts (`s.95 u.78 ...`) to fit standard 80-column displays.
- **Per-dimension scoring varies by gate:** `/spec-review` uses spec dimensions (scope/ux/data/integration/edges/acceptance); `/plan` uses plan dimensions (architecture/sequencing/risk/testability/scope-discipline/completeness); `/check` uses check dimensions (verdict-readiness/coverage/security/sequencing/risk/testability). Verdict sidecar `dimensions` object is open (string keys), not a fixed enum, to accommodate per-gate variation.
- **Backwards compatibility for downstream readers:** dashboard scripts that read `verdict.json` must use `obj.get("confidence", None)` semantics — never bare `obj["confidence"]`.

## Acceptance Criteria

1. After `/spec-review` on N personas, `verdict.json` (or `spec-review-verdict.json`) contains `confidence: { overall: <float 0-1>, dimensions: {...6 keys...}, lowest_dimension: <string>, personas_flagging_lowest: [<string>...] }`.
2. After `/plan` synthesis, `plan-verdict.json` contains the same `confidence` block with plan-appropriate dimension keys.
3. After `/check` synthesis, `check-verdict.json` contains the same `confidence` block with check-appropriate dimension keys.
4. `schemas/check-verdict.schema.json` bumped to `schema_version: 3` with `confidence` as optional property; `dimensions` accepts open string keys.
5. Validator accepts: v2 sidecar without confidence (legacy), v3 sidecar without confidence (graceful absence), v3 sidecar with confidence (target shape).
6. User-facing summary at each gate (manual mode) prints a one-line confidence row in the format shown in **UX / User Flow** above.
7. `/spec`'s 0.95 manual gate is unchanged by this spec (it does not move to verdict-sidecar emission — its confidence is interactive Q&A driven, not synthesis-aggregated).
8. Autorun's `queue/run.log` gains one line per gate per slug: `<timestamp> <slug> <stage> confidence=<overall> dims=<scope:0.x,ux:0.x,...>`.
9. Autorun does NOT halt or branch on confidence values — `--min-confidence` flag is explicitly NOT added (out of scope; deferred to data-driven follow-up).
10. Dashboard rendering of existing sidecars continues to work without modification (additive field, opt-in consumption).
11. Test fixture: synthesizer running on a fixture with 6 mock per-persona confidence outputs produces the correct aggregate (verifiable arithmetic).
12. Test fixture: validator accepts v2 sidecar without confidence + v3 sidecar without confidence + v3 sidecar with confidence; rejects malformed (e.g., overall outside [0,1], non-numeric dimension values).
13. Codex-absent path: synthesis aggregates Claude personas only; emits valid `confidence` block; final summary renders without Codex contribution noted.
14. Surfacing-without-acting principle: zero automated decisions in autorun branch on confidence values during this spec's scope.

## Open Questions

- **Q1 (low priority):** should `confidence` propagate to `findings.jsonl` per-finding (each finding tagged with the persona's confidence at emission time) or stay aggregate-only at the gate level? **Lean: aggregate-only for v1.** Per-finding confidence is a separate value (already partially covered by `severity`); mixing them invites confusion. Revisit if a use case surfaces.
- **Q2 (low priority):** should `/spec` itself adopt the same sidecar shape (write a `spec-confidence.json` alongside `spec.md` capturing the final Q&A confidence)? **Lean: not in this spec.** /spec confidence is interactive and ephemeral — capturing it post-hoc would require recording Q&A turn-by-turn, which is a different scope. Backlog as a possible /wrap-insights enhancement.
- **Q3 (resolved as "no" via spec):** add `--min-confidence` halt flag to autorun? Resolved: explicit out-of-scope per acceptance #9. Decision driven by asymmetric-risk reasoning (false halts cost overnight wallclock + tokens).
