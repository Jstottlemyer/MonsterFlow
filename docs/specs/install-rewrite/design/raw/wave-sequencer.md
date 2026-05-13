# Wave Sequencing — install-rewrite

## Key Considerations

The three-gate default (data → UI → tests) maps cleanly here, but with one nuance: the "data contract" for this spec is split across two repo surfaces — **on-disk content** (`config/` files, `Brewfile` deltas, `scripts/lib/python-pip.sh` — already partly shipped in commit 9c08163) and **flag/env contract** (the new `--no-install`, `--non-interactive`, `--no-theme`, `--install-theme`, `--no-onboard`, `--force-onboard`, `MONSTERFLOW_OWNER` surface that downstream code reads). Both must close in Wave 1 before any consumer (install.sh new stages, scripts/onboard.sh, tests/test-install.sh) can be implemented without churn.

Once the data contract closes, **install.sh stages and scripts/onboard.sh can be implemented in parallel** — they share the env/flag contract, not internals. Tests come last because they exercise the full surface; writing them earlier means rewriting them when contract gaps surface during behavior implementation.

The biggest sequencing trap to avoid: putting flag parsing in the same wave as the stages that consume the flags. If flag parsing slips ("we'll add `--non-interactive` later"), every consumer wave has to be revised. Flag parsing belongs in Wave 1 (the contract), even if its only callers are Wave 2 stages.

The second trap: implementing the install.sh new stages (Wave 2) and writing tests against them (Wave 4) in the same commit. Tests against not-yet-final behavior create churn — defer to Wave 4 once behavior closes in Wave 2/3.

Codex's "additive surgery understates the control-flow changes" caveat from review affects sequencing inside Wave 2: the eight new stages must land in stage-order (0 → 1 → 2 → 3 → 5 → 6 → 9 → 14, per spec line 82-98), not in any-order. A SIGINT trap added after the install stage is structurally wrong; flag parsing added after the migration-detect stage means the migration stage can't honor `--non-interactive`. Wave 2 is sequential within itself.

## Wave Breakdown

### Wave 1 — Data + Flag Contract
- **Closes:** every file/state/flag downstream code reads from. After this wave, anyone implementing Wave 2/3 can do so by reading the contract, not Wave 1's code.
- **Includes:**
  1. `Brewfile` edit — add `cask "cmux"`, remove `brew "tmux"` (one commit).
  2. `config/cmux.json` — neutral cmux defaults; `$HOME`-relative; verified path `~/.config/cmux/cmux.json` per cmux docs (one commit).
  3. `config/tmux.conf` — high-contrast cyan/grey theme; `$HOME`-relative paths only; no Justin-machine specifics (one commit).
  4. `config/zsh-prompt-colors.zsh` — sourceable file; theme-only (no behavioral changes); safe under `set -u` (one commit).
  5. `install.sh` — flag parsing block + `MONSTERFLOW_OWNER` env override + `NON_INTERACTIVE` auto-detect via `[ -t 0 ]`. **No stage logic yet** — this commit just establishes the variables every later stage reads. Default values resolved; `--no-theme` precedence over `--install-theme` enforced. (one commit)
  6. `install.sh` — source `scripts/lib/python-pip.sh` near the top (one-line addition; helper already shipped). (one commit)
- **Depends on:** none — first wave.
- **Verifier signal:** `bash -n install.sh` parses cleanly after each commit; `shellcheck install.sh` returns 0; `./install.sh --help` (or equivalent) prints the new flag surface; `config/` files pass `shellcheck` / `jq .` where applicable.
- **Minimum-shippable test:** Wave 1 alone is independently useful — adopters who clone get the new Brewfile + config files even before stages are wired. Owner can `source config/zsh-prompt-colors.zsh` manually.
- **Parallelizable within wave?** Yes — items 1-4 are independent files; item 5 only touches the top of install.sh; item 6 is a one-liner. Can land as 6 commits in any order, or one commit per file authored by parallel sub-agents.
- **Risk:** **low**. No behavioral coupling; reviewable in isolation.

