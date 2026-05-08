---
gate_mode: permissive
gate_max_recycles: 2
---

# Autorun Runtime Validation Gate Spec — Smoke-Check the Built Thing Before Merge

**Created:** 2026-05-08
**Constitution:** none — session roster only
**Confidence:** Scope 0.92 / UX 0.92 / Data 0.90 / Integration 0.85 / Edges 0.88 / Acceptance 0.92
**gate_mode:** permissive
**gate_max_recycles:** 2

## Summary

Add a post-`/build` runtime validation step to the autorun pipeline that smoke-checks the assembled artifact before declaring a run "validated." Today the deepest validation is unit-test discipline inside `/build` — which catches code-level regressions but misses UI/integration/runtime issues (page didn't render, CLI exits non-zero on its own help text, simulator fails to launch the new build). The gate is **opt-in per-project** via a `runtime:` frontmatter declaration; repos without one get a no-op (preserves today's behavior on meta-tooling repos like MonsterFlow itself). When `runtime:` is set, autorun runs a configurable per-target smoke check; only a passing check qualifies for `auto_merge_policy: validated`.

## Backlog Routing

Carved from in-conversation review 2026-05-08 alongside `autorun-merge-policy`. Together they close the "auto-merge without runtime validation" gap. This spec adds the validation gate; the policy spec adds the merge knob that consumes it. They ship independently — merge-policy can land first with `validated` falling back to `clean`; this spec lights up the `validated` path once shipped.

## Scope

**In scope:**
- New optional frontmatter key `runtime: <target>` in `spec.md` declaring what kind of artifact the spec produces. Initial supported values: `web`, `ios`, `cli`, `none` (explicit no-op).
- New per-target validator scripts under `scripts/runtime-validators/`:
  - `web.sh` — playwright headless visit + console-error scan + HTTP 200 assertion against a configurable target URL or local dev server.
  - `ios.sh` — `xcodebuild test` on simulator (project + scheme detected from spec.md or constitution) + smoke launch + screenshot-on-fail.
  - `cli.sh` — invoke the changed command with `--help` (assert exit 0 + non-empty stdout) plus a configurable `happy_path_args` invocation (assert exit 0).
- New optional `runtime_config:` block in spec.md frontmatter for per-target tuning:
  - `web` → `target_url`, `dev_server_cmd`, `wait_for_selector`, `console_error_allowlist[]`
  - `ios` → `xcodeproj`, `scheme`, `simulator_name`, `test_plan` (optional)
  - `cli` → `cmd`, `happy_path_args`, `expected_stdout_contains` (optional regex)
- Autorun integration: after `/build` succeeds, before the merge-policy decision, dispatch the runtime validator if `runtime:` is set. Validator stdout/stderr captured to `queue/<slug>/runtime-validation.log`; pass/fail recorded to `queue/<slug>/runtime-validation.json` sidecar with schema.
- New schema: `schemas/runtime-validation.schema.json` — captures target, status (`pass | fail | skipped | error`), exit code, log path, duration, target-specific facts (e.g., `web.console_errors[]`, `ios.failed_tests[]`, `cli.stderr_excerpt`).
- Consumed by `autorun-merge-policy`'s `validated` value: merge requires `runtime-validation.json.status == "pass"`. Gates of `pr` and `clean` ignore the result.
- Audit log row in `queue/run.log` per validation: `runtime_validated` event with target, status, duration.
- Tests: 6 fixtures — `runtime: none` (no-op), `runtime: cli` happy path, `runtime: cli` failing path, `runtime: web` mock playwright, `runtime: ios` skipped (no simulator available), invalid `runtime: foo` (rejected).

**Out of scope:**
- Other runtime targets: `mobile-android`, `desktop-electron`, `server-node`, `server-python` — extension-friendly architecture but only `web | ios | cli | none` in v1.
- Hosted CI integration (GitHub Actions matrix runners) — local-only validation in v1; CI parallelization is a follow-up.
- Test framework wrappers — validators are shell scripts that invoke whatever the project already uses (`pytest`, `xcodebuild`, `playwright test`); no opinionated test framework.
- Performance budgets / Lighthouse scoring / accessibility audits — those are quality gates, not smoke checks. Possible future spec.
- Auto-fix loops on runtime failure — runtime fail = halt + report. The 3-attempt iterative-resolution pattern is for `/check` blockers, not runtime.
- Production deploy validation (post-merge against staging/prod) — that's a deploy-pipeline concern, not autorun.
- Visual regression / screenshot diffing — `web.sh` can produce a screenshot on fail but doesn't compare to baselines. Future spec.

## Approach

**Chosen:** target-detector + dispatcher pattern with per-target shell validators.

