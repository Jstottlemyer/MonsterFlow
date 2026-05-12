---
description: Design and implementation planning — 7 specialist agents explore architecture, then produce an implementation plan
---

**IMPORTANT: Do NOT invoke superpowers skills from this command. This command IS the planning workflow.**

You are the design step in the pipeline: `/spec → /spec-review → /design → /check → /build`

(Renamed from `/plan` on 2026-05-12 to avoid collision with Claude Code's
built-in plan-mode tooling. `/plan` still works as a deprecation alias and
delegates here; expect the alias to be removed in a future release. The
internal gate identifier remains `plan` so on-disk selection.json files,
gate-mode keys, and persona directory paths stay backward-compatible.)

Your job is to dispatch 7 parallel design agents, synthesize their analysis into an implementation plan, and present it for approval.

**Argument parsing**: `$ARGUMENTS` may carry an optional feature-slug followed by zero or one gate-mode CLI flag — one of `--strict`, `--permissive`, or `--force-permissive="<reason>"`. Split on whitespace; the first non-flag token (if any) is the feature slug, the remaining flag token (if any) is passed verbatim to `gate_mode_resolve` at Phase 0c. If both `--strict` and `--permissive`/`--force-permissive` appear, `gate_mode_resolve` will reject with exit 2.

## Pre-flight

1. **Find artifacts**: Load `docs/specs/<feature>/spec.md` and `docs/specs/<feature>/review.md`.
   - If `$ARGUMENTS` names a feature, use that.
   - If neither exists: "No spec or review found. Run /spec first."
   - If spec exists but no review: "Spec found but not reviewed. Run /spec-review first, or proceed without review? (Skipping review increases rework risk.)"

2. **Load constitution** (if exists) for constraint checking.

## Phase 0: Persona Metrics — survival classifier (addressed-by-revision mode)

Pre-flight before design agents dispatch. If `docs/specs/<feature>/spec-review/findings.jsonl` exists, run `commands/_prompts/survival-classifier.md` in **addressed-by-revision** mode:

- Inputs: `<feature>/spec-review/findings.jsonl` + `<feature>/spec-review/source.spec.md` (pre-snapshot) + current `<feature>/spec.md` (post-revision).
- **Pre-revision warning:** if `mtime(spec.md) < mtime(spec-review/findings.jsonl)`, emit a warning: `[persona-metrics] WARNING: spec.md hasn't been edited since /spec-review. Did you mean to revise the spec before running /plan? Running classifier anyway (most findings will likely show not_addressed).` Add `"spec-not-revised-since-review"` to `run.json.warnings[]`.
- Idempotency: if `<feature>/spec-review/survival.jsonl` exists and every row's `artifact_hash` matches `sha256(spec.md)`, skip. If `artifact_hash` differs, re-classify and overwrite.
- Outcome semantics: `addressed` = the revision changed the artifact in a way that resolves the finding (substance NOT in source.spec.md but IS in spec.md); `not_addressed` = no visible revision-driven change; `rejected_intentionally` = revised `spec.md`'s `## Open Questions` / `## Out of Scope` / `## Backlog Routing` / `## Deferred` section explicitly names the finding.
- Output: atomic write to `<feature>/spec-review/survival.jsonl`. Echo one-liner if any `classifier_error` rows are written.

If `<feature>/spec-review/findings.jsonl` does not exist (legacy spec or `/spec-review` skipped), this phase is a silent no-op.

**This phase never blocks the stage.**

## Phase 0b: Resolve persona budget (account-type-agent-scaling)

Before dispatching design agents, run the resolver:

```bash
SELECTED=$(bash <REPO_DIR>/scripts/resolve-personas.sh plan \
             --feature "<feature-slug>" --emit-selection-json)
RESOLVER_EXIT=$?
```

