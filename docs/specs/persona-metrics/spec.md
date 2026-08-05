---
status: shipped
---

# Persona Metrics Spec

**Created:** 2026-04-26
**Revised:** 2026-04-26 (post-review v1.1 — 12 Before-You-Build items resolved, 4 Important items folded in)
**Constitution:** none yet for `MonsterFlow`; proceeded without constraints (tracked in Backlog Routing — same precedent as `pipeline-wiki-integration`)
**Confidence:** 0.93 (post-review)
**Session Roster:** pipeline defaults only (28 personas) + Codex adversarial reviewer; no domain add-ons.

> Session roster only — `MonsterFlow` still has no constitution. Same follow-up as `pipeline-wiki-integration`.

## Summary

Add a measurement layer to the multi-agent pipeline that records, per persona, how often its contributions were unique and load-bearing across **all three multi-agent gates: `/spec-review`, `/plan`, and `/check`**. Five new artifacts per feature per stage — `source.<artifact>.md` snapshot (where applicable), `findings.jsonl`, `participation.jsonl`, `run.json`, and `survival.jsonl` — feed an on-demand rollup rendered as a diff in default `/wrap-insights` and a full table via a new `/wrap-insights personas` subcommand. The survival classifier runs at the start of `/plan`, `/check`, and `/build`, judging the prior gate's findings against the artifact at that point. For `/spec-review` and `/check` the classifier compares pre/post snapshots so "addressed" means *addressed by the revision*. For `/plan` (which synthesizes `plan.md` fresh from design recommendations rather than revising it) the classifier judges *which design recommendations made it through Judge into `plan.md`* — the same load-bearing question, applied to synthesis-time inclusion. Tiering rules and probe sampling are deliberately deferred to a follow-up `persona-tiering` spec; this spec ships measurement only, with a schema (`schema_version`, `prompt_version`, `artifact_hash`, `run_id`) designed so the follow-up requires no migration.

## Backlog Routing

| # | Item | Source | Decision |
|---|---|---|---|
| 1 | Multi-model agent roster (Codex/Kimi for review stages) | memory: `project_multi_model_roster.md` | **Stays** — adjacent direction; this spec records `model` per persona so multi-model is evaluable later, but doesn't ship it. |
| 2 | Workflow install drift (spec.md + symlink hygiene) | memory: `project_workflow_install_drift.md` | **Stays** — unrelated infra cleanup. |
| 3 | Constitution for `MonsterFlow` | `spec-upgrade` confidence note | **Stays** — separate `/kickoff` work. |
| 4 | Uncommitted statusline + settings changes | `git status` | **Stays** — unrelated to persona-metrics. |

Open Questions sections in all three existing specs are empty. No deferred phases. No `Next Up` items in CLAUDE.md.

## Scope

### In Scope

- **Pre-review artifact snapshot** at `/spec-review` and `/check` *start*. Before the reviewer agents run, copy the artifact under review (revised or original `spec.md` / `plan.md`) to `docs/specs/<feature>/<stage>/source.spec.md` (or `source.plan.md`). The survival classifier later receives both this snapshot and the post-review revised artifact, so `addressed` means *addressed by the revision*, not "already in source." **`/plan` does not snapshot** — `plan.md` is synthesized fresh at `/plan` time, not revised; there is no pre-state to capture.
- **`findings.jsonl` emit** at the end of synthesis at all three multi-agent gates (`/spec-review`, `/plan`, `/check`). One row per finding cluster (not per persona-mention). Schema includes `schema_version: 1`, `prompt_version`, `finding_id`, `stage` ∈ {`"spec-review"`, `"plan"`, `"check"`}, `personas[]` (includes `"codex-adversary"` when Codex contributed at `/spec-review`/`/check`/`/build`), `title`, `body`, `severity`, `unique_to_persona`, `model_per_persona{}`, `mode: "live"`, `normalized_signature`. At `/plan`, "findings" are design recommendations the design personas raised; `personas[]` lists the design personas (api / data-model / ux / scalability / security / integration) that contributed to the cluster. `mode`, `model_per_persona`, and `normalized_signature` reserved for future probe sampling and multi-model A/B comparison.
- **`participation.jsonl` emit** alongside `findings.jsonl` at all three gates — one row per persona that *ran*, regardless of whether it raised a finding. Fixes survivorship bias. Schema: `persona`, `model`, `findings_emitted` (count), `status` (`"ok"` / `"failed"` / `"timeout"`). `/wrap-insights` rollup uses this to compute denominators honestly.
- **`run.json` manifest** per stage write — captures `run_id` (uuid4), `command` (`"/spec-review"` / `"/plan"` / `"/check"`), `prompt_version`, `model_versions{}`, `artifact_hash` (sha256 of the source snapshot at `/spec-review`/`/check`; sha256 of the produced `plan.md` at `/plan`), `created_at`, `output_paths`, `status`, `warnings[]`. One file per stage write.
- **`survival.jsonl` emit** at the start of three downstream stages:
  - **`/plan` Phase 0** judges `<feature>/spec-review/findings.jsonl` against `source.spec.md` + revised `spec.md`. Outcome semantics: addressed-by-revision.
  - **`/check` Phase 0 (new)** judges `<feature>/plan/findings.jsonl` against `plan.md`. Outcome semantics: *did the design recommendation appear in the synthesized plan?* Because `plan.md` is freshly synthesized (not revised), there is no source snapshot for `/plan`; the classifier compares findings against `plan.md` alone. `addressed` = the design recommendation visibly shaped `plan.md`. `not_addressed` = Judge dropped or demoted it. `rejected_intentionally` = `plan.md` explicitly notes alternatives-considered or rejected-recommendations sections naming this finding.
  - **`/build` Phase 0** judges `<feature>/check/findings.jsonl` against `source.plan.md` + revised `plan.md`. Outcome semantics: addressed-by-revision.
