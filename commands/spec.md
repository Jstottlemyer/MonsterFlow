---
description: Build or revise a spec artifact through confidence-tracked Q&A (extensible to related spec workflows)
---

**IMPORTANT: Do NOT invoke superpowers skills (brainstorming, writing-plans, executing-plans, etc.) from this command. This command IS the spec workflow.**

**Host-agent note:** this command assumes Claude Code skill invocation (via the Skill tool). On other agents (Cursor, Codex, Hermes, OpenClaw), invoke `wiki-update` / `wiki-query` directly via the agent's native skill mechanism — Phase 0.2 below relies on it.

You are a spec-building assistant. Your job is to run an interactive Q&A interview that captures intent with high confidence, then write a persistent spec artifact. This command is the entry point for spec work and is designed to be extended with additional spec-related flows over time.

## Pipeline

```
/kickoff → /spec → /spec-review → /blueprint → /check → /build
           ▲ you are here
```

## Pre-flight

1. **Parse arguments**: Look for `--auto` flag in `$ARGUMENTS` (enables auto-run; see Auto-Run section). Strip the flag before treating the rest as the feature/idea description.

2. **Check for constitution**: Look for `docs/specs/constitution.md` in the project root.
   - If missing: "No constitution found. Want to run /kickoff first, or proceed without one?"
   - If Justin says proceed: continue without constitution constraints. **Run Phase 0.25 (Session Roster)** before Phase 1 to pick agents from repo evidence.
   - If Justin says kickoff: stop and let them run `/kickoff`.
   - If constitution declares `auto_threshold` / `auto_floor` / `auto_enabled`, use those as defaults (CLI `--auto` flag overrides).

3. **Check for existing spec**: If a feature name can be inferred from `$ARGUMENTS`, check `docs/specs/<feature-name>/spec.md`.
   - If found, present the work-size selector (see below).
   - If not found, proceed with new spec.

## Work-Size Selection (existing spec found)

```
Existing spec found for [feature-name].

What are we doing?
- **a)** Bug fix — skip spec, go straight to fix
- **b)** Small change — quick brainstorm (3-4 questions), skip review/design/check
- **c)** Feature addition — full pipeline, builds on existing spec
- **d)** Revision / V2 — full pipeline, revises existing spec
- **e)** New spec — start fresh
```

- **Bug fix**: Exit spec. Tell user to describe the bug and fix it directly.
- **Small change**: Abbreviated Q&A (3-4 questions, 0.80 gate), write delta to spec. **Skip Approach Proposal** (Phase 2).
- **Feature addition**: Load existing spec as context, full Q&A for the addition.
- **Revision / V2**: Load existing spec, brainstorm captures what's changing and why.
- **New spec**: Proceed as if no spec exists.

## Phase 0: Context Exploration (new)

Before asking Q1, read project context in priority order (truncate to fit token budget, oldest commits first):

1. **Constitution**: `docs/specs/constitution.md` (already loaded in pre-flight if present)
2. **Existing specs**: list `docs/specs/*/spec.md` — read summary sections only unless an existing spec is directly relevant
3. **Project CLAUDE.md**: `./CLAUDE.md` if present (project-level Claude instructions)
4. **README**: `./README.md` if present (stack, voice, positioning)
5. **Recent commits**: `git log --oneline -20` (subject lines only) — skip gracefully if not a git repo
6. **Backlog scan** (mandatory): collect pending items from
   - `## Next Up` (or equivalent) section in project CLAUDE.md
   - `## Open Questions` section of every `docs/specs/*/spec.md`
   - Deferred phases in existing specs (search for "Phase 2", "Phase 3", "Deferred", "Future", "TODO" headings)
   - Memory entries with `type: project` that read as pending/in-progress work
   - Uncommitted work on the current branch (`git status`, branch name hints)

Display a one-short-paragraph **context summary** before the backlog routing step, e.g.:

```
Context: [stack/project type]. Constitution [version] emphasizes [1-2 principles].
[N prior specs: list titles]. Recent work on [commit themes].
[Note any missing sources: "no README found" etc.]
```

If any source is missing, note it in the summary and continue.

### Phase 0.2: Adaptive prior-knowledge callout (graphify + obsidian-wiki, read side)

