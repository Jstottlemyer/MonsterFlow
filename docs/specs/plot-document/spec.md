---
gate_mode: permissive
---

# Plot Layer Spec — Narrative Context for MonsterFlow

**Created:** 2026-05-11
**Constitution:** none — session roster only
**Confidence:** Scope 0.95 / UX 0.95 / Data 0.90 / Integration 0.95 / Edge Cases 0.95 / Acceptance 0.95 (avg 0.94)
**Session Roster:** 27 defaults (no additional domain agents — core pipeline work)
**gate_mode:** permissive

Session roster only — run /kickoff later to make this a persistent constitution.

## Summary

Add a narrative context layer to MonsterFlow via the Plot Document — a structured description of the system that lives at `plot/PLOT.md` (Layer 1: system story) and `plot/chapters/*.md` (Layer 2: per-feature walkthroughs with inline code links). Three integration points, implemented in phases:

1. **`/plot` command** (new, standalone) — interactive mode for bootstrapping, checking, and updating the Plot Document. Auto-routes based on file state. This is where narrative gets written and the human editorial pass happens.
2. **`/wrap` Phase 2d** (extension) — lightweight Plot Gate that detects staleness every session and injects `[!STALE]` annotations in-place. Never drafts narrative.
3. **`/spec` Phase 0.2c** (extension) — reads the Plot Document as a third knowledge source alongside graphify and wiki, with tag-aware confidence levels.
4. **(Optional/deferred) PR-time CI gate** — GitHub Action running the same staleness logic as `/wrap` Phase 2d, scoped to the branch diff, blocking merge on failure.

The Plot Document becomes MonsterFlow's fifth knowledge store:

| Store | What it captures | When consumed |
|-------|-----------------|---------------|
| CLAUDE.md | Conventions, architectural decisions | Every session (auto-loaded) |
| auto-memory | Practitioner workflow preferences | Every session (auto-loaded) |
| Obsidian wiki | Distilled knowledge pages | `/spec` Phase 0.2b |
| graphify | Structural code relationships (AST) | `/spec` Phase 0.2a |
| **Plot Document** | **Narrative-level system context** | **`/spec` Phase 0.2c, `/plot`, `/wrap` Phase 2d** |

## Backlog Routing

| # | Item | Source | Routing |
|---|------|--------|---------|
| 1 | `docs/specs/_shipped/` archive move | BACKLOG.md | Stays — mechanical cleanup, unrelated |
| 2 | `queue/` vs `docs/specs/` consolidation | BACKLOG.md | Stays — infrastructure concern |
| 3 | `gate_max_recycles` harmonization | BACKLOG.md | Stays — already deprecated (175329c) |
| 4 | `openrouter-qwen-roster-integration` | BACKLOG.md | Stays — blocked on dynamic-roster-per-gate |
| 5 | 6 parked specs | BACKLOG.md | Stay parked — no overlap |
| 6 | PR-time Plot Gate (CI) | plot-layer-design.md | In scope (Phase 4, optional/deferred) |
| 7 | Plot measurement metrics | plot-layer-design.md | In scope (lightweight metrics ship with Phase 2; dashboard follow-up) |

## Scope

### In scope

- `/plot` command (`commands/plot.md`) — bootstrap, check, update flows with auto-routing
- Plot Document file format and annotation semantics (`[!STALE]`, `[!DRAFT]`)
- `/wrap` Phase 2d — Plot Gate staleness detection and annotation injection
- `/spec` Phase 0.2c — Plot Document reading with tag-aware confidence
- Lightweight metrics: `/wrap` report line + in-document `[!STALE]` annotations (no separate findings file)
- Dogfood: bootstrap Plot Document on this repo (MonsterFlow) as part of Phase 1 validation
- PR-time CI gate (Phase 4, optional/deferred — specced but ships independently)

### Out of scope

- Cross-project narrative (multi-repo Plot Documents)
- Dashboard visualization / trend analysis for Plot metrics (follow-up after dogfooding)
- Plot Document quality scoring or automated editorial feedback
- Changes to the existing Plot Document concept or skill design (this spec integrates the existing design into MonsterFlow)

## Approach

**Phased implementation (Approach A from Q&A):**

