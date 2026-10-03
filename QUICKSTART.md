# Quick Start

A hands-on 10-minute setup for the Claude workflow pipeline. Assumes you're on macOS with Claude Code installed.

## Prerequisites

- **Claude Code CLI** — https://claude.com/claude-code (install it; first `claude` run walks you through its own sign-in)
- **git** — for cloning
- **bash** — macOS ships 3.2; the installer works with it
- **python3** — `brew install python`. Used by the session-cost script.

The `install.sh` will warn if any of these are missing but won't block — install them when prompted or beforehand.

## 1. Clone + install

```bash
git clone https://github.com/Jstottlemyer/MonsterFlow.git ~/Projects/MonsterFlow
cd ~/Projects/MonsterFlow
./install.sh
```

The installer symlinks everything from this repo into `~/.claude/`. It backs up any existing file to `<file>.bak` before linking, so it's safe to re-run.

### What gets installed

| Target | From |
|---|---|
| `~/.claude/commands/*.md` (8 pipeline commands) | `commands/` |
| `~/.claude/personas/{review,plan,check,code-review}/*.md` (27 agents) | `personas/` |
| `~/.claude/templates/*.md` (constitution, repo-signals) | `templates/` |
| `~/.claude/settings.json` (base permissions) | `settings/settings.json` |
| `~/.claude/scripts/*.{py,sh}` (session helpers) | `scripts/` |

The installer will also offer to install required plugins (`superpowers`, `context7`) and recommended ones (`firecrawl`, `code-review`, `ralph-loop`, `playwright`). Say yes unless you have a reason not to.

