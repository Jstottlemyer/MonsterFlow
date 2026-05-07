---
name: pipeline-iterative-resolution-loops
description: Generalize the security-axis 3-attempt counter to all blocking finding-axes; user-selectable count; integrity-class exempt. Self-healing pipeline as a feature.
created: 2026-05-07
status: draft
session_roster: defaults-only (no constitution)
gate_mode: permissive
gate_max_recycles: 2
tags: [pipeline, integration, scalability, security]
---

# Pipeline Iterative Resolution Loops Spec

**Created:** 2026-05-07
**Constitution:** none — session roster only
**Confidence:** Scope 0.95 / UX 0.92 / Data 0.92 / Integration 0.92 / Edges 0.90 / Acceptance 0.92

> Session roster only — run /kickoff later to make this a persistent constitution.

## Summary

Replace v0.9.0's hardcoded-block invariants on **finding-class** axes (security, NO_GO verdict, architectural) with a per-axis iterative-resolution counter. Each `/check` cycle that finds findings on the axis is one logged attempt. After N attempts (default 3, user-selectable), the axis bails. Counter resets on a clean cycle. Integrity-class blocks (malformed sidecar, schema mismatch) are EXEMPT — they signal the synthesizer is broken, not work-in-progress.

This generalizes the **security-axis 3-attempt counter** that was shipped inline in commit `d3a88fb` (and off-by-one corrected in this same session) to **all blocking finding-axes**, formalizes the pattern with schema + tests + frontmatter override + CHANGELOG, and adds a CLI surface (`--max-fix-attempts <axis>:<N>`).

**Why now:** the dynamic-roster-per-gate session demonstrated that hardcoded NO_GO blocks force a costly outer-loop iteration cycle (6 wasted autorun cycles, each catching real-but-progressively-deeper findings, with no opportunity for /build to attempt fixes between cycles). The "blockers are blockers" intent is preserved — they ARE blockers if unresolved after N attempts — but first-cycle halt was the wrong default. **Highlight as feature:** "self-healing pipeline — automatic 3-attempt resolution loops per blocking axis, audit-logged, configurable."

## Backlog Routing

| # | Item | Source | Routing | Reasoning |
|---|------|--------|---------|-----------|
| 1 | `pipeline-security-n-attempts` | BACKLOG.md | (a) In scope — supersedes | This spec is its broader generalization. |
| 2 | `pipeline-iterative-resolution-loops` BACKLOG entry | BACKLOG.md | (a) In scope — formalizes | Backlog → real spec. |
| 3 | `dynamic-roster-per-gate` (in flight) | docs/specs/ | (b) Stays | Sibling; this spec is the unblocker so dynamic-roster can pass /check. |
| 4 | All other BACKLOG items | BACKLOG.md | (b) Stays | Unrelated. |

## Scope

**In scope:**

- **Per-axis iterative-resolution counter** for the three finding-class axes:
  - `security` (already shipped + off-by-one corrected this session)
  - `verdict` (NO_GO synthesis verdict — already shipped this session)
  - `architectural` (class:architectural findings; reserved for v2 — code path defined but axis check deferred until class taxonomy lands as a first-class block axis)
- **Counter semantics:** each `/check` cycle that finds N>0 findings on the axis is one logged attempt. Strict-greater-than comparison (`new_attempts > max_attempts`) bails ONLY after `max` /build fix attempts have run between detections — so `max=3` means 3 actual /build fix cycles before bail.
- **Counter reset:** on a clean cycle for that axis (zero findings on the axis), counter file is removed and a `counter-reset` event is logged. Independent per axis.
- **Audit log:** `docs/specs/<feature>/.<axis>-attempts.log` — JSONL per attempt, schema includes `timestamp`, `run_id`, `axis`, `attempt`, `max_attempts`, axis-specific fields (`finding_ids` for security, `verdict` for verdict). Plus `counter-reset` event rows.
- **Counter file:** `docs/specs/<feature>/.<axis>-attempts` — single integer (the current count). Removed on reset.
- **User-selectable max per axis:**
  - **Constitution-level** (`pipeline-config.md`): `tier_policy.max_fix_attempts.<axis>: <int>` — project-wide default.
  - **Spec.md frontmatter**: `max_fix_attempts: {security: 3, verdict: 5}` — per-feature override.
  - **CLI flag**: `--max-fix-attempts <axis>:<N>` (repeatable) — per-run override. Refused in `$CI`/`$AUTORUN_STAGE` truthy env (mirrors `--force-permissive` env-refusal pattern).
  - **Env var fallback** (already shipped): `SECURITY_MAX_FIX_ATTEMPTS`, `VERDICT_MAX_FIX_ATTEMPTS`. Frontmatter overrides env; CLI overrides frontmatter.