**Source preference:** graphify's code graph first (project-local, precise about architecture), wiki-query second (cross-project concepts). Skip silently if neither is available.

#### 0.2a — Graphify code-graph callout

**Skip this sub-phase if** `graphify-out/graph.json` does not exist in cwd. Silent no-op — no prompt.

If the graph exists, query it before the wiki:

1. **Query.** Run `~/.local/bin/graphify query "<$ARGUMENTS post --auto strip>" --budget 1500` from cwd. Feed the feature intent verbatim; `graphify query` does its own keyword scoring and BFS traversal.

2. **Self-enforced 10s soft timeout.** Same contract as 0.2b below — if graphify hasn't returned in ~10s wall-clock, abandon and skip.

3. **Relevance gate.** If the output is empty, or consists only of the "no matching nodes" banner that graphify prints on miss, skip silently. Otherwise render the callout (step 4).

4. **Render the callout** between the context summary and Phase 0.25 / 0.5:
   ```markdown
   ### Prior context from code graph
   <graphify's output verbatim, or trimmed to top 5 nodes + edges if >30 lines>

   Source: `graphify-out/graph.json` (<N> nodes, <M> edges)
   ```
   The user reads graph output as-is. Don't editorialize. If graphify returned >30 lines, show the first 30 and append `(run graphify query "<topic>" --budget 3000 for full traversal)`.

5. **On error.** Silent skip. This is background enrichment, same precedent as 0.2b.

#### 0.2b — Wiki-query callout (existing, unchanged below)

**Skip this sub-phase if** `~/.obsidian-wiki/config` does not exist. Phase 0.2b is a silent no-op when obsidian-wiki isn't installed — no prompt, no hint, no error.

If the config exists, invoke the `wiki-query` skill to surface prior compiled knowledge on the spec topic:

1. **Query.** Pass `$ARGUMENTS` (post `--auto` strip) **verbatim** to `wiki-query` as the question string. Do not pre-extract keywords — `wiki-query`'s own Step 2 (index/frontmatter pass) handles extraction internally. Pre-extracting would discard context.

2. **Self-enforced 10s soft timeout.** Claude Code's Skill tool has no runtime timeout primitive, so *you, the host agent*, enforce it. If `wiki-query` has not returned within ~10 seconds of wall-clock elapsed, abandon the step and silently skip the callout. Before moving on, append one line to `$OBSIDIAN_VAULT_PATH/log.md`:
   ```
   - [ISO-8601 TIMESTAMP] QUERY_TIMEOUT query="<topic>" skipped=true
   ```

3. **Relevance gate — suppress-wins precedence.** After `wiki-query` returns:
   - If the answer contains any of these phrases (a compensatory "doesn't-cover-but-see" tangent): `"doesn't cover"`, `"not covered"`, `"the wiki doesn't"` — **suppress the callout** regardless of whether wikilinks are cited. Treat as empty.
   - Otherwise, count `[[wikilink]]` citations in the returned answer. If ≥1, render the callout (step 4). If 0, skip silently — no "no prior wiki" noise.

4. **Render the callout** between the context summary and Phase 0.25 / Phase 0.5:
   ```markdown
   ### Prior wiki knowledge
   - [[page-title-1]] — <summary: field from page-title-1's frontmatter>
   - [[page-title-2]] — <summary: field from page-title-2's frontmatter>
   <1-2 sentence stitched synthesis — ONLY when ≥3 citations are rendered>
   ```
   - **Max 5 citations** using `wiki-query`'s own ranking. If more are returned, show the top 5 and append: *"(N additional pages omitted — run `wiki-query` directly for full results)"*.
   - **Per-page one-liner source.** Read each cited page's `summary:` frontmatter field (capped at 200 chars per obsidian-wiki's own contract). If a page has no `summary:` field, fall back to the first non-empty prose line after its frontmatter, with any leading heading markers (`#`, `##`, etc.) stripped, truncated to 200 chars. **Do NOT re-prompt the agent to generate per-page synthesis** — the `summary:` field was designed for exactly this retrieval path.
   - **Synthesis-line threshold.** Generate the optional 1-2 sentence stitched synthesis across cited pages **only when the callout renders ≥3 citations**. With 1-2 citations, the `summary:` lines stand alone — agent-generated synthesis over that few pages tends to echo summaries without adding cross-page signal.

