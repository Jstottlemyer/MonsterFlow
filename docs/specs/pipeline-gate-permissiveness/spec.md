---
status: shipped
feature: pipeline-gate-permissiveness
created: 2026-05-05
revised: 2026-05-05 (post-/spec-review v1; 3 architectural blockers fixed inline + 5 warn-route items applied)
constitution: none — session roster only
session_roster: pipeline defaults (27)
gate_mode: permissive
gate_max_recycles: 2
confidence:
  scope: 0.95
  ux: 0.92
  data: 0.94
  integration: 0.94
  edge_cases: 0.92
  acceptance: 0.92
  average: 0.93
---

# Pipeline Gate Permissiveness Spec

> Session roster only — run /kickoff later to make this a persistent constitution.

## Summary

Apply autorun v6's per-axis warn/block policy framework inward to the interactive pipeline gates (`/spec-review`, `/plan`, `/check`). Findings are classified into 6 axes; only `architectural` and `security` findings halt re-cycles. `contract`, `documentation`, `tests`, and `scope-cuts` route to a `followups.jsonl` (authoritative; rendered to `followups.md` for human reading) that `/build` consumes in wave 1, scheduled by a `target_phase` tag (`build-inline | plan-revision | docs-only | post-build`). Re-cycles cap at 2; iteration 3+ auto-promotes non-`architectural`/`security` findings and emits `GO_WITH_FIXES`. Mode is sticky at the spec frontmatter (`gate_mode: permissive | strict`, default `permissive`); one-shot `--strict` / `--permissive` CLI overrides; strict frontmatter is un-overridable except via `--force-permissive`. Verdict is the existing JSON `check-verdict` fence at `check-verdict@2.0` (additive fields under a schema bump).

## Backlog Routing

| # | Item | Routing | Reason |
|---|---|---|---|
| 1 | `pipeline-gate-permissiveness` | **(a) In scope** | This spec |
| 2 | `pipeline-gate-rightsizing` | (b) Stays | Sibling; sequenced after this lands |
| 3 | `install-sh-backup-uninstall` | (b) Stays | Independent M task |
| 4 | `autorun-verdict-deterministic` | (b) Stays | Sibling; different threat model (unattended autorun, not interactive gates) |
| 5 | Stage-boundary STOP-check inside `run.sh` | (b) Stays | Independent S task |
| 6 | Promote `tests/test-policy-json.sh` | (b) Stays | Independent S task |
| 7 | Per-plugin cost measurement | (b) Stays | Blocked on token-economics Phase 0 |
| 8 | Plugin scoping per gate | (b) Stays | Blocked on #7 |
| 9 | Holistic token-cost instrumentation | (b) Stays | Partially promoted; remainder blocked |
| 10 | Account-type agent scaling | (b) Stays | Blocked on token-economics |
| 11 | Inter-agent debate via Agent Teams | (b) Stays | Blocked on #7 + #10 |

## Scope

