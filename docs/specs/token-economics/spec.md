---
name: token-economics
description: Per-persona cost + retention + downstream-survival + uniqueness instrumentation — best-effort aggregate, no roster scaling
created: 2026-05-03
revised: 2026-05-04
revision: 4.2
status: ready-for-build
session_roster: defaults-only (no constitution)
---

# Token Economics Spec (v4.2 — instrumentation only, public-release-ready)

**Created:** 2026-05-03
**Revised:** 2026-05-04 — v2 narrowed scope; v3 applied 7 round-2 schema-deep blockers; v4 applied Codex round-3 5 blockers + 3 convergent findings; v4.1 applied 6 spec deltas from /plan; **v4.2 applies 8 must-fix items from `/check` — 5 Codex blockers (hyphen-import bug, jsonschema dep, cost↔value join, silent-persona misclassification, --list-projects privacy contradiction) + 3 from primary reviewers (tmux non-tty refusal, salt corruption, inverted-assertion meta-runner)**.
**Constitution:** none — session roster only
**Confidence:** Scope 0.97 / UX 0.94 / Data 0.94 / Integration 0.93 / Edges 0.95 / Acceptance 0.96
**Session Roster:** defaults-only (28 pipeline personas)

> Session roster only — run /kickoff later to make this a persistent constitution.

## Summary

Measure per-persona **cost** (tokens spent in subagent dispatches per gate) and per-persona **value** along three independent axes — **judge-retention** (post-Judge clustering compression ratio), **downstream-survival** (addressed in next pipeline artifact), and **uniqueness** (sole contributor to cluster). v1 ships **two honestly separated signals (M3):** value metrics windowed over 45 most-recent (persona, gate) **artifact directories** across discovered MonsterFlow projects; cost metrics windowed over 45 most-recent observed Agent dispatches per (persona, gate) — **NOT aligned to the value-window 45 directories.** Per-dispatch capture (the join key that aligns them) is v1.1+ scope. Persist to `dashboard/data/persona-rankings.jsonl`, refresh unconditionally at `/wrap-insights`, surface in a new dashboard tab and `/wrap-insights` text section. **No automatic action** — no roster pruning, no tier detection, no gate behavior changes.

