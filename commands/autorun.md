---
description: Run the full pipeline headlessly overnight — spec-review → plan → check → build → PR → merge
---

## Action

**Your only job is to invoke the shell pipeline. Do NOT orchestrate this in-session.**

1. Confirm `queue/<slug>.spec.md` exists in the current project. If not, copy it:
   ```bash
   cp docs/specs/<slug>/spec.md queue/<slug>.spec.md
   ```
2. Run the pipeline in a detached tmux window so it survives session end:
   ```bash
   tmux new-window -n autorun 'autorun start; echo "[autorun] done — press enter"; read'
   ```
   Or to run inline (blocks until complete):
   ```bash
   autorun start
   ```
3. Confirm it started with `autorun status`.

Do NOT read the stage commands (spec-review.md, design.md, etc.) and simulate them yourself. The entire pipeline is driven by `scripts/autorun/run.sh` via the `autorun` CLI.

---

## Overview

`/autorun` orchestrates the existing 8-command pipeline headlessly while you sleep. It is not a replacement for the interactive workflow — you write specs interactively via `/spec` as usual, then drop the result into `queue/` and let `/autorun` drive everything else. It runs as a local process via launchd or a detached tmux session and exits cleanly on the next morning.

---

## Quick Start

1. **Queue a spec:**
   ```bash
   cp docs/specs/myfeature/spec.md queue/myfeature.spec.md
   ```

2. **Start the run:**
   ```bash
   autorun start
   # or, raw invocation:
   flock -n queue/.autorun.lock bash scripts/autorun/run.sh
   ```

3. **Check progress mid-run:**
   ```bash
   autorun status
   ```

4. **Morning check:**
   ```bash
   cat queue/index.md
   ```

---

## Merge Policy (v0.11.0+)

Autorun's merge behavior is controlled by `auto_merge_policy`:

- **`pr`** (default since v0.11.0) — autorun opens a PR and stops. You merge it
  manually after morning review.
- **`clean`** — autorun opens a PR and auto-merges via `gh pr merge --squash
  --auto` if the four-axis gate passes (`MERGE_CAPABLE == 1` AND
  `CODEX_HIGH_COUNT == 0` AND `RUN_DEGRADED == 0` AND mode-aware verdict).
  Under `gate_mode: permissive`, the verdict requires `GO` (NOT
  `GO_WITH_FIXES`). Under `gate_mode: strict`, both `GO` and `GO_WITH_FIXES`
  are accepted.
- **`validated`** — RESERVED. Falls back to `pr` until
  `autorun-runtime-validation-gate` ships. Banner stderr-warns once at run
  start; run.log records `action=fell_back, reason=validated_fallback`.

### Resolution Precedence

CLI flag > spec frontmatter > project constitution > hardcoded default (`pr`).

```bash
# Per-run override (top precedence):
scripts/autorun/run.sh --merge-policy=clean my-feature
# Legacy spelling (deprecated; emits one-line stderr notice each run):
scripts/autorun/run.sh --auto-merge=clean my-feature
```

```yaml
# Per-spec (queue/<slug>.spec.md frontmatter):
---
auto_merge_policy: clean
---
```

```yaml
# Project-wide (<project>/docs/specs/constitution.md frontmatter):
---
auto_merge_policy: clean
---
```

### Run-Start Banner

Autorun emits a 4-knob runtime-config banner to stdout BEFORE Phase 0b
dispatch (D10 / R7). Knobs displayed: `auto_merge_policy`, `agent_budget`,
`gate_mode`, `gate_max_recycles`. Each line shows the resolved value and its
`resolved_from=<cli|spec|frontmatter|constitution|config|default>`.

The merge-policy line warns on every run where `resolved_from=default` until
the user explicitly chooses any value (banner fires forever-until-opt-in; no
sentinel suppression). To silence the warning, set `auto_merge_policy: pr`
(or any value) in spec or constitution frontmatter.

### Per-Run Escape Hatch

To skip auto-merge for a single run regardless of resolved policy, touch:

