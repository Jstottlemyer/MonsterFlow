---
name: dynamic-roster-per-gate
stage: plan
created: 2026-05-06
revised: 2026-05-06
gate_mode: permissive
---

# Plan — dynamic-roster-per-gate

**Generated:** 2026-05-06 (autorun headless)
**Spec:** `docs/specs/dynamic-roster-per-gate/spec.md`
**Review:** `docs/specs/dynamic-roster-per-gate/review-findings.md` (verdicts: ambiguity PASS-WITH-NOTES, feasibility PASS-WITH-NOTES, gaps PASS-WITH-NOTES, requirements PASS-WITH-NOTES, scope **FAIL**, stakeholders **FAIL**)
**Gate mode:** permissive (per spec frontmatter)

---

## Synthesis Posture

The spec is unusually thorough on security carve-outs (SEC-01/02/03), but the scope and stakeholder reviewers each issued FAIL with the same root cause: the spec bundles four ship-able features into one PR (tag-matching + tier policy, constitution rename, two escape hatches, `--explain` + dashboard), and SEC-01/02/03 expand the test surface without the v1 base feature having shipped any value yet.

**Plan posture:** ship the spec as a phased MVP-first sequence. Wave 1–5 delivers the core dispatch behavior (tag-matching, tier policy, persona backfill, gate wiring). Wave 6 lands escape hatches and constitution rename only after Wave 1–5 is green. Wave 7 covers the full security/test matrix. The spec's ACs are partitioned across these waves explicitly so /check can validate each wave in isolation.

This plan does **not** rewrite the spec; it resolves the contract ambiguities that two engineers would implement differently (C1–C5, REQ-001/002/003, R1–R3), commits to the highest-fidelity reading of each, and flags the remaining FAIL-class items as Open Questions for the /check gate to adjudicate before /build.

---

## Design Decisions

### D1. `fit_score` ≡ `fit_count` ≡ `len(spec.tags ∩ persona.fit_tags)` — raw integer (resolves C1)
Three names for one concept in the spec; pin one. The selection.json `fit_score` field is a non-negative integer count of intersecting tags. Drop `fit_count` from prose; rename A1 to use `fit_score`.

**Anti-breadth mitigation (resolves R2):** raw count alone rewards persona authors who declare every tag. Apply a capped specificity adjustment:

```
combined = fit_score × load_bearing_rate × specificity_factor
specificity_factor = 1.0       if len(persona.fit_tags) ≤ 3
                   = 0.85      if len(persona.fit_tags) == 4
                   = 0.70      if len(persona.fit_tags) ≥ 5
```

This is gentle (the dominant signal stays load-bearing-rate × intersection size) but prevents the "declare everything" attractor. CI lint rejects any persona with `len(fit_tags) > 6` without a `fit_tags_justification:` frontmatter comment.

### D2. Tie-breaking: lexicographic by persona name, ascending (resolves C2)
When `combined` scores tie, sort by persona filename (lowercase, ASCII). Deterministic, auditable, no mtime / no random. Documented in `_persona_score.py` docstring + selection.json audit row gains `tie_broken: true | false`.

### D3. Override merge: deep-merge for `tier_pins`, shallow-replace for everything else (resolves C3)
- `tier_policy.tier_pins.<gate>.<persona>` — deep merge across constitution → spec → CLI; later layer wins on each `(gate, persona)` key. So constitution `{check: {scope-discipline: opus}}` + spec `{check: {gaps: opus}}` = `{check: {scope-discipline: opus, gaps: opus}}`.
- All other `tier_policy.*` keys (`opus_min`, `default_worker`, `codex`, `orchestrator`) — shallow replacement; later layer wins on the whole key.

### D4. Security floor scope: `"security" in persona.fit_tags` literal membership test (resolves C4)
The floor applies iff the persona's declared `fit_tags` array contains the string `"security"`. Persona name (`security-architect`, etc.) is not load-bearing for the check. Documented in `_tier_assign.py:enforce_security_floor()`.

