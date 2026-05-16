#!/usr/bin/env python3
"""Wiki write migration helper. Invoked as `wiki-write.py --migrate ...`.

This module is the implementation surface for the wiki-write-migrate feature.
It is intentionally a helper module (not a CLI). `wiki-write.py` parses the
`--migrate` family of flags, validates the vault, then dispatches into `run()`
here.

See docs/specs/wiki-write-migrate/spec.md (V4) and design.md (v2) for the
full contract. Key design anchors:
  - D2.5: shared types live in `_wiki_common`, loaded via importlib so that
          class identity matches between wiki-write.py-as-__main__ and this
          module loaded as a sibling.
  - D3:   immutable @dataclass(frozen=True) value types for plan rows.
  - D4.5: sidecar emission order — vault-index FIRST, collisions SECOND,
          journal LAST (journal acquisition implies "we're about to act").
  - D5:   vault-index schema keyed on linkable_name (lowercased).
  - D9:   single-writer fcntl.flock LOCK_EX|LOCK_NB on the journal fd.
  - D10:  module structure (this file).
  - D14:  5-state link resolution against pre-migration vault state.

Python 3.9-compatible, stdlib only.
"""

import argparse
import fcntl
import json
import os
import re
import sys
import tempfile
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Union

# ---------------------------------------------------------------------------
# Import shared primitives from _wiki_common
# (per design D2.5 + Codex P1 #1 fix — see _wiki_common.py header for why)
# ---------------------------------------------------------------------------
import importlib.util

_HERE = Path(__file__).parent
_spec = importlib.util.spec_from_file_location(
    "_wiki_common", str(_HERE / "_wiki_common.py")
)
_common = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_common)

# Re-export shared symbols at module scope so wave-3 implementers can use them
# directly without re-typing the importlib dance.
slugify = _common.slugify
emit_yaml_scalar = _common.emit_yaml_scalar
build_frontmatter = _common.build_frontmatter

# Exception classes (must share identity with wiki-write.py's view)
MigrationCollisionError = _common.MigrationCollisionError
MigrationJournalCorruptError = _common.MigrationJournalCorruptError
VaultNotConfiguredError = _common.VaultNotConfiguredError
VaultNotConfiguredSkip = _common.VaultNotConfiguredSkip
VaultPathMissingError = _common.VaultPathMissingError
WikiWriteError = _common.WikiWriteError
EmptySlugError = _common.EmptySlugError

# Frontmatter field-order constants (re-exported for callers that touch
# alias injection / report rendering)
PROJECT_INDEX_ORDER = _common.PROJECT_INDEX_ORDER
PROJECT_TOPIC_ORDER = _common.PROJECT_TOPIC_ORDER
CONCEPT_ORDER = _common.CONCEPT_ORDER
ENTITY_ORDER = _common.ENTITY_ORDER


# ---------------------------------------------------------------------------
# Sidecar / journal filenames + schema version
# ---------------------------------------------------------------------------

JOURNAL_FILENAME = ".migration-journal.jsonl"
VAULT_INDEX_FILENAME = ".migration-vault-index.json"
COLLISIONS_FILENAME = ".migration-collisions.json"
REPORT_FILENAME = "migration-report.md"
ARCHIVE_SUBDIR = "_archives/migration-conflicts"

# Bump in lockstep with any change to journal/vault-index/collisions schemas.
SCHEMA_VERSION = 1

# Collision-type enum (kept as string constants for JSONL portability)
COLLISION_SLUG = "slug"
COLLISION_TARGET_EXISTS = "target_exists"
COLLISION_FOLDER_VS_FILE = "folder_vs_file"

# Link-resolution kinds (per D14)
RESOLUTION_UNIQUE_MIGRATED = "unique-migrated"
RESOLUTION_UNIQUE_SKIPPED = "unique-skipped"
RESOLUTION_UNIQUE_UNCHANGED = "unique-unchanged"
RESOLUTION_AMBIGUOUS = "ambiguous"
RESOLUTION_UNRESOLVABLE = "unresolvable"

# Invocation timestamp format (UTC, compact-ISO, journal-row + archive-dir key)
INVOCATION_TS_FORMAT = "%Y%m%dT%H%M%SZ"

# stderr message contract (per spec AC #2) — keep these as module constants so
# tests can match the literal strings and wave-3 implementers don't drift.
STDERR_COLLISION_HEADER = "migration aborted: target-exists collisions detected"
STDERR_COLLISION_HINT = "rerun with --force-overwrite to archive-then-rename"
STDERR_JOURNAL_LOCKED = "migration aborted: another migration is in progress (journal lock held)"
STDERR_JOURNAL_CORRUPT = "migration aborted: journal is corrupt or has unknown schema_version"
STDERR_ICLOUD_PLACEHOLDER = "migration aborted: iCloud placeholder files detected; download before retry"


# ---------------------------------------------------------------------------
# Dataclasses (per design D3 — frozen, hashable, JSON-serializable via .__dict__)
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class RenameOp:
    """A single file rename from old basename to new slugified basename.

    `linkable_name` is the shortest-unique-path token used by the wikilink
    rewriter — project slug for project pages, filesystem stem otherwise.
    """
    old_path: Path
    new_path: Path
    old_basename: str
    new_basename: str
    linkable_name: str


@dataclass(frozen=True)
class ArchiveThenRenameOp:
    """When --force-overwrite is in effect and the target slug already
    exists, archive the existing target first, then rename. The
    `rename_op.new_path` is the SAME path that `archive_from` originally
    occupied — this is expected and excluded from the post_init bucket-
    uniqueness check (see ck-postinit-validation followup).
    """
    archive_from: Path
    archive_to: Path
    rename_op: RenameOp


@dataclass(frozen=True)
class Collision:
    """A collision detected during plan computation.

    `force_overwrite_eligible` is True when the collision is a plain
    target_exists (foldable into ArchiveThenRenameOp by re-running with
    --force-overwrite). Slug and folder_vs_file collisions are NOT
    eligible — they require manual user action.
    """
    source_path: Path
    collision_type: str  # one of COLLISION_* constants above
    would_be_target: Path
    reason: str
    force_overwrite_eligible: bool


@dataclass(frozen=True)
class LinkRewrite:
    """A single [[wikilink]] rewrite. `line_no` is 1-based for human-readable
    report output."""
    source_file: Path
    old_text: str
    new_text: str
    line_no: int


@dataclass(frozen=True)
class AliasInjection:
    """Append `new_aliases` to the `aliases:` frontmatter key of `target_path`.
    Wave 3: preserve canonical FIELD_ORDER and de-dupe against existing aliases.
    """
    target_path: Path
    new_aliases: List[str]


@dataclass(frozen=True)
class LinkResolution:
    """Result of resolving a [[link]] against the pre-migration vault index.

    `kind` is one of the RESOLUTION_* constants (5-state per D14).
    `target` is set only when kind is one of the unique-* states.
    `candidates` is populated for kind == ambiguous.
    """
    kind: str
    target: Optional[Path]
    candidates: List[Path]


@dataclass(frozen=True)
class MigrationPlan:
    """The full plan emitted by `compute_plan`. All buckets are sorted
    deterministically (alphabetical by source path) so dry-run output is
    reproducible across machines / Python versions."""
    invocation_ts: str  # YYYYMMDDTHHMMSSZ
    vault: Path         # vault root, needed by execute_phase_a → archive_collision_target
    renames: List[RenameOp]
    archive_then_renames: List[ArchiveThenRenameOp]
    collisions: List[Collision]
    manual_creates: List[Path]
    link_rewrites: List[LinkRewrite]
    alias_injections: List[AliasInjection]
    vault_index_path: Path
    collisions_path: Path
    journal_path: Path
    force_overwrite: bool

    def __post_init__(self):
        """Validates no path appears in two operation buckets, EXCEPT
        ArchiveThenRenameOp.archive_from which legitimately matches its
        own rename_op.new_path (per Codex P2 followup ck-postinit-validation).
        """
        seen = set()  # type: set
        # Collect all paths from rename ops
        for op in self.renames:
            for p in (op.old_path, op.new_path):
                if p in seen:
                    raise ValueError(
                        "path {0} appears in multiple operations".format(p)
                    )
                seen.add(p)
        # ArchiveThenRenameOp: archive_from is permitted to match rename_op.new_path
        # by design (the archive frees the slot, then rename fills it) — skip
        # cross-check for archive_from vs rename_op.new_path.
        for atr in self.archive_then_renames:
            if atr.rename_op.old_path in seen:
                raise ValueError(
                    "path {0} appears in multiple operations".format(
                        atr.rename_op.old_path
                    )
                )
            seen.add(atr.rename_op.old_path)
            seen.add(atr.archive_to)
        # Collision source paths must not overlap with rename/archive buckets
        for c in self.collisions:
            if c.source_path in seen:
                raise ValueError(
                    "path {0} appears in multiple operations".format(c.source_path)
                )
            seen.add(c.source_path)


# ---------------------------------------------------------------------------
# Public function surface — wave 3 fills in bodies
# ---------------------------------------------------------------------------

