# Design — wiki-write-conventions

**Date:** 2026-05-15
**Designers dispatched:** api:opus, data-model:sonnet, integration:sonnet (codex disabled at /blueprint per default)
**Budget:** 3 (agent_budget=3 in ~/.config/monsterflow/config.json)
**Gate mode:** permissive (frontmatter)
**Status:** ready for /check

## Design Decisions

### D1 — CLI shape: single parser, `--lint` as mode-switch flag (not subcommand)

Per AC #2 verbatim ("optional `--lint` (subcommand)"), but implemented as a top-level `--lint` flag that switches behavior at the action layer, not as an argparse subparser. Reasons (from api design):
- Single `--help` surface — the model reads one doc to understand the tool
- Avoids argparse's "default subcommand" awkwardness
- Migration is the obvious place to break out into a real subcommand later; v1 stays flat

### D2 — Helper owns FULL write lifecycle (frontmatter + body in one atomic write)

V2 spec mandate: no more empty-skeleton + Edit-append. The helper takes body via `--body <text>` or `--body-stdin`, builds the complete file (frontmatter + body), and atomic-writes it in one shot. Mutual exclusion enforced at the action layer; neither flag set = empty body allowed (for stub `index.md` cases). All writes funnel through a single `write_page()` seam so the atomic-write fault-injection test (AC #4) has one place to monkey-patch `os.replace`.

### D3 — 7 custom exceptions, each carrying `exit_code` attribute

`WikiWriteError(Exception)` base with `exit_code = 1` default. Subclasses override:
- `VaultNotConfiguredError(WikiWriteError)` — exit 1 (default-write) or exit 0 (lint silent-skip)
- `VaultPathMissingError(WikiWriteError)` — exit 2
- `EmptySlugError(WikiWriteError, ValueError)` — exit 3 (multi-inherit ValueError per spec mandate)
- `MutuallyExclusiveError(WikiWriteError)` — exit 1
- `MissingRequiredArgError(WikiWriteError)` — exit 1
- `ReservedTopicError(WikiWriteError)` — exit 1
- `FileExistsNoForceError(WikiWriteError)` — exit 1

CLI boundary plucks `exit_code` via attribute, never `isinstance` chains.

### D4 — Exit code matrix locked at 4 (0/1/2/3); argparse errors collapse to 1

AC #2 specifies 4 exit codes. Override `ArgumentParser.error()` so argparse-detected failures (unknown flag, bad `--category` choice) raise our own `MissingRequiredArgError` and exit 1, not argparse's default exit 2 (which is reserved for "vault path resolved but directory does not exist"). This contract is testable and matches the spec.

### D5 — Frontmatter emission: deterministic field order, `json.dumps()` for all string scalars

`FIELD_ORDER` Python list constants per category at module top:
- `PROJECT_INDEX_ORDER = ['title', 'created', 'summary', 'status', 'tags']`
- `PROJECT_TOPIC_ORDER = ['title', 'created', 'parent', 'summary', 'tags']`
- `CONCEPT_ORDER = ['title', 'created', 'summary', 'tags']`
- `ENTITY_ORDER = ['title', 'created', 'type', 'summary', 'tags']`

YAML rules:
- All string scalars emitted as `json.dumps(value)` (JSON is a valid YAML subset for scalars; handles colons, quotes, Unicode without a YAML library)
- Tags: flow style `[json.dumps(t) for t in tags]` joined with `, ` and wrapped in `[ ]`
- Date `created`: quoted string `"2026-05-15"` (local date, no timezone) — testable via `DATE_OVERRIDE` env var hook
- Summary: collapsed to single line via `re.sub(r'\s+', ' ', summary).strip()` before `json.dumps()` — the summary field is a one-line contract for wiki-query Phase 0.2 callouts

Field order is frozen — deterministic emission enables byte-equality tests.

### D6 — Lint detection: 4 violation types (added "spaces in filename" per data-model)

V2 spec had 3 types; data-model designer added a 4th. Final list:
1. Em-dash (or any Unicode dash from the slugify list) in filename
2. Mixed case in filename (any uppercase character in basename)
3. `projects/<name>.md` (flat file where folder + index expected) — distinct violation subtype 3a
4. `projects/<name>/` (folder with no `index.md` inside) — distinct violation subtype 3b
5. Spaces in filename

Lint output format (locked by AC #6 + api design):
```
ok   <N> pages compliant
WARN <M> violations:
  <category>/<path> (<violation type description>)
  ...
```
Zero violations: just the `ok` line, exit 0.
Vault absent: `[wiki-write] skip: vault not configured` line, exit 0.

No `=== Wiki Convention Lint ===` banner from the helper — that's `/wrap`'s decoration. Keeps parser anchors at column 0.

### D7 — `--write-conventions <vault>` is a 3rd helper mode

Data-model + integration designers converged on this. install.sh's `install_wiki_conventions` step invokes `wiki-write.py --write-conventions <vault-path>` rather than embedding the convention-file content in a bash heredoc. The content lives as Python string constants in the helper where it's testable. Adds one CLI mode to the 2 already specified; tradeoff worth taking.

### D8 — Sentinel-block replacement, not append-with-sentinels skip-if-present

Per integration design: when ~/CLAUDE.md already has the wiki-conventions block (from a previous install run), the new run REPLACES the content between sentinels rather than skipping. This is different from the existing `append_wiki_preflight_instruction` pattern (which skips-if-present) because the convention block will evolve with the template; skip-if-present would leave stale content.

Implementation: standalone `scripts/_replace_sentinel_block.py` (per memory `hook_stdin_heredoc` — never `python3 -` with stdin JSON). Function: `replace_block(target_file, start_sentinel, end_sentinel, new_content)`. Idempotent.

### D9 — install.sh sequencing: `install_wiki_conventions` is last in `do_knowledge_layer` Zone B

Order:
1. `_prune_old_backups` (existing or new; centralized backup pruning at top of Zone B)
2. `manage_scaffold_marker` (existing — v0.15.0)
3. `append_wiki_preflight_instruction` (existing)
4. `install_wiki_conventions` (NEW)

The new step silent-skips vault `_convention.md` writes when `.scaffold-pending` exists (vault not yet structured), but STILL injects the ~/CLAUDE.md block. Split logic factored into 2 sub-functions: `_install_vault_conventions` (gated by scaffold check) and `_install_claude_md_block` (always runs).

### D10 — Backup deduplication via run-scoped guard variable

`WIKI_CONV_CLAUDE_MD_BACKED_UP` is set after the first `~/CLAUDE.md.bak.<ts>` is created in a given install run. Subsequent functions in Zone B (`append_wiki_preflight_instruction`, `install_wiki_conventions`'s `_install_claude_md_block`) check this before creating their own backup. Single backup per install run.

`_prune_old_backups` retains files newer than `MONSTERFLOW_BACKUP_RETAIN_DAYS` (default 7). Scope: only `~/CLAUDE.md.bak.<epoch>` and `<vault>/{projects,concepts,entities}/_convention.md.bak.<epoch>` — NOT a broad `$HOME` sweep (would be dangerous and out of scope).

### D11 — `/wrap` Phase 2c lint as Step 3b, always runs (when vault configured)

Per integration design: lint runs whether or not THIS session wrote to the wiki. Convention drift can come from any session; conditioning on writes defeats the purpose. Emits its own fenced block in `/wrap` output, no approval gate, exit-code-0 regardless.

### D12 — Test orchestrator wiring is a NAMED task in the build plan

Per integration design + memory `test-orchestrator-wiring-gap`: parallel `/build` waves that write tests + chmod individually but skip the `run-tests.sh` TESTS-array wiring leave the orchestrator running only legacy tests. This plan assigns the wiring as a SPECIFIC task (T7 below) so it gets a named owner.

### D13 — Contract refinements added by data-model designer (folded in)

- **`--entity-type <t>` required when `--category entity`**. Values: `person | organization | tool | other`. Without it, helper raises `MissingRequiredArgError` (exit 1). Spec V2's frontmatter schema mandates `type:` field; this flag is its input.
- **Topic title humanization rule**. When `--topic foo-bar` and no explicit `--topic-title` provided, the auto-title is computed as: split slug on `-`, join with space, capitalize first word only. `"open-questions"` → `"Open questions"`. Caller can override with explicit `--topic-title`.

### D14 — Obsidian "exclude from graph" reality check

Data-model designer flagged: Obsidian does NOT honor a `exclude: true` frontmatter field natively. The actual exclusion mechanism is filename `_` prefix (which `_convention.md` already has) PLUS adding the path to Obsidian's "Excluded files" setting via the app's UI.

Plan: keep `type: convention` in the seeded `_convention.md` frontmatter as an agent-readable hint (so future tools can filter). Add a one-line note in `templates/wiki-conventions.md` telling adopters to add `**/_convention.md` to Obsidian's Settings → Files & Links → Excluded files setting manually. NOT install.sh's job to mutate Obsidian's settings file (out of scope per V2 spec).

## Implementation Tasks

| # | Task | Depends On | Size | Parallel? | Notes |
|---|------|-----------|------|-----------|-------|
| T1 | Write `templates/wiki-conventions.md` (human-readable doc; codifies slug + layout + frontmatter from spec verbatim) | — | S | Wave 1 | Documentation only; no executable rules |
| T2 | Write `scripts/_replace_sentinel_block.py` (atomic sentinel-block replacement; standalone file per heredoc-stdin memory) | — | S | Wave 1 | Used by install.sh for ~/CLAUDE.md injection |
| T3 | Write `scripts/wiki-write.py` core (UNICODE_DASHES const, SLUG_VALID const, slugify(), 7 exception classes, write_page() seam, frontmatter emission via json.dumps with FIELD_ORDER constants) | — | M | Wave 1 | The biggest single file; ~200 LoC |
| T4 | Write `tests/test-wiki-write.sh` initial cases — slugify fixtures (8 from spec) + 4 exception classes + frontmatter shape per category + atomic-write fault injection | — | M | Wave 1 | Mirrors T3; ~150 LoC bash |
| T5 | Add `--lint` mode to wiki-write.py (4 violation types per D6; output format per AC #6) | T3 | S | Wave 2 | Pure addition; doesn't touch default-write |
| T6 | Add `--write-conventions <vault>` mode to wiki-write.py (emits the 3 _convention.md files from Python string constants) | T3 | S | Wave 2 | Used by install.sh in T9 |
| T7 | Wire `tests/test-wiki-write.sh` into `tests/run-tests.sh` TESTS array | T4 | XS | Wave 2 | Named task — orchestrator-wiring-gap prevention |
| T8 | Add lint + write-conventions test cases to test-wiki-write.sh | T5, T6 | S | Wave 2 | Covers AC #6 + the new --write-conventions surface |
| T9 | Modify `install.sh`: add `_prune_old_backups`, `_install_vault_conventions`, `_install_claude_md_block`, wire into `do_knowledge_layer` Zone B per D9 | T2, T6 | M | Wave 3 | Most touched lines in any single file |
| T10 | Modify `commands/wrap.md` Phase 2c: add Step 3b that invokes `wiki-write.py --lint` and surfaces violations in /wrap output | T5 | S | Wave 3 | Single-section addition |
| T11 | Add install + wrap test cases to test-wiki-write.sh (sentinel-block idempotency, backup pruning, vault-absent paths) | T9, T10 | S | Wave 3 | Closes AC #7 + AC #9 testing |
| T12 | Run `bash tests/run-tests.sh` end-to-end; fix any failures | T11 | S | Wave 4 | Verification gate; fixes back-propagate to whichever wave introduced the bug |
| T13 | Update CHANGELOG.md with v0.16.0 entry; bump VERSION file | T12 | XS | Wave 4 | Release pre-cursor; PR description references this |

**Wave summary:**
- Wave 1 (4 tasks, parallel): T1, T2, T3, T4
- Wave 2 (4 tasks, parallel): T5, T6, T7, T8
- Wave 3 (3 tasks, parallel): T9, T10, T11
- Wave 4 (2 tasks, sequential): T12 → T13

**Estimated total complexity:** 4×S + 1×XS (Wave 1: M+S+M+S) + 4×S (Wave 2) + 1×M+2×S (Wave 3) + 1×S+1×XS (Wave 4) ≈ Medium-feature, single-session build under permissive gate.

## Open Questions

None blocking — all spec contract gaps closed by D1-D14. Two minor items deferred to v2 (not v1 blockers):

- **Multi-mode write (`--mode {create,append-section,update-frontmatter-only,replace-body}`)** — Codex finding #14 from /spec-review. Documented in spec V2 Edge Cases as deferred; v1 uses `--force` overwrite for all overwrite cases. Tracked.
- **AGENTS.md integration for Codex sessions** — Codex finding #7. V2 documents the vault `_convention.md` files as the cross-agent fallback; explicit AGENTS.md writing is a follow-up.

## Risks

1. **install.sh changes are the highest-blast-radius surface.** Modifying `do_knowledge_layer` touches the most-run install path. Mitigation: T9 is a single coherent edit (4 new functions + 1 sequencing change); test cases in T11 cover sentinel-block idempotency + backup-pruning + scaffold-pending interaction.
2. **Test-orchestrator wiring drift.** Memory `test-orchestrator-wiring-gap` documents the recurring pattern where parallel build agents skip `run-tests.sh` updates. T7 names this explicitly; verifier check should fail loudly if `tests/test-wiki-write.sh` exists but doesn't appear in the TESTS array.
3. **YAML emission edge cases.** `json.dumps()` for scalars is correct for JSON-as-YAML-subset, but YAML's quirky scalars (numeric strings like `"123"` being parsed as ints, boolean-like strings `"true"` / `"false"`) need explicit quoting. Mitigation: emit ALL scalars with `json.dumps()` unconditionally; test cases pin titles like `"123"` and `"true"` as fixtures.
4. **Python 3.10+ requirement.** Per project CLAUDE.md, system python3 is 3.9 (too old). Homebrew python3.11 is the working interpreter. Helper's shebang is `#!/usr/bin/env python3`; install.sh should verify python3.10+ is available before invoking `wiki-write.py --write-conventions`. Mitigation: install.sh adds a python3 version check in `_install_vault_conventions`; if too old, surface an actionable error pointing at the Homebrew install path.
5. **`.compact-mode` probe wrote `probe` for this feature** (Phase 0a). End-of-gate banner will emit Path A two-tier `/compact` suggestion at 50%/75% context fill. No action needed; informational.

---

[AUTORUN] Plan approved. Proceeding to /check.
