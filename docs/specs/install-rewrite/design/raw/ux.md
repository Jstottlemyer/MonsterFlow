# UX Design — install-rewrite

## Key Considerations

**Audience split is asymmetric.** Owner runs install.sh ~weekly, knows every prompt cold, wants zero friction. Adopter runs it once on day-zero, has no context, wants legible signposts. CI runs it never-interactively, wants exit codes and silence. The prompt text must read clearly to the adopter (the rarest and most fragile audience) without insulting the owner (most frequent).

**Terminal real estate is 80 columns.** macOS Terminal.app default is 80×24. iTerm2 / Ghostty / cmux default wider but adopters running over SSH or in tmux panes routinely live at 80. Every box-drawn panel must fit in 78 chars (room for `│` on each side). Every prompt and notice must wrap cleanly under 80.

**Box-drawing has a real failure mode.** macOS Terminal.app + iTerm2 + Ghostty + cmux render `╭─╮│╰─╯` correctly with the default mono fonts. But: SSH sessions through screen/tmux without `LANG=*.UTF-8`, `script -q` capture for tests, copy-paste into GitHub issues, and minicom/serial consoles all degrade to `??????`. The spec says "degrades acceptably to garbage." That is the right call **only if the panel's information survives**. The fix: keep box-drawing, but pin the panel content as plain readable lines so a degraded render is still a usable instruction list.

**Glyph budget.** Spec already uses `✓ ✗ ⚠ ○ ⬆ ╭─╮│╰─╯`. That is the maximum. Don't add `•` (status-bar bullet), `→` (arrow — already in `BACKUP:` / `LINKED:` lines), `🔧` or any emoji. Glyphs are load-bearing for tier signaling — overuse dilutes them.

**Prompt rhythm.** Existing install.sh has 4 prompts (`Continue anyway?`, `Copy baseline template?`, `Install required plugins?`, `Run test suite?`). Spec adds 2-4 more (`Proceed? [Y/n]` for brew bundle, `Install MonsterFlow shell theme? [y/N]` for adopter, `Proceed with upgrade? [Y/n]` for migration, `Index ~/Projects/?` for onboard). For a fresh-Mac adopter that is up to 8 yes/no decisions on first run. UX rule: every prompt must answerable from the line above without scrolling. No multi-paragraph preambles before a `[Y/n]:`.

**Default-letter capitalization carries meaning.** `[Y/n]` = enter accepts (safe / expected). `[y/N]` = enter declines (mutating / opt-in). This convention is already used in install.sh — preserve it. Theme prompt is `[y/N]` (mutating), upgrade prompt is `[Y/n]` (expected continuation), brew install is `[Y/n]` (expected — they re-ran intending to install).

**Reversibility messaging.** Adopter's biggest fear: "what did this script just do to my dotfiles?" The theme stage is the riskiest mutation. Every theme line MUST print the disk effect inline (existing `BACKUP:` / `LINKED:` pattern handles this). The `.zshrc` append must show the sentinel block lines so the adopter can find and remove them later. No silent appends.

## Options Explored