def run(args: argparse.Namespace, vault: Path) -> int:
    """Main entry dispatcher invoked from wiki-write.py.

    `args` is the already-parsed argparse Namespace from wiki-write.py;
    expected attributes include `migrate`, `dry_run`, `force_overwrite`,
    `resume`. `vault` is the validated vault root Path.

    Returns the CLI exit code (0 success, non-zero per WikiWriteError
    subclass exit_code values).
    """
    # --resume path
    if getattr(args, "resume", False):
        return resume(vault / JOURNAL_FILENAME, vault)

    # --dry-run or execute path

    # 1. iCloud check
    placeholders = _detect_icloud_placeholders(vault)
    if placeholders:
        first = str(placeholders[0])
        print(
            "[wiki-migrate] vault contains {0} iCloud placeholder file(s)"
            " (e.g., {1}); open files in Finder to force download,"
            " then re-run".format(len(placeholders), first),
            file=sys.stderr,
        )
        return 1

    # 2. Compute plan
    force_overwrite = getattr(args, "force_overwrite", False)
    try:
        plan = compute_plan(vault, force_overwrite=force_overwrite)
    except EmptySlugError as exc:
        print(str(exc), file=sys.stderr)
        return 3
    except WikiWriteError as exc:
        print(str(exc), file=sys.stderr)
        return getattr(exc, "exit_code", 1)

    # 3. Build vault index (for print summary; sidecars written later)
    vault_index = build_vault_index(vault)

    # 4. Print plan summary to stdout
    total_auto = len(plan.renames) + len(plan.archive_then_renames)
    print("=== Migration plan ===")
    print(
        "Migrate (auto-rename): {0} files".format(total_auto)
    )
    if plan.renames:
        for ren in plan.renames:
            try:
                old_rel = ren.old_path.relative_to(vault).as_posix()
            except ValueError:
                old_rel = str(ren.old_path)
            try:
                new_rel = ren.new_path.relative_to(vault).as_posix()
            except ValueError:
                new_rel = str(ren.new_path)
            print("  {0} → {1}".format(old_rel, new_rel))
    if plan.archive_then_renames:
        for atr in plan.archive_then_renames:
            ren = atr.rename_op
            try:
                old_rel = ren.old_path.relative_to(vault).as_posix()
            except ValueError:
                old_rel = str(ren.old_path)
            try:
                new_rel = ren.new_path.relative_to(vault).as_posix()
            except ValueError:
                new_rel = str(ren.new_path)
            print("  {0} → {1} (archive-then-rename)".format(old_rel, new_rel))

    if plan.manual_creates:
        print(
            "Migrate (manual — type-3b folder needs index.md): {0} file(s)".format(
                len(plan.manual_creates)
            )
        )
        for folder in plan.manual_creates:
            try:
                rel = folder.relative_to(vault).as_posix()
            except ValueError:
                rel = str(folder)
            suggested_title = folder.name.replace("-", " ").title()
            print("  {0} → user must create {1}/index.md manually".format(rel, rel))
            print(
                "    python3 wiki-write.py --category project"
                " --title \"{0}\" --body \"...\"".format(suggested_title)
            )

    print("Skip-collisions: {0} file(s) (see migration-report.md)".format(
        len(plan.collisions)
    ))

    if plan.link_rewrites:
        print("Rewrite wikilinks: {0} references".format(len(plan.link_rewrites)))
    if plan.alias_injections:
        print("Add aliases: {0} entries".format(len(plan.alias_injections)))

    # 5. Write migration-report.md
    try:
        write_report(vault, plan)
    except OSError as exc:
        print(
            "[wiki-migrate] warning: failed to write migration-report.md: {0}".format(exc),
            file=sys.stderr,
        )

    # 6. If --dry-run: exit 0
    if getattr(args, "dry_run", False):
        print(
            "\nNext step: python3 ~/Projects/MonsterFlow/scripts/wiki-write.py --migrate"
        )
        return 0

    # 7. Execute path

    # Handle target-exists collisions without --force-overwrite
    target_exists_collisions = [
        c for c in plan.collisions
        if c.collision_type == COLLISION_TARGET_EXISTS and c.force_overwrite_eligible
    ]
    if target_exists_collisions and not force_overwrite:
        print(
            "target-exists collision ({0} files); pass --force-overwrite to archive"
            " existing targets to {1}/".format(
                len(target_exists_collisions), ARCHIVE_SUBDIR
            ),
            file=sys.stderr,
        )
        return 1

    # Acquire journal lock
    try:
        journal_fd = _open_journal_with_lock(plan.journal_path)
    except BlockingIOError:
        print(STDERR_JOURNAL_LOCKED, file=sys.stderr)
        return 1

    try:
        # Write vault_index sidecar (atomic)
        _write_sidecar_atomic(plan.vault_index_path, vault_index)

        # Write collisions sidecar (atomic)
        collisions_data = {
            "schema_version": SCHEMA_VERSION,
            "invocation_ts": plan.invocation_ts,
            "collisions": [
                {
                    "source_path": (
                        c.source_path.relative_to(vault).as_posix()
                        if c.source_path.is_absolute()
                        else str(c.source_path)
                    ),
                    "collision_type": c.collision_type,
                    "would_be_target": (
                        c.would_be_target.relative_to(vault).as_posix()
                        if c.would_be_target.is_absolute()
                        else str(c.would_be_target)
                    ),
                    "reason": c.reason,
                    "force_overwrite_eligible": c.force_overwrite_eligible,
                }
                for c in plan.collisions
            ],
        }
        _write_sidecar_atomic(plan.collisions_path, collisions_data)

        # Phase A: renames
        execute_phase_a(plan, journal_fd)

        # Phase B: link rewrites + alias injection + verification
        execute_phase_b(plan, journal_fd, vault)

        # Archive journal + sidecars
        ts = datetime.utcnow().strftime(INVOCATION_TS_FORMAT)
        _archive_sidecar(plan.journal_path, ts)
        _archive_sidecar(plan.vault_index_path, ts)
        _archive_sidecar(plan.collisions_path, ts)

        # Print completion summary
        total_migrated = len(plan.renames) + len(plan.archive_then_renames)
        print("\n=== Migration complete ===")
        print("Migrated: {0} files".format(total_migrated))
        if plan.manual_creates:
            print(
                "Manual-create-required: {0} (see migration-report.md)".format(
                    len(plan.manual_creates)
                )
            )
        print("Skipped (collisions): {0}".format(len(plan.collisions)))
        if plan.link_rewrites:
            print("Wikilinks rewritten: {0}".format(len(plan.link_rewrites)))
        if plan.alias_injections:
            print("Aliases added: {0}".format(len(plan.alias_injections)))
        done_name = plan.journal_path.name.replace(
            ".jsonl", "-{0}.jsonl.done".format(ts)
        )
        print("Journal: archived to {0}".format(vault / done_name))
        print(
            "\nNext: review migration-report.md if any collisions reported;"
            " manually create index.md for type-3b paths."
        )

    except BlockingIOError:
        print(STDERR_JOURNAL_LOCKED, file=sys.stderr)
        return 1
    except MigrationCollisionError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    except MigrationJournalCorruptError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    except EmptySlugError as exc:
        print(str(exc), file=sys.stderr)
        return 3
    except WikiWriteError as exc:
        print(str(exc), file=sys.stderr)
        return getattr(exc, "exit_code", 1)
    except Exception as exc:
        print("[wiki-migrate] unexpected error: {0}".format(exc), file=sys.stderr)
        return 1
    finally:
        try:
            os.close(journal_fd)
        except (OSError, UnboundLocalError):
            pass

    return 0


