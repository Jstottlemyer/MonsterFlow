---
description: Parallel PRD review — 6 specialist agents analyze the spec for gaps, risks, and ambiguity
---

**IMPORTANT: Do NOT invoke superpowers skills (writing-plans, brainstorming, executing-plans, etc.) from this command. This command IS the review workflow.**

You are the review step in the pipeline: `/spec → /spec-review → /blueprint → /check → /build`

Your job is to dispatch 6 parallel PRD reviewer agents against the spec, consolidate their findings, and present them for approval.

**Argument parsing**: `$ARGUMENTS` may carry an optional feature-slug followed by zero or one gate-mode CLI flag — one of `--strict`, `--permissive`, or `--force-permissive="<reason>"`. Split on whitespace; the first non-flag token (if any) is the feature slug, the remaining flag token (if any) is passed verbatim to `gate_mode_resolve` at Phase 0c. If both `--strict` and `--permissive`/`--force-permissive` appear, `gate_mode_resolve` will reject with exit 2.

## Pre-flight

1. **Find the spec**: Check conversation context for a just-completed brainstorm. If not, look for the most recent spec in `docs/specs/*/spec.md`. If `$ARGUMENTS` names a feature, look in `docs/specs/<feature>/spec.md`.

2. **No spec found**:
   ```
   No spec to review.
   Start with: /spec <idea>
   ```

3. **Load constitution** (if `docs/specs/constitution.md` exists) for constraint checking.

## Phase 1, step 0: Snapshot + rotate (persona-metrics)

Before reviewer agents dispatch, run the snapshot directive at `commands/_prompts/snapshot.md`:

- Snapshot `docs/specs/<feature>/spec.md` → `docs/specs/<feature>/spec-review/source.spec.md` (atomic write).
- Refuse with `run.json.status: "failed"` if `spec.md` is not git-tracked.
- Validate slug against `^[a-z0-9][a-z0-9-]{0,63}$`.
- Create `docs/specs/<feature>/spec-review/raw/` directory.
- If a prior `findings.jsonl` exists in `docs/specs/<feature>/spec-review/`, rename it to `findings-<UTC-ts>.jsonl` (format `%Y-%m-%dT%H-%M-%SZ`) BEFORE the new emit at Phase 2c. Filename is the only superseded marker — no schema mutation.
- Echo one-line user feedback (`[persona-metrics] snapshot ... (rotated N prior)`).

If snapshot refuses, halt the phase — do not dispatch reviewers.

## Phase 0b: Resolve persona budget + tier (account-type-agent-scaling + dynamic-roster-per-gate)

Before dispatching reviewers, run the resolver to determine which personas to dispatch AND at which model tier (`opus` or `sonnet`). As of Slice 3 of `dynamic-roster-per-gate`, the resolver supports a `--with-tier` flag that switches its stdout grammar from bare persona names to `<persona>:<tier>` colon-delimited lines. Phase 0b now REQUIRES this tier-aware grammar so each persona can be dispatched at the correct model. The resolver still accepts the legacy bare-name invocation for other callers, but `/spec-review` always opts in.

```bash
SELECTED=$(bash <REPO_DIR>/scripts/resolve-personas.sh spec-review \
             --feature "<feature-slug>" --with-tier --emit-selection-json \
             2> >(tee /tmp/resolve-personas.stderr >&2))
RESOLVER_EXIT=$?
```

- If `RESOLVER_EXIT != 0`, stdout is empty, OR the resolver script is missing from disk: apply `commands/_prompts/_resolver-recovery.md` (canonical recovery fragment — interactive sessions get a 3-option prompt; non-tty/autorun aborts the gate). Do **not** silently fall back to a hardcoded list — that would defeat the budget. **In particular, do NOT emit anything like `"Resolver not found — falling back to full roster at sonnet tier (no budget config)"`** — that line conflates a missing-script error with the resolver's no-config default and is the exact recovery decision D6 dropped. Missing/failed resolver ≠ no budget config. Follow the fragment or abort.
- Otherwise, dispatch one subagent per line of `$SELECTED` using the parsing + dispatch contract below.
- The resolver writes `docs/specs/<feature>/spec-review/selection.json` with the audit row (schema v2 includes the `tier` field per persona).
- If `~/.config/monsterflow/config.json` is absent or has no `agent_budget`, the resolver emits the full roster — existing behavior preserved (every line still carries a `:<tier>` suffix).
- Print one line to gate stdout: `Selected: <names with tiers> | Dropped: <names>` (read these from `selection.json`).

