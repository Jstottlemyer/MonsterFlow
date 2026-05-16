#!/usr/bin/env python3
"""
wiki-write.py — Deterministic Obsidian-vault page writer for MonsterFlow.

Owns the FULL write lifecycle for project/concept/entity pages:
  slug computation + frontmatter emission + body assembly + atomic write.

Modes:
  1. Default-write  — write a single page (frontmatter + body) atomically.
  2. --lint         — scan the vault for 4 convention violations, exit 0 regardless.
  3. --write-conventions <vault>  — emit per-category _convention.md files.

Usage (default-write):
  python3 wiki-write.py --category project --title "PatternCall iOS" \\
    --topic decisions --summary "..." --tags "ios,native" --body "..."

Usage (lint):
  python3 wiki-write.py --lint

Usage (install-time, emits _convention.md trio):
  python3 wiki-write.py --write-conventions /path/to/vault

Exit codes:
  0 — success or silent-skip (vault absent + --lint)
  1 — vault-absent on default-write, helper misuse, mutually-exclusive flags,
      missing required arg, reserved topic name, refuse-overwrite-no-force
  2 — vault path resolved but directory does not exist
  3 — slug computation produced empty string

Python 3.9 compatible (stdlib only). See docs/specs/wiki-write-conventions/.
"""

import argparse
import json
import os
import re
import sys
import tempfile
from datetime import date
from pathlib import Path
from typing import List, Optional, Tuple

# ---------------------------------------------------------------------------
# Shared primitives — imported from _wiki_common so wiki-write.py (CLI run
# as __main__) and _wiki_migrate.py (loaded as a helper module) share the
# SAME class object identities for exceptions and the SAME slug-transform
# constants. See ck-import-exception-identity for the underlying issue.
# ---------------------------------------------------------------------------

# Make `from _wiki_common import ...` work regardless of how this file is
# invoked: directly via shebang (__main__), imported as `wiki_write` after
# external sys.path manipulation (tests' first-try path), or loaded via
# importlib.util.spec_from_file_location (which does NOT add the script's
# directory to sys.path automatically — tests' fallback path).
_THIS_DIR = os.path.dirname(os.path.abspath(__file__))
if _THIS_DIR not in sys.path:
    sys.path.insert(0, _THIS_DIR)

from _wiki_common import (  # noqa: E402
    UNICODE_DASHES,
    SLUG_MAX_LEN,
    SLUG_VALID,
    RESERVED_TOPIC_NAMES,
    CATEGORIES,
    ENTITY_TYPES,
    STATUS_VALUES,
    PROJECT_INDEX_ORDER,
    PROJECT_TOPIC_ORDER,
    CONCEPT_ORDER,
    ENTITY_ORDER,
    slugify,
    humanize_topic_slug,
    emit_yaml_scalar,
    build_frontmatter,
    WikiWriteError,
    VaultNotConfiguredError,
    VaultNotConfiguredSkip,
    VaultPathMissingError,
    EmptySlugError,
    MutuallyExclusiveError,
    MissingRequiredArgError,
    ReservedTopicError,
    FileExistsNoForceError,
    MigrationCollisionError,
    MigrationJournalCorruptError,
)

VAULT_CONFIG_PATH = '~/.obsidian-wiki/config'


# ---------------------------------------------------------------------------
# Tag parsing (wiki-write.py-local — not shared with _wiki_migrate.py)
# ---------------------------------------------------------------------------

def parse_tags(raw: Optional[str]) -> List[str]:
    """Parse --tags 'a,b,c' into a normalized list.

    - Split on comma, strip whitespace per tag, drop empties.
    - Strip leading '#' (Obsidian inline-tag prefix).
    - Drop tags that don't match ^[a-z][a-z0-9-]*$ after normalization.
    """
    if not raw:
        return []
    out: List[str] = []
    valid = re.compile(r'^[a-z][a-z0-9-]*$')
    for piece in raw.split(','):
        tag = piece.strip()
        if not tag:
            continue
        if tag.startswith('#'):
            tag = tag[1:]
        tag = tag.lower()
        if valid.match(tag):
            out.append(tag)
    return out


# ---------------------------------------------------------------------------
# Frontmatter emission — build_frontmatter is imported from _wiki_common above.
# ---------------------------------------------------------------------------


# ---------------------------------------------------------------------------
# Vault discovery
# ---------------------------------------------------------------------------

