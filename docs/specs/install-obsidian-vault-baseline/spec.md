---
tags: [api, data, docs, integration, migration, scalability, security, ux]
tags_provenance:
  baseline: [api, data, integration, migration, scalability, security, ux]
  llm_added: [docs]
  user_overrides: []
gate_mode: permissive
---

# install-obsidian-vault-baseline Spec

**Created:** 2026-05-14
**Constitution:** none — MonsterFlow personal-tooling repo uses pipeline-default personas (review/design/check)
**Confidence:** Scope 0.95 · UX 0.95 · Data 0.90 · Integration 0.95 · Edge 0.92 · Acceptance 0.92 · **avg 0.93**

## Summary

Ship a 5-file starter Obsidian vault template at `templates/obsidian-vault-baseline/` and have `install.sh`'s `install_obsidian_env` scaffold it to `$OBSIDIAN_VAULT_PATH` when the target directory is missing or empty (cruft-allowlist-aware). Adopter prompted before scaffold; respects existing non-empty vaults absolutely. Closes the v0.12.0 onboarding gap where adopters got `manual:0/6` wiki skills and an empty directory with no idea what goes in it.

## Backlog Routing

| # | Item | Routing |
|---|------|---------|
| 1 | install-obsidian-vault-baseline (this spec) | (a) In scope |
| 2 | install-obsidian-wiki-auto-clone | (b) Stays in BACKLOG.md — separate concern (tool repo vs vault content) |
| 3 | uninstall.sh reverter | (b) Stays in BACKLOG.md — orthogonal, M-sized |

## Scope

**In scope:**
- `templates/obsidian-vault-baseline/` directory with 5 starter files (see Data section).
- `scaffold_obsidian_vault_baseline()` helper in `install.sh`, called from inside `install_obsidian_env` after `$OBSIDIAN_VAULT_PATH` is resolved.
- Empty-detection: cruft-allowlist (`.DS_Store`, `.Spotlight-V100`, `.fseventsd`, `.obsidian/`, `.git/`) ignored; any other content blocks scaffold.
- Adopter `(Y/n)` prompt before scaffold (default Y; auto-Y under `--non-interactive`).
- Prompt for `$OBSIDIAN_VAULT_PATH` when unset (default `~/Documents/ObsidianVault`); write absolute path to `~/.zshenv.local` sentinel block.
- Idempotent re-run: present-status one-liner in install transcript when baseline already exists.
- 6-case test harness under `tests/test-obsidian-vault-baseline.sh`.

**Out of scope:**
- Cloning the upstream `Ar9av/obsidian-wiki` tool repo (handled by separate `install-obsidian-wiki-auto-clone` spec).
- Drift detection / refresh / template versioning (Q7 decision).
- doctor.sh row for this scaffold (Q9 decision).
- Migrating existing vaults (the empty-or-missing guard makes this explicit).

## Approach

Direct extension of the existing `install_obsidian_env` flow — no new install.sh stage, no new doctor section, no new sentinel-block format. Template content authored fresh in MonsterFlow voice (Q4) rather than mirrored from the upstream tool repo (lower fidelity dependency on a third-party README that may rename or restructure). Uses the same idempotency posture as v0.12.0 detect-only stages (Q7): present-status one-liner when re-run finds baseline already in place.

## Roster Changes

No roster changes — install.sh / Bash work falls under MonsterFlow's existing review/design/check personas. No domain agents added.

## UX / User Flow

1. Adopter runs `bash install.sh` (cold start, fresh machine).
2. Knowledge Layer stage reaches `install_obsidian_env`.
3. **`$OBSIDIAN_VAULT_PATH` resolution:**
   - If set in env, use it (tilde-expand before any FS op per `feedback_tilde_expansion_in_bash_config_reads`).
   - If unset and interactive: prompt `"Where should your Obsidian vault live? [default: ~/Documents/ObsidianVault]:"`. Tilde-expand the input. Append to `~/.zshenv.local` sentinel block (chmod 600).
   - If unset and `--non-interactive`: use default `$HOME/Documents/ObsidianVault`, write to `~/.zshenv.local` sentinel block, log to INSTALL_WARNINGS so adopter sees it in tail summary.
4. **Empty check:**
   - Dir doesn't exist → `mkdir -p`; treat as empty.
   - Dir exists → run cruft-allowlist scan (Q6 algorithm). Empty after cruft strip → proceed. Non-empty → skip with log line `Obsidian vault not empty at <path> — baseline scaffold skipped (existing content preserved).`