- **Idempotency + stale survival detection** — at every Phase 0 invocation, the classifier compares the recorded `artifact_hash` in `survival.jsonl` against the current artifact hash. Match → skip. Differ → re-classify and overwrite `survival.jsonl`. `/wrap-insights` warns when a feature's current artifact hash doesn't match its recorded hash (stale survival).
- **Rotate-before-write rule** — at `/spec-review`, `/plan`, and `/check` synthesis *write* time, if `findings.jsonl` already exists in the target directory, rename it to `findings-<UTC-ts>.jsonl` *before* writing the new file. Filename is the superseded marker; no schema mutation. The downstream Phase 0 reads only the canonical `findings.jsonl`. Rotation at the *write* site (not read site) closes a race where a second emit would overwrite the first round before the next stage runs.
- **Atomic writes** — every `findings.jsonl`, `survival.jsonl`, `participation.jsonl`, and `run.json` write goes through `<name>.tmp` → atomic `rename`. A crash mid-write leaves the prior file intact, never a partial.
- **Timestamp format** — all rotation filenames use `%Y-%m-%dT%H-%M-%SZ` UTC (colon-free) for cross-platform safety. On same-second collision (clock skew), append `-<run_id-prefix>`.
- **Three prompt files** under a new `commands/_prompts/` directory:
  - `commands/_prompts/findings-emit.md` — referenced by `commands/spec-review.md` and `commands/check.md`. Specifies clustering rules, persona attribution from raw outputs (incl. Codex), `normalized_signature` computation, `finding_id` derivation, `participation.jsonl` and `run.json` emission, atomic-write discipline.
  - `commands/_prompts/survival-classifier.md` — referenced by `commands/plan.md` and `commands/build.md`. Receives `findings.jsonl`, `source.<artifact>.md`, and the current revised artifact in one batched call; emits `survival.jsonl` with one row per finding (no per-finding LLM calls). Includes `evidence`-substring validator: each non-`"no change"` quote must appear verbatim in the revised artifact, else outcome demoted to `not_addressed` with confidence `low`.
  - `commands/_prompts/snapshot.md` — small inline directive used by `commands/spec-review.md` and `commands/check.md` to copy the pre-review artifact to `source.<name>.md`.
- **`/wrap-insights` Persona Drift section (default)** — diff render against the prior 10-feature window, with ↑/↓/→ arrows on `load_bearing_rate` and `uniqueness_rate`. **Deadband:** arrows render only when `|delta| ≥ 5` percentage points; smaller deltas → render as `→`. Personas with <3 runs in the current window render as `(insufficient data — N runs)` and are excluded from drift arrows. Output includes a one-line legend on first run per session: `legend: load-bearing = unique × addressed; uniqueness = sole-source rate`.
- **`/wrap-insights personas` tab-completable subcommand** — full table, sorted by `load_bearing_rate` descending. Surfaces both `load_bearing_rate` and `survival_rate` independently so a high-survival/low-uniqueness "frequent corroborator" persona is visible as a distinct shape from a low-survival/high-uniqueness "lone-wolf" persona.
- **Rollup as on-demand projection** — `/wrap-insights` reads each feature's `<stage>/findings.jsonl`, `participation.jsonl`, and `survival.jsonl` fresh on each invocation. **Rolling window definition:** "feature" = a `docs/specs/<slug>/` directory; ordering = ascending `survival.jsonl` mtime in the `spec-review/` subdir; "last 10" = the 10 most recent by that ordering. Stages without `survival.jsonl` are excluded. **Stale-hash warning** when a feature's recorded `artifact_hash` no longer matches its current artifact.
- **Adopter privacy posture** — for adopter repos using `MonsterFlow`, the per-feature `findings.jsonl` `body` field contains verbatim review prose that may be sensitive. Adopters can either (a) set `PERSONA_METRICS_GITIGNORE=1` in their environment — `/spec-review` emits a `.gitignore` line for the metrics files automatically — or (b) manually add the metrics paths to their `.gitignore`. Default in `MonsterFlow`'s own repo: committed (matches existing precedent of committing review/check artifacts). Documented in CLAUDE.md template and a `## Privacy` subsection in the new `docs/persona-metrics.md` adopter note.
- **Documentation update** —
  - `README.md` mermaid pipeline diagram: dotted feedback edges from `/wrap-insights` to `/spec-review` and `/check`, labeled "drift surfaces".
  - `docs/index.html` mermaid: same edges.
  - `commands/flow.md` reference card: one-line note about drift surfacing.
  - `CHANGELOG.md`: entry for persona-metrics measurement layer.
  - Pipeline prose: factual update only (mention the new measurement artifacts and the `/wrap-insights` drift surface). Defer the full *"measurement loop → optimization loop"* reframe until `persona-tiering` ships, so framing matches reality on day one.

### Out of Scope

