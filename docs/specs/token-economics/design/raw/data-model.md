# Data Model — Token Economics

**Persona:** data-model
**Lens:** entities, schemas, allowlists, run-state taxonomy, forward-compat for v1.1

## Key Considerations

1. **Three persisted artifacts**, all under `dashboard/data/` (gitignored): `persona-rankings.jsonl` (rolling stats), `persona-roster.js` (current roster sidecar for hybrid render under `file://`), and the in-repo `schemas/persona-rankings.allowlist.json` (committed).
2. **`additionalProperties: false` is the privacy contract.** A10 enforces it on both the generated JSONL and the committed fixture. Every field must be enumerated; the allowlist file is itself the JSON Schema (no separate "schema vs allowlist" split — they are the same artifact).
3. **`run_state` is a row-shape decision, not just an enum.** It needs to be (a) a flat string enum on each row of an intermediate per-directory accumulator, AND (b) aggregated as `run_state_counts: {state: int}` on each emitted (persona, gate) row. Two shapes; same vocabulary.
4. **Null vs omit for missing rates** — schema must allow `null` for `judge_retention_ratio`, `downstream_survival_rate`, `uniqueness_rate` (per e10/e11). Omitting fields breaks idempotent diffs and forces dashboard to branch on `field in row` vs `row[field] === null`. **Use `null`, never omit** — explicit and grep-able.
5. **Forward-compat for v1.1** (per-dispatch hash + `agent_tool_use_id`): bump `schema_version` to 2; v1 readers (dashboard) skip rows where `schema_version > KNOWN_MAX`. Reserve the field names now so v1.1 doesn't need to re-key.
6. **`persona-roster.js` needs more than names** — gate, file path, current content hash, last-modified ISO, deprecated flag. Drives "(never run)" rendering AND deleted-persona strikethrough.
7. **`contributing_finding_ids[]` sort order** — IDs are sorted lexicographically for idempotency BUT the soft-cap rule is "most-recent 50". These conflict. Resolution: store the most-recent-50 set, then sort lexicographically before emit. `truncated_count` carries the surplus.

## Options Explored

### Option A — Single allowlist schema doubles as the row schema (recommended) — S
- One file `schemas/persona-rankings.allowlist.json` with `additionalProperties: false` + full type/constraint metadata.
- Pro: single source of truth, A10 test is `jsonschema.validate(row, schema)` for every line.
- Pro: no drift between "what's allowed" and "what's emitted."
- Con: the allowlist is the *minimum* viable schema; any future evolution touches the same file (acceptable — schema_version + reserved fields handle this).

### Option B — Split: `schemas/persona-rankings.schema.json` (rich) + `schemas/persona-rankings.allowlist.json` (field-name-only set) — M
- Pro: separates "shape" from "privacy gate."
- Con: two files to keep in sync; A10 must verify they agree; double the maintenance cost.
- Rejected: spec calls out one allowlist file (A10 wording), and `additionalProperties: false` already encodes the gate.

### Option C — Embed roster inside `persona-rankings.jsonl` (no sidecar) — M
- Pro: one fewer file.
- Con: changing the roster (file edit, `git mv`) would require re-emitting the whole JSONL; race surface.
- Con: roster represents *current* state; rankings represent *historical* state. Conflating them breaks the "(never run)" semantic (a "never run" row would have no ranking fields and pollute the type).
- Rejected: spec already commits to the sidecar.

### Option D — `run_state` as a sub-enum per persona-source-row, separate from `run_state_counts` aggregate — chosen — S
- The accumulator (per (persona, gate, artifact_directory) tuple) carries one `run_state`. The emitted row aggregates these into `run_state_counts: {state: int}`.
- Pro: matches spec §Data table verbatim (A2 verifiability).
- Pro: future v1.1 invocation-level rows can persist the per-tuple `run_state` directly without schema change.

### Option E — Null-rate handling: `null` vs omitted vs sentinel (`-1`) — `null` chosen — S
- Spec e10/e11 explicitly say "= null". Sentinel values (`-1`) historically cause arithmetic bugs in JS dashboards.
- Schema: rate fields typed `["number", "null"]`, range `[0,1]` when number.

## Recommendation

