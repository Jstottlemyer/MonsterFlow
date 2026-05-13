---
name: install-graphify-wiki-coverage
description: Add a Knowledge Layer stage to install.sh that detects graphify CLI, graphify skill, the six obsidian-wiki skills, OBSIDIAN_VAULT_PATH, and cmux config-without-binary drift; offers to install only the missing pieces; re-runs cleanly when state is already correct.
created: 2026-05-13
revised: 2026-05-13 (folded cmux post-install drift detection — orphaned ~/.config/cmux/cmux.json when brew bundle was declined)
constitution: none — defaults-only roster (precedent: install-rewrite, pipeline-wiki-integration)
confidence: 0.85 (Scope 0.90 / UX 0.85 / Data 0.85 / Integration 0.85 / Edge 0.85 / Acceptance 0.85)
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

`install.sh` today covers pipeline commands, personas, schemas, scripts, theme, brew tools, and plugins, but is silent on the knowledge layer the rest of MonsterFlow depends on: the `graphify` CLI, the `graphify` skill, the six `wiki-*` skills from `github.com/Ar9av/obsidian-wiki`, and the `OBSIDIAN_VAULT_PATH` environment that `/wrap` Phase 2c needs. Adopters who follow the install instructions end with a working pipeline but no knowledge surface; `/wrap` Phase 2c silently no-ops and `/spec` Phase 0.2 never fires.

A parallel post-install drift case also lands here: `cmux` (a Brewfile cask) only installs when the adopter says Y to the brew bundle prompt, but the theme stage symlinks `~/.config/cmux/cmux.json` unconditionally — so a decline path leaves an orphaned cmux config pointing at a binary that doesn't exist. Same detection-and-report pattern, same idempotent re-run guarantee.

This spec adds one new stage — Knowledge Layer — that detects all five pieces with a single summary banner, prompts once to install only what's missing, and treats already-correct state as a zero-op no-prompt path. Adopter default is **prompt-default-N** (consistent with the existing plugin + theme adopter defaults); owner is **auto-yes**.

## Backlog Routing

Backlog: empty at time of spec — `BACKLOG.md` has no graphify/wiki items pending. The closest historical reference is `install-rewrite` v1.1's explicit scope-cut of wiki-export indexing from `onboard.sh`; this spec is the follow-up that reopens the surface with the right framing (install.sh-level detection, not skill execution from bash).

## Scope

### In scope

- New `do_knowledge_layer()` stage in `install.sh`, placed after `do_theme_install` (install.sh:714) and before the CLAUDE.md baseline merge (install.sh:716).
- Detects five pieces and prints one summary block:
  - `graphify` CLI — `command -v graphify` AND `~/.local/venvs/graphify/bin/graphify --help` exits 0
  - `graphify` skill — `[ -f ~/.claude/skills/graphify/SKILL.md ]`
  - Wiki skills (×6) — all of `~/.claude/skills/{wiki-ingest,wiki-update,wiki-query,wiki-export,wiki-lint,wiki-capture}/SKILL.md`
  - Obsidian env — `[ -f ~/.obsidian-wiki/config ]` AND grep succeeds for `OBSIDIAN_VAULT_PATH=` AND the resolved path is an existing dir
  - `cmux` drift — `[ -L ~/.config/cmux/cmux.json ]` (theme stage created it) AND `command -v cmux` fails. Three states: ✓ both present (or both absent — N/A), ⚠ config present + binary absent (drift — the case this spec fixes), ○ neither (no theme, no concern)