### Wave 2 — install.sh Stages (sequential within)
- **Closes:** the full install.sh control flow described in spec lines 82-98. After this wave, the script does what the spec says; consumers can rely on stage ordering.
- **Includes (in stage-order — must land in this sequence; each is one commit):**
  1. **Stage 0 — Linux guard** at top of file (`[ "$(uname)" = Darwin ]` else exit 1). Lands first because it short-circuits everything else.
  2. **Stage 2 — SIGINT/TERM trap** (`cleanup_partial`) — lands before any tmp-file write so any subsequent stage's tmp writes are protected.
  3. **Stage 3 — Migration detect** — read `[ -L $CLAUDE_DIR/commands/spec.md ]`, print upgrade message + 5-line diff; gated on `NON_INTERACTIVE` for the `read -rp`. Hardcodes "v0.5.0" per Open Q3.
  4. **Stage 4 extension — add `brew` to REQUIRED tier**. One-line addition to the existing `has_cmd` loop.
  5. **Stage 8 owner-detect hardening** — replace `PWD == REPO_DIR` block (lines 190-202) with `detect_owner()` (realpath + `git rev-parse --show-toplevel` + `MONSTERFLOW_OWNER` env override). Pure refactor; existing tests should still pass.
  6. **Stage 5 — Install missing** — `if ! brew bundle --file="$REPO_DIR/Brewfile" install; then handle_failure; fi`. Honors `--no-install` (skip entirely) and `--non-interactive` (auto-Y or skip per flag-state). Single confirm prompt for interactive runs.
  7. **Stage 6 — Decline behavior** — REQUIRED-missing hard-stop OR `--no-install` bypass-all; RECOMMENDED-missing loud-notice continue (glyph `⚠`, stderr, single emit, exit 0).
  8. **Stage 9 — Theme stage** — owner-no-prompt vs adopter-prompt-default-N; `--no-theme` wins; uses existing `link_file()` for backup-on-conflict; `.zshrc` append uses sentinel-bracketed pattern (`# BEGIN MonsterFlow theme` / `# END MonsterFlow theme`) for idempotency.
  9. **Stage 14 — Onboard call** — `bash scripts/onboard.sh`, suppressed under `--no-onboard` or `NON_INTERACTIVE` without `--force-onboard`. Lands LAST in install.sh because it's the tail.
- **Depends on:** Wave 1 (flag/env contract; config/ files for theme stage to symlink to; Brewfile for install stage to read).
- **Verifier signal:** after each commit, `bash -n install.sh` parses; `shellcheck install.sh` returns 0; manual smoke run on owner machine completes without error. After commit 9, the full flow is observable: owner re-run prints expected stages, exit 0.
- **Minimum-shippable test:** after commit 6 (install + decline), Wave 2 is shippable as "install stage works"; commit 8 (theme) is shippable as "theme works"; commit 9 (onboard call) is the full close.
- **Parallelizable within wave?** **No — strict sequential ordering.** Each commit modifies install.sh; even if conflicts could be resolved, the control-flow review is much harder if stages land out-of-order. Branch off Wave 1 once; serialize commits 1-9.
- **Risk:** **high**. This wave has the most surface area, the most opportunity for `set -euo pipefail` foot-guns (commit 6 needs the explicit `if !` guard), and the most opportunity for stage-ordering bugs Codex flagged. Recommend: each commit in this wave gets the **autorun-shell-reviewer** subagent before merge (see CLAUDE.md — its 13-pitfall checklist applies directly: PIPESTATUS index, branch invariant, SIGINT race, slug regex, eval scope all relevant here).

### Wave 3 — scripts/onboard.sh
- **Closes:** the onboarding panel surface (assertable substrings `/flow`, `/spec`, `dashboard/index.html`); doctor invocation; opt-in graphify/gh prompts gated on TTY + detection.
- **Includes:** one commit creates `scripts/onboard.sh` end-to-end (~80 lines per spec). Reads `NON_INTERACTIVE` and `FORCE_ONBOARD` env vars set by install.sh. Re-runnable standalone. Uses `[ -t 0 ]` for TTY check on its own opt-in prompts. Wiki indexing intentionally absent.
- **Depends on:** Wave 1 (env-var contract — `NON_INTERACTIVE`, `FORCE_ONBOARD`, `MONSTERFLOW_OWNER` exported by install.sh). Does NOT depend on Wave 2 commit-by-commit — only on the env-var contract closing in Wave 1. **Therefore Wave 3 can run in parallel with Wave 2.**
- **Verifier signal:** `shellcheck scripts/onboard.sh` returns 0; `bash scripts/onboard.sh` runs clean from owner machine; output contains literal `/flow`, `/spec`, `dashboard/index.html` (`grep` assertion).
- **Minimum-shippable test:** Wave 3 is independently runnable — `bash ~/Projects/MonsterFlow/scripts/onboard.sh` ships value even if Wave 2's stage-14 wiring is deferred.
- **Parallelizable within wave?** Single commit; no internal parallelism.
- **Parallelizable with other waves?** **Yes — runs parallel to Wave 2** once Wave 1 lands. Different file, no shared state.
- **Risk:** **low-medium**. Failure mode is panel-text drift breaking test 7's grep, or an opt-in prompt firing in `--non-interactive` mode (Codex's stdin-collision pitfall — verify all `read -rp` calls are gated on `[ -t 0 ] && [ "$NON_INTERACTIVE" != 1 ]`).