- **Tiering rules** (Core / Conditional / Demoted classification, the 20%/5% thresholds from the original sketch). Belongs in follow-up `persona-tiering` spec.
- **Spec-keyword triggers** for conditional personas (security only when auth/PII; a11y only when UI; perf only when latency SLO). Same follow-up.
- **Probe sampling** of demoted personas (random N% shadow runs to refresh metrics and detect re-promotion candidates). Same follow-up. Schema reserves `mode: "probe"` so no migration is needed.
- **Multi-model A/B comparison** between Codex and Claude personas. Schema records `model_per_persona{}` so the comparison is computable later, but no UI or rule ships here.
- **Classifier accuracy validation** (≥8/10 human-agreement check on a sample of survival classifications). Belongs in `persona-tiering` where it actually drives a decision (do we trust the classifier enough to demote?). Validating it here, before any threshold rule exists, validates against nothing.
- **Automated roster edits** — even after tiering ships, demotion/re-promotion stays human-in-the-loop. The pipeline never silently drops a persona.

## Approach

**Chosen: layered emission with deferred pre/post classification.**

1. At `/spec-review` (and `/check`) *start*, snapshot the artifact under review → `source.<name>.md`. Then if `findings.jsonl` exists, rotate it to `findings-<UTC-ts>.jsonl`. *Then* run reviewers.
2. At synthesis end, the synthesizer emits `findings.jsonl` (clustered, with `personas[]` attributed from raw outputs including Codex), `participation.jsonl` (every persona that ran), and `run.json` (manifest with `run_id`, hashes, model versions). All writes atomic.
3. At the next stage's start (`/plan` or `/build`), the survival classifier checks `artifact_hash` against the current revised artifact. If unchanged from a prior classification, skip. Otherwise run one batched LLM call against `findings.jsonl` + `source.<name>.md` + revised artifact → writes `survival.jsonl`.
4. At `/wrap-insights` time, the rollup is computed as a pure projection over `docs/specs/*/`. No derived state file.

**Why this shape:**

- Pre/post snapshotting means the classifier can distinguish *"the revision addressed this"* from *"the source already addressed this"* — without it, every finding whose concern was already in v1 silently inflates the survival rate.
- Rotation at the *write* site (not read site) closes a race where a second `/spec-review` overwrites the first round before `/plan` runs.
- Persona attribution is sourced from raw persona outputs at synthesis time, not reverse-engineered from prose — `unique_to_persona`, `uniqueness_rate`, and `load_bearing_rate` all depend on this being correct.
- `participation.jsonl` fixes survivorship bias: a persona that ran but found nothing has a row, so denominators are honest.
- `run.json` + `schema_version` + `prompt_version` + `artifact_hash` make every row interpretable across schema/prompt evolution and let `/wrap-insights` detect stale classifications.
- Idempotency via `artifact_hash` means `/plan` re-runs are cheap (skip when nothing changed) and stale survival is detectable (warn when changed).
- Decoupled extraction (synthesis-time) from judgment (next-stage classifier) means a bad classification re-runs cheaply without re-running the whole review.
- On-demand projection eliminates a whole class of derived-state-desync bugs.

**Alternatives considered (and rejected) — Q&A trail + post-review:**

- *Inline classifier at revision time* — couples extraction and judgment in one call; harder to audit when a class fires wrong.
- *Manual finding tagging* — high friction; user skips it under time pressure, silently bad data.
- *Text-overlap heuristic for survival* — addressed-as-rephrased findings won't keyword-match (a "missing input validation" finding fixed by a paragraph about request schemas diverges textually).
- *Always-on full table in `/wrap-insights`* — gets scanned-then-ignored after a few cycles; the default render should highlight *change*.
- *Standalone rollup file* — derived state that can desync from source files, gets half-written on crash, raises "which file is authoritative" question.
- *4-state outcome taxonomy with `partially_addressed`* — that bucket is where two LLM runs disagree most; dropping it forces commitment and keeps the metric crisp.
- *5-state taxonomy* (Codex-proposed: `addressed_by_revision` / `already_addressed` / `not_addressed` / `intentionally_deferred` / `rejected_as_invalid`) — Codex's `already_addressed` concern is real but resolved by the pre/post snapshot inside the existing 3-state taxonomy: with `source.spec.md` available, "addressed" means *the revision changed in a way that addresses the finding*, so `already_addressed` is folded into `not_addressed` (the revision didn't drive the change). Keeps classifier cognitive load low.
- *Inline prompt strings in command files* — both prompts are reused twice from day one, so inline = four copies of two strings = guaranteed drift.
- *Eager classifier on every save* — burns LLM budget on keystroke saves; double-counting risk on iterative revision.
- *`finding_id` from raw `title` hash* — title is LLM-generated and varies across re-runs of synthesis. Hashing instead on `normalized_signature` (sha256 of sorted source-persona-output substrings that fed the cluster) is stable across synthesis re-runs given the same raw inputs.
- *Rotate at `/plan` pre-flight (read site)* — second `/spec-review` overwrites first round before `/plan` ever sees it. Rotation must happen at `/spec-review` write site.

## Roster Changes

No roster changes. The existing 28 default personas cover review and check; this spec adds infrastructure around them, not a new specialist.

## UX / User Flow

### Reviewer flow (modified)

1. User runs `/spec-review`.
2. **New (pre-review):** the command snapshots the artifact under review (`spec.md`) to `docs/specs/<feature>/spec-review/source.spec.md`. If a prior `findings.jsonl` already exists in that directory, it's atomically renamed to `findings-<UTC-ts>.jsonl` *before* the new run starts.
3. The 6 PRD reviewer agents (Claude personas) run; Codex adversarial reviewer runs if available (existing Phase 2b behavior).
4. The synthesizer composes `review.md` as today.
5. **New (synthesis post-step):** synthesizer runs `commands/_prompts/findings-emit.md` against the raw persona outputs and clusters → atomically writes `findings.jsonl` (with `personas[]` correctly attributed from raw outputs, including `"codex-adversary"` when applicable), `participation.jsonl` (every persona that ran), and `run.json` (manifest with `run_id`, `prompt_version`, `model_versions{}`, source `artifact_hash`).
6. User revises `spec.md` based on `review.md`. Same flow as today.

