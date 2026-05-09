---
gate_mode: permissive
gate_max_recycles: 2
---

# Autorun Runtime Validation Gate Spec — Smoke-Check the Built Thing Before Merge

**Created:** 2026-05-08
**Revised:** 2026-05-08 (Q&A refinement to 0.95 confidence; cross-spec alignment with autorun-merge-policy)
**Constitution:** none — session roster only
**Audience:** MonsterFlow contributors and pipeline maintainers — adopter-facing copy is handled in `docs/index.html`.
**Applies to:** autorun only. Manual pipeline runs are unaffected (no auto-merge step in manual flow).
**Confidence:** Scope 0.92 / UX 0.92 / Data 0.92 / Integration 0.93 / Edges 0.95 / Acceptance 0.93 (avg 0.93)
**gate_mode:** permissive
**gate_max_recycles:** 2

## Summary

Add a post-`/build` runtime validation step to the autorun pipeline that smoke-checks the assembled artifact before declaring a run "validated." Today the deepest validation is unit-test discipline inside `/build` — which catches code-level regressions but misses UI/integration/runtime issues (page didn't render, CLI exits non-zero on its own help text, simulator fails to launch the new build). The gate is **opt-in per-project** via a `runtime:` frontmatter declaration; repos without one get a no-op (preserves today's behavior on meta-tooling repos like MonsterFlow itself). When `runtime:` is set, autorun runs a configurable per-target smoke check; only `status: pass` qualifies for `auto_merge_policy: validated`. **Any non-pass result (`fail`, `skipped`, `error`) falls back to `pr` (NOT `clean`)** — uniform safe default matching the asymmetric-risk argument in `autorun-merge-policy`.

## Backlog Routing

Carved from in-conversation review 2026-05-08 alongside `autorun-merge-policy`. Together they close the "auto-merge without runtime validation" gap. This spec adds the validation gate; the policy spec adds the merge knob that consumes it. They ship independently — merge-policy lands first with `validated` falling back to `pr`; this spec lights up the `validated → pass → auto-merge` path once shipped.

## Cross-Spec Dependencies

This spec extends `autorun-merge-policy`'s `reason` enum by adding one new value: `runtime_not_pass`. When this spec lands, the merge-policy spec's enum is updated additively (no breaks to existing `reason` values). Audit row gains a `details.runtime_status` field carrying the validator's actual status (`pass | fail | skipped | error`) for forensic granularity, even though all non-pass collapse to one `reason`.

## Definitions

### Validator status enum (closed set)

- `pass` — validator confirms artifact works
- `fail` — validator ran and detected a real failure (test failure, HTTP non-200, console errors, missing selector)
- `skipped` — validator could not run (missing dependency, simulator unavailable, no shadow trust); not a defect signal
- `error` — validator crashed / timed out / didn't write sidecar; treated as load-bearing failure (validator broke, can't trust the result)

### Merge-policy interaction (cross-spec contract)

When `auto_merge_policy: validated` is resolved AND this spec is shipped:
- Validator `status: pass` → merge-policy proceeds to `is_clean_for_merge()` predicate; if predicate satisfied, auto-merge fires
- Validator `status: fail | skipped | error` → merge-policy falls back to `pr`; run.log records `action: fell_back, reason: runtime_not_pass, details: {runtime_status: <actual>}`

Per-status fall-through to `pr` is uniform — no granular fallback to `clean` for skipped/error (Codex H1: anything weaker than `pass` recreates the asymmetric risk).

### Runtime config source-of-truth

Resolver reads `runtime` and `runtime_config` from `$SPEC_FILE` (= `queue/<slug>.spec.md`, the runtime queue copy that autorun executes), matching `auto_merge_policy` resolution per `autorun-merge-policy` spec. Editing `<project>/docs/specs/<slug>/spec.md` after queue copy was made does NOT affect in-flight runtime validation — queue file is canonical for the run.

## Scope

**Applies to:** autorun only.