- If `RESOLVER_EXIT != 0` or stdout empty: apply `commands/_prompts/_resolver-recovery.md` (canonical recovery fragment — interactive: 3-option prompt; non-tty/autorun: abort). No silent seed fallback in headless mode.
- Dispatch one subagent per line of `$SELECTED` (skipping `codex-adversary`; Codex runs separately).
- Resolver writes `docs/specs/<feature>/plan/selection.json`.
- No `agent_budget` in config → full roster (existing behavior).
- Print one line: `Selected: <names> | Dropped: <names>`.

## Phase 0c: Gate Mode Resolution

Resolve the active gate mode + per-gate re-cycle ceiling before dispatching design agents. Canonical reference: [`commands/_gate-mode.md`](_gate-mode.md) — read it for the 24-cell truth table, banner wording, sentinel paths, and audit-log format. Do not duplicate that content here.

```bash
# shellcheck disable=SC1091
. <REPO_DIR>/scripts/_gate_helpers.sh

SPEC="docs/specs/<feature-slug>/spec.md"
GATE_FLAG="<--strict | --permissive | --force-permissive=\"<reason>\" | (empty)>"

GATE_MODE=$(gate_mode_resolve "$SPEC" "$GATE_FLAG")
RESOLVE_EXIT=$?
GATE_MAX_RECYCLES=$(gate_max_recycles_clamp "$SPEC")
```

- If `RESOLVE_EXIT != 0`: refuse the gate. `gate_mode_resolve` already wrote the canonical error to stderr (ambiguity / `--permissive` against `gate_mode: strict` / `--force-permissive` without reason / `--force-permissive` while `$CI`/`$AUTORUN_STAGE` is truthy). Exit without dispatching designers.
- Banners (per `commands/_gate-mode.md` §6) — emit to **stderr**, then `touch` the matching sentinel:
  - `~/.claude/.gate-mode-default-flip-warned-v0.9.0` missing → emit the per-user verbose banner (§6.1) once, then touch.
  - Per-user sentinel exists AND frontmatter absent AND `docs/specs/<feature>/.gate-mode-warned` missing → emit the per-spec one-liner (§6.2), then touch the per-spec sentinel.
  - `mode_source == cli-force` → emit the 4-line `--force-permissive` warning (§6.3) and append the audit row described in `commands/_gate-mode.md` §7 to `docs/specs/<feature>/.force-permissive-log`.