1. **Phase 1: `/plot` command** — new command file, bootstrap + check + update flows, annotation semantics, chapter format with inline code links. Establishes the file format and editorial flow.
2. **Phase 2: `/wrap` Phase 2d** — Plot Gate staleness detection and `[!STALE]` injection. Depends on Phase 1's file format and annotation contract.
3. **Phase 3: `/spec` Phase 0.2c** — read Plot Document as prior knowledge with tag-aware confidence. Depends on the annotation contract from Phase 1.
4. **Phase 4 (optional/deferred): PR-time CI gate** — GitHub Action. Same staleness logic, different trigger and action. Ships independently.

Rationale: `/plot` is the bootstrapping tool — without it there's no Plot Document to gate-check or read. Building it first enables immediate dogfooding and validates the format before wiring in automated consumers.

## Roster Changes

No roster changes.

## UX / User Flow

### `/plot` command

**Auto-routing** — the command reads the state of `plot/` and does the right thing. No subcommands, no flags.

| Condition | Action |
|-----------|--------|
| `!exists(plot/PLOT.md)` | Full bootstrap |
| `exists(plot/PLOT.md) && chapters_dir_empty_or_absent` | Draft chapters from scratch, then run check |
| `exists(plot/PLOT.md) && some_referenced_chapters_missing` | Draft only the missing chapters, then run check |
| `exists(plot/PLOT.md) && all_referenced_chapters_exist` | Run check, report findings, offer to update |

#### Bootstrap flow

1. **Analyze the codebase.** Deeply explore the project — directory structure, entry points, module boundaries, docs, key source files. Also read existing MonsterFlow knowledge stores (CLAUDE.md, wiki pages, graphify snapshot) for additional context. Exhaust what can be learned from code before involving the human.
2. **Ask targeted questions.** At most 2-3, only when the answer is genuinely unknowable from the codebase and would significantly improve the draft. The human can skip any question.
3. **Draft everything.** Layer 1 (`plot/PLOT.md`) and all Layer 2 chapters (`plot/chapters/*.md`), following Plot Document conventions.
4. **Show scope summary.** Brief list of what was drafted — chapter titles and one-sentence descriptions. Single feedback round: human confirms, adds, or removes. Not iterative.
5. **Write files.** Incorporate feedback, write all files to `plot/`.
6. **Run check.** Immediately run the check flow on the newly created content to establish a baseline.

#### Check flow

1. **Read the Plot Document and extract code links** from each chapter (inline markdown links to source files).
2. **Compare Layer 1** against the system's top-level structure. Flag if the system story, active tensions, or major capabilities have shifted.
3. **Compare each chapter** against its linked code. Apply staleness criteria (see Data & State).
4. **Report findings.** List each finding with: section name, what's inaccurate, why, and whether it was caused by the current diff or was already stale (best-effort attribution). Also surface any existing `[!STALE]` and `[!DRAFT]` annotations from previous sessions. If nothing is stale and nothing is missing: "Plot intact."
5. **Offer to update.** "Want me to draft updates for any of these? I can update all of them, or you can pick specific ones." The human can accept all, cherry-pick, or decline.
6. **Draft updates.** For accepted sections, draft updated narrative. Default to clean prose (no `[!DRAFT]` tag) — the developer is present and reviewing in-session. If the developer says "I'll review later," write with `[!DRAFT]` tag instead.
7. **Remove resolved annotations.** When a stale section is updated and reviewed in-session, remove the `[!STALE]` callout. When a drafted section is reviewed, remove `[!DRAFT]`.

#### Broken link handling

When check finds a chapter whose inline code links point to moved/deleted files:

1. Mark the section as stale (`[!STALE]` with reason "entrypoint files moved or deleted").
2. Attempt to resolve where files moved to (`git log --follow`, filename similarity).
3. Offer corrected links alongside the narrative update draft.

#### The editorial pass

The developer reads the agent's draft and corrects factual errors, adjusts emphasis, notices gaps, restructures for clarity. This is where understanding forms. The agent drafts; the human reviews and corrects. An in-session review means the developer is doing the editorial pass in the conversation itself.

### `/wrap` Phase 2d: Plot Gate

> **Phase numbering note:** The design doc (`plot-layer-design.md`) calls this "Phase 3." This spec renumbers it to Phase 2d to group it with the existing knowledge-store phases (2c is Wiki). The spec is authoritative for implementation.

Runs after Phase 2c (Wiki). Silent, automatic, no human interaction. **Skipped in quick mode** (consistent with Phase 2c skip behavior — `/wrap quick` skips all Phase 2 sub-phases after 2a).