**Stale-tags surfacing (D8):** when `--with-tier` is set, the resolver recomputes the tier-baseline from current persona frontmatter and compares it to the recorded `tags:` field. If they diverge, the resolver writes one line `[stale-tags] WARNING: ...` to stderr (it does NOT halt; the recomputed baseline wins). Before dispatching reviewers, scan `/tmp/resolve-personas.stderr` (or the captured stderr stream above) for any line starting with `[stale-tags]` and surface it verbatim to the user as a one-line note so they know a persona's recorded `tags:` is out of date. Do not block on this — proceed with dispatch.

**Stdout grammar (new, Slice 3):** one line per persona. Two shapes:

```
requirements:opus
gaps:sonnet
ambiguity:opus
feasibility:sonnet
scope:sonnet
stakeholders:opus
codex-adversary
```

- `<persona-slug>:<tier>` — colon-delimited, `<tier>` ∈ `{opus, sonnet}`. Dispatch via the Agent tool with the matching `model:` parameter (see below).
- `codex-adversary` — appears BARE (no colon, no tier) when Codex is present in the roster. Dispatch via the existing Codex integration at Phase 2b — do NOT pass it to the Agent tool.

**Dispatch parsing + contract:** for each line of `$SELECTED`:

1. Strip whitespace. If the line is exactly `codex-adversary` (no colon), skip it here — it is handled by Phase 2b.
2. Otherwise, partition on the FIRST `:` — the prefix is the persona slug, the suffix is the tier.
3. If `:` is absent AND the line is NOT `codex-adversary`, the resolver violated its contract. Halt the gate with:
   ```
   [dispatch] resolver emitted bare persona '<line>'; expected '<persona>:<tier>' — refusing to dispatch
   ```
4. If the tier is not one of `opus` or `sonnet`, halt with an analogous error.
5. Otherwise, invoke the Agent tool with `model: "opus"` or `model: "sonnet"` matching the parsed tier, and the persona's role/checklist loaded from `<REPO_DIR>/personas/review/<persona>.md`. No wrapper script — pass `model:` to the Agent tool directly (per plan D4).

## Phase 0c: Gate Mode Resolution (pipeline-gate-permissiveness)

Run AFTER Phase 0b (resolver) and BEFORE Phase 1 (dispatch). Determines the active gate mode (`permissive` | `strict`) plus per-gate re-cycle ceiling, emits the migration banner if needed, and exports `GATE_MODE` / `GATE_MODE_SOURCE` / `GATE_MAX_RECYCLES` for downstream Synthesis (Pass 2) consumption.

**Canonical reference:** `commands/_gate-mode.md` — the truth table (24 cells), banner wording (locked at v0.9.0), CLI flag rejection rules, and `.force-permissive-log` JSONL row format live there. Do NOT reproduce them inline — read that file once and apply.

Use the Bash tool to run, in this order:

```bash
source <REPO_DIR>/scripts/_gate_helpers.sh

# Resolve mode. CLI_FLAG is "" or one of --strict | --permissive | --force-permissive="<reason>"
# (parsed from $ARGUMENTS at top of command).
MODE_RESULT=$(gate_mode_resolve "docs/specs/<feature>/spec.md" "<CLI_FLAG>")
RESOLVE_EXIT=$?
if [ "$RESOLVE_EXIT" -ne 0 ]; then
  # gate_mode_resolve already printed the rejection banner to stderr
  # (see _gate-mode.md sections 6.4 / 6.5 / `--force-permissive` refusal).
  # Abort the gate — do NOT dispatch reviewers.
  exit "$RESOLVE_EXIT"
fi
GATE_MODE="${MODE_RESULT%%:*}"
GATE_MODE_SOURCE="${MODE_RESULT#*:}"
export GATE_MODE GATE_MODE_SOURCE

# Clamp re-cycle ceiling (frontmatter gate_max_recycles, clamped to [1,5]).
GATE_MAX_RECYCLES=$(gate_max_recycles_clamp "docs/specs/<feature>/spec.md")
export GATE_MAX_RECYCLES
```

If `gate_mode_resolve` exits non-zero, surface its stderr verbatim to the user and stop — Phase 1 must not run when mode resolution failed (ambiguity, CI/AUTORUN refusal, or `--permissive` against a strict-flagged spec).

