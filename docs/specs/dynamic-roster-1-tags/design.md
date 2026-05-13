# Plan — dynamic-roster-1-tags

**Spec:** `docs/specs/dynamic-roster-1-tags/spec.md`
**Review:** `queue/dynamic-roster-1-tags/review-findings.md`
**Generated:** 2026-05-07 (autorun headless)
**Slice:** 1 of 5 (`dynamic-roster-per-gate`)
**Gate mode:** `permissive` (per spec frontmatter), `gate_max_recycles: 2`
**Posture:** GO — risks are execution-discipline, not design

---

## Design Decisions (resolutions of /spec-review ambiguities)

The spec review surfaced four critical ambiguities (C1–C4) and several minor inconsistencies. Resolved up-front so /build agents are fully unblocked; each resolution is binding for this slice.

### D1. YAML parsing in the validation test → **stdlib regex extraction** (resolves C3, gaps-C1, req-03)

The spec's "falls back to `ast`-style parser if PyYAML absent" is undefined — Python's `ast` cannot parse YAML, and macOS system Python 3.9 ships neither `PyYAML` nor `jsonschema`. Two reviewers (ambiguity, feasibility, gaps, requirements) flagged this as the single highest-risk ambiguity.

**Decision:** the test parses persona frontmatter with **stdlib-only Python regex extraction**, no `yaml` import. Persona frontmatter has a uniform shape (one-line `fit_tags: [a, b, c]`); a 4-line regex is sufficient and removes the dependency entirely.

```python
# Inside tests/test-persona-fit-tags.sh, invoked via python3 -c '<heredoc>':
import re, sys
FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---", re.DOTALL)
FIT_TAGS_RE = re.compile(r"^fit_tags:\s*\[([^\]]*)\]\s*$", re.MULTILINE)
# fit_tags MUST be inline-array form `[a, b]`. Block-list form (`- a\n  - b`)
# is rejected by the test with a clear error so the convention stays uniform.
```

This honors A11 (bash 3.2 + system Python 3.9, zero pip installs on a fresh machine).

### D2. JSON Schema `$ref` resolution → **don't resolve at test time; inline the enum** (resolves C4, feasibility-1, gaps-C3)

`$ref` resolution requires `jsonschema` + a `RefResolver` with `base_uri`. None of that is available on stock macOS Python 3.9.

**Decision:** the test does **not** validate persona frontmatter against the JSON Schema files at all. Instead, the test inlines a Python `set` of the 9 canonical tag values as the source of truth, and validates each `fit_tags:` value membership-only against that set.

The schema files are validated at a lower bar: `json.load()` parses cleanly (proves valid JSON, valid `$id`/`$schema`/`title` shape). Schema-as-runtime-contract lights up in slice 3+ when a JSON Schema validator is available.

A1, A2, A3 are reframed accordingly: "Schema is **valid JSON** with the documented `$schema`, `$id`, `title`, and structural fields present" — not "schema is valid JSON Schema 2020-12 with all `$ref`s resolved."

### D3. `spec-frontmatter.schema.json` → **NEW file** (resolves C2)

Grep confirms `schemas/spec-frontmatter.schema.json` does not exist on disk. The spec's "NEW or extension" disjunction is resolved to **NEW**. No existing schema to extend.

### D4. `fit_tags:` is REQUIRED on all personas in slice 1 (resolves I1)

The spec contains a self-contradiction: §Scope says "Optional for now; slice 3 makes it required for personas dispatched at gates," but §Data declares `"required": ["fit_tags"]` and A3 says "REQUIRED."

**Decision:** required from day one. The schema as written is correct; the "Optional for now" sentence is an editorial error. Rationale:
- A4 backfills all 19 existing personas in this slice — there is no "transitional" period where some personas lack the field.
- The integrity test (A5) already enforces presence + non-empty + enum-valid + uniqueness. Making the schema match the test is consistent.
- "Required from day one" is the simpler mental model for new persona authors (R-stakeholders).

