# MonsterFlow — Repo-level Instructions for Claude

Personal-tooling repo. Holds commands, personas, templates, and cross-project
reference docs for Justin's 8-command pipeline (`/kickoff → /spec → /spec-review
→ /design → /check → /build`, plus `/flow` and `/wrap`).

(`/design` is MonsterFlow's design-and-implementation-planning gate. It was
previously named `/plan`, but we ceded that name back to Claude Code on
2026-05-12 — `/plan` belongs to Claude Code's built-in plan-mode tooling
(`EnterPlanMode` / `ExitPlanMode`), not to this pipeline. The internal
gate identifier remains `plan` — schemas, persona dir paths, gate_mode
keys, on-disk selection.json files, the artifact filename `plan.md`, and
the autorun shell `scripts/autorun/plan.sh` all stay backward-compatible.
Only the user-facing slash command moved.)

Apply in addition to user-level `~/CLAUDE.md`.

## Built-in Claude Code commands

`/design` is MonsterFlow's design gate. It stays in the terminal and writes `docs/specs/<feature>/plan.md` (the artifact filename keeps the historical name for on-disk backward compat). Avoid `/ultraplan` for pipeline work; it dispatches a remote browser session and produces no local artifact. `/insights` is opt-in via `/wrap-insights` (measurement mode); `/powerup` is ad-hoc educational and not wired into any flow. **`/plan` is Claude Code's built-in plan-mode** — different tool, different intent. If you want MonsterFlow's design pass, use `/design`.

`/wrap` has three tab-completable variants: `/wrap-quick` (fast triage only), `/wrap-insights` (adds Phase 1b `/insights`), `/wrap-full` (insights + force-run conditional phases). Bare-word args (`quick`, `insights`, `full`) still work for direct invocation; the subcommands exist so the variants show up in tab completion.

Persona Metrics ships in v0.2.0 — `/wrap-insights` Phase 1c renders per-persona drift across all three multi-agent gates; `/wrap-insights personas` (bare-arg form) shows the full table. See `docs/specs/persona-metrics/spec.md` for the data flow and outcome semantics. The diagrams.md file in the same dir is the locked source for README + `docs/index.html` mermaid edits.

## Subagents (`.claude/agents/`)

Two focused Claude Code subagents ship with this repo. Neither is auto-scheduled — invoke them on demand via `Agent(subagent_type: ...)` when the trigger condition fires:

- **`autorun-shell-reviewer`** — invoke before committing changes that touch `scripts/autorun/*.sh`. Codifies the 13-pitfall checklist Codex/Opus surfaced (PIPESTATUS index, `\|\| true` reset, grep-c arithmetic, branch invariant, STOP race, slug regex, eval scope, SSH/HTTPS remote, AppleScript injection, `--auto` merge ambiguity, empty-PR loophole, truncated diff, quoting). Returns High/Medium/Low findings with file:line. Treat its High findings as blocking.
- **`persona-metrics-validator`** — invoke when `/wrap-insights` Phase 1c surfaces suspect drift (a persona suddenly at 0%, all features showing `artifact_hash` mismatches, etc.). Read-only; validates JSONL schema + foreign-key joins + hash freshness across `docs/specs/*/{spec-review,plan,check}/`.

Tests for both subagents' frontmatter live at `tests/test-agents.sh`. Run `bash tests/run-tests.sh agents` to validate.

## Autorun Stage Architecture (as of v0.8.x)

- **`spec-review.sh`** and **`check.sh`**: N parallel `claude -p` calls (one per persona, disk-discovered from `personas/<gate>/`). No `--add-dir` — spec/plan content passed inline. `TIMEOUT_PERSONA=600s` per persona; merge step concatenates raw outputs.
- **`check.sh`**: two-phase — Phase 1 is parallel reviewers, Phase 2 is one synthesis call that reads all reviewer outputs and produces the GO/NO-GO verdict.
- **`plan.sh`**: single Claude synthesis call (needs all review findings coherently), no `--add-dir`. Followed by a Codex adversarial design critique when the resolver emits `codex-adversary` for the design gate; output is appended to `plan.md` as a labeled section so `/check` sees it via existing reads. Codex failure at the design gate is non-fatal.
- **Persona directory mapping**: gate name ≠ directory name. `spec-review` → `personas/review/`, `plan` → `personas/plan/`, `check` → `personas/check/`. Never walk `personas/<gate-name>/` directly.
- **`TIMEOUT_PERSONA`** (default 600s) is per-persona; `TIMEOUT_STAGE` (default 1800s) is for synthesis calls. Both configurable via `queue/autorun.config.json`.
- Before committing changes to `scripts/autorun/*.sh`, invoke the `autorun-shell-reviewer` subagent.

## Agent budget (token-cost control)

The persona resolver (`scripts/resolve-personas.sh` / `_resolve_personas.py`) reads `~/.config/monsterflow/config.json` for an `agent_budget` integer (range 1–8). When set, the resolver caps the Claude-persona dispatch at that count per gate; `codex-adversary` is appended separately and does NOT count against the budget. Default (no config or no key) = full on-disk roster.

Recommended: `{"agent_budget": 3}` gives 3 Claude + 1 Codex per gate (`/spec-review`, `/design`, `/check`) — roughly 50% Claude-token reduction vs the full 7/7/6 roster, while keeping an independent-model lens via Codex. Selection is data-driven (rankings from persona insights, falling back to seed list, then alphabetical). Once a feature is in flight, its picks are locked at `docs/specs/<feature>/.budget-lock.json` for deterministic reruns.

Kill switch: `MONSTERFLOW_DISABLE_BUDGET=1` bypasses the cap (full roster). Use only in emergencies; the `selection.json` audit trail records `selection_method=kill-switch`.

## Backlog

Unscheduled ideas live in [BACKLOG.md](BACKLOG.md). Add new items there, not in this file. Promote an item to a real spec via `/spec` when you're ready to work on it.

## graphify

This project has a graphify knowledge graph at graphify-out/.

Rules:
- Before answering architecture or codebase questions, read graphify-out/GRAPH_REPORT.md for god nodes and community structure
- If graphify-out/wiki/index.md exists, navigate it instead of reading raw files
- After modifying code files in this session, run `graphify update .` to keep the graph current (AST-only, no API cost)