5. **Scaffold prompt (interactive only):**
   - `"Found empty vault at <path>. Scaffold 5 starter files (README.md, index.md, .manifest.json, projects/.gitkeep, _raw/.gitkeep)? (Y/n):"`.
   - Default Y on bare-Enter; explicit `n` skips with a one-liner explaining how to scaffold later.
   - Under `--non-interactive`: auto-Y, surface in INSTALL_WARNINGS tail summary block.
6. **Scaffold action:** copy `templates/obsidian-vault-baseline/*` to `$OBSIDIAN_VAULT_PATH`. Atomic per-file (tmp + rename). Set `.manifest.json` permissions to 644.
7. **Success confirmation:** `✓ Obsidian vault baseline scaffolded (5 files) at <path>`. Adopter opens Obsidian.app, points it at `$OBSIDIAN_VAULT_PATH`, sees `index.md` as the front page.
8. **Re-run path** (subsequent `bash install.sh`): present-status one-liner — `Obsidian vault baseline: present (5 files at <path>)`. No prompt, no action.

## Data & State

### Template files (5)

Located at `templates/obsidian-vault-baseline/` in the MonsterFlow repo:

1. **`README.md`** — terse first-five-minutes orientation. Three sections: "what this is" (1 paragraph), "the 6 skills" (one-line summary per skill, names only), "first session" (`capture this: X` → `/wrap` → `what do I know about X` example). Authored in MonsterFlow voice (long comma-stitched sentences per `user_writing_voice`), no em-dashes (per `feedback_no_em_dashes`).
2. **`index.md`** — vault front page. Hand-authored walkthrough (Q4 decision) showing the wiki workflow with one example wikilink (`[[example-page]]`) to demonstrate the syntax. Frontmatter includes `summary:` field per obsidian-wiki contract.
3. **`.manifest.json`** — initialized to the schema expected by the upstream `wiki-update` / `wiki-ingest` skills (see Open Questions — schema not yet confirmed). Working assumption: `{"version": 1, "pages": [], "last_updated": null}`.
4. **`projects/.gitkeep`** — empty placeholder so the `projects/` subdir exists. The 6 wiki skills assume this subdir for per-project knowledge pages.
5. **`_raw/.gitkeep`** — empty placeholder for the raw capture queue (the inbox `wiki-capture` writes to, processed by `wiki-ingest` at /wrap).

### Sentinel block in `~/.zshenv.local`

When prompting for `$OBSIDIAN_VAULT_PATH`, install.sh writes:

```bash
# === MonsterFlow: OBSIDIAN_VAULT_PATH (vault-baseline) ===
export OBSIDIAN_VAULT_PATH="/Users/<adopter>/Documents/ObsidianVault"
# === /MonsterFlow: OBSIDIAN_VAULT_PATH ===
```

Absolute path (tilde pre-expanded). Sentinel-bracketed for idempotent re-runs and clean reversal by future `uninstall.sh`.

## Integration

### install.sh hook point

Inside the existing `install_obsidian_env()` function, after `$OBSIDIAN_VAULT_PATH` is resolved (or prompted) and before the Knowledge Layer wiki-skills detection (so the scaffold runs first, then wiki detection reports against a real vault).

### Function signature

```bash
scaffold_obsidian_vault_baseline() {
    # Args: $1 = vault path (absolute, tilde-expanded)
    # Returns: 0 on success / already-present / adopter-declined
    #          non-zero on hard error (template-source missing, write failed)
    # Side effects: copies 5 files to $1, prints status to stdout, may append to INSTALL_WARNINGS
}
```

### Touch points

- `install.sh` — new helper function + one call site in `install_obsidian_env`. Estimated ~80 LoC.
- `templates/obsidian-vault-baseline/` — 5 new files (~150 lines of content total: README + index.md prose, plus .manifest.json + 2 .gitkeep).
- `tests/test-obsidian-vault-baseline.sh` — new 6-case harness (~250 LoC mirroring the `test-install-knowledge-layer.sh` shape).
- `tests/run-tests.sh` — register the new test (1 line).
- `BACKLOG.md` — remove item #1 (this spec) on ship.

### Sequencing relative to `install-obsidian-wiki-auto-clone`

This spec can ship independently. The other spec adds wiki-skills cloning; the two compose naturally (vault scaffolded → wiki skills detected as `auto:6/6` instead of `manual:0/6`). Order is not constrained — either can ship first.

## Edge Cases

