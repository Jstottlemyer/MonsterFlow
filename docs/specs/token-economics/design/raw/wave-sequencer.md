# Wave Sequencer — token-economics

## Key Considerations

This spec is **not a typical UI feature**. The "user" of wave 1's contract is `compute-persona-value.py` itself plus the dashboard renderer. Three structural truths drive the wave shape:

1. **Phase 0 spike completion (A1.5) is a forcing-function gate, not a wave.** The spike answers Q1 (parent-annotation vs subagent-transcript canonical token source). The *answer* changes one branch inside `compute-persona-value.py` (cheap path vs canonical path) — it does NOT change the output schema, the dashboard, or any other contract. Therefore the spike can complete **in parallel** with Wave 1 contract design; only the engine implementation in Wave 2 has a hard dependency on its outcome.
2. **The data contract is the JSONL output schema + the allowlist schema** — both static JSON files. They lock first because the engine (`compute-persona-value.py`), the renderer (`persona-insights.js`), the allowlist test (`test-allowlist.sh`), and the fixtures all read them. If they slip, every downstream worker churns.
3. **The dashboard tab and the `/wrap-insights` text section are independent renderers reading the same JSONL.** They can ship in parallel inside the same wave and even by different subagents — neither blocks the other once the engine emits real rows.

The three-gate default (data → UI → tests) **mostly applies**, but with two adjustments:
- A "Wave 0" exists for spike completion + schema lock — these have no consumers yet but unblock everything.
- A11 (≥1 row per distinct (persona, gate) pair) is an **end-to-end outcome** — only testable after Wave 2 finishes. So the test wave is genuinely a third wave, not parallelizable with UI.

## Options Explored

### Option A — Strict three-gate (data / UI / tests)
- **Wave 1:** schemas + engine + redact helper. **Wave 2:** dashboard tab + wrap text. **Wave 3:** all tests.
- Pros: textbook, easy to verify per wave.
- Cons: collapses spike completion into Wave 1 even though it's a research task with different cadence; defers A0/A1.5 fixture validation until Wave 3 even though those gate the engine's correctness in Wave 1. Effort: M.

### Option B — Four waves (spike+contracts / engine / surfaces / hardening)
- **Wave 0:** Phase 0 spike close (A1.5) + schemas + fixtures. **Wave 1:** engine (`compute-persona-value.py` + `session-cost.py` extension + redact helper). **Wave 2:** dashboard tab + wrap Phase 1c integration. **Wave 3:** A2–A11 acceptance.
- Pros: schema lock and spike close in parallel before any engine code; engine wave has a clear single-author surface; UI parallelizable across two subagents; test wave is the end-to-end gate.
- Cons: four waves slightly heavier on coordination. Effort: M.

### Option C — Engine-and-tests-together (build A0/A1.5 tests with engine; defer dashboard last)
- **Wave 1:** schemas + spike. **Wave 2:** engine + A0/A1.5/A8/A9/A10 (allowlist + idempotency tests that gate engine correctness). **Wave 3:** dashboard tab + wrap text + A2/A5/A6/A7/A11 (rendering + outcome tests).
- Pros: privacy + idempotency tests live with the code that must satisfy them — fastest way to catch leakage early; dashboard ships against a known-good JSONL.
- Cons: splits the test surface across waves; harder to summarize "wave 3 = tests."
- Effort: M-L.

## Recommendation

**Option C, with a named Wave 0 for spike + schema lock.** The privacy gate (A10 allowlist) and the cost-attribution gate (A1.5) are **pre-conditions for trusting any output** — they belong in the same wave as the engine, not deferred. Dashboard + wrap text + outcome tests then ship against an engine that already proves it doesn't leak and that its token sums agree with the canonical source.

Net wave plan:

### Wave 0 — Spike close + data contracts (parallel-safe)
**Closes:** Phase 0 Q1 resolution (A1.5 outcome known); JSONL output schema; allowlist schema; redacted spike fixtures.