**In scope:**
- New optional frontmatter key `runtime: web | ios | cli | none` in spec.md. `none` = explicit no-op (intent recorded as "no runtime target by design"). Absent = same behavior as `none` but no audit-log clarity.
- New optional `runtime_config:` block in spec.md frontmatter for per-target tuning (read from `$SPEC_FILE`):
  - `web` → `target_url`, `dev_server_cmd` OR `static_dir` (mutually exclusive), `wait_for_selector`, `console_error_allowlist[]`, optional `timeout_seconds`
  - `ios` → `xcodeproj`, `scheme`, `simulator_name`, **`test_plan` (REQUIRED)**, optional `timeout_seconds`
  - `cli` → `cmd`, `happy_path_args`, `expected_stdout_contains` (optional regex), optional `timeout_seconds`
- New per-target validator scripts under `scripts/runtime-validators/`:
  - `web.sh` — playwright headless visit + console-error scan + HTTP 200 assertion against `target_url` (which is either a `dev_server_cmd`-started server OR a `static_dir`-served ephemeral `python3 -m http.server`)
  - `ios.sh` — `xcodebuild test` with REQUIRED `test_plan` (forces explicit smoke scope; full suites belong in `/build`'s verification phase, not autorun runtime gate)
  - `cli.sh` — invoke `<cmd> --help` (exit 0 + non-empty stdout) plus optional `<cmd> <happy_path_args>` invocation (exit 0 + optional regex stdout match)
- Shared helper at `scripts/runtime-validators/_lib.sh` — sidecar writer, log capture, hard timeout enforcement (via `gtimeout` on macOS, `timeout` on Linux), TOFU shadow-validator helper.
- Hybrid TOFU shadow-validator trust model:
  - Engine validator path: `scripts/runtime-validators/<target>.sh` (always trusted; ships with MonsterFlow).
  - Shadow path: `<project>/.monsterflow/runtime-validators/<target>.sh` (per-project override).
  - **Interactive mode (tty detected):** if shadow exists and no `.trusted-hashes.json` entry matches its current SHA-256, prompt the user with: file path, first-line shebang, file size, full content (or paged). User approves → hash recorded → executed. Hash mismatch on subsequent runs → halt with diff display.
  - **Autorun mode (non-tty):** if shadow exists AND its hash matches `.trusted-hashes.json` → run shadow. Otherwise silent-skip shadow + stderr-warn `[autorun] shadow validator at <path> not pre-trusted; using engine validator. Run interactively first to approve.` + fall back to engine validator.
  - Trust file: `<project>/.monsterflow/runtime-validators/.trusted-hashes.json` (gitignored by default; user opts to commit if desired).
- Autorun integration: after `/build` succeeds, before `merge_policy_dispatch`, dispatch the runtime validator if `runtime:` is set and `runtime != none`. Validator stdout/stderr captured to `queue/<slug>/runtime-validation.log`; pass/fail recorded to `queue/<slug>/runtime-validation.json` sidecar.
- New schema: `schemas/runtime-validation.schema.json` — captures target, status, exit code, log path, duration, target-specific facts.
- Audit log row in `queue/run.log` per validation: `runtime_validated` event with `target`, `status`, `duration_seconds`, `sidecar_path`, `validator_path` (engine vs shadow).
- **Cross-spec change:** add `reason: runtime_not_pass` to merge-policy's `reason` enum; add `details.runtime_status` to merge-policy's audit row when the cause is runtime validation.
- **PR body templating:** when `validated` fails (validator non-pass), autorun's `gh pr create --body` includes: `## Runtime validation: <STATUS>` section linking to `queue/<slug>/runtime-validation.log` and (if web/ios) `queue/<slug>/runtime-fail.png`.
- 9 test fixtures + 1 schema-validation test (covers each runtime target, each status, TOFU trust, static_dir, dependency-missing, validator-crash, cross-spec merge-policy fallback).

**Out of scope:**
- Other runtime targets: `mobile-android`, `desktop-electron`, `server-node`, `server-python` — extension-friendly architecture but only `web | ios | cli | none` in v1. Backlog: `runtime-validators-additional-targets`.
- Hosted CI integration (GitHub Actions matrix runners) — local-only validation in v1.
- Test framework wrappers — validators invoke `pytest`, `xcodebuild`, `npx playwright` directly; no opinionated framework.
- Performance budgets / Lighthouse / accessibility audits — quality gates, not smoke checks. Possible future spec.
- Auto-fix loops on runtime failure — runtime fail = halt + report. The 3-attempt iterative-resolution pattern is for `/check` blockers.
- Production deploy validation against staging/prod — deploy-pipeline concern, not autorun.
- Visual regression / screenshot diffing — `web.sh` captures screenshots on fail but doesn't compare to baselines. Backlog: `runtime-validators-visual-regression`.
- Multi-target in one spec (e.g., monorepo with web + ios). v1 is single-target; multi-target deferred. Backlog: `runtime-validators-multi-target`.
- Auth state / cookie management for `web` validator — spec author's responsibility via `dev_server_cmd` setup (e.g., bake test-user cookies into the dev server's seed data). Backlog: `runtime-validators-web-auth`.