**Banner emission** (per `commands/_gate-mode.md` §5 + §6):

1. If `GATE_MODE_SOURCE == default-flip` (frontmatter absent → permissive default) AND `~/.claude/.gate-mode-default-flip-warned-v0.9.0` does NOT exist: emit the verbose ~5-line per-user banner from `_gate-mode.md` §6.1 to stderr, then `touch ~/.claude/.gate-mode-default-flip-warned-v0.9.0`.
2. Else if `GATE_MODE_SOURCE == default-flip` AND the per-user sentinel exists AND `docs/specs/<feature>/.gate-mode-warned` does NOT exist: emit the per-spec one-liner from §6.2 to stderr, then `touch docs/specs/<feature>/.gate-mode-warned`.
3. If `GATE_MODE_SOURCE == cli-force` (i.e., `--force-permissive` was honored): the helper already printed the 4-line warning. Additionally, call `force_permissive_audit "docs/specs/<feature>" "<iteration>" "spec-review" "<reason>"` to append the JSONL audit row to `docs/specs/<feature>/.force-permissive-log`. `<iteration>` is the current re-cycle counter (1-indexed; first run = 1).

**Note on `is_ci_env`:** `gate_mode_resolve` already calls `is_ci_env` internally and refuses `--force-permissive` when `$CI` or `$AUTORUN_STAGE` is truthy (see `_gate-mode.md` §4 whitelist). No additional check needed here — trust the helper's exit code.

**Downstream consumers** (judge / synthesis personas at Phase 2): read `commands/_gate-mode.md` for the classification precedence and verdict-sidecar field semantics. The `GATE_MODE`, `GATE_MODE_SOURCE`, and `GATE_MAX_RECYCLES` env-vars exported above flow into the synthesis call so the verdict sidecar (`verdict.json`) can record `mode`, `mode_source`, `iteration`, `iteration_max`, `cap_reached`, `class_breakdown`, `class_inferred_count`, `followups_file`, and `stage` per `schemas/check-verdict.schema.json` (v2).

## Phase 1: Dispatch PRD Reviewer Agents

For each `<persona>:<tier>` line surfaced by Phase 0b, read the persona file at `<REPO_DIR>/personas/review/<persona>.md`, then dispatch one parallel subagent using the Agent tool with `model: "<tier>"` (`opus` or `sonnet`). The legacy hardcoded list (requirements, gaps, ambiguity, feasibility, scope, stakeholders) is the resolver's full-roster fallback — when the user has no budget configured, all six dispatch as before, each at the tier the resolver assigned.

`codex-adversary` (the bare line, if present) is NOT dispatched here — Phase 2b owns it.

Each agent receives:
- The full spec content
- The constitution (if it exists)
- Their persona's role, checklist, and key questions

**As each reviewer agent returns**, persist its raw output to `docs/specs/<feature>/spec-review/raw/<persona>.md` immediately (atomic write via tmp + `os.replace`). This file-backed persistence is the structural fix that retires R1 (raw outputs no longer depend on conversation context surviving truncation). The `findings-emit` step at Phase 2c reads from this directory.

The 6 reviewers:
1. **requirements** — Success criteria and acceptance conditions
2. **gaps** — What hasn't been thought through yet
3. **ambiguity** — What's unclear, contradictory, or underspecified
4. **feasibility** — Is this buildable? What are the hard problems?
5. **scope** — What's in/out and where scope creep will happen
6. **stakeholders** — Who's affected and whether needs conflict

Each agent must return their findings structured as:
- Critical Gaps (must answer before building)
- Important Considerations (should address but not blocking)
- Observations (non-blocking notes)
- Verdict: PASS / PASS WITH NOTES / FAIL

## Phase 2: Judge + Synthesize

After all 6 agents return, apply two passes:

**Pass 1 — Judge** (read `~/.claude/personas/judge.md`):
1. Remove duplicate findings flagged by multiple agents → merge into one with higher confidence
2. Resolve contradictions between agents → pick one with rationale
3. Demote vague or speculative findings that aren't actionable
4. Promote findings with convergent signal (2+ agents flagged independently)
5. Check proportionality — is the severity appropriate for actual risk?

