# Plan: Token Economics

**Date:** 2026-05-04
**Spec:** `docs/specs/token-economics/spec.md` revision 4.2 (v4.1 + 8 must-fixes from `/check`)
**Review:** `docs/specs/token-economics/review.md` (round 3)
**Check:** `docs/specs/token-economics/check.md` (5 primary PASS WITH NOTES; Codex NO-GO with 5 implementation blockers — all 8 applied as M1–M8)
**Survival:** `docs/specs/token-economics/spec-review/survival.jsonl` — 29/32 round-3 findings addressed by v3→v4 revision (90.6%); 2 not_addressed (TTL, Pro-friend A12 enforcement); 1 rejected_intentionally (persona-author docs). `docs/specs/token-economics/plan/survival.jsonl` — 31/33 plan-stage design recommendations addressed by plan.md (94%).
**Designers:** 7 in parallel — api / data-model / ux / scalability / security / integration / wave-sequencer
**Plan revision:** 1.2 (v1.0 = original; v1.1 = Q1–Q3 + minute-truncation; v1.2 = check M1–M8 applied)

## Architecture Summary

`compute-persona-value.py` is a single Python script that walks two trees, computes `persona-rankings.jsonl`, and emits `persona-roster.js` + `persona-rankings-bundle.js` sidecars so the dashboard can render under `file://` without `fetch()`. All output flows through one allowlist schema (`schemas/persona-rankings.allowlist.json`) with `additionalProperties: false` as the privacy gate. All stderr/stdout flows through one `safe_log()` helper restricted to a fixed `SAFE_EVENTS` enum. `commands/wrap.md` Phase 1c invokes the script unconditionally (not piggybacked on `dashboard-append.sh`); the dashboard adds a third top-level "Persona Insights" mode tab. Phase 0 spike Q1 is forced by A1.5 in tests; everything else is best-effort by design.

**Mental model:** the spec is one engine + one schema + one logger + one bundle pattern, with the dashboard as a passive renderer.

## Key Design Decisions

### Decisions where designers converged (no debate)

1. **Single allowlist file as both row schema and privacy gate** (data-model + security + integration). One file `schemas/persona-rankings.allowlist.json` with `additionalProperties: false`. A10 enforced by **stdlib allowlist validator (M2 from /check, ~30 lines)** that checks `additionalProperties: false`, `required[]`, enum/pattern for the actual fields used. **NOT `jsonschema.validate`** — `jsonschema` is undeclared on this repo (verified missing). No separate "schema" vs "allowlist" split.
2. **Sidecar bundle pattern under `file://`** (ux + integration + data-model). `persona-roster.js` and `persona-rankings-bundle.js` both loaded via `<script src>` setting `window.PERSONA_ROSTER` and `window.__PERSONA_RANKINGS`. No `fetch()`. **`compute-persona-value.py` emits both.** Spec only mentioned the roster sidecar; we extend the same pattern to the rankings JSONL.
3. **`safe_log()` enforces output-side privacy** (api + security). All stderr/stdout flows through one helper restricted to a fixed `SAFE_EVENTS` enum + value-pattern allowlist. Raw `print()` and `sys.stderr.write()` banned by grep test.
4. **mtime-pruned single-pass with substring pre-filter** (scalability solo). Stdlib only. Substring screen for `"Agent"` + `"tool_use"` before `json.loads`. mtime-prune horizon = `MIN(window.created_at) - 24h` slack. Light adopter <2s; heavy adopter 3-5s; cold first-run 30-60s with stderr warning.
5. **Wave 0 / 1 / 2 / 3** (wave-sequencer). Spike close + schemas (Wave 0) → engine + privacy gates (Wave 1) → dashboard + wrap text (Wave 2, parallel) → end-to-end acceptance (Wave 3). Privacy ships **with** the engine, not deferred.
6. **Use `null`, never omit** for missing rates (data-model). Schema types rates as `["number", "null"]` with `[0,1]` constraint when number. Idempotent diffs stay clean; dashboard branches on `=== null` only.
7. **Reserve forward-compat via `schema_version: 1`** (data-model). v1.1 (per-dispatch hash + `agent_tool_use_id`) bumps to 2; v1 readers skip rows with `schema_version > KNOWN_MAX`. **Do NOT pre-reserve future field names** (invites confusion).
8. **`run_state` enum + `run_state_counts` aggregate** (data-model + spec + M4 from /check). **7-key** required object on every row (M4 added `silent` state for `participation.status: ok` AND `findings_emitted: 0`). Value-window states sum to `runs_in_window`; cost-window states (incl. `cost_only`) sum to `cost_runs_in_window` (M3: separate denominators). Dashboard renders dominant state as `.badge` with hover-tooltip showing full breakdown; silent personas render with distinct silent badge (NOT "never run").