### D5. Stale-tags drift = baseline regex re-inference, not LLM re-inference (resolves C5, REQ-001)
`/spec-review` Phase 1 step 0 re-runs `_tag_baseline.py` against current spec body and compares to the recorded `tags_provenance.baseline` subset. Drift = ≥1 enum delta on the baseline subset. LLM-added tags excluded from drift detection. Deterministic and testable.

### D6. Provenance is a structured frontmatter key, not a comment (resolves I4)
Replace the inline `# baseline: ...; llm-added: ...` comment with a durable structured key:

```yaml
tags: [security, data, api]
tags_provenance:
  baseline: [security, data]
  llm_added: [api]
```

Survives `python-frontmatter` round-trips. `_tag_baseline.py` writes both keys atomically.

### D7. Subagent-model precedence: explicit caller-side override; CI guard against frontmatter `model:` (resolves R1)
Empirical verification step in W2: dispatch a throwaway Agent-tool call with `model: "sonnet"` against a persona file containing `model: opus` frontmatter; record which wins. Either way, codify the rule:
- **Preferred:** caller-supplied `model` parameter overrides persona-file frontmatter. Add CI guard `tests/test-persona-no-model-frontmatter.sh` rejecting any `personas/**/*.md` with a `model:` frontmatter key (forbidden — tier comes from resolver, not persona file).
- **Fallback (if Agent tool ignores caller):** the resolver writes a per-dispatch wrapper subagent file at `~/.claude/agents/_dispatch-<persona>-<tier>.md` containing the persona body + frontmatter `model: <tier>`, dispatches against that, deletes after.

W2 picks the path empirically; spec is updated inline before /build.

### D8. Tier slug resolution: configurable map in `pipeline-config.md` with baked-in defaults (resolves TF-1, TF-2)
`_tier_assign.py:resolve_tier_slug(tier)` reads `tier_policy.tier_slugs` from config; falls back to a hardcoded constant (`{"opus": "opus", "sonnet": "sonnet"}`) if unset. selection.json gains a `tier_resolved_slug` field per row. W2 verifies `claude -p --model --help` empirically and documents the canonical slug strings (long-form `claude-opus-4-...` vs short alias `opus`); updates the constant in `_tier_assign.py` accordingly.

### D9. Concurrent write safety: `fcntl.flock` on `selection.json` + audit logs (resolves MR-02, REQ-005)
Reuse v0.9.0's `_followups_lock.py` pattern. All writers (`selection.json`, `.security-downgrade-log`, `.baseline-mismatch-log`, `selection-history.jsonl` if added) acquire `LOCK_EX`; readers use `LOCK_SH`. Single helper at `scripts/_artifact_lock.py` to avoid per-file boilerplate.

### D10. Opus rate-limit fallback: exponential backoff (3 attempts) → halt-with-followup (resolves MR-04, CG-3, REQ-004)
On 429/overloaded for an Opus dispatch:
1. Exponential backoff: 5s, 30s, 120s.
2. If still failing, halt the gate; emit followup row `class: architectural`, `tags: ["opus-rate-limited"]`, `state: open`.
3. **Never** silently downgrade a `fit_tags:[security]` persona — security floor is hard.
4. For non-security personas, `--allow-tier-fallback` (interactive-only, refused in CI/AUTORUN_STAGE) permits one-shot Sonnet substitution with audit row.

### D11. In-flight spec migration: explicit `tags_source: missing | declared | grandfathered` field (resolves MR-01)
Resolver detects missing `tags:`, emits one-line warning, proceeds with ranking-only fallback, writes `tags_source: missing` to selection.json. Existing specs that pre-date the feature get the same treatment. No `--backfill-tags` subcommand in v1; users edit spec.md directly via `/spec` revision flow if they want to opt in.