- **Integrity-class EXEMPT:** integrity blocks (malformed sidecar JSON, schema mismatch, multi-fence detection, bound-check failures) halt immediately on first detection. No counter, no retry. Iterating on a broken parser doesn't fix it; it just burns tokens.
- **`cap_reached + NO_GO` is terminal:** if synthesis explicitly emits `cap_reached: true` alongside NO_GO, that's a deliberate "we've recycled enough at the gate level" signal — bail immediately, don't engage the verdict-axis counter. Honors the v0.9.0 `gate_max_recycles` invariant.
- **Schema:** `schemas/attempts-log.schema.json` (NEW) — JSONL row schema; CI lockstep guard. `schemas/spec-frontmatter.schema.json` extension — `max_fix_attempts` block.
- **Test fixtures:** A12-style matrix per axis: happy path (1 attempt, clean), partial-recovery (1 attempt then clean → reset event), cap-exhausted (4 attempts on max=3 → bail with "exhausted" message), counter-persists-on-integrity-block, counter-resets-on-go-with-fixes (verdict axis), env override, frontmatter override, CLI override, CLI refused in autorun env, multiple axes hit simultaneously (independent counters). Target: 30-50 fixtures.
- **CHANGELOG entry:** `[Unreleased]` → `## [0.10.0]` cut.
- **Documentation:**
  - `docs/index.html` — autorun section already mentions the iterative-resolution-loop story (shipped in this session); update with the broader axes.
  - `README.md` — add a "Self-healing pipeline" headline feature note.
  - Update `commands/check.md` — interactive parity; manual `/check` honors the same counter when invoked iteratively.

**Out of scope (deferred):**

- **Architectural-axis enablement.** The class taxonomy from v0.9.0 has `class:architectural` as a hardcoded block at the verdict-emission level (not the check.sh post-process level). Wiring the counter to architectural-class findings requires a touch of the synthesis prompt + verdict schema. Defer to v0.11.0 follow-up — the framework here supports it (just no axis check yet).
- **Build-stage attempt counter.** /build already has `build_max_retries` (default 3). Out of scope here — it's a different mechanism (test-failure retry, not finding-resolution iteration). Cross-reference only.
- **Per-finding-id deduplication.** Today the counter ticks on any /check cycle with N>0 findings on the axis. We could refine to "tick only when the SAME finding_id reappears" — but that requires fingerprinting findings durably, which is out of scope. Iterating on a similar-but-different finding still counts as a fix attempt.

## Approach

**Chosen approach (user-directed):** generalize the security-axis counter pattern (already shipped, off-by-one corrected) to all blocking finding-class axes, with constitution → spec.md → CLI override precedence (matching v0.9.0 `gate_mode`). Integrity-class exempt. Default count 3.

**Rationale:**

- **Why generalize the existing pattern (not invent a new one):** the security-axis counter is already in production and well-tested through 7 dynamic-roster-per-gate cycles. Reusing the shape minimizes code surface, test surface, and operator confusion.
- **Why integrity-class exempt:** integrity blocks come from synthesizer drift (malformed JSON, fake fences, bound-check failures). They indicate the synthesis prompt or parser is broken, NOT that the work is in-progress. Iterating on a broken parser would consume tokens without making progress. The right response is halt + investigate, not retry.
- **Why user-selectable per axis:** different axes have different cost/risk profiles. Architectural specs may want `verdict: 5` (expensive deep iteration); docs-only specs may want `security: 1` (cheap halt-on-anything). Per-axis configuration honors the v0.9.0 design philosophy that gate behavior should be configurable at three layers.
- **Why three layers (constitution → spec → CLI):** v0.9.0 just shipped this pattern for `gate_mode`; adopters already understand the precedence. Architectural specs genuinely need different counts than docs specs.

**Alternatives considered:**

- **Single global `MAX_FIX_ATTEMPTS`:** rejected — different axes have different cost/risk, and a single knob obscures the reasoning.
- **Per-finding-id counter:** rejected for v1 — adds finding-fingerprinting complexity; "any finding on this axis" is sufficient and matches the security-axis precedent.
- **Build-stage counter only:** rejected — that's a different mechanism (test retry) and doesn't address the /check halt-on-first-finding problem.
- **Architectural-axis enablement in v1:** rejected — class:architectural detection at the post-process level is a separate plumbing change worth its own iteration; the framework here is ready for it without blocking on it.