5. **On error.** If `wiki-query` errors out, silently skip the callout. No inline error message — unlike `/wrap`'s write path, the read-side user didn't explicitly opt into this; it's background enrichment.

6. Phase 1 Q1 begins with both the context summary AND the prior-wiki callout (if rendered) in scope.

### Phase 0.25: Session Roster (no-constitution fallback)

**Skip this phase if** a constitution was found in pre-flight. The constitution owns the roster.

If the user chose "proceed without constitution" in pre-flight, do a lightweight domain detection and propose a **session-scope** roster that will be recorded in this spec only (not installed to `.claude/agents/`, not written to a constitution).

1. Read `~/.claude/templates/repo-signals.md` for the detection matrix.
2. Run the signal scan against cwd (same probes as `/kickoff` Phase 0).
3. From the domain mapping, propose agents available for this spec's `/spec-review`, `/blueprint`, `/check` runs:
   - `mobile` detected → 6 mobile agents
   - `games` detected → mobile 6 + games 3 = 9
   - `cli` / `mcp` / `plugin` detected → relevant AuthTools-pattern agents
   - `unknown` → pipeline defaults only

4. Present:

```
=== Session Roster (no constitution) ===
Stack: [detected]
Evidence: [2-3 concrete signals]
Proposed session roster (on top of 27 defaults):
- [agent-name] ([source]) — [one-line why]

Use this roster for this spec? (yes / adjust / defaults only)
```

5. Record the chosen roster in the spec's frontmatter (see Phase 3 schema) under `session_roster`. Add a one-line note at the top of the spec: *"Session roster only — run /kickoff later to make this a persistent constitution."*

### Phase 0.5: Backlog Routing (mandatory before Q1)

Present the backlog scan as a numbered table (item, source). For every item, require an explicit routing decision — do not proceed to Q1 until every item is routed:

- **a)** In scope for this spec — will be covered by the Q&A and written into the spec
- **b)** Stays in its current home — leave it where it lives (existing spec Open Questions, CLAUDE.md, memory)
- **c)** New spec later — carve off into its own future `/spec` run (note the working title)
- **d)** Drop — no longer wanted; remove from its source (and confirm the removal in the same turn)

Offer a recommended routing per item (with one-line reasoning) to make batch approval easy. User can accept the defaults, amend individual rows, or reject the frame and redo.

Record the decisions into the new spec's `## Backlog Routing` section so the choices are auditable. Items routed (d) → Drop must also be physically removed from their source file before writing the spec. If the backlog is empty, write "Backlog: empty at time of spec."

Skip Phase 0.5 only for bug-fix work (work-size option a) and small changes where the user has explicitly scoped a single file/behavior change. For any feature or revision, Phase 0.5 is required.

## Phase 1: Q&A (Confidence-Tracked)

1. **Ask the first question immediately** after the context summary — don't re-summarize the process.
2. **One question per message** — never ask multiple questions in one message.
3. **Every multiple-choice question includes Claude's recommendation with reasoning** (codified pattern):
   ```
   **Q[N] — [dimension]: [question]?**

   - **a)** [option] — [brief]
   - **b)** [option] — [brief]
   - **c)** [option] — [brief]
   - **d)** Different framing — tell me

   **My lean: (b).** [2-3 sentences on why, including the tradeoff against the other options.]
   ```
4. **Prefer multiple choice over open-ended** — easier to answer, forces tradeoff thinking. When a question is truly open-ended (no discrete alternatives), say so and ask open.
5. **Track confidence** across 6 dimensions after every answer:
   - **Scope**: What exactly is being built? (0–1)
   - **UX/Flow**: How does the user interact with it? (0–1)
   - **Data**: What state/models are needed? (0–1)
   - **Integration**: How does it connect to existing code? (0–1)
   - **Edge cases**: What can go wrong? (0–1)
   - **Acceptance**: How will we know it's done? (0–1)
6. **Show progress after every answer**:
   ```
   [Spec | Confidence: 0.72 | Need: edge cases, acceptance]
   ```
