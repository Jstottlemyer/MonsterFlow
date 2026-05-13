---
name: install-graphify-wiki-coverage
description: Add a Knowledge Layer stage to install.sh that detects graphify CLI, the six obsidian-wiki skills, OBSIDIAN_VAULT_PATH, Obsidian.app, and cmux config-without-binary drift; offers to install only the missing pieces; splits offerings into can-install-now vs manual-action-required so the prompt never overpromises; re-runs cleanly when state is already correct.
created: 2026-05-13
revised: 2026-05-13 (post-review rev1: fix graphify install per docs/graphify-usage.md authority, add Obsidian.app detection, fix CLI detection contradiction, hoist posix_quote, split prompt by actionability, AC tightening)
constitution: none — defaults-only roster (precedent: install-rewrite, pipeline-wiki-integration)
confidence: 0.90 (Scope 0.92 / UX 0.90 / Data 0.90 / Integration 0.90 / Edge 0.88 / Acceptance 0.90)
session_roster: defaults only (27 stock personas)
gate_mode: permissive
tags: [api, data, docs, integration, migration, scalability, security, ux]
tags_provenance:
  baseline: [api, data, integration, migration, scalability, security, ux]
  llm_added: [docs]
  user_overrides: []
---

# install-graphify-wiki-coverage Spec

*Session roster only — run /kickoff later to make this a persistent constitution.*

## Summary

`install.sh` today covers pipeline commands, personas, schemas, scripts, theme, brew tools, and plugins, but is silent on the knowledge layer the rest of MonsterFlow depends on: the `graphify` CLI (which installs its own skill via `graphify claude install`), the six `wiki-*` skills from `github.com/Ar9av/obsidian-wiki`, `OBSIDIAN_VAULT_PATH`, and Obsidian.app itself. Adopters who follow the install instructions end with a working pipeline but no knowledge surface; `/wrap` Phase 2c silently no-ops and `/spec` Phase 0.2 never fires. Suggesting the skills alone is incomplete — the skills point at a vault inside an app that may not be installed.

A parallel post-install drift case also lands here: `cmux` (a Brewfile cask) only installs when the adopter says Y to the brew bundle prompt, but the theme stage symlinks `~/.config/cmux/cmux.json` unconditionally — so a decline path leaves an orphaned cmux config pointing at a binary that doesn't exist. Same detection-and-report pattern, same idempotent re-run guarantee.

This spec adds one new stage — Knowledge Layer — that detects six pieces with a single summary banner, classifies each as **Ready** (✓ present), **Can install now** (install.sh can fix it in this run), or **Manual action required** (instructions printed; user runs them out-of-band), and only prompts when the Can-install-now bucket is non-empty so it never overpromises. Already-correct state is a zero-op no-prompt path. Adopter default is **prompt-default-N** (consistent with the existing plugin + theme adopter defaults); owner is **auto-yes**. cmux drift detection lives in this stage rather than `do_theme_install` because Knowledge Layer is the post-install drift surface for all knowledge-related state — keeping detections co-located lets the user read one summary block instead of two.

## Backlog Routing

Backlog: empty at time of spec — `BACKLOG.md` has no graphify/wiki items pending. The closest historical reference is `install-rewrite` v1.1's explicit scope-cut of wiki-export indexing from `onboard.sh`; this spec is the follow-up that reopens the surface with the right framing (install.sh-level detection, not skill execution from bash).

## Scope

### In scope

