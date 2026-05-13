# Data Model — install-rewrite

**Stage:** /plan (Design) · **Persona:** data-model
**Scope:** Pin every byte of the new on-disk artifacts (`config/*`, sentinel
strings, `.zshrc` block, Brewfile delta, migration target patterns, last-run
sentinel locations) so /build is a copy-paste, not a re-derivation.

## Key Considerations

- **Auditability over cleverness.** Every byte that lands on an adopter's disk
  must be reviewable in git history, contain zero network calls, and use only
  `$HOME`-relative paths. No Justin-machine specifics (no `~/Projects/...`
  hardcoded, no `iCloud` paths, no team-ID strings).
- **Idempotent re-application.** Sentinel-bracketing pattern (proven by the
  persona-metrics gitignore block at install.sh:243-275) is the single
  mechanism for "did I already write this?" detection. No timestamp checks,
  no hash files — just `grep -qF "$BLOCK_BEGIN"`.
- **Atomic writes via `.monsterflow.tmp` suffix** so the SIGINT trap can clean
  up unambiguously without false positives on unrelated `.tmp` files in the
  repo or `~/.claude/`.
- **cmux config path is canonical.** Verified `~/.config/cmux/cmux.json` via
  cmux docs (https://cmux.com/docs/configuration) — that's the path cmux reads
  on launch and writes a commented template to if missing. JSON-with-comments
  + trailing commas accepted.
- **Migration detection via existing symlink target match** is the only
  cross-version state we read. We never persist a "last installed version"
  file — `readlink ~/.claude/commands/spec.md` tells us everything.
- **State spans 3 prefixes:** `~/.claude/`, `~/.config/cmux/`, `~/.local/share/MonsterFlow/`.
  Pin all three explicitly; do not let /build invent fourth-tier locations.
- **Owner vs adopter is computed, not stored.** No state file records "you are
  the owner." Re-computed every run from `realpath` + `git rev-parse`.

## Options Explored

### Option A: One JSON config file (combined cmux + tmux + zsh in one blob)

- **Pros:** single artifact to ship, single backup target, single sentinel.
- **Cons:** cmux reads `cmux.json` only; tmux reads `tmux.conf` only; zsh
  sources `.zsh` files only. Forcing a combined format requires a runtime
  splitter — adds complexity and breaks the "every byte auditable in git"
  property (the splitter becomes the audit surface).
- **Effort:** medium (splitter script + tests).
- **Verdict:** rejected. Native config formats win.

### Option B: Three native config files in `config/` (cmux.json + tmux.conf + zsh-prompt-colors.zsh) — RECOMMENDED

- **Pros:** each tool reads its native format; reviewable in git as-is; the
  symlink IS the install (no copy step, no checksum drift); `link_file()`
  handles all three uniformly with the existing backup pattern.
- **Cons:** three artifacts to maintain (low cost — these are short, stable
  files that change rarely).
- **Effort:** low.
- **Verdict:** recommended.

### Option C: Generated configs from a single template DSL

- **Pros:** color palette defined once, propagated to all three.
- **Cons:** YAGNI for v1. Template engine is a new dep. Generated files
  are second-class in git diff (reviewers read the template, not the
  output) — violates auditability.
- **Effort:** high.
- **Verdict:** rejected (would belong in a v2 "theme variants" spec if
  multiple themes ship).

### Option D: Use `.zshrc` source line vs append the colors directly

- **Pros of source line (chosen):** `.zshrc` block stays 3 lines; theme
  edits don't touch `~/.zshrc`; `--uninstall-theme` (future) only has to
  delete the sentinel block, never re-edit content.
- **Cons of append-direct:** every theme edit re-opens `.zshrc`, harder
  to keep idempotent, breaks the "config file is the source of truth"
  invariant.
- **Verdict:** source line wins. Single line inside the sentinel block,
  pointing at the repo path — re-running install.sh after the repo moves
  surfaces a broken-source warning on next shell startup, which is the
  desired loud failure mode.

### Option E: Last-graphify-run sentinel — file vs marker in dashboard JSONL vs no sentinel

- **No sentinel:** onboard.sh prompts every run → noisy on owner re-runs.
- **Marker in dashboard JSONL:** couples onboard to dashboard schema —
  rejected; dashboard owns its own format.
- **Sentinel file at `~/.local/share/MonsterFlow/.last-graphify-run`** —
  recommended. XDG-conforming location, single-purpose, mtime-readable
  for "ran in last 7 days" gating.

## Recommendation

### Pinned file: `config/cmux.json`

Cmux reads `~/.config/cmux/cmux.json` (verified via cmux docs). Schema
accepts JSON-with-comments and trailing commas; we ship pure JSON for
maximum safety.

```json
{
  "$schema": "https://raw.githubusercontent.com/manaflow-ai/cmux/main/web/data/cmux.schema.json",
  "schemaVersion": 1,
  "app": {
    "appearance": "system"
  },
  "sidebar": {
    "branchLayout": "vertical"
  },
  "notifications": {
    "sound": "default"
  }
}
```

**Rationale per key:**
- `appearance: system` — adopt OS dark/light setting; least-surprise
  default; no opinionated palette imposed.
- `branchLayout: vertical` — matches the "vertical tabs" cmux selling
  point that brought it into MonsterFlow's RECOMMENDED tier.
- `notifications.sound: default` — present but unobtrusive; adopter can
  silence in their own override.
- **Intentionally absent:** `language`, `appIcon`, `customSoundFilePath`,
  any path-bearing fields. Zero `$HOME`-relative paths needed.

**Adopter override pattern:** cmux config is single-file (no merge layer).
If adopters customize, the install becomes a real file → next install.sh
run triggers `link_file()` → `mv $dst → ${dst}.bak` → adopter's edits
preserved as `cmux.json.bak`. Documented as expected behavior.

---

### Pinned file: `config/tmux.conf`

```tmux
# MonsterFlow tmux config — high-contrast cyan/grey theme
# Mirrors the dev-session.sh aesthetic. Zero $HOME-relative paths;
# all references are tmux-symbolic. Override locally via ~/.tmux.local.conf
# (sourced at the bottom if present).

# --- Prefix ---
# Ctrl-a is MonsterFlow's prefix (Ctrl-b conflicts with editors)
unbind C-b
set -g prefix C-a
bind C-a send-prefix

# --- General ---
set -g default-terminal "screen-256color"
set -g history-limit 50000
set -g mouse on
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on
set -sg escape-time 10

# --- Status bar (high-contrast, dark grey background, cyan accent) ---
set -g status on
set -g status-position bottom
set -g status-justify left
set -g status-style "bg=colour234,fg=colour250"
set -g status-left  "#[fg=colour51,bold] #S #[default]"
set -g status-left-length 20
set -g status-right "#[fg=colour244]%Y-%m-%d %H:%M "
set -g status-right-length 30

# Active window: cyan background; inactive: dark grey
setw -g window-status-current-style "bg=colour51,fg=colour234,bold"
setw -g window-status-current-format " #I:#W "
setw -g window-status-style          "bg=colour234,fg=colour250"
setw -g window-status-format         " #I:#W "

# --- Pane borders (cyan = active, grey = inactive) ---
set -g pane-border-style        "fg=colour240"
set -g pane-active-border-style "fg=colour51"

# --- Sane keybindings ---
# Split with current pane's path
bind '"' split-window -v -c "#{pane_current_path}"
bind  %  split-window -h -c "#{pane_current_path}"
# Reload config
bind r source-file ~/.tmux.conf \; display-message "tmux.conf reloaded"
# Vim-style pane navigation
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R

# --- Local override hook ---
# Adopter can drop personal tweaks in ~/.tmux.local.conf without
# editing this file (which is a symlink into the MonsterFlow repo).
if-shell "[ -f ~/.tmux.local.conf ]" "source-file ~/.tmux.local.conf"
```

**Rationale:**
- Prefix `C-a` matches Justin's existing config (per CLAUDE.md tmux section)
  and is widely-used outside MonsterFlow — no surprise for tmux users.
- Colors use 256-color palette codes (`colour234` = dark grey, `colour51` =
  cyan, `colour250` = light grey, `colour240` = mid grey, `colour244` = mid-light
  grey). All standard 256-color, no truecolor escape sequences (works on
  legacy terminals too).
- `default-terminal screen-256color` is the lowest-common-denominator
  that works in both Apple Terminal and Ghostty/cmux.
- `~/.tmux.local.conf` source-hook gives adopters an override path
  without touching the symlinked file (parallel to bash/zsh `.local` rc
  conventions).
- **Zero absolute paths.** `~/.tmux.conf` and `~/.tmux.local.conf` are
  the only filesystem references — both are `~`-prefixed.
- **No `bind-key` to scripts in `~/Projects/...`** — would be a leak.

---

### Pinned file: `config/zsh-prompt-colors.zsh`

```zsh
# MonsterFlow prompt colors — sourced from ~/.zshrc inside a sentinel block.
# Theme-only. No behavioral changes (no aliases, no completion tweaks, no
# PATH edits). Override locally by re-defining MONSTERFLOW_PROMPT_* vars
# AFTER the sentinel block in ~/.zshrc.

# Color palette (matches config/tmux.conf — cyan/grey high-contrast)
typeset -g MONSTERFLOW_PROMPT_USER_COLOR="${MONSTERFLOW_PROMPT_USER_COLOR:-51}"   # cyan
typeset -g MONSTERFLOW_PROMPT_HOST_COLOR="${MONSTERFLOW_PROMPT_HOST_COLOR:-244}"  # mid-light grey
typeset -g MONSTERFLOW_PROMPT_PATH_COLOR="${MONSTERFLOW_PROMPT_PATH_COLOR:-250}"  # light grey
typeset -g MONSTERFLOW_PROMPT_GIT_COLOR="${MONSTERFLOW_PROMPT_GIT_COLOR:-178}"    # gold
typeset -g MONSTERFLOW_PROMPT_ERR_COLOR="${MONSTERFLOW_PROMPT_ERR_COLOR:-203}"    # soft red

# Minimal git-branch helper (no plugins required; safe outside git repos)
_monsterflow_git_branch() {
    local branch
    branch="$(git symbolic-ref --short HEAD 2>/dev/null)" || return 0
    print -n " %F{${MONSTERFLOW_PROMPT_GIT_COLOR}}(${branch})%f"
}

# Enable command substitution in PROMPT
setopt PROMPT_SUBST

# Two-line prompt:
#   user@host  ~/path  (branch)
#   ❯
# Last exit-code colorizes the ❯ glyph (cyan on success, soft red on failure).
PROMPT='%F{${MONSTERFLOW_PROMPT_USER_COLOR}}%n%f@%F{${MONSTERFLOW_PROMPT_HOST_COLOR}}%m%f  %F{${MONSTERFLOW_PROMPT_PATH_COLOR}}%~%f$(_monsterflow_git_branch)
%(?.%F{${MONSTERFLOW_PROMPT_USER_COLOR}}.%F{${MONSTERFLOW_PROMPT_ERR_COLOR}})❯%f '
```

**Rationale:**
- All colors are 256-palette codes matching `tmux.conf` for visual
  cohesion (cyan accent, grey baseline).
- Override-by-env: adopter can re-export any `MONSTERFLOW_PROMPT_*_COLOR`
  AFTER the sentinel block — no need to fork the file.
- `git symbolic-ref --short HEAD` is git's blessed branch-name path;
  silent-fails outside a repo (`|| return 0`).
- **No PATH manipulation, no `alias`, no `compinit`, no plugin manager
  hooks.** Pure prompt theme. This is a hard invariant — changing it
  expands what an adopter has to trust.
- **No `$(date)`-in-prompt** or other per-render shell-outs that would
  measurably slow `cd` (git branch is the only one, and zsh handles it
  cheaply).

---

### Pinned `.zshrc` sentinel block (exact bytes appended)

Appended once to `~/.zshrc`. `install.sh` checks for `BLOCK_BEGIN`
sentinel via `grep -qF` before appending — same pattern as the
persona-metrics gitignore block (install.sh:243-275).

```zsh

# BEGIN MonsterFlow theme
# Auto-added by MonsterFlow install.sh. Re-running install.sh is idempotent.
# To remove: delete the lines between BEGIN/END MonsterFlow theme markers.
[ -f "REPO_DIR_PLACEHOLDER/config/zsh-prompt-colors.zsh" ] && source "REPO_DIR_PLACEHOLDER/config/zsh-prompt-colors.zsh"
# END MonsterFlow theme
```

Where `REPO_DIR_PLACEHOLDER` is replaced at write-time by `$REPO_DIR`
(the realpath of `install.sh`'s dirname). The leading blank line is
intentional — separates the block from prior `.zshrc` content.

**Sentinel constants (used by tests, doctor.sh, future uninstall):**

```bash
ZSHRC_BLOCK_BEGIN="# BEGIN MonsterFlow theme"
ZSHRC_BLOCK_END="# END MonsterFlow theme"
```

**Idempotency rule:** if `grep -qF "$ZSHRC_BLOCK_BEGIN" ~/.zshrc` returns
0, skip the append entirely. Never edit-in-place; always all-or-nothing
block append. (Hand-edited blocks between the markers are NOT touched —
adopter wins on within-block customization, but the price is they don't
get block-content updates from later install.sh runs without first
deleting the block.)

---

### Pinned: `.monsterflow.tmp` SIGINT cleanup convention

All atomic writes performed by `install.sh` and `scripts/onboard.sh` use
the suffix `.monsterflow.tmp`:

```bash
write_atomic() {
    local dst="$1" content="$2"
    local tmp="${dst}.monsterflow.tmp"
    printf '%s' "$content" > "$tmp"
    mv "$tmp" "$dst"
}
```

Cleanup trap (install.sh + onboard.sh):

```bash
cleanup_partial() {
    find "$REPO_DIR" "$CLAUDE_DIR" "$HOME/.config/cmux" \
        -maxdepth 4 -name '*.monsterflow.tmp' -delete 2>/dev/null || true
    echo "" >&2
    echo "⚠ install.sh interrupted; partial state cleaned up." >&2
    exit 130
}
trap cleanup_partial INT TERM
```

**Why `.monsterflow.tmp` and not `.tmp`:** prevents collision with any
adopter's existing `.tmp` files anywhere in `$REPO_DIR` or `~/.claude/`.
The compound suffix (period-separated) survives `basename` operations
and is greppable. `-maxdepth 4` is a safety net so `find` can't run
away on a misconfigured `$HOME`.

---

### Pinned: migration-detect target patterns

```bash
# Match patterns for "this symlink points at a prior MonsterFlow install"
case "$PRIOR_TARGET" in
    */MonsterFlow/*|*/claude-workflow/*) PRIOR_INSTALL=1 ;;
    *) PRIOR_INSTALL=0 ;;
esac
```

**Rationale:** `claude-workflow` is the pre-rebrand name (per
`project_monsterflow_rebrand.md` memory — renamed 2026-05-01, symlink at
`~/Projects/claude-workflow` kept). Both substrings catch the legitimate
prior-install paths regardless of where the adopter cloned. Anything
else (e.g. a hand-rolled symlink to `/tmp/spec.md`) falls through to
"not a prior install" and skips the migration banner.

**What we do NOT match:**
- Bare `*/spec.md` (matches everything — false positives on any symlink).
- Specific version paths (`*/v0.4*` — too narrow; misses dev installs).
- Exact `$HOME/Projects/...` (Justin-machine-specific; would miss
  adopters who clone elsewhere).

The detection symlink target is `~/.claude/commands/spec.md` specifically
(the canonical install marker — has been part of every MonsterFlow
release since v0.1).

---

### Pinned: `.last-graphify-run` sentinel location

```
~/.local/share/MonsterFlow/.last-graphify-run
```

**Why this path:**
- XDG Base Directory spec compliance (`$XDG_DATA_HOME` defaults to
  `~/.local/share`).
- `MonsterFlow/` namespace prevents collision with other tools' state.
- Hidden filename (`.`-prefix) keeps it out of `ls` clutter for adopters
  who poke around in `~/.local/share/`.
- Single-purpose: only `bootstrap-graphify.sh` writes it; only
  `scripts/onboard.sh` reads it.

**Format:** empty file. mtime is the only signal. `touch` on success,
read via `find ... -mtime -7` (used by onboard.sh in the
"offer graphify if not run in last 7 days" gate).

```bash
GRAPHIFY_SENTINEL="$HOME/.local/share/MonsterFlow/.last-graphify-run"

# Read (in onboard.sh):
should_offer_graphify() {
    [ ! -f "$GRAPHIFY_SENTINEL" ] && return 0   # never run → offer
    # Re-offer if last run was >7 days ago
    [ -n "$(find "$GRAPHIFY_SENTINEL" -mtime +7 2>/dev/null)" ]
}

# Write (in bootstrap-graphify.sh, on success):
mkdir -p "$(dirname "$GRAPHIFY_SENTINEL")"
touch "$GRAPHIFY_SENTINEL"
```

**Migration:** if `bootstrap-graphify.sh` doesn't currently write this
sentinel, /build adds the touch line. Pre-existing graphify users who
upgrade will see one extra prompt on first onboard — acceptable
one-time cost.

---

### Pinned: Brewfile final shape (post-/build)

```ruby
# MonsterFlow — Homebrew dependency manifest
#
# Usage:
#   brew bundle --file=Brewfile           # install everything below
#   brew bundle check --file=Brewfile     # report missing without installing
#   brew bundle cleanup --file=Brewfile   # show what's installed but not listed
#
# Tier semantics mirror install.sh:
#   REQUIRED    — pipeline cannot function without these
#   RECOMMENDED — features degrade silently when absent (hooks no-op,
#                 /autorun can't make PRs, etc.)
#   OPTIONAL    — silent-skip features when absent; not in this Brewfile,
#                 install on demand (tmux for headless autorun, etc.)
#
# Not managed here:
#   - claude (Claude Code CLI) — install from https://claude.com/claude-code
#   - codex (OPTIONAL adversarial reviewer) — npm i -g @openai/codex
#   - tmux (OPTIONAL — only needed for legacy headless autorun flow;
#           brew install tmux on demand)
#
# Adopters who want a no-install dry run: pass --no-install to install.sh.

# --- REQUIRED ---
brew "git"
brew "python@3.11"

# --- RECOMMENDED ---
brew "gh"          # /autorun PR ops; gh auth login required after install
brew "shellcheck"  # PostToolUse hook on .sh edits
brew "jq"          # PostToolUse hook on .json edits
cask "cmux"        # Ghostty-based terminal for AI agents (vertical tabs);
                   # config at ~/.config/cmux/cmux.json
```

**Diff vs current Brewfile:**
- ADD: `cask "cmux"` (note: `cask` not `brew` — cmux ships as a
  homebrew-cask, not a formula; per Codex review finding #20).
- REMOVE: `brew "tmux"` (demoted to OPTIONAL per spec scope).
- UPDATE: header comments to name OPTIONAL tier and mention `cmux` config
  path.

**Why `cmux` is a cask, not a formula:** cmux ships as a macOS `.app`
bundle (it's a Ghostty-based GUI terminal). Homebrew uses `cask` for
GUI apps and `brew` for CLI binaries. Using `brew "cmux"` would fail
with a tap-not-found or formula-not-found error.

---

## Constraints Identified

- **`cmux.json` schema is owned by manaflow-ai/cmux upstream.** If they
  rename `branchLayout` or change `notifications.sound` enum values, our
  shipped config breaks silently (cmux would log + use defaults). Mitigation:
  CI test that asserts `jq -e '.sidebar.branchLayout, .app.appearance' config/cmux.json`
  succeeds — catches gross schema drift but not key renames. Out of scope for
  this spec to monitor cmux upstream.
- **`tmux.conf` 256-color palette is fixed.** True-color support varies by
  terminal; we deliberately stay at 256-color for portability. Adopters with
  truecolor terminals see no benefit, but no breakage either.
- **`.zshrc` source line is path-coupled to `$REPO_DIR`.** Moving the repo
  after install breaks the source line. Doctor.sh should detect this (read
  the sentinel block, verify path exists). Adding doctor.sh check is in
  scope for /build.
- **Sentinel block is opaque to upgrades.** Future install.sh that wants to
  ship a new theme variable would need a "rewrite block if version mismatch"
  pass — out of scope for v1; documented in sentinel comment ("re-running
  install.sh is idempotent" implies it does NOT mutate existing block content).
- **`.monsterflow.tmp` find scope is `-maxdepth 4`.** Deeply-nested temp files
  (>4 levels under `$REPO_DIR` or `$CLAUDE_DIR`) won't be cleaned. Acceptable;
  no production code writes that deep.
- **Migration detection is one-shot per install.** If the adopter aborts the
  upgrade prompt, next run shows the prompt again — no "I declined" sentinel.
  This is intentional (declining once shouldn't lock you out of upgrading later).

## Open Questions

- **Q1 (deferred to /build):** Should `tmux.conf` set `set -g default-shell`
  explicitly to `$SHELL`, or rely on tmux's default? Recommendation: omit;
  tmux's default behavior (inherit invoking shell) is correct for adopters,
  and forcing `$SHELL` would break the rare case of an adopter running tmux
  from a non-default shell. /build can revisit if test 6d uncovers an edge.
- **Q2 (deferred to /build):** `cmux.json` includes `$schema` URL pointing at
  GitHub raw — purely cosmetic (helps editors validate). If we want zero-network
  even in editor preview, drop the `$schema` line. Recommendation: keep it.
  cmux itself doesn't fetch the URL; only adopter's editor would, and only on
  manual edit. Audit-clean either way.
- **Q3 (passed up to /plan synthesis):** Spec lists `~/.config/cmux/cmux.json`
  as the symlink target. If an adopter has cmux already configured (existing
  real `cmux.json`), `link_file()` will move it to `cmux.json.bak`. Should
  install.sh print a louder warning ("BACKED UP YOUR EXISTING CMUX CONFIG —
  review cmux.json.bak before running cmux next") vs the existing one-line
  `BACKUP:` notice? Recommendation: keep the existing one-line notice (matches
  tmux/zshrc pattern; consistency over special-casing).

## Integration Points

- **with api persona:** No HTTP endpoints. Brewfile and config files are
  inert artifacts — install.sh shells out to `brew bundle install`,
  `bash scripts/onboard.sh`, etc. The "API" surface is the install.sh flag
  set (covered by api persona's flag-parsing recommendation).
- **with ux persona:** Onboard panel substring assertions (`/flow`, `/spec`,
  `dashboard/index.html`) and the `╭─╮│╰─╯` box-drawing depend on this
  data-model output exposing `~/.local/share/MonsterFlow/` as the
  graphify-sentinel root (so onboard's "offer indexing" gate has the right
  path to check).
- **with security persona:** Every config file in this design uses only
  `$HOME`-relative paths and contains zero `curl|bash`-style remote fetches.
  The cmux.json `$schema` URL is the only network-adjacent string and is
  read by no MonsterFlow code (only by adopter's editor on manual edit, if
  they have a JSON-schema-aware editor). Security persona should verify the
  sentinel-block source line cannot be hijacked (e.g., what happens if
  `$REPO_DIR/config/zsh-prompt-colors.zsh` is later replaced by a malicious
  file? Answer: it's a symlink from a git-tracked path under the user's own
  repo — same trust boundary as install.sh itself; not a new attack surface).
- **with testing persona:** Pinned sentinel constants
  (`ZSHRC_BLOCK_BEGIN`, `GRAPHIFY_SENTINEL` path, `.monsterflow.tmp`
  suffix) become test fixtures. Test 1 (idempotency) greps for
  `BEGIN MonsterFlow theme`; test 2 (fast no-op) checks
  `[ -L ~/.tmux.conf ]`; test 7 (TTY gating) reads
  `~/.local/share/MonsterFlow/.last-graphify-run` mtime; test 8 (migration)
  pre-stages a symlink with `*/MonsterFlow/*` in its target.
- **with versioning persona:** Migration banner hardcodes "v0.5.0" as the
  target version. If versioning persona recommends a different bump
  (per spec Open Q3), every "v0.5.0" string in `print_upgrade_message`
  needs updating. Source `$VERSION` from the `VERSION` file at runtime
  instead — recommendation: replace literal "v0.5.0" with `${VERSION}`
  expansion in the migration banner.

## Sources

- cmux configuration docs: https://cmux.com/docs/configuration (verified
  `~/.config/cmux/cmux.json` path and schema keys)
- cmux GitHub: https://github.com/manaflow-ai/cmux (verified cask shipping
  model)
- Existing install.sh patterns:
  `link_file()` (lines 91-100), persona-metrics sentinel block
  (lines 243-275), `has_cmd()` (lines 21-25)
- Memory: `project_monsterflow_rebrand.md` (claude-workflow → MonsterFlow,
  2026-05-01)
- Memory: `feedback_install_adopter_default_flip.md` (sentinel-bracketed
  gitignore pattern that this design extends to `.zshrc`)