### Wave 4 — tests/test-install.sh
- **Closes:** the 9 acceptance cases from spec lines 503-532, plus shellcheck-clean + onboard-substring assertions. Validates Wave 2 + Wave 3 behavior.
- **Includes (split into ≤3 commits to keep each reviewable):**
  1. Test harness skeleton: `mktemp -d` temp `$HOME`, function-shadowing helpers (`_mock_has_cmd_fail()`, `_mock_brew_recorder()`), case-runner with halt-on-fail + last-20-lines dump on failure. Cases 1, 2, 3 (idempotency, fast no-op, REQUIRED hard-stop). One commit.
  2. Cases 3a, 4, 5, 6a-d (happy path, re-install, `--no-install` bypass-all, theme owner/adopter/flag/backup matrix). One commit.
  3. Cases 7, 8, 9a-c (TTY-gated indexing, migration messaging, non-interactive matrix) + shellcheck pass + onboard-substring assertion. One commit.
- **Depends on:** Wave 2 complete (all stages); Wave 3 complete (onboard.sh exists). Tests against frozen behavior, not in-flight behavior.
- **Verifier signal:** `bash tests/test-install.sh` exits 0 with "9/9 PASS"; `bash tests/run-tests.sh` (the existing master suite) picks up the new harness and stays green.
- **Minimum-shippable test:** Wave 4 commit 1 alone gives 3 acceptance cases — that's a real safety net. Commits 2/3 can defer if needed.
- **Parallelizable within wave?** Yes — the 3 commits can be authored by parallel sub-agents (each owns its case set), then sequenced for landing. Within a commit, cases are independent.
- **Risk:** **medium**. The mock strategy (function-shadowing `has_cmd`) is pinned by the spec, but the brew-binary stub for case 3a needs a stub-binary on a temp PATH (or another function shadow) — easy to get wrong and false-pass. **Recommendation:** test 3a should assert against an argv-recording sentinel file written by the stub, not against stdout — stdout is too easy to game.

### Wave 5 — Documentation
- **Closes:** docs parity: README install one-liner still works; QUICKSTART describes new flag surface + migration; CHANGELOG has v0.5.0 entry.
- **Includes (one commit):**
  - `README.md` — verify install one-liner still works; add brief "what install.sh does now" paragraph.
  - `QUICKSTART.md` — document new flags (`--no-install`, `--no-theme`, `--install-theme`, `--non-interactive`, `--no-onboard`, `--force-onboard`) and `MONSTERFLOW_OWNER` env override.
  - `CHANGELOG.md` — create if missing; add v0.5.0 entry matching the migration message's 5-bullet diff (lines 207-213 of spec). **The CHANGELOG bullets and the migration message bullets MUST match verbatim** — the migration message points adopters at CHANGELOG for full detail.
- **Depends on:** Wave 2 + Wave 3 (so the documented behavior is real). Not strictly dependent on Wave 4, but easier to write after Wave 4 confirms behavior matches docs.
- **Verifier signal:** docs render cleanly; CHANGELOG bullets match migration message bullets verbatim (a `diff` between the two should produce only formatting deltas).
- **Minimum-shippable test:** docs ship as one commit; reviewable in isolation.
- **Parallelizable within wave?** Single commit; no internal parallelism. Three files but they're all docs.
- **Risk:** **low**. Failure mode is bullet drift between CHANGELOG and migration message — fixed by sourcing both from one canonical 5-line text fragment in `docs/specs/install-rewrite/v0.5.0-changes.txt` (consider; out-of-scope micro-decision for /build).

## Three-Gate Mapping (data → UI → tests)