- One batched prompt when at least one piece is missing: `Install missing pieces? [y/N]`. Owner gets auto-yes; adopter default-N (matches plugin / theme adopter defaults).
- Per-piece install actions, gated on missing-only (no clobber):
  - `graphify` CLI: `python3 -m venv ~/.local/venvs/graphify && ~/.local/venvs/graphify/bin/pip3 install graphifyy && ln -sf ~/.local/venvs/graphify/bin/graphify ~/.local/bin/graphify`. Refuse if `~/.local/venvs/graphify` already exists with non-empty contents. If venv dir exists but symlink is missing, re-create only the symlink.
  - `graphify` skill: print `Install graphify skill via the graphify CLI's own setup (run: graphify install-skill)` or equivalent upstream instruction. install.sh does NOT vendor or symlink the skill (third-party content, no MonsterFlow source rights).
  - Wiki skills: print `Run: npx skills add Ar9av/obsidian-wiki` (upstream installer is idempotent and handles all 6). install.sh does NOT auto-exec npx (long-running, interactive, can prompt for network credentials). Fallback when `command -v npx` fails: print the manual `git clone https://github.com/Ar9av/obsidian-wiki && cp -r .skills/* ~/.claude/skills/` recipe from the upstream README.
  - Obsidian env: prompt for vault path, validate it resolves to an existing directory, write `~/.obsidian-wiki/config` with `OBSIDIAN_VAULT_PATH="<path>"` if missing, and append a sentinel-bracketed block to `~/.zshrc` exporting `OBSIDIAN_VAULT_PATH` (reuses `posix_quote` + sentinel pattern from the theme stage).
  - cmux drift: print `Run: brew install --cask cmux  # restores the cask the Brewfile already lists`. install.sh does NOT auto-exec brew (adopter already declined the brew bundle prompt earlier in this same install run — re-prompting is annoying). Owner-auto-yes still surfaces the recommendation but doesn't re-attempt the install either, because by the time we're in `do_knowledge_layer` the brew bundle stage is committed. Re-running `install.sh` after the user manually installs cmux clears the warning.
- Idempotency: re-runs against already-correct state print `Knowledge Layer: all present ✓` and emit zero prompts, zero filesystem writes, zero `.bak` files, zero `.zshrc` mutations.
- `tests/test-install-knowledge-layer.sh` wired into `tests/run-tests.sh` TESTS array (orchestrator-wiring guard at run-tests.sh:139 enforces this).

### Out of scope

- Vendoring the wiki skills into MonsterFlow's `skills/` directory and symlinking them like first-party content. Wiki skills belong to `github.com/Ar9av/obsidian-wiki` (no MonsterFlow author rights, no documented license-compat path); install.sh suggests the upstream installer instead.
- Running `bootstrap-graphify.sh --apply` from `install.sh`. The bootstrap installs launchd agents, post-commit hooks across `~/Projects/*`, and seeds dashboard JSONL — much larger blast radius than the install.sh "detect → install → verify" envelope, and it spends real LLM tokens on graphify's extract pass. Stays as a separate user-invoked one-shot.
- Auto-cloning `github.com/Ar9av/obsidian-wiki` to a fixed path. Skill install is upstream's responsibility.
- Bringing back the wiki-export indexing that `install-rewrite` v1.1 explicitly cut from `onboard.sh`. The skill execution surface stays in `/wrap` Phase 2c where it already lives.
- Detection of graphify per-project graphs (`graphify-out/`). That's a project-level concern; `bootstrap-graphify.sh` handles it.
- Re-running brew bundle from inside `do_knowledge_layer` to recover from a declined brew bundle prompt. The user said no once already in the same install run — pestering them is poor UX. We surface the gap, they re-run install.sh (or invoke `brew install --cask cmux` directly) when ready.
- Removing the orphaned `~/.config/cmux/cmux.json` symlink. It's not harmful (the file just dangles) and removing it would force a re-symlink on next install — more churn than benefit.

## Approach

N/A — small change.

## Roster Changes

N/A — small change. Defaults-only roster covers this surface.

## UX / User Flow

**First-run on a clean adopter machine (none of the four pieces present):**

