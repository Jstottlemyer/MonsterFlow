---
type: convention
---

# Wiki Write Conventions

This file is the single source of truth for how MonsterFlow writes pages into the
Obsidian vault. The executable rules live in `scripts/wiki-write.py` as Python
constants; this document is human-readable documentation derived from the same spec.
`install.sh` derives the per-category vault `_convention.md` files from this template.

---

## 1. Slug Rules

All page filenames and folder names are computed by a deterministic `slugify()` function.
The transform runs in order:

1. Strip whitespace, lowercase.
2. Normalize Unicode dashes to ASCII hyphen-minus. Replaced characters: em-dash (U+2014),
   en-dash (U+2013), figure-dash (U+2012), horizontal-bar (U+2015), minus-sign (U+2212),
   hyphen (U+2010), non-breaking hyphen (U+2011).
3. Replace spaces and forward slashes with hyphens.
4. Strip all characters that are not `[a-z0-9-]`.
5. Collapse consecutive hyphens to one.
6. Strip leading and trailing hyphens.
7. Truncate to 80 characters, then re-strip any trailing hyphen left by truncation.
8. Refuse (exit 3) if the result is empty.

### Example transforms

| Input title | Slug |
|---|---|
| `PatternCall — iOS Native Rewrite` | `patterncall-ios-native-rewrite` |
| `PatternCall—iOS` (no surrounding spaces) | `patterncall-ios` |
| `Foo—Bar—Baz` | `foo-bar-baz` |
| `foo  bar` (double space) | `foo-bar` |

The em-dash case without spaces (`PatternCall—iOS`) is worth noting explicitly: the
Unicode-dash normalization step fires before the kebab transform, so the adjacent letters
are separated by exactly one hyphen regardless of whether whitespace surrounded the dash.

Non-ASCII characters outside the Unicode-dash list (e.g., accented letters) are stripped
in step 4. `"Café Society"` becomes `caf-society`. Transliteration is a documented
limitation, deferred to a future update.

---

## 2. Layout Rules

Three top-level vault categories follow fixed layout conventions.

### `projects/`

Projects use a **folder + index pattern**. The project slug becomes a folder; the entry
page is always `index.md` inside that folder. Sub-topic pages sit alongside it.

```
<vault>/projects/<slug>/index.md       # project entry page
<vault>/projects/<slug>/<topic>.md     # sub-topic page (optional)
```

Examples:

- Title `"PatternCall iOS Native Rewrite"`, no topic:
  `projects/patterncall-ios-native-rewrite/index.md`
- Same project, topic `"decisions"`:
  `projects/patterncall-ios-native-rewrite/decisions.md`
- Title `"CosmicExplorer"`, topic `"open questions"`:
  `projects/cosmicexplorer/open-questions.md`

A flat `projects/<slug>.md` file (no folder) is a **lint violation** (type 3a). A project
folder missing `index.md` is also a lint violation (type 3b).

Topic names go through the same `slugify()` transform. Reserved topic names (`_convention`,
`log`, `_archives`, `_raw`) are refused with exit 1.

### `concepts/`

Concepts are **flat**: one file per concept, no folders.

```
<vault>/concepts/<slug>.md
```

Examples:
- `"Host Improv Pattern"` → `concepts/host-improv-pattern.md`
- `"Slug Normalization"` → `concepts/slug-normalization.md`

### `entities/`

Entities are **flat**: one file per entity, no folders.

```
<vault>/entities/<slug>.md
```

Examples:
- `"Tom Fox"` → `entities/tom-fox.md`
- `"Anthropic"` → `entities/anthropic.md`

---

## 3. Frontmatter Schemas

All frontmatter is emitted by `scripts/wiki-write.py` using `json.dumps()` for string
scalars (valid YAML subset; handles colons, quotes, and special characters without a YAML
library). Field order is fixed per category and deterministic.

### 3a. `projects/<slug>/index.md`

Fields in order: `title`, `created`, `summary`, `status`, `tags`.

`status` must be one of: `active`, `paused`, `shipped`, `archived`.

