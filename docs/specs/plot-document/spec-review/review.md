# REVIEW: Plot Layer — Narrative Context for MonsterFlow

**Spec:** `docs/specs/plot-document/spec.md`
**Reviewers:** requirements, gaps, ambiguity, feasibility, scope, stakeholders, docs-clarity (7 agents)
**Gate mode:** permissive (frontmatter)
**Date:** 2026-05-11

---

## Spec Strengths

- **Clean phasing with explicit dependencies.** The four-phase approach (/plot → /wrap → /spec → CI) has clear ordering rationale and each phase's prerequisites are stated. Phase 1 can be fully validated via dogfood before Phases 2-3 touch existing commands.
- **Annotation contract is well-designed.** Two annotation types with clean ownership (`[!STALE]` by `/wrap`, `[!DRAFT]` by `/plot`), dedup rules, and a cap. The "absence of tag = reviewed" convention avoids tag litter.
- **Graceful degradation everywhere.** All three integration points (and the deferred CI gate) skip silently when no Plot Document exists. Zero impact on projects that don't adopt.

---

## Before You Build (5 items)

### B1. `findings.jsonl` schema is incompatible — define a separate file or extend the schema
**Convergence: 5 of 7 reviewers** (requirements, gaps, feasibility, docs-clarity, stakeholders)
**Class: contract | Severity: blocker**

The proposed plot finding record (`gate`, `chapter`, `section`, `reason`, `severity: "stale"`, `date`) shares no required fields with the v2 `findings.schema.json` (which requires `schema_version`, `finding_id`, `personas[]`, `class`, `normalized_signature`, and constrains `stage` to `["spec-review", "plan", "check"]`). Writing plot records to the same file would fail validation.

**Action:** Either (a) define a separate `plot/findings.jsonl` with its own lightweight schema, or (b) extend `findings.schema.json` with a discriminated union on a `gate` field. Option (a) is simpler and avoids touching the shared schema that existing consumers depend on. Whichever path is chosen, also resolve the write-path question: where does the file live? (Not in `docs/specs/<feature>/` — plot findings are repo-scoped, not feature-scoped.)

### B2. Reconcile phase numbering: spec says "Phase 2d," design doc says "Phase 3"
**Convergence: 3 of 7 reviewers** (ambiguity, scope, docs-clarity)
**Class: documentation | Severity: major**