### D5. Bash 3.2 forbidden-feature list → corrected (resolves I4, req-02)

A11 over-restricts by forbidding `[[ =~ ]]`, which works fine on bash 3.2.57. The actual bash-4 hazards are: `mapfile` / `readarray`, `${arr[-1]}` (negative subscripts), associative arrays (`declare -A`), `&>>` append redirect, and `${var,,}` / `${var^^}` case modification.

**Decision:** the test is bash 3.2 compatible. Forbidden constructs in this slice's test code: `mapfile`, `readarray`, `${arr[-1]}`, `declare -A`, `${var,,}`, `${var^^}`, `&>>`. **`[[ =~ ]]` is allowed.**

### D6. `$id` URL versioning → `/v1/` segment included (resolves O7, scope, gaps-O5)

A12 promises "version-pinned `$id` URLs" but the example URLs in §Data lack a version segment.

**Decision:** all three new schemas use `https://monsterflow.dev/schemas/v1/<name>.schema.json`. Future migrations bump to `/v2/` without disturbing v1. This is identity-only — JSON Schema does not require the URL to be fetchable.

### D7. Test pass count contract → **+4** (resolves C1, req-01)

A5 lists four assertions (presence, enum-valid, non-empty, no-duplicates). A7 says "+3."

**Decision:** the test emits **four** PASS lines, one per assertion in A5(a)–(d). A7 is read as `<previous_count> + 4`. Each assertion is a separate `_test_*` shell function so individual failures pinpoint which constraint broke.

### D8. Failure-message contract (resolves req-04)

Each assertion failure must include: persona file path, the offending value (when applicable), and the canonical 9-value enum (for the membership check). Example:

```
FAIL test_all_fit_tags_are_valid_enum_values
  personas/check/risk.md: fit_tags contains "securty" which is not in the enum.
  Valid values: api, data, docs, integration, migration, refactor, scalability, security, ux
```

### D9. Persona content-hash rotation acknowledged (resolves R2 with concrete scope)

The spec's R2 risk says existing readers may break on the new line. Investigation confirms:
- `scripts/resolve-personas.sh` and `scripts/_resolve_personas.py` do **not** parse persona frontmatter — they work off filenames + config.json + `dashboard/data/persona-rankings.jsonl`. Safe.
- `scripts/_roster.py::compute_persona_content_hash` SHA-256-hashes the **entire persona file**. Adding `fit_tags:` rotates **all 19** persona_content_hash values in `persona-rankings.jsonl` once.

**Decision:** hash rotation is acceptable, not blocking. `persona-rankings.jsonl` already rebuilds across runs; a one-time rotation is indistinguishable from any persona body edit. The plan emits a CHANGELOG note ("v0.10.0 rotates all 19 persona_content_hash values via additive frontmatter; no action needed") so adopters reading rankings drift have context.

A new acceptance check (A13 below) verifies no other code paths read persona frontmatter positionally.

### D10. `spec-frontmatter.schema.json` stays in slice 1 (rejects scope-1's recommendation)

The scope reviewer recommended cutting `spec-frontmatter.schema.json` to slice 2. **Rejected** — scope is the spec author's prerogative, not /plan's. The schema lands in slice 1 as a documented stub. A2 is met by D2's reframing ("valid JSON, documented shape").

### D11. Persona onboarding doc — minimal in-schema description (addresses stakeholders-1)

