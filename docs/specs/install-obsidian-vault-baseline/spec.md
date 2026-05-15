---
tags: [api, data, docs, integration, migration, scalability, security, ux]
tags_provenance:
  baseline: [api, data, integration, migration, scalability, security, ux]
  llm_added: [docs]
  user_overrides: []
gate_mode: permissive
---

# install-obsidian-vault-baseline Spec (V2 — revised after Codex caught 5 architectural blockers)

**Created:** 2026-05-14 (V1) · **Revised:** 2026-05-15 (V2)
**Constitution:** none — MonsterFlow personal-tooling repo uses pipeline-default personas
**Confidence:** Scope 0.95 · UX 0.92 · Data 0.92 · Integration 0.95 · Edge 0.90 · Acceptance 0.92 · **avg 0.93**

## Summary

When `install.sh`'s existing `install_obsidian_env` validates an empty `$OBSIDIAN_VAULT_PATH`, write a 0-byte marker file at `$OBSIDIAN_VAULT_PATH/.scaffold-pending`. MonsterFlow's `CLAUDE.md` instructs Claude that the marker means "suggest the adopter run `/wiki-setup` before any wiki command, then remove the marker on success." The actual vault structure (9 directories, `.obsidian/` config, `index.md`, `log.md`, `.env`) is owned by the upstream `Ar9av/obsidian-wiki` `wiki-setup` skill — not re-implemented in bash.

## V2 revision context

V1 (2026-05-14) failed `/spec-review` with 5 architectural blockers:
- B1: invented `.manifest.json` schema (reality: upstream uses `.env`, no manifest file exists)
- B2: invented `~/.zshenv.local` config target (reality: `~/.obsidian-wiki/config` + `~/.zshrc` sentinel)
- B3: hook point inside `install_obsidian_env` ran after `do_knowledge_layer` already rendered (reality: install.sh:1065)
- B4: contradicted current non-interactive behavior (install.sh:912 returns early when default path missing)
- B5: 5-file scaffold under-delivered vs upstream `wiki-setup` (9 dirs + Obsidian config + index.md + log.md + .env)