### Decisions resolving designer disagreements / spec deltas

9. **DROP `window_start_artifact_dir`** (security override on spec). The field leaks adopter's project + feature + gate names. Drop entirely (its only use was idempotency debug; `(persona, gate)` already identifies the row). Removes a column from the dashboard. **Spec delta required.**
10. **TRUNCATE `last_seen` to date-minute granularity** (security override on spec; revised from hour per Justin 2026-05-04). Full ISO with seconds is over-precise; minute is the chosen tradeoff — gives dashboard "refreshed today" UX without weakening A8 idempotency in practice (minute-precision races are rare). Round to `YYYY-MM-DDTHH:MM:00Z` in both rankings JSONL and committed fixtures. **Spec delta required.**
11. **Per-machine salt for `contributing_finding_ids[]`** (security override on spec). Generate `~/.config/monsterflow/finding-id-salt` (256-bit random, chmod 600) on first run. ID = `<gate-prefix>-sha256(salt || normalized_signature)[:10]`. Cross-machine ID stability lost — explicitly NOT a v1 feature (drill-down is machine-local). **Spec delta required.**
12. **Telemetry line is counts-only, paths are interactive-only** (security override on spec). Spec's `(sources: cwd, config, scan): <path>, <path>, ...` becomes `discovered N projects (sources: cwd:1, config:M, scan:K)` with no paths. Paths only emitted in interactive `--scan-projects-root` first-use confirmation prompt and behind `MONSTERFLOW_DEBUG_PATHS=1` env (logs to local-only `~/.cache/monsterflow/debug.log`, never gitignored). **Spec delta required.**
13. **`--scan-projects-root` requires interactive confirmation on first use** (security new). Adopter's first `--scan-projects-root <dir>` prompts: "Confirm scan of these N roots? Append to `scan-roots.confirmed`? [y/N]". Subsequent runs skip. Non-tty: refuse to scan, log `[persona-value] scan-roots not confirmed; skipping K roots`. Per-project opt-out via `.monsterflow-no-scan` sentinel file. **Spec delta required.**
14. **DO NOT modify `scripts/session-cost.py`** (integration override on spec). New `compute-persona-value.py` imports `PRICING` and `entry_cost` from `session_cost` via **`importlib.util.spec_from_file_location("session_cost", "scripts/session-cost.py")` (M1 fix from `/check`)** — bare `sys.path` insert was a planning hallucination because hyphens are illegal in Python module names. Rationale: lower blast radius; cleaner test boundary; round-3 narrowing to artifact-directory aggregation removed the per-row attribution need.
15. **Path-traversal + symlink-escape hardening** (security new). Shared `validate_project_root(path) -> Path | None` rejects: non-absolute, `..` after normalize, resolved path not under `$HOME` (configurable via `MONSTERFLOW_ALLOWED_ROOTS`), symlinks that escape `$HOME`. Applied to config tier 2 reader AND `--scan-projects-root` arg.
16. **6-flag CLI surface** (api + M5 + M6 from /check). `compute-persona-value.py` exposes: `--scan-projects-root <dir>` (**repeatable; argparse `action="append"`**, locked per Q2), **`--confirm-scan-roots <dir>` (M6, repeatable)** — non-interactive companion for tmux/log-piped sessions; appends to `scan-roots.confirmed` without prompting, `--best-effort` (downgrade A1.5 disagreement to warning), `--out PATH`, `--dry-run` (compute discovery + write nothing; subsumes the cut `--list-projects` per M5), `--explain PERSONA[:GATE]`. **`--list-projects` REMOVED (M5)** — counts-only telemetry contradiction. Help text carries the cascade verbatim. **Verify each flag with `<tool> --help` smoke test before declaring shipped** (per global CLAUDE.md).
17. **API rename `last_seen` → `last_artifact_created_at`** (api). Pre-empts a future "fix to file-mtime" regression that the spec explicitly forbids. Self-documenting field name.
18. **Dashboard "Persona Insights" as a third top-level mode** (integration + ux). Matches existing `data-mode` pattern at `dashboard/index.html:70-71`. NOT a sub-tab under Judge (rankings are cross-project; Judge is per-project).
19. **Validator (`persona-metrics-validator`) fires on first JSONL creation only** (integration). Pre/post `[ -f ]` check in `commands/wrap.md` Phase 1c — 3 lines of bash. Reruns on demand only.
20. **Dashboard "Coverage" column derived from `run_state_counts`** (api + ux). Display `14/18 complete` with full breakdown in tooltip. Avoids surfacing `run_state` as a sortable peer column (meaningless rank).
21. **`/wrap-insights` text shows top + bottom 3 per dimension per gate** (ux), with "(only N qualifying)" annotation when fewer than 3 personas have `runs_in_window ≥ 3`. Always-on retention-vs-survival semantics note at end ("retention is a compression ratio, not a survival rate").