Rather than adding a separate `personas/README.md` (out of slice 1's stated scope), each schema file's top-level `description` field carries the tag-taxonomy guidance. This sits where authors already look (the schema rejection error points at the schema file). A `personas/README.md` rewrite is deferred to slice 3 when the resolver is the natural learning surface.

---

## Architecture Summary

Slice 1 is **purely additive metadata**. Three schema files + 19 single-line frontmatter additions + one bash test. Zero behavior change at runtime — verified by A9 dormancy assertion (grep `fit_tags` matches only the schemas + the new test).

The only consumers of `fit_tags:` after this slice ships:
1. `tests/test-persona-fit-tags.sh` — integrity check.
2. (Future, slice 3+) `scripts/_persona_score.py`, `scripts/resolve-personas.sh` extension.

The closed 9-value enum (`security, data, api, ux, integration, scalability, docs, refactor, migration`) is the integration contract for slices 2–5. Versioned via `$id` `/v1/` segment so future enum extensions can ship as `/v2/` without disturbing v1.

Wave-sequencing follows MonsterFlow's data → UI → tests precedence and the `feedback_parallel_agents_shared_file_race.md` rule:
- **Wave A (parallel, independent files):** schema authoring + 19 persona frontmatter edits + test file creation.
- **Wave B (sequential single-writer):** orchestrator wiring + CHANGELOG entry + install.sh schemas/ propagation. ONE agent, no fan-out.
- **Wave C (verification):** run full test suite, run `/preship`, verify A9 dormancy by grep.

---

## Implementation Tasks

| #   | Task                                                           | Depends On | Size | Wave | Parallel?     |
|-----|----------------------------------------------------------------|------------|------|------|---------------|
| T1  | Create `schemas/tag-enum.schema.json`                          | —          | S    | A    | yes           |
| T2  | Create `schemas/spec-frontmatter.schema.json`                  | T1 (logical, not file) | S | A | yes (with T1) |
| T3  | Create `schemas/persona-frontmatter.schema.json`               | T1 (logical, not file) | S | A | yes (with T1) |
| T4  | Backfill `fit_tags:` into 6 `personas/review/*.md`             | —          | S    | A    | yes           |
| T5  | Backfill `fit_tags:` into 7 `personas/plan/*.md`               | —          | S    | A    | yes           |
| T6  | Backfill `fit_tags:` into 6 `personas/check/*.md`              | —          | S    | A    | yes           |
| T7  | Create `tests/test-persona-fit-tags.sh`                        | —          | M    | A    | yes           |
| T8  | **Wire orchestrator: append to `tests/run-tests.sh` `TESTS=()`** | T7      | S    | B    | **NO — sequential single-writer** |
| T9  | **CHANGELOG `[Unreleased]` entry**                              | T1–T7      | S    | B    | **NO — sequential single-writer** (same agent as T8) |
| T10 | **Update `install.sh`: symlink `schemas/`**                    | T1–T3      | S    | B    | **NO — sequential single-writer** (same agent as T8) |
| T11 | Run full test suite; verify +4 PASS, zero regressions          | T8         | S    | C    | sequential     |
| T12 | A9 dormancy grep + A13 reader-audit grep                        | T1–T7      | S    | C    | yes (with T11) |
| T13 | Run `autorun-shell-reviewer` subagent on T8/T10 changes        | T8, T10    | S    | C    | yes            |

**LoC estimate:** ~280 lines total (3 schemas ~30 LoC each, test ~80 LoC, 19 single-line edits, run-tests.sh +1 line, CHANGELOG +6 lines, install.sh +6 lines).

### Wave A — parallel additive writes (T1–T7)

All seven tasks write **disjoint files**. No coordination needed.

**T1. `schemas/tag-enum.schema.json`** — single source of truth for the 9-value enum.

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://monsterflow.dev/schemas/v1/tag-enum.schema.json",
  "title": "MonsterFlow tag enum (v1)",
  "description": "Closed 9-value vocabulary for spec tags: and persona fit_tags:. Extension policy: bump $id to /v2/ + add followups.jsonl entry to retag personas under v2; do NOT mutate v1 in place.",
  "type": "string",
  "enum": ["api", "data", "docs", "integration", "migration", "refactor", "scalability", "security", "ux"]
}
```
Enum sorted alphabetically — byte-stable diffs across slices 2–5.

**T2. `schemas/spec-frontmatter.schema.json`** — optional `tags:` (slice 1 stub; slice 2 makes it required for new specs).

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://monsterflow.dev/schemas/v1/spec-frontmatter.schema.json",
  "title": "MonsterFlow spec.md frontmatter (v1, slice-1 stub)",
  "description": "Slice 1 stub. Only validates the optional tags: field. additionalProperties: true is intentional in v1; tightened in slice-2 (`dynamic-roster-2-baseline`) when /spec Phase 3 LLM-propose-user-confirm wires up.",
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

**T3. `schemas/persona-frontmatter.schema.json`** — REQUIRED `fit_tags:` (per D4).

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://monsterflow.dev/schemas/v1/persona-frontmatter.schema.json",
  "title": "MonsterFlow persona.md frontmatter (v1)",
  "description": "Every persona under personas/{review,plan,check}/ MUST declare fit_tags:. Pick 1–3 values from tag-enum.schema.json that describe the content axes the persona reviews. Multi-tag personas (e.g., risk: [scalability, security, integration]) are matched on union with spec tags. See personas/<gate>/*.md for examples.",
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

**T4 / T5 / T6 — Persona backfill, 19 files.** Edit anchor (per R7 mitigation): use the unique `name: <persona-slug>` line, **not** the `---` delimiter (which is non-unique across files). Insert `fit_tags: [...]` immediately after `name:`. Mappings copied verbatim from spec §Scope:

| File                               | `fit_tags:`                              |
|------------------------------------|------------------------------------------|
| `personas/review/requirements.md`  | `[docs, integration]`                    |
| `personas/review/gaps.md`          | `[docs, scalability]`                    |
| `personas/review/ambiguity.md`     | `[docs, ux]`                             |
| `personas/review/feasibility.md`   | `[scalability, integration]`             |
| `personas/review/scope.md`         | `[docs, refactor]`                       |
| `personas/review/stakeholders.md`  | `[ux, docs]`                             |
| `personas/plan/api.md`             | `[api, integration]`                     |
| `personas/plan/data-model.md`      | `[data, migration]`                      |
| `personas/plan/ux.md`              | `[ux]`                                   |
| `personas/plan/scalability.md`     | `[scalability]`                          |
| `personas/plan/security.md`        | `[security]`                             |
| `personas/plan/integration.md`     | `[integration]`                          |
| `personas/plan/wave-sequencer.md`  | `[refactor, integration]`                |
| `personas/check/completeness.md`   | `[docs]`                                 |
| `personas/check/sequencing.md`     | `[refactor, integration]`                |
| `personas/check/risk.md`           | `[scalability, security, integration]`   |
| `personas/check/scope-discipline.md` | `[docs, refactor]`                     |
| `personas/check/security-architect.md` | `[security]`                         |
| `personas/check/testability.md`    | `[refactor]`                             |

Mappings are provisional (Q-mapping-validation). Slice 3's resolver will surface empirically wrong picks; corrections are PR-scope, not blocking on slice 1.

**Pre-flight gate (R6 mitigation):** before any backfill edit, run

```bash
expected=19
actual=$(find personas/review personas/plan personas/check -maxdepth 1 -name '*.md' \
         ! -name 'judge.md' ! -name 'synthesis.md' | wc -l | tr -d ' ')