## Roster Changes

No roster changes. Current 19-persona roster covers the build:
- `data-model` — schema design (`.<axis>-attempts.log` JSONL schema; frontmatter `max_fix_attempts` block)
- `integration` — wiring the counter at multiple block sites in check.sh + interactive `commands/check.md`
- `scalability` — per-axis cost implications + counter file growth + GC
- `api` — CLI flag surface (`--max-fix-attempts`)
- `ux` — gate stdout messaging + audit log readability
- `security-architect` — verifying the carve-out for integrity-class is sound (security findings still get auditable resolution; the cap is a safety floor)
- `testability` — A12 matrix design

## UX / User Flow

### Default (no config)

```
$ autorun start
[autorun] check: 4 security finding(s); attempt 1/3 — logged to .security-attempts.log; continuing pipeline
[autorun] check: verdict=NO_GO; attempt 1/3 — logged to .verdict-attempts.log; continuing pipeline
[autorun] build: ... (attempts to address findings)
[autorun] check (cycle 2): 4 security finding(s); attempt 2/3 — continuing pipeline
[autorun] check (cycle 2): verdict=NO_GO; attempt 2/3 — continuing pipeline
... (after 3 build attempts) ...
[autorun] check (cycle 4): 4 security finding(s); 3 fix attempts exhausted (this is detection #4) — hardcoded block
```

### Spec-level override

```yaml
# In spec.md frontmatter
max_fix_attempts:
  security: 5      # raise: this spec needs more security iteration
  verdict: 2       # lower: fail fast on architectural disagreement
```

### CLI override (interactive only)

```bash
/autorun --max-fix-attempts security:5 --max-fix-attempts verdict:2
# Refused in autorun env (CI=true, AUTORUN_STAGE=anything)
```

### Counter reset on clean cycle

```
[autorun] check: 0 security finding(s) — clean axis; counter reset, .security-attempts removed (event logged to .security-attempts.log)
```

## Data & State

### `.security-attempts.log` / `.verdict-attempts.log` schema (JSONL)

Per-attempt row:
```json
{
  "timestamp": "2026-05-07T02:32:58Z",
  "run_id": "66f2e679-9383-4846-ae62-68c882f46ab6",
  "axis": "security",
  "attempt": 2,
  "max_attempts": 3,
  "sec_count": 4,
  "finding_ids": ["ck-a1b2c3d4e5", "ck-9f8e7d6c5b", "ck-deadbeef01", "ck-1234567890"]
}
```

For verdict axis, replace `sec_count` + `finding_ids` with `verdict: "NO_GO"`.

Reset event row:
```json
{
  "timestamp": "2026-05-07T02:45:12Z",
  "run_id": "<uuid>",
  "axis": "security",
  "event": "counter-reset",
  "reason": "clean-check"
}
```

### `spec.md` frontmatter additions

```yaml
max_fix_attempts:
  security: 3
  verdict: 3
  architectural: 3      # reserved for v2 architectural-axis enablement
```

### `pipeline-config.md` (constitution-level)

```yaml
tier_policy:
  # ... existing tier_policy keys ...
  max_fix_attempts:
    security: 3
    verdict: 3
    architectural: 3
```

### CLI

`--max-fix-attempts <axis>:<N>` — repeatable, parsed via `_max_fix_attempts.py validate-cli` (axis ∈ closed enum {security, verdict, architectural}; N is positive integer).

## Integration

### Files touched

**Schemas (W1):**
- `schemas/attempts-log.schema.json` (NEW) — JSONL row schema for both security and verdict axes; closed-enum `axis`; per-axis required fields.
- `schemas/spec-frontmatter.schema.json` (extension) — `max_fix_attempts` block; closed-enum keys; integer values.
- `schemas/pipeline-config.schema.json` (NEW or extension) — same `max_fix_attempts` block at constitution level.

**Counter logic (W2):**
- `scripts/autorun/check.sh` (extension) — already has security + verdict counters from this session; add architectural-axis hook (no-op stub for v1; full implementation deferred); read frontmatter + CLI for override; precedence: CLI > frontmatter > env > constitution > default 3.
- `scripts/_max_fix_attempts.py` (NEW) — reads spec.md frontmatter + pipeline-config.md + CLI; emits resolved `max_fix_attempts` per axis. AST-banlisted (no eval/exec/subprocess/socket) — same shape as `_policy_json.py`.

