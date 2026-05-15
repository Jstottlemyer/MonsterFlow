# Design — pipeline-pacing-and-prefill

**Stage:** /blueprint · iteration 1 · gate_mode: permissive (frontmatter)
**Dispatched:** api:opus, integration:sonnet, data-model:sonnet (budget=3; codex-adversary skipped per /blueprint default gate policy)
**Synthesizes:** spec.md iter2 + review.md iter1 + 3 design persona outputs

## Architecture summary

Five v0.14 UX-pacing items ship via three new artifacts (banner helper, ETA helper, mobile-verify skill) plus minimal-diff splices into eight existing slash commands and four autorun scripts. State surface is intentionally small: three sentinel files (one JSON, two literal markers), no new schemas, no new JSONL. All design personas converged on the same shape; one disagreement (ETA reader's data source) surfaced an honest scope-reduction (ETA ships fallback-only in v0.14).

## Key design decisions

### D1 — `scripts/_pipeline_banner.sh` is dual-mode (sourceable + executable) with positional args

**Source:** api (primary), integration (concurrence)

Helper exposes two subcommands: `_pipeline_banner.sh start <gate> <feature>` and `end <gate> <feature>`. Stdout-vs-stderr routing decided inside the helper via `${AUTORUN:-0}` — callers don't pass a flag. Heavy fields (cost, ETA, denominator) computed inside; optional `--cost <n>` / `--next <gate>` overrides exist for the rare pre-computed case (e.g., autorun pipeline state that already knows next gate). Same pattern as the existing `scripts/_gate_helpers.sh`.

**Bash 3.2 compatibility:** denominator from `pipeline_path` frontmatter via a `case` statement (no associative array). Stage-of-N counter passed in as positional arg or computed via running counter in env (`$PIPELINE_STAGE_NUM`).

Helper file structure includes a `## Wording Reference` section at the top documenting the canonical banner formats so commands/*.md can reference it with a one-liner instead of duplicating the format string.

### D2 — Mobile-verify uses exit-code-authoritative contract

**Source:** api

`commands/build.md` Phase 3 calls `~/.claude/skills/mobile-verify/scripts/verify.sh` via **deterministic path-based invocation**, not Skill-tool discovery. Exit codes are the contract surface:

- `0` — PASS
- `1` — CODE failure (compile error, runtime crash, smoke-scan match)
- `2` — INFRA failure (simulator unbootable, xcrun missing, runtime mismatch)

Stdout is human-readable detail; `/build` does NOT parse stdout for routing. SKILL.md exists for human-facing affordance/discovery; pipeline calls bypass discovery for determinism (per Codex CDX-10).

### D3 — Sidecar files at `docs/specs/<feature>/`

**Source:** data-model (primary), api (concurrence)

Three sidecars, two shapes:

- **`.compact-mode`** — bare literal (`probe` or `suppress`). Written once by `/blueprint` pre-flight after `claude-code-guide` consultation on OQ2. Defaults to `suppress` if file absent. One value to express → no JSON overhead.
- **`.last-compact-suggestion`** — JSON: `{"last_context_pct": int, "last_emit_ts": iso8601, "path": "A"|"B"}`. Written atomically via temp+mv. Banner emitter reads at every end-banner; suppresses re-emission if `last_context_pct` matches and `now - last_emit_ts < 600sec`. Fail-open on parse error (treat as no-prior-emission).
- **`~/.claude/.banner-disabled`** — user-global empty marker. Existence = opt-out. Suppresses ALL banner emission (including the `/compact` line).

**Filename canonical:** `.last-compact-suggestion` (drop the `-context-pct` suffix from the review's draft). JSON contents carry the context_pct field; filename stays compact.

### D4 — ETA ships fallback-only in v0.14

**Source:** integration (finding)

`dashboard/data/persona-rankings.jsonl` schema has no duration/timing field — it tracks value metrics (uniqueness, survival, load-bearing rates), not wall-clock times. Building a per-gate-median ETA against this schema would require inventing a field, which violates the persona-metrics contract.

**Decision:** `_pipeline_eta.py` returns hardcoded defaults always (spec=480, spec-review=360, blueprint=180, check=300, build=900 seconds). AC4 amends to test ONLY the fallback path. Real-data ETA is carved off as a v0.15 follow-up requiring a separate timing JSONL (probably hooked into session-cost.py's existing stage-timing tracking, since that already records gate boundaries).

This is an honest scope reduction. The spec promised "ETA from rankings history if present" — that promise can't be kept without schema changes. Better to ship fallback-only than to invent a field.

### D5 — `session-cost.py --cumulative-only --session-only` flag (additive)

**Source:** integration

Banner helper extracts cumulative cost via a new flag on the existing script: `session-cost.py --cumulative-only --session-only 2>/dev/null || true`. Returns a single dollar-amount integer (cents). On any error: omit cost field, banner emits without it, never crashes the gate. Adds ~10 lines to session-cost.py; doesn't break `/wrap` Phase 1's existing read pattern.

### D6 — *DROPPED post-spike (2026-05-14).*

Item 4 (tab-prefill / empty-Enter-default) was dropped after `claude-code-guide`
investigation revealed: (i) empty-Enter is harness-blocked, (ii) tab-prefill IS
a Claude Code feature but the suggestions are generated from Claude's response
context — slash commands cannot author them via any structured marker. The
`_pipeline_input.sh` parser becomes moot. Item 4 is now a CLAUDE.md
documentation entry per the revised spec.

### D7 — install.sh integration is automatic (glob-based)

**Source:** integration

Existing install.sh has a scripts glob (`scripts/*.sh`) that auto-symlinks all helpers to `~/.claude/scripts/`. New `_pipeline_banner.sh` and `_pipeline_input.sh` (if D6 ships) get picked up automatically. No install.sh entry needed.

For the mobile-verify skill: install.sh's skills wave needs verification. **OQ4 (carried from spec):** confirm `~/.claude/skills/` discovery works automatically when a new skill dir appears, or whether install.sh's skill-symlink wave needs an explicit entry. Resolved during T4 implementation.

### D8 — Codex skipped at /blueprint, runs at /check

Per /blueprint default gate policy (resolver emits `codex-adversary` bare but it's pass-through-unchanged at interactive /blueprint). Codex critique happens at /check Phase 2b instead, against the synthesized design.md. This is intentional — design synthesis benefits from a single coherent Claude pass; adversarial review against the design happens at the next gate.

## Implementation tasks

Three-wave plan; total 11 tasks. Wave-sequencer default precedence (data → UI → tests) honored: helpers (data + infra) ship in Wave 1, commands/autorun splice (UI/behavior) in Wave 2, tests + release artifacts in Wave 3.

| # | Task | Depends on | Size | Wave | Parallel? |
|---|---|---|---|---|---|
| T1 | Create `scripts/_pipeline_banner.sh` (start/end subcommands, dual-mode, case-statement denominator) | — | M | 1 | yes |
| T2 | Create `scripts/_pipeline_eta.py` (fallback-only per D4) | — | S | 1 | yes |
| T3 | Add `--cumulative-only --session-only` flag to `~/.claude/scripts/session-cost.py` | — | S | 1 | yes |
| T4 | Create `~/.claude/skills/mobile-verify/SKILL.md` + `scripts/verify.sh` + 3 test fixtures (`good/`, `bad/`, `infra/`) | — | M | 1 | yes |
| ~~T5~~ | *DROPPED post-spike: `_pipeline_input.sh` moot with Item 4 retired.* | — | — | — | — |
| ~~T5b~~ | *Folded into T6 (same agent owns CLAUDE.md doc append since it's a small surgical doc edit alongside the commands/*.md sweep)* | — | — | — | — |
| T6 | **Single agent, sequential, template-first** — Splice banner + input-grammar `(a/b/c)` into 8 `commands/*.md` (spec, spec-review, blueprint, check, build, wrap, preship, flow) AND append `## Tab-accept suggestions` paragraph to `CLAUDE.md`. NO `[default]` annotations. Procedure: apply to `commands/spec.md` FIRST as template; agent visually verifies result reads correctly; then proceeds through 7 remaining + CLAUDE.md in same pass. Total <15min. AC1 grep validates drift at end. | T1 | L | 2 | NO file-level parallelism within T6 (sequential); T6 still runs parallel with T7+T8 in Wave 2 |
| T7 | Add banner-emission to 4 `scripts/autorun/*.sh` (spec-review, design, check, build) — stderr emit when `$AUTORUN=1` | T1 | M | 2 | yes |
| T8 | Update `commands/build.md` Phase 3 with mobile detection (4-branch) + dispatch + CODE/INFRA retry split | T4 | M | 2 | yes (with T7) |
| T9 | Write test suite: `test-pipeline-banner.sh`, `test-input-grammar.sh`, `test-claude-md-tab-accept-pro-tip.sh`, `test-mobile-verify-{code,infra}-attempts.sh`, `test-banner-{standalone-mode,concurrent-worktrees,autorun-stderr}.sh`, `test-compact-prompt-path-{a,b}.sh`, `test-changelog-v0.14.0-entry.sh` (10 new files) | T1-T8 | L | 3 | yes |
| T10 | Update `tests/run-tests.sh` wiring + `CHANGELOG.md` v0.14.0 entry + `VERSION` bump to 0.14.0 | T9 | S | 3 | yes |
| T11 | Invoke `autorun-shell-reviewer` subagent on `scripts/autorun/*.sh` modifications BEFORE /build's pre-commit (AC15) | T7 | S | 3 | sequential after T7 |

**Wave 1** (5 tasks, all parallel) — foundations: helpers + skill. No dependencies.

**Wave 2** (3 tasks, partial parallel) — splice into commands + autorun + build.md. T6 depends on T1+T5; T7 depends on T1; T8 depends on T4. T6 and T7 can run side-by-side; T8 can run with both.

**Wave 3** (3 tasks, parallel) — tests + release artifacts. T9 depends on all of Wave 2; T10 depends on T9; T11 is a sequential post-step after T7 (per the established autorun-shell-reviewer pattern).

## Open Questions (carried to /check)

**OQ4 (spec) — `~/.claude/skills/` discovery for mobile-verify.** Confirm install.sh's skill-symlink wave handles new spokes automatically (glob over `~/.claude/skills/*/SKILL.md`), or whether each skill needs an explicit entry. Resolution path: grep install.sh during T4 implementation; if not glob-handled, add explicit entry in T10.

**~~OQ5~~** — *MOOT post-spike 2026-05-14. `_pipeline_input.sh` retired with Item 4.*

**OQ6 (new) — Path B `$5-boundary` throttling.** Spec spec'd Path B emits a one-liner when cumulative cost crosses $5. Should the same `.last-compact-suggestion` JSON sentinel throttle re-emission when context% changes but cost doesn't cross another $5? Lean: yes, throttle Path B with the same sentinel (path field distinguishes A vs B emissions). Confirm at /check.

**~~OQ7~~** — *RESOLVED 2026-05-14: append `pipeline-eta-from-timing-data` entry to `BACKLOG.md` during T10 (release-artifact wave). Entry points: `session-cost.py` stage-timing tracking, new `dashboard/data/gate-timing.jsonl`, `_pipeline_eta.py` real-data branch. Size estimate: S-M. v0.15 candidate.*

## Risk register

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| ~~R1~~ | *RESOLVED via spike 2026-05-14: harness IS unsupported. Item 4 dropped; replaced with CLAUDE.md doc entry. Risk eliminated by scope cut.* | — | — | — |
| R2 | mobile-verify detection (4-branch) misses a valid mobile project | medium | medium | **Two-part mitigation:** (a) constitution `stack: mobile` is always-on deterministic override — documented prominently in commands/build.md Phase 3 prose. (b) Soft warning when detection returns false BUT a Swift signal exists (`.swift` files present OR `Package.swift` present): emit `[mobile-verify] no app detected; if this should be mobile, set constitution stack: mobile` to /build's Phase 3 output. AC8 amends to assert this warning fires on swift-signal-without-mobile-product. Doesn't change /build behavior; creates discoverability that addresses the EXACT trigger (user didn't know the affordance existed). |
| R3 | Banner emission to stderr in autorun breaks an unknown fence-extractor stdout reader | low | high | T7 explicitly tests fence-extractor output integrity; AC18 asserts zero `[pipeline]` lines on stdout under $AUTORUN=1 |
| R4 | `.last-compact-suggestion` JSON parse error silently breaks throttling | low | low | Fail-open contract (D3) — parse error treated as no-prior-emission; throttling degrades gracefully |
| R5 | `session-cost.py --cumulative-only` flag conflicts with existing /wrap call | low | medium | Add flag as ADDITIVE; existing flagless invocation preserves /wrap's behavior; test by running /wrap unchanged after T3 |
| R6 | Wave 2's 8-file splice (T6) drifts: one file gets the new pattern, another keeps the old | medium | low | Splice is template-first (per memory `feedback_template_first_batching`) — apply to one file, get approval, batch remainder; AC1 grep catches drift |
| R7 | bash 3.2 incompatibility in `_pipeline_banner.sh` (e.g., `${arr[-1]}`, `declare -A`) | medium | medium | Explicit constraint per memory `feedback_negative_array_subscript_bash32`; test under `BASH=/bin/bash` |
| R8 | autorun-shell-reviewer (T11) flags blocking issues in scripts/autorun/*.sh and forces rework | medium | medium | This is the desired protection per CLAUDE.md — bake review iteration into Wave 3 budget; halt on High findings |

## Spec amendments inferred during synthesis

None. The spec iter2 (post /spec-review B1-B5, M1-M3, O1-O4) is fully implementable as written, modulo the four OQs surfaced above (all defer-to-/check cleanly).

## Codex critique placeholder

Skipped per /blueprint default gate policy. Codex runs at /check Phase 2b against this synthesized design.md and the spec.md together. Adversarial findings (if any) flow into the /check verdict sidecar.