[ "$actual" = "$expected" ] || { echo "persona drift: expected $expected, found $actual"; exit 1; }
```

If the count differs from 19, halt and surface to user — do NOT auto-map a new persona.

**T7. `tests/test-persona-fit-tags.sh`** — bash 3.2 compatible, stdlib Python only. Skeleton:

```bash
#!/usr/bin/env bash
set -uo pipefail
ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ENGINE_DIR"

PASS=0; FAIL=0

# Optional dep guard (R8): never crash; the inline-array regex path needs no extras.
# (Documentation-only — keeps the path clear if a future variant wants PyYAML.)

_python_check() {
  python3 - <<'PY'
import re, sys, glob, json
ENUM = {"api","data","docs","integration","migration","refactor","scalability","security","ux"}
FM = re.compile(r"^---\n(.*?)\n---", re.DOTALL)
FIT = re.compile(r"^fit_tags:\s*\[([^\]]*)\]\s*$", re.MULTILINE)
GATES = ["personas/review", "personas/plan", "personas/check"]
SKIP = {"judge.md", "synthesis.md"}
errors = {"presence": [], "enum": [], "nonempty": [], "unique": []}
for gate in GATES:
    for path in sorted(glob.glob(f"{gate}/*.md")):
        if path.split("/")[-1] in SKIP: continue
        text = open(path, encoding="utf-8").read()
        m = FM.search(text)
        if not m: errors["presence"].append((path, "no frontmatter")); continue
        fm = FIT.search(m.group(1))
        if not fm: errors["presence"].append((path, "no fit_tags: line")); continue
        raw = [v.strip().strip('"').strip("'") for v in fm.group(1).split(",") if v.strip()]
        if not raw: errors["nonempty"].append(path); continue
        bad = [v for v in raw if v not in ENUM]
        if bad: errors["enum"].append((path, bad))
        if len(set(raw)) != len(raw): errors["unique"].append((path, raw))
print(json.dumps(errors))
PY
}