**Pro-tier relief comes in v1.1 (BACKLOG #3) immediately after this lands.** This v1 ships measurement only; the friend-on-Pro who motivated the work gets actionable cost reduction once the next spec ships, not from this one.

## Backlog Routing

| # | Item | Source | Routing |
|---|------|--------|---------|
| 1 | Token economics instrumentation | BACKLOG.md | **(a) In scope** — this spec |
| 3 | Account-type agent scaling | BACKLOG.md | **(b) Stays — committed v1.1 fast-follow** after this spec ships and ≥10 validated runs accumulate |
| 4 | Inter-agent debate (Agent Teams) | BACKLOG.md | **(b) Stays** — research, separate `/spec` after #3 |
| 2 | Onboarding install.sh rewrite | BACKLOG.md | **(b) Stays** — independent, separate `/spec` |
| — | Plugin scoping per gate (action) | BACKLOG.md | **(b) Stays** — needs per-plugin cost measurement (also deferred) |
| — | Per-plugin cost measurement | BACKLOG.md | **(b) Stays** — depends on Phase 0 spike completing first |
| — | Per-dispatch persona-hash capture (proper content-hash boundary) | NEW | **(b) Stays** — required for invocation-level metrics; v1 uses best-effort artifact-directory aggregation |

## Scope

**In scope:**
- Per-persona, per-gate cost attribution. Subagent transcripts at `~/.claude/projects/<proj>/<parent-session-uuid>/subagents/agent-<agentId>.jsonl`; linkage via `agentId` in parent's `Agent` tool_result trailing text (see Phase 0 spike result).
- **Best-effort aggregation by artifact directory** — v1 windows over the most recent 45 (persona, gate) **artifact directories** (i.e., `docs/specs/<feature>/<gate>/` directories that contain `findings.jsonl`), not Agent dispatches. Rationale: existing artifacts lack stable `agent_tool_use_id`; invocation-level join is a v1.1 expansion (see `run_state` column for what each row represents).
- **Three value signals**, kept independent:
  - **Judge retention ratio** = `count(findings.jsonl rows where persona ∈ personas[]) / count(all top-level bullets in <stage>/raw/<persona>.md, including Critical Gaps + Important Considerations + Observations)`. Measures: how compressively did Judge cluster this persona's bullets? **NOTE: This is a compression ratio, not a survival rate.** Judge can merge multiple bullets into one finding or split one bullet across findings; the ratio captures cluster density per emitted bullet, not "did this thought survive." Renamed from `judge_survival_rate` in v3 to avoid overinterpretation.
  - **Downstream survival rate** = `count(survival.jsonl rows with outcome == addressed where finding's personas[] includes persona) / count(findings.jsonl rows where persona ∈ personas[])`. Uses ONLY `outcome == addressed` per the actual `survival.jsonl` schema (which has `addressed`, `not_addressed`, `rejected_intentionally`, `classifier_error` — no `kept`). Truly captures: did this persona's surviving findings get picked up downstream?
  - **Uniqueness rate** = `count(findings.jsonl rows where unique_to_persona == persona) / count(findings.jsonl rows where persona ∈ personas[])`. Uses existing `findings.jsonl.unique_to_persona` field — no jaccard, no recomputation.
- Persistence to `dashboard/data/persona-rankings.jsonl` with **rolling 45 (persona, gate) artifact-directory window**. Reports totals (no averaging) AND `avg_tokens_per_invocation` as a derived field for cost ranking.
- **`run_state` column** on each row capturing artifact completeness — see Data section.
- Refresh hook in `/wrap-insights` Phase 1c — **unconditional**, NOT piggybacked on `dashboard-append.sh`.
- **Project Discovery defaults to opt-in for `~/Projects/*` scanning** for public-release safety — see §Project Discovery cascade below.
- New "Persona Insights" dashboard tab — sortable table with separate columns for **judge_retention_ratio, downstream_survival_rate, uniqueness_rate, total_tokens, avg_tokens_per_invocation, runs_in_window, run_state**. No composite score. Renders both data-driven rows AND "(never run)" rows for personas in current `personas/` files but absent from JSONL (hybrid; see Approach).
- `/wrap-insights` text sub-section showing top + bottom 3 per gate × per dimension (when ≥3 qualifying personas exist).
- `contributing_finding_ids[]` field on each row for drill-down, **soft-capped** at most-recent 50 IDs + `truncated_count`.
- Edge-case handling for new personas, persona-prompt edits (best-effort, see e2), file concurrency, malformed JSONL, deleted personas.

**Out of scope (deferred to separate specs):**
- Roster scaling / auto-pruning (BACKLOG #3) — committed v1.1 immediately after.
- Tier detection (Pro/Max/API) — only useful for #3.
- Runtime gate-roster resolver, gate command edits.
- Composite ranking score.
- Per-plugin cost attribution + plugin-scoping action.
- Per-dispatch `agent_tool_use_id` capture in `findings.jsonl` / `run.json` (the proper invocation-level join — v1.1+).
- Per-dispatch persona-content-hash capture (the proper content-hash boundary — v1.1+).
- Per-project opt-out granularity (current spec is per-project opt-in via config; per-project opt-out is symmetric and adds adopter knobs we don't need yet).
- Build-outcome correlation as a value signal.
- Linux support for new scripts (macOS-only).
- The logging-shim path if Phase 0 spike fails — separate spec, not in-flight expansion.
- `/wrap-insights ranking` bare-arg full-table — duplicates dashboard tab; cut from v1.

## Phase 0 Spike Result (preliminary — closed Q2)

**Status:** preliminary. **Q1 deferred to A1.5** test outcome (forcing function: on disagreement, A1.5 fails the build and `/plan` re-opens Q1). **Q2 closed by probe** during round-3 review.

**Probe:** `~/.claude/projects/-Users-jstottlemyer-Projects-RedRabbit/42dcaafa-1fbb-4d52-9344-1899381a205c.jsonl` (6427 lines, 73 Agent dispatches).

**Closed:**
- **Where do subagent usage rows land?** NOT in parent session JSONL. Subagent transcripts at `~/.claude/projects/<proj>/<parent-session-uuid>/subagents/agent-<agentId>.jsonl` with full per-row `usage`. Sibling `agent-<agentId>.meta.json` contains `{agentType, description}`.
- **What field links parent→subagent?** The `agentId` string (16 hex chars) in parent's `Agent` tool_result trailing text: `agentId: <16-hex>\n<usage>total_tokens: N\ntool_uses: N\nduration_ms: N</usage>`.
- **How do we recover the persona name?** The Agent dispatch's `input.prompt` contains `personas/<gate>/<name>.md` (regex-extractable across all 73 fixtures).
- **Q2 — worktree behavior:** worktree sessions get their **own top-level `~/.claude/projects/<sanitized-worktree-path>/` entry**. `subagents/` folders sit under that, NOT under the original parent dir. Project Discovery does NOT need to follow worktree symlinks; just dedupe by absolute realpath.

**Still open (to resolve in `/plan` via A1.5):**
- **Q1 — canonical token source:** is the `total_tokens` annotation in parent's tool_result equal to the sum from `subagents/agent-<id>.jsonl`? **A1.5 verifies. On agreement: parent annotation is canonical (cheap). On disagreement: A1.5 fails build, `/plan` re-opens Q1, subagent transcript is canonical.**

**Spike fixture:** `tests/fixtures/persona-attribution/` — populated in `/plan` with **redacted** JSONL excerpts (only allowlisted fields per `schemas/persona-rankings.allowlist.json`; see Privacy section).

## Approach

**Phase 1 — instrumentation:**
- Extend `scripts/session-cost.py` to walk both root families:
  - **Cost root:** `~/.claude/projects/*/` for session JSONLs + `subagents/` subdirs.
  - **Value root:** discovered MonsterFlow project paths (see §Project Discovery) for `docs/specs/*/{spec-review,plan,check}/{findings,survival,run}.json{l}`.
  - Group cost by (parent_session_id, agentId) → match agentId to its `subagents/agent-<id>.jsonl`, sum `usage`. Recover persona name via regex on parent's `Agent` tool_use prompt; emit per-(persona, gate, parent_session_uuid).
- New `scripts/compute-persona-value.py`:
  - Walks `findings.jsonl` + `survival.jsonl` + `run.json` across all discovered projects.
  - Computes per (persona, gate, **artifact_directory**):
    - **judge_retained_count** = rows in `findings.jsonl` where `persona ∈ personas[]`.
    - **emitted_bullet_count** = top-level bullets (lines starting with `- ` or `* ` at first-column indent) under `## Critical Gaps`, `## Important Considerations`, `## Observations` headings in `<stage>/raw/<persona>.md`. Excludes nested/continuation bullets, numbered lists, the `## Verdict` section.
    - **downstream_survived_count** = rows in `survival.jsonl` with `outcome == addressed` whose `finding_id` joins to `findings.jsonl` rows where `persona ∈ personas[]`.
    - **unique_count** = rows in `findings.jsonl` where `unique_to_persona == persona`.
    - **total_tokens** = sum across all Agent dispatches in this artifact directory's parent session(s) where the dispatch loaded this persona.
    - **run_state** = one of `complete_value`, `missing_raw`, `missing_findings`, `missing_survival`, `malformed`, `cost_only`. (See Data section for state machine and which states count toward which denominator.)
  - Caps the window at the most recent 45 (persona, gate) artifact directories per persona-gate pair.
  - Emits totals AND `avg_tokens_per_invocation = total_tokens / runs_in_window` as a derived field.
  - Excludes a row's rates from rendering if `runs_in_window < 3` (sets `insufficient_sample: true`); row is still written.
  - Soft-caps `contributing_finding_ids[]` at most-recent 50 IDs; surplus rolled into `truncated_count`.
- **Roster sidecar emit:** `compute-persona-value.py` walks current `personas/{review,plan,check}/*.md` and emits a sibling `dashboard/data/persona-roster.js` (a `window.PERSONA_ROSTER = [...]` assignment) so the dashboard can render "(never run)" rows under `file://` without `fetch()`.
- Refresh hook in `commands/wrap.md` Phase 1c — invokes `compute-persona-value.py` **unconditionally** when `/wrap-insights` runs.

**Phase 2 — visualization:**
- New "Persona Insights" tab in `dashboard/index.html`:
  - Reads JSONL data + `persona-roster.js` (loaded via `<script src>`, no `fetch()`).
  - Sortable table merging the two sources. Personas in the roster AND JSONL: data row. In roster but NOT in JSONL: "(never run)" row. In JSONL but NOT in roster: strikethrough (deleted persona).
  - Columns: persona, gate, runs_in_window, run_state, judge_retention_ratio, downstream_survival_rate, uniqueness_rate, total_tokens, avg_tokens_per_invocation, last_seen, persona_content_hash, contributing_finding_ids (collapsible).
  - **Insufficient-sample rows: rate cells render as "—".** Sorting by any rate column places null cells at the **bottom** (always — locked).
  - Warning banner above the table on first render: "Persona scores reflect this machine's MonsterFlow runs only. Screenshots and copy-pastes share persona names + numbers — review before sharing publicly."
- `/wrap-insights` Phase 1c sub-section format:
  ```
  Persona insights (last 45 (persona, gate) directories, all discovered projects)
    spec-review:  highest judge-retention → ux-flow (0.89), scope-discipline (0.84), cost-and-quotas (0.78)
                  highest downstream-survival → scope-discipline (62%), edge-cases (54%)
                  highest uniqueness → edge-cases (32%), scope-discipline (28%)
                  lowest avg cost → cost-and-quotas (8.2k tok/invocation), gaps (9.1k tok/invocation)
                  never run this window: legacy-reviewer (in roster, no data)
    plan:         …
    check:        …
  ```
  Show all-available with "(only N qualifying)" annotation if fewer than 3 personas have `runs_in_window ≥ 3`. v1 stays static — no week-over-week deltas. **Cost ranking uses avg_tokens_per_invocation (not total)** so frequently-run personas aren't penalized.

**Alternatives considered + rejected:**
- Computing on-the-fly per dashboard load (slow on large histories).
- Per-project (not cross-project) aggregation (artificially shrinks samples).
- Composite ranking score (rounds 1+2 reviewers showed it's gameable, severity-blind, schema-redundant).
- Re-jaccarding finding titles (existing `unique_to_persona` already encodes signal).
- Per-invocation averaging without the artifact-directory window (no stable join key — see v3 round-2 review for full analysis).
- Auto-discovering `~/Projects/*` by default (privacy risk on public release; flipped to opt-in).

## Project Discovery (cascade — opt-in defaults for public release)

`compute-persona-value.py` resolves project roots via three-tier cascade. **For public release, defaults are conservative — `~/Projects/*` auto-scan is OFF unless adopters opt in.**

1. **Current repo (always on):** the cwd's `docs/specs/` is always included if present. Adopter sees their own data on day one without configuration.
2. **Explicit config:** `${XDG_CONFIG_HOME:-$HOME/.config}/monsterflow/projects` — one absolute path per line. Comments (`#`) and blank lines ignored. Missing paths logged to stderr but skipped (no abort). Adopter-maintained.
3. **CLI scan flag (opt-in, interactive confirmation — Δ5):** `compute-persona-value.py --scan-projects-root <dir>` walks `<dir>/*/docs/specs/`. **First use of any `<dir>`** triggers an interactive prompt:
   - Walks discovery, prints discovered project list to stderr (paths allowed here — interactive bootstrap, not steady state).
   - Prompts: "Confirm scan of these N roots? Append to `scan-roots.confirmed`? [y/N]"
   - On `y`: append `<dir>\n` to `${XDG_CONFIG_HOME:-$HOME/.config}/monsterflow/scan-roots.confirmed` (chmod 600).
   - On `N`: exit 0, no scan.
   - **Non-tty (e.g. `dashboard-append.sh`, `/autorun`, tmux pipe-pane via `dev-session.sh`):** never auto-confirms. Emits self-diagnostic stderr message `[persona-value] non-interactive stdin detected; cannot prompt to confirm scan-roots. Use --confirm-scan-roots <dir> from a real terminal first, or run interactively, then re-invoke /wrap-insights.` and skips scan tier (cwd + config still proceed).
   - Subsequent runs with same `<dir>` skip prompt automatically.
   - **Per-project opt-out:** any project root containing a `.monsterflow-no-scan` zero-byte sentinel file is silently excluded from cascade tier 3, regardless of `scan-roots.confirmed`. Documented for client-confidential repos.

4. **`--confirm-scan-roots <dir>` (M6):** non-interactive companion to tier 3, intended for tmux/log-piped sessions where stdin isn't a TTY. Validates `<dir>` via `validate_project_root()`, then appends to `scan-roots.confirmed` without prompting. Repeatable. Idempotent (re-adding an existing entry is a no-op). Emits `[persona-value] confirmed scan root: <count_only>` to stderr.

**CLI surface (post-M5 fold):** 5 flags total — `--scan-projects-root <dir>` (repeatable), `--confirm-scan-roots <dir>` (repeatable, M6), `--best-effort` (downgrade A1.5 disagreement to warning), `--out PATH`, `--dry-run` (compute discovery + write nothing; subsumes the cut `--list-projects` per M5), `--explain PERSONA[:GATE]`. `--list-projects` removed (privacy contradiction with counts-only telemetry).

Output is the union with deduplication via absolute `realpath` (handles worktrees per Q2 closure).

**Telemetry (Δ4):** on every invocation, `compute-persona-value.py` prints to stderr a one-line **counts-only** summary: `[persona-value] discovered N projects (sources: cwd:1, config:M, scan:K)`. Paths are NEVER in steady-state stderr — only emitted in the interactive `--scan-projects-root` first-use confirmation prompt and behind `MONSTERFLOW_DEBUG_PATHS=1` (logs to `~/.cache/monsterflow/debug.log`, machine-local, gitignored implicitly because outside repo).

**Lifecycle:** the config file is created lazily — `compute-persona-value.py` does NOT create it on first run. Adopters who want cross-project aggregation read the docs (`docs/specs/token-economics/spec.md` §Project Discovery) and create it themselves. Discoverable via the stderr telemetry plus a one-line README at `~/.config/monsterflow/README.md` written by `install.sh` if absent (out of scope here; opens an issue in onboarding).

## Roster Changes

No roster changes.

## Privacy (public release — strict allowlist enforcement)

This spec ships in a public repo. Four concrete privacy gates apply:

1. **A0 fixtures use allowlist enforcement.** `tests/fixtures/persona-attribution/` may contain ONLY the fields enumerated in `schemas/persona-rankings.allowlist.json` (linkage IDs, timestamps, model id, `usage` blocks, persona path). Tests reject every field not in the allowlist — no canary scanning. A redaction helper `scripts/redact-persona-attribution-fixture.py` exists as a **single-purpose** utility (not a general-purpose redaction tool; bound to the schema) to prep new fixtures.
2. **`compute-persona-value.py` reads `findings.jsonl` from any discovered project — including private ones if the adopter opts in via cascade tier 2 or 3.** The output JSONL records ONLY the fields in `schemas/persona-rankings.allowlist.json` — NEVER finding titles, bodies, or paths. **`contributing_finding_ids[]` are per-machine SALTED (Δ3):** `sha256(salt || normalized_signature)[:10]`, where `salt` is a 256-bit random value at `${XDG_CONFIG_HOME:-$HOME/.config}/monsterflow/finding-id-salt` (chmod 600, generated on first run). Cross-machine ID stability is **NOT a v1 feature** — drill-down is machine-local. A10 verifies via allowlist test.

   **Salt file robustness (M7):** validate on read — `len == 32 bytes` AND non-zero AND file perms `0o600`. On any failure (zero-byte, truncated, world-readable, missing): regenerate the salt atomically (tmp + `os.replace`) AND clear `dashboard/data/persona-rankings.jsonl` (drill-down continuity reset is the only honest behavior — old IDs are no longer reproducible from new salt). Emit `[persona-value] regenerated finding-id-salt; cleared rankings (drill-down reset)` to stderr. First-run race: file creation uses `O_CREAT | O_EXCL` (atomic create-or-fail), then `os.replace` from tmp; second racer sees existing file, validates, proceeds.
3. **`compute-persona-value.py` scrubs stderr/stdout** — warning paths use a `safe_log()` wrapper that emits only allowlisted field names + counts, never finding titles or bodies. A10 verifies stderr capture.
4. **`dashboard/data/persona-rankings.jsonl` is gitignored** per existing `dashboard/data/*.jsonl` rule. **`tests/fixtures/persona-attribution/` is committed but allowlist-enforced.** A9 covers both: gitignore for generated artifact, allowlist for committed fixture.

## Integration

**Files modified:**
- `commands/wrap.md` — Phase 1c: invoke `compute-persona-value.py` unconditionally; append "Persona insights" sub-section. (Δ6: `scripts/session-cost.py` is **NOT** modified — `compute-persona-value.py` imports `PRICING` and `entry_cost` via **`importlib.util.spec_from_file_location("session_cost", "scripts/session-cost.py")` (M1, ~3 lines at top of script)** because the hyphenated filename can't be bound to a module name via `sys.path` alone. Lower blast radius; cleaner test boundary; round-3 narrowing to artifact-directory aggregation removed the per-row attribution need inside `session-cost.py`.)
- `dashboard/index.html` — add "Persona Insights" third top-level mode tab.
- `dashboard/persona-insights.js` (NEW; `dashboard.js` is **not** modified) — render hybrid (data + roster) merge from `persona-rankings-bundle.js` + `persona-roster.js`.

**Files created:**
- `scripts/compute-persona-value.py` — value computation + Project Discovery cascade + roster sidecar emit + rankings bundle emit + `safe_log()` stderr + **stdlib allowlist validator (M2: ~30 lines, replaces `jsonschema.validate`; checks `additionalProperties: false`, `required[]`, enum/pattern for the actual fields used; no PyPI dep)**. Imports `PRICING` + `entry_cost` from `session_cost` via `importlib.util` (M1).
- `scripts/redact-persona-attribution-fixture.py` — single-purpose A0 fixture redaction helper, bound to the allowlist schema.
- `schemas/persona-rankings.allowlist.json` — JSON schema (`additionalProperties: false`) enumerating permitted fields in `dashboard/data/persona-rankings.jsonl` and `tests/fixtures/persona-attribution/*.jsonl`.
- `dashboard/data/persona-rankings.jsonl` — generated, gitignored.
- `dashboard/data/persona-rankings-bundle.js` — generated, gitignored, `window.__PERSONA_RANKINGS = […]` (sibling to JSONL; loaded under `file://` via `<script src>`).
- `dashboard/data/persona-roster.js` — generated, gitignored, `window.PERSONA_ROSTER = […]`.
- `tests/test-compute-persona-value.sh` — covers e1–e12 + Project Discovery cascade + drill-down.
- `tests/test-phase-0-artifact.sh` — A0 machine check.
- `tests/test-allowlist.sh` — A10 normal-fixture enforcement (asserts every row in regular fixtures + generated `persona-rankings.jsonl` validates; expected exit 0).
- `tests/test-allowlist-inverted.sh` (M8) — A10 inverted-assertion meta-runner: invokes the allowlist validator against `tests/fixtures/persona-attribution/leakage-fail.jsonl`, asserts BOTH non-zero exit code AND specific stderr violation message (e.g., contains literal `additionalProperties` and the offending field name). Only this test is allowed to "fail successfully"; `tests/run-tests.sh` runs it via inverted-exit-code check (`! ./tests/test-allowlist-inverted.sh` shape).
- `tests/test-path-validation.sh` — symlink escape, `..` segments, non-absolute config entries, per-project `.monsterflow-no-scan` opt-out (Δ5).
- `tests/test-finding-id-salt.sh` — same input + different salts → different IDs; salt file perms = 600 (Δ3).
- `tests/test-scan-confirmation.sh` — non-tty refusal, pre-confirmed roots, sentinel files (Δ5).
- `tests/test-no-raw-print.sh` — grep gate banning raw `print()` and `sys.stderr.write()` in `compute-persona-value.py` (Δ4 enforcement).
- `tests/fixtures/persona-attribution/` — REDACTED real-data excerpts + `leakage-fail.jsonl` (deliberate-failure fixture verifies A10 catches violations).
- `tests/fixtures/cross-project/` — two synthetic project trees for A3.

**Files NOT touched:**
- `commands/{spec-review,plan,check}.md` — gates dispatch the full default roster.
- `settings/settings.json` — no new keys.
- `findings-emit` directive at `commands/_prompts/findings-emit.md` — NOT modified (per-dispatch hash capture is a v1.1 spec, not this one).

**Existing systems leveraged:**
- Persona-metrics infrastructure (`docs/specs/persona-metrics/spec.md`) — `findings.jsonl` (`personas[]`, `unique_to_persona`), `survival.jsonl` (`outcome == addressed`), `run.json` (`created_at`), snapshot/findings-emit directives.
- `scripts/judge-dashboard-bundle.py` — cross-project walk pattern.

**Subagents to invoke during/after build:**
- `persona-metrics-validator` — after first `/wrap-insights` run that produces `persona-rankings.jsonl`.

## Data & State

### New artifact: `dashboard/data/persona-rankings.jsonl`

One row per (persona, gate) pair seen in the last 45 (persona, gate) **artifact directories** discovered:

```jsonc
{
  "schema_version": 1,                              // for forward-compatible v1.1 evolution
  "persona": "scope-discipline",
  "gate": "spec-review",
  "runs_in_window": 18,                             // count of artifact directories contributing to VALUE window
  "window_size": 45,
  "cost_runs_in_window": 22,                        // M3: cost-window count (independent of value-window); count of Agent dispatches contributing
  "run_state_counts": {                             // per-state denominator transparency (M4: 7 states including silent)
    "complete_value": 11,
    "silent": 3,
    "missing_survival": 3,
    "missing_findings": 0,
    "missing_raw": 0,
    "malformed": 0,
    "cost_only": 4                                  // contributes to cost_runs_in_window only, NOT runs_in_window
  },
  "total_emitted": 47,                              // sum of bullets in raw/<persona>.md across complete_value + silent + missing_survival rows
  "total_judge_retained": 31,                       // sum of findings.jsonl rows where persona ∈ personas[]; counts complete_value + missing_survival
  "total_downstream_survived": 19,                  // sum of survival.jsonl rows with outcome == addressed; counts complete_value only
  "total_unique": 9,                                // sum of findings.jsonl rows where unique_to_persona == persona; counts complete_value + missing_survival
  "silent_runs_count": 3,                           // M4: number of silent runs (status:ok, findings_emitted:0); informational
  "total_tokens": 274500,                           // M3: sum across COST window (cost_runs_in_window dispatches, NOT runs_in_window)
  "judge_retention_ratio": 0.659,                   // total_judge_retained / total_emitted    -- compression ratio, NOT survival
  "downstream_survival_rate": 0.404,                // total_downstream_survived / total_judge_retained
  "uniqueness_rate": 0.191,                         // total_unique / total_judge_retained
  "avg_tokens_per_invocation": 12477,               // M3: total_tokens / cost_runs_in_window (cost-window denominator, NOT value-window)
  "last_artifact_created_at": "2026-05-02T18:14:00Z", // minute-truncated; MAX(run.json.created_at) of contributing dirs, rounded down to minute
  "persona_content_hash": "sha256:9a4b…",           // CURRENT hash of personas/<gate>/<name>.md (NFC + LF-normalized). Best-effort: historical rows used unknown hash.
  "contributing_finding_ids": ["sr-9a4b1c2d8e", ...],   // most-recent 50 IDs only; per-machine SALTED hash (sha256(salt || normalized_signature)[:10])
  "truncated_count": 0,                             // count of finding IDs beyond the 50 cap
  "insufficient_sample": false                      // true iff runs_in_window < 3
}
```

**Counting unit:** **(persona, gate) artifact directories** — each `docs/specs/<feature>/<gate>/` directory containing a `findings.jsonl` counts as one invocation toward each persona that appears in that gate's findings. The 45-window is a global most-recent-by-`run.json.created_at` cap.

**No composite score.** Three independent rate columns + total + avg cost + run state.

### Run state machine (M4: 7 states, includes `silent`)

Each artifact directory contributes to (persona, gate) row(s) in one of seven states. The state determines which totals/rates the directory feeds. **`total_tokens` denominator is the cost window (independent of value-window per M3) — the ✓ in this column means "if cost data exists for this dispatch, it's counted in the cost-window aggregate."**

| `run_state` | Trigger | Counts toward `runs_in_window` (value) | Counts toward cost-window | Counts toward judge-retention | Counts toward downstream-survival | Counts toward uniqueness |
|---|---|---:|---:|---:|---:|---:|
| `complete_value` | All four artifacts present + valid (raw/, findings.jsonl, survival.jsonl, run.json), persona is in findings.jsonl `personas[]` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `silent` (M4) | All four artifacts present + valid; persona has `participation.jsonl` row with `status: ok` AND `findings_emitted: 0` (ran successfully, raised nothing) | ✓ | ✓ | ✓ (numerator = 0, denominator includes emitted bullets) | — (no findings to address downstream) | — (no findings to be unique) |
| `missing_survival` | Raw + findings + run present; survival.jsonl missing or empty | ✓ | ✓ | ✓ | — (excluded from denominator) | ✓ |
| `missing_findings` | Raw + run present; findings.jsonl missing | ✓ | ✓ | — (excluded; emitted-only ratio meaningless without retention numerator) | — | — |
| `missing_raw` | Findings + run present; raw/ missing | ✓ | ✓ | — (excluded; can't count emitted bullets) | — | — |
| `malformed` | Any artifact exists but fails schema parse | ✓ | ✓ | — (excluded; data unreliable) | — | — |
| `cost_only` | Cost data exists (Agent dispatch in session JSONL) but no value artifact at corresponding `docs/specs/<feature>/<gate>/` directory | — (cost-window only) | ✓ | — | — | — |

The `run_state_counts` field on each output row makes the denominator transparent; A2 verifies. **Note:** `cost_only` rows do NOT count toward `runs_in_window` (the value-window denominator) per M3 — they're cost-window-only contributions. The dashboard tooltip on `runs_in_window` and on cost columns explicitly says "value-window: N directories; cost-window: M dispatches" since they're different counts.

### Survival semantics — stated honestly

- **judge_retention_ratio**: this is a **compression ratio**, not a survival rate. Judge can merge multiple bullets into one finding (low ratio doesn't mean "low quality") OR split one bullet across findings (high ratio doesn't mean "high quality"). Renamed in v4 to avoid stakeholder overinterpretation.
- **downstream_survival_rate**: a true survival rate — "of this persona's findings that survived Judge clustering, what fraction were addressed in the next pipeline artifact?" Uses `outcome == addressed` from `survival.jsonl` (the only outcome value indicating actual pickup; other values: `not_addressed`, `rejected_intentionally`, `classifier_error`).
- **Downstream timing caveat:** if `survival.jsonl` doesn't exist yet for a row's gate (e.g., spec-review survival is computed only when `/plan` runs), the row sits in `missing_survival` state — counted in retention denominators but excluded from downstream denominators. Low downstream-survival is NOT the same as "rejected"; it may mean "not yet evaluated." Dashboard tooltip explains.

### Cost attribution — dependent on Phase 0 spike Q1

Pseudocode:

```python
for parent_session_jsonl in walk("~/.claude/projects/*/*.jsonl"):
    for agent_dispatch in parent_session_jsonl:
        if agent_dispatch.tool_use.name != "Agent": continue
        persona = regex_extract_persona(agent_dispatch.tool_use.input.prompt)
        gate    = regex_extract_gate(agent_dispatch.tool_use.input.prompt)
        if not persona: persona = "<unknown>"   # description-invoked subagents (e.g., persona-metrics-validator)
        agentId = parse_agent_id_from_tool_result_trailing_text(agent_dispatch.tool_result)
        subagent_jsonl = "~/.claude/projects/<parent-proj>/<parent-session-uuid>/subagents/agent-<agentId>.jsonl"
        # Q1 resolution via A1.5: if total_tokens annotation == sum(subagent_jsonl.usage), use annotation (cheap).
        #                         else use sum(subagent_jsonl.usage) (canonical, per-message).
        # On A1.5 disagreement: build fails, /plan re-opens Q1.
        tokens  = canonical_token_source(agent_dispatch, subagent_jsonl)
        emit_per_persona_row(persona, gate, parent_session_uuid, tokens)
```

### Idempotency contract (A8 spec)

- Diff-stable fields (must match byte-for-byte across re-runs with no new source data): `schema_version`, `persona`, `gate`, `runs_in_window`, `window_size`, `run_state_counts`, `total_*`, `judge_retention_ratio`, `downstream_survival_rate`, `uniqueness_rate`, `avg_tokens_per_invocation`, `persona_content_hash`, `contributing_finding_ids` (sorted), `truncated_count`, `insufficient_sample`.
- Intentionally-volatile fields (excluded from idempotency check): `last_artifact_created_at` (sourced from MAX `run.json.created_at` of contributing artifact directories, **truncated to date-minute**; NEVER file mtime).
- **Δ1 — `window_start_artifact_dir` removed** in v4.1: leaked adopter project + feature + gate names; redundant with `(persona, gate)` row key.
- Floats serialized as `round(x, 6)` to avoid `0.6590…1` drift.
- JSON serialization uses `sort_keys=True` to avoid dict insertion-order drift.
- Rows sorted by `(gate, persona)` for deterministic ordering.

### Window: 45 (persona, gate) artifact directories

- Reset condition: persona's `personas/<gate>/<name>.md` **content hash** changes. **Best-effort:** the row marks the new current hash; historical attribution is approximate (we don't know which old directories used the old vs new persona content). Window starts accumulating fresh data under the new hash; old data may persist transiently in the window denominator until rolled out by 45 new invocations.
- Window applies independently per (persona, gate).

### File concurrency

- `compute-persona-value.py` writes via tmp + `os.replace` — atomic on POSIX and Windows.
- Readers (dashboard, `/wrap-insights`) tolerate parse errors: malformed JSONL line → skip with one-line warning, do not abort.
- Cross-project / cross-machine race: **last-writer-wins, documented.** No false-confidence freshness check (the v3 `last_seen` comparison was flagged as unreliable by Codex round-3). If two `/wrap-insights` invocations race, both produce valid full snapshots from the same source data; the later write wins. Adopters running multi-machine should treat the JSONL as machine-local (it's gitignored anyway — see Multi-machine sync below).

### Multi-machine sync semantics

`dashboard/data/persona-rankings.jsonl` is gitignored. Each machine maintains its own window over its own `~/.claude/projects/`. Cross-machine aggregation is OUT OF SCOPE for v1 — adopters running MonsterFlow on multiple machines see machine-local data on each. Documented; not a defect.

## Edge Cases

| ID | Case | Behavior |
|----|------|----------|
| e1 | Persona with `runs_in_window < 3` | Row written with `insufficient_sample: true`. Dashboard renders rate cells as "—" (not opacity-dimmed numbers). Sort places nulls at bottom always. Omitted from `/wrap-insights` top/bottom lists. |
| e2 | Persona prompt changed | Detect via content-hash. **Best-effort window reset:** current row marks new hash; historical data may persist transiently in denominator until window rolls out (we don't know which historical directories used the old vs new content). Documented honestly; A4 weakened from v3. |
| e3 | `findings.jsonl` malformed at compute time | Mark that artifact directory as `run_state: malformed`; skip findings counts for that directory; cost still counted; one-line stderr warning (allowlist-scrubbed). |
| e4 | `persona-rankings.jsonl` malformed at read time | Dashboard + `/wrap-insights` skip the malformed line, render the rest, print one-line warning. |
| e5 | Two `/wrap-insights` race on the same JSONL | Atomic write via tmp + `os.replace`. Last-writer-wins, documented; no freshness-check (was unreliable in v3). |
| e6 | Stale data (no `/wrap-insights` run in 14+ days) | Dashboard shows stale-cache banner with last refresh timestamp. No fallback action. |
| e7 | Persona file deleted from `personas/` | Rows for that persona remain in JSONL until window rolls out, but `persona_content_hash: null`. Dashboard renders deleted personas with strikethrough. |
| e8 | `findings.jsonl` exists but lacks `personas[]` (legacy schema) | Mark `run_state: malformed`; skip with allowlist-scrubbed warning. Excluded from rates. |
| e9 | Persona in roster files but NOT in JSONL ("never run") | Dashboard renders "(never run)" row from `persona-roster.js`. `/wrap-insights` lists under "never run this window: ..." per gate. |
| e10 | Persona's `total_emitted == 0` | `judge_retention_ratio = null`. Cell renders as "—". `insufficient_sample: true`. |
| e11 | Persona's `total_judge_retained == 0` (downstream + uniqueness denominators are 0) | `downstream_survival_rate` and `uniqueness_rate` = null. Cells render as "—". |
| e12 | Fresh-install adopter with zero historical data | Dashboard tab renders empty data area + full "(never run)" roster from `persona-roster.js`. Banner: "No data yet. Run `/spec-review`, `/plan`, or `/check` then `/wrap-insights` to populate." A11 explicitly excludes this case from its outcome assertion. |

## Acceptance Criteria

| ID | Criterion | Verification |
|----|-----------|--------------|
| **A0** | Phase 0 spike preliminary findings persisted; remaining open Q1 forced by A1.5 | `tests/test-phase-0-artifact.sh` asserts: (a) spec contains `## Phase 0 Spike Result` heading; (b) section names linkage field (`agentId`); (c) `tests/fixtures/persona-attribution/` exists with ≥1 `.jsonl` validating against `schemas/persona-rankings.allowlist.json`. |
| **A1** | Per-persona cost = sum of subagent rows (exact equality) | For fixture: `sum(per_persona_tokens across all gates) == sum(usage rows from subagents/agent-*.jsonl)` exactly. Diagnostic columns `orchestrator_tokens` and `unattributed_tokens` reported but not constrained. |
| **A1.5** | Parent annotation cross-checks subagent transcript sum (forcing function for spike Q1) | For every Agent dispatch in fixture: `total_tokens` from parent's tool_result trailing text == `sum(usage.input_tokens + usage.output_tokens)` from `subagents/agent-<id>.jsonl`. **On agreement:** parent annotation is canonical (cheap). **On disagreement:** A1.5 fails the build, `/plan` re-opens Q1 and switches `compute-persona-value.py` to subagent-canonical reads. Permanent test (catches future Anthropic format drift). |
| **A2** | Three rates + run_state_counts computed | `persona-rankings.jsonl` rows have `judge_retention_ratio`, `downstream_survival_rate`, `uniqueness_rate` ∈ [0.0, 1.0] OR null (per e10/e11). `run_state_counts` totals match `runs_in_window`. State denominator semantics from §Data table verified by counting fixture directories per state. Rows with `runs_in_window < 3` carry `insufficient_sample: true`. |
| **A3** | Cross-project aggregation works (programmatic) | `tests/fixtures/cross-project/` contains two synthetic project trees. `tests/test-compute-persona-value.sh` invokes `compute-persona-value.py --scan-projects-root <fixture-A> --scan-projects-root <fixture-B>` and asserts output JSONL contains data drawn from both roots. Cascade tested via cwd-only path, fixture-config path, and `--scan-projects-root` path. |
| **A4** | Content-hash window reset (best-effort) | Test: (1) seed N invocations; (2) modify persona file body; (3) run one fresh dispatch; (4) re-run compute. Assert `persona_content_hash` updated to new value AND `contributing_finding_ids[]` includes only post-edit findings (pre-edit IDs cleared from drill-down). Window denominator is best-effort (may include transient pre-edit residue); test does NOT assert `runs_in_window: 1` (would require dispatch-time hash capture, deferred to v1.1). |
| **A5** | Dashboard tab renders correctly | "Persona Insights" tab present; sortable; separate columns for judge_retention_ratio, downstream_survival_rate, uniqueness_rate, total_tokens, avg_tokens_per_invocation, run_state; insufficient-sample rate cells render as "—"; nulls always sort to bottom; deleted personas strikethrough; "(never run)" rows from `persona-roster.js`; warning banner present. Loaded under `file://`. |
| **A6** | `/wrap-insights` text section renders | Output includes "Persona insights (last 45 (persona, gate) directories, all discovered projects)" with top + bottom 3 per gate × per dimension. Cost ranking uses `avg_tokens_per_invocation`, not totals. When fewer than 3 qualify: "(only N qualifying)" annotation. v1 stays static (no deltas). |
| **A7** | Edge cases covered by tests | `tests/test-compute-persona-value.sh` validates e1–e12 + Project Discovery cascade + drill-down `contributing_finding_ids[]` populated correctly + soft-cap behavior (51st ID rolls to `truncated_count`) + `--scan-projects-root` opt-in (default off). |
| **A8** | Idempotent refresh | Diff `persona-rankings.jsonl` after two consecutive `compute-persona-value.py` runs with no new source data: byte-for-byte identical excluding `last_seen`. JSON serialization uses `sort_keys=True` AND `round(x, 6)` for floats. Diff-stable allowlist documented in §Idempotency contract. |
| **A9** | Privacy: gitignore + fixture path enforcement | `git check-ignore docs/specs/<feature>/spec-review/findings.jsonl` returns 0 (ignored). Same for `dashboard/data/persona-rankings.jsonl` and `dashboard/data/persona-roster.js`. **Plus:** `tests/fixtures/persona-attribution/` is COMMITTED but every file in it must validate against `schemas/persona-rankings.allowlist.json`. Test asserts both. |
| **A10** | Privacy: allowlist enforcement (replaces canary) | `tests/test-allowlist.sh` asserts: (a) `dashboard/data/persona-rankings.jsonl` rows have ZERO fields outside `schemas/persona-rankings.allowlist.json`; (b) `tests/fixtures/persona-attribution/*.jsonl` rows have ZERO fields outside the same allowlist; (c) stderr/stdout from `compute-persona-value.py` (captured during the test run) contains zero matches for `LEAKAGE_CANARY_xyz123` (a deliberate canary written into a fixture finding title — verifies safe_log() scrubs); (d) the deliberate-failure fixture `tests/fixtures/persona-attribution/leakage-fail.jsonl` (which DOES include a forbidden field) makes the allowlist test fail when run alone (proves the test catches violations). |
| **A11** | Spec-level outcome criterion | After first `/wrap-insights` run on a project with **at least one** `findings.jsonl` row, `persona-rankings.jsonl` contains ≥1 row per **distinct (persona, gate) pair present in the source `findings.jsonl[s]`**. Fresh-install adopter case (zero data) is e12, NOT a failure of A11 — A11's precondition is "at least one source row exists." |

## Build-time clarifications (appended at /build, not re-litigated)

These pin ambiguities surfaced by spec-review and `/check` reviewers. They tighten edge-case behavior without re-opening MVP scope.

- **D5 — Window rollover = full rebuild.** The JSONL is fully rebuilt every `compute-persona-value.py` run by walking the most-recent-45-per-(persona,gate) source window. No append path exists. Atomic write via `tmp + os.replace`. This is the only contract consistent with A8 idempotency.
- **D6 — Schema migration v1 → v1.1.** v1.1 release notes will instruct `rm dashboard/data/persona-rankings.jsonl` before upgrade. v1 readers consume only `schema_version: 1` rows. v1.1+ readers regenerate from source on first run regardless of preexisting JSONL. A12 asserts `compute-persona-value.py` refuses to read a JSONL row whose `schema_version != 1` (logs warning, treats as cache miss, regenerates).
- **D7 — `participation.jsonl` precondition for `silent` state.** When `participation.jsonl` is missing or malformed for an artifact directory, fall through to the existing state machine: treat as `complete_value` if other artifacts validate, else `missing_*`. A persona that ran successfully but produced zero findings without a `participation.jsonl` row gets bucketed as `complete_value` with `total_emitted: 0` (already covered by e10).
- **D8 — `silent` state retention semantics.** Silent state contributes (0, 0) to retention — null per e10 rule. The `silent_runs_count` field surfaces volume separately.
- **D9 — Cost-window cap = 45.** Explicit field `cost_window_size: 45` parallel to `window_size: 45`. Both default to 45; both clamp identically.
- **D10 — Multi-persona finding survival counts +1 each.** A finding with `personas: [scope-discipline, edge-cases]` and `outcome: addressed` increments downstream-survival for BOTH personas. No fractional credit.
- **D11 — Bullet-counting regex pinned.** Top-level emitted-bullet regex: `^[-*] ` (zero leading whitespace, dash or star, single space). Excludes `^  - `, `^ - `, `^\d+\. `, and any line under `## Verdict` heading. Extraction is line-oriented with a state machine tracking current `## Heading`.
- **D13 — Persona-content-hash normalization.** `persona_content_hash = "sha256:" + sha256(unicodedata.normalize('NFC', text).encode('utf-8').rstrip(b'\n') + b'\n').hexdigest()`. Trailing whitespace within lines is significant; trailing newlines normalize to exactly one; BOM stripped before normalization.
- **Bundle architecture — two files retained.** Spec calls for `persona-rankings-bundle.js` + `persona-roster.js` as two separate `<script src>` tags. Plan D1 considered a single combined `persona-insights-bundle.js`. Implementation kept the two-file pattern: both atomic-written and the dashboard's `__PERSONA_BUNDLES_LOADED` flag handles partial load. Combined-bundle migration is a v1.1 cleanup, not a v1 ship blocker.

## Open Questions

1. **Spike Open Q1 — canonical token source** (parent annotation vs subagent transcript). Forced by A1.5: on agreement, parent annotation is canonical; on disagreement, A1.5 fails build and `/plan` re-opens.
2. **Phase 0 spike-failure path:** if spike turns up clean linkage (current evidence says yes), v1 ships as-is. If `/plan` discovers linkage breaks under load, **logging-shim path is a separate spec**. Abort threshold: `compute-persona-value.py` exits non-zero unless `--best-effort` is passed when fewer than 99% of Agent dispatches with persona prompts resolve to `(agentId, persona, gate, tokens)`.
3. **Per-dispatch hash + tool_use_id capture (v1.1+):** the proper fix for invocation-level metrics + content-hash boundary. Adds `agent_tool_use_id` and `persona_content_hash` to `findings.jsonl` / `run.json` at emit time. Out of scope here; tracked in BACKLOG.

## Spec Must-Fixes M1–M8 — applied in v4.2 from `/check`

| M | Section affected | Change | Driving source |
|---|------------------|--------|----------------|
| M1 | §Integration / Files modified | `compute-persona-value.py` imports `session_cost` via `importlib.util.spec_from_file_location` (hyphenated filename can't be bound via `sys.path` alone — empirically verified) | Codex |
| M2 | §Integration / Files created | Replace `jsonschema.validate` with stdlib allowlist validator (~30 lines); `jsonschema` is undeclared dep (verified missing on this machine) | Codex |
| M3 | §Summary + §Run state machine + §Data row schema | Cost and value are **two honestly separated signals** — cost windows over Agent dispatches per (persona, gate); value windows over 45 artifact directories. Different denominators. New `cost_runs_in_window` field. Per-dispatch join key is v1.1+ scope | Codex |
| M4 | §Run state machine + §Data row schema | Add 7th `silent` state (status:ok, findings_emitted:0); read `participation.jsonl`. New `silent_runs_count` field. Silent personas no longer misclassified as "never run" | Codex |
| M5 | §Project Discovery / CLI surface | Drop `--list-projects` (privacy contradiction with counts-only telemetry); fold use case into `--dry-run`. CLI now 5 flags + the new `--confirm-scan-roots` from M6 = 6 total | Codex + scope-discipline (convergent) |
| M6 | §Project Discovery / CLI | Add `--confirm-scan-roots <dir>` (repeatable) non-interactive companion — tmux pipe-pane / `dev-session.sh` defeats interactive prompt; without this Justin hits silent refusal day-one. Self-diagnostic stderr message on non-tty | risk |
| M7 | §Privacy salt section | Validate salt on read (32 bytes, non-zero, perms 0o600); regenerate-and-clear-rankings on failure; first-run race uses `O_CREAT \| O_EXCL` | risk |
| M8 | §Integration / Files created | Split `tests/test-allowlist.sh` into normal + `tests/test-allowlist-inverted.sh`; inverted asserts non-zero exit AND specific stderr message (avoids "crash falsely passes" bug) | testability |

## Spec Deltas Δ1–Δ6 — applied in v4.1 from `/plan` design synthesis

| Δ | Section affected | Change | Driving persona(s) |
|---|------------------|--------|--------------------|
| Δ1 | Data row schema | Dropped `window_start_artifact_dir` field — leaked adopter project + feature + gate names; `(persona, gate)` row key suffices | security |
| Δ2 | Data row schema | Renamed `last_seen` → `last_artifact_created_at`; truncated to **date-minute** (originally hour per security; relaxed to minute per Justin's call — within-hour activity not a concern; minute precision improves dashboard "refreshed today" UX without weakening A8 idempotency in practice) | security + api + Justin |
| Δ3 | Data + Privacy | `contributing_finding_ids[]` are per-machine SALTED (`sha256(salt \|\| normalized_signature)[:10]`); salt at `~/.config/monsterflow/finding-id-salt`; cross-machine ID stability NOT a v1 feature | security |
| Δ4 | Project Discovery telemetry | Counts-only stderr (`sources: cwd:1, config:M, scan:K`); paths only in interactive prompt + `MONSTERFLOW_DEBUG_PATHS=1` env (logs to `~/.cache/monsterflow/debug.log`) | security + api |
| Δ5 | Project Discovery tier 3 | First-use interactive `scan-roots.confirmed` flow; non-tty refuses; `.monsterflow-no-scan` per-project sentinel | security |
| Δ6 | Integration files modified | DO NOT modify `scripts/session-cost.py`; `compute-persona-value.py` imports `PRICING`/`entry_cost` via `sys.path` insert | integration |

## Spec Review Round 1 + 2 + 3 — Resolved Concerns

**Round 1** (`spec-review/findings-2026-05-04T01-37-36Z.jsonl`, 23 clusters): scope was combined #1+#3; v2 narrowed to instrumentation-only.

**Round 2** (`spec-review/findings-2026-05-04T02-12-25Z.jsonl`, 29 clusters): 7 schema-deep blockers → v3 inline edits closed all 7.

**Round 3** (`spec-review/findings.jsonl`, 32 clusters): 6/6 primary reviewers PASS or PASS WITH NOTES with 0 critical; Codex FAIL with 5 simplification-shaped blockers + 6 majors → **v4 (this revision) applies them all**:

| Round-3 Codex Blocker | v4 Resolution |
|---|---|
| Cost/value join under-specified | Declared v1 = "best-effort aggregate by **artifact directory**", not invocation. Window unit redefined; per-dispatch join deferred to v1.1 backlog. |
| Content-hash reset not implementable from current state | e2 + A4 weakened to "best-effort"; documented honestly that historical attribution is approximate; per-dispatch hash capture moved to v1.1 backlog. |
| Run states unspecified | Added `run_state` enum + `run_state_counts` row field; state machine table in §Data defines which states count toward which denominator. |
| Bullet-counting is compression ratio, not survival | Renamed `judge_survival_rate` → `judge_retention_ratio`. Documented explicitly that this is NOT survival. |
| Privacy tests too shallow | A10 rewritten as allowlist enforcement against `schemas/persona-rankings.allowlist.json`; new `tests/test-allowlist.sh`; `safe_log()` wrapper in `compute-persona-value.py`; deliberate-failure fixture. |
| Project Discovery over-broad for public release | Defaults flipped: cwd-only + explicit config; `~/Projects/*` scan moved to opt-in `--scan-projects-root` flag. Telemetry mandatory. |
| `run.json` location not defined | §Integration cites `docs/specs/<feature>/<stage>/run.json` (created by existing persona-metrics directive). |
| Freshness race insufficient | Removed false-confidence check; documented last-writer-wins explicitly. Multi-machine sync stated as machine-local v1. |
| Totals without averages awkward for cost | Added `avg_tokens_per_invocation` derived field; cost ranking uses average not total. |
| Downstream survival timing unspecified | Added `missing_survival` run_state + tooltip explaining low downstream may mean "not yet evaluated." |

| Round-3 Convergent Major | v4 Resolution |
|---|---|
| JS hybrid roster impossible under `file://` | `compute-persona-value.py` emits `persona-roster.js` sibling; dashboard reads via `<script src>`. |
| `survival.jsonl` no `kept` value | Spec uses `outcome == addressed` only (one-line fix). |
| `contributing_finding_ids[]` no cap | Soft-capped at most-recent 50 + `truncated_count` field. |
| Persona-author exposure via rendered output | Warning banner above dashboard table. |

| Round-3 Polish | v4 Resolution |
|---|---|
| `XDG_CONFIG_HOME` respect | Cascade tier 2 uses `${XDG_CONFIG_HOME:-$HOME/.config}/monsterflow/projects`. |
| `sort_keys=True` for A8 | §Idempotency contract specifies. |
| A11 fresh-install degradation | A11 precondition explicitly "at least one source row exists"; e12 covers fresh-install. |
| A11 underspecified boundary | Reworded to "distinct (persona, gate) pairs present in source findings.jsonl[s]." |
| A1.5 forcing function | A1.5 explicitly fails the build on disagreement. |
| A4 contributing_finding_ids cleared | A4 asserts pre-edit IDs cleared from drill-down. |
| `/wrap-insights ranking` bare-arg dropped | Removed from scope; one render surface fewer. |
| `schema_version` field on rows | Added (`schema_version: 1`). |
| Project Discovery telemetry | Mandatory stderr line on every invocation. |
| Bullet definition (top-level only, no Verdict) | §Approach spelled out: "lines starting with `- ` or `* ` at first-column indent" under specific headings, exclude Verdict + nested + numbered. |
| Schema example denominator annotations | Inline JSONC comments on `judge_retention_ratio` and `downstream_survival_rate` showing each denominator. |
| Null-rate sort position | Locked: nulls always sort to bottom. |
| Worktree dedup | Project Discovery dedupes by absolute `realpath` (handles worktrees per Q2 closure). |
| Persona contributors' data lifecycle doc | Will be addressed in `docs/persona-ranking.md` (out of scope here; opens a docs issue post-merge). |