| Task | Complexity |
|---|---|
| Run A1.5 probe on the existing RedRabbit fixture session: parse parent annotation `total_tokens` vs sum of subagent `usage` rows for ≥10 dispatches; record agreement/disagreement | S |
| Write `schemas/persona-rankings.schema.json` (row shape per spec §Data) | S |
| Write `schemas/persona-rankings.allowlist.json` (enumerate exactly the field names permitted in JSONL rows + fixture rows) | S |
| Write `scripts/redact-persona-attribution-fixture.py` (single-purpose: read raw JSONL, drop every field not in allowlist, write clean copy) | S |
| Produce `tests/fixtures/persona-attribution/` redacted excerpts (≥1 valid `.jsonl` + 1 deliberate `leakage-fail.jsonl`) | S |
| Produce `tests/fixtures/cross-project/` two synthetic project trees with `findings.jsonl` + `survival.jsonl` + `run.json` + `raw/<persona>.md` per gate | M |

**Depends on:** none — first wave.
**Verifier signal:** (a) A1.5 outcome documented in `plan/raw/spike-q1-result.md` deciding which canonical-token branch the engine takes; (b) both schema files validate as JSON Schema; (c) redact script round-trips one fixture cleanly; (d) deliberate-failure fixture has a forbidden field.
**Minimum-shippable test:** Wave 0 alone delivers: a known answer to Q1, two locked schemas, and a privacy-redaction toolchain. Even if Waves 1–2 slip, the schema + fixture artifacts are reusable.
**Parallelism:** 2–3 subagents:
- Sub-A: A1.5 probe + spike result note.
- Sub-B: both schemas + redact helper.
- Sub-C: cross-project synthetic fixtures.
**DoD:** A0 + A1.5 tests pass against fixtures (those tests can be stubbed to assert the artifacts exist + parse; full enforcement happens in Wave 1).

### Wave 1 — Engine + privacy gates (sequential after Wave 0)
**Closes:** `compute-persona-value.py` produces `persona-rankings.jsonl` rows that pass the allowlist test, are idempotent, and agree with subagent-transcript token sums.

| Task | Complexity |
|---|---|
| Extend `scripts/session-cost.py` — add `--per-persona` mode emitting (persona, gate, parent_session_uuid, tokens) groupings; uses Wave 0's A1.5 branch decision | M |
| `scripts/compute-persona-value.py` — Project Discovery cascade (cwd / config / `--scan-projects-root`), worktree dedup via realpath, telemetry stderr line | M |
| `compute-persona-value.py` — value walk: judge_retained, downstream_survived, unique, emitted_bullet_count, run_state classification per artifact dir | L |
| `compute-persona-value.py` — 45-window cap per (persona, gate); soft-cap `contributing_finding_ids[]` at 50 + `truncated_count`; `insufficient_sample` flag | M |
| `compute-persona-value.py` — roster sidecar emit (`persona-roster.js` as `window.PERSONA_ROSTER = [...]`) | S |
| `compute-persona-value.py` — `safe_log()` wrapper: stderr/stdout emit only allowlisted field names + counts | S |
| `compute-persona-value.py` — atomic write via tmp + `os.replace`; `sort_keys=True`; `round(x, 6)` for floats; rows sorted by (gate, persona) | S |
| `tests/test-phase-0-artifact.sh` — full A0 enforcement (heading, agentId field name, fixture exists + allowlist-validates) | S |
| `tests/test-allowlist.sh` — A10 enforcement (4 sub-asserts: JSONL clean, fixtures clean, stderr canary scrub, deliberate-failure fixture catches violation) | M |