The spec and the design document use different phase numbers for the same feature. The spec is authoritative (it's the implementation artifact), but someone reading the design doc first will be confused.

**Action:** Add a one-line note to the spec: *"Note: the design doc (`plot-layer-design.md`) calls this 'Phase 3.' This spec renumbers it to Phase 2d to group it with the existing knowledge-store phases (2c is Wiki)."* No other changes needed.

### B3. `/wrap` quick-mode: state whether Phase 2d runs or is skipped
**Convergence: 2 of 7 reviewers** (gaps, scope)
**Class: contract | Severity: major**

`/wrap quick` skips Phases 1a, 1b, 1c, 2b, 2c, 3b, and 5. Phase 2d is not mentioned in either skip list or keep list. Since 2c (Wiki) is skipped in quick mode, a reader of "Phase 2d runs after 2c" might infer 2d is also skipped.

**Action:** Add an explicit statement: either "Phase 2d is skipped in quick mode" (group with 2c) or "Phase 2d runs even in quick mode" (it's lightweight and silent). Recommended: **skip in quick mode** — consistency with 2c, and quick mode exists because the user is in a hurry.

### B4. Scope AC27 staleness tests to non-LLM mechanics only
**Convergence: 2 of 7 reviewers** (requirements, feasibility)
**Class: tests | Severity: major**

AC27 says scripted tests cover "staleness detection against fixture content," but staleness detection is an LLM judgment call — no deterministic oracle exists. The mechanical parts (annotation injection, dedup with 3-reason cap, inline link extraction) are fully testable.

**Action:** Reword AC27: "Scripted tests in `tests/run-tests.sh` cover: annotation injection, annotation deduplication (including 3-reason cap and oldest-drop behavior), and inline link extraction from chapter content." Remove "staleness detection against fixture content" — staleness is validated via dogfood (AC8) and manual smoke tests (AC28).

### B5. Clarify the `/plot` routing state machine for the "missing chapters" condition
**Convergence: 2 of 7 reviewers** (ambiguity, docs-clarity)
**Class: contract | Severity: major**

The routing table conflates two states: (1) PLOT.md references chapters that don't exist as files, and (2) PLOT.md exists but `plot/chapters/` is empty with no chapter references. Edge Case 2 collapses the second into the first.

**Action:** Rewrite the routing table with explicit boolean conditions:
- `!exists(plot/PLOT.md)` → bootstrap
- `exists(plot/PLOT.md) && chapters_dir_empty_or_absent` → draft chapters, then check
- `exists(plot/PLOT.md) && all_referenced_chapters_exist` → check
- `exists(plot/PLOT.md) && some_referenced_chapters_missing` → draft missing, then check

---

## Important But Non-Blocking (7 items)

### S1. Layer 1 (PLOT.md) staleness criteria need grounding
**Convergence: 3 of 7** (gaps, ambiguity, docs-clarity)

Layer 2 chapters have inline code links for the gate to scope comparison. Layer 1 has no links — the check says "compare against top-level structure" without defining what evidence sources anchor that comparison. Consider: directory tree, entry points listed in CLAUDE.md or README, package.json/Cargo.toml surface.

### S2. `[!DRAFT]` + `[!STALE]` on the same section — define precedence
**Convergence: 1 of 7** (gaps)

A developer drafts content, says "review later" (`[!DRAFT]`), then code changes before review (`[!STALE]` injected by `/wrap`). Spec doesn't address two annotations on the same section. Recommendation: allow both (they mean different things), with `/plot` surfacing both when it runs check.

### S3. Post-bootstrap check behavior — report-only or full offer-to-update flow?
**Convergence: 1 of 7** (ambiguity)

Bootstrap step 6 says "run check to establish a baseline." But the check flow unconditionally offers updates. Recommendation: post-bootstrap check is report-only (no update offer) since the prose was just written from the code. Note this in the spec.

### S4. Annotation dedup procedure — define the structural operation
**Convergence: 1 of 7** (ambiguity)

"Drop the oldest" needs to specify: renumber remaining items. The implementation is: remove item (1), shift (2)→(1), (3)→(2), append new item as (3). Note: if `/wrap` recognizes an existing reason still applies, it should not re-count it toward the cap.

### S5. `/wrap` Phase 2d latency — set a skip condition or budget
**Convergence: 2 of 7** (requirements, feasibility)

`/wrap` targets 2-3 minutes total. Phase 2d reads all chapters + linked files + makes an LLM comparison. For large Plot Documents this could be expensive. Recommendation: skip Phase 2d if no files linked from any chapter were modified in the session's diff. This makes the common case ("Plot: intact") near-instant.

### S6. Annotation manipulation — delegate to deterministic helpers
**Convergence: 1 of 7** (feasibility)

The dedup, renumbering, and callout injection are string surgery on structured markdown. LLMs are unreliable at this. The `/plan` step should design shell/Python helpers for callout manipulation rather than relying on free-form LLM editing.

### S7. Add a `/flow` reference card AC and schema enum update AC
**Convergence: 2 of 7** (scope, requirements)

The spec mentions updating `/flow` and "may need" to update the schema enum, but neither has an AC. Promote to explicit ACs.

---

## Watch List

- **CI gate (Phase 4) will need its own design pass.** Four reviewers flagged that "same staleness logic" in a GitHub Action requires Claude API access, headless invocation, structured verdict output, and cost governance. This is all valid but premature — Phase 4 is deferred. When promoted, it needs a separate spec or a spec revision.
- **Staleness calibration.** The boundary between "feature works differently" and "implementation details changed" is the hardest judgment the gate makes. Feasibility reviewer recommends writing 3-5 labeled examples (stale/not-stale with reasoning) directly in `commands/plot.md` to seed the gate's calibration. Good idea for `/plan`.
- **Adopter communication.** Stakeholders reviewer notes that `/wrap` Phase 2d modifies `plot/` files silently. A CHANGELOG entry at Phase 2 ship would prevent surprise. The opt-out mechanism is already covered (no Plot Document = no gate).
- **External skill references.** The spec references `PLOT_DOC_CONCEPT.md` and `PLOT_SKILL_DESIGN.md` at cross-repo paths. If those are inaccessible during build, `plot-layer-design.md` (in this repo) is the fallback authority.

---

## Agent Disagreements Resolved

- **Ambiguity (FAIL) vs all others (PASS WITH NOTES)** — The ambiguity reviewer applied a strict deterministic-API threshold: undefined trigger signals, undefined algorithms, undefined procedures. Resolution: **Override to PASS WITH NOTES.** This is a Claude Code markdown command, not a deterministic API. The "algorithm" is the LLM prompt itself. The "trigger" for `[!DRAFT]` is conversational. The phase numbering conflict is a documentation fix, not a design gap. The substantive findings (routing state machine, post-bootstrap check, dedup procedure) are all real and captured as B5, S3, and S4 above — but they are refinements, not implementation blockers.

---

## Reviewer Verdicts

| Dimension | Verdict | Key Finding |
|-----------|---------|-------------|
| Requirements | PASS WITH NOTES | findings.jsonl schema incompatibility (blocker) |
| Gaps | PASS WITH NOTES | findings.jsonl schema + write path (blocker) |
| Ambiguity | FAIL → overridden to PASS WITH NOTES | 5 CGs on underspecification; substantive items captured, severity recalibrated |
| Feasibility | PASS WITH NOTES | findings.jsonl schema + latency budget |
| Scope | PASS WITH NOTES | Phase numbering conflict + external skill dependency |
| Stakeholders | PASS WITH NOTES | Adopter opt-out (resolved: no Plot Doc = no gate) |
| Docs Clarity | PASS WITH NOTES | Link extraction scope + staleness algorithm |

---

## Consolidated Verdict

**7 of 7 reviewers passed (1 overridden from FAIL).** The spec is ready for `/plan` after resolving 5 Before-You-Build items: the findings.jsonl schema decision (B1), phase numbering reconciliation (B2), quick-mode skip behavior (B3), AC27 scoping (B4), and routing state machine clarification (B5). All 5 are concrete, each resolvable with a one-paragraph spec edit. No architectural redesign needed.

Overall health: **Good — minor refinements needed.**