```
[... theme stage output ...]

=== Knowledge Layer ===
graphify CLI:        ✗ (not installed)
graphify skill:      ✗ (~/.claude/skills/graphify/SKILL.md absent)
wiki skills:         ✗ (0/6)
OBSIDIAN_VAULT_PATH: ✗ (~/.obsidian-wiki/config absent)
cmux drift:          ○ N/A (no theme config present)

Install missing pieces? [y/N]: y

Installing graphify CLI...
  RUNNING: python3 -m venv ~/.local/venvs/graphify
  RUNNING: pip3 install graphifyy
  LINKED:  ~/.local/bin/graphify → ~/.local/venvs/graphify/bin/graphify
  ✓ graphify CLI installed

Installing wiki skills...
  install.sh does not auto-exec npx (interactive + network).
  Run this yourself when ready:
    npx skills add Ar9av/obsidian-wiki
  Fallback (no npx):
    git clone https://github.com/Ar9av/obsidian-wiki ~/Projects/obsidian-wiki
    cp -r ~/Projects/obsidian-wiki/.skills/* ~/.claude/skills/

Configuring OBSIDIAN_VAULT_PATH...
  Vault path [~/Documents/Obsidian/wiki]: <enter to accept default>
  Path resolves to existing directory: ✓
  WROTE:    ~/.obsidian-wiki/config
  APPENDED: ~/.zshrc (sentinel-bracketed OBSIDIAN_VAULT_PATH export)
  ✓ Obsidian env configured

graphify skill: install via the graphify CLI's own skill setup (see graphify --help for the install-skill subcommand or upstream README).

=== Knowledge Layer setup complete ===
Run `npx skills add Ar9av/obsidian-wiki` in a separate terminal to finish wiki skills.
```

**Re-run after everything is present:**

```
[... theme stage output ...]

=== Knowledge Layer ===
graphify CLI:        ✓
graphify skill:      ✓
wiki skills:         ✓ (6/6)
OBSIDIAN_VAULT_PATH: ✓ → /Users/jstottlemyer/Documents/Obsidian/wiki
cmux drift:          ✓ (config + binary both present)

Knowledge Layer: all present ✓
```

No prompt, no mutations.

**cmux drift case (theme installed, brew bundle declined):**

```
=== Knowledge Layer ===
graphify CLI:        ✓
graphify skill:      ✓
wiki skills:         ✓ (6/6)
OBSIDIAN_VAULT_PATH: ✓ → /Users/jstottlemyer/Documents/Obsidian/wiki
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

**Files created (when user opts in):**

- `~/.local/venvs/graphify/` — Python venv, ~25MB, owned by user
- `~/.local/bin/graphify` — symlink into the venv binary
- `~/.obsidian-wiki/config` — single line `OBSIDIAN_VAULT_PATH="..."`, written only if missing
- `~/.zshrc` — append-only, sentinel-bracketed block:
  ```
  # BEGIN MonsterFlow obsidian-wiki
  export OBSIDIAN_VAULT_PATH="..."
  # END MonsterFlow obsidian-wiki
  ```
  Sentinel pattern matches the existing theme block at install.sh:701-712.

**Files NOT touched:**

- `~/.claude/skills/wiki-*/` — install.sh never writes to skill dirs (upstream installer's territory)
- `~/.claude/skills/graphify/` — same
- Existing non-sentinel `OBSIDIAN_VAULT_PATH=` exports in `~/.zshrc` — skipped with one-line notice
- `~/.config/cmux/cmux.json` symlink under the drift case — leave it dangling rather than churn the theme stage's output. Theme stage owns that file; do_knowledge_layer only reports on it.

**No new persistent state in MonsterFlow repo.** The new stage is pure addition to `install.sh`; no new config files, no schema bumps.

## Integration

**Code touched:**

- `install.sh:714` — `do_theme_install` returns, new `do_knowledge_layer` call inserted before `# --- CLAUDE.md baseline ---` at install.sh:716
- New helper functions colocated with `do_theme_install` (above install.sh:714):
  - `detect_knowledge_layer()` — returns 4 status booleans + render summary block
  - `do_knowledge_layer()` — runs detection, prompts if anything missing, dispatches per-piece installers
  - `install_graphify_cli()`, `install_obsidian_env()` — per-piece actions
  - `print_wiki_skills_instructions()` — non-executing, just prints the upstream command + fallback
- Reuses existing helpers: `link_file`, `posix_quote` (theme stage), sentinel-block append idiom, `OWNER` detection
- `tests/run-tests.sh:22-126` — append new entry `test-install-knowledge-layer.sh` to TESTS array (orchestrator-wiring guard at run-tests.sh:139 enforces parity)