- New `do_knowledge_layer()` stage in `install.sh`, placed after `do_theme_install` (install.sh:714) and before the CLAUDE.md baseline merge (install.sh:716).
- Hoist `posix_quote` from inside `do_theme_install` (install.sh:694-697) to a top-level helper so `install_obsidian_env()` can call it under `--no-theme` (Knowledge Layer runs regardless of theme flag).
- Detects six pieces and prints one summary block:
  - **graphify CLI** — `command -v graphify` succeeds AND running it returns exit 0 on `--help`. The presence check is binary-on-PATH only — any working `graphify` (brew tap, pipx, manual install, the MonsterFlow-managed venv) counts as ✓. Eliminates the prior detection contradiction with EC1.
  - **Wiki skills (×6)** — all of `~/.claude/skills/{wiki-ingest,wiki-update,wiki-query,wiki-export,wiki-lint,wiki-capture}/SKILL.md`. These six are the MonsterFlow runtime-required set (pinned per Open Question #2 deferred for `/blueprint`); the upstream obsidian-wiki repo ships more.
  - **OBSIDIAN_VAULT_PATH** — `[ -f ~/.obsidian-wiki/config ]` AND a small parser (NOT `source`) extracts `OBSIDIAN_VAULT_PATH=` (handles optional `export` prefix, double quotes, literal `~` via `${VAR/#\~/$HOME}`) AND the resolved path is an existing directory. Soft warning if `.obsidian/` subdir is missing.
  - **Obsidian.app** — `[ -d /Applications/Obsidian.app ]`. App, not a brew formula or skill. Needed for the vault path to be meaningful.
  - **cmux drift** — `[ -L ~/.config/cmux/cmux.json ]` (theme stage created it; non-symlinks under that path are user-managed and out of scope) AND `command -v cmux` fails. Three states: ✓ both present (or both absent — N/A), ⚠ config present + binary absent (drift — the case this spec fixes), ○ neither (no theme, no concern).
  - **graphify skill is NOT a separate detection.** Installed by `graphify claude install` as part of CLI setup; covered by the CLI detection. (Closes Open Question #1 from rev0.)
- Per-piece status classification (Codex's doctor + fixer reshape):
  - **Ready** (✓): all detection checks passed. No action.
  - **Can install now**: install.sh has an automated install action it can run in this stage. Pieces: graphify CLI, OBSIDIAN_VAULT_PATH config + zsh export, Obsidian.app.
  - **Manual action required**: install.sh prints exact commands; user runs them out-of-band. Pieces: wiki skills (`npx skills add ...`), cmux drift (`brew install --cask cmux`).
- Single batched prompt fires ONLY when the Can-install-now bucket is non-empty: `Install <list of Can-install-now pieces>? [y/N]`. Owner auto-yes; adopter default-N. When the only gaps are in Manual-action-required, instructions print but no prompt fires — the user can't say yes to something install.sh can't do.
- Per-piece install actions (Can-install-now bucket, gated on missing-only — no clobber):
  - **graphify CLI**: `python3 -m venv ~/.local/venvs/graphify && ~/.local/venvs/graphify/bin/pip3 install "graphifyy[mcp]" && ln -sf ~/.local/venvs/graphify/bin/graphify ~/.local/bin/graphify && graphify claude install`. Note the `[mcp]` extras and the double-y in `graphifyy` (per `docs/graphify-usage.md:39,141`; `pip install graphify` single-y is an unrelated package and is a known footgun). The `graphify claude install` step writes `~/.claude/skills/graphify/SKILL.md` + the PreToolUse hook + the CLAUDE.md pointer section, so the skill comes free with the CLI install. Refuse the venv create if `~/.local/venvs/graphify` already exists with non-empty contents. If venv dir exists but the `~/.local/bin/graphify` symlink is missing, re-create only the symlink (don't re-pip-install, don't re-run `graphify claude install`).
  - **OBSIDIAN_VAULT_PATH**: prompt for vault path with sane default (`~/Documents/Obsidian/wiki`), validate it resolves to an existing directory, soft-warn if `.obsidian/` subdir is missing (still proceed — user might not have opened the vault yet), write `~/.obsidian-wiki/config` with `OBSIDIAN_VAULT_PATH="<path>"` if missing, and append a sentinel-bracketed block to `~/.zshrc` exporting `OBSIDIAN_VAULT_PATH` (uses the now-top-level `posix_quote` + sentinel block pattern from theme stage). Under non-interactive owner mode with no discoverable default (vault dir not present), skip the env-write entirely with stderr notice ("vault path not configured; set OBSIDIAN_VAULT_PATH manually and re-run") — do NOT block, do NOT write a guessed value.
  - **Obsidian.app**: `brew install --cask obsidian`. The cask exists upstream (`brew info --cask obsidian` resolves); not currently in MonsterFlow's Brewfile. install.sh shells out to brew here rather than re-running brew bundle (the bundle stage is committed by the time we're in `do_knowledge_layer`; one-off cask install is the minimum viable action).
- Per-piece manual-action instructions (Manual-action-required bucket, print-only):
  - **Wiki skills**: print `Run: npx skills add Ar9av/obsidian-wiki` (upstream installer is idempotent, handles all 6). install.sh does NOT auto-exec npx (long-running, interactive, can prompt for network credentials). Fallback when `command -v npx` fails: print the manual `git clone https://github.com/Ar9av/obsidian-wiki && cp -r .skills/* ~/.claude/skills/` recipe.
  - **cmux drift**: print `Run: brew install --cask cmux  # restores the cask the Brewfile already lists`. install.sh does NOT auto-exec brew here (adopter already declined the brew bundle prompt earlier in this same install run — re-prompting is annoying). Owner-auto-yes still surfaces the recommendation but doesn't re-attempt the install either.
- Idempotency: re-runs against already-correct state print `Knowledge Layer: all present ✓` and emit zero prompts, zero filesystem writes, zero `.bak` files, zero `.zshrc` mutations.
- `tests/test-install-knowledge-layer.sh` wired into `tests/run-tests.sh` TESTS array (append after all existing entries; orchestrator-wiring guard at `run-tests.sh` enforces the disk-vs-array count check).
- Test seam: gate the venv install action and `brew install --cask obsidian` invocation behind `MONSTERFLOW_INSTALL_TEST=1` (existing env knob) — under tests, mock the binary/cask install at the harness layer rather than spending real time on `pip install` or brew network calls.

### Out of scope

- Vendoring the wiki skills into MonsterFlow's `skills/` directory and symlinking them like first-party content. Wiki skills belong to `github.com/Ar9av/obsidian-wiki` (no MonsterFlow author rights, no documented license-compat path); install.sh suggests the upstream installer instead.
- Running `bootstrap-graphify.sh --apply` from `install.sh`. The bootstrap installs launchd agents, post-commit hooks across `~/Projects/*`, and seeds dashboard JSONL — much larger blast radius than the install.sh "detect → install → verify" envelope, and it spends real LLM tokens on graphify's extract pass. Stays as a separate user-invoked one-shot.
- Auto-cloning `github.com/Ar9av/obsidian-wiki` to a fixed path. Skill install is upstream's responsibility.
- Bringing back the wiki-export indexing that `install-rewrite` v1.1 explicitly cut from `onboard.sh`. The skill execution surface stays in `/wrap` Phase 2c where it already lives.
- Detection of graphify per-project graphs (`graphify-out/`). That's a project-level concern; `bootstrap-graphify.sh` handles it.
- Re-running brew bundle from inside `do_knowledge_layer` to recover from a declined brew bundle prompt. The user said no once already in the same install run — pestering them is poor UX. We surface the gap, they re-run install.sh (or invoke `brew install --cask cmux` directly) when ready. (Note: the Obsidian.app one-off `brew install --cask obsidian` is NOT considered "re-running brew bundle" — it's a single targeted cask install with no bundle-level side effects.)
- Removing the orphaned `~/.config/cmux/cmux.json` symlink. It's not harmful (the file just dangles) and removing it would force a re-symlink on next install — more churn than benefit.
- Creating an Obsidian vault if one doesn't exist. Obsidian.app's own first-run flow handles vault creation. install.sh detects the app + asks for an existing vault path; if the user doesn't have one yet, the env-write skips with a notice.
- Adding `obsidian` cask to the existing `Brewfile`. The Knowledge Layer stage takes ownership of this install path; bundling it into `brew bundle` would re-prompt under the existing brew-bundle "Proceed?" gate and add nothing over the targeted install.

## Approach

N/A — small change.

## Roster Changes

N/A — small change. Defaults-only roster covers this surface.

## UX / User Flow

**First-run on a clean adopter machine (none of the six pieces present):**

```
[... theme stage output ...]

=== Knowledge Layer ===
graphify CLI:        ✗ (not installed)
wiki skills:         ✗ (0/6)            [manual action required]
OBSIDIAN_VAULT_PATH: ✗ (~/.obsidian-wiki/config absent)
Obsidian.app:        ✗ (not in /Applications)
cmux drift:          ○ N/A (no theme config present)

Can install now: graphify CLI, OBSIDIAN_VAULT_PATH, Obsidian.app
Manual action required: wiki skills

Install the 3 pieces install.sh can handle? [y/N]: y

Installing graphify CLI...
  RUNNING: python3 -m venv ~/.local/venvs/graphify
  RUNNING: ~/.local/venvs/graphify/bin/pip3 install "graphifyy[mcp]"
  LINKED:  ~/.local/bin/graphify → ~/.local/venvs/graphify/bin/graphify
  RUNNING: graphify claude install
  ✓ graphify CLI installed (skill + PreToolUse hook installed by `graphify claude install`)

Installing Obsidian.app...
  RUNNING: brew install --cask obsidian
  ✓ Obsidian.app installed

Configuring OBSIDIAN_VAULT_PATH...
  Vault path [~/Documents/Obsidian/wiki]: <enter to accept default>
  Path resolves to existing directory: ✓
  Soft warning: .obsidian/ subdir not found — open Obsidian.app and create the vault there to finish.
  WROTE:    ~/.obsidian-wiki/config
  APPENDED: ~/.zshrc (sentinel-bracketed OBSIDIAN_VAULT_PATH export)
  ✓ Obsidian env configured

Manual action required:
  wiki skills (0/6 installed):
    npx skills add Ar9av/obsidian-wiki
    # Fallback if npx unavailable:
    git clone https://github.com/Ar9av/obsidian-wiki ~/Projects/obsidian-wiki
    cp -r ~/Projects/obsidian-wiki/.skills/* ~/.claude/skills/

=== Knowledge Layer setup complete ===
Run the wiki skills command in a separate terminal to finish the knowledge layer.
```

**Re-run after everything is present:**

```
[... theme stage output ...]

=== Knowledge Layer ===
graphify CLI:        ✓
wiki skills:         ✓ (6/6)
OBSIDIAN_VAULT_PATH: ✓ → /Users/jstottlemyer/Documents/Obsidian/wiki
Obsidian.app:        ✓ (/Applications/Obsidian.app)
cmux drift:          ✓ (config + binary both present)

Knowledge Layer: all present ✓
```

No prompt, no mutations.

**cmux drift case (theme installed, brew bundle declined):**

```
=== Knowledge Layer ===
graphify CLI:        ✓
wiki skills:         ✓ (6/6)
OBSIDIAN_VAULT_PATH: ✓ → /Users/jstottlemyer/Documents/Obsidian/wiki
Obsidian.app:        ✓ (/Applications/Obsidian.app)
cmux drift:          ⚠ config present but binary absent

The theme stage symlinked ~/.config/cmux/cmux.json, but cmux itself
isn't installed. The brew bundle prompt was declined earlier in this
run. To restore the cask:

  brew install --cask cmux

Re-run install.sh after to clear this warning.
```

Single batched prompt does NOT fire for cmux drift alone (it's a print-only diagnostic, no install action this stage can take).

**Adopter under `--non-interactive`:**

Summary block renders normally; the `Install missing pieces?` prompt is skipped (default-N behavior), no installs happen, no env writes. Re-run interactively to install.

**Owner (`MONSTERFLOW_OWNER=1` or `PWD == REPO_DIR` with `script_dir == git_root`):**

Same summary block. The `Install missing pieces?` prompt is auto-yes — installs proceed without confirmation.

## Data & State

**Files created (when user opts in to the Can-install-now pieces):**

- `~/.local/venvs/graphify/` — Python venv, ~25MB, owned by user
- `~/.local/bin/graphify` — symlink into the venv binary
- `~/.claude/skills/graphify/SKILL.md` — written by `graphify claude install` (NOT by install.sh directly; graphify owns this file)
- `~/CLAUDE.md` graphify section + `~/.claude/settings.json` PreToolUse hook block — also written by `graphify claude install` per its own documented behavior. install.sh doesn't manage either.
- `~/.obsidian-wiki/config` — single line `OBSIDIAN_VAULT_PATH="..."`, written only if missing
- `~/.zshrc` — append-only, sentinel-bracketed block:
  ```
  # BEGIN MonsterFlow obsidian-wiki
  export OBSIDIAN_VAULT_PATH="..."
  # END MonsterFlow obsidian-wiki
  ```
  Sentinel pattern matches the existing theme block at install.sh:701-712. `posix_quote` is hoisted to top-level so this works under `--no-theme`.
- `/Applications/Obsidian.app` — written by `brew install --cask obsidian` (not by install.sh directly; brew owns the artifact lifecycle).

**Files NOT touched:**

- `~/.claude/skills/wiki-*/` — install.sh never writes to skill dirs (upstream `npx skills add` installer's territory)
- Existing non-sentinel `OBSIDIAN_VAULT_PATH=` exports in `~/.zshrc` — skipped with one-line notice
- `~/.config/cmux/cmux.json` symlink under the drift case — leave it dangling rather than churn the theme stage's output. Theme stage owns that file; do_knowledge_layer only reports on it.
- An existing `/Applications/Obsidian.app` (whether brew-installed or manually-installed) — detection treats it as ✓ regardless of provenance; install action skips.

**No new persistent state in MonsterFlow repo.** The new stage is pure addition to `install.sh`; no new config files, no schema bumps, no Brewfile additions (Obsidian.app uses a targeted `brew install --cask obsidian`, not a bundle add — see Out of Scope).

## Integration

**Code touched:**

- `install.sh:694-697` — hoist `posix_quote` from inside `do_theme_install` to a top-level function definition (above `do_theme_install`). Theme stage continues to use it; knowledge layer also calls it under `--no-theme`.
- `install.sh:714` — after `do_theme_install` returns, new `do_knowledge_layer` call inserted before `# --- CLAUDE.md baseline ---` at install.sh:716.
- New helper functions colocated above install.sh:714:
  - `detect_knowledge_layer()` — returns 5 status structures (per-piece state: Ready / Can install now / Manual action required) + renders the summary block.
  - `do_knowledge_layer()` — runs detection, classifies each piece into Ready / Can-install / Manual-action buckets, prompts (only when Can-install bucket is non-empty), dispatches the per-piece installers.
  - `install_graphify_cli()` — runs the four-command install sequence (`python3 -m venv` → `pip3 install "graphifyy[mcp]"` → `ln -sf` → `graphify claude install`).
  - `install_obsidian_env()` — prompts for vault path, validates, writes `~/.obsidian-wiki/config` + `~/.zshrc` sentinel block (calls hoisted `posix_quote`).
  - `install_obsidian_app()` — runs `brew install --cask obsidian`, treats post-install `[ -d /Applications/Obsidian.app ]` as the success oracle (handles the "brew non-zero exit but app exists" case from EC17).
  - `parse_obsidian_config()` — small parser for `~/.obsidian-wiki/config` handling `export`/quotes/comments/tilde (per EC18).
  - `print_wiki_skills_instructions()`, `print_cmux_drift_instructions()`, `print_obsidian_app_manual_instructions()` — print-only, no exec.
- Reuses existing helpers: `link_file` (theme stage), sentinel-block append idiom, `OWNER` detection, `NON_INTERACTIVE` flag.
- `tests/run-tests.sh` — append new entry `test-install-knowledge-layer.sh` to the TESTS array (after all existing entries; orchestrator-wiring guard enforces parity).

**Pipeline integration:**

- `/wrap` Phase 2c (existing) — depends on `OBSIDIAN_VAULT_PATH` and the six wiki skills. Once an adopter completes this spec's install flow, Phase 2c stops being a silent no-op.
- `/spec` Phase 0.2 (existing) — same dependency on wiki-query skill + `~/.obsidian-wiki/config`. Same effect.
- No changes to `/blueprint`, `/check`, `/build`, or autorun.

**Dependencies on external behaviors:**

- `graphifyy` PyPI package install via `pip3` — relies on `python3 ≥ 3.9` (already a REQUIRED tier in install.sh:349-356)
- `npx skills add Ar9av/obsidian-wiki` — relies on Node.js + npx; install.sh does NOT auto-install Node, just suggests the command. Fallback recipe doesn't need Node.

## Edge Cases

1. **graphify CLI present but venv dir absent** (binary from some other source — homebrew tap, pipx, etc.) → mark CLI as ✓, skip the venv install action. Don't try to "fix" a binary the user installed differently. Detection is `command -v` only, NOT venv-path-required (resolves the rev0 contradiction).
2. **`~/.local/venvs/graphify` exists but the `~/.local/bin/graphify` symlink is missing** → re-create only the symlink with `ln -sf`. Don't re-run pip, don't re-run `graphify claude install`.
3. **`~/.local/venvs/graphify` exists with non-empty contents** when user said "install" → refuse with one-line notice (`graphify venv already exists at ~/.local/venvs/graphify — remove it manually if you want a clean reinstall`). No clobber, no .bak (venvs are large and have hardlinks).
4. **`~/.obsidian-wiki/config` exists but the configured `OBSIDIAN_VAULT_PATH` doesn't resolve to a directory** → summary shows `⚠ vault path configured but missing: <path>` and the auto-install path skips this piece (user moved their vault; we don't guess where).
5. **`~/.zshrc` already has a non-sentinel `OBSIDIAN_VAULT_PATH=` line** (e.g., user wrote their own export before running install.sh) → skip the sentinel append, print one-line notice (`~/.zshrc already exports OBSIDIAN_VAULT_PATH — leaving your line alone`). Still write `~/.obsidian-wiki/config` if missing (the skills read both).
6. **Wiki skills partially present** (e.g., 4 of 6, common when user pulled an older obsidian-wiki version) → summary shows `✗ (4/6)`; the same `npx skills add` instruction prints (idempotent upstream — re-running installs only the missing two).
7. **`npx` unavailable** → manual-action message prints the git-clone + cp fallback recipe instead of the npx line. No silent failure.
8. **Idempotent re-run after partial install** (user said yes but ctrl-c'd during pip) → next run detects venv-without-binary (case 2) and offers to finish via the symlink-only path.
9. **`--non-interactive` mode** → summary still renders (zero side effects); the install prompt is skipped (default-N); no installs happen. Manual-action-required text prints regardless (it's print-only).
10. **`NO_THEME=1` + Knowledge Layer** → Knowledge Layer still runs (it has its own placement at install.sh:716, after `do_theme_install` returns). The hoisted top-level `posix_quote` ensures `install_obsidian_env()` works even when theme stage was skipped.
11. **Adopter without `~/.local/bin` in PATH** → already warned in RECOMMENDED tier at install.sh:365-368. The graphify symlink will be created either way; PATH fix is the user's job after install.sh exits.
12. **cmux drift with `--no-theme` + prior symlink state** → if `--no-theme` is passed but a `~/.config/cmux/cmux.json` symlink already exists from a prior install run, the cmux check STILL fires (it's a drift detection, not a theme-stage-output check). The `⚠ config present but binary absent` warning surfaces. Rationale: `--no-theme` suppresses theme writes for THIS run; it doesn't unmount the user's awareness of pre-existing drift.
13. **cmux drift when cmux IS installed via some other path** (Homebrew tap, manual install, etc.) → `command -v cmux` succeeds, drift resolves to `✓`. The check is binary-presence, not version-match.
14. **`brew` binary itself missing during the drift case** → `command -v cmux` fails → ⚠ drift state. The recommendation still prints `brew install --cask cmux`; the adopter resolves the brew prerequisite first (REQUIRED tier already warns about this on the same install run).
15. **Owner-auto-yes with cmux drift** → still print-only (per scope). Owner sees the same warning text adopter sees; install.sh does not silently re-run brew bundle on their behalf. This is intentional — drift surfacing is the point, not stealth recovery.
16. **Obsidian.app installed manually (not via brew)** — `[ -d /Applications/Obsidian.app ]` returns true; detection is ✓ regardless of how the .app got there. `brew info --cask obsidian` would say "Not installed" (brew tracks casks it installed) but install.sh does not consult brew for detection. This matches the user-observed state where the .app was downloaded directly from obsidian.md.
17. **Obsidian install action collides with a pre-existing manual install** — if detection somehow misses (e.g., racing the user installing Obsidian.app during install.sh's run) and `brew install --cask obsidian` exits non-zero because `/Applications/Obsidian.app` already exists, install.sh treats the failure as success (re-check `[ -d /Applications/Obsidian.app ]` after the brew call; if true, ✓). No `--force` flag (we don't clobber the user's manual install).
18. **OBSIDIAN_VAULT_PATH config file parsing** — the parser handles: `OBSIDIAN_VAULT_PATH="path"`, `OBSIDIAN_VAULT_PATH=path`, `export OBSIDIAN_VAULT_PATH="path"`, leading whitespace, trailing `#` comments. Literal `~` is expanded via `${VAR/#\~/$HOME}` BEFORE the directory-exists check (per `feedback_tilde_expansion_in_bash_config_reads` memory). The parser does NOT `source` the file (avoids arbitrary code execution).
19. **Non-interactive owner mode + missing vault path** — `install_obsidian_env()` would normally prompt. Under `--non-interactive` (or `$AUTORUN_STAGE` set), the prompt is skipped, no value is guessed, no config file is written, and one-line stderr notice prints: `vault path not configured — set OBSIDIAN_VAULT_PATH manually and re-run install.sh`. Detection reports ✗ on subsequent runs until the user resolves it.
20. **`brew` unavailable when Obsidian.app needs installing** — `command -v brew` fails. The Can-install-now action can't run. Demote to Manual-action-required for this piece on this run, print the direct-download fallback (no version pin — defer to obsidian.md/download or the latest GitHub Release page rather than hardcoding a version that will rot):
    ```
    Obsidian.app: install manually from https://obsidian.md/download
    (or the latest release: https://github.com/obsidianmd/obsidian-releases/releases/latest)
    ```
    Do NOT shell out to `curl + hdiutil + cp` from install.sh — version-pinning rot, mount-leak risk, jq dependency for the latest-release lookup. brew cask is the supported path; direct download is the user's hands-on fallback.

## Acceptance Criteria

**AC1 — Summary block renders correctly for all-absent state.**
Fixture: clean `$HOME` with none of (graphify CLI, wiki skills, `~/.obsidian-wiki/config`, `/Applications/Obsidian.app`) present and no `~/.config/cmux/cmux.json` symlink. Run install.sh under `--non-interactive`. Assert stdout contains, in order:
  - `graphify CLI:` followed by `✗`
  - `wiki skills:` followed by `✗ (0/6)`
  - `OBSIDIAN_VAULT_PATH:` followed by `✗`
  - `Obsidian.app:` followed by `✗`
  - `cmux drift:` followed by `○ N/A`

And the "Install ..." prompt does NOT fire (non-interactive skip). Manual-action-required text (`npx skills add Ar9av/obsidian-wiki`) DOES print regardless (print-only).

**AC2 — Summary block renders correctly for all-present state.**
Fixture: pre-populate `~/.local/bin/graphify` (executable stub), all 6 `~/.claude/skills/wiki-*/SKILL.md` (touch), `~/.obsidian-wiki/config` with a vault path pointing to an existing dir, `/Applications/Obsidian.app` (mkdir, since the test fixture's `$HOME` doesn't have a real Applications dir — adjust path constant or symlink as harness requires), and skip the cmux row by not staging the symlink. Run install.sh under `--non-interactive`. Assert stdout shows five `✓` lines (one each: graphify CLI, wiki skills 6/6, OBSIDIAN_VAULT_PATH, Obsidian.app, cmux drift `○ N/A`), the closing `Knowledge Layer: all present ✓` line, and zero install actions executed (assert no `pip3`, `brew`, `ln`, or write to `~/.zshrc` occurred via `$STUB_LOG` or filesystem comparison).

**AC3 — Idempotency: no mutations on already-correct re-run.**
Setup: under the AC2 fixture, capture `MARKER=$(mktemp)`. Run install.sh. After first run, assert detection ✓ on all 5 lines. Then `touch "$MARKER"`. Run install.sh a second time. After second run, assert ALL of:
  - `find ~/.local/venvs/graphify ~/.local/bin/graphify ~/.claude/skills/wiki-* ~/.obsidian-wiki ~/.zshrc ~/.config/cmux -newer "$MARKER" 2>/dev/null` returns empty (zero files mutated under any Knowledge-Layer-owned path).
  - `find ~/.claude ~/.local ~/.obsidian-wiki -name '*.bak.*' -newer "$MARKER"` returns empty (no backup files created).
  - Line count of `~/.zshrc` is identical before-and-after the second run.
  - `grep -c "BEGIN MonsterFlow obsidian-wiki" ~/.zshrc` returns exactly 1 (sentinel block not duplicated).

**AC4 — Owner auto-yes vs adopter default-N.**
Under `MONSTERFLOW_OWNER=1` + interactive TTY + all-absent state, assert the "Install ...?" prompt does NOT block waiting for input (auto-yes path taken; the Can-install-now pieces run). Under `MONSTERFLOW_OWNER=0` + interactive TTY + all-absent state + simulated empty stdin (default-N), assert ZERO of the following filesystem mutations occurred (via `find $HOME -newer <pre-run-marker>` returning empty for each path): `~/.local/venvs/graphify`, `~/.local/bin/graphify`, `~/.obsidian-wiki/config`, `~/.zshrc` (no new sentinel block), `/Applications/Obsidian.app`. Manual-action text still prints in both cases (print-only).

**AC5 — Wiki skills: install.sh prints instructions, does not exec npx.**
Under all-absent state with `MONSTERFLOW_OWNER=1` (auto-yes), assert install.sh stdout contains the literal `npx skills add Ar9av/obsidian-wiki` string. Assert no `npx` process is invoked (test runs with `PATH` stub that records all invocations to `$STUB_LOG`; if `npx` appears in the log, the test fails).

**AC6 — Test wired into orchestrator.**
`tests/test-install-knowledge-layer.sh` exists and is executable; it is appended to the `TESTS` array of `tests/run-tests.sh` after all existing entries; the orchestrator-wiring guard at `run-tests.sh` (disk-count vs array-count parity check) does not fire when the suite runs.

**AC7 — cmux drift detection.**
Fixture: pre-stage `~/.config/cmux/cmux.json` as a symlink (matches what the theme stage produces) AND ensure no `cmux` binary on PATH (no stub for cmux in `$STUB_DIR`). Run install.sh under `--non-interactive`. Assert stdout contains: `cmux drift:` followed by `⚠ config present but binary absent`, the literal recommendation `brew install --cask cmux`, and that NO `brew` invocation is logged in `$STUB_LOG` from the cmux-drift code path (drift is print-only; the Obsidian.app brew call, if any, has a distinct argv). Run install.sh a second time with the same fixture and assert byte-identical drift output — re-runs do not flap the warning.

**AC8 — Obsidian.app detection vs install.**
Two fixtures:
  (a) Pre-staged `/Applications/Obsidian.app` (or test-harness equivalent): under any owner/adopter mode, assert detection reports `Obsidian.app: ✓` AND no `brew` invocation for `--cask obsidian` appears in `$STUB_LOG` (install action skipped, idempotency preserved).
  (b) Empty `/Applications` + `MONSTERFLOW_OWNER=1` + `MONSTERFLOW_INSTALL_TEST=1`: assert install.sh stdout shows `Obsidian.app: ✗` then `RUNNING: brew install --cask obsidian` then `✓ Obsidian.app installed` (via the test seam stub for brew). Re-run with the now-staged `.app` and assert detection flips to ✓ with no further brew invocation.

**AC9 — OBSIDIAN config parsing handles edge inputs.**
Fixture: pre-stage `~/.obsidian-wiki/config` with body:
```
# vault config
export OBSIDIAN_VAULT_PATH="~/Documents/test vault"
```
AND pre-stage `~/Documents/test vault/` as an existing directory. Run install.sh under `--non-interactive`. Assert detection reports `OBSIDIAN_VAULT_PATH: ✓ → /Users/<user>/Documents/test vault` (tilde-expanded, spaces preserved, comment ignored, `export` prefix tolerated). No `source` invocation appears in `$STUB_LOG` (parsing is safe — no arbitrary code execution).

## Open Questions

None below the 0.80 small-change gate. Two items worth flagging but not blocking:

- **Sentinel for obsidian-wiki block in .zshrc.** Pick a sentinel string that won't collide with anything obsidian-wiki itself might write. Current proposal: `# BEGIN MonsterFlow obsidian-wiki` / `# END MonsterFlow obsidian-wiki`, matching the theme block's style.
- **cmux drift symmetric for other Brewfile casks.** Right now only cmux gets the drift check, because cmux is the only cask the theme stage symlinks user-visible config for. If the theme stage ever symlinks config for another cask (e.g., `iterm2-shell-integration`), the drift check pattern should generalize. Out of scope for this spec; revisit during `/blueprint` if the cmux check ends up as a one-off vs the start of a pattern.

## Revisions

**rev1 (2026-05-13, post-`/spec-review`):** Resolved 5 critical findings:
- Fixed graphify install command per `docs/graphify-usage.md:39,141` authority — now `pip3 install "graphifyy[mcp]" && graphify claude install` (closed Open Question #1; the `install-skill` subcommand was a guess that doesn't exist).
- Fixed CLI detection contradiction — now `command -v graphify` only (any working binary counts, matches EC1).
- Hoisted `posix_quote` from inside `do_theme_install` to top-level (required so `install_obsidian_env()` works under `--no-theme`).
- Split the prompt by actionability — Can-install-now vs Manual-action-required (Codex's doctor + fixer reshape). Prompt only fires when there's something install.sh can actually install.
- Added Obsidian.app as a sixth detection — needed because suggesting the wiki skills without the app they target is incomplete. Detection is `[ -d /Applications/Obsidian.app ]` (filesystem-based, catches manual installs that brew doesn't track).

Plus tightened AC1 (cmux row assertion), AC3 (marker + path list + sentinel-block count), AC4 (binary mutation assertions), added AC8 (Obsidian.app detect vs install), AC9 (config parsing edge inputs). Added EC16-20 covering Obsidian-manual-install + brew-collision + brew-unavailable + non-interactive vault path. Updated Summary, Out of Scope, Data & State, Integration, and UX examples to match. Confidence 0.85 → 0.90.