1. **Check for Plot Document.** If `plot/PLOT.md` does not exist, skip entirely.
2. **Read the Plot Document.** Read `plot/PLOT.md` and all files in `plot/chapters/`.
3. **Run the gate comparison.** Compare prose claims against current codebase state and the session's diff. Use inline code links from chapters to identify relevant code.
4. **Apply staleness criteria.** (See Data & State for the full contract.)
5. **Annotate in-place.** For each stale section, inject or update a `[!STALE]` callout immediately below the section heading.
6. **Report in `/wrap` output:**
   - "Plot: intact." (common case)
   - "Plot: 2 stale sections annotated in payments.md, 1 in auth.md."
   - "Plot: Layer 1 may need review — [reason]."

**What it does NOT do:**
- Never drafts narrative content (detect and annotate only)
- Never asks questions (silent)
- Never removes existing annotations (`[!STALE]` stays until human resolves via `/plot`; `[!DRAFT]` stays until human reviews)

### `/spec` Phase 0.2c: Plot Document reading

Runs after Phase 0.2b (wiki-query). Skip silently if `plot/PLOT.md` does not exist.

1. **Read `plot/PLOT.md` and all `plot/chapters/*.md`.**
2. **Apply tag-aware confidence:**
   - **Clean prose** (no tags): reliable context, use with confidence.
   - **`[!STALE]` sections**: narrative is known to be wrong. Flag it: "Note: the Plot Document's description of [feature] is stale — [reason]. I'll ground this part of the spec in the code directly rather than the narrative."
   - **`[!DRAFT]` sections**: AI-generated, useful but unverified. Use as context but don't treat as authoritative.
3. **Render callout** between context summary and Phase 0.5:
   ```
   ### Prior narrative context (Plot Document)
   - Layer 1: [1-sentence system story summary]
   - [N] chapters: [list titles]
   - [N stale, N draft, N clean]

   Source: plot/PLOT.md + plot/chapters/ ([N] chapters)
   ```

## Data & State

### File structure

```
plot/
  PLOT.md              # Layer 1: the system's story (1-2 pages)
  chapters/
    feature-name.md    # Layer 2: one per significant feature
    another-feature.md
    ...
```

No sidecar status files. The document itself is the single source of truth for what needs attention, via in-document annotations.

### Chapter format

Layer 2 chapters are narrative walkthroughs with inline markdown links to relevant source files:

```markdown
# Payment Flow

The payment flow begins at the [PaymentController](../../src/payments/controller.ts)
which validates the request against the [schema](../../src/payments/schema.ts)...
```

Links serve dual purposes: human readers can click through to code; the gate extracts link targets to scope its comparison.

### Annotation types

Two annotation types using GitHub-compatible callout syntax:

**`[!STALE]`** — prose contradicts code. Injected by `/wrap` Phase 2d automatically.

```markdown
### Refund handling

> [!STALE] Refund processing is now async via a queue — this section
> describes synchronous processing. (detected 2026-05-11)
```

**`[!DRAFT]`** — AI-generated, not yet human-reviewed. Created by `/plot` when the developer opts for later review.

```markdown
### Batch refunds

> [!DRAFT] Agent-drafted content, not yet human-reviewed. (drafted 2026-05-11)
```

| Tag | Meaning | Created by | Removed by |
|-----|---------|-----------|------------|
| `[!STALE]` | Prose contradicts code | `/wrap` Phase 2d (automatically) | Human, after reviewing updated draft from `/plot` |
| `[!DRAFT]` | AI-generated, not yet human-reviewed | `/plot` (when developer opts for later review) | Human, after editorial review |

Absence of a tag is the reviewed state. Clean prose = human-verified.

### Annotation deduplication

When `/wrap` Phase 2d finds a section already has a `[!STALE]` annotation:

- **Single `[!STALE]` callout per section**, with numbered reasons.
- New reasons are appended to the existing callout with a new date.
- **Cap at 3 reasons.** If a 4th arrives, drop the oldest. This prevents unbounded growth while preserving recent drift signals.

Example:
```markdown
> [!STALE] (1) Refund processing is now async (detected 2026-05-08).
> (2) Retry logic added to payment gateway calls (detected 2026-05-11).
```

### Staleness criteria

A section is stale when the prose makes a claim that the code contradicts:

