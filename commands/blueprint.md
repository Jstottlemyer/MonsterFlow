---
description: Design and implementation planning — budget-selected specialist agents explore architecture, then produce an implementation plan
---

**IMPORTANT: Do NOT invoke superpowers skills from this command. This command IS the planning workflow.**

You are the design step in the pipeline: `/spec → /spec-review → /blueprint → /check → /build`

(MonsterFlow's design gate is `/blueprint`. The slash command was previously
named `/plan` but we ceded that name back to Claude Code on 2026-05-12 —
`/plan` belongs to Claude Code's built-in plan-mode tooling
(`EnterPlanMode` / `ExitPlanMode`), not to this pipeline. The internal
gate identifier remains `plan` so on-disk selection.json files, gate-mode
keys, persona directory paths, the artifact filename `design.md`, and the
autorun shell `scripts/autorun/design.sh` stay backward-compatible — only
the user-facing slash command moved.)

**BEFORE dispatching anything, read `~/.config/monsterflow/config.json` and run the Phase 0b resolver.** The dispatch count is N = lines emitted by the resolver (default = full personas/design/ roster of 7; capped by `agent_budget` when set). Do NOT hardcode a count — your dispatch must match the resolver output exactly.

Your job is to dispatch N parallel design agents (where N is determined by the Phase 0b resolver — see "BEFORE dispatching" above), synthesize their analysis into an implementation plan, and present it for approval.

**Argument parsing**: `$ARGUMENTS` may carry an optional feature-slug followed by zero or one gate-mode CLI flag — one of `--strict`, `--permissive`, or `--force-permissive="<reason>"`. Split on whitespace; the first non-flag token (if any) is the feature slug, the remaining flag token (if any) is passed verbatim to `gate_mode_resolve` at Phase 0c. If both `--strict` and `--permissive`/`--force-permissive` appear, `gate_mode_resolve` will reject with exit 2.

## Pre-flight

1. **Find artifacts**: Load `docs/specs/<feature>/spec.md` and `docs/specs/<feature>/review.md`.
   - If `$ARGUMENTS` names a feature, use that.
   - If neither exists: "No spec or review found. Run /spec first."
   - If spec exists but no review: "Spec found but not reviewed. Run /spec-review first, or proceed without review? (Skipping review increases rework risk.)"

2. **Load constitution** (if exists) for constraint checking.

