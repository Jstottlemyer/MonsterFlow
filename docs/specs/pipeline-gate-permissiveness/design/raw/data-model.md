## Summary (data-model persona — full output captured in conversation)

**Schema bump strategy: Option A (strict v2-only).** `_policy_json.py` validator doesn't support oneOf (verified). Strict version-per-schema with consumer branching on `schema_version` for read-time backcompat.

**`schemas/check-verdict.schema.json` v1→v2:**
- Bump `schema_version: const 1 → const 2`, `prompt_version: "check-verdict@1.0" → "check-verdict@2.0"`
- Add 9 required fields: `iteration`, `iteration_max`, `mode`, `mode_source`, `class_breakdown`, `class_inferred_count`, `followups_file`, `cap_reached`, `stage`
- `class_breakdown` is an object with all 7 class keys required + `additionalProperties: false`
- `iteration_max: maximum: 5` (matches Edge 11 clamp)
- `additionalProperties: false` preserved
- `_policy_json.py` requires zero code change (generic validator)

**`schemas/followups.schema.json` (NEW):**
- 17 required fields per spec lines 261-280
- `class` enum NARROWED to 4 values (`contract`, `documentation`, `tests`, `scope-cuts`) — architectural/security/unclassified never reach followups
- `target_phase` enum: 4 values
- `state` enum: 3 values
- `addressed_by` and `previously_addressed_by` accept `^[0-9a-f]{7,40}$|^PR#[0-9]+$`
- Add `"followups"` to `_policy_json.py KNOWN_SCHEMAS` tuple

**`schemas/findings.schema.json` v1→v2:**
- Bump `schema_version: 2`, `prompt_version: findings-emit@2.0`
- Add 3 required fields: `class` (7-value enum), `class_inferred` (boolean), `source_finding_ids` (array of finding_id pattern)
- Plus optional `tags` (string[]) for sev:security parity per api persona

**Lifecycle state machine** (verified diagrammed):
- open → addressed (via /build wave-final commit, addressed_by=SHA)
- open → superseded (via regenerate-active when source_gate matches AND finding_id absent)
- addressed → open (regression, regression=true, previously_addressed_by=prior SHA)
- superseded is TERMINAL (no exit edge)
- Invariants enumerable in tests: regression=true ⇒ state=open AND previously_addressed_by != null; addressed_by != null ⇒ state=addressed (or regression-back); source_gate is immutable post-create

**Persona-metrics back-fill: Option E1.** 2-line change in `compute-persona-value.py` around line 1085-1093 (the survival/findings join site): `fr_class = fr.get("class", "unclassified"); if fr_class == "unclassified": continue`.

**Constraints:**
- `_policy_json.py` lacks oneOf/if-then-else (validator extension would be M-effort)
- `KNOWN_SCHEMAS` tuple needs `"followups"` added (1-line edit)
- `class` enum on findings (7) is BROADER than on followups (4); narrowing happens at projection time
- `source_gate` immutability codified in synthesis logic
- Pre-v0.9.0 `findings.jsonl` rows fail v2 validation IF re-validated; validation is write-time only

**Open Questions:**
- OQ1 no top-level header row in followups.jsonl (per-row schema_version like findings.jsonl)
- OQ2 keep `superseded_by: null` for pure regression; `regression: true` is the audit signal
- OQ3 `class_breakdown` hard-pinned 7 keys (no extra) for v1; v2 adds via prompt_version bump
- OQ4 read both v1/v2 findings.jsonl rows transparently; default missing class to unclassified
- OQ5 `previously_addressed_by` is string (single most-recent); list deferred to v2
