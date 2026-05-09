---
name: token-economics
plan_for: spec v4.2 (revision 4.2, status: ready-for-build)
created: 2026-05-09
status: ready-for-check
session_roster: defaults-only (autonomous synthesis — full 7 designer roster not dispatched in headless mode)
---

# Implementation Plan — token-economics v4.2

## Source Artifacts

- Spec: `docs/specs/token-economics/spec.md` (v4.2)
- Review: 7 spec-review personas (ambiguity, docs-clarity, feasibility, gaps, requirements, scope, stakeholders) + risk analysis
- Round-3 verdict: 6/6 primary PASS WITH NOTES; risk analysis: GO with risks 1–2 promoted to Phase 0.5

This plan synthesizes those reviews + the 14 inline M/Δ must-fixes already applied in the spec, and folds round-3 review notes into ordered build tasks. No autonomous re-litigation of scope; carve-outs from review become inline tasks (T-prefixed) where they tighten ACs without re-opening MVP.

---

## Design Decisions

### D1 — Single-bundle dashboard load (resolves risk #2)

The spec calls for two separate generated JS sidecars (`persona-rankings-bundle.js` + `persona-roster.js`) loaded as two `<script src>` tags. Risk #2 in the spec's risk analysis flags the cross-file refresh race. **Decision: emit a single `dashboard/data/persona-insights-bundle.js` containing both `window.__PERSONA_RANKINGS = [...]` and `window.PERSONA_ROSTER = [...]` plus a top-level `window.__PERSONA_INSIGHTS_GENERATED_AT = "<ISO>"`.** Atomic by construction. The JSONL file (`persona-rankings.jsonl`) remains the canonical source of truth; the bundle is a derived render-side mirror.

Spec sections affected: §Approach Phase 1 ("Roster sidecar emit"), §Integration "Files created", A5. None of these are gated on the two-file shape; the change is a strict simplification.

### D2 — Phase 0.5 import-cleanliness gate (resolves risk #1)

Before any code that depends on M1 (`importlib.util` import of `session_cost`) is written, run a one-line probe asserting `scripts/session-cost.py` has zero side effects on import (no stdout/stderr, no `sys.exit`, no file writes). If it fails, refactor `session-cost.py` to put CLI logic under `if __name__ == "__main__":` first. This is a build pre-flight, not a runtime test; lives in `tests/test-session-cost-import-clean.sh`.

### D3 — `--explain PERSONA[:GATE]` semantics defined (resolves gaps #1)

Spec lists this flag in the post-M5 CLI surface but does not specify behavior. **Decision: `--explain PERSONA[:GATE]` writes a human-readable plaintext block to stdout (NOT JSONL) showing — for the named persona (and optional gate filter) — the row's `run_state_counts`, the `contributing_finding_ids[]` resolved against the most-recent matching `findings.jsonl` (titles INCLUDED, since `--explain` is interactive-debug surface invoked by the data owner on their own machine), and the source artifact directory paths.** Gated by the same TTY check as `--scan-projects-root` first-use prompt: refuses on non-tty stdin with a `[persona-value] --explain requires a TTY (resolves finding titles to plaintext); use --dry-run for counts-only` stderr line. Privacy posture: this is local-only output; it never feeds the JSONL, the bundle, or `/wrap-insights` text.

### D4 — `<unknown>` persona bucket contract (resolves gaps #3)

Description-invoked subagents (e.g., `persona-metrics-validator`, `autorun-shell-reviewer`) hit `persona = "<unknown>"`. **Decision: `<unknown>` rows are emitted to JSONL with `gate: "<unknown>"` and `run_state: "cost_only"` (always — they have no value-side artifact to land in `findings.jsonl`).** Dashboard hides them by default behind a "show orchestrator overhead" toggle. `/wrap-insights` text section excludes them from top/bottom 3 rankings. Cost-window aggregates still account for them so adopters can see total orchestrator overhead via the toggle.

### D5 — Window rollover = full rebuild (resolves gaps #4)

The JSONL is fully rebuilt every `compute-persona-value.py` run by walking the most-recent-45-per-(persona,gate) source window. **No append path exists.** Atomic write via tmp + `os.replace`. This is the only contract consistent with A8 idempotency. Documented in §Window section as a build deliverable (T-DOC-1).