REPORT="$(_python_check)"
report() {
  local key="$1"; local label="$2"
  local n; n=$(printf '%s' "$REPORT" | python3 -c 'import sys,json; d=json.loads(sys.stdin.read()); print(len(d["'"$key"'"]))')
  if [ "$n" = "0" ]; then echo "PASS $label"; PASS=$((PASS+1));
  else echo "FAIL $label"; printf '%s' "$REPORT" | python3 -c 'import sys,json; d=json.loads(sys.stdin.read()); [print("  ",e) for e in d["'"$key"'"]]'; echo "  Valid values: api, data, docs, integration, migration, refactor, scalability, security, ux"; FAIL=$((FAIL+1)); fi
}

report presence  test_all_personas_have_fit_tags
report enum      test_all_fit_tags_are_valid_enum_values
report nonempty  test_no_empty_fit_tags
report unique    test_no_duplicate_fit_tags

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
```

Estimated 70–85 LoC including comments. The `≤80 LoC` target in the spec is aspirational — if it lands at 90 LoC with helpful error messages, that's acceptable (treated as a target per I3, not a blocker).

### Wave B — sequential single-writer (T8 / T9 / T10)

**Critical constraint (R1 mitigation):** all three tasks touch repo-shared files (`tests/run-tests.sh`, `CHANGELOG.md`, `install.sh`). They MUST run in **one** agent invocation, sequentially, after all of Wave A completes. NEVER parallelize.

**T8.** Append to the `TESTS=()` array in `tests/run-tests.sh`. Anchor: insert immediately after the most recent test added. Single-line append:

```bash
  test-persona-fit-tags.sh
```

Verify with `grep -c '^[[:space:]]*test-persona-fit-tags.sh' tests/run-tests.sh` returns `1` (R1's `/preship` assertion).

**T9.** `CHANGELOG.md` insertion (R5 mitigation). Pre-step: `Read CHANGELOG.md` and confirm the existing shape — header `# Changelog` followed by release blocks `## [0.9.0] - 2026-05-05`. Insert a new `## [Unreleased]` section between `# Changelog` (after its 2-line preamble) and `## [0.9.0]`.

Exact text (verbatim from spec A8 + D9 hash-rotation note):

