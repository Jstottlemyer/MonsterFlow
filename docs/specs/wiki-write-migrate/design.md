# Design — wiki-write-migrate

**Date:** 2026-05-16
**Designers dispatched:** api:opus, data-model:sonnet, integration:sonnet + codex-adversary (Phase 2b — new at /blueprint as of 2026-05-16)
**Budget:** 3 Claude + 1 Codex
**Gate mode:** permissive (frontmatter)
**Status:** ready for /check

## Design Decisions

### D1 — CLI: single flat parser, mutually-exclusive group, deferred import (api + integration)

`scripts/wiki-write.py`'s existing argparse parser gains a `migration mode` argument-group. `--dry-run` and `--resume` live in an `add_mutually_exclusive_group()` so argparse natively rejects the combo with the spec's exact phrasing `--dry-run and --resume are mutually exclusive` (override `ArgumentParser.error()` for this one message). `_wiki_migrate` is imported INSIDE the `--migrate` branch only — lint and default-write pay zero startup cost.

### D2 — Module entry: `run(args: argparse.Namespace, vault: pathlib.Path) -> int` (api)

Vanilla Namespace consistent with existing `run_lint` / `run_default_write`. Vault injected from outside for testability (tests can pass a tmp vault path).

### D3 — `MigrationPlan` as frozen dataclass with `invocation_ts` (api)

```python
@dataclass(frozen=True)
class MigrationPlan:
    invocation_ts: str              # YYYYMMDDTHHMMSSZ (CG-2 pinned per-invocation)
    renames: list[RenameOp]
    collisions: list[Collision]
    manual_creates: list[Path]      # type-3b "folder missing index.md"
    link_rewrites: list[LinkRewrite]
    alias_injections: list[AliasInjection]
    vault_index_path: Path          # <vault>/.migration-vault-index.json
    collisions_path: Path           # <vault>/.migration-collisions.json
    journal_path: Path              # <vault>/.migration-journal.jsonl

@dataclass(frozen=True)
class RenameOp:
    old_path: Path; new_path: Path; old_basename: str; new_basename: str

@dataclass(frozen=True)
class Collision:
    source_path: Path; collision_type: str  # slug|target_exists|folder_vs_file
    would_be_target: Path; reason: str; force_overwrite_eligible: bool

@dataclass(frozen=True)
class LinkRewrite:
    source_file: Path; old_text: str; new_text: str; line_no: int

@dataclass(frozen=True)
class AliasInjection:
    target_path: Path; new_aliases: list[str]
```

Nested dataclasses; `__post_init__` validates no path appears in two buckets.

### D4 — Journal as TypedDict, append-only JSONL, fsync per row (data-model + Codex)

```python
class JournalRow(TypedDict):
    schema_version: int             # 1
    phase: str                      # "rename"
    old_path: str; new_path: str
    old_basename: str; new_basename: str
    ts: str                         # ISO-8601 UTC
    status: str                     # "in_flight" | "completed"
```

Emission: `json.dumps(row, sort_keys=True, ensure_ascii=False)` + `\n`. Status updates are NEW appended rows with same `old_path` + new `status` + same `ts` (logically same transaction). Readers take the LATEST row per `old_path` (use `dict[old_path] = row` over append-only walk).

After each `f.write()`: `f.flush()` then `os.fsync(f.fileno())` BEFORE the `os.rename()` call. Survives kernel-buffer crash (Codex F2 correctness).

### D5 — Pre-migration vault index sidecar (data-model + F3)

`<vault>/.migration-vault-index.json` schema:

```json
{
  "schema_version": 1,
  "built_at": "2026-05-16T07:25:31Z",
  "basenames": {
    "welcome": ["projects/Welcome.md"],
    "host-improv-pattern": ["concepts/host-improv-pattern.md"]
  },
  "aliases": {
    "patterncall ios native rewrite": ["projects/PatternCall — iOS Native Rewrite.md"]
  },
  "frontmatter": {
    "projects/Welcome.md": {"title": "Welcome", "aliases": [], "tags": ["project"]}
  }
}
```

