# Persona Metrics Implementation Plan

**Created:** 2026-04-26
**Revised:** 2026-04-26 (post-check v1.1 — 12 Must Fix items + 8 Should Fix items folded in; v1.2 — scope (b) adopted via diagram review feedback: `/plan` is now a metrics emit site, `/check` is now a survival-classifier trigger)
**Spec:** `docs/specs/persona-metrics/spec.md` (v1.1 post-review)
**Review:** `docs/specs/persona-metrics/review.md` (12 Before-You-Build items resolved)
**Check:** `docs/specs/persona-metrics/check.md` (GO WITH FIXES — all addressed below)
**Designers:** 6 parallel /plan agents (api, data-model, ux, scalability, security, integration) + 5 /check reviewers + Codex adversarial

---

## Architecture Summary

Persona-metrics is a **purely additive markdown-choreography feature** — no runtime daemon, no DB, no new dependencies. Everything happens via prompt-file directives executed by the host agent, against text files committed to the repo.

**Six new artifact types per feature per stage:**
- `source.<artifact>.md` (pre-review snapshot)
- `raw/<persona>.md` per persona that ran (raw output persisted to disk — replaces conversation-context dependency)
- `raw/codex-adversary.md` if Codex ran (replaces `/tmp/codex-<stage>-review.txt`)
- `findings.jsonl` (clustered, attributed)
- `participation.jsonl` (every persona that ran, with status)
- `run.json` (manifest)
- `survival.jsonl` (next-stage classification)

Plus three prompt files (`commands/_prompts/{snapshot,findings-emit,survival-classifier}.md`), four JSON Schema files (`schemas/{findings,participation,survival,run}.schema.json` at repo root, not symlinked), and a trimmed adopter note (paragraph in README + 3-line block in CLAUDE.md template — full `docs/persona-metrics.md` deferred). The `/wrap-insights personas` subcommand file (`commands/wrap-insights-personas.md`) is also deferred; bare-arg form `/wrap-insights personas` works without it.

**Phase ordering** is the spine of the design:

- **`/spec-review` and `/check`:** Phase 1 gains a *step 0* — snapshot + rotate-before-write + create `<stage>/raw/` dir — before reviewer agents dispatch. As each reviewer agent returns, Phase 1 persists its raw output to `<stage>/raw/<persona>.md` *immediately* (atomic write, before context might be truncated). Phase 2 (Judge+Synthesize) and Phase 2b (Codex, which writes to `<stage>/raw/codex-adversary.md`) run as today. A new **Phase 2c** then emits `findings.jsonl`, `participation.jsonl`, and `run.json` by reading the on-disk `<stage>/raw/*.md` files — never from conversation context. This retires the harness-context-access risk (formerly R1) entirely; raw outputs are file-backed by construction.
- **`/plan` and `/build`:** new **Phase 0** (pre-existing-Phase-1) runs the survival classifier when a prior `findings.jsonl` exists and either no `survival.jsonl` exists or its `artifact_hash` differs. Silent-skip otherwise. Never blocks the stage.
- **`/wrap` (the underlying file `wrap-insights` delegates to):** new **Phase 1c** (between existing 1b `/insights` and 2) renders the Persona Drift section, gated on `insights` in args. `personas` arg flips to full-table mode.