**Pass 2 — Synthesis** (read `~/.claude/personas/synthesis.md`, use Review output structure):
1. Organize by topic, not by agent — reader shouldn't need to know which agent said what
2. Identify themes multiple agents converged on
3. Identify gaps no agent covered
4. Write in direct language — no hedging

## Phase 2b: Codex Adversarial Check (if available)

Silent skip if Codex is not installed or not authenticated — no error, no prompt.

```bash
if command -v codex >/dev/null 2>&1 && codex login status >/dev/null 2>&1; then
  codex exec --full-auto --ephemeral \
    --output-last-message /tmp/codex-spec-review.txt \
    "Adversarial spec review: challenge the assumptions, tradeoffs, and design decisions in this spec. Look for missing failure modes, incorrect assumptions, better alternatives that weren't considered, and scope that will cause problems later." \
    < <spec-path>
fi
```

Replace `<spec-path>` with the resolved path to the spec file. If the file exists at `/tmp/codex-spec-review.txt` after the run:
- If Codex surfaces findings not already in the Claude synthesis, add a **Codex Adversarial View** subsection to the consolidated review with those findings.
- If Codex finds nothing new, note "Codex: no additional findings."
- If Codex was skipped (not available), omit the section entirely — no mention of it.

**Persist Codex output to disk** (parallel to per-persona raw outputs from Phase 1): if Codex ran successfully, copy `/tmp/codex-spec-review.txt` → `docs/specs/<feature>/spec-review/raw/codex-adversary.md` (atomic write). The `findings-emit` step at Phase 2c reads this file to attribute `codex-adversary` in `personas[]` for any cluster that includes Codex's contribution.

## Phase 2c: Persona Metrics emit

Run the directive at `commands/_prompts/findings-emit.md`. It reads the on-disk `docs/specs/<feature>/spec-review/raw/*.md` files (per-reviewer outputs + optional `codex-adversary.md`), reads the synthesizer's clustering decisions from this turn's context, and atomically writes:

- `docs/specs/<feature>/spec-review/findings.jsonl`
- `docs/specs/<feature>/spec-review/participation.jsonl`
- `docs/specs/<feature>/spec-review/run.json`

Schemas at `schemas/{findings,participation,run}.schema.json`. `prompt_version: "findings-emit@1.0"` recorded on every emitted row.

If the metrics paths are tracked-and-not-gitignored AND `docs/specs/<feature>/.persona-metrics-warned` does not yet exist, print a one-line privacy warning and touch the sentinel file (suppresses warning on subsequent stage emits in the same feature).

## Phase 3: Present & Write

1. **Present consolidated review**:
   ```
   === REVIEW: [Feature Name] ===

   Overall health: [Good / Concerns / Significant Gaps]

   ## Before You Build ([count] items)
   [Prioritized list of critical questions/gaps]

   ## Important But Non-Blocking ([count] items)
   [Should address, won't block]

   ## Observations
   [Non-blocking notes worth considering]

   ## Reviewer Verdicts
   | Dimension | Verdict | Key Finding |
   |-----------|---------|-------------|
   | Requirements | PASS/NOTES/FAIL | ... |
   | Gaps | PASS/NOTES/FAIL | ... |
   | Ambiguity | PASS/NOTES/FAIL | ... |
   | Feasibility | PASS/NOTES/FAIL | ... |
   | Scope | PASS/NOTES/FAIL | ... |
   | Stakeholders | PASS/NOTES/FAIL | ... |

   ## Conflicts Resolved
   [Any agent disagreements and how they were resolved]

   [AUTORUN MODE: If AUTORUN=1 is set in your environment, skip this approval prompt. Write all artifacts and proceed immediately to the next stage. Do not output the approval prompt text below.]
   Approve to proceed to /blueprint? (approve / refine <what to change>)
   ```

2. **Write `docs/specs/<feature>/review.md`** with the full consolidated review.

## On Approve

Update the spec with any critical gaps that were resolved during review discussion. Announce:
```
Review approved. Spec updated. Ready for /blueprint.
```

## On Refine

Address the feedback, update the spec, re-run affected reviewers if needed, re-present.

## Key Principles

- **Show artifacts, not process** — present findings, not how they were produced
- **One approval at a time** — don't combine review with planning
- **You control the pace** — you decide when to approve
- **Parallel execution** — all 6 reviewers run simultaneously
- **Persistent artifacts** — review.md survives the session

**Arguments**: $ARGUMENTS