```markdown
## [Unreleased]

### Added

- **Tag schema (slice 1 of `dynamic-roster-per-gate`):** closed 9-value tag enum (`schemas/v1/tag-enum.schema.json`) + spec frontmatter stub (`schemas/v1/spec-frontmatter.schema.json`) + persona frontmatter (`schemas/v1/persona-frontmatter.schema.json`) — required `fit_tags:` on all personas.
- `tests/test-persona-fit-tags.sh` — validates presence, enum-membership, non-empty, no-duplicates across all 19 pipeline personas.
- `fit_tags:` frontmatter backfilled on all 19 pipeline personas (review 6, plan 7, check 6).

### Changed

- `install.sh` symlinks `schemas/` into adopter's `~/.claude/schemas/`, sentinel-bracketed for idempotent re-run.
- All 19 persona files gained one frontmatter line. **Note:** `_roster.compute_persona_content_hash` rotates once for every persona — `dashboard/data/persona-rankings.jsonl` will show `persona_content_hash` deltas on next snapshot. No action needed; rebuild is automatic.

### Notes

- No runtime behavior changes ship in this release. `fit_tags:` is dormant data until slice 3 (`dynamic-roster-3-tier`) wires the resolver.
```

**T10.** `install.sh` schemas/ propagation (R3 mitigation). Add a sentinel-bracketed schemas/ symlink block after the existing personas symlink loop (around line 505 per inspection). Pattern:

```bash
# >>> dynamic-roster-1-tags: schemas/ propagation
mkdir -p "$CLAUDE_DIR/schemas"
echo "Installing JSON schemas..."
for schema in "$REPO_DIR"/schemas/*.json; do
    [ -f "$schema" ] || continue
    link_file "$schema" "$CLAUDE_DIR/schemas/$(basename "$schema")"
done
# <<< dynamic-roster-1-tags: schemas/ propagation
```