`/check` follows the identical shape, writing to `docs/specs/<feature>/check/{source.plan.md, findings.jsonl, participation.jsonl, run.json}`.

### Survival classifier flow (new)

1. User runs `/plan` (or `/build`).
2. **New pre-flight:** the command looks for `findings.jsonl` in the prior stage's directory (`spec-review/` for `/plan`, `check/` for `/build`). If absent → silently skip; no `survival.jsonl` written; the next `/wrap-insights` notes "no findings to classify for this feature, this stage."
3. **Idempotency check:** if `survival.jsonl` exists, compare its recorded `artifact_hash` to the current `sha256(revised_artifact)`. Match → skip (already current). Differ → re-classify and overwrite (stale survival).
4. **Classifier runs once, batched:** prompt at `commands/_prompts/survival-classifier.md` receives the entire `findings.jsonl` + the prior-stage `source.<artifact>.md` snapshot + the current revised artifact in one prompt → atomically writes `survival.jsonl` with one row per finding.
5. **Evidence validator:** before write, each non-`"no change"` `evidence` quote is checked as a verbatim substring of the revised artifact. If absent (hallucinated quote), the row's `outcome` is demoted to `not_addressed` and `confidence` set to `low`.
6. Command continues with its existing work. Instrumentation never blocks the stage — see Edge Cases for failure handling.

### Reading flow — drift render

1. User runs `/wrap-insights` (existing command, opt-in `/wrap` variant).
2. **New:** a Persona Drift section is added to `/wrap-insights` output (alongside the existing `/insights` surfacing, not replacing it). It reads `<feature>/<stage>/{findings,participation,survival}.jsonl` for every feature in `docs/specs/`, computes per-persona rolling-window stats over the last 10 features (ordered by ascending `survival.jsonl` mtime in `spec-review/`), and renders the diff. Arrows render only when `|delta| ≥ 5` percentage points:

```
=== Persona drift (last 10 features vs prior 10) ===
legend: load-bearing = unique × addressed; uniqueness = sole-source rate

↑ a11y          load-bearing  4% → 18%  (3 features had UI scope)
↓ test-quality  load-bearing 22% →  9%  (recent flags duplicated correctness)
↓ security      uniqueness   85% → 60%  (codex-adversary flagged same items)
   no change: 14 personas
   insufficient data (N<3): 3 personas
   stale survival (artifact changed after classification): 1 feature
```

3. User can run `/wrap-insights personas` for the full rolling-window table. The full table surfaces `load_bearing_rate` AND `survival_rate` independently — a high-survival/low-uniqueness "frequent corroborator" persona is shape-distinct from a low-survival/high-uniqueness "lone wolf" persona, both of which are valuable in different ways.

> **What does the user *do* with drift signal between this spec and `persona-tiering`?** Manual roster review — eyeball the drift table, make judgment calls about which personas are earning their slot. Tiering rules in the follow-up spec automate this; for now it stays human-in-the-loop.

## Data & State

### Per-feature artifacts (committed to repo by default — see Privacy below)

```
docs/specs/<feature>/
  spec-review/
    source.spec.md                              # snapshot of spec.md at /spec-review start
    raw/<persona>.md                            # raw output per reviewer (incl. codex-adversary.md if applicable)
    findings.jsonl                              # current; written at /spec-review synthesis
    findings-2026-04-26T10-15-22Z.jsonl         # superseded (only on iterative re-review)
    participation.jsonl                         # every persona that ran this stage
    run.json                                    # manifest: run_id, prompt_version, hashes, status
    survival.jsonl                              # written at /plan start; judges spec-review findings
  plan/
    raw/<persona>.md                            # raw output per design persona
    findings.jsonl                              # written at /plan synthesis (design recommendations)
    participation.jsonl
    run.json
    survival.jsonl                              # written at /check start; judges plan findings
                                                # NOTE: no source.plan.md — plan.md is synthesized,
                                                # not revised, so there is no pre-state snapshot
  check/
    source.plan.md                              # snapshot of plan.md at /check start
    raw/<persona>.md                            # raw output per check reviewer (incl. codex-adversary.md)
    findings.jsonl
    participation.jsonl
    run.json
    survival.jsonl                              # written at /build start; judges check findings
```

**Privacy:** in adopter repos, `findings.jsonl` body fields contain verbatim review prose that may be sensitive. Adopters set `PERSONA_METRICS_GITIGNORE=1` to opt-out (auto-gitignore), or manually add the metrics paths to `.gitignore`. Default in `MonsterFlow`'s own (public) repo: committed.

**Timestamp format** for rotation filenames: `%Y-%m-%dT%H-%M-%SZ` UTC (colon-free, cross-platform safe). Same-second collision: append `-<run_id-prefix>`.

### `findings.jsonl` schema (one JSON object per line, one row per cluster)

```json
{
  "schema_version": 1,
  "prompt_version": "findings-emit@1.0",
  "finding_id": "sr-a7c4f2e891",
  "stage": "spec-review",
  "personas": ["security", "ux"],
  "title": "Auth flow doesn't specify token revocation timing",
  "body": "<verbatim strongest single statement from any persona that raised this cluster>",
  "severity": "major",
  "unique_to_persona": null,
  "model_per_persona": {"security": "claude-opus-4-7", "ux": "claude-opus-4-7"},
  "normalized_signature": "<sha256 of sorted persona-output substrings that fed this cluster>",
  "mode": "live"
}
```