### D12. Test fixture count: hard cap at 33 (resolves CG-3)
Per scope reviewer's allowlist:
- A1–A14: 14 happy-path fixtures (one per AC)
- SEC-01: 3 fixtures (downgrade rejection × 3 gates)
- SEC-02: 7 fixtures (3 baseline-positive + 2 baseline-negative + 2 adversarial-injection)
- SEC-03: 3 fixtures (mutation-zero × 3 invocation forms)
- Edge cases: 6 representative fixtures (cold-start, empty-intersection, budget<opus_min, tier_pins-promotion, stale-tags, concurrent-write)

Total: **33 fixtures**, hard cap. Anything beyond gets deferred to a follow-up hardening spec. Wall-clock budget A18 stays at <10s.

### D13. Phased ship: MVP at v0.10.0 (W1–W5), escape hatches + rename at v0.10.1 (W6), full security matrix at v0.10.2 (W7) (resolves CG-1, CG-2, IC-5)
- **v0.10.0 (MVP):** tag schema + persona fit_tags backfill + resolver tag-matching + tier rule + gate wiring. Uses existing `constitution.md` filename. No escape hatches. No `--explain`. No dashboard column. Ships A1–A18 + A21 (basic security floor enforcement; rejection only, no escape hatch).
- **v0.10.1:** `--allow-security-downgrade`, `--acknowledge-baseline-mismatch`, constitution rename, `--explain` flag, dashboard tier-mix column. Ships A15, A16, A19, A23, A24 (new), A25 (new).
- **v0.10.2:** full SEC-02 adversarial fixture set, SEC-03 mutation-zero with full env-var pinning, A22 expansion, R7 persona-fit-tags-freshness CI guard.

This plan tracks all 7 waves but flags v0.10.0 as the MVP cut. /check should validate that W1–W5 stand alone before approving full-feature build.

### D14. Constitution rename adopter migration (resolves CG-2, MR-11, R6)
install.sh detects three states explicitly:
- `[ -L docs/specs/constitution.md ]` (symlink): no-op, log "migration already applied".
- `[ -f docs/specs/constitution.md ]` && `[ ! -f docs/specs/pipeline-config.md ]`: back up to `~/.monsterflow-backups/<timestamp>/constitution.md`, rename in place, create reverse symlink (`constitution.md` → `pipeline-config.md`), banner the change.
- `[ ! -e docs/specs/constitution.md ]` && `[ ! -e docs/specs/pipeline-config.md ]`: create `pipeline-config.md` from template, create reverse symlink for back-compat readers.
- Both real files exist: halt with migration error; user resolves manually.

`tests/test-install-idempotency.sh` runs install.sh 3× on a fixture repo; asserts identical state after run 2 and 3. Symlink retained through v0.11.0; removed in v0.12.0 by install.sh detection (>= 0.12.0 + symlink exists → prompt removal).

### D15. Codex lineage isolation in `persona-rankings.jsonl` (resolves R5)
Schema-pin: every row carries `lineage: "claude" | "codex"`. Resolver `(fit_score × load_bearing_rate)` reads only `lineage == "claude"` rows. Backfill existing rows with `lineage: "claude"` (Codex emission to this file is opt-in / recent). CI grep guard rejects new emit sites lacking the field. Lockstep file-pair guard against `dashboard/data/persona-rankings.schema.json`.

### D16. Tier-aware autorun timeouts (resolves R4)
`pipeline-config.md` introduces `autorun.timeout_persona_opus: 1200` and `autorun.timeout_persona_sonnet: 600` (defaults shown). `scripts/autorun/{spec-review,plan,check}.sh` reads the per-tier timeout from `selection.json` rows and passes the correct `timeout` value per parallel `claude -p` call. Opus-timeout-with-no-other-Opus-in-panel is classified as `block` axis (violates A2); Opus-timeout-with-other-Opus-present = `warn`.

