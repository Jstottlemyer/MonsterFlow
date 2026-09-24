# MonsterFlow — Repo-level Instructions

Read this file whether your harness resolves it as `CLAUDE.md` (Claude Code)
or `AGENTS.md` (Codex, other agents) — `AGENTS.md` at repo root is a symlink
to this file, not a copy. Directories with their own `CLAUDE.md` (currently
`scripts/autorun/`, `tests/`, `commands/`) extend this one with
subtree-scoped rules; read the nearest one to whatever you're editing, in
addition to this root file.

Personal-tooling repo. Holds commands, personas, templates, and cross-project
reference docs for Justin's 8-command pipeline (`/kickoff → /spec → /spec-review
→ /blueprint → /check → /build`, plus `/flow`, `/wrap`, and `/plot`).

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

Apply in addition to your harness's user-level instructions file
(`~/CLAUDE.md` for Claude Code; equivalent for other harnesses).

## Built-in Claude Code commands

(Codex readers: `/plan` below refers to Claude Code's plan-mode tooling
specifically; check your own harness for the equivalent built-in before
assuming a name is free.)

`/blueprint` is MonsterFlow's design gate. It stays in the terminal and writes `docs/specs/<feature>/design.md`. Avoid `/ultraplan` for pipeline work; it dispatches a remote browser session and produces no local artifact. `/insights` is opt-in via `/wrap-insights` (measurement mode); `/powerup` is ad-hoc educational and not wired into any flow. **`/plan` is Claude Code's built-in plan-mode** — different tool, different intent. If you want MonsterFlow's design pass, use `/blueprint`. Use `/effort high` at the start of each gate for consistent quality output (stays in terminal, no pipeline duplication). `/deep-research` is OPT-IN for spec research phases; `/rewind` is OPT-IN for checkpoint rollback at build; `/autofix-pr` is AVOID — it spawns a remote session like `/ultraplan`.

`/wrap` has three tab-completable variants: `/wrap-quick` (fast triage only), `/wrap-insights` (adds Phase 1b `/insights`), `/wrap-full` (insights + force-run conditional phases). Bare-word args (`quick`, `insights`, `full`) still work for direct invocation; the subcommands exist so the variants show up in tab completion.

Persona Metrics ships in v0.2.0 — `/wrap-insights` Phase 1c renders per-persona drift across all three multi-agent gates; `/wrap-insights personas` (bare-arg form) shows the full table. See `docs/specs/persona-metrics/spec.md` for the data flow and outcome semantics. The diagrams.md file in the same dir is the locked source for README + `docs/index.html` mermaid edits.

## Subagents (`.claude/agents/`)

Two focused Claude Code subagents ship with this repo. Neither is auto-scheduled — invoke them on demand via `Agent(subagent_type: ...)` when the trigger condition fires:

- **`autorun-shell-reviewer`** — pre-commit gate for `scripts/autorun/*.sh` changes. See `scripts/autorun/CLAUDE.md` for the trigger checklist and invocation rule.
- **`persona-metrics-validator`** — invoke when `/wrap-insights` Phase 1c surfaces suspect drift (a persona suddenly at 0%, all features showing `artifact_hash` mismatches, etc.). Read-only; validates JSONL schema + foreign-key joins + hash freshness across `docs/specs/*/{spec-review,design,check}/`.

Tests for both subagents' frontmatter live at `tests/test-agents.sh`. Run `bash tests/run-tests.sh agents` to validate.

## Autorun pipeline

Stage architecture, timeouts, agent-budget knob, and the shell-scripting
pitfalls specific to this directory now live in `scripts/autorun/CLAUDE.md`
— read it before touching anything under `scripts/autorun/`.

## Backlog

Unscheduled ideas live in [BACKLOG.md](BACKLOG.md). Add new items there, not in this file. Promote an item to a real spec via `/spec` when you're ready to work on it.

## Plot Document

The Plot Document (`plot/PLOT.md` + `plot/chapters/*.md`) is MonsterFlow's fifth knowledge store — narrative-level system context with inline code links. Managed by `/plot` (standalone, on-demand); consumed by `/wrap` Phase 2d (automated staleness detection) and `/spec` Phase 0.2c (prior-knowledge callout). Annotation helpers live at `scripts/_plot_annotations.py`. All annotation manipulation (inject/remove `[!STALE]`/`[!DRAFT]`) must go through the helper, never free-form LLM editing. This repo's code is heavily documented markdown — `/plot` is shipped here but the Plot Document is more valuable on source-code-heavy projects.

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