### D6 — Schema migration contract for v1 → v1.1 (resolves gaps #2)

v1 ships with `schema_version: 1`. **Decision: v1.1 release notes will instruct `rm dashboard/data/persona-rankings.jsonl` before upgrade; readers in v1 only consume `schema_version: 1` rows; readers in v1.1+ regenerate from source on first run regardless of preexisting JSONL.** This avoids cross-version migration code in v1. A12 asserts that `compute-persona-value.py` refuses to read a JSONL row whose `schema_version != 1` (logs warning, treats as cache miss, regenerates).

### D7 — `participation.jsonl` precondition for `silent` state (resolves ambiguity #4)

Spec M4 introduces `silent` state requiring `participation.jsonl` row with `status: ok` AND `findings_emitted: 0`. **Decision: when `participation.jsonl` is missing or malformed for an artifact directory, fall through to the existing state machine (treat as `complete_value` if the other artifacts validate, else `missing_*`).** A persona that ran successfully but produced zero findings without a `participation.jsonl` row gets bucketed as `complete_value` with `total_emitted: 0` (already covered by e10). Documented in §Run state machine table (T-DOC-1).

### D8 — `silent` state retention semantics (resolves ambiguity #9, feasibility note)

Spec table says silent contributes (numerator=0, denominator includes emitted bullets). But a silent persona by definition emitted zero bullets (`findings_emitted: 0`). **Decision: silent state contributes (0, 0) to the retention ratio — null per e10 rule.** Cross-reference e10 explicitly. The `silent_runs_count` field surfaces the volume separately so adopters see "this persona ran 5 times silently" without it polluting retention rates.

### D9 — Cost-window cap = 45 (resolves ambiguity #3)

Add explicit field `cost_window_size: 45` to the schema, parallel to `window_size: 45`. Both default to 45; both clamp identically. T-DOC-1 makes this explicit in §Approach.

### D10 — Multi-persona finding survival counts +1 each (resolves ambiguity #11)

A finding with `personas: [scope-discipline, edge-cases]` and `outcome: addressed` increments downstream-survival for BOTH personas. Documented in §Approach denominator definition (T-DOC-1). No fractional credit; multi-persona findings reward all contributors.

### D11 — Bullet-counting regex pinned (resolves ambiguity #18)

Top-level emitted-bullet regex: `^[-*] ` (zero leading whitespace, dash or star, single space, anything after). Excludes `^  - `, `^ - `, `^\d+\. `, and any line under `## Verdict` heading. Extraction is line-oriented with a state machine that tracks current `## Heading`. T-DOC-1 codifies; A2 fixture exercises both passing and rejected cases.

### D12 — `last_artifact_created_at` minute-truncation A8 policy (resolves feasibility note)

Field is excluded from A8 idempotency byte-equality. **Decision: A8 freezes time inside the test (passes a synthetic `_NOW` injection or runs both invocations within the same calendar minute) and asserts byte-equal including this field; production reads are not subject to that constraint.** Production may show within-minute drift; that is not a defect.

### D13 — Persona-content-hash normalization pinned (resolves feasibility observation)

`persona_content_hash = "sha256:" + sha256(unicodedata.normalize('NFC', text).encode('utf-8').rstrip(b'\n') + b'\n').hexdigest()`. Trailing whitespace within lines is significant; trailing newlines normalize to exactly one; BOM stripped before normalization. T-DOC-1 codifies.

### D14 — Wave sequencer ordering: data → tests → UI

Default three-gate precedence per `commands/plan.md` instructions. **Wave 1: schemas + data layer + privacy primitives. Wave 2: tests against fixtures. Wave 3: dashboard UI + `/wrap-insights` text wiring.** Rationale: data contract and privacy gates have the highest blast radius; tests against the contract validate before UI consumes; UI is the cheapest to iterate.

### D15 — Test orchestrator wiring is a single-owner sequential post-step