**Interactive parity (W3):**
- `commands/check.md` — Phase 0c reads `max_fix_attempts` resolved values; honors counter logic in iterative flow.

**Tests (W4):**
- `tests/test-attempts-counter.sh` (NEW) — A12-style matrix.
- `tests/test-attempts-log-schema.sh` (NEW) — schema validation against both axes.
- `tests/test-frontmatter-override.sh` (NEW) — spec.md `max_fix_attempts` resolves correctly.
- `tests/test-cli-override.sh` (NEW) — `--max-fix-attempts` parsing + autorun-env refusal.
- `tests/test-autorun-policy.sh` (extension) — update existing `test_check_security_findings_hardcoded_block` to assert the NEW counter behavior (3 attempts then bail), not the old AC#4 hardcoded behavior.

**Docs (W5):**
- `docs/index.html` — already mentions security counter; extend the autorun section to mention verdict-axis + architectural-axis (v2) + the broader spec.
- `README.md` — "Self-healing pipeline" headline feature.
- `CHANGELOG.md` — `[Unreleased]` → `## [0.10.0]`.
- `BACKLOG.md` — remove `pipeline-iterative-resolution-loops` (shipped); update `pipeline-security-n-attempts` to mark superseded.

### Dependencies

**Existing infrastructure (no changes):**
- `scripts/autorun/check.sh` security + verdict counters (already shipped this session; this spec formalizes + tests + adds frontmatter/CLI override).
- v0.9.0 `gate_mode` precedence pattern (constitution → spec → CLI) — we mirror it.

**No new external dependencies.**

## Edge Cases

1. **Counter file unwritable** (perms / full disk) → fall back to integrity block; do not silently continue. Already implemented for security; mirror for verdict.

2. **Log file unwritable** → same as #1: integrity block. Already implemented for both axes.

3. **Counter reset on integrity block** → DOES NOT reset. Integrity blocks indicate synthesizer drift, not security/verdict clearance. Persists counter for the eventual real cycle.

4. **Multiple axes hit simultaneously** (e.g., 4 security findings AND verdict NO_GO in same cycle) → both counters tick independently. Either axis bailing exits the pipeline; the OTHER counter's state is preserved.

5. **`cap_reached + NO_GO`** → terminal, NOT counter-engaged. Distinct from "regular NO_GO". This is the v0.9.0 `gate_max_recycles` mechanism saying "we've recycled enough times at the gate; further iterations wasted." The verdict counter is for the OUTER autorun loop; gate_max_recycles is for the INNER /spec-review/plan/check recycle within a single gate invocation.

6. **Frontmatter `max_fix_attempts: 0`** → effectively disables the axis (any finding on first cycle bails). Allowed (paranoid mode); test fixture covers it.

7. **Frontmatter `max_fix_attempts: 100`** → allowed (very-permissive mode); test fixture covers it. No upper bound — user is responsible for token cost.

8. **Negative or non-integer value** → schema rejects at config-load; halt with clear error.

9. **Unknown axis name in CLI** (`--max-fix-attempts foo:3`) → reject with "unknown axis 'foo'; valid: security|verdict|architectural"; exit 2.

10. **CLI in autorun env** (`AUTORUN=1` or `$CI` truthy) → refused; mirrors `--force-permissive` pattern. Acceptable error message at gate stdout.

11. **Counter file written by older check.sh version** (v0.9.x format) → backward-compatible read. No format change in v0.10.0; same single-int file.

12. **Spec.md edited mid-flight** (e.g., user changes `max_fix_attempts` between cycles) → resolver reads at each cycle; new value takes effect immediately. Counter state independent of max value (you can lower max even if counter is at higher value — bail fires immediately on next detection if `counter > new_max`).

13. **Concurrent access** — single-process per slug; no race risk. Documented assumption.

14. **Integrity-class hardcoded-block intent preserved** — explicitly call out in CHANGELOG that integrity-class blocks are NOT softened. Synthesizer drift is a halt-and-investigate signal, not a work-in-progress signal.

## Acceptance Criteria

A1. **Security-axis counter (already shipped, regression-tested):** counter ticks per /check cycle with N>0 security findings; bails when `attempts > max` (default 3). Trace: 1, 2, 3 continue; 4 bails.

A2. **Verdict-axis counter (already shipped, regression-tested):** same shape, applied to NO_GO verdict. Trace: 1, 2, 3 continue; 4 bails.

A3. **Architectural-axis stub:** code path exists; v1 emits no axis-block (deferred to v2 enablement). Test fixture asserts the path is wired but doesn't fire.