```yaml
---
title: "PatternCall iOS Native Rewrite"
created: "2026-05-15"
summary: "Native SwiftUI/SpriteKit rewrite of the PatternCall web app"
status: "active"
tags: ["project", "ios"]
---
```

### 3b. `projects/<slug>/<topic>.md`

Fields in order: `title`, `created`, `parent`, `summary`, `tags`.

`parent` is the project slug (not the display title). `title` is the humanized topic name
(e.g., slug `open-questions` becomes title `"Open questions"`; caller can override with
`--topic-title`).

```yaml
---
title: "Decisions"
created: "2026-05-15"
parent: "patterncall-ios-native-rewrite"
summary: "Key architecture decisions for the iOS native rewrite"
tags: ["project", "topic"]
---
```

### 3c. `concepts/<slug>.md`

Fields in order: `title`, `created`, `summary`, `tags`.

```yaml
---
title: "Host Improv Pattern"
created: "2026-05-15"
summary: "When models author negative-recovery paths despite explicit STOP instructions"
tags: ["concept"]
---
```

### 3d. `entities/<slug>.md`

Fields in order: `title`, `created`, `type`, `summary`, `tags`.

`type` must be one of: `person`, `organization`, `tool`, `other`.

```yaml
---
title: "Tom Fox"
created: "2026-05-15"
type: "person"
summary: "iOS engineer; key contact on PatternCall rewrite"
tags: ["entity", "person"]
---
```

---

## 4. Convention Files (`_convention.md`)

Each category folder in the vault contains a `_convention.md` file seeded by
`install.sh`. These files carry only `type: convention` in their frontmatter. The
`exclude: true` field is NOT used because Obsidian does not honor it natively. The actual
exclusion mechanism is the `_` prefix on the filename combined with the manual step in
Section 6 below.

The convention files are the cross-agent fallback: any agent that reads the vault before
writing will see the rules directly in the category folder.

---

## 5. Helper Invocation

Always use `scripts/wiki-write.py` for writes under `projects/`, `concepts/`, and
`entities/`. Do not compute the path freehand or make a separate Edit call to add body
content. The helper writes the complete file (frontmatter + body) atomically in one shot.

Short body (via `--body` flag):

```bash
python3 ~/Projects/MonsterFlow/scripts/wiki-write.py \
  --category project \
  --title "PatternCall iOS Native Rewrite" \
  --topic decisions \
  --summary "Key architecture decisions for the iOS native rewrite" \
  --tags "ios,native" \
  --body "## Decision (2026-05-15)\n\nChose SwiftUI over React Native because..."
```

Long body (via `--body-stdin`):

```bash
cat <<'EOF' | python3 ~/Projects/MonsterFlow/scripts/wiki-write.py \
  --category project \
  --title "PatternCall iOS Native Rewrite" \
  --topic decisions \
  --summary "..." --tags "ios" --body-stdin
## Decision (2026-05-15)

Long body content here...
EOF
```

`--body` and `--body-stdin` are mutually exclusive. Omitting both writes frontmatter with
an empty body (acceptable for stub `index.md` files that will be filled in Obsidian
directly, but explicit body content is preferred).

For entity pages, include `--entity-type {person,organization,tool,other}`. Example:
`--category entity --title "Anthropic" --entity-type organization`.

To overwrite an existing page, pass `--force`.

---

## 6. Lint

`scripts/wiki-write.py --lint` scans the vault and reports four violation types:

1. Unicode dash in filename (should have been slugified)
2. Mixed case in filename (any uppercase character in basename)
3a. `projects/<name>.md` flat file (should be a folder with `index.md`)
3b. `projects/<name>/` folder with no `index.md` inside

The command exits 0 regardless of violations (non-blocking). `/wrap` Phase 2c calls it
automatically after wiki-sync and surfaces any violations as a warning block in the wrap
summary.

To run manually:

```bash
python3 ~/Projects/MonsterFlow/scripts/wiki-write.py --lint
```

---

## 7. Obsidian Manual Step

After first vault open, add `**/_convention.md` to Obsidian Settings → Files & Links →
Excluded files to prevent convention files from appearing in graph view and search results.
