---
created: 2026-05-15
constitution: none
revision: V2 (post-spec-review)
confidence:
  scope: 0.95
  ux: 0.92
  data: 0.95
  integration: 0.92
  edges: 0.92
  acceptance: 0.95
gate_mode: permissive
tags: [api, data, docs, integration, scalability, security, ux]
tags_provenance:
  baseline: [api, data, integration, scalability, security, ux]
  llm_added: [docs]
  user_overrides: []
---

# wiki-write-conventions Spec

**Created:** 2026-05-15
**Revision:** V2 — folds in 3 reviewer + 23 Codex findings; migration carved to follow-up spec
**Constitution:** none (MonsterFlow personal-tooling repo; pipeline owns roster)
**Confidence:** scope 0.95, ux 0.92, data 0.95, integration 0.92, edges 0.92, acceptance 0.95
**gate_mode:** permissive

## Summary

Three separate wiki-update calls produced three different layouts for the same logical project (`projects/PatternCall/PatternCall`, `projects/PatternCall — iOS Native Rewrite`, `projects/Welcome`), because the upstream `wiki-update` skill has no canonical schema for how project / concept / entity pages get named and structured. This spec ships a deterministic Python helper (`scripts/wiki-write.py`) that computes paths and writes the full file (frontmatter + body) atomically in one shot — code, not prompts, performs both the path decision and the write. install.sh derives both a per-category vault `_convention.md` and a sentinel-bracketed block in ~/CLAUDE.md from a single template, so the rule lives in user-owned surfaces and survives upstream `setup.sh` re-runs. A `/wrap` lint phase catches drift when the model bypasses the helper. Migration of existing wrong-structure pages is explicitly out of scope and carved to a follow-up spec (`wiki-write-migrate`) where the wikilink-rewriting and rollback complexity can be designed properly.

## Backlog Routing