Field rules:

- `schema_version: 1` today. Bumped on any breaking schema change. Old rows remain readable; rollup branches on version.
- `prompt_version`: identifier of the `findings-emit.md` prompt revision that produced this row. Old rows stay interpretable when the prompt evolves.
- `finding_id` = `<stage-prefix>-` + first **10** chars of `sha256(normalized_signature)`. 10 chars (40 bits) reduces collision risk over time vs the originally-proposed 6.
- `normalized_signature` = `sha256` (full hex) of a deterministic representation of the cluster: the sorted, lowercased, whitespace-collapsed list of source-persona-output substrings that fed the cluster (NOT the synthesizer-generated `title`, which varies across LLM re-runs). This is what makes `finding_id` stable across synthesis re-runs given identical raw inputs.
- `stage` ∈ {`"spec-review"`, `"check"`}.
- `personas` = every persona that raised this cluster, including `"codex-adversary"` when Codex contributed (per existing Phase 2b integration). One row per cluster, never per persona-mention.
- `severity` ∈ {`"blocker"`, `"major"`, `"minor"`, `"nit"`}.
- `unique_to_persona` is a denormalized convenience: non-null iff `len(personas) == 1`; equals `personas[0]` in that case. Derivable from `personas[]` — readers may compute either way.
- `model_per_persona` records the model that produced each persona's contribution (e.g. `{"security": "claude-opus-4-7", "codex-adversary": "codex"}`). Populated today; used by future multi-model A/B comparison without migration.
- `mode` reserved: `"live"` today, `"probe"` when probe sampling ships. (Superseded iterative-re-review rounds are marked by filename rename, not by mutating this field.)

### `participation.jsonl` schema (one row per persona that ran this stage)

```json
{
  "schema_version": 1,
  "stage": "spec-review",
  "persona": "security",
  "model": "claude-opus-4-7",
  "findings_emitted": 3
}
```

Lists every persona invoked during the stage, regardless of finding count. A persona that ran but raised nothing has `findings_emitted: 0` — visible in the rollup as "ran 8/10 features, 0 unique findings," which is meaningful data (drift candidate). Without this file, zero-finding personas would be invisible (survivorship bias).

### `run.json` schema (one file per stage write)

```json
{
  "schema_version": 1,
  "run_id": "<uuid4>",
  "command": "/spec-review",
  "prompt_version": "findings-emit@1.0",
  "model_versions": {"reviewer-default": "claude-opus-4-7", "codex-adversary": "codex"},
  "artifact_hash": "<sha256 of source.spec.md>",
  "created_at": "2026-04-26T10:15:22Z",
  "output_paths": ["spec-review/findings.jsonl", "spec-review/participation.jsonl"],
  "status": "ok"
}
```

`status` ∈ {`"ok"`, `"partial"`, `"failed"`}. Per-stage manifest closes audit, debug, and reproducibility gaps in one artifact.

### `survival.jsonl` schema (one JSON object per line, one row per finding from prior stage)

```json
{
  "schema_version": 1,
  "prompt_version": "survival-classifier@1.0",
  "finding_id": "sr-a7c4f2e891",
  "outcome": "addressed",
  "evidence": "Added §3.4: Token revocation triggers within 5s of logout request.",
  "confidence": "high",
  "artifact_hash": "<sha256 of revised spec.md at classification time>"
}
```

Field rules:

- `outcome` ∈ {`"addressed"`, `"not_addressed"`, `"rejected_intentionally"`, `"classifier_error"`}. The error case is *not* a sidecar — it's an outcome value, preserving one-row-per-finding schema integrity. `evidence` for `classifier_error` carries the error reason; `confidence` is `"low"`.
- `addressed` means the *revision* (post-review artifact) addresses the finding in a way the *source* (pre-review snapshot) did not. Both files are inputs to the classifier. Findings whose concern was already satisfied in the source classify as `not_addressed` — the persona didn't drive the change.
- `evidence` is a verbatim quote from the revised artifact, ≤120 Unicode codepoints (not bytes); `"no change"` literal when `outcome == "not_addressed"`. Validator: each non-`"no change"` quote must appear as a substring in the revised artifact, else outcome demoted to `not_addressed` and `confidence` demoted to `low`.
- `rejected_intentionally` requires explicit naming in the revised artifact's `## Open Questions`, `## Out of Scope`, `## Backlog Routing`, or `## Deferred` section (case-insensitive header match). Absence is not rejection.
- `confidence` reflects classifier certainty: `"low"` preferred over guessing when the revision is ambiguous. Logged but not currently used in rollup math (reserved for future weighted survival).
- `artifact_hash` records `sha256` of the revised artifact at classification time. On `/plan` (or `/build`) re-run, comparing this against `sha256(current_revised_artifact)` tells the classifier whether to skip (match) or re-run (differ). Stale survival is detectable when current artifact's hash doesn't match the recorded hash — `/wrap-insights` warns.

### Rollup (computed on demand by `/wrap-insights`, never stored)

**Window definition:** "feature" = a `docs/specs/<slug>/` directory; ordering = ascending `survival.jsonl` mtime in the `spec-review/` subdir; "last 10" = the 10 most recent by that ordering. Stages without `survival.jsonl` are excluded from window membership. The same window definition applies to "prior 10" for trend comparison.

For each persona over the rolling window:

