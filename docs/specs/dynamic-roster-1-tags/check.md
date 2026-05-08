OVERALL_VERDICT: GO_WITH_FIXES

# Plan Checkpoint — dynamic-roster-1-tags

All six specialist reviewers returned **PASS WITH NOTES**. The plan is architecturally sound and the slice is correctly metadata-only. Six surgical Must-Fix items (all mechanical edits to T7 / T11 / Wave B) should be folded in before /build dispatches; none requires re-design.

## Reviewer Verdicts

| Reviewer | Verdict | Blocking? |
|---|---|---|
| completeness | PASS WITH NOTES | No (2 Must-Fix, surgical) |
| risk | PASS WITH NOTES | No (2 Must-Fix, surgical) |
| scope-discipline | PASS WITH NOTES | No (2 cut candidates, optional) |
| security-architect | PASS WITH NOTES | No (zero blockers, zero `sev:security`) |
| sequencing | PASS WITH NOTES | No (4 Should-Fix clarifications) |
| testability | PASS WITH NOTES | No (2 Must-Fix, mechanical) |

## Must Fix (fold into plan before /build)

1. **chmod +x on the new test file (completeness-M1).** Add explicit `chmod +x tests/test-persona-fit-tags.sh` to T7 done-criteria + verification grep `[ -x tests/test-persona-fit-tags.sh ]` in T11. Prevents silent skip per `feedback_test_orchestrator_wiring_gap.md`.

2. **JSON-loadability smoke check for the three schemas (completeness-M2).** Add to T7 or T11: `python3 -c "import json; [json.load(open(p)) for p in ['schemas/tag-enum.schema.json','schemas/spec-frontmatter.schema.json','schemas/persona-frontmatter.schema.json']]"`. Locks A1/A2/A3.

3. **Test harness fail-open guard (risk-M1).** After `REPORT="$(_python_check)"`, validate `$REPORT` parses as JSON with the four expected keys; abort with non-zero if not. Otherwise A7 (+4 PASS) is satisfiable by a broken test.

4. **One commit per task in Wave B (risk-M2).** Specify in Sequencing Notes: T8 → commit → T9 → commit → T10 → commit. Recoverable from partial failure; consistent with `feedback_git_add_then_commit_sweeps_index.md` (use `git commit <path>`, not `git add . && git commit`).

5. **Baseline pass-count capture for A7/T11 (testability-M1).** Before Wave A: run `bash tests/run-tests.sh` and record `BASELINE_PASS` count in commit message / ephemeral note. After Wave C: assert `final == BASELINE_PASS + 4`. Without this the +4 assertion is vacuous.

6. **Negative-path fixtures replacing A15 manual sentinel (testability-M2 + scope-SF2 + risk-S1).** Replace the `_AC15_test.md` ritual with `tests/fixtures/persona-fit-tags/{bad-missing,bad-empty,bad-enum,bad-duplicate}.md` and have `test-persona-fit-tags.sh` assert each fixture FAILS as expected. Removes a sentinel-leak risk (`feedback_skip_token_self_collision.md`) and gives permanent regression coverage.

## Should Fix (recommend, non-blocking)

- **T13 deps include T7** (sequencing-S1): `autorun-shell-reviewer` reviews the new test file too.
- **Explicit commit-gate task T14** with `Depends On: T11, T12, T13` (sequencing-S3).
- **Reword T11 parallelism** from "sequential" to "after Wave B; parallel-safe with T12/T13" (sequencing-S4).
- **Block-form YAML detection** in `FIT_TAGS_RE` path: emit "use inline-array form" error, not "missing field" (risk-S3).
- **Widen A9 dormancy grep** to include `dashboard/`, `personas/`, `schemas/`, `.claude/agents/` (testability-S2).
- **T13 verdict-handling spec**: High → block + retry ≤2x; Medium/Low → followups.jsonl, no halt (testability-S1).
- **Hash-rotation rebuild check** in T11 (testability-S5).
- **Quoting refactor for `_python_check`** — temp file + single inline Python script per assertion (completeness-#6).
- **CHANGELOG anchor** keyed on literal `## [0.9.0] - 2026-05-05` header (completeness-#7).
- **Cut candidates** (scope-discipline): T10/A14 install.sh schemas/ propagation could defer to slice 3 (no runtime consumer yet); accept or document the rationale.

## Decision Path

GO_WITH_FIXES is the right verdict because:
- Zero architectural concerns; six independent reviewers converged on PASS.
- Zero security findings (slice is metadata-only; no auth/secret/untrusted-input surface).
- All Must-Fix items are 1–10 LoC edits to the plan document or test file — no waves restructure, no spec change, no design pivot.
- `gate_mode: permissive`, `gate_max_recycles: 2` — the fixes fit comfortably inside one re-cycle if /build ever needs to revisit.

Apply Must-Fix #1–#6 inline, then /build is cleared to dispatch Wave A.

