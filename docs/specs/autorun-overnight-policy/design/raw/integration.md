# Integration Analysis — Raw

### Key Considerations
1. **Two parallel state systems coexist** — existing `$ARTIFACT_DIR/state.json` (run.sh:36-44, build.sh:72-80) used for orphan detection (run.sh:93-118); new `queue/runs/<run-id>/run-state.json` for RUN_DEGRADED. Spec silent on whether per-item is deprecated. Risk: if `_policy.sh` writes only to per-run, resume semantics break.
2. **notify.sh integration cleaner than spec implies** — current consumes `$QUEUE_DIR/run-summary.md` (notify.sh:23) synthesized at run.sh:679-685. New morning-report is strict superset. Migration: produce JSON first, render MD, keep run-summary.md as symlink one release for back-compat.
3. **CODEX_HIGH_COUNT × RUN_DEGRADED gate clear, but site is buried** — single bypass at run.sh:555-559. Today's `merge-gate` failure writes failure.md and skips run-summary.md → notify.sh sends FAILED subject. New `pr-awaiting-review` state must NOT write failure.md.
4. **commands/check.md synthesis change is dual-mode and safe** — additive (OVERALL_VERDICT first line + JSON sidecar). Subtle: autorun grep at check.sh:226 + run.sh:246 (resume-skip) currently uses `NO-GO\|NO GO`. Spec AC#3 pins `NO_GO`. Greps need updating OR synthesis emits both.
5. **findings-emit unaffected** — `<feature>/check/findings.jsonl` vs `<feature>/check-verdict.json` — separate paths, separate consumers. No collision.
6. **doctor.sh pre-existing** — `set -uo pipefail` (no `-e`); new check fits existing probe pattern; no doctor.sh tests today.
7. **tests/run-tests.sh orchestrator** — `feedback_test_orchestrator_wiring_gap.md` memory: parallel /build agents write tests but forget the TESTS=() array. Add `test-autorun-policy.sh` between test-resolve-personas.sh and end (lines 21-43).
8. **AUTORUN_DRY_RUN=1 is spec's quietest hole** — each stage has dry-run early-return (spec-review.sh:27-37, check.sh:35-43, etc.). Spec doesn't say if policy fires in dry-run. Recommend (b): dry-run still constructs run-state.json + writes morning-report.json — dry-run becomes canonical AC#9 smoke.
9. **autorun-shell-reviewer expansion bounded** — current 13 pitfalls; +5 = 14-18 appended cleanly.
10. **queue/index.md + queue/run-summary.md orthogonal** — three artifact layers (per-item state.json, queue-level index/summary, per-run morning-report). One too many. Plan-stage decision: regenerate index.md to point to current, or accept duplication?
11. **Sourced-helper × set -e × trap risk** — every script has `set -euo pipefail`; build.sh and verify.sh install EXIT traps. Three failure modes: helper can't use own EXIT trap; policy_block returning nonzero without `|| true` kills caller before warn; flock not portable.
12. **`_codex_probe.sh` replaces inline checks at exactly two sites** — run.sh:394 (`elif command -v codex >/dev/null`); spec-review.sh has NO inline codex check (filtered at line 73). AC#11's "no inline command -v codex remains" is one-line replacement at run.sh:394.

### Options Explored
- **A — Replace per-item state.json everywhere**: breaks orphan detection. High cost. Rejected.
- **B — Keep both** ✅: per-item for resume, per-run for policy. Low cost.
- **C — Symlink run-summary.md → current/morning-report.md**: notify.sh works one release; macOS symlink flake under cp/git.
- **D — notify.sh reads JSON directly, drops run-summary.md** ✅: single source of truth. Breaks anyone tailing externally.
- **E — Dry-run exercises policy plumbing end-to-end** ✅: AC#9 testable without live claude. Stub updates needed.
- **F — Dry-run short-circuits policy**: smaller diff, can't validate headline behavior.
- **G — Synthesis emits both NO-GO and NO_GO**: greps + sidecar both work. Two normalizations in tree.
- **H — Update greps to match `NO-GO\|NO_GO`** ✅: single canonical token. One grep change per file.