## Approach

**Chosen:** target-detector + dispatcher pattern with per-target shell validators + hybrid TOFU shadow trust + cross-spec audit consistency.

The `runtime:` value selects a validator at `scripts/runtime-validators/<target>.sh` (engine) or `<project>/.monsterflow/runtime-validators/<target>.sh` (shadow, TOFU-gated). Validator invoked with two args: the slug + path to spec.md. Runs synchronously, writes log + sidecar atomically, exits 0 on pass / non-zero on fail. Autorun reads sidecar to know verdict.

Validators decoupled from autorun's main loop. Per-project overrides allowed but trust-gated.

### `web.sh` mechanics

1. Resolve serving strategy:
   - `static_dir` set → start `python3 -m http.server <port> -d <static_dir>` in background; readiness wait on HTTP HEAD against `target_url` (which must point to the same port).
   - `dev_server_cmd` set → start in background subshell with PID tracked; 30-second readiness wait via HTTP HEAD against `target_url`.
   - Both set → exit `status: error` with stderr "static_dir and dev_server_cmd are mutually exclusive."
   - Neither set → assume `target_url` is externally-served (no setup; just navigate).
2. Use `npx playwright` (via `node_modules/.bin/playwright` if present in project; otherwise `npx`) to navigate to `target_url`, wait for `wait_for_selector` (default `body`), capture console events.
3. Pass = HTTP 200 + selector visible + no unallowlisted console errors.
4. On fail, capture screenshot to `queue/<slug>/runtime-fail.png`.
5. Tear down dev server (kill tracked PID + child processes).
6. **HTTPS/self-signed certs:** playwright invoked with `--ignore-https-errors` for dev convenience; logged in sidecar `details.https_errors_ignored: true` for audit.

### `ios.sh` mechanics

1. Resolve `xcodeproj` (from spec or by walking up to find a `.xcodeproj`).
2. **Validate `test_plan` is set in `runtime_config`** — if missing, exit `status: error` with stderr "test_plan is required for runtime: ios; full xcodebuild test suites belong in /build verification, not autorun runtime gate. Specify a smoke-scoped test plan."
3. Run `xcodebuild test -project <proj> -scheme <scheme> -destination 'platform=iOS Simulator,name=<simulator_name>' -testPlan <test_plan>`.
4. If tests pass, smoke-launch the built app on the simulator for 5 seconds, capture screenshot to `queue/<slug>/runtime-pass.png` (kept for audit even on pass).
5. Pass = test exit 0 + smoke launch produces non-empty screenshot.
6. Fail = capture failed test names + log excerpt to sidecar `details.failed_tests[]`.

### `cli.sh` mechanics