### D17. Autorun escape-hatch deadlock — explicit halt-with-followup (resolves CG-1)
SEC-02 baseline-mismatch in autorun: gate halts, emits structured followup row `class: scope-cuts`, `tags: ["baseline-false-positive-suspected"]`. Operator addresses interactively in the morning via `--acknowledge-baseline-mismatch <reason>`. SEC-01 security-downgrade follows the same halt-with-followup pattern. This matches the v0.9.0 `--force-permissive` precedent (halt overnight on the rare hard cases; resolve interactively).

---

## Implementation Tasks

| # | Task | Wave | Depends On | Size | Parallel? | Resolves |
|---|------|------|-----------|------|-----------|----------|
| 1 | `schemas/tags.enum.json` — single source of truth for the closed enum | W1 | — | S | — | I1, MR-05 |
| 2 | `schemas/spec-frontmatter.schema.json` extension — `tags`, `tags_provenance`, `tier_policy` | W1 | 1 | S | Yes (with 3) | A19, D6 |
| 3 | `schemas/persona-frontmatter.schema.json` (new) — `fit_tags`, `fit_tags_justification` | W1 | 1 | S | Yes (with 2) | A17, A19 |
| 4 | `schemas/selection.schema.json` extension — `tier`, `tier_policy_applied`, `tier_resolved_slug`, `tags_source`, `tie_broken`, `lineage` | W1 | 1 | S | Yes (with 2,3) | A13, D8, D11, D15 |
| 5 | `schemas/check-verdict.schema.json` review for `selection.json` consumer drift | W1 | 4 | S | — | A19 |
| 6 | Lockstep CI guard extension — file-pair stubs for new schemas | W1 | 2,3,4 | S | — | A19 |
| 7 | Empirical verification — `claude -p --model --help` + Agent-tool model precedence test | W2 | — | S | Yes (with 1) | TF-1, R1 |
| 8 | `scripts/_persona_score.py` — fit_score × load_bearing_rate × specificity_factor; cold-start; tie-break lex | W2 | 4,7 | M | — | A1, A10, D1, D2, R2 |
| 9 | `scripts/_tier_assign.py` — top-N → tier; tier_pins; budget<opus_min; security floor; CLI flag validator | W2 | 8 | L | — | A2–A8, SEC-01, D4, D7, D8 |
| 10 | `scripts/_tag_baseline.py` — regex baseline; AST-banlist (no eval/exec/subprocess/socket) | W2 | 1 | M | Yes (with 8,9) | SEC-02, A22, R3 |
| 11 | `scripts/_artifact_lock.py` — fcntl.flock helper for selection.json + audit logs | W2 | 4 | S | Yes (with 8,9,10) | MR-02, REQ-005, D9 |
| 12 | `scripts/resolve-personas.sh` extension — content-tag intersection + ranked tier output `<persona>:<tier>` | W2 | 8,9,10,11 | M | — | A1, A13, A14 |
| 13 | Resolver Opus rate-limit handler — backoff + halt-with-followup | W2 | 12 | M | — | MR-04, CG-3, REQ-004, D10 |
| 14 | Persona `fit_tags` backfill — review/ (6) | W3 | 3 | M | Yes (with 15,16) | A17, IC-4 |
| 15 | Persona `fit_tags` backfill — plan/ (7) | W3 | 3 | M | Yes (with 14,16) | A17, IC-4 |
| 16 | Persona `fit_tags` backfill — check/ (6) | W3 | 3 | M | Yes (with 14,15) | A17, IC-4 |
| 17 | `tests/test-persona-frontmatter.sh` — schema validation across all 19 personas | W3 | 14,15,16 | S | — | A17 |
| 18 | `commands/spec.md` Phase 3 extension — baseline∪LLM tag inference, user-confirm/edit/skip, broad-tag-set warning | W4 | 10 | M | — | A12, R3, D6 |
| 19 | LLM mocking harness — `MONSTERFLOW_LLM_FIXTURE_DIR` env-driven test pattern | W4 | 18 | S | — | REQ-003 |
| 20 | `commands/spec-review.md` Phase 0b + Phase 1 step 0 — resolver call, tier dispatch, stale-tags warning | W5 | 12 | M | Yes (with 21,22) | A11, A14, D5 |
| 21 | `commands/plan.md` Phase 0b — resolver call, tier dispatch | W5 | 12 | S | Yes (with 20,22) | A14 |
| 22 | `commands/check.md` Phase 0b — resolver call, tier dispatch | W5 | 12 | S | Yes (with 20,21) | A14 |
| 23 | `scripts/autorun/spec-review.sh` — `:tier` parsing, `--model` per call, tier-aware timeout | W5 | 12,16 | M | Yes (with 24,25) | A14, R4, D16 |
| 24 | `scripts/autorun/plan.sh` — same | W5 | 12 | M | Yes (with 23,25) | A14, R4 |
| 25 | `scripts/autorun/check.sh` — same | W5 | 12 | M | Yes (with 23,24) | A14, R4 |
| 26 | **MVP CUT v0.10.0** — wire 1–25 into preship; ship under existing `constitution.md` filename | M1 | 1–25 | S | — | D13 |
| 27 | `--allow-security-downgrade` CLI handler + followup-row writer + audit log | W6 | 9,11 | M | Yes (with 28) | SEC-01-followup, A24 (new) |
| 28 | `--acknowledge-baseline-mismatch` CLI handler + followup-row writer + audit log | W6 | 10,11 | M | Yes (with 27) | SEC-02-followup, A25 (new) |
| 29 | Constitution rename — files + symlink + install.sh idempotency branches + backup dir | W6 | — | M | Yes (with 27,28) | CG-2, MR-11, R6, D14 |
| 30 | `tests/test-install-idempotency.sh` — 3× run assertion | W6 | 29 | S | — | R6 |
| 31 | `scripts/_explain_format.py` — read-only stdout pretty-printer over selection.json | W6 | 4 | M | Yes (with 27,28,29) | SEC-03, A23, IC-1 |
| 32 | `--explain` integration in `resolve-personas.sh` — RESOLVER_DRY_RUN=1 short-circuit | W6 | 12,31 | S | — | A23, IC-1, REQ-009 |
| 33 | Dashboard "Panel Tier Mix" column — read selection.json defensively | W6 | 4,12 | M | Yes (with 27–32) | A16, IC-2, IC-3 |
| 34 | **MVP CUT v0.10.1** — wire 27–33 into preship | M2 | 26, 27–33 | S | — | D13 |
| 35 | `tests/test-dynamic-roster.sh` — A1–A14 happy paths (14 fixtures) | W7 | 26 | L | Yes (with 36–41) | A18, D12 |
| 36 | `tests/test-tier-resolver.sh` — `_tier_assign.py` unit tests | W7 | 9 | M | Yes (with 35,37–41) | A18 |
| 37 | `tests/test-persona-fit-tags.sh` — fit_tags integrity (no orphans, no empty fit_tags warning) | W7 | 14,15,16 | S | Yes (with 35,36,38–41) | A17 |
| 38 | `tests/test-spec-tags-flow.sh` — `/spec` Phase 3 baseline∪LLM union flow | W7 | 18,19 | M | Yes (with 35–37,39–41) | A12 |
| 39 | `tests/test-security-floor.sh` — SEC-01 fixtures (3) | W7 | 9 | M | Yes (with 35–38,40,41) | A21, SEC-01 |
| 40 | `tests/test-tag-baseline.sh` — SEC-02 fixtures (7: 3 positive + 2 negative + 2 adversarial) | W7 | 10 | M | Yes (with 35–39,41) | A22, SEC-02, R3 |
| 41 | `tests/test-explain-mutation-zero.sh` — SEC-03 fixtures (3) with HOME/XDG/TMPDIR/PYTHONDONTWRITEBYTECODE pinning | W7 | 31,32 | M | Yes (with 35–40) | A23, SEC-03, TF-4 |
| 42 | `tests/test-concurrent-write.sh` — selection.json + audit log fcntl.flock under parallel writers | W7 | 11 | M | Yes (with 35–41) | MR-02, REQ-005 |
| 43 | `tests/test-rate-limit-fallback.sh` — Opus 429 mock → backoff → followup row | W7 | 13 | M | Yes (with 35–42) | MR-04, REQ-004 |
| 44 | Wire all new test files into `tests/run-tests.sh` orchestrator (single sequential post-step) | W7 | 35–43 | S | — | feedback_test_orchestrator_wiring_gap |
| 45 | Grep-test for stale `selection.json` literals in `commands/*.md`, `scripts/autorun/*.sh`, `docs/**/*.md` | W7 | 4 | S | Yes (with 35–44) | TF-5, feedback_schema_bump_grep_prose_drift |
| 46 | Codex lineage backfill — `dashboard/data/persona-rankings.jsonl` + new schema field | W7 | 4 | S | Yes (with 35–45) | R5, D15 |
| 47 | `CHANGELOG.md` + `README.md` + `docs/budget.md` updates | W7 | 26,34 | S | — | docs |
| 48 | **MVP CUT v0.10.2** — wire 35–47 into preship; full feature ship | M3 | 34, 35–47 | S | — | D13 |

