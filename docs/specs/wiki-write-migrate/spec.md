---
created: 2026-05-15
revision: V2 (post-spec-review, F1 empirically verified)
constitution: none
confidence:
  scope: 0.95
  ux: 0.92
  data: 0.94
  integration: 0.92
  edges: 0.92
  acceptance: 0.95
gate_mode: permissive
tags: [api, data, docs, integration, migration, refactor, scalability, security, ux]
tags_provenance:
  baseline: [api, data, integration, scalability, security, ux]
  llm_added: [docs, migration, refactor]
  user_overrides: []
---

# wiki-write-migrate Spec

**Created:** 2026-05-15
**Revision:** V2 — folds /spec-review F1-F5 architectural findings + 11 contract refinements. F1 empirically verified via Obsidian spike at `~/Projects/_spike-f1-wiki-write-migrate/` (2026-05-16, all 5 link probes resolved purple).
**Constitution:** none (MonsterFlow personal-tooling repo; pipeline owns roster)
**Confidence:** scope 0.95, ux 0.92, data 0.94, integration 0.92, edges 0.92, acceptance 0.95
**gate_mode:** permissive

## F1 Verification (added in V2)

The spec's foundational assumption — that `[[slug]]` resolves to `projects/<slug>/index.md` in Obsidian — was tested empirically on 2026-05-16. A fixture vault under `~/Projects/_spike-f1-wiki-write-migrate/` created `projects/spike-target/index.md` (frontmatter `aliases: [spike-target, "Spike Target"]`) and `concepts/spike-link-tester.md` (containing 5 link-form probes). All 5 probes resolved in Obsidian's live preview:

| Probe | Link form | Result |
|-------|-----------|--------|
| P1 | `[[spike-target]]` (bare slug) | resolved via alias |
| P2 | `[[Spike Target]]` (Title Case) | resolved via alias |
| P3 | `[[spike-target/index]]` (full path) | resolved via path |
| P4 | `[[spike-target/]]` (folder+slash) | resolved via folder→index auto-fold |
| P5 | `[[Spike-Target]]` (case variant) | resolved via case-insensitive alias |

**Conclusion:** F1 holds, conditional on the migrated page's `aliases:` array including the **canonical slug** (not just the old human title). V2's AC #6 reflects this fix.

**Bonus safety net (P4):** Obsidian auto-folds `[[folder/]]` to `folder/index.md` — robust against the rare user who writes folder-with-slash link forms.

## Summary

`wiki-write-conventions` (v0.16.0, shipped 2026-05-15) handles NEW wiki writes deterministically: canonical slug rules, folder+index for projects, atomic write, lint that catches drift. This spec handles EXISTING wrong-structure pages — the cleanup pass. Adds a `--migrate` mode to `scripts/wiki-write.py` (routing to a new `scripts/_wiki_migrate.py` module) that scans the vault, proposes renames + wikilink rewrites + alias preservation, and executes them under a durable journal that supports `--resume` after crash. Collisions are migrated-around (skipped + reported); the user resolves manually or with `--force-overwrite`. Discovery is via the existing `/wrap` Phase 2c Step 3b lint — no inline prompt, the lint surfaces the command and the user runs it when ready. Two-step UX: `--dry-run` shows the plan, plain `--migrate` executes. No interactive prompts during execution.

## Backlog Routing

| Item | Source | Routing |
|------|--------|---------|
| resolver-recovery-shell-owned | BACKLOG.md (added today) | stays — unrelated to wiki migration |
| install-obsidian-wiki-auto-clone | BACKLOG.md | stays — different surface (install of upstream tool, not vault migration) |
| uninstall.sh reverter | BACKLOG.md | stays — different concern |
| PR #10 plot layer review | BACKLOG.md | stays — different concern |

No backlog items merge into this spec. (The `wiki-write-migrate` entry in BACKLOG.md gets removed when this spec ships, per the standard pipeline convention.)

## Scope

**In scope:**