**Pipeline integration:**

- `/wrap` Phase 2c (existing) — depends on `OBSIDIAN_VAULT_PATH` and the six wiki skills. Once an adopter completes this spec's install flow, Phase 2c stops being a silent no-op.
- `/spec` Phase 0.2 (existing) — same dependency on wiki-query skill + `~/.obsidian-wiki/config`. Same effect.
- No changes to `/blueprint`, `/check`, `/build`, or autorun.

**Dependencies on external behaviors:**

- `graphifyy` PyPI package install via `pip3` — relies on `python3 ≥ 3.9` (already a REQUIRED tier in install.sh:349-356)
- `npx skills add Ar9av/obsidian-wiki` — relies on Node.js + npx; install.sh does NOT auto-install Node, just suggests the command. Fallback recipe doesn't need Node.

## Edge Cases

1. **graphify CLI present but venv dir absent** (binary from some other source — homebrew tap, pipx, etc.) → mark CLI as ✓, skip the venv install action. Don't try to "fix" a binary the user installed differently.
2. **`~/.local/venvs/graphify` exists but the `~/.local/bin/graphify` symlink is missing** → re-create only the symlink with `ln -sf`. Don't re-run pip.
3. **`~/.local/venvs/graphify` exists with non-empty contents** when user said "install" → refuse with one-line notice (`graphify venv already exists at ~/.local/venvs/graphify — remove it manually if you want a clean reinstall`). No clobber, no .bak (venvs are large and have hardlinks).
4. **`~/.obsidian-wiki/config` exists but the configured `OBSIDIAN_VAULT_PATH` doesn't resolve to a directory** → summary shows `⚠ vault path configured but missing: <path>` and the auto-install path skips this piece (user moved their vault; we don't guess where).
5. **`~/.zshrc` already has a non-sentinel `OBSIDIAN_VAULT_PATH=` line** (e.g., user wrote their own export before running install.sh) → skip the sentinel append, print one-line notice (`~/.zshrc already exports OBSIDIAN_VAULT_PATH — leaving your line alone`). Still write `~/.obsidian-wiki/config` if missing (the skills read both).
6. **Wiki skills partially present** (e.g., 4 of 6, common when user pulled an older obsidian-wiki version) → summary shows `✗ (4/6)`; install action is the same npx command (idempotent upstream — re-running installs only the missing two).
7. **`npx` unavailable** → install action prints the git-clone + cp fallback recipe instead of the npx line. No silent failure.
8. **Idempotent re-run after partial install** (user said yes but ctrl-c'd during pip) → next run detects venv-without-binary (case 2) and offers to finish via the symlink-only path.
9. **`--non-interactive` mode** → summary still renders (zero side effects); the install prompt is skipped (default-N); no installs happen. Documented in the output so headless adopters know what to do next.
10. **`NO_THEME=1` + Knowledge Layer** → unrelated; Knowledge Layer runs regardless of theme flag (different concerns).
11. **Adopter without `~/.local/bin` in PATH** → already warned in RECOMMENDED tier at install.sh:365-368. The graphify symlink will be created either way; PATH fix is the user's job after install.sh exits.
12. **cmux drift with `--no-theme`** → if the user passed `--no-theme`, the theme stage never created `~/.config/cmux/cmux.json`, so the cmux check resolves to `○ N/A`. No warning, no recommendation.
13. **cmux drift when cmux IS installed via some other path** (Homebrew tap, manual install, etc.) → `command -v cmux` succeeds, drift resolves to `✓`. The check is binary-presence, not version-match.
14. **`brew` binary itself missing during the drift case** → `command -v cmux` fails → ⚠ drift state. The recommendation still prints `brew install --cask cmux`; the adopter resolves the brew prerequisite first (REQUIRED tier already warns about this on the same install run).
15. **Owner-auto-yes with cmux drift** → still print-only (per scope). Owner sees the same warning text adopter sees; install.sh does not silently re-run brew bundle on their behalf. This is intentional — drift surfacing is the point, not stealth recovery.

## Acceptance Criteria

**AC1 — Summary block renders correctly for all-absent state.**
Fixture: clean `$HOME` with none of (graphify CLI, graphify skill, wiki skills, `~/.obsidian-wiki/config`) present. Run install.sh under `--non-interactive`. Assert stdout contains the four `✗` lines and the "Install missing pieces?" prompt does NOT fire (non-interactive skip).

**AC2 — Summary block renders correctly for all-present state.**
Fixture: pre-populate `~/.local/venvs/graphify/bin/graphify` (stub), `~/.claude/skills/graphify/SKILL.md` (touch), all 6 `~/.claude/skills/wiki-*/SKILL.md` (touch), and `~/.obsidian-wiki/config` with a vault path pointing to an existing dir. Run install.sh under `--non-interactive`. Assert stdout shows four `✓` lines, the closing `Knowledge Layer: all present ✓` line, and zero install actions executed.

**AC3 — Idempotency: no mutations on already-correct re-run.**
Run install.sh twice under the AC2 fixture. After the second run, assert: no new files created since first run (`find $HOME -newer <marker> -type f` empty for tracked paths), no `.bak` files anywhere under `~/.claude` or `~/.local`, no new `~/.zshrc` lines, no new `~/.obsidian-wiki/config` lines.

**AC4 — Owner auto-yes vs adopter default-N.**
Under `MONSTERFLOW_OWNER=1` + interactive TTY + all-absent state, assert the install prompt does NOT block (auto-yes path taken). Under `MONSTERFLOW_OWNER=0` + interactive TTY + all-absent state + simulated empty stdin (default-N), assert no installs run.

**AC5 — Wiki skills: install.sh prints instructions, does not exec npx.**
Under all-absent state with `MONSTERFLOW_OWNER=1` (auto-yes), assert install.sh stdout contains the literal `npx skills add Ar9av/obsidian-wiki` string. Assert no `npx` process is invoked (test runs with `PATH` stub that fails on `npx` exec — if install.sh tried to run it, the test fails).

**AC6 — Test wired into orchestrator.**
`tests/test-install-knowledge-layer.sh` exists and is executable; it is listed in the `TESTS` array of `tests/run-tests.sh`; the orchestrator-wiring guard at `run-tests.sh:139-155` does not fire when the suite runs (disk count matches array count).

**AC7 — cmux drift detection.**
Fixture: pre-stage `~/.config/cmux/cmux.json` as a symlink (matches what the theme stage produces) AND ensure no `cmux` binary on PATH (no stub for cmux in `$STUB_DIR`). Run install.sh under `--non-interactive`. Assert stdout contains: `cmux drift:` followed by `⚠ config present but binary absent`, the literal recommendation `brew install --cask cmux`, and that NO `brew` invocation is logged in `$STUB_LOG` from this stage (drift is print-only). Run install.sh a second time with the same fixture and assert byte-identical drift output — re-runs do not flap the warning.

## Open Questions

None below the 0.80 small-change gate. Three items worth flagging but not blocking:

- **graphify skill install command.** This spec assumes the graphify CLI has its own `install-skill` subcommand or upstream-documented path for installing `~/.claude/skills/graphify/SKILL.md`. If it doesn't (i.e., the skill on this machine was hand-copied), the install action should fall back to printing the GitHub raw-URL download recipe. Verify against `graphify --help` during `/blueprint`.
- **Sentinel for obsidian-wiki block in .zshrc.** Pick a sentinel string that won't collide with anything obsidian-wiki itself might write. Current proposal: `# BEGIN MonsterFlow obsidian-wiki` / `# END MonsterFlow obsidian-wiki`, matching the theme block's style.
- **cmux drift symmetric for other Brewfile casks.** Right now only cmux gets the drift check, because cmux is the only cask the theme stage symlinks user-visible config for. If the theme stage ever symlinks config for another cask (e.g., `iterm2-shell-integration`), the drift check pattern should generalize. Out of scope for this spec; revisit during `/blueprint` if the cmux check ends up as a one-off vs the start of a pattern.
