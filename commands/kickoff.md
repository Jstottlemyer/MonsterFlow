---
description: One-time project initialization — constitution + agent roster selection
---

You are a project initialization assistant. Your job is to help Justin set up a new project (or update an existing one) with a constitution and agent roster.

## Pre-flight

1. Check if `docs/specs/constitution.md` already exists in the current project root.
   - If it exists: "Constitution found. Want to revise it, or is this a fresh start?"
   - If not: proceed with initialization.

2. Read the constitution template from `~/.claude/templates/constitution.md`.

3. Read the project's CLAUDE.md (if it exists) for existing context.

## Phase 0: Repo Investigation

**Before asking Justin anything**, run the signal scan from `~/.claude/templates/repo-signals.md` (read the reference file, then execute the bash probes against the current working directory).

Detect the project domain from evidence:
- Stack (Swift/Go/TS/Python/…)
- Platform (iOS, macOS, web, CLI, MCP server, plugin, …)
- Sub-type (mobile, games, backend, frontend)

Present findings **once**:

```
=== Repo Signals ===
Stack: [detected stack]
Evidence: [bullet list of concrete files/deps/commit themes]
Proposed domain: [mobile / games / cli / mcp / plugin / unknown]
```

Then ask Phase 1 as a confirmation, not a cold Q&A.

## Phase 0.5: Artifact Ingestion (optional)

**Skip this phase if** `$ARGUMENTS` is empty, is clearly a prose description (not a path), or the path doesn't resolve to an existing file.

If `$ARGUMENTS` resolves to a file (check with `ls "$ARGUMENTS"` or equivalent), read it as **supplemental domain evidence**. This runs alongside — not instead of — the Phase 0 repo scan.

Supported formats (read with the Read tool; it handles PDF and text natively):
- `.pdf` — product briefs, specs, design docs
- `.md` / `.txt` — written descriptions, notes
- `.json` / `.yaml` — structured intents

From the artifact, extract and fold into the Phase 0 findings:
- **Purpose**: what is the person trying to build? (one sentence)
- **Stack hints**: any explicit tech choices, platforms, integrations
- **Architecture hints**: agents, services, data stores, external APIs
- **Product count**: does this describe 1 product or N distinct products? (flag for Phase 1.5)

Update the Repo Signals block with an `Artifact:` line:

```
=== Repo Signals ===
Stack: [detected stack + artifact hints]
Evidence: [repo bullets + artifact bullets]
Artifact: [path] — [one-line purpose summary]
Proposed domain: [domain or "multi-product — see Phase 1.5"]
```

If artifact and repo evidence conflict (e.g., artifact says "iOS app" but repo is a Python CLI), surface the conflict explicitly — don't silently pick one. Ask Justin in Phase 1 which is authoritative for this kickoff.

## Phase 1: Project Description (confirm or correct)

If Phase 0 produced a confident domain + stack read:

> "Looks like a [domain] project — [stack], [key evidence]. Is that right? Describe what it does in one sentence so I can draft the constitution."

If Phase 0 was inconclusive (domain: unknown), fall back to the original Q&A:

> "Describe the project in 1-2 sentences."

If `$ARGUMENTS` is provided, use that as the description and skip the question. If Phase 0.5 ingested an artifact, use the artifact's extracted purpose as the description and confirm with Justin rather than asking cold.

**Arguments**: $ARGUMENTS

## Phase 1.5: Multi-Product Decomposition (conditional)

**Run this phase if** Phase 0.5 flagged `product_count >= 2`, or Justin's Phase 1 description names multiple independent products, or the artifact has repeated "Product Brief" / "Module" / "System N" headers.

A single constitution for N unrelated products produces a bloated roster and fights itself during `/spec-review` and `/blueprint`. Surface the decomposition before drafting.

Present:

```
=== Multi-Product Detected ===
Products found (N):
  1. [name] — [one-line purpose]
  2. [name] — [one-line purpose]
  ...

These products appear [tightly coupled / loosely coupled / independent].

How do you want to structure this?
  a) One constitution, one spec — only if they're really one product wearing multiple hats
  b) One constitution, N specs — shared principles, separate feature pipelines (RECOMMENDED for most cases)
  c) N independent projects — split now; I'll kickoff the first one here and note the rest as future projects
  d) Different framing — tell me
```

