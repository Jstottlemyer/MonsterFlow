---
created: 2026-05-15
constitution: none
confidence:
  scope: 0.95
  ux: 0.92
  data: 0.92
  integration: 0.92
  edges: 0.88
  acceptance: 0.92
gate_mode: permissive
tags: [api, data, docs, integration, migration, refactor, scalability, security, ux]
tags_provenance:
  baseline: [api, data, integration, scalability, security, ux]
  llm_added: [docs, migration, refactor]
  user_overrides: []
---

# wiki-write-migrate Spec

**Created:** 2026-05-15
**Constitution:** none (MonsterFlow personal-tooling repo; pipeline owns roster)
**Confidence:** scope 0.95, ux 0.92, data 0.92, integration 0.92, edges 0.88, acceptance 0.92
**gate_mode:** permissive

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
- **Collision handling** — when a slug collision, target-exists, or folder-vs-file collision is detected during `--dry-run`, the conflicting file is SKIPPED (not migrated), recorded in `migration-report.md` with per-collision resolution instructions. Migration proceeds for all non-colliding files. `--force-overwrite` opts into clobbering target-exists collisions when the user has explicitly decided. Slug collisions and folder-vs-file collisions are never auto-resolved (the user must rename manually before re-running).
- **Aliases preservation** — every migrated page's frontmatter gets `aliases: ["<old-basename-without-md>"]` auto-populated. Obsidian's quick-switcher uses `aliases` natively, so the old human-visible title remains discoverable. This extends the canonical frontmatter schema (set in `wiki-write-conventions`) with a new optional `aliases` field; `wiki-write.py` default-write also gains an optional `--alias <name>` flag (multi-value).
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

**Error paths (exit codes):**

- `0` — success (including silent-skip when vault is absent under `--migrate --dry-run` — same behavior as `--lint`)
- `1` — vault absent on `--migrate` (not `--dry-run`), or other helper-misuse (e.g., `--resume` without an existing journal when `MONSTERFLOW_MIGRATE_STRICT=1`)
- `2` — vault path resolved but directory does not exist
- `3` — slug computation produced empty string for one or more files (vault content unmigrate-able without manual rename first)
- `4` — `MigrationCollisionError` — target-exists collision detected without `--force-overwrite`; helper aborts after writing dry-run report
- `5` — `MigrationJournalCorruptError` — `--resume` found a malformed journal

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

**Journal schema (JSONL — one row per state transition, append-only):**

```jsonl
{"phase":"rename","old_path":"projects/PatternCall — iOS Native Rewrite.md","new_path":"projects/patterncall-ios-native-rewrite/index.md","old_basename":"PatternCall — iOS Native Rewrite","new_basename":"patterncall-ios-native-rewrite","ts":"2026-05-15T07:25:31Z","status":"in_flight"}
{"phase":"rename","old_path":"projects/PatternCall — iOS Native Rewrite.md","new_path":"projects/patterncall-ios-native-rewrite/index.md","old_basename":"PatternCall — iOS Native Rewrite","new_basename":"patterncall-ios-native-rewrite","ts":"2026-05-15T07:25:31Z","status":"completed"}
{"phase":"rename","old_path":"projects/Welcome.md","new_path":"projects/welcome/index.md","old_basename":"Welcome","new_basename":"welcome","ts":"2026-05-15T07:25:32Z","status":"in_flight"}
... 
```

