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
obsidian-app: "ready" | "can-install" | "manual"  (manual = brew unavailable, EC20)
cmux:         "ready" | "drift" | "na"
```

**Rationale:** all three reviewers identified this as the simplest workable shape. Adding a 6th piece later (Open Question #3 generalization) means one more scalar + one more render arg; that linear growth is acceptable when piece count is fixed at 5.

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

### D5 — `RUNNING:` stdout contract is API surface

Every external command invocation prints `  RUNNING: <command line>` to stdout BEFORE the call. AC5 / AC8b grep against this in `$STUB_LOG`. Under `MONSTERFLOW_INSTALL_TEST=1`, the `RUNNING:` echo fires but the actual command is short-circuited (stub binary on PATH handles it, or the helper returns early).

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

### D7 — `chmod 600` on `~/.obsidian-wiki/config` write

Match the `~/.claude/*.apikey` permissions pattern. Apply before the `mv -f` so the file is never transiently world-readable.

### D8 — Three test-env short-circuits, all behind `MONSTERFLOW_INSTALL_TEST=1`

`install_graphify_cli`, `install_obsidian_app`, and the `graphify claude install` sub-step each guard their slow external call behind the env check. `RUNNING:` echo fires before the guard so AC assertions still see the intent. `graphify claude install` is additionally a separate short-circuit because under tests we don't want graphify mutating `~/CLAUDE.md` + `~/.claude/settings.json` outside the test's $HOME (per api persona OQ#3).

### D9 — Prompt default for vault path: env var if set, else `~/Documents/Obsidian/wiki`

`install_obsidian_env` checks `${OBSIDIAN_VAULT_PATH:-}` from the running shell; if non-empty AND the path resolves to a directory, use it as the prompt default. Otherwise the hardcoded default. Users who already configured their shell don't get a worse-than-their-current-value prompt.

### D10 — Last-wins for duplicate `OBSIDIAN_VAULT_PATH` in config

`grep ... | tail -1` instead of `grep -m1 ...`. Matches shell-eval "last assignment wins" semantics; documents in `parse_obsidian_config` function header.

## Function Surface

All defined at top level (callable under `--no-theme`):

```bash
# Hoisted from do_theme_install (D2)
posix_quote()

# Detection — read-only; stdout = status token; always returns 0
detect_graphify_cli()
detect_wiki_skills()
detect_obsidian_env()
detect_obsidian_app()
detect_cmux_drift()
parse_obsidian_config()    # stdout = expanded vault path; exit 1 if absent/unparseable

# Rendering — read-only; stdout = human-facing block
render_knowledge_summary <g> <w> <e> <a> <c>

# Action — mutating; stdout = RUNNING/WROTE/APPENDED/LINKED/✓/⚠/✗
install_graphify_cli()
install_obsidian_env()
install_obsidian_app()

# Instructions — print-only, no exec
print_wiki_skills_instructions()
print_cmux_drift_instructions()
print_obsidian_app_manual_instructions()

# Orchestrator — single call site at install.sh:~758
do_knowledge_layer()
```

## Implementation Tasks

Three waves, data → behavior → tests. Each wave has natural parallelism within it; cross-wave dependencies are sequential.

### Wave 1 — Foundation (no parallelism between 1.1 and 1.2; 1.3 parallel with 1.1)

| # | Task | Depends On | Size | Parallel? |
|---|---|---|---|---|
| 1.1 | Hoist `posix_quote` to install.sh:~610; delete nested copy in `do_theme_install`. Add comment naming both callers. | — | S | — |
| 1.2 | Add `MONSTERFLOW_APPLICATIONS_DIR` env-override pattern (read in `detect_obsidian_app`); document in `install.sh --help` env-vars list. | — | S | Yes (with 1.1) |
| 1.3 | Write `parse_obsidian_config()` — pure-bash parser handling all 6 input shapes from D3, `tr -d '\r'`, last-wins. Includes function-header comment naming the no-source security invariant. | — | M | Yes (with 1.1) |

### Wave 2 — Detection + render (all parallel; depends only on Wave 1)

| # | Task | Depends On | Size | Parallel? |
|---|---|---|---|---|
| 2.1 | `detect_graphify_cli()` — `command -v graphify` only (per EC1). Token grammar D1. | 1.1 | S | Yes |
| 2.2 | `detect_wiki_skills()` — count `~/.claude/skills/wiki-*/SKILL.md` for the 6 names; emit `manual:N/6`. | 1.1 | S | Yes |
| 2.3 | `detect_obsidian_env()` — call `parse_obsidian_config`, validate `[ -d ]` after tilde expansion, soft-warn on missing `.obsidian/` subdir. | 1.3 | M | Yes |
| 2.4 | `detect_obsidian_app()` — `[ -d "${MONSTERFLOW_APPLICATIONS_DIR:-/Applications}/Obsidian.app" ]`; emit `manual` when `command -v brew` fails (EC20). | 1.2 | S | Yes |
| 2.5 | `detect_cmux_drift()` — `[ -L ~/.config/cmux/cmux.json ]` + `command -v cmux`; emit `ready` / `drift` / `na`. | 1.1 | S | Yes |
| 2.6 | `render_knowledge_summary()` — 5 positional args, prints the ===Knowledge Layer=== block matching spec UX section. | 1.1 | S | Yes |

### Wave 3 — Action + orchestrate + instructions (sequence-sensitive)

| # | Task | Depends On | Size | Parallel? |
|---|---|---|---|---|
| 3.1 | `install_graphify_cli()` — 4-step install (`python3 -m venv` → `pip3 install "graphifyy[mcp]"` → `ln -sf` → `graphify claude install`). Short-circuit each under `MONSTERFLOW_INSTALL_TEST=1` with `RUNNING:` echo first. Idempotency: venv-exists check, symlink-only recovery (EC2). Refuse-and-notice on non-empty venv (EC3). | 2.1 | M | — |
| 3.2 | `install_obsidian_env()` — prompt default from `$OBSIDIAN_VAULT_PATH` env or hardcoded `~/Documents/Obsidian/wiki` (D9). Validate path → atomic write `~/.obsidian-wiki/config` with chmod 600 → append sentinel block to `~/.zshrc` using hoisted `posix_quote`. Skip silently under non-interactive owner mode with no discoverable default (EC19). Skip sentinel append if non-sentinel `OBSIDIAN_VAULT_PATH=` exists (EC5). | 2.3 | M | Yes (with 3.1, 3.3) |
| 3.3 | `install_obsidian_app()` — `brew install --cask obsidian`. Re-check `[ -d ${MONSTERFLOW_APPLICATIONS_DIR:-/Applications}/Obsidian.app ]` after as success oracle (EC17 brew-collision-with-manual-install path). Short-circuit body under `MONSTERFLOW_INSTALL_TEST=1`. | 2.4 | S | Yes (with 3.1, 3.2) |
| 3.4 | `print_wiki_skills_instructions()` — `npx skills add Ar9av/obsidian-wiki` + git-clone fallback when `command -v npx` fails (EC7). | 2.2 | S | Yes |
| 3.5 | `print_cmux_drift_instructions()` — `brew install --cask cmux` recommendation, no exec. | 2.5 | S | Yes |
| 3.6 | `print_obsidian_app_manual_instructions()` — used in EC20 path when brew unavailable. Points to `https://obsidian.md/download` and `…/releases/latest`. | 2.4 | S | Yes |
| 3.7 | `do_knowledge_layer()` — orchestrator. Calls detect helpers, captures 5 scalars, calls render, classifies into Can-install-now + Manual-action-required buckets, prompts only when Can-install bucket is non-empty (owner auto-yes, adopter default-N), dispatches matching install_* helpers, then prints all manual-action instructions. | 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 2.6 | M | — |
| 3.8 | Wire `do_knowledge_layer` into install.sh main flow at line ~758 (after `do_theme_install` returns, before CLAUDE.md merger). Add call-site comment naming the ordering invariant. | 3.7 | XS | — |