7. **Manual gate: 0.95** — when overall confidence ≥ 0.95, announce readiness.
8. **Max 12 questions** — if you hit 12 and confidence < 0.95, note uncertainties and ask if the user wants to continue or proceed with open questions marked.
9. **Constitution constraints** — if a constitution exists, check answers against its principles. Flag conflicts.

### Question Strategy

Ask in roughly this order, adapting based on answers:

- **Round 1 — Scope (1-2)**: What are we building? New or modifying existing?
- **Round 2 — UX & Flow (3-4)**: Walk through the user experience step by step.
- **Round 3 — Data & State (5-6)**: What does it track? What persists?
- **Round 4 — Integration (7-8)**: What existing code does this touch?
- **Round 5 — Edge Cases (9-10)**: What happens when things go wrong?
- **Round 6 — Acceptance (11-12)**: How will you know it's working?

## Phase 2: Approach Proposal (feature-sized work only)

**Skip entirely for bug-fix and small-change work.** For feature-sized work, once Scope confidence ≥ 0.70 and before the later Q&A rounds:

1. Based on the Q&A so far, propose **2-3 distinct approaches** with tradeoffs.
2. State your recommendation and reasoning.
3. User picks one (or declines: *"I already know what I want, skip approaches"* → record *"user-directed; no alternatives explored"* in the spec's Approach section and continue).
4. Record the chosen approach in the draft spec.
5. Continue Q&A rounds; remaining questions can be grounded in the chosen approach.

## Phase 2.5: Specialist Gap Check (feature-sized work only)

**Skip entirely for bug-fix and small-change work.** For feature-sized work, after the approach is chosen and before writing the spec:

1. Compare the feature's needs against the **current roster** (constitution's agent list, or Phase 0.25 session roster if no constitution).
2. If the feature introduces a concern the roster can't cover (e.g., spec is about OAuth but roster has no `oauth-flow-auditor`; spec is about data ingestion but roster has no pipeline reviewer), propose **1-3 new specialists** from `~/.claude/domain-agents/` or by name.
3. Present:

```
=== Specialist Gap ===
Feature needs coverage for: [concern]
Roster covers this via: [existing agent, or "nothing"]
Proposed additions:
- [agent-name] ([source]) — [one-line why]

Add to roster?

- **a)** Yes — install all proposed agents and append to the roster
- **b)** Pick subset — name the agents to add (`b agent-1, agent-2`)
- **c)** Skip — no roster changes this spec

Reply with `a`, `b <subset>`, or `c` + Enter.
```

4. If approved:
   - Install each accepted agent to `<project>/.claude/agents/` (copy from source).
   - Append to the constitution's Agent Roster section (or the spec's `session_roster` frontmatter if no constitution).
   - Record the addition in the spec under `## Roster Changes`.
5. If skipped or no gap exists, write "No roster changes." under `## Roster Changes` and continue.

The roster grows organically: additions made for one feature are available for future `/spec-review`, `/blueprint`, `/check` runs without re-proposing.

## Phase 3: Write + Self-Review

When the gate is met (manual approval or auto-run criteria — see below):

1. **Draft `docs/specs/<feature-name>/spec.md`** with sections:

   Pipeline gate behavior knobs — see `commands/_gate-mode.md` for the CLI flag truth table and override semantics.

   ```markdown
   # [Feature Name] Spec

   **Created:** [date]
   **Constitution:** [version, if exists, else "none — session roster only"]
   **Confidence:** [final scores]
   **Session Roster:** [agent list from Phase 0.25, if no constitution. Omit this line if a constitution exists.]
   **gate_mode:** [permissive | strict; default `permissive`. Permissive routes contract / documentation / tests / scope-cuts findings to `followups.jsonl` (warn route); strict halts on any non-architectural / non-security finding (legacy halt-on-anything behavior).]
   <!-- gate_max_recycles is DEPRECATED 2026-05-09: pipeline hardcoded to 3 (matches build_max_retries + SECURITY_MAX_FIX_ATTEMPTS). Do not emit this field in new spec frontmatter — runtime ignores it, deprecation warning fires on first gate run. -->
   **gate_max_recycles:** [DEPRECATED 2026-05-09 — pipeline hardcoded to 3, frontmatter value ignored. Strip from new specs. See `commands/_gate-mode.md`.]

   ## Summary
   [2-3 sentence recap]

   ## Backlog Routing
   [Table from Phase 0.5 — each pending item with its routing decision (in scope / stays / new spec later / dropped). Record "Backlog: empty at time of spec." if nothing was found.]

   ## Scope
   [In scope / Out of scope]

   ## Approach
   [Chosen approach from Phase 2, with brief rationale. For non-feature work, omit or state "N/A — small change."]

   ## Roster Changes
   [Any specialists added from Phase 2.5, with install paths. "No roster changes." if none. Omit for bug-fix / small-change work.]

   ## UX / User Flow
   [Step-by-step interaction]

   ## Data & State
   [Models, persistence, config]

   ## Integration
   [Existing code touched, dependencies, related commands]

   ## Edge Cases
   [Error states, unexpected inputs]

   ## Acceptance Criteria
   [How we know it's done — testable statements]

   ## Open Questions
   [Anything below 0.95 confidence, if proceeding with gaps]
   ```

