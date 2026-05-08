# ULTRAPROMPT Extraction Plan

## Purpose

Extract the useful operating-system ideas from ULTRAPROMPT into MonsterFlow without replacing MonsterFlow's core identity: a Claude slash-command workflow with persona gates, autorun, graph/wiki memory, and pragmatic local install ergonomics.

This plan intentionally avoids wholesale porting. The goal is to add durable proof, resumability, and feature-local state where MonsterFlow already has strong concepts but weaker mechanical enforcement.

## Non-Goals

- Do not copy ULTRAPROMPT's client/payment/legal workspace model.
- Do not import its bundled MCP servers.
- Do not convert MonsterFlow into a project-manager runtime with an orchestrator-only control plane.
- Do not require users to run from a separate vault repo.
- Do not weaken existing persona metrics, gate-mode, autorun, or dashboard contracts.

## Extraction Priorities

### 1. Feature Artifact Index

Add a generated `docs/specs/<feature>/artifact-index.yaml` as the compact feature-state source.

Problem:
MonsterFlow stores high-value state across `spec.md`, `review.md`, `plan.md`, `check.md`, `check-verdict.json`, `followups.jsonl`, raw persona output, survival classifier output, and autorun state. Resuming or auditing a feature requires rediscovering all of these files.

Proposed implementation:

- Create `scripts/build-feature-artifact-index.py`.
- Inputs:
  - `--feature <slug>`
  - optional `--json-out`
  - optional `--yaml-out`, default `docs/specs/<feature>/artifact-index.yaml`
- Index:
  - feature slug
  - generated timestamp
  - stage artifacts present/missing
  - current check verdict summary
  - followup counts by state and target phase
  - raw reviewer output paths
  - survival metrics paths
  - known evidence paths under the feature directory
  - latest git commit touching the feature directory when available
- Run after `/spec-review`, `/plan`, `/check`, `/build`, and autorun stage transitions.

Acceptance criteria:

- Script exits non-zero for invalid slugs.
- Script succeeds for legacy feature directories with missing optional artifacts.
- Output is deterministic except for timestamp and git-derived metadata.
- Tests cover complete feature, partial feature, malformed verdict, and missing followups.

Likely files:

- `scripts/build-feature-artifact-index.py`
- `tests/test-build-feature-artifact-index.sh` or Python equivalent
- `commands/spec-review.md`
- `commands/plan.md`
- `commands/check.md`
- `commands/build.md`
- `scripts/autorun/*.sh` if stage hooks exist there

### 2. Build Evidence Checker

Add a mechanical proof checker before `/build` declares completion.

Problem:
MonsterFlow has structured verdicts and followups, but needs a deterministic check that claimed proof actually resolves on disk. This catches false completion cases like missing screenshots, missing test logs, unresolved followups, or a build summary claiming verification that did not happen.

Proposed implementation:

- Create `scripts/check-build-evidence.py`.
- Inputs:
  - `--feature <slug>`
  - `--json-out <path>`
  - `--markdown-out <path>`
- Checks:
  - `check-verdict.json` is readable if present.
  - `NO_GO` verdict blocks build completion.
  - open `build-inline` and `docs-only` followups are either consumed or explicitly carried forward.
  - evidence paths cited in `build.md`, `check.md`, raw outputs, or followups exist.
  - evidence directories are not empty.
  - claimed test/build/lint outputs have an associated command summary or log path when the text says they were run.
  - security findings have disposition before final completion.
- Output:
  - JSON report with `status: pass|warn|fail`
  - Markdown report written under `docs/specs/<feature>/build/evidence-check.md`

Acceptance criteria:

- Missing claimed evidence fails.
- Empty evidence directories fail.
- Legacy features without build evidence warn rather than crash.
- Security findings without disposition fail.
- `/build` includes the report path in its final summary.

Likely files:

- `scripts/check-build-evidence.py`
- `schemas/build-evidence.schema.json`
- `tests/test-build-evidence.sh`
- `commands/build.md`
- `scripts/autorun/build.sh` if present

### 3. Check Gate Packet

Generate a machine-readable packet before `/check` synthesis.

Problem:
The `/check` stage has a strong prompt contract and v2 sidecar, but the model synthesis still has to infer exactly what evidence and reviewer inputs are authoritative. A gate packet makes the trust boundary explicit.

Proposed implementation:

- Create `scripts/build-check-gate-packet.py`.
- Inputs:
  - `--feature <slug>`
  - `--packet-out docs/specs/<feature>/check/gate-packet.yaml`
- Include:
  - slug
  - generated timestamp
  - hashes for `spec.md`, `review.md`, `plan.md`, and `check/source.plan.md`
  - selected personas from `check/selection.json`
  - raw persona output paths and hashes
  - active gate mode, source, iteration, and recycle cap
  - codex adversarial review path if present
  - expected sidecar schema version
  - artifact index path when present

Acceptance criteria:

- Packet generation fails if required `/check` source artifacts are missing.
- Packet detects missing selected reviewer raw output.
- Packet is referenced by `/check` synthesis prompt.
- Packet path is recorded in `check-verdict.json` in a future schema version or in the prose body as an interim step.

Likely files:

