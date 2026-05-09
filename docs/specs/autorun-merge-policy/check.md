OVERALL_VERDICT: GO_WITH_FIXES

# Plan Checkpoint Synthesis — autorun-merge-policy

## Reviewer Verdicts

| Reviewer | Verdict | Must-Fix Count | Headline |
|---|---|---|---|
| Completeness | PASS WITH NOTES | 4 | AC↔D contradictions + missing fixtures |
| Risk | PASS WITH NOTES | 3 | followups counter race, banner stream, partial order |
| Scope-Discipline | PASS WITH NOTES | 0 | Trim banner two-tier, drift wrapper, triage recipe |
| Security-Architect | PASS WITH NOTES | 0 | 3 should-fix sev:security (SA-1/2/3) |
| Sequencing | PASS WITH NOTES | 3 | Wave-3 file contention, predicate-arg ordering, baseline capture site |
| Testability | PASS WITH NOTES | 4 | Counter anchor, join key, fixture classification, truth table |

All six reviewers landed on PASS WITH NOTES. No reviewer flagged the architecture as wrong. The Must-Fix surface is concentrated in (a) contract precision (counter formula, join key, predicate axes, partial order), (b) sequencing inside Wave 3, and (c) three fixture gaps. Each is a surgical edit measured in lines, not waves.

## Must Fix (block /build until resolved)

**Architectural / sequencing**
1. **Wave 3 file contention** (seq-MF1) — W3.1–W3.5 all edit `scripts/autorun/run.sh` in parallel. Sequence them, or have one agent own all run.sh edits in Wave 3. Documented race per `feedback_parallel_agents_shared_file_race.md`.
2. **W3.4 / W3.4b ordering** (seq-MF2) — `is_clean_for_merge` requires the 4th `followups_added` arg; W3.4 wires the call before W3.4b wires `FOLLOWUPS_ADDED`. Merge into one task or move W3.4b first.
3. **W3.4b baseline-capture site unowned** (seq-MF3) — `FOLLOWUPS_BASELINE` must be captured at run start (W3.1 territory). Without explicit ownership, agent will recompute at dispatch and defeat the R1 guard.

**Contract precision**
4. **AC#13 ↔ D6 contradiction** (comp-MF1) — AC#13 says drift detector "never halts"; D6 halts on privilege elevation. Reconcile in spec patch.
5. **Banner stdout vs stderr** (comp-MF2 / risk-MF2) — D10 says stderr `[ -t 2 ]`, R7 says stdout `[ -t 1 ]`. Pick stdout (R7) — banner is intentional output. Strike conflicting D10 line.
6. **`followups_added` counter scoping** (risk-MF1 / test-MF1) — must be slug-scoped (grep `"slug": "$SLUG"` in followups.jsonl), not raw `wc -l`; pin canonical artifact path, diff method, missing-file behavior, and slug-filter semantics. Add parallel-slug fixture.
7. **Partial order `pr` / `clean` / `validated`** (risk-MF3) — D6 asymmetric halt is non-deterministic without an explicit ordering. Pin: `pr ≡ validated_today < clean`; document forward-compat for activated `validated`.
8. **Two-event audit join key** (test-MF2) — promote `ts_run_start` (or a `run_id`) to required field on BOTH `merge_policy_resolved` and `merge_action_completed`; add fixture asserting two consecutive runs of same slug yield two pairable (start,end) pairs.
9. **`pr_create_failed` fixture trio classification** (test-MF3) — collapse to one fixture, OR add `details.pr_create_stderr_class` enum and assert per fixture. Current trio is theater without a classification contract.

**Test fixtures**
10. **AC-R2 has no fixture** (comp-MF3) — split start/end events need a crash-between fixture asserting the start row survives. Without it, AC-R2 is unverified.
11. **AC#3 constitution-only precedence fixture missing** (comp-MF4) — W2.8 covers default + spec-set + CLI-over-spec. Add the constitution layer or update AC#3 wording.
12. **`is_clean_for_merge` truth table** (test-MF4) — 4 axes = 24 reachable cells; named-AC fixtures don't cover combinatorics. Add `tests/fixtures/is_clean_for_merge_truth_table.tsv` + loop.