**In scope**
- New 6-class taxonomy applied at `/spec-review`, `/plan`, `/check`: `architectural` / `security` / `contract` / `documentation` / `tests` / `scope-cuts` (+ `unclassified` as fail-closed fallback).
- Per-class verdict policy (block / warn / polish) with permissive and strict defaults; `unclassified` is hardcoded-block in both modes.
- Sticky mode declaration via spec frontmatter `gate_mode:` (default `permissive`).
- One-shot CLI overrides: `/check --strict`, `/check --permissive`; strict frontmatter is un-overridable except via `--force-permissive` (same flag pattern for `/spec-review`, `/plan`).
- Hard re-cycle cap (default 2, configurable to 5 via frontmatter `gate_max_recycles:`); cap is per-gate, not pipeline-global.
- Authoritative `docs/specs/<feature>/followups.jsonl` artifact (one row per active warn-routed finding); `followups.md` rendered from it deterministically for human reading. Each row has lifecycle state (`open` / `addressed` / `superseded`), `target_phase` (`build-inline` / `plan-revision` / `docs-only` / `post-build`), and dedupe key (`finding_id`). `/build` consumes `followups.jsonl` in wave 1, filtered to `state: open`, scheduled by `target_phase`.
- JSON-fenced verdict block compatible with autorun v6's `extract-fence` machinery; ships under `check-verdict@2.0` (schema bump, additive fields). Reuse fence label `check-verdict`; preserve required fields (`schema_version`, `prompt_version`, `verdict`, `blocking_findings[]`, `security_findings[]`, `generated_at`); add `iteration`, `iteration_max`, `mode`, `mode_source`, `class_breakdown`, `followups_file`, `cap_reached`. Generalize fence label to `gate-verdict` only if v2 needs it.
- Reviewer-side `class:` tagging on each finding; Judge highest-class-wins dedup AND has reclassification authority (Judge may upgrade a cluster's class if a contributor's body shows it's mis-tagged); Synthesis renders the verdict from aggregated counts.
- Autorun lockstep: `schemas/check-verdict.schema.json` bump + `_policy_json.py` validator update + `scripts/autorun/check.sh` `GO_WITH_FIXES` handling all ship in the SAME PR.
- Migration UX: stderr banner at gate entry on specs without `gate_mode:` declared; `install.sh` upgrade path prints a one-time note; CHANGELOG entry under v0.9.0.

**Out of scope**
- `/build` gate-style permissiveness (execution discipline, not finding-routing — different problem class).
- Removing the LLM from the verdict trust path — that's `autorun-verdict-deterministic`'s job (different threat model: unattended overnight runs, not human-in-loop interactive review).
- Per-class mode override (e.g., `gate_overrides: {documentation: warn, tests: block}`) — escape hatch for v2 if a real complaint surfaces. v1 ships with global mode only.
- Adaptive re-cycle cap by class mix — over-engineered for v1; flat cap-of-2 suffices for the empirical pattern.
- Taxonomy expansion to data-loss / migration-risk / operational-reliability / performance-regression / observability-gap / release-rollback / supply-chain axes — these are real but defer to v2. v1 routes them under `architectural` (if structural) or `contract` (if pin-shaped). The taxonomy has a documented extension point so v2 is additive.
- Work-class → gate-intensity mapping (skip /spec-review for bug fixes, etc.) — that's `pipeline-gate-rightsizing`, the sibling spec sequenced after this one.

## Approach

**Port autorun v6's per-axis policy inward.** The autorun-overnight-policy session shipped a per-axis warn/block framework where each axis (security, integrity, etc.) has hardcoded carve-outs and tunable policy for the rest. The same shape applies to interactive gates — reviewer findings carry an axis (here: `class`), the policy table maps `(class, mode) → verdict`, and the verdict aggregator applies highest-class-wins on dedup.

Reuse, don't reinvent:
- The YAML-fenced verdict shape and `extract-fence` extractor from autorun v6.
- The `_policy_json.py` validator pattern (extend `check-verdict.schema.json`, don't create a parallel schema).
- The persona-metrics `findings.jsonl` row shape (already JSONL, already has severity — adding `class` is additive).
- The `feedback_obvious_decisions.md` UX principle: when the right answer is structurally obvious ("apply this docs nit inline"), make it and document it instead of asking three iterations of "fix now / defer / hold."

Empirical basis from the autorun-overnight-policy v4 retrospective (recorded in [[projects/MonsterFlow/concepts/pipeline-gate-permissiveness]]): ~30% of /check must-fixes were genuinely architectural; ~70% were contract pins, framing, or test additions that landed inline in /build's first commits anyway. v4's two documentation MFs were applied inline in 30 minutes — the cap-of-2 + auto-promote model formalizes that empirical pattern.

Approach explored alternatives:
- **3-tier flat taxonomy (block/warn/polish)** rejected — forces the judge to do the architectural-vs-contract distinction implicitly; the 6-class taxonomy makes it explicit and gives `pipeline-gate-rightsizing` a stable axis to key roster decisions off later.
- **Default strict, opt into permissive** rejected — preserves halt-on-everything as default, defeating the motivation; users wouldn't discover the new framework until they hit the flag.
- **Synthesis-only classification** rejected — loses per-reviewer context (security-architect persona knows what's a security finding; a downstream classifier doesn't).
- **Deterministic post-processor (no LLM in verdict path)** rejected for *this* spec — that's the right answer for `autorun-verdict-deterministic` (different threat model). Mixing them couples two specs that should ship independently.

## Roster Changes

No roster changes. The 27 pipeline defaults already cover this work-class (the spec is *about* the pipeline); no new domain specialist is required. If `/check` reveals a coverage gap (e.g., a finding-classification specialist who can validate the class taxonomy on real fixtures), promote at that gate.

## UX / User Flow

### Authoring a spec with a non-default gate mode

```
$ /spec security-token-rotation
… Q&A …
[written: docs/specs/security-token-rotation/spec.md]

# user edits frontmatter:
gate_mode: strict
gate_max_recycles: 5
```

Subsequent `/spec-review` / `/plan` / `/check` runs read these knobs from frontmatter automatically. No per-invocation flag needed.

### Running a default-permissive gate

```
$ /check pipeline-gate-permissiveness
[gate] No gate_mode declared in frontmatter — defaulting to permissive. Pin gate_mode: strict to preserve pre-v0.9.0 halt-on-anything behavior. (silenced after first run)
… 5 reviewers run; Judge aggregates; Synthesis writes verdict …

```check-verdict
{
  "schema_version": 2,
  "prompt_version": "check-verdict@2.0",
  "verdict": "GO_WITH_FIXES",
  "stage": "check",
  "iteration": 1,
  "iteration_max": 2,
  "mode": "permissive",
  "mode_source": "default",
  "blocking_findings": [],
  "security_findings": [],
  "class_breakdown": {
    "architectural": 0, "security": 0, "contract": 3,
    "documentation": 2, "tests": 2, "scope-cuts": 0, "unclassified": 0
  },
  "class_inferred_count": 0,
  "followups_file": "docs/specs/pipeline-gate-permissiveness/followups.jsonl",
  "cap_reached": false,
  "generated_at": "2026-05-05T18:30:00Z"
}
```

→ followups.jsonl regenerated (7 active rows); followups.md re-rendered. /build wave 1 will consume rows where state="open" AND target_phase ∈ {build-inline, docs-only}.
```

### One-shot strict override (matches frontmatter)

```
$ /check pipeline-gate-permissiveness --strict
… verdict shows mode: strict, mode_source: cli, all 7 findings in blocking_findings[] …
```

### Strict frontmatter, attempted permissive override

```
$ /check security-token-rotation --permissive
ERROR: spec declares gate_mode: strict; cannot override without --force-permissive
$ /check security-token-rotation --force-permissive
[gate] WARNING: --force-permissive overriding gate_mode: strict on a strict-flagged spec.
       This is auditable: appended to docs/specs/security-token-rotation/.force-permissive-log
       with timestamp + iteration + user. Verdict will record mode_source: cli-force.
… verdict shows mode: permissive, mode_source: cli-force …
$ cat docs/specs/security-token-rotation/.force-permissive-log
2026-05-05T18:30:00Z iteration=1 user=jstottlemyer gate=check
```

### Re-cycle cap reached

```
$ /check feature-xyz   # iteration 3, after two NO_GO cycles
… Judge produces 4 findings (1 architectural, 3 documentation) …
[gate] cap reached: gate_max_recycles=2; auto-promoting non-architectural/security/unclassified to followups.jsonl

```check-verdict
{
  "schema_version": 2,
  "prompt_version": "check-verdict@2.0",
  "verdict": "NO_GO",
  "stage": "check",
  "iteration": 3,
  "iteration_max": 2,
  "mode": "permissive",
  "mode_source": "frontmatter",
  "blocking_findings": [{"persona": "scope-discipline", "finding_id": "ck-9a3b4c5d6e", "summary": "Spec scope is two features"}],
  "security_findings": [],
  "class_breakdown": {
    "architectural": 1, "security": 0, "contract": 0,
    "documentation": 3, "tests": 0, "scope-cuts": 0, "unclassified": 0
  },
  "class_inferred_count": 0,
  "followups_file": "docs/specs/feature-xyz/followups.jsonl",
  "cap_reached": true,
  "generated_at": "2026-05-05T18:35:00Z"
}
```
```

## Data & State

### Class taxonomy

| Class | Permissive verdict | Strict verdict | Tiebreaker / Notes |
|---|---|---|---|
| `architectural` | block | block | Hardcoded. Structural reshape of the spec; new component; trust-boundary change. *Tiebreaker vs `scope-cuts`:* "structural reshape" → architectural; "remove an in-scope item" → scope-cuts. |
| `security` | block | block | Hardcoded. Auth, authz, secret handling, prompt-injection, untrusted input. Maps to existing `sev:security` tag (see Integration: `class:security` ↔ `sev:security` mapping). |
| `contract` | warn → followups | block | API/CLI/schema pins, signature gaps. *Tiebreaker vs `documentation`:* if the fix is a code/schema change → contract; if prose-only → documentation. |
| `documentation` | warn → followups | block | README, comments, plan/spec framing — fix is prose-only. |
| `tests` | warn → followups (with carve-outs) | block | Missing test coverage. **Carve-out:** tests covering a *changed trust boundary*, *data migration*, *CLI/schema contract*, or *previous regression* → upgrade to `architectural` at Judge step. |
| `scope-cuts` | warn → followups (load-bearing only) | warn → followups | Nice-to-haves; do-not-add suggestions. **Carve-out:** if the cut would *destabilize delivery* (e.g., "this spec includes a second feature") → upgrade to `architectural`. |
| `unclassified` | block | block | Fail-closed fallback. Reviewer omits `class:` OR emits a value not in the enum → coerced to `unclassified` at Judge step with `class_inferred: true`. Blocks until Judge/Synthesis assigns a real class. |

**Hardcoded carve-outs:** `architectural`, `security`, `unclassified` (always block). The mode flag flips only `contract`, `documentation`, `tests`, `scope-cuts`.

**Taxonomy extension hook (v2):** the class enum is closed for v1. v2 may add data-loss / migration-risk / perf / observability axes; the schema's `class` field will accept them under a `prompt_version` bump without breaking existing rows.

### Spec frontmatter additions

```yaml
gate_mode: permissive | strict   # default: permissive
gate_max_recycles: 2             # default: 2; max: 5
```

Both are read by `/spec-review`, `/plan`, `/check`. Absent fields use defaults.

### Finding schema (additive)

Extend the existing reviewer finding row (already JSONL in `persona-metrics`):

```json
{"persona": "scope-discipline", "severity": "M", "class": "documentation",
 "finding_id": "MF3", "title": "...", "body": "...", "suggested_fix": "...",
 "class_inferred": false, "source_finding_ids": ["MF3"]}
```

`class` is required for all reviewer outputs in v1. **Fail-closed coercion at Judge step:** if a reviewer (a) omits `class:`, OR (b) emits a value not in the enum (`architectural | security | contract | documentation | tests | scope-cuts | unclassified`), Judge coerces to `class: unclassified` and sets `class_inferred: true`. `unclassified` blocks in both modes, so the missing-data path is fail-closed (no silent demotion of a security finding to `contract: warn`). This replaces the v0 spec's `class: contract` fallback.

`class_inferred` lives on the JSONL row, not the verdict block. The verdict aggregates `class_inferred_count: int` for `/wrap-insights` consumption.

`source_finding_ids` is a Judge-populated list of contributing reviewer-row IDs after dedup (one row per reviewer; this list is `[finding_id]` when no merge occurred, `[id_a, id_b, …]` after a merge). Enables persona-metrics joins across iterations.

### Verdict schema extensions — `check-verdict@2.0`

The existing `schemas/check-verdict.schema.json` (autorun v6) is the contract: **JSON-fenced** (label `check-verdict`), persisted as `check-verdict.json` sidecar, required fields `schema_version`, `prompt_version`, `verdict`, `blocking_findings[]`, `security_findings[]`, `generated_at`. `verdict` enum already includes `GO_WITH_FIXES` (no enum change needed). `additionalProperties` is currently `false` — this spec bumps `schema_version: 2`, `prompt_version: "check-verdict@2.0"` and adds the following fields:

```json
{
  "iteration": 1,                                  // 1-indexed; increments past iteration_max only when cap reached
  "iteration_max": 2,                              // = gate_max_recycles from frontmatter
  "mode": "permissive",                            // "permissive" | "strict" — the active mode
  "mode_source": "frontmatter",                    // "frontmatter" | "cli" | "cli-force" | "default"
  "class_breakdown": {                             // counts of post-Judge findings by class
    "architectural": 0, "security": 0, "contract": 3,
    "documentation": 2, "tests": 2, "scope-cuts": 0,
    "unclassified": 0
  },
  "class_inferred_count": 0,                       // findings coerced to `unclassified` at Judge step
  "followups_file": "docs/specs/<slug>/followups.jsonl",  // null iff no warn-routed findings exist
  "cap_reached": false,                            // true iff iteration > iteration_max
  "stage": "check"                                 // "spec-review" | "plan" | "check" — for v2 cross-stage consumers
}
```

`blocking_findings[]` (existing) carries `architectural | security | unclassified` findings. `security_findings[]` (existing) is a subset of `blocking_findings[]` — preserved for autorun v6 compat. `class:security` findings populate both during the migration window; v2 may collapse the duplication.

The fence label and required fields are unchanged from autorun v6, so existing `extract-fence` machinery continues to work. **Schema bump is NOT optional** — `additionalProperties: false` rejects every new field until the schema ships. See Integration: autorun lockstep.

**Generalization to `gate-verdict@1.0`:** the same shape applies at `/spec-review` and `/plan`. Fence label and schema are reused as `check-verdict` for v1 (one-PR landing). v2 may rename to `gate-verdict@1.0` if cross-stage consumers need a stable contract — additive rename, no field changes.

### `followups.jsonl` artifact (authoritative)

Single rolled-up file at `docs/specs/<feature>/followups.jsonl` — the **authoritative store**. JSONL, one row per active warn-routed finding. Conforms to `schemas/followups.schema.json` (NEW).

```json
{
  "schema_version": 1,
  "prompt_version": "followups-emit@1.0",
  "finding_id": "ck-9a3b4c5d6e",          // dedupe key — same shape as findings.jsonl
  "source_gate": "check",                  // "spec-review" | "plan" | "check" — lifecycle reconciliation is scoped to source_gate == current_gate
  "source_iteration": 1,                   // iteration of the source gate that emitted this row
  "class": "contract",
  "title": "Pin the --strict flag's exit code",
  "body": "<verbatim from findings.jsonl>",
  "suggested_fix": "Document --strict returns 2 on NO_GO, matching autorun convention.",
  "target_phase": "build-inline",          // "build-inline" | "plan-revision" | "docs-only" | "post-build"
  "state": "open",                         // "open" | "addressed" | "superseded"
  "addressed_by": null,                    // commit SHA or PR ref when state="addressed"; written by /build wave-final; null while open
  "previously_addressed_by": null,         // when state transitions addressed → open (regression), the prior addressed_by SHA is preserved here
  "regression": false,                     // true iff this row is a regression — was previously state:addressed and re-surfaced
  "superseded_by": null,                   // finding_id of the row that replaced this one; null while open/addressed
  "created_at": "2026-05-05T18:00:00Z",
  "updated_at": "2026-05-05T18:00:00Z"
}
```

**Lifecycle (regenerate-active, scoped to `source_gate == current_gate`):** at each gate iteration, Synthesis reads the existing `followups.jsonl` and reconciles ONLY rows where `source_gate == current_gate`. Rows from other gates are untouched (a `/plan` iteration must not supersede `/check`'s open rows, and vice versa). For each post-Judge warn-routed finding from the current gate:

1. If `finding_id` matches an existing `state: open` row (same `source_gate`) → update `updated_at` and `source_iteration`; do not duplicate.
2. If `finding_id` matches a `state: addressed` row (same `source_gate`) → **transition the row back to `state: open`** with `regression: true` set on the row, `updated_at: now`, `source_iteration` updated. The original `addressed_by` value is preserved on the row as `previously_addressed_by` (audit trail). This is a regression: the author had marked it fixed and it resurfaced. Surfaces in `/wrap-insights` as a regression signal.
3. If `finding_id` is new → append a new row with `state: open`, `source_gate: <current_gate>`.
4. For each existing `state: open` row WHERE `source_gate == current_gate` AND whose `finding_id` does NOT appear in this iteration's post-Judge warn-routed set → mark as `state: superseded`, set `superseded_by: null` (pure removal), `updated_at: now`. Author either fixed it before this iteration ran, OR Judge reclassified it elsewhere. Rows from OTHER gates remain untouched.

This eliminates the "stale findings preserved forever" pathology AND prevents cross-gate corruption (gate B's regeneration cannot supersede gate A's open rows). `/build` filters to `state: open` regardless of `source_gate`, but only after verifying the most-recent verdict is `GO` or `GO_WITH_FIXES` (see Integration `commands/build.md`).

**`target_phase` assignment:** Synthesis tags each new row at write time. Defaults by class:
- `architectural` → never lands here (blocks)
- `security` → never lands here (blocks)
- `contract` → `build-inline` (default) or `plan-revision` if the fix requires re-design (Synthesis judgment)
- `documentation` → `docs-only`
- `tests` → `build-inline` (default) or `post-build` if the test additions are observability/regression rather than gating
- `scope-cuts` → `post-build` (mention in PR; do not require build action)

`/build` wave 1 consumes rows where `state: "open"` AND `target_phase IN ("build-inline", "docs-only")`. `plan-revision` rows trigger a `/plan` re-run. `post-build` rows are PR-body annotations.

**Atomicity:** read existing → mutate in-memory → write `.tmp` → rename. Standard atomic-write-replace, since this is regenerate-from-active rather than blind append. Multi-writer protection: a lock-file `.followups.jsonl.lock` is acquired by Synthesis (the sole writer per gate); concurrent gate runs queue rather than race.

### `followups.md` (rendered, not authoritative)

Generated deterministically from `followups.jsonl` by a Python helper (`scripts/render-followups.py`). Filtered to `state: open`. Grouped by `target_phase`, then by `class`. One section per `target_phase`. **Never hand-edited.** Header includes a `<!-- generated from followups.jsonl; do not edit by hand -->` sentinel.

`/build` wave 1 reads `followups.jsonl` (authoritative); humans read `followups.md`. The two are kept in sync by `render-followups.py` invoked at the end of each gate's Synthesis step.

## Integration

**Files modified:**
- `commands/spec-review.md` — verdict logic + frontmatter read + `--strict`/`--permissive`/`--force-permissive` parse + `followups.jsonl` regenerate + `render-followups.py` invocation
- `commands/plan.md` — same
- `commands/check.md` — same
- `commands/build.md` — wave-1 task list reads `followups.jsonl` if present, BUT FIRST verifies the most-recent gate verdict (read from `check-verdict.json` or equivalent stage sidecar) is `GO` or `GO_WITH_FIXES`. If the latest verdict is `NO_GO`, `/build` refuses to start (existing behavior; `followups.jsonl` is not consumed). If the latest verdict is `GO`/`GO_WITH_FIXES`, filter to `state: open` AND `target_phase IN (build-inline, docs-only)`; `plan-revision` rows trigger `/plan` re-run; `post-build` rows become PR-body annotations. This guards against strict-mode runs leaving stale `state: open` rows visible to `/build`.
- `commands/spec.md` — Phase 3 frontmatter schema gains `gate_mode`, `gate_max_recycles`
- `personas/{review,plan,check}/*.md` (~28 files) — instruct each reviewer to emit `class:` in findings; **template-batched** (write once, get approval, batch-apply per `feedback_template_first_batching.md`)
- `personas/judge.md` — highest-class-wins dedup AND reclassification authority; coercion rule for missing/invalid `class` → `unclassified`; tiebreaker rules from the Class taxonomy table
- `personas/synthesis.md` — render verdict JSON fence from aggregated counts; regenerate `followups.jsonl` per the lifecycle rules; invoke `render-followups.py`
- `schemas/check-verdict.schema.json` — `schema_version: 2`, `prompt_version: check-verdict@2.0`, additive fields per the Verdict schema extensions; `additionalProperties: false` preserved. **Exhaustive new-field list (9 fields; missing any one rejects every verdict on first run):** `iteration`, `iteration_max`, `mode`, `mode_source`, `class_breakdown`, `class_inferred_count`, `followups_file`, `cap_reached`, `stage`. CI fixture-test must validate each field's presence in the schema.
- `schemas/findings.schema.json` — additive `class`, `class_inferred`, `source_finding_ids`
- `scripts/autorun/check.sh` — already extracts the JSON `check-verdict` fence; updated to honor `iteration` / `iteration_max` / `cap_reached` for iteration-loop termination; treats `verdict: GO_WITH_FIXES` as iteration-stop equivalent of `GO` (existing enum, new semantics)
- `scripts/_policy_json.py` — validator update for `check-verdict@2.0`
- `install.sh` — one-time upgrade banner on first run after v0.9.0 install

**Files created:**
- `schemas/followups.schema.json` — JSONL row schema for `followups.jsonl`
- `scripts/render-followups.py` — deterministic `followups.jsonl` → `followups.md` renderer
- `tests/test-permissiveness.sh` — fixtures for the (mode, class) matrix + the additional cases below.
- `tests/fixtures/permissiveness/*.findings.jsonl` — fixtures exercising: each class × each mode; mixed-class findings; dedup-disagreement (two reviewers, different `class`); missing/invalid `class:` coerced to `unclassified`; stale-followups-from-prior-permissive-run; cap-reached-with-security; cap-reached-in-strict; CLI override precedence; legacy sidecars.

**Autorun lockstep (single-PR landing):** the schema bump (`check-verdict@2.0`), `_policy_json.py` validator update, and `scripts/autorun/check.sh` iteration-stop handling MUST land in the same PR as the persona/command changes. `additionalProperties: false` rejects every new field until the schema bumps; partial landing breaks autorun on first run. CI guard: `tests/test-autorun-policy.sh` validates the bumped schema against fixture verdicts before the PR can merge.

**`class:security` ↔ `sev:security` mapping:** existing autorun blocks on `sev:security` tags via `security_findings[]`. v1 of this spec preserves both: any finding with `class:security` ALSO gets `sev:security` tag emitted by Judge AND populates `security_findings[]`. Removing the duplication is deferred to v2 (after one release of dual-mechanism running in production proves equivalence).

**Persona-metrics integration:** `findings.jsonl` rows gain `class`, `class_inferred`, `source_finding_ids` (additive). Pre-v0.9.0 rows lack these fields; `/wrap-insights` Phase 1c reads `class` with default `unclassified` for missing-field rows, AND filters survival-rate joins to `class != "unclassified"` so historical rows don't pollute per-class stats.

**Default-flip migration UX:**
- **Stderr banner at gate entry** when a spec lacks an explicit `gate_mode:` field (one-time per session per spec): `[gate] No gate_mode declared in frontmatter — defaulting to permissive. Pin gate_mode: strict to preserve pre-v0.9.0 halt-on-anything behavior.` Suppression sentinel: `docs/specs/<feature>/.gate-mode-warned`.
- **`install.sh` upgrade note** on first run after v0.9.0 install: prints a one-paragraph migration block describing the default flip + how to opt back into strict per-spec.
- **CHANGELOG.md** entry under v0.9.0 with the migration bullet.

**Sequencing:** independent of `pipeline-gate-rightsizing` (sibling); but autorun-side changes ride this spec's PR. Lands as v0.9.0; back-compat tag pinned to v0.8.x for adopters who want to defer.

## Edge Cases

1. **Reviewer omits `class:` on a finding, OR emits a value not in the enum.** Judge coerces to `class: unclassified` and sets `class_inferred: true` on the row. `unclassified` is hardcoded-block in both modes (fail-closed). Replaces v0's `class: contract` fallback (which silently demoted security findings to warn in permissive mode).

2. **Class disagreement across reviewers (one says `architectural`, another says `documentation`).** Highest-class-wins: `architectural > security > unclassified > contract > tests > documentation > scope-cuts`. Single source of truth in `personas/judge.md`. **Judge has reclassification authority:** if a contributor's body shows the cluster is mis-tagged (e.g., security findings hidden under `documentation`), Judge upgrades to the correct class.

3. **Iteration 3 has only architectural findings.** Hard cap doesn't auto-promote architectural/security/unclassified — they still halt. Verdict shows `cap_reached: true` AND `verdict: NO_GO` AND `iteration > iteration_max`. User decides: bump `gate_max_recycles` in frontmatter and re-run (iteration counter resets to 1 on a clean re-invocation; survives across re-cycles within one invocation), or address inline.

4. **CLI `--strict` on a spec with `gate_mode: strict` frontmatter.** No conflict. `mode: strict`, `mode_source: cli` (CLI was the proximate source even though it matches frontmatter).

5. **CLI `--permissive` on a spec with `gate_mode: strict` frontmatter.** **Rejected by default.** Strict frontmatter is un-overridable except via `--force-permissive`; bare `--permissive` exits with an error message naming the conflict. With `--force-permissive`: `mode: permissive`, `mode_source: cli-force`. Two side-effects fire BEFORE the gate runs: (a) loud stderr banner naming the override + path to the audit log; (b) a row appended to `docs/specs/<feature>/.force-permissive-log` with `<UTC-timestamp> iteration=<N> user=<git-user> gate=<gate-name>` for post-hoc audit. Architectural / security / unclassified still block (carve-outs are not mode-flippable).

5b. **CLI `--force-permissive` on a `gate_mode: permissive` spec.** No-op override (no strict to escape). `mode: permissive`, `mode_source: cli` (NOT `cli-force` — the force semantic only applies when overriding strict). No audit-log row written.

6. **`--strict --permissive` (or `--permissive --strict`) on the same invocation.** Last-flag-wins is rejected (silent ambiguity). Exit with an error naming both flags.

7. **`/check` runs against a spec with no frontmatter at all.** First run: stderr banner ("`No gate_mode declared … defaulting to permissive`"), touch suppression sentinel, proceed with `mode: permissive`, `mode_source: default`. Subsequent runs: no banner.

8. **`followups.jsonl` from a prior iteration contains rows the author already fixed.** Synthesis regenerates active rows from this iteration's post-Judge findings. Rows whose `finding_id` doesn't appear in the new set are marked `state: superseded`. `/build` filters to `state: open`, so superseded rows don't re-enter the build queue.

9. **`/build` runs against a pre-v0.9.0 spec (no `followups.jsonl`, no `gate_mode:` frontmatter).** Behavior unchanged; wave 1 reads only plan.md as today. No banner (banner is gate-time, not build-time).

10. **Strict-mode run after a permissive run that left `followups.jsonl` populated.** Strict run does NOT regenerate `followups.jsonl` (strict means halt; nothing to warn-route). Existing rows are left intact (audit trail). Verdict's `followups_file` field references the existing path; `/build` filtering by `state: open` AND the gate's `verdict: NO_GO` semantics keeps stale rows from being consumed (build only proceeds on GO / GO_WITH_FIXES). On next permissive run, regenerate-active reconciles state.

11. **Frontmatter declares `gate_max_recycles: 10` (above the max).** Clamp to 5 with a stderr warning **once per session** (cached in `docs/specs/<feature>/.recycles-clamped` sentinel). Spec's recorded value unchanged (so `git diff` doesn't fight the user).

12. **Adversarial finding tagged `class: scope-cuts` to bypass a real architectural concern.** Mitigations: (a) highest-class-wins dedup catches it if any other reviewer tags it correctly; (b) Judge's reclassification authority catches it if a contributor's body content reveals the mis-tag; (c) the `tests` and `scope-cuts` carve-outs (load-bearing → architectural) catch the most common shape. Residual single-reviewer mis-tags remain — threat model assumes reviewer good-faith; adversarial-prompt-injection-resistance is `autorun-verdict-deterministic`'s problem.

13. **Required schema field omitted from a hand-edited verdict block.** `_policy_json.py` validator rejects on read. The gate command shells out to the validator immediately after Synthesis writes the verdict (write-time validation), surfacing errors before the user moves on. Synthesis re-emits on validation failure.

14. **Multiple gates writing `followups.jsonl` concurrently** (e.g., autorun runs `/spec-review` while the user manually runs `/check` on a different spec). Per-spec `.followups.jsonl.lock` lock-file acquired by Synthesis; the second writer waits or aborts with a clear error. Within one spec's pipeline, gates are serialized by construction (`/spec-review` blocks `/plan` blocks `/check` blocks `/build`).

15. **`render-followups.py` produces stale output if `followups.jsonl` was hand-edited.** The rendered `followups.md` carries a `<!-- generated; do not edit -->` sentinel; pre-commit hook (separate spec, optional) can validate the sentinel. v1 ships render-on-Synthesis only; manual re-render is `python3 scripts/render-followups.py docs/specs/<feature>/`.

16. **Late-cycle clarifications (deferred from /check + /plan):**

    16a. **Reworded-finding dedup-key drift.** If a reviewer rewords a finding across iterations, the `finding_id` hash changes. Iteration N-1's row gets `state: superseded`; iteration N writes a new `state: open` row. `/build` is unaffected (it filters to `state: open` regardless of source-rewording history). Persona-metrics survival joins MAY undercount survival rate for reworded findings — this is acceptable v1 behavior; semantic dedup is deferred to v2 (e.g., body-shingle fingerprinting).

    16b. **Renderer-failure recovery path.** If `scripts/render-followups.py` fails AFTER `followups.jsonl` is atomically written (e.g., disk full, transient I/O error), the gate does NOT block. The verdict is still emitted (Synthesis owns that path); `followups.md` may be stale or absent. The next gate run regenerates. No silent data loss — `followups.jsonl` is the authoritative store.

    16c. **`iteration > iteration_max` semantics.** The iteration counter in `.iteration-state.json` is 1-indexed. It increments past `iteration_max` only ONCE — the cap-reached terminal write at iteration `iteration_max + 1`. Anything above that is malformed; autorun's `check.sh` bound-check (W1.7) rejects it. Manual re-runs reset the counter to 1 unless `--no-reset-iteration` is passed (or the operator manually preserves the sidecar).

    16d. **Per-spec banner once-per-session-per-spec semantics.** The per-spec sentinel `docs/specs/<feature>/.gate-mode-warned` is touched on first gate run after the per-user verbose banner has fired. It persists ACROSS sessions on disk (not session-scoped; the user can `rm` it to re-trigger). Multi-spec workflows: a user with N specs without `gate_mode` will see N per-spec one-line nudges (one per spec, but each only once across sessions per spec). The per-user verbose banner still fires once-ever per machine-version.

    16e. **Codex review at `/check` is mandatory** (per BACKLOG `codex-review-per-spec`): pipeline-gate-permissiveness's `/check` MUST include a Codex adversarial review. This was confirmed at /check-time and is locked at v0.9.0 ship. Future architectural specs follow the same convention.

## Acceptance Criteria

A1. `/check` on a spec with `gate_mode: permissive` (default) and 3 documentation findings emits `verdict: GO_WITH_FIXES`, regenerates `followups.jsonl` with 3 rows (`state: open`, `target_phase: docs-only`), renders `followups.md` from it, exits 0.

A2. Same scenario with `gate_mode: strict` (or `--strict` CLI) emits `verdict: NO_GO`, does NOT regenerate `followups.jsonl`. Pre-existing rows from prior permissive runs are left intact (audit trail). The verdict's `followups_file` field references the path if it exists, else `null`. Exits non-zero, lists all 3 as `blocking_findings[]`.

A3. `/check` with 1 architectural finding + 5 documentation findings: in BOTH permissive and strict modes, emits `verdict: NO_GO`, exits non-zero. Permissive: `followups.jsonl` contains the 5 docs findings (architectural in `blocking_findings[]`). Strict: no regenerate.

A4. `/check` iteration 3 (after two NO_GO re-cycles) with `gate_max_recycles: 2`: non-architectural / non-security / non-unclassified findings auto-promote to `followups.jsonl` (`state: open`); architectural / security / unclassified remain blocking. Verdict shows `cap_reached: true`, `iteration: 3`, `iteration_max: 2`.

A5. `/check` iteration 3 with `gate_max_recycles: 2` and ZERO architectural/security/unclassified findings: emits `verdict: GO_WITH_FIXES`, all findings regenerated into `followups.jsonl`, exits 0.

A6. `/spec-review` and `/plan` exhibit equivalent behavior on identical fixture inputs (same mode, same finding classes → same verdict, same followups split). Each gate's iteration counter is independent; per-gate cap (not pipeline-global).

A7. `/build` wave 1 first reads the most-recent stage verdict sidecar (e.g., `check-verdict.json`); proceeds only if `verdict ∈ {GO, GO_WITH_FIXES}`; refuses to start on `NO_GO`. On proceed: reads `followups.jsonl` filtered to `state: "open"` AND `target_phase IN ("build-inline", "docs-only")`, includes those rows in the wave-1 task list. `target_phase: plan-revision` rows trigger a `/plan` re-run rather than a build task. `target_phase: post-build` rows become PR-body annotations only. (A7-mid-upgrade): a `/build` against a pre-v0.9.0 spec (no `followups.jsonl`, no `check-verdict@2.0`) behaves as today (no verdict-check, no banner, no error). (A7-strict-stale): a `/build` invoked after a strict-mode `NO_GO` /check that left stale `state: open` rows from a prior permissive run → /build refuses (verdict is NO_GO).

A8. The verdict JSON fence parses cleanly through autorun v6's `extract-fence`, validates against `schemas/check-verdict.schema.json` at `schema_version: 2`. Required fields preserved (`schema_version`, `prompt_version`, `verdict`, `blocking_findings[]`, `security_findings[]`, `generated_at`); new fields (`iteration`, `iteration_max`, `mode`, `mode_source`, `class_breakdown`, `class_inferred_count`, `followups_file`, `cap_reached`, `stage`) all present and validated.

A8b. **Autorun lockstep:** `scripts/autorun/check.sh` end-to-end against a `verdict: GO_WITH_FIXES` fixture: does NOT trigger a re-cycle, does NOT trip the fix-attempt-on-Medium pathology, exits 0. Same fixture against `verdict: NO_GO`: re-cycles up to `gate_max_recycles`, exits non-zero on cap. CI guard rejects partial PR landings (schema bumped without `_policy_json.py` update or vice versa).

A9. Two reviewers disagree on class for the same finding → Judge dedup picks the higher class per the precedence rule; verdict counts reflect the higher class; `findings.jsonl` row has `source_finding_ids: [id_a, id_b]`. (A9b): one reviewer marks a finding `class: documentation` whose body content reads as a security issue → Judge reclassifies to `security` (reclassification authority).

A10. Reviewer omits `class:` field OR emits an out-of-enum value (e.g., `class: arch`) → Judge coerces to `class: unclassified` with `class_inferred: true` recorded on the JSONL row; verdict shows `class_inferred_count: 1`; `unclassified` blocks in both modes.

A11. CLI `--strict` on `gate_mode: permissive` frontmatter: verdict `mode: strict`, `mode_source: cli`, behavior matches strict mode for that run.

A11b. CLI `--permissive` on `gate_mode: strict` frontmatter without `--force-permissive`: gate exits with an error, no run. With `--force-permissive`: verdict `mode: permissive`, `mode_source: cli-force`, run proceeds, AND (a) stderr banner prints naming the override + audit-log path; (b) `docs/specs/<feature>/.force-permissive-log` gains a row with `<UTC-timestamp> iteration=<N> user=<git-user> gate=<gate-name>`. `--strict --permissive` together: gate exits with an ambiguity error. CLI `--force-permissive` on a `gate_mode: permissive` spec: no audit-log row, `mode_source: cli` (no strict to escape).

A12. `tests/test-permissiveness.sh` covers the (mode × class) matrix PLUS: mixed-class findings, dedup-disagreement (two reviewers, conflicting `class`), missing `class:` (omission), invalid `class:` (out-of-enum), stale-followups-from-prior-permissive-run, cap-reached-with-security, cap-reached-in-strict, CLI override precedence (`--strict`/`--permissive`/`--force-permissive`), legacy sidecars from pre-v0.9.0 specs, target_phase routing for each class. All pass.

A13. `gate_max_recycles: 10` (above the 5 max): clamps to 5 with a stderr warning **once per session** (cached in `.recycles-clamped` sentinel). The literal frontmatter value remains 10 (no auto-edit).

A14. `followups.jsonl` lifecycle (scoped to current gate): across iteration 1 → 2 → 3 in a single gate run, an open finding (`source_gate: check`) fixed before iteration 2 is marked `state: superseded` (not removed); a finding still present in iteration 2 has its `updated_at` and `source_iteration` updated (not duplicated); a new finding in iteration 2 is appended as a new `state: open` row. **Cross-gate isolation:** rows with `source_gate: spec-review` or `source_gate: plan` are NEVER touched by a `/check` iteration's regeneration, even if their `finding_id` is absent from /check's post-Judge set. `/build` wave 1 sees `state: open` rows from all gates. (A14b): `followups.md` is regenerated by `render-followups.py` after every `followups.jsonl` write and contains the `<!-- generated -->` sentinel. (A14d): a previously `addressed` row whose finding regresses transitions back to `state: open`, gains `regression: true` and `previously_addressed_by: <prior-SHA>`; surfaces as a regression signal in `/wrap-insights`.

A14c. **Concurrency:** two gates attempting to write `followups.jsonl` simultaneously → second writer waits on `.followups.jsonl.lock` (or aborts with a clear error if `--no-block` is set). No lost-update; no partial JSONL.

A15a. **Doc surfaces (blocking):** `docs/index.html` mermaid diagram updated to show the three-tier verdict (`GO` / `GO_WITH_FIXES` / `NO_GO`); CHANGELOG.md entry under v0.9.0 with the migration bullet (default flips from de-facto strict to permissive; how to opt back in via `gate_mode: strict`).

A15b. **Doc surfaces (follow-up, not blocking v0.9.0):** README `Pipeline` section narrative update. May land in v0.9.1 docs sweep.

A15c. **Version:** ships as v0.9.0 (minor bump from 0.8.0). Rationale lives in `project_versioning.md` memory + CHANGELOG, not in this AC.

A16. **Migration UX:** stderr banner at gate entry on a spec without `gate_mode:` declared in frontmatter prints exactly once per session (suppression sentinel `.gate-mode-warned`). `install.sh` upgrade path on first run after v0.9.0 install prints a one-paragraph migration note and only on first run (idempotent on subsequent invocations).

A17. **`class:security` ↔ `sev:security` parity:** any finding with `class: security` ALSO populates `security_findings[]` and carries `sev:security` tag, preserving autorun v6 security-blocking semantics. Removed in v2 after one release proves equivalence.

## Open Questions

Closed in this revision:

- **(was O1) In-flight spec migration:** RESOLVED — implicit `gate_mode: permissive` default applies to existing specs. Migration UX (stderr banner + install.sh note + CHANGELOG) addresses surprise. Adopters who want to preserve halt-on-anything pin `gate_mode: strict` in frontmatter (one line edit per spec).

Remaining (non-blocking, surfaceable in `/plan`):

- O2. Whether `personas/judge.md`'s highest-class-wins + reclassification-authority rules need a recursive self-test (Judge reviewing its own classification fixtures) or just doc rule + per-fixture tests is enough. Lean: per-fixture.
- O3. Exact wording for stderr banner / install.sh migration paragraph / CHANGELOG bullet — defer to /build wave 5 (writes once, locked thereafter).
- O4. v0.9.0 version-pin coordination with the reserved grep-fallback removal (memory `project_versioning.md`): both can ride v0.9.0 (additive), or grep-fallback bumps to v0.9.1. Lean: ride together.