A4. **Per-axis independence:** counter for axis A does not affect counter for axis B. Test fixture: simultaneous security + verdict findings; each ticks independently.

A5. **Counter reset on clean axis:** zero findings on axis → counter file removed, reset event logged. Independent per axis.

A6. **Counter persists on integrity block:** integrity-class block (malformed JSON sidecar) does NOT reset any counter. Test fixture verifies.

A7. **Constitution-level override:** `pipeline-config.md` `tier_policy.max_fix_attempts.<axis>` resolves to runtime cap. Default 3 if absent.

A8. **Spec.md frontmatter override:** `max_fix_attempts: {security: N}` resolves and overrides constitution. Test fixture per axis.

A9. **CLI override:** `--max-fix-attempts <axis>:<N>` repeatable; resolves and overrides spec. Test fixture per axis.

A10. **Env var override (back-compat):** `SECURITY_MAX_FIX_ATTEMPTS=N`, `VERDICT_MAX_FIX_ATTEMPTS=N` continue to work. Precedence: CLI > frontmatter > env > constitution > default 3. Test fixture.

A11. **Autorun-env refusal:** CLI overrides refused in `$CI`/`$AUTORUN_STAGE` truthy env. Halt with clear error.

A12. **`cap_reached + NO_GO` terminal:** counter NOT engaged; bails immediately as before. Test fixture verifies.

A13. **Off-by-one correct:** `max=3` permits exactly 3 /build fix attempts before bail (NOT 2). Test fixture: 4-cycle simulation asserts cycles 1, 2, 3 each followed by /build invocation; cycle 4 bails.

A14. **Audit log schema:** JSONL rows validated against `attempts-log.schema.json`. Reset events validated separately. Test fixture: malformed row → schema rejection.

A15. **Audit log non-gitignored:** `.security-attempts.log` and `.verdict-attempts.log` are committable for audit-trail review. Test fixture: `git check-ignore` returns no match.

A16. **Counter file unwritable → integrity block:** filesystem failure halts run with clear error; no silent continuation.

A17. **Log file unwritable → integrity block:** same shape.

A18. **Frontmatter `0`** disables the axis (paranoid mode). Test fixture.

A19. **Frontmatter very-large value** (e.g., 100) is allowed. Test fixture asserts no clamp.

A20. **Negative / non-integer rejected at config-load.** Schema validation. Test fixture per error class.

A21. **Test matrix:** A12-style fixtures × A1–A20 assertions = 30-50 PASSes; deterministic; <10s wall-clock.

A22. **Schema lockstep CI guard:** `attempts-log.schema.json` + `spec-frontmatter.schema.json` + `pipeline-config.schema.json` all version-pinned; partial PR landings rejected.

A23. **CHANGELOG + README + docs/index.html updated** to document the broader feature; existing security-axis content preserved + extended.

A24. **`tests/test-autorun-policy.sh` `test_check_security_findings_hardcoded_block` test updated** to assert NEW counter behavior, not old AC#4. (Currently failing per /preship in this session.)

A25. **Pipeline cycle through itself:** this spec ships under v0.9.0+ defaults (permissive gates, security counter at 3 attempts, verdict counter at 3 attempts) AND its own broader counter once merged. First-cycle test: this spec's own /check cycles should converge in ≤3 attempts.

## Open Questions

None at confidence ≥ 0.90. Two minor items deferred:

- **Q-architectural-axis-enablement:** Wiring class:architectural to a counter requires touching the synthesis prompt + verdict schema. Out of scope for v1; defer to v0.11.0.
- **Q-per-finding-deduplication:** Counter ticks on any /check cycle with N>0 findings, not on per-finding-id reappearance. Refinement to fingerprint-based dedup is out of scope for v1.

## Sequencing Note

Ships unblocked. Security-axis counter is already in production (commit `d3a88fb` + this session's off-by-one fix). Verdict-axis counter is already in production (this session, post-shell-reviewer). This spec formalizes both + adds tests + frontmatter/CLI override.

**Critical sequencing constraint:** ship this BEFORE re-running autorun on `dynamic-roster-per-gate`. Otherwise dynamic-roster-per-gate continues to halt on AC#5 NO_GO without engaging the verdict counter. The two are causally linked — this spec is the unblocker.

**Sibling specs unaffected:** `monsterflow-pipeline-config-rename`, `pipeline-security-escape-hatches`, `pipeline-resolver-debugging`, `pipeline-rate-limit-resilience` — all independent.
