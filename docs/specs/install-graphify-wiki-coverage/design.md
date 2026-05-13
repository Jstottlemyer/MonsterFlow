---
feature: install-graphify-wiki-coverage
stage: design
created: 2026-05-13
gate_mode: permissive
gate_mode_source: frontmatter
iteration: 1
iteration_max: 3
roster:
  selected: [api, data-model, integration]
  dropped: [ux, scalability, security, wave-sequencer]
  codex_disabled: true
  budget: 3
  selection_method: rankings
verdict: ready-for-check
---

# Design — install-graphify-wiki-coverage

## Architecture Summary

The Knowledge Layer is a **detect → classify → render → dispatch** pipeline inserted into `install.sh` between `do_theme_install` and the `CLAUDE.md` baseline merger. It owns no persistent state of its own — every run re-detects from filesystem state, classifies each of 5 pieces into one of three buckets (Ready / Can install now / Manual action required), renders one summary block, and only prompts when the Can-install-now bucket is non-empty. The only authored files are `~/.obsidian-wiki/config` (atomic write, only if missing) and a sentinel-bracketed `~/.zshrc` block (idempotent append). All other state belongs to upstream installers (`graphify claude install`, `brew install --cask obsidian`, `npx skills add Ar9av/obsidian-wiki`) or to detection-only checks (cmux drift, wiki skill presence).

Three reviewers converged on the simpler option at every decision point: 5 parallel scalar locals over assoc arrays, pure-bash parser over python3 helper, single new test file over shared lib extraction. The api persona pinned the stdout-token grammar (`ready` / `can-install` / `manual:N/M` / `drift` / `na`); the data-model persona pinned the parser semantics (last-wins on duplicate keys, CRLF-tolerant, no `source`); the integration persona pinned the call-site ordering and the `posix_quote` hoist location.

## Design Decisions

### D1 — 5 parallel scalar locals carry per-piece status

Each `detect_<piece>` helper echoes a fixed status token to stdout, captured at the call site into a local var. No `declare -A` (bash 3.2 ceiling per `feedback_negative_array_subscript_bash32`), no exit-code-as-status (`set -euo pipefail` would abort).

```
graphify:     "ready" | "can-install"
wiki:         "ready" | "manual:N/6"     (N=0..5; ready when N=6)
obsidian-env: "ready:<path>" | "can-install" | "warn:<path>"
obsidian-app: "ready" | "can-install"    (no "manual" token — see MF1)
cmux:         "ready" | "drift" | "na"
```

