---
description: Execute the implementation plan with parallel agents
---

**IMPORTANT: Do NOT invoke superpowers planning skills from this command. Superpowers execution skills (debugging, verification) ARE used during build.**

You are the build step in the pipeline: `/spec → /spec-review → /blueprint → /check → /build`

Your job is to execute the implementation plan using parallel agents where possible, with superpowers discipline skills active.

## Pre-flight

1. **Find artifacts**: Load `docs/specs/<feature>/design.md` and optionally `docs/specs/<feature>/check.md`.
   - If `$ARGUMENTS` names a feature, use that.
   - If plan doesn't exist: "No plan found. Run /blueprint first."
   - If check doesn't exist: "Plan not checked. Run /check first, or proceed without checkpoint? (Skipping /check increases rework risk.)"
   - If check exists and verdict was NO-GO: "Checkpoint failed. Fix the plan with /blueprint first."

2. **Load constitution** (if exists) and spec for context.

## Phase 0: Persona Metrics — survival classifier (addressed-by-revision mode)

Pre-flight before execution. If `docs/specs/<feature>/check/findings.jsonl` exists, run `commands/_prompts/survival-classifier.md` in **addressed-by-revision** mode:

- Inputs: `<feature>/check/findings.jsonl` + `<feature>/check/source.design.md` (pre-snapshot) + current `<feature>/design.md` (post-revision).
- **Pre-revision warning:** if `mtime(design.md) < mtime(check/findings.jsonl)`, emit a warning that `design.md` hasn't been edited since `/check`. Run anyway.
- Idempotency: skip if recorded `artifact_hash` matches `sha256(design.md)`; re-classify otherwise.
- Outcome semantics: addressed-by-revision (substance NOT in source.design.md but IS in design.md after revision).
- Output: atomic write to `<feature>/check/survival.jsonl`. Echo one-liner if any `classifier_error` rows are written.

If `<feature>/check/findings.jsonl` does not exist, silent no-op.

**This phase never blocks the build.**

## Phase 0c: Verdict-Gated Followups Consumption

Before presenting the execution plan, gate `/build` on the most-recent `/check` verdict sidecar and consume any open followups it queued. This is `/build`-specific logic — it does not read CLI mode flags; it reads the verdict's own `mode` field.

### Step 1 — Read the verdict sidecar (HARDCODED path)

Read `docs/specs/<feature>/check-verdict.json`. `/build` does **NOT** fall through to other gate sidecars (e.g. spec-review or plan stage sidecars) — those are write-only audit artifacts in v1 and are explicitly out of scope for `/build` consumption (per Cross-cutting Decisions Pinned in plan).

### Step 2 — Legacy-detection ladder (4-path)

Walk these in order; the first match wins:

1. **Missing sidecar** (`check-verdict.json` does not exist at the path) — pre-v0.9.0 spec. Set `FOLLOWUPS_AVAILABLE=false`. Proceed with today's behavior: no followups consumption, no banner, no error. Continue to Phase 1.

2. **Malformed JSON sidecar** (file exists but `python3 -c "import json,sys; json.load(open(sys.argv[1]))" check-verdict.json` fails) — refuse with stderr error:
   > `verdict file unreadable; re-run /check or rm <path>`

   Exit non-zero. Do not dispatch any wave.

3. **v1 sidecar** (file parses; `schema_version: 1`) — refuse with stderr error:
   > `this spec uses pre-v0.9.0 verdict format; re-run /check to regenerate at v2.`

   Exit non-zero. Do not dispatch any wave.

4. **v2 sidecar** (file parses; `schema_version: 2`) — proceed to Step 3.

### Step 3 — Verdict-gate (v2 only)

Read the `verdict` field. Required: `verdict ∈ {GO, GO_WITH_FIXES}` to proceed. On `verdict: NO_GO`, refuse with stderr:
> `/check returned NO_GO; address blocking findings before /build`

Exit non-zero.

### Step 4 — Read followups.jsonl

When `verdict ∈ {GO, GO_WITH_FIXES}`, read `docs/specs/<feature>/followups.jsonl` and filter to rows where:

- `state: "open"` (i.e. `state == "open"`) AND
- `target_phase IN ("build-inline", "docs-only")`

These are wave-1 task additions.

### Step 5 — Route by `target_phase`

For each open followup:

- **`build-inline`** — prepend to wave-1 task list as a regular implementation task.
- **`docs-only`** — prepend to wave-1 task list as a docs/comments-only task.
- **`plan-revision`** — STOP wave 1. Emit:
  > `/blueprint re-run required for <count> finding(s)`

  Then abort `/build`. The user must re-run `/blueprint` to address structural findings before `/build` can proceed.
- **`post-build`** — hold for the PR-body annotation phase. Do **NOT** add to wave 1.

## Phase 1: Present Execution Plan

Parse the plan's task breakdown and present:

```
=== BUILD: [Feature Name] ===

Tasks: [total count]
Waves: [count based on dependency analysis]

Wave 1: [tasks with no dependencies] ([count] parallel agents)
Wave 2: [tasks depending on Wave 1] (blocked until Wave 1 completes)
...

Execution discipline:
- Debugging: superpowers:systematic-debugging
- Verification: superpowers:verification-before-completion
- Testing: write thorough tests

[AUTORUN MODE: If AUTORUN=1 is set in your environment, skip this approval prompt. Write all artifacts and proceed immediately to the next stage. Do not output the approval prompt text below.]
Launch Wave 1?

- **a) Launch** — dispatch Wave 1 agents now
- **b) Hold** — pause and review the plan first (`b I want to adjust task X`)

Reply with `a` or `b <reason>` + Enter.
```

## Phase 2: Execute Waves

On `a`:

