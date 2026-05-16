---
created: 2026-05-15
constitution: none
confidence:
  scope: 0.95
  ux: 0.92
  data: 0.95
  integration: 0.92
  edges: 0.88
  acceptance: 0.95
gate_mode: permissive
tags: [api, data, docs, integration, migration, scalability, security, ux]
tags_provenance:
  baseline: [api, data, integration, scalability, security, ux]
  llm_added: [docs, migration]
  user_overrides: []
---

# wiki-write-conventions Spec

**Created:** 2026-05-15
**Constitution:** none (MonsterFlow personal-tooling repo; pipeline owns roster)
**Confidence:** scope 0.95, ux 0.92, data 0.95, integration 0.92, edges 0.88, acceptance 0.95
**gate_mode:** permissive

## Summary

Three separate wiki-update calls produced three different layouts for the same logical project (`projects/PatternCall/PatternCall`, `projects/PatternCall — iOS Native Rewrite`, `projects/Welcome`), because the upstream `wiki-update` skill has no canonical schema for how project / concept / entity pages get named and structured. This spec ships a deterministic Python helper (`scripts/wiki-write.py`) that computes paths in code rather than in a prompt, a single template (`templates/wiki-conventions.md`) that install.sh seeds into both the vault and ~/CLAUDE.md so the rule lives in user-owned surfaces and survives upstream `setup.sh` re-runs, a one-shot `--migrate` mode that converts existing wrong-structure pages with link rewriting, and a `/wrap` lint phase that catches drift when the model bypasses the helper and calls upstream wiki-update freehand.

## Backlog Routing

| Item | Source | Routing |
|------|--------|---------|
| resolver-recovery-shell-owned | BACKLOG.md (added today) | stays — unrelated to wiki conventions |
| install-obsidian-wiki-auto-clone | BACKLOG.md | stays — adjacent (touches obsidian-wiki install), but different surface; coordinates loosely |
| uninstall.sh reverter | BACKLOG.md | stays — different concern |
| PR #10 plot layer review | BACKLOG.md | stays — different concern |

No backlog items merge into this spec.

## Scope

**In scope:**

