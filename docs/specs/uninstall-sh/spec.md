---
tags: []
tags_provenance:
  baseline: []
  llm_added: []
  user_overrides: []
gate_mode: permissive
---

# uninstall.sh Spec (rev2)

**Created:** 2026-05-13
**Revised:** 2026-05-13 (post-/spec-review rev1; addressed 8 must-fix findings + scope creep carve-off)
**Constitution:** none — session roster only
**Confidence:** Scope 0.94 · UX 0.90 · Data 0.90 · Integration 0.86 · EdgeCases 0.82 · Acceptance 0.85 (avg 0.88)

## Summary

Ship `uninstall.sh` as the reverse of `install.sh`. Architecture is **manifest-first + detector-fallback hybrid** (rev2 pivot per Codex review): install.sh writes an append-only JSONL manifest at install-time recording every mutation; uninstall reads the manifest and reverses exactly those entries. For pre-manifest installs (cold-start), uninstall falls back to filesystem detection. Default behavior is a non-destructive **dry-run**; `--apply` is the only flag that commits. Symmetric scope (owner + adopter). Two prerequisite specs carve off the install.sh changes that rev1 tried to bundle in: `install.sh-manifest-emit` (manifest writes) and `install.sh-uninstall-prep` (CLAUDE.md sentinel ownership in `claude-md-merge.py` + opening-banner mention + existing-symlink-backup-in-`link_file`). Both prereqs ship and pass tests before uninstall-sh build begins.

## Backlog Routing

| # | Item | Source | Routing |
|---|------|--------|---------|
| 1 | `uninstall.sh` reverter | BACKLOG.md (2026-05-13) | **(a) in scope** — this spec |
| 2 | `install-obsidian-vault-baseline` | BACKLOG.md (2026-05-13) | (c) new spec later — independent |
| 3 | `install-obsidian-wiki-auto-clone` | BACKLOG.md (2026-05-13) | (c) new spec later — independent |
| 4 | `install.sh-manifest-emit` (new prereq from rev2) | this spec's review | (c) BLOCKING prerequisite — must ship first |
| 5 | `install.sh-claude-md-ownership` (new prereq from rev2 + I9 split) | this spec's review | (c) BLOCKING prerequisite — must ship first |
| 6 | `install-hooks-uninstall-mode` (new from I9 split) | this spec's rev2 review | (c) non-blocking rider — can ship after |

## Scope

### In scope