```bash
mkdir -p queue/<slug>     # required if dir does not exist yet
touch queue/<slug>/.manual-review
```

`merge_policy_dispatch` checks for this file immediately before merge and
records `action=fell_back, reason=manual_review_requested`. PR stays open.

### Audit Trail

Two events per slug, both on `queue/run.log` (JSONL), joinable on
`(slug, run_id)`:

- `event=merge_policy_resolved` — written immediately after policy resolution
  at run start. Captures `policy`, `resolved_from`, `gate_mode`, `spec_sha`
  (immutable for the run via `git hash-object queue/<slug>.spec.md`). The
  start row survives mid-run crashes — forensic data is preserved.
- `event=merge_action_completed` — written at the merge-call site. Captures
  closed-set `action ∈ {pr_only, auto_merged, fell_back, merge_failed}` and
  closed-set `reason ∈ {warnings_present, verdict_no_go,
  codex_high_severity, run_degraded, validated_fallback, branch_protection,
  merge_call_failed, manual_review_requested, recycle_demoted_findings,
  pr_create_failed, codex_absent, stale_base_ahead}` (required when action
  is `fell_back` or `merge_failed`, null otherwise). `stale_base_ahead` fires
  pre-PR when origin/main has advanced past the branch's merge-base; GitHub's
  squash-merge would silently revert those commits.

### Drift Detector

When `<project>/docs/specs/<slug>/spec.md` (canonical) and
`queue/<slug>.spec.md` (queue copy) disagree on `auto_merge_policy`, the
detector at `run.sh` start:

- **Halts (exit 2)** when queue ELEVATES policy above canonical (e.g.
  canonical=`pr`, queue=`clean`). Privilege-elevation guard (D6).
- **Warns** on downward drift (queue is safer than canonical). Run continues.
- **Silent-skips** when canonical absent (cross-project / hand-queued).

Partial order: `pr ≡ validated_today < clean`.

### YAML-Subset Semantics

Frontmatter parsing (via `_gh_frontmatter_field`):

- Reads only between first two `---` lines at column 1.
- `field: value` with optional leading spaces. First match wins; duplicate
  keys resolve to first.
- Strips trailing comments only when preceded by whitespace.
- Strips one pair of surrounding quotes (single or double).
- **Does NOT support block/multiline values (`|`, `>`).**
- Quoted `#` values can be mangled in edge cases.
- Resolver halts (exit 2) on any non-enum value the parser returns.

### Interim PR-Backlog Triage

Until `pipeline-autorun-final-status-render` ships, an overnight batch of
10+ specs lands a triage wall in your morning PR review. Run autorun-batch
with no more than ~10 specs at a time and use this recipe each morning:

```bash
gh pr list -l autorun --json number,title,isDraft \
  --jq '.[] | "\(.number)\t\(if .isDraft then "DRAFT" else "READY" end)\t\(.title)"' \
  | column -t -s $'\t'
```

### `gate_mode` ≠ `AUTORUN_MODE`

Two orthogonal axes:

- `gate_mode` (spec frontmatter) — `strict | permissive`. Controls whether
  `clean`-policy auto-merge accepts `GO_WITH_FIXES` (strict) or only `GO`
  (permissive).
- `AUTORUN_MODE` (CLI `--mode=`) — `overnight | supervised`. Controls the
  per-axis warn/block presets (verdict / branch / codex_probe / verify_infra).

Both can be set independently; the banner reads `gate_mode` from spec
frontmatter directly.

---

## Queue Format

- **File naming:** `queue/<slug>.spec.md`
  - Slug must match `^[a-z0-9][a-z0-9-]{0,63}$`
  - Example: `queue/dark-mode-toggle.spec.md`
- **Contents:** a fully-written `spec.md` (the output of `/spec`) — not a partial draft
- **Multiple items:** processed sequentially, alphabetical order
- **`.prompt.txt` entries are NOT supported in v1** — queue fully-written `spec.md` files only. Phase 2 will add `.prompt.txt` support once `/spec --auto` is built.
- **Idempotent re-runs:** items with `queue/<slug>/run-summary.md` already present are skipped silently