- Export the resolved values for downstream phases (Phase 1 dispatchers, Phase 2 synthesis, Phase 2c emit, Phase 3 verdict sidecar):
  ```bash
  export GATE_MODE GATE_MODE_SOURCE GATE_MAX_RECYCLES
  ```
  (`GATE_MODE_SOURCE` is captured from `gate_mode_resolve`'s side-channel — see helper docstring.)
- The verdict sidecar written at Phase 3 records `mode`, `mode_source`, `iteration`, `iteration_max`, `cap_reached`, `class_breakdown`, `class_inferred_count`, `followups_file`, and `stage` per `schemas/check-verdict.schema.json` (v2). The `--force-permissive` reason string lands in `docs/specs/<feature>/.force-permissive-log` (audit trail), not in the verdict sidecar.

## Phase 1: Dispatch Design Agents

Read each persona file in `<REPO_DIR>/personas/plan/` corresponding to a name in `$SELECTED`, then dispatch one parallel subagent per name using the Agent tool. The legacy 7-designer roster (api, data-model, ux, scalability, security, integration, wave-sequencer) is the resolver's full-roster fallback. Each agent receives:
- The spec content
- The review findings (if available)
- The constitution (if exists)
- Their persona's role, checklist, and key questions

**As each design agent returns**, persist its raw output to `docs/specs/<feature>/plan/raw/<persona>.md` immediately (atomic write). The Phase 2c emit reads from this directory. (Note: no snapshot step at `/plan` — `plan.md` is synthesized fresh at this stage, not revised; there is no pre-state to snapshot.)

The 7 designers:
1. **api** — Interface design and developer/user ergonomics
2. **data-model** — Data model, storage, and migrations
3. **ux** — User experience and ergonomics
4. **scalability** — Performance at scale and bottlenecks
5. **security** — Threat model and attack surface
6. **integration** — How it fits existing system
7. **wave-sequencer** — What ships in what wave; data contract precedence (three-gate default: data → UI → tests)

Each agent must return:
- Key Considerations
- Options Explored (with pros/cons/effort)
- Recommendation
- Constraints Identified
- Open Questions
- Integration Points with other dimensions

## Phase 2: Judge + Synthesize into Implementation Plan

After all 7 agents return, apply two passes using the personas in `~/.claude/personas/`:

**Pass 1 — Judge** (read `personas/judge.md`):
1. Remove duplicate recommendations across agents → merge into one
2. Resolve contradictions (e.g., security vs UX tradeoff) → pick one with rationale, or flag for human input
3. Demote speculative concerns that don't apply to current scope
4. Promote recommendations with convergent signal (2+ agents aligned)

**Pass 2 — Synthesis** (read `personas/synthesis.md`, use Plan output structure):
1. Produce unified architecture summary from all agent recommendations
2. Compile key design decisions with rationale
3. Surface open questions requiring human input
4. Build consolidated risk register
5. **Produce implementation plan** with:
   - Ordered task breakdown
   - Dependencies between tasks
   - Which tasks can run in parallel
   - Estimated complexity per task (S/M/L)

## Phase 2c: Persona Metrics emit

Run `commands/_prompts/findings-emit.md`. It reads `docs/specs/<feature>/plan/raw/*.md` (per-design-persona outputs persisted in Phase 1) and the synthesizer's clustering decisions, and atomically writes:

- `docs/specs/<feature>/plan/findings.jsonl` — one row per design-recommendation cluster, with `personas[]` listing the design personas (api / data-model / ux / scalability / security / integration / wave-sequencer) that contributed.
- `docs/specs/<feature>/plan/participation.jsonl`
- `docs/specs/<feature>/plan/run.json` — `artifact_hash: sha256(plan.md)` (the freshly synthesized plan, not a source snapshot).

`stage: "plan"` recorded on every emitted row. `prompt_version: "findings-emit@1.0"`. The next stage's classifier (`/check` Phase 0 in synthesis-inclusion mode) reads this `findings.jsonl` and judges which design recommendations made it through Judge into `plan.md`.

## Phase 3: Present & Write

1. **Present the plan**:
   ```
   === PLAN: [Feature Name] ===

   ## Design Decisions
   [Key choices made and rationale]

   ## Implementation Tasks
   | # | Task | Depends On | Size | Parallel? |
   |---|------|-----------|------|-----------|
   | 1 | ... | — | S | — |
   | 2 | ... | 1 | M | — |
   | 3 | ... | 1 | M | Yes (with 2) |

   ## Open Questions
   [Decisions needing Justin's input]

   ## Risks
   [Top risks from design analysis]

   [AUTORUN MODE: If AUTORUN=1 is set in your environment, skip this approval prompt. Write all artifacts and proceed immediately to the next stage. Do not output the approval prompt text below.]
   Approve to proceed to /check? (approve / adjust <what to change>)
   ```

2. **Write `docs/specs/<feature>/plan.md`** with the full plan.

## On Approve

```
Plan approved. Ready for /check (5 plan reviewer agents will validate before build).
```

## On Adjust

Modify the plan as requested, re-run affected design agents if needed, re-present.

## Key Principles

- **Parallel execution** — all 7 designers run simultaneously
- **Concrete over abstract** — tasks should be implementable, not vague
- **Show tradeoffs** — why approach A vs B
- **YAGNI** — cut anything not needed for the current scope
- **Persistent artifacts** — plan.md survives the session

**Arguments**: $ARGUMENTS