def discover_vault(
    mode: str = 'lint',
    for_lint: bool = False,  # deprecated; use mode= instead
) -> Path:
    """Read ~/.obsidian-wiki/config, extract OBSIDIAN_VAULT_PATH, return absolute Path.

    ``mode`` controls vault-absent semantics:

      'lint'              -> VaultNotConfiguredSkip (exit 0, silent-skip)
      'migrate-dry-run'   -> VaultNotConfiguredSkip (exit 0, silent-skip)
      'migrate-resume'    -> VaultNotConfiguredSkip (exit 0, silent-skip)
      'write-conventions' -> VaultNotConfiguredError (exit 1)
      'default-write'     -> VaultNotConfiguredError (exit 1)
      'migrate-execute'   -> VaultNotConfiguredError (exit 1)

    Raises VaultPathMissingError (exit 2) when the config resolves to a path
    that does not exist on disk, regardless of mode.

    ``for_lint`` is a deprecated boolean keyword retained for backward
    compatibility only.  When True it forces mode to 'lint'.  New callers
    must pass ``mode=`` directly and leave ``for_lint`` at its default False.
    """
    _SKIP_MODES = frozenset({'lint', 'migrate-dry-run', 'migrate-resume'})
    _ERROR_MODES = frozenset({'write-conventions', 'default-write', 'migrate-execute'})
    _ALL_MODES = _SKIP_MODES | _ERROR_MODES

    # Back-compat: for_lint=True overrides mode to 'lint'.
    if for_lint:
        mode = 'lint'
    elif mode not in _ALL_MODES:
        raise ValueError(
            "discover_vault: unknown mode {0!r}; expected one of {1}".format(
                mode, sorted(_ALL_MODES)
            )
        )

    def _vault_absent_exc(detail: str) -> WikiWriteError:
        if mode in _SKIP_MODES:
            return VaultNotConfiguredSkip(
                "[wiki-write] skip: vault not configured{0}".format(
                    " ({0})".format(detail) if detail else ""
                )
            )
        return VaultNotConfiguredError(
            "[wiki-write] vault not configured{0}".format(
                "; run setup.sh in obsidian-wiki repo first" if not detail
                else ": {0}".format(detail)
            )
        )

    cfg_path = Path(os.path.expanduser(VAULT_CONFIG_PATH))
    if not cfg_path.exists():
        raise _vault_absent_exc("")
    vault_path: Optional[str] = None
    try:
        for line in cfg_path.read_text(encoding='utf-8').splitlines():
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            m = re.match(r'^OBSIDIAN_VAULT_PATH\s*=\s*"?([^"]+)"?\s*$', line)
            if m:
                vault_path = m.group(1).strip()
                break
    except OSError as e:
        raise _vault_absent_exc(str(e))
    if not vault_path:
        raise _vault_absent_exc(
            "OBSIDIAN_VAULT_PATH missing from {0}".format(cfg_path)
        )
    resolved = Path(os.path.expanduser(vault_path))
    if not resolved.is_dir():
        raise VaultPathMissingError(
            "[wiki-write] vault path does not exist: {0}; "
            "create the directory in Obsidian.app first".format(resolved)
        )
    return resolved


# ---------------------------------------------------------------------------
# Atomic write seam
# ---------------------------------------------------------------------------

def write_page(
    vault: Path,
    category: str,
    slug: str,
    topic: Optional[str],
    frontmatter_str: str,
    body_str: str,
    force: bool = False,
) -> str:
    """Compute target path, write frontmatter + body atomically. Returns abs path."""
    if category == 'project':
        proj_dir = vault / 'projects' / slug
        if topic:
            target = proj_dir / '{0}.md'.format(topic)
        else:
            target = proj_dir / 'index.md'
    elif category == 'concept':
        target = vault / 'concepts' / '{0}.md'.format(slug)
    elif category == 'entity':
        target = vault / 'entities' / '{0}.md'.format(slug)
    else:
        raise MissingRequiredArgError("unknown category: {0}".format(category))

    parent = target.parent
    parent.mkdir(parents=True, exist_ok=True)

    if os.path.exists(str(target)) and not force:
        raise FileExistsNoForceError(
            "[wiki-write] refusing to overwrite {0}; pass --force to replace".format(target)
        )

    content = frontmatter_str
    if body_str:
        if not body_str.endswith('\n'):
            body_str = body_str + '\n'
        content = content + body_str

    tmp = tempfile.NamedTemporaryFile(
        dir=str(parent),
        mode='w',
        delete=False,
        suffix='.tmp',
        encoding='utf-8',
    )
    tmp_name = tmp.name
    try:
        tmp.write(content)
        tmp.flush()
        os.fsync(tmp.fileno())
        tmp.close()
        os.replace(tmp_name, str(target))
    except BaseException:
        try:
            if os.path.exists(tmp_name):
                os.unlink(tmp_name)
        except OSError:
            pass
        raise
    return str(target.resolve())