**Parallelism:**
- W1 schemas (tasks 2,3,4) parallel.
- W2 helpers (tasks 8,9,10,11) parallel after schemas land.
- W3 persona backfills (14,15,16) parallel after schema 3 lands.
- W5 gate command edits (20,21,22) parallel; autorun shells (23,24,25) parallel.
- W6 escape hatches + rename + explain + dashboard (27–33) parallel.
- W7 tests (35–46) parallel — single test orchestrator wire-in (44) is sequential.

**Critical path:** schemas (W1) → helpers (W2) → resolver (12) → gate wiring (W5) → MVP cut. ~10 sequential dependencies.

---

## Open Questions for /check

These items are deferred to /check rather than resolved unilaterally because they touch policy decisions or have FAIL-class review findings that warrant a second-gate eyeball:

**Q1. (CG-1, scope FAIL)** Should W6 escape hatches (`--allow-security-downgrade`, `--acknowledge-baseline-mismatch`) ship at all in v1, or stay deferred until real-world friction justifies them? Plan currently includes them in v0.10.1 with halt-with-followup autorun behavior; scope reviewer recommends defer-until-needed. /check decides.

**Q2. (CG-2, MR-11, scope+gaps FAIL)** Is the constitution rename a separate spec (`pipeline-config-rename`) or part of this one? Plan currently bundles into v0.10.1 with adopter migration (D14); scope reviewer recommends carve out. /check decides.