- `scripts/build-check-gate-packet.py`
- `tests/test-check-gate-packet.sh`
- `commands/check.md`
- `schemas/check-gate-packet.schema.json`

### 4. Manual Pipeline Checkpoints

Add a lightweight per-feature checkpoint log for manual slash-command flows.

Problem:
Autorun has durable `run-state.json`, but manual `/spec -> /spec-review -> /plan -> /check -> /build` sessions rely on stage artifacts and chat continuity. A compact checkpoint log makes manual resumption cheaper and less ambiguous.

Proposed implementation:

- Create or append `docs/specs/<feature>/run.md`.
- Add helper script `scripts/feature-checkpoint.py`.
- Each stage appends:
  - timestamp
  - stage
  - status
  - important artifact paths
  - verdict or next required action
  - warnings/degradations
- `/flow` or `/build` can instruct users to inspect `run.md` for resume context.

Acceptance criteria:

- Checkpoint appends are atomic.
- Running the same stage twice appends a new entry rather than rewriting history.
- Manual and autorun checkpoints are visually distinguishable.
- Checkpoint helper refuses invalid feature slugs.

Likely files:

- `scripts/feature-checkpoint.py`
- `tests/test-feature-checkpoint.sh`
- `commands/spec.md`
- `commands/spec-review.md`
- `commands/plan.md`
- `commands/check.md`
- `commands/build.md`

### 5. Optional Feature Tickets

Introduce tickets only after artifact indexing and evidence checks are stable.

Problem:
ULTRAPROMPT's ticket files improve resumability and parallel work ownership, but importing them too early risks bloating MonsterFlow's simpler feature pipeline.

Proposed implementation:

- Add optional `docs/specs/<feature>/tickets/T-001-*.md`.
- Use tickets for `/build` wave tasks, not for every pipeline stage.
- Ticket frontmatter:
  - `id`
  - `feature`
  - `status`
  - `task_type`
  - `wave`
  - `blocked_by`
  - `owner`
  - `file_paths`
  - `evidence`
  - `handoff`
- Generate tickets from the task breakdown in `plan.md`.
- Keep ticket support opt-in until proven useful.

Acceptance criteria:

- `/build` can run without ticket files for legacy specs.
- When tickets exist, `/build` uses them as the task source.
- Ticket closeout requires evidence checker pass or explicit carry-forward.
- Tickets are included in `artifact-index.yaml`.

Likely files:

- `scripts/generate-build-tickets.py`
- `scripts/check-build-ticket.py`
- `schemas/build-ticket.schema.json`
- `commands/build.md`

### 6. Deterministic Research Trigger

Add a small preflight that decides whether current external research is required.

Problem:
MonsterFlow can use research tools, but the decision is mostly prompt-driven. Modern APIs, model choices, security guidance, regulations, pricing, and dependency versions should not rely on stale memory.

Proposed implementation:

- Create `scripts/research-trigger.py`.
- Inputs:
  - `--feature <slug>`
  - `--stage spec|plan`
  - optional `--source <path>`
- Detect trigger terms:
  - current/latest/today/recent
  - API/vendor/model/library/dependency/version
  - law/regulation/security/compliance/pricing
  - browser/platform/framework behavior
  - external service integration
- Output `docs/specs/<feature>/research-trigger.json`.
- Prompt stages must record either:
  - research performed with links/citations, or
  - research not required with reason.

Acceptance criteria:

- Trigger never performs network access itself.
- Trigger produces deterministic JSON.
- `/plan` warns when research is required but no research evidence is recorded.
- Tests cover obvious positive and negative cases.

Likely files:

- `scripts/research-trigger.py`
- `schemas/research-trigger.schema.json`
- `tests/test-research-trigger.sh`
- `commands/spec.md`
- `commands/plan.md`

## Rollout Order

1. Build `artifact-index.yaml`.
2. Add build evidence checker.
3. Add check gate packet.
4. Add manual checkpoint log.
5. Add optional build tickets.
6. Add deterministic research trigger.

This order keeps the first changes mostly observational. Tickets and research policy come later because they change workflow behavior more visibly.

## Test Strategy

- Use fixture feature directories under `tests/fixtures/`.
- Add one "complete happy path" fixture.
- Add one "legacy partial feature" fixture.
- Add one "malformed sidecar" fixture.
- Add one "claimed evidence missing" fixture.
- Validate JSON/YAML outputs with schemas where practical.
- Keep shell tests consistent with existing MonsterFlow test style unless a Python test is clearly simpler.

## Compatibility Rules

- Legacy feature directories must continue to work.
- New scripts should warn rather than fail when optional artifacts are missing.
- Hard failures should be reserved for integrity issues, invalid slugs, malformed required files, or missing proof that the system explicitly claims exists.
- No existing schema should be broken without adding a migration or backward-compatible reader.

## Success Criteria

MonsterFlow has successfully extracted the useful ULTRAPROMPT ideas when:

- A feature can be resumed from disk without rereading every stage artifact.
- `/build` cannot honestly claim completion while cited proof is missing.
- `/check` synthesis has an explicit trust packet.
- Manual flows leave durable checkpoints similar in spirit to autorun state.
- Ticket files improve wave execution without becoming mandatory ceremony.
- Current-context research needs are detected mechanically before plan decisions rely on stale assumptions.