## Security Findings (hardcoded blockers)

- **SA-1 (sev:security)** — Codex-absent treated as `CODEX_HIGH_COUNT==0` vacuously satisfies `clean`-policy auto-merge; any Codex outage silently bypasses an entire reviewer axis. Add `CODEX_RAN` var; require `CODEX_RAN==1` for `clean` unless `gate_mode==strict`; new `reason=codex_absent`.
- **SA-2 (sev:security)** — `MERGE_POLICY_DISPATCH_OVERRIDE` is unguarded. A stale env var in CI/dev shell silently redirects dispatch while audit row still says `auto_merged`. Gate on `MONSTERFLOW_TEST_MODE=1` sentinel; warn-and-ignore otherwise.
- **SA-3 (sev:security)** — PR body embeds reviewer-summary content (attacker-influenceable via spec/plan text). Downstream LLM consumers (this pipeline, /code-review skill) can be prompt-injected, including via embedded `` ```check-verdict `` fence. Wrap in 4-backtick fences, NFKC-normalize + zero-width-strip, hard-fail on any `check-verdict` substring.

## Should Fix (apply inline at /build, do not block)

- Banner two-tier collapse (scope SF1), `mkdir -p` first-run hint (scope SF2), interim PR-backlog triage recipe (scope SF3), 3-state field-state wrapper (scope SF4), OQ3 deletion (scope SF5)
- D15 spec-edit moving AC#13 from `autorun-batch.sh` to `run.sh` (comp SF5)
- `gate_mode` field added to AC#9 schema (comp SF6)
- `merge_sha` null-on-`auto_merged` doc note (comp SF7)
- `.manual-review` first-time-use UX (comp SF8)
- OQ1/OQ2/OQ3 resolution before /build (comp SF9)
- `--merge-policy=` ↔ `--auto-merge=` literal-spelling grep-test (comp SF10)
- Forensic `spec_sha` failure handling (comp SF11)
- `pr_create_stderr_tail` field (risk SF1), force-push detection by `head:<branch>` not title (risk SF2), `--auto-merge=` removal version pinning (risk SF3), recycle-fixed-followups predicate semantics (risk SF4)
- W2.5 PR title ownership clarification (seq SF1), W2.8 fixture-per-file vs sequential ownership (seq SF2), W2.9 "BEFORE commit" qualifier (seq SF3), W3.6 `gh pr edit --title` decision (seq SF4), CHANGELOG bump timing (seq SF5), AC#21 cross-spec lifecycle note (seq SF6)
- AC#11 banner-fires-forever fixture (test SF1), drift-elevation halt fixture (test SF2), `gate_mode` in schema-shape test (test SF3), `MERGE_POLICY_DISPATCH_OVERRIDE` 5-line contract block (test SF4), W3.12 enumerate 11 sections (test SF5)
- SA-4 banner sanitizer, SA-5 SLUG canonicalization assertion, SA-6 quoted-`#` doc note

## Decision Path

GO_WITH_FIXES. Three security findings are hardcoded blockers per repo policy and resolvable as additive enum values + one fixture each in Wave 2. Twelve non-security Must-Fix items are: 1 sequencing/parallelism fix (one agent owns Wave-3 run.sh edits), 6 contract pins (counter formula, join key, partial order, banner stream, AC↔D reconciliation, predicate-arg ordering), 3 fixture additions (AC-R2 crash-recovery, AC#3 constitution layer, is_clean truth table), 1 baseline-capture ownership reassignment, 1 fixture trio classification decision. None require architectural rework; total surgical surface ≈ 100–150 LoC + 5–8 fixtures + a one-paragraph spec patch.

Recommend: roll SA-1/SA-2/SA-3 into Wave 2 explicitly, fold W3.4 + W3.4b into a single sequenced Wave-3 task with run.sh-owner designation, patch the 4 contract ambiguities into D6/D10/D17/D21/D22 before /build dispatches.

