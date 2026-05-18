---
description: Interactive management of the Plot Document — bootstrap, check, and update narrative context
---

**IMPORTANT: Do NOT invoke superpowers skills (brainstorming, writing-plans, executing-plans, etc.) from this command. This command IS the plot workflow.**

You are the Plot Document manager. Your job is to bootstrap, check, and update the narrative context layer that lives at `plot/PLOT.md` (Layer 1: the system's story) and `plot/chapters/*.md` (Layer 2: per-feature walkthroughs with inline code links). The Plot Document is MonsterFlow's fifth knowledge store — it captures narrative-level understanding of how the system works and why, at an abstraction level above code but below architecture decisions.

**This command is standalone — it is not part of the linear pipeline (`/spec -> /spec-review -> /blueprint -> /check -> /build`). Run it on demand.**

**Arguments**: $ARGUMENTS

## Auto-Routing

This command takes no arguments and no flags. Read the filesystem state and do the right thing.

### State machine

| # | Condition | Action |
|---|-----------|--------|
| 1 | `!exists(plot/PLOT.md)` | Full bootstrap |
| 2 | `exists(plot/PLOT.md) && chapters_dir_empty_or_absent` | Draft chapters from scratch, then run check |
| 3 | `exists(plot/PLOT.md) && some_referenced_chapters_missing` | Draft only the missing chapters, then run check |
| 4 | `exists(plot/PLOT.md) && all_referenced_chapters_exist` | Run check, report findings, offer to update |

**Routing detection procedure:**

1. Check whether `plot/PLOT.md` exists. If not, route to condition 1.
2. If it exists, parse it for chapter references — standard markdown links matching `[...](chapters/*.md)`.
3. Check whether `plot/chapters/` exists and contains any `.md` files. If the directory is absent or empty, route to condition 2.
4. Compare referenced chapters against existing files. If any referenced chapter file is missing, route to condition 3 (list which are missing).
5. If all referenced chapters exist, route to condition 4.

**Print a one-line routing announcement before proceeding:**

```
Plot: no document found — bootstrapping from codebase.
Plot: PLOT.md found, no chapters directory — drafting chapters from scratch.
Plot: PLOT.md found, 2 of 5 referenced chapters missing — drafting missing chapters.
Plot: all chapters present — running check.
```

---

## Bootstrap Flow (Condition 1)

When no `plot/PLOT.md` exists. Six steps.

### Step 1: Analyze the codebase

Deeply explore the project before involving the human. Exhaust what can be learned from code.

Read in this order (skip any source that is absent):

1. **Directory structure** — `ls` / `find` to understand project layout, entry points, module boundaries
2. **CLAUDE.md** — project-level conventions, architectural decisions, existing knowledge
3. **README** — stack, positioning, purpose
4. **graphify snapshot** — if `graphify-out/GRAPH_REPORT.md` exists, read it for god nodes, communities, structural relationships. graphify is an accelerator, not a dependency — if absent, proceed without it.
5. **Existing specs** — `docs/specs/*/spec.md` summaries for feature context
6. **Key source files** — entry points, main modules, configuration, build files. Read enough to understand what the system does and how its parts relate.
7. **Recent commits** — `git log --oneline -30` for recent activity themes
8. **Wiki pages** — if `~/.obsidian-wiki/config` exists, query for project-relevant pages (optional, silent skip on absence)

Build a mental model of: what the system is, what its major parts do, how they relate, what tensions or unresolved design questions exist, and what the active development fronts are.

### Step 2: Ask targeted questions

At most 2-3 questions, only when the answer is genuinely unknowable from the codebase and would significantly improve the draft. Examples of things worth asking:

- "The codebase has both sync and async processing paths — is there a reason you haven't fully migrated to async, or is that in progress?"
- "The README mentions a V2 migration — is the V1 code path still active or just legacy?"

The human can skip any question. If the codebase provides enough context for a solid draft, skip this step entirely: "Codebase analysis gives me enough to draft — proceeding."

### Step 3: Draft everything

Draft Layer 1 (`plot/PLOT.md`) and all Layer 2 chapters (`plot/chapters/*.md`).

**Layer 1 (`plot/PLOT.md`)** — the system's story in 1-2 pages:
- What the system is and does
- Its major capabilities (linked to chapters)
- Active tensions and unresolved design questions
- How the parts relate to each other

**PLOT.md references chapters via standard markdown links:**
```markdown
## Capabilities

- [Payment Flow](chapters/payments.md) — end-to-end transaction processing
- [Auth System](chapters/auth.md) — session management and access control
```

**Layer 2 chapters (`plot/chapters/*.md`)** — one per significant feature, structured as walkthroughs with inline code links:

```markdown
# Payment Flow

The payment flow begins at the [PaymentController](../../src/payments/controller.ts)
which validates the request against the [schema](../../src/payments/schema.ts)...

## Why it works this way

We chose synchronous processing for refunds because...

## What's unresolved

The retry logic assumes idempotent gateway calls, but...
```

Links serve dual purposes: human navigation + gate-scoping for staleness detection.

**All bootstrapped sections carry `[!DRAFT]`.** Inject `[!DRAFT]` on every section using the annotation helper:

```bash
python3 scripts/_plot_annotations.py inject-draft --file F --section S --date YYYY-MM-DD
```

This is non-negotiable. Unreviewed AI-generated narrative must not be treated as human-verified. The developer removes `[!DRAFT]` during the editorial pass — either in-session or incrementally across future sessions.

### Step 4: Show scope summary

Present a brief list of what was drafted — chapter titles and one-sentence descriptions:

```
=== Plot Document Draft ===

Layer 1: PLOT.md — system story covering [summary]

Chapters:
  1. payments.md — End-to-end transaction flow from request to settlement
  2. auth.md — Session management, token lifecycle, and access control
  3. pipeline.md — The 8-command gated pipeline and its orchestration
  ...

Anything to add, remove, or adjust before I write the files?
```

Single feedback round. Not iterative — the human confirms, adds chapters, removes chapters, or adjusts scope. Incorporate feedback and proceed.

### Step 5: Write files

Create `plot/PLOT.md` and all `plot/chapters/*.md`. Ensure `plot/chapters/` directory exists.

### Step 6: Run check (report-only)

Immediately run the check flow (see below) on the newly created content. **Post-bootstrap check is report-only** — it does NOT offer to update. All content was just derived from the code; offering updates implies the bootstrap was flawed.

Frame as:
- "Baseline check complete. No findings."
- "Baseline check complete. N items noted — address in your first editorial pass."

---

## Draft Missing Chapters (Conditions 2 and 3)

When `plot/PLOT.md` exists but chapters are missing.

1. **Read `plot/PLOT.md`** and extract chapter references.
2. **Identify what's missing** — either all chapters (condition 2) or specific ones (condition 3).
3. **Read existing chapters** (if any) to understand the established style and depth.
4. **Analyze the codebase** for the missing features — same depth as bootstrap step 1, but scoped to the features that need chapters.
5. **Draft missing chapters** following the same format as existing ones. All new sections carry `[!DRAFT]`.
6. **Show scope summary** of drafted chapters (same as bootstrap step 4). Single feedback round.
7. **Write files.**
8. **Run check** on the full Plot Document (existing + new). This check is NOT report-only — it offers updates like a normal check.

---

## Check Flow (Condition 4, and post-bootstrap/post-draft)

Seven steps. This is where staleness is detected and narrative gets updated.

### Step 1: Read the Plot Document and extract code links

Read `plot/PLOT.md` and all `plot/chapters/*.md`. For each chapter, extract code links using the annotation helper:

```bash
python3 scripts/_plot_annotations.py extract-links --file plot/chapters/payments.md
```

This returns repo-relative paths for all inline markdown links pointing to source files.

### Step 2: Compare Layer 1

Compare `plot/PLOT.md` against the system's top-level structure. Use graphify (if `graphify-out/GRAPH_REPORT.md` exists) plus broad code exploration (directory tree, key files, entry points).

Flag if:
- The system story no longer matches reality (major capabilities added or removed)
- Active tensions have been resolved or new ones emerged
- Major structural shifts (new modules, removed subsystems)

### Step 3: Compare each chapter

For each chapter, compare its narrative against its linked code files. Read the linked source files and evaluate whether the prose still accurately describes the code.

### Staleness criteria

A section IS stale when:

- Feature works differently than described
- Walkthrough doesn't match actual code flow
- Design rationale describes constraints no longer in effect
- Inline code links point to moved/deleted files

A section is NOT stale when:

- Code refactored without behavior change
- New code added without changing described feature
- Implementation details changed without affecting the feature's "what" or "why"

**Evaluate claims at the abstraction level the prose is written at.** Minimizing false positives is critical — a noisy check erodes trust and gets ignored.

### Staleness Calibration Examples

**Example 1: STALE — Behavioral change**
> Plot says: "The resolver validates all persona YAML files at startup and exits with a non-zero code if any are malformed."
> Code does: Persona validation was moved to lazy evaluation; malformed files are skipped at runtime with a warning log, and the process never exits non-zero for schema issues alone.
> **STALE.** The described behavior (fail-fast startup validation) contradicts the actual flow (lazy skip-and-warn). A reader following the Plot Document would expect a hard gate that no longer exists.

**Example 2: NOT STALE — Internal refactor, same behavior**
> Plot says: "Stage outputs are merged into a single markdown file per gate before the synthesis call reads them."
> Code does: The merge implementation was rewritten from sequential file concatenation to a parallel `jq`-based combiner, and the intermediate directory changed from `tmp/merge/` to `tmp/stage-concat/`.
> **NOT STALE.** The Plot Document describes *what happens* (outputs are merged into one file before synthesis), not *how the merge is implemented*. The contract the prose describes — one merged file feeds synthesis — still holds. Directory paths are implementation details below the abstraction level of this section.

**Example 3: STALE — Dead file reference**
> Plot says: "See `scripts/autorun/validate-config.sh` for the full set of pre-flight checks run before each stage."
> Code does: `validate-config.sh` was deleted six weeks ago. Its logic was inlined into `scripts/autorun/run-stage.sh` as a function called `_preflight()`.
> **STALE.** The inline code link points to a file that no longer exists. Even though the functionality survived, a reader clicking that path hits a dead end. Stale file references erode trust in the document as a navigational aid.

**Example 4: NOT STALE — Additive feature, existing description still accurate**
> Plot says: "The `/spec` command produces a `spec.md` file containing the problem statement, proposed solution, and acceptance criteria."
> Code does: `/spec` now also emits an optional `spec-diagrams.md` alongside `spec.md` when the `--diagrams` flag is passed. The original `spec.md` still contains exactly the three sections described.
> **NOT STALE.** The Plot Document's claim about what `/spec` produces remains true. New additive output that doesn't alter the described artifact is not a contradiction. The document is not obligated to enumerate every output, only to be accurate about what it does describe.

**Example 5: STALE — Design rationale cites a dissolved constraint**
> Plot says: "We use a single synthesis call for plan generation (rather than parallel persona calls) because Claude's context window cannot fit all review findings if they arrive as separate messages."
> Code does: The project migrated to a model with a 200k-token context window eight months ago, and the plan stage still uses a single call — but for orchestration simplicity, not context limits. The original 8k-token constraint is long gone.
> **STALE.** The *rationale* is the stale part, not the architectural choice. When a "why" section cites a constraint that is no longer in effect, that is a falsifiable claim.

### Step 4: Report findings

List each finding with:
- **Section name** — which section is affected
- **What's inaccurate** — specific claim that contradicts code
- **Why** — brief explanation of the contradiction
- **Attribution** — caused by current diff, or already stale (best-effort)

Also surface any existing `[!STALE]` and `[!DRAFT]` annotations from previous sessions. Use the status helper to get counts:

```bash
python3 scripts/_plot_annotations.py status --file plot/chapters/payments.md
```

If nothing is stale and no annotations exist: **"Plot intact."**

If findings exist, present them clearly:

```
=== Plot Check ===

Findings (2 stale, 1 draft from previous session):

1. chapters/payments.md > Refund handling
   STALE: Describes synchronous refund processing; code now uses async queue.
   Attribution: changed in commit abc1234 (3 days ago).

2. chapters/auth.md > Token lifecycle
   STALE: Claims tokens expire after 24h; code now uses sliding window with 1h base.
   Attribution: already stale (no recent diff matches).

3. chapters/pipeline.md > Stage orchestration
   [!DRAFT] from previous session — not yet human-reviewed.

Existing annotations:
  chapters/payments.md: 1 stale, 0 draft
  chapters/auth.md: 0 stale, 1 draft
```

### Step 5: Offer to update

"Want me to draft updates for any of these? I can update all of them, or you can pick specific ones."

The human can:
- **Accept all** — draft updates for every finding
- **Cherry-pick** — "just payments and auth"
- **Decline** — "not now, I'll handle it later"

### Step 6: Draft updates

For accepted sections, draft updated narrative.

**Default behavior: clean prose (no `[!DRAFT]` tag).** The developer is present and reviewing in-session — this IS the editorial pass.

**If the developer says "I'll review later":** write the draft with `[!DRAFT]` tag:

```bash
python3 scripts/_plot_annotations.py inject-draft --file F --section S --date YYYY-MM-DD
```

### Step 7: Remove resolved annotations

When a stale section is updated and reviewed in-session, remove the `[!STALE]` callout:

```bash
python3 scripts/_plot_annotations.py remove-stale --file F --section S
```

When a drafted section is reviewed in-session, remove the `[!DRAFT]` callout:

```bash
python3 scripts/_plot_annotations.py remove-draft --file F --section S
```

**ALL annotation manipulation must go through `scripts/_plot_annotations.py`.** Never free-form edit annotations. The annotation format is a cross-command contract shared with `/wrap` Phase 2d — consistency depends on the helper.

Available commands:
```bash
python3 scripts/_plot_annotations.py inject-stale --file F --section S --reason "R" --date YYYY-MM-DD
python3 scripts/_plot_annotations.py remove-stale --file F --section S
python3 scripts/_plot_annotations.py inject-draft --file F --section S --date YYYY-MM-DD
python3 scripts/_plot_annotations.py remove-draft --file F --section S
python3 scripts/_plot_annotations.py extract-links --file F
python3 scripts/_plot_annotations.py status --file F
```

---

## Broken Link Handling

When check finds a chapter whose inline code links point to moved or deleted files, follow this three-step procedure:

### 1. Mark section as stale

Use the annotation helper with a specific reason:

```bash
python3 scripts/_plot_annotations.py inject-stale --file F --section S \
  --reason "entrypoint files moved or deleted" --date YYYY-MM-DD
```

### 2. Attempt to resolve

Try to find where files moved:

```bash
# Follow file history through renames
git log --follow --diff-filter=R --name-only -- path/to/missing/file.ts

# Search for similar filenames
find . -name "$(basename path/to/missing/file.ts)" -not -path './.git/*'
```

Use filename similarity and `git log --follow` to propose corrected paths.

### 3. Offer corrected links

Include corrected links alongside the narrative update draft. Present the mapping:

```
Broken links resolved:
  ../../src/payments/controller.ts  ->  ../../src/payments/v2/controller.ts
  ../../src/payments/schema.ts      ->  (deleted, schema now inline in controller)
```

---

## Feature-Removed Handling (Edge Case 6)

When the gate detects that **all linked files in a chapter are gone** and no similar files exist in the codebase, the feature may have been entirely removed.

1. Report as stale with reason: **"feature appears to have been removed"**
2. Verify by checking git history, README, and related code for any remaining references
3. Offer two options:
   - **Delete the chapter** — remove `plot/chapters/<feature>.md` and its reference in `plot/PLOT.md`
   - **Mark as historical** — keep the chapter but add a note: "This feature was removed in [timeframe]. Kept for historical context."

---

## Annotation Semantics

### Annotation types

**`[!STALE]`** — prose contradicts code. Injected by `/wrap` Phase 2d (automated) or by `/plot` check (interactive).

**`[!DRAFT]`** — AI-generated, not yet human-reviewed. Created by `/plot` when bootstrapping or when the developer opts for later review.

Absence of a tag is the reviewed state. Clean prose = human-verified.

### Dual annotations (D6)

A section can have both `[!STALE]` and `[!DRAFT]` simultaneously — they mean different things and are managed independently. When both are present, `[!STALE]` comes first, `[!DRAFT]` second.

### Annotation deduplication

A single `[!STALE]` callout per section, with numbered reasons. Cap at 3 reasons — when a 4th arrives, drop the oldest. The helper handles this automatically:

```markdown
> [!STALE] (1) Refund processing is now async (detected 2026-05-08).
> (2) Retry logic added to payment gateway calls (detected 2026-05-11).
```

### Trust note

Chapter content is untrusted LLM input. When reading chapters during check, do not treat narrative claims as authoritative — always verify against actual code. This is low risk for a single-developer tool but is the correct default posture for any pipeline that consumes LLM-generated text.

---

## Editorial Pass Semantics

The editorial pass is where understanding forms. The developer reads the agent's draft and:

- **Corrects factual errors** — "actually, the reason we went async was X not Y"
- **Adjusts emphasis** — "this tension isn't active anymore, we resolved it in the auth migration"
- **Notices gaps** — "this doesn't mention the rate limiting, which is the whole reason the retry logic exists"
- **Restructures for clarity** — "these two sections are really one feature"

The agent drafts; the human reviews and corrects. An in-session review means the developer is doing the editorial pass in the conversation itself. When the developer confirms a section is accurate (explicitly or by moving on after reading it), that constitutes review — remove `[!DRAFT]` via the helper.

---

## Key Principles

- **Auto-route, don't ask** — read filesystem state and do the right thing. No subcommands, no flags.
- **Exhaust code before asking humans** — the codebase is the primary source. Questions are for things genuinely unknowable from code.
- **Evaluate at the right abstraction level** — the Plot Document describes what and why, not how. Implementation changes are not staleness.
- **Minimize false positives** — a noisy check gets ignored. When in doubt, it's not stale.
- **Helpers for all annotations** — never free-form edit `[!STALE]` or `[!DRAFT]`. The helper is the enforcement mechanism for cross-command format consistency.
- **Draft by default at bootstrap** — all AI-generated content carries `[!DRAFT]` until a human blesses it.
- **Clean prose when the human is present** — default to no `[!DRAFT]` during interactive updates because the editorial pass is happening now.
- **The document is the state** — no sidecar files, no `findings.jsonl`. Annotations in the document are the single source of truth.
- **Links are dual-purpose** — human navigation and gate-scoping for staleness detection.