**Q3. (IC-1, scope minor)** Is `--explain` v1 or deferred? Plan currently includes in v0.10.1 with read-only contract (task 31); scope reviewer recommends defer (`jq selection.json` covers happy path). /check decides.

**Q4. (IC-2)** Is the dashboard tier-mix column v1 or deferred? Plan currently in v0.10.1; scope reviewer recommends defer. /check decides.

**Q5. (MR-03, security)** Audit log integrity — currently "we wrote a file"; no hash chain, no signing, no commit-required-on-write. Acceptable for single-user dev workstations (per MR-13)? Or add minimum tamper-evident SHA-256 chain? Plan defers to a follow-up but flags the threat-model documentation as an in-spec acceptance.

**Q6. (MR-07, scope-cuts)** Cost telemetry — Opus floor measurably increases per-feature cost. Plan does not add a Cost column. Defensible defer or v1 requirement?

**Q7. (MR-08)** `/spec` Phase 3 in autorun — interactive flow with no documented headless path. Plan defers; should `/spec` refuse autorun invocation, or auto-accept LLM proposal with followup row?

**Q8. (R3, high-severity)** Tag-inflation incentive at spec-author level. Plan adds the `len(tags) ≥ 4` warning and an A22 reverse-adversarial fixture. Is the gentle prompt sufficient, or does dispatch need a hard cap on tag-set size?