3. **Probe `.compact-mode` for the pipeline-pacing-and-prefill `/compact` suggestion path** (pipeline-pacing-and-prefill Item 3 / AC5). Determine whether the running Claude Code build supports the `.context_window.used_percentage` field on the status-line stdin JSON that `scripts/statusline-command.sh:42` reads. The probe surface is "does `scripts/statusline-command.sh` exist and reference `.context_window.used_percentage` on or near line 42?" — not a live invocation, just a static reachability check (the live JSON only arrives at status-line runtime).

   - If the file exists and contains the literal `.context_window.used_percentage` (e.g., `grep -q 'context_window.used_percentage' scripts/statusline-command.sh`): write the literal string `probe` (no newline-only content; bare token) to `docs/specs/<feature>/.compact-mode`. The end-of-gate banner (`scripts/_pipeline_banner.sh end`) will read this and emit the Path A two-tier `/compact` suggestion when context fill crosses 50% / 75%.
   - Otherwise (file missing OR field absent): write the literal string `suppress` to `docs/specs/<feature>/.compact-mode`. The end-of-gate banner will fall back to the Path B cost-boundary one-liner.
   - This file is gitignored (`docs/specs/*/.compact-mode` per `.gitignore`) so the probe result stays spec-scoped per worktree and never lands in commits.
   - Idempotent: if `docs/specs/<feature>/.compact-mode` already exists with a valid literal (`probe` or `suppress`), leave it untouched — the operator may have overridden it manually.
   - Silent no-op when the feature has no `docs/specs/<feature>/` directory yet (standalone / not-yet-spec'd flow). The banner helper treats a missing `.compact-mode` as `suppress` by default.

## Phase 0a: Ensure raw/ directory exists (run BEFORE subagent dispatch)

**RUN THIS NOW with the Bash tool — BEFORE Phase 0b, BEFORE dispatching any subagent.** Subagents write to `plan/raw/<persona>.md` and the Write tool does NOT auto-create parent directories. Unlike `/spec-review` and `/check`, there is no snapshot step at this gate (`design.md` is synthesized fresh), so the dir creation has no other home — it MUST happen here.

```bash
mkdir -p docs/specs/<feature>/plan/raw/
```

(Note the historical `plan/` directory name — the internal gate identifier remains `plan` per CLAUDE.md's gate-rename guard, even though the user-facing slash command is `/blueprint`.)

## Phase 0: Persona Metrics — survival classifier (addressed-by-revision mode)

Pre-flight before design agents dispatch. If `docs/specs/<feature>/spec-review/findings.jsonl` exists, run `commands/_prompts/survival-classifier.md` in **addressed-by-revision** mode:

- Inputs: `<feature>/spec-review/findings.jsonl` + `<feature>/spec-review/source.spec.md` (pre-snapshot) + current `<feature>/spec.md` (post-revision).
- **Pre-revision warning:** if `mtime(spec.md) < mtime(spec-review/findings.jsonl)`, emit a warning: `[persona-metrics] WARNING: spec.md hasn't been edited since /spec-review. Did you mean to revise the spec before running /plan? Running classifier anyway (most findings will likely show not_addressed).` Add `"spec-not-revised-since-review"` to `run.json.warnings[]`.
- Idempotency: if `<feature>/spec-review/survival.jsonl` exists and every row's `artifact_hash` matches `sha256(spec.md)`, skip. If `artifact_hash` differs, re-classify and overwrite.
- Outcome semantics: `addressed` = the revision changed the artifact in a way that resolves the finding (substance NOT in source.spec.md but IS in spec.md); `not_addressed` = no visible revision-driven change; `rejected_intentionally` = revised `spec.md`'s `## Open Questions` / `## Out of Scope` / `## Backlog Routing` / `## Deferred` section explicitly names the finding.
- Output: atomic write to `<feature>/spec-review/survival.jsonl`. Echo one-liner if any `classifier_error` rows are written.

If `<feature>/spec-review/findings.jsonl` does not exist (legacy spec or `/spec-review` skipped), this phase is a silent no-op.

**This phase never blocks the stage.**

## Phase 0b: Resolve persona budget + tier dispatch (account-type-agent-scaling + dynamic-roster-per-gate)

Before dispatching design agents, run the resolver in **tier-aware** mode:

```bash
SELECTED=$(bash <REPO_DIR>/scripts/resolve-personas.sh design \
             --feature "<feature-slug>" \
             --with-tier \
             --emit-selection-json)
RESOLVER_EXIT=$?
```

- `--with-tier` switches resolver stdout to colon-delimited `<persona>:<tier>` grammar (one line per selected persona; `tier ∈ {opus, sonnet}`). `codex-adversary` continues to be emitted bare (no tier suffix) when Codex is authed.
- `--emit-selection-json` persists `docs/specs/<feature>/design/selection.json` (records `tier_policy_applied`, dropped personas, and recovery state).
- If `RESOLVER_EXIT != 0`, stdout empty, OR the resolver script is missing from disk: apply `commands/_prompts/_resolver-recovery.md` (canonical recovery fragment — interactive: 3-option prompt; non-tty/autorun: abort). No silent seed fallback in headless mode. **Do NOT emit anything like `"Resolver not found — falling back to full roster at sonnet tier (no budget config)"`** — that conflates a missing-script error with the resolver's no-config default and is the exact recovery D6 dropped. Missing/failed resolver ≠ no budget config.
- No `agent_budget` in config → full roster (existing behavior).
- Print one line: `Selected: <names> | Dropped: <names>` (strip `:<tier>` suffix for the display).

**Dispatch parsing.** Iterate each line of `$SELECTED`:

1. **`codex-adversary`** (bare, no colon) → Codex path (Codex runs separately; do not dispatch via Agent tool). Codex runs at Phase 2b AFTER the designers have synthesized — adversarial review of the freshly-written `design.md` against the spec + the codebase. Enabled by default as of 2026-05-16 (was historically disabled; flipped after wiki-write-migrate V3 ran /blueprint and the synthesizing personas needed an adversarial pass to catch the kind of architectural drift Codex caught at /spec-review V2 and at /check).
2. **`<persona>:<tier>`** (e.g. `api:opus`, `data-model:sonnet`) → split on `:`; load `personas/design/<persona>.md`; invoke the Agent tool with `model: "opus"` (when tier is `opus`) or `model: "sonnet"` (when tier is `sonnet`). The model tier is set per-persona, not stage-wide.
3. **Bare persona that is not `codex-adversary`** (no colon suffix) → halt: `[dispatch] resolver emitted bare persona '<line>'; expected '<persona>:<tier>' — refusing to dispatch`. This indicates a `--with-tier` regression in the resolver; do not silently default a tier.

Example stdout:

```
api:opus
data-model:sonnet
ux:sonnet
scalability:sonnet
security:opus
integration:sonnet
wave-sequencer:sonnet
codex-adversary
```

If the resolver emits any informational warnings on stderr, pass them through transparently. (Unlike `/spec-review`, `/plan` does not introduce a dedicated tag-baseline drift step at this gate — there is no spec-revision flow here to warn about.)

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

- If `RESOLVE_EXIT != 0`: refuse the gate. `gate_mode_resolve` already wrote the canonical error to stderr (ambiguity / `--permissive` against `gate_mode: strict` / `--force-permissive` without reason / `--force-permissive` while `$CI`/`$AUTORUN_STAGE` is truthy). Exit without dispatching designers. Emit halt-surface block:
  ```
  ╔══ autoship halt ══════════════════════════════════════════════╗
  ║ feature: <slug>
  ║ stage:   blueprint
  ║ reason:  gate_mode_resolve failed (see stderr above)
  ║ next:    fix the gate-mode flag or spec frontmatter, then re-run /blueprint <slug>
  ╚══════════════════════════════════════════════════════════════════╝
  [AUTOSHIP-HALT]
  ```
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

<!-- BEGIN autoship-detection -->
## Autoship Detection (V3 Path B)

Before this gate's work begins, scan all user messages in the current Claude Code session for the literal substring:

  `is shipped via merged PR with verifier reporting`

If found AND no subsequent `/goal clear` invocation since the most recent trigger:

1. Extract the spec slug from the matched /goal line (regex: `docs/specs/([a-z0-9][a-z0-9-]{0,63})/spec\.md`).
2. If the extracted slug matches this gate's feature argument:
   - Emit exactly: `[autoship] active goal detected — proceeding autonomously through pipeline`
   - Set internal flag: autoship-active = true
   - Skip the manual approval prompt for this gate
3. If slug mismatches:
   - Emit: `[autoship] /goal active for <other-slug>, current gate is <this-slug> — manual mode`
   - autoship-active = false

Otherwise: autoship-active = false; existing AUTORUN=1 env-var check, then existing approval prompt.
<!-- END autoship-detection -->

## Phase 1: Dispatch Design Agents

Read each persona file in `<REPO_DIR>/personas/design/` corresponding to a name in `$SELECTED` (after stripping `:<tier>` suffix per Phase 0b parsing), then dispatch one parallel subagent per name using the Agent tool with the tier-resolved `model:` parameter. The legacy 7-designer roster (api, data-model, ux, scalability, security, integration, wave-sequencer) is the resolver's full-roster fallback. Each agent receives:
- The spec content
- The review findings (if available)
- The constitution (if exists)
- Their persona's role, checklist, and key questions

**As each design agent returns**, persist its raw output to `docs/specs/<feature>/plan/raw/<persona>.md` immediately (atomic write). The Phase 2c emit reads from this directory. (Note: no snapshot step at `/plan` — `design.md` is synthesized fresh at this stage, not revised; there is no pre-state to snapshot.)

The designer roster (personas/design/, 7 personas as of 2026-05-14):
1. **api** — Interface design and developer/user ergonomics
2. **data-model** — Data model, storage, and migrations
3. **ux** — User experience and ergonomics
4. **scalability** — Performance at scale and bottlenecks
5. **security** — Threat model and attack surface
6. **integration** — How it fits existing system
7. **wave-sequencer** — What ships in what wave; data contract precedence (three-gate default: data → UI → tests)

Which of these actually run is determined by Phase 0b — the resolver reads `~/.config/monsterflow/config.json` `agent_budget` and emits N persona names. Dispatch ONLY those N. Do not run the full list unless the resolver emits all 7.

Each agent must return:
- Key Considerations
- Options Explored (with pros/cons/effort)
- Recommendation
- Constraints Identified
- Open Questions
- Integration Points with other dimensions

## Phase 2: Judge + Synthesize into Implementation Plan

After all dispatched agents return (count = lines in `$SELECTED` from Phase 0b, minus the bare `codex-adversary` entry — Codex runs at Phase 2b on the synthesized design.md), apply two passes using the personas in `~/.claude/personas/`:

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

## Phase 2b: Codex Adversarial Check (if available)

Silent skip if Codex is not installed or not authenticated — no error, no prompt.

```bash
if command -v codex >/dev/null 2>&1 && codex login status >/dev/null 2>&1; then
  cat docs/specs/<feature>/design.md | codex exec --full-auto --ephemeral \
    --output-last-message /tmp/codex-blueprint-review.txt \
    "Adversarial design review: this is the synthesized implementation plan after 3 designers ran in parallel. Challenge the design against the spec AND against the codebase. Look for: load-bearing assumptions that aren't testable, missing dependencies between tasks, wave-sequencing errors, algorithmic bugs in pseudocode, integration points that don't match the actual code, and any drift between the plan's claims and what the underlying scripts/modules actually do."
fi
```

If `/tmp/codex-blueprint-review.txt` exists after the run:
- If Codex surfaces findings not already in the Claude synthesis, add a **Codex Adversarial View** subsection to the plan presentation with those findings.
- If Codex finds nothing new, note "Codex: no additional findings."
- If Codex was skipped (not available), omit the section entirely — no mention of it.

**Persist Codex output to disk** (parallel to per-designer raw outputs from Phase 1): if Codex ran successfully, copy `/tmp/codex-blueprint-review.txt` → `docs/specs/<feature>/plan/raw/codex-adversary.md` (atomic write). The `findings-emit` step at Phase 2c reads this file to attribute `codex-adversary` in `personas[]` for any cluster that includes Codex's contribution.

## Phase 2c: Persona Metrics emit

Run `commands/_prompts/findings-emit.md`. It reads `docs/specs/<feature>/plan/raw/*.md` (per-design-persona outputs persisted in Phase 1) and the synthesizer's clustering decisions, and atomically writes:

- `docs/specs/<feature>/plan/findings.jsonl` — one row per design-recommendation cluster, with `personas[]` listing the design personas (api / data-model / ux / scalability / security / integration / wave-sequencer) that contributed.
- `docs/specs/<feature>/plan/participation.jsonl`
- `docs/specs/<feature>/plan/run.json` — `artifact_hash: sha256(design.md)` (the freshly synthesized plan, not a source snapshot).

`stage: "plan"` recorded on every emitted row. `prompt_version: "findings-emit@1.0"`. The next stage's classifier (`/check` Phase 0 in synthesis-inclusion mode) reads this `findings.jsonl` and judges which design recommendations made it through Judge into `design.md`.

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
   Approve to proceed to /check?

   - **a)** Approve — accept the plan and continue
   - **b)** Adjust — name what to change (`b split T6 into two waves`)

   Reply with `a` or `b <change>` + Enter.
   ```

2. **Write `docs/specs/<feature>/design.md`** with the full plan.

## On Approve

```
Plan approved. Ready for /check (budget-selected plan reviewer agents will validate before build).
```

## On Adjust

Modify the plan as requested, re-run affected design agents if needed, re-present.

## Key Principles

- **Parallel execution** — all budget-selected designers run simultaneously
- **Concrete over abstract** — tasks should be implementable, not vague
- **Show tradeoffs** — why approach A vs B
- **YAGNI** — cut anything not needed for the current scope
- **Persistent artifacts** — design.md survives the session

**Arguments**: $ARGUMENTS

<!-- BEGIN autoship-chain-invoke -->
## Autoship Chain-Invoke (V3 Path B)

If autoship-active = true at this gate's completion:

1. Emit a pre-handoff stdout marker (visible failure signal if chain breaks):
   ```
   [autoship] handing off to <next-gate> — if you see this without the next gate running, the Skill chain broke (paste `/<next-gate> <slug>` to resume)
   ```
2. Final action — invoke the next gate via the Skill tool:
   - /spec-review final action: `Skill(skill="blueprint", args="<feature-slug>")`
   - /blueprint final action: `Skill(skill="check", args="<feature-slug>")`
   - /check final action on GO or GO_WITH_FIXES: `Skill(skill="build", args="<feature-slug>")`
   - /check final action on NO_GO: STOP, emit halt-surface block (do not chain)
   - /build final action: existing PR-open path; halt-surface block on branch-protection-block

This MUST be the final action — no further work after the Skill invocation. Graceful degradation: if the Skill call fails or doesn't transfer control, the user sees the pre-handoff marker as the last visible signal and resumes manually.
<!-- END autoship-chain-invoke -->