Readers take the LATEST row per `old_path` to determine current status. `phase: "rename"` is the only phase for v1 (Phase B's per-file rewrites don't get journaled — they're idempotent enough to re-run from scratch on resume). Future Phase A operations (move, delete) could add phase variants.

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

1. `scripts/_wiki_migrate.py` exists in the MonsterFlow repo. Python 3.9-compatible (no `|` union types, no `match` statements, no parenthesized context managers). Stdlib only. Module surface: `run(args, vault) -> int`, `compute_plan(vault) -> MigrationPlan` (namedtuple or dataclass), `execute_phase_a(plan, journal_path) -> None`, `execute_phase_b(journal_path, vault) -> None`, `resume(journal_path, vault) -> None`, `write_report(vault, plan) -> None`, `resolve_wikilink(old_basename, new_basename, vault_index) -> str`.

2. `scripts/wiki-write.py` accepts new flags: `--migrate` (mode-switch), `--dry-run` (modifier; requires `--migrate`), `--resume` (modifier; requires `--migrate`; mutually exclusive with `--dry-run`), `--force-overwrite` (modifier; requires `--migrate`; not `--dry-run`), `--alias <name>` (default-write modifier; may repeat). New exception classes: `MigrationCollisionError` (exit 4), `MigrationJournalCorruptError` (exit 5). Migration routing dispatches to `_wiki_migrate.run(args, vault)`.

3. Migration's wikilink rewriter uses shortest-unique-path: for each `[[old-basename]]` reference, after the corresponding file's rename, the rewriter computes the new form by checking `<new-basename>` uniqueness across the post-migration vault. If unique → emit `[[new-basename]]` (preserving piped-display, fragment, embed sigils). If non-unique → emit `[[<category>/<new-basename>|<old-basename-or-display>]]`. Tests cover the disambiguating-suffix case explicitly.

4. Migration's journal is durable JSONL at `<vault>/.migration-journal.jsonl`, append-only, with rows recording each Phase A rename's (`old_path`, `new_path`, `old_basename`, `new_basename`, `ts`, `status`) — written BEFORE the rename and updated AFTER. `--resume` reads the journal and completes any `status:"in_flight"` rows. On clean completion, journal is archived to `.migration-journal-<UTC-ts>.jsonl.done`.

5. Collisions are skipped + reported by default; `--force-overwrite` opts into clobbering target-exists collisions only (slug collisions and folder-vs-file collisions are never auto-resolved — always require manual user action). All collisions are recorded in `<vault>/migration-report.md` with per-collision resolution instructions.

6. Every migrated page's frontmatter gains `aliases: ["<old-basename-without-md>"]` (appended to existing aliases if any, deduplicated). The aliases field becomes a documented optional field in `templates/wiki-conventions.md` for all four category schemas (project-index, project-topic, concept, entity). `wiki-write.py` default-write gains a `--alias <name>` flag (multi-value; may repeat).

7. `--dry-run` writes `<vault>/migration-report.md` and prints a stdout summary including the `Next step: python3 ~/Projects/MonsterFlow/scripts/wiki-write.py --migrate` line. The execute step (`--migrate` without `--dry-run`) recomputes the plan from scratch (no stale-plan failure mode). Both modes write the report; execute additionally writes the journal and performs the renames + rewrites.

8. `wiki-write.py --lint` output adds a one-line tail when violations > 0: `To preview a fix: python3 ~/Projects/MonsterFlow/scripts/wiki-write.py --migrate --dry-run`. No `/wrap`-time prompt; the user reads and acts at their own pace.

9. `tests/test-wiki-migrate.sh` covers at minimum: (a) slug-collision detection (two sources → same canonical slug, both skipped), (b) target-exists detection (skipped without `--force-overwrite`; clobbered with), (c) folder-vs-file detection (flat file skipped, folder retained), (d) type-3b manual-create case (helper prints the creation command), (e) journal-write-before-rename atomicity (journal row exists before `os.rename` completes — verified via in-process mock), (f) `--resume` from a journal with in-flight rows (rename completed, journal updated to `completed`), (g) `--resume` from a malformed journal (exits 5 `MigrationJournalCorruptError`), (h) Phase B shortest-unique-path resolver (unique → bare slug; ambiguous → disambiguating prefix), (i) code-fence wikilinks NOT rewritten, (j) frontmatter wikilinks NOT rewritten, (k) piped-display preserved, (l) fragment preserved, (m) embed sigil preserved, (n) alias auto-injection (single migration), (o) alias dedup (existing alias array preserved + extended), (p) `migration-report.md` content (sections + per-collision instructions), (q) `--dry-run` exit codes 0 / silent-skip-on-vault-absent, (r) `--migrate` exit codes 0 / 1 / 2 / 3 / 4 / 5, (s) case-insensitive filesystem no-op rename detection. Wired into `tests/run-tests.sh` (named task — `test-orchestrator-wiring-gap` memory).

## Open Questions

None at write time. The 4 originally documented in the BACKLOG entry are answered (Q1 wikilink resolver, Q2 journal, Q3 collision matrix, Q4 aliases). The 3 surfaced during Q&A are also answered (Q5 two-step recompute, Q6 module split, Q7 surfacing-via-lint-no-prompt).

A future follow-up worth tracking, not blocking this spec:

- **Bulk alias addition for already-conformant pages** — out of scope here; the `--alias` flag on default-write supports per-page addition. If a user later wants to retroactively add aliases to pages that were created without them, that's a separate `--add-alias` mode or a future migration sub-pass. Note in BACKLOG.md if the need surfaces.
