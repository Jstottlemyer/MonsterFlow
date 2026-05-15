---
tags: [api, data, docs, integration, migration, scalability, security, ux]
tags_provenance:
  baseline: [api, data, integration, migration, scalability, security, ux]
  llm_added: [docs]
  user_overrides: []
gate_mode: permissive
---

# install-obsidian-vault-baseline Spec (V3 — fixes 2 V2 architectural blockers + 3 majors)

**Created:** 2026-05-14 (V1) · **Revised:** 2026-05-15 (V2, V3)
**Constitution:** none — MonsterFlow personal-tooling repo uses pipeline-default personas
**Confidence:** Scope 0.95 · UX 0.94 · Data 0.94 · Integration 0.96 · Edge 0.92 · Acceptance 0.94 · **avg 0.94**

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
- New helper function `manage_scaffold_marker()` in `install.sh`, called from the END of `install_obsidian_env()` (immediately before `echo "  ✓ Obsidian env configured"` at install.sh:971). The helper resolves `vault_path` itself (works for both first-install and re-run paths — see Integration section), then performs the empty-check + marker write OR the scaffold-detection + stale-marker sweep.
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
3. **NEW: marker management at end of install_obsidian_env**. The helper `manage_scaffold_marker()` is called from install.sh:971 (immediately before the existing `echo "  ✓ Obsidian env configured"`). Critically, it works for BOTH paths: first-install (the `else` branch wrote the config + sentinel) AND re-run (the `if [ -f "$config" ]` branch was a no-op). It resolves `vault_path` itself via `parse_obsidian_config`:
   ```bash
   manage_scaffold_marker() {
       # Resolve vault path independently — works regardless of which branch above ran.
       local resolved_path
       resolved_path="$(parse_obsidian_config 2>/dev/null)" || resolved_path=""
       if [ -z "$resolved_path" ] || [ ! -d "$resolved_path" ]; then
           return 0   # No config or path missing — nothing to mark
       fi

       # Stage A: cruft strip
       local non_cruft_count
       non_cruft_count=$(find "$resolved_path" -mindepth 1 -maxdepth 1 \
           ! -name '.DS_Store' ! -name '.Spotlight-V100' ! -name '.fseventsd' \
           ! -name '.obsidian' ! -name '.git' ! -name '.scaffold-pending' \
           2>/dev/null | wc -l | tr -d ' ')
       if [ "$non_cruft_count" = "0" ]; then
           # Empty after cruft strip → write marker (no scaffold-marker check needed)
           if ! touch "$resolved_path/.scaffold-pending" 2>/dev/null; then
               add_install_warning "vault read-only — could not write $resolved_path/.scaffold-pending. Run /wiki-setup manually when ready."
               return 0
           fi
           echo "  WROTE:    $resolved_path/.scaffold-pending (run /wiki-setup in your next Claude session)"
           return 0
       fi

       # Stage B: vault has content — check scaffold markers (V3 success predicate, .env dropped per Codex I2)
       local scaffold_markers=0
       for m in concepts entities _archives _raw index.md log.md .obsidian; do
           [ -e "$resolved_path/$m" ] && scaffold_markers=$((scaffold_markers + 1))
       done
       if [ "$scaffold_markers" -ge 3 ]; then
           # Already scaffolded → sweep stale marker if any
           if [ -e "$resolved_path/.scaffold-pending" ]; then
               rm -f "$resolved_path/.scaffold-pending"
               echo "  REMOVED:  stale $resolved_path/.scaffold-pending (vault already scaffolded)"
           fi
       fi
       # Stage C (vault has user content but isn't scaffolded): silent no-op (intentional — adopter's content, not our concern)
   }

   # Called from install_obsidian_env, immediately before the final "✓ Obsidian env configured" echo:
   manage_scaffold_marker
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

### CLAUDE.md addition (verbatim authored content) — V3 reframe per Codex I1

Add to `CLAUDE.md` under a new `## Obsidian vault scaffolding (post-install)` section, near the existing Knowledge Layer / Obsidian content:

```markdown
## Obsidian vault scaffolding (post-install)

**Preflight check for wiki-related work:** Before responding to any wiki-* command (`wiki-update`, `wiki-query`, `wiki-ingest`, `wiki-capture`, `wiki-export`, `wiki-lint`) OR before `/wrap`'s Phase 2c wiki integration, check whether `$OBSIDIAN_VAULT_PATH/.scaffold-pending` exists.

If the marker exists, install.sh detected an empty vault but the upstream wiki structure has not been built yet. Suggest the adopter run `/wiki-setup` (from the upstream `Ar9av/obsidian-wiki` skills) before proceeding with the wiki-related ask.

**Marker cleanup:** After `/wiki-setup` completes successfully — confirmed by the vault now containing at least 3 of: `concepts/`, `entities/`, `_archives/`, `_raw/`, `index.md`, `log.md`, `.obsidian/` — delete the `.scaffold-pending` marker file. Do NOT remove the marker if /wiki-setup did not run or did not complete successfully.

If `/wiki-setup` is not available in the current session, the adopter still needs to install the wiki skills (see `install-obsidian-wiki-auto-clone` in BACKLOG.md / future spec). Surface the marker once with a one-line note and proceed with the wiki-related ask using whatever capability is currently installed.

This preflight does NOT fire on session start or for non-wiki work — only when the user requests something wiki-adjacent.
```

