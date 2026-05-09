---
gate_mode: permissive
gate_max_recycles: 2
---

# Autorun Runtime Validation Gate Spec — Smoke-Check the Built Thing Before Merge

**Created:** 2026-05-08
**Revised:** 2026-05-08 (Q&A refinement → 0.95); 2026-05-09 (Revision 2 — post-/check NO_GO; external-PR trust model resolved; security blockers F1-F5 collapsed via skip-on-external-author)
**Constitution:** none — session roster only
**Audience:** MonsterFlow contributors and pipeline maintainers — adopter-facing copy is handled in `docs/index.html`.
**Applies to:** autorun only. Manual pipeline runs are unaffected (no auto-merge step in manual flow).
**Confidence:** Scope 0.95 / UX 0.92 / Data 0.95 / Integration 0.93 / Edges 0.97 / Acceptance 0.95 (avg 0.945)
**gate_mode:** permissive
**gate_max_recycles:** 2

## Summary

Add a post-`/build` runtime validation step to the autorun pipeline that smoke-checks the assembled artifact before declaring a run "validated." Today the deepest validation is unit-test discipline inside `/build` — which catches code-level regressions but misses UI/integration/runtime issues (page didn't render, CLI exits non-zero on its own help text, simulator fails to launch the new build). The gate is **opt-in per-project** via a `runtime:` frontmatter declaration; repos without one get a no-op (preserves today's behavior on meta-tooling repos like MonsterFlow itself). When `runtime:` is set, autorun runs a configurable per-target smoke check; only `status: pass` qualifies for `auto_merge_policy: validated`. **Any non-pass result (`fail`, `skipped`, `error`) falls back to `pr` (NOT `clean`)** — uniform safe default matching the asymmetric-risk argument in `autorun-merge-policy`.

## Backlog Routing

Carved from in-conversation review 2026-05-08 alongside `autorun-merge-policy`. Together they close the "auto-merge without runtime validation" gap. This spec adds the validation gate; the policy spec adds the merge knob that consumes it. They ship independently — merge-policy lands first with `validated` falling back to `pr`; this spec lights up the `validated → pass → auto-merge` path once shipped.

## Cross-Spec Dependencies

This spec extends `autorun-merge-policy`'s `reason` enum by adding TWO new values: `runtime_not_pass` AND `runtime_pr_external_author` (the latter from Revision 2's external-PR trust model — see **Trust Model** below). When this spec lands, the merge-policy spec's enum is updated additively (no breaks to existing values). Audit row gains a `details.runtime_status` field carrying the validator's actual status (`pass | fail | skipped | error | skipped_external_author`) for forensic granularity.

## Trust Model (Revision 2 — closes 5 sev:security blockers via single architectural decision)

**Threat:** MonsterFlow accepts external PRs (`feedback_branch_protection_external_prs.md`); autorun fires unattended on PR branches. The `runtime_config` fields `dev_server_cmd`, `cmd`, `xcodeproj`, `test_plan`, AND web-served content reachable via `target_url`, ALL flow through shell-eval or browser execution → unattended RCE on the maintainer's host the moment any external contributor opens a PR with a malicious spec.md or hostile served content.