| Field | Definition |
|---|---|
| `participated_count` | count of stages this persona ran (from `participation.jsonl`), regardless of findings emitted |
| `runs` | count of stages where this persona emitted at least one finding |
| `findings_total` | sum of cluster appearances by this persona |
| `unique_count` | rows where `unique_to_persona == this_persona` |
| `survived_count` | rows whose joined `survival.jsonl` row has `outcome == "addressed"` |
| `unique_and_survived_count` | both of the above on the same row |
| `uniqueness_rate` | `unique_count / findings_total` |
| `survival_rate` | `survived_count / findings_total` |
| `load_bearing_rate` | `unique_and_survived_count / findings_total` (the gold metric) |
| `rejected_intentionally_rate` | rows where outcome is `rejected_intentionally` / `findings_total` |
| `silent_rate` | `(participated_count - runs) / participated_count` — fraction of stages this persona ran but raised nothing |
| `trend` | ↑/↓/→ comparing the rate against the prior 10-feature window. Arrow renders only when `|delta| ≥ 5` percentage points. |

**On `load_bearing_rate` framing:** the metric correctly identifies *uniqueness × addressed-by-revision* but inherently penalizes a strong persona that frequently *corroborates* others' findings. The full table surfaces `survival_rate` independently so frequent-corroborator personas are visible as a distinct shape. Tiering logic (deferred to `persona-tiering`) will weight these accordingly; for now, both numbers are shown side-by-side.