---

## Configuration (`queue/autorun.config.json`)

All fields are optional. Create this file only when you need to override a default.

```json
{
  "webhook_url": "",
  "mail_to": "",
  "spec_review_fatal_threshold": 2,
  "build_max_retries": 3,
  "test_cmd": "",
  "timeout_stage": 1800,
  "timeout_codex": 120
}
```

| Field | Default | Notes |
|-------|---------|-------|
| `webhook_url` | `""` | Slack-compatible webhook; empty = skip |
| `mail_to` | `""` | Email address; empty = skip |
| `spec_review_fatal_threshold` | `2` | How many `Verdict: FAIL` reviewers halt the item |
| `build_max_retries` | `3` | Build wave retry limit before rollback |
| `test_cmd` | `""` | Empty = skip tests (appropriate for repos with no test suite) |
| `timeout_stage` | `1800` | Per-`claude -p` call timeout in seconds |
| `timeout_codex` | `120` | Codex review timeout in seconds |
| `timeout_verify` | `600` | Spec compliance verifier timeout in seconds |

---

## The Pipeline

Each queue item runs through these stages in order:

### Stage 1 — Spec Review (parallel)
- Budget-selected reviewer agents (default: full personas/review/ roster of 7; capped by `agent_budget` in `~/.config/monsterflow/config.json`) run in parallel against the spec
- Findings merged into `queue/<slug>/review-findings.md`
- **Gate:** ≥ `spec_review_fatal_threshold` (default 2) agents emit `Verdict: FAIL` → item halted, `failure.md` written, next item

### Stage 2 — Risk Analysis (sequential, after Stage 1)
- Lightweight risk agent reads spec + review findings
- Output: `queue/<slug>/risk-findings.md`
- Non-fatal: a risk-analysis failure does not halt the item
- Merged into `review-findings.md` before plan stage

### Stage 3 — Plan
- Sequential; receives merged review + risk findings as context
- Output: `queue/<slug>/design.md`

### Stage 4 — Check
- Budget-selected reviewer agents (default: full personas/check/ roster of 6; capped by `agent_budget`) validate the plan
- **Gate:** `NO-GO` verdict → item halted

### Stage 5 — Build + Verify
- Branches from `main`: `autorun/<slug>`
- Pre-build SHA captured to `queue/<slug>/pre-build-sha.txt`
- One wave = one commit produced by the build agent
- Kill-switch checked after each wave
- After each wave: tests run (`test_cmd`), then spec compliance check (`verify.sh`)
  - Verifier checks git diff against spec requirements — "routes load" does NOT satisfy a requirement that specifies UI elements, access gates, or data fields
  - On verify failure: unmet requirements injected into the NEXT attempt's prompt as explicit `[FAIL]` items
- Retry up to `build_max_retries`× on either test or compliance failure
- On exhaustion: `git reset --hard <pre-build-sha>` + `failure.md` written
- Compliance gaps preserved in `queue/<slug>/verify-gaps.md`

### Stage 6 — PR Creation
- `gh pr create --base main --head autorun/<slug>`
- PR body includes full provenance block: spec → review → plan → check → build artifacts

### Stage 7 — Codex Review
- `codex exec review` fires post-PR
- **`**High:**` findings** are blocking — one autonomous fix attempt is made, then tests re-run, then Codex re-run once
- **`**Medium:**` / `**Low:**`** are non-blocking — justification comment posted to PR

### Stage 8 — Squash Merge
- Executes if: 0 `**High:**` findings remain AND tests pass
- `gh pr merge --squash`
- Otherwise PR is left open, findings logged, notification sent

---

## Kill-Switch

```bash
touch queue/STOP     # halts after current build wave
autorun stop         # same via wrapper
```

The run halts cleanly after the current wave completes — no partial commits, no uncommitted state. Remove `queue/STOP` before the next run.

---

## Dry-Run Mode

