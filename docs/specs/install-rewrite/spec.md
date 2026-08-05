---
status: shipped
name: install-rewrite
description: Pivot install.sh from a checker into a detect → install → verify → onboard flow with brew-bundle install, owner-vs-adopter theme baseline, version-aware migration, non-interactive auto-detect, and a regression-proofed test harness.
created: 2026-05-03
revised: 2026-05-04 (post-review v1.1 — scope cut wiki indexing; resolved 3 contradictions; added migration story, non-interactive mode, Linux guard, SIGINT trap; pinned has_cmd mock strategy and `set -euo pipefail` catch pattern)
constitution: none — defaults-only roster (precedent: pipeline-wiki-integration, persona-metrics, spec-upgrade)
confidence: 0.93 (post-revision)
session_roster: defaults only (27 stock personas — no domain agents installed for this spec)
---

# Install Rewrite Spec

*Session roster only — run /kickoff later to make this a persistent constitution.*

## Summary

Pivot `install.sh` from its current "detect → warn → symlink" flow into "detect → install → verify → onboard." Today an adopter who runs the one-liner ends up with a working symlink graph but no `gh`, no `shellcheck`, no `jq`, and no idea what to type next; features degrade silently. After this spec, a fresh-Mac adopter ends with a demonstrably-working pipeline, a one-screen "what to do next" panel, and (if they opt in) a baseline shell theme matching MonsterFlow's dogfood configuration.

