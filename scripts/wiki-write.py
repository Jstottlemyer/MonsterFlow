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
# Module-level constants
# ---------------------------------------------------------------------------

UNICODE_DASHES = ['‐', '‑', '‒', '–', '—', '―', '−']
# U+2010 hyphen, U+2011 non-breaking hyphen, U+2012 figure-dash, U+2013 en-dash,
# U+2014 em-dash, U+2015 horizontal-bar, U+2212 minus-sign

SLUG_MAX_LEN = 80
SLUG_VALID = re.compile(r'^[a-z0-9][a-z0-9-]{0,79}$')

RESERVED_TOPIC_NAMES = {'_convention', 'index', 'log', '_archives', '_raw'}

CATEGORIES = ('project', 'concept', 'entity')
ENTITY_TYPES = ('person', 'organization', 'tool', 'other')
STATUS_VALUES = ('active', 'paused', 'shipped', 'archived')

PROJECT_INDEX_ORDER = ['title', 'created', 'summary', 'status', 'tags']
PROJECT_TOPIC_ORDER = ['title', 'created', 'parent', 'summary', 'tags']
CONCEPT_ORDER = ['title', 'created', 'summary', 'tags']
ENTITY_ORDER = ['title', 'created', 'type', 'summary', 'tags']

VAULT_CONFIG_PATH = '~/.obsidian-wiki/config'


# ---------------------------------------------------------------------------
# Exception hierarchy (Python 3.9 syntax — no parenthesized inheritance)
# ---------------------------------------------------------------------------

class WikiWriteError(Exception):
    exit_code = 1


class VaultNotConfiguredError(WikiWriteError):
    exit_code = 1  # default-write path


class VaultNotConfiguredSkip(WikiWriteError):
    exit_code = 0  # --lint silent-skip path (per ck-vault-not-cfg)


class VaultPathMissingError(WikiWriteError):
    exit_code = 2


class EmptySlugError(WikiWriteError, ValueError):
    exit_code = 3


class MutuallyExclusiveError(WikiWriteError):
    exit_code = 1


class MissingRequiredArgError(WikiWriteError):
    exit_code = 1


class ReservedTopicError(WikiWriteError):
    exit_code = 1


class FileExistsNoForceError(WikiWriteError):
    exit_code = 1


# ---------------------------------------------------------------------------
# Slug + title helpers
# ---------------------------------------------------------------------------

def slugify(title: str) -> str:
    """Deterministic slug transform per spec Data & State section.

    See spec fixture cases — all 8 must pass.
    """
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
    # 7. Truncate to 80 chars, then re-strip trailing hyphen
    t = t[:SLUG_MAX_LEN].rstrip('-')
    # 8. Validate; refuse empty
    if not t:
        raise EmptySlugError(
            "slug computation produced empty string; pick a different title"
        )
    return t


def humanize_topic_slug(slug: str) -> str:
    """For auto-derived topic titles when --topic <slug> has no explicit title.

    Split on '-', join with space, capitalize first word only.
    'open-questions' -> 'Open questions'.
    """
    words = slug.split('-')
    if not words:
        return slug
    first = words[0].capitalize() if words[0] else ''
    rest = words[1:]
    return ' '.join([first] + rest).strip()


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
# Frontmatter emission
# ---------------------------------------------------------------------------

def emit_yaml_scalar(value) -> str:
    """JSON-compatible YAML emission.

    - None: returns None (caller omits the key entirely, per ck-yaml-omit)
    - list of strings: flow style [json.dumps(x), ...] joined with ', '
    - str: collapse internal whitespace for one-liners is caller's job;
           here we just json.dumps()
    - other: json.dumps()
    """
    if value is None:
        return None  # type: ignore[return-value]
    if isinstance(value, list):
        if len(value) == 0:
            return '[]'
        items = [json.dumps(x, ensure_ascii=False) for x in value]
        return '[' + ', '.join(items) + ']'
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    return json.dumps(value, ensure_ascii=False)


def _field_order_for(category: str, has_topic: bool) -> List[str]:
    if category == 'project':
        return PROJECT_TOPIC_ORDER if has_topic else PROJECT_INDEX_ORDER
    if category == 'concept':
        return CONCEPT_ORDER
    if category == 'entity':
        return ENTITY_ORDER
    raise MissingRequiredArgError("unknown category: {0}".format(category))