The `runtime:` value selects a validator at `scripts/runtime-validators/<target>.sh`. The validator is invoked with two args: the slug + the path to spec.md (so it can read `runtime_config:` itself). It runs synchronously, writes its own log + sidecar, exits 0 on pass / non-zero on fail. Autorun reads the sidecar to know the verdict.

This keeps the validators decoupled from autorun's main loop and lets users override them per-project (validator scripts can be shadowed in a project's `.monsterflow/runtime-validators/` directory if it exists).

**`web.sh` mechanics:**
1. If `dev_server_cmd` is set, start it in the background with a 30-second readiness wait (HTTP HEAD against `target_url` until 2xx or timeout).
2. Use `npx playwright` (must be installed in the project; spec author's responsibility) to navigate to `target_url`, wait for `wait_for_selector`, capture console events.
3. Pass = HTTP 200 + selector visible + no unallowlisted console errors.
4. On fail, capture screenshot to `queue/<slug>/runtime-fail.png`.
5. Tear down dev server.

**`ios.sh` mechanics:**
1. Resolve `xcodeproj` (from spec or by walking up to find a `.xcodeproj`).
2. `xcodebuild test -project <proj> -scheme <scheme> -destination 'platform=iOS Simulator,name=<simulator_name>'`. If `test_plan` set, pass `-testPlan`.
3. If tests pass, smoke-launch the built app on the simulator for 5 seconds, capture screenshot.
4. Pass = test exit 0 + smoke launch produces non-empty screenshot.
5. Fail = capture failed test names + log excerpt.

**`cli.sh` mechanics:**
1. Invoke `<cmd> --help` — assert exit 0, stdout non-empty.
2. Invoke `<cmd> <happy_path_args>` — assert exit 0; if `expected_stdout_contains` set, assert regex match.
3. Pass = both exits 0 + regex matches if set.
4. Fail = capture stderr excerpt + actual exit code.

Rejected alternatives:
- *Single mega-validator with target dispatch inside* — harder to extend, harder to unit-test.
- *Python validators instead of shell* — adds a dependency layer; shell is consistent with the rest of `scripts/autorun/` and can call out to language-specific tools (xcodebuild, npx, pytest) from there.
- *Run validation as part of `/build`'s verification phase* — coupling concern. /build is about the diff being correct in code; runtime validation is about the assembled thing working. Different scope; different failure-mode signals.
- *Make `runtime:` required for all specs* — over-rotates. Most MonsterFlow specs are config/docs/tooling without a runtime target. Default no-op is the right shape.

## Roster Changes

No persistent roster changes. The `risk` reviewer persona at `/check` already evaluates whether a plan covers runtime/integration concerns; this spec just gives autorun a way to actually run the smoke check. `autorun-shell-reviewer` subagent gates the new shell scripts.

## UX / User Flow

**Spec-author opt-in:**
```yaml
# spec.md frontmatter for an iOS feature
runtime: ios
runtime_config:
  xcodeproj: apps/MyGame/MyGame.xcodeproj
  scheme: MyGame
  simulator_name: "iPhone 15 Pro"
  test_plan: SmokeOnly
```

**Spec-author opt-in for a web feature:**
```yaml
runtime: web
runtime_config:
  target_url: http://localhost:3000
  dev_server_cmd: "npm run dev"
  wait_for_selector: "[data-testid='app-loaded']"
  console_error_allowlist:
    - "Failed to load resource: the server responded with a status of 404"  # known asset 404
```

**Autorun output on a passing run (with `auto_merge_policy: validated`):**
```
[autorun] /build complete
[autorun] runtime validation: target=web
[autorun] starting dev server: npm run dev
[autorun] navigating to http://localhost:3000
[autorun] selector found, no console errors
[autorun] runtime validation: PASS (4.2s)
[autorun] auto_merge_policy=validated, gates clean, runtime pass → auto-merging
[autorun] merged: https://github.com/.../pull/42
```

**Autorun output on a failing runtime check:**
```
[autorun] /build complete
[autorun] runtime validation: target=ios
[autorun] xcodebuild test ... FAIL
[autorun] runtime validation: FAIL (45s) — 2 tests failed
[autorun] failed tests: GameSceneTests.testInitialState, GameSceneTests.testLevelLoad
[autorun] log: queue/my-feature/runtime-validation.log
[autorun] sidecar: queue/my-feature/runtime-validation.json
[autorun] auto_merge_policy=validated, runtime FAIL → opening PR with validation failure
[autorun] PR opened: https://github.com/.../pull/42 [needs-fix:runtime]
```

**`runtime: none` or unset:**
```
[autorun] /build complete
[autorun] runtime validation: skipped (no runtime target declared)
[autorun] continuing to merge-policy decision
```

## Data & State

**New schema:** `schemas/runtime-validation.schema.json`

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "Runtime validation sidecar",
  "type": "object",
  "required": ["schema_version", "target", "status", "started_at", "duration_seconds", "log_path"],
  "properties": {
    "schema_version": {"type": "integer", "const": 1},
    "target": {"type": "string", "enum": ["web", "ios", "cli", "none"]},
    "status": {"type": "string", "enum": ["pass", "fail", "skipped", "error"]},
    "exit_code": {"type": "integer"},
    "started_at": {"type": "string", "format": "date-time"},
    "duration_seconds": {"type": "number"},
    "log_path": {"type": "string"},
    "details": {
      "type": "object",
      "description": "Target-specific facts. web: console_errors[], http_status, screenshot_path. ios: failed_tests[], simulator_name, screenshot_path. cli: stderr_excerpt, actual_exit_code, regex_matched."
    }
  }
}
```

Sidecar lives at `queue/<slug>/runtime-validation.json`. Log lives at `queue/<slug>/runtime-validation.log`. Fail-only screenshots at `queue/<slug>/runtime-fail.png`.

No state outside per-slug queue dir.

## Integration

- `scripts/autorun/run.sh` — after `/build` succeeds, dispatch runtime validation if `runtime:` is set. Read result; pass to merge-policy resolver.
- `scripts/runtime-validators/web.sh`, `ios.sh`, `cli.sh` — new files (~150-300 LoC each).
- `scripts/runtime-validators/_lib.sh` — shared helpers (sidecar writer, log capture, timeout enforcement).
- `schemas/runtime-validation.schema.json` — new schema.
- Validator override path: `<project>/.monsterflow/runtime-validators/<target>.sh` shadows the global. Allows per-project customization without forking the engine.
- `autorun-merge-policy` integration: `validated` value reads `queue/<slug>/runtime-validation.json.status == "pass"` to qualify for merge.
- Tests: `tests/test-runtime-validation.sh` (~250 LoC, 6 fixtures + 1 schema-validation test).
- `commands/autorun.md` — document the new key + per-target config.
- `docs/specs/constitution.md` template — note the new optional key.
- `docs/index.html` — autorun section can mention the gate as "in flight" once this spec lands.

Touched files: 1 modified shell script + 4 new shell scripts + 1 schema + 1 test file + 2 doc updates. Estimated ~800-1200 LoC delta (validators are the bulk).

## Edge Cases

- **`runtime:` unset:** validator never invoked; merge-policy `validated` falls back to `clean`. `runtime: none` explicit-no-op gives the same behavior with audit-log clarity (intent recorded as "no runtime target by design").
- **Validator dependency missing:** `web.sh` requires `npx playwright` to be installed in the project. If absent, validator exits with `status: error` (not `fail`) — distinct from a runtime failure. Surfaces as `[autorun] runtime validation: ERROR — playwright not found in project (run: npx playwright install)`. Run treated as if `runtime:` was unset (validation skipped); merge-policy `validated` falls back to `clean` with a stderr warning.
- **Dev server fails to start within 30s readiness wait:** validator exits with `status: error`; logs the wait timeout + last HTTP status. Fail differently than a 200-but-broken-page.
- **Simulator not available (no Xcode, headless CI without macOS):** `ios.sh` exits with `status: skipped`; log explains. Fall-back semantics same as missing dependency.
- **Console error allowlist matches a real bug:** allowlist is opt-in and explicit; spec author's responsibility. We don't second-guess. Sidecar records `details.console_errors_allowlisted[]` so reviewers can audit what was suppressed.
- **Long-running validators (>5 min):** hard timeout enforced via `timeout` (GNU) or `gtimeout` (macOS coreutils). Default 5 min per target, override via `runtime_config.timeout_seconds`. Validator exits with `status: error` on timeout.
- **Validator script has a bug (segfaults, exits non-zero before writing sidecar):** autorun catches missing-sidecar case and writes a synthetic sidecar with `status: error, details: {reason: "validator did not write sidecar"}`. Run goes through merge-policy resolution as ERROR — `validated` falls back to `clean`.
- **Per-project validator override:** `<project>/.monsterflow/runtime-validators/web.sh` shadows the global. Validated by checking the override is executable + readable; warning logged if found but not executable.
- **Multiple targets in one spec (e.g., monorepo with web + ios):** v1 is single-target. Multi-target deferred — would require a `runtime: [web, ios]` array form and an aggregator policy (all-pass / any-pass / quorum). Backlog candidate.
- **`runtime_config` key typos (e.g., `target_url` typo'd as `tagret_url`):** validator's required-key check fails fast with stderr message naming the missing key. No fall-through; spec author needs to fix.
- **Network-required validation in offline environment:** `web.sh` against an external `target_url` fails with timeout if offline. No special handling — that's the validator's job to report.
- **Race with the merge step:** validation runs before merge-policy resolution; sidecar is written atomically (tmp + rename) before autorun reads it. No race.
- **Cleanup on validator success:** dev servers stopped, simulators unbooted (where applicable), temp screenshots in `queue/` retained for forensics.
- **Cleanup on autorun-batch STOP:** if STOP is touched mid-validation, validator finishes its current attempt + sidecar is written; next iteration honors STOP. Mid-validation halts are messy and avoided by waiting for the iteration boundary.

## Acceptance Criteria

1. New optional frontmatter key `runtime: web | ios | cli | none` accepted in `spec.md` with optional `runtime_config:` block.
2. Validator scripts at `scripts/runtime-validators/{web,ios,cli}.sh` ship with the engine; project-level shadows at `<project>/.monsterflow/runtime-validators/<target>.sh` override the global.
3. Validator outputs `queue/<slug>/runtime-validation.json` (matches `schemas/runtime-validation.schema.json`) and `queue/<slug>/runtime-validation.log`.
4. `web.sh` validator: starts optional dev server, navigates to target URL via headless playwright, asserts HTTP 200 + selector visible + no unallowlisted console errors, captures screenshot on fail.
5. `ios.sh` validator: runs `xcodebuild test` against the configured project/scheme/simulator, smoke-launches the built app on success.
6. `cli.sh` validator: asserts `--help` exit 0 + non-empty stdout, plus optional happy-path args invocation with regex stdout match.
7. Validators write `status: pass | fail | skipped | error` distinguishing real failures from missing dependencies.
8. Validator timeout: 5-min default per target, override via `runtime_config.timeout_seconds`. Timeout produces `status: error`, not `fail`.
9. Autorun runs the validator after `/build` and before the merge-policy decision; sidecar is consumed by the `validated` merge-policy value.
10. `runtime:` unset OR `runtime: none` → validator step skipped (no-op); merge-policy `validated` falls back to `clean` semantics with a one-line stderr warning.
11. Validator dependency missing (e.g., playwright not installed) → `status: error`, autorun proceeds to merge-policy as if validation skipped.
12. `queue/run.log` records one `runtime_validated` event per slug with target, status, duration, sidecar path.
13. `commands/autorun.md` documents the new key, per-target config, and validator override path.
14. Test fixture: `runtime: none` → no validator dispatched, run.log records skip, merge-policy resolved as before.
15. Test fixture: `runtime: cli` against a happy-path command → validator passes, status: pass, sidecar matches schema.
16. Test fixture: `runtime: cli` against a failing command (exit 1) → status: fail, exit_code captured, autorun continues to merge-policy with `validated` blocked.
17. Test fixture: `runtime: web` with mock playwright (or skip if not installed) → status: pass on a known-good fixture page.
18. Test fixture: `runtime: ios` with no simulator available → status: skipped, autorun continues, validated falls back.
19. Test fixture: invalid `runtime: foo` value → exit 2 at frontmatter parse, no validator dispatched.
20. Test fixture: per-project validator shadow → shadow runs instead of global, audit log records `validator_path` field.
21. Schema validator (`scripts/_validate_runtime_validation_sidecar.py` or equivalent) accepts well-formed sidecars and rejects malformed ones (missing required fields, unknown status values).
22. `autorun-shell-reviewer` subagent passes a clean review against new validator scripts per its 13-pitfall checklist (especially: PIPESTATUS around `npx`/`xcodebuild`/`gtimeout`, explicit pathspec, no `git add -A`, AppleScript-injection check on macOS path).

## Open Questions

- **Q1:** should the `web` validator support running against a built static site (e.g. `out/`, `dist/`, `build/`) without a dev server? **Lean: yes for v1.5** — add a `static_dir:` config alternative to `dev_server_cmd:`. Validator serves it via `python3 -m http.server` ephemerally. Useful for static-site projects (Next export, Astro). Could ship in v1 if it doesn't bloat the spec; otherwise carve to follow-up.
- **Q2:** should validation happen on its own dedicated branch (separate from /build's branch) to isolate any side effects (port binding, filesystem state)? **Lean: no** — validators run sandboxed by convention (start dev server in subshell with PID tracked + killed; xcodebuild simulator is isolated). Branch isolation adds complexity for ambiguous gain.
- **Q3:** should validator output (screenshots, logs) be attached to the PR body when `validated` fails? **Lean: yes for v1.5** — autorun's PR-creation already templates the body; adding "Runtime validation: FAIL — see screenshot at <link>" closes the loop. Implementation note for /build: extend `gh pr create --body` template.
- **Q4 (resolved):** should missing-dependency error halt the run or fall through? Resolved: fall through with stderr warning. A missing playwright or simulator is the user's environment, not a code defect; halting would be a worse experience than letting the run land as a PR with the validation gap noted.
- **Q5 (resolved):** can the validator be parallelized with /build's verification phase? Resolved: no — runtime validation is post-build by definition. Parallelizing would couple the two phases and obscure failure-mode signals.
