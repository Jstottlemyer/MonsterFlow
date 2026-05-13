## Data Model Design — dynamic-roster-per-gate

### Key Considerations

1. **Naming canonicalization (G1):** Two computed fields must have single canonical names across every artifact: `fit_score` (integer, intersection count) and `combined_score` (float, `fit_score × load_bearing_rate`). Any alias (`fit_count`, `weighted_score`, etc.) is a defect.

2. **Tier policy deep-merge (G4):** Three-layer merge with clear precedence requires explicit schema semantics, not just documented intent. Each layer is a partial object; merge is key-level (leaf wins, gaps filled from lower layer).

3. **Circular detection risk (G7/SEC-02):** `_tag_baseline.py` must strip YAML frontmatter before applying regex. Without this, `tags: [security]` in the frontmatter would self-trigger the `security` regex and inflate confidence on reprocessing.

4. **Backfill gate (M1):** `lineage` field is absent from most existing personas. Schema must treat it as optional with a defined default, not required.

### Schema Recommendations

**`spec-frontmatter.schema.json`**
- Add `tags`: array of strings, `enum` constrained to the 9-value closed set, `minItems: 0`, `uniqueItems: true`
- Add `tags_provenance`: string, pattern `^(baseline|manual|cli)(\+override)?$`
- Add `tier_policy`: object, `additionalProperties: false`, keys are gate names, each value is a `tier_pins` object
- Use `$defs/tag-enum` for shared enum (prevents drift between spec-frontmatter and persona-frontmatter)

**`persona-frontmatter.schema.json` (extension)**
- `fit_tags`: array, enum same 9-value set, `minItems: 0`, optional (missing = empty set, score = 0)
- `lineage`: string, enum `["claude", "codex", "gemini"]`, optional, **default `"claude"`** (resolves M1 without backfill)
- `load_bearing_rate`: number, `minimum: 0`, `maximum: 1`, optional, default `0.5`

**`selection.schema.json` row extension (NEW FILE)**
- Add `tier`: enum `["opus", "sonnet"]`, required
- Add `fit_score`: integer, `minimum: 0`, required
- Add `combined_score`: number, `minimum: 0`, required
- Add top-level `tier_policy_applied` audit block: `{source: enum["constitution"|"spec"|"cli"], opus_min: integer, opus_count_actual: integer, sonnet_count_actual: integer}`

**`tier_policy` merge semantics (G4)**
- Constitution provides base object; spec overlays via key-level deep-merge (spec leaf wins, constitution fills absent keys); CLI applies final leaf overrides
- `tier_pins` per gate merges recursively: `spec.check.scope-discipline=opus` and `constitution.plan.risk=opus` both survive, no clobber

### Constraints Identified

- Closed enum shared between `spec.tags` and `fit_tags` must be defined once (`$defs/tag-enum`) and `$ref`-ed in both schemas. Duplication is a drift risk.
- `_tag_baseline.py` pipeline order is normative, not advisory: NFKC → strip frontmatter → strip fences → lowercase → regex → emit set.
- Test floor: `≥33 fixtures, <15s wall-clock`. No other number appears anywhere in the plan.
- Defaults applied at READ TIME in Python code, not written back to persona files.

### Open Questions

- Should `tags_provenance` track per-tag source or just highest-precedence source for the whole array? Per-tag is more auditable; simpler approach for v1 is a comment-only record.
- Is `tier_policy` valid at top-level constitution or only per-gate? Clarify whether a global default tier pin is in scope.

### Integration Points

- `selection.json` is read by `/wrap-insights` Phase 1c; new fields must be backward-compatible (existing rows without them should not break the renderer).
- Resolver defaults (`lineage=claude`, `load_bearing_rate=0.5`) applied at read time, not written back to persona files.