Adopt **Option A + Option D + Option E**: one allowlist-shaped schema; `run_state` enum used both per-tuple internally and as keys of `run_state_counts` on emit; explicit `null` for absent rates.

### Sketch — `schemas/persona-rankings.allowlist.json`

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://github.com/Jstottlemyer/MonsterFlow/schemas/persona-rankings.allowlist.json",
  "title": "Persona Rankings — allowlisted row schema (v1)",
  "description": "Authoritative allowlist for dashboard/data/persona-rankings.jsonl AND tests/fixtures/persona-attribution/*.jsonl. additionalProperties: false is the privacy gate (A10). Bump schema_version on any breaking change; reserve future field names here to keep idempotent diffs stable.",
  "type": "object",
  "required": [
    "schema_version",
    "persona",
    "gate",
    "runs_in_window",
    "window_size",
    "run_state_counts",
    "total_emitted",
    "total_judge_retained",
    "total_downstream_survived",
    "total_unique",
    "total_tokens",
    "judge_retention_ratio",
    "downstream_survival_rate",
    "uniqueness_rate",
    "avg_tokens_per_invocation",
    "last_seen",
    "persona_content_hash",
    "window_start_artifact_dir",
    "contributing_finding_ids",
    "truncated_count",
    "insufficient_sample"
  ],
  "properties": {
    "schema_version": { "type": "integer", "const": 1 },
    "persona": {
      "type": "string",
      "pattern": "^[a-z0-9][a-z0-9-]{0,63}$",
      "description": "Persona slug as it appears in personas/<gate>/<name>.md (NFC-normalized, lowercase, hyphenated)."
    },
    "gate": {
      "type": "string",
      "enum": ["spec-review", "plan", "check"]
    },
    "runs_in_window": { "type": "integer", "minimum": 0, "maximum": 45 },
    "window_size": { "type": "integer", "const": 45 },
    "run_state_counts": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "complete_value",
        "missing_survival",
        "missing_findings",
        "missing_raw",
        "malformed",
        "cost_only"
      ],
      "properties": {
        "complete_value":    { "type": "integer", "minimum": 0 },
        "missing_survival":  { "type": "integer", "minimum": 0 },
        "missing_findings":  { "type": "integer", "minimum": 0 },
        "missing_raw":       { "type": "integer", "minimum": 0 },
        "malformed":         { "type": "integer", "minimum": 0 },
        "cost_only":         { "type": "integer", "minimum": 0 }
      },
      "description": "Sum of values MUST equal runs_in_window. A2 verifies."
    },
    "total_emitted":              { "type": "integer", "minimum": 0 },
    "total_judge_retained":       { "type": "integer", "minimum": 0 },
    "total_downstream_survived":  { "type": "integer", "minimum": 0 },
    "total_unique":               { "type": "integer", "minimum": 0 },
    "total_tokens":               { "type": "integer", "minimum": 0 },
    "judge_retention_ratio": {
      "type": ["number", "null"],
      "minimum": 0.0,
      "maximum": 1.0,
      "description": "total_judge_retained / total_emitted. null iff total_emitted == 0 (e10). Compression ratio, not survival."
    },
    "downstream_survival_rate": {
      "type": ["number", "null"],
      "minimum": 0.0,
      "maximum": 1.0,
      "description": "total_downstream_survived / total_judge_retained. null iff total_judge_retained == 0 (e11)."
    },
    "uniqueness_rate": {
      "type": ["number", "null"],
      "minimum": 0.0,
      "maximum": 1.0,
      "description": "total_unique / total_judge_retained. null iff total_judge_retained == 0 (e11)."
    },
    "avg_tokens_per_invocation": {
      "type": ["number", "null"],
      "minimum": 0,
      "description": "total_tokens / runs_in_window. null iff runs_in_window == 0. Cost ranking uses this, not totals."
    },
    "last_seen": {
      "type": "string",
      "format": "date-time",
      "description": "ISO 8601 UTC. Sourced from MAX(run.json.created_at) of contributing artifact directories. NEVER file mtime. Excluded from idempotency diff."
    },
    "persona_content_hash": {
      "type": ["string", "null"],
      "pattern": "^sha256:[0-9a-f]{64}$",
      "description": "CURRENT hash of personas/<gate>/<persona>.md (NFC + LF-normalized, then sha256). null iff persona file deleted (e7)."
    },
    "window_start_artifact_dir": {
      "type": "string",
      "description": "Repo-relative path of the oldest artifact directory still in the window. Used for adopter debugging."
    },
    "contributing_finding_ids": {
      "type": "array",
      "items": {
        "type": "string",
        "pattern": "^(sr|pl|ck)-[0-9a-f]{10,}$"
      },
      "maxItems": 50,
      "description": "Most-recent 50 finding IDs (by run.json.created_at of source dir), then sorted lexicographically before emit for idempotent diff. Surplus rolled into truncated_count."
    },
    "truncated_count": {
      "type": "integer",
      "minimum": 0,
      "description": "Count of contributing finding IDs beyond the 50-cap."
    },
    "insufficient_sample": {
      "type": "boolean",
      "description": "true iff runs_in_window < 3. Dashboard renders rate cells as '—'; row excluded from /wrap-insights top/bottom lists."
    }
  },
  "additionalProperties": false
}
```

### Sketch — `dashboard/data/persona-roster.js` shape

```javascript
// AUTOGENERATED by scripts/compute-persona-value.py — do not edit.
// Loaded via <script src> under file:// (no fetch).
window.PERSONA_ROSTER = [
  {
    "persona": "scope-discipline",
    "gate": "spec-review",
    "file_path": "personas/spec-review/scope-discipline.md",
    "persona_content_hash": "sha256:9a4b...",
    "last_modified": "2026-04-29T14:02:11Z",
    "deprecated": false
  },
  {
    "persona": "ux-flow",
    "gate": "spec-review",
    "file_path": "personas/spec-review/ux-flow.md",
    "persona_content_hash": "sha256:1f3e...",
    "last_modified": "2026-05-01T08:40:55Z",
    "deprecated": false
  }
  // ...
];
window.PERSONA_ROSTER_GENERATED_AT = "2026-05-04T17:32:11Z";
```

**Rationale for each roster column:**
- `persona` + `gate` — join key against `persona-rankings.jsonl`.
- `file_path` — adopter debug ("where does this live?"); also lets dashboard render a tooltip.
- `persona_content_hash` — lets dashboard detect "roster says hash X, JSONL row has hash Y → persona was edited; data is pre-edit, expect transient skew" (per e2 weakened semantics).
- `last_modified` — secondary signal for "(never run since edit)" UX.
- `deprecated` — false for v1; reserved so future tombstone files (`personas/<gate>/.deprecated/<name>.md` or a manifest) can hide noisy never-run rows without schema bump.
- `PERSONA_ROSTER_GENERATED_AT` — top-level sibling so dashboard can show "roster as of …" beside the data freshness banner.

### `run_state` enum

Vocabulary lives in one place — the JSON Schema enum on `run_state_counts.properties`. Six values:

| `run_state` | semantics |
|---|---|
| `complete_value`    | raw + findings + survival + run all present and parse-clean |
| `missing_survival`  | raw + findings + run; survival.jsonl absent or empty |
| `missing_findings`  | raw + run; findings.jsonl absent |
| `missing_raw`       | findings + run; raw/<persona>.md absent |
| `malformed`         | any artifact present but fails schema parse |
| `cost_only`         | Agent dispatch in session JSONL but no value artifact at the matching `docs/specs/<feature>/<gate>/` |

`run_state_counts` MUST contain all six keys (object, `additionalProperties: false`, all six required, default 0). Ensures A2's "totals match runs_in_window" test is unambiguous and dashboard rendering doesn't need to handle missing keys.

### Null vs omit decision (per e10/e11)

**Use `null`, never omit.** Reasons:
- Idempotent diffs (A8): `sort_keys=True` + present-but-null is byte-stable; conditionally-omitted fields produce non-deterministic key sets.
- Dashboard JS: `row.judge_retention_ratio === null` is one branch; `'judge_retention_ratio' in row` is two. Less branching = fewer bugs.
- Schema enforcement: `"type": ["number", "null"]` is one declaration; making fields optional weakens the privacy gate (allowlist would be ambiguous about what's permitted).

## Constraints Identified

- **C1 — `additionalProperties: false` everywhere.** Top-level row, `run_state_counts`, and any future nested object. A10 leans on this.
- **C2 — `runs_in_window ≤ window_size` (45).** Schema enforces upper bound; logic enforces equality with `sum(run_state_counts.values())`.
- **C3 — Null rate fields require `total_*` denominator to be 0.** Schema can't express this conditional; A2 tests it.
- **C4 — `contributing_finding_ids` sorted lexicographically on emit.** Cap selection is "most-recent-50 then sort." This is a logic constraint, not a schema constraint (schema only enforces `maxItems: 50`).
- **C5 — `last_seen` excluded from idempotency diff.** Documented in spec §Idempotency contract; data model honors by allowing it as a normal field but `tests/test-compute-persona-value.sh` strips it before comparison.
- **C6 — `persona_content_hash` is current, not historical.** Per e2 honesty; schema allows null for deleted-persona case.
- **C7 — Roster is regenerated every run** (not appended). Atomic write via tmp + `os.replace`.
- **C8 — Schema file lives at `schemas/persona-rankings.allowlist.json` and is committed.** Dashboard does NOT read it (no schema validation in JS); Python writer + `tests/test-allowlist.sh` are the only consumers.

## Open Questions

1. **Q-DM-1: Should `persona-roster.js` be JSONL-shaped instead of a JS array?** A JSONL sidecar (`persona-roster.jsonl`) + a one-line `roster.js` shim would let other tooling consume it. **Recommendation:** keep as `.js` for v1 (matches spec verbatim, single render surface). Revisit if a CLI tool needs to read it.
2. **Q-DM-2: Should we reserve `agent_tool_use_id` and `dispatch_persona_content_hash` field names in the v1 allowlist now to ease v1.1 evolution?** Adding them as optional fields with `null` defaults today means v1 rows survive v1.1 readers without a `schema_version` bump. **Recommendation:** NO — bump `schema_version` to 2 for v1.1 and keep v1 minimal. Reserved-but-unused fields invite "why is this always null?" questions and complicate A10. **Caveat:** if adversarial reviewer pushes back, reconsider during /check.
3. **Q-DM-3: Do we need a top-level `meta` row at line 0 of the JSONL** (e.g., `{"_meta": true, "generated_at": "...", "tool_version": "..."}`)? Pro: helps adopter triage stale data. Con: every consumer (dashboard, /wrap-insights, A10 test) needs to skip it. **Recommendation:** NO — put generation metadata in stderr telemetry (already specified) and on `persona-roster.js` (`PERSONA_ROSTER_GENERATED_AT`). Keep JSONL homogeneous.
4. **Q-DM-4: `persona` slug pattern strictness.** Current sketch is `^[a-z0-9][a-z0-9-]{0,63}$`. Need to verify against actual `personas/*/*.md` filenames — if any contain underscores or capitals the pattern rejects valid data. (api persona owns the regex_extract_persona implementation; data-model owns the schema constraint. Coordinate during /check.)

## Integration Points with other dimensions

- **api dimension:** consumes the schema as the contract for `compute-persona-value.py` emit. The Python writer should `jsonschema.validate(row, allowlist_schema)` per row before serialize (cheap; catches drift at write-time, not just test-time).
- **scalability dimension:** the row size is ~600–800 bytes (50 finding IDs dominate). At 28 personas × 3 gates × ~750 bytes = ~63 KB JSONL — trivial. No index needed.
- **integration dimension:** the `persona-roster.js` sidecar is the ONLY mechanism that lets the dashboard render hybrid rows under `file://` (no `fetch()`). This is a hard constraint, not a preference.
- **edges dimension:** e10/e11 (null rates) are encoded as `["number", "null"]` schema unions; e7 (deleted persona) as `persona_content_hash: null`; e9 ("never run") rendered FROM `persona-roster.js` — no JSONL row exists. e1 (insufficient_sample) is an explicit boolean field, not derived at read time, so dashboard doesn't recompute.
- **testing dimension:** A10 = `jsonschema.validate` over every row in both the generated artifact and the committed fixture. The deliberate-failure fixture (`tests/fixtures/persona-attribution/leakage-fail.jsonl`) needs ONE forbidden field added (e.g., `"finding_title": "..."`) to prove `additionalProperties: false` catches it.
- **observability dimension:** stderr telemetry line should include row count + count of `insufficient_sample: true` rows ("emitted 84 rows, 12 insufficient_sample") — adopters know "is my window populated yet?"