### Recommendation
**Adopt B + D + E + H.**
1. Keep per-item state.json for orphan detection. Add per-run run-state.json for policy. Document two roles in defaults.sh header.
2. morning-report.json is single durable record; morning-report.md rendered from it. Replace run.sh:679-685 with morning-report.md write at new path; one-release back-compat symlink at queue/run-summary.md.
3. Dry-run stubs participate in policy plumbing. Each stage's `AUTORUN_DRY_RUN=1` branch sources `_policy.sh`, sets `AUTORUN_CURRENT_STAGE`, writes deterministic OVERALL_VERDICT first-line + check-verdict.json sidecar. Makes tests/autorun-dryrun.sh canonical AC#9 smoke.
4. Normalize NO-GO ↔ NO_GO at producers and consumers. Synthesis emits NO_GO; update check.sh:226 grep to `NO-GO\|NO_GO\|NO GO` and run.sh:246 likewise.
5. flock portability check at /plan time. If unavailable on macOS bash 3.2, fall back to mkdir-based mutex.
6. `_policy.sh` API: `policy_block` returns 1 but does NOT call exit. Callers `policy_block ... || true` to defer exit. Document in helper header.

### Constraints Identified
1. bash 3.2: no assoc arrays, no `${arr[-1]}`, no `wait -n` — parallel arrays + function dispatch
2. set -e propagation through sourced helpers — caller's trap wins
3. flock may not exist on macOS — verify before locking primitive
4. `set -uo pipefail` in doctor.sh (no `-e`) — defensive pattern
5. detect_orphan reads per-item state.json with python3 (run.sh:97) — `_json_get` parity
6. AUTORUN_DRY_RUN smoke at tests/autorun-dryrun.sh — only test exercising full pipeline
7. `flock -n queue/.autorun.lock` external launcher (run.sh header) — adding slug-scoped lockfile nests cleanly
8. **commands/check.md is consumed by both interactive AND autorun, but autorun synthesis prompt is INLINE in check.sh:180-193, NOT loaded from commands/check.md.** Spec's "synthesis prompt update" needs to land in TWO places.

### Open Questions
1. Where does autorun-side synthesis prompt update land? Both `commands/check.md` AND `scripts/autorun/check.sh:180-193`.
2. Does morning-report.md replace queue/run-summary.md immediately, or coexist?
3. flock availability on dev box?
4. Should `pr-awaiting-review` write failure.md? Recommend: write run-summary.md item-level + set notify subject from morning-report.json.
5. tests/autorun-dryrun.sh assertions — add queue/runs/current/{run-state,morning-report}.json + RUN_DEGRADED derivation
6. queue/index.md vs morning-report.md overlap — three artifacts, one too many

### Integration Points
- run.sh: --mode parse near :12; run-id+lockfile near :608; gate at :555-559; final write at :679-685
- check.sh: sidecar read at :226 (replaces grep); inline synthesis prompt at :180-193
- build.sh: branch reset at :232; ALSO run.sh:280-288 has destructive autorun-branch reset to BASE_REF (not enumerated in spec but should be covered)
- verify.sh: classify at :121-131
- spec-review.sh: NO inline codex check today (only run.sh:394)
- _policy.sh sourced into 5 callers each with `set -euo pipefail` + EXIT traps
- _codex_probe.sh single consumer at run.sh:394
- notify.sh body at :18-39 (read morning-report.json)
- commands/check.md synthesis at :86-176
- AUTORUN_CURRENT_STAGE: new env var set by run.sh's update_stage() at :61-64
- Auto-merge gate: existing `if [ "$CODEX_HIGH_COUNT" -gt 0 ]` becomes `if [ ... ] || [ "$RUN_DEGRADED" -gt 0 ]`
- DRY_RUN smoke must update assertions
- STOP-file halt path should also write morning-report.json with halted-at-stage
- Persona-metrics: <feature>/check/findings.jsonl vs <feature>/check-verdict.json — no collision