### M-series decisions (locked in v1.2 from /check)

22. **Cost vs value: two honestly separated signals** (M3, Codex). Value windows over 45 (persona, gate) **artifact directories**; cost windows over 45 observed **Agent dispatches** per (persona, gate). Different denominators. New `cost_runs_in_window` field. Dashboard tooltip on `runs_in_window` and cost columns explicitly states the two windows. Per-dispatch capture (the join key) is v1.1+ scope.

23. **Silent personas (M4, Codex)** — `participation.jsonl` rows with `status: ok` AND `findings_emitted: 0`. Add `silent` to run_state enum (now 7 states); add `silent_runs_count` to row schema; dashboard renders distinct silent badge (NOT "never run"). Without this, low-noise personas are invisible or mislabeled.

24. **Salt file robustness (M7, risk).** Validate on read: `len == 32 bytes` AND non-zero AND `os.stat().st_mode & 0o777 == 0o600`. On any failure: regenerate salt atomically (`O_CREAT | O_EXCL` for first-run race; `tmp + os.replace` for regeneration); ALSO clear `dashboard/data/persona-rankings.jsonl` (drill-down continuity reset is the only honest behavior). Emit `safe_log("regenerated_salt_cleared_rankings")` event.

25. **`--confirm-scan-roots` non-interactive flag (M6, risk).** tmux pipe-pane and `dev-session.sh` defeat `isatty(stdin)`; without an alternative, Justin hits silent refusal day-one. Flag accepts repeatable `<dir>`, validates via `validate_project_root()`, appends to `scan-roots.confirmed` without prompting, idempotent (re-add is no-op). Self-diagnostic stderr message when the regular interactive flow refuses on non-tty.

26. **`tests/test-allowlist-inverted.sh` separation (M8, testability).** A test that fails when run alone is brittle — a crash falsely "passes" the inverted assertion. Split: regular `test-allowlist.sh` runs normal fixtures (expected exit 0); `test-allowlist-inverted.sh` invokes validator with `leakage-fail.jsonl` and asserts BOTH non-zero exit AND specific stderr violation message containing literal `additionalProperties` and the offending field name. `tests/run-tests.sh` invokes via `! ./tests/test-allowlist-inverted.sh` shape.

27. **`importlib.util` for `session_cost` import (M1, Codex).** `from session_cost import …` was a planning-stage hallucination — hyphenated filenames can't be bound to module names via `sys.path` alone. Use `importlib.util.spec_from_file_location("session_cost", str(Path(__file__).parent / "session-cost.py"))` (3 lines, one-time at top of `compute-persona-value.py`).

28. **Stdlib allowlist validator (M2, Codex).** No PyPI `jsonschema` dependency on public-release week. ~30 lines of stdlib python: load schema → walk row keys + assert in `properties` (`additionalProperties: false`) → assert `required[]` keys present → for each property, check type + (if `enum`) value-in-enum + (if `pattern`) regex match. Allowlist schema is small (~22 fields); validator is testable in isolation. New file `scripts/_allowlist_validator.py` (single-purpose helper module).

## Implementation Tasks (Wave-Ordered)

### Wave 0 — Spike close + data contracts (parallel; 2-3 subagents)

| # | Task | Depends On | Size | Parallel? |
|---|------|------------|------|-----------|
| 0.1 | Close Phase 0 spike Q1 — probe one MonsterFlow session, verify `total_tokens` annotation == `sum(usage)` from `subagents/agent-<id>.jsonl`. Write result to `plan/raw/spike-q1-result.md`. Update spec §Phase 0 Spike Result. | — | S | yes |
| 0.2 | Write `schemas/persona-rankings.allowlist.json` per data-model sketch + security overrides (drop `window_start_artifact_dir`, **minute-truncated** `last_artifact_created_at` (renamed from `last_seen`)). | — | S | yes (with 0.1, 0.3, 0.4) |
| 0.3 | Write `scripts/redact-persona-attribution-fixture.py` (single-purpose, bound to allowlist schema). | 0.2 | S | yes (with 0.1, 0.4) |
| 0.4 | Build `tests/fixtures/cross-project/` — two synthetic project trees, each with `docs/specs/<f>/{spec-review,plan,check}/{findings,survival,run.json,raw/<persona>.md}`. Designed so ≥1 (persona, gate) pair has ≥3 qualifying rows AND ≥1 has only 1 (so A6 "(only N qualifying)" branch is exercisable). | — | M | yes |
| 0.5 | Build `tests/fixtures/persona-attribution/` — redacted real session excerpts via 0.3, plus deliberate-failure fixture (`leakage-fail.jsonl`) with one forbidden field. | 0.1, 0.3 | S | sequential after 0.1+0.3 |