- Feature works differently than described
- Walkthrough doesn't match actual code flow
- Design rationale describes constraints no longer in effect
- Inline code links point to moved/deleted files

A section is **NOT** stale when:

- Code was refactored without behavior change
- New code was added that doesn't change the described feature
- Implementation details changed without affecting what the feature is or why it exists

**Evaluate claims at the abstraction level the prose is written at.** Minimizing false positives is critical — a noisy gate will be ignored immediately.

### Metrics (lightweight, ships with Phase 2)

**`/wrap` report line:** always present when `plot/PLOT.md` exists. One of:
- "Plot: intact."
- "Plot: N stale sections annotated in [chapters]."
- "Plot: Layer 1 may need review — [reason]."

No separate `findings.jsonl` for the Plot Gate. The in-document `[!STALE]` annotations are the persistent record of staleness, and the `/wrap` report line communicates findings to the user at session end. If trend analysis (hit rate, accumulation, time-to-resolution) becomes valuable after dogfooding, a `plot/findings.jsonl` can be added in a follow-up — but speculative infrastructure without a current consumer is not worth the file.

## Integration

### New files

- `commands/plot.md` — the `/plot` command definition (peer of `commands/spec.md`, `commands/wrap.md`)

### Modified files

- `commands/wrap.md` — add Phase 2d (Plot Gate) after Phase 2c (Wiki)
- `commands/spec.md` — add Phase 0.2c (Plot Document reading) after Phase 0.2b (wiki-query)
- `docs/index.html` or README — mention Plot Document as the fifth knowledge store (follow-up docs pass)

### `/flow` reference card

Add `/plot` to the command listing. It's a standalone command, the 9th in the pipeline (on-demand, not sequenced between existing pipeline stages).

### Relationship to existing commands

| Command | Relationship to Plot Layer |
|---------|---------------------------|
| `/plot` | **New.** Owner of the Plot Document lifecycle. |
| `/wrap` | **Extended.** Phase 2d runs the Plot Gate after wiki (Phase 2c). |
| `/spec` | **Extended.** Phase 0.2c reads Plot Document as prior knowledge. |
| `/kickoff` | Unaffected. Constitution doesn't own Plot Document. |
| `/spec-review`, `/plan`, `/check`, `/build` | Unaffected. They consume the spec, which now has richer context from `/spec` Phase 0.2c. |

### No Plot-specific findings file

The Plot Gate does not write to any `findings.jsonl`. The `/wrap` report line and in-document `[!STALE]` annotations are sufficient for v1. No shared schema changes needed. Existing pipeline consumers are unaffected.

## Edge Cases

1. **No Plot Document exists.** `/wrap` Phase 2d skips silently. `/spec` Phase 0.2c skips silently. `/plot` auto-routes to bootstrap. Graceful degradation everywhere.

2. **Plot Document exists but `plot/chapters/` is empty or absent.** `/plot` drafts chapters from scratch (same as the "chapters_dir_empty_or_absent" routing condition), then runs check.

3. **All chapter links are broken.** Mark section as stale with reason "entrypoint files moved or deleted." Attempt to resolve where files moved (`git log --follow`, filename similarity). Offer corrected links in the update draft.

4. **`[!STALE]` annotation accumulates 3+ reasons.** Cap at 3, drop oldest. The callout signals "this section needs attention" — 3 reasons is enough to convey that.

5. **`/plot` and `/wrap` run in the same session.** No conflict — `/plot` is interactive and runs on-demand; `/wrap` Phase 2d runs at session end. If `/plot` resolved staleness earlier in the session, `/wrap` Phase 2d will find the section clean and report "Plot: intact."

6. **Chapter describes a feature that was entirely removed.** The gate detects that all linked files are gone and no similar files exist. Reports as stale with reason "feature appears to have been removed." `/plot` update flow offers to either delete the chapter or mark it as historical context.

7. **Very large codebase at bootstrap.** Agent explores and proposes chapters via scope summary. Human trims in the single feedback round. No hard cap — the scope summary step is the scoping mechanism.

8. **`/spec` reads `[!STALE]` content.** Explicitly flags it: "Note: the Plot Document's description of [feature] is stale — [reason]. I'll ground this part of the spec in the code directly rather than the narrative." Does not silently use known-bad narrative.

