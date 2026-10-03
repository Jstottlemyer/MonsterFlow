# `/build` implementation workers: Claude subagents or Codex

`/build` runs a feature's plan wave by wave. Each task in a wave is
implemented by a worker. By default the workers are Claude Code subagents
(the Agent tool). With `build_workers: "codex"`, each task goes to a Codex
CLI worker instead.

Only the implementation moves. The Claude Code session running `/build` (the
orchestrator) keeps everything else, unchanged:

- the task graph, wave order and the approval prompt before each wave;
- task contracts (what each task owns, how to verify it, which build note to write);
- verification: it re-runs the full suites itself after every wave;
- commits, `/preship`, and every remote action (push, PR, merge).

Turning it on is **additive**. With the key absent, `/build` behaves exactly
as it always has.

## Turn it on

Prerequisite: the Codex CLI is installed and signed in
(`codex login status` succeeds). See
[QUICKSTART §2b](../QUICKSTART.md#2b-enable-codex-multi-model-reviews-optional).

Set the key in `~/.config/monsterflow/config.json`
([QUICKSTART §6c](../QUICKSTART.md#6c-codex-implementation-workers-for-build-optional-opt-in)
has a copy-paste snippet that preserves your other keys):

```json
{
  "$schema_version": 1,
  "build_workers": "codex",
  "codex_worker_model": "<optional model>"
}
```

| Key | Values | Default | Effect |
|---|---|---|---|
| `build_workers` | `"claude"` \| `"codex"` | `"claude"` (key absent) | Who implements `/build` tasks |
| `codex_worker_model` | any model your Codex account can use | Codex's own default | Passed as `codex exec -m` |

Precedence for the model: `--model` on the adapter, then
`$MONSTERFLOW_CODEX_WORKER_MODEL`, then `codex_worker_model`, then Codex's
default.

**Per run:** you can switch without editing config. Tell `/build` "use Codex
workers" or "use Claude subagents" at a wave approval prompt; it applies
from the next wave and is recorded in the build notes.

**Turn it off:** set `"build_workers": "claude"` or delete the key.

## Check the model before a long build

```bash
bash scripts/build-codex-worker.sh --probe-model            # configured model
bash scripts/build-codex-worker.sh --probe-model --model X  # a specific one
```

Exit 0: usable. Exit 6: not usable on this account (some models are not
available to every account type; the error is printed). Exit 3: Codex is not
installed or not signed in. `/build` runs this probe before the first Codex
wave.

## What a Codex worker can and cannot do

Each task runs through `scripts/build-codex-worker.sh` as
`codex exec --sandbox workspace-write` with network access off:

| Worker can | Worker cannot (the orchestrator does it) |
|---|---|
| Edit files inside the repo | Commit, stage or touch `.git` (read-only) |
| Run typecheck and tests that don't need sockets | Install dependencies (no network); it reports what it needs |
| Write tests and build notes | Run tests that bind or connect to `127.0.0.1` (local DB servers, HTTP harnesses, parity suites) |

So after each Codex wave the orchestrator installs any reported dependency
(keeping the lockfile change minimal), runs the socket-dependent suites,
re-runs everything, and only then commits. A worker's claim that a failure
"was already there" is checked, not trusted.

The worker reports in `<task-dir>/<task-id>.last.md`, whose first line is
`DONE`, `DONE_WITH_CONCERNS`, `NEEDS_CONTEXT` or `BLOCKED`: the same four
statuses `/build` already handles. Progress streams to
`<task-dir>/<task-id>.events.jsonl`; a worker that adds nothing to it for
about 10 minutes is treated as stalled.

## Project-specific worker rules

Every worker gets the generic rules in `templates/build-worker-preamble.md`.
To add rules for one repository, create `.monsterflow/build-worker-preamble.md`
in that repo; the adapter appends it after the generic rules. Typical
entries: a command workers must never run (for example a package manager
that tries the network and damages the dependency tree), or how to run the
project's tests through local binaries.

## Running the adapter by hand

```bash
bash scripts/build-codex-worker.sh [--repo DIR] [--model M] <task-dir> <task-id>
```

It reads `<task-dir>/<task-id>.prompt.md` and writes `.last.md`,
`.events.jsonl` and `.stderr.log` next to it. Exit codes: 0 report written;
2 usage or missing contract; 3 Codex unavailable; 4 Codex failed; 5 no
report.

## Troubleshooting

- **A Codex process sits at 0% CPU with "Reading additional input from
  stdin".** `codex exec` was started without its stdin closed. The adapter
  and `scripts/build-codex-review.sh` always pipe or redirect stdin; if you
  call `codex exec` yourself in the background, add `< /dev/null`.
- **Exit 6 on the probe.** Pick another model, or remove
  `codex_worker_model` to use Codex's default.
- **A worker's tests fail only in the sandbox** (`listen EPERM` and similar).
  Those tests need sockets; the orchestrator runs them.

## Phase 3 review

Separately from the workers, `/build` Phase 3 asks Codex (when available) to
review the build via `scripts/build-codex-review.sh`. It reviews the commits
since the build's base plus any uncommitted changes, in a read-only sandbox,
and skips silently when Codex is not set up. That runs whether or not
`build_workers` is `codex`.