**DoD Wave 0:** Q1 result documented. Both schemas validate. Cross-project fixtures cover both A6 branches. Deliberate-failure fixture has one forbidden field that `additionalProperties: false` would catch.

### Wave 1 — Engine + privacy gates (sequential after Wave 0; ~2 subagents internally)

| # | Task | Depends On | Size | Parallel? |
|---|------|------------|------|-----------|
| 1.1 | Project Discovery cascade — implement `validate_project_root()` (path-traversal + symlink containment); cwd auto-discovery; `${XDG_CONFIG_HOME:-$HOME/.config}/monsterflow/projects` reader; `--scan-projects-root` with interactive `scan-roots.confirmed` flow + `.monsterflow-no-scan` opt-out sentinel; **non-tty refusal path with self-diagnostic stderr message (M6)**; **`--confirm-scan-roots <dir>` non-interactive companion flag (M6)**. | 0.2 | M | — |
| 1.2 | `safe_log()` helper — fixed `SAFE_EVENTS` enum (`discovered_projects`, `malformed_artifact`, `missing_artifact`, `window_rolled`, `wrote_rankings`, `truncated_finding_ids`, `rejected_config_entry`, `rejected_symlink_escape`, **`regenerated_salt_cleared_rankings` (M7)**, **`silent_persona_observed` (M4)**, **`non_interactive_scan_refused` (M6)**); value-pattern allowlist (persona/gate/state/sha256/int/ISO-date); raw `print()` banned by `tests/test-no-raw-print.sh` grep gate. **Plus stdlib allowlist validator helper module `scripts/_allowlist_validator.py` (M2, ~30 lines: additionalProperties + required + enum/pattern; no PyPI dep).** | — | S+ | yes (with 1.1) |
| 1.3 | Cost walk — `~/.claude/projects/*/*.jsonl` mtime-pruned single-pass with substring pre-filter (`"Agent"` + `"tool_use"`); per-(persona, gate, parent_session_uuid) attribution; persona-name regex from Agent dispatch prompt; `agentId` from tool_result trailing text. Imports `PRICING` + `entry_cost` from `session_cost` **via `importlib.util.spec_from_file_location` (M1) — bare `sys.path` does not work because filename has a hyphen**. **M3: emits to cost-window per (persona, gate); independent of value-window denominator.** | 1.1, 1.2, 0.5 | M | — |
| 1.4 | A1.5 cross-check — for every Agent dispatch in fixture: `total_tokens` from parent's tool_result == `sum(usage.input_tokens + usage.output_tokens)` from `subagents/agent-<id>.jsonl`. On agreement: parent annotation is canonical. **On disagreement: `compute-persona-value.py` exits non-zero** unless `--best-effort`. Resolves spike Open Q1. | 1.3 | S | — |
| 1.5 | Value walk + `run_state` classification — walks `findings.jsonl`, **`participation.jsonl` (M4)**, `survival.jsonl`, `run.json`, `raw/<persona>.md` per artifact directory; classifies into **7-state enum (M4 added `silent` for participation status:ok + findings_emitted:0)**; computes `total_emitted` from top-level bullets under `## Critical Gaps` / `## Important Considerations` / `## Observations` (excludes `## Verdict`, nested, numbered); emits `silent_runs_count` per row (M4). | 1.1, 1.2, **0.4** | L | yes (with 1.3) |
| 1.6 | 45-window cap (separate value + cost windows per M3) + `contributing_finding_ids[]` soft-cap (most-recent-50 + `truncated_count`); IDs sorted lex before emit; per-machine salt at `${XDG_CONFIG_HOME:-$HOME/.config}/monsterflow/finding-id-salt` (256-bit random, chmod 600); ID = `<gate-prefix>-sha256(salt \|\| normalized_signature)[:10]`. **M7: validate salt on read (32 bytes, non-zero, perms 0o600); on failure regenerate atomically via `O_CREAT \| O_EXCL` (first-run race) + `tmp + os.replace` (regen) AND clear `dashboard/data/persona-rankings.jsonl` for drill-down continuity reset.** | 1.5 | M | — |
| 1.7 | Roster sidecar emit — walks `personas/{review,plan,check}/*.md`; emits `dashboard/data/persona-roster.js` (`window.PERSONA_ROSTER = […]` with persona, gate, file_path, persona_content_hash, last_modified, deprecated). | — | S | yes (with 1.3, 1.5) |
| 1.8 | Rankings bundle emit — computes JSONL row per (persona, gate); **validates each via stdlib `_allowlist_validator.validate(row, allowlist_schema)` (M2 — NOT `jsonschema`)**; atomic write to `dashboard/data/persona-rankings.jsonl`; sibling `dashboard/data/persona-rankings-bundle.js` (`window.__PERSONA_RANKINGS = […]`); `sort_keys=True` + `round(x, 6)` for floats. | 1.4, 1.6, 1.7 | M | — |
| 1.9 | `tests/test-allowlist.sh` — A10 normal-fixture path. Asserts: every row in `persona-rankings.jsonl` has zero non-allowlist fields; every row in `tests/fixtures/persona-attribution/*.jsonl` (except `leakage-fail.jsonl`) passes; expected exit 0. Plus stderr canary check (`LEAKAGE_CANARY_xyz123`). | 1.2, 1.8, 0.5 | M | — |
| 1.9-inv | **`tests/test-allowlist-inverted.sh` (M8)** — A10 inverted-assertion path. Invokes validator with `tests/fixtures/persona-attribution/leakage-fail.jsonl`; asserts BOTH non-zero exit AND specific stderr violation message containing literal `additionalProperties` and the offending field name (e.g., `finding_title`). `tests/run-tests.sh` invokes via `! ./tests/test-allowlist-inverted.sh`. Standalone `make test` shape doesn't crash-into-passing. | 1.9, 0.5 | S | yes (with 1.9) |
| 1.10 | `tests/test-phase-0-artifact.sh` — A0. Asserts spec contains `## Phase 0 Spike Result` heading; section names `agentId`; `tests/fixtures/persona-attribution/` exists with ≥1 valid `.jsonl`. | 0.1, 0.5 | S | yes (with 1.9) |
| 1.11 | `tests/test-path-validation.sh` — symlink escape, `..` segments, non-absolute config entries; per-project `.monsterflow-no-scan` opt-out. | 1.1 | S | yes (with 1.9, 1.10) |

