# MonsterFlow — Repo-level Instructions for Claude

Personal-tooling repo. Holds commands, personas, templates, and cross-project
reference docs for Justin's 8-command pipeline (`/kickoff → /spec → /spec-review
→ /blueprint → /check → /build`, plus `/flow` and `/wrap`).

(`/blueprint` is MonsterFlow's design-and-implementation-planning gate. The
gate, the slash command, the persona directory (`personas/design/`), the
autorun script (`scripts/autorun/design.sh`), the artifact filename
(`docs/specs/<feature>/design.md`), the `selection.json` `gate` field,
and the persisted JSONL `stage` value all use `design` as of 2026-05-12.
`/plan` belongs to Claude Code's built-in plan-mode tooling
(`EnterPlanMode` / `ExitPlanMode`), not to this pipeline. Historical
on-disk references to `plan` were migrated in the rename PR; there is
NO back-compat alias — pass `design` to the resolver, read `design.md`
from spec dirs, look for `stage: "design"` in JSONL. One exception:
`_GATE_PREFIX["design"] == "pl"` keeps historical finding-id continuity
(prefix is internal salt only).)

Apply in addition to user-level `~/CLAUDE.md`.

## Built-in Claude Code commands

`/blueprint` is MonsterFlow's design gate. It stays in the terminal and writes `docs/specs/<feature>/design.md`. Avoid `/ultraplan` for pipeline work; it dispatches a remote browser session and produces no local artifact. `/insights` is opt-in via `/wrap-insights` (measurement mode); `/powerup` is ad-hoc educational and not wired into any flow. **`/plan` is Claude Code's built-in plan-mode** — different tool, different intent. If you want MonsterFlow's design pass, use `/blueprint`.

`/wrap` has three tab-completable variants: `/wrap-quick` (fast triage only), `/wrap-insights` (adds Phase 1b `/insights`), `/wrap-full` (insights + force-run conditional phases). Bare-word args (`quick`, `insights`, `full`) still work for direct invocation; the subcommands exist so the variants show up in tab completion.

Persona Metrics ships in v0.2.0 — `/wrap-insights` Phase 1c renders per-persona drift across all three multi-agent gates; `/wrap-insights personas` (bare-arg form) shows the full table. See `docs/specs/persona-metrics/spec.md` for the data flow and outcome semantics. The diagrams.md file in the same dir is the locked source for README + `docs/index.html` mermaid edits.

## Subagents (`.claude/agents/`)

Two focused Claude Code subagents ship with this repo. Neither is auto-scheduled — invoke them on demand via `Agent(subagent_type: ...)` when the trigger condition fires:

- **`autorun-shell-reviewer`** — invoke before committing changes that touch `scripts/autorun/*.sh`. Codifies the 13-pitfall checklist Codex/Opus surfaced (PIPESTATUS index, `\|\| true` reset, grep-c arithmetic, branch invariant, STOP race, slug regex, eval scope, SSH/HTTPS remote, AppleScript injection, `--auto` merge ambiguity, empty-PR loophole, truncated diff, quoting). Returns High/Medium/Low findings with file:line. Treat its High findings as blocking.
- **`persona-metrics-validator`** — invoke when `/wrap-insights` Phase 1c surfaces suspect drift (a persona suddenly at 0%, all features showing `artifact_hash` mismatches, etc.). Read-only; validates JSONL schema + foreign-key joins + hash freshness across `docs/specs/*/{spec-review,design,check}/`.

Tests for both subagents' frontmatter live at `tests/test-agents.sh`. Run `bash tests/run-tests.sh agents` to validate.

## Autorun Stage Architecture (as of v0.8.x)

- **`spec-review.sh`** and **`check.sh`**: N parallel `claude -p` calls (one per persona, disk-discovered from `personas/<gate>/`). No `--add-dir` — spec/plan content passed inline. `TIMEOUT_PERSONA=600s` per persona; merge step concatenates raw outputs.
- **`check.sh`**: two-phase — Phase 1 is parallel reviewers, Phase 2 is one synthesis call that reads all reviewer outputs and produces the GO/NO-GO verdict.
- **`design.sh`**: single Claude synthesis call (needs all review findings coherently), no `--add-dir`. Followed by a Codex adversarial design critique when the resolver emits `codex-adversary` for the design gate; output is appended to `design.md` as a labeled section so `/check` sees it via existing reads. Codex failure at the design gate is non-fatal.
- **Persona directory mapping**: gate name ≠ directory name only for spec-review (`personas/review/`); design and check share their gate name (`personas/design/`, `personas/check/`). Never walk `personas/<gate-name>/` for spec-review directly.
- **`TIMEOUT_PERSONA`** (default 600s) is per-persona; `TIMEOUT_STAGE` (default 1800s) is for synthesis calls. Both configurable via `queue/autorun.config.json`.
- Before committing changes to `scripts/autorun/*.sh`, invoke the `autorun-shell-reviewer` subagent.

## Agent budget (token-cost control)

The persona resolver (`scripts/resolve-personas.sh` / `_resolve_personas.py`) reads `~/.config/monsterflow/config.json` for an `agent_budget` integer (range 1–8). When set, the resolver caps the Claude-persona dispatch at that count per gate; `codex-adversary` is appended separately and does NOT count against the budget. Default (no config or no key) = full on-disk roster.

Recommended: `{"agent_budget": 3}` gives 3 Claude + 1 Codex per gate (`/spec-review`, `/blueprint`, `/check`) — roughly 50% Claude-token reduction vs the full 7/7/6 roster, while keeping an independent-model lens via Codex. Selection is data-driven (rankings from persona insights, falling back to seed list, then alphabetical). Once a feature is in flight, its picks are locked at `docs/specs/<feature>/.budget-lock.json` for deterministic reruns.

Kill switch: `MONSTERFLOW_DISABLE_BUDGET=1` bypasses the cap (full roster). Use only in emergencies; the `selection.json` audit trail records `selection_method=kill-switch`.

## Backlog

Unscheduled ideas live in [BACKLOG.md](BACKLOG.md). Add new items there, not in this file. Promote an item to a real spec via `/spec` when you're ready to work on it.

## graphify

This project has a graphify knowledge graph at graphify-out/.

Rules:
- Before answering architecture or codebase questions, read graphify-out/GRAPH_REPORT.md for god nodes and community structure
- If graphify-out/wiki/index.md exists, navigate it instead of reading raw files
- After modifying code files in this session, run `graphify update .` to keep the graph current (AST-only, no API cost)

## Obsidian vault scaffolding (post-install)

**Preflight check for wiki-related work:** Before responding to any wiki-* command (`wiki-update`, `wiki-query`, `wiki-ingest`, `wiki-capture`, `wiki-export`, `wiki-lint`) OR before `/wrap`'s Phase 2c wiki integration, check whether `$OBSIDIAN_VAULT_PATH/.scaffold-pending` exists.

If the marker exists, install.sh detected an empty vault but the upstream wiki structure has not been built yet. Suggest the adopter run `/wiki-setup` (from the upstream `Ar9av/obsidian-wiki` skills) before proceeding with the wiki-related ask.

**Marker cleanup:** After `/wiki-setup` completes successfully — confirmed by the vault now containing at least 3 of: `concepts/`, `entities/`, `_archives/`, `_raw/`, `index.md`, `log.md`, `.obsidian/` — delete the `.scaffold-pending` marker file. Do NOT remove the marker if /wiki-setup did not run or did not complete successfully.

If `/wiki-setup` is not available in the current session, the adopter still needs to install the wiki skills (see `install-obsidian-wiki-auto-clone` in BACKLOG.md / future spec). Surface the marker once with a one-line note and proceed with the wiki-related ask using whatever capability is currently installed.

This preflight does NOT fire on session start or for non-wiki work — only when the user requests something wiki-adjacent.

## Tab-accept suggestions (Claude Code built-in)

After Claude responds in an interactive session, Claude Code may show a
grayed-out follow-up suggestion in your input box (based on conversation
context). Press **Tab** or **Right arrow** to accept it, then **Enter** to
submit. Suggestions skip after turn 1, in non-interactive mode, in plan
mode, and when the prompt cache is cold.

To disable globally:
`export CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false`

Or toggle via `/config`. Slash commands cannot author suggestions directly
— they are inferred from Claude's response context.