# ---------------------------------------------------------------------------
# Default-write dispatcher
# ---------------------------------------------------------------------------

def _today_str() -> str:
    override = os.environ.get('DATE_OVERRIDE') or os.environ.get('WIKI_WRITE_DATE_OVERRIDE')
    if override:
        return override
    return date.today().isoformat()


def run_default_write(args: argparse.Namespace) -> int:
    if not args.category:
        raise MissingRequiredArgError("--category is required for default-write")
    if args.category not in CATEGORIES:
        raise MissingRequiredArgError(
            "--category must be one of {0}".format(', '.join(CATEGORIES))
        )
    if not args.title:
        raise MissingRequiredArgError("--title is required for default-write")
    if args.body is not None and args.body_stdin:
        raise MutuallyExclusiveError(
            "[wiki-write] pick one of --body or --body-stdin, not both"
        )

    slug = slugify(args.title)

    topic_slug: Optional[str] = None
    if args.topic:
        # Check raw input against reserved names BEFORE slugify (leading _ is
        # otherwise stripped by the kebab transform, hiding _convention etc.).
        raw_topic = args.topic.strip().lower()
        if raw_topic in RESERVED_TOPIC_NAMES:
            raise ReservedTopicError(
                "[wiki-write] topic name '{0}' is reserved".format(raw_topic)
            )
        topic_slug = slugify(args.topic)
        if topic_slug in RESERVED_TOPIC_NAMES:
            raise ReservedTopicError(
                "[wiki-write] topic name '{0}' is reserved".format(topic_slug)
            )

    # Body assembly
    body_str = ''
    if args.body is not None:
        body_str = args.body
    elif args.body_stdin:
        body_str = sys.stdin.read()

    # Frontmatter field assembly per category
    created = _today_str()
    tags = parse_tags(args.tags)
    aliases = args.alias if args.alias else []

    vault = discover_vault(mode='default-write')

    if args.category == 'project':
        if topic_slug:
            # Topic page
            topic_title = humanize_topic_slug(topic_slug)
            base_tags = ['project', 'topic']
            merged_tags = base_tags + [t for t in tags if t not in base_tags]
            fm = build_frontmatter(
                'project', has_topic=True,
                title=topic_title,
                created=created,
                parent=slug,
                summary=args.summary,
                tags=merged_tags,
                aliases=aliases if aliases else None,
            )
        else:
            # Index page
            status = args.status if args.status else 'active'
            base_tags = ['project']
            merged_tags = base_tags + [t for t in tags if t not in base_tags]
            fm = build_frontmatter(
                'project', has_topic=False,
                title=args.title,
                created=created,
                summary=args.summary,
                status=status,
                tags=merged_tags,
                aliases=aliases if aliases else None,
            )
    elif args.category == 'concept':
        base_tags = ['concept']
        merged_tags = base_tags + [t for t in tags if t not in base_tags]
        fm = build_frontmatter(
            'concept', has_topic=False,
            title=args.title,
            created=created,
            summary=args.summary,
            tags=merged_tags,
            aliases=aliases if aliases else None,
        )
    else:  # entity
        etype = args.entity_type if args.entity_type else 'other'
        if etype not in ENTITY_TYPES:
            raise MissingRequiredArgError(
                "--entity-type must be one of {0}".format(', '.join(ENTITY_TYPES))
            )
        base_tags = ['entity', etype]
        merged_tags = base_tags + [t for t in tags if t not in base_tags]
        fm = build_frontmatter(
            'entity', has_topic=False,
            title=args.title,
            created=created,
            type=etype,
            summary=args.summary,
            tags=merged_tags,
            aliases=aliases if aliases else None,
        )

    written = write_page(
        vault=vault,
        category=args.category,
        slug=slug,
        topic=topic_slug,
        frontmatter_str=fm,
        body_str=body_str,
        force=args.force,
    )
    print(written)
    return 0


# ---------------------------------------------------------------------------
# Lint mode
# ---------------------------------------------------------------------------

