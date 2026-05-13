# Integration — install-rewrite

**Persona:** integration
**Stage:** /plan (Design)
**Source spec:** `docs/specs/install-rewrite/spec.md` v1.1
**Source review:** `docs/specs/install-rewrite/review.md` (item #16: "additive surgery framing understates control-flow changes")

## Key Considerations

- Resolves review item #16 by **explicitly diagramming** the control-flow rewire — not just naming the new stages, but pinning where each one is cut into the live 354-line `install.sh` and which ordering invariants hold them in sequence.
- The script today is a single linear top-to-bottom flow with **one** prompt-driven exit at line 82-86 ("Continue anyway?"). The rewrite splits that single decline gate into two tier-aware decline gates and inserts six other new stages around the existing 354 lines without renumbering or reordering existing stages.
- Three hard ordering invariants emerge from the spec that a naive "insert at top" reading would violate:
  1. **Linux guard MUST run before any `brew` reference** (currently `has_cmd brew` does not exist; new code introduces it). Guard goes at line 3-4, before `set -euo pipefail` even matters for brew.
  2. **SIGINT trap MUST be installed before any `.tmp` file is written.** The spec puts atomic `.monsterflow.tmp` writes inside the new theme stage and inside any future stage that mutates user files. Trap install must precede the first such write.
  3. **Migration detect MUST run before any symlink mutation.** The "Detected prior install" message + opt-out prompt is meaningful only if the user can still cleanly bail before symlinks get rewritten. Detect goes between flag-parse and tier-detect, not after.
- The existing **"Continue anyway?" prompt at lines 81-88** is the largest semantic casualty. The new tier-aware decline behavior (REQUIRED hard-stop; RECOMMENDED loud-notice continue) **fully replaces** it. The single prompt does not survive in any path.
- `tests/run-tests.sh` registers tests by adding to the `TESTS=(…)` array at lines 22-28. The new `tests/test-install.sh` must be added there (likely first, since it is the slowest — but per the file's "cheapest first" comment, possibly last). One-line edit.
- `scripts/onboard.sh` exit code: spec says "non-blocking; printed at end" but doesn't pin behavior on non-zero exit. Recommendation below addresses this.
- `--non-interactive` propagation: env var beats argv for cross-script sharing. Recommendation below.
- The `python_pip` helper sourcing pattern is one line, sourced once near the top after Linux guard and trap install but before any pip invocation (currently install.sh has zero pip calls, so the source line is plumbing for future use, not yet load-bearing in install.sh itself).

## New vs Old Flow Diagram

Line numbers reference the **current** `install.sh` (354 lines). New stages are marked `[NEW]`; existing stages keep their current line ranges. The "→ insert here" arrows indicate the cut points.

```
┌──────────────────────────────────────────────────────────────────────────┐
│ install.sh — control flow (post-rewrite)                                 │
└──────────────────────────────────────────────────────────────────────────┘

  Line 1     #!/bin/bash
  Line 2     set -euo pipefail
             ↓
  [NEW] Stage 0: Linux guard
        Insert AFTER line 2, BEFORE line 4 (REPO_DIR computation).
        Rationale: must precede any brew lookup, any path computation that
        could fail oddly on Linux. exit 1 cleanly with macOS-only message.
             ↓
  Line 4-9   REPO_DIR / CLAUDE_DIR / VERSION computation                   [unchanged]
  Line 11-15 Banner echo                                                    [unchanged]
             ↓
  [NEW] Stage 1: Parse flags
        Insert AFTER line 15 (banner), BEFORE line 21 (has_cmd def).
        Variables set: NO_INSTALL, INSTALL_THEME, NO_THEME, NON_INTERACTIVE,
        NO_ONBOARD, FORCE_ONBOARD. Auto-set NON_INTERACTIVE=1 if [ ! -t 0 ].
        Flag-precedence resolved here: NO_THEME=1 zeroes INSTALL_THEME.
             ↓
  [NEW] Stage 2: SIGINT trap
        Insert immediately after Stage 1.
        Defines cleanup_partial(), then `trap cleanup_partial INT TERM`.
        Must precede the first .monsterflow.tmp write (Stage 9 theme).
             ↓
  [NEW] Source python_pip helper
        `. "$REPO_DIR/scripts/lib/python-pip.sh"` — single line, after trap.
        Forward-compat plumbing; install.sh has no pip calls yet.
             ↓
  [NEW] Stage 3: Migration detect
        Insert after python_pip source, BEFORE line 21 (has_cmd def).
        Reads $CLAUDE_DIR/commands/spec.md symlink target; if matches
        */MonsterFlow/* or */claude-workflow/*, prints upgrade message and
        (unless NON_INTERACTIVE) prompts "Proceed with upgrade? [Y/n]".
        Bail = exit 0 (clean), no mutations have happened yet.
             ↓
  Line 21-25 has_cmd() definition                                          [unchanged]
             ↓
  Line 27-32 Tier-bucket arrays declared                                   [unchanged]
             ↓
  Line 34-37 REQUIRED detection (git, claude, python3)                     [+1 line: brew]
        ONLY EDIT: add `has_cmd brew || REQUIRED_MISSING+=("brew (Homebrew) — install from https://brew.sh: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"")`
             ↓
  Line 39-47 Python version check                                          [unchanged]
             ↓
  Line 49-53 RECOMMENDED detection                                         [edit: drop tmux, add cmux]
        Drop: `has_cmd tmux || RECOMMENDED_MISSING+=(...)` (tmux → OPTIONAL)
        Add:  `has_cmd cmux || RECOMMENDED_MISSING+=("cmux ...")`
        Add:  `has_cmd tmux || OPTIONAL_MISSING+=(...)` in the OPTIONAL block (line 62)
             ↓
  Line 56-59 PATH sanity check                                             [unchanged]
             ↓
  Line 61-62 OPTIONAL detection (codex)                                    [+1 line: tmux moved here]
             ↓
  Line 64-79 Display tier-by-tier findings                                 [unchanged]
             ↓
  ┌─────────────────────────────────────────────────────────────────────┐
  │ DELETED: lines 81-88 ("Continue anyway?" single-prompt decline)     │
  │ Replaced wholesale by new Stage 5 + Stage 6 below.                  │
  └─────────────────────────────────────────────────────────────────────┘
             ↓
  [NEW] Stage 5: Install missing (brew bundle)
        Replaces deleted lines 81-88.
        Gate: skip entire stage if NO_INSTALL=1.
        Otherwise, if any tier is missing, prompt single confirm
          (auto-Y under NON_INTERACTIVE only if --force-install also set,
           else fall through to Stage 6 decline path).
        Run: `if ! brew bundle --file="$REPO_DIR/Brewfile" install; then …`
        Hardened guard catches non-zero before set -e kills script.
             ↓
  [NEW] Stage 6: Decline behavior
        Runs after Stage 5 regardless of whether install ran or was skipped.
        REQUIRED still missing AND NOT NO_INSTALL → exit 1 with install commands
        REQUIRED still missing AND NO_INSTALL    → stderr notice, continue
        RECOMMENDED still missing                 → loud notice (⚠, stderr,
                                                    single emit), continue, exit 0
                                                    from this stage
             ↓
  Line 91-100 link_file() definition                                       [unchanged]
             ↓
  Line 102-105 mkdir -p $CLAUDE_DIR/{commands,personas,templates}          [unchanged]
             ↓
  Line 107-127 Pipeline commands + persona-metrics prompts symlinks        [unchanged]
             ↓
  Line 129-159 Personas + domain agents symlinks                           [unchanged]
             ↓
  Line 161-166 Templates symlinks                                          [unchanged]
             ↓
  Line 168-171 Settings symlink                                            [unchanged]
             ↓
  Line 173-180 Scripts symlinks (note: scripts/onboard.sh will land here    [unchanged
              automatically — it lives under scripts/ so the existing       — pattern picks
              `for script in "$REPO_DIR"/scripts/*.sh` glob picks it up     it up free]
              with no install.sh edit)
             ↓
  Line 182-189 Autorun scripts symlinks                                    [unchanged]
             ↓
  Line 190-202 Owner detection (PWD == REPO_DIR)                           [REPLACED]
        Swap the body of these lines for the hardened detect_owner() from
        spec.md lines 354-371. Preserves the OWNER variable name so all
        downstream references (line 237, line 242) continue to work.
             ↓
  Line 204-230 queue/.gitignore writers (write_queue_gitignore, ADOPTER)   [unchanged]
             ↓
  Line 232-278 Persona-metrics gitignore default-flip                      [unchanged]
        Sentinel-bracketed pattern (BEGIN persona-metrics … END) is REUSED
        verbatim by the new theme stage's .zshrc append.
             ↓
  [NEW] Stage 9: Install theme
        Insert AFTER line 278 (end of persona-metrics block), BEFORE
        line 280 (CLAUDE.md baseline).
        Rationale: theme is a user-config concern; sits naturally after
        the other user-config concerns (gitignore blocks) and before the
        global ~/CLAUDE.md merge.
        Gate: skip entirely if NO_THEME=1.
        Owner: apply without prompt (link_file calls).
        Adopter: prompt-default-N unless INSTALL_THEME=1.
        Under NON_INTERACTIVE without INSTALL_THEME → silent skip.
        Targets: ~/.tmux.conf, ~/.config/cmux/cmux.json (link_file),
                 ~/.zshrc append (sentinel-bracketed, reusing line 244-275
                 pattern's grep -qF guard for idempotency).
             ↓
  Line 280-292 CLAUDE.md baseline merge                                    [unchanged]
        Note: existing read -rp prompt at line 284 must respect
        NON_INTERACTIVE — see Stage 1 propagation. Minimal edit: wrap the
        read -rp in `if [ "$NON_INTERACTIVE" = "0" ]; then … else … fi`.
             ↓
  Line 294-303 Git hooks (install-hooks.sh)                                [unchanged]
             ↓
  Line 305-316 Plugin install prompts                                      [edit: NON_INTERACTIVE skip]
        Both read -rp prompts (line 307, line 312) wrapped in
        `if [ "$NON_INTERACTIVE" = "0" ]; then … fi`. Under non-interactive,
        plugins are NOT installed (safe default — adopter can re-run).
             ↓
  Line 318-326 Test suite validation                                       [edit: NON_INTERACTIVE skip]
        Same pattern: wrap read -rp at line 321 in NON_INTERACTIVE check.
        Under non-interactive, default to NOT running tests (slow, noisy).
             ↓
  Line 328-354 "Installation complete" + Next steps echo                   [unchanged]
             ↓
  [NEW] Stage 14: Onboard
        Insert AFTER line 354 (last echo).
        Gate: skip if NO_ONBOARD=1, OR if NON_INTERACTIVE=1 without FORCE_ONBOARD.
        Otherwise: `bash "$REPO_DIR/scripts/onboard.sh" || true`
        The `|| true` makes onboard.sh non-blocking — see Recommendation §3.
             ↓
  EOF (exit 0 by virtue of falling off end with set -e and no failure)
```

## Options Explored

### Option A: Insert all new stages, leave existing line ranges intact

Cuts new stages in at the boundaries shown above; existing code keeps its line numbers shifted by the size of the inserts but its **function** is preserved verbatim. The deleted lines 81-88 ("Continue anyway?" prompt) are the only surgical removal.

- **Pros:** Minimal blast radius. Every existing code path stays exactly as the test suite + memory entries expect. Spec's "additive surgery" framing remains accurate. Easy to review the diff.
- **Cons:** install.sh grows from 354 lines to ~530 lines, edging toward the "if it grows past ~500 lines, extraction is a follow-up spec" threshold the spec itself names.
- **Effort:** Single PR, ~180 net new lines + 8 deleted + 3-line edits in three existing prompts.

### Option B: Extract new stages into `scripts/install/` helper modules sourced from install.sh

Same flow, but each new stage lives in its own `scripts/install/<stage>.sh` file sourced into install.sh's namespace.

- **Pros:** install.sh stays under 400 lines. Each new stage is independently testable.
- **Cons:** Spec **explicitly rejects this**: "Refactoring the existing 354 lines into helper modules (rejected — additive surgery only)". Premature factoring on top of a feature.
- **Effort:** Higher — adds 6-7 new files plus the stage logic.

### Option C: Split install.sh into install.sh (existing) + install-v2.sh (new flow), let adopter choose

A two-script world where v2 is the new flow and v1 is preserved for rollback.

- **Pros:** Trivial rollback. Both flows verifiable side-by-side.
- **Cons:** Doubles the maintenance surface. README + QUICKSTART would have to explain "which one to run." Migration messaging becomes awkward — v0.4.x detect logic now needs to know which install was used.
- **Effort:** Highest. Rejected.

## Recommendation

**Option A.** It is the only option the spec permits, and it is also the right call on its merits: the cuts are clean, the existing code is preserved verbatim, and the line-number-anchored diagram above gives `/build` a precise insertion map.

**Concrete integration plan (line-number cuts):**

1. **Insert Stage 0 (Linux guard)** between current line 2 and line 4. ~5 new lines.
2. **Insert Stage 1 (flag parse)** between current line 15 and line 21. ~25 new lines (one `case` block per flag, one TTY auto-detect line).
3. **Insert Stage 2 (SIGINT trap)** immediately after Stage 1. ~10 new lines.
4. **Insert `python_pip` source line** immediately after Stage 2. ~1 new line.
5. **Insert Stage 3 (migration detect)** after the source line, before current line 21. ~15 new lines.
6. **Edit current line 36** (REQUIRED detection): add `has_cmd brew || REQUIRED_MISSING+=(…)`. ~1 new line.
7. **Edit current lines 49-53** (RECOMMENDED detection): drop tmux line, add cmux line. ~0 net lines.
8. **Edit current line 62** (OPTIONAL detection): add tmux. ~1 new line.
9. **Delete current lines 81-88** ("Continue anyway?" prompt). −8 lines.
10. **Insert Stage 5 + Stage 6** at the deletion site. ~50 new lines (single confirm prompt + `if ! brew bundle …` + tier-aware decline branching).
11. **Replace current lines 190-202** (owner detection) with the hardened `detect_owner()` from spec.md lines 354-371. Net ~+15 lines.
12. **Insert Stage 9 (theme)** between current line 278 and line 280. ~50 new lines (link_file calls for two targets, sentinel-bracketed `.zshrc` append, owner-vs-adopter branching, NON_INTERACTIVE guard).
13. **Edit current line 284** (CLAUDE.md baseline `read -rp`): wrap in NON_INTERACTIVE guard. ~3 new lines.
14. **Edit current lines 307 and 312** (plugin install prompts): wrap each in NON_INTERACTIVE guard. ~6 new lines.
15. **Edit current line 321** (test suite prompt): wrap in NON_INTERACTIVE guard. ~3 new lines.
16. **Insert Stage 14 (onboard call)** after current line 354. ~5 new lines.

**Net delta:** +180 lines, −8 lines, ~12 lines edited. install.sh ends at ~530 lines.

**Existing prompt fate:**
- Line 82-86 "Continue anyway?" → **DELETED**, replaced by tier-aware decline.
- Line 284 "Copy baseline template?" → **PRESERVED** with NON_INTERACTIVE guard.
- Line 307 "Install required plugins now?" → **PRESERVED** with NON_INTERACTIVE guard.
- Line 312 "Also install recommended plugins?" → **PRESERVED** with NON_INTERACTIVE guard.
- Line 321 "Run test suite to validate install?" → **PRESERVED** with NON_INTERACTIVE guard.

**`tests/run-tests.sh` registration:**
Edit the `TESTS=(…)` array at lines 22-28 of `tests/run-tests.sh` to append `test-install.sh`. Per the file's "cheapest first" comment, append at the end (test-install.sh runs against a temp $HOME and is by far the slowest test):

```bash
TESTS=(
  test-hooks.sh
  test-agents.sh
  test-skills.sh
  test-bump-version.sh
  autorun-dryrun.sh
  test-install.sh    # NEW — slowest, runs last
)
```

The new test file must be `chmod +x` so the existing line 40 check (`if [ ! -x "$TESTS_DIR/$t" ]`) passes.

**onboard.sh exit-code propagation:**
Spec says "non-blocking; printed at end" but is silent on what install.sh does if onboard.sh exits non-zero. Recommendation: install.sh treats onboard.sh as **fully non-blocking** — wrap the call in `|| true` so any onboard failure cannot fail the install:

```bash
# Stage 14 invocation
if [ "$NO_ONBOARD" = "0" ] && { [ "$NON_INTERACTIVE" = "0" ] || [ "$FORCE_ONBOARD" = "1" ]; }; then
    bash "$REPO_DIR/scripts/onboard.sh" || {
        echo "" >&2
        echo "⚠ onboard.sh exited non-zero (non-fatal). Re-run anytime: bash scripts/onboard.sh" >&2
    }
fi
```

The `|| { … }` form preserves the exit code in stderr breadcrumbs without killing install.sh. Rationale: install completed successfully by the time we reach onboard; an onboard failure (gh not authed, network blip on graphify offer, etc.) shouldn't retroactively fail the install.

**`--non-interactive` propagation:**
Recommendation: **environment variable**, not argv. install.sh exports `MONSTERFLOW_NON_INTERACTIVE=$NON_INTERACTIVE` before calling `bash "$REPO_DIR/scripts/onboard.sh"` (and any other child script). Each child script reads `${MONSTERFLOW_NON_INTERACTIVE:-0}` at top-of-file and gates its own prompts.

Why env, not argv:
- Survives sub-script `bash` invocations without arg-forwarding gymnastics.
- Future sister scripts (doctor.sh, bootstrap-graphify.sh) get one consistent knob to honor.
- Consistent with existing `MONSTERFLOW_OWNER` env override pattern.

**Sister scripts that should also gain `--non-interactive` support:**
- `scripts/doctor.sh` — currently has no prompts (it's all probes), so the env var is read-only / no-op for now, but document it for future-proofing.
- `scripts/bootstrap-graphify.sh` — has a `read -r -p "Proceed with --apply across all targets?"` at line 138. Add: gate it on `${MONSTERFLOW_NON_INTERACTIVE:-0} = "0"`. Defer the actual edit if BOOTSTRAP isn't called from install.sh's onboard path (it isn't directly — it's called from onboard.sh's `offer_graphify_bootstrap` only on user opt-in, which itself is gated by TTY in spec.md line 282-284). **Net: small one-line edit to bootstrap-graphify.sh as a defensive measure; not strictly required for this spec but cheap.**
- `scripts/onboard.sh` — primary new consumer of the env var (gates `offer_graphify_bootstrap`, `offer_gh_auth`, panel print).
- `scripts/install-hooks.sh` — has zero prompts, no edit needed.

**`python_pip` helper sourcing pattern:**
Single line, placed **after** the SIGINT trap installation but **before** the migration-detect stage. Rationale: trap install is bash-builtin and doesn't need pip; migration detect could in principle want pip later if it grows; everything from there onward can rely on `python_pip` being available. Concretely:

```bash
# After Stage 2 trap install:
. "$REPO_DIR/scripts/lib/python-pip.sh"
```

install.sh has zero current pip calls, so this is forward-compat plumbing. The helper is non-invasive (defines two functions, runs no top-level code) so the source is safe even if unused this run.

**Documentation touchpoints:**
- **README.md** — install one-liner unchanged (`./install.sh`). Add a "Flags" subsection naming `--no-install`, `--no-theme`, `--non-interactive`, `--no-onboard`, `--force-onboard`, `--install-theme`. Reference QUICKSTART.md for migration messaging.
- **QUICKSTART.md** — add a "Upgrading from v0.4.x" subsection that previews the migration message; add a "Non-interactive / CI" subsection naming the env vars (`MONSTERFLOW_OWNER`, `MONSTERFLOW_NON_INTERACTIVE`) and the flag-only equivalents.
- **CHANGELOG.md** — create if absent (spec admits "Optional CHANGELOG.md — referenced by migration message; create if not present"). v0.5.0 entry must list at minimum the 5 bullets the migration message hardcodes (line 207-211 of spec.md). The migration message and CHANGELOG.md must stay in sync — recommend a simple grep test in `tests/test-install.sh` that asserts every bullet from the migration message appears as a substring in CHANGELOG.md.

## Constraints Identified

- **354-line baseline is institutional memory.** Two memory entries (`feedback_install_adopter_default_flip.md`, persona-metrics gitignore sentinel pattern) reference specific behaviors at specific line ranges. The diagram preserves both verbatim (line 195-197 owner-detect logic is replaced but the OWNER variable contract is preserved; lines 232-278 persona-metrics block is unchanged).
- **set -euo pipefail bites the new stages, not the old ones.** Existing code was written under set -e and is fine. New brew-bundle, theme-symlink, and migration-detect stages all need explicit `if !` guarding or `|| true` exit-handling. Diagrammed in Stage 5 (`if ! brew bundle …`) and Stage 14 (`|| { … }`).
- **`tests/run-tests.sh` is `set -uo pipefail` (no `-e`).** Per its line 15. test-install.sh failures will be counted by the runner via the exit code at line 49 (`bash "$TESTS_DIR/$t" || TEST_EXIT=$?`); no install.sh-side accommodation needed.
- **Symlink graph during testing.** test-install.sh runs against a temp `$HOME` (per spec acceptance-criteria preamble). It cannot use the existing `~/.claude` real symlink graph as a fixture. Must create the temp graph in test setup and tear it down. This is harness work, owned by /build, but the integration constraint is: **install.sh must not assume `$HOME == /Users/<real-user>`** anywhere — and currently it doesn't (all paths derive from `$HOME` directly), so this constraint holds.
- **Owner detection gets called from one site only.** Current line 194-197 sets `OWNER=...` once; downstream uses are at lines 237 (persona-metrics gitignore default-flip) and lines 242 (`-n "$ADOPTER_ROOT"` check). The new `detect_owner()` must preserve both contracts: `OWNER=1|0` semantics and `ADOPTER_ROOT` derivation. Diagrammed in §11 of recommendation.
- **plugin install prompts (lines 307, 312) become silent skips under non-interactive.** This is a behavior change — current behavior is "prompt always asks." Document explicitly: under `--non-interactive`, plugins are NOT installed; adopter must re-run install.sh interactively or run `claude plugins install …` themselves. Document in QUICKSTART CI section.
- **CLAUDE.md baseline merge prompt (line 284) becomes silent skip under non-interactive.** Same caveat. Adopter who runs `--non-interactive` and has no `~/CLAUDE.md` will not get one created. Acceptable — they can re-run interactively. Document in QUICKSTART.

## Open Questions

1. **Should `--force-install` exist as a companion to `--no-install`?** Spec defines `--no-install` (bypass all enforcement) and the auto-Y under non-interactive question is unsettled. Recommendation: do NOT add `--force-install`. Under non-interactive without `--no-install`, the right behavior is "REQUIRED missing → exit 1" (current spec edge-cases table line 403). If the user wants brew bundle to run automatically, they can pipe `Y\n` to install.sh's stdin or run interactively. Avoiding `--force-install` keeps the flag surface to 6.
2. **Should bootstrap-graphify.sh's `--apply` confirmation honor `MONSTERFLOW_NON_INTERACTIVE`?** Recommendation above says yes (defensive), but the touch is minimal and arguably out of scope for this spec. Either way works; flagging for /check.
3. **Migration detect's "alert + opt-out" prompt under `--non-interactive`.** Spec line 446-449 shows the prompt being skipped under non-interactive (just exits 0 if NON_INTERACTIVE=1 without confirm). But that means a non-interactive run on a v0.4.x machine **silently upgrades** without showing the diff. Recommendation: print the upgrade message to **stderr** even under non-interactive (so it lands in CI logs) but skip the confirm. Worth confirming.
4. **The Stage 14 onboard call's `|| true` masks legitimate onboard.sh syntax errors.** A future onboard.sh with a `set -e` violation would fail silently except for the stderr breadcrumb. Acceptable risk (onboard.sh is shellcheck-gated per spec acceptance bar) but flagging.

## Integration Points

- **with `tests/run-tests.sh`:** add `test-install.sh` to the TESTS array at lines 22-28; chmod +x the new test file. No other changes to the runner.
- **with `scripts/doctor.sh`:** invoked by `scripts/onboard.sh` (already exists, no install.sh edit). Future: read `MONSTERFLOW_NON_INTERACTIVE` to skip its (currently absent) prompts.
- **with `scripts/bootstrap-graphify.sh`:** invoked by `scripts/onboard.sh` on user opt-in (already exists). Recommend a one-line edit to gate its `read -r -p` at line 138 on `${MONSTERFLOW_NON_INTERACTIVE:-0} = "0"`.
- **with `scripts/install-hooks.sh`:** invoked unchanged by install.sh at line 302. No edit.
- **with `scripts/lib/python-pip.sh`:** sourced by install.sh after the SIGINT trap; helper-only, no top-level code runs at source time. Forward-compat plumbing.
- **with `scripts/onboard.sh` (NEW):** install.sh invokes it at end via `bash "$REPO_DIR/scripts/onboard.sh" || …`; `MONSTERFLOW_NON_INTERACTIVE` propagates via env. onboard.sh must read the env var at top-of-file and gate `offer_graphify_bootstrap`, `offer_gh_auth`, the codex one-liner, and the panel print accordingly.
- **with `tests/test-install.sh` (NEW):** runs against `mktemp -d` $HOME, mocks `has_cmd` via bash function-shadowing. Must NOT touch real `~/.claude` or `~/.tmux.conf`. Required to register in `tests/run-tests.sh` per above.
- **with `Brewfile` (already at repo root, commit 9c08163):** add `cask "cmux"`, remove `brew "tmux"` (per spec.md line 247-249). install.sh references it via `--file="$REPO_DIR/Brewfile"` in Stage 5.
- **with `config/` directory (NEW):** Stage 9 references `$REPO_DIR/config/cmux.json`, `$REPO_DIR/config/tmux.conf`, `$REPO_DIR/config/zsh-prompt-colors.zsh` as link_file sources. Pinning their contents is owned by the data persona, not integration; integration only constrains paths.
- **with `README.md`, `QUICKSTART.md`, `CHANGELOG.md`:** docs touchpoints per Recommendation §"Documentation touchpoints" above.
- **with `VERSION` file:** spec hardcodes v0.5.0 in the migration message (spec.md line 207). The auto-bump post-commit hook will produce v0.5.0 automatically when the install-rewrite commit lands as `feat:` (since current is v0.4.2, feat → minor → 0.5.0). If /build splits across multiple commits, only the LAST `feat:` will trigger the v0.5.0 bump; earlier commits in the chain bump intermediate versions which is fine.
- **with `~/.claude/commands/spec.md` symlink target inspection:** migration detect (Stage 3) reads this. Constraint: if a user manually replaced the symlink with a real file, migration detect won't fire. Documented behavior: detection requires the symlink to exist and target to match `*/MonsterFlow/*` or `*/claude-workflow/*`.
- **with the existing `set -euo pipefail` at line 2:** preserved verbatim. New stages use `if !` guarding (Stage 5 brew bundle) or `|| true` (Stage 14 onboard) to coexist with `-e`. No `set +e` toggle anywhere — keeps the safety net active throughout.