Sentinel comments make the block idempotent on re-run (matches `feedback_install_adopter_default_flip.md` discipline). After T10, the agent **must** invoke the `autorun-shell-reviewer` subagent against the `install.sh` change (and re-invoke after T8's run-tests.sh change) before declaring Wave B done — per `feedback_build_subagent_invocations_must_fire.md`.

### Wave C — verification (T11 / T12 / T13)

**T11.** `bash tests/run-tests.sh` exits 0. Pass count = `<previous_count> + 4`. Zero regressions.

**T12.** Two greps:
- A9 dormancy: `grep -rn 'fit_tags' scripts/ commands/ tests/` matches only `tests/test-persona-fit-tags.sh` and the schema files. Anything else surfaces a stowaway consumer.
- A13 reader audit (R2): `grep -rnE 'sed -n.*personas/|head -n.*personas/|awk.*NR.*personas/|cut.*personas/.*\.md' scripts/` returns empty. Confirms no positional reader exists. Investigation already shows `_roster.py` and `compute-persona-value.py` are SHA-256 whole-file readers (D9), and `resolve-personas.sh` doesn't touch persona body — but the grep makes it auditable.

**T13.** Invoke `Agent(subagent_type: "autorun-shell-reviewer")` with the two changed shell files (`install.sh` after T10, `tests/run-tests.sh` after T8). Treat its High findings as blocking. Note: `tests/test-persona-fit-tags.sh` is NEW shell; the reviewer should also pass it through — supply it in the same invocation.

---

## Acceptance Criteria (mapped to spec + new ACs)

Spec ACs A1–A12 stand. The plan adds three to close review gaps:

- **A13 (new, addresses R2/D9):** No code path under `scripts/`, `commands/`, or `tests/` reads persona frontmatter positionally. Verified by grep audit (T12).
- **A14 (new, addresses R3):** `install.sh` symlinks `schemas/*.json` into `$CLAUDE_DIR/schemas/`, sentinel-bracketed for idempotent re-runs. Smoke-tested by re-running `bash install.sh` in a clean shell and confirming no duplicate symlinks.
- **A15 (new, addresses gaps-C2):** A new persona file added to `personas/{review,plan,check}/` without `fit_tags:` causes `bash tests/run-tests.sh` to exit non-zero. Manually verified once during /build by adding a sentinel `personas/check/_AC15_test.md` without frontmatter, running tests, confirming exit ≠ 0, and removing the sentinel.

Pass-count contract clarified: A7 reads `<previous_count> + 4` (per D7).

---

## Risks (consolidated)

| ID  | From         | Severity | Status         | Mitigation                                                                |
|-----|--------------|----------|----------------|---------------------------------------------------------------------------|
| R1  | risk         | High     | Mitigated      | Wave B is sequential single-writer (one agent for T8/T9/T10).             |
| R2  | risk         | High     | Investigated   | No positional readers exist (D9). A13 grep audit makes it ongoing.       |
| R3  | risk         | Medium   | Mitigated      | A14 + T10 sentinel-bracketed install block.                                |
| R4  | risk         | Medium   | Documented     | `$id` /v1/ + extension policy in tag-enum.schema.json `description`.       |
| R5  | risk         | Medium   | Mitigated      | T9 explicit insertion anchor + verbatim text.                              |
| R6  | risk         | Low      | Mitigated      | Pre-backfill count gate (find ... \| wc -l = 19).                          |
| R7  | risk         | Low      | Mitigated      | Edit anchors keyed on `name:` line, not `---`.                             |
| R8  | risk         | Low      | Mitigated      | D1 dropped PyYAML dependency entirely; stdlib regex only.                  |
| RP1 | feasibility  | Medium   | Mitigated      | D2 — schemas validated as JSON, not as JSON Schema 2020-12.                |
| RP2 | gaps-I3      | Low      | Documented     | LoC target ≤80 is aspirational (D8); 90 LoC ceiling acceptable.            |
| RP3 | hash-rotation| Low      | Documented     | D9 + CHANGELOG note in T9.                                                 |

---

## Open Questions (none blocking)

- **OQ1 (Q-mapping-validation, deferred):** are the 19 persona→tag mappings empirically right? Slice 3 will surface; PR-scope corrections, not blocking.
- **OQ2 (gaps-I5):** existing specs in `docs/specs/` lack `tags:`. Slice 1 grandfathers them per Edge Case 7. Slice 2's `_tag_baseline.py` will likely backfill on first auto-run.
- **OQ3 (stakeholders-2):** adopters with custom personas: their personas will fail `tests/test-persona-fit-tags.sh` until they backfill. CHANGELOG note in T9 flags this; not blocking slice 1 ship.

---

## Out of Scope (carried forward to slices 2–5)

Verbatim from spec §Out of scope. Plan adds no new deferrals.

- `_tag_baseline.py`, `_tier_assign.py`, `_persona_score.py` — slice 2/3.
- `scripts/resolve-personas.sh` extension (tag intersection) — slice 3.
- Command-md updates (`commands/*.md` Phase 0b) — slice 4.
- `scripts/autorun/*.sh` tier suffix parsing — slice 4.
- `dashboard/index.html` tier-mix column — slice 5.
- `/spec` Phase 3 LLM-propose-user-confirm — slice 2.
- `personas/README.md` tag-taxonomy doc — slice 3.
- Schema lockstep CI guard (test that asserts `$id` versions are coherent) — slice 2 or 3 (when there's a schema migration to enforce).
- `additionalProperties: false` tightening on `spec-frontmatter.schema.json` — slice 2.

---

## Sequencing Notes

- **Wave-sequencer rule (data → UI → tests):** there's no UI in slice 1; sequencing collapses to data (schemas + persona backfill) → tests (fit-tags test) → integration (run-tests + install + CHANGELOG).
- **`/build` orchestrator instruction:** dispatch Wave A as parallel subagents. After all Wave A subagents return DONE, run **one** sequential subagent for Wave B (T8/T9/T10 in order). Then Wave C verification by the orchestrator (or one final subagent).
- **Pre-commit gate:** invoke `autorun-shell-reviewer` BEFORE any commit that includes shell file changes (install.sh, run-tests.sh, the new test). Per `feedback_build_subagent_invocations_must_fire.md`, this is non-negotiable.
- **Revert profile:** single revert commit cleanly removes all of slice 1. No data migrations to undo (schemas are new files; persona edits are single-line additions). `persona_content_hash` re-rotates back to pre-slice values.

---

**Plan ready for /check.**
