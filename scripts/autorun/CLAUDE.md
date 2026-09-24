# scripts/autorun/ — Instructions

Applies in addition to the repo root `CLAUDE.md`. Scope: this directory's
`*.sh` files and the pipeline they implement.

## Stage architecture (as of v0.8.x)

- **`spec-review.sh`** and **`check.sh`**: N parallel `claude -p` calls (one
  per persona, disk-discovered from `personas/<gate>/`). No `--add-dir` —
  spec/plan content passed inline. `TIMEOUT_PERSONA=600s` per persona; merge
  step concatenates raw outputs.
- **`check.sh`**: two-phase — Phase 1 is parallel reviewers, Phase 2 is one
  synthesis call that reads all reviewer outputs and produces the GO/NO-GO
  verdict.
- **`design.sh`**: single Claude synthesis call (needs all review findings
  coherently), no `--add-dir`. Followed by a Codex adversarial design
  critique when the resolver emits `codex-adversary` for the design gate;
  output is appended to `design.md` as a labeled section so `/check` sees it
  via existing reads. Codex failure at the design gate is non-fatal.
- **Persona directory mapping**: gate name ≠ directory name only for
  spec-review (`personas/review/`); design and check share their gate name
  (`personas/design/`, `personas/check/`). Never walk `personas/<gate-name>/`
  for spec-review directly.
- **`TIMEOUT_PERSONA`** (default 600s) is per-persona; `TIMEOUT_STAGE`
  (default 1800s) is for synthesis calls. Both configurable via
  `queue/autorun.config.json`.

## Agent budget (token-cost control)

The persona resolver (`scripts/resolve-personas.sh` / `_resolve_personas.py`)
reads `~/.config/monsterflow/config.json` for an `agent_budget` integer
(range 1–8). When set, the resolver caps the Claude-persona dispatch at that
count per gate; `codex-adversary` is appended separately and does NOT count
against the budget. Default (no config or no key) = full on-disk roster.

Recommended: `{"agent_budget": 3}` gives 3 Claude + 1 Codex per gate
(`/spec-review`, `/blueprint`, `/check`) — roughly 50% Claude-token
reduction vs the full 7/7/6 roster, while keeping an independent-model lens
via Codex. Selection is data-driven (rankings from persona insights, falling
back to seed list, then alphabetical). Once a feature is in flight, its
picks are locked at `docs/specs/<feature>/.budget-lock.json` for
deterministic reruns.

Kill switch: `MONSTERFLOW_DISABLE_BUDGET=1` bypasses the cap (full roster).
Use only in emergencies; the `selection.json` audit trail records
`selection_method=kill-switch`.

## Pre-commit review gate

**Before committing any change to `scripts/autorun/*.sh`**, invoke the
`autorun-shell-reviewer` subagent (`Agent(subagent_type: "autorun-shell-reviewer")`).
It codifies a 13-pitfall checklist (PIPESTATUS index, `|| true` reset,
grep-c arithmetic, branch invariant, STOP race, slug regex, eval scope,
SSH/HTTPS remote, AppleScript injection, `--auto` merge ambiguity, empty-PR
loophole, truncated diff, quoting). Treat High findings as blocking, apply
them inline before commit; Medium/Low may defer to a follow-up commit.

This must be pre-commit, not post-hoc. A `/build` wave that modifies files
in this directory should report DONE with changes staged-but-not-committed;
the orchestrator runs the subagent over the staged set, then commits. Relying
on a later code-review pass to catch the same list means the issue is
already in commit history when found — harder to fix cleanly, and it has
already been missed once here (PR #7, `check.sh`).

Tests for the subagent's frontmatter live at `tests/test-agents.sh`. Run
`bash tests/run-tests.sh agents` to validate.

## Stub / dry-run modes must produce the full artifact graph

`AUTORUN_DRY_RUN=1` stubs must write every artifact the stage downstream
reads, not just this stage's own output. A stub that skips an artifact
either forces smoke tests to weaken their assertions (false confidence) or
lets stage-handoff bugs through undetected — the exact class of bug a smoke
test exists to catch. If the stub is "skip the expensive part," it should
still emit a skeleton output of the same shape.

## Security findings: N-attempt cap, never first-cycle halt

`class:security` findings from `/check` must not auto-halt the pipeline on
the first cycle. Allow up to **3 resolution attempts** (`SECURITY_MAX_FIX_ATTEMPTS`,
env-overridable), each logged to `.security-attempts.log`
(JSONL: timestamp, run_id, attempt, max_attempts, sec_count, finding_ids).
Block only once `attempt >= max_attempts`. Counter resets to 0 on a clean
check; persists across an integrity block (that's its own signal, not
security clearance); resets on a fresh `run_id`. Security findings still get
tagged `sev:security` and surfaced in `findings.jsonl` — they just don't
gate the pipeline on attempt 1.

## Verdict policy axes

`queue/autorun.config.json` → `policies.{verdict,branch,codex_probe,verify_infra}`
each take `warn` or `block` independently. For the permissive-by-default
contract to hold end-to-end, `verdict` must be `warn` — leaving any axis at
its old hardcoded `block` default silently reintroduces first-cycle halts.

## When `/build` exhausts 3 attempts under autorun

That signals the spec is structurally too wide for unsupervised wave-based
execution — not `/build` incompetence. Watch for "no commits since
pre-build SHA (substantive)" + "exhausted N retries — rolling back" in
autorun output. Carve the spec into 3-5 slices along responsibility
boundaries (schema-only / single-script / command-wiring / etc.), each:

- Metadata-only OR single-coherent-purpose (not "schema + script + command + test" combined)
- ≤300 lines of spec.md, ≤200 LoC implementation, ≤1 new test file
- Independently shippable, though a slice may depend on a prior one

Name slices `<parent-spec>-1-<noun>`, `<parent-spec>-2-<noun>`, etc. Keep
the parent spec in `docs/specs/<parent>/` as an overview pointing at the
slices.

## When `/verify` keeps citing unsatisfiable evidence ACs

If `/verify` returns INCOMPLETE across multiple retries citing the same
diff-uninspectable ACs (e.g. "all tests pass" wanting test-run stdout
inside the commit), don't let blind retries roll back good commits. The
root cause is usually the AC itself — it must be either diff-inspectable or
explicitly delegated to a separate verification step.

Recovery: `touch queue/STOP` (checked at top of the retry loop, so the
in-flight attempt still finishes) → `git checkout main` (required before
any manual reset; the branch-mismatch integrity guard in `build.sh`
otherwise blocks `git reset --hard` from firing, which is the thing that
protects good commits) → manually verify on `autorun/<slug>`
(`bash tests/run-tests.sh`, compare pass count vs main) → if clean,
`git checkout main && git merge --squash autorun/<slug> && git commit` →
`bash scripts/autorun-rotate-artifacts.sh <slug>` to preserve forensic
state before cleanup.

## Recovering from a "no commit" fix-attempt failure

`fix-attempt` in `run.sh` can trigger on Medium/Low Codex findings, not
just High — the spec calls only High blocking, but the trigger grep is more
aggressive in practice. If it fails with no commit, the pipeline writes
`failure.md` and closes the PR without merging. `gh pr reopen` will fail in
this state. Recover with `git checkout main && git merge --squash
<autorun-branch> && git commit`, then push and fix any real findings as a
follow-up commit.