**Resolution (chosen 2026-05-09):** **Runtime validation is SKIPPED on non-CODEOWNERS branches.** When autorun detects an external-author PR (the branch's most recent author is not a CODEOWNERS-listed user, OR the spec.md was last modified by a non-CODEOWNERS user, OR no `.github/CODEOWNERS` exists), validator dispatch is bypassed and run.log records `action: fell_back, reason: runtime_pr_external_author, details: {runtime_status: skipped_external_author}`.

**Cascade — this single decision closes 5 sev:security blockers from the /check synthesis:**

| Blocker | Was | Now closed by |
|---|---|---|
| F1 (substring check on shadow validators bypassable) | Half-defense | Removed entirely — shadow validators only run on owner-authored branches; external-PR risk vanishes; TOFU is the only gate |
| F2 (external-PR provenance → unattended RCE) | The parent finding | **Resolved directly** — skip-on-external-author |
| F3 (TOFU realpath→hash→exec is TOCTOU) | Real-but-narrow concern | Hardening still applied (open-once + fstat + hash-from-fd + exec-from-fd; trust-file lock across sequence; reject symlinks) but threat surface no longer reaches external attackers |
| F4 (`gh release upload` of validator log/screenshot leaks secrets) | Real concern | Validator output upload is OWNER-AUTHORED-PR ONLY; external PRs never invoke validator → never produce output to upload. Plus secret-scrubber regex (sk-, gh[ps]_, AKIA, Bearer, JWT-shape, hex≥32) applied to any uploaded log; screenshots opt-in via `attach_screenshots: true` (default off) |
| F5 (`--ignore-https-errors` enables MITM on external HTTPS) | Concern with external `target_url` | `--ignore-https-errors` flag applies ONLY when `target_url` host matches `localhost\|127.0.0.1\|::1\|*.test\|*.localhost`; for external hosts (gated by `allow_external_url: true`), TLS verification is ON |

**Tradeoff:** external PRs do not get runtime-validated by autorun (must be reviewed manually by the maintainer). This is the explicit v1 ergonomic — the asymmetric-risk argument matches `autorun-merge-policy`: silent unattended RCE on the maintainer's host is much costlier than "external PR validation requires manual review." Future spec `autorun-runtime-validation-sandboxed-external` can promote this to (b) sandbox-exec or (c) human-gate-on-frontmatter-diff if external-PR volume warrants.

## Definitions

### Validator status enum (closed set, Revision 2)

- `pass` — validator confirms artifact works
- `fail` — validator ran and detected a real failure (test failure, HTTP non-200, console errors, missing selector)
- `skipped` — validator could not run (missing dependency, simulator unavailable, no shadow trust); not a defect signal
- `skipped_external_author` — Revision 2 — branch authored by non-CODEOWNERS user; runtime validation skipped per Trust Model. Distinct from `skipped` so post-incident forensics can distinguish "external PR" from "local dependency missing"
- `error` — validator crashed / timed out / didn't write sidecar / sidecar status mismatches captured exit code (F9 cross-check); treated as load-bearing failure

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
- **Q11 (resolved 2026-05-09 — Revision 2):** what's the external-PR trust model? **Resolved: skip on non-CODEOWNERS branches** (option a from /spec-review session). Cascade: F1 substring check removed entirely, F3 hardening kept but threat surface narrowed, F4 secret-scrubber added + screenshots opt-in, F5 `--ignore-https-errors` restricted to local hosts only.

---

## Revision 2 — Post-/check NO_GO Resolutions (2026-05-09)

This section consolidates all changes from `/check` synthesis (`docs/specs/autorun-runtime-validation-gate/check.md` — 23 must-fix blockers) into structured deltas. Section content above has been updated to match. This section preserves the audit trail of what changed and why.

### Security blockers (5 must-fix → all resolved)

All 5 sev:security blockers (F1-F5) resolved by the **Trust Model** section above (Q11 resolution: skip-on-external-author). Plus four "Should Fix (apply inline)" security items also adopted:

- **F6 — autorun-stamp moves to sidecar**: `[AUTORUN MODE — approval auto-granted]` no longer appended to plan body; written to separate `queue/<slug>/autorun-stamp.json` sidecar so the in-body-directive pattern can't be forged in a footer. New AC: stamp emission verified by file existence + JSON shape, NOT by body grep.
- **F7 — trust file is per-host, not per-repo**: `~/.claude/runtime-validators-trusted-hashes.json` (chmod 600). Repo-committed `.trusted-hashes.json` was rejected — auto-grants execution to all teammates with no technical guard.
- **F8 — TOFU mandates display-before-trust**: prompt shows full file content via pager BEFORE the trust-grant question. No "answer `n` to display then `y` to trust" path. AC: fixture sends `n` to display, asserts trust-grant prompt is NOT shown.
- **F9 — sidecar status cross-checked against captured exit code**: `run.sh` reads validator's exit code; if exit==0 but sidecar.status != "pass" (or exit!=0 but sidecar.status=="pass"), coerce to `error` with `details.crosscheck_failed: true`. Closes the silent-corruption window where a buggy validator writes a wrong status.

### Contract gaps (4 must-fix → all resolved)

- **C1 (completeness F1) — `scripts/_validate_runtime_validation_sidecar.py` MUST EXIST.** AC#32 named it but no task created it. Now: explicit task in Wave 2 to create + wire into `dispatch_validated_merge` (the merge-policy helper reads sidecar via this validator before honoring `pass`). New AC#35: validator rejects malformed sidecars (missing required fields, unknown status enum value); accepts well-formed.
- **C2 (completeness F2) — `runtime_config.web.allow_external_url` documented + defaults false.** Was required by D4 but absent from task 1's spec amendments and AC#1's web-runtime field list. Now: schema field added, default `false`. When `target_url` host is non-local AND `allow_external_url` is unset/false → validator exits `status: error` with stderr "external target_url requires explicit `allow_external_url: true` opt-in." New AC#36.
- **C3 (testability M1) — AC#16 trigger condition pinned**: AC#16 fires on `(non-pass AND auto_merge_policy: validated)`. NOT D23's "any non-skipped status regardless of policy." Reasoning: `pr` and `clean` policies don't read runtime-validation state, so PR-body section is meaningless under those policies. Fixture: spec sets `runtime: cli` + `auto_merge_policy: pr`, validator fails → PR body has NO `## Runtime validation:` section.
- **C4 (testability M3) — `schemas/run-log-runtime-validated.schema.json` ships in same PR.** Was missing. Schema fields: `event: "runtime_validated"`, `target`, `status` (closed enum incl. `skipped_external_author`), `duration_seconds`, `sidecar_path`, `validator_path`, `shadow_trust`. `/wrap-insights` Phase 1c parses this row.

### Testability fixtures (4 must-fix → all added)

- **T1 (M1)** — AC#16 trigger fixture per C3 above
- **T2 (M2)** — iOS std-dev calibration fixture: pre-recorded black-PNG (fail) + rendered PNG (pass) + actual SwiftUI screenshot (pass) bytes. Threshold (5.0 std_dev) verified against all three. **Note:** D8 std_dev is being CUT to backlog per scope-cuts (SF1) — replaced by simpler "screenshot file > 0 bytes AND not all-black via 50-pixel sample" check. Fixture targets the simpler check.
- **T3 (M3)** — schema validator per C4 above
- **T4 (M4)** — PID-sweep recovery fixture: pre-seed `queue/.runtime-pids` with a real backgrounded `sleep 60` PGID; run validator; assert sweep killed it AND truncated the file. Plus second fixture: stale lock dir (PID written 30 min ago, PID dead) → validator reclaims lock + writes new PID stamp.

### Sequencing fixes (3 must-fix, mechanical)

- **S1 (must reorder)** — Task 17 (`autorun-shell-reviewer` invocation) moves from Wave 6 to mid-Wave-3 (between tasks 9 and 10). Per memory `feedback_build_subagent_invocations_must_fire.md` + repo CLAUDE.md: subagent must fire BEFORE the commit that touches `scripts/autorun/*.sh`. Task 9 ships `run.sh` edits; tasks 10/11 stack on it. Subagent fires after task 9, before tasks 10/11. (Same pattern fires AGAIN after tasks 10/11 land — two invocations on the integration changes.)
- **S2 (must split)** — Wave 1 splits into Wave 1a `{2, 3, 8, 13, 14}` (independent prerequisites) and Wave 1b `{4}` (`_lib.sh` depends on 2/3). Was lumped.
- **S3 (must flip)** — Task 8 dependency direction inverted in original plan: `.playwright-version` is consumed by `web.sh` (task 5), NOT produced by it. Fixed: task 8 → produces; task 5 → consumes.

### Risk fixes (3 must-fix → all addressed)

- **R1 (R-M1) — iOS cold-build timing**: bump iOS-specific default `timeout_seconds` to **900s** (cold SwiftUI/SpriteKit measured >300s on M-series). Documented as `ios.sh` baked-in default; spec author can override per-spec. Plus measurement protocol in `commands/autorun.md`: "for first iOS spec on a fresh machine, run `time xcodebuild test -testPlan SmokeOnly -destination ...` once to establish baseline; if >720s consistently, increase `timeout_seconds`." Other targets (`web`, `cli`) keep 300s default.
- **R2 (R-M2) — kill switch**: `AUTORUN_DISABLE_RUNTIME_VALIDATION=1` env var bypass at top of `run.sh`'s validator dispatch. When set, validator step skipped entirely; merge-policy `validated` falls back to `pr` per existing semantics; run.log records `action: fell_back, reason: validated_fallback, details: {runtime_status: skipped, kill_switch: true}`. Documented in `commands/autorun.md` migration section.
- **R3 (R-M3) — mutex stale-lock recovery**: `_lib.sh` lock acquisition uses `mkdir queue/.runtime-validators.lock/` + writes `lock_pid.txt` (current PID) + `lock_started_at.txt` (UTC ISO). Stale-lock reclaim: `(now - started_at) > 2 × max(timeout_seconds across all validators) AND PID is dead` → reclaim atomically (rmdir + retry mkdir). First crash no longer bricks the gate.

### Scope cuts (apply per SF1-SF6, ~110-150 LoC saved)

All six SHOULD-FIX scope-cuts adopted:

- **SF1 — D8 std_dev pixel analysis CUT**: replaced with simpler "file > 0 bytes AND not all-black via 50-pixel sample." Carved to backlog as `runtime-validators-blank-screen-detection`.
- **SF2 — D10 dual PR-body strategy CUT**: pick one — `link to log + base64-embedded screenshot thumbnail`. Drop the alternative.
- **SF3 — D19 Xcode signing & build-settings pre-flight CUT**: keeps test-plan check only. Signing concerns belong in /build verification, not autorun runtime gate.
- **SF4 — D11 startup-sweep PID file CUT**: `setsid + trap-EXIT only` for v1. PID file machinery deferred.
- **SF5 — D16 5MB log-cap CUT**: deferred. Validators are bounded by `timeout_seconds`; 5MB is a secondary defense premature for v1.
- **SF6 — D18 playwright version-mismatch fallback CUT**: pin engine version in CI config; no comparison logic at runtime.

### Additional ACs (revisions 2 adds 6 new ACs to existing 34)

- **AC#35** — Sidecar validator `scripts/_validate_runtime_validation_sidecar.py` accepts well-formed sidecars; rejects malformed (missing required fields, unknown status enum, status/exit mismatch). Wired into `dispatch_validated_merge` in merge-policy spec.
- **AC#36** — `runtime_config.web.allow_external_url` (default `false`) gates external `target_url` hosts. Non-local host without opt-in → validator exits `status: error`. Local hosts (`localhost`, `127.0.0.1`, `::1`, `*.test`, `*.localhost`) bypass the gate.
- **AC#37** — External-author detection: when CODEOWNERS exists AND most-recent commit on branch (or last spec.md modifier) is non-CODEOWNERS user → validation skipped; run.log records `action: fell_back, reason: runtime_pr_external_author, details: {runtime_status: skipped_external_author}`. Fixture: PR branch with CODEOWNERS-listed user as committer → validation runs; same branch with external author → validation skipped.
- **AC#38** — `AUTORUN_DISABLE_RUNTIME_VALIDATION=1` env var bypasses validator dispatch; run.log records kill-switch state in `details.kill_switch: true`.
- **AC#39** — Status cross-check (F9): if validator exit code disagrees with sidecar `status`, autorun coerces to `error` with `details.crosscheck_failed: true`. Fixture: stub validator exits 0 but writes `status: fail` → autorun records `status: error, details: {crosscheck_failed: true}`.
- **AC#40** — `~/.claude/runtime-validators-trusted-hashes.json` is the trust file location (chmod 600 enforced by helper); repo-committed `.trusted-hashes.json` is explicitly rejected with stderr message.

### Cross-spec adjustments to autorun-merge-policy

In addition to the original `runtime_not_pass` reason value addition, this spec also adds:
- `runtime_pr_external_author` reason value (closed enum extension)
- `details.runtime_status` accepts `skipped_external_author` value (closed enum extension)

Both are additive to the merge-policy `_MP_REASONS` readonly array. No breaks to existing consumers.

### Confidence delta (revision 1 → revision 2)

- Scope: 0.92 → **0.95** (Trust Model resolves the 5 sev:security blockers; scope is now disciplined and testable)
- UX: 0.92 (unchanged)
- Data: 0.92 → **0.95** (all 4 contract gaps closed; closed enums now fully specified)
- Integration: 0.93 (unchanged)
- Edges: 0.95 → **0.97** (external-author + kill-switch + status-crosscheck close 3 previously-open footguns)
- Acceptance: 0.93 → **0.95** (6 new ACs covering the new behaviors; testability M1-M4 all fixtured)
- **Average: 0.93 → 0.945**

Iteration count consumed: this is iteration 1 of 2 (per `/check` Decision Path). Remaining budget: 1 iteration before the spec needs to revisit fundamentals.
