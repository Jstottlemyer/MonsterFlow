# Review — wiki-write-conventions

**Date:** 2026-05-15
**Dispatched:** gaps:opus, requirements:sonnet, scope:sonnet + codex-adversary (Codex CLI)
**Budget:** 3 + 1 codex (agent_budget=3 in ~/.config/monsterflow/config.json)
**Gate mode:** permissive (frontmatter)
**Verdict:** GO (architectural findings folded into V2; non-blocking findings tracked)

## Overall Health: Concerns → Resolved

V1 had three reviewer PASS WITH NOTES verdicts + a 23-finding Codex adversarial pass. Major architectural concerns converged on three surfaces: helper-doesn't-control-write-lifecycle, slug-regex-broken-for-em-dash-without-spaces, and migration-too-complex-for-one-spec. V2 rewrites all three inline; the spec is now smaller, sharper, and the carved-out migration work is tracked properly in BACKLOG.md as `wiki-write-migrate`.

## Before You Build (resolved inline in V2 — 0 open)

All four Critical findings from V1 have been addressed in V2:

1. **Helper didn't control write lifecycle** (Codex #1) → V2 helper accepts `--body <text>` or `--body-stdin`, writes the full file (frontmatter + body) atomically in one shot. No more "write empty + Edit-append" pattern. ~/CLAUDE.md instruction updated to say "do not follow with an Edit to add body content." AC #2 + AC #4 reflect this.