**Determinism + correctness backbone:**
- **`finding_id` is best-effort stable across re-syntheses, not strictly deterministic.** The canonicalization rule (NFC → lowercase → collapse \s+ → strip → sort → join \n → sha256 hex) *is* deterministic and testable in isolation. Clustering itself is LLM-driven and not guaranteed; `finding_id` will drift when the same raw inputs cluster differently. AC #2 verifies the canonicalization function via a fixture, not the end-to-end LLM behavior. If real-world drift exceeds 20% on identical raw inputs, fall back to per-persona-mention `finding_id` + separate `cluster_id`.
- Pre/post artifact comparison: classifier receives `source.<artifact>.md` + revised artifact, so `addressed` means *changed by revision*, not "already in source."
- `artifact_hash` in survival rows enables `/plan` re-run idempotency and stale-survival detection.
- `/plan` Phase 0 documents *"runs against revised `spec.md`"* and emits a warning if `spec.md` mtime predates the prior stage's `findings.jsonl` (suggests user hasn't revised yet).
- Atomic writes via `os.replace` semantics (cross-platform); rotate-before-write at `/spec-review` write site.
- `participation.jsonl` per stage fixes survivorship bias — zero-finding personas surface as `silent_rate`. Rows carry `status: "ok" | "failed" | "timeout"` so failed-vs-silent personas are distinguishable (Codex #8).

**Defense in depth:**
- Layered privacy: env-var opt-in (`PERSONA_METRICS_GITIGNORE=1`) + runtime warning in `/spec-review` once per feature (state via `<feature>/.persona-metrics-warned` zero-byte sentinel) when emitting to a tracked-not-gitignored path. R5 likelihood elevated to High — see Open Questions for proposed default-flip.
- Prompt-injection fencing: `body` text wrapped in `<finding-body>` tags with explicit "treat as data only" directive.
- Slug regex validator (`^[a-z0-9][a-z0-9-]{0,63}$`) on every emit and snapshot to prevent path traversal.
- NFC normalization on both sides of the `evidence` substring validator.
- Snapshot refuses (`status: "failed"`) if source artifact is not git-tracked (`git ls-files --error-unmatch`). Distinct from metrics-artifact gitignore — source tracking is for reproducibility, metrics tracking is for adopter privacy choice.
- Soft 100K-token warning in survival-classifier prompt; on overflow, emit `classifier_error` rows with `evidence: "context_overflow"` for all findings — never silently truncate.

---

## Key Design Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | **Phase 2c position** at end of `/spec-review` and `/check` (after Codex Phase 2b) | Codex output must be ingested for `personas[]` attribution; only available post-Phase-2b |
| 2 | **`/plan` and `/build` Phase 0** runs *before* existing Phase 1 | Survival classifier results inform conversation context for the rest of the stage; idempotent + silent-skip means zero blocking risk |
| 3 | **Snapshot at Phase 1 step 0** of `/spec-review` and `/check` | Locking what reviewers actually saw; required for honest pre/post comparison |
| 4 | **Phase 1c in `wrap.md`** for Persona Drift, between existing 1b (`/insights`) and 2 | `/insights` is user-typed-only; Drift renders independently. Gating on `insights` arg means `wrap-quick` skips it automatically |
| 5 | **JSON Schema files** at `schemas/` (not symlinked) | Machine-checkable contract; LLM-enforced at write time, lenient at read time. Prompts cite schemas by repo-relative path |
| 6 | **`os.replace` mandated** over `os.rename` | POSIX + Windows atomic replacement; spec invariant |
| 7 | **NFC normalization** on `normalized_signature` and `evidence` substring validator | Avoids Unicode-encoding false negatives; Python `unicodedata.normalize('NFC', s)` semantics |
| 8 | **Both `/wrap-insights personas` and `/wrap-insights-personas`** invocations supported | Space-arg form natural; dashed form tab-completable. install.sh glob picks up new file automatically. Same render path |
| 9 | **`run.json` per stage write** as audit anchor | Closes audit, debug, schema versioning, prompt versioning gaps in one artifact. `warnings: []` field carries security-runtime warnings (e.g., "uncommitted-and-not-gitignored") |
| 10 | **Migration script deferred** until first `schema_version` bump | YAGNI; ship with v1 schema only. When v2 ships, `scripts/migrate-persona-metrics.py` accompanies it; old rows archive to `findings.v1.jsonl` |
| 11 | **VERSION bump = MINOR** (no breaking change to existing pipeline contracts) | Spec is purely additive |
| 12 | **`/plan`/`/build` echo a one-liner** when `classifier_error` rows are written | Makes silent failures visible at the point they occur, not deferred to next `/wrap-insights` |
| 13 | **`/spec-review`/`/check` echo a one-liner** at snapshot+rotate | Ambient confidence the instrumentation ran; helps debugging drift weirdness later |
| 14 | **Smoke-test demo command deferred** to a follow-up | Adopter-experience win but not on the critical path; ship measurement first |
| 15 | **3-state outcome taxonomy preserved** (vs Codex-proposed 5-state) | Pre/post snapshot resolves Codex's `already_addressed` concern inside 3-state; keeps classifier cognitive load low |

---

## Implementation Tasks

| # | Task | Depends On | Size | Wave |
|---|---|---|---|---|
| **T-1** | **Synthesizer survey (done in `/plan` invocation):** confirmed `commands/spec-review.md` and `commands/check.md` have explicit `## Phase 2: Judge + Synthesize` sections — synthesis is host-agent prose, no factor-out work needed. Recorded as resolved. | — | done | Wave 0 |
| **T0** | **Raw-output persistence spike:** in a real `/spec-review` test run, dispatch one throwaway sub-agent and verify its raw output can be written to `<feature>/spec-review/raw/<persona>.md` from the host turn (atomic, ~2 KB). Validates the structural fix; if blocked, escalate before T6 starts. | — | S (~30 min) | Wave 0 |
| **T0.5** | **Build test fixtures:** `tests/fixtures/normalized_signature_input.txt` + precomputed `.hex` for canonicalization determinism; `tests/fixtures/hallucinated_evidence_findings.jsonl` + `revised.spec.md` for evidence-validator demotion; `tests/fixtures/synthetic-features/{a,b,c}/` for rolling-window math (3 feature dirs with hand-crafted artifacts). | — | M (~1 hr) | Wave 0 |
| 1 | `schemas/findings.schema.json` (draft 2020-12) — pinned at repo root, not symlinked. Covers all fields incl. `schema_version`, `prompt_version`, `finding_id` regex, `personas[]`, `severity`/`mode`/`model_per_persona`, `normalized_signature` hex | — | S | Wave 1 |
| 2 | `schemas/participation.schema.json` — covers `schema_version`, `stage`, `persona`, `model`, `findings_emitted`, **`status` enum** (`ok`/`failed`/`timeout`) | — | S | Wave 1 |
| 3 | `schemas/survival.schema.json` — `outcome` enum incl. `classifier_error`, `evidence` length cap (≤120 codepoints), `confidence` enum, `artifact_hash` regex | — | S | Wave 1 |
| 4 | `schemas/run.schema.json` — `run_id` uuid4 regex, `command` enum, `status` enum, `warnings[]` array, all hash fields | — | S | Wave 1 |
| 5 | `commands/_prompts/snapshot.md` — directive: copy `spec.md`/`plan.md` to `<stage>/source.<name>.md`; **explicit comment block** distinguishing source-artifact tracking (reproducibility, refuse if untracked) from metrics-artifact gitignore (per-adopter privacy choice); `git ls-files --error-unmatch` precondition; slug regex validator; atomic `os.replace`; user-feedback echo | — | S | Wave 1 |
| 6 | `commands/_prompts/findings-emit.md` — synthesizer post-step prompt. **Reads `<stage>/raw/*.md` from disk** (not conversation context). Clusters; computes `normalized_signature` per canonicalization rule; derives `finding_id` (10-char prefix, **best-effort stable**); emits `findings.jsonl`, `participation.jsonl` (incl. `status` field), `run.json` atomically. `<finding-body>` data-only fencing on body text. NFC normalization. Slug regex validator. Prompt-version bump rule in header. References `schemas/*.schema.json`. | T0 | XL | Wave 1 |
| 7 | `commands/_prompts/survival-classifier.md` — batched single-call. **Two outcome-semantics modes** selected by caller directive: (a) **addressed-by-revision** for `/plan` and `/build` Phase 0 (receives `findings.jsonl` + `source.<artifact>.md` + revised artifact; `addressed` = revision changed the artifact in a way addressing the finding); (b) **synthesis-inclusion** for `/check` Phase 0 (receives `<feature>/plan/findings.jsonl` + `plan.md` only — no source snapshot; `addressed` = design recommendation visibly shaped `plan.md`, `not_addressed` = Judge dropped/demoted, `rejected_intentionally` = `plan.md`'s alternatives-considered section names it). Common to both modes: 3-state outcome + `<finding-body>` fencing + NFC-normalized evidence substring validator + `artifact_hash` recording + idempotency-skip + 100K-token soft warning (on overflow → emit `classifier_error` rows for all findings, never silent truncate). References `schemas/survival.schema.json`. | T0 | XL | Wave 1 |
| ~~8~~ | ~~`commands/wrap-insights-personas.md`~~ — **DEFERRED to follow-up.** Bare-arg form `/wrap-insights personas` works without separate file. | — | — | — |
| 9 | **TRIMMED:** add 1-paragraph note to `README.md` (under existing pipeline section) + 3-line block to `templates/CLAUDE.md` covering `PERSONA_METRICS_GITIGNORE=1`. Full `docs/persona-metrics.md` adopter doc deferred until second adopter exists. | — | XS | Wave 1 |
| 10 | Bump `VERSION` (MINOR) + `CHANGELOG.md` entry mentioning `PERSONA_METRICS_GITIGNORE` env var | — | S | Wave 1 |
| 11 | `README.md` mermaid pipeline diagram: **replace existing pipeline mermaid with Diagram 1 (Tight-C variant) from `docs/specs/persona-metrics/diagrams.md`** — full source there, copy verbatim. Adds Judge interstitials, Persona Metrics side observer, all three Judges feeding PM. Factual prose update only (no measurement-loop reframe yet). | — | S | Wave 1 |
| 12 | `docs/index.html` mermaid: same Diagram 1 source as T11, copied verbatim from `diagrams.md`. | — | S | Wave 1 |
| 13 | `commands/flow-card.txt`: one-line note about drift surfacing | — | S | Wave 1 |
| 14 | `commands/spec-review.md`: Phase 1 step 0 (snapshot + rotate-before-write + create `<stage>/raw/`); **Phase 1 also persists each reviewer's raw output to `<stage>/raw/<persona>.md` immediately on agent return**; Phase 2c (after Phase 2b) invokes `findings-emit.md` reading from disk; runtime gitignore warning gated by `<feature>/.persona-metrics-warned` sentinel; one-line snapshot/rotation echo. | T0, T5, T6 | M | Wave 2 |
| 15 | `commands/check.md`: **two responsibilities** — (1) Phase 0 pre-flight survival classifier in **synthesis-inclusion mode** against `<feature>/plan/findings.jsonl` + `plan.md` (NEW in scope (b)); checks `survival.jsonl.artifact_hash` vs `sha256(plan.md)`; idempotent; never blocks. (2) Existing review flow: snapshot `plan.md` → `<feature>/check/source.plan.md`, persist raw outputs (incl. `codex-adversary.md`), Phase 2c synthesis emit. | T0, T5, T6, T7 | M | Wave 2 |
| 16 | `commands/plan.md`: **two responsibilities** — (1) Phase 0 pre-flight survival classifier in **addressed-by-revision mode** against `<feature>/spec-review/findings.jsonl` + `source.spec.md` + revised `spec.md`; checks `survival.jsonl.artifact_hash` vs `sha256(spec.md)`; **emits warning if `spec.md` mtime predates `findings.jsonl`** (user hasn't revised); never blocks. (2) **At synthesis end, persist each design persona's raw output to `<feature>/plan/raw/<persona>.md`** and run `findings-emit.md` to write `<feature>/plan/findings.jsonl`, `participation.jsonl`, `run.json` (NEW in scope (b)). No `source.plan.md` snapshot — plan.md is synthesized fresh, no pre-state. | T0, T5, T6, T7 | M | Wave 2 |
| 17 | `commands/build.md`: identical Phase 0 against `<feature>/check/findings.jsonl` and revised `plan.md` | T7 | M | Wave 2 |
| 18 | `commands/wrap.md`: Phase 1c (Persona Drift) between Phase 1b and Phase 2, gated on `insights` in args. Reads `<feature>/<stage>/{findings,participation,survival}.jsonl`; computes per-persona rolling-window stats (incl. `silent_rate` from `participation.findings_emitted == 0` rows where `status == "ok"`); renders diff (5pp deadband) by default; renders full table when args include `personas`. Renders stale-survival warning (`artifact_hash` mismatch). Skips lenient on malformed JSONL with one-line warning. | T1–T4, **T6, T7** | L | Wave 2 |
| 19 | `install.sh`: explicit loop for `commands/_prompts/*.md` symlinks; **detect non-symlink regular files at target paths and back up to `.bak`** before symlinking. Honor `PERSONA_METRICS_GITIGNORE=1` (touch `.gitignore` if absent; idempotent block via `# BEGIN persona-metrics` / `# END` sentinels). | T5, T6, T7 | M | Wave 3 |
| 20 | `scripts/doctor.sh`: verify prompt symlinks (`snapshot.md`, `findings-emit.md`, `survival-classifier.md`); verify `schemas/*.schema.json` parse as valid JSON; **prompt-version drift grep** — assert `prompt_version: "<name>@<ver>"` matches between prompt-file headers and the schema example fields; **fixture-based canonicalization check** — feed `tests/fixtures/normalized_signature_input.txt` through canonicalization, assert hex output matches `.hex`; **fixture-based atomic-write check** — create stale `<name>.tmp`, run no-op write, assert prior canonical file unchanged. | T5, T6, T7, T0.5 | M | Wave 3 |
| 21 | **Smoke test:** real feature end-to-end through `/spec-review` → revise → `/plan` → `/check` → revise → `/build`. Verify all artifact types written **at all three multi-agent gates (spec-review, plan, check)** with valid schemas; **`personas[]` has `len ≥ 2` for at least one cluster** (R1-detection sentinel — if blocked, raw outputs weren't accessed); **survival.jsonl exists at all three Phase 0 sites** (`/plan` start judging spec-review findings; `/check` start judging plan findings in synthesis-inclusion mode; `/build` start judging check findings); idempotency on each Phase 0 re-run (assert `run_id` unchanged); stale-survival warning after artifact edit; **legacy-spec regression** — run `/plan` on `pipeline-wiki-integration` (no `findings.jsonl`), assert silent skip + no failure. | T14–T20 | L | Wave 4 |
| 22 | **Render verification on synthetic 3-feature fixture set (T0.5):** `/wrap-insights` against `tests/fixtures/synthetic-features/`. Verify `load_bearing_rate`, `silent_rate`, `survival_rate` round-trip within 0.01 of manually-computed values. Verify ↑/↓/→ trend arrows respect 5pp deadband. Verify `(insufficient data — N runs)` for personas with <3 runs. Verify `/wrap-insights personas` (bare-arg form) renders full table. | T18, T0.5 | M | Wave 4 |
| 23 | **Install verification on fresh checkout:** re-run `install.sh`; verify all expected symlinks; verify `PERSONA_METRICS_GITIGNORE=1` block appended idempotently (re-run produces no duplicate); verify pre-existing non-symlink at one prompt path triggers `.bak` backup. | T19, T20 | S | Wave 4 |

**Totals:** 22 active tasks (T8 deferred, T9 trimmed) across 5 waves: Wave 0 (3 tasks: 1 done, 2 new), Wave 1 (12 parallel, 2 long poles), Wave 2 (5 parallel command-file mods — **commit each individually** for self-consistent partial completions), Wave 3 (2 parallel install/doctor), Wave 4 (3 acceptance).

**Re-estimated effort:**
- Wave 0: ~1.5 hr (T0 spike + T0.5 fixtures parallelized)
- Wave 1: ~1 work day total parallelized (T6 + T7 each promoted to XL — they each carry NFC normalization across two callsites, fencing, slug regex, atomic-write semantics, schema references, prompt-version bump rule, batched-call discipline; "half day parallelized" was wishful)
- Wave 2: ~half day parallelized
- Wave 3: ~1.5 hr (T20 expanded with fixture checks + drift grep)
- Wave 4: ~half day on real feature + fixture verification
- **Realistic wall-clock: 3 work sessions.**

---

## Open Questions (need Justin's input — answered after /check)

Answers locked in this revision unless Justin overrides:

1. ~~`/plan` and `/build` echo of `classifier_error`~~ → **on by default** (UX recommendation accepted; cheap signal at point of failure).
2. ~~`docs/persona-metrics.md` site nav link~~ → **moot, doc deferred** (T9 trimmed to README + CLAUDE.md note).
3. ~~Snapshot refusal on gitignored sources~~ → **refuse hard** with `run.json.status: "failed"`. Distinct from metrics-artifact gitignore (per-adopter privacy choice — see Defense in depth).
4. ~~Codex temp-file path~~ → **`<feature>/<stage>/raw/codex-adversary.md`** (clean break from `/tmp`; treats Codex as a regular persona for emission). Updated in T14, T15, T6.
5. ~~Smoke-test demo command~~ → **defer** to follow-up. Synthetic-feature fixtures (T0.5) cover the validation need without a user-facing demo.
6. ~~Auto-prune of superseded findings~~ → **defer** to follow-up. No MVP value.

**Still open (need explicit yes/no before /build):**

7. **R5 default-flip:** for *adopter* installs, default `PERSONA_METRICS_GITIGNORE=1` (opt-in to commit) instead of opt-in to gitignore? `MonsterFlow`'s own repo overrides via name-detection in install.sh. Recommend **yes** for adopter safety; conservative answer is no. The risk register elevated R5 likelihood to High because most users don't read installer output.

8. **Recovery story documentation:** should `docs/specs/persona-metrics/plan.md` carry a one-line rollback recipe ("remove new symlinks + revert command-file edits + leave committed JSONL as harmless leftovers") for the case where T21 fails after Waves 1–3 complete? Recommend yes; one sentence.

---

## Risk Register (post-check)

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| ~~1~~ | ~~Synthesizer-raw-output access blocked by harness~~ | — | — | **Retired.** Adopting raw-output persistence to disk (T0 spike + T14/T15 immediate-write-on-agent-return) makes raw outputs file-backed by construction. T0 validates the persistence approach in <30 min. |
| 2 | **Codex output ordering/availability** — Phase 2c reads `<feature>/<stage>/raw/codex-adversary.md`; if Phase 2b failed mid-write or didn't run while Codex was configured, attribution is wrong | Low | Medium | Phase 2c checks `codex-adversary.md` mtime ≥ run start; if Codex was configured but file absent or stale, omit `codex-adversary` from `personas[]` and record `run.json.warnings[]: ["codex-output-missing"]`. |
| 3 | **`finding_id` non-determinism due to LLM clustering variance** — different runs cluster the same raw inputs differently, producing different `normalized_signature` | Medium | Low (after demotion) | **Demoted honestly:** AC #2 verifies the *canonicalization function* via T0.5 fixture (deterministic, testable). Clustering itself is best-effort. If T21 measures >20% drift on identical raw inputs, fall back to per-persona-mention `finding_id` + separate `cluster_id`. |
| 4 | **NFC normalization missed at one comparison site** — silent false negatives in evidence validator | Low | Medium | Centralized NFC rule in `survival-classifier.md`; T7 includes explicit codepath through both sides. T20 doctor.sh fixture-test covers. |
| 5 | **Adopter forgets `PERSONA_METRICS_GITIGNORE=1` and commits sensitive prose to public repo** | **High** | High (history-rotation hard) | Layered: env-var + runtime warning in `/spec-review` once-per-feature (sentinel file) + adopter note in README + CLAUDE.md template + (proposed Open Question #7) default-flip for adopter installs. |
| 6 | **install.sh idempotent gitignore append breaks on adopter edits** | Medium | Low | `# BEGIN persona-metrics` / `# END` sentinels; install.sh detects existing block and skips. T19 + T23 verify. |
| 7 | **Atomic-write semantics wrong on Windows** | Low (now fixed) | Medium | `os.replace` mandated in T5/T6/T7. Cross-platform smoke deferred (solo dev macOS). |
| 8 | **`/wrap-insights` slow at 200+ features** | Low (years out) | Low | Pure on-demand projection; cache deferred to future spec. |
| 9 | **Prompt-version bump forgotten** — schema field stays at old version, downstream readers misinterpret | Medium | Low | Bump rule in prompt-file headers; **T20 doctor.sh prompt-version drift grep** (post-check addition) catches mismatches. |
| 10 | **Codex output absent (Codex not configured)** — Phase 2c silently omits `codex-adversary` from `personas[]` | Expected behavior | None | No mitigation needed — adopters without Codex see Claude-only attribution; correct by design. |
| **11** | **install.sh stomps pre-existing non-symlink files** at target paths in `~/.claude/commands/_prompts/` (other plugin, manual experiment) | Medium | Medium | T19 detects regular files at target and backs up to `.bak` before symlinking. T23 verifies. |
| **12** | **Schema-vs-prompt drift** — JSON Schema files (T1–T4) and prompt-file prose (T6, T7) diverge on field names/enums | Medium | Medium | T20 doctor.sh grep-validates schema-named fields appear in prompt-file headers/examples. Cheap, catches the common case. |
| **13** | **LLM context-window overflow on large specs** — combined `findings.jsonl` + `source.spec.md` + revised `spec.md` exceeds classifier context | Low (years out, large specs) | Medium | T7 prompt: on overflow, emit `classifier_error` rows for all findings with `evidence: "context_overflow"`. Never silent truncate. T21 includes a deliberately-large fixture (optional, defer if scope-tight). |
| **14** | **`participation.findings_emitted: 0` ambiguous between silent-vs-failed persona** — `silent_rate` corrupted | Medium | Low | T2 schema + T6 prompt include `status: "ok"|"failed"|"timeout"` field. Silent = `findings_emitted == 0 AND status == "ok"`. Failed personas excluded from `silent_rate` denominator. |

## Recovery if T21 fails after Waves 1–3 complete

Remove new symlinks (`~/.claude/commands/_prompts/{snapshot,findings-emit,survival-classifier}.md`); revert the four command-file edits (T14–T17) via `git revert`; leave any committed `findings.jsonl`/`participation.jsonl`/`run.json`/`survival.jsonl` artifacts in place — they're harmless leftovers if the feature is yanked. The Wave-2-individual-commit discipline keeps each command-file edit independently revertable.

---

## Approval

`/check` returned **GO WITH FIXES**; all 12 Must Fix items folded into this revision. Two Open Questions (#7 default-flip, #8 recovery doc) still need explicit Justin yes/no before `/build`.

Ready for `/build` once Open Questions are answered.