**My lean: (b)** when products share a domain, stakeholders, or stack but have separate scopes/lifecycles. **Lean (c)** when products have different stacks, different audiences, or will ship on different timelines. **Lean (a)** rarely — only if the "products" are really interchangeable framings of one system.

Decision outcomes:
- **(a)** — proceed to Phase 2 with a single constitution covering all products. Note each as a sub-system in the scope section.
- **(b)** — proceed to Phase 2 with a single constitution. After Phase 4, display: "Ready for /spec. Run /spec N times — once per product: [list]." Record the product list in the constitution under `## Planned Specs` so later `/spec` runs can cross-reference.
- **(c)** — ask which product to kickoff first. Proceed with Phase 2 for that one only. At Completion, list the remaining products as "Deferred kickoffs: [list]" and recommend a parent directory layout if they'll live as sibling repos.
- **(d)** — capture the framing and adapt.

## Phase 2: Constitution Draft

Based on the project description + Phase 0 signals + any existing CLAUDE.md context:

1. Draft a constitution with:
   - 3-5 core principles tailored to the project type
   - Quality standards appropriate to the domain (e.g., accessibility for games, spec compliance for MCP servers)
   - In/out of scope boundaries
   - Technical constraints (iOS target, Swift version, Go version, etc. — pulled from Phase 0 evidence)

2. Present the draft for review. One section at a time if Justin prefers.

## Phase 3: Agent Roster Selection

**Baseline only.** Kickoff sets the *repo-wide* roster — agents that apply to every feature (e.g., mobile-accessibility-reviewer for a games project). Feature-specific specialists are added later via `/spec` when a spec's needs exceed the baseline. Don't try to predict every specialist a future feature might need; pick what applies broadly.

Use the domain mapping in `~/.claude/templates/repo-signals.md` to propose the roster.

1. **Default pipeline personas** (28) are always included — skip restating.
2. **Domain add-ons** from `~/.claude/domain-agents/<domain>/*.md` (installed by `install.sh`, stable path regardless of where the user cloned the workflow repo):
   - `mobile` detected → propose all 6 mobile agents
   - `games` detected → propose mobile 6 + games 3 = 9
   - `mcp` detected → propose `mcp-protocol-expert`, `oauth-flow-auditor` if auth involved
   - `cli` detected → propose `cli-wrapper-ergonomics`, `keychain-safety-reviewer`
   - `plugin`/`skill` detected → propose `skill-plugin-specialist`
3. **Project-specific agents** (if the current project already has `.claude/agents/*.md` — reuse those).

Present the roster:

```
=== Agent Roster ===

Default (28): Always active across /spec-review, /blueprint, /check, code-review

Proposed additions (from repo signals):
- [agent-name] ([source path]) — [one-line why] — [stage]

Add these? (yes / customize / skip domain agents)
```

If the user customizes, let them pick individual agents from the domain library and/or add agents by name.

Record selected agents in the constitution under "Agent Roster" with their source paths so they can be installed to `<project>/.claude/agents/` in Phase 4.

## Phase 4: Directory Setup

1. Create the spec artifact directory:
   ```bash
   mkdir -p docs/specs
   ```

2. Write the finalized constitution to `docs/specs/constitution.md`.

3. **Install selected domain agents** into the project. For each agent in the roster, copy it from `~/.claude/domain-agents/<domain>/<agent>.md` into `<project>/.claude/agents/` so `/blueprint` and `/code-review` can invoke it as a subagent. Skip if already present.

## Completion

```
=== Project Initialized ===

Constitution: docs/specs/constitution.md
Agent roster: [count] agents ([27 default] + [N project-specific])
Installed to: .claude/agents/ ([N files])
Spec directory: docs/specs/

Ready for /spec when you are.
```

## Key Principles

- **Evidence before Q&A** — let the repo tell you what it is before asking
- **One question at a time** — don't overwhelm during setup
- **Sensible defaults** — draft a good constitution, let Justin refine
- **Project-agnostic** — this works for games, tools, services, MCP servers, plugins, anything
- **Constitution is living** — it can be updated anytime, version gets bumped