- **Data gate (Wave 1):** Brewfile, `config/*`, flag/env contract, `python_pip` source line. Everything downstream code reads from. Closes the contract so Wave 2 + Wave 3 can be planned and implemented against documented inputs, not Wave 1 source code.
- **UI gate (Wave 2 + Wave 3, parallel):** install.sh's new stages + scripts/onboard.sh. The "user-visible surface" — what an adopter sees and what their disk state becomes. Wave 5 (docs) is technically the user-visible explanation surface and lives at the tail of UI.
- **Tests gate (Wave 4):** acceptance harness covering all 9 cases. Hardens the now-final behavior. Adding tests in Wave 2/3 would force rewrites every commit.

Wave 5 (docs) is a hybrid: explanatory UI for the same behavior Wave 2+3 closes. Sequenced after Wave 2+3 because docs against in-flight behavior drift; sequenced before or alongside Wave 4 because tests don't gate docs.

## Recommendation

The full ordered task list, suitable for `/build`:

```
WAVE 1 — Data + Flag Contract  (parallel-safe within; ~6 commits)
  T1.1  Brewfile: add cask "cmux", remove brew "tmux"
  T1.2  config/cmux.json (neutral defaults, $HOME-relative)
  T1.3  config/tmux.conf (cyan/grey theme, $HOME-relative)
  T1.4  config/zsh-prompt-colors.zsh (theme-only, set -u safe)
  T1.5  install.sh: flag parsing + MONSTERFLOW_OWNER + NON_INTERACTIVE auto-detect
        (top-of-file block; no stage logic; sets variables only)
  T1.6  install.sh: source scripts/lib/python-pip.sh

  GATE: shellcheck install.sh → 0; jq config/cmux.json → 0;
        ./install.sh --help shows new flags

WAVE 2 — install.sh Stages  (STRICTLY SEQUENTIAL within; 9 commits)
  T2.1  Stage 0: Linux guard (top of file)
  T2.2  Stage 2: SIGINT/TERM trap (cleanup_partial)
  T2.3  Stage 3: Migration detect + upgrade message
  T2.4  Stage 4 extension: add brew to REQUIRED tier
  T2.5  Stage 8: hardened detect_owner() replaces PWD-based block
  T2.6  Stage 5: brew bundle install with `if !` guard
  T2.7  Stage 6: tier-split decline behavior + loud notice
  T2.8  Stage 9: theme stage (link_file reuse + .zshrc sentinel append)
  T2.9  Stage 14: onboard call (suppressed under --no-onboard / NON_INTERACTIVE)

  GATE per commit: shellcheck → 0; manual smoke run on owner machine
  GATE wave-end: invoke autorun-shell-reviewer subagent on cumulative diff

WAVE 3 — scripts/onboard.sh  (parallel with Wave 2 once Wave 1 lands)
  T3.1  scripts/onboard.sh end-to-end (doctor call, panel, opt-in prompts)

  GATE: shellcheck → 0; bash scripts/onboard.sh prints panel; grep -c "/flow" → 1

WAVE 4 — tests/test-install.sh  (parallel-safe within; 3 commits)
  T4.1  Harness skeleton + cases 1, 2, 3
  T4.2  Cases 3a, 4, 5, 6a-d
  T4.3  Cases 7, 8, 9a-c + shellcheck assertion + onboard substring

  GATE: bash tests/test-install.sh → "9/9 PASS"; bash tests/run-tests.sh stays green

WAVE 5 — Documentation  (one commit)
  T5.1  README + QUICKSTART + CHANGELOG (v0.5.0 entry matching migration text)

  GATE: bullets in CHANGELOG match install.sh's migration message verbatim
```

**Critical-path serialization:** `Wave 1 → (Wave 2 || Wave 3) → Wave 4 → Wave 5`. Wave 2 and Wave 3 can run in parallel branches off Wave 1; both must merge before Wave 4 starts.

**Smallest atomic commits:** every numbered task above is one commit. The two task counts that may compress: T1.1 + T1.6 could land together as "infrastructure prep" (both one-liners); T5.1 stays as one doc commit (three files but one logical change).

## Constraints Identified