- A `--migrate [--dry-run] [--resume] [--force-overwrite]` mode added to `scripts/wiki-write.py` that scans `<vault>/{projects,concepts,entities}/` for convention violations and produces a migration plan: rename targets + wikilink rewrites + alias preservations.
- Migration code lives in `scripts/_wiki_migrate.py` (new module, ~400 LoC), imported and dispatched by wiki-write.py — single CLI surface, separated implementation.
- **Wikilink rewriting** uses Obsidian's native shortest-unique-path resolver model: `[[Welcome]]` becomes `[[welcome]]` when the new slug is uniquely identifiable across the vault; ambiguous targets get the disambiguating folder prefix `[[projects/welcome|Welcome]]`. Computed against the POST-migration vault state for every link.
- **Durable journal** at `<vault>/.migration-journal.jsonl` recording each rename tuple before the rename happens. On clean completion, journal archived to `<vault>/.migration-journal-<ts>.jsonl.done`. `--resume` reads the journal, completes any in-flight Phase A renames, then runs Phase B link rewrites against the journal's (old, new) mapping. Journal is correctness-mandatory — Phase B's rewriter cannot recover the (old → new) basename mapping from filesystem state alone, so the journal IS the durable mapping.
- **Journal schema versioned (V2 — fixes F6)** — every journal row includes `schema_version: 1` so future `_wiki_migrate.py` upgrades can detect and refuse incompatible journals (`MigrationJournalCorruptError`, exit 5). Future schema bumps (e.g., new `phase:` variants beyond `rename`) get explicit version handling in the reader.
- **Advisory lock against concurrent invocations (V2 — fixes F5)** — Phase A acquires an exclusive `fcntl.flock()` on `<vault>/.migration-journal.jsonl` before writing any row. A second `--migrate` invocation while the first is in flight fails to acquire the lock and exits 1 with `migration already in progress; wait for completion or rm <vault>/.migration-journal.jsonl if no other process is running`. The lock is released when the journal handle closes (on clean completion OR crash).
- **Phase B post-run verification (V2 — fixes Codex C2 / F9)** — after Phase B completes, the rewriter does a final scan of the vault looking for any wikilinks whose target (per Obsidian's resolver model) is one of the journal's `old_basename` values that should have been rewritten. Any survivors are surfaced as warnings in stdout AND appended to `migration-report.md` under `## Verification Findings`. Non-blocking; informational. Helps detect rewriter bugs in development.
- **Phase B idempotency (V2 — fixes F2)** — the rewriter checks each `[[X]]` reference against TWO sets from the journal: `old_basenames` (the slugs we migrated FROM) and `new_basenames` (the slugs we migrated TO). A reference is rewritten only when it matches `old_basenames` AND does NOT already match `new_basenames` (case-insensitive). This handles the Welcome→welcome case: after pass 1 the reference is `[[welcome]]`, which matches both old AND new in case-insensitive comparison — the new-form check fires first, skip. Re-runs are safe and idempotent.
- **Split-brain reference resolution (V2 — fixes F3)** — before rewriting any `[[X]]` reference, the rewriter resolves X against the PRE-migration vault state (using the journal's `old_path` list + a scan of currently-unmigrated files for cross-check). If X uniquely resolves to one migrated file → rewrite. If X resolves to a SKIPPED file (collision) → leave alone, flag in `migration-report.md` under `## Ambiguous References`. If X resolves ambiguously to multiple files → leave alone, flag in `migration-report.md`. This protects users from losing references that intended skipped pages.
- **Collision handling (V2 — fixes F4)** — when a slug collision, target-exists, or folder-vs-file collision is detected during `--dry-run`, the conflicting file is SKIPPED (not migrated), recorded in `migration-report.md` with per-collision resolution instructions. Migration proceeds for all non-colliding files. `--force-overwrite` opts into LOSSLESS clobbering of target-exists collisions: the existing target is FIRST moved to `<vault>/_archives/migration-conflicts/<UTC-ts>/<original-relative-path>` (preserving directory structure), THEN the source is renamed into the now-vacant target path. The archive copy is referenced in `migration-report.md`. Slug collisions and folder-vs-file collisions are never auto-resolved (the user must rename manually before re-running) — `--force-overwrite` does NOT affect them.
- **Aliases preservation (V2 — fixes F1)** — every migrated page's frontmatter gets `aliases: ["<canonical-slug>", "<old-basename-without-md>"]` auto-populated. The canonical slug entry is what makes `[[slug]]` references resolve to the migrated page via Obsidian's alias resolver (empirically verified — see F1 Verification block at top). The old-basename entry preserves quick-switcher discoverability via the old human-visible title. Existing aliases in the source page's frontmatter are preserved; new aliases are appended and the array is deduplicated case-insensitively. This extends the canonical frontmatter schema (set in `wiki-write-conventions`) with a new optional `aliases` field; `wiki-write.py` default-write also gains an optional `--alias <name>` flag (multi-value).
- **Two-step UX** — `--dry-run` prints the plan and writes `<vault>/migration-report.md`. Execute step is a separate `--migrate` invocation (no `--dry-run` flag). The plan is recomputed on execute — no stale-plan failure mode.
- **No interactive prompts during execution** — fully deterministic. The user reviews the dry-run, decides, runs execute. Per-collision resolution happens out of band (manual rename + re-run, or `--force-overwrite`).
- **Surfacing via existing lint** — `/wrap` Phase 2c Step 3b's existing `wiki-write.py --lint` output gets a one-line tail: `To preview a fix: python3 ~/Projects/MonsterFlow/scripts/wiki-write.py --migrate --dry-run`. No /wrap-time prompt — preserves /wrap's speed and avoids fat-finger risk on a destructive workflow.
- **Type-3b "folder missing index.md" can't auto-rename** — the helper detects this case and prints the creation command for the user to run manually (`python3 wiki-write.py --category project --title "..." --body "..."`). Other violation types (Unicode-dash filenames, mixed-case filenames, projects-flat-file) DO auto-rename.

**Out of scope:**

- Touching the upstream `Ar9av/obsidian-wiki` skills (`wiki-update`, `wiki-query`, `wiki-ingest`, etc.) — they remain unchanged.
- Migration of `_archives/`, `_raw/`, root-level `index.md` / `log.md` — those are owned by `/wiki-setup` and have their own conventions.
- Free-form content rewriting (typo fixes, prose changes, content merges). Migration is purely structural: rename + rewrite refs + preserve discoverability via aliases.
- A shadow-vault transactional model (considered as Q2 option c, rejected — too heavyweight, `.obsidian/` plugin-state breaks the swap).
- Interactive per-collision prompting (considered as Q3 option c, rejected — breaks the `--resume` deterministic-continuation contract).
- Plan-handoff via disk artifact (considered as Q5 option b, rejected — stale-plan failure mode is more friction than recomputing).
- Cross-vault migration (moving content between different vaults).
- Migration of `aliases` for pages that haven't been migrated yet (the `--alias` flag is available on default-write for new pages, but bulk-adding aliases to existing conformant pages isn't in scope).

## Approach

User-directed across 7 /spec Q&A rounds + 1 user-driven re-examination of Q2 ("(b) seems like it could easily leave someone in a broken state"). No formal alternatives proposal — the BACKLOG entry had pre-documented 4 open questions, and the Q&A locked decisions on each plus 3 additional sub-questions that surfaced during discussion.

Four moving parts that compose:

1. **`scripts/_wiki_migrate.py`** is a new module (~400 LoC) imported by wiki-write.py. Owns: plan computation, collision detection, Phase A renames with journal, Phase B link rewriter with shortest-unique-path resolver, alias frontmatter injection, `migration-report.md` writer, `--resume` from journal.
2. **`scripts/wiki-write.py`** gains a `--migrate` flag (with `--dry-run`, `--resume`, `--force-overwrite` sub-flags) that routes to `_wiki_migrate.run()`. ~30 LoC of CLI plumbing; no other behavior changes in wiki-write.py. The existing exception hierarchy gets two additions: `MigrationCollisionError` (when --force-overwrite is needed for a target-exists collision), `MigrationJournalCorruptError` (when --resume finds a malformed journal).
3. **Canonical frontmatter schema extension** — `aliases` becomes an optional field across all four category schemas (project-index, project-topic, concept, entity). `wiki-write.py` default-write gains an optional `--alias <name>` flag (multi-value, may repeat or comma-separate). `templates/wiki-conventions.md` is updated to document the new field. The seeded `_convention.md` files in each vault category get re-emitted on next install.sh run.
4. **`/wrap` Phase 2c Step 3b lint output** — one-line addition: when the helper reports `WARN N violations:`, append `To preview a fix: python3 ~/Projects/MonsterFlow/scripts/wiki-write.py --migrate --dry-run`. The wiki-write.py `--lint` mode itself emits this tail; /wrap surfaces it verbatim.

Key design choice (reinforced by user pushback on Q2): the journal is correctness-mandatory, not optional convenience. Without persistent (old → new) basename mapping, Phase B's wikilink rewriter cannot recover after a crash — the filesystem only tells you "what files are where NOW," not "what files USED to be called what." The journal is what makes `--resume` work AND what makes a clean execution of Phase B work (Phase B reads the journal even on non-resume runs to know which (old, new) pairs to scan for in wikilink references).

## Roster Changes

No roster changes. The pipeline's default personas (api, data-model, ux, scalability, security, integration, wave-sequencer for /blueprint; completeness, sequencing, risk, scope-discipline, testability, security-architect for /check; requirements, gaps, ambiguity, feasibility, scope, stakeholders, docs-clarity for /spec-review) cover migration's surface: data-model designs the journal schema, security examines the destructive surface, integration plans the wiki-write.py module dispatch, wave-sequencer sequences Phase A → Phase B → report.

## UX / User Flow

**Discovery (via existing lint):**

1. User runs `/wrap` (default) at end of session.
2. `/wrap` Phase 2c Step 3b invokes `python3 ~/Projects/MonsterFlow/scripts/wiki-write.py --lint`.
3. Helper scans vault, reports violations:
   ```
   ok   86 pages compliant
   WARN 5 violations:
     projects/PatternCall — iOS Native Rewrite.md (type 1: Unicode dash in filename)
     projects/Welcome.md (type 3a: projects/<name>.md flat file)
     concepts/HostImprov.md (type 2: mixed case in filename)
     projects/concierge/ (type 3b: projects/<name>/ folder missing index.md)
     entities/Tom Fox.md (type 1: space in filename — flagged as Unicode-dash adjacent)
   To preview a fix: python3 ~/Projects/MonsterFlow/scripts/wiki-write.py --migrate --dry-run
   ```
4. User reads, decides when to fix. /wrap continues normally — no prompt, no interruption.

**Dry-run (user-initiated, when ready):**

1. User runs `python3 ~/Projects/MonsterFlow/scripts/wiki-write.py --migrate --dry-run`.
2. Helper scans vault, computes plan:
   - Identify all violation pages (4 auto-renamable, 1 type-3b that needs manual creation)
   - For each renamable page: compute target slug + target path (folder+index for projects, flat for concepts/entities)
   - Detect collisions (slug, target-exists, folder-vs-file) — flag affected files for skip
   - Walk all `.md` files in the vault, identify `[[wikilink]]` references that target any renamable page's old basename
   - For each ref, compute the post-migration shortest-unique-path form
   - Compile alias additions: each migrated page's frontmatter gets `aliases: ["<old-basename-without-md>"]`
3. Helper prints the plan to stdout:
   ```
   === Migration plan ===
   Scanned: 91 pages under projects/, concepts/, entities/
   Migrate (auto-rename): 3 files
     projects/PatternCall — iOS Native Rewrite.md → projects/patterncall-ios-native-rewrite/index.md
     projects/Welcome.md → projects/welcome/index.md
     concepts/HostImprov.md → concepts/host-improv.md
   Migrate (manual — type-3b folder needs index.md): 1 file
     projects/concierge/ → user must create projects/concierge/index.md manually
       python3 wiki-write.py --category project --title "Concierge" --body "..."
   Skip-already-conformant: 86 files
   Skip-collisions: 1 file (see migration-report.md)
   Rewrite wikilinks: 12 references across 6 pages
   Add aliases: 3 entries (one per auto-renamed file)

   Next step: python3 ~/Projects/MonsterFlow/scripts/wiki-write.py --migrate
   ```
4. Helper writes `<vault>/migration-report.md` with full collision detail.
5. User reviews `migration-report.md` if any collisions reported; resolves manually (rename a colliding file out of the way) or decides to `--force-overwrite`; OR proceeds to execute.

**Execute (user-initiated, after reviewing dry-run):**

1. User runs `python3 ~/Projects/MonsterFlow/scripts/wiki-write.py --migrate`.
2. Helper RE-COMPUTES the plan (does not read a stored plan from disk — recomputing on every invocation prevents the stale-plan failure mode).
3. Phase A — renames:
   - For each renamable file (excluding collisions):
     - Write journal row to `<vault>/.migration-journal.jsonl` BEFORE rename. Row schema: `{"phase":"rename","old_path":"...","new_path":"...","old_basename":"...","new_basename":"...","ts":"<ISO-8601>","status":"in_flight"}`
     - Execute `os.rename(old, new)` (creates parent folder if needed via `os.makedirs`)
     - Update journal row's status to `"completed"` (re-emit row with `status:"completed"`; journal is append-only — readers take the latest row per `old_path`)
   - On rename failure: status stays `in_flight`, helper aborts with stderr error, journal preserved for `--resume`.
4. Phase B — link rewrites + alias injection:
   - Read journal, build (old_basename → new_basename) mapping
   - Walk every `.md` file in the vault
   - For each file: find all `[[wikilink]]` references whose target (after stripping piped-display, fragment, embed sigils) matches an `old_basename` in the mapping
   - Compute the post-migration form via shortest-unique-path: if the new basename is unique in the post-migration vault, emit `[[new-basename]]`; otherwise emit `[[<folder>/<new-basename>|<display-text-or-old-basename>]]`
   - Write file atomically via tempfile + os.replace
   - For each MIGRATED page (not other pages), inject `aliases: ["<old-basename-without-md>"]` into frontmatter (use `wiki-write.py`'s existing YAML emission logic)
5. On clean completion, archive journal: `mv .migration-journal.jsonl .migration-journal-<UTC-ts>.jsonl.done`
6. Helper prints summary:
   ```
   === Migration complete ===
   Migrated: 3 files
   Manual-create-required: 1 (see migration-report.md)
   Skipped (already-conformant): 86
   Skipped (collisions): 1
   Wikilinks rewritten: 12 across 6 pages
   Aliases added: 3
   Journal: archived to <vault>/.migration-journal-2026-05-15T07-30-00Z.jsonl.done

   Next: review migration-report.md if any collisions reported; manually create index.md for type-3b paths.
   ```

**Resume (after crash):**

1. User runs `python3 ~/Projects/MonsterFlow/scripts/wiki-write.py --migrate --resume`.
2. Helper reads `<vault>/.migration-journal.jsonl`:
   - If absent: exit 0 with `[wiki-migrate] no in-flight journal; nothing to resume`.
   - If present but malformed (not valid JSONL, or rows missing required fields): exit non-zero with `MigrationJournalCorruptError` — user investigates manually.
3. Identify in-flight Phase A renames (rows with `status:"in_flight"` and no later `completed` row for the same `old_path`):
   - For each: attempt rename, update journal status.
   - If still failing: abort with stderr error, preserve journal.
4. Run Phase B from scratch (Phase B is idempotent — already-rewritten links don't match the old-form pattern; re-running just walks the vault and confirms no remaining old refs).
5. Archive journal on clean completion (same as the non-resume happy path).

**Error paths (exit codes) — V2 collapses 4 and 5 per scope SC-007:**

- `0` — success, including silent-skip when vault is absent under `--migrate --dry-run` or `--migrate --resume` (V2 — fixes F8)
- `1` — vault absent on `--migrate` (no `--dry-run` or `--resume`); helper-misuse including: `--dry-run` + `--resume` combo (mutually exclusive — argparse rejects with `--dry-run and --resume are mutually exclusive`); `--migrate` lock contention (advisory lock held by another invocation — V2 F5); `--resume` without an existing journal when `MONSTERFLOW_MIGRATE_STRICT=1`; target-exists collision detected without `--force-overwrite` (`MigrationCollisionError` internally); journal schema mismatch on `--resume` (`MigrationJournalCorruptError` internally). Stderr message distinguishes the cause.
- `2` — vault path resolved but directory does not exist
- `3` — slug computation produced empty string for one or more files

The exception classes `MigrationCollisionError` and `MigrationJournalCorruptError` are kept internally (testable by name + stderr-string matching) but the CLI uniformly returns 1 for both. Promote to distinct exit codes when a scripted consumer materializes.

## Data & State

**Files MonsterFlow owns:**

- `scripts/_wiki_migrate.py` — the migration module. Python 3.9-compatible (matches wiki-write.py's existing constraint). ~400 LoC. No third-party deps (stdlib only).
- `scripts/wiki-write.py` (existing) — gains `--migrate` / `--dry-run` / `--resume` / `--force-overwrite` / `--alias <name>` flags + new exception classes. ~30 LoC of additions.
- `templates/wiki-conventions.md` (existing) — gains documentation for the optional `aliases` frontmatter field across all 4 category schemas.
- `tests/test-wiki-migrate.sh` — new bash test harness (~600 LoC, ~30 cases). Covers: slug-collision detection, target-exists detection, folder-vs-file detection, type-3b manual-create path, Phase A journal write/read/resume, Phase B wikilink rewriting (shortest-unique-path), alias injection, --force-overwrite, dry-run output format, migration-report.md content, code-fence wikilink preservation, frontmatter wikilink preservation, fragment/embed link rewriting, atomic file writes.

**Files MonsterFlow writes at runtime:**

- `<vault>/.migration-journal.jsonl` — append-only journal during Phase A. Removed (archived) on clean completion.
- `<vault>/.migration-journal-<UTC-ts>.jsonl.done` — archived journal after clean completion. Retained indefinitely (one per migration run; user can `rm` after reviewing).
- `<vault>/migration-report.md` — written by every `--dry-run` and `--migrate` invocation. Overwritten on each run. Contains: collision details with per-collision resolution instructions, type-3b manual-create commands, full migration plan, link rewrite summary.

**Journal schema (JSONL — one row per state transition, append-only) — V2 adds schema_version per F6:**

```jsonl
{"schema_version":1,"phase":"rename","old_path":"projects/PatternCall — iOS Native Rewrite.md","new_path":"projects/patterncall-ios-native-rewrite/index.md","old_basename":"PatternCall — iOS Native Rewrite","new_basename":"patterncall-ios-native-rewrite","ts":"2026-05-15T07:25:31Z","status":"in_flight"}
{"schema_version":1,"phase":"rename","old_path":"projects/PatternCall — iOS Native Rewrite.md","new_path":"projects/patterncall-ios-native-rewrite/index.md","old_basename":"PatternCall — iOS Native Rewrite","new_basename":"patterncall-ios-native-rewrite","ts":"2026-05-15T07:25:31Z","status":"completed"}
{"schema_version":1,"phase":"rename","old_path":"projects/Welcome.md","new_path":"projects/welcome/index.md","old_basename":"Welcome","new_basename":"welcome","ts":"2026-05-15T07:25:32Z","status":"in_flight"}
... 
```

Readers take the LATEST row per `old_path` to determine current status. Reader policy on unknown `schema_version`: refuse with `MigrationJournalCorruptError` (CLI exit 1). `phase: "rename"` is the only phase for v1; future variants get explicit reader-side handling.

**Frontmatter schema extension (canonical, applies to ALL category schemas):**

```yaml
---
title: ...
created: ...
summary: ...
status: ...        # project-index only
type: ...          # entity only
parent: ...        # project-topic only
tags: [...]
aliases:           # NEW — optional
  - "Old Visible Title 1"
  - "Old Visible Title 2"
---
```

`aliases` is a list of strings. May be omitted (current schema behavior). When `wiki-write.py` default-write is invoked with `--alias <name>` (potentially multi-value via repeat or comma-separate), the value(s) populate the array. When `_wiki_migrate.py` runs Phase B, the migrated page's old basename gets auto-added. Existing values are preserved (de-duplicated).

**`migration-report.md` shape:**

```markdown
# Migration Report — 2026-05-15T07:25:00Z

## Plan summary
Migrate (auto-rename): 3 files
Migrate (manual create required): 1 file
Skip-already-conformant: 86 files
Skip-collisions: 1 file

## Auto-renames
- projects/PatternCall — iOS Native Rewrite.md → projects/patterncall-ios-native-rewrite/index.md
  - Aliases to add: ["PatternCall — iOS Native Rewrite"]
- ... (full list)

## Manual creates required (type-3b)
- projects/concierge/ — folder exists, index.md missing
  - Run: `python3 wiki-write.py --category project --title "Concierge" --body "..."`

## Collisions (skipped)
- entities/Tom Fox.md — slug "tom-fox" collides with existing entities/tom-fox.md
  - Resolution: rename one file manually, then re-run --migrate
  - Or: `--force-overwrite` to clobber existing entities/tom-fox.md (DESTRUCTIVE)

## Wikilink rewrites
12 references across 6 pages will be rewritten:
- concepts/host-improv-pattern.md: [[Welcome]] → [[welcome]]
- ... (full list)

## Notes
- code-fence wikilinks are NOT rewritten (test fixtures preserved verbatim)
- frontmatter wikilinks are NOT rewritten (config references preserved verbatim)
- piped-display wikilinks: [[Welcome|click here]] → [[welcome|click here]] (display text preserved)
- fragment links: [[Welcome#section]] → [[welcome#section]] (fragment preserved)
- embed links: ![[Welcome]] → ![[welcome]] (sigil preserved)
```

## Integration

**Touches:**

- `scripts/wiki-write.py` — adds `--migrate` / `--dry-run` / `--resume` / `--force-overwrite` / `--alias` flags (argparse plumbing) + new exception classes (`MigrationCollisionError`, `MigrationJournalCorruptError`) + routing block that imports `_wiki_migrate` and dispatches.
- `scripts/_wiki_migrate.py` — new file. Module surface: `run(args, vault) -> int`, plus internal helpers `compute_plan`, `execute_phase_a`, `execute_phase_b`, `resume`, `write_report`, plus the shortest-unique-path resolver `resolve_wikilink(old_basename, new_basename, vault_index) -> str`.
- `templates/wiki-conventions.md` — adds documentation for the optional `aliases` frontmatter field. Reflected in the 3 vault `_convention.md` files on next install.sh run.
- `commands/wrap.md` Phase 2c Step 3b — no change (the lint output already surfaces; the new tail line is emitted by `wiki-write.py --lint`, not added in wrap.md).
- `scripts/wiki-write.py` `run_lint()` — adds one line to its output when violations > 0: `To preview a fix: python3 ~/Projects/MonsterFlow/scripts/wiki-write.py --migrate --dry-run`.
- `tests/test-wiki-write.sh` — gains an assertion that `run_lint()`'s tail line is present when violations exist.
- `tests/test-wiki-migrate.sh` — new file.
- `tests/run-tests.sh` — wire in `test-wiki-migrate.sh` (named task per `test-orchestrator-wiring-gap` memory).
- `BACKLOG.md` — `wiki-write-migrate` entry removed (replaced by this shipped spec).

**Doesn't touch:**

- `install.sh` — migration doesn't run at install time. Helper invocation is purely user-initiated.
- Upstream `Ar9av/obsidian-wiki` repo or skills.
- `commands/spec.md`, `commands/blueprint.md`, `commands/check.md`, `commands/build.md` — migration is not pipeline-aware.
- `scripts/_replace_sentinel_block.py` — separate utility, untouched.
- Vault directory structure outside the three managed categories (`projects/`, `concepts/`, `entities/`) — `_archives/`, `_raw/`, root files left alone.

## Edge Cases

- **Vault not configured (`~/.obsidian-wiki/config` absent)** — under `--migrate --dry-run`, exits 0 with `[wiki-migrate] skip: vault not configured`. Under `--migrate` (execute), exits 1 with the same message.
- **Vault path resolved but directory does not exist** — exits 2 (matches `wiki-write.py` existing behavior).
- **Empty vault (no `.md` files under managed categories)** — exits 0 with `Nothing to migrate; 0 pages found.`
- **All pages already conformant** — exits 0 with `Nothing to migrate; 87 pages already compliant.`
- **`--resume` invoked with no in-flight journal** — exits 0 with `[wiki-migrate] no in-flight journal; nothing to resume.` (Strict mode via `MONSTERFLOW_MIGRATE_STRICT=1` env var exits 1 instead, for CI/scripted invocations that want to assert state.)
- **Journal exists from a PRIOR completed migration (status: completed throughout)** — this shouldn't happen because completed journals get renamed to `.done`. If it does (e.g., user manually copied the file back), `--migrate` treats it as in-flight and replays Phase B; effect is idempotent (no link rewrites match because everything's already in new form). `--resume` does the same.
- **Slug collision (two source files → same canonical slug)** — both files SKIPPED. Reported in `migration-report.md` with `Resolution: rename one file manually, then re-run --migrate`.
- **Target-exists collision (canonical target path already exists as a DIFFERENT page)** — source SKIPPED unless `--force-overwrite` passed. Reported.
- **Folder-vs-file collision (`projects/welcome.md` flat AND `projects/welcome/` folder both exist)** — flat file SKIPPED. Folder is assumed canonical. Reported with `Resolution: merge flat file's content into folder's index.md, then re-run --migrate`.
- **Type-3b violation (`projects/<name>/` folder exists, no `index.md` inside)** — NOT a rename target. Helper detects and reports under "Manual creates required" with the exact `wiki-write.py --category project --title ...` command for the user to run.
- **Case-insensitive filesystem no-op rename** — `os.rename("Welcome.md", "welcome.md")` on macOS HFS+/APFS may succeed silently as a no-op (filesystem treats them as the same file). Detected by comparing canonical path inode after rename; if unchanged AND content matches, helper logs `[wiki-migrate] case-insensitive no-op rename: <path> (already same file)` and continues.
- **Wikilink in code fence (` ```...``` `)** — NOT rewritten. Migration's link rewriter uses the same code-fence-aware regex as `--lint`'s scanner.
- **Wikilink in frontmatter (between first two `---`)** — NOT rewritten. Same reason.
- **Wikilink piped-display form (`[[Welcome|click here]]`)** — rewritten with display preserved: `[[welcome|click here]]`. Or for ambiguous targets: `[[projects/welcome|click here]]`.
- **Wikilink fragment form (`[[Welcome#section]]`)** — rewritten with fragment preserved: `[[welcome#section]]`.
- **Wikilink embed form (`![[Welcome]]`)** — rewritten with sigil preserved: `![[welcome]]`.
- **Mid-Phase-A rename failure** — current file's rename status stays `in_flight` in journal; helper exits non-zero with the OSError message. User runs `--resume` (or investigates and rms the offending journal row manually).
- **Mid-Phase-B rewrite failure on a single file** — atomic-write trap means no partial-file corruption; the OFFENDING file keeps old wikilinks. Helper exits non-zero, journal preserved. `--resume` re-runs Phase B from scratch — already-rewritten files have no remaining old-form links, so the rewriter touches only the not-yet-rewritten files.
- **Concurrent --migrate invocations** — second invocation detects existing journal, treats as `--resume` scenario. Both ATTEMPT to acquire the same files; second loses on `os.rename` for already-completed renames (idempotent; treats as already-done). Last-writer-wins on link rewrites — atomic per-file, no corruption, possibly redundant work.
- **Vault on a network/iCloud drive** — `os.rename` and `os.replace` still atomic per POSIX. iCloud Drive's sync may lag (rename happens locally; sync propagates later); the helper doesn't wait for sync. Documented; user's responsibility to let sync settle before using the migrated vault on another machine.
- **Slug computation produces empty string** — e.g., file named `!!!.md`. Helper logs to report under "Migration blocked — manual rename required" with the message `slug computation produced empty string; rename <path> manually before re-running --migrate`. Migration proceeds for all other files; exit 3 only if ALL files are blocked.
- **Alias collision** — if a migrated page's old basename matches another (already-conformant) page's title or alias. Helper logs but does NOT skip — both files retain their aliases; Obsidian's quick-switcher disambiguates at lookup time (showing both matches).
- **Existing `aliases: [...]` in a migrated page's frontmatter** — preserve existing values, append the old basename, deduplicate. Order: new values appended to end.

## Acceptance Criteria

1. `scripts/_wiki_migrate.py` exists in the MonsterFlow repo. Python 3.9-compatible (no `|` union types, no `match` statements, no parenthesized context managers). Stdlib only (including `fcntl` for the advisory lock). Module surface: `run(args, vault) -> int`, `compute_plan(vault) -> MigrationPlan` (namedtuple or dataclass), `execute_phase_a(plan, journal_path) -> None`, `execute_phase_b(journal_path, vault) -> None`, `resume(journal_path, vault) -> None`, `write_report(vault, plan) -> None`, `resolve_wikilink(old_basename, new_basename, vault_index) -> str`, `resolve_link_target_pre_migration(link, vault, journal) -> Optional[Path]` (V2 F3 split-brain resolver), `archive_collision_target(target_path, vault) -> Path` (V2 F4 lossless overwrite).

2. `scripts/wiki-write.py` accepts new flags: `--migrate` (mode-switch), `--dry-run` (modifier; requires `--migrate`; mutually exclusive with `--resume`), `--resume` (modifier; requires `--migrate`), `--force-overwrite` (modifier; requires `--migrate`; ignored with `--dry-run`), `--alias <name>` (default-write modifier; may repeat). Internal exception classes `MigrationCollisionError` and `MigrationJournalCorruptError` map to CLI exit 1 in V2 (collapsed from 4/5 per scope SC-007). Migration routing dispatches to `_wiki_migrate.run(args, vault)`.

3. Migration's wikilink rewriter uses Obsidian's shortest-unique-path model. Uniqueness predicate (V2 F7): a basename is unique when it appears exactly once across `<vault>/{projects,concepts,entities}/**/*.md` after the rename plan applies (the `_archives/`, `_raw/`, root-level files are NOT in the uniqueness denominator). Form-emission: unique → `[[new-basename]]` preserving piped-display, fragment, embed sigils; non-unique → `[[<category>/<new-basename>|<display-text-or-old-basename>]]`. Tests cover both branches. Wikilink edge cases (V2 F10 + F11): handles bare `[[X]]`, folder-qualified `[[folder/X]]`, `.md`-suffix `[[X.md]]`, fragment `[[X#section]]`, embed `![[X]]`, piped-display `[[X|label]]`, callout-block `> [!note] [[X]]`. HTML comments `<!-- [[X]] -->` are NOT rewritten (preserve verbatim).

4. Migration's journal is durable JSONL at `<vault>/.migration-journal.jsonl`, append-only, with rows recording each Phase A rename's (`schema_version: 1`, `phase: "rename"`, `old_path`, `new_path`, `old_basename`, `new_basename`, `ts`, `status`) — written BEFORE the rename and updated AFTER. V2 adds `schema_version` field (F6) — reader refuses unknown versions with `MigrationJournalCorruptError`. V2 adds advisory `fcntl.flock()` on the journal file during Phase A (F5) — second concurrent invocation exits 1 with lock-contention message. `--resume` reads the journal and completes any `status:"in_flight"` rows. On clean completion, journal archived to `.migration-journal-<UTC-ts>.jsonl.done`.

5. Collisions are skipped + reported by default. `--force-overwrite` opts into LOSSLESS overwrite of target-exists collisions only (V2 F4): the existing target is FIRST moved to `<vault>/_archives/migration-conflicts/<UTC-ts>/<original-relative-path>` (preserving directory structure), THEN the source is renamed into the now-vacant target path. The archive copy path is recorded in `migration-report.md`. Slug collisions and folder-vs-file collisions are NEVER affected by `--force-overwrite` — they always require manual user action.

6. Every migrated page's frontmatter gains `aliases: ["<canonical-slug>", "<old-basename-without-md>"]` (V2 fixes F1 — canonical slug entry enables `[[slug]]` resolution via Obsidian's alias resolver, empirically verified). Existing `aliases:` entries in the source page are preserved; new entries are appended and the array is deduplicated case-insensitively. The `aliases` field becomes a documented optional field in `templates/wiki-conventions.md` for all four category schemas (project-index, project-topic, concept, entity). `wiki-write.py` default-write gains a `--alias <name>` flag (multi-value; may repeat or comma-separate).

7. `--dry-run` writes `<vault>/migration-report.md` and prints a stdout summary including the `Next step: python3 ~/Projects/MonsterFlow/scripts/wiki-write.py --migrate` line. The execute step (`--migrate` without `--dry-run`) recomputes the plan from scratch (no stale-plan failure mode). Both modes write the report; execute additionally writes the journal, performs the renames + rewrites, and runs the Phase B post-run verification scan (V2 F9 — appends `## Verification Findings` section to the report if any old-form wikilinks survive).

8. `wiki-write.py --lint` output adds a one-line tail when violations > 0: `To preview a fix: python3 ~/Projects/MonsterFlow/scripts/wiki-write.py --migrate --dry-run`. No `/wrap`-time prompt; the user reads and acts at their own pace.

9. Phase B idempotency (V2 F2): the rewriter checks each `[[X]]` reference against both `old_basenames` and `new_basenames` sets from the journal (case-insensitive comparison). Rewrite fires only when X matches `old_basenames` AND does NOT already match `new_basenames`. Re-runs of Phase B are idempotent — already-rewritten references are detected and skipped.

10. Split-brain reference resolution (V2 F3): before rewriting any `[[X]]`, the rewriter resolves X against the pre-migration vault state. If X uniquely resolves to a MIGRATED file → rewrite. If X resolves to a SKIPPED (collision) file → leave alone, append to `migration-report.md` under `## Ambiguous References`. If X resolves ambiguously to multiple files (some migrated, some not) → leave alone, append to `migration-report.md`.

11. `tests/test-wiki-migrate.sh` covers at minimum: (a) slug-collision detection (two sources → same canonical slug, both skipped), (b) target-exists detection without `--force-overwrite` (skipped + reported), (c) target-exists WITH `--force-overwrite` (existing target archived to `_archives/migration-conflicts/<ts>/...` before rename; archive path recorded in report), (d) folder-vs-file detection (flat file skipped, folder retained), (e) type-3b manual-create case (helper prints the creation command), (f) journal `schema_version: 1` present on every row + reader rejects unknown versions, (g) journal pre-rename atomicity (V2 revised per F12 — test pre-plants an in-flight journal row matching plan, runs `--migrate --resume`, asserts rename completes and row status → completed), (h) advisory lock on journal during Phase A (V2 F5 — second concurrent invocation exits 1 with lock-contention stderr message), (i) Phase B shortest-unique-path resolver (unique → bare slug; ambiguous → disambiguating prefix), (j) Phase B idempotency on re-run (V2 F2 — rewriter detects already-canonical form, skip), (k) split-brain reference detection (V2 F3 — ambiguous link flagged in report, NOT auto-rewritten), (l) Phase B post-run verification (V2 F9 — verification scan surfaces any survivors), (m) code-fence wikilinks NOT rewritten, (n) frontmatter wikilinks NOT rewritten, (o) HTML-comment wikilinks NOT rewritten (V2 F11), (p) callout-block wikilinks ARE rewritten, (q) piped-display preserved, (r) fragment preserved, (s) embed sigil preserved, (t) `--alias` flag default-write multi-value handling, (u) alias auto-injection includes canonical slug + old basename (V2 F1), (v) alias dedup case-insensitive, (w) `migration-report.md` content (sections + per-collision instructions + archive paths + ambiguous-references + verification-findings), (x) `--dry-run` exit codes 0 / silent-skip-on-vault-absent, (y) `--migrate` exit codes 0 / 1 / 2 / 3, (z) `--migrate --dry-run --resume` rejected by argparse (exit 1; mutual exclusion per V2 F8), (aa) `--force-overwrite` does NOT bypass slug-collisions (V2 F14 — both files still skipped), (bb) orphan wikilink preservation (V2 F15 — `[[never-existed]]` reference not touched). Wired into `tests/run-tests.sh` (named task — `test-orchestrator-wiring-gap` memory). Case-sensitive-filesystem skip guard on the case-insensitive-rename test (V2 F13).

## Open Questions

None at V2 write time. The 4 originally documented in the BACKLOG entry are answered (Q1 wikilink resolver, Q2 journal, Q3 collision matrix, Q4 aliases). The 3 surfaced during Q&A are answered (Q5 two-step recompute, Q6 module split, Q7 surfacing-via-lint-no-prompt). The 5 architectural findings from /spec-review (F1 alias-contains-slug, F2 idempotency, F3 split-brain, F4 lossless overwrite, F5 advisory lock) are folded inline. The 11 contract/tests/vault-discovery refinements (F6-F17 — schema_version, uniqueness predicate, --resume on vault-absent, post-run verification, expanded wikilink edges, bash-testable atomicity test, FS-sensitive test guard, --force + slug-collision test, orphan-link test, path-with-spaces, iCloud placeholders) are folded into Data & State and Acceptance Criteria.

A future follow-up worth tracking, not blocking this spec:

- **Bulk alias addition for already-conformant pages** — out of scope here; the `--alias` flag on default-write supports per-page addition. If a user later wants to retroactively add aliases to pages that were created without them, that's a separate `--add-alias` mode or a future migration sub-pass. Note in BACKLOG.md if the need surfaces.
- **F1 empirical verification on Obsidian versions** — the spike (2026-05-16) verified resolution against the current installed Obsidian version. If Obsidian's resolver semantics change in a future version, the alias-based resolution could break. A version-pin test in `test-wiki-migrate.sh` is not feasible (can't run Obsidian headless); document the assumption in templates/wiki-conventions.md so future debuggers know where to look.