Keys in `basenames` and `aliases` are LOWERCASED at write time (Obsidian's resolver is case-insensitive). Values are lists — `len > 1` surfaces ambiguity to the split-brain resolver. `frontmatter` sub-dict is keyed by original-case path; Phase B reads this to preserve existing aliases when injecting new ones (no need to re-read source files).

Written atomically via tempfile + os.replace + fsync. Written BEFORE the advisory lock is acquired (the index is read-only during Phase A+B; no concurrent-write protection needed for the index itself).

### D6 — Collisions sidecar for Phase B split-brain resolver (data-model)

`<vault>/.migration-collisions.json`:

```json
{
  "schema_version": 1,
  "invocation_ts": "20260516T072531Z",
  "collisions": [
    {
      "source_path": "projects/Welcome.md",
      "collision_type": "target_exists",
      "would_be_target": "projects/welcome/index.md",
      "reason": "...",
      "force_overwrite_eligible": true
    }
  ]
}
```

Phase B builds `frozenset(c['source_path'] for c in collisions)` for O(1) membership tests. The split-brain resolver checks if a resolved link target is in this set → flag as ambiguous, don't rewrite.

### D7 — Aliases: canonical slug FIRST, dedup case-insensitive but preserve-input-case (data-model + F1)

```yaml
aliases:
  - "patterncall-ios-native-rewrite"      # canonical slug (position 0 — enables [[slug]] resolution)
  - "PatternCall — iOS Native Rewrite"    # old basename (discoverability via old title)
  - "<any existing aliases>"              # preserved from source frontmatter, appended after
```

Dedup is case-insensitive (first occurrence wins, preserving original case). New entries are appended after existing ones; canonical slug inserted at position 0 if absent. Block-sequence YAML style (not flow-style) for readability in the file.

### D8 — Archive timestamp: compact filename-safe form (data-model + CG-2)

`<vault>/_archives/migration-conflicts/<YYYYMMDDTHHMMSSZ>/<original-relative-path>` — e.g., `_archives/migration-conflicts/20260516T072531Z/projects/welcome/index.md`. Computed ONCE per `--migrate` invocation via `datetime.utcnow().strftime("%Y%m%dT%H%M%SZ")`, stored in `MigrationPlan.invocation_ts`. All collisions in the same run share this timestamp.

### D9 — Lock spans Phase A AND Phase B (Codex)

Helper opens `<vault>/.migration-journal.jsonl` with `os.open(path, os.O_CREAT | os.O_WRONLY | os.O_APPEND, 0o644)` (creates if absent), then `fcntl.flock(fd, LOCK_EX | LOCK_NB)`. Lock held for the ENTIRE migration: Phase A renames, Phase B link rewrites, Phase B verification scan. Released automatically when the fd closes (clean exit OR crash). Second concurrent invocation gets `BlockingIOError`, exits 1.

### D10 — Module structure (api)

```
scripts/_wiki_migrate.py
├── module constants (CATEGORIES, JOURNAL_FILENAME, etc.)
├── dataclasses + TypedDict (MigrationPlan, RenameOp, Collision, LinkRewrite, AliasInjection, JournalRow)
├── run(args, vault) -> int                      # public entry point
├── compute_plan(vault) -> MigrationPlan         # public
├── build_vault_index(vault) -> VaultIndex       # public
├── execute_phase_a(plan, journal_fd) -> None    # public
├── execute_phase_b(plan, journal_fd, vault) -> None  # public
├── resume(journal_path, vault) -> int           # public
├── write_report(vault, plan) -> None            # public
├── resolve_wikilink(old, new, vault_index) -> str
├── resolve_link_target_pre_migration(link, index, collisions) -> LinkResolution
├── archive_collision_target(target, vault, ts) -> Path
├── _open_journal_with_lock(path) -> fd          # internal
├── _append_journal_row(fd, row) -> None
├── _read_journal(path) -> list[JournalRow]
├── _detect_icloud_placeholders(vault) -> list[Path]
└── _slugify import from wiki_write
```

### D11 — Exception classes live in `wiki-write.py` (integration)

`MigrationCollisionError` and `MigrationJournalCorruptError` are added to `wiki-write.py` alongside the existing exception hierarchy. `_wiki_migrate.py` imports them back. One-way dependency: `_wiki_migrate` imports from `wiki-write`, not vice versa at module-load time (deferred-import keeps lint/default-write startup cost zero).

### D12 — Stderr message contract per CG-1

Each of the 6 sub-causes that collapse into CLI exit 1 has a pinned stderr message (V3 AC #2 enumerated them). Override `ArgumentParser.error()` to surface our messages with the right phrasing instead of argparse's defaults.

### D13 — Help text via `epilog=` + `RawDescriptionHelpFormatter` (api)

Long, example-rich `--migrate --help` covering: the two-step UX, all 4 sidecar files (`.migration-journal.jsonl`, `.migration-vault-index.json`, `.migration-collisions.json`, archived `.done` versions), full exit-code table with stderr substrings, `MONSTERFLOW_MIGRATE_STRICT` env var, the `--alias` flag interaction (note: `--alias` on `--migrate` is silently ignored; alias injection is automatic from migration logic).

### D14 — `LinkResolution` enum from api (new structured return)

Api designer proposed: `resolve_link_target_pre_migration` returns a 5-state enum instead of `Optional[Path]`:

```python
@dataclass
class LinkResolution:
    kind: Literal["unique-migrated", "unique-skipped", "unique-unchanged", "ambiguous", "unresolvable"]
    target: Optional[Path]
    candidates: list[Path]  # only populated when kind == "ambiguous"
```

Phase B branches on `kind`: `unique-migrated` → rewrite; `unique-skipped` → flag ambiguous in report; `unique-unchanged` (resolves to a not-being-migrated page) → leave alone; `ambiguous` → flag in report; `unresolvable` (orphan link) → leave alone. Clean correspondence to V3 AC #10's 5 outcomes.

## Implementation Tasks

| # | Task | Depends On | Size | Wave |
|---|------|-----------|------|------|
| T1 | Add `MigrationCollisionError` + `MigrationJournalCorruptError` to `wiki-write.py` | — | XS | W1 |
| T2 | Add `--migrate` / `--dry-run` / `--resume` / `--force-overwrite` / `--alias` flags to `wiki-write.py` argparse + mutex group + stderr contract per CG-1 | — | S | W1 |
| T3 | Add `run_lint()` tail-line: `To preview a fix: python3 ...wiki-write.py --migrate --dry-run` (V3 AC #8) | — | XS | W1 |
| T4 | Add `aliases` field documentation to `templates/wiki-conventions.md` for all 4 category schemas (V3 AC #6) | — | XS | W1 |
| T5 | `scripts/_wiki_migrate.py` core: module constants + dataclasses + `compute_plan` + `build_vault_index` + `resolve_wikilink` + `resolve_link_target_pre_migration` + `archive_collision_target` + `_detect_icloud_placeholders` (~350-450 LoC, Python 3.9-compat, stdlib-only) | T1 | M | W2 |
| T6 | `_wiki_migrate.py` Phase A: `execute_phase_a` + `_open_journal_with_lock` + `_append_journal_row` (journal write with fsync; flock acquired) | T5 | S | W2 |
| T7 | `_wiki_migrate.py` Phase B: `execute_phase_b` (link rewrites + idempotency check + post-run verification) + alias injection + `write_report` (~150 LoC) | T5 | M | W2 |
| T8 | `_wiki_migrate.py` `--resume`: `_read_journal` + `resume(journal_path, vault) -> int` (re-runs Phase A in-flight rows + Phase B from scratch) | T6, T7 | S | W2 |
| T9 | `wiki-write.py` routing: deferred-import + dispatch `_wiki_migrate.run(args, vault)` from the `--migrate` branch | T2, T5-T8 | XS | W3 |
| T10 | `tests/test-wiki-migrate.sh` initial cases — slugify-via-import + plan computation + collision detection (~200 LoC) | T5 | M | W3 |
| T11 | `tests/test-wiki-migrate.sh` Phase A cases — journal write/read + flock contention + fsync atomicity + resume from in-flight (~150 LoC) | T6, T8 | M | W3 |
| T12 | `tests/test-wiki-migrate.sh` Phase B cases — wikilink rewrites + idempotency byte-stability + split-brain + verification + alias injection + force-overwrite archive (~200 LoC) | T7 | M | W3 |
| T13 | Wire `tests/test-wiki-migrate.sh` into `tests/run-tests.sh` TESTS array (named task per memory `test-orchestrator-wiring-gap`) | T10-T12 | XS | W4 |
| T14 | `CHANGELOG.md` `[0.17.0]` entry + remove `wiki-write-migrate` BACKLOG entry + bump `VERSION` to `0.17.0` | T13 | XS | W4 |

**Wave summary:**
- W1 (4 tasks, parallel): T1, T2, T3, T4 — wiki-write.py + template changes
- W2 (4 tasks, mostly sequential with one parallel): T5 first, then T6 + T7 parallel, then T8
- W3 (4 tasks, parallel): T9, T10, T11, T12 — routing + tests
- W4 (2 tasks, sequential): T13, T14

**Estimated total:** ~900-1100 LoC across `_wiki_migrate.py` + tests. Within single-build-session budget (per memory `slice-strategy-for-autorun-build`, the threshold is ≤300 spec lines + ≤200 LoC per slice; this is bigger, but the wave structure carves it correctly).

## Open Questions

None — all V3 architectural pins resolved during design. Open questions surfaced by api designer (invocation timestamp format, `LinkResolution` return type, `--alias` + `--migrate` interaction) are resolved here:

- Invocation timestamp: `YYYYMMDDTHHMMSSZ` compact form (D8 — data-model designer's call)
- `LinkResolution`: 5-state enum-dataclass (D14)
- `--alias` + `--migrate`: silently ignored (alias injection is migration logic's job, not the user's per-call decision)

## Risks

1. **`_wiki_migrate.py` reaches ~500 LoC** — biggest single file in the v0.17.0 build. Mitigation: clear module structure (D10) keeps it navigable; Phase A and Phase B logic separated.
2. **Vault-index sidecar is a NEW disk artifact** — `<vault>/.migration-vault-index.json` adds to the vault during migration. Mitigation: archived alongside journal on completion; user can `rm .migration-*.done` files at their leisure.
3. **`fcntl.flock` doesn't work on Windows** — Python 3.9 stdlib `fcntl` is Unix-only. Mitigation: MonsterFlow is macOS-only per project CLAUDE.md; not a v1 concern. Document.
4. **The lock spans Phase A AND Phase B** — for a slow Phase B (many pages, many refs), this could hold the lock for minutes. Mitigation: lock contention message is informational only ("wait for completion"); single-user vault assumption means this isn't a real-world race. Documented.
5. **Codex at /blueprint now runs** — added Phase 2b to skill in this commit. Skill change is BUNDLED with this PR for atomic ship.

## Codex Adversarial View

[To be filled by Phase 2b run on this freshly-written design.md — Codex now runs at /blueprint per the skill change in this commit.]

---

[AUTORUN + /goal] Design synthesized. Phase 2b (Codex on design.md) running next, then /check.