**DoD Wave 1:** A0, A1, A1.5, A8, A9, A10 all green against Wave 0 fixtures. Engine produces a real `persona-rankings.jsonl` + `persona-rankings-bundle.js` + `persona-roster.js` from the cross-project fixture.

### Wave 2 — Surfaces (parallel; 2 subagents)

| # | Task | Depends On | Size | Parallel? |
|---|------|------------|------|-----------|
| 2.1 | `commands/wrap.md` Phase 1c integration — insert unconditional `compute-persona-value.py` invoke after line 160; pre/post `[ -f persona-rankings.jsonl ]` check gates `persona-metrics-validator` invocation (V3 trigger); render text section per ux's locked format (top + bottom 3 per dim × per gate, "(only N qualifying)" handling, "never run this window" line, retention-vs-survival semantics note). | 1.8 | M | yes |
| 2.2 | `dashboard/index.html` — third top-level mode button `<button data-mode="personas">Persona Insights</button>` near line 70; three `<script src>` tags in strict order (roster.js → rankings-bundle.js → persona-insights.js); extend mode handler. | — | S | yes (with 2.1) |
| 2.3 | `dashboard/persona-insights.js` (NEW) — registers `window.__renderPersonaInsightsView`; merges `PERSONA_ROSTER` + `__PERSONA_RANKINGS`; renders sortable table (per ux spec) with `.badge` for dominant `run_state` (**M4: silent badge distinct from "never run" badge**); **two count tooltips per M3 — "value-window: N directories; cost-window: M dispatches" on `runs_in_window` and on cost columns**; `.row-low-sample` (opacity 0.55) for insufficient_sample; strikethrough + red badge for deleted; "(never run)" rows from roster-only entries; null-rate cells `—` (sort to bottom always); color bands; banners (privacy + stale-cache + empty-state per ux's locked copy); **content-hash mixed-window tooltip "Hash recently changed (mixed-window)" when current hash != oldest row's hash in window** (Risk S3). | 2.2 | M | sequential after 2.2 |
| 2.4 | `.gitignore` — add `dashboard/data/persona-rankings-bundle.js`, `dashboard/data/persona-roster.js` (existing `dashboard/data/*.jsonl` covers JSONL). | — | S | yes |

**DoD Wave 2:** Both rendering surfaces work against Wave-1 JSONL under `file://`. Banner copy matches ux spec verbatim. State badge silent for `complete_value`, otherwise dominant-state badge with hover-tooltip breakdown.

### Wave 3 — End-to-end acceptance (parallel; 2-3 subagents)

| # | Task | Depends On | Size | Parallel? |
|---|------|------------|------|-----------|
| 3.1 | `tests/test-compute-persona-value.sh` — **A1 (cost-sum equality on subagent rows)**, A2 (3 rates + 7-state `run_state_counts`; value-states sum to `runs_in_window`; cost-window states sum to `cost_runs_in_window` per M3); A3 (cross-project cascade tested via cwd, fixture-config, `--scan-projects-root`, `--confirm-scan-roots`); A4 (content-hash window reset, asserts post-edit `contributing_finding_ids[]` cleared per **product-decision wording per Codex**); A7 (e1–e12 + soft-cap behavior + `--scan-projects-root` opt-in default-off + **silent-persona rendering per M4**); **A8 (idempotent re-run: byte-equality excluding `last_artifact_created_at`)**; A11 (≥1 row per distinct (persona, gate) pair present in source `findings.jsonl[s]` + e12 fresh-install case explicitly tested). | 1.8, 0.4 | L | yes |
| 3.2 | Dashboard A5 — DOM-level assertions that "Persona Insights" tab present, sortable, insufficient-sample rows dim with "—" rate cells, deleted personas strikethrough + "deleted" badge, "(never run)" rows from roster-only entries, **silent badge distinct from "never run" badge per M4**, all three banners (privacy / stale-cache / empty-state) render correctly under each precondition (**explicit e12 fresh-install sub-case: no JSONL + roster.js present → empty-state banner + "(never run)" rows for full roster**). **Banner assertions use CSS class (`.banner-privacy`, `.banner-empty-state`, `.banner-stale`) + load-bearing word, NOT full copy equality** per testability. **Color band assertions use `.band-low/.band-mid/.band-high` class boundaries, not RGB pixel diff.** Loaded under `file://`. | 2.3 | M | yes (with 3.1, 3.3) |
| 3.3 | `/wrap-insights` A6 — text-format assertions; cost ranking uses `avg_tokens_per_invocation` not totals; "(only N qualifying)" annotation; retention-vs-survival semantics note present. | 2.1 | S | yes (with 3.1, 3.2) |
| 3.4 | Privacy regression: `tests/test-finding-id-salt.sh` (same input + different salts → different IDs; salt file perms 600 verified via **`python3 os.stat`** for portability per testability; **M7: zero-byte salt + truncated salt + world-readable perms each trigger regen + rankings clear**); `tests/test-scan-confirmation.sh` (non-tty refusal with self-diagnostic message; **`--confirm-scan-roots` non-interactive flow per M6**; pre-confirmed roots; `.monsterflow-no-scan` sentinel respected). | 1.6, 1.1 | S | yes (with 3.1) |
| 3.5 | Telemetry + final lint — verify no raw `print()` in `compute-persona-value.py` (test 1.2's grep gate passes; **regex pinned per testability — catches `print(`, `sys.stdout.write`, `sys.stderr.write`; excludes comments and string literals; scope `compute-persona-value.py` only**); verify `--help` output for all 6 flags lists the Project Discovery cascade verbatim; verify the `persona-metrics-validator` subagent runs cleanly against Wave-1 output; **A1.5 disagreement-path test (testability #5) — exercise tampered fixture, assert non-zero exit + `--best-effort` downgrade behavior**; **A0 spike-result content checks (testability #4) — assert `wc -l > 10` + literal token grep for `total_tokens` + `subagents/agent-` + verdict line**. | All Wave 1+2 | S | sequential after others |

**DoD Wave 3:** A0–A11 all green. Privacy regression suite green. `--help` output matches CLI spec. `persona-metrics-validator` reports zero schema violations.

### Wave 3 — additions per Q1 (locked 2026-05-04)

| # | Task | Depends On | Size | Parallel? |
|---|------|------------|------|-----------|
| 3.6 | `scripts/install-precommit-hooks.sh` (NEW) — adopter-installable opt-in script. Wires a pre-commit hook that runs `tests/test-allowlist.sh` whenever any file under `tests/fixtures/persona-attribution/**` or `dashboard/data/**` is staged. Idempotent (rerunnable, doesn't duplicate hooks); detects existing hooks and prepends safely. Not auto-enabled by `install.sh` rewrite. | 1.9 | S | yes (with 3.1–3.5) |
| 3.7 | `docs/persona-ranking.md` (NEW, in-scope per Q1) — single page covering: **two-window cost-vs-value distinction per M3** (with worked example so adopters don't misread aligned numbers), retention-vs-survival semantics callout, **silent-vs-never-run badge distinction per M4**, persona contributors' data lifecycle, Project Discovery cascade with concrete examples (`scan-roots.confirmed` flow, **`--confirm-scan-roots` for tmux/log-piped sessions per M6**, `.monsterflow-no-scan` opt-out, `MONSTERFLOW_DEBUG_PATHS=1` env), pre-commit hook installation snippet pointing at 3.6. **Deps simplified per sequencing #2: 1.1 + 1.6 + 3.6 (NOT 3.1) — runs parallel with Wave 3 tests.** | **1.1, 1.6, 3.6** | S | yes (parallel with 3.1–3.5) |

### Out-of-band tasks (post-merge, not blocking v1)

- `~/.config/monsterflow/README.md` — written by future `install.sh` rewrite (BACKLOG #2 — Onboarding spec).

## Open Questions — all resolved 2026-05-04

| # | Question | Resolution |
|---|----------|------------|
| 1 | Adopt 6 spec deltas in v4.1 or in `/check`? | **Adopt in v4.1.** Spec amended in same session; `/check` reviews coherent spec/plan pair. |
| 2 | `session-cost.py` non-modification (Δ6) — pre-commit or surface for `/check` re-litigation? | **Pre-commit.** Δ6 in spec; `/check` flags only if import path is genuinely broken. |
| 3 | Pre-commit hook — opt-in script or docs only? | **Both** — `scripts/install-precommit-hooks.sh` (Wave 3 task 3.6) + `docs/persona-ranking.md` paragraph (Wave 3 task 3.7). |
| 4 | `--scan-projects-root` repeatable or comma-separated? | **Repeatable**, argparse `action="append"`. Matches one-path-per-line convention in `scan-roots.confirmed`. |

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| A1.5 disagreement (parent annotation ≠ subagent sum) → engine has no canonical token source | Low (Q2 closed; Q1 remains) | High (spec re-opens) | A1.5 fails build hard; `--best-effort` downgrade exists; subagent transcript path is canonical fallback |
| Adopter's `--scan-projects-root ~/Projects` includes client-confidential repos | Medium | High (privacy leak) | Interactive scan-confirmation flow (decision #13); `.monsterflow-no-scan` per-project opt-out; counts-only telemetry (decision #12); allowlist-enforced output (A10) |
| `additionalProperties: false` rejects a legitimate field added in v1.1 | Medium | Low | `schema_version: 1` bump path documented; v1.1 spec must update allowlist explicitly |
| Heavy adopter (5 projects, 167 features) > 5s refresh | Medium | Low | mtime-prune brings 3-5s; cold first-run 30-60s with stderr warning. Document, don't optimize beyond Wave 1. |
| Persona-name regex breaks under `/autorun` headless flow scaffolding | Low | Medium | Regex tested across 73 RedRabbit fixtures during round-2; unknown personas map to `<unknown>` (don't silently drop). Add autorun fixture in /check if /autorun ships first. |
| `findings.jsonl` schema evolves under our feet (e.g., persona-metrics adds a field) | Low | Low | We read only `personas[]` + `unique_to_persona`; both schema-stable. Forward-compat by reading-permissively. |
| Dashboard `<script src>` load order fails silently if one bundle is missing | Low | Medium | Each bundle file emits `window.__BUNDLE_FOO_LOADED = true`; persona-insights.js asserts presence + renders empty-state on absence. |
| Salt file leaks → finding IDs become guessable | Very low | Low | Single-machine impact; regenerate to invalidate; documented in `docs/persona-ranking.md`. |
| Adopter `git add -f dashboard/data/persona-rankings.jsonl` to share a snapshot | Medium | Low (allowlist-enforced output already privacy-safe) | A10 catches at PR review time; allowlist removes most leak vectors. |
| **tmux pipe-pane / `dev-session.sh` defeats interactive scan-confirmation flow** (M6 / Risk S1) | **High (will hit Justin day-one without M6)** | Medium | `--confirm-scan-roots` non-interactive flag (M6); self-diagnostic stderr message on non-tty refusal. |
| **Salt file mid-run corruption / partial-write** (M7 / Risk S2) | Low | Medium (drill-down breaks; rankings invalidated) | Validate on read (32 bytes, non-zero, perms 0o600); regenerate atomically + clear rankings JSONL on failure. |
| **Content-hash 90%-pre-edit-data window** (Risk S3) | Medium | Low (informational; doesn't affect correctness, just interpretation) | "Hash recently changed (mixed-window)" tooltip when current hash != oldest row's hash in window. |
| **Plan-text hallucinations surviving to /build** (M1 — `from session_cost import` bug) | **Demonstrated** (caught by Codex at /check, fixed before code) | Low (caught by adversarial gate) | Adversarial reviewer (Codex) verifies plan against actual codebase, not just spec text; established pattern at every gate. |

## Spec Deltas to Apply Before /check

These five deltas are required by the plan but currently misalign with spec v4. Apply as v4.1 before `/check`:

| # | Spec section | Change |
|---|--------------|--------|
| Δ1 | Data section / row schema | DROP `window_start_artifact_dir` field |
| Δ2 | Data section / `last_seen` | Truncate to **date-minute** (revised from hour per Justin 2026-05-04); rename to `last_artifact_created_at` |
| Δ3 | Data section / `contributing_finding_ids` | Per-machine salt: `sha256(salt \|\| normalized_signature)[:10]`; salt at `~/.config/monsterflow/finding-id-salt` (256-bit, chmod 600); cross-machine ID stability explicitly NOT a feature |
| Δ4 | Project Discovery / Telemetry | Counts-only stderr telemetry; paths only in interactive `--scan-projects-root` confirmation + behind `MONSTERFLOW_DEBUG_PATHS=1` env (logs to `~/.cache/monsterflow/debug.log`) |
| Δ5 | Project Discovery / Tier 3 | First-use interactive confirmation via `~/.config/monsterflow/scan-roots.confirmed`; non-tty refuses; per-project `.monsterflow-no-scan` opt-out sentinel |
| Δ6 | Integration / Files modified | DO NOT modify `scripts/session-cost.py`; `compute-persona-value.py` imports `PRICING` + `entry_cost` instead |

## Agent Disagreements Resolved

- **Should `compute-persona-value.py` modify `session-cost.py` (per spec) or import from it (per integration)?** Integration's lower-blast-radius argument wins: round-3 narrowing to artifact-directory aggregation removed the per-row attribution need. Recorded as Δ6.
- **Telemetry line format** — spec says paths; security says counts-only. Security wins: paths leak project structure on a public repo. Counts-only in steady state; paths only in interactive confirmation prompt. Recorded as Δ4.
- **Window start field** — spec persists `window_start_artifact_dir` (a path); security says drop or hash. Drop: only used for idempotency debug, redundant with `(persona, gate)` key. Recorded as Δ1.
- **`last_seen` precision** — spec uses full ISO; security said truncate to hour for work-pattern privacy; Justin relaxed to minute (within-hour activity not a privacy concern; minute precision improves dashboard UX). Recorded as Δ2 (also renamed to `last_artifact_created_at` per api).
- **Contributing finding ID hashing** — spec's "sha256-derived but not assumed unguessable" + security's "rainbow-table threat is real for targeted recon." Per-machine salt closes the threat at the cost of cross-machine ID stability (not a v1 use case). Recorded as Δ3.
- **`--scan-projects-root` UX** — api wants flag-and-go; security wants confirmation. Security wins on a public release: friction-aligned with privacy risk. Non-tty refusal preserves automation. Recorded as Δ5.
- **`run_state` surfacing in dashboard** — ux's badge-only-when-non-default approach beats api's first-class `Coverage` column proposal. Resolution: keep both — small `.badge` (dominant state) AND a `Coverage` column rendering `14/18 complete` from `run_state_counts`. ux's "no peer-rank by run_state" concern addressed by removing it from default sort.
- **Three render surfaces** — spec previously had 3; round-3 cut bare-arg full-table. Wave 2 confirms 2 surfaces only (dashboard tab + `/wrap-insights` text section).

## Consolidated Verdict (post-/check, v1.2)

**Plan is ready for `/build`.** Spec v4.2 (Δ1–Δ6 + M1–M8 applied) and plan v1.2 (this file) are coherent. `/check` returned GO WITH FIXES; all 8 must-fix items applied inline above. 33 design recommendations clustered in `plan/findings.jsonl` (94% addressed by plan.md). 29 check findings clustered in `check/findings.jsonl` (M1–M8 = blockers; ~16 should-fix folded into task descriptions). Wave 0 starts with the Phase 0 spike (A1.5 forcing function) — see Wave 0 task 0.1.

**Confirmed plan hallucinations from /check + how they were caught:**
- M1 `from session_cost import` was a planning hallucination — hyphenated filename can't bind via `sys.path`. Codex verified empirically; fixed via `importlib.util.spec_from_file_location`.
- M2 `jsonschema.validate` was an undeclared dependency assumption — `python3 -c "import jsonschema"` fails on this machine. Fixed via stdlib allowlist validator.

The adversarial gate (Codex) catching what 5 primary reviewers missed is the established pattern at every step — `/spec-review` round 2 + 3 + `/check` all showed it. Worth memorializing as the reason Codex stays in the workflow.