The change is **additive surgery** on the existing 354-line `install.sh`, not a rewrite. Existing logic — owner-vs-adopter detection (now hardened), persona-metrics gitignore default-flip, post-commit hook installation, sentinel-bracketed gitignore blocks — is preserved. New stages slot in: brew-bundle install (single confirm, with a hardened `if ! brew bundle …; then` guard so `set -euo pipefail` doesn't kill the script before the catch path runs), version-aware migration messaging when prior install is detected, config-theme symlink (owner-no-prompt / adopter-prompt-default-N) that reuses the existing `link_file()` backup pattern, and a new standalone `scripts/onboard.sh` that prints the next-steps panel and (only) kicks off graphify indexing when its detection condition holds.

## Revisions

**v1.1 (2026-05-04, post `/spec-review`):** Resolved 10 blocker findings + 8 important + 2 minor. Scope cut: dropped wiki-export indexing from `scripts/onboard.sh` (it's a Claude Code skill, not bash-callable; gated owner-only anyway). Kept theme baseline + cmux (Justin's owner-favored extras). Resolved `--no-install` semantics (bypasses ALL enforcement, true CI escape hatch). Resolved owner theme prompt (no-prompt for owner, prompt-default-N for adopter). Replaced "byte-identical stdout" idempotency with state assertions. Pinned `has_cmd` mock strategy (function-shadowing in tests). Added owner detection robustness (realpath + git-toplevel + `MONSTERFLOW_OWNER` env override). Added non-interactive mode (auto-detect via `[ -t 0 ]` + explicit `--non-interactive` flag). Added v0.4.x → v0.5.0 migration messaging. Added Linux guard, SIGINT trap, brew-bundle catch pattern. Resolved `pip3` migration contradiction (out-of-scope, no incremental migration). Fixed cmux terminology (cask, not formula).

## Backlog Routing

| # | Item | Source | Routing |
|---|------|--------|---------|
| 1 | Opinionated idempotent install.sh | BACKLOG.md:46-68 | **(a) In scope — this spec** |
| 2 | Per-plugin cost measurement | BACKLOG.md:13-17 | (b) Stays — token-economics track |
| 3 | Plugin scoping per gate | BACKLOG.md:19-23 | (b) Stays — depends on #2 |
| 4 | Holistic token instrumentation | BACKLOG.md:25-42 | (b) Stays — partially in token-economics spec |
| 5 | Account-type agent scaling | BACKLOG.md:72-78 | (b) Stays — depends on token-economics |
| 6 | Inter-agent debate (Agent Teams) | BACKLOG.md:82-89 | (b) Stays — research-grade, deferred |

## Scope

### In scope

- Brewfile-driven install of REQUIRED + RECOMMENDED tools (Brewfile already shipped in commit 9c08163)
- `python_pip()` helper sourced and used inside `install.sh` (helper already shipped in 9c08163)
- Tier-aware decline behavior: REQUIRED-missing hard-stops, RECOMMENDED-missing continues with a defined loud notice
- Brew itself in REQUIRED tier (no special-case code path); error message names the brew.sh URL and the install command
- `cmux` added to RECOMMENDED via `cask "cmux"` syntax (homebrew-cask, auto-updates per cask author)
- `tmux` demoted to OPTIONAL (still installed by adopters who use the autorun headless flow; tracked under Open Questions for possible removal once autorun migrates off tmux)
- New `config/` directory shipping neutral opinionated defaults: `cmux.json`, `tmux.conf`, `zsh-prompt-colors.zsh`
- Theme stage uses the existing `link_file()` backup pattern (`mv $dst → ${dst}.bak` when target is not already a symlink) — never silently clobbers user files
- `--install-theme` / `--no-theme` flags; `--no-theme` wins when both are passed
- Default theme behavior: **owner = install without prompt; adopter = prompt-default-N**
- `--no-install` flag — **bypasses ALL detection and enforcement** (true CI escape hatch); symlinks still run; REQUIRED-missing does NOT hard-stop under this flag
- `--non-interactive` flag (or auto-detect via `[ -t 0 ]`) — disables every prompt, selects safe defaults: skip theme install (unless `--install-theme` also passed), skip onboard panel (unless `--force-onboard`), skip `gh auth login` offer
- `--no-onboard` flag — suppress onboard panel for fully-scripted runs
- New standalone `scripts/onboard.sh` invoked by install.sh as its last step (unless `--no-onboard` or non-interactive); independently re-runnable
- onboard.sh runs `scripts/doctor.sh`, prints next-steps panel (with assertable substrings: `/flow`, `/spec`, `dashboard/index.html`), optionally kicks off graphify indexing (`bootstrap-graphify.sh`)
- onboard.sh offers `gh auth login` only if `gh` installed AND unauthenticated AND TTY present
- onboard.sh surfaces codex opt-in as a single line ("Want adversarial review? Run `/codex:setup`")
- Owner detection: `realpath` of `install.sh` dirname compared against `git rev-parse --show-toplevel`; `MONSTERFLOW_OWNER=1` env var overrides
- Linux fail-fast guard: top of `install.sh` exits 1 with "MonsterFlow install.sh is macOS-only" if `[ "$(uname)" != Darwin ]`
- SIGINT trap: `trap cleanup_partial INT TERM` removes any half-written `.tmp` files on Ctrl-C
- v0.4.x → v0.5.0 migration messaging: detect prior install via existing `~/.claude/commands/spec.md` symlink to a MonsterFlow path; print "Upgrading MonsterFlow from prior install: here is what is new in v0.5.0" with a 5-line diff before mutating
- `tests/test-install.sh` — 9 cases (see Acceptance Criteria); runs against a temp `$HOME` so it doesn't touch the dev machine; uses bash function-shadowing to mock `has_cmd` (no PATH manipulation, no Docker)

### Out of scope

- Linux support (per BACKLOG.md: "the brew assumption is macOS-only; Linux can wait until there's a real Linux adopter") — Linux guard exits cleanly with messaging, but no functional Linux path
- Auto-bootstrapping brew via `curl | bash` (rejected on security grounds — adopter must run brew's installer themselves; we just print the URL)
- Migrating autorun off tmux to a native headless flow (parked under Open Questions; "tmux is used in our headless flow — not sure if we should keep it or use a native headless flow but good either way")
- Per-tool install prompts (rejected — bulk single-confirm is the agreed UX)
- Refactoring the existing 354 lines into helper modules (rejected — additive surgery only)
- Wiki-export indexing kickoff from `scripts/onboard.sh` (deferred; `wiki-export` is a Claude Code skill that runs inside the agent loop, not bash-callable; gated owner-only via `~/.obsidian-wiki/config` so adopters wouldn't see it anyway. If it returns later, the implementation path is to factor wiki logic into a callable `scripts/wiki-export.sh` that the skill also wraps)
- Adopting the `python_pip` auto-detect helper in sister scripts (`bootstrap-graphify.sh`, venv-install paths). Those scripts keep their hardcoded `pip3` calls — they work today; switching them to the helper is a separate sweep, not a "migration"
- Theme uninstall script (deferred until an adopter actually asks; `--no-theme` only governs the current run, doesn't reverse a prior install)
- Custom theme color overrides (would require a theme-config-merge layer; YAGNI for v1)
- Per-tool RECOMMENDED opt-in (bulk-only is the agreed UX)

## Approach

**Additive surgery** on `install.sh`. The existing file does several things well and has memory-backed institutional knowledge baked in (PWD-based owner detection per `feedback_install_adopter_default_flip.md`; sentinel-bracketed gitignore block; auto-bump hook installation; persona-metrics default-flip). Preserving all of it (with owner-detect hardened, not replaced) is the lowest-risk path to closing the BACKLOG.md gap.

**The flow becomes:**

```
0. Linux guard         (NEW — top of file; exit 1 if not Darwin)
1. Parse flags         (NEW — --no-install, --install-theme/--no-theme, --non-interactive, --no-onboard, --force-onboard)
2. SIGINT trap         (NEW — cleanup_partial on INT/TERM)
3. Migration detect    (NEW — `[ -L $CLAUDE_DIR/commands/spec.md ]` → print v0.4.x → v0.5.0 upgrade message with diff)
4. Detect tier-by-tier (existing has_cmd loop — extend REQUIRED with `brew`)
5. Install missing     (NEW — `if ! brew bundle --file=Brewfile install; then handle_failure; fi`, single confirm; respects --no-install bypass-all and --non-interactive)
6. Decline behavior    (NEW — REQUIRED hard-stop OR --no-install bypass; RECOMMENDED loud-notice continue per defined format)
7. Symlink files       (existing — commands, personas, scripts, autorun, settings)
8. Adopter-vs-owner    (existing — queue/.gitignore, persona-metrics gitignore block; owner-detect uses new hardened logic)
9. Install theme       (NEW — config/ symlinks via link_file() reusing backup pattern; owner=no-prompt, adopter=prompt-default-N, --no-theme wins)
10. CLAUDE.md baseline (existing)
11. Git hooks          (existing — install-hooks.sh wiring)
12. Plugin install     (existing — claude plugins install)
13. Validate           (existing — tests/run-tests.sh)
14. Onboard            (NEW — bash scripts/onboard.sh; suppressed under --no-onboard or --non-interactive without --force-onboard)
```

Stages 7–13 are unchanged code. Stages 0, 1, 2, 3, 5, 6, 9, 14 are new. Stage 4 gets one line added. Stage 8 gets the owner-detect call swapped for the hardened variant.

**Why not wholesale rewrite:** Loses too much memory-backed detail. The owner detection took a memory entry to land correctly; the gitignore sentinel pattern took another. A blank-slate rewrite would either re-litigate those decisions or accidentally drop them.

**Why not extract-into-helpers:** Premature refactor on top of a feature, violates "don't add abstractions beyond what the task requires" from global CLAUDE.md. If install.sh later grows past ~500 lines, extraction is a follow-up spec. Per Codex: "additive surgery framing understates the control-flow changes" — `/plan` will explicitly diagram new vs old flow to avoid sequencing/early-exit bugs around existing validation/plugin prompts.

## Roster Changes

No roster changes. Defaults-only roster (27 stock personas) covers this work.

## UX / User Flow

### Fresh-Mac adopter (full happy path)

```
$ git clone https://github.com/Jstottlemyer/MonsterFlow.git ~/Projects/MonsterFlow
$ cd ~/Projects/MonsterFlow && ./install.sh

=== Claude Workflow Pipeline Installer — v0.5.0 ===
Repo:   /Users/.../MonsterFlow
Target: /Users/.../.claude

✗ REQUIRED — pipeline will not work without these:
  - brew (Homebrew) — install from https://brew.sh:
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  - claude (Claude Code CLI) — https://claude.com/claude-code

Install these and re-run install.sh.
$ exit 1
```

After adopter installs brew + claude, re-run:

```
$ ./install.sh
=== Claude Workflow Pipeline Installer — v0.5.0 ===

✓ REQUIRED tools present
⚠ RECOMMENDED missing: gh, shellcheck, jq, cmux

About to install via Homebrew (uses Brewfile at repo root):
  - gh         (GitHub CLI — /autorun PR ops)
  - shellcheck (PostToolUse hook on .sh edits)
  - jq         (PostToolUse hook on .json edits)
  - cmux       (Ghostty-based terminal for AI agents — cask)

Proceed? [Y/n]: <enter>

[brew bundle install runs, output streamed]
✓ brew bundle complete

Installing pipeline commands... [existing output]
[…all the existing symlink output…]

Install MonsterFlow shell theme? [y/N]: y
  BACKUP: ~/.tmux.conf → ~/.tmux.conf.bak  (existing real file preserved)
  LINKED: ~/.tmux.conf → /Users/.../MonsterFlow/config/tmux.conf
  LINKED: ~/.config/cmux/cmux.json → /Users/.../MonsterFlow/config/cmux.json
  ✓ source <repo>/config/zsh-prompt-colors.zsh added to ~/.zshrc (sentinel-bracketed)

[…rest of existing install output…]

=== Installation complete ===

Running scripts/onboard.sh...

╭─ MonsterFlow is ready ──────────────────────────────╮
│                                                       │
│  Next steps:                                          │
│    1. cd into a project                               │
│    2. /flow            — see the workflow card        │
│    3. /spec            — design your first feature    │
│    4. open ~/Projects/MonsterFlow/dashboard/index.html│
│                                                       │
│  Optional:                                            │
│    • Index ~/Projects/ for the dashboard? [y/N]       │
│    • Authenticate gh CLI now? (gh auth login) [y/N]   │
│    • Want adversarial review? Run /codex:setup        │
│                                                       │
╰───────────────────────────────────────────────────────╯
```

### Owner re-run (no prompts)

```
$ ./install.sh
=== Claude Workflow Pipeline Installer — v0.5.0 ===

✓ REQUIRED tools present
✓ RECOMMENDED tools present

[brew bundle check — nothing to install, stage skipped]
[symlinks — all already present, no-op]
[theme — owner mode: applied without prompt; files already symlinked, no-op]
[onboard — prints panel; offers indexing only if not run recently]

=== Everything already in place ===
exit 0   (under 3 seconds)
```

### v0.4.x → v0.5.0 adopter (upgrade flow)

```
$ ./install.sh
=== Claude Workflow Pipeline Installer — v0.5.0 ===

⬆ Detected prior MonsterFlow install — upgrading to v0.5.0.
  What's new in v0.5.0:
    - install.sh now installs brew tools for you (was: warn-only)
    - Optional shell theme (~/.tmux.conf, cmux config, prompt colors)
    - New flags: --no-install, --no-theme, --non-interactive
    - cmux added to RECOMMENDED; tmux moved to OPTIONAL
    - macOS-only (Linux guard added)

  See CHANGELOG.md for full details. Proceed with upgrade? [Y/n]:
```

### CI / restricted env

```
$ ./install.sh --non-interactive
[Linux guard runs]
[detection runs but install stage is skipped if any tools missing — exit 1 with REQUIRED list]
[symlinks proceed when REQUIRED present]
[theme skipped (would need --install-theme too)]
[onboard skipped (would need --force-onboard)]

# OR, true CI escape:
$ ./install.sh --no-install --no-theme --no-onboard
[detection results printed for log; no enforcement]
[symlinks proceed regardless of missing tools]
[exit 0]
```

## Data & State

### `Brewfile` (already shipped, will add `cmux` cask in /build)

```ruby
# REQUIRED
brew "git"
brew "python@3.11"

# RECOMMENDED
brew "gh"
brew "shellcheck"
brew "jq"
cask "cmux"        # Homebrew cask (not a formula); auto-updates per cask author
# tmux removed from default — moved to OPTIONAL (offline/headless flows)
```

### `config/` directory (NEW)

```
config/
├── cmux.json                    # neutral opinionated cmux config (vertical tabs, dark theme)
├── tmux.conf                    # high-contrast cyan/grey theme, $HOME-relative paths only
└── zsh-prompt-colors.zsh        # sourceable file; theme-only, no behavioral changes
```

These files ship in-repo, are reviewable in git history, contain zero network calls, and use only `$HOME`-relative paths (no Justin-machine specifics). Satisfies the "safety from a security standpoint" requirement: every byte is auditable before it lands on the adopter's disk.

### `scripts/onboard.sh` (NEW, standalone)

Independently re-runnable. Outline:

```bash
#!/bin/bash
# scripts/onboard.sh — post-install onboarding panel
# Re-run anytime: `bash ~/Projects/MonsterFlow/scripts/onboard.sh`
# Honours --non-interactive, --force-onboard from install.sh via env vars.

set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# 1. Run doctor.sh to verify wiring (failure printed but non-fatal)
bash "$REPO_DIR/scripts/doctor.sh" || true

# 2. Print next-steps panel (boxed; copy-pasteable commands; assertable substrings)
print_panel    # MUST contain literal substrings: /flow, /spec, dashboard/index.html

# 3. Optional kickoffs (each gates on detection AND TTY presence)
if [ -t 0 ] && [ -d "$HOME/Projects" ]; then
    offer_graphify_bootstrap
fi
if [ -t 0 ] && command -v gh >/dev/null 2>&1 && ! gh auth status >/dev/null 2>&1; then
    offer_gh_auth
fi
command -v codex >/dev/null 2>&1 || echo "  Want adversarial review? Run /codex:setup"
```

**Wiki indexing is intentionally absent** — `wiki-export` is a Claude Code skill, not a shell-callable command. If it returns later, the implementation path is to factor wiki logic into a callable `scripts/wiki-export.sh` that the skill also wraps.

### Flag surface (new)

| Flag | Purpose | Default |
|------|---------|---------|
| `--no-install` | Bypass ALL detection + enforcement; symlinks still run; CI escape hatch | off |
| `--install-theme` | Force theme install on (overrides owner/adopter default) | off |
| `--no-theme` | Force theme install off; **wins over `--install-theme`** | off |
| `--non-interactive` | Disable every prompt; safe defaults; auto-set when `[ -t 0 ]` is false | auto |
| `--no-onboard` | Suppress onboard panel run (panel still re-runnable later) | off |
| `--force-onboard` | Run onboard panel even under `--non-interactive` | off |

(Existing flags / env vars preserved: `PERSONA_METRICS_GITIGNORE`, plus new: `MONSTERFLOW_OWNER=1` env override for owner detection.)

### "Loud notice" definition

For RECOMMENDED-missing decline path:

- Glyph: `⚠`
- Stream: `stderr`
- Format (one line + one line): `⚠ Continuing without [tool list]. Features will silently no-op (PR ops, shellcheck hook, etc.). Re-run install.sh anytime to install.`
- Repeat: emitted once at decline-time, NOT repeated at exit
- Exit code: 0 (RECOMMENDED-missing is non-fatal; the loud-notice IS the signal)

### State changes on disk

| Path | Owner-default | Adopter-default | Backup if existing real file? | Sentinel-bracketed? |
|------|---------------|-----------------|-------------------------------|---------------------|
| `~/.tmux.conf` → `config/tmux.conf` | symlinked, no prompt | prompt-default-N | YES (`mv → .bak` via link_file) | N/A (symlink) |
| `~/.config/cmux/cmux.json` → `config/cmux.json` | symlinked, no prompt | prompt-default-N | YES | N/A (symlink) |
| `~/.zshrc` (one line: `source <repo>/config/zsh-prompt-colors.zsh`) | appended, no prompt | prompt-default-N | N/A (append, not replace) | YES (`# BEGIN MonsterFlow theme` / `# END MonsterFlow theme`) |

The `.zshrc` append uses the sentinel-bracketing pattern proven by the persona-metrics gitignore block — re-running install.sh is idempotent; future `--uninstall-theme` (out of scope) would cleanly remove the block.

## Integration

### Files modified

- `install.sh` — additive surgery; new flag parsing, Linux guard, SIGINT trap, migration detect, install stage, decline handler, theme stage, onboard call. Owner-detect call site swapped for hardened helper. `set -euo pipefail` retained; new install + brew-bundle stages use explicit `if !` guarding.
- `Brewfile` — already at repo root (commit 9c08163); add `cask "cmux"`, remove `brew "tmux"`
- `scripts/lib/python-pip.sh` — already shipped; install.sh sources it and uses `python_pip` for any pip invocation. The helper does pip3-vs-pip auto-detection at call time (no migration, just resolution). Sister scripts (`bootstrap-graphify.sh`, venv-install paths) continuing to hardcode `pip3` is OUT OF SCOPE for this spec — they keep working as-is; adopting the auto-detect helper there is a separate sweep.

### Files created

- `scripts/onboard.sh` — new standalone, ~80 lines
- `config/cmux.json`, `config/tmux.conf`, `config/zsh-prompt-colors.zsh` — new (contents pinned at /plan time)
- `tests/test-install.sh` — new harness covering 9 acceptance cases
- (Optional) `CHANGELOG.md` — referenced by migration message; create if not present

### Existing code preserved

- `has_cmd()` PATH-augmenting helper (lines 21-25) — extend its callers, not the function. Tests use bash function-shadowing (`has_cmd() { return 1; }`) to mock it without modifying production code.
- `link_file()` (lines 91-100) — REUSED by the new theme stage for backup-on-conflict
- `write_queue_gitignore()` (lines 208-225) — unchanged
- Persona-metrics default-flip block (lines 232-278) — unchanged; sentinel-bracketed pattern reused for new `.zshrc` theme append
- CLAUDE.md baseline merge (lines 280-292) — unchanged
- Git hooks installation (lines 294-303) — unchanged
- Plugin install prompts (lines 305-316) — unchanged; respect `--non-interactive`
- Test suite validation (lines 318-326) — unchanged

### Owner detection (hardened)

```bash
# Replaces lines 190-202.
detect_owner() {
    if [ "${MONSTERFLOW_OWNER:-0}" = "1" ]; then
        echo 1; return 0
    fi
    local script_dir
    script_dir="$(cd "$(dirname "$0")" && pwd -P)"   # realpath via -P
    local git_root
    git_root="$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || true)"
    if [ -n "$git_root" ] && [ "$script_dir" = "$git_root" ]; then
        echo 1
    else
        echo 0
    fi
}
OWNER="$(detect_owner)"
```

This handles: symlinked repo paths (`-P` resolves them), `bash ~/Projects/MonsterFlow/install.sh` from any cwd, git worktrees (each worktree's `--show-toplevel` matches its own dir), agent-driven runs that set `MONSTERFLOW_OWNER=1` explicitly.

### Touchpoints with other scripts

- `scripts/bootstrap-graphify.sh` — onboard.sh invokes it on opt-in (already exists)
- `scripts/doctor.sh` — onboard.sh invokes it (already exists)
- `scripts/install-hooks.sh` — install.sh continues to call it (already exists)
- `scripts/lib/python-pip.sh` — install.sh sources it; sister-script migration deferred (Open Q1)

## Edge Cases

### Linux user

```bash
# At top of install.sh, before any brew calls:
if [ "$(uname)" != "Darwin" ]; then
    echo "MonsterFlow install.sh is macOS-only." >&2
    echo "Linux support tracked in BACKLOG.md as out-of-scope for v1." >&2
    exit 1
fi
```

### Tier-split decline behavior

| State | Behavior |
|-------|----------|
| REQUIRED missing AND user declines auto-install | Hard-stop. Print install command per tool. Exit 1. |
| REQUIRED missing AND `--no-install` passed | **Bypass-all: print detection results to stdout for log, do NOT hard-stop, proceed to symlinks.** Adopter has explicitly waived enforcement. |
| RECOMMENDED missing AND user declines | Continue with loud notice (defined format above). Exit 0 from this stage. |
| `--no-install` passed (any tool state) | Skip install stage entirely. Symlinks still run. One-line stderr notice: "Skipped install per --no-install. Some features may be degraded." Exit 0. |
| `--non-interactive` AND no flag combo allows skipping | If REQUIRED missing, hard-stop with "REQUIRED missing in non-interactive mode; pass --no-install to bypass." |

### `set -euo pipefail` + brew bundle

```bash
# CORRECT pattern (spec requires this form, not implicit error handling):
if ! brew bundle --file="$REPO_DIR/Brewfile" install; then
    echo "⚠ brew bundle failed for some formulas. Re-run install.sh after fixing." >&2
    echo "  Symlinks were not created to avoid a half-installed state." >&2
    exit 1
fi
```

### SIGINT mid-install

```bash
cleanup_partial() {
    # Remove any half-written .tmp files this run created
    find "$REPO_DIR" "$CLAUDE_DIR" -name '*.monsterflow.tmp' -delete 2>/dev/null || true
    echo "" >&2
    echo "⚠ install.sh interrupted; partial state cleaned up." >&2
    echo "  Re-run when ready." >&2
    exit 130
}
trap cleanup_partial INT TERM
```

All atomic file writes use `<file>.monsterflow.tmp` suffix so the trap can clean them up unambiguously.

### v0.4.x → v0.5.0 migration

```bash
# Detect via existing symlink target
PRIOR_INSTALL=0
if [ -L "$CLAUDE_DIR/commands/spec.md" ]; then
    PRIOR_TARGET="$(readlink "$CLAUDE_DIR/commands/spec.md")"
    case "$PRIOR_TARGET" in
        */MonsterFlow/*|*/claude-workflow/*) PRIOR_INSTALL=1 ;;
    esac
fi

if [ "$PRIOR_INSTALL" = "1" ]; then
    print_upgrade_message    # static 5-line diff describing v0.5.0 changes
    if [ "$NON_INTERACTIVE" = "0" ]; then
        read -rp "Proceed with upgrade? [Y/n]: " UPGRADE_CONFIRM
        [[ "$UPGRADE_CONFIRM" =~ ^[Nn]$ ]] && exit 0
    fi
fi
```

### Theme symlink with existing real file

`link_file()` (existing lines 91-100) already handles this:

```bash
link_file() {
    local src="$1" dst="$2"
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
        echo "  BACKUP: $dst → ${dst}.bak"
        mv "$dst" "${dst}.bak"
    fi
    ln -sf "$src" "$dst"
    echo "  LINKED: $dst → $src"
}
```

The new theme stage MUST call `link_file` (not raw `ln -sf`) for every theme target — explicit requirement to preserve user data.

### Re-run on fully-installed system

- Linux guard passes
- Migration detect: prior install detected → confirms upgrade (auto-skips under `--non-interactive`)
- `has_cmd` checks pass for all tiers
- `brew bundle check --file=Brewfile` returns clean → skip the install stage entirely
- Symlinks already exist → `ln -sf` no-ops
- Theme: owner mode → no-prompt, all symlinks already present → no-op; adopter mode → prompt-default-N, declined → no-op
- `.zshrc` sentinel block exists → skip append
- onboard.sh: doctor runs, panel prints, indexing offers gate on "not-run-recently" sentinel files (`~/.local/share/MonsterFlow/.last-graphify-run`)
- Total runtime target: under 3 seconds (revised from "<2s" per Feasibility — interactive `read` prompts that are still in the fast path on owner runs add jitter)

### `--no-theme` on a system with theme already installed

Spec deliberately does NOT remove the existing theme. `--no-theme` only governs default-no-prompt for the current run. To uninstall the theme cleanly, adopter would run a separate `scripts/uninstall-theme.sh` (out of scope — added if/when an adopter actually asks).

### Network failure mid-`brew bundle`

The `if ! brew bundle ...; then` guard catches the non-zero exit explicitly (set -euo pipefail does not kill the script when the failing command is the test of an `if`). Failure handler prints message, exits 1. No half-install (symlinking is gated behind successful brew install completion, except under `--no-install` bypass).

### Terminal that doesn't render box-drawing characters

The onboarding panel uses Unicode box-drawing (`╭─╮│╰─╯`) — degrades acceptably to garbage on legacy terminals but doesn't break the script. If this becomes a real adopter complaint, fall back to plain ASCII (`+----+ | | +----+`).

### `--install-theme` + `--no-theme` passed together

`--no-theme` wins. Documented in the flag table; implementation does flag-precedence check before applying defaults.

## Acceptance Criteria

`tests/test-install.sh` runs all 9 cases below against a temp `$HOME` (created with `mktemp -d`, sourced into a subshell with `HOME=<tmp>`) so it never touches the dev machine. Mocking strategy: bash function-shadowing (`has_cmd() { return 1; }` defined in the test before sourcing install.sh) — no PATH manipulation, no Docker. Each case asserts via `[[ ]]` / `grep` / `find` against expected output and disk state; one failure halts the suite with the case number and last 20 lines of output.

1. **Idempotency under repeat runs (state-based, not byte-based).** Run `install.sh` twice in a row with all tools present. Assertions:
   - No duplicate symlinks: `find $HOME/.claude -type l -exec readlink {} \; | sort | uniq -d` returns empty
   - No duplicate `.zshrc` sentinel blocks: `grep -c "BEGIN MonsterFlow theme" ~/.zshrc` returns 0 or 1, never 2+
   - Key messages present in both runs' stdout: "Installation complete", "MonsterFlow is ready"
   - Both runs exit 0

2. **Fast no-op on fully-installed system.** Pre-stage temp `$HOME` with all symlinks present, all brew tools detectable. Run `install.sh`. Assertions: stdout contains "everything already in place"; exit code 0; total wall-clock under 3 seconds (raised from 2s per Feasibility).

3. **Fresh-Mac REQUIRED hard-stop.** Pre-stage temp `$HOME` with no symlinks; shadow `has_cmd` to report all tools missing. Run `install.sh`. Assertions: REQUIRED panel printed; brew install command included in output; exit code 1.

3a. **Fresh-Mac happy path (NEW — separates happy path from hard-stop).** Pre-stage with brew + claude + git + python3 present, RECOMMENDED missing (`gh`, `jq`, `shellcheck`). Pipe `Y\n` to install.sh's stdin. Assertions: `brew bundle install` invoked (mock the brew binary to a stub that records its argv); symlinks created; theme stage prompted (adopter mode) and declined-default-N exits theme stage cleanly; onboard panel printed; exit 0.

4. **Re-install after `brew uninstall jq`.** Pre-stage all symlinks present, all tools present except jq. Run `install.sh` with `Y` piped. Assertions: install stage runs; `brew bundle install` invoked with `--file=Brewfile`; post-install jq detection returns true; symlink graph diff before/after is empty.

5. **`--no-install` flag bypasses ALL enforcement.** Pre-stage with `git`, `python3`, `brew`, `claude` all missing. Run `install.sh --no-install`. Assertions: detection results printed to stdout; **no hard-stop on REQUIRED-missing**; symlinks still created; exit code 0. (This is the CI-escape contract.)

6. **Theme install honors owner-vs-adopter default and backup pattern.**
   - **6a (owner, no prompt):** Run from owner detection → theme symlinks created without any `read` prompt. Assertion: `[ -L ~/.tmux.conf ]` true; no "Install MonsterFlow shell theme?" string in stdout.
   - **6b (adopter, prompt-default-N):** Force adopter mode (cd to a temp dir; unset `MONSTERFLOW_OWNER`). Run with no theme flags. Pipe empty input to consume default. Assertions: prompt printed; `[ -L ~/.tmux.conf ]` false (declined).
   - **6c (adopter, `--install-theme`):** Force adopter mode + `--install-theme`. Assertions: no prompt; `[ -L ~/.tmux.conf ]` true.
   - **6d (existing real file backup):** Pre-stage `~/.tmux.conf` as a real file with known content. Run with theme install. Assertion: `~/.tmux.conf.bak` exists with the original content; `~/.tmux.conf` is now a symlink to `config/tmux.conf`.

7. **Indexing kickoff gates on detection and TTY.** Pre-stage temp `$HOME` with `~/Projects/test-proj/some.py` present. (a) With TTY (`script -q /dev/null` wrapper) → onboard.sh offers graphify prompt. (b) With `--non-interactive` → onboard.sh runs but does NOT offer prompt (silent). Verified via `grep -c "Index ~/Projects" output.txt` returning 1 vs 0. Wiki indexing is NOT tested (not in scope per v1.1 cut).

8. **v0.4.x → v0.5.0 migration messaging.** Pre-stage temp `$HOME` with `~/.claude/commands/spec.md` symlinked to a `*/MonsterFlow/*` path (simulating prior install). Run `install.sh`. Assertions: stdout contains "Detected prior MonsterFlow install — upgrading to v0.5.0"; upgrade-diff message contains "What's new in v0.5.0" with at least 5 bullets.

9. **Non-interactive mode (auto-detect + explicit flag).**
   - **9a (TTY absent):** Run `install.sh </dev/null` (no TTY on stdin). Assertions: no `read -rp` prompts in stdout; theme not installed (default-N applied silently); onboard panel suppressed unless `--force-onboard`.
   - **9b (`--non-interactive` flag explicit):** Run with TTY but `--non-interactive`. Same assertions as 9a.
   - **9c (`--non-interactive --force-onboard`):** Panel runs but no interactive sub-prompts; graphify offer is silent skip.

Plus a non-test acceptance bar:

- **Shellcheck-clean.** `shellcheck install.sh scripts/onboard.sh tests/test-install.sh` returns 0 with no warnings.
- **Linux guard verified manually** (no automated test — would need a Linux runner). Document the manual check in PR description.
- **Documentation parity.** README.md install one-liner still works post-change (no flag-rename break). QUICKSTART.md updated to describe new flag surface + migration messaging. CHANGELOG.md created/updated with v0.5.0 entry.
- **Onboard panel substring assertions.** Test 7 (or a new dedicated test) asserts the panel contains literal `/flow`, `/spec`, `dashboard/index.html`. Adding/removing a numbered step requires a test update — this is the explicit "panel content has acceptance" gate.

## Open Questions

1. **Tmux in autorun.** Justin's prior answer: "tmux is used in our headless flow — not sure if we should keep it or use a native headless flow but good either way." Demoting tmux to OPTIONAL in this spec assumes autorun continues to use it (and adopters of autorun can install tmux on demand). If a follow-up spec migrates autorun to a native headless approach (`nohup`, `disown`, plain `&`), tmux can be removed from OPTIONAL entirely. Tracked here, not blocking.
2. **`config/` file contents.** Spec names the three files (`cmux.json`, `tmux.conf`, `zsh-prompt-colors.zsh`) but doesn't pin exact contents. /plan resolves this — needs a per-file pass naming the colors, the tmux key bindings, the prompt format, and a safety review against shipping anything tied to Justin's machine specifically (e.g., absolute paths in tmux.conf must be `$HOME`-relative). Plan should also confirm cmux's actual config-file path (`~/.config/cmux/cmux.json`) by checking cmux docs at /plan time.
3. **Versioning.** Adding flags + new files is a `feat:` commit per the auto-bump rules → minor bump (0.4.x → 0.5.0). Confirm at /plan time whether to land as one commit or several (e.g., one per stage). The migration message hardcodes "v0.5.0" — if /plan picks a different version, that string moves.