### Option A: Keep panel boxes, no ASCII fallback
Preserve `╭─╮│╰─╯` everywhere. Document in README that legacy terminals will see garbage but the script still works. **Pro:** simplest implementation, single render path, modern terminals look polished. **Con:** the one place an adopter hits a degraded terminal (a CI log they're inspecting after a failed run) is exactly when they need the panel content most. **Effort:** zero — already specced.

### Option B: Detect terminal capability, dual-render
Check `$TERM` / `tput`-driven UTF-8 detection, fall back to ASCII (`+----+ | | +----+`) when degraded. **Pro:** cleanest output everywhere. **Con:** detection is fragile (LANG vs LC_ALL vs locale charmap; SSH-forwarded `$TERM=xterm` lies about UTF-8); adds branching to the one panel-render function; tests now have two renderings to assert. **Effort:** ~30 lines + test cases.

### Option C: Plain-text panel only, no box-drawing
Use a horizontal rule (`---`) and indented bullets, no box. **Pro:** survives every terminal; trivial to test (substring grep needs no box-char escaping). **Con:** loses the visual "this is a discrete panel" affordance that helps a tired adopter spot the next-steps section in a long install scrollback. **Effort:** trivial.

### Option D (recommended): Box-drawing with content-survives-degrade discipline
Keep `╭─╮│╰─╯` panels, but commit to a panel-content invariant: every line inside the box must be readable as plain text if the box chars render as `?`. No box-char-dependent layout (no centering that requires the corners, no ASCII art). The acceptance test (`grep '/flow' onboard-output.txt`) already enforces this for the onboard panel — extend it conceptually to every panel. **Pro:** modern terminals look good, degraded terminals stay usable, no detection logic. **Con:** discipline-based, not enforced. **Effort:** zero implementation; just a content rule the panel-text drafts already follow.

## Recommendation

Adopt Option D. Pin every user-visible string below. Each string is reviewed for: ≤80 cols when rendered, no box-char-load-bearing layout, glyph used per tier convention, default-letter capitalization correct, no emoji.

### Stage 0 — Linux guard (stderr; exit 1)

```
MonsterFlow install.sh is macOS-only.
Linux support is tracked in BACKLOG.md as out-of-scope for v1.
If you need Linux, please open an issue with your use case.
```

(3 lines, all stderr. Third line is new vs spec — gives the Linux user an action instead of a dead end. Cost: 1 line. Worth it.)

### Stage 1 — Header (unchanged from existing install.sh, kept verbatim for owner muscle memory)

```
=== Claude Workflow Pipeline Installer — v0.5.0 ===

Repo:   /Users/<user>/Projects/MonsterFlow
Target: /Users/<user>/.claude

```

### Stage 3 — Migration detect (v0.4.x → v0.5.0)

When prior install detected, print BEFORE detection panel, BEFORE any mutation:

```
⬆ Detected prior MonsterFlow install — upgrading to v0.5.0.

  What's new in v0.5.0:
    - install.sh now installs brew tools for you (was: warn-only)
    - Optional shell theme (~/.tmux.conf, cmux config, prompt colors)
    - New flags: --no-install, --no-theme, --non-interactive
    - cmux added to RECOMMENDED; tmux moved to OPTIONAL
    - macOS-only (Linux guard added)

  See CHANGELOG.md for full details.

Proceed with upgrade? [Y/n]:
```

(Exactly 5 bullets per acceptance test 8. Default `[Y/n]` because the user already typed `./install.sh` knowing this would run. Suppressed under `--non-interactive` — proceeds silently.)

### Stage 4 — Detection results (panel)

REQUIRED-missing panel format (extends existing install.sh formatting; preserves the `✗ REQUIRED — ...` heading and indented-list style adopters/owners already know):

```
✗ REQUIRED — pipeline will not work without these:
  - brew (Homebrew) — install from https://brew.sh:
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  - claude (Claude Code CLI) — https://claude.com/claude-code
  - git — install Xcode CLI tools (xcode-select --install) or brew install git
  - python3 — brew install python

Install these and re-run install.sh.
```

(Then `exit 1`. Format intentionally matches the existing install.sh REQUIRED-missing block — adopters who hit this twice see the same shape. The brew line is the only one with a 2-line install command; indent it 6 spaces under the bullet so it visually attaches.)

RECOMMENDED-missing panel:

```
✓ REQUIRED tools present
⚠ RECOMMENDED missing: gh, shellcheck, jq, cmux
```

(Single line summary when the count is short. If >4 missing, fall back to the bulleted form per existing install.sh convention.)

### Stage 5 — Brew bundle install prompt

Exact text:

```
About to install via Homebrew (uses Brewfile at repo root):
  - gh         (GitHub CLI — /autorun PR ops)
  - shellcheck (PostToolUse hook on .sh edits)
  - jq         (PostToolUse hook on .json edits)
  - cmux       (Ghostty-based terminal for AI agents — cask)

Proceed? [Y/n]:
```

(Tools right-padded to a common width — `gh` → 11 chars including padding so the parenthetical descriptions line up. The parenthetical names the WHY, not the WHAT — adopter needs to know "gh enables /autorun PR ops" more than "gh = GitHub CLI." Default `[Y/n]` because they already passed detection knowing tools are missing.)

If declined → loud notice (see below), continue.

### Stage 5 — Brew bundle failure message (stderr; exit 1)

```
⚠ brew bundle failed for some formulas.
  Re-run install.sh after fixing the underlying issue
  (network, brew tap auth, disk space, etc.).
  Symlinks were not created to avoid a half-installed state.
```

(4 lines, stderr. Names the likely failure causes so adopter has a starting place.)

### Stage 6 — Loud notice (RECOMMENDED-missing decline)

Spec defined this; refining for fit and stream:

- Glyph: `⚠`
- Stream: stderr
- Single emit at decline-time; NOT repeated at exit
- Exit code: 0

Exact text:

```
⚠ Continuing without gh, shellcheck, jq, cmux.
  Features will silently no-op (PR ops, shellcheck hook, etc.).
  Re-run install.sh anytime to install.
```

(Three lines instead of spec's "one line + one line" — the missing-tool list breaks the 80-col limit when ≥4 tools are missing if kept on a single line. Wrapping at 3 lines keeps it readable while preserving the loud-notice character. Tool list is dynamically interpolated; keep `, ` joiner.)

### Stage 9 — Theme install prompt (adopter only; owner skips prompt)

Exact text:

```
Install MonsterFlow shell theme? [y/N]:
  Adds: ~/.tmux.conf, ~/.config/cmux/cmux.json, prompt colors in ~/.zshrc
  Existing files are backed up to .bak; .zshrc gets a sentinel-bracketed block
  you can remove later. No network calls; all source files in repo at config/.
```

(Default `[y/N]` because this MUTATES dotfiles — declining must be one-keystroke. Three indented lines below the prompt explain WHAT, the safety story, and the auditability story. This is the riskiest prompt for an adopter; the explanatory lines pay rent. Total height: 4 lines.)

### Theme stage output (each line printed as the action happens)

```
  BACKUP: ~/.tmux.conf → ~/.tmux.conf.bak  (existing real file preserved)
  LINKED: ~/.tmux.conf → /Users/<user>/Projects/MonsterFlow/config/tmux.conf
  LINKED: ~/.config/cmux/cmux.json → /Users/<user>/Projects/MonsterFlow/config/cmux.json
  APPENDED: ~/.zshrc (sentinel block: # BEGIN MonsterFlow theme … # END MonsterFlow theme)
```

(`APPENDED` is a new verb beyond the existing `BACKUP`/`LINKED` vocabulary — it accurately reflects that .zshrc is not a symlink. Sentinel literals are spelled in the message so a future grep finds them.)

### Stage 14 — Onboard panel (exact text; assertable substrings present)

```
╭─ MonsterFlow is ready ──────────────────────────────────────╮
│                                                              │
│  Next steps:                                                 │
│    1. cd into a project                                      │
│    2. /flow            — see the workflow card               │
│    3. /spec            — design your first feature           │
│    4. open ~/Projects/MonsterFlow/dashboard/index.html       │
│                                                              │
│  Optional:                                                   │
│    • Index ~/Projects/ for the dashboard? [y/N]              │
│    • Authenticate gh CLI now? (gh auth login)        [y/N]   │
│    • Want adversarial review? Run /codex:setup               │
│                                                              │
╰──────────────────────────────────────────────────────────────╯
```

(Width: 64 chars including borders — fits 80-col cleanly. Substrings `/flow`, `/spec`, `dashboard/index.html` present per acceptance test 7. Numbered list capped at 4 items — adopter scans, doesn't read; 4 is the comprehension cliff. The two `[y/N]` Optional bullets are ACTIVE prompts that gate on TTY; they print the prompt inline and ALSO `read -rp` separately below the panel — the panel is a preview, the prompts come after it for accessibility (screen readers handle `read` better than mid-panel input).)

After the panel:

```
  Index ~/Projects/ for the dashboard? [y/N]:
  Authenticate gh CLI now? (gh auth login) [y/N]:
```

(Each `read -rp` separately. Skipped under `--non-interactive`. Per spec the codex line is informational only — no prompt.)

### Stage 14 — Owner-mode onboard fast path

```
=== Everything already in place ===
```

(Single line. No panel re-print on owner re-runs when nothing changed — saves the noise. `doctor.sh` still runs silently; only its failures print. This is the "fast no-op under 3s" UX promise.)

### SIGINT cleanup message (stderr; exit 130)

```

⚠ install.sh interrupted; partial state cleaned up.
  Re-run when ready.
```

(Leading blank line so Ctrl-C's `^C` doesn't run together with the message. Two content lines, stderr. Exit 130 = bash convention for SIGINT.)

### `--no-install` notice (stderr; informational)

```
⚠ Skipped install per --no-install. Some features may be degraded.
```

(Single line. Exit code from this stage is 0 — bypass means bypass.)

### `--non-interactive` REQUIRED-missing message (stderr; exit 1)

```
✗ REQUIRED tools missing in non-interactive mode:
  - <tool list>
Pass --no-install to bypass enforcement, or install the tools and re-run.
```

(Names the escape hatch in the error message itself — CI operator does not have to read docs to recover.)

## Constraints Identified

- **80-column width is hard.** Every panel must fit in 78 chars of content + 2 chars border. Verified: header panel = 64 chars wide; REQUIRED-missing panel uses no box-borders so width is content-bound; brew-bundle prompt longest line is `  - cmux       (Ghostty-based terminal for AI agents — cask)` = 60 chars. All in budget.
- **Glyph set is fixed** at `✓ ✗ ⚠ ○ ⬆ ╭─╮│╰─╯ •`. The `•` (U+2022) is used inside the onboard panel's Optional list and renders correctly in every terminal we care about.
- **stdout vs stderr is load-bearing.** All success messages → stdout. All `⚠` notices and `✗` errors → stderr. CI logs that grep stderr for failure signals will work correctly.
- **Prompt count budget for adopter day-zero: 5.** brew install + theme install + onboard graphify + onboard gh-auth + (conditionally) v0.4.x upgrade. The existing CLAUDE.md baseline + plugins + run-tests prompts stack on top — total ceiling is ~8. That is the cap. If a future spec adds another prompt, something has to go.
- **Adopter sees the panel ONCE.** Owner sees it weekly. Optimize panel readability for the adopter; owner can tolerate any consistent format.
- **No emoji.** Per global CLAUDE.md and Justin's writing voice — emoji never ships in install output. Only the curated glyph set.

## Open Questions

1. **Should the onboard panel's `[y/N]` Optional bullets be visually distinguished from the numbered Next-steps?** Current design uses `•` for Optional and `1./2./3./4.` for Next steps. Alternative: prefix Optional with `?` to telegraph "this asks a question." Recommend keeping `•` — `?` would collide with the trailing `?` in the prompt sentences and create visual noise.
2. **Is `cmux` the right place to introduce non-mainstream tooling without a one-line "what is cmux" footnote?** A fresh adopter sees `cmux` in the brew-install list and the parenthetical says "Ghostty-based terminal for AI agents — cask" — that's self-explanatory enough for someone in this audience (already running Claude Code), but worth a confidence check. Recommend: keep current parenthetical; do not expand.
3. **Should the `APPENDED:` line in the theme stage be more verbose** (e.g., quote the actual two lines added)? Risk: it bloats the install scrollback. Benefit: total auditability. Recommend the current single-line summary; the sentinel literals in the message are enough for an adopter to grep their own .zshrc later.
4. **Does the migration message need a `[diff]` link or path** to a CHANGELOG.md anchor? Spec leaves this implicit. Recommend: keep the current `See CHANGELOG.md for full details.` line; if CHANGELOG.md is created in /build, the message stays accurate. If it isn't, the line still degrades gracefully (adopter checks the repo).
5. **Box-drawing fallback ever?** Recommendation: NO automated fallback (Option D). If a real adopter complaint comes in, revisit and add Option B. The content-survives-degrade discipline means adopters can still follow the panel even if the box is rendered as `?`.

## Integration Points

- **with api:** The flag surface (`--no-install`, `--install-theme`, `--no-theme`, `--non-interactive`, `--no-onboard`, `--force-onboard`) is the public API of install.sh. UX requires that flag-precedence be deterministic and documented in the prompt text when conflicts could be ambiguous (`--no-theme` wins over `--install-theme`). API persona owns parser semantics; UX owns the user-facing strings naming each flag.
- **with data-model:** Onboard panel substring assertions (`/flow`, `/spec`, `dashboard/index.html`) are a contract between UX text and acceptance-test grep patterns. The exact string "MonsterFlow is ready" is also a contract — test 7 / acceptance criteria #2 grep for it. Any rewording requires test update; this is the explicit "panel content has acceptance" gate the review called out.
- **with integration:** The `link_file()` reuse for the theme stage means the existing `BACKUP:` / `LINKED:` line format is the SAME format adopters see for command/persona/template symlinks. Consistency wins — adopter learns the format once at command-symlink time and recognizes it at theme-symlink time. The new `APPENDED:` verb extends the vocabulary minimally for `.zshrc`. The migration-detect flow integrates with the existing version-bump tag history (CHANGELOG.md) — if /plan's integration agent decides to auto-generate CHANGELOG.md from `git log v0.4.x..HEAD`, the migration message's "See CHANGELOG.md" line already points at it.
