# V2 Review: autoship-outcome-instrumentation

**Date:** 2026-06-02
**Reviewers dispatched (agent_budget=3):** requirements (opus), gaps (sonnet), scope (sonnet)
**Codex:** SKIPPED — auth refresh token expired (refresh_token_reused). Run `codex login` to re-authenticate. V1's Codex findings (which V2 explicitly addresses) remain in `v1-raws/codex-adversary.md` for reference.
**Gate mode:** permissive (frontmatter)

---

## Overall health: **Good** — minor tightening; no blockers

V2 cleanly closes all 5 V1 blockers (B1-B5). All 3 Claude reviewers independently agreed: **no critical gaps blocking /blueprint.** Combined IC count: 8 items. Most are AC tightening, one is a real regression risk (gaps IC-1: helper re-raise affects an unrelated path) that needs scoping at /blueprint or inline.

V1 history preserved at `spec-review/v1-raws/` (4 files: requirements.md, gaps.md, scope.md, codex-adversary.md).

---

## Before You Build (0 items)

None.

---

## Important But Non-Blocking (8 items)

### IC-1 [gaps, architectural / major] — `append_event` re-raise regresses `cmd_render` path
**Most important non-blocker.** The spec changes `append_event` to re-raise on JSONL write failure. `append_event` has TWO callers: `cmd_log_event` (which `_emit_outcome_event` calls) AND `cmd_render` (called during `/spec`, `/blueprint`, `/check` gate renders). After the change, a permission error on the JSONL during gate-render will surface as a gate failure — regression in a path outside this spec's scope.

**Resolution:** scope the re-raise to `cmd_log_event` only via `append_event(..., raise_on_failure: bool = False)`. Spec should pin this constraint explicitly.

### IC-2 [gaps + requirements, contract / major] — `CANONICAL_SPEC` unset window
`CANONICAL_SPEC` is set at run.sh:740 but trap installed at line 683. Early-exit before 740 (e.g., `acquire_lock` fails) means trap fires with `CANONICAL_SPEC` unset → `--spec-path ""` → helper fails.

**Resolution:** in `_emit_outcome_event`, guard `[ -n "${CANONICAL_SPEC:-}" ] || return` (with WARN). Add to §Edge Cases.

### IC-3 [requirements, contract / major] — AC1 vs AC7 contradiction on helper-fails row count
AC1 asserts +1 row for all 6 fixtures including `helper-fails`. AC7 says helper failure produces no row. They contradict on the helper-fails fixture.

**Resolution:** split AC1 — "5 success fixtures → +1 each; helper-fails → +0 (covered by AC7)."

### IC-4 [requirements, contract / major] — AC8 grep scoping
`grep -F 'rc=$?' scripts/autorun/run.sh` is whole-file; passes even if rc=$? exists elsewhere but is missing from emission block.

**Resolution:** scope to function body: `awk '/^_emit_outcome_event\(\)/,/^}/' scripts/autorun/run.sh | grep -F 'rc=$?'`.

### IC-5 [requirements + scope, contract / major] — Trap install fold-vs-separate clarification
Bash EXIT traps replace, not stack. If existing 673-683 handler is on EXIT, MUST fold; if on TERM/INT/HUP, install separately.

**Resolution:** add to §Notes for /blueprint: "Verify existing handler's signal list before deciding fold vs separate."

### IC-6 [scope, contract / major] — `_extract_halt_stage` pattern verification
Spec acknowledges grep pattern is tentative. AC4 fixture is synthetic — even wrong format would pass test.

**Note from gaps O-2:** actual `log_run` at run.sh:514 emits `{"timestamp":...,"stage":"spec-review",...}`. Spec's pattern `'"stage": *"[^"]*"'` (zero-or-more spaces) DOES match. So this is verified, not gap. But AC4 fixture should match actual format.

**Resolution:** at /blueprint, lock fixture format to match `log_run`'s actual JSONL.

### IC-7 [requirements, contract / major] — AC11 partial-write boundary
"Simulate write failure" testable for pre-write failures, not mid-write (disk-full after partial bytes). Helper doesn't specify truncation.

**Resolution:** scope AC11 to "open/write-permission failures before any bytes written" (atomic-write requirement is overkill for personal tooling).

### IC-8 [requirements, tests / minor] — No AC asserts existing reasons still work
AC11/12 cover helper changes. No AC asserts `shipped`/`failed`/`cancelled` still pass post-change.

**Resolution:** add §Acceptance one-liner "existing helper tests must continue to pass" OR add AC13.

---

## Observations

- All 3 reviewers independently confirmed V1's F1/F2/F3 (gaps) are closed.
- Concurrent JSONL writes already handled via `fcntl.flock(LOCK_EX)` at helper line 221-227.
- `pr-open` backwards-compat is fine — no live consumer breaks.
- AC10 idempotency design is sound.
- Pitfall guards section pulled in the right memory entries.
- `OUTCOME_HELPER_OVERRIDE` is the correct testability seam.
- Scope growth (146→240 lines, 9→12 ACs) is proportionate and load-bearing.

---

## Reviewer Verdicts

| Persona | Verdict | Key Finding |
|---|---|---|
| requirements (opus) | PASS WITH NOTES | 6 AC-tightening items; no blockers |
| gaps (sonnet) | PASS WITH NOTES | IC-1 (re-raise regresses cmd_render) is the most important non-blocker |
| scope (sonnet) | PASS WITH NOTES | Scope growth justified; trap-fold decision needs lock-in at /blueprint |
| codex-adversary | SKIPPED | Auth expired (refresh_token_reused) — re-authenticate via `codex login` |

## Conflicts Resolved

No reviewer conflicts. Gaps and requirements both independently surfaced IC-1 (cmd_render regression) and IC-2 (CANONICAL_SPEC unset). Scope confirmed V2's scope growth is proportionate. All three converged on "PASS WITH NOTES, no blockers."

## Synthesized verdict

**V2 is approval-ready.** Zero blockers, 8 non-blocking tightening items. IC-1 is the only one with real downstream regression risk (helper change affects unrelated path); /blueprint should scope the re-raise to `cmd_log_event` only. The other 7 are AC tightening that /blueprint can fold in cleanly.

Codex re-auth recommended before /blueprint to restore adversarial coverage.