**Depends on:** Wave 0 (schemas + fixtures + Q1 outcome).
**Verifier signal:** running `compute-persona-value.py` against `tests/fixtures/cross-project/` produces `dashboard/data/persona-rankings.jsonl` that (a) passes `tests/test-allowlist.sh`, (b) passes `tests/test-phase-0-artifact.sh`, (c) is byte-for-byte stable across two consecutive runs except for `last_seen` (A8 idempotency), (d) `total_tokens` per (persona, gate, dir) sums match subagent transcript sums (A1).
**Minimum-shippable test:** Wave 1 standalone delivers the JSONL artifact — usable from CLI even without dashboard. The pipeline can begin recording cost/value data while Wave 2 is being built.
**Parallelism:** 2 subagents:
- Sub-A: `session-cost.py` extension + `compute-persona-value.py` cost path + Project Discovery.
- Sub-B: `compute-persona-value.py` value path + run_state machine + roster sidecar + atomicity.
- Final integration + tests done sequentially by one author after both subagents land.
**DoD:** A0, A1, A1.5, A8, A9, A10 acceptance criteria all pass against the cross-project fixture.

### Wave 2 — Surfaces (dashboard tab + wrap text — parallel internally)
**Closes:** dashboard "Persona Insights" tab renders the JSONL; `/wrap-insights` Phase 1c invokes `compute-persona-value.py` and renders the text sub-section.

| Task | Complexity |
|---|---|
| `dashboard/index.html` — add "Persona Insights" tab nav + container; `<script src>` to `dashboard/data/persona-roster.js`; warning banner | S |
| `dashboard/persona-insights.js` — load JSONL (existing pattern from other tabs), merge with `window.PERSONA_ROSTER`, render sortable table (cols per spec), null-cells "—", null-sort-bottom, deleted-persona strikethrough, "(never run)" rows | M |
| `dashboard/persona-insights.js` — collapsible `contributing_finding_ids` drill-down; stale-cache banner if `last_seen` >14d | S |
| `commands/wrap.md` — Phase 1c: invoke `compute-persona-value.py` **unconditionally** (NOT piggybacked on `dashboard-append.sh`); emit "Persona insights" sub-section text per spec format; "(only N qualifying)" when <3 personas qualify; cost ranking via `avg_tokens_per_invocation` | M |

**Depends on:** Wave 1 (the JSONL must exist with stable schema; roster.js sidecar must emit).
**Verifier signal:** (a) Open `dashboard/index.html` under `file://` in a browser — Persona Insights tab loads, table populates from cross-project fixture data, sort works, "(never run)" rows render; (b) run `/wrap-insights` in this repo — Phase 1c output contains "Persona insights" header + per-gate top/bottom 3.
**Minimum-shippable test:** A5 + A6 manual verification + smoke browser load. (Full A5/A6 automated assertions live in Wave 3.)
**Parallelism:** 2 subagents in parallel:
- Sub-A: `dashboard/index.html` HTML edits + `dashboard/persona-insights.js`.
- Sub-B: `commands/wrap.md` Phase 1c integration.
**DoD:** Both surfaces render against a Wave-1-produced JSONL without errors; warning banner present on dashboard.

### Wave 3 — End-to-end acceptance + edge-case hardening
**Closes:** every acceptance criterion (A0–A11) passes; e1–e12 edge cases verified; pipeline is publishable.