See [`install.sh` flags & env vars](#installsh-flags--env-vars) below if you need to script around it (CI, restricted environments, theme opt-in/out).

## 2b. Enable Codex multi-model reviews (optional)

The pipeline can call Codex as an adversarial reviewer at `/spec-review`, `/check`, and `/build`. It silently skips if Codex isn't set up — nothing breaks.

To enable, inside Claude Code:

```
/plugin marketplace add openai/codex-plugin-cc
/plugin install codex@openai-codex
/reload-plugins
/codex:setup
```

`/codex:setup` will offer to install the Codex CLI via npm. Once installed, authenticate:

```
!codex login
```

This opens a browser — sign in with a ChatGPT account (free tier works). Run `/codex:setup` again to confirm `ready: true`. See `plugins.md` for more detail.

## 3. Add your personal layer

The pipeline is shared (checked into this repo), but **your personal context is not**. Create `~/CLAUDE.md` with things like:

```markdown
# My Claude Config

## Who I Am
- [Your role, what you're building]

## Collaboration Preferences
- [e.g., "One question at a time", "Show tradeoffs before committing to an approach"]

## Projects
- [Short pointer to each project you work on]
```

This file loads automatically in every Claude Code session and is purely for you — it's not shared with the team.

## 4. Verify install

Open a fresh terminal, `cd` into any project (or a scratch dir), and run Claude:

```bash
claude
```

First run: Claude Code walks you through its own browser sign-in (Anthropic account — separate from GitHub). Once you're in, try:
```
/flow
```

You should see the workflow reference card. If the command is unknown, the symlink didn't take — re-run `./install.sh` from the workflow repo.

**If Claude Code was already running when you ran `./install.sh`**, quit and relaunch it. Slash commands are discovered at session start; a stale session will render the old card.

## 5. Run the pipeline on a real project

Pick a small project you have lying around:

```bash
cd ~/Projects/<some-project>
claude
```

Then in Claude Code:
```
/kickoff
```

`/kickoff` will scan the repo for stack signals (Swift, Go, TS, Python, MCP, plugin...) and propose a domain-specific agent roster. Confirm or adjust, and it writes `docs/specs/constitution.md` + installs any domain agents into `.claude/agents/`.

Next, for your first feature or change:
```
/spec <one-sentence description>
```

This runs a confidence-tracked Q&A, writes `docs/specs/<feature>/spec.md`, and kicks off the rest of the pipeline when you're ready (`/spec-review` → `/plan` → `/check` → `/build`).

End every session with:
```
/wrap
```

Captures session summary, triages learnings, checks git loose ends, and audits permissions.

## 5b. Example: onboarding a brownfield mobile Swift app

Brownfield = an existing codebase you're bringing into the pipeline for the first time.

### Step 1 — scan the codebase with graphify first

Before running `/kickoff`, let graphify build a knowledge graph of the existing code. This gives Claude a precise map of your file structure, key types, and relationships — so the constitution and future specs are grounded in what's actually there, not guesses.

```bash
cd ~/Projects/MyiOSApp
graphify update .
```

This runs locally with no LLM calls (AST-only) and takes seconds on most iOS projects. It writes to `graphify-out/`. Once done, open Claude Code:

```bash
claude
```

Claude will automatically read `graphify-out/GRAPH_REPORT.md` before answering architecture questions. You can also query it directly:
```
graphify query "what are the main view controllers" --budget 1500
```

### Step 2 — run /kickoff

```
/kickoff
```

For a Swift/SwiftUI project, Claude will detect the stack and propose the mobile domain agents. A session looks like this:

```
=== Repo Signals ===
Stack: Swift 5.9, SwiftUI, SpriteKit
Evidence:
  - 23 .swift files, 4 .xcodeproj files
  - Package.swift with SwiftUI + SpriteKit dependencies
  - graphify graph: 142 nodes, ContentView, GameScene, PlayerViewModel as god nodes
Proposed domain: mobile + games

Proposed session roster (on top of 27 defaults):
  swift-mentor       — Swift idioms, @Observable, async/await best practices
  test-writer        — XCTest / Swift Testing unit + UI test coverage
  performance-advisor — Instruments-style memory + frame-rate review
  swiftui-scene-builder — SwiftUI layout and scene composition
  accessibility-guardian — HIG compliance + VoiceOver + Dynamic Type

Use this roster? (yes / adjust / defaults only)
```

### Step 3 — add a visual/graphical reviewer to the constitution

If your app has significant UI work (custom layouts, animations, game scenes), add a visual reviewer when `/kickoff` asks about the roster. Type **adjust** and add:

```
+ ui-visual-reviewer
```

`/kickoff` will install it from `~/.claude/domain-agents/mobile/` if it exists, or offer to create it from a template. For a visual review focus, the resulting constitution looks like:

```markdown
# MyiOSApp Constitution

**Version:** 1.0

## Core Principles

### I. SwiftUI-first, UIKit by exception
Use SwiftUI for all new views. UIKit only where SwiftUI lacks capability or
for interop with existing UIKit surfaces. Never mix paradigms in the same view.

### II. Visual quality is a first-class requirement
Every spec that touches UI must include a Visual/UX section reviewed by the
ui-visual-reviewer agent. Pixel-level concerns (spacing, alignment, typography
scale, animation timing) are blocker-severity findings, not nits.

### III. HIG compliance before feature completion
Apple Human Interface Guidelines govern layout, navigation patterns, and
interactive controls. A feature is not done if it fails HIG review.

## Quality Standards

### Testing
XCTest for unit + integration; Swift Testing for new test targets (iOS 18+).
UI tests via XCUITest for critical user flows.

### Accessibility
VoiceOver labels, Dynamic Type, minimum 44pt touch targets. Reviewed by
accessibility-guardian at every /spec-review gate.

### Performance
60fps on iPhone 13 baseline. No main-thread blocking. Reviewed by
performance-advisor at /check.

## Agent Roster

Default 27 pipeline agents always active. Project-specific additions:

- **swift-mentor** — Swift best practices, concurrency patterns — /spec-review, /plan
- **test-writer** — XCTest + Swift Testing coverage review — /plan, /check
- **performance-advisor** — memory, frame rate, Instruments signals — /check
- **swiftui-scene-builder** — SwiftUI layout + scene composition — /spec-review, /plan
- **accessibility-guardian** — HIG, VoiceOver, Dynamic Type — /spec-review, /check
- **ui-visual-reviewer** — spacing, animation, visual polish — /spec-review, /plan

## Constraints

### In Scope
iOS 18+ iPhone and iPad. Swift only. SwiftUI primary, SpriteKit for game scenes.

### Out of Scope
macOS, watchOS, Android. Objective-C. Server-side code.

### Technical Constraints
Deployment target: iOS 18. Xcode 16+. Swift Package Manager preferred over CocoaPods.
```

### Step 4 — your first spec on the brownfield

Once the constitution is written, start a spec for whatever you're adding or changing:

```
/spec add a score animation that plays when the player levels up
```

Because graphify already scanned the project, Claude knows your existing `GameScene`, `PlayerViewModel`, and `ScoreView` — the spec Q&A will reference real types, not invented ones.

## 6. The pipeline at a glance

```
/kickoff → /spec → /spec-review → /plan → /check → /build
           define    6 PRD        7 design  5 plan   execute
           (Q&A)     agents       agents    agents   (parallel)
```

Work scales — you don't need the full pipeline for a bug fix:

| Work Size | What to run |
|---|---|
| Bug fix | Describe it, fix it, verify |
| Small change | `/spec` then `/build` |
| Feature | Full pipeline |
| V2 / rework | Revise existing spec, then full pipeline |

## 6b. Agent Budget (optional, opt-in)

Cap how many Claude personas run per gate. Useful if you're on Claude Pro
($20/mo) and want fewer parallel reviewers, or if you want to dial up
adversarial review on specific gates. Codex-adversary is **additive** —
not counted against your budget.

```bash
# Set or change budget (interactive Q&A)
bash install.sh --reconfigure-budget

# Inspect what would dispatch for a gate
bash scripts/resolve-personas.sh check --feature my-feature --why

# Emergency kill switch — restore full roster for one run
MONSTERFLOW_DISABLE_BUDGET=1 autorun
```

Defaults: budget=3 (Pro), budget=6 (free or Max). Range 1–8. No config
present → full roster (existing-user behavior preserved).

Full reference + schema + reset paths: [`docs/budget.md`](docs/budget.md).

## 6c. Codex implementation workers for `/build` (optional, opt-in)

By default `/build` implements each task with Claude subagents. You can hand
the implementation of each task to Codex workers instead, for example to use
your OpenAI quota or a different model. Claude Code stays the orchestrator:
the task graph, wave approvals, verification, commits and every push or PR
step are unchanged. This is **additive**: without the setting, `/build`
behaves exactly as before.

Needs the Codex CLI installed and signed in (see [2b](#2b-enable-codex-multi-model-reviews-optional)).

```bash
# Turn it on (and optionally pin a model) in ~/.config/monsterflow/config.json
python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.config/monsterflow/config.json")
c = json.load(open(p)) if os.path.exists(p) else {"$schema_version": 1}
c["build_workers"] = "codex"
# c["codex_worker_model"] = "<model>"   # optional; default is Codex's own
json.dump(c, open(p, "w"), indent=2)
PY

# Check the model works on your account before a long build
bash scripts/build-codex-worker.sh --probe-model

# Turn it off: set "build_workers": "claude", or delete the key
```

You can also switch for a single run without editing config: tell `/build`
"use Codex workers" (or "use Claude subagents") at a wave approval prompt.

Defaults: `build_workers` absent = `claude`. If Codex isn't installed or
signed in, `/build` falls back to Claude subagents and says so.

Full reference, sandbox limits, project-specific worker rules and
troubleshooting: [`docs/build-workers.md`](docs/build-workers.md).

## 7. Run the pipeline overnight (optional)

Write a spec, then let `/autorun` drive the rest while you sleep — no interactive session needed.

**v0.7+:** `run.sh` processes exactly ONE slug per invocation. For multi-spec queues, use the `autorun-batch.sh` wrapper. Per-axis warn/block policy framework (`verdict` / `branch` / `codex_probe` / `verify_infra`) lets overnight runs ship a degraded PR rather than halt at 3am — security/integrity findings still hardcoded-block.

```bash
# From any project:
cd ~/Projects/myproject

# Queue one or more specs
cp docs/specs/feature-a/spec.md queue/feature-a.spec.md
cp docs/specs/feature-b/spec.md queue/feature-b.spec.md

# Single slug — overnight semantics (warn-eligible axes warn rather than halt)
scripts/autorun/run.sh --mode=overnight feature-a

# Multi-slug queue (replaces the legacy queue-loop; cron-friendly)
scripts/autorun/autorun-batch.sh --mode=overnight

# Or detached via tmux for unattended runs
tmux new-window -n autorun 'scripts/autorun/autorun-batch.sh --mode=overnight; echo "[autorun] done — press enter"; read'

# Morning check
cat queue/runs/index.md
ls queue/runs/<run-id>/morning-report.md
```

**Per-axis policy** (set in `queue/autorun.config.json` or via env vars `AUTORUN_VERDICT_POLICY=warn`, etc.):

```json
{
  "policies": {
    "verdict": "warn",
    "branch": "warn",
    "codex_probe": "warn",
    "verify_infra": "warn"
  }
}
```

`integrity` and `security_findings` axes are NOT config-controllable — hardcoded `block`. `verdict=NO_GO` always blocks; only `GO_WITH_FIXES` is warn-eligible.

**Cron migration (≤ v0.6 → v0.7+):**
```
# Before:
0 22 * * * cd /path/to/repo && scripts/autorun/run.sh
# After:
0 22 * * * cd /path/to/repo && scripts/autorun/autorun-batch.sh --mode=overnight
```

**Known v1 limitation (v0.7):** D33 multi-fence rejection blocks the easy prompt-injection class but does NOT authenticate a single fence quoted from reviewed content. Mitigation is **detection-hardening, not prevention**. For repos processing untrusted spec sources (third-party PRs, externally-authored queue items), set `verdict_policy=block` and disable unattended auto-merge until the architectural fix lands. See `BACKLOG.md` → `autorun-verdict-deterministic`.

**How it works:** `autorun` is a thin CLI wrapper installed at `~/.local/bin/autorun` by `install.sh`. It resolves back to `MonsterFlow/scripts/autorun/run.sh` regardless of where it's called from. The engine (stage scripts, personas) always lives in `MonsterFlow`; the target (git, docs/, queue/) is always `$PWD` of the project you called it from.

**Kill-switch:**
```bash
touch queue/STOP    # honored at iteration boundaries by autorun-batch.sh
                    # (in-flight run.sh completes its current slug)
```

See `commands/autorun.md` for the full reference (config options, failure handling, dry-run mode, notification channels).

## If something looks wrong

Run the doctor — it captures your install state and auto-files a GitHub Issue for Justin:

```bash
cd ~/Projects/MonsterFlow
./scripts/doctor.sh
```

You'll see a URL at the end (the issue it just created). Justin gets the notification.

## Troubleshooting

**`install.sh` errored on symlinks** — you probably have existing regular files at the target path. The installer backs them up to `.bak` first; check if the `.bak` files are what you expected before re-running.

**A command isn't recognized** — slash commands live in `~/.claude/commands/`. Confirm it's a symlink pointing back to this repo:
```bash
ls -la ~/.claude/commands/
```
If entries are regular files (not symlinks), re-run `./install.sh`.

**Want to experiment without breaking your main install** — clone to a different path and just edit files locally without running `install.sh`. Use your own CLAUDE.md to point to your sandbox.

**Plugin install failed** — plugins require Claude Code CLI auth and a working Anthropic account. Run `claude plugins install superpowers context7` directly; see error output.

## `install.sh` flags & env vars

`install.sh` is opinionated and idempotent — re-runs are safe. The flag surface exists for CI, restricted environments, and adopters who want to opt out of the theme layer.

**Flags:**

| Flag | Effect |
|---|---|
| `--help`, `-h` | Print usage and exit 0 (no I/O beyond stdout) |
| `--no-install` | Skip detection + brew install entirely; just symlink. CI escape hatch |
| `--install-theme` | Force theme install (overrides default-N for adopters) |
| `--no-theme` | Skip theme install (wins over `--install-theme`) |
| `--non-interactive` | Suppress all prompts. Auto-detected when stdin is not a TTY |
| `--no-onboard` | Suppress the post-install onboard panel |
| `--force-onboard` | Run the onboard panel even under `--non-interactive` |

Unknown flags exit with code 2 (distinct from REQUIRED-missing exit 1) so CI can tell user-error from environmental failure.

**Env vars adopters might want:**

| Env var | Effect |
|---|---|
| `MONSTERFLOW_OWNER=1` / `=0` | Force owner (1) or adopter (0) mode. Owner mode opts into theme by default and disables the metrics-gitignore default. Without it, the script auto-detects via `$PWD == repo dir` |
| `PERSONA_METRICS_GITIGNORE=1` / `=0` | Override the metrics-gitignore default. `=1` forces opt-in-to-commit (adopter default). `=0` allows commit (MonsterFlow's own repo default). See README "Persona Metrics" for what gets gitignored |

## Going deeper

- `README.md` — repo structure, full pipeline reference
- `plugins.md` — plugin dependencies + what each does
- `domains/mobile/CLAUDE.md` and `domains/games/CLAUDE.md` — example domain configs
- `docs/specs/example-feature/spec.md` — a real spec artifact showing the output shape

**Domain agents** live at `~/.claude/domain-agents/{mobile,games}/` after install (9 agents total — mobile 6, games 3). They aren't active globally; `/kickoff` copies the relevant ones into each project's `.claude/agents/` based on repo signals.

## Staying in sync

This repo is the source of truth. When Justin pushes changes, pull and re-run install:

```bash
cd ~/Projects/MonsterFlow
git pull
./install.sh
```

Re-running the installer is idempotent — existing symlinks get refreshed, real files get backed up to `.bak`.