**V3 rationale (per V2 Codex I1):** earlier drafts said "when you start a session" — Claude doesn't proactively inspect filesystem state unless a user request triggers relevant behavior. Reframing as a *preflight for wiki-related commands* makes the instruction enforceable. **V3 success predicate (per V2 Codex I2):** dropped `.env` from the predicate; upstream `wiki-setup` writes `.env` separately (may target the tool repo, not `$vault`), so requiring it would block the marker cleanup after legitimate /wiki-setup completion. Used `≥ 3 of 7 indicators` to match the install.sh sweep threshold.

### Sentinel-block format

No change. `install_obsidian_env` already manages `~/.obsidian-wiki/config` and `~/.zshrc` sentinel block; V2 doesn't touch either.

## Integration

### install.sh hook point (V3 — fixes V2 B1' anchor-in-wrong-branch + B2' self-contradiction)

The marker logic lives in a **new helper function** `manage_scaffold_marker()` defined in `install.sh` and CALLED from inside `install_obsidian_env()` at the very end of the function — immediately before the final `echo "  ✓ Obsidian env configured"` (currently at install.sh:971) and before `return 0` (install.sh:972).

This anchor placement is critical: the existing `install_obsidian_env` body is wrapped in `if [ -f "$config" ]; then : ; else <work>; fi` (install.sh:905-970). Placing the helper call at line 971 — OUTSIDE that conditional, but still inside the function — means it fires unconditionally on every install.sh invocation, supporting both first-install (config absent → else branch ran) and re-run (config exists → if branch was a no-op).

The helper itself resolves `vault_path` via `parse_obsidian_config` (the existing function in install.sh), NOT by reading a local variable from one branch — this is what makes the helper robust to both code paths.

**Line-number anchor for `/build`:** insert the helper definition before `install_obsidian_env()` (around install.sh:900); insert the call `manage_scaffold_marker` at install.sh:971 (between the final `fi` of the conditional block and the success echo).

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

### Test cases (5 — Q-rev5 decision; V3 fixes test 5 setup per Codex I3)

1. **Empty vault → marker written** — `$vault_path` exists, is empty (no entries at all). `~/.obsidian-wiki/config` is fresh (absent before run, written during run pointing at `$vault_path`). After `install_obsidian_env` runs, `$vault_path/.scaffold-pending` exists and is 0 bytes; install.sh exit 0.
2. **Non-empty user content → no marker** — `$vault_path` contains `notes.md`. `~/.obsidian-wiki/config` written during run. After run, NO `.scaffold-pending` file exists; the user's `notes.md` is untouched; install.sh exit 0.
3. **Cruft-only vault → marker written** — `$vault_path` contains only `.DS_Store` + `.obsidian/`. After run, `.scaffold-pending` exists; cruft entries preserved unchanged.
4. **Already-scaffolded vault → no marker (cold first install)** — `$vault_path` contains `concepts/`, `entities/`, `_archives/`, `_raw/`, `index.md`, `log.md`, `.obsidian/` (7 scaffold markers, well above the ≥3 threshold). `~/.obsidian-wiki/config` is fresh. After run, NO `.scaffold-pending` written; all scaffold content untouched.
5. **Stale-marker sweep on rerun** — **V3 fixed setup**: pre-stage BOTH `~/.obsidian-wiki/config` (pointing at the test vault — simulating a prior install.sh run that wrote the config) AND `$vault_path` containing `concepts/`, `entities/`, `index.md` (≥3 scaffold markers from a prior /wiki-setup) PLUS a leftover `.scaffold-pending` (Claude failed to clean up). `~/.zshrc` already has the sentinel block. Run `bash install.sh`. The `if [ -f "$config" ]; then : ; fi` branch is the no-op path on this rerun; `manage_scaffold_marker` still runs at the function end. Assertion: `.scaffold-pending` removed; scaffold content untouched; no spurious writes to config or zshrc.

This test 5 setup specifically exercises the V3-fixed re-run path that V2's anchor couldn't reach (Codex I3 catch). The pre-staged config is the load-bearing detail.

### Test case 6 (V3 add — Codex I3 follow-up: read-only vault)

6. **Read-only vault → INSTALL_WARNINGS, exit 0** — `$vault_path` exists, is empty, but `chmod 555` (read-only). `touch` fails. After run, `INSTALL_WARNINGS` contains the "vault read-only" message; no marker file; install.sh exit 0 (does not propagate touch failure).

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

None remaining at confidence ≥ 0.94. V1's Open Question about `.manifest.json` schema is moot. V2's Codex-caught issues (anchor in wrong branch, spec self-contradiction, weak CLAUDE.md trigger, wrong success predicate, test 5 setup) are all addressed in V3.

## Notes for /spec-review V3 pass

- V1 blockers (B1-B5) all addressed in V2 → no resurfacing expected.
- V2 blockers (B1' anchor, B2' contradiction) addressed: anchor moved outside the conditional via the new `manage_scaffold_marker` helper called at install.sh:971; Integration + Scope now agree on placement.
- V2 majors I1-I3 addressed: CLAUDE.md reframed as wiki-preflight (not session-start); success predicate uses `concepts/, entities/, _archives/, _raw/, index.md, log.md, .obsidian/` (no `.env`, ≥3 threshold); test 5 setup pre-stages config + scaffolded vault.
- New defensive: V3 added case 6 (read-only vault) per Codex I3 follow-up.
