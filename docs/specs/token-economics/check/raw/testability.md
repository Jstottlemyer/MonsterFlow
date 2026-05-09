# Testability and Verifiability — /check Review

**Verdict:** PASS WITH NOTES

The plan has strong AC→task→verification mapping (the table at the end is the right shape), 10 dedicated test scripts, an inverted-assertion test for fail-detection, and explicit manual smoke + subagent validation steps. Test orchestrator wiring is correctly identified as a single-owner risk and addressed (T-WIRE-1 + D15). Several specifically-called-out behaviors, however, lack a corresponding test in Wave 2.

## Must Fix

```yaml
- persona: testability-and-verifiability
  finding_id: tv-1
  severity: major
  class: tests
  title: "A1.5 forcing-function only verifies agreement, not the failure path"
  body: "T-TEST-2 lists A1.5 as 'fails build on disagreement' but no fixture is enumerated that exercises the disagreement case. Without a synthetic-mismatch fixture, A1.5 can silently regress to 'always agrees' and the canonical-token-source forcing function stops forcing. The test currently only proves the happy path."
  suggested_fix: "Add a deliberate-mismatch fixture under tests/fixtures/persona-attribution/a1_5-disagreement.jsonl whose parent annotation total_tokens differs from sum(subagents/usage). Assert A1.5 exits non-zero on it (parallel to the test-allowlist-inverted.sh shape). Document in T-PRE-3 scope."

- persona: testability-and-verifiability
  finding_id: tv-2
  severity: major
  class: tests
  title: "Bullet-counting regex (D11) lacks explicit edge-case test enumeration"
  body: "judge_retention_ratio's denominator depends entirely on the bullet regex. D11 pins '^[-*] ' under three specific headings, excluding ## Verdict, numbered lists, nested bullets, and other headings. T-DOC-1 codifies it but T-TEST-2 doesn't enumerate fixtures for: (a) bullets under ## Verdict (must be excluded), (b) numbered '1. ' lines (must be excluded), (c) nested '  - ' (must be excluded), (d) bullets under unrelated headings (must be excluded). Silent regex drift here corrupts every retention number on the dashboard."
  suggested_fix: "Add a tests/fixtures/persona-attribution/raw-edge-cases.md fixture covering all four exclusion categories plus the three valid headings. Assert emitted_bullet_count matches a hand-computed expected value. Fold into T-TEST-2 as A2 sub-case."

- persona: testability-and-verifiability
  finding_id: tv-3
  severity: major
  class: tests
  title: "T-TEST-10 perf budget soft-fails — regressions ship silently"
  body: "Spec memory has prior incidents where /wrap-insights latency drifted unnoticed. Soft-fail (warning only) means a 10x regression caused by a future schema change passes CI green. The whole point of a 5s budget is to catch regressions before they reach Justin's nightly /wrap-insights run."
  suggested_fix: "Hard-fail at 3x budget (15s) and warn at 1x (5s). Keep machine-specific calibration but make egregious regressions block. One line of bash."
```

## Should Fix

```yaml
- persona: testability-and-verifiability
  finding_id: tv-4
  severity: minor
  class: tests
  title: "T-TEST-2 A8 'concurrent case' lacks specified concurrency mechanism"
  body: "R8 is mitigated by T-CORE-9 sorting after truncation, but the A8 test only diffs two sequential runs. No fixture exercises actual concurrent invocation (e.g., two background processes hitting the same JSONL via os.replace). Without a real concurrency exercise, sort-after-truncate is unverified end-to-end."
  suggested_fix: "Add a sub-test in T-TEST-2: spawn two background compute-persona-value.py processes against the same fixture, wait for both, assert (a) JSONL parses cleanly, (b) contributing_finding_ids[] is sorted in the surviving file."

- persona: testability-and-verifiability
  finding_id: tv-5
  severity: minor
  class: tests
  title: "Stale-data banner (e6, 14+ days) and insufficient-sample-only banner (T-UI-3) lack tests"
  body: "Both banners are user-facing observability for 'is this dashboard trustworthy.' e6 is in the spec edge-case table; T-UI-3 adds the all-insufficient banner. Neither has a test in Wave 2. T-TEST-9 covers fresh-install + corruption recovery only."
  suggested_fix: "Extend T-TEST-9 (or add T-TEST-11) to cover: (a) all-insufficient-sample banner triggers when every row has insufficient_sample:true, (b) stale banner triggers when generated_at is >14d old. Headless DOM check via a small node script or Playwright selector."

- persona: testability-and-verifiability
  finding_id: tv-6
  severity: minor
  class: tests
  title: "T-CORE-6 subagent layout drift threshold has no test"
  body: "T-CORE-6 emits a stderr drift warning and A1.6 caps unattributed at 5%, but no test enumerates the threshold check. Future Anthropic format change would silently push unattributed past 5% with no CI signal until production /wrap-insights runs."
  suggested_fix: "Fold an assertion into T-TEST-2: synthetic fixture with 6/100 unparseable dispatches must trip the threshold (non-zero exit absent --best-effort)."

- persona: testability-and-verifiability
  finding_id: tv-7
  severity: minor
  class: tests
  title: "<unknown> bucket toggle (D4) and orchestrator-overhead UI behavior unverified"
  body: "T-UI-2 adds the toggle but no test asserts that <unknown>/cost_only rows are hidden by default and shown when toggled. Easy to regress when the dashboard JS gets touched in v1.1."
  suggested_fix: "Add a snapshot-style assertion in T-TEST-9 or a new tiny test that loads dashboard/persona-insights.js against a fixture with <unknown> rows and asserts default-hidden, toggle-shown."

- persona: testability-and-verifiability
  finding_id: tv-8
  severity: minor
  class: tests
  title: "No regression test for pre-existing dashboard tabs after T-UI-1"
  body: "T-UI-1 adds a third top-level mode tab to dashboard/index.html. No test asserts the existing two tabs still render. Risk is low but the file is shared with judge-dashboard-bundle output, so a structural HTML change could silently break."
  suggested_fix: "One-line grep test in tests/run-tests.sh asserting the existing tab IDs still exist post-T-UI-1."
```

## Notes

- **A4 weakened to best-effort makes the test loose.** Plan acknowledges this honestly (test does NOT assert `runs_in_window: 1`), but the assertion that survives — "post-edit findings only in `contributing_finding_ids[]`" — is the right pin given the v1 boundary. Keep as is, but T-DOC-2 should explicitly call out that retention rates may show transient pre-edit residue for up to 45 directories post-edit, so adopters don't read drift as a defect.
- **Cross-machine race (e5)** is documented as last-writer-wins and not tested — appropriate for v1 since the file is gitignored and machine-local. No action.
- **Observability surface is thin** — counts-only stderr telemetry is good for privacy but means a recurring crash (e.g., salt corruption regenerating every run) isn't visible without `MONSTERFLOW_DEBUG_PATHS=1`. Consider a one-line `~/.cache/monsterflow/persona-value-errors.log` rotating tail in v1.1, not a v1 blocker.
- **T-VERIFY-2 (`persona-metrics-validator` invocation)** is the right belt-and-suspenders move for the first emit. Worth recording its output in the PR body so future regressions have a baseline.

## Verdict

**PASS WITH NOTES** — Test surface is well-mapped to ACs, but three test-coverage gaps (A1.5 failure-path fixture, bullet-regex edge cases, perf hard-fail ceiling) are major enough that they should land in this build, not a follow-up. The Should-Fix items are low-cost additions that prevent silent regressions in the parts of the system most likely to drift over time (subagent format, dashboard JS, banner triggers).