### Wave 4 — Tests (sequential within file; can interleave with 3.x once 3.7 lands)

| # | Task | Depends On | Size | Parallel? |
|---|---|---|---|---|
| 4.1 | Create `tests/test-install-knowledge-layer.sh` with setup/teardown/run_install borrowed from `test-install.sh`. Add stub helpers for `graphify`, `brew` (with cask-install argv detection), `npx`. Add `stage_applications_dir_present` / `stage_applications_dir_empty` fixtures using `MONSTERFLOW_APPLICATIONS_DIR`. | 1.2 | M | Yes (with Wave 2-3) |
| 4.2 | Implement AC1 (all-absent summary), AC2 (all-present idempotent), AC3 (no mutations on re-run with marker + per-path find), AC4 (owner auto-yes vs adopter default-N), AC5 (wiki print-only), AC6 (orchestrator wiring), AC7 (cmux drift), AC8a/b (Obsidian.app detection vs install), AC9 (config parser edge inputs). | 3.7, 3.8, 4.1 | L | — |
| 4.3 | Append `test-install-knowledge-layer.sh` to TESTS array in `tests/run-tests.sh` (after all existing entries). Verify orchestrator-wiring guard does not fire. Run full suite to confirm 59 → 60 passing. | 4.2 | XS | — |