9. **Multiple `[!DRAFT]` sections in a chapter.** Each section has its own `[!DRAFT]` callout. No interaction between them. Each is resolved independently by human review.

10. **Session where only `/wrap` runs (no `/plot`).** Normal case. `/wrap` Phase 2d injects annotations if needed; `[!STALE]` tags accumulate across sessions until someone runs `/plot`. This is by design — low-frequency, high-value engagement.

## Acceptance Criteria

### Phase 1: `/plot` command

- **AC1.** `commands/plot.md` exists and is invocable as `/plot` in Claude Code.
- **AC2.** On a project with no `plot/` directory, `/plot` runs the full bootstrap flow: explores codebase, asks at most 2-3 questions, drafts Layer 1 + Layer 2, shows scope summary, writes files after feedback.
- **AC3.** On a project with `plot/PLOT.md` but missing chapters, `/plot` drafts the missing chapters, then runs check.
- **AC4.** On a project with a complete Plot Document, `/plot` runs check: compares prose against code via inline link extraction, reports findings, offers to update.
- **AC5.** Drafted updates default to clean prose (no `[!DRAFT]` tag). When the developer says "I'll review later," drafts include `[!DRAFT]` tag.
- **AC6.** Broken inline links are detected, flagged as stale, and the agent attempts to resolve where files moved.
- **AC7.** `[!STALE]` and `[!DRAFT]` annotations are removed when the corresponding section is updated and reviewed in-session.
- **AC8.** **Dogfood:** `/plot` has been run on this repo (MonsterFlow) and the resulting Plot Document has been editorially reviewed by a human before Phase 1 is considered complete.

### Phase 2: `/wrap` Phase 2d

- **AC9.** `/wrap` Phase 2d runs after Phase 2c (Wiki) and before Phase 3 (Loose Ends). Skipped in quick mode (consistent with Phase 2c).
- **AC10.** When `plot/PLOT.md` does not exist, Phase 2d is skipped silently.
- **AC11.** When the Plot Document is accurate, `/wrap` output includes "Plot: intact."
- **AC12.** When staleness is found, `[!STALE]` callouts are injected in-place with reason and date.
- **AC13.** Existing `[!STALE]` callouts are updated (new reason appended, not duplicated), capped at 3 reasons.
- **AC14.** Phase 2d never drafts narrative, never asks questions, never removes existing annotations.

### Phase 3: `/spec` Phase 0.2c

- **AC15.** `/spec` Phase 0.2c runs after Phase 0.2b (wiki-query).
- **AC16.** When `plot/PLOT.md` does not exist, Phase 0.2c is skipped silently.
- **AC17.** Clean prose sections are used as reliable context in the spec Q&A.
- **AC18.** `[!STALE]` sections are explicitly flagged: "the Plot Document's description of [feature] is stale — [reason]."
- **AC19.** `[!DRAFT]` sections are used as context but not treated as authoritative.
- **AC20.** A callout block is rendered between context summary and Phase 0.5, listing Layer 1 summary, chapter titles, and tag counts.

### Phase 4: PR-time CI gate (optional/deferred)

- **AC21.** A GitHub Action runs on PRs targeting main.
- **AC22.** Gate runs the same staleness comparison as `/wrap` Phase 2d, scoped to `git diff main...HEAD`.
- **AC23.** If `plot/PLOT.md` doesn't exist, the gate passes immediately.
- **AC24.** On FAIL, the PR is blocked. The developer runs `/plot` to update the narrative and pushes as part of the PR.
- **AC25.** On PASS, no action needed.

### Testing

- **AC26.** Scripted tests in `tests/run-tests.sh` cover: annotation injection, annotation deduplication (including 3-reason cap and oldest-drop renumbering), and inline link extraction from chapter content. (Staleness detection is LLM-based and validated via dogfood AC8 and manual smoke tests AC27, not scripted tests.)
- **AC27.** Manual smoke tests validate the interactive flows (`/plot` bootstrap, check, update) and the `/wrap` + `/spec` integration.
- **AC28.** `/flow` reference card lists `/plot` as a standalone on-demand command.

## Open Questions

None — confidence at 0.95 across all six dimensions. Minor items deferred:

- **Dashboard visualization** for Plot metrics (hit rate, accumulation, time-to-resolution) — follow-up after dogfooding reveals what's worth tracking.
- **Cross-project narrative** — explicitly out of scope; would require separate design work.