def build_frontmatter(category: str, has_topic: bool, **fields) -> str:
    """Build the complete frontmatter block (including leading + trailing ---).

    Fields whose value is None are omitted entirely (per ck-yaml-omit).
    Summary values are whitespace-collapsed to a single line before emission.
    """
    order = _field_order_for(category, has_topic)
    # Collapse summary whitespace if present
    if 'summary' in fields and isinstance(fields.get('summary'), str):
        fields['summary'] = re.sub(r'\s+', ' ', fields['summary']).strip()
        if not fields['summary']:
            fields['summary'] = None

    lines = ['---']
    for key in order:
        if key not in fields:
            continue
        value = fields[key]
        if value is None:
            continue  # omit key entirely
        rendered = emit_yaml_scalar(value)
        if rendered is None:
            continue
        lines.append('{0}: {1}'.format(key, rendered))
    lines.append('---')
    lines.append('')  # trailing newline after frontmatter block
    return '\n'.join(lines) + '\n'


# ---------------------------------------------------------------------------
# Vault discovery
# ---------------------------------------------------------------------------

def discover_vault(for_lint: bool = False) -> Path:
    """Read ~/.obsidian-wiki/config, extract OBSIDIAN_VAULT_PATH, return absolute Path.

    Raises VaultNotConfiguredError (default-write) or VaultNotConfiguredSkip (--lint)
    when config is absent. Raises VaultPathMissingError when the resolved path
    does not exist on disk.
    """
    cfg_path = Path(os.path.expanduser(VAULT_CONFIG_PATH))
    if not cfg_path.exists():
        if for_lint:
            raise VaultNotConfiguredSkip(
                "[wiki-write] skip: vault not configured"
            )
        raise VaultNotConfiguredError(
            "[wiki-write] vault not configured; run setup.sh in obsidian-wiki repo first"
        )
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
        if for_lint:
            raise VaultNotConfiguredSkip(
                "[wiki-write] skip: vault not configured ({0})".format(e)
            )
        raise VaultNotConfiguredError(
            "[wiki-write] vault config unreadable: {0}".format(e)
        )
    if not vault_path:
        if for_lint:
            raise VaultNotConfiguredSkip("[wiki-write] skip: vault not configured")
        raise VaultNotConfiguredError(
            "[wiki-write] OBSIDIAN_VAULT_PATH missing from {0}".format(cfg_path)
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
    override = os.environ.get('WIKI_WRITE_DATE_OVERRIDE')
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

    vault = discover_vault(for_lint=False)

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
        vault = discover_vault(for_lint=True)
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

**Frontmatter (index.md):** `title`, `created`, `summary`, `status` (active|paused|shipped|archived), `tags`.

**Frontmatter (topic.md):** `title`, `created`, `parent` (the project slug), `summary`, `tags`.

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

**Frontmatter:** `title`, `created`, `summary`, `tags`.

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

**Frontmatter:** `title`, `created`, `type` (person|organization|tool|other), `summary`, `tags`.

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
        raise MissingRequiredArgError("[wiki-write] {0}".format(message))


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
    p.add_argument('--lint', action='store_true',
                   help='Scan the vault for convention violations; exit 0 regardless.')
    p.add_argument('--write-conventions', dest='write_conventions',
                   metavar='VAULT_PATH',
                   help='Emit the three per-category _convention.md files into VAULT_PATH.')
    return p


def main(argv: Optional[List[str]] = None) -> int:
    parser = build_parser()
    try:
        args = parser.parse_args(argv)
    except WikiWriteError as e:
        sys.stderr.write(str(e.args[0] if e.args else e) + '\n')
        return e.exit_code

    try:
        if args.lint:
            return run_lint(args)
        if args.write_conventions:
            return run_write_conventions(args.write_conventions)
        return run_default_write(args)
    except WikiWriteError as e:
        msg = str(e.args[0]) if e.args else e.__class__.__name__
        sys.stderr.write(msg + '\n')
        return e.exit_code


if __name__ == '__main__':
    sys.exit(main())
