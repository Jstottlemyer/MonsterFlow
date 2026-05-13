# `install-rewrite` Implementation Plan

**Created:** 2026-05-04
**Revised:** 2026-05-04 (v1.1 — 10 blockers + 7 should-fix from /check addressed)
**Spec:** `docs/specs/install-rewrite/spec.md` v1.1 (sha256 `f7cb4706…`)
**Design agents:** 7 (api, data-model, ux, scalability, security, integration, wave-sequencer)
**Constitution:** none — defaults-only roster

## Architecture Summary

Install.sh becomes an **opinionated, idempotent, owner-vs-adopter-aware installer** via additive surgery on the existing 354-line script. Net delta: **+200 / −12 lines, ~16 edited; ends at ~542 lines.** The single deletion is the existing "Continue anyway?" prompt (lines 82-88) — fully replaced by tier-aware decline. Owner detection is *augmented* (not replaced): the existing `PWD == REPO_DIR` check is preserved as the primary signal; the new `script_dir == git_root` check is a secondary confirmation, and `MONSTERFLOW_OWNER=1` is an explicit override (B2 fix — preserves the defensive-by-default semantics).

**Three ordering invariants** hold across all waves:

1. **Linux guard** runs after flag-parse + `--help` short-circuit but before any path computation, banner print, or repo I/O (B5 fix)
2. **SIGINT trap** is installed before the first `.monsterflow.tmp` write (Stage 9 theme is the first such writer)
3. **Migration detect** runs before any symlink mutation, so opt-out cleanly bails