def _has_unicode_dash(name: str) -> bool:
    for d in UNICODE_DASHES:
        if d in name:
            return True
    return False


def _has_uppercase(name: str) -> bool:
    for ch in name:
        if ch.isascii() and ch.isupper():
            return True
    return False


def run_lint(args: argparse.Namespace) -> int:
    try:
        vault = discover_vault(mode='lint')
    except VaultNotConfiguredSkip as e:
        print(str(e.args[0]) if e.args else "[wiki-write] skip: vault not configured")
        return 0

    violations: List[Tuple[str, str]] = []
    compliant_count = 0

    # Walk projects/, concepts/, entities/
    for sub in ('projects', 'concepts', 'entities'):
        root = vault / sub
        if not root.is_dir():
            continue

        if sub == 'projects':
            # Each entry should be a folder containing index.md; flat .md is a violation
            for entry in sorted(root.iterdir()):
                # Skip underscore-prefixed names (Obsidian/convention reserved: _convention.md, _archives/, etc.)
                if entry.name.startswith('_') or entry.name.startswith('.'):
                    continue
                rel = '{0}/{1}'.format(sub, entry.name)
                if entry.is_file() and entry.suffix == '.md':
                    # Type 3a: flat file under projects/
                    violations.append((rel, 'type 3a: projects/<name>.md flat file (expected folder + index.md)'))
                    # Still apply name-level checks
                    if _has_unicode_dash(entry.name):
                        violations.append((rel, 'type 1: Unicode dash in filename'))
                    if _has_uppercase(entry.name):
                        violations.append((rel, 'type 2: mixed case in filename'))
                elif entry.is_dir():
                    # Folder under projects/ — must contain index.md
                    index_md = entry / 'index.md'
                    if not index_md.is_file():
                        violations.append((rel + '/', 'type 3b: projects/<name>/ folder missing index.md'))
                    else:
                        compliant_count += 1
                    # Apply name-level checks to the folder name itself
                    if _has_unicode_dash(entry.name):
                        violations.append((rel + '/', 'type 1: Unicode dash in filename'))
                    if _has_uppercase(entry.name):
                        violations.append((rel + '/', 'type 2: mixed case in filename'))
                    # Walk topic .md files inside
                    for topic_file in sorted(entry.glob('*.md')):
                        if topic_file.name == 'index.md':
                            continue
                        topic_rel = '{0}/{1}/{2}'.format(sub, entry.name, topic_file.name)
                        topic_compliant = True
                        if _has_unicode_dash(topic_file.name):
                            violations.append((topic_rel, 'type 1: Unicode dash in filename'))
                            topic_compliant = False
                        if _has_uppercase(topic_file.name):
                            violations.append((topic_rel, 'type 2: mixed case in filename'))
                            topic_compliant = False
                        if topic_compliant:
                            compliant_count += 1
        else:
            # concepts/ and entities/ — flat .md files
            for entry in sorted(root.iterdir()):
                if entry.name.startswith('_') or entry.name.startswith('.'):
                    continue
                if not (entry.is_file() and entry.suffix == '.md'):
                    continue
                rel = '{0}/{1}'.format(sub, entry.name)
                file_compliant = True
                if _has_unicode_dash(entry.name):
                    violations.append((rel, 'type 1: Unicode dash in filename'))
                    file_compliant = False
                if _has_uppercase(entry.name):
                    violations.append((rel, 'type 2: mixed case in filename'))
                    file_compliant = False
                if file_compliant:
                    compliant_count += 1

    print('ok   {0} pages compliant'.format(compliant_count))
    if violations:
        print('WARN {0} violations:'.format(len(violations)))
        for path, desc in violations:
            print('  {0} ({1})'.format(path, desc))
        print('To preview a fix: python3 ~/Projects/MonsterFlow/scripts/wiki-write.py --migrate --dry-run')
    return 0


# ---------------------------------------------------------------------------
# --write-conventions mode
# ---------------------------------------------------------------------------

