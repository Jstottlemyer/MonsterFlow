# API Design — install-rewrite

**Persona:** api (CLI/flag/exit-code surface)
**Spec:** docs/specs/install-rewrite/spec.md (v1.1)
**Scope:** Pin the public CLI surface for `install.sh`, `scripts/onboard.sh`, and the `python_pip` helper so `/build` has zero ambiguity about argv parsing, env vars, exit codes, and flag precedence.

## Key Considerations

- **One installer, two callers:** humans (interactive TTY) and CI/agents (`--non-interactive`, no TTY). Every flag must collapse to a sane default in both modes — no flag may *require* TTY to make sense.
- **Flag precedence is load-bearing.** Spec already pins `--no-theme` wins over `--install-theme`; we must extend that contract to every flag pair that can co-occur, including `--no-install` interactions with everything else.
- **Discoverability:** `install.sh --help` must list every flag with its default and its precedence rule. Today there is no `--help`. Adding one is in-scope for this spec (it's part of the new flag surface).
- **Idempotent re-runs are an existing behavior we must preserve.** New flags must not break the "run twice, same disk state" property documented in Acceptance case 1.
- **Exit codes are the public API for autorun/CI.** `0`/`1`/`130` is a small, conventional surface — no new exit codes invented unless a test case demands one.
- **Env vars are the override layer.** Use them for "I am the owner / I am CI / I want metrics committed" — three knobs, namespaced under `MONSTERFLOW_*` so they never collide with brew/claude/git env.
- **`python_pip` helper is already shipped and battle-tested.** Validate the contract; do not re-design it.
- **Onboard.sh inherits installer state via env vars, not argv.** The installer invokes onboard.sh as the last step; onboard must also run standalone (`bash scripts/onboard.sh`) and reach the same code paths. Env-var inheritance is the cleanest seam.
- **No flag should silently change owner-vs-adopter detection.** That detection drives privacy-sensitive defaults (persona-metrics gitignore, theme prompt). Conflating it with `--non-interactive` would re-open the public-repo data leak class of bug.

## Options Explored

### Option A: Flag-only surface (no env vars beyond what already exists)

All knobs are CLI flags. Owner detection stays purely path-based (`realpath`-of-script vs `git rev-parse --show-toplevel`).

- Pros: single surface to document; `--help` is the complete contract; no env-var/flag precedence puzzles.
- Cons: agent-driven runs (`bash install.sh` from inside an `autorun` worktree) can't override owner detection without forging git state; CI escape requires remembering a flag combo every time; `MONSTERFLOW_OWNER` was already named in the spec as the fix for owner-detect fragility.
- Effort: low. Rejected because it doesn't satisfy the spec's hardened-owner-detect requirement.

### Option B: Flag + env hybrid (RECOMMENDED)

Flags for per-run intent (`--no-install`, `--no-theme`, …); env vars for cross-run / agent-context overrides (`MONSTERFLOW_OWNER`, `PERSONA_METRICS_GITIGNORE` — already exists). `--non-interactive` is *both* a flag and an auto-detect (`[ -t 0 ]`); other flags are flag-only. Onboard.sh inherits installer intent via env vars (`MONSTERFLOW_NON_INTERACTIVE`, `MONSTERFLOW_FORCE_ONBOARD`) so it works standalone or as a sub-process.

- Pros: matches the spec's stated surface 1:1; preserves the existing `PERSONA_METRICS_GITIGNORE` env contract; gives agents a way to set owner without faking git; one sentence per env var in `--help`.
- Cons: precedence rules must be documented (env vs flag); two-surface API has a slightly higher learning cost.
- Effort: low (the spec already named all the pieces). Strongly recommended.

### Option C: Subcommand surface (`install.sh detect | install | theme | onboard`)

Decompose the monolithic flow into named subcommands; flags become per-subcommand.

- Pros: better discoverability; each phase independently testable from the CLI; matches modern tooling (`brew`, `git`, `claude`).
- Cons: massive surface change; breaks the documented one-liner (`./install.sh`); spec explicitly calls for **additive surgery**, not API redesign; would re-litigate the README/QUICKSTART contract; out of scope.
- Effort: high. Rejected.

### Option D: `--help` only, no new flags (rely on env vars)

Make every new knob env-only (`MONSTERFLOW_NO_INSTALL=1`, `MONSTERFLOW_NO_THEME=1`, …).

- Pros: zero argv parsing complexity; CI users `export` once and forget.
- Cons: poor discoverability (env vars don't show in `--help` on most tools); humans expect flags; spec already enumerates the flag surface in §Flag surface table — pivoting now would invalidate the test plan and the v0.4.x→v0.5.0 migration message that hardcodes `--no-install`, `--no-theme`, `--non-interactive` as the headline new flags.
- Effort: low. Rejected on UX grounds + spec churn.

## Recommendation

**Option B — flag + env hybrid.** Pinned surface below.

### `install.sh` flag surface

| Flag | Default | Wins-over | Effect |
|------|---------|-----------|--------|
| `--help` / `-h` | n/a | (terminates) | Print flag table + env var table + exit 0. NEW. |
| `--no-install` | off | (orthogonal) | Bypass ALL detection enforcement: REQUIRED-missing does NOT hard-stop, brew bundle is skipped entirely, symlinks still run. CI escape hatch. |
| `--install-theme` | off | (loses to `--no-theme`) | Force theme install ON regardless of owner-vs-adopter default. |
| `--no-theme` | off | beats `--install-theme` | Force theme install OFF regardless of default. |
| `--non-interactive` | auto | (orthogonal) | Disable every `read -rp`. Auto-set when `[ -t 0 ]` is false. Explicit flag wins (you can force non-interactive even on a TTY). |
| `--no-onboard` | off | beats `--force-onboard` | Suppress `scripts/onboard.sh` invocation. |
| `--force-onboard` | off | loses to `--no-onboard` | Run onboard panel even under `--non-interactive`. |

### `install.sh` env vars

| Env Var | Default | Effect |
|---------|---------|--------|
| `MONSTERFLOW_OWNER` | unset | If `=1`, force owner mode (skip path-based detection). If `=0`, force adopter mode. Any other value: ignored. |
| `PERSONA_METRICS_GITIGNORE` | owner→0, adopter→1 | EXISTING. `=1` adds gitignore block; `=0` commits metrics. Unchanged contract. |
| `MONSTERFLOW_NON_INTERACTIVE` | 0 | Internal — set by install.sh before invoking onboard.sh. Adopters should use the `--non-interactive` flag instead. |
| `MONSTERFLOW_FORCE_ONBOARD` | 0 | Internal — set by install.sh before invoking onboard.sh when `--force-onboard` was passed. |
| `MONSTERFLOW_SKIP_DOCTOR` | 0 | Internal escape used by tests to skip `doctor.sh` invocation in onboard.sh (keeps test runtime predictable). NOT a documented adopter flag. |

### Argv parsing rules

1. Parse flags **first**, before Linux guard, before SIGINT trap, before any `mkdir`/`echo`. Reason: `--help` must work on Linux too (don't trip the OS guard for a docs query); SIGINT trap is irrelevant if we're going to exit-0 from `--help` immediately.
2. Single pass, `while [ $# -gt 0 ]; do case "$1" in … esac; shift; done`. No long-option clustering, no `--flag=value` syntax (none of our flags take values).
3. Unknown flag → exit 2 with `install.sh: unknown flag '$1'. Run install.sh --help for the flag list.` (exit 2 distinguishes "user error" from exit 1 "REQUIRED missing".)
4. After argv parsing, resolve `--non-interactive` auto-detection: if flag not passed AND `[ -t 0 ]` is false, set `NON_INTERACTIVE=1`.
5. Resolve theme intent: `if [ "$NO_THEME" = 1 ]; then THEME_INSTALL=0; elif [ "$INSTALL_THEME" = 1 ]; then THEME_INSTALL=1; else THEME_INSTALL=$([ "$OWNER" = 1 ] && echo 1 || echo 0); fi`. Adopter prompt-default-N is then conditional on `THEME_INSTALL=0 && NON_INTERACTIVE=0` → ask; otherwise apply directly.
6. Resolve onboard intent: `if [ "$NO_ONBOARD" = 1 ]; then RUN_ONBOARD=0; elif [ "$FORCE_ONBOARD" = 1 ]; then RUN_ONBOARD=1; elif [ "$NON_INTERACTIVE" = 1 ]; then RUN_ONBOARD=0; else RUN_ONBOARD=1; fi`.

### `install.sh` exit codes

| Code | Meaning | Contract |
|------|---------|----------|
| 0 | Success — install completed, OR `--no-install` bypass succeeded, OR `--help` printed. | RECOMMENDED-missing exits 0 (loud notice IS the signal). Migration-decline (`n` to upgrade prompt) also exits 0. |
| 1 | REQUIRED tool missing AND `--no-install` not passed AND user did not opt to install. Also: `brew bundle install` failed. Also: Linux guard tripped. | Stable contract — autorun/CI parses on this. |
| 2 | Argv parse error (unknown flag). | NEW. Conventional shell exit code for "user error in CLI usage." |
| 130 | SIGINT/SIGTERM trapped — `cleanup_partial` ran, `.monsterflow.tmp` files removed. | Conventional `128 + signal` for SIGINT. |

No other exit codes. `brew bundle` failures, `claude plugins install` failures, `tests/run-tests.sh` failures all funnel through 1.

### `scripts/onboard.sh` CLI

**Argv:** none. Onboard takes no positional args, no flags.

**Env vars consumed:**

| Env Var | Default | Effect |
|---------|---------|--------|
| `MONSTERFLOW_NON_INTERACTIVE` | 0 | If `=1`, suppress all `read -rp` prompts (graphify offer, gh auth offer). Panel still prints. |
| `MONSTERFLOW_FORCE_ONBOARD` | 0 | Currently a no-op inside onboard (it's how install.sh decided to *invoke* onboard, not a behavior switch *inside* onboard). Reserved for future "force re-offer everything" semantics. |
| `MONSTERFLOW_SKIP_DOCTOR` | 0 | If `=1`, skip the `bash scripts/doctor.sh` call. Test-only knob. |
| `HOME` | (real) | Tests override to a `mktemp -d` path so onboard never touches the dev machine. |

**Exit codes:**

| Code | Meaning |
|------|---------|
| 0 | Panel printed; whether sub-prompts were declined or non-interactive-skipped is irrelevant. Doctor failures are non-fatal (`|| true`). |
| 130 | SIGINT during a `read -rp` (graphify offer, gh auth offer). Same trap as install.sh. |

**Re-run contract:** `bash ~/Projects/MonsterFlow/scripts/onboard.sh` works standalone with no env setup. TTY auto-detect (`[ -t 0 ]`) handles non-interactive case if `MONSTERFLOW_NON_INTERACTIVE` not set.

### `python_pip` helper API (validated, no changes)

The shipped helper at `scripts/lib/python-pip.sh` already has the right contract:

```bash
. "$REPO_DIR/scripts/lib/python-pip.sh"

python_pip --which                       # prints resolved path: "/opt/homebrew/bin/pip3" or "python3 -m pip"
python_pip install --user some-package   # forwards args to resolved pip; returns its exit code
python_pip install -r requirements.txt   # same
```

**Resolution order** (already pinned in helper source): `pip3` → `pip` → `python3 -m pip` → exit 127 with brew install hint.

**Contract checks for /build:**

1. Sourcing `python-pip.sh` must NOT execute anything (it only defines functions). Verify: `bash -c '. scripts/lib/python-pip.sh; type python_pip'` exits 0 with no output before `type`.
2. `python_pip --which` must be safe to capture in `$()` (no stderr noise on the happy path).
3. `python_pip` returns the wrapped pip's exit code unchanged. Tests that mock pip-failure must assert on that propagation.
4. install.sh sources the helper; sister scripts (`bootstrap-graphify.sh`, `compute-persona-value.py`'s shell wrappers) are explicitly OUT OF SCOPE per spec — they continue calling `pip3` directly. This is a **non-migration**: helper exists, install.sh uses it, sisters keep working as-is.

### `--help` text (pinned for /build)

```
install.sh — MonsterFlow installer (v0.5.0)

Usage: install.sh [flags]

Flags:
  --help, -h           Print this help and exit.
  --no-install         Bypass ALL tool detection + enforcement. Symlinks still
                       run. REQUIRED-missing does NOT hard-stop. CI escape hatch.
  --install-theme      Force shell theme install ON (overrides default).
  --no-theme           Force shell theme install OFF. Wins over --install-theme.
  --non-interactive    Disable every prompt; pick safe defaults. Auto-enabled
                       when stdin is not a TTY.
  --no-onboard         Skip the post-install onboard panel.
  --force-onboard      Run onboard panel even under --non-interactive.

Env vars:
  MONSTERFLOW_OWNER=1            Force owner mode (skip path-based detection).
  MONSTERFLOW_OWNER=0            Force adopter mode.
  PERSONA_METRICS_GITIGNORE=1    Gitignore persona-metrics artifacts (adopter
                                 default). Set =0 to commit them.

Exit codes:
  0   Success (or --help, or --no-install bypass, or RECOMMENDED-missing).
  1   REQUIRED tool missing, brew bundle failed, or Linux guard tripped.
  2   Unknown flag (argv parse error).
  130 Interrupted (SIGINT/SIGTERM); partial state cleaned up.

See docs/specs/install-rewrite/spec.md and CHANGELOG.md for v0.5.0 details.
```

### Public flag matrix (test harness reference)

The 9-case test harness in `tests/test-install.sh` iterates this matrix. Each row is one acceptance case from spec §Acceptance Criteria; the matrix below pins the exact argv/env each test must use.

| # | Case (spec) | Argv | Env overrides | Expected exit |
|---|-------------|------|---------------|---------------|
| 1 | Idempotency repeat | `` (twice) | tools-present mocks | 0, 0 |
| 2 | Fast no-op | `` | tools-present mocks, all symlinks pre-staged | 0 |
| 3 | Fresh-Mac REQUIRED hard-stop | `` | all-tools-missing mocks | 1 |
| 3a | Fresh-Mac happy path | `` (with `Y\n` on stdin) | brew/claude/git/python3 present, RECOMMENDED missing | 0 |
| 4 | Re-install after `brew uninstall jq` | `` (with `Y\n` on stdin) | jq missing, others present, symlinks pre-staged | 0 |
| 5 | `--no-install` bypass-all | `--no-install` | all tools missing | 0 |
| 6a | Theme owner no-prompt | `` | `MONSTERFLOW_OWNER=1` | 0 |
| 6b | Theme adopter prompt-N | `` (with `\n` on stdin) | `MONSTERFLOW_OWNER=0` | 0 |
| 6c | Theme adopter --install-theme | `--install-theme` | `MONSTERFLOW_OWNER=0` | 0 |
| 6d | Existing real file backup | `--install-theme` | `MONSTERFLOW_OWNER=0`, pre-stage `~/.tmux.conf` as real file | 0 |
| 7a | Onboard with TTY | (via `script -q /dev/null`) | `~/Projects/test-proj/some.py` pre-staged | 0 |
| 7b | Onboard non-interactive | `--non-interactive --force-onboard` | same pre-staging | 0 |
| 8 | v0.4.x → v0.5.0 migration | `--non-interactive` | `~/.claude/commands/spec.md` symlinked to `*/MonsterFlow/*` | 0 |
| 9a | TTY-absent auto-detect | `</dev/null` (no TTY on stdin) | tools-present | 0 |
| 9b | --non-interactive with TTY | `--non-interactive` | tools-present | 0 |
| 9c | Non-interactive + force-onboard | `--non-interactive --force-onboard` | tools-present | 0 |

**Negative cases (NEW — recommend adding to harness):**

| # | Case | Argv | Expected exit | Stderr substring |
|---|------|------|---------------|------------------|
| N1 | Unknown flag | `--garbage` | 2 | `unknown flag` |
| N2 | Linux guard | `` (with `uname` shadowed to print `Linux`) | 1 | `macOS-only` |
| N3 | brew bundle failure | `` (brew shadowed to exit 1, `Y\n` on stdin) | 1 | `brew bundle failed` |

The N1–N3 cases are NOT in the spec's 9-case list but are required to lock the exit-code contract. Recommend `/build` adds them to `tests/test-install.sh` at low cost.

## Constraints Identified

- **`--help` cannot reuse the existing CLAUDE.md merge `argparse`-style.** Bash, not Python. Plain `case` switch + heredoc is the only sane implementation.
- **Argv parse must precede `set -euo pipefail`'s reach over OS detection.** If we put the Linux guard *before* argv parse, `install.sh --help` fails on Linux. Order: shebang → `set -euo pipefail` → argv parse → `--help` short-circuit → Linux guard → SIGINT trap → everything else.
- **Env-var inheritance into onboard.sh requires explicit `export`** (or per-call `MONSTERFLOW_NON_INTERACTIVE=1 bash scripts/onboard.sh`). Per-call form is cleaner — no env pollution into the user's shell after install.sh exits.
- **`MONSTERFLOW_OWNER` ambiguity:** spec said "=1 overrides." We extend to "=0 forces adopter" because tests need to force adopter mode without `cd`-ing out of the repo. Documented in `--help`.
- **`PERSONA_METRICS_GITIGNORE` precedence with `MONSTERFLOW_OWNER`:** owner-detect runs first, then `PERSONA_METRICS_GITIGNORE` defaults from owner state, then explicit env var (if set) wins. This is the existing contract — no change.
- **`--non-interactive` does NOT imply `--no-theme` or `--no-onboard`.** A CI user who wants the theme installed must pass `--non-interactive --install-theme` together. Documented.
- **`--no-install` does NOT skip the test-suite prompt at end of install.sh.** That prompt is gated by `--non-interactive` (silent skip) or `--no-onboard` semantics? No — test-suite is its own prompt. Recommend: `--no-install` + `--non-interactive` together silences it. `--no-install` alone does not. (Open question O1 below.)
- **Migration prompt under `--non-interactive`:** auto-proceed (no prompt). Spec already pins this: `[ "$NON_INTERACTIVE" = "0" ] && read -rp …`.

## Open Questions

1. **Test-suite prompt under `--no-install` alone.** Spec doesn't pin whether `./install.sh --no-install` should still ask "Run test suite to validate install? [Y/n]". Recommendation: yes, it should — `--no-install` is about brew enforcement, not about skipping post-install verification. Adopters who want fully silent behavior pass `--non-interactive` too. Confirm at /build.
2. **`--help` flag aliases.** I pinned `--help` and `-h`. Should we also accept `help` (bare word, no dashes) the way `git` does? Recommend: no — keeps the parser simple, matches `brew --help` / `claude --help` conventions.
3. **Exit code for `brew bundle install` partial-failure.** Spec pins exit 1 for total failure. What about "3 of 4 formulas installed, jq failed"? `brew bundle` returns non-zero on any failure; we propagate as exit 1. Confirm this matches CI expectations (most CI prefers fail-loud over partial-success).
4. **Should `--no-install` print the detection results at all?** Spec says "print detection results to stdout for log." Confirm format: same tier-by-tier output as today (✗ REQUIRED / ⚠ RECOMMENDED / ○ OPTIONAL), just no enforcement after the print. Recommendation: yes, identical format — gives logs the same shape regardless of bypass.
5. **`MONSTERFLOW_OWNER=0` use case.** I added it for test ergonomics, but if `/build` finds tests can force adopter mode purely by `cd /tmp/notrepo && bash $REPO/install.sh`, we can drop `=0` and keep only `=1` (matching the spec verbatim). Decide at /build based on test harness shape.

## Integration Points

- **with data-model:** Flag-derived state (`NO_INSTALL`, `INSTALL_THEME`, `NO_THEME`, `NON_INTERACTIVE`, `NO_ONBOARD`, `FORCE_ONBOARD`, `OWNER`, `THEME_INSTALL`, `RUN_ONBOARD`) becomes the in-memory state record install.sh threads through stages. data-model persona must pin variable names + scope (all unset-or-`0`/`1`, no tri-state, no string sentinels). The `MONSTERFLOW_*` env-var namespace is the cross-process state surface — data-model owns the schema, this persona owns the spelling.

- **with ux:** Flag *naming* and `--help` *wording* are this persona's call; flag *prompting copy* (the actual `read -rp` strings, the panel text, the loud-notice glyph) is ux's call. Boundary: I pin `--no-theme` as the flag spelling; ux pins "Install MonsterFlow shell theme? [y/N]:" as the prompt string. Both must agree on the assertable substrings (`/flow`, `/spec`, `dashboard/index.html`) — those live in ux's panel design.

- **with security:** `MONSTERFLOW_OWNER=1` is a privilege-escalation switch (it flips persona-metrics gitignore default to 0 = commit metrics). security must validate that the env-var override is documented as adopter-readable (so an adopter can't accidentally commit prose) and that `--help` calls it out. Also: argv parsing must NOT eval any flag values (no `eval`, no unquoted `$@` expansion in `case` patterns) — a hostile alias around install.sh shouldn't be able to inject. Memory-backed precedent: `feedback_install_adopter_default_flip.md` already burned us once on adopter-vs-owner default flips; security must re-check the new flag matrix doesn't re-open that class of bug.

- **with testing (downstream of /build):** The flag matrix above IS the test plan. test-install.sh must iterate it; any new flag added later requires a new row. The N1–N3 negative cases extend the spec's 9-case list — recommend adopting them but flag as a `/build`-time decision since they're additive to the spec.

- **with docs (README/QUICKSTART/CHANGELOG):** README's one-liner (`./install.sh`) stays unchanged — zero-flag invocation is the happy path. QUICKSTART must gain a "non-interactive install" section quoting the `--non-interactive --no-theme --no-onboard` triple as the canonical CI recipe. CHANGELOG v0.5.0 entry must list every new flag + the `MONSTERFLOW_OWNER` env var; the migration message in install.sh ALREADY hardcodes `--no-install`, `--no-theme`, `--non-interactive` as the v0.5.0 headline — keep the wording in sync.