1. Invoke `<cmd> --help` — assert exit 0, stdout non-empty.
2. Invoke `<cmd> <happy_path_args>` — assert exit 0; if `expected_stdout_contains` set, assert regex match.
3. Pass = both exits 0 + regex matches if set.
4. Fail = capture stderr excerpt + actual exit code to sidecar `details.{stderr_excerpt, actual_exit_code, regex_matched}`.
5. **Working directory:** invoked from project root (autorun's `$PWD` at validator dispatch time). PATH inherited from autorun's environment. Spec author responsible for ensuring `<cmd>` is resolvable (installed binary, relative path, or build-artifact path).

Rejected alternatives:
- *Single mega-validator with target dispatch inside* — harder to extend, harder to unit-test.
- *Python validators instead of shell* — adds a dependency layer; shell is consistent with the rest of `scripts/autorun/`.
- *Run validation as part of `/build`'s verification phase* — coupling concern. /build is about diff correctness; runtime validation is about assembled-thing-works. Different scope, different failure-mode signals.
- *Make `runtime:` required for all specs* — over-rotates. Most MonsterFlow specs are config/docs/tooling without a runtime target. Default no-op is the right shape.
- *Trust-by-default for shadow validators* — silent-compromise vector for any third-party project. Hybrid TOFU is the right shape.
- *Disable shadow validators entirely* — removes a useful customization feature for trusted personal repos. TOFU is more nuanced.
- *Granular fallback (skipped → clean, error → halt)* — recreates the asymmetric risk per Codex H1. Uniform fall-back to `pr` is the safe default.
- *Optional `test_plan` for iOS* — full xcodebuild test suites can be 10+ min, blowing past the 5-min default timeout. Requiring `test_plan` forces explicit smoke scope.

## Roster Changes

No persistent roster changes. The `risk` reviewer persona at `/check` already evaluates whether a plan covers runtime/integration concerns; this spec just gives autorun a way to actually run the smoke check. `autorun-shell-reviewer` subagent gates the new shell scripts.

## UX / User Flow

**Spec-author opt-in (iOS):**
```yaml
runtime: ios
runtime_config:
  xcodeproj: apps/MyGame/MyGame.xcodeproj
  scheme: MyGame
  simulator_name: "iPhone 15 Pro"
  test_plan: SmokeOnly   # REQUIRED for ios
```

**Spec-author opt-in (web with dev server):**
```yaml
runtime: web
runtime_config:
  target_url: http://localhost:3000
  dev_server_cmd: "npm run dev"
  wait_for_selector: "[data-testid='app-loaded']"
  console_error_allowlist:
    - "Failed to load resource: the server responded with a status of 404"
```

**Spec-author opt-in (web static site):**
```yaml
runtime: web
runtime_config:
  target_url: http://localhost:8765
  static_dir: out
  wait_for_selector: "main"
```

**Spec-author opt-in (cli):**
```yaml
runtime: cli
runtime_config:
  cmd: "scripts/autorun/run.sh"
  happy_path_args: "--help"
  expected_stdout_contains: "Usage:"
```

**Autorun output on a passing run (with `auto_merge_policy: validated`):**
```
[autorun] /build complete
[autorun] runtime validation: target=web (engine validator)
[autorun] starting dev server: npm run dev (PID 4123)
[autorun] navigating to http://localhost:3000
[autorun] selector found, no console errors
[autorun] runtime validation: PASS (4.2s)
[autorun] auto_merge_policy=validated, gates clean, runtime pass → auto-merging
[autorun] merged: https://github.com/.../pull/42
```

**Autorun output on a failing runtime check (validated → pr fallback):**
```
[autorun] /build complete
[autorun] runtime validation: target=ios (engine validator, test_plan=SmokeOnly)
[autorun] xcodebuild test ... FAIL
[autorun] runtime validation: FAIL (45s) — 2 tests failed
[autorun] failed tests: GameSceneTests.testInitialState, GameSceneTests.testLevelLoad
[autorun] log: queue/my-feature/runtime-validation.log
[autorun] sidecar: queue/my-feature/runtime-validation.json
[autorun] auto_merge_policy=validated, runtime FAIL → falling back to pr
[autorun] PR opened: https://github.com/.../pull/42
[autorun] action=fell_back reason=runtime_not_pass details.runtime_status=fail
```

**Autorun output on shadow validator without TOFU (autorun mode):**
```
[autorun] runtime validation: target=cli (shadow at <project>/.monsterflow/runtime-validators/cli.sh detected)
[autorun] shadow validator not pre-trusted; using engine validator. Run interactively first to approve.
[autorun] runtime validation: PASS (engine, 2.1s)
```

**Interactive mode TOFU prompt (first encounter):**
```
[autorun] shadow validator detected at .monsterflow/runtime-validators/cli.sh
  size: 1247 bytes
  shebang: #!/bin/bash
  sha256: a3f5...

  Display full content? [y/n] y
  ... [content displayed]

  Trust this validator and record hash? [y/N] y
[autorun] hash recorded to .monsterflow/runtime-validators/.trusted-hashes.json
[autorun] runtime validation: PASS (shadow, 2.4s)
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
  "required": ["schema_version", "target", "status", "started_at", "duration_seconds", "log_path", "validator_path"],
  "properties": {
    "schema_version": {"type": "integer", "const": 1},
    "target": {"type": "string", "enum": ["web", "ios", "cli", "none"]},
    "status": {"type": "string", "enum": ["pass", "fail", "skipped", "error"]},
    "exit_code": {"type": "integer"},
    "started_at": {"type": "string", "format": "date-time"},
    "duration_seconds": {"type": "number"},
    "log_path": {"type": "string"},
    "validator_path": {"type": "string", "description": "Resolved validator script path — engine path under scripts/runtime-validators/ OR shadow path under <project>/.monsterflow/runtime-validators/"},
    "shadow_trust": {"type": "string", "enum": ["engine", "shadow_trusted", "shadow_untrusted_skipped"], "description": "Records whether shadow was used + trust path. Engine = no shadow exists; shadow_trusted = TOFU hash matched; shadow_untrusted_skipped = autorun-mode silent skip."},
    "details": {
      "type": "object",
      "description": "Target-specific facts. web: console_errors[], http_status, screenshot_path, https_errors_ignored. ios: failed_tests[], simulator_name, screenshot_path, test_plan. cli: stderr_excerpt, actual_exit_code, regex_matched."
    }
  }
}
```

Sidecar lives at `queue/<slug>/runtime-validation.json` (atomic write via tmp + `os.replace`). Log lives at `queue/<slug>/runtime-validation.log`. Pass screenshots at `queue/<slug>/runtime-pass.png` (ios only); fail screenshots at `queue/<slug>/runtime-fail.png` (web + ios on fail).

**Cross-spec audit row addition:**
- Add `reason: runtime_not_pass` to `autorun-merge-policy`'s `reason` enum.
- Add `details.runtime_status: pass | fail | skipped | error` to merge-policy's run.log row when the cause is runtime validation.

**TOFU trust file:** `<project>/.monsterflow/runtime-validators/.trusted-hashes.json`
```json
{
  "version": 1,
  "hashes": {
    "web.sh": {"sha256": "...", "approved_at": "...", "approved_by": "tty:user@host"},
    "cli.sh": {...}
  }
}
```

Gitignored by default in installed projects (per `install.sh` adding `.monsterflow/runtime-validators/.trusted-hashes.json` to project's `.gitignore`). User can opt to commit if they want shared-team trust.

## Integration

- `scripts/autorun/run.sh` — after `/build` succeeds, dispatch runtime validation if `runtime:` is set and != `none`. Read sidecar; pass result to `merge_policy_dispatch` per cross-spec contract.
- `scripts/runtime-validators/web.sh`, `ios.sh`, `cli.sh` — new files (~150-300 LoC each).
- `scripts/runtime-validators/_lib.sh` — shared helpers: `write_sidecar_atomic`, `enforce_timeout`, `tofu_resolve_validator`, `compute_sha256`, `prompt_tofu_approval`.
- `schemas/runtime-validation.schema.json` — new schema.
- Validator override path: `<project>/.monsterflow/runtime-validators/<target>.sh` shadows the global, gated by TOFU per Approach.
- Cross-spec edits to `autorun-merge-policy`:
  - Add `runtime_not_pass` to reason enum
  - Add `details.runtime_status` to audit row schema (additive; null when cause is not runtime)
  - Update merge-policy's `dispatch_validated_merge` to read `runtime-validation.json.status == "pass"` instead of falling back to clean
  - Update merge-policy's banner to reflect: "validated requires runtime validation pass"
- Tests: `tests/test-runtime-validation.sh` (~350 LoC, 9 fixtures + 1 schema-validation test).
- `commands/autorun.md` — document the new key, per-target config, validator override path, TOFU trust workflow, PR body templating on fail.
- `templates/constitution.md` — add commented-out `runtime:` example with explanatory note.
- `docs/index.html` — autorun section can mention the gate as in-flight or shipped once landed.
- `install.sh` — add `.monsterflow/runtime-validators/.trusted-hashes.json` to project `.gitignore` (additive line if section already exists).

Touched files: 1 modified shell script + 4 new shell scripts + 1 schema + 1 test file + 5 doc/config files + 4 cross-spec edits to autorun-merge-policy. Estimated ~1000-1400 LoC delta.

## Edge Cases

- **`runtime:` unset:** validator never invoked; merge-policy `validated` falls back to `pr` per cross-spec contract. `runtime: none` explicit-no-op gives same behavior with audit-log clarity (intent recorded as "no runtime target by design").
- **Validator dependency missing** (e.g., `npx playwright` not installed): validator exits `status: error`. Autorun continues; merge-policy `validated` falls back to `pr` with reason=runtime_not_pass + details.runtime_status=error. Stderr surfaces `[autorun] runtime validation: ERROR — playwright not found in project (run: npx playwright install)` so user knows what to fix.
- **Dev server fails to start within 30s readiness wait:** validator exits `status: error`; logs the wait timeout + last HTTP status. Falls back to `pr` per cross-spec contract.
- **Static_dir + dev_server_cmd both set:** validator exits `status: error` with stderr "static_dir and dev_server_cmd are mutually exclusive."
- **Simulator not available** (no Xcode, headless CI without macOS): `ios.sh` exits `status: skipped`. Falls back to `pr` per cross-spec contract.
- **`test_plan` missing for `runtime: ios`:** validator exits `status: error` with stderr message instructing user to specify a smoke-scoped test plan.
- **Console error allowlist matches a real bug:** allowlist is opt-in and explicit; spec author's responsibility. Sidecar records `details.console_errors_allowlisted[]` for audit.
- **HTTPS / self-signed certs in dev:** playwright invoked with `--ignore-https-errors`; sidecar logs `details.https_errors_ignored: true`. For prod-pinned validation, spec author can add a custom check to a shadow validator.
- **Auth state / cookies / sessions:** out of scope for v1. Spec author handles via `dev_server_cmd` (e.g., dev server seeded with test cookies). Backlog: `runtime-validators-web-auth`.
- **Long-running validators (>5 min):** hard timeout enforced via `gtimeout` (macOS coreutils) or `timeout` (Linux). Default 5 min per target, override via `runtime_config.timeout_seconds`. Timeout produces `status: error`. iOS with `test_plan` keeps default 5 min; full-suite users either set a long `timeout_seconds` or split tests via `test_plan`.
- **Validator script crash / segfault / exits before writing sidecar:** autorun catches missing-sidecar case via post-dispatch readiness check + writes synthetic sidecar with `status: error, details: {reason: "validator did not write sidecar"}`. Merge-policy falls back to `pr`.
- **Shadow validator exists but not in `.trusted-hashes.json` (autorun mode):** silent-skip shadow + stderr-warn + fall back to engine. `shadow_trust: shadow_untrusted_skipped` recorded in sidecar.
- **Shadow validator hash mismatch (interactive mode):** halt with diff display showing `<old hash> vs <current hash>` + first 50 lines of diff. User must re-approve or remove the shadow. Autorun mode never sees this — autorun only runs trusted-hash-matched shadows.
- **`.trusted-hashes.json` corrupt JSON:** validator's TOFU resolver catches the parse error, treats as if file didn't exist (silent skip in autorun, fresh prompt in interactive). User can `rm` and re-approve.
- **Per-project shadow has wrong shebang or non-executable:** validator's TOFU resolver checks `[ -x "$shadow_path" ]` after hash match. If not executable, log warning + fall to engine.
- **Multiple targets in one spec:** v1 single-target. Multi-target deferred. Backlog item.
- **`runtime_config` key typo** (e.g., `tagret_url`): validator's required-key check fails fast with stderr message naming the missing required key. No silent fall-through; spec author fixes.
- **Network-required validation in offline environment:** `web.sh` against external `target_url` times out. Validator's job to report; surfaces as `status: error` with timeout details.
- **Race with merge step:** validation runs before merge-policy resolution; sidecar atomic write completes before autorun reads it. No race.
- **Cleanup on validator success:** dev servers stopped (PID-tracked SIGTERM then SIGKILL), simulators unbooted (where applicable), screenshots retained for audit.
- **Cleanup on autorun-batch STOP:** validator finishes its current attempt + sidecar written; next iteration honors STOP. Mid-validation halts avoided by waiting for iteration boundary.
- **Cross-project queue (no canonical at `<project>/docs/specs/<slug>/spec.md`):** runtime config drift detector inherits behavior from merge-policy's drift detector — silent-skip when canonical missing.

## Acceptance Criteria

1. New optional frontmatter key `runtime: web | ios | cli | none` accepted in `spec.md` with optional `runtime_config:` block read from `$SPEC_FILE` (queue copy).
2. Validator scripts at `scripts/runtime-validators/{web,ios,cli}.sh` ship with the engine; project shadows at `<project>/.monsterflow/runtime-validators/<target>.sh` override the global via hybrid TOFU.
3. Validator outputs `queue/<slug>/runtime-validation.json` (matches `schemas/runtime-validation.schema.json`) and `queue/<slug>/runtime-validation.log`.
4. `web.sh` validator: starts optional dev server (via `dev_server_cmd`) OR ephemeral static server (via `static_dir`) — mutually exclusive — then navigates via headless playwright with `--ignore-https-errors`, asserts HTTP 200 + selector visible + no unallowlisted console errors, captures screenshot on fail.
5. `ios.sh` validator: **REQUIRES `test_plan` in `runtime_config`** (rejects with `status: error` if missing); runs `xcodebuild test -testPlan <plan>` against configured project/scheme/simulator; smoke-launches built app on success.
6. `cli.sh` validator: asserts `--help` exit 0 + non-empty stdout, plus optional happy-path args invocation with regex stdout match.
7. Validators write `status: pass | fail | skipped | error` distinguishing real failures from missing dependencies.
8. Validator timeout: 5-min default per target, override via `runtime_config.timeout_seconds`. Timeout produces `status: error`, not `fail`.
9. Autorun runs the validator after `/build` and before `merge_policy_dispatch`; sidecar consumed by merge-policy per cross-spec contract.
10. **Cross-spec safety contract:** any non-pass validator status (`fail`, `skipped`, `error`) → merge-policy falls back to `pr` (NOT `clean`) with `reason=runtime_not_pass, details.runtime_status=<actual>`.
11. `runtime:` unset OR `runtime: none` → validator step skipped (no-op); merge-policy `validated` falls back to `pr` with stderr warning.
12. Validator dependency missing (e.g., playwright) → `status: error`, autorun proceeds; merge-policy falls back to `pr`.
13. **Hybrid TOFU shadow trust:** interactive mode prompts user with file path + size + shebang + content + sha256 → on approval, hash recorded to `.trusted-hashes.json` → subsequent runs verify hash. Autorun mode silent-skips shadow when hash absent + falls back to engine + emits stderr warning.
14. Shadow hash mismatch in interactive mode → halt with diff display; user must re-approve or remove shadow.
15. `queue/run.log` records one `runtime_validated` event per slug with target, status, duration_seconds, sidecar_path, validator_path (engine vs shadow), shadow_trust value.
16. **PR body templating on fail:** when validator status is non-pass AND `auto_merge_policy: validated` was the policy, `gh pr create --body` includes a `## Runtime validation: <STATUS>` section linking to log + sidecar + screenshot (if web/ios).
17. `commands/autorun.md` documents the new key, per-target config, TOFU trust workflow, PR body templating, validator override path, fallback behavior.
18. `templates/constitution.md` includes a commented-out `runtime:` example with explanatory note.
19. **Cross-spec changes to `autorun-merge-policy`:** (a) add `runtime_not_pass` to `reason` enum; (b) add `details.runtime_status` field to audit row; (c) update `dispatch_validated_merge` to read `runtime-validation.json.status == "pass"`; (d) update banner to reflect runtime-validation requirement when policy is `validated`. All four edits land in the same PR as this spec.
20. `install.sh` adds `.monsterflow/runtime-validators/.trusted-hashes.json` to project `.gitignore` (additive; idempotent).
21. Test fixture: `runtime: none` → no validator dispatched, run.log records skip, merge-policy resolved to `pr` fallback (cross-spec).
22. Test fixture: `runtime: cli` against happy-path command → `status: pass`, sidecar matches schema, merge-policy proceeds.
23. Test fixture: `runtime: cli` against failing command (exit 1) → `status: fail`, exit_code captured, merge-policy falls back to `pr` with reason=runtime_not_pass, details.runtime_status=fail.
24. Test fixture: `runtime: web` with `static_dir` and known-good fixture page → `status: pass`.
25. Test fixture: `runtime: web` with `dev_server_cmd` (mocked) → dev server PID tracked + cleaned up; status: pass.
26. Test fixture: `runtime: ios` with no simulator available → `status: skipped`, merge-policy falls back to `pr`.
27. Test fixture: `runtime: ios` without `test_plan` → `status: error` with stderr message; merge-policy falls back to `pr`.
28. Test fixture: invalid `runtime: foo` value → exit 2 at frontmatter parse, no validator dispatched.
29. Test fixture: shadow validator without TOFU (autorun mode) → silent-skip shadow + stderr warning + engine validator runs + sidecar.shadow_trust = shadow_untrusted_skipped.
30. Test fixture: shadow validator with valid TOFU hash → shadow runs, sidecar.shadow_trust = shadow_trusted, validator_path = shadow path.
31. Test fixture: validator script crashes before writing sidecar → autorun writes synthetic sidecar with status: error; merge-policy falls back to `pr`.
32. Schema validator (`scripts/_validate_runtime_validation_sidecar.py` or equivalent) accepts well-formed sidecars; rejects malformed ones (missing required fields, unknown status values).
33. `autorun-shell-reviewer` subagent passes a clean review against new validator scripts per its 13-pitfall checklist (PIPESTATUS around `npx`/`xcodebuild`/`gtimeout`, explicit pathspec, no `git add -A`, AppleScript-injection check on macOS path).
34. **VERSION + CHANGELOG bump:** if shipping after `autorun-merge-policy` (which is v0.11.0), this spec ships as v0.12.0 with CHANGELOG entry under `## [0.12.0]` describing the runtime-validation gate addition + cross-spec changes to merge-policy.

## Open Questions

- **Q1 (resolved by Q3 in this session):** should the `web` validator support `static_dir` for static-site projects? **Resolved: yes** — shipped in v1 with `static_dir` and `dev_server_cmd` mutually exclusive.
- **Q2 (resolved):** should validation happen on its own dedicated branch? **Resolved: no** — validators run sandboxed by convention (PID-tracked dev server in subshell, simulator isolated). Branch isolation adds complexity for ambiguous gain.
- **Q3 (resolved by Q3 in this session):** should validator output be attached to PR body when `validated` fails? **Resolved: yes** — shipped in v1; AC#16 templates the PR body section.
- **Q4 (resolved by Q1 in this session):** should missing-dependency error halt the run or fall through? **Resolved: fall through with stderr warning + fall back to `pr`** per cross-spec safety contract. Halting would punish good intent (forward-compat user opting into validated).
- **Q5 (resolved):** can the validator be parallelized with /build's verification phase? **Resolved: no** — runtime validation is post-build by definition. Parallelizing would couple phases and obscure failure-mode signals.
- **Q6 (resolved by Q1 in this session):** should `validated` fall back to `clean` or `pr` when validator is non-pass? **Resolved: `pr` (uniform safe default)** per Codex H1 reasoning shared with autorun-merge-policy spec.
- **Q7 (resolved by Q2 in this session):** what's the trust model for shadow validators? **Resolved: hybrid TOFU** — interactive prompt + hash record on first encounter; autorun mode silent-skips untrusted shadows.
- **Q8 (deferred to backlog):** auth state / cookie management for `web` validator? **Deferred** — spec author handles via `dev_server_cmd` setup in v1; future spec `runtime-validators-web-auth` covers richer auth flows.
- **Q9 (deferred to backlog):** visual regression / screenshot diffing? **Deferred** — `web.sh` captures fail screenshots in v1; comparison against baselines is `runtime-validators-visual-regression`.
- **Q10 (deferred to backlog):** multi-target spec support? **Deferred** — single-target v1; `runtime-validators-multi-target` covers array-form `runtime: [web, ios]` + aggregator policy.