- A canonical layout for the three top-level vault categories that MonsterFlow's flow touches most: `projects/`, `concepts/`, `entities/`. Projects get folder + `index.md`; concepts and entities stay flat.
- A deterministic slug rule (strict kebab-case + ASCII only) that makes file names URL-stable, prevents case-insensitive-filesystem collisions, and mechanically forbids em-dashes (per the personal-voice rule the user has codified twice — `no-em-dashes` memory + the image's complaint).
- A Python helper at `scripts/wiki-write.py` that the model is told (via ~/CLAUDE.md) to invoke for any write under those three categories. Code performs the slug transform, picks the right layout, writes frontmatter atomically. Model never authors the path string.
- A `templates/wiki-conventions.md` source-of-truth that install.sh derives two artifacts from: a vault-side `_convention.md` per category, and a sentinel-bracketed block in ~/CLAUDE.md. install.sh is the only writer of either; updating the template + re-running install.sh refreshes both.
- A `--migrate` subcommand that scans the existing vault, proposes a rename plan with a confirm gate, executes the renames, and rewrites `[[wikilink]]` references across all `.md` files.
- A `/wrap` lint phase that runs `wiki-write.py --lint` and reports violations (em-dashes in filenames, projects/ without index.md, slug case drift) as a non-blocking warn — catches the slip path where the model bypasses the helper and calls upstream wiki-update directly.

**Out of scope:**

- Touching the upstream `Ar9av/obsidian-wiki` skill prompts. We do NOT patch `~/.claude/skills/wiki-update/SKILL.md` — that file is owned by the upstream tool's `setup.sh` and any local patch gets wiped on re-run.
- An upstream PR to `Ar9av/obsidian-wiki` adding convention-discovery. Future work; tracked separately.
- Layout rules for `_archives/`, `_raw/`, `index.md`, `log.md` — those are owned by `/wiki-setup` (upstream) and already have their own conventions.
- Free-form note writes (the user pasting raw text into the vault outside of `wiki-update`). The helper is opt-in; direct vault writes are unaffected.
- A `wiki-write --link` cross-reference feature — deferred; can be a follow-up.

## Approach

User-directed across 7 Q&A rounds; no alternatives explored. The approach has four moving parts that compose:

1. **Template at `templates/wiki-conventions.md`** is the single source of truth. Codifies slug rules + layout decisions + frontmatter schema in one file.
2. **`scripts/wiki-write.py`** is a deterministic helper that does the slug transform + layout decision in Python (~150 LoC). Reads the convention template at runtime to know the rules, applies them mechanically. Subcommands: default-write, `--migrate`, `--lint`.
3. **`install.sh` `do_knowledge_layer`** derives two artifacts from the template at install time: vault `_convention.md` files (one per category) and a sentinel-bracketed block in ~/CLAUDE.md. install.sh is idempotent — re-running refreshes both targets cleanly.
4. **`/wrap` lint phase** is a non-blocking check that runs `wiki-write.py --lint` against the vault and reports violations to the user in the wrap summary. Catches drift caused by direct upstream wiki-update calls.

Key design choice: code, not prompts, enforces the rule. Same lesson as `resolver-recovery-shell-owned` — when a rule lives in a markdown prompt, the model improvises around it; when the rule lives in a Python function, the model can't get it wrong because it never sees the decision point.

## Roster Changes

No roster changes. Pipeline default personas cover this scope (api, data-model, integration, ux, security, scalability, wave-sequencer for /blueprint; standard /check + /spec-review rosters).

## UX / User Flow

**First-time install (or `install.sh --reconfigure`):**

1. `install.sh do_knowledge_layer` runs.
2. Detects vault path via `parse_obsidian_config`.
3. Reads `templates/wiki-conventions.md`.
4. Writes `<vault>/projects/_convention.md`, `<vault>/concepts/_convention.md`, `<vault>/entities/_convention.md` (idempotent — overwrites with current template content; user-edits to these files get backed up to `.bak.<ts>` first).
5. Injects sentinel-bracketed wiki-conventions block into ~/CLAUDE.md (idempotent — same sentinel-block pattern as the existing obsidian-wiki preflight insert). Backs up `~/CLAUDE.md.bak.<ts>` once per install run before any modifications.
6. Surfaces in the install banner: `Knowledge Layer: wrote 3 _convention.md files, ~/CLAUDE.md updated with wiki-conventions block`.

**Day-to-day write (model invokes the helper):**

1. Model decides "I want to record what we learned about PatternCall iOS rewrite into the wiki."
2. Model reads ~/CLAUDE.md's wiki-conventions block (in system prompt at session start), which says "for project/concept/entity writes, call `python3 ~/Projects/MonsterFlow/scripts/wiki-write.py` with the documented flags."
3. Model invokes:
   ```bash
   python3 ~/Projects/MonsterFlow/scripts/wiki-write.py \
     --category project \
     --title "PatternCall iOS Native Rewrite" \
     --topic "decisions" \
     --summary "Native SwiftUI/SpriteKit rewrite of the PatternCall web app" \
     --tags "ios,native,rewrite"
   ```
4. Helper computes slug: `patterncall-ios-native-rewrite`.
5. Helper detects `--topic` is set → write target is `<vault>/projects/patterncall-ios-native-rewrite/decisions.md`. Without `--topic`, target would be `<vault>/projects/patterncall-ios-native-rewrite/index.md`.
6. Helper writes frontmatter + an empty content body atomically (tmp + `os.replace`).
7. Helper prints the written path to stdout, exits 0.
8. Model can then append body content via a follow-up Edit call.

**Migration (one-shot on adopter's existing vault):**

1. User runs `python3 ~/Projects/MonsterFlow/scripts/wiki-write.py --migrate --dry-run`.
2. Helper scans `<vault>/projects/`, `<vault>/concepts/`, `<vault>/entities/`.
3. For each file or folder whose name violates the convention (em-dashes, mixed case, projects/ without index.md, etc.), proposes a rename to the canonical slug.
4. Reports the rename plan + the count of `[[wikilink]]` references that would be rewritten across the vault. Reports a separate count of edge-case references (in code fences, in frontmatter values, fragment links) that the migration won't touch automatically.
5. User reviews and re-runs without `--dry-run`. Helper prompts `Confirm rename of <N> files and rewrite of <M> wikilinks? [y/N]`.
6. On confirm, helper performs renames sequentially with a trap that rolls back on first failure (no partial migration left behind). Wikilink rewriting happens after all renames complete.
7. On completion: `[migrate] renamed <N> files, rewrote <M> wikilinks, skipped <K> edge-case references — see migration-report.md for the skip list`.

**Lint (every `/wrap`):**

1. `/wrap` Phase calls `python3 ~/Projects/MonsterFlow/scripts/wiki-write.py --lint`.
2. Helper scans vault for convention violations.
3. Surfaces in `/wrap` output:
   ```
   === Wiki Convention Lint ===
   ok   42 pages compliant
   WARN 3 violations:
     projects/PatternCall — iOS Native Rewrite.md (em-dash in filename; suggest patterncall-ios-native-rewrite/)
     projects/Welcome.md (no folder + index pattern; suggest welcome/index.md)
     concepts/HostImprov.md (mixed case; suggest host-improv.md)
   Fix with: wiki-write.py --migrate --dry-run
   ```
4. Non-blocking — `/wrap` continues even if violations exist.

## Data & State

**Files MonsterFlow owns:**

- `templates/wiki-conventions.md` — the single source of truth. Markdown + frontmatter. Codifies: slug rules (kebab-ascii regex), layout rules (folder+index for projects, flat for concepts/entities), frontmatter schema per category, the example reject-list (em-dashes, mixed case, spaces).
- `scripts/wiki-write.py` — the helper. Python 3.10+ (per project CLAUDE.md). Stdlib only (no third-party deps). Atomic writes via `tempfile.NamedTemporaryFile` + `os.replace`.
- `tests/test-wiki-write.sh` — bash test harness. Cases: slug transform with em-dash input, slug transform with mixed case, atomic-write trap, --migrate dry-run output shape, --lint detection of three violation types, ~/CLAUDE.md sentinel-block idempotency on re-run.

**Files MonsterFlow writes/modifies at install time:**

- `<vault>/projects/_convention.md`, `<vault>/concepts/_convention.md`, `<vault>/entities/_convention.md` — derived from `templates/wiki-conventions.md`. Per-category subset of the rules. Backed up to `.bak.<ts>` before overwrite if user has edited them.
- `~/CLAUDE.md` — sentinel-bracketed block injected at the end of the file. Sentinel comments: `<!-- WIKI-CONVENTIONS-START -->` and `<!-- WIKI-CONVENTIONS-END -->`. install.sh's existing `link_file`/insert-pattern infrastructure already supports this shape (per the obsidian preflight memory pattern). Backs up `~/CLAUDE.md.bak.<ts>` once per install run.

**Files MonsterFlow writes/modifies at runtime:**

- `<vault>/{projects,concepts,entities}/<slug>/index.md` or `<slug>.md` — actual content writes via `wiki-write.py`. Atomic.
- `<vault>/migration-report.md` — written once after a successful `--migrate` run. Lists renamed files, rewritten wikilinks, and skipped edge-case references for manual review. User can delete after reviewing.

**Frontmatter schemas (codified in template, enforced by helper):**

`projects/<slug>/index.md`:
```yaml
---
title: PatternCall iOS Native Rewrite
created: 2026-05-15
summary: Native SwiftUI/SpriteKit rewrite of the PatternCall web app
status: active           # one of: active | paused | shipped | archived
tags: [project, ios]     # free-form list
---
```

`projects/<slug>/<topic>.md`:
```yaml
---
title: Decisions
created: 2026-05-15
parent: patterncall-ios-native-rewrite
summary: <one-line summary, max 200 chars>
tags: [project, topic]
---
```

`concepts/<slug>.md`:
```yaml
---
title: Host Improv Pattern
created: 2026-05-15
summary: When models author negative-recovery paths despite explicit STOP instructions
tags: [concept]
---
```

`entities/<slug>.md`:
```yaml
---
title: Tom Fox
created: 2026-05-15
type: person             # one of: person | organization | tool | other
summary: <one-line summary>
tags: [entity, person]
---
```

## Integration

**Touches:**

- `install.sh` — `do_knowledge_layer` gains a new step (call it `install_wiki_conventions`) that runs after `manage_scaffold_marker`. Reads `templates/wiki-conventions.md`, writes the three vault `_convention.md` files, injects the sentinel block into ~/CLAUDE.md. Idempotent.
- `commands/wrap.md` — Phase 2c (the wiki-sync phase) gets a new sub-step: after wiki-update writes, call `wiki-write.py --lint` and surface violations in the wrap summary. Non-blocking.
- `~/CLAUDE.md` (the user's) — gains a sentinel-bracketed wiki-conventions block. Block content: "When writing to the Obsidian vault under `projects/`, `concepts/`, or `entities/`, use `python3 ~/Projects/MonsterFlow/scripts/wiki-write.py` instead of computing the path freehand in a wiki-update call. The helper enforces the slug + layout conventions." Plus a link to the vault's `_convention.md` files for the full rules.
- `tests/run-tests.sh` — picks up `tests/test-wiki-write.sh` via the existing pattern that globs `test-*.sh`.

**Doesn't touch:**

- Upstream `Ar9av/obsidian-wiki` repo (no PRs, no patches to ~/.claude/skills/wiki-update/).
- Existing MonsterFlow pipeline gates (`/spec-review`, `/blueprint`, `/check`, `/build`). The helper is a leaf script, not pipeline machinery.
- `wiki-query` (read side). The convention only governs writes; reads are unaffected.
- `wiki-ingest`, `wiki-export`, `wiki-lint`, `wiki-capture` — those upstream skills do their own things and aren't in scope here. (Note: upstream has a `wiki-lint` skill of its own; ours is a different lint scoped to convention compliance. They co-exist; user can run either or both.)

## Edge Cases

- **Vault not configured** — `~/.obsidian-wiki/config` absent. Helper exits 1 with `wiki not configured; run setup.sh in obsidian-wiki repo first`. install.sh's `install_wiki_conventions` step silent-skips the vault writes (no vault to write to) but still updates ~/CLAUDE.md (the convention rule applies as soon as the vault gets set up).
- **Vault path expands to a non-existent directory** — helper exits 2 with the resolved path and `vault path does not exist; create the directory in Obsidian.app first`. Doesn't auto-create — that's `/wiki-setup`'s job.
- **`--migrate` slug collision** — two existing pages map to the same canonical slug (e.g., `PatternCall.md` and `patterncall.md` on a case-sensitive filesystem). Helper refuses to migrate the colliding pair, lists them in the dry-run output as `[collision] manual resolution needed`, and proceeds with the rest. Single-page collisions don't block the migration as a whole.
- **`--migrate` interrupted mid-run** — atomic-write trap on rename loop: if any rename fails, the helper aborts and reports the in-flight state (renames already done are not auto-reverted; the helper exits with a non-zero code and surfaces a manual cleanup checklist). Wikilink rewrites only happen after all renames succeed, so a partial migration cannot leave broken links.
- **Wikilink rewriting in code fences** — helper's rewriter ignores `[[...]]` tokens that appear between ` ``` ` fences (and inline backtick spans), to avoid corrupting code samples. Counted as `skipped (in code)` in the migration report.
- **Wikilink rewriting in frontmatter values** — same: helper ignores `[[...]]` that appears inside frontmatter (between the first two `---` lines). Counted as `skipped (in frontmatter)`.
- **Fragment / embed links** — `[[foo#section]]` and `![[foo]]` are rewritten the same way as bare `[[foo]]` (the `foo` part). Section anchors and embed sigils preserved.
- **User edits `<vault>/projects/_convention.md`** — install.sh re-run backs up the user-edited file to `.bak.<ts>` before overwriting. User can restore. The template is the source of truth; per-vault customization isn't supported in v1 (could be a follow-up: a `.local` override sentinel similar to the install.sh adopter pattern).
- **Model calls upstream wiki-update directly anyway** — happens. The lint phase catches it within one `/wrap` cycle. User can fix by running `--migrate`. The convention rule in ~/CLAUDE.md is advisory, not mandatory; we don't try to block direct wiki-update calls (would require patching upstream, which Q5 ruled out).
- **Slug after transform is empty** — title was all symbols (`"!!!"`) or all stripped chars. Helper refuses with exit 3 and surfaces `slug computation produced empty string; pick a different title`.
- **Title contains a forward slash** — `re.sub(r'\s+', '-', ...)` doesn't catch `/`. Slug computation strips it before the kebab transform; resulting slug joins the parts with a hyphen. E.g., `"a/b"` → `a-b`.
- **Long titles** — slug capped at 80 chars. Truncation happens before the trailing-hyphen strip. Title-frontmatter field preserves the full original.
- **install.sh sentinel block already present in ~/CLAUDE.md** — install.sh's existing sentinel-aware insert pattern replaces the content between the sentinels rather than appending a duplicate block.
- **install.sh run in a non-interactive context (CI / autorun)** — `install_wiki_conventions` runs unconditionally; no prompts. Failures are non-fatal and collected into the tail-summary block (per the `install_sh_auto_install_then_tail_summary` memory pattern).

## Acceptance Criteria

1. `templates/wiki-conventions.md` exists in the MonsterFlow repo and codifies the slug rules (kebab-ascii regex), layout rules (folder+index for projects, flat for concepts and entities), and frontmatter schema per category from this spec verbatim.
2. `scripts/wiki-write.py` accepts `--category {project,concept,entity}`, `--title <T>`, optional `--topic <T>`, optional `--summary <S>`, optional `--tags <T1,T2>`, optional `--force`. Exits 0 on success and prints the written file path to stdout. Exits 1 when the vault is not configured, 2 when the vault path does not exist, 3 when the computed slug is empty.
3. Slug computation is deterministic: `re.sub(r'[^a-z0-9-]', '', re.sub(r'\s+', '-', title.lower().strip()))`, followed by double-hyphen collapse, trailing-hyphen strip, and 80-character truncation. Test fixture: `"PatternCall — iOS Native Rewrite"` → `"patterncall-ios-native-rewrite"`.
4. Helper writes frontmatter (schema per the Data section) and an empty body, atomically via `tempfile.NamedTemporaryFile` + `os.replace`. Refuses to overwrite an existing file unless `--force` is passed.
5. `scripts/wiki-write.py --migrate [--dry-run]` scans the vault, proposes a rename plan with a wikilink-rewrite count, asks for `[y/N]` confirmation when run without `--dry-run`, performs renames sequentially, rewrites wikilinks after all renames succeed, and writes `<vault>/migration-report.md` with the result.
6. `scripts/wiki-write.py --lint` scans the vault for convention violations (em-dashes in filenames, mixed case, projects/ entries without an `index.md`) and prints a `WARN <N> violations:` block. Exits 0 (non-blocking) regardless of violation count.
7. `install.sh` `do_knowledge_layer` invokes a new `install_wiki_conventions` step that writes `<vault>/{projects,concepts,entities}/_convention.md` from `templates/wiki-conventions.md` and injects a sentinel-bracketed wiki-conventions block into ~/CLAUDE.md. Both writes are idempotent. ~/CLAUDE.md backup at `~/CLAUDE.md.bak.<ts>` is created once per install run before any modification.
8. `tests/test-wiki-write.sh` covers the slug transform with em-dash input, the frontmatter shape per category, the atomic-write trap, the `--migrate --dry-run` output shape, the `--lint` detection of three violation types, the ~/CLAUDE.md sentinel-block idempotency on re-run, and the wikilink-rewrite skip behavior for code-fence and frontmatter references.
9. `commands/wrap.md` Phase 2c invokes `wiki-write.py --lint` after wiki-sync and surfaces violations in the wrap summary as a non-blocking warning.

## Open Questions

None at write time. Confidence on edges is 0.88 (below the 0.95 manual gate); the remaining uncertainty is around wikilink-rewriting edge cases that the spec explicitly punts to `skipped` status with a manual-review report — those are documented behaviors rather than unresolved questions, so proceeding without further Q&A.

A future follow-up worth tracking, not blocking this spec:

- Upstream PR to `Ar9av/obsidian-wiki` adding convention-discovery to wiki-update natively, which would let us relax the ~/CLAUDE.md instruction once it lands. Tracked in BACKLOG.md, not in this spec.