**Q9. (D7, R1 high-severity)** Subagent-model precedence — the empirical W2 verification step (task 7) decides between caller-override path and per-dispatch wrapper file path. /check should ratify the chosen path before /build commits to it.

**Q10. (Q-haiku-tier from spec)** Reserved for /check if cost data emerges; spec already defers to v2.

---

## Risks (top 5 carried into /build)

1. **R1 / D7 / task 7** — Subagent-model precedence empirical: if Agent-tool / `claude -p` ignore caller-supplied `model` and persona frontmatter wins, the entire dispatch contract changes. Mitigated by W2 empirical step + CI guard against `model:` in personas. **Plan-blocker if W2 task 7 finds caller cannot override.**

2. **R2 / D1 / task 8** — Fit-score breadth bias: specificity_factor (0.7–1.0) is gentle; if persona authors still drift toward declaring everything, future iteration to Jaccard required. Mitigated by CI lint at `fit_tags > 6`.

3. **R3** — Tag-inflation incentive: gentle UX prompt; carries forward as observable in `tags_set_size_distribution` dashboard metric (W7).

4. **R4 / D16 / task 23–25** — Tier-aware autorun timeouts: Opus 2× wall-clock budget. Tested under representative-spec load fixture; if real specs exceed 1200s, raise default before v0.10.0 ship.

5. **R6 / D14 / task 30** — install.sh idempotency: 3× test only covers fresh + 2 reruns. Real adopter trees may have torn intermediate states (partial rename, manual edits). install.sh halt-with-error path on "both files exist" is the safety net.

---

## Acceptance Criteria Mapping

All 23 spec ACs (A1–A23) are addressed across the waves. Two new ACs introduced by /plan (per REQ-002):

- **A24 (new)** — `--allow-security-downgrade` CLI: refused under CI/AUTORUN_STAGE; accepted interactively with mandatory non-empty reason; writes followup row with `class: security`, `state: open`, `tags: ["security-downgrade-acknowledged"]`, `metadata.reason`, `metadata.actor: "$USER"`, `metadata.timestamp_utc`; blocks /build wave 1 until transitioned to `state: addressed` with referencing commit SHA. (Task 27.)
- **A25 (new)** — `--acknowledge-baseline-mismatch` CLI: same shape as A24 with `tags: ["baseline-mismatch-acknowledged"]`, `metadata.removed_tags: [<list>]`. (Task 28.)

A20 (dogfood) remains explicitly deferred per spec; flagged as a follow-up BACKLOG item at v0.10.0 ship per REQ-011.

---

## Sequencing & Ship Plan

```
W1 (schemas)      W2 (helpers + resolver)     W3 (persona backfill)     W4 (/spec)     W5 (gate wiring)
   ↓                       ↓                          ↓                     ↓                 ↓
   └─────────────────[ MVP CUT v0.10.0 ]─────────────────────────────────────────────────────┘

W6 (escape hatches + rename + explain + dashboard)
   ↓
   └────[ v0.10.1 — pending Q1–Q4 /check decisions ]

W7 (full security/test matrix)
   ↓
   └────[ v0.10.2 — full feature ship ]
```

**Estimated effort:** v0.10.0 ≈ 4–6 build days (foundational + parallel-friendly). v0.10.1 ≈ 2–3 build days (each escape hatch + rename = independent). v0.10.2 ≈ 2 build days (test fixtures parallel).

**Permissive gate mode (`gate_max_recycles: 2`)** applies; class:warn findings (docs, contract minor, scope-cuts) apply inline at /build; class:block findings (architectural, security) gate on /check verdict.

---

*Plan generated by /plan synthesis pass over 7 design persona outputs (api, data-model, ux, scalability, security, integration, wave-sequencer) under autorun. Ready for /check.*