`rejected_intentionally` counts as *not survived* for `survival_rate` (the finding didn't shape the artifact) but is tracked separately so a high `rejected_intentionally_rate` per persona surfaces "raises real concerns the user opts to defer" — useful future signal for tiering.

`silent_rate` flags personas that participate but rarely contribute — a high silent_rate is a soft demotion signal even when load_bearing_rate looks fine on the few findings that do appear.

## Integration

### Prerequisite (for `/plan`)

Before sequencing the implementation, `/plan` must survey the existing `commands/spec-review.md` and `commands/check.md` and confirm there's a discrete synthesizer step that can be extended with a structured emit. If synthesis is implicit/inlined today, factoring out the synthesis phase is prerequisite work — flag it as a blocker if encountered.

### Files modified

- `commands/spec-review.md` — pre-flight snapshots `spec.md` to `source.spec.md`, creates `<stage>/raw/`, persists each reviewer's raw output, rotates prior `findings.jsonl`; synthesizer post-step references `commands/_prompts/findings-emit.md`.
- `commands/plan.md` — **two new responsibilities**: (1) Phase 0 pre-flight runs `survival-classifier.md` against `<feature>/spec-review/findings.jsonl` (existing in scope (a)); (2) at synthesis end, persist each design persona's raw output to `<feature>/plan/raw/<persona>.md` and run `findings-emit.md` to write `<feature>/plan/findings.jsonl`, `participation.jsonl`, `run.json` (NEW in scope (b)). No `source.plan.md` — plan.md is synthesized fresh.
- `commands/check.md` — **two new responsibilities**: (1) Phase 0 pre-flight runs `survival-classifier.md` against `<feature>/plan/findings.jsonl` judging *synthesis-inclusion* against `plan.md` (NEW in scope (b); uses the variant directive in `survival-classifier.md` for synthesis-inclusion semantics — no source snapshot is passed); (2) existing review flow snapshots `plan.md` to `source.plan.md`, persists raw outputs, runs synthesis emit (mirrors `/spec-review`).
- `commands/build.md` — Phase 0 pre-flight against the `check/` directory (existing scope, addressed-by-revision semantics).
- `commands/wrap-insights.md` — adds Persona Drift section to default output; recognizes `personas` subcommand; renders stale-survival warning when applicable.
- `README.md` — mermaid pipeline diagram gains dotted feedback edges from `/wrap-insights` to `/spec-review` and `/check`, labeled "drift surfaces". Pipeline prose factually updated (mention measurement artifacts + drift surface); full *measurement-loop → optimization-loop* reframe deferred to `persona-tiering` ship.
- `docs/index.html` — same mermaid edges; same factual prose update.
- `commands/flow.md` — reference card mentions drift surfacing.
- `CHANGELOG.md` — entry for persona-metrics measurement layer.

### Files added

- `commands/_prompts/findings-emit.md` — synthesizer post-step prompt; specifies `findings.jsonl`, `participation.jsonl`, and `run.json` schemas, clustering rules, persona attribution from raw outputs (incl. Codex), `normalized_signature` computation, atomic-write discipline.
- `commands/_prompts/survival-classifier.md` — next-stage pre-flight prompt; specifies `survival.jsonl` schema and **two outcome-semantics modes**: (a) **addressed-by-revision** for `/plan` and `/build` Phase 0 (compares pre-snapshot vs revised artifact); (b) **synthesis-inclusion** for `/check` Phase 0 (compares findings vs `plan.md` alone — no pre-snapshot, since `plan.md` is freshly synthesized). The mode is selected by the calling command's invocation directive. Includes `evidence` substring validator, `artifact_hash` recording, idempotency check, batched single-call discipline.
- `commands/_prompts/snapshot.md` — small directive for snapshotting the artifact under review at `/spec-review` and `/check` start.
- `commands/wrap-insights-personas.md` — full-table subcommand mirroring the `wrap-quick`/`wrap-full` pattern.
- `docs/persona-metrics.md` — adopter note documenting the measurement layer + privacy posture (`PERSONA_METRICS_GITIGNORE` opt-out).

### `install.sh` changes

- Iterate `commands/_prompts/*.md` and symlink to `~/.claude/commands/_prompts/`. Same pattern as the existing `commands/*.md` iteration; backup-to-`.bak` for any pre-existing regular files (existing helper).
- Pick up `commands/wrap-insights-personas.md` automatically (existing `commands/*.md` glob already handles new files).
- Honor `PERSONA_METRICS_GITIGNORE=1` env var on install: append the metrics paths to `.gitignore` in the user's project (idempotent).

### Dependencies

- No new runtime dependencies. Both prompts are LLM-only; no libraries added.
- Existing `python3.11` already used by other workflow scripts; not required by this feature.

## Edge Cases

- **Bug-fix or small-change path** — user skips `/spec-review` and `/check` entirely. No rollup contribution. Rollup is per-feature-per-stage; absent stages don't contribute. Honest by construction.
- **Iterative re-review** — running `/spec-review` (or `/check`) twice writes the second `findings.jsonl` *after* renaming the first to `findings-<UTC-ts>.jsonl`. Rotation happens at write site, not read site, so the second run can't clobber the first. Only the canonical `findings.jsonl` counts; superseded rounds remain auditable on disk under timestamped names.
- **Same-second rotation collision** — clock skew or rapid re-runs may produce two `findings-<UTC-ts>.jsonl` candidates with the same timestamp. Append `-<run_id-prefix>` (8 chars of `run_id`) to disambiguate.
- **Crash mid-write** — atomic-write discipline (`<name>.tmp` → `rename`) means a crashed run leaves the prior file intact, never a partial. The next run reads the prior canonical file and overwrites cleanly.
- **Concurrent invocation** — running `/wrap-insights` while `/spec-review` is mid-synthesis is safe: atomic-write guarantees `/wrap-insights` reads either the prior canonical version or the new one, never a partial. Cross-stage races (`/plan` mid-classify while `/spec-review` re-runs) are unlikely in solo-dev tmux flow but follow the same atomic-write protection.
- **Stalled pipeline** — `/spec-review` runs but `/plan` never does. `findings.jsonl` exists; no `survival.jsonl`. Findings remain unclassified and don't contribute to the rollup until the pipeline advances.
- **`/plan` re-run on unchanged spec** — classifier compares recorded `artifact_hash` against current `sha256(spec.md)`; on match, skip (no LLM call, no rewrite). Idempotent.
- **`/plan` re-run after spec edit** — `artifact_hash` mismatch → re-classify and overwrite `survival.jsonl`. The prior `survival.jsonl` is *not* archived because the rollup only ever uses the latest classification.
- **Stale survival** — user edits `spec.md` after `/plan` has already classified, then runs `/wrap-insights` without re-running `/plan`. Recorded `artifact_hash` no longer matches current spec hash; `/wrap-insights` renders a one-line warning: `stale survival (artifact changed after classification): N feature(s)`. User can re-run `/plan` to refresh.
- **Missing prior `findings.jsonl`** — legacy spec or skipped stage. Classifier silently skips; no `survival.jsonl` written. `/wrap-insights` notes "no findings to classify for this feature, this stage."
- **Cold start** — fewer than 10 features have run end-to-end. Drift compares against whatever prior window exists; personas with <3 runs in current window render as `(insufficient data — N runs)`. After ~10 real features, drift becomes meaningful. Empty rollup renders: *"Persona drift: no measured features yet — run 1+ feature through `/spec-review` and `/plan` to seed."*
- **Persona added or removed mid-window** — `participation.jsonl` records who ran in each stage. A persona added partway has fewer runs and falls into `insufficient data` until ≥3. Persona removal: their old rows stay in `findings.jsonl`/`participation.jsonl` historically, but no new runs accumulate.
- **Renamed personas** — treated as a new persona. Old name accumulates no new runs and naturally drops out; new name starts fresh. A future `personas.alias.json` could merge them, deferred.
- **Persona zero-findings** — captured in `participation.jsonl` (`findings_emitted: 0`). Surfaces as `silent_rate` in the rollup. A persona that ran 8/10 features with 0 findings is visible — not invisible.
- **Classifier returns malformed JSON** — write fails on schema validation. Each affected finding gets a row with `outcome: "classifier_error"`, `evidence: "<error reason>"`, `confidence: "low"` (preserves one-row-per-finding schema integrity). Stage transition continues (instrumentation never blocks). Re-run with `/plan` after fixing the underlying issue overwrites the error rows.
- **Network or model unavailable** — same shape as malformed: emit a `classifier_error` row per finding. Don't block the stage; don't pollute schema.
- **Hallucinated evidence quote** — `evidence` substring validator demotes outcome to `not_addressed` and `confidence` to `low`. Recorded but doesn't inflate `survival_rate`.
- **Re-running rollup with no `survival.jsonl` files at all** — Persona Drift renders: *"no measured features yet — run 1+ feature through `/spec-review` and `/plan` to seed."*
- **Cross-platform filename safety** — rotation timestamps use `%Y-%m-%dT%H-%M-%SZ` (no colons), avoiding Windows/exFAT illegality.
- **Branch / merge workflows** — committed `findings.jsonl` and `survival.jsonl` will diff across feature branches. Adopters running this in shared repos should either (a) gitignore them via `PERSONA_METRICS_GITIGNORE=1`, or (b) accept that the rollup reflects whichever branch is checked out. For `MonsterFlow`'s solo-dev pattern this is a non-issue.
- **Retention / pruning** — superseded `findings-<UTC-ts>.jsonl` files accumulate indefinitely. No auto-prune in this spec; user can remove them by hand. A future `/wrap` step or `/wrap-insights` `--prune-superseded` flag is deferred.
- **Feature directory naming** — uses existing `docs/specs/<slug>/` convention; no new constraint.
- **`/wrap-insights` performance at scale** — pure read projection; fine through ~50 features. At 200+ features the read+aggregate may be perceptibly slow. Caching is deferred; spec ships without it.
- **Manually edited `findings.jsonl` / `survival.jsonl`** — supported (the files are markdown-friendly JSONL). Schema validator catches malformed rows on next read; misshapen rows are skipped with a one-line warning in `/wrap-insights`.

## Acceptance Criteria

This spec is "done" when **all** of the following hold:

1. `/spec-review` snapshots `spec.md` to `<feature>/spec-review/source.spec.md` at start, then writes `findings.jsonl`, `participation.jsonl`, and `run.json` at synthesis end. All four files exist with valid schemas (all required fields present including `schema_version`, `prompt_version`, `artifact_hash`).
2. `finding_id` is deterministic given identical clustering output: synthesizing the same set of raw persona outputs twice produces the same `finding_id` per cluster (because `normalized_signature` is computed from sorted-lowercased-whitespace-collapsed source substrings, not from the LLM-generated `title`).
3. `personas[]` correctly includes `"codex-adversary"` for any cluster whose underlying source includes Codex output, with `model_per_persona["codex-adversary"] = "codex"`.
4. **`/plan` produces the analogous emit artifacts** in `<feature>/plan/` — `findings.jsonl` (one row per design-recommendation cluster, attributed to `personas[]` from the 6 design personas), `participation.jsonl`, `run.json`, plus `raw/<persona>.md` per design persona. **No `source.plan.md`** (plan.md is freshly synthesized — there is no pre-state). Schemas valid.
5. **`/check` produces the analogous emit artifacts** in `<feature>/check/` — `source.plan.md`, `findings.jsonl`, `participation.jsonl`, `run.json`, `raw/<persona>.md` per check reviewer (incl. `codex-adversary.md` if Codex ran).
6. `survival.jsonl` is written at `/plan` start (addressed-by-revision mode). Classifier receives `findings.jsonl` + `source.spec.md` + revised `spec.md`. At least one finding is correctly tagged `addressed` with a verbatim evidence quote that the substring validator confirms appears in the revised artifact. Each row carries `artifact_hash`.
7. **`survival.jsonl` is written at `/check` start** (synthesis-inclusion mode, NEW in scope (b)). Classifier receives `<feature>/plan/findings.jsonl` + `plan.md` (no source snapshot). At least one design recommendation is correctly tagged `addressed` (visibly shaped `plan.md`) with a verbatim evidence quote.
8. `survival.jsonl` is written at `/build` start (addressed-by-revision mode), same check against revised `plan.md`.
9. **Idempotency at all three Phase 0 sites:** running `/plan`, `/check`, or `/build` twice without changing the input artifact does not re-invoke the classifier (verified by `run_id` in `survival.jsonl` unchanged on the second run); running after editing the input re-invokes the classifier (`artifact_hash` change).
10. **Iterative re-review:** running `/spec-review`, `/plan`, or `/check` twice on the same feature renames the older `findings.jsonl` to `findings-<UTC-ts>.jsonl` (colon-free format) *at the second emit's write site*, before the second write. The rename is the only superseded marker — no schema mutation.
11. **Atomic writes:** simulating a crash mid-write (kill the synthesis process) leaves the prior `findings.jsonl` intact; no partial JSONL is observed.
12. **Evidence validator:** seeding the classifier with a finding whose `evidence` quote is *not* a substring of the revised artifact (or `plan.md` for synthesis-inclusion mode) results in `outcome: "not_addressed"` (demoted) and `confidence: "low"` in the written row.
13. **Stale-survival warning:** editing `spec.md` (or `plan.md`) after the relevant Phase 0 has classified, then running `/wrap-insights` without re-running, surfaces a "stale survival" warning naming that feature.
14. `/wrap-insights` Persona Drift section appears in default output with the legend line, ↑/↓/→ arrows respect the 5-percentage-point deadband, and shows correct trends for the smoke-test feature. Renders rates for **all three gates' personas** (review + design + check personas).
15. `/wrap-insights personas` subcommand prints the full rolling-window table with both `load_bearing_rate` AND `survival_rate` columns, and is tab-completable from the command line (verified by presence of `~/.claude/commands/wrap-insights-personas.md` after install).
16. **Hand-verification on one real feature:** the `load_bearing_rate`, `silent_rate`, and `survival_rate` rendered by `/wrap-insights` match manual computation from the source `findings.jsonl` + `participation.jsonl` + `survival.jsonl` files **across all three gates**.
17. Documentation updated: README mermaid + `docs/index.html` mermaid render with all three Judge nodes feeding Persona Metrics; `commands/flow.md` reference card mentions drift surfacing; `CHANGELOG.md` entry added; adopter note (README paragraph + CLAUDE.md template block) covers privacy posture.
18. `install.sh` correctly symlinks all `commands/_prompts/*.md` files. Re-run on a fresh checkout produces the expected symlinks. With `PERSONA_METRICS_GITIGNORE=1` (default for adopter installs), the metrics paths are appended to `.gitignore` (idempotent).

## Open Questions

None — all 12 Before-You-Build items from `review.md` are resolved in this revision. Confidence ≥ 0.93 across all six dimensions.

Items deferred to `persona-tiering` follow-up (per Out of Scope):
- Tiering rules (Core / Conditional / Demoted thresholds)
- Probe sampling for demoted personas
- Multi-model A/B comparison surface
- Classifier accuracy validation (≥8/10 human-agreement check)
- Retention auto-prune step
