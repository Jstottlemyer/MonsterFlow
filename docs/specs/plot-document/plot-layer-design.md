# Plot Layer Design for MonsterFlow

*Design document for integrating the Plot Document into MonsterFlow as a narrative context layer.*

## Background

### The Plot Document

The Plot Document is a structured narrative that tells the story of a software system — what it does, what its parts do, why they exist, and what's unresolved. It exists because when AI agents write most of the code, humans lose the understanding that used to form as a byproduct of implementation. The Plot Document creates a new thing to maintain — a narrative description of the system — so that the byproduct comes back. The maintenance itself is the point; the document is a side effect; the understanding that forms while maintaining it is the real output.

Two components:

- **The Plot Document** lives in the repo as `plot/PLOT.md` (Layer 1: the system's story, 1-2 pages) and `plot/chapters/*.md` (Layer 2: one entry per significant feature, structured as walkthroughs with design rationale).
- **The Plot Gate** checks whether the Plot Document still matches the code after a change. It evaluates narrative integrity — is the system's story still true? — not code quality.

Two touch points where humans maintain it:

1. **During feature design** — a team brainstorms a feature and produces Plot Document content as a byproduct. The agent drafts; the human reviews and corrects.
2. **When the Plot Gate fires** — a change makes the Plot Document inaccurate. The gate flags what's stale, the agent drafts an update, and the developer does the editorial pass.

The editorial pass — reading the narrative, catching errors, adjusting emphasis, noticing gaps — is where understanding forms. An agent can draft any layer, but a human must review and correct it.

Full concept: [PLOT_DOC_CONCEPT.md](../plot-doc/PLOT_DOC_CONCEPT.md). Skill design: [PLOT_SKILL_DESIGN.md](../plot-doc/PLOT_SKILL_DESIGN.md). Example skill implementation: [foundations-ai-studio plot skill](../../code/aice/foundry/foundations-ai-studio/.claude/skills/plot/SKILL.md).

### MonsterFlow's knowledge architecture

MonsterFlow has an 8-command gated pipeline (`/kickoff` through `/autorun`) with a multi-store knowledge architecture. The `/wrap` command triages end-of-session learnings into four stores, each serving a different query pattern:

| Store | What it captures | When consumed |
|-------|-----------------|---------------|
| CLAUDE.md | Conventions, architectural decisions with rationale | Every session (auto-loaded) |
| auto-memory | Practitioner workflow preferences, behavioral corrections | Every session (auto-loaded) |
| Obsidian wiki | Distilled knowledge pages (architecture decisions, tool picks, constraints, patterns) | `/spec` Phase 0.2 (prior knowledge callout) |
| graphify code graph | AST-based structural relationships (symbol relationships, call graphs, community structure) | `/spec` Phase 0.2 (prior knowledge callout) |

The `/spec` command's Phase 0.2 queries graphify and the Obsidian wiki for relevant context before beginning specification dialogue. This is where accumulated knowledge from prior sessions informs the current session's work.

### The gap

MonsterFlow captures **decision-level** context well (discrete architectural choices with rationale, in CLAUDE.md and wiki) and **structural** context well (code relationships, in graphify). It does not capture **narrative-level** context — holistic understanding of how a system works as a coherent whole. You can query "what depends on what?" (graphify) and "what was decided about X?" (wiki), but not "how does the payment module work end-to-end, and why does it handle refunds that way?"

The Plot Document fills exactly this gap. It is the narrative layer that MonsterFlow's knowledge architecture is missing.

## Design

### Overview

Three integration points:

1. **`/wrap` Phase 3: Plot Gate** — lightweight drift detection every session. Annotates the Plot Document in-place when staleness is found. Never drafts narrative content.
2. **`/plot` command** — on-demand interactive mode for bootstrapping, checking, and updating the Plot Document. This is where narrative gets written and where the human editorial pass happens.
3. **`/spec` Phase 0.2: narrative context** — reads the Plot Document as a third knowledge source alongside graphify and wiki, with tag-aware confidence levels.

### The knowledge store

The Plot Document becomes MonsterFlow's fifth knowledge store:

| Store | What it captures | When consumed |
|-------|-----------------|---------------|
| CLAUDE.md | Conventions, architectural decisions | Every session (auto-loaded) |
| auto-memory | Practitioner workflow preferences | Every session (auto-loaded) |
| Obsidian wiki | Distilled knowledge pages | `/spec` Phase 0.2 |
| graphify | Structural code relationships (AST) | `/spec` Phase 0.2 |
| **Plot Document** | **Narrative-level system context — how modules work, how parts relate, what tensions exist** | **`/spec` Phase 0.2, `/plan`, on-demand** |

### File structure

Standard Plot Document structure, unchanged from the existing design:

```
plot/
  PLOT.md              # Layer 1: the system's story (1-2 pages)
  chapters/
    feature-name.md    # Layer 2: one per significant feature
    another-feature.md
    ...
```

No sidecar status files. The document itself is the single source of truth for what needs attention, via in-document annotations (see below).

### In-document annotations

Two annotation types, using GitHub-compatible callout syntax:

**`[!STALE]`** — This section's claims no longer match the code. Injected by `/wrap` automatically when drift is detected.

```markdown
### Refund handling

> [!STALE] Refund processing is now async via a queue — this section
> describes synchronous processing. (detected 2026-05-11)

The merchant initiates a refund from the transaction detail page. The system
validates the refund amount against the original transaction, checks that the
refund window hasn't expired, and processes the refund synchronously through
the payment gateway...
```

**`[!DRAFT]`** — This section was AI-generated and hasn't been human-reviewed. Created by `/plot` when drafting new or updated content.

```markdown
### Batch refunds

> [!DRAFT] Agent-drafted content, not yet human-reviewed. (drafted 2026-05-11)

> **Merchants can now process refunds in bulk by uploading a CSV of
> transaction IDs...**

...agent-drafted narrative follows...
```

| Tag | Meaning | Created by | Removed by |
|-----|---------|-----------|------------|
| `[!STALE]` | Prose contradicts code | `/wrap` (automatically) | Human, after reviewing updated draft from `/plot` |
| `[!DRAFT]` | AI-generated, not yet human-reviewed | `/plot` (when drafting new or updated content) | Human, after editorial review |

**Absence of a tag is the reviewed state.** Clean prose = human-verified. Tags = needs attention. No `[!REVIEWED]` tag — that would litter the entire document.

---

## `/wrap` Phase 3: Plot Gate

### When it runs

After the existing `/wrap` phases (CLAUDE.md triage, wiki ingest, graphify snapshot). Runs every `/wrap` cycle.

### What it does

1. **Check for Plot Document.** If `plot/PLOT.md` does not exist, skip this phase entirely. No Plot Document means nothing to check.

2. **Read the Plot Document.** Read `plot/PLOT.md` and all files in `plot/chapters/`.

3. **Run the gate comparison.** Same logic as the existing Plot Gate skill — compare prose claims against current codebase state and the session's diff. Use entrypoint links, path matching, and diff scoping to identify relevant code for each chapter.

4. **Apply staleness criteria.** A section is stale when the prose makes a claim that the code contradicts (feature works differently, walkthrough doesn't match actual flow, design rationale describes constraints no longer in effect, entrypoint link points to moved/deleted file). A section is NOT stale just because code was refactored without behavior change, new code was added that doesn't change the described feature, or implementation details changed without affecting what the feature is or why it exists. Minimizing false positives is critical — a noisy gate in `/wrap` will be ignored immediately. Evaluate claims at the abstraction level the prose is written at.

5. **Annotate in-place.** For each stale section found, inject a `[!STALE]` callout immediately below the section heading (or immediately before the section's first paragraph if no heading). The callout includes: what's inaccurate, why, and the date detected.

6. **Report in `/wrap` output.** Include a summary line in the `/wrap` report:
   - "Plot: intact." (common case for mature projects)
   - "Plot: 2 stale sections annotated in payments.md, 1 in auth.md."
   - "Plot: Layer 1 may need review — [reason]."

### What it does NOT do

- **Never drafts narrative content.** It detects and annotates, it does not write prose.
- **Never asks questions.** It is silent — no human interaction.
- **Never removes existing annotations.** A `[!STALE]` tag from a previous session stays until a human resolves it via `/plot`. A `[!DRAFT]` tag stays until a human reviews it.
- **Never duplicates annotations.** If a section already has a `[!STALE]` callout, the gate updates the existing annotation (new reason, new date) rather than adding a second one.

### Cost

For a mature project where the Plot Document is accurate, this phase adds a few seconds of comparison and outputs "Plot: intact." The common case is near-zero cost. The expensive case (multiple stale sections found) is also the case where the cost is justified.

---

## `/plot` Command: Interactive Mode

### When it runs

On-demand — the developer runs `/plot` when they want to bootstrap, check, or update the Plot Document. This is MonsterFlow's integration of the existing Plot Document skill's interactive mode.

### Routing

The command reads the state of the `plot/` directory and does the right thing:

1. **No `plot/PLOT.md`** — full bootstrap.
2. **`plot/PLOT.md` exists but has links to missing chapters** — draft the missing chapters.
3. **Everything exists** — run check, report findings, offer to update.

In all cases, after writing anything missing, also run the check on everything that exists.

### Bootstrap flow

For new projects or projects without a Plot Document:

1. **Analyze the codebase.** Deeply explore the project — directory structure, entry points, module boundaries, docs, key source files. Exhaust what can be learned from code before involving the human. Also read existing MonsterFlow knowledge stores (CLAUDE.md, wiki pages, graphify snapshot) for additional context.

2. **Ask targeted questions.** At most 2-3, only when the answer is genuinely unknowable from the codebase and would significantly improve the draft. The human can skip any question.

3. **Draft everything.** Layer 1 and all Layer 2 chapters, following Plot Document conventions.

4. **Show scope summary.** Brief list of what was drafted — chapter titles and one-sentence descriptions. Single feedback round: human confirms, adds, or removes. Not iterative.

5. **Write files.** Incorporate feedback, write all files to `plot/`.

6. **Run check.** Immediately run the check flow on the newly created content to establish a baseline.

### Check flow

For existing Plot Documents:

1. **Read the Plot Document and identify relevant code for each chapter** (entrypoint links, path matching, diff scoping).

2. **Compare Layer 1** against the system's top-level structure. Flag if the system story, active tensions, or major capabilities have shifted.

3. **Compare each chapter** against its relevant code. Apply the same staleness criteria as `/wrap` Phase 3.

4. **Report findings.** List each finding with: section name, what's inaccurate, why, and whether it was caused by the current diff or was already stale (best-effort attribution). Also surface any existing `[!STALE]` and `[!DRAFT]` annotations from previous sessions. If nothing is stale and nothing is missing: "Plot intact."

5. **Offer to update.** "Want me to draft updates for any of these? I can update all of them, or you can pick specific ones." The human can accept all, cherry-pick, or decline.

6. **Draft updates.** For accepted sections, the agent drafts updated narrative. If the human is reviewing in-session, write clean prose directly (no `[!DRAFT]` tag needed — the human is doing the editorial pass right now). If the human wants to review later in their editor, write the draft with a `[!DRAFT]` tag so it's visibly unreviewed.

7. **Remove resolved annotations.** When a stale section is updated and reviewed, the `[!STALE]` callout is removed. When a drafted section is reviewed, the `[!DRAFT]` callout is removed.

### The editorial pass

This is where the S5 (Practitioner Knowledge Compounding) value lives. The developer reads the agent's draft and:

- Corrects factual errors ("actually, the reason we went async was X not Y")
- Adjusts emphasis ("this tension isn't active anymore, we resolved it in the auth migration")
- Notices gaps ("this doesn't mention the rate limiting, which is the whole reason the retry logic exists")
- Restructures for clarity ("these two sections are really one feature")

This is the "bicycle" from the concept doc — the developer is actively engaging with the system's self-description, building and exercising architectural taste. It's not documenting; it's *thinking about the system through the lens of its narrative*.

---

## `/spec` Phase 0.2: Narrative Context

### How it works

The prior knowledge callout already queries graphify and the Obsidian wiki. The Plot Document becomes a third source:

| Source | Query pattern | What it provides |
|--------|--------------|-----------------|
| graphify | "What depends on what?" | Structural facts — nodes, edges, call graphs |
| Obsidian wiki | "What was decided about X?" | Discrete decisions with rationale |
| **Plot Document** | "How does this part of the system work, and why?" | Narrative coherence — the story of a feature or the system |

### Tag-aware confidence

`/spec` Phase 0.2 reads the Plot Document and treats content differently based on annotations:

- **Clean prose** (no tags): reliable context, use with confidence in the spec dialogue.
- **`[!STALE]` sections**: the narrative is known to be wrong. Flag it: "Note: the Plot Document's description of [feature] is stale — [reason]. I'll ground this part of the spec in the code directly rather than the narrative."
- **`[!DRAFT]` sections**: AI-generated, useful but unverified. Use as context but don't treat as authoritative for decisions.
- **No Plot Document**: no narrative context available. Degrades gracefully to graphify + wiki only.

### What this enables

When a developer starts a spec conversation — "I want to add retry logic to the payment flow" — `/spec` Phase 0.2 pulls:

- From **graphify**: the payment module's dependencies and downstream consumers
- From **wiki**: past decisions about error handling strategy
- From **Plot Document**: the narrative of how the payment flow works end-to-end, including the tensions and tradeoffs in its current design

The spec conversation starts with *understanding*, not just facts. The developer doesn't need to re-explain how payments work — the narrative is already loaded. The conversation can focus on the new feature rather than re-establishing context.

---

## Change frequency expectations

For mature projects, the Plot Document should change infrequently. Most code changes don't alter what a feature *is* or *why it works that way* — they change implementation details that the Plot Document intentionally abstracts over.

This means:

- **Most `/wrap` cycles produce "Plot: intact."** The gate check is lightweight and the common case is no findings.
- **`/plot` is run occasionally, not every session.** When the developer wants to bootstrap, when accumulated `[!STALE]` tags warrant attention, or when a significant feature ships and the narrative needs updating.
- **`[!STALE]` annotations may accumulate across sessions.** This is fine. They're visible in the document, they surface in `/spec` Phase 0.2 with appropriate confidence calibration, and they get resolved when someone runs `/plot`.

The system is designed for low-frequency, high-value engagement with the narrative — not constant churn.

---

## Integration with MonsterFlow's measurement layer

MonsterFlow's existing persona drift analysis (rolling-window measurement of persona `load_bearing_rate`, `survival_rate`, etc.) can extend to the Plot Layer:

- **Plot Gate hit rate**: fraction of `/wrap` cycles that produce findings. Trending up = Plot Document falling behind; trending down = well-maintained.
- **Annotation accumulation**: count of `[!STALE]` and `[!DRAFT]` tags over time. A project with growing unresolved annotations isn't engaging with the narrative.
- **Spec quality correlation**: do features with current (tag-free) Plot Document coverage produce fewer `/spec-review` findings than features where the narrative is stale or absent? This is the empirical test of whether narrative context improves specification dialogue.
- **Time-to-resolution**: sessions between a `[!STALE]` annotation being injected and being resolved. Long gaps indicate the team isn't engaging with the editorial pass.

These metrics fit naturally into MonsterFlow's existing `findings.jsonl` / `run.json` infrastructure.

---

## PR-time Plot Gate (CI integration)

MonsterFlow is entirely human-driven today — all commands are initiated by the developer in a Claude Code session. There is no CI integration or GitHub Actions integration anywhere in the pipeline.

The Plot Gate is a natural place to introduce CI for the first time, because the gate was designed for exactly this from the start: read-only, silent, pass/fail with a parseable verdict line. The original Plot Document concept describes two touch points — the developer runs the gate locally (primary mechanism) and it runs automatically at PR time as a merge-blocking safety net. In this design, `/wrap` Phase 3 covers the local touch point. A CI check covers the PR touch point.

### Why the PR gate matters even with `/wrap`

`/wrap` Phase 3 catches drift at the end of the session that *caused* the drift. But not all code changes flow through MonsterFlow's pipeline:

- Another team member pushes changes without running `/wrap`
- An agent in a non-MonsterFlow session modifies code that a chapter describes
- Multiple PRs land in sequence, and the cumulative effect invalidates the narrative even though no single PR did

The PR gate is the safety net that catches drift regardless of how the change was made. It answers: "after this PR merges, will the Plot Document still be accurate?"

### How it works

A GitHub Action runs on every PR targeting the main branch. It:

1. Checks out the branch
2. Runs the Plot Gate in gate mode — same comparison logic as `/wrap` Phase 3, but with the diff scoped to the branch (`git diff main...HEAD`)
3. Outputs findings (if any) and a verdict: **PASS** or **FAIL**
4. If `plot/PLOT.md` doesn't exist, the gate passes immediately — you can't fail a narrative integrity check when there's no narrative

On **FAIL**, the PR is blocked. The developer runs `/plot` to review findings and update the narrative, then pushes the updated Plot Document as part of the PR. This is one of the two touch points from the original concept where the editorial pass happens — encountering drift while you're still in the context of the change that caused it.

### Relationship to `/wrap` Phase 3

The two mechanisms are complementary, not redundant:

| | `/wrap` Phase 3 | PR Gate (CI) |
|---|---|---|
| **Trigger** | End of every MonsterFlow session | Every PR to main |
| **Scope** | Session's changes | Branch's full diff |
| **Action on findings** | Injects `[!STALE]` annotations | Blocks merge |
| **Catches drift from** | MonsterFlow sessions | Any source |
| **Developer context** | In the session, full context available | PR review time, may be a different day |

In the common case where the developer runs `/wrap` at the end of their session and addresses any `[!STALE]` annotations before opening a PR, the CI gate will pass. The CI gate is the backstop for the cases where that didn't happen.

### Implementation note

This is the only part of this design that introduces CI infrastructure to MonsterFlow. It can be implemented independently of the `/wrap` and `/spec` integration — a team could adopt the PR gate first without any MonsterFlow pipeline changes, or adopt the MonsterFlow integration first without CI. The gate logic is the same in both cases; only the trigger and the action on failure differ.

---

## What this design does not address

- **Cross-project narrative.** The Plot Document is per-project. It doesn't capture "how do these three services work together?" across repo boundaries. Cross-project narrative context would require either a multi-repo Plot Document or integration with a cross-repo awareness tool like Rhumb feeding into narrative generation.

- **Bootstrap cost for large existing projects.** The bootstrap flow (analyze codebase, draft everything) can be expensive for large codebases. The existing skill design handles this through scoping (the agent exhausts code analysis before asking questions, and the scope summary lets the human trim), but very large monorepos may need additional scoping heuristics.

- **Plot Document quality bootstrapping.** The first editorial pass on a bootstrapped Plot Document is the most important — it establishes the quality bar. A weak first pass means weak narratives, which means the Plot Gate produces noise, which erodes trust. The design doesn't force engagement at bootstrap time (per the existing skill's principle: "forcing engagement at bootstrap time means nobody starts"), but the quality of the initial editorial pass determines the quality of everything downstream.

- **Team-scale editorial engagement.** The editorial pass builds understanding for the person doing the editing. Everyone else reads the finished document. The concept doc calls this "the bicycle only seats one." Approaches like rotating the editorial pass across team members or pairing on review can partially address this, but they're process decisions outside the scope of this design.

---

## Implementation guidance

This design adds three things to MonsterFlow:

1. **A new `/wrap` phase** (Phase 3) that runs the Plot Gate comparison and injects `[!STALE]` annotations. This is the lightest integration — it reads the Plot Document, compares against code, and writes small annotations when findings exist.

2. **A `/plot` command** that runs the full interactive Plot Document skill (bootstrap, check, draft updates, editorial flow). The existing [Plot skill design](../plot-doc/PLOT_SKILL_DESIGN.md) and [skill implementation](../../code/aice/foundry/foundations-ai-studio/.claude/skills/plot/SKILL.md) are the reference — the MonsterFlow version adds awareness of `[!STALE]`/`[!DRAFT]` annotations and integration with MonsterFlow's other knowledge stores during bootstrap.

3. **Plot Document reading in `/spec` Phase 0.2** that loads narrative context alongside graphify and wiki queries, with tag-aware confidence levels.

The `/wrap` phase and `/spec` integration are the structural changes. The `/plot` command is largely the existing skill, adapted to MonsterFlow's context.