1. **Dispatch Wave 1** — launch parallel agents for independent tasks using the Agent tool.
   - Each agent receives: the spec, plan, relevant plan tasks, constitution
   - Each agent writes thorough tests alongside implementation
   - Each agent reports: DONE, DONE_WITH_CONCERNS, NEEDS_CONTEXT, or BLOCKED

2. **Monitor Wave 1** — as agents complete:
   - DONE: mark task complete, unblock Wave 2 dependents
   - DONE_WITH_CONCERNS: review concerns, decide whether to proceed
   - NEEDS_CONTEXT: provide context and resume
   - BLOCKED: investigate, unblock or reassign

3. **Launch subsequent waves** as dependencies resolve.

4. **Between waves**: brief status update to Justin.

## Phase 3: Verification

After all waves complete:

1. Run verification checks (build, tests, lint)

## Phase 3a: Autorun-shell-reviewer dispatch (when scripts/autorun/*.sh modified)

Before the Codex implementation review and pre-commit step, check whether
this /build modified `scripts/autorun/*.sh`:

```bash
AUTORUN_CHANGES=$(git diff --name-only HEAD scripts/autorun/ 2>/dev/null | head -20)
if [ -n "$AUTORUN_CHANGES" ]; then
  echo "[build] autorun-shell-reviewer dispatch — scripts/autorun/ changed:"
  echo "$AUTORUN_CHANGES" | sed 's/^/  /'
  # Invoke the autorun-shell-reviewer subagent via the Agent tool with:
  #   subagent_type: "autorun-shell-reviewer"
  #   prompt: describe the diff and ask for High/Medium/Low findings
  # Halt on High findings; iterate up to 3 attempts (per
  # pipeline-iterative-resolution-loops convention); on 3rd failure,
  # surface findings to user as DONE_WITH_CONCERNS and stop pre-commit.
fi
```

When `AUTORUN_CHANGES` is non-empty, **you must**:

1. Invoke the `autorun-shell-reviewer` subagent via the Agent tool
   (`subagent_type: "autorun-shell-reviewer"`). Pass a prompt that includes
   the list of changed files and asks for High/Medium/Low findings per the
   subagent's pitfall checklist.

2. **On High findings:** apply fixes and re-invoke the subagent. Repeat up
   to **3 attempts** total (per pipeline-iterative-resolution-loops convention).
   - Attempt 1 — fix High findings, re-invoke.
   - Attempt 2 — fix remaining High findings, re-invoke.
   - Attempt 3 failure — do NOT pre-commit. Surface all unresolved High
     findings to Justin as `DONE_WITH_CONCERNS` and stop. Do not proceed to
     pre-commit or PR until the user acknowledges.

3. **On Medium/Low findings only:** log them in the build summary and proceed
   to the Codex review step. Medium/Low do not block commit.

4. **No changes to scripts/autorun/*.sh:** skip this phase entirely (silent).

2. **Codex implementation review (if available)** — silent skip if not installed/authenticated:

   ```bash
   if command -v codex >/dev/null 2>&1 && codex login status >/dev/null 2>&1; then
     codex exec review --uncommitted --full-auto --ephemeral \
       --output-last-message /tmp/codex-build-review.txt \
       "Challenge the implementation. Look for: security issues, deviations from the plan, better approaches that weren't taken, and correctness problems the tests might not catch."
   fi
   ```

   If `/tmp/codex-build-review.txt` exists and contains findings, include a **Codex Review** section in the build complete summary. If skipped or no findings, omit.

3. **Run `/preship`** — pre-commit gate before declaring done:
   - `git status` for uncommitted WIP
   - Verify any CLI flags suggested this session
   - Audit numbered instructions from the user (all ✓ before reporting done)

4. Present results:
   ```
   === BUILD COMPLETE: [Feature Name] ===

   Tasks completed: [count]
   Tests: [pass/fail count]
   Build: [pass/fail]

   Concerns raised during build:
   - [any DONE_WITH_CONCERNS items]

   Codex review: [findings summary, or "skipped / no additional findings"]

   Next steps:
   - Code review: superpowers:requesting-code-review (quick) or /code-review (PR)
   - Wrap up: /wrap
   ```

## Phase 4: Wave-Final Mark Addressed

After all wave commits have landed and Phase 3 verification has passed, mark any consumed followups as `addressed` in `followups.jsonl` so future `/check` cycles know they were resolved.

This phase fires **after** the wave-final commit lands — it uses the wave-final commit SHA, not any intermediate commit.

### Pre-v0.9.0 backcompat

If `docs/specs/<feature>/check-verdict.json` does not exist (legacy path established in Phase 0c — `FOLLOWUPS_AVAILABLE=false`), Phase 4 is a no-op. There are no followups to mark.

### Mark addressed

For each followup whose `finding_id` was addressed in this `/build`'s wave-final commit, call:

```bash
WAVE_FINAL_SHA=$(git rev-parse HEAD)
python3 scripts/build-mark-addressed.py \
  --feature <slug> \
  --finding-ids <id1,id2,...> \
  --commit-sha "$WAVE_FINAL_SHA"
```

Semantics:

- The commit SHA comes from `git rev-parse HEAD` **after** the wave-final commit lands.
- The script writes `state: addressed` back to the matching followups.jsonl rows.
- The script **refuses** on `state: superseded` rows — those are not addressable.
- The script is **idempotent** on `state: addressed` rows — re-running is safe.

## Key Principles

- **Wave-based execution** — respect dependency order
- **Parallel where possible** — independent tasks run simultaneously
- **Justin controls pace** — approval before each wave (can be overridden with "go all")
- **Superpowers for execution** — debugging, verification skills are active here
- **Report, don't hide** — surface concerns immediately

**Arguments**: $ARGUMENTS