Per project memory `feedback_test_orchestrator_wiring_gap.md` and risk #4: parallel `/build` agents must NOT touch `tests/run-tests.sh`. Wiring is a dedicated final task (T-WIRE-1) with explicit verification: `bash tests/run-tests.sh` must list all 10 new tests in its output. The inverted-assertion test (`test-allowlist-inverted.sh`) is invoked via `! ./tests/test-allowlist-inverted.sh` and that exact shell shape is part of the task spec.

### D16 — Document but don't ship: support runbook + persona-author posture

Stakeholder review flagged missing support runbook + persona-author-as-data-subject posture. **Decision: ship a one-page `docs/specs/token-economics/notes.md` covering: (a) interpreting low scores, (b) salt-rotation procedure, (c) persona-author guidance ("scores are machine-local, sample-noisy, and not a contributor evaluation"), (d) `--scan-projects-root` first-time-adopter walkthrough, (e) Linux-untested disclaimer, (f) v1.1-unblock criterion.** Surfaces same-PR; closes review gaps without scope creep.

---

## Implementation Tasks

| # | Task | File(s) | Depends On | Size | Parallel? | Wave |
|---|------|---------|------------|------|-----------|------|
| **T-PRE-1** | Phase 0.5: assert `scripts/session-cost.py` is import-clean | `tests/test-session-cost-import-clean.sh` (new) + possible refactor of `scripts/session-cost.py` (CLI under `if __name__`) | — | S | — | 0 |
| **T-PRE-2** | Author redaction helper for A0 fixtures | `scripts/redact-persona-attribution-fixture.py` | T-PRE-1 | M | — | 0 |
| **T-PRE-3** | Populate redacted A0 fixtures from RedRabbit session probe | `tests/fixtures/persona-attribution/*.jsonl` (real-data redacted) + `leakage-fail.jsonl` (deliberate-failure) | T-PRE-2 | S | — | 0 |
| **T-SCHEMA-1** | Author allowlist schema | `schemas/persona-rankings.allowlist.json` (`additionalProperties: false`, all v1 fields enumerated incl. `schema_version`, `cost_runs_in_window`, `cost_window_size`, `silent_runs_count`, `run_state_counts`, `truncated_count`, `insufficient_sample`) | — | S | Yes (with T-PRE-*) | 0 |
| **T-CORE-1** | Stub `compute-persona-value.py` skeleton: argparse with all 6 flags (`--scan-projects-root`, `--confirm-scan-roots`, `--best-effort`, `--out`, `--dry-run`, `--explain`), import-via-importlib of `session_cost`, `safe_log()` stderr wrapper | `scripts/compute-persona-value.py` | T-PRE-1, T-SCHEMA-1 | M | — | 1 |
| **T-CORE-2** | Project Discovery cascade (cwd + config + scan-confirmed), realpath dedup, `.monsterflow-no-scan` sentinel, tilde expansion, `validate_project_root()`, `scan-roots.confirmed` parsing robustness mirroring salt-file pattern (R7) | `scripts/compute-persona-value.py` | T-CORE-1 | M | — | 1 |
| **T-CORE-3** | Salt management (`finding-id-salt`): atomic create-or-fail (`O_CREAT \| O_EXCL`), validate-on-read (32 bytes, perms 0o600, non-zero), regenerate-and-clear-rankings on failure | `scripts/compute-persona-value.py` | T-CORE-1 | M | Yes (with T-CORE-2) | 1 |
| **T-CORE-4** | Stdlib allowlist validator (~30 LoC; replaces `jsonschema.validate`); enforces `additionalProperties: false`, `required[]`, basic type/enum/pattern | `scripts/compute-persona-value.py` (or sibling `scripts/_allowlist.py`) | T-SCHEMA-1 | S | Yes | 1 |
| **T-CORE-5** | Cost-side walker: walk `~/.claude/projects/*/`, parse Agent dispatches, recover persona via regex `personas/<gate>/<name>.md` from `Agent.input.prompt`, link `agentId` to `subagents/agent-<id>.jsonl`, sum `usage`, fall back to parent annotation when canonical (per A1.5 outcome) | `scripts/compute-persona-value.py` | T-CORE-1, T-CORE-2 | L | — | 1 |
| **T-CORE-6** | CC subagent layout drift probe (R6): sample 10 most-recent dispatches at startup, assert ≥80% parseable, emit `[persona-value] CC subagent layout v? detected` line; A1.6 unattributed-rate ≤5% threshold (see Open Q below) | `scripts/compute-persona-value.py` | T-CORE-5 | S | Yes | 1 |
| **T-CORE-7** | Value-side walker: walk discovered project roots, build per-(persona, gate, artifact-directory) records with `run_state` enum, read `participation.jsonl` for silent state (D7 fall-through on missing), count emitted bullets per D11 regex, count judge-retention from `findings.jsonl.personas[]`, count downstream-survival from `survival.jsonl.outcome == addressed`, count uniqueness from `findings.jsonl.unique_to_persona` | `scripts/compute-persona-value.py` | T-CORE-1, T-CORE-2 | L | — | 1 |
| **T-CORE-8** | Window aggregation: most-recent-45 per (persona, gate) by `run.json.created_at`; cost-window 45 dispatches independently per D9; `<unknown>` bucket per D4; missing-subagent-transcript fallback per gaps #11 (trust parent annotation, log warning) | `scripts/compute-persona-value.py` | T-CORE-5, T-CORE-7 | M | — | 1 |
| **T-CORE-9** | Salted finding-ID generator: `sha256(salt || normalized_signature)[:10]`, soft-cap most-recent-50 + `truncated_count`, sorted output for A8 stability (R8 concurrent-race fix) | `scripts/compute-persona-value.py` | T-CORE-3, T-CORE-7 | S | — | 1 |
| **T-CORE-10** | Output emit: `dashboard/data/persona-rankings.jsonl` (atomic, sort_keys=True, round 6dp, sorted by (gate, persona)) + single combined `dashboard/data/persona-insights-bundle.js` per D1 (rankings + roster + `generated_at`) | `scripts/compute-persona-value.py` | T-CORE-4, T-CORE-8, T-CORE-9 | M | — | 1 |
| **T-CORE-11** | Schema-version reader guard per D6: refuse non-v1 rows on read, treat as cache miss | `scripts/compute-persona-value.py` | T-CORE-10 | XS | Yes | 1 |
| **T-CORE-12** | Counts-only stderr telemetry (Δ4); `--quiet` flag (resolves gaps #6); raw `print()` / `sys.stderr.write()` ban enforced via `safe_log()` discipline | `scripts/compute-persona-value.py` | T-CORE-1 | S | Yes | 1 |
| **T-CORE-13** | `--explain PERSONA[:GATE]` per D3 (TTY-gated, plaintext finding titles, local-only) | `scripts/compute-persona-value.py` | T-CORE-7 | S | Yes (after T-CORE-7) | 1 |
| **T-CORE-14** | `--dry-run` per M5: full discovery telemetry, write nothing | `scripts/compute-persona-value.py` | T-CORE-10 | XS | Yes | 1 |
| **T-CORE-15** | Roster walk: enumerate `personas/{review,plan,check}/*.md` in cwd, emit names + current content-hash (D13 normalization) into the combined bundle's `PERSONA_ROSTER`; empty roster on missing `personas/` per gaps #10 | `scripts/compute-persona-value.py` | T-CORE-10 | S | Yes | 1 |
| **T-TEST-1** | `tests/test-phase-0-artifact.sh` — A0 (spec section + linkage field + ≥1 fixture validates) | `tests/test-phase-0-artifact.sh` | T-PRE-3, T-SCHEMA-1 | S | Yes | 2 |
| **T-TEST-2** | `tests/test-compute-persona-value.sh` — A1, A1.5, A2, A3 (cross-project), A4 (best-effort hash reset), A6, A7 (e1–e12), A8 (idempotency incl. concurrent re-run per R8), A11, A12 (re-cycled artifact dir per R3), A13 (multi-persona +1 per D10), A14 (silent state retention per D8) | `tests/test-compute-persona-value.sh` + `tests/fixtures/cross-project/{proj-a,proj-b}/...` | T-CORE-* (all) | L | — | 2 |
| **T-TEST-3** | `tests/test-allowlist.sh` — A10 normal: every JSONL row + every committed fixture validates against allowlist; canary scrub check on captured stderr | `tests/test-allowlist.sh` | T-SCHEMA-1, T-CORE-10, T-PRE-3 | S | Yes | 2 |
| **T-TEST-4** | `tests/test-allowlist-inverted.sh` — M8: invokes validator against `leakage-fail.jsonl`, asserts non-zero exit AND stderr contains `additionalProperties` + offending field name; orchestrator invokes via `! ./tests/test-allowlist-inverted.sh` | `tests/test-allowlist-inverted.sh` | T-TEST-3 | S | Yes | 2 |
| **T-TEST-5** | `tests/test-path-validation.sh` — Δ5: symlink escape, `..` segments, non-absolute config entries, per-project `.monsterflow-no-scan` opt-out, tilde-literal handling per project memory (R7) | `tests/test-path-validation.sh` | T-CORE-2 | M | Yes | 2 |
| **T-TEST-6** | `tests/test-finding-id-salt.sh` — Δ3 + M7: same input + different salts → different IDs; salt file perms = 600; corruption recovery clears rankings; `O_CREAT \| O_EXCL` race | `tests/test-finding-id-salt.sh` | T-CORE-3 | M | Yes | 2 |
| **T-TEST-7** | `tests/test-scan-confirmation.sh` — M6: non-tty refusal with self-diagnostic stderr message; pre-confirmed roots skip prompt; sentinel files exclude; `--confirm-scan-roots` non-interactive append idempotent | `tests/test-scan-confirmation.sh` | T-CORE-2 | M | Yes | 2 |
| **T-TEST-8** | `tests/test-no-raw-print.sh` — Δ4 grep gate: ban literal `print(` and `sys.stderr.write(` in `scripts/compute-persona-value.py` (allow only `safe_log()`) | `tests/test-no-raw-print.sh` | T-CORE-12 | XS | Yes | 2 |
| **T-TEST-9** | A12 dashboard recovery test: simulate salt corruption + regen; assert dashboard renders e12 fresh-install banner (NOT blank table or JS error) | `tests/test-dashboard-recovery.sh` | T-CORE-3, T-UI-2 | S | — | 2 |
| **T-TEST-10** | Non-functional: `compute-persona-value.py` wall-time ≤5s on this machine's `~/.claude/projects/` (R5); soft-fail with warning, not hard-fail | `tests/test-compute-perf.sh` | T-CORE-* (all) | S | Yes | 2 |
| **T-UI-1** | Update `dashboard/index.html` — add "Persona Insights" third top-level mode tab, wire `<script src="data/persona-insights-bundle.js">` | `dashboard/index.html` | T-CORE-10 | S | — | 3 |
| **T-UI-2** | New `dashboard/persona-insights.js` — render hybrid (rankings + roster) merge; sortable columns (persona, gate, runs_in_window, run_state, judge_retention_ratio, downstream_survival_rate, uniqueness_rate, total_tokens, avg_tokens_per_invocation, last_seen, persona_content_hash, contributing_finding_ids collapsible); insufficient-sample cells render "—"; nulls always sort to bottom; deleted-persona strikethrough; "(never run)" rows; warning banner; orchestrator-overhead toggle for `<unknown>` rows (D4); cost-vs-value tooltip for the dual-window (review docs-clarity DC-05); column-header `aria-sort` + `role="columnheader"` (resolves gaps #8) | `dashboard/persona-insights.js` (NEW) | T-UI-1 | M | — | 3 |
| **T-UI-3** | Empty-state + insufficient-sample-only banner: trigger fresh-install banner ("No data yet…") when zero rows; trigger second banner ("All current rows are insufficient sample — keep running gates") when rows exist but every row has `insufficient_sample: true` (resolves stakeholder conflict A11-vs-e12 in-between case) | `dashboard/persona-insights.js` | T-UI-2 | S | Yes (after T-UI-2) | 3 |
| **T-WRAP-1** | Update `commands/wrap.md` Phase 1c: invoke `compute-persona-value.py` unconditionally; append "Persona insights" sub-section per spec format; surface `--scan-projects-root` hint when output telemetry shows `cwd:1, config:0, scan:0` (resolves stakeholder onboarding gap); cost ranking uses `avg_tokens_per_invocation` not totals; document `--confirm-scan-roots` for non-tty adopters | `commands/wrap.md` | T-CORE-10 | M | — | 3 |
| **T-DOC-1** | Spec docs delta: codify D5 (full-rebuild contract), D6 (schema migration), D7/D8 (silent-state semantics), D9 (cost_window_size field), D10 (multi-persona +1 each), D11 (bullet regex), D13 (hash normalization) inline in spec.md as a "Build-time clarifications" section appended below §Acceptance Criteria — does NOT re-litigate; only pins ambiguities review surfaced | `docs/specs/token-economics/spec.md` | — | M | Yes | 3 |
| **T-DOC-2** | New `docs/specs/token-economics/notes.md` per D16: support runbook (interpreting low scores, salt rotation, multi-machine semantics), persona-author posture statement, `--scan-projects-root` onboarding paragraph, Linux-untested disclaimer, v1.1-unblock criterion ("≥10 personas per gate have `runs_in_window ≥ 3` within 30 days"), `persona-metrics-validator` invocation procedure | `docs/specs/token-economics/notes.md` (NEW) | — | M | Yes | 3 |
| **T-DOC-3** | `.gitignore` updates: add `dashboard/data/persona-rankings.jsonl`, `dashboard/data/persona-insights-bundle.js`; verify `tests/fixtures/persona-attribution/` is NOT ignored (committed) | `.gitignore` | T-CORE-10 | XS | Yes | 3 |
| **T-DOC-4** | `~/.config/monsterflow/README.md` content: spec it now (resolves gaps #7) — write the literal one-liner here so install.sh can copy it later. Lives at `docs/specs/token-economics/config-readme.md` for now; install.sh wiring tracked in BACKLOG | `docs/specs/token-economics/config-readme.md` (NEW) | — | XS | Yes | 3 |
| **T-WIRE-1** | Single-owner sequential post-step: wire all 10 new tests into `tests/run-tests.sh`; ensure `test-allowlist-inverted.sh` is invoked via inverted-exit shell shape (`! ./tests/test-allowlist-inverted.sh`); verify `bash tests/run-tests.sh` lists all 10 in output | `tests/run-tests.sh` | T-TEST-1..10 | S | — | 4 |
| **T-VERIFY-1** | Manual smoke: run `compute-persona-value.py` once on this repo's cwd; verify `persona-rankings.jsonl` produced; load `dashboard/index.html` under `file://`; verify Persona Insights tab renders; run `/wrap-insights` and verify text section appears | n/a (verification) | T-WIRE-1, T-UI-3, T-WRAP-1 | S | — | 4 |
| **T-VERIFY-2** | Invoke `persona-metrics-validator` subagent on the freshly emitted `persona-rankings.jsonl` (per spec §Integration "Subagents to invoke"); record verdict in PR | n/a (verification) | T-VERIFY-1 | XS | Yes | 4 |

---

## Wave Structure

**Wave 0 — Pre-flight (sequential):** T-PRE-1 → T-PRE-2 → T-PRE-3, with T-SCHEMA-1 in parallel after T-PRE-1.
- Gate: T-PRE-1 must pass before any Wave 1 task starts. If `session-cost.py` is not import-clean, the M1 strategy collapses and the spec must revise (escalate to user).

**Wave 1 — Core data layer (parallel where marked):** T-CORE-1 sequential first; then T-CORE-2 + T-CORE-3 + T-CORE-4 parallel; then T-CORE-5 + T-CORE-7 parallel (independent walkers); then T-CORE-6, T-CORE-8 dependent on walkers; then T-CORE-9, T-CORE-10, T-CORE-11–15 in dependency order shown.
- Gate: T-CORE-10 produces a real `persona-rankings.jsonl` against this repo's cwd. Spot-check it is well-formed before Wave 2.
- Use the `superpowers:dispatching-parallel-agents` discipline: each parallel agent owns its own files; no shared-file appends; no global git ops (per project memory `feedback_parallel_agents_shared_file_race.md`).

**Wave 2 — Tests (highly parallel):** All T-TEST-* run in parallel; each owns its own `tests/test-*.sh` file. T-TEST-9 waits for T-UI-2.
- Thorough tests, not strict TDD (per project memory `feedback_testing.md`).

**Wave 3 — UI + docs (parallel):** T-UI-1 → T-UI-2 → T-UI-3 sequential; T-WRAP-1, T-DOC-1, T-DOC-2, T-DOC-3, T-DOC-4 parallel with the UI chain.

**Wave 4 — Wiring + verification (sequential):** T-WIRE-1 then T-VERIFY-1 then T-VERIFY-2.

---

## Dependency Graph (key edges)

```
T-PRE-1 ──┬─→ T-PRE-2 ─→ T-PRE-3 ──┐
          │                          ├─→ T-CORE-1 ──┬─→ T-CORE-2 ──┐
          └─→ T-SCHEMA-1 ────────────┘              ├─→ T-CORE-3 ──┤
                                                    ├─→ T-CORE-4 ──┤
                                                    │              ▼
                                                    └─→ (consumed by T-CORE-5..15)

T-CORE-5,7 ─→ T-CORE-6,8 ─→ T-CORE-9 ─→ T-CORE-10 ─→ T-CORE-11..15
                                                ▼
                                T-TEST-2..10  ─→  T-WIRE-1  ─→  T-VERIFY-1 → T-VERIFY-2
                                T-UI-1 → T-UI-2 → T-UI-3 ────────┘
                                T-WRAP-1 ────────────────────────┘
```

---

## Open Questions

1. **Spec Open Q1 — canonical token source.** Carried forward from spec; resolved at T-TEST-2 / A1.5. On A1.5 disagreement, build halts and `/plan` re-opens. (No action this plan.)

2. **`scripts/session-cost.py` current state — is it import-clean today?** Unknown without inspection. T-PRE-1 answers in 5 minutes. If unclean, T-PRE-1's scope expands to include a `session-cost.py` refactor (CLI under `if __name__`); add ~30 min.

3. **Linux support stance for the new scripts.** Spec says macOS-only; review (stakeholders) flagged that nothing in the design is intrinsically macOS-only. **Recommendation: keep macOS-only stance for v1 (the testing surface lives on Justin's machine), but add a one-line "should work on Linux but untested" note to T-DOC-2.**

4. **Audit-trail for `--confirm-scan-roots` (gaps #12).** Recommendation: append `# added <ISO> by --confirm-scan-roots` comment header per line. Trivial; if user agrees, fold into T-CORE-2. Otherwise defer.

5. **Persona-author public-ranking posture (stakeholders Critical Gap 1).** Plan addresses via T-DOC-2 (notes.md persona-author guidance). User may want stronger UI gating (e.g., hide bottom-3 entirely when `runs_in_window < 10`). **Recommendation: ship T-DOC-2 statement now; revisit UI gating after first 30 days of data.**

6. **A1.6 unattributed-dispatch threshold (feasibility).** Recommendation: pin at 5% under default mode, 100% under `--best-effort`. Folded into T-CORE-6.

7. **A1 wording — equality partition (feasibility).** Recommendation: reword A1 in T-DOC-1 as `sum(per_persona_tokens) + sum(unknown_tokens) + sum(orchestrator_tokens) == sum(usage rows from subagents/)`. Strict-equality moves to the partition, not the persona bucket.

---

## Risks (rolled up from spec risk analysis + plan synthesis)

| # | Risk | Severity | Mitigation in plan |
|---|------|----------|--------------------|
| R1 | `session-cost.py` import side effects break compute script | High | T-PRE-1 (Phase 0.5 gate) |
| R2 | Two-bundle dashboard refresh race | High | D1 single-bundle architecture; T-CORE-10 emits combined bundle |
| R3 | Re-cycle artifact directory semantics undefined | Medium | T-TEST-2 fixture A12 pins behavior; T-DOC-1 documents |
| R4 | Test orchestrator wiring gap (recurring pattern) | Medium | D15 single-owner sequential T-WIRE-1; explicit verification step |
| R5 | `/wrap-insights` latency regression on accumulated history | Medium | T-TEST-10 wall-time check; cache short-circuit deferred to v1.1 if not needed at ship |
| R6 | CC subagent format drift fixture freeze | Medium | T-CORE-6 runtime probe + stderr drift warning |
| R7 | `scan-roots.confirmed` parsing fragility (tilde, BOM, comments) | Medium | T-CORE-2 mirrors salt-file robustness pattern; T-TEST-5 covers |
| R8 | Concurrent `/wrap-insights` produces non-deterministic `contributing_finding_ids` | Low | T-CORE-9 sorts after truncation; T-TEST-2 A8 covers concurrent case |
| R9 | `<unknown>` bucket biases rankings | Medium (added by plan synthesis) | D4 contract; UI hides by default |
| R10 | v1 → v1.1 schema migration ambiguity | Medium (added by plan synthesis) | D6 + T-CORE-11 reader guard |
| R11 | First-time `/wrap-insights` adopter sees only cwd, no path to cross-project | Medium (added by stakeholder review) | T-WRAP-1 surfaces `--scan-projects-root` hint when telemetry shows cwd-only |
| R12 | Stakeholder: low-score persona looks broken to author | Medium | T-DOC-2 author-facing posture statement |
| R13 | Plan adds Wave-3 doc tasks late; build agent skips them | Low | T-VERIFY-1 manual smoke includes loading dashboard + reading docs |

---

## Verification & Acceptance Mapping

| Spec AC | Plan task(s) | Verification path |
|---------|--------------|-------------------|
| A0 | T-PRE-3, T-SCHEMA-1, T-TEST-1 | `bash tests/test-phase-0-artifact.sh` |
| A1, A1.5 | T-CORE-5, T-TEST-2 | `bash tests/test-compute-persona-value.sh` (A1.5 fails build on disagreement) |
| A2 | T-CORE-7, T-CORE-8, T-TEST-2 | rate columns ∈ [0,1] ∪ {null}; `run_state_counts` totals match |
| A3 | T-CORE-2, T-TEST-2 + `tests/fixtures/cross-project/` | output JSONL contains data from both fixture roots |
| A4 | T-CORE-9, T-TEST-2 | hash bumps; pre-edit IDs cleared from drill-down |
| A5 | T-UI-1, T-UI-2, T-UI-3 | manual `file://` load |
| A6 | T-WRAP-1 | `/wrap-insights` text contains "Persona insights..." block |
| A7 | T-TEST-2 | e1–e12 + cascade + drill-down + soft-cap |
| A8 | T-CORE-10, T-TEST-2 | byte-equal diff (mod `last_artifact_created_at`) |
| A9 | T-DOC-3, T-TEST-3 | `git check-ignore` + allowlist |
| A10 | T-TEST-3, T-TEST-4 | normal + inverted shapes |
| A11 | T-CORE-7, T-TEST-2 | precondition: ≥1 source row exists |
| A12 (added) | D6, T-CORE-11, T-TEST-9 | schema-version guard + dashboard recovery banner |
| A13 (added) | D10, T-TEST-2 | multi-persona +1 each |
| A14 (added) | D8, T-TEST-2 | silent state contributes (0,0) → null |

---

## Persistent Artifacts (this plan writes / triggers)

- `docs/specs/token-economics/plan.md` (this file)
- `docs/specs/token-economics/notes.md` (T-DOC-2, in build)
- `docs/specs/token-economics/config-readme.md` (T-DOC-4, in build)
- New scripts: `scripts/compute-persona-value.py`, `scripts/redact-persona-attribution-fixture.py`
- New schema: `schemas/persona-rankings.allowlist.json`
- New tests (10): see Wave 2 + T-VERIFY-1 invocation
- Modified: `commands/wrap.md`, `dashboard/index.html`, `tests/run-tests.sh`, `.gitignore`, `docs/specs/token-economics/spec.md` (T-DOC-1 build-time clarifications appendix)
- New dashboard module: `dashboard/persona-insights.js`
- Generated (gitignored): `dashboard/data/persona-rankings.jsonl`, `dashboard/data/persona-insights-bundle.js`
- Committed fixture: `tests/fixtures/persona-attribution/*.jsonl`, `tests/fixtures/cross-project/{proj-a,proj-b}/...`

---

## Approve to proceed to /check?

Autonomous mode — written without approval gate; `/check` will validate this plan before `/build` consumes it.