CONVENTION_PROJECTS = """---
type: convention
title: Projects category convention
---

# Projects — quick reference

See `templates/wiki-conventions.md` in the MonsterFlow repo for the full conventions. This file is the per-category quick reference.

**Layout:** each project is a folder under `projects/`, named with a kebab-case slug. The folder contains `index.md` (the landing page) and optionally one `.md` per topic (e.g. `decisions.md`, `open-questions.md`).

**Slug rule:** lowercase ASCII, digits, and hyphens only. Unicode dashes (em-dash, en-dash, hyphens, minus-sign) are normalized to ASCII `-`. Max 80 chars.

**Frontmatter (index.md):** `title`, `created`, `summary`, `status` (active|paused|shipped|archived), `tags`. Optional: `aliases` — alternate names for Obsidian's quick-switcher; auto-added on migration to preserve old-name links.

**Frontmatter (topic.md):** `title`, `created`, `parent` (the project slug), `summary`, `tags`. Optional: `aliases` — same semantics as index.md.

Always write via `python3 ~/Projects/MonsterFlow/scripts/wiki-write.py --category project ...`.
"""

CONVENTION_CONCEPTS = """---
type: convention
title: Concepts category convention
---

# Concepts — quick reference

See `templates/wiki-conventions.md` in the MonsterFlow repo for the full conventions. This file is the per-category quick reference.

**Layout:** flat `.md` file under `concepts/`, named with a kebab-case slug.

**Slug rule:** lowercase ASCII, digits, and hyphens only. Unicode dashes normalized to ASCII `-`. Max 80 chars.

**Frontmatter:** `title`, `created`, `summary`, `tags`. Optional: `aliases` — alternate names for Obsidian's quick-switcher; auto-added on migration to preserve old-name links.

Always write via `python3 ~/Projects/MonsterFlow/scripts/wiki-write.py --category concept ...`.
"""

CONVENTION_ENTITIES = """---
type: convention
title: Entities category convention
---

# Entities — quick reference

See `templates/wiki-conventions.md` in the MonsterFlow repo for the full conventions. This file is the per-category quick reference.

**Layout:** flat `.md` file under `entities/`, named with a kebab-case slug.

**Slug rule:** lowercase ASCII, digits, and hyphens only. Unicode dashes normalized to ASCII `-`. Max 80 chars.

**Frontmatter:** `title`, `created`, `type` (person|organization|tool|other), `summary`, `tags`. Optional: `aliases` — alternate names for Obsidian's quick-switcher; auto-added on migration to preserve old-name links.

Always write via `python3 ~/Projects/MonsterFlow/scripts/wiki-write.py --category entity --entity-type <t> ...`.
"""


def _atomic_write_text(target: Path, content: str) -> None:
    parent = target.parent
    parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        import time
        backup = target.with_suffix(target.suffix + '.bak.{0}'.format(int(time.time())))
        try:
            target.replace(backup)
        except OSError:
            pass
    tmp = tempfile.NamedTemporaryFile(
        dir=str(parent), mode='w', delete=False, suffix='.tmp', encoding='utf-8',
    )
    tmp_name = tmp.name
    try:
        tmp.write(content)
        tmp.flush()
        os.fsync(tmp.fileno())
        tmp.close()
        os.replace(tmp_name, str(target))
    except BaseException:
        try:
            if os.path.exists(tmp_name):
                os.unlink(tmp_name)
        except OSError:
            pass
        raise


def run_write_conventions(vault_arg: str) -> int:
    vault = Path(os.path.expanduser(vault_arg)).resolve()
    if not vault.is_dir():
        raise VaultPathMissingError(
            "[wiki-write] vault path does not exist: {0}".format(vault)
        )
    targets = [
        (vault / 'projects' / '_convention.md', CONVENTION_PROJECTS),
        (vault / 'concepts' / '_convention.md', CONVENTION_CONCEPTS),
        (vault / 'entities' / '_convention.md', CONVENTION_ENTITIES),
    ]
    for target, content in targets:
        _atomic_write_text(target, content)
        print(str(target))
    return 0


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

class _MFArgumentParser(argparse.ArgumentParser):
    def error(self, message):
        # Override to emit exit code 1 (not argparse's default 2) and use our
        # stderr format.  Mutual-exclusion errors from add_mutually_exclusive_group
        # are also routed here so they surface through the same path.
        sys.stderr.write(str(message) + '\n')
        sys.exit(1)