| Item | Source | Routing |
|------|--------|---------|
| resolver-recovery-shell-owned | BACKLOG.md (added today) | stays — unrelated to wiki conventions |
| install-obsidian-wiki-auto-clone | BACKLOG.md | stays — adjacent (touches obsidian-wiki install), but different surface |
| uninstall.sh reverter | BACKLOG.md | stays — different concern |
| PR #10 plot layer review | BACKLOG.md | stays — different concern |
| **wiki-write-migrate (NEW, this spec's V2 carve-out)** | spec-review V1 → V2 | **new spec later** — carved out tonight, file via /spec when the core helper has been in use for a week |

## Scope

**In scope:**

- A canonical layout for the three top-level vault categories that MonsterFlow's flow touches most: `projects/`, `concepts/`, `entities/`. Projects get folder + `index.md`; concepts and entities stay flat.
- A deterministic slug rule (Unicode-dash normalization + strict kebab-case + ASCII only) that makes file names URL-stable, prevents case-insensitive-filesystem collisions, and mechanically forbids em-dashes (per the personal-voice rule the user has codified twice).
- A Python helper at `scripts/wiki-write.py` that the model is told (via ~/CLAUDE.md) to invoke for any write under those three categories. **The helper owns the full write lifecycle:** it accepts body content via `--body <text>` or `--body-stdin`, computes the path, writes the complete file (frontmatter + body) atomically in one shot. Model never authors the path string AND never makes a follow-up Edit call to add body content.
- A `templates/wiki-conventions.md` source-of-truth that install.sh derives two artifacts from: a vault-side `_convention.md` per category, and a sentinel-bracketed block in ~/CLAUDE.md. install.sh is the only writer of either; updating the template + re-running install.sh refreshes both.
- A `/wrap` lint phase that runs `wiki-write.py --lint` and reports violations (em-dashes in filenames, mixed-case filenames, `projects/` entries without `index.md`) as a non-blocking warn — catches the slip path where the model bypasses the helper.

**Out of scope (explicit carve-outs):**

- **Migration of existing wrong-structure pages.** Wikilink rewriting in Obsidian (shortest-unique-path resolution, basename collisions across folders, piped-link form `[[old|display]]`, fragment links, embed links) plus filesystem-collision handling (case-insensitive macOS HFS+/APFS, Unicode normalization variants, existing-folder-vs-existing-file conflicts) plus a durable journal for resume/rollback together represent ~40-60% of the original spec's implementation surface and the only piece that touches existing vault content destructively. Carved to a follow-up spec `wiki-write-migrate` (tracked in BACKLOG.md after this spec ships). Adopters with existing wrong-structure pages live with them under the new convention's lint warnings until the migrate spec ships.
- Touching the upstream `Ar9av/obsidian-wiki` skill prompts. We do NOT patch `~/.claude/skills/wiki-update/SKILL.md` — that file is owned by the upstream tool's `setup.sh` and any local patch gets wiped on re-run.
- An upstream PR to `Ar9av/obsidian-wiki` adding convention-discovery. Future work; tracked separately.
- Layout rules for `_archives/`, `_raw/`, `index.md`, `log.md` — owned by `/wiki-setup` (upstream).
- Free-form note writes (the user pasting raw text into the vault outside of `wiki-update`). The helper is opt-in; direct vault writes are unaffected.
- Multi-agent enforcement surface. install.sh writes ~/CLAUDE.md (the surface Claude Code reads); other agent entrypoints (Codex, Cursor, Hermes) are not in scope for v1. The vault `_convention.md` files are the cross-agent fallback — any agent that reads the vault will see them.
- Concurrent-write coordination. Two parallel agent sessions writing to the same page is documented as last-writer-wins. Single-user vault assumption; fcntl locks deferred until two-agent contention is observed in practice.
- Aliases-in-frontmatter migration helper. Documented as a noted limitation; can be added in a follow-up.
- Topic-name slug rules beyond the basic kebab transform (reserved names, length caps for topics specifically). Topic uses the same slug transform as the project; if that produces a problem in practice it gets fixed then.

## Approach

User-directed across 7 Q&A rounds + 1 review-driven revision. Three moving parts that compose:

1. **Template at `templates/wiki-conventions.md`** is the single source of truth for human-readable conventions (what slug rules look like, what frontmatter looks like, examples). The slug-transform and layout-decision LOGIC lives in `scripts/wiki-write.py` as Python constants (per Codex finding #8 — runtime parsing of markdown rules is fragile); the template is documentation, not executable rules.
2. **`scripts/wiki-write.py`** is a deterministic helper that does slug transform + layout decision + frontmatter emission + body write in Python (~200 LoC). Subcommands: default-write (with `--body` or `--body-stdin`) and `--lint`. Migration is NOT in this spec.
3. **`install.sh` `do_knowledge_layer`** writes the three vault `_convention.md` files from the template and injects a sentinel-bracketed block into ~/CLAUDE.md. Idempotent — re-running refreshes both targets cleanly. Backups of pre-existing files via `.bak.<ts>`.
4. **`/wrap` Phase 2c lint addition** runs `wiki-write.py --lint` after wiki-sync and surfaces violations in the wrap summary. Non-blocking.

Key design choice (reinforced by review): code, not prompts, enforces the rule AND owns the full write. The original V1 had the helper write an empty body and expected a follow-up Edit; Codex finding #1 correctly identified that as a gap (model can still corrupt body content during the Edit). V2 closes that gap: helper takes body via flag or stdin, writes the complete file atomically.

## Roster Changes

No roster changes. Pipeline default personas cover this scope.

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
2. Model reads ~/CLAUDE.md's wiki-conventions block (in system prompt at session start), which says "for project/concept/entity writes, call `python3 ~/Projects/MonsterFlow/scripts/wiki-write.py` with the documented flags. Pass body via `--body` (short) or `--body-stdin` (long). Do not make follow-up Edit calls to add body content."
3. Model invokes (short body):
   ```bash
   python3 ~/Projects/MonsterFlow/scripts/wiki-write.py \
     --category project \
     --title "PatternCall iOS Native Rewrite" \
     --topic "decisions" \
     --summary "Native SwiftUI/SpriteKit rewrite of the PatternCall web app" \
     --tags "ios,native,rewrite" \
     --body "## Decision (2026-05-15)\n\nChose SwiftUI over React Native because..."
   ```
   Or for longer bodies, via stdin:
   ```bash
   cat <<'EOF' | python3 ~/Projects/MonsterFlow/scripts/wiki-write.py \
     --category project --title "PatternCall iOS Native Rewrite" --topic decisions \
     --summary "..." --tags "ios" --body-stdin
   ## Decision (2026-05-15)
   ...
   EOF
   ```
4. Helper normalizes title through Unicode-dash pre-pass: replaces em-dash (`U+2014`), en-dash (`U+2013`), figure-dash (`U+2012`), horizontal-bar (`U+2015`), minus-sign (`U+2212`), and Unicode hyphens (`U+2010`, `U+2011`) with ASCII hyphen-minus BEFORE the kebab transform.
5. Helper computes slug: `patterncall-ios-native-rewrite`.
6. Helper detects `--topic` is set → write target is `<vault>/projects/patterncall-ios-native-rewrite/decisions.md`. Without `--topic`, target would be `<vault>/projects/patterncall-ios-native-rewrite/index.md`.
7. Helper writes the full file (frontmatter + body) atomically via tmp + `os.replace`.
8. Helper prints the written path to stdout, exits 0.

**Lint (every `/wrap`):**

1. `/wrap` Phase 2c calls `python3 ~/Projects/MonsterFlow/scripts/wiki-write.py --lint`.
2. Helper scans vault for convention violations.
3. Surfaces in `/wrap` output. Zero violations:
   ```
   === Wiki Convention Lint ===
   ok   42 pages compliant
   ```
   With violations:
   ```
   === Wiki Convention Lint ===
   ok   42 pages compliant
   WARN 3 violations:
     projects/PatternCall — iOS Native Rewrite.md (em-dash in filename)
     projects/Welcome.md (no folder + index pattern)
     concepts/HostImprov.md (mixed case in filename)
   Fix: re-write via wiki-write.py with the same content under the canonical path. Migration helper tracked in BACKLOG.md → wiki-write-migrate.
   ```
4. Non-blocking — `/wrap` continues. Exit code always 0.

## Data & State

**Files MonsterFlow owns:**

- `templates/wiki-conventions.md` — single source of truth for human-readable conventions. Documentation only; the executable rules live in `scripts/wiki-write.py` as Python constants.
- `scripts/wiki-write.py` — the helper. Python 3.10+. Stdlib only. Atomic writes via `tempfile.NamedTemporaryFile(dir=<target-parent>, delete=False)` + `os.replace`. Slug-transform constants (Unicode-dash list, slug regex, length cap) defined at module top, doubly-tested via `tests/test-wiki-write.sh`.
- `tests/test-wiki-write.sh` — bash test harness. Cases: slug transform with em-dash adjacent to spaces, slug transform with em-dash WITHOUT adjacent spaces, slug transform with mixed Unicode dashes, frontmatter shape per category, atomic-write fault-injection trap, `--lint` zero-violation output, `--lint` detection of three violation types, `--lint` exit code when vault absent, `--body` and `--body-stdin` both write the body correctly, ~/CLAUDE.md sentinel-block idempotency on re-run.

**Files MonsterFlow writes/modifies at install time:**

- `<vault>/projects/_convention.md`, `<vault>/concepts/_convention.md`, `<vault>/entities/_convention.md` — derived from `templates/wiki-conventions.md`. Per-category subset of the rules. Backed up to `.bak.<ts>` before overwrite if user has edited them. Frontmatter `type: convention` and `exclude: true` so Obsidian's graph/search treats them as docs, not concepts (Codex finding #22).
- `~/CLAUDE.md` — sentinel-bracketed block injected at the end of the file. Sentinels: `<!-- WIKI-CONVENTIONS-START -->` and `<!-- WIKI-CONVENTIONS-END -->`. Backs up `~/CLAUDE.md.bak.<ts>` once per install run before any modification.

**Files MonsterFlow writes at runtime:**

- `<vault>/{projects,concepts,entities}/<slug>/index.md` or `<slug>.md` — actual content writes via `wiki-write.py`. Atomic.

**Slug rule (frozen, V2 — codified in `scripts/wiki-write.py` as `slugify(title: str) -> str`):**

```python
# Module constants (top of scripts/wiki-write.py)
UNICODE_DASHES = ['‐', '‑', '‒', '–', '—', '―', '−']
SLUG_MAX_LEN = 80
SLUG_VALID = re.compile(r'^[a-z0-9][a-z0-9-]{0,79}$')

def slugify(title: str) -> str:
    # 1. Strip + lowercase
    t = title.strip().lower()
    # 2. Normalize Unicode dashes to ASCII hyphen-minus BEFORE kebab transform
    for d in UNICODE_DASHES:
        t = t.replace(d, '-')
    # 3. Spaces and forward slashes to hyphens
    t = re.sub(r'[\s/]+', '-', t)
    # 4. Strip all non-[a-z0-9-]
    t = re.sub(r'[^a-z0-9-]', '', t)
    # 5. Collapse double-hyphens
    t = re.sub(r'-+', '-', t)
    # 6. Strip leading/trailing hyphens
    t = t.strip('-')
    # 7. Truncate to 80 chars, then re-strip trailing hyphen (in case truncation landed mid-word)
    t = t[:SLUG_MAX_LEN].rstrip('-')
    # 8. Validate; refuse empty
    if not t:
        raise ValueError("slug computation produced empty string; pick a different title")
    return t
```

Fixtures (must pass in `tests/test-wiki-write.sh`):
- `"PatternCall — iOS Native Rewrite"` → `patterncall-ios-native-rewrite` (em-dash with spaces)
- `"PatternCall—iOS"` → `patterncall-ios` (em-dash WITHOUT spaces — Codex finding #2)
- `"Foo—Bar—Baz"` → `foo-bar-baz`
- `"foo  bar"` (double space) → `foo-bar`
- `"a/b"` → `a-b`
- `"Café Society"` → `caf-society` (non-ASCII stripped; Codex finding #20 — documented tradeoff, transliteration deferred)
- `"!!!"` → raises ValueError
- `"a" * 100` → 80-char truncation, strips trailing hyphen if any

**Frontmatter schemas (codified in `scripts/wiki-write.py` as Python dicts, NOT parsed from template at runtime):**

`projects/<slug>/index.md`:
```yaml
---
title: PatternCall iOS Native Rewrite
created: 2026-05-15
summary: Native SwiftUI/SpriteKit rewrite of the PatternCall web app
status: active
tags: [project, ios]
---
```

`projects/<slug>/<topic>.md`:
```yaml
---
title: Decisions
created: 2026-05-15
parent: patterncall-ios-native-rewrite
summary: <one-line summary>
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
type: person
summary: <one-line summary>
tags: [entity, person]
---
```

**YAML emission rule:** the helper emits frontmatter using JSON-compatible YAML — string values are written as JSON strings (`json.dumps(value)`) which is valid YAML for scalars (Codex finding #16 addressed without a YAML library). Multi-line strings are quoted with escaped newlines. Lists are emitted in flow style `[a, b, c]` with each element JSON-encoded.

## Integration

**Touches:**

- `install.sh` — `do_knowledge_layer` gains a new step (`install_wiki_conventions`) that runs after `manage_scaffold_marker`. Reads `templates/wiki-conventions.md`, writes the three vault `_convention.md` files (with `type: convention, exclude: true` frontmatter), injects the sentinel block into ~/CLAUDE.md. Idempotent.
- `commands/wrap.md` — Phase 2c (the wiki-sync phase) gets a new sub-step: after wiki-update writes, call `wiki-write.py --lint` and surface violations in the wrap summary. Non-blocking. Exit code 0 regardless.
- `~/CLAUDE.md` (the user's) — gains a sentinel-bracketed wiki-conventions block. Block content: "When writing to the Obsidian vault under `projects/`, `concepts/`, or `entities/`, use `python3 ~/Projects/MonsterFlow/scripts/wiki-write.py` instead of computing the path freehand in a wiki-update call. Pass body via `--body` or `--body-stdin`; the helper writes the complete file atomically. Do not follow with an Edit to add body content." Plus a one-line link to the vault's `_convention.md` files for the full rules.
- `tests/run-tests.sh` — picks up `tests/test-wiki-write.sh` via the existing glob pattern.
- `BACKLOG.md` — adds `wiki-write-migrate` follow-up spec entry (the carved-out migration work).

**Doesn't touch:**

- Upstream `Ar9av/obsidian-wiki` repo (no PRs, no patches to ~/.claude/skills/wiki-update/).
- Existing MonsterFlow pipeline gates (`/spec-review`, `/blueprint`, `/check`, `/build`). The helper is a leaf script, not pipeline machinery.
- `wiki-query` (read side). Convention only governs writes; reads unaffected.
- `wiki-ingest`, `wiki-export`, `wiki-lint` (upstream), `wiki-capture`.

## Edge Cases

- **Vault not configured** — `~/.obsidian-wiki/config` absent. Helper exits 0 with `[wiki-write] skip: vault not configured; run setup.sh in obsidian-wiki repo first` (silent-skip per the install.sh adopter pattern; non-blocking for `/wrap` lint). Default-write subcommand exits 1 in this case with the same message; only `--lint` is silent-skip.
- **Vault path expands to a non-existent directory** — helper exits 2 with the resolved path and `vault path does not exist; create the directory in Obsidian.app first`. Doesn't auto-create — that's `/wiki-setup`'s job.
- **Concurrent writes from two agent sessions** — last-writer-wins. Atomic `os.replace` protects each individual write from partial state; two helpers writing to the same path race on the final replace. Documented; fcntl locks deferred until contention is observed (Codex finding #15).
- **TOCTOU on `--force` overwrite check** — there is a small window between the `os.path.exists` check and the `os.replace`. For a single-user vault, last-writer-wins is acceptable. Documented; same deferral as concurrent writes above.
- **Topic-slug edge case (Codex finding #10)** — topic name goes through the same `slugify()` transform as project title. `--topic "Open Questions / Risks"` → `open-questions-risks`. Length cap and empty-after-transform raise the same `ValueError`.
- **Reserved filenames (Codex finding #19)** — helper refuses `_convention`, `index` (without `--topic`), `log`, `_archives`, `_raw` as topic names. Project slugs are unrestricted (collision with `_convention.md` is structurally impossible because conventions live one directory up).
- **YAML special characters in title/summary/tags (Codex finding #16)** — helper emits all string scalars via `json.dumps()`, which produces valid YAML. Titles like `Foo: Bar` or summaries containing single quotes are correctly escaped without a YAML library dependency.
- **Tags input parsing (Codex finding #17)** — `--tags "a,b,c"` splits on comma, strips whitespace per tag, drops empty tags. Leading `#` is stripped (Obsidian uses `#` for inline tags, frontmatter doesn't). Tags must each match `^[a-z][a-z0-9-]*$` after normalization (slug rules). Invalid tags surface a warning and are dropped from the emitted list.
- **`--body` and `--body-stdin` both set** — helper refuses with exit 1, `pick one of --body or --body-stdin, not both`.
- **Neither `--body` nor `--body-stdin` set** — helper writes the file with frontmatter + an empty body. This is allowed (matches V1 behavior for stub-write cases like a new project's `index.md` that gets edited later via Obsidian directly), but the model is told via ~/CLAUDE.md to prefer providing body content explicitly.
- **`--lint` and `install_wiki_conventions` when vault is absent** — both exit 0 with a skip notice. `/wrap` surfaces the skip notice and continues. No spurious errors on machines without a vault.
- **Slug after transform is empty** — title was all symbols or stripped chars. Helper refuses with exit 3 and `slug computation produced empty string; pick a different title`.
- **install.sh sentinel block already present in ~/CLAUDE.md** — install.sh's existing sentinel-aware insert pattern replaces the content between the sentinels rather than appending a duplicate block. ~/CLAUDE.md.bak is created before the first modification of this install run; subsequent re-runs in the same run don't create additional backups.
- **install.sh in CI / autorun (no TTY)** — `install_wiki_conventions` runs unconditionally; no prompts. Failures collected into the tail-summary block.
- **Backup accumulation (Codex finding #23)** — `~/CLAUDE.md.bak.<ts>` and `_convention.md.bak.<ts>` files accumulate over re-runs. install.sh prunes backups older than 7 days at install time (configurable via `MONSTERFLOW_BACKUP_RETAIN_DAYS`; default 7). Documented; not enforced via /wrap lint.
- **Existing wrong-structure pages in the vault** — explicitly out of scope for this spec. The lint surfaces them as violations and points at `wiki-write-migrate` (the follow-up spec in BACKLOG.md). Adopters can either re-write affected pages manually via the helper or wait for the migration spec to ship.
- **Codex / Cursor / other agents (Codex finding #7)** — v1 ships ~/CLAUDE.md as the primary install target. The vault `_convention.md` files are the cross-agent fallback — any agent that reads the vault before writing will see them. Codex-specific AGENTS.md integration is tracked as a follow-up; not a blocker for v1.

## Acceptance Criteria

1. `templates/wiki-conventions.md` exists in the MonsterFlow repo and codifies (in human-readable prose) the slug rules, layout rules (folder+index for projects, flat for concepts/entities), and frontmatter schema per category from this spec. The template is documentation; executable logic lives in the Python helper.

2. `scripts/wiki-write.py` accepts: `--category {project,concept,entity}`, `--title <T>`, optional `--topic <T>`, optional `--summary <S>`, optional `--tags <T1,T2,...>`, optional `--entity-type {person,organization,tool,other}` (default `other`; only meaningful when `--category entity`), optional `--body <text>` or `--body-stdin` (mutually exclusive), optional `--force`, optional `--lint` (mode-switch flag), optional `--write-conventions <vault-path>` (mode-switch flag; emits the three `_convention.md` files into the named vault). Exit codes: 0 success or silent-skip (vault absent + `--lint`), 1 vault-absent on default-write, helper-misuse, or `--body` and `--body-stdin` both set, 2 vault path resolved but directory does not exist, 3 slug computation produced empty string.

3. Slug computation matches the `slugify()` reference implementation in the `## Data & State` section verbatim. All 8 fixture cases listed there pass in `tests/test-wiki-write.sh`. Specifically: `"PatternCall — iOS Native Rewrite"` → `patterncall-ios-native-rewrite` AND `"PatternCall—iOS"` (no surrounding spaces) → `patterncall-ios`.

4. Helper writes the full file (frontmatter + body, when body is provided) atomically via `tempfile.NamedTemporaryFile(dir=<target-parent>, delete=False)` + `os.replace`. Test fixture in `tests/test-wiki-write.sh` injects a fault between tmp-write and rename (via monkey-patched `os.replace` raising `OSError`) and asserts no partial file exists at the target path after the failure. Refuses to overwrite an existing file unless `--force` is passed; TOCTOU on the existence check is documented as last-writer-wins (single-user vault assumption).

5. **REMOVED in V2** — migration carved to follow-up spec `wiki-write-migrate` (tracked in BACKLOG.md).

6. `scripts/wiki-write.py --lint` scans the vault for four violation types — (1) Unicode dash in filename, (2) mixed case in filename, (3a) `projects/<name>.md` (flat file where folder + index expected), (3b) `projects/<name>/` (folder missing `index.md`) — and prints: when violations == 0, exactly one line `ok   <N> pages compliant` followed by exit 0; when violations > 0, the same `ok` line followed by `WARN <N> violations:` and one bullet per violation (each bullet names the path and the type number), exit 0 regardless. `/wrap` Phase 2c parses this output by detecting the `WARN <N> violations:` line; absence means zero violations.

7. `install.sh` writes vault `_convention.md` files via `install_wiki_conventions` inside `do_knowledge_layer` (Zone B), AND injects the sentinel-bracketed wiki-conventions block into ~/CLAUDE.md via `_install_wiki_conventions_claude_md_block` invoked AFTER the existing `claude-md-merge.py` baseline merge at install.sh line ~1440 (the two-stage split is required because `do_knowledge_layer` runs at line 1421, before the baseline merge at line 1440 — injecting the sentinel block earlier would let the baseline merge interact with or strip it). The vault `_convention.md` files carry frontmatter `type: convention` (Obsidian doesn't natively honor `exclude: true`; the `_` prefix on the filename is the actual exclusion mechanism plus a manual user step in Obsidian Settings → Files & Links → Excluded files). ~/CLAUDE.md sentinel block re-runs REPLACE content between sentinels rather than appending. ~/CLAUDE.md backup at `~/CLAUDE.md.bak.<ts>` is created once per install run before any of the three ~/CLAUDE.md writers (`append_wiki_preflight_instruction`, `claude-md-merge.py`, the new sentinel-block injector) modifies the file; subsequent writers in the same run skip backup creation via a shared run-scoped guard.

8. `tests/test-wiki-write.sh` covers, at minimum: (a) the 8 slug-transform fixtures from `## Data & State`, (b) frontmatter shape per category (project index, project topic, concept, entity), (c) atomic-write fault-injection trap, (d) `--lint` zero-violation output format, (e) `--lint` detection of the three violation types listed in AC #6, (f) `--lint` silent-skip exit 0 when vault is absent, (g) `--body` and `--body-stdin` both write body correctly, (h) `--body` + `--body-stdin` mutual exclusion (exit 1), (i) `--force` overwrite behavior, (j) ~/CLAUDE.md sentinel-block idempotency on re-run (no duplicate appends), (k) YAML special-char escaping (titles with colons, summaries with quotes), (l) topic-name reserved-name refusal (`--topic _convention` fails).

9. `commands/wrap.md` Phase 2c invokes `python3 ~/Projects/MonsterFlow/scripts/wiki-write.py --lint` after wiki-sync and surfaces violations in the wrap summary as a non-blocking warning block. Exit code 0 from the lint helper does not block `/wrap` Phase 2c from proceeding to subsequent phases.

## Open Questions

None at write time. V2 confidence ≥ 0.92 across all dimensions. The remaining uncertainty is around Codex agent compatibility (~/CLAUDE.md vs AGENTS.md — Codex finding #7), which is documented as out-of-scope for v1 and tracked as a follow-up.