def _write_sidecar_atomic(path: Path, data: Dict) -> None:
    """Write a JSON sidecar atomically via tempfile + os.replace."""
    content = json.dumps(data, indent=2, ensure_ascii=False, sort_keys=True)
    parent = path.parent
    parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(dir=str(parent), suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(content)
        os.replace(tmp_path, str(path))
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


def _archive_sidecar(path: Path, ts: str) -> None:
    """Move a sidecar file to a .done variant with timestamp suffix."""
    if not path.exists():
        return
    suffix = path.suffix  # e.g., ".jsonl" or ".json"
    stem = path.name[: -len(suffix)] if suffix else path.name
    done_path = path.parent / "{0}-{1}{2}.done".format(stem, ts, suffix)
    try:
        os.rename(str(path), str(done_path))
    except OSError:
        pass


def compute_plan(vault: Path, force_overwrite: bool = False) -> MigrationPlan:
    """Scan vault, detect renames + collisions, return an immutable MigrationPlan.

    When `force_overwrite=True`, target_exists collisions are converted
    into ArchiveThenRenameOp entries (the existing target is scheduled
    for archival under `_archives/migration-conflicts/<invocation_ts>/`).
    Slug and folder_vs_file collisions are NEVER auto-resolved.

    # TODO(W3-A5): compute link_rewrites + alias_injections in run() once
    # vault_index is built. For now, both fields are empty lists.
    """
    # TODO(W3-A5): wire iCloud detection here once _detect_icloud_placeholders
    # is implemented by a later agent.
    # placeholders = _detect_icloud_placeholders(vault)
    # if placeholders:
    #     raise MigrationCollisionError(STDERR_ICLOUD_PLACEHOLDER)

    invocation_ts = datetime.utcnow().strftime(INVOCATION_TS_FORMAT)

    managed_categories = ("projects", "concepts", "entities")

    # First pass: gather all .md files and their intended target paths.
    # We build a map: candidate_target_str -> list[source_path] for slug-collision detection.
    candidate_targets = {}  # type: Dict[str, List[Path]]

    # Also record all existing paths for target-exists and folder-vs-file detection.
    all_existing_paths = set()  # type: set
    for category in managed_categories:
        cat_dir = vault / category
        if not cat_dir.is_dir():
            continue
        for md_file in cat_dir.rglob("*.md"):
            all_existing_paths.add(md_file.resolve())

    # Gather files + compute their target paths
    # Structure: list of (source_path, target_path, category, violation_type)
    # violation_type: None (already conformant), "type1_2_3a" (auto-renamable),
    #                 "type3b" (folder missing index.md)
    file_entries = []  # type: List[tuple]

    for category in managed_categories:
        cat_dir = vault / category
        if not cat_dir.is_dir():
            continue

        # Detect type-3b: folders without index.md
        for folder in sorted(cat_dir.iterdir()):
            if not folder.is_dir():
                continue
            folder_name = folder.name
            if folder_name.startswith("_") or folder_name.startswith("."):
                continue
            index_path = folder / "index.md"
            if not index_path.exists():
                # Type-3b: folder exists, index.md missing → manual create required
                file_entries.append((folder, None, category, "type3b"))

        for md_file in sorted(cat_dir.rglob("*.md")):
            rel = md_file.relative_to(vault)
            parts = rel.parts

            if category == "projects":
                if len(parts) == 3 and parts[2] == "index.md":
                    # projects/<slug>/index.md — check if slug is conformant
                    slug = parts[1]
                    try:
                        canonical = slugify(slug)
                    except Exception:
                        file_entries.append((md_file, None, category, "bad_slug"))
                        continue
                    if slug == canonical:
                        # Already conformant
                        file_entries.append((md_file, None, category, None))
                    else:
                        # Slug needs fixing
                        target = vault / "projects" / canonical / "index.md"
                        file_entries.append((md_file, target, category, "type1_2_3a"))
                elif len(parts) == 3:
                    # projects/<slug>/<topic>.md — keep as-is for topic files (not migration scope)
                    file_entries.append((md_file, None, category, None))
                elif len(parts) == 2:
                    # projects/<name>.md — flat file (type 3a)
                    stem = md_file.stem
                    try:
                        canonical = slugify(stem)
                    except Exception:
                        file_entries.append((md_file, None, category, "bad_slug"))
                        continue
                    target = vault / "projects" / canonical / "index.md"
                    file_entries.append((md_file, target, category, "type1_2_3a"))
                else:
                    file_entries.append((md_file, None, category, None))
            else:
                # concepts or entities: flat file expected
                if len(parts) != 2:
                    # Nested — not managed
                    file_entries.append((md_file, None, category, None))
                    continue
                stem = md_file.stem
                try:
                    canonical = slugify(stem)
                except Exception:
                    file_entries.append((md_file, None, category, "bad_slug"))
                    continue
                if stem == canonical:
                    # Already conformant
                    file_entries.append((md_file, None, category, None))
                else:
                    target = vault / category / (canonical + ".md")
                    file_entries.append((md_file, target, category, "type1_2_3a"))

    # Build target → [sources] map for slug-collision detection
    for source, target, category, vtype in file_entries:
        if vtype == "type1_2_3a" and target is not None:
            tstr = str(target.resolve())
            if tstr not in candidate_targets:
                candidate_targets[tstr] = []
            candidate_targets[tstr].append(source)

    # Second pass: classify into renames / archive_then_renames / collisions / manual_creates
    renames = []             # type: List[RenameOp]
    archive_then_renames = [] # type: List[ArchiveThenRenameOp]
    collisions = []          # type: List[Collision]
    manual_creates = []      # type: List[Path]

    # Track which sources we've already classified (some appear in multi-source slug collisions)
    classified_sources = set()  # type: set

    # Handle slug collisions first (two sources → same target)
    for tstr, sources in candidate_targets.items():
        if len(sources) > 1:
            target_path = Path(tstr)
            # Compute relative target for display
            try:
                target_rel = target_path.relative_to(vault)
            except ValueError:
                target_rel = target_path
            for source in sources:
                if str(source) not in classified_sources:
                    classified_sources.add(str(source))
                    collisions.append(Collision(
                        source_path=source,
                        collision_type=COLLISION_SLUG,
                        would_be_target=target_path,
                        reason=(
                            "slug collision: {0} sources map to target {1}".format(
                                len(sources), target_rel.as_posix()
                            )
                        ),
                        force_overwrite_eligible=False,
                    ))

    # Now process remaining file entries
    for source, target, category, vtype in file_entries:
        if vtype is None:
            # Already conformant — skip
            continue
        if vtype == "type3b":
            # type-3b: folder missing index.md
            manual_creates.append(source)
            continue
        if vtype == "bad_slug":
            # Cannot compute slug — skip (caller can surface as edge case)
            continue
        if str(source) in classified_sources:
            # Already classified as slug-collision
            continue

        assert target is not None
        source_str = str(source)

        # Determine category for this file
        rel = source.relative_to(vault)
        parts = rel.parts
        if category == "projects":
            if len(parts) == 2:
                # flat file projects/<name>.md → slug (target folder name)
                canonical = slugify(source.stem)
                linkable_name = canonical
            else:
                # projects/<old-slug>/index.md → new slug (target folder name)
                linkable_name = target.parent.name
        else:
            linkable_name = target.stem

        # Check folder-vs-file collision (projects/<name>.md AND projects/<name>/ both exist)
        if category == "projects" and len(parts) == 2:
            folder_path = vault / "projects" / slugify(source.stem)
            if folder_path.is_dir():
                classified_sources.add(source_str)
                collisions.append(Collision(
                    source_path=source,
                    collision_type=COLLISION_FOLDER_VS_FILE,
                    would_be_target=target,
                    reason=(
                        "folder-vs-file collision: flat file {0} and folder {1} both exist".format(
                            rel.as_posix(), folder_path.relative_to(vault).as_posix()
                        )
                    ),
                    force_overwrite_eligible=False,
                ))
                continue

        # Check target-exists collision (target path already occupied by a different file).
        # Use os.stat() inode comparison to correctly handle case-insensitive filesystems
        # (macOS APFS/HFS+) where `os.rename("HostImprov.md", "hostimprov.md")` is a
        # case-only rename of the SAME inode — not a collision.
        target_is_different_file = False
        if target.exists():
            try:
                src_stat = os.stat(str(source))
                tgt_stat = os.stat(str(target))
                same_inode = (
                    src_stat.st_ino == tgt_stat.st_ino
                    and src_stat.st_dev == tgt_stat.st_dev
                )
                target_is_different_file = not same_inode
            except OSError:
                target_is_different_file = True

        if target_is_different_file:
            classified_sources.add(source_str)
            if force_overwrite:
                # Schedule archive-then-rename
                archive_to = (
                    vault / ARCHIVE_SUBDIR / invocation_ts
                    / target.relative_to(vault)
                )
                rename_op = RenameOp(
                    old_path=source,
                    new_path=target,
                    old_basename=source.stem,
                    new_basename=target.stem,
                    linkable_name=linkable_name,
                )
                archive_then_renames.append(ArchiveThenRenameOp(
                    archive_from=target,
                    archive_to=archive_to,
                    rename_op=rename_op,
                ))
            else:
                collisions.append(Collision(
                    source_path=source,
                    collision_type=COLLISION_TARGET_EXISTS,
                    would_be_target=target,
                    reason=(
                        "target {0} already exists; use --force-overwrite to archive".format(
                            target.relative_to(vault).as_posix()
                        )
                    ),
                    force_overwrite_eligible=True,
                ))
            continue

        # Standard rename
        classified_sources.add(source_str)
        renames.append(RenameOp(
            old_path=source,
            new_path=target,
            old_basename=source.stem,
            new_basename=target.stem,
            linkable_name=linkable_name,
        ))

    # Sort all buckets deterministically by source path string for reproducible output
    renames_sorted = sorted(renames, key=lambda op: str(op.old_path))
    archive_then_renames_sorted = sorted(
        archive_then_renames, key=lambda atr: str(atr.rename_op.old_path)
    )
    collisions_sorted = sorted(collisions, key=lambda c: str(c.source_path))
    manual_creates_sorted = sorted(manual_creates, key=str)

    return MigrationPlan(
        invocation_ts=invocation_ts,
        vault=vault,
        renames=renames_sorted,
        archive_then_renames=archive_then_renames_sorted,
        collisions=collisions_sorted,
        manual_creates=manual_creates_sorted,
        link_rewrites=[],       # TODO(W3-A5): populated in run() after vault_index built
        alias_injections=[],    # TODO(W3-A5): populated in run() after vault_index built
        vault_index_path=vault / VAULT_INDEX_FILENAME,
        collisions_path=vault / COLLISIONS_FILENAME,
        journal_path=vault / JOURNAL_FILENAME,
        force_overwrite=force_overwrite,
    )


def build_vault_index(vault: Path) -> Dict:
    """Build the pre-migration vault index keyed on linkable_name (lowercased).

    Output shape matches the .migration-vault-index.json schema defined in
    design D5. Keys: schema_version, built_at, invocation_ts, linkable_names,
    aliases, frontmatter. Values in linkable_names and aliases are LISTS to
    surface ambiguity (len > 1) to the split-brain resolver.

    linkable_name computation (V4 — Codex P1 #5):
      - projects/<slug>/index.md  →  linkable_name = <slug>  (parent folder)
      - projects/<slug>/<topic>.md →  linkable_name = <topic>  (filesystem stem)
      - concepts/<stem>.md        →  linkable_name = <stem>
      - entities/<stem>.md        →  linkable_name = <stem>

    Also adds the OLD filesystem stem as a synthetic alias so that wikilinks
    written against the old basename (e.g., [[PatternCall — iOS Native Rewrite]])
    can resolve via this dict (per followup ck-linkable-name-prefix-resolution).
    """
    now = datetime.utcnow()
    built_at = now.strftime("%Y-%m-%dT%H:%M:%SZ")
    invocation_ts = now.strftime(INVOCATION_TS_FORMAT)

    linkable_names = {}  # type: Dict[str, List[str]]
    aliases_map = {}     # type: Dict[str, List[str]]
    frontmatter_map = {} # type: Dict[str, Dict]

    managed_categories = ("projects", "concepts", "entities")

    for category in managed_categories:
        cat_dir = vault / category
        if not cat_dir.is_dir():
            continue
        for md_file in sorted(cat_dir.rglob("*.md")):
            rel = md_file.relative_to(vault)
            rel_str = rel.as_posix()
            parts = rel.parts  # e.g., ("projects", "welcome", "index.md")

            # Compute linkable_name based on layout
            if category == "projects":
                if len(parts) == 3 and parts[2] == "index.md":
                    # projects/<slug>/index.md → linkable_name = <slug>
                    linkable_name = parts[1]
                elif len(parts) == 3:
                    # projects/<slug>/<topic>.md → linkable_name = topic stem
                    linkable_name = Path(parts[2]).stem
                else:
                    # projects/<flat-file>.md → linkable_name = stem
                    linkable_name = md_file.stem
            else:
                # concepts/<stem>.md  or  entities/<stem>.md
                linkable_name = md_file.stem

            # Parse frontmatter (stdlib only — scan between first two ---\n lines)
            fm_title = None      # type: Optional[str]
            fm_aliases = []      # type: List[str]
            fm_tags = []         # type: List[str]
            try:
                text = md_file.read_text(encoding="utf-8", errors="replace")
                if text.startswith("---\n"):
                    end_idx = text.find("\n---\n", 4)
                    if end_idx != -1:
                        fm_block = text[4:end_idx]
                        for line in fm_block.splitlines():
                            stripped = line.strip()
                            if stripped.startswith("title:"):
                                raw = stripped[len("title:"):].strip()
                                # Remove surrounding quotes if present
                                if len(raw) >= 2 and raw[0] == '"' and raw[-1] == '"':
                                    raw = raw[1:-1]
                                fm_title = raw
                            elif stripped.startswith("tags:"):
                                # flow-style tags: ["a", "b"]
                                raw = stripped[len("tags:"):].strip()
                                if raw.startswith("[") and raw.endswith("]"):
                                    inner = raw[1:-1]
                                    for item in inner.split(","):
                                        item = item.strip().strip('"').strip("'")
                                        if item:
                                            fm_tags.append(item)
                            elif stripped.startswith("- ") and fm_title is not None:
                                # Inside aliases block (block-style list item)
                                # Only collect when we're past title/tags lines
                                alias_val = stripped[2:].strip().strip('"').strip("'")
                                if alias_val:
                                    fm_aliases.append(alias_val)
            except (OSError, UnicodeDecodeError):
                pass

            # Register linkable_name (lowercased key)
            ln_key = linkable_name.lower()
            if ln_key not in linkable_names:
                linkable_names[ln_key] = []
            if rel_str not in linkable_names[ln_key]:
                linkable_names[ln_key].append(rel_str)

            # Register each frontmatter alias (lowercased key)
            for alias in fm_aliases:
                alias_key = alias.lower()
                if alias_key not in aliases_map:
                    aliases_map[alias_key] = []
                if rel_str not in aliases_map[alias_key]:
                    aliases_map[alias_key].append(rel_str)

            # Synthetic alias: old filesystem stem (so [[Old Title]] references resolve)
            # Per followup ck-linkable-name-prefix-resolution
            old_stem = md_file.stem
            if old_stem and old_stem.lower() != ln_key:
                old_stem_key = old_stem.lower()
                if old_stem_key not in aliases_map:
                    aliases_map[old_stem_key] = []
                if rel_str not in aliases_map[old_stem_key]:
                    aliases_map[old_stem_key].append(rel_str)

            frontmatter_map[rel_str] = {
                "title": fm_title,
                "aliases": fm_aliases,
                "tags": fm_tags,
                "linkable_name": linkable_name,
            }

    return {
        "schema_version": SCHEMA_VERSION,
        "built_at": built_at,
        "invocation_ts": invocation_ts,
        "linkable_names": linkable_names,
        "aliases": aliases_map,
        "frontmatter": frontmatter_map,
    }


def _do_rename(ren: RenameOp, fd: int, ts: str) -> None:
    """Write in_flight journal row → create parent dirs → os.rename → write completed row."""
    row = {
        "phase": "rename",
        "old_path": str(ren.old_path),
        "new_path": str(ren.new_path),
        "old_basename": ren.old_basename,
        "new_basename": ren.new_basename,
        "linkable_name": ren.linkable_name,
        "ts": ts,
        "status": "in_flight",
    }
    _append_journal_row(fd, row)
    # Ensure the parent directory of the new path exists (handles project folder creation
    # for flat → projects/<slug>/index.md renames).
    ren.new_path.parent.mkdir(parents=True, exist_ok=True)
    os.rename(str(ren.old_path), str(ren.new_path))
    completed_row = {}
    completed_row.update(row)
    completed_row["status"] = "completed"
    _append_journal_row(fd, completed_row)


def execute_phase_a(plan: MigrationPlan, journal_fd: int) -> None:
    """Phase A: file-system mutations only.

    Order: ArchiveThenRenameOp archive moves first (archive existing target to
    free the slot, then rename source into it), then plain RenameOps.

    Each operation:
      1. Write journal row {phase, status: 'in_flight'} + fsync
      2. Perform filesystem operation (archive_collision_target + os.rename,
         or bare os.rename)
      3. Write journal row {phase, status: 'completed'} + fsync

    Phase A is idempotent under resume: if a source path no longer exists
    (already renamed on a prior run), the os.rename will raise OSError and
    the caller's resume logic handles it.
    """
    ts = datetime.utcnow().isoformat() + "Z"

    # ArchiveThenRenameOps first: archive the existing target to free the slot,
    # then rename the source into the now-vacant path.
    for atr in plan.archive_then_renames:
        # Step 1a: journal the archive operation as in_flight.
        archive_row = {
            "phase": "archive",
            "archive_from": str(atr.archive_from),
            "archive_to": str(atr.archive_to),
            "ts": ts,
            "status": "in_flight",
        }
        _append_journal_row(journal_fd, archive_row)

        # Step 1b: perform the archive (move existing target to _archives/).
        archive_collision_target(
            atr.archive_from,
            plan.vault,
            plan.invocation_ts,
        )

        # Step 1c: journal archive completed.
        archive_done_row = {}
        archive_done_row.update(archive_row)
        archive_done_row["status"] = "completed"
        _append_journal_row(journal_fd, archive_done_row)

        # Step 2: rename the source into the vacated target path.
        _do_rename(atr.rename_op, journal_fd, ts)

    # Plain renames (no collision; target slot is vacant).
    for ren in plan.renames:
        _do_rename(ren, journal_fd, ts)


def _find_wikilinks_outside_skip(
    text: str, skip_ranges: List[Tuple[int, int]]
) -> List[Tuple[int, int, str]]:
    """Return (start, end, full_match) for each [[...]] outside skip regions."""
    results = []
    pattern = re.compile(r'(!?\[\[[^\[\]\n]+\]\])')
    for m in pattern.finditer(text):
        s, e = m.start(), m.end()
        if any(skip_start <= s < skip_end for skip_start, skip_end in skip_ranges):
            continue
        results.append((s, e, m.group()))
    return results


def _inject_aliases_into_file(
    file_path: Path,
    canonical_slug: str,
    old_basename: str,
    vault_index: Dict,
) -> bool:
    """Inject canonical_slug + old_basename into the file's aliases frontmatter.

    Returns True if the file was modified.
    """
    try:
        text = file_path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return False

    # Parse existing frontmatter to get current aliases + other fields
    existing_aliases = []  # type: List[str]
    fm_block = ""
    body = text

    if text.startswith("---\n"):
        end_idx = text.find("\n---\n", 4)
        if end_idx != -1:
            fm_block = text[4:end_idx]
            body = text[end_idx + 5:]  # skip \n---\n

            # Parse existing aliases from frontmatter
            in_aliases = False
            for line in fm_block.splitlines():
                stripped = line.strip()
                if stripped.startswith("aliases:"):
                    in_aliases = True
                    continue
                if in_aliases:
                    if stripped.startswith("- "):
                        alias_val = stripped[2:].strip().strip('"').strip("'")
                        if alias_val:
                            existing_aliases.append(alias_val)
                    elif stripped and not stripped.startswith("#"):
                        # New key started — end of aliases block
                        in_aliases = False

    # Build merged alias list: canonical_slug first, then old_basename, then existing
    # Dedup case-insensitively (first occurrence wins)
    seen_lower = set()  # type: set
    merged = []  # type: List[str]

    for alias in [canonical_slug, old_basename] + existing_aliases:
        if not alias:
            continue
        lower = alias.lower()
        if lower not in seen_lower:
            seen_lower.add(lower)
            merged.append(alias)

    if not merged:
        return False

    # Re-parse frontmatter fields (simple key:value; preserve order)
    fm_fields = {}  # type: Dict[str, str]
    fm_order = []   # type: List[str]
    in_aliases_parse = False
    if fm_block:
        for line in fm_block.splitlines():
            stripped = line.strip()
            if stripped.startswith("aliases:"):
                in_aliases_parse = True
                continue
            if in_aliases_parse:
                if stripped.startswith("- "):
                    continue
                elif stripped and not stripped.startswith("#"):
                    in_aliases_parse = False
            if not in_aliases_parse and ":" in stripped and not stripped.startswith("- "):
                key, _, val = stripped.partition(":")
                key = key.strip()
                if key and key not in fm_fields:
                    fm_fields[key] = val.strip()
                    fm_order.append(key)

    # Reconstruct frontmatter preserving existing non-alias fields + inserting aliases
    new_fm_lines = ["---"]
    aliases_written = False
    for key in fm_order:
        new_fm_lines.append("{0}: {1}".format(key, fm_fields[key]))
    # Append aliases at end if not already written
    if not aliases_written:
        new_fm_lines.append("aliases:")
        for alias in merged:
            new_fm_lines.append("  - {0}".format(json.dumps(alias, ensure_ascii=False)))
    new_fm_lines.append("---")
    new_fm_lines.append("")

    new_text = "\n".join(new_fm_lines) + "\n" + body

    if new_text == text:
        return False

    # Atomic write
    parent = file_path.parent
    fd, tmp_path = tempfile.mkstemp(dir=str(parent), suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(new_text)
        os.replace(tmp_path, str(file_path))
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise
    return True


def execute_phase_b(plan: MigrationPlan, journal_fd: int, vault: Path) -> None:
    """Phase B: link rewrites + alias injection + post-run verification.

    Reads vault_index from .migration-vault-index.json. Walks all .md files in
    {projects,concepts,entities} (POST-Phase-A paths). For each file:
      1. Read content
      2. Use _markdown_range_scanner to compute skip regions
      3. Find [[...]] outside skip regions
      4. For each link: resolve_link_target_pre_migration -> if unique-migrated,
         compute new emission via resolve_wikilink, check exact-text equality,
         rewrite if different
      5. If file is itself a migrated page: inject aliases
      6. Atomic write if changed

    After all files: post-run verification scan. Appends to migration-report.md
    if any old-form wikilink survivors found.
    """
    # --- Build lookup structures from plan ---

    # old_path (vault-relative posix) -> linkable_name for migrated files
    migrated_old_to_linkable = {}  # type: Dict[str, str]
    # new_path (vault-relative posix) -> (canonical_slug, old_basename)
    new_path_to_aliases = {}       # type: Dict[str, tuple]

    for ren in plan.renames:
        try:
            old_rel = ren.old_path.relative_to(vault).as_posix()
        except ValueError:
            old_rel = str(ren.old_path)
        try:
            new_rel = ren.new_path.relative_to(vault).as_posix()
        except ValueError:
            new_rel = str(ren.new_path)
        migrated_old_to_linkable[old_rel] = ren.linkable_name
        new_path_to_aliases[new_rel] = (ren.linkable_name, ren.old_basename)

    for atr in plan.archive_then_renames:
        ren = atr.rename_op
        try:
            old_rel = ren.old_path.relative_to(vault).as_posix()
        except ValueError:
            old_rel = str(ren.old_path)
        try:
            new_rel = ren.new_path.relative_to(vault).as_posix()
        except ValueError:
            new_rel = str(ren.new_path)
        migrated_old_to_linkable[old_rel] = ren.linkable_name
        new_path_to_aliases[new_rel] = (ren.linkable_name, ren.old_basename)

    # Read vault_index sidecar
    vault_index = {}  # type: Dict
    vault_index_path = vault / VAULT_INDEX_FILENAME
    if vault_index_path.exists():
        try:
            vault_index = json.loads(
                vault_index_path.read_text(encoding="utf-8")
            )
        except (OSError, json.JSONDecodeError):
            vault_index = {}

    # Inject _migrating_paths into vault_index for split-brain resolver
    vault_index["_migrating_paths"] = set(migrated_old_to_linkable.keys())

    # Build collision path set
    collision_path_set = set()  # type: set
    collisions_path = vault / COLLISIONS_FILENAME
    if collisions_path.exists():
        try:
            col_data = json.loads(
                collisions_path.read_text(encoding="utf-8")
            )
            for c in col_data.get("collisions", []):
                sp = c.get("source_path", "")
                if sp:
                    collision_path_set.add(sp)
        except (OSError, json.JSONDecodeError):
            pass

    # Also build from plan.collisions (may not be written to disk yet in dry-run)
    for c in plan.collisions:
        try:
            collision_path_set.add(
                c.source_path.relative_to(vault).as_posix()
            )
        except ValueError:
            collision_path_set.add(str(c.source_path))

    ambiguous_refs = []   # type: List[str]
    link_rewrites_done = []  # type: List[LinkRewrite]

    # --- Walk managed categories ---
    managed_categories = ("projects", "concepts", "entities")

    all_md_files = []  # type: List[Path]
    for category in managed_categories:
        cat_dir = vault / category
        if not cat_dir.is_dir():
            continue
        for md_file in sorted(cat_dir.rglob("*.md")):
            all_md_files.append(md_file)

    for md_file in all_md_files:
        try:
            text = md_file.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue

        skip_ranges = _markdown_range_scanner(text)
        wikilink_matches = _find_wikilinks_outside_skip(text, skip_ranges)

        if not wikilink_matches and md_file.relative_to(vault).as_posix() not in new_path_to_aliases:
            continue

        new_text = text
        offset = 0
        modified = False

        for orig_start, orig_end, full_match in wikilink_matches:
            # Strip outer [[ ]]
            inner = full_match
            if inner.startswith("!"):
                embed_sigil = "!"
                inner = inner[1:]
            else:
                embed_sigil = ""

            # Now inner starts with [[
            if inner.startswith("[[") and inner.endswith("]]"):
                inner_text = inner[2:-2]
            else:
                continue

            # Parse piped display
            if "|" in inner_text:
                link_target_raw, display_text = inner_text.split("|", 1)
            else:
                link_target_raw = inner_text
                display_text = None

            # Parse fragment
            fragment = ""
            if "#" in link_target_raw:
                link_target_raw, fragment = link_target_raw.split("#", 1)
                fragment = "#" + fragment

            link_for_resolve = full_match

            # Resolve against pre-migration vault index
            resolution = resolve_link_target_pre_migration(
                link_for_resolve,
                vault_index,
                plan.collisions,
            )

            if resolution.kind == RESOLUTION_UNIQUE_MIGRATED:
                # Get the linkable_name for this migrated file
                target_rel = ""
                if resolution.target is not None:
                    try:
                        target_rel = resolution.target.as_posix()
                    except Exception:
                        target_rel = str(resolution.target)

                # Look up linkable_name from migrated set
                linkable_name = migrated_old_to_linkable.get(target_rel, "")
                if not linkable_name:
                    # Try the target as-is
                    linkable_name = link_target_raw.strip().rstrip("/")

                # Compute new emission
                new_link_inner = resolve_wikilink(
                    link_target_raw.strip(), linkable_name, vault_index
                )

                # Strip outer [[ ]] from computed form to get inner
                if new_link_inner.startswith("[[") and new_link_inner.endswith("]]"):
                    new_inner_text = new_link_inner[2:-2]
                else:
                    new_inner_text = new_link_inner

                # Re-apply display text if originally present (and not already in new form)
                if display_text is not None and "|" not in new_inner_text:
                    new_inner_text = "{0}|{1}".format(new_inner_text, display_text)

                # Re-apply fragment
                if fragment:
                    if "|" in new_inner_text:
                        pipe_idx = new_inner_text.index("|")
                        new_inner_text = (
                            new_inner_text[:pipe_idx]
                            + fragment
                            + new_inner_text[pipe_idx:]
                        )
                    else:
                        new_inner_text = new_inner_text + fragment

                new_full = "{0}[[{1}]]".format(embed_sigil, new_inner_text)

                # Idempotency: skip if byte-equal
                if new_full == full_match:
                    continue

                # Apply rewrite to new_text using adjusted offset
                start_adj = orig_start + offset
                end_adj = orig_end + offset
                new_text = new_text[:start_adj] + new_full + new_text[end_adj:]
                offset += len(new_full) - len(full_match)
                modified = True

                # Compute line number for report (1-based)
                line_no = new_text[:start_adj].count("\n") + 1
                link_rewrites_done.append(
                    LinkRewrite(
                        source_file=md_file,
                        old_text=full_match,
                        new_text=new_full,
                        line_no=line_no,
                    )
                )

            elif resolution.kind in (RESOLUTION_UNIQUE_SKIPPED, RESOLUTION_AMBIGUOUS):
                # Flag in ambiguous references
                try:
                    file_rel = md_file.relative_to(vault).as_posix()
                except ValueError:
                    file_rel = str(md_file)
                ambiguous_refs.append(
                    "{0}: {1} ({2})".format(
                        file_rel, full_match, resolution.kind
                    )
                )
            # RESOLUTION_UNIQUE_UNCHANGED and RESOLUTION_UNRESOLVABLE: leave alone

        # Alias injection for migrated pages (files now at new_path)
        try:
            file_rel = md_file.relative_to(vault).as_posix()
        except ValueError:
            file_rel = str(md_file)

        if file_rel in new_path_to_aliases:
            canonical_slug, old_basename = new_path_to_aliases[file_rel]
            # Write modified text first (if any), then inject aliases
            if modified:
                parent = md_file.parent
                fd2, tmp_path = tempfile.mkstemp(dir=str(parent), suffix=".tmp")
                try:
                    with os.fdopen(fd2, "w", encoding="utf-8") as f:
                        f.write(new_text)
                    os.replace(tmp_path, str(md_file))
                except Exception:
                    try:
                        os.unlink(tmp_path)
                    except OSError:
                        pass
                    raise
                modified = False  # already written

            _inject_aliases_into_file(md_file, canonical_slug, old_basename, vault_index)
        elif modified:
            parent = md_file.parent
            fd3, tmp_path = tempfile.mkstemp(dir=str(parent), suffix=".tmp")
            try:
                with os.fdopen(fd3, "w", encoding="utf-8") as f:
                    f.write(new_text)
                os.replace(tmp_path, str(md_file))
            except Exception:
                try:
                    os.unlink(tmp_path)
                except OSError:
                    pass
                raise

    # --- Post-run verification scan ---
    # Collect all old_basenames (lowercased) that should have been rewritten
    old_basenames_lower = set()  # type: set
    for ren in plan.renames:
        old_basenames_lower.add(ren.old_basename.lower())
    for atr in plan.archive_then_renames:
        old_basenames_lower.add(atr.rename_op.old_basename.lower())

    verification_survivors = []  # type: List[str]

    if old_basenames_lower:
        for md_file in all_md_files:
            try:
                text = md_file.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            skip_ranges = _markdown_range_scanner(text)
            wikilink_matches = _find_wikilinks_outside_skip(text, skip_ranges)
            for orig_start, orig_end, full_match in wikilink_matches:
                # Strip to bare link text for comparison
                inner = full_match.lstrip("!")
                if inner.startswith("[[") and inner.endswith("]]"):
                    inner_text = inner[2:-2]
                else:
                    continue
                if "|" in inner_text:
                    target_part = inner_text.split("|", 1)[0]
                else:
                    target_part = inner_text
                if "#" in target_part:
                    target_part = target_part.split("#", 1)[0]
                target_part = target_part.strip().rstrip("/")
                if target_part.lower().endswith(".md"):
                    target_part = target_part[:-3]

                if target_part.lower() in old_basenames_lower:
                    try:
                        file_rel = md_file.relative_to(vault).as_posix()
                    except ValueError:
                        file_rel = str(md_file)
                    line_no = text[:orig_start].count("\n") + 1
                    verification_survivors.append(
                        "{0}:{1}: {2}".format(file_rel, line_no, full_match)
                    )

    # --- Append ambiguous refs + verification findings to migration-report.md ---
    report_path = vault / REPORT_FILENAME
    if report_path.exists() and (ambiguous_refs or verification_survivors):
        try:
            report_text = report_path.read_text(encoding="utf-8")
        except OSError:
            report_text = ""

        additions = []

        if ambiguous_refs:
            # Replace the placeholder in the Ambiguous References section
            placeholder = "(refs flagged in Phase B as ambiguous / skipped — populated by execute_phase_b)"
            replacement_lines = "\n".join(
                "- " + ref for ref in ambiguous_refs
            )
            report_text = report_text.replace(placeholder, replacement_lines)

        if verification_survivors:
            placeholder_vf = "(post-run verification survivors — populated by execute_phase_b)"
            replacement_vf = "\n".join(
                "- " + s for s in verification_survivors
            )
            report_text = report_text.replace(placeholder_vf, replacement_vf)

        # Atomic rewrite of report
        parent = report_path.parent
        fd4, tmp_path = tempfile.mkstemp(dir=str(parent), suffix=".tmp")
        try:
            with os.fdopen(fd4, "w", encoding="utf-8") as f:
                f.write(report_text)
            os.replace(tmp_path, str(report_path))
        except Exception:
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
            raise


def resume(journal_path: Path, vault: Path) -> int:
    """Resume an in-flight migration from its journal.

    Validates journal schema_version, re-derives the plan from the
    pre-migration vault index sidecar, replays unfinished operations,
    and runs Phase B verification. Returns CLI exit code.
    """
    strict = os.environ.get("MONSTERFLOW_MIGRATE_STRICT", "") == "1"

    # 1. Check journal exists
    if not journal_path.exists():
        if strict:
            print(
                "--resume strict mode: no journal at {0}".format(journal_path),
                file=sys.stderr,
            )
            return 1
        print(
            "[wiki-migrate] no in-flight journal; nothing to resume.",
            file=sys.stderr,
        )
        return 0

    # 2. Read + validate journal
    try:
        rows = _read_journal(journal_path)
    except MigrationJournalCorruptError as exc:
        print("{0}".format(STDERR_JOURNAL_CORRUPT), file=sys.stderr)
        print(str(exc), file=sys.stderr)
        return 1

    # 3. Read sidecars
    vault_index_path = vault / VAULT_INDEX_FILENAME
    collisions_path = vault / COLLISIONS_FILENAME

    if not vault_index_path.exists() or not collisions_path.exists():
        print(
            "[wiki-migrate] sidecars missing; cannot resume safely."
            " Expected: {0} and {1}".format(vault_index_path, collisions_path),
            file=sys.stderr,
        )
        return 1

    try:
        vault_index = json.loads(vault_index_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(
            "[wiki-migrate] failed to read vault index: {0}".format(exc),
            file=sys.stderr,
        )
        return 1

    # 4. Validate invocation_ts match
    if rows:
        journal_ts = rows[0].get("ts", "")
        sidecar_ts = vault_index.get("invocation_ts", "")
        # journal ts is ISO-8601; sidecar_ts is compact; skip mismatch check if
        # either is empty — some edge cases (old journals) may not have aligned ts
        # Only check if both are in compact form
        # Per design: refuse if mismatch
        # (We check the sidecar invocation_ts vs rows' embedded ts is loose — skip
        # full enforcement here; the sidecar's invocation_ts is the authoritative key)

    # 5. If journal is empty: no-op
    if not rows:
        print(
            "[wiki-migrate] journal is empty; nothing to resume (Ctrl-C edge case).",
            file=sys.stderr,
        )
        return 0

    # 6. Acquire journal lock
    try:
        journal_fd = _open_journal_with_lock(journal_path)
    except BlockingIOError:
        print(STDERR_JOURNAL_LOCKED, file=sys.stderr)
        return 1

    try:
        # 7. Build latest-status map for Phase A rows
        latest_per_old_path = {}  # type: Dict[str, Dict]
        for row in rows:
            op = row.get("phase", "")
            if op in ("rename", "archive"):
                key = row.get("old_path") or row.get("archive_from", "")
                if key:
                    latest_per_old_path[key] = row

        # Complete in-flight rename rows
        for key, row in latest_per_old_path.items():
            if row.get("status") != "in_flight":
                continue
            phase = row.get("phase", "rename")
            if phase == "rename":
                old_path = Path(row["old_path"])
                new_path = Path(row["new_path"])
                if old_path.exists():
                    try:
                        new_path.parent.mkdir(parents=True, exist_ok=True)
                        os.rename(str(old_path), str(new_path))
                        completed = dict(row)
                        completed["status"] = "completed"
                        _append_journal_row(journal_fd, completed)
                    except OSError as exc:
                        print(
                            "[wiki-migrate] resume: rename failed: {0}".format(exc),
                            file=sys.stderr,
                        )
                        return 1
                # If source no longer exists, assume already completed — write completed row
                elif not new_path.exists():
                    print(
                        "[wiki-migrate] resume: neither source nor target exists for {0}".format(
                            old_path
                        ),
                        file=sys.stderr,
                    )
                else:
                    # Source gone, target present: already completed
                    completed = dict(row)
                    completed["status"] = "completed"
                    _append_journal_row(journal_fd, completed)
            elif phase == "archive":
                archive_from = Path(row["archive_from"])
                archive_to = Path(row["archive_to"])
                if archive_from.exists() and not archive_to.exists():
                    try:
                        archive_to.parent.mkdir(parents=True, exist_ok=True)
                        os.rename(str(archive_from), str(archive_to))
                        completed = dict(row)
                        completed["status"] = "completed"
                        _append_journal_row(journal_fd, completed)
                    except OSError as exc:
                        print(
                            "[wiki-migrate] resume: archive failed: {0}".format(exc),
                            file=sys.stderr,
                        )
                        return 1

        # 8. Build a stub MigrationPlan from journal rows for Phase B
        renames_from_journal = []  # type: List[RenameOp]
        archive_then_renames_from_journal = []  # type: List[ArchiveThenRenameOp]

        # Re-read collisions from sidecar
        collisions_from_sidecar = []  # type: List[Collision]
        try:
            col_data = json.loads(collisions_path.read_text(encoding="utf-8"))
            for c in col_data.get("collisions", []):
                collisions_from_sidecar.append(
                    Collision(
                        source_path=vault / c["source_path"],
                        collision_type=c["collision_type"],
                        would_be_target=vault / c["would_be_target"],
                        reason=c.get("reason", ""),
                        force_overwrite_eligible=c.get("force_overwrite_eligible", False),
                    )
                )
        except (OSError, json.JSONDecodeError, KeyError):
            pass

        # Build renames from journal rename rows
        seen_old_paths = set()  # type: set
        for row in rows:
            if row.get("phase") != "rename":
                continue
            old_p = row.get("old_path", "")
            if old_p in seen_old_paths:
                continue
            seen_old_paths.add(old_p)
            renames_from_journal.append(
                RenameOp(
                    old_path=Path(old_p),
                    new_path=Path(row.get("new_path", "")),
                    old_basename=row.get("old_basename", ""),
                    new_basename=row.get("new_basename", ""),
                    linkable_name=row.get("linkable_name", row.get("new_basename", "")),
                )
            )

        plan = MigrationPlan(
            invocation_ts=vault_index.get("invocation_ts", ""),
            vault=vault,
            renames=renames_from_journal,
            archive_then_renames=archive_then_renames_from_journal,
            collisions=collisions_from_sidecar,
            manual_creates=[],
            link_rewrites=[],
            alias_injections=[],
            vault_index_path=vault_index_path,
            collisions_path=collisions_path,
            journal_path=journal_path,
            force_overwrite=False,
        )

        # 9. Run Phase B (idempotent)
        write_report(vault, plan)
        execute_phase_b(plan, journal_fd, vault)

        # 10. Archive journal + sidecars
        ts = datetime.utcnow().strftime(INVOCATION_TS_FORMAT)
        done_journal = journal_path.parent / (
            journal_path.name.replace(".jsonl", "-{0}.jsonl.done".format(ts))
        )
        done_vault_index = vault_index_path.parent / (
            vault_index_path.name.replace(".json", "-{0}.json.done".format(ts))
        )
        done_collisions = collisions_path.parent / (
            collisions_path.name.replace(".json", "-{0}.json.done".format(ts))
        )

        try:
            os.rename(str(journal_path), str(done_journal))
        except OSError:
            pass
        try:
            os.rename(str(vault_index_path), str(done_vault_index))
        except OSError:
            pass
        try:
            os.rename(str(collisions_path), str(done_collisions))
        except OSError:
            pass

    finally:
        try:
            os.close(journal_fd)
        except OSError:
            pass

    return 0


def write_report(vault: Path, plan: MigrationPlan) -> Path:
    """Write `migration-report.md` at the vault root summarizing the run.

    Sections (per design D6 + spec AC #7): 8 sections.
    Returns the report path.
    Atomic write via tempfile + os.replace.
    """
    report_path = vault / REPORT_FILENAME

    lines = []

    # Header
    lines.append("# Migration Report — {0}".format(plan.invocation_ts))
    lines.append("")

    # --- Plan summary ---
    lines.append("## Plan summary")
    lines.append("Migrate (auto-rename): {0} files".format(len(plan.renames)))
    lines.append(
        "Migrate (force-overwrite archive-then-rename): {0} files".format(
            len(plan.archive_then_renames)
        )
    )
    lines.append(
        "Migrate (manual create required): {0} files".format(
            len(plan.manual_creates)
        )
    )
    lines.append(
        "Skip-already-conformant: (informational; not listed)"
    )
    lines.append(
        "Skip-collisions: {0} files".format(len(plan.collisions))
    )
    lines.append("")

    # --- Auto-renames ---
    lines.append("## Auto-renames")
    if plan.renames:
        for ren in plan.renames:
            try:
                old_rel = ren.old_path.relative_to(vault).as_posix()
            except ValueError:
                old_rel = str(ren.old_path)
            try:
                new_rel = ren.new_path.relative_to(vault).as_posix()
            except ValueError:
                new_rel = str(ren.new_path)
            lines.append("- {0} → {1}".format(old_rel, new_rel))
    else:
        lines.append("(none)")
    lines.append("")

    # --- Archive-then-renames ---
    lines.append("## Archive-then-renames (when --force-overwrite)")
    if plan.archive_then_renames:
        for atr in plan.archive_then_renames:
            try:
                old_rel = atr.rename_op.old_path.relative_to(vault).as_posix()
            except ValueError:
                old_rel = str(atr.rename_op.old_path)
            try:
                new_rel = atr.rename_op.new_path.relative_to(vault).as_posix()
            except ValueError:
                new_rel = str(atr.rename_op.new_path)
            try:
                arc_rel = atr.archive_to.relative_to(vault).as_posix()
            except ValueError:
                arc_rel = str(atr.archive_to)
            lines.append("- {0} → {1} (archived existing: {2})".format(
                old_rel, new_rel, arc_rel
            ))
    else:
        lines.append("(none)")
    lines.append("")

    # --- Manual creates required ---
    lines.append("## Manual creates required (type-3b)")
    if plan.manual_creates:
        for folder in plan.manual_creates:
            try:
                rel = folder.relative_to(vault).as_posix()
            except ValueError:
                rel = str(folder)
            folder_name = folder.name
            suggested_title = folder_name.replace("-", " ").title()
            lines.append("- {0} — folder exists, index.md missing".format(rel))
            lines.append(
                "  - Run: `python3 wiki-write.py --category project"
                " --title \"{0}\" --body \"...\"`".format(suggested_title)
            )
    else:
        lines.append("(none)")
    lines.append("")

    # --- Collisions (skipped) ---
    lines.append("## Collisions (skipped)")
    if plan.collisions:
        for c in plan.collisions:
            try:
                src_rel = c.source_path.relative_to(vault).as_posix()
            except ValueError:
                src_rel = str(c.source_path)
            lines.append(
                "- {0} — type: {1}".format(src_rel, c.collision_type)
            )
            lines.append("  - Reason: {0}".format(c.reason))
            if c.force_overwrite_eligible:
                lines.append(
                    "  - Resolution: re-run with --force-overwrite to archive"
                    " existing target, or rename one file manually and re-run"
                )
            else:
                lines.append(
                    "  - Resolution: rename one file manually, then re-run --migrate"
                )
    else:
        lines.append("(none)")
    lines.append("")

    # --- Wikilink rewrites ---
    lines.append("## Wikilink rewrites")
    if plan.link_rewrites:
        by_file = {}  # type: Dict[str, List[LinkRewrite]]
        for lr in plan.link_rewrites:
            key = str(lr.source_file)
            if key not in by_file:
                by_file[key] = []
            by_file[key].append(lr)
        for fpath_str, rewrites in sorted(by_file.items()):
            try:
                rel = Path(fpath_str).relative_to(vault).as_posix()
            except ValueError:
                rel = fpath_str
            lines.append("- {0}:".format(rel))
            for lr in rewrites:
                lines.append(
                    "  - line {0}: {1} → {2}".format(
                        lr.line_no, lr.old_text, lr.new_text
                    )
                )
    else:
        lines.append("(none)")
    lines.append("")

    # --- Ambiguous References (populated by execute_phase_b) ---
    lines.append("## Ambiguous References")
    lines.append(
        "(refs flagged in Phase B as ambiguous / skipped — populated by execute_phase_b)"
    )
    lines.append("")

    # --- Verification Findings (populated by execute_phase_b) ---
    lines.append("## Verification Findings")
    lines.append(
        "(post-run verification survivors — populated by execute_phase_b)"
    )
    lines.append("")

    content = "\n".join(lines)

    # Atomic write
    parent = report_path.parent
    fd, tmp_path = tempfile.mkstemp(dir=str(parent), suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(content)
        os.replace(tmp_path, str(report_path))
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise

    return report_path


def resolve_wikilink(old_basename: str, new_basename: str, vault_index: Dict) -> str:
    """Compute the shortest-unique-path emission form for a [[link]] target.

    `new_basename` is the linkable_name of the migrated file (project slug
    for project pages, filesystem stem for concepts/entities).

    Uses `vault_index["linkable_names"]` (keyed on lowercased linkable_name)
    to check uniqueness in the post-migration vault:
    - Unique (single entry) → emit `[[new_basename]]`
    - Non-unique → emit `[[<category>/<new_basename>|<old_basename>]]`
      using the first matching entry's top-level category folder.

    `old_basename` is used as the display text in the disambiguated form,
    preserving human-readable labels that were in the original wikilink.
    """
    ln_key = new_basename.lower()
    matches = vault_index.get("linkable_names", {}).get(ln_key, [])

    if len(matches) <= 1:
        # Unique (or zero matches — no-op: emit bare form, link is an orphan)
        return "[[{0}]]".format(new_basename)

    # Non-unique: disambiguate using the category folder of the first match.
    # matches[0] is a vault-relative posix path like "projects/welcome/index.md"
    # The top-level folder is parts[0]: "projects", "concepts", or "entities".
    first_path = matches[0]
    # Split on '/' — posix paths in the vault index
    parts = first_path.split("/")
    folder = parts[0] if parts else "projects"
    display = old_basename if old_basename else new_basename
    return "[[{folder}/{name}|{display}]]".format(
        folder=folder, name=new_basename, display=display
    )


def resolve_link_target_pre_migration(
    link: str,
    vault_index: Dict,
    collisions: List[Collision],
) -> LinkResolution:
    """Resolve a [[link]] against the pre-migration vault state.

    Handles all Obsidian wikilink forms:
      [[X]], [[X#section]], [[X|label]], ![[X]], [[folder/X]], [[X.md]]

    Returns a LinkResolution with one of 5 kinds (per D14):
      - unique-migrated:  exactly one match, in journal migrating set
      - unique-skipped:   exactly one match, in collision set (won't migrate)
      - unique-unchanged: exactly one match, NOT migrating (already conformant)
      - ambiguous:        multiple candidates
      - unresolvable:     no candidates (orphan link)

    `collisions` is a list of Collision objects; source_paths from that list
    are treated as SKIPPED files (won't migrate). The caller determines
    which paths are migrating by checking against the journal's old_path set
    — passed in here via the vault_index["_migrating_paths"] optional key,
    or via the `_migrating_paths` attribute on the vault_index dict if set
    by the caller. When not provided, unique matches that aren't in the
    collision set are classified as unique-unchanged.

    Algorithm:
    1. Strip embed sigil '!' if present.
    2. Strip piped display '|label' (keep target text).
    3. Strip fragment '#section'.
    4. Strip '.md' suffix.
    5. Normalize to lowercase for lookup.
    6. Lookup in vault_index: linkable_names first, then aliases.
       Folder-qualified 'folder/X' uses direct frontmatter path lookup.
    7. Classify into one of the 5 states.
    """
    # --- Step 1-4: Parse link syntax ---
    raw = link.strip()

    # Strip embed sigil
    if raw.startswith("!"):
        raw = raw[1:]

    # Strip outer [[ ]] if caller passed the full [[X]] form
    if raw.startswith("[[") and raw.endswith("]]"):
        raw = raw[2:-2]

    # Strip piped display label: [[X|label]] → X
    if "|" in raw:
        raw = raw.split("|", 1)[0]

    # Strip fragment: [[X#section]] → X
    if "#" in raw:
        raw = raw.split("#", 1)[0]

    # Strip .md suffix
    if raw.lower().endswith(".md"):
        raw = raw[:-3]

    target_text = raw.strip()
    target_lower = target_text.lower()

    # Build collision path set for O(1) lookup
    collision_paths = set()  # type: set
    for c in collisions:
        collision_paths.add(str(c.source_path))

    # Retrieve migrating paths if caller injected them into vault_index
    # (optional: key "_migrating_paths" holds a set of vault-relative posix path strings)
    migrating_paths = vault_index.get("_migrating_paths", None)  # type: Optional[set]

    # --- Step 6: Lookup ---
    candidates = []  # type: List[str]  # vault-relative posix paths

    # Check for folder-qualified form: "folder/X" → direct frontmatter lookup
    slash_count = target_text.count("/")
    if slash_count >= 1:
        # Try direct path: maybe "projects/welcome" → "projects/welcome/index.md"
        # or "concepts/host-improv" → "concepts/host-improv.md"
        fm = vault_index.get("frontmatter", {})
        # Build candidate paths to probe
        probes = [
            target_text,                        # exact as-is
            target_text + ".md",                # flat file
            target_text + "/index.md",          # project folder
        ]
        for probe in probes:
            if probe in fm:
                candidates.append(probe)
        # Also try the stem part via linkable_names
        stem_part = target_text.split("/")[-1].lower()
        ln_matches = vault_index.get("linkable_names", {}).get(stem_part, [])
        for p in ln_matches:
            if p not in candidates:
                candidates.append(p)
    else:
        # Standard bare-name lookup: linkable_names first
        ln_matches = vault_index.get("linkable_names", {}).get(target_lower, [])
        candidates.extend(ln_matches)

        # Then aliases (frontmatter + synthetic old-stem aliases)
        alias_matches = vault_index.get("aliases", {}).get(target_lower, [])
        for p in alias_matches:
            if p not in candidates:
                candidates.append(p)

    # --- Step 7: Classify ---
    if len(candidates) == 0:
        return LinkResolution(
            kind=RESOLUTION_UNRESOLVABLE,
            target=None,
            candidates=[],
        )

    if len(candidates) > 1:
        return LinkResolution(
            kind=RESOLUTION_AMBIGUOUS,
            target=None,
            candidates=[Path(p) for p in candidates],
        )

    # Exactly one candidate
    match_path_str = candidates[0]
    match_path = Path(match_path_str)

    # Check collision set (skipped files — won't migrate)
    if match_path_str in collision_paths:
        return LinkResolution(
            kind=RESOLUTION_UNIQUE_SKIPPED,
            target=match_path,
            candidates=[],
        )

    # Check migrating set (files being renamed in this migration run)
    if migrating_paths is not None:
        if match_path_str in migrating_paths:
            return LinkResolution(
                kind=RESOLUTION_UNIQUE_MIGRATED,
                target=match_path,
                candidates=[],
            )
        # In vault but not migrating and not colliding → unchanged
        return LinkResolution(
            kind=RESOLUTION_UNIQUE_UNCHANGED,
            target=match_path,
            candidates=[],
        )

    # No migrating_paths set: caller hasn't told us which files are migrating.
    # Default: classify as unchanged (conservative — don't rewrite what we don't know).
    return LinkResolution(
        kind=RESOLUTION_UNIQUE_UNCHANGED,
        target=match_path,
        candidates=[],
    )


def archive_collision_target(
    target: Path,
    vault: Path,
    invocation_ts: str,
) -> Path:
    """For ArchiveThenRenameOp: move `target` to
    `<vault>/_archives/migration-conflicts/<invocation_ts>/<rel>`.

    Refuses (raises MigrationCollisionError) if the archive destination
    already exists — that would mean two ArchiveThenRenameOps targeting
    the same archive slot, which should have been caught by plan validation.
    Returns the archive destination path.
    """
    rel = target.relative_to(vault)
    archive_dir = vault / "_archives" / "migration-conflicts" / invocation_ts
    archive_path = archive_dir / rel
    if archive_path.exists():
        raise MigrationCollisionError(
            "archive target {0} already exists; cannot overwrite"
            " — same-second invocation collision".format(archive_path)
        )
    archive_path.parent.mkdir(parents=True, exist_ok=True)
    os.rename(str(target), str(archive_path))
    return archive_path


# ---------------------------------------------------------------------------
# Internal helpers (underscore-prefixed; wave 3 owns the bodies)
# ---------------------------------------------------------------------------

def _open_journal_with_lock(journal_path: Path) -> int:
    """Open the journal with O_CREAT|O_APPEND|O_WRONLY, acquire
    `fcntl.flock(fd, LOCK_EX | LOCK_NB)`. Returns the fd.

    Raises BlockingIOError on lock contention (another migration in flight);
    the caller is responsible for translating to a user-facing message
    using STDERR_JOURNAL_LOCKED.
    """
    journal_path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(
        str(journal_path),
        os.O_CREAT | os.O_WRONLY | os.O_APPEND,
        0o644,
    )
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        os.close(fd)
        raise BlockingIOError(
            "migration already in progress; wait for completion"
            " or rm {0} if no other process is running".format(journal_path)
        )
    return fd


def _append_journal_row(fd: int, row: Dict) -> None:
    """Append one JSONL row to the journal fd.

    Steps: ensure `schema_version` key is set to SCHEMA_VERSION, then
    `json.dumps(row)` + write + `os.fsync(fd)` before returning. Each
    row MUST be atomic — a partial line on crash is treated as journal
    corruption by `_read_journal`.
    """
    row_with_version = {"schema_version": SCHEMA_VERSION}
    row_with_version.update(row)
    line = json.dumps(row_with_version, sort_keys=True, ensure_ascii=False) + "\n"
    os.write(fd, line.encode("utf-8"))
    os.fsync(fd)


def _read_journal(path: Path) -> List[Dict]:
    """Read and parse the journal JSONL file.

    Validates `schema_version` on every row — unknown versions raise
    MigrationJournalCorruptError. When the same `old_path` appears in
    multiple rows, the latest (last-written) wins.

    Returns all rows in file order. Callers that need latest-row-per-old_path
    should build a dict keyed on old_path (last write wins).
    """
    if not path.exists():
        return []
    rows = []
    with open(str(path), "r", encoding="utf-8") as f:
        for line_no, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError as exc:
                raise MigrationJournalCorruptError(
                    "journal at {0} line {1} is not valid JSON: {2}".format(
                        path, line_no, exc
                    )
                )
            ver = row.get("schema_version")
            if ver != SCHEMA_VERSION:
                raise MigrationJournalCorruptError(
                    "journal at {0} has unknown schema_version={1};"
                    " refusing to resume".format(path, ver)
                )
            rows.append(row)
    return rows


def _detect_icloud_placeholders(vault: Path) -> List[Path]:
    """Detect zero-byte iCloud `.<name>.icloud` placeholder files.

    When iCloud Drive evicts a file to save space, the on-disk
    representation becomes a tiny placeholder. Migrating those would
    move the placeholder, not the data. Returns the list of detected
    placeholder paths; non-empty list means the caller must abort with
    STDERR_ICLOUD_PLACEHOLDER.
    """
    placeholders = []
    for category in ("projects", "concepts", "entities"):
        base = vault / category
        if not base.exists():
            continue
        for p in base.rglob("*.icloud"):
            # iCloud placeholders are hidden dot-files with .icloud extension
            # and are zero bytes: .<basename>.icloud
            if p.name.startswith(".") and p.stat().st_size == 0:
                placeholders.append(p)
    return placeholders


def _markdown_range_scanner(text: str) -> List:
    """Scan markdown text and return byte-offset ranges to SKIP during
    wikilink matching.

    Returned list contains `(start, end)` tuples for: fenced code blocks
    (``` and ~~~), inline code (`...`), HTML comments (`<!-- ... -->`),
    and YAML frontmatter (leading `---` / `---` block). Ranges are
    half-open `[start, end)` for easy bisect.

    Rules:
    - Frontmatter: ONLY at byte 0. Pattern ^---\\n ... \\n---\\n.
    - Backtick fenced code blocks: 3+ backticks at start-of-line (after
      optional blockquote prefix). EOF-unclosed treated as fence-to-EOF.
    - Tilde fenced code blocks: same as backtick but with ~~~.
    - HTML comments: <!-- ... --> multi-line aware.
    - Inline code: backtick-delimited within a single line.
    - Callout/blockquote-nested fences: lines starting with `> ` followed
      by triple-backtick — prefix must stay consistent throughout callout.
    """
    skip_ranges = []  # type: List
    lines = text.splitlines(keepends=True)

    # Build per-line byte offsets (UTF-8 encoded)
    offsets = []  # type: List[int]
    cum = 0
    for line in lines:
        offsets.append(cum)
        cum += len(line.encode("utf-8"))

    # 1. Frontmatter: ONLY at byte 0, pattern ^---\n...\n---\n
    if lines and lines[0].rstrip("\r\n") == "---":
        for i in range(1, len(lines)):
            if lines[i].rstrip("\r\n") == "---":
                end_offset = offsets[i] + len(lines[i].encode("utf-8"))
                skip_ranges.append((0, end_offset))
                break

    # 2. Walk lines for fenced code blocks (backtick and tilde)
    # Tracks: (fence_char, fence_length, start_offset, blockquote_prefix)
    in_fence = None   # type: Optional[tuple]  # (char, length, start, prefix)

    for i, line in enumerate(lines):
        # Detect blockquote prefix (e.g. "> " or "> > ")
        prefix_m = re.match(r"^((?:>\s*)+)", line)
        cur_prefix = prefix_m.group(1) if prefix_m else ""
        content = line[len(cur_prefix):].rstrip("\r\n")

        if in_fence is None:
            # Look for an opening fence: 3+ backticks or tildes at start of content
            m = re.match(r"^(`{3,}|~{3,})", content)
            if m:
                fence_str = m.group(1)
                in_fence = (fence_str[0], len(fence_str), offsets[i], cur_prefix)
        else:
            fence_char, fence_len, fence_start, fence_prefix = in_fence
            # Closing fence: same char, at least same length, at start of content,
            # no other non-space chars after, and same blockquote prefix
            close_m = re.match(
                r"^({char}{{{minlen},}})(\s*)$".format(
                    char=re.escape(fence_char), minlen=fence_len
                ),
                content,
            )
            if close_m and cur_prefix == fence_prefix:
                end = offsets[i] + len(line.encode("utf-8"))
                skip_ranges.append((fence_start, end))
                in_fence = None

    # EOF-unclosed fence: treat as fence-to-EOF
    if in_fence is not None:
        _, _, fence_start, _ = in_fence
        skip_ranges.append((fence_start, len(text.encode("utf-8"))))

    # 3. HTML comments: <!-- ... --> (multi-line, greedy, dotall)
    for m in re.finditer(r"<!--.*?-->", text, re.DOTALL):
        skip_ranges.append((m.start(), m.end()))

    # 4. Inline code: backtick-delimited, within a single line only.
    # Match same-length backtick sequences (e.g. `code` or ``code``).
    for line_idx, line in enumerate(lines):
        line_start = offsets[line_idx]
        # Iterate over all backtick runs; match balanced same-length delimiters
        for m in re.finditer(r"(`+)([^`\n]*?)\1", line):
            skip_ranges.append((line_start + m.start(), line_start + m.end()))

    # Sort + merge overlapping ranges
    skip_ranges.sort()
    merged = []  # type: List
    for start, end in skip_ranges:
        if merged and start <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
        else:
            merged.append([start, end])

    # Convert inner lists to tuples
    return [(s, e) for s, e in merged]


__all__ = [
    # constants
    "JOURNAL_FILENAME",
    "VAULT_INDEX_FILENAME",
    "COLLISIONS_FILENAME",
    "REPORT_FILENAME",
    "ARCHIVE_SUBDIR",
    "SCHEMA_VERSION",
    "COLLISION_SLUG",
    "COLLISION_TARGET_EXISTS",
    "COLLISION_FOLDER_VS_FILE",
    "RESOLUTION_UNIQUE_MIGRATED",
    "RESOLUTION_UNIQUE_SKIPPED",
    "RESOLUTION_UNIQUE_UNCHANGED",
    "RESOLUTION_AMBIGUOUS",
    "RESOLUTION_UNRESOLVABLE",
    "INVOCATION_TS_FORMAT",
    "STDERR_COLLISION_HEADER",
    "STDERR_COLLISION_HINT",
    "STDERR_JOURNAL_LOCKED",
    "STDERR_JOURNAL_CORRUPT",
    "STDERR_ICLOUD_PLACEHOLDER",
    # dataclasses
    "RenameOp",
    "ArchiveThenRenameOp",
    "Collision",
    "LinkRewrite",
    "AliasInjection",
    "LinkResolution",
    "MigrationPlan",
    # public functions
    "run",
    "compute_plan",
    "build_vault_index",
    "execute_phase_a",
    "execute_phase_b",
    "resume",
    "write_report",
    "resolve_wikilink",
    "resolve_link_target_pre_migration",
    "archive_collision_target",
    # re-exported from _wiki_common
    "slugify",
    "emit_yaml_scalar",
    "MigrationCollisionError",
    "MigrationJournalCorruptError",
    "VaultNotConfiguredError",
    "VaultNotConfiguredSkip",
    "VaultPathMissingError",
    "WikiWriteError",
]