V2 resolves all 5 by **shifting the scaffold work itself to upstream `/wiki-setup`** (run by Claude in the adopter's first session) and reducing install.sh's job to writing a single 0-byte marker file. The blockers dissolve: no manifest schema to get wrong, no new config target (we don't write any config — `install_obsidian_env` already does that), no hook-point conflict (we add code at the END of `install_obsidian_env`, after detection has already finished), no non-interactive behavior change (current behavior preserved verbatim), no under-scoped scaffold (we don't scaffold).

## Backlog Routing

| # | Item | Routing |
|---|------|---------|
| 1 | install-obsidian-vault-baseline (this spec) | (a) In scope (revised) |
| 2 | install-obsidian-wiki-auto-clone | (b) Stays in BACKLOG.md — sibling spec, ships independently |
| 3 | uninstall.sh reverter | (b) Stays in BACKLOG.md |

## Scope

**In scope:**
- 5-line addition to `install.sh` at the END of `install_obsidian_env()` (after config write + `~/.zshrc` sentinel append): if the now-validated `$vault_path` is empty (cruft-aware) AND not-yet-scaffolded (scaffold-marker check), `touch "$vault_path/.scaffold-pending"`.
- 1-paragraph addition to MonsterFlow's `CLAUDE.md` instructing Claude on the marker semantics (surface `/wiki-setup` suggestion + remove marker post-success).
- Belt-and-suspenders sweep: on subsequent `bash install.sh` runs, if marker exists AND vault is now scaffolded (≥2 of `concepts/`, `entities/`, `_archives/`, `_raw/`, `.env`), `rm` the stale marker.
- 5-case test harness at `tests/test-obsidian-vault-baseline.sh`.

**Out of scope:**
- The actual vault scaffolding (`mkdir concepts/ entities/ ...`, write `index.md`, write `.env`, etc.) — upstream `wiki-setup` owns this.
- Changes to `install_obsidian_env`'s existing config-write behavior, sentinel-block format, or non-interactive return-early logic.
- Cloning the upstream wiki-skills repo (sibling spec `install-obsidian-wiki-auto-clone`).
- `--reconfigure-vault` flag (no longer needed; marker can be touched by hand).
- doctor.sh row for this marker (Q9 decision held: scaffold-once action, not ongoing state).

## Approach

Maximally minimal: install.sh's job ends at "we noticed your vault is empty; here's a breadcrumb." Claude's job (via CLAUDE.md instruction) is to act on the breadcrumb when it sees it. Upstream `wiki-setup` does the actual file-creation work. This composes three independent surfaces without coupling them: install.sh stays bash-only and idempotent; MonsterFlow's CLAUDE.md grows by one paragraph; upstream wiki-setup is unchanged.

The original Q&A (V1) drove much detail (5-file template, manifest schema, prompt UX) that V2 deletes entirely. The retained decisions: cruft-allowlist algorithm for empty detection (Q6, expanded with scaffold-marker stage), integration point in `install_obsidian_env`. The Q-rev1 through Q-rev5 round nailed: deferral to /wiki-setup (Q-rev1.b), marker + CLAUDE.md hint (Q-rev2.b/b2), Claude-owned cleanup + install.sh sweep (Q-rev3.b), two-stage detection (Q-rev4.a), 5 test cases (Q-rev5.b).

## Roster Changes

No roster changes.

## UX / User Flow

### First-time install

1. Adopter runs `bash install.sh` (cold start).
2. Knowledge Layer stage runs `install_obsidian_env`:
   - Prompts for vault path (interactive) or uses `$OBSIDIAN_VAULT_PATH` / default `$HOME/Documents/Obsidian/wiki` (non-interactive).
   - Writes `~/.obsidian-wiki/config` + appends sentinel block to `~/.zshrc` (existing behavior — no change).
3. **NEW: vault-state classification** (5 lines added to `install_obsidian_env`, after the existing soft-warn about missing `.obsidian/`):
   ```bash
   # Stage A: cruft strip
   local non_cruft_count
   non_cruft_count=$(find "$vault_path" -mindepth 1 -maxdepth 1 \
       ! -name '.DS_Store' ! -name '.Spotlight-V100' ! -name '.fseventsd' \
       ! -name '.obsidian' ! -name '.git' ! -name '.scaffold-pending' \
       2>/dev/null | wc -l | tr -d ' ')
   if [ "$non_cruft_count" = "0" ]; then
       # Stage B+C: empty after cruft → write marker (skip Stage B since nothing to check)
       touch "$vault_path/.scaffold-pending"
       echo "  WROTE:    $vault_path/.scaffold-pending (run /wiki-setup in your next Claude session)"
   else
       # Stage B: check scaffold markers
       local scaffold_markers=0
       for m in concepts entities _archives _raw .env; do
           [ -e "$vault_path/$m" ] && scaffold_markers=$((scaffold_markers + 1))
       done
       if [ "$scaffold_markers" -ge 2 ]; then
           # Stage B-true: already scaffolded → sweep stale marker if any
           if [ -e "$vault_path/.scaffold-pending" ]; then
               rm -f "$vault_path/.scaffold-pending"
               echo "  REMOVED:  stale $vault_path/.scaffold-pending (vault already scaffolded)"
           fi
       else
           # Stage C: vault has user content but isn't scaffolded — leave alone
           :
       fi
   fi
   ```
4. Install.sh completes. Final output mentions the marker in the tail summary block (`INSTALL_WARNINGS`-adjacent informational line, not a true warning).

### First Claude session

1. Adopter opens Claude (anywhere — could be `cd $OBSIDIAN_VAULT_PATH` or in MonsterFlow itself).
2. Claude reads `CLAUDE.md` (project-level or `~/CLAUDE.md` if Claude is in the vault dir; for MonsterFlow we'll add the instruction to MonsterFlow's own `CLAUDE.md`).
3. The new CLAUDE.md paragraph (see Data section below) tells Claude: "If `$OBSIDIAN_VAULT_PATH/.scaffold-pending` exists, suggest `/wiki-setup` before any wiki-* command; after `/wiki-setup` completes, remove the marker."
4. Adopter runs `/wiki-setup` (upstream skill); vault gets the 9-directory structure + `.obsidian/app.json` + `index.md` + `log.md` + `.env`.
5. Claude removes the marker.

### Re-run install.sh after scaffold

1. `bash install.sh` again. `install_obsidian_env` runs as before.
2. Vault is now non-empty (has `concepts/`, `.env`, etc). Stage A's `non_cruft_count` is `>0`. Stage B fires: `scaffold_markers >= 2` → sweep stale marker if any (defensive — Claude should have removed it, but install.sh sweeps anyway).
3. Install.sh completes silently for this stage.

## Data & State

### Files written by this spec

1. **`$OBSIDIAN_VAULT_PATH/.scaffold-pending`** — 0-byte marker. Existence == "vault not yet scaffolded." File content is irrelevant; only the path matters. `touch`-created; chmod 644 (default umask).
2. **`CLAUDE.md` paragraph in `~/Projects/MonsterFlow/CLAUDE.md`** — see below.

### CLAUDE.md addition (verbatim authored content)

Add to `CLAUDE.md` under a new `## Obsidian vault scaffolding (post-install)` section, near the existing Knowledge Layer / Obsidian content:

```markdown
## Obsidian vault scaffolding (post-install)

When you start a session in this repo or anywhere `$OBSIDIAN_VAULT_PATH` resolves, check whether `$OBSIDIAN_VAULT_PATH/.scaffold-pending` exists. If it does, the adopter ran install.sh against an empty vault and the upstream wiki structure has not been built yet.

Before responding to any wiki-* command (`wiki-update`, `wiki-query`, `wiki-ingest`, etc.) or `/wrap`'s Phase 2c wiki integration, suggest the adopter run `/wiki-setup` (from the upstream `Ar9av/obsidian-wiki` skills) first. After `/wiki-setup` completes successfully (vault now has `concepts/`, `entities/`, `_archives/`, `_raw/`, `.env`), delete the `.scaffold-pending` marker file.

If `/wiki-setup` is not available in the current session, the adopter still needs to install the wiki skills (see `install-obsidian-wiki-auto-clone` in BACKLOG.md / future spec). In that case, surface the marker once with a one-line note and proceed.
```

### Sentinel-block format

No change. `install_obsidian_env` already manages `~/.obsidian-wiki/config` and `~/.zshrc` sentinel block; V2 doesn't touch either.

## Integration

### install.sh hook point (post-Codex-fix from V1.B3)

Inside `install_obsidian_env`, immediately after the existing soft-warn block:
```bash
if [ ! -d "$vault_path/.obsidian" ]; then
    echo "  ⚠ $vault_path/.obsidian/ not found — open Obsidian.app and create the vault to finish setup"
fi
```
Insert the vault-state classification block from the UX section above. This runs AFTER config is written and the path is known-good, but inside the function — so the marker write happens before `do_knowledge_layer` returns.

Line-number anchor for `/build`: target install.sh:935 (after the soft-warn, before the atomic config write at line 941).

### Touch points

- `install.sh` — ~25 LoC added inside `install_obsidian_env` (vault-state classification + marker write/sweep).
- `CLAUDE.md` — ~12 lines added (1 H2 section + 1 paragraph).
- `tests/test-obsidian-vault-baseline.sh` — new 5-case harness, ~180 LoC modeled on `test-install-knowledge-layer.sh`.
- `tests/run-tests.sh` — register the new test (1 line).
- `BACKLOG.md` — remove item #1 on ship; update v0.12.0 follow-up note to point to this spec's outcome.
- `CHANGELOG.md` — `[0.15.0]` (or current minor) entry.

### Sequencing relative to install-obsidian-wiki-auto-clone

This spec ships independently. The marker mechanism still works without the upstream wiki skills being installed (CLAUDE.md's instruction includes the "/wiki-setup unavailable" branch: surface a one-line note, proceed). The sibling spec, when shipped, makes `/wiki-setup` actually invokable from the adopter's Claude session.

## Edge Cases

1. **Vault path is a symlink** — install.sh resolves via the existing `vault_path="${vault_path/#\~/$HOME}"` expansion at install.sh:926. No additional canonicalization needed (V1's `readlink -f` was a Codex catch — BSD doesn't support `-f`; we drop the canonicalization entirely).
2. **Vault contains only `.git/`** — Codex C8 risk. Stage A's cruft list includes `.git/`, so this counts as empty → marker written. Adopter who `git init`'d a private notes repo gets one marker file written, which `/wiki-setup` would then process by adding the 9-directory structure ON TOP of their git repo (their content is preserved — wiki-setup uses `mkdir -p`). Test case (3) of the harness explicitly covers `.git/`-only state.
3. **Vault is read-only** — `touch` fails. `install_obsidian_env`'s existing path-validation already returns early on missing/unreadable paths. For read-only-but-extant paths, the touch failure should be logged to `INSTALL_WARNINGS` and the function should continue (per existing `add_install_warning` pattern in install.sh).
4. **Concurrent install.sh runs** — touching a marker file is idempotent; no `flock` needed for the marker itself. The sentinel-block append in install.sh is already guarded by `grep -qF "$begin"` (line 953) which handles the concurrency case the way it always has.
5. **Adopter runs `/wiki-setup` without the marker existing** — fine; upstream behavior unchanged. CLAUDE.md only prompts when the marker exists.
6. **Marker survives upstream `/wiki-setup` because Claude forgot to `rm`** — install.sh's belt-and-suspenders sweep (Stage B) catches this on the next install.sh re-run. Documented and tested in case 5.
7. **Vault has 1 of the 5 scaffold markers** (e.g., only `concepts/`) — Stage B's `>= 2` threshold means this is NOT considered scaffolded. Probably a partial/aborted /wiki-setup OR a coincidental user directory. Spec treats this as "user content present" (Stage C) — leave alone. Adopter's choice whether to manually run /wiki-setup or clean up first.

## Acceptance Criteria

### Test cases (5 — Q-rev5 decision)

1. **Empty vault → marker written** — `$vault_path` exists, is empty (no entries at all). After `install_obsidian_env` runs, `$vault_path/.scaffold-pending` exists and is 0 bytes; install.sh exit 0.
2. **Non-empty user content → no marker** — `$vault_path` contains `notes.md`. After run, NO `.scaffold-pending` file exists; the user's `notes.md` is untouched; install.sh exit 0.
3. **Cruft-only vault → marker written** — `$vault_path` contains only `.DS_Store` + `.obsidian/`. After run, `.scaffold-pending` exists; cruft entries preserved unchanged.
4. **Already-scaffolded vault → no marker** — `$vault_path` contains `concepts/`, `entities/`, `_archives/`, `_raw/`, `.env` (5 scaffold markers, well above the ≥2 threshold). After run, NO `.scaffold-pending` written; all scaffold content untouched.
5. **Stale-marker sweep** — `$vault_path` contains `concepts/`, `entities/`, AND a leftover `.scaffold-pending` from a prior run. After `bash install.sh` runs, `.scaffold-pending` is removed (Stage B sweep); scaffold content untouched. Test asserts both removal and preservation.

### Manual acceptance (author checklist, not a test)

- Author runs `bash install.sh` on a clean macOS machine with `$OBSIDIAN_VAULT_PATH` unset → defaults to `$HOME/Documents/Obsidian/wiki`; if path doesn't exist, install_obsidian_env returns early per existing behavior; if exists and empty, marker written.
- Author opens Claude in a project with this spec's CLAUDE.md change; if the marker exists in `$OBSIDIAN_VAULT_PATH`, Claude suggests `/wiki-setup` in its first response to any wiki-related ask.
- Author runs `/wiki-setup`; vault gets 9 dirs + index.md + log.md + .env; Claude removes the marker.
- Author re-runs `bash install.sh` → silent success on the Knowledge Layer stage (no spurious prompts, no re-write of marker).

### Definition of "shipped"

- All 5 tests pass under `bash tests/run-tests.sh`.
- `bash install.sh` on a clean machine completes without errors and writes the marker when expected.
- CLAUDE.md change pushed; visible to Claude in the next session.
- BACKLOG.md item #1 removed; CHANGELOG entry written.
- This spec's `/spec-review` returns PASS or PASS WITH NOTES on second-pass (this is V2; first pass was the FAIL that drove the rewrite).

## Open Questions

None remaining at confidence ≥ 0.90. The V1 Open Question about `.manifest.json` schema is moot — we don't write a manifest. The `--reconfigure-vault` flag is moot — adopter can `touch $vault/.scaffold-pending` by hand to re-trigger the CLAUDE.md prompt.

## Notes for /spec-review V2 pass

- Watch for resurfacing of V1 blockers: the spec should NOT reference `~/.zshenv.local`, `.manifest.json`, `readlink -f`, `--reconfigure-vault`, or a "5-file scaffold" anywhere except in the V2 revision context section (where they're explicitly documented as dropped).
- Codex should validate that the install.sh:935 hook anchor is real and the surrounding lines support a 25-LoC insertion without disturbing existing logic.
- Confirm CLAUDE.md instruction is unambiguous enough that Claude won't double-rm the marker or rm-too-eagerly (before /wiki-setup actually succeeds).