2. **Slug regex broke on em-dash without surrounding spaces** (gaps + requirements + Codex #2) → V2 adds a Unicode-dash normalization pre-pass to `slugify()` that replaces all 7 Unicode dash variants (em, en, figure-dash, horizontal-bar, minus-sign, Unicode hyphens) with ASCII hyphen-minus BEFORE the kebab transform. AC #3 + the 8 fixture cases in `## Data & State` pin both `"PatternCall — iOS Native Rewrite"` and `"PatternCall—iOS"` to correct slugs.

3. **Migration rollback story contradicted itself** (gaps + Codex #3) AND **wikilink rewriter under-specified** (gaps + Codex #5) AND **filesystem collision matrix missing** (Codex #4) → all three resolved by V2 carving migration out entirely. The migration design needs a proper resolver model (shortest-unique-path), durable journal for resume, and a collision matrix — none of which fit in tonight's scope. New BACKLOG entry: `wiki-write-migrate`.

4. **Non-blocking lint as sole enforcement is weak** (Codex #6) → resolved by V2 moving FULL WRITE LIFECYCLE into the helper. The helper IS the prevention; lint is the catch when the model bypasses the helper anyway. Lint stays non-blocking but the enforcement story is now stronger because the helper does more than just path-decision.

## Important But Non-Blocking (folded into V2 ACs)

- **Atomic-write test assertion was not pinned** (requirements:sonnet) → V2 AC #4 specifies the exact fault-injection mechanism: "monkey-patched `os.replace` raising `OSError`" + "asserts no partial file exists at the target path after the failure."
- **Lint zero-violation output format undefined** (requirements:sonnet) → V2 AC #6 pins the exact output: `ok   <N> pages compliant` line, no WARN block when violations == 0.
- **Vault-absent exit codes** (scope:sonnet) → V2 AC #2 + Edge Cases specify: `--lint` silent-skip exit 0 when vault absent; default-write exit 1 with the same message.
- **YAML escaping** (Codex #16) → V2 Data & State adds a YAML emission rule: `json.dumps()` for all string scalars (JSON is a valid YAML subset for scalars). No YAML library dependency.
- **Tag parsing edge cases** (Codex #17) → V2 Edge Cases documents: comma-split, strip-whitespace, drop-empty, strip-leading-`#`, validate against `^[a-z][a-z0-9-]*$`, drop invalid with a warning.
- **`_convention.md` polluting Obsidian graph** (Codex #22) → V2 AC #7 + Data & State specify `type: convention, exclude: true` frontmatter on the convention files so Obsidian's graph/search treats them as docs.
- **Backup accumulation** (Codex #23) → V2 Edge Cases adds `MONSTERFLOW_BACKUP_RETAIN_DAYS` (default 7) for install-time pruning.

## Observations (documented, not blocking)

- **TOCTOU on `--force` overwrite check** (gaps:opus) — V2 documents last-writer-wins for single-user vault. `fcntl.flock` deferred until concurrent contention is observed in practice.
- **Concurrent writes from two agent sessions** (Codex #15) — same deferral, same documentation.
- **`~/CLAUDE.md` doesn't reach Codex/Cursor sessions** (Codex #7) — V2 documents the vault `_convention.md` files as the cross-agent fallback. AGENTS.md integration tracked as future work.
- **Aliases-in-frontmatter** (Codex #13) — deferred; can be added in `wiki-write-migrate` since aliases are most useful during migration of old human-visible titles.
- **Flat concept/entity may age poorly** (Codex #11) — Q4 of /spec explicitly accepted this tradeoff; promotion-to-folder threshold is "if a concept genuinely grows, split into sibling concept pages with `related:` links." Documented.
- **`index.md` everywhere may fight Obsidian ergonomics** (Codex #12) — Q1 of /spec explicitly accepted this; Obsidian's sidebar shows the page's `title:` frontmatter field, not the filename. Documented.
- **Category naming singular CLI / plural directory** (Codex #9) — intentional; documented in V2 Scope section.
- **Topic slugging** (Codex #10) — V2 Edge Cases specifies: topic uses the same `slugify()` transform as project title; reserved topic names (`_convention`, `index`, `log`, `_archives`, `_raw`) refused.
- **Lint scope narrow** (Codex #21) — V2 keeps lint scoped to three violation types for v1. Other checks (spaces, non-ASCII in filenames, missing required frontmatter) can be added as the lint surface gets exercised in practice.

## Reviewer Verdicts

| Dimension | V1 Verdict | V2 Verdict (after revision) |
|-----------|-----------|------------------------------|
| Gaps (opus) | PASS WITH NOTES | PASS (architectural gaps folded inline; migration carved out) |
| Requirements (sonnet) | PASS WITH NOTES | PASS (contract ambiguities pinned in AC #3 / #4 / #6) |
| Scope (sonnet) | PASS WITH NOTES | PASS (carve-out recommendation accepted; helper-write-lifecycle simplification accepted) |
| Codex Adversarial | 23 findings (6 High-Risk, 7 Design Gaps, 8 Failure Modes) | 6 architectural folded inline; 11 contract/test/edge folded inline into ACs and Edge Cases; 6 deferred-as-documented (TOCTOU, concurrent writes, AGENTS.md, aliases, flat-ages-poorly, index.md ergonomics) |

## Conflicts Resolved

- **gaps:opus wanted journal+rollback on `--migrate`; scope:sonnet wanted to carve `--migrate` out entirely.** Both are reasonable strategies for the same problem; scope's path was simpler and matched Codex's #3/#4/#5 findings about migration's inherent complexity. Accepted scope's recommendation; carved.
- **Codex #14 (no policy for existing valid files — `--force` is too blunt) vs V1 spec's simple `--force` overwrite.** V2 keeps `--force` as the v1 escape hatch with last-writer-wins documented. Multi-mode write (`create / append-section / update-frontmatter-only / replace-body`) is a real follow-up but not blocking v1; documented as future work in Edge Cases.

## Codex Adversarial View

Codex's 23-finding pass was the highest-value contribution of this review — it identified the write-lifecycle gap (#1) that all three Claude reviewers missed, and surfaced the migration-complexity matrix (#3, #4, #5) that confirmed scope's carve-out recommendation. Worth noting: Codex's findings #11-23 included several that V1 had genuinely overlooked but that don't block v1 (YAML escaping, backup retention, category-naming consistency, topic-slug edge cases, `_convention.md` polluting graph) — these are now folded into V2's ACs and Edge Cases rather than left as known gaps.

---

**V2 approved for /blueprint.** All architectural findings resolved inline; non-blocking findings tracked as `wiki-write-migrate` follow-up spec OR documented as v1 carve-outs in Edge Cases.

[AUTORUN] Proceeding to /blueprint.
