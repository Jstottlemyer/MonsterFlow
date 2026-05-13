# Implementation Plan — pipeline-gate-permissiveness

**Spec:** `docs/specs/pipeline-gate-permissiveness/spec.md` (438 lines, refined twice)
**Generated:** 2026-05-05
**Designers:** api, data-model, ux, scalability, security, integration, wave-sequencer + codex-adversary
**Target version:** v0.9.0 (minor bump from 0.8.0)

---

## Architecture Summary

This spec ports autorun v6's per-axis warn/block policy framework inward to interactive gates. Land as a **single PR** (autorun lockstep is non-negotiable: schema bump + validator + `check.sh` must ship together). Implementation is decomposed into **5 waves of ordered commits within that PR**.

**Implementation-surface clarification (Codex round-4 #5, applied inline):** `commands/{spec-review,plan,check,build}.md` are markdown prompt templates read by Claude (the LLM agent), NOT executable parsers. CLI-parse / env-check / JSONL-write / lock-acquire / sidecar-emit responsibilities live in **shell + Python scripts** that the gate commands instruct Claude to invoke via Bash tool. New scripts created for this:

- `scripts/gate-mode-resolve.sh` — frontmatter parse, CLI flag parse (`--strict`/`--permissive`/`--force-permissive=<reason>`), mode resolution table, env-var refusal (`$CI`/`$AUTORUN_STAGE`), banner emission with sentinel suppression, `.force-permissive-log` JSONL row append.
- `scripts/_followups_lock.py` — lock primitive (already in W1.5).
- `scripts/render-followups.py` — rendering (already in W1.6).
- `scripts/_followups_lifecycle.py` (NEW) — read `followups.jsonl`, apply regenerate-active reconciliation scoped to `source_gate`, write atomic. Replaces hand-written reconciliation in `personas/synthesis.md` prose with deterministic Python. Synthesis prose calls this script.
- `scripts/build-mark-addressed.py` (NEW) — `/build` wave-final calls this with `--feature <slug> --finding-ids <ids> --commit-sha <SHA>` to write `state: addressed`. Resolves MF2 (addressed_by writer).
- `scripts/_iteration-state.py` (NEW) — read/increment/clamp the `.iteration-state.json` sidecar per spec, with worktree-scoped path.

The gate commands' prose orchestrates these scripts; assertions live in shell snippets the command tells Claude to run. This matches the autorun pattern (`scripts/autorun/check.sh` does the work; `commands/check.md` orchestrates Claude in interactive mode).

**Convergent design decisions (7 designers + Codex agreed):**

1. **Strict v2-only schema bump.** No `oneOf` versioning; `_policy_json.py` validator doesn't support it (verified). v1 verdicts on disk remain readable by historical-archive consumers; new emissions are v2-only. Single-PR landing eliminates the dual-version window.
2. **Per-gate verdict sidecars.** `spec-review-verdict.json`, `plan-verdict.json`, `check-verdict.json`. The fence label stays `check-verdict` (label != filename); `stage` field discriminates. Autorun's hardcoded `check-verdict.json` path preserved. **`/build` hardcoded to read `check-verdict.json` ONLY** — never falls through to plan-verdict / spec-review-verdict (Codex blocker #2 closed).
3. **`fcntl.flock` via Python helper for concurrency.** New `scripts/_followups_lock.py`. Kernel auto-cleanup on process death; no PID-liveness probe needed. Lock-file content carries `{pid, hostname, started_at}` for audit logging only. NFS/iCloud explicitly out of scope.
4. **`class: unclassified` fail-closed fallback** with `unclassified == block` HARDCODED (not configurable via constitution). Constitution attempting to demote unclassified → constitution-validation failure.
5. **Synthesis owns iteration counter; persisted via `.iteration-state.json` per spec.** Bounds-checked at autorun extraction. Clean re-invocation removes the sidecar (or explicit `--reset-iteration` flag). This closes Codex major #5 (off-by-one bug surface).
6. **Template-first persona batching.** One persona's class-tagging block written + approved (Wave 2 gate), then `scripts/apply-class-tagging-template.sh` batch-applies to remaining 27. CI sentinel check (`<!-- BEGIN class-tagging -->...<!-- END class-tagging -->`) catches drift.
7. **`class: security` ↔ `sev:security` parity** via dual-emission: row gets `class: "security"` AND `tags: ["sev:security"]`. NOT severity-enum reuse (severity is orthogonal: blocker/major/minor/nit). Runtime parity enforcement in `_policy_json.py`'s new `_enforce_class_sev_parity()`.
8. **`/build` legacy-detection branch (Codex blocker #1):** explicit ladder — missing sidecar (pre-v0.9.0) → today's behavior; v1 sidecar → refuse with clear error pointing to upgrade; v2 sidecar with verdict ∈ {GO, GO_WITH_FIXES} → proceed; v2 NO_GO → refuse.
9. **Refuse `--force-permissive` in CI/AUTORUN env** (`$CI` or `$AUTORUN_STAGE` set). Force-permissive is interactive-escape-hatch only. Mixing with automation = exit-with-error.
10. **Architectural carve-outs added inline (Codex major #7):** data-loss, irreversible-migration, release-rollback-failure, supply-chain-risk findings route to `class: architectural` (block) in v1. v2 will give these own classes. Tiebreaker added to spec at /build wave 5.

---

## Open Questions (require Justin's call)

These are decisions the designers identified but didn't fully resolve. None block plan approval; flagging for awareness.

- **OQ1. `--force-permissive` reason string** (security Q4): require `--force-permissive="releasing hotfix; doc nit known"`? Cheap to add, useful post-hoc audit. **Recommendation: yes** — make the reason string mandatory when the flag is used.
- **OQ2. `commands/spec.md` template format** (integration Q2): the template uses `**Field:**` human-prose style; actual specs use YAML `---` frontmatter. Reconcile in this PR or follow-up? **Recommendation: follow-up** — scope-disciplined; CHANGELOG note it.
- **OQ3. v0.9.0 bundling with grep-fallback removal** (spec O4): both can ride v0.9.0 (additive) or grep-fallback bumps to v0.9.1. **Recommendation: ride together** — clean cut.
- **OQ4. `/wrap-quick` force-permissive surface** (ux OQ-UX-2): include in /wrap-quick (security-adjacent, not opt-in) or only in /wrap-insights/full? **Recommendation: /wrap-quick** per ux persona — the audit signal must reach the user without an opt-in step. Defer-able to v0.9.1 if commands/wrap.md work isn't in scope.

---

## Risks (top from design analysis)

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | Partial PR landing (schema without validator/check.sh) breaks autorun on first run | Low (single-PR rule) | High | CI guard A8b rejects partial landings; tests/test-autorun-policy.sh enforces |
| R2 | Persona drift across 28 batched files produces divergent class definitions | Medium | Medium | Template-first wave 2 gate; `<!-- BEGIN class-tagging -->` sentinels; tests/test-class-tagging-spliced.sh CI check |
| R3 | `unclassified=block` deadlock during persona migration if any persona omits `class:` (Codex major #6) | Medium | High | New `--dry-run-class-coverage` flag run before persona-batch merge; reports omissions without producing real verdicts |
| R4 | Iteration counter off-by-one on manual re-runs / Synthesis retries / validator re-emits (Codex major #5) | Medium | Medium | `.iteration-state.json` sidecar is the source of truth; autorun bounds-check at extraction; clean re-invocation requires explicit reset |
| R5 | Strict-mode stale `followups.jsonl state: open` rows misleading to humans (Codex major #4) | Low | Low | /build refuses on NO_GO regardless of followups state; verdict's `mode_source: cli-force` audit trail makes the override visible |
| R6 | `flock` semantics weak on NFS/iCloud (Codex major #3) | Very Low (single-host) | Low | Document local-worktree assumption in `_followups_lock.py` docstring; out of scope to support remote FS |
| R7 | Reworded findings drift `finding_id` hash → undercount survival rate | Low | Low | Acknowledged in spec edge cases; semantic dedup deferred to v2 |
| R8 | v0.9.0 collision with reserved grep-fallback removal (spec O4) | Low | Low | Bundle both in v0.9.0 release notes |

---

## Implementation Tasks

Five waves of ordered commits within one PR. Wave 2 has a USER APPROVAL GATE before wave 3 (template-first batching). Within each wave, tasks marked `[P]` can run in parallel.

### Wave 1 — Data contract + autorun lockstep (load-bearing)

| # | Task | Depends On | Size | Parallel? |
|---|---|---|---|---|
| 1.1 | Bump `schemas/check-verdict.schema.json` to v2 (9 new fields, additionalProperties:false preserved) | — | S | [P] |
| 1.2 | Extend `schemas/findings.schema.json` (additive `class`, `class_inferred`, `source_finding_ids`, optional `tags`); bump `schema_version: 2`, `prompt_version: findings-emit@2.0` | — | S | [P] |
| 1.3 | Create `schemas/followups.schema.json` (NEW; class enum NARROWED to 4 values: contract/documentation/tests/scope-cuts; full lifecycle row spec) | — | S | [P] |
| 1.4 | Add `"followups"` to `_policy_json.py` `KNOWN_SCHEMAS` tuple; implement `_enforce_class_sev_parity()` runtime check | 1.2, 1.3 | S | — |
| 1.5 | Create `scripts/_followups_lock.py` (NEW; `fcntl.flock` helper; CLI: acquire/with-lock; lock-file metadata = {pid, hostname, started_at}; --timeout=60s default) | — | S | [P] |
| 1.6 | Create `scripts/render-followups.py` (NEW; deterministic; sort by target_phase, then class/created_at/finding_id; exit codes 0/2/3/4; --no-lock for read-only) | 1.3 | M | — |
| 1.7 | Update `scripts/autorun/check.sh`: GO_WITH_FIXES + cap_reached handling + iteration bound-check (0 < iteration ≤ iteration_max + 1) at extract_and_decide; preserve `sec_count > 0` block (load-bearing for class:security parity) | 1.1, 1.4 | M | — |
| 1.8 | Update `tests/test-autorun-policy.sh` CI guard (A8b) — fails CI if schema bumps without validator/check.sh in same PR; add v2 verdict fixture round-trip test | 1.1, 1.4, 1.7 | S | — |
| 1.9 | Add `docs/specs/*/followups.jsonl` to `install.sh` `PERSONA_METRICS_GITIGNORE` block | — | XS | [P] |

**Verifier:** hand-crafted v2 verdict fixture validates; `followups.jsonl` fixture round-trips through `_policy_json.py validate`; `bash scripts/autorun/check.sh` against GO_WITH_FIXES fixture exits 0 without re-cycling; CI guard rejects synthetic partial landing (schema-only commit). Run `autorun-shell-reviewer` subagent against any `scripts/autorun/*.sh` changes (CLAUDE.md mandate).

**Minimum-shippable test:** Yes — wave 1 alone delivers a usable v2 schema autorun can read.

---

### Wave 2 — Persona template proof-point (1 persona, USER APPROVAL GATE)

| # | Task | Depends On | Size | Parallel? |
|---|---|---|---|---|
| 2.1 | Write `personas/_templates/class-tagging.md` (NEW; canonical instruction block with the 7-class taxonomy, severity orthogonality, `class:security` ↔ `sev:security` dual-emission rule, `<!-- BEGIN class-tagging -->...<!-- END class-tagging -->` sentinels) | 1.2 | M | — |
| 2.2 | Apply template to ONE representative reviewer persona — `personas/review/scope-discipline.md` (touches architectural/scope-cuts/contract plausibly) | 2.1 | S | — |
| 2.3 | Update `personas/judge.md` — highest-class-wins precedence (`architectural > security > unclassified > contract > tests > documentation > scope-cuts`); reclassification authority; missing/invalid → coerce to `unclassified` with `class_inferred: true`; tiebreaker rules including v1 architectural carve-outs (data-loss, migration, rollback, supply-chain) | 1.2, 2.1 | M | [P with 2.4] |
| 2.4 | Update `personas/synthesis.md` — verdict JSON fence emission; `followups.jsonl` regenerate-active scoped to `source_gate == current_gate`; `addressed → open` regression transition; lock acquisition; `render-followups.py` invocation; `.iteration-state.json` source-of-truth | 1.5, 1.6, 2.1 | M | [P with 2.3] |
| 2.5 | Add `--dry-run-class-coverage` mode to gate command shell snippet — reports which personas omit `class:` without producing real verdicts (R3 mitigation) | 2.1 | S | — |
| **GATE** | **Justin reviews template + scope-discipline.md application; approves wording before wave 3 fan-out** | 2.2, 2.3, 2.4 | — | — |

**Verifier:** template reads coherently; Judge applied to a 2-reviewer-disagreement fixture produces highest-class-wins verdict; Synthesis fixture run produces v2-schema-valid verdict + well-formed followups.jsonl; `--dry-run-class-coverage` against scope-discipline returns success.

**Minimum-shippable test:** Marginal — Judge + Synthesis are useful in isolation only with one reviewer's tagged output.

---

### Wave 3 — Behavior closure: 27-persona batch + gate commands

| # | Task | Depends On | Size | Parallel? |
|---|---|---|---|---|
| 3.1 | Create `scripts/apply-class-tagging-template.sh` — splice script with idempotency sentinel; **single-file-at-a-time invocable** (`apply-class-tagging-template.sh <persona-path>`); `--dry-run` mode produces unified diff to `/tmp/class-tagging-splice.diff` for human review BEFORE real run; `tests/test-class-tagging-spliced.sh` invariant test (asserts content between sentinels is byte-identical to template, not just bracket-presence) | Wave 2 | S | — |
| 3.2 | **Step 1: dry-run** — `find personas/{review,plan,check} -name "*.md" -exec apply-class-tagging-template.sh --dry-run {} \;` produces aggregate diff. **HUMAN REVIEW GATE on the diff** before real run. **Step 2: real run** over remaining ~27 personas after diff approval | 3.1 | S | — |
| 3.2b | Independent post-splice validator: `tests/test-agents.sh` extension that asserts frontmatter parses on every persona file post-splice (catches "splicer ate the `---` delimiter" failure that sentinel-only test would miss) | 3.2 | XS | — |
| 3.3 | Create `commands/_gate-mode.md` shared include — 24-cell CLI flag truth table; mode resolution rules; banner text templates | Wave 2 | S | [P with 3.4] |
| 3.4 | Create `scripts/_gate_helpers.sh` — `gate_max_recycles` clamp logic; sourced by all 3 interactive gate commands | — | S | [P with 3.3] |
| 3.5 | Update `commands/spec-review.md` — frontmatter parse, CLI flag parse (`--strict`/`--permissive`/`--force-permissive`), mode resolution, banner emission with both sentinels (`~/.claude/.gate-mode-default-flip-warned-v0.9.0` + `docs/specs/<feature>/.gate-mode-warned`), `.force-permissive-log` writes (JSONL audit row), `.recycles-clamped` clamping, iteration tracking via `.iteration-state.json`, Synthesis invocation, `spec-review-verdict.json` emission, refuse `--force-permissive` if `$CI` or `$AUTORUN_STAGE` set | 1.4, 1.5, 3.3, 3.4 | M | [P with 3.6, 3.7] |
| 3.6 | Update `commands/plan.md` — same shape as 3.5; emits `plan-verdict.json` | 1.4, 1.5, 3.3, 3.4 | M | [P with 3.5, 3.7] |
| 3.7 | Update `commands/check.md` — same shape as 3.5; emits `check-verdict.json` (preserves autorun's hardcoded path) | 1.4, 1.5, 3.3, 3.4 | M | [P with 3.5, 3.6] |
| 3.8 | Update `commands/build.md` — read `check-verdict.json` (HARDCODED, not "or equivalent"); legacy-detection ladder (missing sidecar = pre-v0.9.0 today's behavior; v1 sidecar = refuse w/ upgrade pointer; **malformed JSON sidecar = refuse with same error class as v1**; v2 GO/GO_WITH_FIXES = proceed; v2 NO_GO = refuse); filter `followups.jsonl` to `state: open` AND `target_phase IN (build-inline, docs-only)`; plan-revision rows trigger `/plan` re-run; post-build rows become PR-body annotations | 1.4 | M | [P with 3.5/3.6/3.7] |
| 3.8b | Create `scripts/build-mark-addressed.py` (NEW) — `/build` wave-final calls `build-mark-addressed.py --feature <slug> --finding-ids "ck-aa,ck-bb" --commit-sha <SHA>`; acquires `_followups_lock.py`; reads followups.jsonl; sets `state: addressed`, `addressed_by: <SHA>`, `updated_at: now` on matching rows; atomic .tmp+rename. Closes MF2 (addressed_by writer ownership); enables A14d testability | 1.5 | S | — |
| 3.9 | Update `commands/spec.md` Phase 3 — frontmatter schema gains `gate_mode`, `gate_max_recycles` (template format reconciliation deferred to follow-up per OQ2) | — | XS | [P] |
| 3.10 | Update `scripts/_render_persona_insights_text.py` — 2-3 line back-fill: `row.get('class', 'unclassified')` + filter `if row.get('class') != 'unclassified'` for class-stratified stats | 1.2 | XS | [P] |

**Verifier:** end-to-end `/check` against fixture spec with known finding mix produces expected verdict + correct `followups.jsonl`; `/check --permissive` on strict-frontmatter spec exits with conflict error; `/check --force-permissive` writes audit log + emits banner; `/build` against NO_GO refuses to start; `/build` against missing-sidecar (pre-v0.9.0 spec) behaves as today.

**Minimum-shippable test:** Yes — at end of wave 3, the feature is end-to-end functional.

---

### Wave 4 — Documentation surfaces (A15a — blocking for v0.9.0)

| # | Task | Depends On | Size | Parallel? |
|---|---|---|---|---|
| 4.1 | Update `docs/index.html` mermaid diagram — three-tier verdict (GO / GO_WITH_FIXES / NO_GO); `diagrams.md` source updated first | Wave 3 | S | [P with 4.2] |
| 4.2 | Update `CHANGELOG.md` v0.9.0 entry — default flip from de-facto strict → permissive; opt-back-in instructions (`gate_mode: strict`); taxonomy summary; `.force-permissive-log` audit-log location + per-user/per-spec sentinel paths; one-line note on grep-fallback removal if bundled per OQ3 | Wave 3 | S | [P with 4.1] |
| 4.3 | Update `install.sh` — append one bullet to existing `<<UPGRADE` heredoc; gate on `~/.claude/.gate-permissiveness-migration-shown` sentinel for one-shot semantics | — | XS | [P] |

**Verifier:** `docs/index.html` renders three-tier diagram cleanly; `CHANGELOG.md` v0.9.0 entry passes adopter scan (clear migration steps); `install.sh` upgrade-banner test (run twice → second silent); `bash scripts/doctor.sh` confirms VERSION sync.

---

### Wave 5 — Hardening: tests + orchestrator wiring + edge-case coverage

| # | Task | Depends On | Size | Parallel? |
|---|---|---|---|---|
| 5.1 | Create `tests/test-permissiveness.sh` (NEW) — A12 fixture matrix: each (mode × class), mixed-class, dedup-disagreement, missing/invalid `class:`, stale-followups (strict-after-permissive), cap-reached (with security; in strict), CLI override precedence (`--strict`/`--permissive`/`--force-permissive`), legacy sidecars, target_phase routing, `addressed → open` regression transition, cross-gate isolation per A14, concurrency lock per A14c, `--force-permissive` refused in CI env | All | M | — |
| 5.2 | Create `tests/fixtures/permissiveness/*.findings.jsonl` — fixture data for 5.1; ~30 fixtures total | 5.1 | M | [P with 5.1] |
| 5.3 | **EXPLICIT ORCHESTRATOR WIRING** — edit `tests/run-tests.sh` to invoke `test-permissiveness.sh` AND `test-class-tagging-spliced.sh`. Verify count: `ls tests/test-*.sh \| wc -l` matches orchestrator's invocation list (per `feedback_test_orchestrator_wiring_gap.md`) | 3.1, 5.1 | XS | — |
| 5.4 | Update `tests/test-agents.sh` if new persona template requires frontmatter validation | 3.2 | XS | [P with 5.3] |
| 5.5 | Add Edge Case 16 to spec.md (defer-from-spec): reworded-finding dedup-key drift; renderer-failure recovery path; `iteration > iteration_max` data&state expansion; per-spec banner once-per-session-per-spec (vs once-per-session) clarification; "Codex review at /check is mandatory" line in spec Approach section per BACKLOG | — | XS | [P] |

---

### Wave 6 — Release commit (PR-final)

| # | Task | Depends On | Size | Parallel? |
|---|---|---|---|---|
| 6.1 | Bump `VERSION` to 0.9.0 via `scripts/bump-version.sh minor`; verify `docs/index.html` version pins sync; absolute final commit of the PR — runs only after `bash tests/run-tests.sh` exits clean (W5 fully green). If W5 reveals a fix-needed, recover by amending the prior wave's commit, NOT by reverting a v0.9.0 VERSION declaration. Closes Codex round-4 #1 + sequencing #4. | All waves green | XS | — |

**Verifier:** `bash tests/run-tests.sh` exits 0; `cat VERSION` returns `0.9.0`; `git log --oneline -1` shows the version-bump commit at HEAD.

**Verifier:** `bash tests/run-tests.sh` runs `test-permissiveness.sh` + `test-class-tagging-spliced.sh`; all fixtures pass; `ls tests/test-*.sh | wc -l` matches orchestrator's invocation count (no dangling files); all previously-existing tests still pass.

---

## Cross-cutting Decisions Pinned

These resolve open questions from /spec-review v2 + designer divergences:

- **Lock primitive:** `fcntl.flock` (kernel auto-release on FD close); helper at `scripts/_followups_lock.py`; lock-file content `{pid, hostname, started_at}` for audit only (not for liveness checks); 60s default timeout; NFS/iCloud out of scope.
- **`render-followups.py` runs OUTSIDE the lock** — post-rename atomic file is stable; eliminates double-locking (per scalability OQ-S2).
- **Sidecar names:** `spec-review-verdict.json`, `plan-verdict.json`, `check-verdict.json`. Fence label stays `check-verdict` for v1; `gate-verdict@1.0` rename deferred to v2 only if cross-stage consumers need a stable contract.
- **`/build` reads `check-verdict.json` ONLY** (hardcoded; never falls through to plan-verdict / spec-review-verdict). Codex blocker #2 closed.
- **Architectural carve-outs (Codex major #7):** data-loss, irreversible-migration, release-rollback-failure, supply-chain-risk findings → `class: architectural` (block). Add to taxonomy table tiebreaker rules in `personas/judge.md`.
- **`unclassified == block` is HARDCODED**, not a configurable gate_policy row. Constitution attempting to demote → constitution-validation failure (security recommendation).
- **`--force-permissive` requires reason string** (recommended; OQ1 lean-yes). `--force-permissive="releasing hotfix"`. Reason captured in audit log row.
- **`.iteration-state.json` per spec** is the iteration counter source of truth (Codex major #5 fix). Synthesis reads + increments; autorun bounds-checks; clean re-invocation removes the file (or `--reset-iteration`).
- **`--dry-run-class-coverage`** flag added to gates as an unclassified-deadlock mitigation (Codex major #6). Run before merging persona batch.
- **`commands/spec.md` template format reconciliation** deferred to follow-up (OQ2; CHANGELOG note).

---

## What ships in v0.9.0 vs deferred

**Ships in v0.9.0:**
- All 5 waves above
- A1–A17 acceptance criteria from spec
- Migration banner (per-user + per-spec sentinels)
- `--force-permissive` audit log
- `cap_reached` next-steps stderr block (ux Option E)
- `followups.md` rendered output with provenance header (ux Option F)
- A15a (mermaid + CHANGELOG)

**Deferred to v0.9.1+:**
- A15b (README narrative update)
- `/wrap-quick` force-permissive surface (defer-able per OQ4; ux Option D layer 3)
- `commands/spec.md` template YAML reconciliation
- `gate-verdict@1.0` fence-label generalization
- Taxonomy expansion to v2 axes (data-loss / migration-risk / perf / observability as their own classes — v1 carves them as architectural)

---

## Plan-time New Acceptance Criteria

Designers proposed these additions; folding into spec at /build wave 5:

- **A18.** Per-user sentinel `~/.claude/.gate-mode-default-flip-warned-v0.9.0` fires verbose explanation once-ever; touch-on-first-gate.
- **A19.** Per-spec sentinel fires one-line nudge once-per-spec after per-user sentinel exists.
- **A20.** `--force-permissive` writes JSONL audit row with pinned fields (`timestamp`, `iteration`, `gate`, `user`, `spec`, `verdict_sidecar`, `reason`).
- **A21.** `cap_reached AND verdict: NO_GO` prints 3-line "next steps" stderr block; `cap_reached AND GO_WITH_FIXES` stays silent.
- **A22.** `followups.md` header includes provenance block (spec/gate/mode/iteration/links) + counts (open/addressed/superseded).
- **A23.** `regression: true` rows get `⚠ regressed (was addressed in <SHA>)` marker in rendered MD.
- **A24.** `--force-permissive` exits non-zero if `$CI` or `$AUTORUN_STAGE` env vars set (interactive escape hatch only).
- **A25.** `unclassified` is hardcoded-block; constitution attempting to demote rejects at constitution-validation step.
- **A26.** `/build` legacy-detection ladder: missing sidecar (pre-v0.9.0 behavior) / v1 sidecar (refuse w/ upgrade pointer) / v2 GO|GO_WITH_FIXES (proceed) / v2 NO_GO (refuse). All 4 paths fixture-tested.
- **A27.** `--dry-run-class-coverage` flag reports persona-by-persona class-tagging compliance; runs before persona-batch merge.
- **A28.** `class:security` ↔ `tags:["sev:security"]` parity enforced at runtime in `_enforce_class_sev_parity()`; mismatch coerces to `unclassified` AND emits `security_findings[]` row of `kind: class_sev_mismatch`.

---

## Approval

Approve to proceed to `/check` (5 plan reviewer agents will validate before /build)? (approve / adjust `<what to change>`)