1. **`uninstall.sh` at repo root** — top-level script, same invocation shape as `install.sh`.
2. **Symmetric audience** — adopter cleanup AND owner-side install-testing.
3. **Dry-run-by-default** — first run prints a plan with no side effects; `--apply` commits.
4. **Manifest-first + detector-fallback hybrid** — primary architecture reads `~/.claude/.monsterflow-install-manifest.jsonl` (written by prereq #4); detector-fallback handles pre-manifest installs by re-scanning filesystem state.
5. **Reversed surfaces** (complete list per /spec-review B2 — verified against install.sh):
   - **Symlinks under `~/.claude/`** (whose `readlink` target resolves into `$REPO_DIR` or `claude-workflow` pre-rebrand path): `commands/`, `agents/`, `personas/`, `templates/`, `hooks/`, `scripts/`, `skills/`, `schemas/`, `domain-agents/`, `commands/_prompts/`.
   - **`~/.claude/settings.json`** — file path (not directory). Symlink → reverse.
   - **`~/.local/bin/autorun`** — symlink → reverse.
   - **`~/.local/bin/graphify`** — symlink (only if `readlink` points into `~/.local/venvs/graphify/bin/graphify` AND manifest confirms MonsterFlow-installed). See B6 detection logic.
   - **`~/.claude/skills/graphify*`** — symlink + matching hook entry (via `graphify claude uninstall` IF the binary is verified-MonsterFlow per above; else direct strip).
   - **Repo-local git hooks** installed by `scripts/install-hooks.sh` — reverse via the same script's `--uninstall` mode (prereq #5 also adds that mode if missing).
   - **`~/.zshrc` sentinel-bracketed blocks**: theme block, obsidian-wiki block. Strip-in-place with B3 backup policy.
   - **`~/.config/cmux/cmux.json`**, **`~/.config/ghostty/config`**, **`~/.tmux.conf`** — symlinks → reverse + manifest-driven backup restore.
   - **`~/CLAUDE.md`** — strip the managed block (sentinel ownership lives in `claude-md-merge.py` per prereq #5).
   - **`~/.obsidian-wiki/config`** — remove ONLY when manifest says MonsterFlow created it. Cold-start fallback: leave with warning (per /spec-review I2).
6. **Backup-restore semantics (revised per /spec-review B5)**:
   - **Manifest-driven (primary)**: each install mutation writes a manifest row including `dst`, `backup_path`, `backup_sha256`, `created_at`, `reason`. uninstall restores exactly the named backup. SHA256 mismatch → refuse-restore with manual-cleanup instruction.
   - **Detector-fallback**: when no manifest exists, restore `.bak.<ts>` ONLY when exactly one backup file exists for the target AND its mtime is older than the current symlink's `ctime`. Ambiguous (multiple backups, newer-than-symlink, etc.) → leave backups in place, remove the symlink only, print actionable hint.
7. **Sentinel-block strip with full-file backup (per /spec-review B3)**: before stripping any sentinel-bracketed block from any file (`~/.zshrc`, `~/CLAUDE.md`), save the entire file to `<file>.uninstall.bak.<ts>`. Dry-run prints the backup path. `--apply` writes the backup BEFORE modifying the file. Adopter can restore the whole file if they had user content inside the managed block.
8. **Idempotency via manifest tombstone**: on successful `--apply`, uninstall.sh moves the manifest to a timestamped path `~/.claude/.monsterflow-install-manifest.uninstalled.<ts>`. Re-running `uninstall.sh --apply` finds no active manifest and exits with the canonical "Nothing to remove" message. Forensic trail is preserved at the timestamped path; multiple uninstall cycles produce multiple tombstone files. Partial-apply failures (exit 1) do NOT tombstone — the manifest stays active so the retry sees the remaining operations.
9. **`created_file` reversal policy (per `op:created_file` manifest rows)**: when the manifest records `op:created_file` (the install-time copy-the-whole-template case for `~/CLAUDE.md`), reversal computes current `sha256sum` and compares against manifest-recorded `created_sha256`:
   - **SHA match** (file unchanged since install): safe to delete. `--apply` deletes the file.
   - **SHA mismatch** (user edited the file post-install): preserve the file in place. Strip the managed sentinel-bracketed block (the `op:appended_block` row for the same file's baseline-managed content) via the standard sentinel-strip path. File becomes "user-owned with no managed content" — adopter keeps their edits, MonsterFlow's managed content is gone.
   - Full-file backup at scope #7 still fires before any modification.
   - Dry-run output explicitly states which branch will fire ("SHA match: will delete" or "SHA mismatch: will preserve + strip managed block").

### Out of scope

1. **Reversing third-party tools**: `Obsidian.app`, standalone `graphify` venv, `cmux` binary stay installed. Dry-run prints manual-removal hints.
2. **Per-stage uninstall flags**: no `--no-theme`, `--no-knowledge-layer`. All-or-nothing default.
3. **Per-piece confirmation prompts**: single dry-run-then-`--apply` gate.
4. **Vault content removal**: `OBSIDIAN_VAULT_PATH` survives.
5. **Reversing `git clone`**: dry-run prints a hint.
6. **`~/.claude/projects/<slug>/memory/`** — user-authored auto-memory survives.
7. **`~/.claude/usage-data/`** — Claude Code telemetry, not MonsterFlow state.
8. **`~/.zshenv.local`** — secrets file (per global CLAUDE.md secrets policy); explicit untouched.
9. **`~/.config/monsterflow/config.json`** — user config (agent_budget knob); explicit untouched.
10. **launchd plists** — verified absent: install.sh writes no `LaunchAgents/` files (audited rev2; if a future install.sh adds them, this spec must be revised to cover reversal).
11. **Existing-symlink overwrite recovery** — when install.sh replaced a user's pre-existing symlink (not a regular file), no backup exists. uninstall removes the symlink; user restores their original target manually. Adopters acknowledge via banner. (Mitigation in prereq #5 if `link_file` learns to back up existing symlinks.)
12. **Concurrent install + uninstall** — no lock file; dry-run mitigates by giving the user a chance to see what's running.
13. **Multi-machine state sync** — local machine only.
14. **Safe-restore guarantees** (per /spec-review I3 + /check SF10): the manifest-driven backup-restore + checksum-verify path with provable ownership is **manifest-mode only**. Cold-start (no manifest, pre-prereq-#4 installs) intentionally trades safety for cold-start support — restore happens only when exactly one backup exists and its mtime predates the symlink ctime; ambiguous cases leave backups in place with a hint. Adopters who want strongest guarantees must re-install once prereq #4 ships.

## Approach

**Manifest-first + detector-fallback hybrid** (rev2 pivot).

install.sh writes append-only JSONL to `~/.claude/.monsterflow-install-manifest.jsonl` at every mutation site (~20 sites — prereq #4 adds the writes; this spec consumes them). uninstall.sh reads the manifest and reverses exactly the recorded operations. For pre-manifest installs (no manifest file present), uninstall falls back to filesystem-detection logic (same primitives as `do_knowledge_layer`'s `detect_*` functions + `readlink` target checks against `$REPO_DIR`).

Manifest row examples:
- `{"op":"symlink","dst":"~/.tmux.conf","src":".../config/tmux.conf","backup":"~/.tmux.conf.bak.20260513110422","sha256":"..."}`
- `{"op":"append_block","file":"~/.zshrc","begin":"# BEGIN MonsterFlow theme","end":"# END MonsterFlow theme","sha256":"..."}`
- `{"op":"created_file","path":"~/CLAUDE.md","sha256":"..."}` (template-copy case)
- `{"op":"appended_block","file":"~/CLAUDE.md","begin":"# BEGIN MonsterFlow CLAUDE.md baseline","end":"# END MonsterFlow CLAUDE.md baseline","sha256":"..."}`
- `{"op":"graphify_install","binary":"~/.local/bin/graphify","venv":"~/.local/venvs/graphify"}`
- `{"op":"obsidian_wiki_config_write","path":"~/.obsidian-wiki/config","format":"single-line"}`

**Why hybrid:**
- Manifest gives provable ownership for destructive operations (.bak restore, CLAUDE.md handling, graphify reversal).
- Detector-fallback preserves cold-start support (uninstall works against pre-prereq-#4 installs).
- Codex's 6 HIGH findings all collapse: missing surfaces become impossible (manifest is exhaustive by construction); .bak safety becomes manifest-named; CLAUDE.md ownership becomes explicit; graphify ownership becomes explicit; user-edit data-loss is bounded by full-file backup (#7 in scope).

**Rejected alternatives:**
- **Pure detect-and-reverse** (rev1): missing-surface drift, .bak unsafe, weak ownership signals for destructive ops.
- **Mirror-walk** (`do_undo_<X>` per `do_<X>`): drift hazard + no ownership signal.

**Prerequisite specs** (3 specs per /spec-review I9 resolution; #4 + #5 are blocking, #6 is non-blocking rider):
- **#4 `install.sh-manifest-emit`** (BLOCKING): install.sh writes `~/.claude/.monsterflow-install-manifest.jsonl` at every mutation site (~20 sites). Append-only; manifest never modified post-install. New install on a machine with existing manifest appends new rows (multi-install tracking) with `repo_dir` per row (per /spec-review I2). Schema versioned (`{"schema_version":1,...}` on first row).
- **#5 `install.sh-claude-md-ownership`** (BLOCKING): (a) Move `~/CLAUDE.md` block ownership into `scripts/claude-md-merge.py` with explicit modes (`created_file` / `appended_block` / `skipped_manual`); (b) Add `# BEGIN MonsterFlow CLAUDE.md baseline` / `# END MonsterFlow CLAUDE.md baseline` sentinels around the managed block. Also: add `bash uninstall.sh` mention to install.sh opening banner AND end-block Next Steps (~10-line ride-along).
- **#6 `install-hooks-uninstall-mode`** (non-blocking rider — can ship after uninstall-sh if needed): (a) `scripts/install-hooks.sh --uninstall` mode (currently missing per Codex); (b) optional `link_file` extension to back up pre-existing symlinks (not just regular files). uninstall-sh's git-hook reversal falls back to direct strip if #6 hasn't shipped yet.

## Roster Changes

No roster changes.

## UX / User Flow

### Dry-run (default)

```
$ bash uninstall.sh
=== uninstall.sh — DRY RUN ===
(No side effects. Re-run with --apply to commit.)

Manifest: ~/.claude/.monsterflow-install-manifest.jsonl
  · 47 mutation rows (installed 2026-05-13 11:04:22 UTC; 1 install)

Would remove symlinks under ~/.claude/ (manifest-confirmed, 38 entries):
  ~/.claude/commands/spec.md → $REPO_DIR/commands/spec.md
  ~/.claude/settings.json → $REPO_DIR/settings/settings.json
  ~/.claude/schemas → $REPO_DIR/schemas
  ... (38 total)

Would back up files before stripping sentinel blocks:
  ~/.zshrc → ~/.zshrc.uninstall.bak.20260513154500
  ~/CLAUDE.md → ~/CLAUDE.md.uninstall.bak.20260513154500

Would strip sentinel blocks:
  ~/.zshrc: "MonsterFlow theme" (lines 142-147) + "MonsterFlow obsidian-wiki" (lines 149-152)
  ~/CLAUDE.md: "MonsterFlow CLAUDE.md baseline" (lines 18-43)

Would remove + restore originals (manifest-named backups):
  ~/.tmux.conf  ← ~/.tmux.conf.bak.20260513110422 (sha256 verified ✓)
  ~/.config/cmux/cmux.json  ← .bak.20260513110424 (sha256 verified ✓)
  ~/.config/ghostty/config  ← .bak.20260513110425 (sha256 verified ✓)

Would run graphify reversal (manifest-confirmed MonsterFlow install):
  graphify claude uninstall   (or direct strip if subcommand absent)

Would remove ~/.obsidian-wiki/config (manifest says MonsterFlow created it).

Third-party tools left in place (run manually if you want them gone):
  Obsidian.app   → brew uninstall --cask obsidian
  graphify CLI   → rm -rf ~/.local/venvs/graphify ~/.local/bin/graphify
  cmux           → brew uninstall cmux

Repo at $REPO_DIR untouched. rm -rf it after if you want the source gone.

Re-run with --apply to perform the above. No changes made.
```

### Cold-start (no manifest)

```
$ bash uninstall.sh
=== uninstall.sh — DRY RUN (cold-start mode) ===
No install manifest found at ~/.claude/.monsterflow-install-manifest.jsonl.
Falling back to filesystem detection.

Symlinks detected (target resolves into $REPO_DIR):
  ... (same shape as above, sans sha256 verification)

Backup restore (cold-start — conservative):
  ~/.tmux.conf: found 1 backup, older than current symlink — WILL restore
  ~/.config/cmux/cmux.json: found 3 backups, ambiguous — symlink will be removed; backups left in place
  ... (ambiguity hint per file)

(rest of plan as above)
```

### Apply

```
$ bash uninstall.sh --apply
=== uninstall.sh — APPLY ===
Backing up files before sentinel strip...
  SAVED:    ~/.zshrc.uninstall.bak.20260513154500
  SAVED:    ~/CLAUDE.md.uninstall.bak.20260513154500
Removing symlinks under ~/.claude/...
  REMOVED:  ~/.claude/commands/spec.md
  ...
Stripping sentinel blocks...
  STRIPPED: MonsterFlow theme block from ~/.zshrc
  STRIPPED: MonsterFlow obsidian-wiki block from ~/.zshrc
  STRIPPED: MonsterFlow CLAUDE.md baseline block from ~/CLAUDE.md
Restoring originals...
  RESTORED: ~/.tmux.conf  ← ~/.tmux.conf.bak.20260513110422 (sha256 ✓)
  ...
Reversing graphify skill install...
  ✓ graphify claude uninstall
=== Uninstall complete ===
Open a new shell so ~/.zshrc takes effect.
(Sentinel-block backups remain at ~/.zshrc.uninstall.bak.* and ~/CLAUDE.md.uninstall.bak.* — delete when satisfied.)
```

### Idempotent re-run

```
$ bash uninstall.sh --apply
=== uninstall.sh — APPLY ===
Manifest empty (or no manifest + cold-start finds nothing). Nothing to remove.
```

## Data & State

### Inputs uninstall reads

- `~/.claude/.monsterflow-install-manifest.jsonl` (primary; written by prereq #4).
- `$REPO_DIR` (cwd or `$0`'s dirname) — for detector-fallback symlink-target matching.
- `readlink` output for each candidate symlink (in both manifest mode and cold-start).
- File content for sentinel-grep + sha256 verification.
- `readlink ~/.local/bin/graphify` → verify points into `~/.local/venvs/graphify/bin/graphify` (NOT `command -v graphify`).

### Manifest-driven backup restore

For each `{"op":"symlink", ..., "backup":"<path>", "backup_sha256":"<hex>"}` row:

1. Verify the `<path>` exists. If absent, skip with warning "backup file moved/deleted; symlink will be removed without restore."
2. Verify `sha256sum <path>` matches recorded `backup_sha256`. Mismatch → refuse-restore with hint: "backup checksum mismatch — likely modified after install. Remove symlink only; restore manually if desired."
3. `--apply`: `rm "$dst"` (the symlink), then `mv "<path>" "$dst"`.

### Detector-fallback backup restore (no manifest)

For each symlink whose target resolves into `$REPO_DIR`:

1. Glob `<dst>.bak.*`, sort by mtime descending.
2. If exactly 1 backup AND its mtime is older than `stat -f %c <symlink>`: restore newest.
3. Otherwise: remove symlink only, leave backups in place, log "ambiguous backup state for `<dst>` — restore manually."

### Sentinel-block strip (with full-file backup per B3)

For each `(file, sentinel_pair)` to strip:

1. Save `<file>` → `<file>.uninstall.bak.<ts>` (atomic write).
2. Run python3 helper that finds ALL `# BEGIN <pair>` ... `# END <pair>` regions (line-anchored, exact-match sentinel) and removes each in order.
3. Handle edge cases (per /spec-review B8):
   - Unbalanced (BEGIN without END or END without BEGIN): refuse-strip with error; the full-file backup at step 1 is the recovery path.
   - Duplicate sentinel pairs: strip all of them (idempotent — install only writes one, but defensive).
4. Atomic write via `tmp + os.replace`.

### Exit codes

- `0` — dry-run completed OR `--apply` completed cleanly OR idempotent re-run.
- `1` — partial apply (some operations completed, some failed). Re-runnable; manual inspection recommended.
- `2` — invalid invocation (unknown flag, missing $REPO_DIR resolution).
- `3` — catastrophic failure (manifest corrupted, filesystem permission errors on multiple operations). Manual cleanup required; print exact paths.

## Integration

### Prerequisites

- **prereq #4 `install.sh-manifest-emit`**: must ship + pass tests + adopters re-install (or run a `migrate-to-manifest` one-shot).
- **prereq #5 `install.sh-uninstall-prep`**: CLAUDE.md sentinel ownership in `claude-md-merge.py` + opening-banner mention + (optional) existing-symlink-backup. Must ship + pass tests.

### Touches in this spec (uninstall-sh build)

- **`uninstall.sh`** (new file at repo root).
- **`tests/test-uninstall-sh.sh`** (new file). Registers in `tests/run-tests.sh`.
- **`scripts/_uninstall_helpers.py`** (new helper for manifest parse + sentinel-strip — heredoc-avoidance per `feedback_hook_stdin_heredoc` memory).
- **`README.md`**: paragraph in install section pointing to uninstall.
- **`docs/index.html`**: sentence in install notice referencing uninstall.
- **`CHANGELOG.md`** `[Unreleased]`: Added entry.

### Does NOT touch

- `~/.claude/projects/<slug>/memory/` (user-authored memory).
- `~/.claude/usage-data/` (Claude Code telemetry).
- `~/Library/Application Support/com.mitchellh.ghostty/` (not modified by install.sh).
- `$OBSIDIAN_VAULT_PATH` (user data).
- `~/.zshenv.local` (secrets file).
- `~/.config/monsterflow/config.json` (user config — agent_budget knob).
- launchd plists (none written by install.sh; audited rev2).

## Edge Cases

1. **Manifest present but corrupted JSONL** (one row malformed): skip the malformed row with warning; continue with other rows. Catastrophic if first-row schema_version unreadable → exit 3.
2. **Symlink target points outside `$REPO_DIR`**: skip + warn (cold-start) or refuse (manifest-mode: manifest says we own it; mismatch = user retargeted it post-install; warn + skip).
3. **Expected symlink is a regular file**: skip + warn.
4. **Orphaned `.bak.<ts>`** (target absent): list in dry-run; no action.
5. **`~/.zshrc` unbalanced sentinels** (BEGIN without END or vice versa): refuse-strip; full-file backup at scope #7 step 1 IS the recovery path.
6. **Duplicate sentinel pairs**: strip all (defensive idempotency).
7. **`graphify claude uninstall` subcommand absent**: detect via `graphify claude --help` grep; fall back to direct symlink + hook strip.
8. **Run from outside the repo**: resolve `$REPO_DIR` via `$(cd "$(dirname "$0")" && pwd)`.
9. **`$REPO_DIR` already `rm -rf`'d**: manifest mode still works (manifest has dst paths). Cold-start mode falls back to broken-symlink heuristic via `/MonsterFlow/` OR `/claude-workflow/` path substring.
10. **Manifest backup file checksum mismatch**: refuse-restore + actionable hint.
11. **`~/.zshrc` is itself a symlink**: follow link for grep + write target; atomic write via same-dir tmp at the target location.
12. **`--apply` partial failure**: print exact failing path; exit 1. Re-run is idempotent and retries.
13. **Multiple installs over time** (multi-install manifest with 2+ install sessions): reverse in reverse-chronological order (newest install's mutations first, oldest last). Older `.bak.<ts>` files from earlier installs may still be on disk — they're not in the manifest's restore list, so they remain (correct behavior; they're not what we replaced).

## Acceptance Criteria

**22 top-level ACs** (~28 enumerable sub-cases after AC19a-d + AC20a-c splits + AC6b user-edit variant + AC23 multi-clone per /check MF5) in `tests/test-uninstall-sh.sh` (per /spec-review CG2/CG3 + IC1-IC5 + OB6 + /check iter2 expansions).

### Manifest-mode ACs

1. **AC1 — dry-run with no side effects**: `bash uninstall.sh` from fully-installed `$HOME` stub produces expected plan output AND `diff -r $HOME $HOME_SNAPSHOT_BEFORE` shows zero diff under `~/.claude/`, `~/.zshrc`, `~/CLAUDE.md`, `~/.config/{cmux,ghostty,monsterflow}/`, `~/.tmux.conf` paths.
2. **AC2 — `--apply` removes all manifest-recorded symlinks** under `~/.claude/{commands,agents,personas,templates,hooks,scripts,skills,schemas,domain-agents,commands/_prompts}` AND `~/.claude/settings.json` AND `~/.local/bin/{autorun,graphify}` AND every path the manifest records as `op:symlink`.
3. **AC3 — sentinel blocks stripped from `~/.zshrc`** AND surrounding content (lines BEFORE the first BEGIN and AFTER the last END) matches the pre-install snapshot byte-for-byte (`diff` against `~/.zshrc.pre-install-snapshot` returns empty).
4. **AC4 — manifest-named backup restored**: `~/.tmux.conf` post-uninstall is a regular file matching `~/.tmux.conf.original`. Newest-by-name backup recorded in manifest wins (multiple `.bak.<ts>` don't confuse — manifest names the one).
5. **AC5 — older backups stay in place**: `.bak.<older-ts>` files not named by the manifest remain on disk post-uninstall.
6. **AC6 — `~/CLAUDE.md` round-trip, unchanged case** (prereq #5 + uninstall): `bash install.sh && bash uninstall.sh --apply && diff ~/CLAUDE.md ~/CLAUDE.md.pre-install` → empty diff. Asserts `op:created_file` SHA-match branch: file is deleted (when pre-install file was absent and install created from template).
6b. **AC6b — `~/CLAUDE.md` user-edited case** (prereq #5 + uninstall): `bash install.sh && echo "USER NOTE" >> ~/CLAUDE.md && bash uninstall.sh --apply` → `~/CLAUDE.md` still exists; contains `"USER NOTE"`; the MonsterFlow sentinel-bracketed block is gone; full-file backup at `~/CLAUDE.md.uninstall.bak.<ts>` exists with the pre-strip content. Asserts SHA-mismatch preserve-and-strip-managed-block branch.
7. **AC7 — sentinel-block full-file backup**: before strip, `~/.zshrc.uninstall.bak.<ts>` and `~/CLAUDE.md.uninstall.bak.<ts>` exist; content matches pre-strip file byte-for-byte.
8. **AC8 — idempotent re-run via manifest tombstone**: `bash uninstall.sh --apply; bash uninstall.sh --apply` — first run renames manifest to `~/.claude/.monsterflow-install-manifest.uninstalled.<ts>` (tombstone exists, original manifest path absent); second run finds no active manifest, exits 0, output contains canonical `"Nothing to remove"` (single canonical string referenced in dry-run, apply, and AC; per IC4). Failed partial-apply (exit 1) does NOT tombstone — assertion: manifest stays at original path so retry resumes.
9. **AC9 — non-MonsterFlow symlink skipped**: `~/.claude/commands/spec.md` repointed to `/tmp/custom` → uninstall logs warning, does NOT remove.
10. **AC10 — regular file in symlink slot skipped**: regular file at expected symlink path → warning, no delete.
11. **AC11 — unbalanced sentinel refuses strip** (BEGIN without END): warning + refuse-strip + full-file backup at AC7 is the recovery path. `--apply` aborts the zshrc strip only; explicitly enumerated continuing operations: symlink removals AND CLAUDE.md strip AND `.bak` restores AND graphify reversal still proceed.
12. **AC12 — END without BEGIN AND duplicate sentinel pair handling**: END-without-BEGIN → same refuse-strip path as AC11. Duplicate BEGIN/END pairs → strip both (defensive idempotency).
13. **AC13 — graphify ownership detection**: PATH stub puts unrelated `graphify` first → uninstall checks `readlink ~/.local/bin/graphify` (not `command -v`), only invokes `graphify claude uninstall` against the MonsterFlow-managed symlink target.
14. **AC14 — graphify fallback when subcommand absent**: stub `graphify` to omit `claude uninstall` subcommand → fall back to direct symlink + hook strip; dry-run output names the fallback explicitly.
15. **AC15 — third-party tools left in place**: post-`--apply`, `Obsidian.app` + `~/.local/venvs/graphify/` + `~/.local/bin/graphify` (when manifest says NOT MonsterFlow-installed; OR present as detector-skip case) + `cmux` binary all exist. Dry-run output contains exact strings `brew uninstall --cask obsidian`, `rm -rf ~/.local/venvs/graphify`, `brew uninstall cmux` (assertion per CG2 hint-text grep).
16. **AC16 — `~/.obsidian-wiki/config` heuristic**: manifest says MonsterFlow created it → remove. Manifest says NOT MonsterFlow (or cold-start) → leave with warning. AC asserts both branches.
17. **AC17 — no-backup branch**: when manifest references a backup file that's been deleted, uninstall removes the symlink only, prints "backup file moved/deleted; original lost." No hard error; exits 0.
18. **AC18 — manifest backup checksum mismatch**: backup file present but `sha256sum` differs from manifest → refuse-restore with documented hint; symlink still removed. Exit 0.
19. **AC19 — exit codes correct** (per /spec-review CG3 — post-failure state too): dry-run → 0; clean apply → 0; idempotent re-run → 0; partial-apply failure (force a permission error mid-way) → 1 AND completed operations stay completed AND fresh re-run finishes remaining; catastrophic failure (corrupt manifest) → 3; bad flag → 2.
20. **AC20 — cold-start mode** (no manifest): bash uninstall.sh on a $HOME with no manifest file → falls back to filesystem detection; detector-fallback backup restore (single-backup-older-than-symlink rule) works correctly; AC asserts both ambiguous-backup-skipped case AND single-backup-restored case AND `claude-workflow/` pre-rebrand path recognition.

### Cross-cutting ACs

- **AC21 — `install.sh` opening banner references uninstall** (prereq #5 grep-test, cross-spec): `install.sh` contains `bash uninstall.sh` mention in BOTH the opening banner AND end-block Next Steps.
- **AC22 — README and docs/index.html updated**: each file contains `uninstall.sh` reference.

## Open Questions

1. **Granularity of manifest schema versioning**: schema_version=1 declared on first manifest row. When a future prereq #4 revision changes manifest fields, what's the migration path? (Defer to /blueprint of prereq #4 — out of scope here.)
2. **Migration for existing installs**: today's adopters who already ran install.sh have no manifest. Three options: (a) require re-install to seed manifest (annoying); (b) ship a `scripts/migrate-to-manifest.sh` one-shot (one-time cost); (c) rely on detector-fallback for them forever (works but reduces safety). Lean: (b) but this is /blueprint territory for prereq #4.
3. ~~Exit code 1 vs 3 in cold-start partial failures~~ **PINNED at /check iter2 (MF6): exit 1** (re-runnable; monotonic; same as manifest-mode exit 1).
4. **Detector-fallback sunset** (per /spec-review I10 + /check SF10): detector-fallback is intentionally supported for cold-start AND 1-2 releases post-prereq-#4. After that window, uninstall requires a manifest for destructive restores and config removal; cold-start adopters must run a `scripts/migrate-to-manifest.sh` one-shot first. Migrate-to-manifest is part of prereq #4 scope.

## Notes

- `gate_max_recycles` deliberately omitted (deprecated per CLAUDE.md guard).
- `tags: []` — closed enum doesn't include "tooling/uninstall." `pipeline` and `refactor` don't fit.
- **Rev2 changelog vs rev1**:
  - Architecture pivoted from pure detect-and-reverse → manifest-first + detector-fallback hybrid (Codex B1).
  - Install surface list completed: added schemas, domain-agents, settings.json (file not dir), commands/_prompts, ~/.local/bin/autorun, git hooks (Codex B2).
  - Sentinel-strip now writes full-file backup before mutation (B3 — 3-way convergent finding).
  - CLAUDE.md retrofit + banner update + link_file extension carved into prereq #5 (`install.sh-uninstall-prep`) per Scope S1/S2 (B4 + I1).
  - .bak restore replaced "newest by mtime" with manifest-named-and-checksummed; detector-fallback explicitly conservative (B5).
  - graphify ownership detection via `readlink ~/.local/bin/graphify`, not `command -v graphify` (B6).
  - Added ACs: claude-workflow path (B7); END-without-BEGIN + duplicates (B8 part 1); post-failure state (B8 part 2 + CG3); no-backup branch (CG2); hint-text grep (CG2); manifest checksum (new); cold-start mode (new). Total 20 + 2 cross-cutting.
  - Explicit OOS: `~/.zshenv.local` (O2), `~/.config/monsterflow/` (O3), launchd plists (verified absent), concurrent install/uninstall (no lock), existing-symlink overwrite (acknowledged).
  - OQ5 closed (no test-suite at end). OQ items reduced from 5 → 3 (manifest schema, migration, cold-start exit codes — all blueprint-level).
  - Approach compressed: removed install.sh line numbers + algorithm details that belong in /blueprint (Scope S4).
  - Exit code 1 split: 1 = partial dirty (re-runnable), 3 = catastrophic (manual cleanup) (O1).
  - Idempotent message canonicalized: single `"Nothing to remove"` string referenced across dry-run, apply, AC8 (IC4).
  - AC1 scoped to specific paths instead of `diff -r $HOME` (OB1).