1. **`$OBSIDIAN_VAULT_PATH` resolves to a symlink** — `readlink -f` the path before all FS ops; scaffold lands on the real target. The sentinel block in `~/.zshenv.local` records the user-supplied path (not the resolved one) so user intent is preserved.
2. **Vault path contains spaces** — always quote `"$VAULT_PATH"` in install.sh; tests cover this in case (c) of the harness if Q8's option (b) is extended (we chose b → 6 cases; this lives in Open Questions as a defensive-coding reminder).
3. **Tilde in user-typed path** — adopter types `~/MyVault`; install.sh applies `${VAR/#\~/$HOME}` BEFORE writing to sentinel block (per `feedback_tilde_expansion_in_bash_config_reads`).
4. **`templates/obsidian-vault-baseline/` missing in the cloned repo** — hard error: `Template source missing at <path>. Re-clone or check repo integrity.` Refuses scaffold, surfaces in tail summary.
5. **Adopter declines scaffold (`n` at prompt)** — log line: `Vault baseline skipped per adopter choice. Re-run with bash install.sh --reconfigure-vault when ready.` (The `--reconfigure-vault` flag is a documented escape hatch; implementation deferred to first issue request — adding it preemptively violates YAGNI.)
6. **Cruft accumulates after first install** — adopter opens Obsidian.app once (creates `.obsidian/`), then closes without writing notes. Re-run install.sh: `.obsidian/` is on the allowlist, so empty-detection still considers the vault empty and proposes scaffold. Edge case is fine — scaffold is what we want here.
7. **Write race** — adopter has Obsidian.app open on the vault path during scaffold. File-level race on `index.md` etc. Per-file atomic writes (tmp + rename) avoid corruption; Obsidian.app's file watcher picks up new files as if the user added them externally.
8. **Disk full / permission denied** — bubble up the bash error, log to INSTALL_WARNINGS, exit with non-zero from `scaffold_obsidian_vault_baseline()` but continue install.sh (do not exit the whole install — vault baseline is not a hard dependency of the rest of the install).

## Acceptance Criteria

### Test cases (6 — Q8 decision)

1. **Cold scaffold** — empty existing dir + interactive + Y at prompt → all 5 files present, `.manifest.json` valid JSON, no warnings.
2. **Missing dir** — `$OBSIDIAN_VAULT_PATH` points to non-existent path + interactive + Y → `mkdir -p` runs, 5 files present.
3. **Idempotent re-run** — already-scaffolded vault → present-status one-liner emitted, no file writes, no prompt.
4. **Refuse on non-empty** — vault contains a user-authored `notes.md` → scaffold skipped, log line written, exit 0 (not a failure), user file untouched.
5. **Cruft allowlist** — dir contains only `.DS_Store` + `.obsidian/` → treated as empty, scaffold proceeds, the 2 cruft entries preserved.
6. **Env-var unset + non-interactive** — `OBSIDIAN_VAULT_PATH` unset + `--non-interactive` → default `$HOME/Documents/ObsidianVault` used, sentinel block written to `~/.zshenv.local`, scaffold proceeds, tail-summary warning emitted listing the default path used.

### Manual acceptance

- `bash install.sh` on a fresh machine (or with `$OBSIDIAN_VAULT_PATH` unset) produces a working vault that opens cleanly in Obsidian.app with `index.md` as the front page.
- The 5 starter files read naturally to a first-time adopter who has never seen the wiki skills — no jargon-heavy prose, no broken wikilinks beyond the intentional example.
- `bash install.sh` re-run on the same machine emits no spurious prompts and the install transcript shows `Obsidian vault baseline: present (5 files at <path>)`.

### Definition of "shipped"

- All 6 tests pass under `bash tests/run-tests.sh`.
- `bash install.sh` end-to-end on a clean macOS adopter machine completes without errors.
- v0.12.0's `manual:0/6` wiki-skills reporting unchanged (this spec doesn't touch wiki-skills detection — only vault content).
- BACKLOG.md item #1 removed; CHANGELOG.md gets `[0.15.0]` entry (or whatever minor version is current at ship time).

## Open Questions

1. **`.manifest.json` initial schema** (deferred to implementation) — the exact JSON the upstream `Ar9av/obsidian-wiki` skills expect (`wiki-update` writes it, `wiki-ingest` reads it). Working assumption: `{"version": 1, "pages": [], "last_updated": null}`. Resolve at `/build` time by reading the upstream tool repo's source-of-truth file, NOT by guessing. If the schema is more elaborate than this, that fact is local and doesn't change anything in this spec — only the literal contents of the template file.
2. **`--reconfigure-vault` escape hatch** (deferred) — Edge Case 5 documents the flag in a log line but doesn't implement it. YAGNI until an adopter reports being stuck after declining the scaffold prompt. Track in BACKLOG.md as a follow-up note when this spec ships.
3. **Vault path validation** — should install.sh refuse paths under `/System`, `/usr`, `/private`, etc.? Right now we trust the adopter. Probably fine for v1, revisit if anyone foot-guns themselves.