- **Stage ordering inside install.sh is non-negotiable.** SIGINT trap must precede any tmp write; flag parsing must precede any stage that consumes flags; Linux guard must be first. Wave 2's commit order matches spec lines 82-98 exactly.
- **`set -euo pipefail` is retained.** Every new stage that runs a subcommand whose non-zero exit must NOT kill the script needs an explicit `if ! cmd; then handle; fi` guard. Codex flagged this for `brew bundle`; the same pattern applies to `gh auth status`, `python_pip`, and `bash scripts/doctor.sh` calls inside onboard.sh (already gated with `|| true`).
- **CHANGELOG bullets must match migration message bullets verbatim.** If Wave 5 drifts from Wave 2's migration text, adopters who click through CHANGELOG see a different story than the installer told them. Mitigation: write the 5-line diff once and reference it in both places (or accept the drift risk and add a Wave 4 test that asserts the match).
- **`autorun-shell-reviewer` subagent should review Wave 2 cumulative diff before merge** per repo CLAUDE.md ("invoke before committing changes that touch `scripts/autorun/*.sh`" — install.sh isn't autorun, but the 13-pitfall checklist applies cleanly to any large bash diff with SIGINT traps + flag parsing + sentinel writes).
- **Owner-detect refactor (T2.5) is a pure refactor with no observable behavior change** when running from a fresh clone at the repo root. Wave 4's existing test coverage of owner-vs-adopter behavior must stay green across this commit. Treat it as a no-behavior-change commit and verify with diff-of-test-output.

## Open Questions

1. **Should the `python_pip` source line (T1.6) actually land in Wave 1?** It's a one-line addition with no current consumer in install.sh — every existing pip call in install.sh (`python3 "$REPO_DIR/scripts/claude-md-merge.py"` is python3 not pip) doesn't invoke pip. If install.sh genuinely doesn't invoke pip today, T1.6 is a no-op in Wave 1 and can move to whichever wave first introduces a pip call (none, in this spec). **Recommend: drop T1.6 entirely from this spec's plan unless `/plan`'s api/data-model persona surfaces a consumer.** Sister-script migration is explicitly out-of-scope per spec line 71.

2. **Does Wave 2 need to ship behind a feature flag during rollout?** The spec assumes a single PR / merge. For owner self-dogfood that's fine. If adopter rollout is staged, Wave 2 should ship into a `--experimental-install` flag first and graduate. Spec doesn't address; recommend asking at /check time.

3. **Does the wave-1 `config/` content need a one-shot review by Justin** before /build emits the files? The spec names the three files but pins zero bytes of content. Open Q2 in the spec acknowledges this. Recommend: /plan's `ux` or `security` persona drafts the three files; Justin reviews; /build commits unchanged. If skipped, Wave 1 ships placeholder content and Wave 5 doc commit also has to be revised.

## Integration Points

- **with integration persona:** confirm the `python_pip` source line (T1.6) actually has a consumer in this spec's surface — if not, drop. Confirm `scripts/install-hooks.sh` invocation (line 302 of install.sh) doesn't need to move relative to the new stages; it currently lands between stage 9 (theme) and stage 14 (onboard) per spec ordering, which seems right but confirm with integration's full-flow diagram.
- **with api persona:** confirm the env-var contract (`NON_INTERACTIVE`, `FORCE_ONBOARD`, `MONSTERFLOW_OWNER`, `PERSONA_METRICS_GITIGNORE`) is documented as a stable surface. If Wave 3's onboard.sh reads these, they're a public contract — document in QUICKSTART (T5.1).
- **with data-model persona:** the sentinel-bracketed `.zshrc` block (T2.8) and the `~/.local/share/MonsterFlow/.last-graphify-run` sentinel file (mentioned in spec line 480) are persistent state — confirm naming, location, and lifecycle. If these change during /build, adopters get duplicate blocks or stale opt-in re-prompts.
- **with ux persona:** confirm panel text (Wave 3) — the box-drawing characters degrade on legacy terminals (spec acknowledges); also confirm the loud-notice format (single-line stderr, `⚠`, no repeat) reads acceptably in CI logs that strip colors.
- **with scalability persona:** non-applicable for this spec (no perf/concurrency surface beyond "under 3s on owner re-run" which Wave 4 case 2 already asserts).
- **with security persona:** confirm `config/*` files contain zero network calls and only `$HOME`-relative paths. T1.2/T1.3/T1.4 each need a security pass before commit; the spec asserts "every byte is auditable before it lands on the adopter's disk" — that's a /check gate, but flagging here so /plan's security persona owns it.
- **with all other personas:** **Wave 1 must close before any other persona's work can be implemented.** If a downstream persona (api, ux, data-model) surfaces a contract gap during /plan, it goes back into Wave 1 — not deferred to Wave 2. The wave-sequencer's job is to keep schema/contract additions out of behavior waves; surface any such mid-stream gap loudly.
