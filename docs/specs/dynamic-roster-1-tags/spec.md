---
name: dynamic-roster-1-tags
description: Slice 1 of dynamic-roster-per-gate — tag schema + fit_tags backfill on 19 existing personas. Foundation for content-aware persona selection.
created: 2026-05-08
status: draft
session_roster: defaults-only (no constitution)
gate_mode: permissive
gate_max_recycles: 2
tags: [data, integration, security]
parent_spec: dynamic-roster-per-gate
slice: 1-of-5
---

# Dynamic Roster — Slice 1: Tag Schema + fit_tags Backfill

**Created:** 2026-05-08
**Constitution:** none — session roster only
**Confidence:** Scope 0.95 / UX 0.92 / Data 0.95 / Integration 0.92 / Edges 0.92 / Acceptance 0.95
**Parent spec:** `docs/specs/dynamic-roster-per-gate/spec.md` — this slice is one of five carved when run #8 of the parent's auto-build exhausted retries due to surface-area scope.

> Session roster only — run /kickoff later to make this a persistent constitution.

## Summary

Define the **closed-enum tag vocabulary** + add `fit_tags:` frontmatter to all 19 existing pipeline personas. This is the smallest shippable slice of `dynamic-roster-per-gate` — a metadata-only foundation that future slices (`_tag_baseline.py`, `_tier_assign.py`, command/autorun wiring, dashboard) build on.

**No behavior changes in this slice.** Resolver, dispatch, and gate scripts are unchanged. The only consumers of `fit_tags:` after this slice ships are the schema validator + the persona-fit-tags integrity test. The full content-aware selection feature lights up when slice 3 (`dynamic-roster-3-tier`) ships.

**Why slice this way:** the parent `dynamic-roster-per-gate` spec failed auto-build with "no commits since pre-build SHA" — /build agents couldn't synthesize a coherent commit across 5+ new Python scripts, 19 persona edits, schema files, command rewrites, autorun integration, and dashboard work in 3 retries. Slicing by responsibility lets each slice fit a single /build wave: this slice is **purely additive metadata + one schema + one validation test** (~150 LoC + 19 small file edits). Mechanical scope; high probability of clean auto-build.

## Backlog Routing

| # | Item | Source | Routing | Reasoning |
|---|------|--------|---------|-----------|
| 1 | `dynamic-roster-per-gate` parent spec | docs/specs/ | (b) Stays | Parent overview; this slice supersedes its first ~150 LoC of scope. Subsequent slices supersede the rest. |
| 2 | `dynamic-roster-2-baseline` (slice 2) | (carved from parent) | (c) New spec later | Will spec after slice 1 ships. Depends on this slice's tag enum. |
| 3 | `dynamic-roster-3-tier` (slice 3) | (carved from parent) | (c) New spec later | Tier-assignment logic. Depends on slice 2 baseline. |
| 4 | `dynamic-roster-4-dispatch` (slice 4) | (carved from parent) | (c) New spec later | Command + autorun wiring. Depends on slice 3 resolver. |
| 5 | `dynamic-roster-5-dashboard` (slice 5) | (carved from parent) | (c) New spec later | Tier-mix column. Depends on slice 3+4 emitting `selection.json` with `tier` field. |
| 6 | All other BACKLOG items | BACKLOG.md | (b) Stays | Unrelated. |

## Scope

**In scope (entire slice):**

- **Tag enum** — closed list, single source of truth in `schemas/tag-enum.schema.json`:
  ```
  security, data, api, ux, integration, scalability, docs, refactor, migration
  ```
  9 values. Multi-value (array) wherever used.

- **`spec-frontmatter.schema.json`** (NEW or extension) — declares optional `tags:` array field where each item is from the tag enum. JSON Schema 2020-12, `additionalProperties: false`. **Optional in this slice** (no enforcement gate); future slices make it required for new specs.

- **`persona-frontmatter.schema.json`** (NEW) — declares optional `fit_tags:` array field where each item is from the tag enum. Same closed-enum constraint. Optional for now; slice 3 makes it required for personas dispatched at gates.