## Wave Sequencing Rationale (data → behavior → tests, with parallelism per wave)

- **Wave 1** lays infrastructure both detection and action need (hoisted `posix_quote`, the parser, the test-env override). Three tasks; two are S-sized and parallel.
- **Wave 2** is pure read-only detection + rendering. All six tasks are independent; six parallel agents in `/build` cleanly.
- **Wave 3** has internal parallelism: 3.1/3.2/3.3 are independent installers, 3.4/3.5/3.6 are independent print-only helpers, 3.7 is the orchestrator that fans them in. 3.8 is a trivial call-site wire-up.
- **Wave 4** can run in parallel with Wave 2 (test fixtures + harness) but the AC implementations themselves wait on the orchestrator.

`/build` should dispatch Wave 2 tasks in one parallel batch, Wave 3 print-only helpers + installers in a second batch, then sequential orchestrator + call-site wire-up. Test wiring (Wave 4) overlaps wave 2.

## Open Questions

(None blocking `/check`. These are runtime details `/build` can resolve from context.)

- **Q1 — Render summary exact byte format.** Spec UX section shows specific column alignment (`graphify CLI:        ✓`). Pin the column width in the renderer (~20 chars to the colon, then status). Trivial; `/build` can copy from spec UX block.
- **Q2 — Order of summary block rows.** Spec UX shows: graphify CLI, wiki skills, OBSIDIAN_VAULT_PATH, Obsidian.app, cmux drift. Match that order exactly in `render_knowledge_summary` so AC1 grep assertions work positionally.
- **Q3 — Where do `Manual action required:` instruction blocks print relative to the install actions?** Spec UX shows: install actions first, then "Manual action required:" header + per-piece instructions. Preserve that order in `do_knowledge_layer`.

## Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `posix_quote` hoist regression — nested definition survives the delete pass | Low | High (silent shadow; `--no-theme` runs would still hit undefined fn) | Two-part change in same commit; grep test in /check stage: `grep -c 'posix_quote() {' install.sh` must equal 1 |
| `graphify claude install` writes to adopter `~/CLAUDE.md` outside test fixture | Medium | Medium | D8 short-circuits the sub-call under `MONSTERFLOW_INSTALL_TEST=1`; AC asserts no graphify-managed lines in baseline test fixture's CLAUDE.md |
| Wiki skills hardcoded as 6 — upstream ships a 7th | Medium | Low | Spec explicitly pins "the 6 skills MonsterFlow uses"; doc this in the detection function header; surface as Open Question for future revisit |
| `brew install --cask obsidian` fails when `/Applications/Obsidian.app` exists from manual install | High (the case Justin already hit) | Low | EC17 success-oracle: re-check `[ -d ]` after brew, treat as ✓ regardless of brew exit code |
| Parser handles a config-file shape we didn't anticipate | Low | Low | AC9 covers `export` + quotes + tilde + comments + spaces; `parse_obsidian_config` returns empty + exit 1 on parse failure; caller treats as ✗ (config-malformed) and proceeds |
| Idempotency AC3 flakes due to install.sh's other stages touching unrelated files | Low | Low | AC3 path list is explicit (`~/.local/venvs/graphify`, `~/.local/bin/graphify`, `~/.claude/skills/wiki-*`, `~/.obsidian-wiki`, `~/.zshrc`, `~/.config/cmux`); other stages don't touch these |

## Roster Notes

Resolver picked 3 of 7 design personas under `agent_budget=3`: api (opus), data-model (sonnet), integration (sonnet). Dropped: ux (no UI surface), scalability (5 detections × filesystem checks = sub-second; not load-bearing), security (covered inline by api persona's no-source / posix_quote rationale and data-model persona's chmod 600), wave-sequencer (3 reviewers already produced a coherent wave order without arbitration).

Codex disabled at design gate per /blueprint policy default.