| Task | Complexity |
|---|---|
| `tests/test-compute-persona-value.sh` — A2 (three rates + run_state_counts), A3 (cross-project cascade — cwd / config / `--scan-projects-root`), A4 (content-hash window reset best-effort + `contributing_finding_ids[]` cleared), A7 (e1–e12 + drill-down soft-cap), A11 (≥1 row per distinct (persona, gate) pair) | L |
| Dashboard automated check — A5 assertions (column presence, "—" rendering, null sort position, strikethrough class, banner text, file:// load) via small headless harness OR scripted DOM grep | M |
| `/wrap-insights` automated check — A6 (text section format match, top/bottom 3 logic, "(only N qualifying)" branch, avg-not-total cost ranking) | S |
| Invoke `persona-metrics-validator` subagent on the produced `persona-rankings.jsonl` — confirms schema joins are sane | S |
| Documentation pass — confirm spec §Project Discovery is referenced from any stderr telemetry; verify `.gitignore` covers `dashboard/data/persona-rankings.jsonl` and `dashboard/data/persona-roster.js` | S |

**Depends on:** Waves 1 + 2.
**Verifier signal:** all 12 acceptance criteria green; `bash tests/run-tests.sh` clean; `persona-metrics-validator` returns no schema mismatches.
**Minimum-shippable test:** Wave 3 is the one that lets us flip the spec from "shipped behind tests" to "shipped publicly with confidence." Without it, A11's outcome guarantee is unverified.
**Parallelism:** 2–3 subagents (each acceptance criterion is independent):
- Sub-A: A2 + A3 + A4 + A7 (the big test file).
- Sub-B: A5 dashboard assertions.
- Sub-C: A6 wrap text assertions + persona-metrics-validator invocation.

## Constraints Identified

- **A1.5 outcome can flip the engine's canonical-token branch.** Wave 0 must complete the probe before Wave 1's `session-cost.py` extension lands, OR Wave 1 must implement both branches behind a config flag and let Wave 0 set it. The first option is simpler — Wave 0 is genuinely a gate.
- **`dashboard/data/*.jsonl` is gitignored** — Wave 1 cannot rely on a checked-in JSONL for Wave 2/3 to consume. Wave 2 dashboard testing must regenerate the JSONL from the cross-project fixture as a test fixture itself.
- **`compute-persona-value.py` must run under existing `dashboard-append.sh` cadence AND on every `/wrap-insights`** (unconditional, NOT piggybacked). Wave 1 must make the script idempotent (A8) so the double-invocation is safe.
- **Public-release scrutiny gate:** Wave 1 cannot ship without Wave 1's privacy tests (A10) green. This is non-negotiable per spec §Privacy and the historical incident note in Justin's CLAUDE.md.
- **`/wrap` Phase 1c is also touched by persona-metrics spec** (`docs/specs/persona-metrics/spec.md`) — Wave 2's `commands/wrap.md` edit must read the existing Phase 1c structure and append, not overwrite.

## Open Questions

- **None blocking.** Q1's resolution is now Wave 0 work, not a planning blocker.
- One question for `/check`: does the cross-project fixture in Wave 0 need ≥3 distinct artifact directories per (persona, gate) to make `insufficient_sample = false` rows possible for A2/A6? If yes, fixture size grows; if no, fixture can be minimal and A6's "(only N qualifying)" branch becomes the default exercise. **Plan-time recommendation:** make the fixture rich enough to produce ≥3 qualifying rows for ≥1 (persona, gate) pair, so both branches of A6 are exercisable.

## Integration Points

- **Wave 0 → Wave 1:** schemas + fixtures + spike result note. Hand-off doc: `plan/raw/spike-q1-result.md` (Wave 0 produces; Wave 1 reads to choose engine branch).
- **Wave 1 → Wave 2:** the JSONL row schema and `persona-roster.js` shape. Hand-off contract: `schemas/persona-rankings.schema.json` (locked in Wave 0) + a sample `persona-rankings.jsonl` produced from cross-project fixture (Wave 1 commits sample to `tests/fixtures/cross-project/expected-rankings.jsonl`).
- **Wave 1 → Wave 3:** the engine itself + idempotency guarantees (A8) + privacy guarantees (A10). Test wave reads engine output as a black box.
- **Wave 2 → Wave 3:** dashboard DOM IDs/classes used by the renderer must be stable so A5's automated check can grep them. Hand-off contract: a one-page README in `dashboard/` listing the test-relevant selectors (or include the assertions inline in `persona-insights.js` as data-attributes).
- **Cross-spec hand-off:** `commands/wrap.md` Phase 1c edit must coordinate with persona-metrics spec's existing Phase 1c content. Wave 2 sub-B's first step: read the current `commands/wrap.md` Phase 1c block and confirm append-strategy. If conflict, escalate before editing.
- **Subagent integration:** `persona-metrics-validator` is invoked in Wave 3, not Wave 1 — no point validating an empty/sample JSONL. `autorun-shell-reviewer` is NOT triggered (no `scripts/autorun/*.sh` changes in this spec).
