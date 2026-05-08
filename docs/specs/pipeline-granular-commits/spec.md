---
gate_mode: permissive
gate_max_recycles: 2
---

# Pipeline Granular Commits Spec

**Created:** 2026-05-08
**Constitution:** none — session roster only
**Confidence:** Scope 0.95 / UX 0.90 / Data 0.95 / Integration 0.85 / Edges 0.85 / Acceptance 0.95
**gate_mode:** permissive
**gate_max_recycles:** 2

## Summary

Reduce blast radius of `git reset --hard` rollbacks during autorun by emitting one commit per persona raw output at `/spec-review` + `/check`, separate commits for synthesis and verdict sidecar, and one commit per task inside `/build` waves instead of one commit per wave-end. Squash-merge at PR-time preserves clean `main` history; granular commits exist only on the autorun branch where they're load-bearing for recovery.

## Backlog Routing

This spec was carved from in-conversation observation (2026-05-08) that last week's dynamic-roster-per-gate verifier-pedantry near-rollback would have lost 5 good commits at once. No prior backlog entry; no items to route.

## Scope

**In scope:**
- `scripts/autorun/spec-review.sh` — commit each `docs/specs/<feature>/spec-review/raw/<persona>.md` atomically as it lands; separate commits for `review.md` (synthesis) and `findings.jsonl` + `participation.jsonl` + `run.json` (metrics + verdict).
- `scripts/autorun/check.sh` — same shape: per-reviewer raw commit + synthesis commit + verdict sidecar commit (`check-verdict.json`).
- `scripts/autorun/build.sh` — one commit per wave-task (each `/build` subagent's diff lands as its own commit) instead of one batched wave-end commit. Orchestrator wiring (test runner updates, etc.) is a single sequential post-step commit after all wave-task commits land.
- Codex adversarial output (`raw/codex-adversary.md`) gets its own commit at any gate where it ran.
- Squash-merge default at PR creation time stays unchanged — `gh pr merge --squash` collapses the granular commits into one before they hit `main`.

**Out of scope:**
- `/plan` — single synthesis output, atomic by nature; no change.
- `/spec` — interactive, no multi-output structure to split.
- Manual (non-autorun) pipeline runs — no shell-script commit machinery to modify.
- History-rewriting existing autorun branches.
- Changing the squash-merge convention.

## Approach

**Chosen:** modify each autorun stage script to call a small helper `scripts/_autorun_commit.sh <path> <message>` that does atomic `git add <path> && git commit -m <message>` (per memory `feedback_git_add_then_commit_sweeps_index.md` — explicit pathspec, never `git add -A`). Helper is a thin wrapper that:
- Skips empty diffs (early return + log line; not an error).
- Includes `[autorun-granular]` token in commit message body so post-merge consumers can identify which commits were per-stage granular vs single-stage.
- Preserves `[skip-auto-bump]` token on every commit (autorun runs are not version events).

Rejected alternatives:
- *Single big commit at stage end with a manifest file listing intermediate states* — defeats the point; rollback still loses N work units.
- *Use `git stash push -k --keep-index`-style staging instead of commits* — fragile across the 8-stage autorun, breaks if a stage exits unexpectedly.

## Roster Changes

No roster changes. Existing `autorun-shell-reviewer` subagent is the right gate for the `scripts/autorun/*.sh` modifications this spec produces.

## UX / User Flow

**Today (single-commit-per-stage):**
```
autorun branch:
  abc123 spec-review: 6 personas + synthesis + metrics
  def456 plan
  ghi789 check: 5 reviewers + synthesis + verdict
  jkl012 build wave 1 (3 tasks + orchestrator wiring)
  mno345 build wave 2 (2 tasks)
```
Verifier wedge at wave 2 → `git reset --hard HEAD~1` loses 2 good tasks.

**With this spec (granular):**
```
autorun branch:
  abc123 spec-review: raw/requirements.md
  abc124 spec-review: raw/gaps.md
  abc125 spec-review: raw/ambiguity.md
  abc126 spec-review: raw/feasibility.md
  abc127 spec-review: raw/scope.md
  abc128 spec-review: raw/stakeholders.md
  abc129 spec-review: raw/codex-adversary.md  (if Codex ran)
  abc130 spec-review: synthesis (review.md)
  abc131 spec-review: metrics (findings + participation + run.json)
  ...
  jkl010 build wave 1 task 1: <slug>
  jkl011 build wave 1 task 2: <slug>
  jkl012 build wave 1 task 3: <slug>
  jkl013 build wave 1: orchestrator wiring (run-tests.sh)
  jkl020 build wave 2 task 1: <slug>
  jkl021 build wave 2 task 2: <slug>
```
Verifier wedge at wave 2 task 2 → `git reset --hard HEAD~1` loses 1 task. PR squash-merge collapses all of these to a single commit on `main`.

## Data & State

- No new persistent state. Existing on-disk artifacts (`raw/<persona>.md`, `synthesis.md`, sidecars) are unchanged; only the commit timing changes.
- New helper script: `scripts/_autorun_commit.sh` (~30 LoC).
- No schema changes.

## Integration

- `scripts/autorun/spec-review.sh` — replace single `git add docs/specs/<feature>/spec-review/ && git commit` with per-file calls to `_autorun_commit.sh` after each persona's raw write returns. Synthesis call already runs after all raws return; commits separately. Metrics emit (`findings-emit.md` directive) commits separately.
- `scripts/autorun/check.sh` — same edits, mirroring the review's two-phase parallel-then-synthesis structure.
- `scripts/autorun/build.sh` — replace wave-end `git add -A && git commit` (per memory `feedback_git_add_then_commit_sweeps_index.md` — explicitly pathspec) with one commit per wave subagent. Each subagent's prompt already restricts it to specific file paths; capture those at dispatch time and pass to the helper after the subagent returns.
- `scripts/autorun-batch.sh` — no changes (operates on stages, not commits).
- `commands/spec-review.md` / `commands/check.md` / `commands/build.md` — no changes (these are the interactive-mode skills; no shell-script commit machinery).

Touched files: 4 shell scripts + 1 new helper + 1-3 test fixtures. Estimated ~100-200 LoC delta.

## Edge Cases

- **Empty raw output (persona crashed mid-write):** `_autorun_commit.sh` detects empty diff → log + skip, no error. The downstream synthesis call already handles missing-persona cases.
- **Failed synthesis after raws committed:** raws stay committed (good — recoverable). Synthesis failure surfaces via existing failure path. On retry, raws don't re-commit (already in git); only synthesis runs.
- **Build subagent that writes no files:** empty diff → log + skip + warn. May indicate subagent failure; existing failure detection unchanged.
- **Concurrent persona writes:** already atomic on disk via tmp + `os.replace`; commits are serialized via the bash script (not parallel) so no race.
- **Pre-existing failed-attempt commits on autorun branch:** `scripts/autorun-rotate-artifacts.sh` already rotates `queue/<slug>/runs/<prev_run_id>/`; this spec doesn't change rotation. Re-running a stage on a fresh attempt branch gets fresh commits.
- **PIPESTATUS reset after `|| true`:** per memory `feedback_pipestatus_or_true.md`, helper must capture `git commit` exit inside the `||` branch, not after.
- **Pathspec includes a directory just created in the same wave:** `git add <dir>` on an empty dir is a no-op; that's fine — the next persona writes a file and commits it.
- **Squash-merge on PR with 30+ granular commits:** verified working via existing `gh pr merge --squash --admin`. No changes needed; PR description still authored from the spec/synthesis content.

## Acceptance Criteria

1. After `/spec-review` on N personas (N=2..8), `git log --oneline` on the autorun branch shows N+2 commits attributable to spec-review (N raw + 1 synthesis + 1 metrics+verdict). +1 if Codex ran.
2. After `/check` on M reviewers, same shape: M+2 commits (M raw + 1 synthesis + 1 verdict sidecar). +1 if Codex ran.
3. After `/build` wave with K tasks, K+1 commits (K task commits + 1 orchestrator-wiring commit).
4. Each granular commit message includes `[autorun-granular]` and `[skip-auto-bump]` tokens.
5. Each granular commit's diff is restricted to the single artifact (or single subagent's file paths) it represents — no incidental sweeping of working-tree changes.
6. Test fixture `tests/test-autorun-granular-commits.sh` simulates a verifier wedge mid-build-wave-2 and asserts that `git reset --hard HEAD~1` preserves all but the last task commit (and that the lost task can be re-attempted without affecting earlier wave-2 commits).
7. Test fixture asserts that `gh pr merge --squash` (mocked) collapses all granular commits to a single commit on the target branch.
8. Auto-bump hook does NOT fire on autorun branches (verified via `[skip-auto-bump]` token in each commit message).
9. `autorun-shell-reviewer` subagent passes a clean review against the modified `spec-review.sh` / `check.sh` / `build.sh` against its 13-pitfall checklist (especially: PIPESTATUS reset, explicit pathspec, no `-A` sweeps).
10. Empty-diff edge cases (crashed persona, build subagent that wrote nothing) emit a single log line without aborting the stage.

## Open Questions

None blocking. One latent: should the granular commits be tagged (lightweight tag per stage transition) for easier `git log --decorate` reading on long autorun branches? Default no — tags are global namespace pollution and the commit message tokens already make grep-style filtering trivial. Revisit if recovery investigations get hard.