def build_parser() -> argparse.ArgumentParser:
    p = _MFArgumentParser(
        prog='wiki-write.py',
        description='Deterministic Obsidian-vault page writer for MonsterFlow.',
        add_help=True,
    )
    p.add_argument('--category', choices=list(CATEGORIES))
    p.add_argument('--title')
    p.add_argument('--topic')
    p.add_argument('--summary')
    p.add_argument('--tags')
    p.add_argument('--entity-type', dest='entity_type',
                   choices=list(ENTITY_TYPES), default='other')
    p.add_argument('--status', choices=list(STATUS_VALUES), default='active')
    p.add_argument('--body')
    p.add_argument('--body-stdin', dest='body_stdin', action='store_true')
    p.add_argument('--force', action='store_true')
    p.add_argument('--alias', action='append', default=[],
                   help='Alternate name for Obsidian quick-switcher. May be repeated.')
    p.add_argument('--lint', action='store_true',
                   help='Scan the vault for convention violations; exit 0 regardless.')
    p.add_argument('--write-conventions', dest='write_conventions',
                   metavar='VAULT_PATH',
                   help='Emit the three per-category _convention.md files into VAULT_PATH.')

    # --migrate mode + modifiers
    # --dry-run and --resume are mutually exclusive; both require --migrate.
    p.add_argument('--migrate', action='store_true',
                   help='Scan the vault for convention violations and migrate them. '
                        'Two-step UX: use --dry-run first to preview, then run without it to execute.')
    _migrate_mx = p.add_mutually_exclusive_group()
    _migrate_mx.add_argument('--dry-run', dest='dry_run', action='store_true',
                             help='Preview the migration plan without writing any files. '
                                  'Requires --migrate. Mutually exclusive with --resume.')
    _migrate_mx.add_argument('--resume', action='store_true',
                             help='Resume an interrupted migration from the in-flight journal. '
                                  'Requires --migrate. Mutually exclusive with --dry-run.')
    p.add_argument('--force-overwrite', dest='force_overwrite', action='store_true',
                   help='Archive existing targets and overwrite on target-exists collisions. '
                        'Requires --migrate. Ignored when combined with --dry-run.')

    return p


def main(argv: Optional[List[str]] = None) -> int:
    parser = build_parser()
    # Note: _MFArgumentParser.error() calls sys.exit(1) directly, so the
    # WikiWriteError catch below is kept only for future custom argument actions.
    try:
        args = parser.parse_args(argv)
    except WikiWriteError as e:
        sys.stderr.write(str(e.args[0] if e.args else e) + '\n')
        return e.exit_code

    # Post-parse validation: --dry-run / --resume / --force-overwrite each require
    # --migrate.  argparse handles the --dry-run + --resume mutual exclusion natively
    # via add_mutually_exclusive_group().
    if getattr(args, 'dry_run', False) and not args.migrate:
        sys.stderr.write('--dry-run requires --migrate\n')
        return 1
    if getattr(args, 'resume', False) and not args.migrate:
        sys.stderr.write('--resume requires --migrate\n')
        return 1
    if getattr(args, 'force_overwrite', False) and not args.migrate:
        sys.stderr.write('--force-overwrite requires --migrate\n')
        return 1

    try:
        if args.lint:
            return run_lint(args)
        if args.write_conventions:
            return run_write_conventions(args.write_conventions)
        if args.migrate:
            # Deferred import — _wiki_migrate is only loaded when --migrate is used,
            # keeping lint/default-write/write-conventions startup cost zero.
            import importlib.util
            _here = Path(__file__).parent  # adjust if Path isn't already imported
            _spec = importlib.util.spec_from_file_location(
                "_wiki_migrate", str(_here / "_wiki_migrate.py")
            )
            _migrate = importlib.util.module_from_spec(_spec)
            _spec.loader.exec_module(_migrate)

            # Resolve vault via existing discover_vault (W1-A4 added mode param).
            # Vault-absent semantics differ by sub-mode:
            if args.dry_run:
                vault_mode = 'migrate-dry-run'
            elif args.resume:
                vault_mode = 'migrate-resume'
            else:
                vault_mode = 'migrate-execute'

            try:
                vault = discover_vault(mode=vault_mode)
            except VaultNotConfiguredSkip as e:
                print(f'[wiki-migrate] skip: {e}', file=sys.stderr)
                sys.exit(0)
            except VaultNotConfiguredError as e:
                print(f'[wiki-migrate] {e}', file=sys.stderr)
                sys.exit(1)

            # Dispatch
            sys.exit(_migrate.run(args, vault))
        return run_default_write(args)
    except WikiWriteError as e:
        msg = str(e.args[0]) if e.args else e.__class__.__name__
        sys.stderr.write(msg + '\n')
        return e.exit_code


if __name__ == '__main__':
    sys.exit(main())