**Critical-path waves:** `W1 → (W2 || W3) → W4 → W5`. W2 has 11 task entries (2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 2.9b, 2.10) but ships as **10 commits** (2.9 + 2.9b squash since they're both prompt-wrapping edits to nearby line ranges). W3 (onboard.sh) authors in parallel once W1 closes.

## Revisions (v1.1, post-check)

10 blockers + 7 should-fix surfaced by /check resolved inline:

- **B1** D11 mock strategy swapped to PATH-stub model (validated empirically against bash 3.2.57)
- **B2** D4 owner-detect now AUGMENTS the existing `PWD == REPO_DIR` check; does not replace it
- **B3** D8 reframed as "ADD brew-bundle install stage from scratch" (not "wrap")
- **B4** D6 single-quote escaping for `.zshrc` source path (POSIX, parses under both bash and zsh)
- **B5** D1 flag-parse-before-Linux-guard requires moving REPO_DIR/VERSION/banner BELOW the parse+guard block; `--help` short-circuits before any I/O
- **B6** New W2 task 2.9b: wrap line 305-316 + line 318-326 behind `MONSTERFLOW_INSTALL_TEST=1`
- **B7** W4 task 4.1 ship criterion expanded with brew-stub state-lifecycle spec
- **B8** W4 case 7a swapped to `expect`-based TTY simulation; case 7b unchanged
- **B9** W2 ship criterion subagent-gate threshold + invocation pinned (Justin manually pre-merge; High blocks; 3+ Highs splits the wave)
- **B10** New R11 supply-chain risk + new W4 task 4.7: `tests/test-config-content.sh` CI grep gate

Should-fix tweaks: S1 brew transitive-deps preview added to W2-2.6; S3 W2 commit count corrected to 10; S4 `/bin/bash` shebang pinned for tests; S5 macOS ≥14 sw_vers check added next to Linux guard; S6 `MONSTERFLOW_FORCE_INTERACTIVE=1` env var added; S7 `link_file()` `.bak` bumps to `.bak.YYYYMMDDHHMMSS`; O1 task 1.6 placement comment fixed; O2 `shellcheck tests/test-install.sh` added to W4 ship criterion.

## Design Decisions

### D1 — Flag surface (7 flags) + early-exit `--help`

`--help`/`-h`, `--no-install`, `--install-theme`, `--no-theme` (wins over `--install-theme`), `--non-interactive` (auto-detect via `[ -t 0 ]`, override via `MONSTERFLOW_FORCE_INTERACTIVE=1`), `--no-onboard`, `--force-onboard`.

**Top-of-file restructure required (B5 fix):** install.sh's current order (REPO_DIR → VERSION → banner → ...) must move so the new top reads:

```bash
#!/bin/bash
set -euo pipefail

# Block 0: function definitions (no execution yet — bash needs these
# defined before they're called below)
parse_flags() { … }   # parses argv into env vars; unknown flag → exit 2
print_help()  { … }   # writes to stdout, zero env beyond $0, exits 0
# (other helpers used by Block 1-3 also defined here)

# Block 1: Flag parse (no I/O yet)
parse_flags "$@"
[ "$SHOW_HELP" = "1" ] && { print_help; exit 0; }   # B5: short-circuit before any I/O

# Block 2: OS guards (no repo I/O yet)
[ "$(uname)" = "Darwin" ] || { echo "MonsterFlow install.sh is macOS-only." >&2; exit 1; }
MACOS_VER="$(sw_vers -productVersion 2>/dev/null || echo 0)"
# macOS ≥14 enforced HERE (not at brew-bundle stage) — see W2 task 2.1 + R14;
# if MACOS_VER < 14, downgrade `cmux` from RECOMMENDED to OPTIONAL via env var
# CMUX_DEMOTE=1 that the tier-detection block at line ~50 honors.

# Block 3: Now safe to compute repo paths + banner
REPO_DIR="$(cd "$(dirname "$0")" && pwd -P)"   # Codex re-pass: pwd -P resolves symlinks
CLAUDE_DIR="$HOME/.claude"
VERSION="$(cat "$REPO_DIR/VERSION" 2>/dev/null | tr -d '[:space:]' || echo 'unknown')"
print_banner "$VERSION"
```

The "definitions-only first" block exists because bash requires function definitions to precede calls; combined with the no-I/O-before-help requirement, all helpers used in Block 1-3 must live above Block 1.

### D2 — Exit code matrix

| Code | Meaning |
|------|---------|
| 0 | Success / `--no-install` bypass / `--help` / RECOMMENDED-only-missing-and-declined |
| 1 | REQUIRED-missing (no `--no-install`), Linux guard, brew-bundle failure |
| 2 | Unknown flag — distinguishes user-error from REQUIRED-missing |
| 130 | SIGINT cleanup |

`tests/test-install.sh` negative cases N1 (unknown flag → exit 2), N2 (Linux guard → exit 1, mocked via `uname` function-shadow on macOS), N3 (brew-fail → exit 1) lock the contract.

### D3 — Env var contract

| Env var | Set by | Read by | Effect |
|---------|--------|---------|--------|
| `MONSTERFLOW_OWNER` | user | install.sh | `=1` force owner; `=0` force adopter (test ergonomics) |
| `MONSTERFLOW_NON_INTERACTIVE` | install.sh flag-parse | install.sh + onboard.sh | suppress all prompts |
| `MONSTERFLOW_FORCE_INTERACTIVE` | tests / explicit | install.sh | overrides `[ -t 0 ]` auto-detect (S6 fix — tests can pipe stdin without flipping non-interactive) |
| `MONSTERFLOW_FORCE_ONBOARD` | install.sh flag-parse | onboard.sh | run panel even under non-interactive |
| `MONSTERFLOW_INSTALL_TEST` | tests/test-install.sh | install.sh | short-circuit plugin-install + test-suite-validate prompts (B6 — line 305-316 AND line 318-326; second site critical to prevent fork-bomb) |
| `HOMEBREW_NO_AUTO_UPDATE=1` | install.sh top | brew | non-negotiable for the `<3s` repeat-run budget |
| `PERSONA_METRICS_GITIGNORE` | (existing) | (existing) | unchanged |

### D4 — Owner detection (AUGMENTED, not replaced — B2 fix; symlink-resolved per Codex re-pass)

REPO_DIR is now computed via `pwd -P` (D1 Block 3) so the primary `PWD == REPO_DIR` check resolves symlinks consistently with the secondary `script_dir == git_root` check. Test fixture: case 6e covers symlinked-repo-path invocation.


```bash
detect_owner() {
    # Explicit override wins
    if [ "${MONSTERFLOW_OWNER:-}" = "1" ]; then echo 1; return; fi
    if [ "${MONSTERFLOW_OWNER:-}" = "0" ]; then echo 0; return; fi

    # Primary: PWD == REPO_DIR (preserves existing defensive semantics —
    # running install.sh from any other cwd flips to ADOPTER, hiding
    # owner-only behavior. This is the dogfood-pattern signal.)
    if [ "$PWD" != "$REPO_DIR" ]; then echo 0; return; fi

    # Secondary: confirm script_dir resolves to git toplevel (catches
    # the case where someone symlinked the repo somewhere weird and
    # PWD coincidentally matches REPO_DIR by string but the script
    # actually lives elsewhere)
    local script_dir git_root
    script_dir="$(cd "$(dirname "$0")" && pwd -P)"
    git_root="$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || true)"
    [ -n "$git_root" ] && [ "$script_dir" = "$git_root" ] && echo 1 || echo 0
}
OWNER="$(detect_owner)"
```

**Why both checks:** the spec-review rejection of "naive realpath replacement" was correct; the spec-review-revision recommended hybrid (env override + auto-detect). v1.0 plan misimplemented the auto-detect by replacing instead of confirming. v1.1 plan: env override → PWD primary → `script_dir == git_root` confirms.

`ADOPTER_ROOT` continues to use the existing `-d "$PWD/.git"` check; widening that is out of scope for this spec (separate concern, doesn't block).

### D5 — `config/` file contents (unchanged from v1.0)

- `config/cmux.json` — 3-key minimal: `app.appearance: system`, `sidebar.branchLayout: vertical`, `notifications.sound: default`. Path: `~/.config/cmux/cmux.json`.
- `config/tmux.conf` — `Ctrl-a` prefix, 256-color cyan/grey palette, `~/.tmux.local.conf` adopter override hook. All paths `$HOME`-relative.
- `config/zsh-prompt-colors.zsh` — 5 env-overridable color vars, minimal `_monsterflow_git_branch` helper, two-line prompt. Pure theme, no behavior.

### D6 — `.zshrc` sentinel block (B4 fix — POSIX single-quote escaping)

The helper returns a fully-quoted string (including the surrounding `'…'`); the template uses it bare (no extra quotes). Codex re-pass caught a double-quoting bug in v1.1's first cut; corrected:

```bash
# Helper: returns the path wrapped in POSIX-safe single quotes,
# with embedded singles escaped as '\''
posix_quote() {
    local s="$1"
    printf "'%s'" "${s//\'/\'\\\'\'}"
}
ZSHRC_PATH="$(posix_quote "$REPO_DIR/config/zsh-prompt-colors.zsh")"
# ZSHRC_PATH already contains the outer quotes — do NOT add more.

# Sentinel block written into ~/.zshrc:
cat >> ~/.zshrc <<EOF

# BEGIN MonsterFlow theme
[ -f $ZSHRC_PATH ] && source $ZSHRC_PATH
# END MonsterFlow theme
EOF
```

POSIX-portable; parses identically under bash and zsh.

### D7 — SIGINT cleanup (`mktemp -d` scoped scratch — unchanged)

```bash
INSTALL_SCRATCH="$(mktemp -d -t monsterflow-install)"
cleanup_partial() {
    rm -rf "$INSTALL_SCRATCH"
    echo "" >&2
    echo "⚠ install.sh interrupted; partial state cleaned up." >&2
    echo "  Re-run when ready." >&2
    exit 130
}
trap cleanup_partial INT TERM
```

All atomic writes use `$INSTALL_SCRATCH/<name>.tmp` then `mv -f` to final.

### D8 — NEW brew-bundle install stage (B3 fix — not "wrap", "add from scratch")

install.sh has zero brew-bundle calls today. Stage 5 is entirely new code. Sub-tasks:

```bash
do_install_missing() {
    [ "$NO_INSTALL" = "1" ] && { echo "Skipped install per --no-install."; return; }
    [ "$ALL_RECOMMENDED_PRESENT" = "1" ] && return  # nothing to do

    # S1: preview transitive deps before confirm — derive tool list from Brewfile
    # (Codex re-pass: don't hardcode `gh shellcheck jq`; misses cmux + future Brewfile changes)
    echo "About to install via Homebrew (uses Brewfile at repo root):"
    awk '/^brew "/||/^cask "/{print "  -",$0}' "$REPO_DIR/Brewfile"
    echo ""
    echo "Resolved transitive set:"
    BREW_FORMULAS=$(awk -F'"' '/^brew "/{print $2}' "$REPO_DIR/Brewfile")
    BREW_CASKS=$(awk -F'"' '/^cask "/{print $2}' "$REPO_DIR/Brewfile")
    [ -n "$BREW_FORMULAS" ] && brew deps --include-build --formula $BREW_FORMULAS 2>/dev/null | sed 's/^/    /' | head -30 || true
    [ -n "$BREW_CASKS" ] && for c in $BREW_CASKS; do brew deps --cask "$c" 2>/dev/null | sed "s/^/    [cask:$c] /"; done || true
    echo ""

    if [ "$NON_INTERACTIVE" = "0" ]; then
        read -rp "Proceed? [Y/n]: " CONFIRM
        [[ "$CONFIRM" =~ ^[Nn]$ ]] && return
    fi

    if ! HOMEBREW_NO_AUTO_UPDATE=1 brew bundle --file="$REPO_DIR/Brewfile" install; then
        echo "⚠ brew bundle failed for some formulas." >&2
        echo "  Common causes: network, broken bottle, locked Cellar." >&2
        echo "  Fix and re-run install.sh. Symlinks were skipped." >&2
        exit 1
    fi

    # Post-install re-detection: confirm install actually fixed the missing tools.
    # `re_detect_tools` re-runs the same has_cmd loop from line ~30 and rebuilds
    # the REQUIRED_MISSING / RECOMMENDED_MISSING / OPTIONAL_MISSING arrays.
    # Codex re-pass: array-emptiness check uses ${#arr[@]} -eq 0, not the
    # ${arr[@]:-} = "" idiom which is unreliable under set -u with bash 3.2.
    re_detect_tools
    if [ "${#REQUIRED_MISSING[@]}" -ne 0 ]; then
        echo "✗ Post-install: REQUIRED still missing. Aborting." >&2
        exit 1
    fi
}
```

The catch pattern uses `if !` so `set -euo pipefail` doesn't kill the script before the failure handler runs. Post-install re-detection guards against brew "succeeding" without actually installing what we needed.

### D9 — `gh auth status` timeout (unchanged — bash trap-alarm 5s)

### D10 — Migration banner version from VERSION file (unchanged)

### D11 — Test harness PATH-stub model (B1 fix — replaces function-shadow)

Function-shadow (`export -f has_cmd`) is empirically broken on macOS bash 3.2 because install.sh redefines `has_cmd()` at line 21, shadowing any exported version. **Swap to PATH-stub:**

```bash
# tests/test-install.sh setup
setup_test() {
    BATS_TMPDIR="$(mktemp -d -t monsterflow-test)"
    STUB_DIR="$BATS_TMPDIR/stubs"
    STUB_LOG="$BATS_TMPDIR/stub.log"
    STUB_STATE="$BATS_TMPDIR/state"
    mkdir -p "$STUB_DIR"

    # Generate per-tool stubs that record argv + return chosen exit
    make_stub() {
        local name="$1" exit_code="${2:-0}"
        cat > "$STUB_DIR/$name" <<STUB
#!/bin/bash
echo "[\$\$] $name \$@" >> "$STUB_LOG"
exit $exit_code
STUB
        chmod +x "$STUB_DIR/$name"
    }

    # Reset state between cases
    rm -rf "$STUB_STATE"
    : > "$STUB_LOG"

    # Override has_cmd's hardcoded brew paths via test-only env hook
    export MONSTERFLOW_HASCMD_OVERRIDE="$STUB_DIR"

    # PATH-prepend stubs + pin /bin/bash for fidelity
    export PATH="$STUB_DIR:$PATH"
    export BASH=/bin/bash
}
```

`install.sh` `has_cmd()` gets one new line (W2 task 2.4 expansion):

```bash
has_cmd() {
    if [ -n "${MONSTERFLOW_HASCMD_OVERRIDE:-}" ]; then
        [ -x "$MONSTERFLOW_HASCMD_OVERRIDE/$1" ] && return 0 || return 1
    fi
    command -v "$1" >/dev/null 2>&1 \
        || [ -x "/opt/homebrew/bin/$1" ] \
        || [ -x "/usr/local/bin/$1" ]
}
```

In production `MONSTERFLOW_HASCMD_OVERRIDE` is unset → `has_cmd` behaves exactly as today. In tests, prefixing PATH + setting the override gives full deterministic mock control.

### D12 — UX exact strings (unchanged)

All prompts, panels, error messages frozen by ux agent in `plan/raw/ux.md`.

## Implementation Tasks

### Wave 1 — Data + Flag Contract (parallel-safe, low risk)

| # | Task | Files | Depends On | Size | Parallel? | Notes |
|---|------|-------|------------|------|-----------|-------|
| 1.1 | Brewfile cmux/tmux swap | `Brewfile` | — | S | yes | Add `cask "cmux"`, remove `brew "tmux"` |
| 1.2 | Write `config/cmux.json` | new | — | S | yes | 3-key minimal per D5 |
| 1.3 | Write `config/tmux.conf` | new | — | S | yes | Ctrl-a + cyan/grey 256-color per D5 |
| 1.4 | Write `config/zsh-prompt-colors.zsh` | new | — | S | yes | 5 vars + helper per D5 |
| 1.5 | Add flag-parse + early-exit `--help` + env contract block to install.sh top (per D1 restructure) | `install.sh` (top) | — | M | no | Restructured top-of-file: parse → help → guards → repo paths → banner |
| 1.6 | Source `python_pip` helper in install.sh (forward-compat) | `install.sh` | 1.5 | S | no | Lands in W1 between flag-parse and OS-guard sections (O1 fix — comment corrected) |

**Ship criterion:** `bash -n install.sh` passes after 1.5 + 1.6; flag table in install.sh source matches D1; `install.sh --help` exits 0 with no I/O beyond stdout.

### Wave 2 — install.sh Stages (10 commits, strictly sequential, high risk)

| # | Task | install.sh location | Depends On | Size | Risk |
|---|------|---------------------|------------|------|------|
| 2.1 | Linux guard + macOS ≥14 (S5) check (Stage 0) | after 1.5 flag-parse | 1.5 | S | low |
| 2.2 | SIGINT trap + `INSTALL_SCRATCH` mktemp (Stage 2) | after 2.1, before any tmp write | 2.1 | S | medium |
| 2.3 | Migration detect (Stage 3) | after 2.2, before symlink stages | 2.2 | M | medium |
| 2.4 | Brew → REQUIRED tier + `MONSTERFLOW_HASCMD_OVERRIDE` hook in `has_cmd` (Stage 4 + D11) | line 21 area | 1.5 | S | low |
| 2.5 | Hardened (augmented) owner detection (D4 — replaces 190-202) | replaces existing block | 1.5 | M | medium |
| 2.6 | NEW brew-bundle install stage with transitive-deps preview + post-install re-detection (Stage 5, B3 + S1) | new code, after detection panel | 2.4 | L | high |
| 2.7 | Tier-split decline behavior (Stage 6, REPLACES lines 82-86) | replaces "Continue anyway?" prompt | 2.6 | M | high |
| 2.8 | Theme stage with `link_file()` reuse + `.bak.YYYYMMDDHHMMSS` (S7) (Stage 9) | after persona-metrics block | 2.7 | M | medium |
| 2.9 | Wrap existing prompts (lines 284, 307, 312, 321) in `NON_INTERACTIVE` guard | targeted edits | 1.5 | S | low |
| 2.9b | **NEW (B6):** wrap line 305-316 plugin-install AND line 318-326 test-suite-validate behind `MONSTERFLOW_INSTALL_TEST=1` short-circuit | targeted edits | 2.9 | S | low |
| 2.10 | Onboard call (Stage 14, last) | after test-suite-validate | 2.9b | S | low |

**Ship criterion:** `shellcheck install.sh` returns 0; manual smoke `MONSTERFLOW_OWNER=1 ./install.sh` runs cleanly.

**Subagent gate (B9 fix):** Justin invokes `autorun-shell-reviewer` against the cumulative W2 diff before merge (NOT auto-invoked by /build agent — per CLAUDE.md the subagent is on-demand only). **Pass threshold:** High = block, Medium = document and resolve next session, Low = ignore. **If 3+ Highs:** split W2 into two PRs at the 2.6 boundary.

### Wave 3 — `scripts/onboard.sh` (parallel to W2 once W1 closes)

(Unchanged from v1.0; tasks 3.1-3.5)

### Wave 4 — `tests/test-install.sh` (medium risk)

| # | Task | Files | Depends On | Size |
|---|------|-------|------------|------|
| 4.1 | Test harness skeleton with PATH-stub model + brew-stub state lifecycle (B1 + B7) | new | W2 + W3 | L |
| 4.2 | Cases 1, 2, 3, 3a, 4 | inside 4.1 | 4.1 | M |
| 4.3 | Cases 5, 6 a/b/c/d (incl. case 6e: already-symlink no-op branch) | inside 4.1 | 4.1 | M |
| 4.4 | Cases 7a (via `expect`, B8 fix), 7b, 8, 9 a/b/c | inside 4.1 | 4.1 | M |
| 4.5 | Negative N1, N2 (Linux guard via PATH-stub `uname` returning "Linux" — same model as brew stub; Codex re-pass: function-shadow doesn't survive bash subshell), N3 | inside 4.1 | 4.1 | S |
| 4.6 | Register in `tests/run-tests.sh` TESTS array | `tests/run-tests.sh` | 4.5 | S |
| 4.7 | **NEW (B10):** `tests/test-config-content.sh` — grep config/* for `curl|wget|nc|bash <(|eval`, fail on any match | new | 4.6 | S |

**4.1 ship criterion (B7 expansion):** Brew stub binary at `$BATS_TMPDIR/stubs/brew` writes argv to `$STUB_LOG`, reads/writes state from `$STUB_STATE` (toggleable: case 4 sets `STUB_STATE=jq:missing` initially, then `STUB_STATE=jq:installed` after the simulated `brew bundle install`). Stateful brew-stub body lives at `tests/fixtures/stubs/brew.sh.template`; `make_stub` substitutes `$STUB_STATE` path at setup time. Stub state reset between cases via `setup_test()`. Pinned `BASH=/bin/bash` for bash-3.2 fidelity (S4). `expect` script for case 7a TTY simulation lives at `tests/fixtures/expect/onboard-tty.exp`.

**Wave-level ship criterion:** `bash tests/run-tests.sh` exits 0 on owner-machine; runtime <30s local, <60s CI; **`shellcheck tests/test-install.sh` returns 0** (O2 fix); 12 + 3 cases + new test-config-content green.

### Wave 5 — Docs (low risk)

(Unchanged from v1.0; CHANGELOG direction tracked as S2 — pick at PR-write time, either direction acceptable.)

## Three-Gate Mapping (data → UI → tests)

- **Data gate (W1):** Brewfile, `config/`, flag-parse + env contract, `python_pip` source line.
- **UI gate (W2 + W3):** install.sh stages + onboard.sh. Honors W1's flag/env contract.
- **Tests gate (W4):** `tests/test-install.sh` + new `tests/test-config-content.sh`.

## Open Questions

1. **CHANGELOG source-of-truth direction (S2)** — at PR-write time, pick: install.sh canonical (current plan default) OR CHANGELOG canonical (sequencing's preferred direction). Either works.
2. **`config/` file contents pre-review** — Justin pre-reviews the literal cmux.json/tmux.conf/zsh-prompt-colors.zsh bytes before /build emits them (5-min review).

(Open questions 1, 4, 5 from v1.0 collapsed per scope-discipline C2 — they were process steps, not real questions.)

## Risks

| # | Risk | Wave | Mitigation |
|---|------|------|------------|
| R1 | install.sh stages land out-of-order → SIGINT trap missing when tmp written → orphan files | W2 | Strict sequential commit ordering 2.1→2.10; `autorun-shell-reviewer` subagent gate (B9 threshold pinned) |
| R2 | Test harness recursion via install.sh's existing prompts | W4 | `MONSTERFLOW_INSTALL_TEST=1` env flag at line 305-316 AND line 318-326 (B6) |
| R3 | `gh auth status` hangs on corporate proxy, kills <3s budget | W3 | trap-alarm 5s timeout (D9) |
| R4 | Theme symlink clobbers user config silently | W2 (2.8) | `link_file()` BACKUP→`.bak.YYYYMMDDHHMMSS` pattern (S7); Acceptance case 6d |
| R5 | `.zshrc` source line breaks on path with spaces or special chars | W2 (2.8) | Single-quote escaping (D6, B4) |
| R6 | SIGINT cleanup deletes attacker-staged files | W2 (2.2) | `mktemp -d` scoped scratch + `rm -rf <dir>` |
| R7 | Migration banner hardcodes wrong version after auto-bump | W2 (2.3) | `${VERSION}` from VERSION file at runtime (D10) |
| R8 | Net delta ~542 lines pushes install.sh near the "extract into helpers" threshold | W2 | Acceptable for v1; extraction tracked as future spec only if file grows past ~600 |
| R9 | Adopter on macOS without Xcode CLI gets cryptic git error before Linux guard | W2 (2.1) | Linux guard checks `uname`; macOS ≥14 check via `sw_vers` (S5) |
| R10 | Box-drawing renders as garbage on legacy terminal | W3 | content-survives-degrade discipline |
| **R11** | **NEW (B10):** Supply-chain tampering of `config/*` (adversary commits malicious tmux.conf or zsh-prompt-colors.zsh) | W4 (4.7) | `tests/test-config-content.sh` greps config/* for `curl|wget|nc|bash <(|eval`; fails CI on match |
| R12 | Brew transitive-deps surprise — adopter sees 4 tools, brew installs 30 | W2 (2.6) | Pre-confirm `brew deps --include-build` preview (S1) |
| R13 | Bash 3.2 vs 5.x subtle test-harness differences | W4 | `BASH=/bin/bash` pinned in test invocations (S4) |
| R14 | cmux requires macOS ≥14; adopter on macOS 13 hits cryptic cask install fail | W2 (2.1) | `sw_vers` pre-flight (S5) — downgrade cmux to OPTIONAL on macOS 13 |
| R15 | `[ -t 0 ]` collides with tests piping stdin → false non-interactive | W4 | `MONSTERFLOW_FORCE_INTERACTIVE=1` (S6, D3) |

## Convergence Notes (v1.1)

**v1.0 → v1.1 changes by source:**

- **Codex adversarial (5 NEW blockers landed inline per session memory):** B2 owner-detect regression, B3 brew-bundle wrap fiction, B4 printf %q+zsh mismatch, B5 flag-parse top-of-file conflict, B7 `link_file` `.bak` overwrite (now S7).
- **Testability FAIL:** B1 mock strategy swap, B6 recursion guard sites, B7 brew-stub lifecycle, B8 `script -q` swap to `expect`.
- **Risk PASS WITH NOTES:** B9 subagent gate threshold, B10 supply-chain R11, S1 brew preview, S4 bash pin, S5 cmux macOS ≥14, S6 FORCE_INTERACTIVE, S7 .bak timestamp.
- **Sequencing PASS WITH NOTES:** O1 task 1.6 comment, S3 W2 commit count corrected to 10 (= number of tasks 2.1, 2.2, ..., 2.9, 2.9b, 2.10 — actually 11; counted as 10 for net commits because 2.9 + 2.9b can squash into one commit if needed).
- **Scope-discipline:** rejected C1 (drop INSTALL_TEST env var) — Testability B6 proved it serves a distinct concern; collapsed Open Questions 1, 4, 5 per C2.
- **Completeness:** O2 added shellcheck on test-install.sh to W4 ship criterion.

**v1.1 surface area:** 15 risks (was 10), 12 design decisions (unchanged count, several rewritten), 22 tasks (was 21 — added 2.9b + 4.7).
