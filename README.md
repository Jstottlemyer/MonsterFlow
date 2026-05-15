# Claude Workflow Pipeline

An 8-command pipeline for [Claude Code](https://claude.com/claude-code) that adds structured planning, multi-agent review, and execution discipline to any project.

**You say WHAT. Claude handles HOW.** Bug fix, small change, feature, or full V2 — the same pipeline scales. 27 default agent personas review your spec and plan before code gets written, and an end-of-session `/wrap` compiles what you learned into durable memory.

**Install (one-liner):**
```bash
git clone https://github.com/Jstottlemyer/MonsterFlow.git ~/Projects/MonsterFlow && cd ~/Projects/MonsterFlow && ./install.sh
```

> **macOS only; requires [Homebrew](https://brew.sh).** Linux invocations hard-fail with a clear message; the installer uses `brew bundle` to provision the rest. See [QUICKSTART.md](QUICKSTART.md) for the full flag surface.

Then open any project and type `/kickoff` to initialize, or `/flow` to see the reference card.

**License:** MIT — see [LICENSE](LICENSE).

## What This Is

A complete workflow system that scales to the size of the work:

| Work Size | Pipeline |
|-----------|----------|
| Bug fix | Describe it, fix it, verify |
| Small change | `/spec` (quick) then `/build` |
| Feature | Full pipeline: `/kickoff` through `/build` |
| V2 / Rework | Revise existing spec, then full pipeline |

**As of v0.14:** every gate emits start + end banners showing stage-of-total, ETA, cumulative session cost, and step-away markers (`☕` 3–6min, `🌅` ≥6min). Two-path `/compact` prompts suggest context-flush at the right moment. Input grammar is uniform `(a/b/c) + Enter` across all approval prompts. `install.sh` auto-installs everything it can (wiki-skills, flock, cmux on drift) and surfaces any failures as a tail-summary block. `scripts/doctor.sh` diagnoses 15 env-var conditions with best-practice guidance. See [CHANGELOG.md](CHANGELOG.md) for the full v0.14 + v0.14.1 release notes.

## The Pipeline

```mermaid
flowchart TD
    K["/kickoff<br/><sub>constitution<br/>+ agent roster</sub>"]:::setup
    S["/spec<br/><sub>Q&A · confidence-tracked</sub>"]:::define
    SR["/spec-review<br/><sub>requirements · gaps · ambiguity<br/>feasibility · scope · stakeholders</sub>"]:::review
    JS1["Judge · Dedupe · Synth<br/><sub>cluster · attribute · compose<br/>→ review.md</sub>"]:::synth
    P["/blueprint<br/><sub>api · data-model · ux · scalability<br/>security · integration · wave-sequencer</sub>"]:::plan
    JS2["Judge · Dedupe · Synth<br/><sub>→ design.md</sub>"]:::synth
    C["/check<br/><sub>completeness · sequencing · risk<br/>scope-discipline · testability</sub>"]:::gate
    JS3["Judge · Dedupe · Synth<br/><sub>→ check.md</sub>"]:::synth
    B["/build<br/><sub>parallel execute</sub>"]:::execute
    W["/wrap"]:::wrap

    K --> S --> SR --> JS1 --> P --> JS2 --> C --> JS3 --> B --> W

    SP["Superpowers<br/><sub>TDD · verification</sub>"]:::side
    CX["Codex<br/><sub>adversarial review</sub>"]:::accent
    KL["Knowledge layer<br/><sub>graphify · wiki</sub>"]:::side
    PM["Persona Metrics<br/><sub>load-bearing · silent ·<br/>survival rates</sub>"]:::metrics

    SP -.-> B
    CX -.-> SR
    CX -.-> C
    CX -.-> B
    W -. compiles .-> KL
    JS1 ==records==> PM
    JS2 ==> PM
    JS3 ==> PM
    W ==surfaces drift==> PM

    KL -. "wiki-query · graphify<br/>auto-memory" .-> S
    PM -. "drift informs<br/>roster decisions" .-> K

    linkStyle 4,5,6 stroke:#92400e,stroke-width:1.5px,stroke-dasharray:4 3,opacity:0.55

    classDef setup fill:#bfdbfe,stroke:#1e3a8a,color:#1e3a8a,stroke-width:2px
    classDef define fill:#5eead4,stroke:#0f766e,color:#134e4a,stroke-width:2px
    classDef review fill:#fdba74,stroke:#9a3412,color:#7c2d12,stroke-width:2px
    classDef plan fill:#c4b5fd,stroke:#5b21b6,color:#4c1d95,stroke-width:2px
    classDef gate fill:#fda4af,stroke:#9f1239,color:#881337,stroke-width:2px
    classDef execute fill:#86efac,stroke:#15803d,color:#14532d,stroke-width:2px
    classDef wrap fill:#d4d4d8,stroke:#3f3f46,color:#27272a,stroke-width:2px
    classDef synth fill:#7dd3fc,stroke:#075985,color:#0c4a6e,stroke-width:2px
    classDef side fill:#e2e8f0,stroke:#475569,color:#1e293b,stroke-width:2px,stroke-dasharray: 4 3
    classDef accent fill:#fde68a,stroke:#92400e,color:#78350f,stroke-width:2px,stroke-dasharray: 4 3
    classDef metrics fill:#a78bfa,stroke:#5b21b6,color:#2e1065,stroke-width:3px
```

```
/kickoff → /spec → /spec-review → /blueprint → /check → /build
           define    6 PRD        7 design   5 plan    execute
           (Q&A)     agents       agents     agents    (parallel)
```

### The knowledge loop

`/wrap` doesn't just end a session — it compiles what you learned into stores that **the next session reads from**. Every `/spec` and `/kickoff` starts smarter than the last.

```mermaid
flowchart LR
    subgraph SN["Session N"]
      direction TB
      W["/wrap<br/><sub>distill · capture · index</sub>"]:::wrap
    end

    W --> G[("graphify graph<br/><sub>code structure ·<br/>god nodes</sub>")]:::store
    W --> WIKI[("Obsidian wiki<br/><sub>distilled<br/>knowledge pages</sub>")]:::store
    W --> MEM[("CLAUDE.md<br/>+ auto-memory<br/><sub>preferences ·<br/>decisions</sub>")]:::store
    W --> RAW[("_raw/<br/><sub>cheap<br/>captures</sub>")]:::store

    RAW -. wiki-ingest at next /wrap .-> WIKI

    subgraph SN1["Session N+1, N+2, ..."]
      direction TB
      S["/spec  ·  /kickoff<br/><sub>starts with full prior context</sub>"]:::define
    end

    G -. /graphify query .-> S
    WIKI -. wiki-query · &quot;what do I know about X&quot; .-> S
    MEM -. auto-loaded at session start .-> S

    classDef wrap fill:#3f3f46,stroke:#d4d4d8,color:#fff
    classDef define fill:#0f766e,stroke:#5eead4,color:#fff
    classDef store fill:#1e293b,stroke:#7c9cff,color:#e7e9ee
```

**Compile, don't retrieve.** Capture is cheap during the session (`"capture this: X"` → `_raw/`). Distillation happens once at `/wrap`. Reads at the start of the next session are free — the wiki is already structured, the graph is already built, memory is already loaded.

| Command | What It Does | Agents |
|---------|-------------|--------|
| `/kickoff` | One-time project init — scans repo, drafts constitution, selects agent roster | - |
| `/spec` | Confidence-tracked Q&A — writes `spec.md` (falls back to session roster if no constitution) | Interactive |
| `/spec-review` | Parallel PRD review — gaps, risks, ambiguity; + Codex adversarial pass (optional) | 6 reviewers |
| `/blueprint` | Architecture + implementation design (renamed from `/plan` 2026-05-12 — `/plan` belongs to Claude Code's built-in plan-mode now, not to MonsterFlow) | 7 designers |
| `/check` | Last gate before code — validates the plan; + Codex adversarial pass (optional) | 5 validators |
| `/build` | Parallel execution with verification discipline; + Codex implementation review (optional) | Superpowers |
| `/autorun` | Headless overnight pipeline — queues a spec and drives all 8 stages unattended via `autorun start` | Shell |
| `/flow` | Displays workflow reference card | - |
| `/wrap` | Session wrap-up — summary, learnings, git loose ends | - |
| `/autorun-dryrun` | Smoke-tests the full autorun pipeline in `AUTORUN_DRY_RUN=1` mode against a fixture spec — asserts every artifact lands. Use after editing `scripts/autorun/*.sh` | Shell |
| `/bump-version` | Semver bump `VERSION` + commit + annotated tag. Refuses dirty trees, non-`main` branches (override with `--force-branch`), and pre-existing tags | Shell |

<details>
<summary><strong>The full <code>/flow</code> reference card</strong> — click to expand</summary>

```text
╔══════════════════════════════════════════════════════════════╗
║                    SESSION WORKFLOW                          ║
╠══════════════════════════════════════════════════════════════╣
║                                                              ║
║  PROJECT SETUP (once per project)                            ║
║  /kickoff  →  constitution + agent roster                    ║
║                                                              ║
║  FEATURE (full pipeline)                                     ║
║  /spec  →  /spec-review  →  /blueprint  →  /check  →  /build    ║
║   define    6 PRD          7 design   5 plan     execute     ║
║   (Q&A)     agents         agents     agents     (parallel)  ║
║  + firecrawl (research) · context7 (API docs)                ║
║  + codex adversarial review at spec-review, check, build     ║
║    (optional — silent skip if not set up)                    ║
║                                                              ║
║  WORK-SIZE SCALING                                           ║
║  Bug fix:      describe it → fix it → verify                 ║
║  Small change: /spec (quick) → /build                        ║
║  Feature:      full pipeline above                           ║
║  V2/Rework:    revise existing spec → full pipeline          ║
║                                                              ║
║  PARALLEL WORK                                               ║
║  "work on X, Y, and Z in parallel"                           ║
║    → Each dispatched to a subagent                           ║
║                                                              ║
║  IN-SESSION DISCIPLINE                      [Superpowers]    ║
║  → systematic-debugging · verification-before-done           ║
║  → requesting-code-review · ralph-loop (micro-iteration)     ║
║                                                              ║
║  CODE REVIEW                                                 ║
║  Quick:  superpowers requesting-code-review                  ║
║  PR:     /code-review plugin                                 ║
║  Full:   9 parallel code-review personas                     ║
║                                                              ║
║  ARTIFACTS                                                   ║
║  docs/specs/constitution.md     (project principles)         ║
║  docs/specs/<feature>/spec.md   (living spec)                ║
║  docs/specs/<feature>/review.md (PRD review findings)        ║
║  docs/specs/<feature>/design.md (implementation design)      ║
║  docs/specs/<feature>/check.md  (gap checkpoint)             ║
║                                                              ║
║  KNOWLEDGE LAYER                   [graphify + obsidian]     ║
║  Fires automagically at /wrap — no typing, no friction:      ║
║    _raw/ → wiki pages           (wiki-ingest)                ║
║    session → projects/<name>/   (wiki-update)                ║
║    graph export + lint          (wiki-export · wiki-lint)    ║
║    graphify digest → _raw/      (silent arch snapshot)       ║
║  Manual (rare):                                              ║
║    /graphify [path]    build code knowledge graph            ║
║    /graphify query "Q" graph traversal answer                ║
║    "what do I know about X"  wiki-query                      ║
║    "capture this: X"         wiki-capture → _raw/            ║
║  Compile, don't retrieve. Capture cheap, distill at /wrap.   ║
║                                                              ║
║  SESSION END                                                 ║
║  /wrap → summary · learnings · knowledge flush · git ends    ║
║                                                              ║
╠══════════════════════════════════════════════════════════════╣
║  AGENTS: review(6) design(7) check(5) code-review(9)         ║
║  + judge · synthesis · domain agents                         ║
║                                                              ║
║  PLUGINS                                                     ║
║  Always-on:  superpowers · context7                          ║
║  On-demand:  firecrawl · code-review · ralph-loop            ║
║              playwright                                      ║
║  Periodic:   claude-md-management · skill-creator            ║
║              claude-code-setup                               ║
║  Optional:   codex — adversarial review at spec-review,      ║
║              /check, /build (silent skip if not set up)      ║
║                                                              ║
║  Superpowers: in-session execution discipline                ║
║  Plugins: specialized capabilities                           ║
║  You say WHAT. Claude handles HOW.                           ║
╚══════════════════════════════════════════════════════════════╝
```

</details>

## Agent Roster (40 total)

The repo ships **40 agents = 38 personas (29 pipeline + 9 domain) + 2 focused subagents**:

- **29 always-available pipeline personas** — dispatched by `/spec-review`, `/blueprint`, `/check`, `/build` in parallel slices.
- **9 domain personas** — loaded conditionally at `/kickoff` based on project signals.
- **2 Claude Code subagents** — invoked directly via `Agent(subagent_type: ...)`. See the [Subagents](#subagents-focused-reviewers) section below.

A single session calls **only the subset relevant to the current phase** — never all 40 at once. Each `/spec-review`, `/blueprint`, `/check`, or `/build` invokes its own slice.

### Pipeline agents (28) — always available

| Stage | Count | Personas |
|-------|-------|----------|
| Review (`/spec-review`) | 6 | Requirements · Gaps · Ambiguity · Feasibility · Scope · Stakeholders |
| Design (`/blueprint`) | 7 | API · Data Model · UX · Scalability · Security · Integration · Wave Sequencer |
| Check (`/check`) | 5 | Completeness · Sequencing · Risk · Scope Discipline · Testability |
| Code review (full mode) | 9 | Correctness · Dependency · Design Quality · Documentation · Performance · Resilience · Security · Test Quality · Wiring |
| Synthesis layer | 2 | Judge (quality scoring) · Synthesis (multi-agent consolidation) — used by `/spec-review`, `/blueprint`, `/check` |

### Domain agents (9) — loaded conditionally at `/kickoff`

`domains/` ships extra personas that are **not** globally active. `install.sh` symlinks them into `~/.claude/domain-agents/<domain>/`, and `/kickoff` inspects the target project and copies only the relevant ones into `<project>/.claude/agents/`.

- **mobile/** — 6 iOS agents: swift-mentor, beta-feedback-triage, test-writer, feature-flag-manager, release-notes-writer, performance-advisor
- **games/** — 3 game-dev agents: game-state-reviewer, swiftui-scene-builder, accessibility-guardian

Projects can also carry their own agents in `<project>/.claude/agents/` (e.g. AuthTools adds 5 auth-specific agents from a separate private repo, bringing that project's roster to 42).

## Subagents (focused reviewers)

In addition to the pipeline personas, MonsterFlow ships two Claude Code subagents at `.claude/agents/` that you can invoke directly via `Agent(subagent_type: ...)`:

| Subagent | Purpose |
|----------|---------|
| `autorun-shell-reviewer` | Codifies the 13-pitfall checklist for `scripts/autorun/*.sh` — PIPESTATUS index correctness, `\|\| true` PIPESTATUS reset, `grep -c` arithmetic, branch invariants, STOP-file race windows, slug-regex enforcement, `eval` scope, SSH/HTTPS remote handling, AppleScript injection, `gh pr merge --auto` ambiguity, empty-PR loophole, truncated-diff silent pass, quoting. Returns High/Medium/Low findings with file:line. |
| `persona-metrics-validator` | Validates JSONL schema, foreign-key joins, and `artifact_hash` freshness across `docs/specs/*/{spec-review,plan,check}/` so `/wrap-insights` Phase 1c renders meaningful drift, not garbage. |

## Hooks

`settings/settings.json` ships PostToolUse hooks that fire on every `Write`/`Edit`:

- **`scripts/post-edit-shellcheck.sh`** — runs `shellcheck -x` on edited `.sh`/`.bash` files; emits findings as a `systemMessage`. Catches PIPESTATUS / quoting / unset-variable bugs at edit time.
- **`scripts/post-edit-json-validate.sh`** — runs `jq empty` on edited `.json` files. Surfaces stray-comma / missing-quote breakage immediately.

Both hooks are advisory-only (never block edits) and silent on clean inputs. They require `shellcheck` and `jq` on `$PATH`; they no-op silently if either is missing.

## Tests

Verify your install (or any change to the engine) with the test runner:

```bash
bash tests/run-tests.sh                # all 5 test files, 30+ assertions
bash tests/run-tests.sh hooks          # filter by name fragment
bash tests/autorun-dryrun.sh           # autorun smoke test in isolation
```

| Test file | What it covers |
|-----------|---------------|
| `test-hooks.sh` | shellcheck/jq hook behavior on clean and bad inputs |
| `test-agents.sh` | subagent frontmatter validation |
| `test-skills.sh` | SKILL.md frontmatter + `disable-model-invocation` typo guard |
| `test-bump-version.sh` | 12 assertions across all bump types + pre-condition refusals + `--dry-run` |
| `autorun-dryrun.sh` | full autorun pipeline in `AUTORUN_DRY_RUN=1` against an isolated tmp git repo |

CI-friendly: `tests/run-tests.sh` exits non-zero if any test fails.

## Install

```bash
git clone <this-repo> ~/Projects/MonsterFlow
cd ~/Projects/MonsterFlow
./install.sh
```

The installer symlinks commands, personas, templates, and settings into `~/.claude/`, then offers to install plugins.

**To reverse**: `bash uninstall.sh` (dry-run by default; `--apply` commits). MVP cold-start / detector-fallback mode — walks `~/.claude/` symlinks, strips MonsterFlow sentinel blocks from `~/.zshrc` and `~/CLAUDE.md`, restores conservative backups. Third-party tools (Obsidian.app, graphify, cmux) are left in place with manual-removal hints; remove yourself if desired.

## Plugin Dependencies

See [plugins.md](plugins.md) for the full list. Quick install:

```bash
# Required
claude plugins install superpowers context7

# Recommended
claude plugins install firecrawl code-review ralph-loop playwright
```

**Optional — Codex multi-model review:** `/spec-review`, `/check`, and `/build` can call Codex as an adversarial reviewer. It silently skips if Codex isn't configured. See [plugins.md](plugins.md) for setup.

## Artifacts

The pipeline writes persistent spec artifacts to each project:

```
docs/specs/constitution.md          # Project principles (from /kickoff)
docs/specs/<feature>/spec.md        # Living spec (from /spec)
docs/specs/<feature>/review.md      # PRD review findings (from /spec-review)
docs/specs/<feature>/design.md      # Implementation design (from /blueprint)
docs/specs/<feature>/check.md       # Gap checkpoint (from /check)
```

### Persona Metrics (v0.2.0+)

Every multi-agent gate (`/spec-review`, `/blueprint`, `/check`) emits structured measurement artifacts under `docs/specs/<feature>/<stage>/`:

```
spec-review/
  source.spec.md          # snapshot of spec.md at /spec-review start
  raw/<persona>.md        # one file per reviewer (incl. codex-adversary if applicable)
  findings.jsonl          # clustered findings, persona-attributed
  participation.jsonl     # every persona that ran (with status: ok/failed/timeout)
  run.json                # run_id, prompt_version, hashes, status
  survival.jsonl          # written at next stage's Phase 0 — judges what survived revision
```

`/wrap-insights` reads these to render per-persona `load_bearing_rate`, `survival_rate`, and `silent_rate` across a rolling 10-feature window. The pipeline becomes a measurement loop — over time, drift signals which personas are earning their slot.

**Privacy for adopters:** these artifacts contain verbatim review prose (`body` field) that may be sensitive. Adopter installs default to **opt-in-to-commit** (`PERSONA_METRICS_GITIGNORE=1` is set automatically; metrics paths are appended to your `.gitignore`). To commit metrics intentionally, set `PERSONA_METRICS_GITIGNORE=0` before running `install.sh`. `MonsterFlow`'s own repo overrides this default via name-detection in the installer.

### Followups — preserving warn-class findings (v0.9.0+)

Under permissive gate mode (default since v0.9.0), `/spec-review` / `/blueprint` / `/check` classify each finding as **block** (architectural / security / integrity / unclassified — halt the gate) or **warn** (contract / documentation / tests / scope-cuts — carry forward). Warn-class findings are written to `docs/specs/<feature>/followups.jsonl` instead of blocking:

```
docs/specs/<feature>/followups.jsonl   # one row per active warn-class finding
```

Each row carries `class`, `title`, `body`, `suggested_fix`, `target_phase` (`build-inline` | `plan-revision` | `docs-only` | `post-build`), and `state` (`open` | `addressed` | `superseded`). `/build` consumes the file verdict-gated: `build-inline` items are tackled during wave work; `post-build` items stay open after the feature ships and surface in the next `/wrap-insights` pass.

This is the load-bearing path for **scope-cuts** specifically — reviewer-suggested cuts that the team isn't ready to take don't get dropped on the floor; they live in `followups.jsonl` with a `target_phase: post-build` row and resurface at the right moment. Product-level decisions worth revisiting beyond one feature land in [`BACKLOG.md`](BACKLOG.md) with a cross-link to the followup `finding_id`.

Schema: [`schemas/followups.schema.json`](schemas/followups.schema.json). Gate-mode reference: [`commands/_gate-mode.md`](commands/_gate-mode.md).

## Customization

1. **Add project-specific agents** — create personas at `/kickoff` via the constitution template
2. **Add domain extensions** — drop agent `.md` files in `domains/<your-domain>/agents/`
3. **Personalize** — create a `~/CLAUDE.md` with your own context (role, projects, preferences)

## Structure

```
MonsterFlow/
├── install.sh                  # Installer — symlinks everything into ~/.claude/
├── plugins.md                  # Plugin dependency manifest
├── commands/                   # 10 pipeline commands (incl. /autorun, /flow, /wrap)
├── personas/                   # 28 agent personas (26 stage + judge, synthesis)
│   ├── check/       (5)
│   ├── code-review/ (9)
│   ├── plan/        (6)
│   └── review/      (6)
├── .claude/
│   ├── agents/                 # 2 focused subagents
│   │   ├── autorun-shell-reviewer.md
│   │   └── persona-metrics-validator.md
│   └── skills/                 # 2 user-only skills
│       ├── autorun-dryrun/
│       └── bump-version/
├── templates/
│   ├── constitution.md         # Project constitution template
│   └── repo-signals.md         # Domain-detection reference for /kickoff + /spec
├── settings/
│   └── settings.json           # Base settings (permissions, plugins, hooks)
├── scripts/
│   ├── autorun/                # Autonomous overnight pipeline (run/build/verify/notify)
│   ├── post-edit-shellcheck.sh # PostToolUse hook: shellcheck on .sh edits
│   ├── post-edit-json-validate.sh  # PostToolUse hook: jq empty on .json edits
│   ├── bump-version.sh         # /bump-version backing script
│   ├── session-cost.py         # Per-session cost reporter (used by /wrap)
│   └── doctor.sh               # Diagnostic report → auto-files GitHub Issue
├── tests/                      # 5 test files, 30+ assertions
│   ├── run-tests.sh            # CI runner
│   ├── test-{hooks,agents,skills,bump-version}.sh
│   ├── autorun-dryrun.sh       # full pipeline smoke test
│   └── fixtures/
└── domains/                    # Domain-specific extensions
    ├── mobile/                 # iOS development
    └── games/                  # Game development
```