```bash
AUTORUN_DRY_RUN=1 autorun start
```

Stage scripts write stub artifacts and exit 0 without calling `claude -p`. Use this to test orchestration wiring without API cost.

---

## Testing Retry + Rollback

Force exhaustion of all build retries by setting `test_cmd` to always fail:

```json
{ "test_cmd": "exit 1" }
```

Expected behavior:
1. Wave 1 runs, tests fail → retry 1
2. Retry 2, retry 3 → all fail
3. `git reset --hard <pre-build-sha>` fires
4. `queue/<slug>/failure.md` written
5. Notification sent; pipeline continues to next queue item

---

## Failure Handling

On any stage failure, `/autorun` writes `queue/<slug>/failure.md` and moves to the next item. The file includes:

- Stage that failed, wave number, exit code
- Branch name and pre-build SHA
- Last 50 lines of stderr
- A ready-to-run **re-queue command:**
  ```bash
  rm queue/myfeature/failure.md && cp docs/specs/myfeature/spec.md queue/myfeature.spec.md
  ```

`queue/index.md` is written after all items complete with a per-item summary table (slug | verdict | stage-reached | PR URL or failure path).

---

## Notifications

All channels are optional. The macOS banner fires automatically on macOS without any config.

| Channel | How to enable |
|---------|--------------|
| **macOS banner** | Automatic (`osascript`) — fires on completion or failure |
| **Mail** | Set `mail_to` in `autorun.config.json` |
| **Webhook** | Set `webhook_url` (Slack-compatible) |

Note: macOS notification (AC #6) is manual-verification only — no pipeline stage depends on it. If all channels fail, `queue/run-summary.md` is the fallback forensic artifact.

---

## Scheduling Overnight

### Option 1 — tmux (simplest)
```bash
# Start a detached session that runs the queue and exits
tmux new-session -d -s autorun 'autorun start'
```

### Option 2 — launchd
See `QUICKSTART.md` for a full launchd plist example. Key points:
- Use a LaunchAgent (not LaunchDaemon) so it runs as your user
- The launchd plist (or your tmux invocation) is responsible for sourcing `~/.zshenv.local` before invoking `autorun start` — `run.sh` does NOT source it itself.

---

## Security Notes

- **`AUTORUN_GH_TOKEN`** — keep in `~/.zshenv.local` (chmod 600); use a fine-grained PAT scoped to `autorun/*` branches only (create PR + merge, nothing else)
- **`queue/` is gitignored** — `install.sh` writes `queue/.gitignore` into both the engine repo and the adopter project (cwd if it has a `.git` dir). Specs, config, run logs, and PR URLs stay local.
- **`queue/run.log`** — JSON-lines forensic trail written per wave: `{timestamp, slug, stage, exit_code}`
- **Credentials** — `defaults.sh` explicitly **unsets `ANTHROPIC_API_KEY`** so `claude -p` falls back to OAuth (the claude.ai subscription, not the API console balance). `GH_TOKEN` and Codex auth are inherited from the parent shell's environment.
- **`test_cmd`** — arbitrary shell from `queue/autorun.config.json`, executed inside `$PROJECT_DIR`. Treat your config like an executable: don't paste an unreviewed `test_cmd` from elsewhere.

---

## Queue Directory Layout (reference)

```
queue/
  autorun.config.json         # optional config overrides
  STOP                        # kill-switch: touch to halt
  myfeature.spec.md           # queue entry
  index.md                    # written after each full run
  run.log                     # JSON-lines forensic trail
  .autorun.lock               # flock file (auto-managed)
  .current-stage              # human-readable current stage
  myfeature/
    review-findings.md        # merged spec-review + risk output
    risk-findings.md
    design.md
    check.md
    build-log.md
    pre-build-sha.txt         # written once at Stage 5 entry
    verify-gaps.md            # per-requirement [PASS]/[FAIL] from compliance check
    state.json                # machine-readable run state
    failure.md                # written on rollback (presence = failed)
    pr-url.txt
    run-summary.md            # written on success (presence = complete)
```
