---
status: in-flight
tags: [pipeline]
gate_mode: permissive
---

# build-codex-workers Spec

**Created:** 2026-10-02
**Constitution:** none — MonsterFlow personal-tooling repo uses pipeline-default personas

## Summary

Let `/build` hand the implementation of each plan task to a Codex CLI worker instead of a Claude Code subagent, as an **opt-in** (`build_workers: "codex"` in `~/.config/monsterflow/config.json`). Claude Code stays the orchestrator: the task graph, wave order and approvals, task contracts, verification, commits and every remote action are unchanged. With the key absent, `/build` behaves exactly as before.

The same change fixes three `/build` defects that surfaced in the run below:

1. Phase 3's Codex implementation review ran `codex exec review --uncommitted`. `/build` commits every wave, so by Phase 3 there is nothing uncommitted and the review sees nothing.
2. `codex exec review --base` cannot take custom instructions, and a backgrounded `codex exec` whose stdin is left open blocks forever on "Reading additional input from stdin" (observed: 73 minutes at 0% CPU).
3. Phase 4 called `python3 scripts/build-mark-addressed.py`, a path that exists only inside the MonsterFlow repo, so it failed in every other project.

## Evidence

A full `/build` of the Red Rabbit `canon-resolution-and-world-isolation` feature (2026-10-01/02) switched from Claude subagents to Codex workers from Wave 2b onward, at the maintainer's request, without changing the plan or task decomposition. 34 Codex worker runs implemented 18 plan tasks (Wave 2b, a gap task, and Wave 3) plus fix-ups and implementation-review fixes; the orchestrator verified, ran socket-dependent suites and parity, and committed. Lessons now encoded here:

- The workspace-write sandbox has a read-only `.git`, no network and no localhost sockets. Workers cannot install dependencies, commit, or run local-server and parity suites, so the orchestrator must.
- A package-manager run inside the sandbox tried the network and deleted the installed dependency tree. Projects need a way to forbid such commands: a per-repo worker preamble.
- A requested model was not available on the user's Codex account type. Probe the model before dispatching a wave.
- Two worker contracts asserted contradictory behavior; the worker correctly stopped with `NEEDS_CONTEXT`. The four existing `/build` statuses map cleanly onto worker reports.

## Requirements

- **R1 (additive).** `build_workers` absent or `"claude"` → Phase 2 dispatches Agent-tool subagents exactly as today. Only `"codex"` changes dispatch.
- **R2 (adapter).** `scripts/build-codex-worker.sh <task-dir> <task-id>` runs one task contract through `codex exec --sandbox workspace-write` with network access off, `--ephemeral --json`, the prompt on stdin (never left open), and writes `<task-id>.last.md`, `.events.jsonl` and `.stderr.log`. Prompt = `templates/build-worker-preamble.md`, then the target repo's optional `.monsterflow/build-worker-preamble.md`, then the contract.
- **R3 (model).** `--model` > `$MONSTERFLOW_CODEX_WORKER_MODEL` > `codex_worker_model` > Codex default. `--probe-model` exits 0 when the model is usable and 6 when it is not.
- **R4 (fallback).** Codex not installed or not signed in → exit 3, and `/build` uses Claude subagents and says so.
- **R5 (orchestrator duties).** `commands/build.md` Phase 2 documents what stays with the orchestrator: dependency installs, socket-dependent suites, full re-verification, commits, remote actions, stall detection from the event log, and recording a mid-build provider switch.
- **R6 (Phase 3 review).** `scripts/build-codex-review.sh` reviews the commits since the build's base plus uncommitted changes, with custom instructions, in a read-only sandbox, stdin closed; silent skip (exit 0, no output) without Codex.
- **R7 (Phase 4 path).** Phase 4 calls `<REPO_DIR>/scripts/build-mark-addressed.py`.
- **R8 (discoverable).** `QUICKSTART.md` §6c (opt-in section, like §6b Agent Budget) shows how to turn it on, probe, and turn it off; `docs/build-workers.md` is the full reference; `docs/budget.md` and the resolver's config schema list both keys.

## Acceptance criteria

All covered by `tests/test-build-codex-worker.sh` (PATH-stub fake `codex`; the real CLI is never invoked), wired into `tests/run-tests.sh`.

- **AC1** Exit 3 without Codex or without auth; exit 2 for a missing contract; exit 4 on Codex failure; exit 5 when no report is written.
- **AC2** Happy path passes `--sandbox workspace-write`, `sandbox_workspace_write.network_access=false`, `--ephemeral`, `--json`, `--cd <repo>`, prompt on stdin; stdin order is preamble, project overlay, contract; an open endless caller stdin does not reach Codex.
- **AC3** Model precedence `--model` > env > config > none; probe exit 0 / 6.
- **AC4** Review: read-only sandbox, instructions name `<base>..HEAD`, never `--uncommitted`, Codex stdin empty even when the caller's stdin is an endless stream (fails rather than hangs if regressed), silent skip without Codex, exit 4 on failure.
- **AC5** `build.md` anchors: Phase 2 section, Claude-default wording, Codex-unavailable fallback, adapter dispatch line, Phase 3 review script, no `--uncommitted`, Phase 4 `<REPO_DIR>` path.
- **AC6** Config schema enum `claude|codex` and string model; `docs/budget.md` key rows; QUICKSTART §6c and its link to `docs/build-workers.md`; the reference doc covers enabling, probing and disabling; the preamble template ships.

## Out of scope

- Codex workers for review gates (`/spec-review`, `/blueprint`, `/check` already run Codex as an additive adversary).
- Running `/autorun`'s build stage on Codex workers.
- Tooling to re-slice a build's commits into the plan's PR stack: see `BACKLOG.md` (`build-pr-stack-materialize`).