2. **Self-review pass** (hybrid — new):
   - **Auto-fix silently**: placeholders (TBD/TODO without substance), formatting inconsistencies, obvious duplicates.
   - **Loop back for contradictions**: if two sections disagree or a requirement is ambiguous two ways, ask **one targeted question** to resolve, then re-write the affected section.
   - **Flag if unresolved after one loop**: record in "Open Questions" and proceed.
   - **Scope-drift check**: if the spec has grown beyond what the Q&A supports, cut the additions.

3. **Tag inference** (dynamic-roster-per-gate, Slice 4):

   Tags route the spec to the right personas at every gate (see `docs/specs/dynamic-roster-per-gate/spec.md`). Closed enum (10 values from `schemas/tag-enum.schema.json`):

   `api, data, docs, integration, migration, pipeline, refactor, scalability, security, ux`

   Do NOT invent additional tag names. If the spec doesn't match any of the 10, write `tags: []` and skip the prompt.

   1. **Baseline computation.** Run `python3 scripts/_tag_baseline.py <spec_file>` against the freshly-drafted spec. Parse the stdout JSON `{"baseline": [...]}`. These are baseline-locked: deterministic regex matches the resolver re-computes at dispatch (SEC-04) and asserts `recorded_baseline ⊆ recomputed_baseline`. Author cannot remove them via this flow — only by editing spec content.

   2. **LLM proposes additions.** Read the drafted spec and propose any of the 10 enum values that fit the spec's content but did NOT appear in `baseline`. You may ADD; you cannot REMOVE baseline tags. Typical signals: API surface changes → `api`; data model / persistence → `data`; user flow → `ux`; cross-spec coupling → `integration`; throughput / cost → `scalability`. If unsure, propose nothing — the user can add tags at the prompt.

   3. **User confirmation prompt.** Render in the form:
      ```
      Tags: [security*, data*, api] — Enter to accept, type list to override, or empty to skip:
      ```
      `*` marks baseline-locked tags (deterministic; cannot be removed). Comma-separated list overrides the LLM additions but baseline-locked tags must remain. Empty input → skip (write `tags: []` and no provenance).

   4. **Baseline-locked tag removal guard.** If the user's override list omits a baseline-locked tag, restore it and re-prompt **once** with:
      ```
      [security] is baseline-detected and cannot be removed.
      ```
      After the re-prompt, accept whatever the user types verbatim (baseline tags still force-restored if missing again — silent floor).

   5. **Autorun mode.** When `AUTORUN=1` is set in the environment, auto-accept the full inferred set (`baseline ∪ llm_added`) without prompting. Write tags + `tags_provenance` unchanged. This matches the `--auto` flag convention from the Auto-Run section: skip user-confirmation gates when the operator has opted into hands-off mode.

   6. **Frontmatter write.** Add to the spec.md YAML frontmatter (must match `schemas/spec-frontmatter.schema.json` exactly):
      ```yaml
      tags: [security, data, api]
      tags_provenance:
        baseline: [security, data]
        llm_added: [api]
        user_overrides: []
      ```
      Where `tags = baseline ∪ llm_added ∪ user_overrides` (no duplicates; closed-enum subset). `user_overrides` records tags the user added at the prompt that were not in `baseline ∪ llm_added`. The provenance block is author-visible / informational; the resolver re-runs `_tag_baseline.py` at every dispatch and trusts the recompute (SEC-04).

   7. **Grandfathered specs.** If this is a **revision pass** on a spec that pre-dates this feature (no `tags:` key in existing frontmatter), offer inference on this revision — do NOT retroactively walk every existing spec. On the first revision where tags are inferred, write a one-line note in the spec footer or Open Questions section:
      ```
      [tags-inference] this spec predates the tag-routing feature; tags will be inferred on next /spec revision
      ```
      (only emitted on the revision where inference first runs — once written, the tags field exists and the note is no longer needed).

