# tests/ — Instructions

Applies in addition to the repo root `CLAUDE.md`.

## Bash 3.2 target

macOS ships bash 3.2 by default. All shell tests must run on it without
Homebrew bash. Forbidden constructs (grep the codebase for the pattern
`Bash 3.2 compatible` to see current per-file compliance headers):

- `${array[-1]}` — negative subscripts are bash 4+; on 3.2 under `set -e`
  this crashes the script. Use `$!` for last-launched PID, or track the
  last element explicitly.
- `declare -A`, `mapfile`/`readarray`, `local -n`, `read -a`, `[[ =~ ]]`
  against complex patterns, `&>`.
- Pin `BASH=/bin/bash` at the top of new test files so a contributor's
  gnubin-prefixed PATH doesn't silently run them under bash 5.

## Mocking shell helper functions

Use the **PATH-stub model**, not `export -f`. `export -f my_helper` does
not survive a sourced script redefining `my_helper()` afterward — the
script's own definition wins silently, and the mock is shadowed without
error.

Pattern: write executable stubs into a `mktemp -d` directory, prepend it to
`PATH`. Pair with a one-line override hook in the script under test:

```bash
has_cmd() {
    if [ -n "${MONSTERFLOW_HASCMD_OVERRIDE:-}" ]; then
        [ -x "$MONSTERFLOW_HASCMD_OVERRIDE/$1" ] && return 0 || return 1
    fi
    # …production behavior unchanged…
}
```

Production sets nothing → real behavior. Tests set the override env var →
deterministic mock control.

## Fixture paths must be absolute

Every file a test creates — stubs, fixtures, scratch dirs — must be anchored
at an absolute path (`$STUB_DIR`, `$CASE_HOME`, `$BATS_TMPDIR`, `$TMPDIR`),
never relative. A relative write lands in the repo root and pollutes
`git status`. This has caused stray committed-looking files from build-wave
test scaffolding before; grep `git status --porcelain` for stray
short-slug-named files before calling a wave done.

## `mktemp` portability

Always `mktemp -d -t <prefix>.XXXXXX` / `mktemp -t <prefix>.XXXXXX` — never
a bare prefix. GNU mktemp (via Homebrew coreutils + gnubin in PATH) rejects
bare prefixes with "too few X's"; BSD mktemp accepts them, so this only
breaks on some contributors' machines. Guard the result:

```bash
TMP="$(mktemp -d -t my-test.XXXXXX)"
[ -z "$TMP" ] || [ ! -d "$TMP" ] && { echo "FAIL: mktemp -d returned invalid path" >&2; exit 1; }
```

## Wiring new test files into the orchestrator

A test passing when run directly (`bash tests/test-X.sh`) is not the same
as it running under CI/local default. `tests/run-tests.sh` only executes
what's in its `TESTS` array. When a `/build` wave adds new test files,
name an explicit task that extends the array — don't assume it falls out
of "each agent writes its own test file." At `/preship`, confirm
`bash tests/run-tests.sh`'s reported count matches `ls tests/test-*.sh | wc -l`.
Also `chmod +x` new test files — the orchestrator treats a missing
executable bit as a failure.

## Parallel `/build` agents and shared files

Two failure modes when multiple wave agents run concurrently:

1. **Shared-file appends race.** If two agents both append to
   `tests/run-tests.sh`'s TESTS array (or any other shared file), each does
   Read → Edit against a snapshot that can go stale mid-flight, silently
   dropping a sibling's append. Fix: no agent prompt should say "append your
   entry to the shared file" — that's a single sequential orchestrator
   post-step, after all agents report DONE.

2. **A "pre-existing failure" claim from one agent mid-race may be a
   transient artifact** of a sibling's in-progress write, not a real
   pre-existing bug. Don't trust individual agents' "this was already
   broken" claims. Re-run the full suite yourself after all agents settle;
   only that result is authoritative.

Also forbid global git ops (`git stash`, `git checkout`, `git reset`) inside
parallel agent prompts — they affect the whole working tree, including
sibling agents' uncommitted edits. Baseline comparisons should read only the
agent's own files.

## Schema-version bumps need a prose grep, not just the lockstep test

When a `const`-pinned field (`schema_version`, `prompt_version`) bumps, the
schema/validator lockstep test proves the two are in sync — it does not
catch stale-version JSON examples embedded in `commands/*.md` prose or
`scripts/autorun/*.sh` heredocs (synthesis prompts, dry-run stubs). Those
surfaces instruct an LLM to emit the old shape, which then fails
`additionalProperties: false` validation at runtime, not at CI time. After
any such bump, run a grep for the old version literal across
`commands/ scripts/ docs/ tests/`, excluding intentionally-old-shaped
negative fixtures.