**Detection uses `has_cmd`, not raw `command -v`.** `install.sh:323-332` exposes a `has_cmd()` helper that handles `MONSTERFLOW_HASCMD_OVERRIDE` (test seam) plus Homebrew paths (`/opt/homebrew/bin`, `/usr/local/bin`). All Knowledge Layer detection that probes a binary uses `has_cmd`, never raw `command -v`. (MF3, Codex #3.)

**Rationale:** all three reviewers identified the 5-scalar shape as the simplest workable approach. Adding a 6th piece later (Open Question #3 generalization) means one more scalar + one more render arg; that linear growth is acceptable when piece count is fixed at 5.

### D2 — `posix_quote` hoisted to install.sh:~610, above `detect_owner`

Currently nested inside `do_theme_install` (install.sh:694-697). Knowledge Layer runs under `--no-theme` and needs the helper. Hoist + delete-nested in one commit (two-part change; both halves required to avoid silent shadow).

**Rationale:** Codex flagged the scope leak; integration persona picked the placement (D2 grouping with other standalone helpers). Comment at hoist site: *"Top-level helper; used by do_theme_install and do_knowledge_layer. Defined here so --no-theme runs can still call install_obsidian_env()."*

### D3 — Pure-bash parser for `~/.obsidian-wiki/config`

`grep` + `sed` + `${VAR/#\~/$HOME}` tilde expansion. No `source` (security — user-writable file = arbitrary code execution). No python3 heredoc (per `feedback_hook_stdin_heredoc` memory — stdin collision with vault-path prompt). No temp `.py` file (lifecycle complexity not justified for this parsing surface).

Handles all observed input shapes:
```
OBSIDIAN_VAULT_PATH="~/Documents/Obsidian/wiki"
OBSIDIAN_VAULT_PATH=~/Documents/Obsidian/wiki
export OBSIDIAN_VAULT_PATH="~/Documents/test vault"
  OBSIDIAN_VAULT_PATH="..."                          # leading whitespace
OBSIDIAN_VAULT_PATH="..."   # inline comment
OBSIDIAN_WIKI_REPO=...                               # unknown key — silently skip
```

Last-wins on duplicate keys (matches shell-eval semantics). Defensive `tr -d '\r'` before directory check.

### D4 — Single new test file `tests/test-install-knowledge-layer.sh`

Copy harness pattern from `tests/test-install.sh` (setup_test, teardown_test, run_install, stage_* helpers). Wire into TESTS array of `tests/run-tests.sh` (append after all existing entries; orchestrator-wiring guard enforces parity). Known duplication; shared-lib extraction deferred to a separate spec.

### D5 — `RUNNING:` stdout contract is API surface (split assertion targets)

Every external command invocation prints `  RUNNING: <command line>` to stdout BEFORE the call. AC5 / AC8b grep against this in **`$CASE_OUT`** (install.sh stdout is captured there per `tests/test-install.sh:300` precedent). **`$STUB_LOG`** is the orthogonal assertion target for "did stub binary X actually get invoked?" — populated by stubs themselves writing argv. The two assertion sites are complementary, not interchangeable: CASE_OUT proves the installer announced intent; STUB_LOG proves the binary actually ran (or did not). (MF5, Codex #6.)

Under `MONSTERFLOW_INSTALL_TEST=1`, helpers don't short-circuit (per D8) — they call through to PATH-stubbed binaries which handle the test-fixture filesystem writes (per D13). The `RUNNING:` echo always fires; the stub-or-real binary handles the actual work.

Stable lexicon (extends existing `link_file` shape):
- `  RUNNING: <cmd>` — before external invocation
- `  WROTE:   <path>` — after file write
- `  APPENDED: <path>` — after sentinel-bracketed append
- `  LINKED:  <path> → <target>` — symlink creation
- `  ✓ <piece> installed` — success terminus
- `  ⚠ <message>` — soft warning, non-fatal
- `  ✗ <message>` — hard failure, non-fatal at this stage

### D6 — `MONSTERFLOW_APPLICATIONS_DIR` env override for tests

`detect_obsidian_app` reads `${MONSTERFLOW_APPLICATIONS_DIR:-/Applications}/Obsidian.app`. Tests set `MONSTERFLOW_APPLICATIONS_DIR="$CASE_HOME/Applications"` so the isolated `$HOME` fixture can pre-stage the .app without touching the real `/Applications`. Follows the existing `MONSTERFLOW_HASCMD_OVERRIDE` pattern.

### D7 — `chmod 600` + same-directory temp file on `~/.obsidian-wiki/config` write

Match the `~/.claude/*.apikey` permissions pattern. Write to `~/.obsidian-wiki/.config.tmp.$$` (same directory as target, NOT `$INSTALL_SCRATCH` which lives under `/var/folders/...` and would make `mv` cross-filesystem and lose atomicity). `chmod 600` BEFORE the `mv -f`. Trap cleanup ensures the tmp file is removed if the process is interrupted between create and rename. (MF8, Codex #8.)

### D8 — Test isolation via PATH stubs, NOT helper-level short-circuits (resolves Codex iter2 MF2)

The earlier draft had install helpers check `MONSTERFLOW_INSTALL_TEST=1` and return early. That contradicted D13 (stubs must create filesystem side-effects) — if the helper short-circuits, the stub never runs and the fixture state is never written. Revised contract:

- **Install helpers do NOT check `MONSTERFLOW_INSTALL_TEST=1`.** They unconditionally call `python3`, `pip3`, `brew`, `graphify`, `npx` from PATH. The `RUNNING:` echo (D5) fires before each call.
- **Tests inject stub binaries** at the front of PATH via `$STUB_DIR`. Each stub does two things: (a) writes its argv to `$STUB_LOG` (existing pattern), and (b) creates the minimum filesystem fixture the real binary would write (per D13).
- The `MONSTERFLOW_INSTALL_TEST=1` env var remains a marker for OTHER stages (plugin install, test suite re-invocation per install.sh:794, 819) that the Knowledge Layer doesn't interact with. Knowledge Layer's test isolation is achieved purely through PATH stub substitution.

This collapses the prior "short-circuit OR stub" branching into a single path: helpers always call through PATH; tests stub PATH. AC13 (RUNNING: echo precedes external call) still holds: the echo fires before the stub-or-real call, regardless. The previous concern about `graphify claude install` leaking to adopter state is now resolved by the PATH-stub model — the stubbed `graphify` writes a placeholder SKILL.md inside `$CASE_HOME/.claude/skills/`, never touches `$REAL_HOME`.

### D9 — Prompt default for vault path: env var if set, else `~/Documents/Obsidian/wiki`

`install_obsidian_env` checks `${OBSIDIAN_VAULT_PATH:-}` from the running shell; if non-empty AND the path resolves to a directory, use it as the prompt default. Otherwise the hardcoded default. Users who already configured their shell don't get a worse-than-their-current-value prompt.

### D10 — Last-wins for duplicate `OBSIDIAN_VAULT_PATH` in config

`grep ... | tail -1` instead of `grep -m1 ...`. Matches shell-eval "last assignment wins" semantics; documents in `parse_obsidian_config` function header.

### D11 — Drop EC20 (brew-unavailable Obsidian.app path) — unreachable

`brew` is REQUIRED tier in install.sh (lines 342, 399); a missing brew aborts install.sh BEFORE the Knowledge Layer can run. EC20's "brew unavailable → manual Obsidian.app install instructions" path therefore can never execute from `do_knowledge_layer`'s insertion point. Remove EC20 from spec.md to delete dead code; drop the `manual` token from `detect_obsidian_app`'s grammar; drop `print_obsidian_app_manual_instructions` from the function surface (task 3.6 deleted). (MF1, Codex #1.)

### D12 — Split graphify install: binary now, `graphify claude install` AFTER baseline merger

The plan's rev0 task 3.1 ran the full 4-command graphify install inside `do_knowledge_layer` at install.sh:~758. But `graphify claude install` writes to `~/CLAUDE.md` and `~/.claude/settings.json` (per `docs/graphify-usage.md`); the CLAUDE.md baseline merger runs IMMEDIATELY AFTER `do_knowledge_layer` at install.sh:759. Sequence: graphify writes → baseline merger may overwrite. Codex and Risk persona independently flagged.

Resolution: split graphify install into TWO functions, placed at TWO install.sh sites:

1. **`install_graphify_cli_binary()`** — runs INSIDE `do_knowledge_layer` (current position): `python3 -m venv ~/.local/venvs/graphify`, `pip3 install "graphifyy[mcp]"`, `ln -sf ~/.local/venvs/graphify/bin/graphify ~/.local/bin/graphify`. Stops there. The graphify CLI is on PATH but the skill / hook / CLAUDE.md section are NOT yet installed.

2. **`install_graphify_skill_via_cli()`** — runs AFTER the CLAUDE.md baseline merger at install.sh:~760. Single command: `graphify claude install`. Two-part idempotency gate (per Codex iter2 MF3): only invoke when `has_cmd graphify` AND `[ ! -f ~/.claude/skills/graphify/SKILL.md ]`. PATH-stubbed `graphify` writes the SKILL.md placeholder under tests (D8 + D13); no helper-level short-circuit needed — `$HOME` isolation comes from the harness, not from the helper.

This puts the "skill install" mutations AFTER the baseline merger has run, so graphify's section is the last write to `~/CLAUDE.md` and survives by virtue of being last. The orchestrator `do_knowledge_layer` calls `install_graphify_cli_binary`; the new top-level call site at install.sh:~760 invokes `install_graphify_skill_via_cli` only when `do_knowledge_layer` reported graphify CLI was just installed (or had previously been installed via this path — same idempotency check). (MF2, Codex #2 + Risk.)

### D13 — Test stubs MUST create the expected fixture filesystem state

Since helpers no longer short-circuit (D8 revised), tests rely entirely on PATH stubs to simulate real behavior. Idempotency ACs (AC2, AC3) walk the filesystem AFTER a stubbed install to verify state — stubs that only echo "did the thing" produce illusory passes (second run sees nothing on disk, test crashes). Resolution: every stub in `tests/test-install-knowledge-layer.sh` creates the filesystem artifacts the real binary would. Concretely:

- Stubbed `python3` on `-m venv <path>` creates `<path>/bin/` and `<path>/bin/python3` + `<path>/bin/pip3` placeholders (`pip3` placeholder is itself an executable stub that knows to write `<venv>/bin/graphify` when called with `install "graphifyy[mcp]"`).
- Stubbed `pip3` on `install "graphifyy[mcp]"` (the venv's pip3 placeholder created by the python3 stub, not the system pip3) creates `<venv>/bin/graphify` placeholder + writes a `<venv>/lib/python*/site-packages/graphifyy-0.4.21.dist-info/` marker dir.
- Stubbed `brew` on `install --cask obsidian` creates `${MONSTERFLOW_APPLICATIONS_DIR}/Obsidian.app/Contents/MacOS/` (the minimum to satisfy `[ -d /Applications/Obsidian.app ]`).
- Stubbed `graphify` on `claude install` creates `$HOME/.claude/skills/graphify/SKILL.md` placeholder. (`$HOME` here is `$CASE_HOME` — the test harness's isolated home — so writes never reach `$REAL_HOME`.)

**All stub placeholders that need to be invoked later (the venv-bin `python3` and `pip3`, the `<venv>/bin/graphify`) MUST be created with `chmod +x` so subsequent calls find them executable** (per Codex iter3 SF). Stubs also append `STUB <argv>` to `$EVENT_LOG` (the shared ordering log introduced for AC13).

These stubs live in `tests/test-install-knowledge-layer.sh` and are reset per test case via `setup_test`. (MF6, Codex #5, Codex iter2 MF1+MF2, Codex iter3.)

### D14 — Within-wave parallelism: Wave 2 + Wave 3 serialize; Wave 1 stays parallel; Wave 4 overlaps

Codex iter1 #4 flagged that "all parallel within wave" was overconfident — Wave 2 + Wave 3 helpers all add new functions to the same section of `install.sh` and would collide on insertion order. Wave 1 is different: its three tasks edit structurally non-overlapping regions (1.1 hoists a helper to top-level, 1.2 adds an env-var entry to `--help`, 1.3 adds the parser as a new top-level function). They can parallel safely.

Resolution:
- **Wave 1**: 1.2 and 1.3 parallel with 1.1 (different regions of install.sh; no merge conflict).
- **Wave 2**: `/build` dispatches ONE agent for the whole wave; the agent executes the 6 tasks sequentially. All Wave 2 tasks add detection helpers to the same new section above `do_knowledge_layer`.
- **Wave 3**: Same model as Wave 2 — one agent, sequential tasks.
- **Wave 4**: Task 4.1 (test harness scaffold + stubs in a separate test file) can run in parallel with Waves 2-3 in its own agent. Task 4.2 waits on 3.7/3.8/3.9. Task 4.3 (one-line append to `tests/run-tests.sh`) waits on 4.2. (Codex #4, refined by Codex iter3.)

## Function Surface

All defined at top level (callable under `--no-theme`):

```bash
# Hoisted from do_theme_install (D2)
posix_quote()

# Detection — read-only; stdout = status token; always returns 0
detect_graphify_cli()                    # uses has_cmd (MF3)
detect_wiki_skills()
detect_obsidian_env()
detect_obsidian_app()                    # no "manual" token after MF1
detect_cmux_drift()                      # uses has_cmd (MF3)
parse_obsidian_config()                  # stdout = expanded vault path; exit 1 if absent/unparseable

# Rendering — read-only; stdout = human-facing block
render_knowledge_summary <g> <w> <e> <a> <c>

# Action — mutating; stdout = RUNNING/WROTE/APPENDED/LINKED/✓/⚠/✗
install_graphify_cli_binary()            # venv + pip + symlink ONLY; called from do_knowledge_layer (D12)
install_graphify_skill_via_cli()         # `graphify claude install`; called AFTER baseline merger (D12)
install_obsidian_env()                   # same-dir temp file per D7 (MF8)
install_obsidian_app()                   # uses has_cmd brew (MF3)

# Instructions — print-only, no exec
print_manual_instructions <piece>        # SF3: collapsed wiki + cmux into one helper with case
                                         # (print_obsidian_app_manual_instructions deleted — D11/MF1)

# Orchestrator — TWO call sites in install.sh
do_knowledge_layer()                     # at install.sh:~758, after do_theme_install, before baseline merger
# (no new orchestrator function; install_graphify_skill_via_cli is invoked
#  directly from install.sh:~760, right after the baseline merger.)
```

## Implementation Tasks

Four waves, data → behavior → orchestrator → tests. **Sequencing rule**: Waves 1→2→3 are sequential for install.sh work (Wave N+1 waits on Wave N's install.sh edits). **Wave 4** is in a separate test file and follows a finer-grained schedule: task 4.1 (test harness scaffold + stubs) depends only on 1.2 (`MONSTERFLOW_APPLICATIONS_DIR` env override) and can begin AFTER Wave 1 completes, running in parallel with Waves 2 and 3 in its own agent. Task 4.2 (AC implementations) waits on 3.7/3.8/3.9 since it tests the orchestrator. Task 4.3 (run-tests.sh wiring) waits on 4.2. **Within-wave parallelism is dropped per D14 for Wave 2 and Wave 3 only** — all their helpers edit the same `install.sh` region, so one agent per wave executes the wave's tasks sequentially. Wave 1's three tasks edit non-overlapping regions and stay parallel (1.2 + 1.3 with 1.1).

### Wave 1 — Foundation (1.2 and 1.3 parallel with 1.1)

| # | Task | Depends On | Size | Parallel? |
|---|---|---|---|---|
| 1.1 | Hoist `posix_quote` to install.sh:~610 (verify line < `do_theme_install` invocation line; the hoist must precede its first call site, not just its prior definition). Delete nested copy in `do_theme_install`. Add comment naming both callers. | — | S | — |
| 1.2 | Add `MONSTERFLOW_APPLICATIONS_DIR` env-override pattern (read in `detect_obsidian_app`); document in `install.sh --help` env-vars list. | — | S | Yes (with 1.1) |
| 1.3 | Write `parse_obsidian_config()` — pure-bash parser. Pin the grammar narrow (per Codex #7 + SF5): accepts `[export ]KEY=value` and `[export ]KEY="value"` only; no single quotes, no escaped quotes inside double quotes, `#` introduces comment ONLY when outside double-quoted strings. Tilde expansion via `${VAR/#\~/$HOME}` AFTER quote removal. `tr -d '\r'`. Last-wins on duplicates. Reject malformed lines silently (skip-not-fail) but log a one-line `⚠` notice when at least one line was skipped. Function-header comment names the no-source security invariant. | — | M | Yes (with 1.1) |

### Wave 2 — Detection + render (sequential per D14; depends only on Wave 1)

Per D14, `/build` dispatches ONE agent for the whole wave; the agent executes the 6 tasks sequentially (all touch the same install.sh). Wave 4.1 (test harness scaffold) can run in parallel with this wave in a separate agent.

| # | Task | Depends On | Size |
|---|---|---|---|
| 2.1 | `detect_graphify_cli()` — `has_cmd graphify` only (per EC1 + MF3). Token grammar D1. | 1.1 | S |
| 2.2 | `detect_wiki_skills()` — for each name in an explicit array `(wiki-ingest wiki-update wiki-query wiki-export wiki-lint wiki-capture)`, test `[ -f ~/.claude/skills/$name/SKILL.md ]`; emit `manual:N/6`. NOT a glob count (per Completeness OB3). | 1.1 | S |
| 2.3 | `detect_obsidian_env()` — call `parse_obsidian_config`, validate `[ -d ]` after tilde expansion, soft-warn on missing `.obsidian/` subdir. | 1.3 | M |
| 2.4 | `detect_obsidian_app()` — `[ -d "${MONSTERFLOW_APPLICATIONS_DIR:-/Applications}/Obsidian.app" ]`. Status token is `ready` or `can-install` only — no `manual` (D11/MF1). | 1.2 | S |
| 2.5 | `detect_cmux_drift()` — `[ -L ~/.config/cmux/cmux.json ]` + `has_cmd cmux`; emit `ready` / `drift` / `na`. (has_cmd per MF3.) | 1.1 | S |
| 2.6 | `render_knowledge_summary()` — 5 positional args, prints the ===Knowledge Layer=== block matching spec UX section. Column width ~20 chars to the colon. Row order matches spec UX exactly so AC1 positional greps work. | 1.1 | S |

### Wave 3 — Action + orchestrate + instructions (sequential per D14)

Per D14, single agent for the whole wave; tasks executed sequentially.

| # | Task | Depends On | Size |
|---|---|---|---|
| 3.1a | `install_graphify_cli_binary()` — 4-step install: `mkdir -p ~/.local/bin` (parent for the symlink target; install.sh already creates this at install.sh:564 for `autorun` but Knowledge Layer can run in a state where neither dir exists yet — defense-in-depth per Codex iter3) → `python3 -m venv ~/.local/venvs/graphify` → `~/.local/venvs/graphify/bin/pip3 install "graphifyy[mcp]"` (**venv pip, not system pip3** — per Codex iter2 MF1) → `ln -sf ~/.local/venvs/graphify/bin/graphify ~/.local/bin/graphify`. Each external-command step echoes `RUNNING:` to stdout BEFORE invocation (per D5, MF5); the `mkdir -p` is silent. No helper-level short-circuit — PATH stubs do the work under `MONSTERFLOW_INSTALL_TEST=1` (per D8 revised). Idempotency: venv-exists check, symlink-only recovery (EC2). Refuse-and-notice on non-empty venv (EC3). **NO `graphify claude install` here** — that's 3.1b. | 2.1 | M |
| 3.1b | `install_graphify_skill_via_cli()` — single command `graphify claude install`. Idempotency: gate on `has_cmd graphify` AND `[ ! -f ~/.claude/skills/graphify/SKILL.md ]` (per Codex iter2 MF3 — if 3.1a failed, graphify won't be on PATH; skip cleanly). PATH stub for `graphify` writes the SKILL.md placeholder under tests (D13). EC2 symlink-only-recovery path must NOT re-invoke this — re-detect skill presence before calling. | 2.1, 3.1a | S |
| 3.2 | `install_obsidian_env()` — prompt default from `$OBSIDIAN_VAULT_PATH` env or hardcoded `~/Documents/Obsidian/wiki` (D9). Validate path → atomic write `~/.obsidian-wiki/config` using same-dir temp file `~/.obsidian-wiki/.config.tmp.$$` + `chmod 600` + `mv -f` (D7/MF8) → append sentinel block to `~/.zshrc` using hoisted `posix_quote`. Skip silently under non-interactive owner mode with no discoverable default (EC19). Skip sentinel append if non-sentinel `OBSIDIAN_VAULT_PATH=` exists (EC5). When shell env and config file disagree, prefer config file's value and print a one-line notice (Risk SF). | 2.3 | M |
| 3.3 | `install_obsidian_app()` — `brew install --cask obsidian` (brew is REQUIRED-tier; install.sh aborts before Knowledge Layer if absent — no defensive no-brew branch here per Codex iter2 MF4). Re-check `[ -d ${MONSTERFLOW_APPLICATIONS_DIR:-/Applications}/Obsidian.app ]` AFTER as success oracle (EC17 brew-collision path). When brew exits non-zero AND .app is present, print stderr notice `⚠ brew exited <code> but Obsidian.app is present; treating as success` (SF6, Risk). PATH stub for brew creates the .app fixture under tests (D13). | 2.4 | S |
| 3.4 | `print_manual_instructions <piece>` — single function with case statement for `wiki` and `cmux` pieces (SD-01, collapses former 3.4 + 3.5). `wiki` arm: `npx skills add Ar9av/obsidian-wiki` + git-clone fallback when `has_cmd npx` fails (EC7). `cmux` arm: `brew install --cask cmux` recommendation. (Former 3.6 `print_obsidian_app_manual_instructions` deleted per D11/MF1.) | 2.2, 2.5 | S |
| 3.7 | `do_knowledge_layer()` — orchestrator. Split into two sub-functions for testability (Risk should-fix on 3.7 splitting): `classify_knowledge_layer()` echoes the bucket decisions (pure; unit-testable) and `dispatch_knowledge_layer()` consumes them and runs the installers + prints. `do_knowledge_layer` just sequences detect→render→classify→dispatch. Calls `install_graphify_cli_binary` (NOT the skill installer — that's a separate call site at install.sh:~760 per D12). | 3.1a, 3.2, 3.3, 3.4, 2.6 | M |
| 3.8 | Wire `do_knowledge_layer` into install.sh main flow at line ~758 (after `do_theme_install` returns, before CLAUDE.md merger). Add call-site comment naming the ordering invariant. | 3.7 | XS |
| 3.9 | Wire `install_graphify_skill_via_cli` at install.sh:~760, AFTER the CLAUDE.md baseline merger (D12). Call-site gate is `has_cmd graphify && [ ! -f ~/.claude/skills/graphify/SKILL.md ]` (matches the helper's own internal gate per Codex iter3 — "skill missing" alone is insufficient because 3.1a might have failed, leaving graphify off PATH; the call site and helper both check, defense-in-depth). Add call-site comment explaining why this is split out from `do_knowledge_layer`. | 3.1b, 3.8 | XS |

### Wave 4 — Tests (can run in its own agent in parallel with Waves 2-3)

| # | Task | Depends On | Size | Parallel? |
|---|---|---|---|---|
| 4.1 | Create `tests/test-install-knowledge-layer.sh` with setup/teardown/run_install borrowed from `test-install.sh`. Add `MONSTERFLOW_APPLICATIONS_DIR` env override. Per D13 (MF6), stubs MUST create real filesystem side effects: stub `python3` on `-m venv X` creates `X/bin/{python3,pip3}` placeholders; stub `pip3` on `install "graphifyy[mcp]"` creates `<venv>/bin/graphify` + a dist-info marker; stub `brew` on `install --cask obsidian` creates `${MONSTERFLOW_APPLICATIONS_DIR}/Obsidian.app/Contents/MacOS/`; stub `graphify` on `claude install` creates `~/.claude/skills/graphify/SKILL.md` placeholder. Add `stage_applications_dir_present` / `stage_applications_dir_empty` fixtures. | 1.2 | M | Yes (with Wave 2-3) |
| 4.2 | Implement AC1-AC11 (see ACs section below). Assertion targets: `$CASE_OUT` for installer UI / `RUNNING:` lines (per D5/MF5); `$STUB_LOG` for stub argv (e.g., "npx was/wasn't invoked"). Include `case_posix_quote_hoist_integrity` static assertion: `grep -c '^posix_quote() {' install.sh` equals 1 AND the line of that match precedes the line of `do_theme_install`'s first invocation. | 3.7, 3.8, 3.9, 4.1 | L | — |
| 4.3 | Append `test-install-knowledge-layer.sh` to TESTS array in `tests/run-tests.sh` (after all existing entries; do not hardcode the expected total count — orchestrator-wiring guard enforces parity). Verify the guard does not fire. | 4.2 | XS | — |

## Wave Sequencing Rationale (data → behavior → tests; serial within-wave per D14)

- **Wave 1** lays infrastructure both detection and action need (hoisted `posix_quote`, the parser, the test-env override). Three tasks; 1.2 and 1.3 parallel with 1.1.
- **Wave 2** is read-only detection + rendering. Six tasks; all touch install.sh, so a single agent executes them sequentially (D14, Codex #4).
- **Wave 3** is action helpers + orchestrator + two call sites. Eight tasks (3.1a, 3.1b, 3.2, 3.3, 3.4, 3.7, 3.8, 3.9). Single agent, sequential. `install_graphify_skill_via_cli` is intentionally split out and wired AFTER the CLAUDE.md baseline merger (D12).
- **Wave 4** can run in its own parallel agent (separate test file, doesn't touch install.sh). 4.2 waits on the orchestrator (3.7, 3.8, 3.9) before AC implementation.

`/build` dispatch model: **one agent per wave**, in dependency order. Wave 4's harness scaffolding (4.1) can begin in parallel with Wave 2; AC implementation (4.2) waits.

## Open Questions

(None blocking `/check`. These are runtime details `/build` can resolve from context.)

- **Q1 — Render summary exact byte format.** Spec UX section shows specific column alignment (`graphify CLI:        ✓`). Pin the column width in the renderer (~20 chars to the colon, then status). Trivial; `/build` can copy from spec UX block.
- **Q2 — Order of summary block rows.** Spec UX shows: graphify CLI, wiki skills, OBSIDIAN_VAULT_PATH, Obsidian.app, cmux drift. Match that order exactly in `render_knowledge_summary` so AC1 grep assertions work positionally.
- **Q3 — Where do `Manual action required:` instruction blocks print relative to the install actions?** Spec UX shows: install actions first, then "Manual action required:" header + per-piece instructions. Preserve that order in `do_knowledge_layer`.

## Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `posix_quote` hoist regression — nested definition survives the delete pass | Low | High (silent shadow; `--no-theme` runs would still hit undefined fn) | Two-part change in same commit; **static test assertion** in `case_posix_quote_hoist_integrity` (task 4.2): `grep -c '^posix_quote() {' install.sh` equals 1 AND its line precedes `do_theme_install`'s first invocation |
| `graphify claude install` writes to adopter `~/CLAUDE.md` outside test fixture | Low (after MF7) | High (security: cross-test adopter-state leak) | D12 splits graphify install so `graphify claude install` runs AFTER baseline merger; D8/D13 use PATH stubs (no helper-level short-circuits) so `graphify` invocations resolve to the stubbed binary which writes only inside `$CASE_HOME`; **AC10** asserts `$REAL_HOME/CLAUDE.md` is byte-identical pre/post test run AND `$CASE_HOME/CLAUDE.md` contains no `graphify` section. *sev:security* |
| Wiki skills hardcoded as 6 — upstream ships a 7th | Medium | Low | Explicit name array in `detect_wiki_skills` (NOT a glob); one location to update; document in function header |
| `brew install --cask obsidian` fails when `/Applications/Obsidian.app` exists from manual install | High (the case Justin already hit) | Low | EC17 success-oracle: re-check `[ -d ]` after brew, treat as ✓ regardless of brew exit code. Visible warning when brew exited non-zero (SF6). |
| Parser handles a config-file shape we didn't anticipate | Low | Low | AC9 covers `export` + quotes + tilde + comments + spaces; explicit narrow grammar pinned in task 1.3 (no single quotes, no escapes inside double quotes); malformed lines silently skipped with one-line `⚠` notice; AC9 sub-case for `#` inside quoted vault path (per SF5) |
| Idempotency AC3 flakes due to filesystem timing | Low | Low | `MARKER=$(mktemp); sleep 1` before second run (APFS sub-second mtime); single `find $CASE_HOME -newer "$MARKER"` (per SF4) since harness already isolates $HOME |
| Stub side-effects diverge from real binary behavior | Medium | Medium | D13 codifies stub responsibility — each stub creates the filesystem artifacts the real binary would. Add at least one end-to-end smoke test that runs against `MONSTERFLOW_INSTALL_TEST=0` with mock binaries on PATH (Risk MF) so the un-short-circuited code path is exercised. |

## Additional Acceptance Criteria (added in design rev1 / post-/check round 1)

These extend `spec.md`'s AC1-AC9. Treat as additive — they live here, not in `spec.md`, until /build inlines them.

**AC10 — Adopter state isolation (security guard)** — *sev:security*
Under `MONSTERFLOW_INSTALL_TEST=1`, after `do_knowledge_layer` + the post-merger `install_graphify_skill_via_cli` complete:
- `sha256sum $REAL_HOME/CLAUDE.md` is byte-identical pre/post test run (the test harness's `$HOME` isolation did not leak — graphify did not mutate the developer's real CLAUDE.md). Capture pre-run sha into `$BATS_TMPDIR/real-home-claude-md.sha` at suite start; assert post-run sha matches.
- `grep -q 'graphify\|graphify-out' $CASE_HOME/CLAUDE.md` returns non-zero (graphify did not write to the test fixture's CLAUDE.md under stubs). Stubbed `graphify claude install` writes `~/.claude/skills/graphify/SKILL.md` placeholder only — it does NOT touch CLAUDE.md.

**AC11 — Non-sentinel `OBSIDIAN_VAULT_PATH` skip path** (resolves Completeness SF2 / EC5)
Fixture: pre-stage `$HOME/.zshrc` with a user-authored line `export OBSIDIAN_VAULT_PATH="/some/path"` (no sentinel block). Run install.sh under `MONSTERFLOW_OWNER=1` + all-absent state. Assert:
- `install_obsidian_env` emits `~/.zshrc already exports OBSIDIAN_VAULT_PATH — leaving your line alone` to stdout.
- No `# BEGIN MonsterFlow obsidian-wiki` block appears in `~/.zshrc` after the run (`grep -c "BEGIN MonsterFlow obsidian-wiki"` returns 0).
- `~/.obsidian-wiki/config` IS still written if it was previously absent (the user's manual export covers shell startup; the config file covers wiki skill consumption — both surfaces matter).

**AC12 — `posix_quote` hoist integrity** (resolves Risk MF4 / Completeness SF3)
Static assertion (no fixture; runs against the install.sh source as committed):
- `grep -c '^posix_quote() {' install.sh` returns exactly 1.
- The line number of that match precedes the line number of the first `do_theme_install` invocation: `[ "$(grep -n '^posix_quote() {' install.sh | head -1 | cut -d: -f1)" -lt "$(grep -n 'do_theme_install$' install.sh | head -1 | cut -d: -f1)" ]`.
- `grep -c 'posix_quote() {' install.sh` (without the `^` anchor) ALSO equals 1 (no shadow definition inside any function body).

**AC13 — `RUNNING:` echo precedes external invocation** (resolves Risk MF2 / Codex iter2)
Under `MONSTERFLOW_OWNER=1` + all-absent state, the test fixture introduces a shared event log: stubs append `STUB <argv>` to `$EVENT_LOG`, and `install_graphify_cli_binary`'s `RUNNING:` echo also writes `RUNNING <command>` to `$EVENT_LOG` (in addition to stdout). Assert: in `$EVENT_LOG`, the `RUNNING python3 -m venv ...` line appears BEFORE the corresponding `STUB python3 -m venv ...` line. This catches refactors that reorder helper so the external call fires before the echo. (Per Codex iter3 SF — cross-file ordering between `$CASE_OUT` and `$STUB_LOG` is not establishable without a shared log; `$EVENT_LOG` solves it.)

**AC14 — Stub side-effects produce a realistic post-install filesystem** (resolves Risk MF2 / Codex iter2 MF2)
With D8 revised (helpers always call through PATH; no short-circuit branch), this AC's job becomes: prove the D13 stubs produce a filesystem that subsequent re-detection treats as fully-installed. Fixture: all-absent state + owner-auto-yes. After one install run, re-run install.sh under the SAME PATH stubs. Assert: the second run reports `Knowledge Layer: all present ✓` (all 5 detections see ✓), zero install actions fire, AC3 idempotency holds. This catches the "stub wrote partial state and detector still finds it" regression — the only way for the all-present line to fire is if every stub created enough filesystem state for its corresponding detect helper to return `ready`.

## Roster Notes

Resolver picked 3 of 7 design personas under `agent_budget=3`: api (opus), data-model (sonnet), integration (sonnet). Dropped: ux (no UI surface), scalability (5 detections × filesystem checks = sub-second; not load-bearing), security (covered inline by api persona's no-source / posix_quote rationale and data-model persona's chmod 600), wave-sequencer (3 reviewers already produced a coherent wave order without arbitration).

Codex disabled at design gate per /blueprint policy default.
