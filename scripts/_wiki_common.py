"""
_wiki_common.py — Shared primitives for the MonsterFlow Obsidian-wiki tooling.

This module is the SINGLE source of truth for symbols that must be shared
between `wiki-write.py` (the CLI, run as `__main__`) and `_wiki_migrate.py`
(a helper module loaded by wiki-write.py at runtime).

Why a separate module:
  `wiki-write.py` has a hyphen in its filename, so `import wiki-write` is not
  a valid Python identifier. To load it from a sibling module the only
  portable option is `importlib.util.spec_from_file_location`. Doing that
  produces a Module object whose class objects have a DIFFERENT `id()` than
  the same classes evaluated in the `__main__` execution of wiki-write.py.

  Consequence: `except MigrationCollisionError` in `__main__` does NOT catch
  raises from the importlib-loaded copy. The two `MigrationCollisionError`
  classes are unrelated types.

Fix: keep the shared types in a normal, hyphen-free, importable module name
(`_wiki_common`). Both `wiki-write.py` and `_wiki_migrate.py` import from
THIS module, so they share one class object identity.

Python 3.9 compatible, stdlib only.
"""

import json
import re
from typing import List, Optional

# ---------------------------------------------------------------------------
# Slug-transform constants
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

# Frontmatter key ordering per category / page-kind
PROJECT_INDEX_ORDER = ['title', 'created', 'summary', 'status', 'tags', 'aliases']
PROJECT_TOPIC_ORDER = ['title', 'created', 'parent', 'summary', 'tags', 'aliases']
CONCEPT_ORDER = ['title', 'created', 'summary', 'tags', 'aliases']
ENTITY_ORDER = ['title', 'created', 'type', 'summary', 'tags', 'aliases']


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


# --- New exception classes added for the wiki-write-migrate feature -------
# Per spec V4 AC #2 (collapsed), both new classes return CLI exit 1 — but
# they remain distinct INTERNAL types so callers / tests can match by name
# and the stderr-message contract (CG-1) can distinguish the cause.

class MigrationCollisionError(WikiWriteError):
    """--migrate detected target-exists collisions and was not given
    --force-overwrite. Internally distinct from FileExistsNoForceError so
    --migrate / default-write code paths can be told apart, even though
    both surface as CLI exit 1."""
    exit_code = 1


class MigrationJournalCorruptError(WikiWriteError):
    """--migrate --resume found a journal that is not valid JSONL, has rows
    missing required fields, or carries an unknown schema_version. User
    must investigate manually before re-running."""
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


# ---------------------------------------------------------------------------
# YAML scalar emission
# ---------------------------------------------------------------------------

def emit_yaml_scalar(value):
    """JSON-compatible YAML emission.

    - None: returns None (caller omits the key entirely, per ck-yaml-omit)
    - list of strings: flow style [json.dumps(x), ...] joined with ', '
    - str: collapse internal whitespace for one-liners is caller's job;
           here we just json.dumps()
    - other: json.dumps()
    """
    if value is None:
        return None
    if isinstance(value, list):
        if len(value) == 0:
            return '[]'
        items = [json.dumps(x, ensure_ascii=False) for x in value]
        return '[' + ', '.join(items) + ']'
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    return json.dumps(value, ensure_ascii=False)


# ---------------------------------------------------------------------------
# Frontmatter assembly (shared between wiki-write.py and _wiki_migrate.py
# alias-injection step — single source of truth per ck-import-exception-identity)
# ---------------------------------------------------------------------------

def _field_order_for(category: str, has_topic: bool):
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
    `aliases` is emitted block-style; other list fields stay flow-style.
    """
    order = _field_order_for(category, has_topic)
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
            continue
        if key == 'aliases':
            if not isinstance(value, list) or len(value) == 0:
                continue
            lines.append('aliases:')
            for alias in value:
                lines.append('  - {0}'.format(json.dumps(alias, ensure_ascii=False)))
            continue
        rendered = emit_yaml_scalar(value)
        if rendered is None:
            continue
        lines.append('{0}: {1}'.format(key, rendered))
    lines.append('---')
    lines.append('')
    return '\n'.join(lines) + '\n'


__all__ = [
    # constants
    'UNICODE_DASHES',
    'SLUG_MAX_LEN',
    'SLUG_VALID',
    'RESERVED_TOPIC_NAMES',
    'CATEGORIES',
    'ENTITY_TYPES',
    'STATUS_VALUES',
    'PROJECT_INDEX_ORDER',
    'PROJECT_TOPIC_ORDER',
    'CONCEPT_ORDER',
    'ENTITY_ORDER',
    # helpers
    'slugify',
    'humanize_topic_slug',
    'emit_yaml_scalar',
    'build_frontmatter',
    # exceptions
    'WikiWriteError',
    'VaultNotConfiguredError',
    'VaultNotConfiguredSkip',
    'VaultPathMissingError',
    'EmptySlugError',
    'MutuallyExclusiveError',
    'MissingRequiredArgError',
    'ReservedTopicError',
    'FileExistsNoForceError',
    'MigrationCollisionError',
    'MigrationJournalCorruptError',
]