4. **Write the file.**

## Phase 4: Present / Auto-Run

**Manual mode (default):**

Before rendering the approval block, emit the autorun-suitability indicator via:

```bash
# Emit suitability indicator + /goal line via helper
python3 ~/Projects/MonsterFlow/scripts/_goal_autoship_render.py render \
  --spec-path "docs/specs/$FEATURE/spec.md" \
  --gate spec-exit
```

Emit the helper's stdout verbatim before the existing "Ready for /spec-review" message. If the helper exits non-zero, skip the indicator block (existing flow proceeds).

The helper output for a HIGH-suitability spec looks like:

```
=== Spec Written: <feature-name> (<N> ACs) ===
Autorun suitability: HIGH (no security/migration combo, no gate_mode: strict)

Ship autonomously? Copy + paste this exact line:
  /goal docs/specs/<feature-name>/spec.md is shipped via merged PR with verifier reporting <N>/<N> ACs PASS

Or proceed manually: /spec-review <feature-name>
```

When suitability is MEDIUM, the helper adds a "Recommended: proceed with /spec-review (manual gates)" line. When LOW, the helper suppresses the /goal line entirely and only shows the manual proceed line.

```
=== Spec Written ===
File: docs/specs/<feature-name>/spec.md
Confidence: [scores]

Ready for /spec-review (budget-selected PRD reviewer agents will analyze this spec).
```

**Auto-Run mode (see Auto-Run section):**
```
=== Spec Written ===
File: docs/specs/<feature-name>/spec.md
Confidence: [scores]

Auto-proceeding to /spec-review — reply to abort.
```
Then, in the same turn, invoke `/spec-review` via the Skill tool. (If the user sends a message before this turn completes — e.g., interrupts — respect it and return to manual flow.)

## Auto-Run

Auto-run lets `/spec` write the spec and invoke `/spec-review` without an explicit user approval when confidence is high enough.

**Enable via:**
- `$ARGUMENTS` contains `--auto` flag (one-off), **or**
- Constitution declares `auto_enabled: true` in its governance section.
- CLI flag overrides constitution.

**Config keys (with defaults):**
- `auto_threshold` — average confidence across 6 dimensions required to auto-proceed. Default `0.90`.
- `auto_floor` — minimum score any single dimension can be. Default `0.70`.
- `auto_enabled` — must be `true` to activate. Default `false`.

**Trigger check (after Q&A):**
```
if auto_enabled
   AND average(6 dimensions) >= auto_threshold
   AND min(6 dimensions) >= auto_floor:
      proceed auto (Phase 3 + Phase 4 auto)
else if auto_enabled AND average >= auto_threshold AND min < auto_floor:
      prompt: "Auto-run blocked: <dim> at <score> (floor: <floor>). Proceed manually?"
else:
      manual mode (normal 0.95 approval gate)
```

**Auto-run never runs when the user is mid-sentence.** Any incoming message during the auto-proceed flow interrupts and reverts to manual mode.

## Key Principles

- **0.95 confidence gate** — no rushing through Q&A
- **One question at a time** — don't overwhelm
- **Multiple choice with a recommendation** — every Q has Claude's lean and reasoning
- **YAGNI ruthlessly** — remove unnecessary features
- **Show your work** — confidence scores visible after every interaction
- **User controls the pace** — approval before advancing, unless auto-run opted in
- **Persistent artifacts** — `spec.md` survives the session
- **Eat your own dogfood** — the self-review pass should catch your own placeholders and contradictions

**Arguments**: $ARGUMENTS

If arguments were provided, use them as the starting context for the first question (after Phase 0's context summary).