- **Backfill `fit_tags:` into all 19 existing personas** — frontmatter-only edits. One additive line per file. Proposed mappings (LLM-proposed in this slice's /build wave; validate against persona purpose):

  **`personas/review/` (6):**
  - `requirements.md` → `fit_tags: [docs, integration]`
  - `gaps.md` → `fit_tags: [docs, scalability]`
  - `ambiguity.md` → `fit_tags: [docs, ux]`
  - `feasibility.md` → `fit_tags: [scalability, integration]`
  - `scope.md` → `fit_tags: [docs, refactor]`
  - `stakeholders.md` → `fit_tags: [ux, docs]`

  **`personas/plan/` (7):**
  - `api.md` → `fit_tags: [api, integration]`
  - `data-model.md` → `fit_tags: [data, migration]`
  - `ux.md` → `fit_tags: [ux]`
  - `scalability.md` → `fit_tags: [scalability]`
  - `security.md` → `fit_tags: [security]`
  - `integration.md` → `fit_tags: [integration]`
  - `wave-sequencer.md` → `fit_tags: [refactor, integration]`

  **`personas/check/` (6):**
  - `completeness.md` → `fit_tags: [docs]`
  - `sequencing.md` → `fit_tags: [refactor, integration]`
  - `risk.md` → `fit_tags: [scalability, security, integration]`
  - `scope-discipline.md` → `fit_tags: [docs, refactor]`
  - `security-architect.md` → `fit_tags: [security]`
  - `testability.md` → `fit_tags: [refactor]`

- **`tests/test-persona-fit-tags.sh`** (NEW) — validates: (a) every persona file under `personas/{review,plan,check}/` has `fit_tags:` frontmatter, (b) every `fit_tags:` value is from the closed enum (no orphan values), (c) no persona has `fit_tags: []` (must declare at least one). Bash test, ≤80 LoC. Adds to `tests/run-tests.sh`.

- **CHANGELOG entry** — `[Unreleased]` block: "feat(personas): tag-enum schema + fit_tags backfill on 19 pipeline personas (slice 1 of dynamic-roster-per-gate)".

**Out of scope (deferred to subsequent slices):**

- `_tag_baseline.py` regex + NFKC + code-fence exclusion — slice 2.
- `_tier_assign.py` + tier rule + security_floor enforcement — slice 3.
- `_persona_score.py` (`fit_count × load_bearing_rate`) — slice 3.
- `scripts/resolve-personas.sh` extension (tag intersection + tier output) — slice 3.
- Command-md updates (Phase 0b dispatch wiring) — slice 4.
- `scripts/autorun/spec-review.sh` etc. (tier suffix parsing) — slice 4.
- `dashboard/index.html` tier-mix column — slice 5.
- `/spec` Phase 3 LLM-propose-user-confirm tag inference — slice 2 (paired with `_tag_baseline.py` since that's where the union math lives).
- Any test fixture exercising the resolver / selection — slice 3+ where the resolver actually consumes `fit_tags:`.

## Approach

**Chosen approach:** metadata-only additive slice. Three new files (`tag-enum.schema.json`, `spec-frontmatter.schema.json`, `persona-frontmatter.schema.json`) + 19 small frontmatter edits + one validation test. No code paths read `fit_tags:` yet — the field is dormant data until slice 3 lights it up.

**Rationale:**

- **Why metadata-only first:** the parent spec's run #8 failed auto-build because the agents couldn't reason coherently across active code paths AND new schemas AND backfills AND command rewrites. A slice that introduces ONLY metadata + schemas has zero behavior risk and zero cross-file logic — purely declarative additions.
- **Why include the validation test in this slice:** without `tests/test-persona-fit-tags.sh`, a typo in any of the 19 backfills wouldn't be caught until slice 3 tries to consume the data. The test is cheap (~80 LoC, no fixtures, no claude-p calls) and locks the schema before downstream work depends on it.
- **Why propose specific tag mappings up-front:** the /build wave shouldn't have to invent persona-tag fit; that's design judgment. The mappings are committed in the spec so /build's job is mechanical (transcribe to frontmatter), not architectural.

**Alternatives considered:**

- **Bigger first slice (schema + `_tag_baseline.py` + backfill):** rejected — `_tag_baseline.py` has real logic (regex + NFKC + code-fence carve-out + adversarial fixtures). Adding it doubles the surface area; the parent spec already proved that's too much.
- **Skip the validation test in slice 1:** rejected — without it, slice 3's resolver would be the first place a typo surfaces, and at that point we'd be debugging the resolver instead of the data.
- **Auto-generate persona mappings via LLM at /build time:** rejected — non-deterministic; different /build runs would produce different mappings; couldn't review.

## Roster Changes

No roster changes. Current 19-persona roster is what we're backfilling. The build needs:
- `data-model` — schema design (3 small JSON Schema files)
- `integration` — backfill mechanics across persona files
- `testability` — `tests/test-persona-fit-tags.sh`

## UX / User Flow

**Author / new persona authoring:**
```yaml
# personas/<gate>/<new-persona>.md
---
name: <persona-name>
fit_tags: [security, data]   # required at slice 3+; optional in slice 1
---
```

**Validation invocation (manual or via tests/run-tests.sh):**
```
$ bash tests/test-persona-fit-tags.sh
PASS test_all_personas_have_fit_tags
PASS test_all_fit_tags_are_valid_enum_values
PASS test_no_empty_fit_tags
Results: 3 passed, 0 failed
```

**No runtime behavior changes** — `/spec`, `/spec-review`, `/plan`, `/check`, `/build`, `/autorun` all behave exactly as before this slice ships. The personas just have an extra metadata line that nothing reads yet.

## Data & State

### `schemas/tag-enum.schema.json` (NEW)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://monsterflow.dev/schemas/tag-enum.schema.json",
  "title": "MonsterFlow tag enum",
  "type": "string",
  "enum": ["security", "data", "api", "ux", "integration", "scalability", "docs", "refactor", "migration"]
}
```

### `schemas/spec-frontmatter.schema.json` (NEW or extension)

Adds optional `tags:` field referencing `tag-enum.schema.json`:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://monsterflow.dev/schemas/spec-frontmatter.schema.json",
  "title": "MonsterFlow spec.md frontmatter",
  "type": "object",
  "properties": {
    "tags": {
      "type": "array",
      "items": { "$ref": "tag-enum.schema.json" },
      "uniqueItems": true,
      "default": []
    }
  },
  "additionalProperties": true
}
```

(`additionalProperties: true` for v1 — other frontmatter keys aren't yet schema-validated. Tightened in later slices.)

### `schemas/persona-frontmatter.schema.json` (NEW)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://monsterflow.dev/schemas/persona-frontmatter.schema.json",
  "title": "MonsterFlow persona.md frontmatter",
  "type": "object",
  "properties": {
    "fit_tags": {
      "type": "array",
      "items": { "$ref": "tag-enum.schema.json" },
      "uniqueItems": true,
      "minItems": 1
    }
  },
  "required": ["fit_tags"],
  "additionalProperties": true
}
```

`fit_tags` is REQUIRED + minItems:1 — once slice 1 ships, every persona must declare at least one fit tag. This is the integrity gate.

### Persona file diff (19 files, same shape)

Before:
```yaml
---
name: security-architect
description: Adversarial security review of plans
---
```

After:
```yaml
---
name: security-architect
fit_tags: [security]
description: Adversarial security review of plans
---
```

One added line per file. Description and other fields untouched.

## Integration

### Files touched

**Schemas (created in slice 1):**
- `schemas/tag-enum.schema.json` (NEW)
- `schemas/spec-frontmatter.schema.json` (NEW or extension)
- `schemas/persona-frontmatter.schema.json` (NEW)

**Persona backfill (19 files):**
- `personas/review/{requirements,gaps,ambiguity,feasibility,scope,stakeholders}.md` — add `fit_tags:` line
- `personas/plan/{api,data-model,ux,scalability,security,integration,wave-sequencer}.md` — same
- `personas/check/{completeness,sequencing,risk,scope-discipline,security-architect,testability}.md` — same

**Test (NEW):**
- `tests/test-persona-fit-tags.sh` — validation harness (≤80 LoC bash)
- `tests/run-tests.sh` — wire up the new test (one line: `run_test "persona-fit-tags"`)

**Docs:**
- `CHANGELOG.md` — `[Unreleased]` entry

### Dependencies

**No new external dependencies.** Test uses bash + `python3 -c` for JSON-Schema validation against the enum.

**Existing infrastructure (no changes in this slice):**
- `scripts/resolve-personas.sh` — unchanged.
- `scripts/autorun/{spec-review,plan,check}.sh` — unchanged.
- `commands/{spec,spec-review,plan,check,build}.md` — unchanged.
- All 19 personas' BODY content — unchanged. Only frontmatter gets a new line.

## Edge Cases

1. **Persona file has no frontmatter at all** (e.g., a draft persona without `---` block) → test fails with "no frontmatter found at <file>". Current 19 personas all have frontmatter; this is a future-proofing assertion.

2. **`fit_tags:` listed but empty** (`fit_tags: []`) → schema rejects (`minItems: 1`); test fails with clear message.

3. **`fit_tags:` includes value not in enum** (typo, e.g., `securty`) → schema rejects; test fails listing the offender + valid enum.

4. **`fit_tags:` has duplicate values** (`[security, security]`) → schema rejects (`uniqueItems: true`); test fails.

5. **YAML frontmatter parsed inconsistently** — test uses `python3 yaml.safe_load` (no PyYAML dep — falls back to `ast`-style parser if PyYAML absent; bash 3.2 + system Python 3.9 compatible).

6. **New persona added after slice 1** — `fit_tags:` is required; CI/test run on PR would fail until added. Acceptable enforcement gate.

7. **Spec.md authors don't add `tags:` yet** — slice 1 makes it OPTIONAL. No existing specs need editing. Slice 2+ makes it required for NEW specs but grandfathers existing ones.

8. **Backfilled `fit_tags:` are wrong for a persona** (judgment call) — fix in a follow-up commit; test only validates schema correctness, not domain accuracy. Slice 3's resolver dispatch will surface bad mappings empirically.

## Acceptance Criteria

A1. **Tag enum file exists at `schemas/tag-enum.schema.json`** with exactly 9 values: `security, data, api, ux, integration, scalability, docs, refactor, migration`. Validates as JSON Schema 2020-12.

A2. **`schemas/spec-frontmatter.schema.json`** declares optional `tags:` field referencing `tag-enum.schema.json`, with `uniqueItems: true`, `default: []`. Schema is valid JSON Schema.

A3. **`schemas/persona-frontmatter.schema.json`** declares REQUIRED `fit_tags:` field, `minItems: 1`, `uniqueItems: true`, items referencing `tag-enum.schema.json`. Schema is valid JSON Schema.

A4. **All 19 existing personas have `fit_tags:` frontmatter** matching the proposed mappings in §Scope above. Frontmatter parseable as YAML; values are from the closed enum.

A5. **`tests/test-persona-fit-tags.sh` exists** and asserts:
- (a) Every `personas/{review,plan,check}/*.md` file has frontmatter with `fit_tags:` present
- (b) Every `fit_tags:` value is in the closed enum (no orphan values)
- (c) No persona has `fit_tags: []` or missing `fit_tags`
- (d) No persona has duplicate `fit_tags:` entries

A6. **`tests/run-tests.sh` invokes the new test** — added to the test orchestrator's loop. Existing test count + 1.

A7. **All existing tests still pass.** `bash tests/run-tests.sh` exits 0; total pass count is `<previous_count> + 3` (where 3 is the new validations from A5).

A8. **CHANGELOG entry** added under `[Unreleased]` referencing this slice + parent spec.

A9. **No code paths read `fit_tags:` in this slice.** Grep for `fit_tags` across `scripts/`, `commands/`, `tests/` should match only `tests/test-persona-fit-tags.sh` and the schema files. (Slices 2+ extend; slice 1 is dormant.)

A10. **Backwards compatibility:** existing specs without `tags:` field continue to load + parse without error. Resolver, dispatch, and gate scripts are unchanged — verified by running `bash tests/run-tests.sh` and seeing zero regressions.

A11. **Persona-fit-tags YAML parser bash-3.2 compatible** — the test runs on macOS Bash 3.2 (per `feedback_negative_array_subscript_bash32.md`); no `mapfile`, no `${arr[-1]}`, no `&>`, no `[[ =~ ]]`. Use `python3 -c` for YAML/JSON validation.

A12. **Schema lockstep CI guard:** `tag-enum.schema.json`, `spec-frontmatter.schema.json`, `persona-frontmatter.schema.json` are all version-pinned (`$id` URLs include schema version) so future migrations stay traceable.

## Open Questions

None at confidence ≥ 0.90. One minor item:

- **Q-mapping-validation:** the proposed `fit_tags:` mappings (e.g., `requirements.md → [docs, integration]`) are inference-judgment calls. Slice 3's resolver will surface empirically-wrong mappings (a persona never selected on relevant specs). Fix-forward in subsequent commits, not blocking on slice 1.

## Sequencing Note

Ships unblocked. Foundation for slices 2-5 of `dynamic-roster-per-gate`. Once this slice merges:

- Slice 2 (`dynamic-roster-2-baseline`) can spec — depends on tag enum.
- Slice 3 (`dynamic-roster-3-tier`) can spec — depends on persona `fit_tags:` being present.
- Slice 4 (`dynamic-roster-4-dispatch`) can spec — depends on slice 3 resolver.
- Slice 5 (`dynamic-roster-5-dashboard`) can spec — depends on slice 3+4 emitting `tier` in `selection.json`.

This slice unblocks the entire chain and is safe to merge independently because no code consumes `fit_tags:` yet (A9 verifies dormancy). Reverting this slice would require reverting all five — but the slice itself is metadata-only with one validation test, so revert is mechanical.
