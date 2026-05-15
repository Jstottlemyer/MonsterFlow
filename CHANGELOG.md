# Changelog

All notable changes to `MonsterFlow` are documented here.

## [Unreleased]

## [0.14.1] - 2026-05-15

### Fixed

- **`mktemp` portability across BSD + GNU** — every `mktemp -d -t <prefix>` call now uses `<prefix>.XXXXXX` template. Adopters with Homebrew `coreutils` + `gnubin` in PATH get GNU mktemp before `/usr/bin/mktemp`, which rejects bare prefixes ("too few X's in template"). Sites fixed: `install.sh:264` + 6 test setup helpers. Empty mktemp result no longer cascades to file ops in `/`.
- **`tests/run-tests.sh` portability** — 4 missed `setup_test` / `setup_case` sites in `test-install.sh`, `test-install-knowledge-layer.sh`, `test-tier-resolver.sh`, `test-dynamic-roster.sh` were running `mktemp -d -t bare-prefix` and crashing 20-something cases on GNU mktemp systems before any assertion ran.
- **Stale `PROJECT_DIR` shell pollution** — when adopters had `PROJECT_DIR` exported from another tool (e.g., a different project's workflow scripts), the resolver inherited it and looked for spec dirs in the wrong project. Tests now `unset PROJECT_DIR` in setup helpers; runtime resolver (`scripts/resolve-personas.sh`) auto-unsets `PROJECT_DIR` when it points at a path without `docs/specs/` and emits a one-line warning.

### Added

- **`install.sh` auto-install + tail-summary** (per `feedback_install_sh_auto_install_then_tail_summary`) — install.sh now auto-installs everything it can: wiki-skills via `npx skills add Ar9av/obsidian-wiki`, cmux via `brew install --cask cmux` on drift, `flock` via `Brewfile`. Manual-action prompts retired. New `INSTALL_WARNINGS` accumulator + tail-summary block printed as the FINAL output of install.sh enumerates anything that failed or got skipped, with a one-line "Best practice:" fix for each.
- **`Brewfile`** — `brew "flock"` added to RECOMMENDED tier. File-locking required by `scripts/autorun/_policy.sh` + `scripts/_followups_lock.py` for concurrent `/build` safety; stock macOS doesn't ship `flock`.
- **`session-cost.py --cumulative-only`** — additive flag returns integer cents on stdout (exit 0 success / 1 session-data-absent). Used by `_pipeline_banner.sh` for end-banner cumulative-cost emission without re-parsing `session-cost.py`'s human-readable default output.
- **`scripts/doctor.sh` — Environment Pollution Check section** — 15 env-var conditions diagnosed: `PROJECT_DIR` validity, `MONSTERFLOW_DISABLE_BUDGET` / `MONSTERFLOW_OWNER` / `MONSTERFLOW_HASCMD_OVERRIDE` / test-mode flags, `MONSTERFLOW_FORCE_INTERACTIVE` ⊥ `MONSTERFLOW_NON_INTERACTIVE` conflict, install-time flag leaks (`NO_INSTALL`, `NO_ONBOARD`, `FORCE_ONBOARD`, `CMUX_DEMOTE`), `AUTORUN` without `AUTORUN_STAGE`, `coreutils/gnubin` in PATH. Each WARN line includes a `Best practice:` fix.

### Changed

- **`mobile-verify` carved to v0.14.1 BACKLOG** — per `/check ck-pacing-005` 4-way reviewer convergence (scope-discipline + codex-C4/C6 + risk-SF4). Will ship as standalone `mobile-verify-skill` spec with narrowed CODE/INFRA classification + targeted UDID erase + repo-versioned `.claude/skills/mobile-verify/` location.

## [0.14.0] - 2026-05-14

### Added

- **Pipeline progress banners** (`scripts/_pipeline_banner.sh` + `scripts/_pipeline_eta.py`) —
  every gate now emits a start banner before work and an end banner after work.
  Format: `Stage N of M — /<gate> starting · ~Xmin · <step-away marker>` and
  `Stage N of M ✓ /<gate> done (Xm Ys · $N.NN cumulative) · next: /<gate> · N gates remaining`.
  ETA uses documented defaults only (spec=~8min, spec-review=~6min, blueprint=~3min,
  check=~5min, build=varies). Step-away markers: `☕` for 3-6 min, `🌅` for 6+ min.
  Denominator computed from `pipeline_path` frontmatter via Bash 3.2-compat `case` statement.
  Null-guard: emits `[pipeline] /build · standalone mode` when no spec.md or no frontmatter.
  Autorun: all banner output routes to stderr under `$AUTORUN=1`; stdout stays clean for
  verdict-sidecar fence parsing. User-global opt-out: `~/.claude/.banner-disabled` empty marker.

- **Two-path `/compact` prompting** — end-of-gate banner appends a context-aware
  `/compact` suggestion:
  - **Path A** (probe configured): reads `.context_window.used_percentage` from
    `scripts/statusline-command.sh`'s JSON stdin format. Soft prompt at >50%,
    strongly recommended at >75%.
  - **Path B** (probe absent on current Claude Code version): suppresses the
    percentage line; emits a cost-boundary one-liner when cumulative session cost
    has crossed $5 since the last `/compact` or fresh session.
  Path selection written to `docs/specs/<feature>/.compact-mode` (bare literal
  `probe` or `suppress`) by `/blueprint` pre-flight. Throttle sentinel at
  `docs/specs/<feature>/.last-compact-suggestion` (JSON:
  `{"last_context_pct": int, "last_emit_ts": iso8601, "path": "A"|"B"}`).
  Both files gitignored; both fail-open on parse error.

- **Input grammar normalize** — all 13 approval-prompt emission sites across
  `commands/*.md` (kickoff, spec, spec-review, blueprint, check, build, wrap,
  wrap-quick, wrap-insights, wrap-full, autorun, flow) now use uniform `(a/b/c)` +
  Enter format. Free-text augment after letter selection preserved
  (`b also do X<Enter>`). Zero remaining `(1/2/3)`, `(yes/no)`, or `(y/n)` patterns
  in active prompt-emission lines.

- **CLAUDE.md `## Tab-accept suggestions` section** — one paragraph documenting
  Claude Code's built-in Tab/Right-arrow accept-suggestion pattern and
  `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false` opt-out env-var. No scripts touched;
  documentation only.

### Carved out (not in v0.14.0)

> **launchd plist cleanup** — moved to `docs/runbooks/launchd-rebrand-cleanup.md`
> per /spec-review. Operational runbook, not a code change.
>
> **Tab-prefill affordance** — dropped post-/blueprint spike. Claude Code's
> built-in prompt-suggestion system covers the affordance; slash commands cannot
> author suggestions directly. Replaced with the CLAUDE.md documentation paragraph above.
>
> **`mobile-verify` skill** — carved to **v0.14.1** per /check ck-005 (2026-05-14).
> Disproportionate architectural scope (skill location, CODE/INFRA classification,
> targeted UDID erase on infra failure, install.sh skills wave). Will get its own
> /spec → /build cycle. See BACKLOG.md `mobile-verify-skill` entry.

## [0.13.1] - 2026-05-14

### Fixed

- **`/wrap-insights` Phase 1c silent failure** — `scripts/compute-persona-value.py`'s
  cost-walk prompt parser had two related gaps after the plan→design rename:
  (a) `_PERSONA_PROMPT_RE` alternation only matched `(review|plan|check)`,
  silently dropping post-rename `personas/design/<name>.md` mentions in session
  logs; (b) `_DIR_TO_GATE` had no entry for legacy `plan`, so pre-rename session
  logs produced rows with `gate: "plan"` that failed the allowlist enum
  `["spec-review", "design", "check"]` at `emit_rankings()`, aborting the whole
  compute with `ValueError: rankings row N failed allowlist`. Phase 1c showed
  nothing because nothing got emitted. Fix: regex now includes `design`,
  `_DIR_TO_GATE` adds `"plan": "design"` so both eras of session logs attribute
  to the canonical gate. After the fix, `--best-effort` emits 25 rows across
  all 3 gates on a real machine; 12/12 test cases still pass.

## [0.13.0] - 2026-05-14

### Added

- **`uninstall.sh` (cold-start MVP)** — reverse of `install.sh` in
  detector-fallback mode. Dry-run by default; `--apply` commits. Walks
  symlinks under `~/.claude/{commands,agents,personas,templates,hooks,scripts,skills,schemas,domain-agents,commands/_prompts}`
  plus `settings.json`, plus theme stage (`~/.tmux.conf`,
  `~/.config/cmux/cmux.json`, `~/.config/ghostty/config`), plus
  `~/.local/bin/autorun`. Strips sentinel-bracketed blocks from `~/.zshrc`
  (theme + obsidian-wiki) and `~/CLAUDE.md` (baseline). Recognizes
  pre-rebrand `claude-workflow` paths via target-substring fallback.
  Conservative backup-restore (single backup + older than symlink ctime).
  Third-party tools (Obsidian.app, graphify, cmux) left in place with
  manual-removal hint strings.
- **`scripts/_uninstall_helpers.py`** — Python backend (stdlib-only;
  positional-CLI per `feedback_hook_stdin_heredoc` memory). 6 subcommands:
  `parse-manifest`, `detect-fallback-symlinks`, `detect-fallback-backup`,
  `strip-sentinel-block`, `sha256-check`, `tombstone-manifest`.
- **`scripts/claude-md-merge.py` sentinel-retrofit** (MVP subset of
  install-sh-claude-md-ownership prereq): wraps appended canonical sections
  in `# BEGIN MonsterFlow CLAUDE.md baseline` / `# END MonsterFlow CLAUDE.md baseline`
  so `uninstall.sh` can strip them cleanly.
- **`tests/test-uninstall-sh.sh`** — 8 cases covering dry-run no-side-effects,
  `--apply` symlink removal, zshrc sentinel-strip with surrounding content
  preserved, full-file backup before strip, idempotent re-run, unbalanced-sentinel
  refusal, non-MonsterFlow symlink-skip, and pre-rebrand `claude-workflow`-path
  recognition. Wired into `tests/run-tests.sh`.

### Deferred to follow-up specs

- **`install-sh-manifest-emit`** (drafted at `docs/specs/install-sh-manifest-emit/spec.md`)
  — manifest emission + `schemas/install-manifest.v1.schema.json` + `MONSTERFLOW_MANIFEST=1`
  staging gate. Enables ownership-provable manifest-mode reversal.
- **`install-sh-claude-md-ownership`** (drafted; partial — sentinel-retrofit landed
  here as MVP subset; explicit-modes refactor of `claude-md-merge.py` deferred).

## [0.12.1] - 2026-05-14

### Added

- **Ghostty terminal theme** shipped as `config/ghostty.config` (Apple
  Terminal "Homebrew" replica — bright green `#28fe14` phosphor on black,
  SF Mono 13pt, padded windows). `do_theme_install` now symlinks it to
  `~/.config/ghostty/config` alongside the existing cmux + tmux + zsh
  prompt links. Adopters with a hand-edited ghostty config get a
  timestamped `.bak` via the existing `link_file` backup machinery.
- **Post-install Obsidian vault hint** in `install.sh` end-block — fires
  conditionally when `detect_obsidian_env` returns `warn:*` or
  `can-install`. Guides adopter through the one manual GUI step (launch
  Obsidian.app, create vault at `~/Documents/Obsidian/wiki`, re-run
  install). Companion paragraph on `docs/index.html` install section.

### Changed

- **`.gitignore` post-rename cleanup** — mirrors every `plan/*` rule with
  a `design/*` rule (post plan→design rename arc) so persona-metrics
  artifacts under `docs/specs/<feature>/design/` no longer leak into
  `git status`. Also broadens `raw/` → `raw*/` in all four stage dirs so
  rev-archive variants (`raw-rev1/`, etc.) are covered. Adds
  `source.design.md` alongside `source.plan.md` for the `check/` gate.
- **Docs cleanup**: user-facing `design` → `blueprint` references in
  README, flow-card, docs/index.html, and the locked mermaid source at
  `docs/specs/persona-metrics/diagrams.md` (~60 refs across slash-command
  text + mermaid edge labels + artifact filenames). Internal `design`
  identifier preserved per CLAUDE.md guard.
- **Autorun launch-log strings** swap Unicode `→` for ASCII `->` in
  `scripts/autorun/{check,spec-review}.sh` and use braced `${tier}`
  expansion. Pure-cosmetic; renders cleanly across all terminals.

### Spec work (no implementation yet — drafted in this release)

- **`docs/specs/uninstall-sh/`** — full spec pipeline completed: spec
  (rev3, manifest-first hybrid), review (rev2 GO_WITH_FIXES), design (13
  decisions, 6 tasks across 4 waves), check (iter2 GO_WITH_FIXES, 0
  architectural blockers). Awaits two prereq specs before `/build`.
- **`docs/specs/install-sh-manifest-emit/spec.md`** — uninstall-sh
  prereq #4; defines `~/.claude/.monsterflow-install-manifest.jsonl`
  schema + `schemas/install-manifest.v1.schema.json` JSON Schema +
  `MONSTERFLOW_MANIFEST=1` env-var staging gate.
- **`docs/specs/install-sh-claude-md-ownership/spec.md`** — uninstall-sh
  prereq #5; refactors `scripts/claude-md-merge.py` for explicit modes
  (`created_file`/`appended_block`/`skipped_manual`), adds sentinel pair
  around managed `~/CLAUDE.md` content.

## [0.12.0] - 2026-05-13

### Added

- **`install.sh` Knowledge Layer stage.** New `do_knowledge_layer` block
  runs between `do_theme_install` and the CLAUDE.md baseline merger.
  Detects 5 knowledge-layer pieces (graphify CLI, the 6 obsidian-wiki
  skills, `OBSIDIAN_VAULT_PATH`, Obsidian.app, cmux config-without-binary
  drift), classifies each as Ready / Can-install-now / Manual-action-required,
  and prompts only when the Can-install-now bucket is non-empty.
  Adopter default is prompt-N; owner is auto-yes (respects `--no-install`).
  17 new tests in `tests/test-install-knowledge-layer.sh` cover AC1–AC15
  plus `posix_quote` hoist integrity. Suite count: 59 → 60.
- **`MONSTERFLOW_APPLICATIONS_DIR`** env override for `detect_obsidian_app`
  (test seam matching the existing `MONSTERFLOW_HASCMD_OVERRIDE` pattern).
- **`parse_obsidian_config`** pure-bash parser. Handles quoted/unquoted
  values, `export` prefix, inline comments outside quotes, `#` inside
  quoted paths (e.g. `~/Documents/notes#archive`), CRLF tolerance, tilde
  expansion via `${VAR/#\~/$HOME}`, last-wins on duplicate keys. No
  `source`, no `eval` (security invariant in function docstring).

### Changed

- **`posix_quote` hoisted to top-level** (was nested inside
  `do_theme_install`). Required so `install_obsidian_env()` can call
  it under `--no-theme` runs.

### Fixed

- **`config/cmux.json` no longer overrides user theme.** Dropped
  `app.appearance: "system"` (was clobbering adopter-curated look/feel
  via the theme-stage symlink) and `notifications.sound: "default"`
  (no-op re-assertion of the default). Kept `sidebar.branchLayout: "vertical"`
  as a defensible workflow-shape opinion.

## [0.11.10] - 2026-05-13

### Fixed

- **install.sh now refreshes stale symlinks.** New `clean_stale_symlinks()`
  helper removes orphaned `~/.claude/*` symlinks pointing into the repo
  whose targets no longer exist. Catches rename drift — adopters were
  left with a dead `/plan` slash command after PR #15 renamed
  `commands/design.md` → `commands/blueprint.md`. Wired into every link
  pass (commands, _prompts, personas, schemas, scripts, domain-agents,
  templates). Also fixes the stage-loop walk from `personas/plan/`
  (gone) to `personas/design/` after the R2 hard cutover.
- **onboard.sh watchdog leak.** `gh_auth_check_with_timeout` killed the
  watchdog subshell but its `sleep` child was orphaned to launchd and
  ran to completion. Rewrote with explicit `sleep_pid` tracking so no
  zombie sleep survives.

### Performance

- **test-install.sh diagnostics + bounded hangs.** `run_install` and
  `run_install_with_input` gained a 30s watchdog (`RUN_TIMEOUT=N` to
  override) with sentinel-file TIMEOUT detection. A hung install.sh
  dies at 30s with `rc=124` and a `*** TIMEOUT ***` marker appended
  to `$CASE_OUT`, instead of waiting indefinitely (the 220s case_2
  scenario reported on a second machine).
- **Input-pipe-runs-dry guard.** `run_install_with_input` now appends
  20 trailing newlines to the explicit input. Unexpected `read -rp`
  prompts get an empty answer (accept default) instead of blocking
  on a closed pipe — addresses the documented "input may be consumed
  too early" failure mode.
- **TTY inheritance guard.** `run_install` + 4 other bare
  `bash $INSTALL_SH` sites now redirect stdin from `/dev/null`. Forces
  install.sh to non-interactive even when the test suite is invoked
  from a TTY-attached shell (e.g., `./install.sh` triggering
  `tests/run-tests.sh`); previously `[ -t 0 ]` autodetected the
  inherited TTY and prompts blocked.
- **Auto-dump install.sh tail on `[FAIL]`.** Suite runner emits the last
  40 lines of `$CASE_OUT` before teardown on every failed case, so the
  next failure surfaces WHICH prompt or stage stalled.
- Test-env short-circuits under `MONSTERFLOW_INSTALL_TEST=1`:
  `claude-md-merge.py` (install.sh) + `doctor.sh` (onboard.sh) +
  `gh_auth_check_with_timeout` (onboard.sh) skipped, saving several
  subprocesses per case. Healthy suite: 13.6s → 12.3s (~10%).

### Added

- **Spec: `install-graphify-wiki-coverage`.** Captures the future
  Knowledge Layer stage for install.sh — detect graphify CLI, graphify
  skill, the 6 obsidian-wiki skills, and `OBSIDIAN_VAULT_PATH`; offer
  to install only missing pieces; re-run cleanly when state is already
  correct. Ready for `/spec-review`.

### Renamed

- **`/design` slash command renamed to `/blueprint`.** A parallel
  Claude Code session in the CosmicExplorer repo flagged a real
  collision between MonsterFlow's `/design` slash command and the
  `frontend-design` plugin skill. PR #15 renamed `commands/design.md`
  to `commands/blueprint.md` and updated user-facing slash refs
  across CLAUDE.md, README.md, docs/index.html, flow-card.txt, and
  sibling `commands/*.md`. PR #16 catches the `domains/{games,mobile}/CLAUDE.md`
  stragglers + a stale `tests/run-tests.sh` comment.
- **Internal gate identifier remains `design`** (intentional —
  slash-command-only scope). Personas live in `personas/design/`,
  the autorun script is `scripts/autorun/design.sh`, the artifact is
  `docs/specs/<feature>/design.md`, JSONL persists `stage: "design"`,
  selection.json persists `gate: "design"`. Changing those would
  reverse PR #14's hard cutover for no benefit.
- Historical CHANGELOG entries (0.11.0, 0.11.9) intentionally still
  reference `/design` — they describe what was true at the time of
  those releases.

## [0.11.9] - 2026-05-12

### Fixed

- **`auto_merged` false-positive in morning report.** `_merge_policy.sh`
  previously logged `action=auto_merged` for every `gh pr merge --auto`
  exit-0, even when the follow-up `gh pr view --json state` returned
  non-MERGED (queued-behind-branch-protection). `run.sh` then trusted that
  label to set `MERGED=1`, so the morning report could claim a PR shipped
  that was still gated. Now: state-gated — MERGED → `auto_merged`,
  otherwise → `fell_back/auto_queued_unconfirmed`. Action vocabulary
  unchanged; schema-safe.
- **PR draft-verdict NO_GO grep false-positive.** `run.sh` fell back to
  `grep -qi "NO-GO\|NO_GO" check.md` when `check-verdict.json` sidecar was
  missing, which false-positived on any reviewer prose literally mentioning
  those strings. Now: sidecar required; missing sidecar fails closed to
  NO_GO (draft) rather than silently shipping a GO PR.
- **Diff-truncation false flag at exactly 3000 lines.** `verify.sh`
  computed `DIFF_LINE_COUNT` AFTER `head -3000`, so an exact-3000-line diff
  triggered the truncation warning. True line count is now computed
  separately; warning fires only when the raw diff actually exceeds 3000.

### Added

- **Codex adversarial design critique at `/design` gate.** When
  `agent_budget` is configured and Codex is authenticated, the resolver
  emits `codex-adversary` at the design gate. `plan.sh` now runs a
  post-synthesis Codex critique over `plan.md` + spec + review-findings,
  appending a labeled `## Adversarial Design Critique (Codex)` section to
  `plan.md` so `/check` sees it via existing reads. Failure is non-fatal
  (logs a warning, keeps the Claude-only plan). Sibling artifact
  `plan-codex-findings.md` is also written for downstream tooling.

Source: `autorun-shell-reviewer` subagent audit (2026-05-12). 4 findings
graded High/Medium under the 13-pitfall checklist; one High (auto_merged)
+ three Mediums applied this release. Two further Mediums deferred to
follow-ups: `defaults.sh:71-108` `eval` replacement (not exploitable
without hostile config) and a separate codex-axis classification gap.

## [0.11.0] - 2026-05-08

### Renamed

- **`/plan` ceded back to Claude Code; MonsterFlow's design gate is now
  `/design`.** MonsterFlow's pipeline previously claimed the `/plan` slash
  command, which collided with Claude Code's own built-in plan-mode tooling
  (`EnterPlanMode` / `ExitPlanMode` and the `superpowers:writing-plans`
  skill). On 2026-05-12 we removed our `commands/plan.md` entirely so
  `/plan` belongs unambiguously to Claude Code's plan-mode. MonsterFlow
  ships `/design` for the design step. The pipeline now reads as
  `/spec → /spec-review → /design → /check → /build`.
- **No deprecation alias.** Earlier drafts of this rename kept `/plan` as
  a stub that redirected to `/design`; that approach was dropped because
  it kept MonsterFlow occupying a name that legitimately belongs to
  Claude Code. Adopters who type `/plan` will now get Claude Code's
  plan-mode behavior, which is the correct outcome.
- **Internal gate identifier unchanged:** schemas, persona directory paths
  (`personas/plan/`), `gate_mode` keys, `selection.json` `gate` field,
  autorun shell name (`scripts/autorun/plan.sh`), and the artifact filename
  (`docs/specs/<feature>/plan.md`) all keep `plan` as the internal name
  for on-disk artifact backward-compatibility. Only the user-facing slash
  command moved.
- Updated: root CLAUDE.md, README.md, docs/index.html, sibling commands/*.md
  (build, check, spec, spec-review, wrap, kickoff, autorun, _gate-mode),
  domain CLAUDE.mds (`domains/games/`, `domains/mobile/`). Historical
  `docs/specs/*/` artifacts retain `/plan` references as audit trail of
  past pipeline invocations.
- Captured rationale: `feedback_slashcmd_collision_with_claude_builtins`
  memory.

## [0.11.0] - 2026-05-08

Autorun merge-policy default flip — autorun now opens a PR by default;
auto-merge is opt-in per-spec, per-project, or per-CLI. Spec / plan / check
artifacts: `docs/specs/autorun-merge-policy/`.

### ⚠ BREAKING DEFAULT

- **Autorun no longer auto-merges by default.** Previous behavior:
  `gh pr create` → `gh pr merge --squash --auto` if gates clean. New
  behavior: `gh pr create` → leave PR open (`action=pr_only`). Auto-merge
  fires only when an explicit policy is set anywhere in the precedence
  chain (CLI > spec.md > constitution > default).
- **Default value:** `auto_merge_policy: pr` (safe). Reasoning: silent
  regression in main is much costlier than morning PR review, especially
  for downstream projects MonsterFlow runs against (asymmetric-risk).
- **Action required (external adopters):** to preserve the legacy
  auto-merge-on-clean behavior, set one of:
  - Per-spec: `auto_merge_policy: clean` in `spec.md` frontmatter
  - Per-project: `auto_merge_policy: clean` in `<project>/docs/specs/constitution.md`
  - Per-run: `scripts/autorun/run.sh --merge-policy=clean <slug>`
  - Or via `autorun-batch.sh --merge-policy=clean`
- A run-start banner displays the resolved policy + 3 other knobs
  (gate_mode, agent_budget, gate_max_recycles) every run; the merge-policy
  line warns on every run where `resolved_from=default` until the user
  explicitly chooses any value (banner fires forever-until-opt-in).
- **Soft batch-size ceiling:** until `pipeline-autorun-final-status-render`
  ships, run autorun-batch with no more than ~10 specs at a time to avoid
  triage-wall on morning PR review. Interim recipe in `commands/autorun.md`:
  `gh pr list -l autorun --json number,title,isDraft`.

### Added

- New optional frontmatter key `auto_merge_policy: pr | clean | validated`
  in `spec.md` and `<project>/docs/specs/constitution.md`.
- New CLI flag `--merge-policy=<pr|clean|validated>` on
  `scripts/autorun/run.sh` and `scripts/autorun/autorun-batch.sh`.
  Legacy `--auto-merge=` accepted as a deprecated alias (emits one-line
  stderr deprecation notice; will be removed in a future major release).
- `scripts/autorun/_merge_policy.sh` — helper library with
  `merge_policy_resolve`, `merge_policy_validate`, `is_clean_for_merge`
  (mode-aware predicate refining the verdict axis under `gate_mode:
  permissive` to require `VERDICT == GO`), `merge_policy_render_banner`,
  `merge_policy_dispatch` (sole caller of `log_merge_action_completed`),
  `queue_copy_drift_check`, `merge_policy_field_state`, and
  `merge_policy_followups_count`.
- New `validated` policy value falls back to `pr` (NOT `clean`) until
  `autorun-runtime-validation-gate` ships; banner stderr-warns once at
  run start; run.log records `action=fell_back, reason=validated_fallback`.
- New per-run escape hatch: `queue/<slug>/.manual-review` touch file
  forces auto-merge skip for this slug only. Records
  `action=fell_back, reason=manual_review_requested`.
- New audit row schema (split start + end events) on `queue/run.log`:
  `event=merge_policy_resolved` written immediately after policy
  resolution at run start (start row survives mid-run crashes);
  `event=merge_action_completed` written by `merge_policy_dispatch` at
  end. Both joinable on `(slug, run_id)`. Forensic fields: `spec_sha`
  (immutable for the run), `pr_number`, `merge_sha` (MAY be null on
  `auto_merged` because `gh --auto` queues the merge for later).
- `action` enum (closed, 4 values): `pr_only, auto_merged, fell_back,
  merge_failed`.
- `reason` enum (closed, 11 values): `warnings_present, verdict_no_go,
  codex_high_severity, run_degraded, validated_fallback,
  branch_protection, merge_call_failed, manual_review_requested,
  recycle_demoted_findings, pr_create_failed, codex_absent`.
- Drift detector at `run.sh` start: compares `auto_merge_policy` line in
  `queue/<slug>.spec.md` vs canonical at
  `<project>/docs/specs/<slug>/spec.md`. Asymmetric: halts on privilege
  elevation (queue elevates above canonical); warns on downward drift;
  silent-skip when canonical absent (cross-project / hand-queued).
- PR conventions: title `[autorun] <slug>`, body includes verdict +
  spec link + run.log path + merge-policy resolution; label `autorun`;
  re-run force-pushes existing branch.
- Hardening: `gh pr create` failure on the primary terminal-action path
  is caught and recorded as `action=merge_failed, reason=pr_create_failed`;
  branch is preserved; autorun exits 0.
- Hardening: `clean` policy + missing/auth-failed Codex (CODEX_RAN==0)
  under `gate_mode: permissive` falls back to PR-only with
  `reason=codex_absent`. Strict mode preserves vacuous-zero semantics.
- Hardening: `MERGE_POLICY_DISPATCH_OVERRIDE` test hook is gated on
  `MONSTERFLOW_TEST_MODE=1` sentinel; warn-and-ignore in production
  shells.
- Hardening: PR body sanitizer (`_mp_sanitize_pr_body_text`) NFKC-
  normalizes + zero-width-strips reviewer summaries; hard-fails on
  `check-verdict` substring (prompt-injection guard for downstream LLM
  consumers).
- `tests/test-autorun-merge-policy.sh` — 60+ assertions covering
  AC#3/7/8/11/13/16/17/18/19/20/21/22/23/24/25, AC-R1/R2, SA-1/2/3,
  YAML-subset behavior, `is_clean_for_merge` truth table, `(slug,
  run_id)` join key, slug-scoped followups counter.
- `templates/constitution.md` — adds commented-out `auto_merge_policy:`
  example with explanatory note.

### Changed

- `scripts/autorun/run.sh:1069-1102` (legacy four-axis merge gate) is
  now composed via `merge_policy_dispatch`; the four-axis gate
  (`MERGE_CAPABLE`, `CODEX_HIGH_COUNT`, `RUN_DEGRADED`, `VERDICT`) is
  preserved unchanged. `is_clean_for_merge` refines only the verdict
  axis under `clean`-policy permissive mode.
- `commands/autorun.md` — documents the new key, precedence, CLI flag,
  banner content (both verbose/terse tiers), per-run escape hatch,
  manual-pipeline pointer, how to silence the banner, YAML-subset
  semantics, and interim PR-backlog triage recipe.

### Notes

- Manual pipeline (`/spec → /spec-review → /plan → /check → /build`
  invoked interactively) is unaffected — there is no auto-merge step in
  manual flow; the user invokes `gh pr merge` themselves.
- Per-axis merge policy, repository-level branch protection rules, env-
  var escape hatches, and Levenshtein typo-suggestion are explicitly
  out of scope. See `BACKLOG.md`.

## [0.10.10] - 2026-05-07

### Added

- `extractionplan.md` at project root — recovered ULTRAPROMPT Extraction Plan generated by Codex on 2026-05-06 00:17 (294 lines, 6 priorities: Feature Artifact Index, Build Evidence Checker, Check Gate Packet, Manual Pipeline Checkpoints, Optional Feature Tickets, Deterministic Research Trigger). Originally lost to a Claude-session "cleanup" sweep; reconstructed from the Codex session JSONL `apply_patch` payload at `~/.codex/sessions/2026/05/06/rollout-2026-05-06T00-17-06-...jsonl`.

### Notes

- Recovery surfaced a feedback gap (memory `feedback_dont_clean_unfamiliar_untracked_files.md`): substantial untracked files at project root are in-progress user work — investigate before any session-end cleanup. The system prompt's "Executing actions with care" rule applies.

## [0.10.9] - 2026-05-07

Consolidated entry covering v0.10.0 → v0.10.9 (10 patch tags, 2026-05-06 to 2026-05-07). Per-tag granularity collapsed because CHANGELOG was not updated between auto-bumps; future tags will be entered between bumps to preserve granularity (see memory `feedback_auto_bump_changelog_warning.md`).

### Added

- **Tag schema (slice 1 of `dynamic-roster-per-gate`):** closed 9-value tag enum (`schemas/v1/tag-enum.schema.json`) + spec frontmatter stub (`schemas/v1/spec-frontmatter.schema.json`) + persona frontmatter (`schemas/v1/persona-frontmatter.schema.json`) — required `fit_tags:` on all personas. (v0.10.0)
- `tests/test-persona-fit-tags.sh` — validates presence, enum-membership, non-empty, no-duplicates across all 19 pipeline personas. Includes negative-path fixtures under `tests/fixtures/persona-fit-tags/{bad-missing,bad-empty,bad-enum,bad-duplicate}/`. (v0.10.0)
- `fit_tags:` frontmatter backfilled on all 19 pipeline personas (review 6, plan 7, check 6). (v0.10.0)
- `feat(autorun)`: iterative-resolution loops — verdict-axis counter + off-by-one fix. (v0.10.0)
- `feat(autorun)`: security-axis 3-attempt counter + per-run rotate wrapper. (v0.10.0)
- BACKLOG: `pipeline-autorun-heartbeat` adds verifier-evidence-pedantry detection (lever e). (v0.10.2)
- BACKLOG: `pipeline-autorun-source-of-truth-consolidation` (supersedes earlier `pipeline-autorun-run-archive` framing). (v0.10.3)
- BACKLOG: `pipeline-autorun-final-status-render` — single-screen exit summary + /flow card. (v0.10.4)
- BACKLOG: `pipeline-codex-coverage-extension` — extend Codex review from /spec-review + /check to /plan + /build wave-final. (v0.10.9)

### Changed

- `install.sh` symlinks `schemas/` into adopter's `~/.claude/schemas/`, sentinel-bracketed for idempotent re-run. (v0.10.0)
- All 19 persona files gained one frontmatter block. **Note:** `_roster.compute_persona_content_hash` rotates once for every persona — `dashboard/data/persona-rankings.jsonl` will show `persona_content_hash` deltas on next snapshot. No action needed; rebuild is automatic. (v0.10.0)
- `dynamic-roster-per-gate` spec **tier-mix rule updated**: `≥1 Opus + remaining N-1 Sonnet` → `≥1 Opus + ≥1 Sonnet + remainder split 50/50`, with cost-conscious tiebreak (extra seat → Sonnet) for odd remainders. New `tier_policy` keys: `sonnet_min`, `remainder_split`, `remainder_tiebreak`. Deterministic panel-size table for N=2..8 added to spec. (v0.10.8 → v0.10.9 net)
- `dynamic-roster-per-gate` spec **Codex policy** stays `additive` by default (initial v0.10.8 amendment introduced a `tag-gated` mode; reverted in v0.10.9 after evidence audit — Codex's track record of H1/H2 saves on autorun-overnight-policy v6, autorun-verdict-deterministic, and dynamic-roster-per-gate run #6 doesn't justify the gating complexity). Two-state knob: `additive | disabled`.
- A9 grep contract tightened on slice-1 personas (`dynamic-roster-1-tags` attempt 3 fix). (v0.10.1)
- Settings: dropped `"model": "opus"` pin from `settings/settings.json`; harness now picks the model itself for new sessions. (v0.10.7)

### Removed / Rejected

- **`autorun-verdict-deterministic` spec REJECTED** after /spec-review surfaced 8 critical gaps + 4× H1 from Codex (load-bearing: `claude -p` reviewers have stdout, not file-write authority — sidecar emission unimplementable). The cost of closing the v6 single-fence-spoof residual exceeds its narrow attack-surface value. v6 multi-fence detection + NFKC normalization + zero-width stripping remain the baseline. BACKLOG entry preserves all 8 surfaced CGs for any future revisit. (v0.10.5 → v0.10.7 attempt + rejection)
- BACKLOG: `pipeline-gate-permissiveness` row removed (shipped as v0.9.0). (v0.10.0)

### Notes

- No runtime behavior changes ship in this release window beyond the v0.10.0 autorun loops + counters; the v0.10.8 / v0.10.9 tier-mix rule and Codex policy clarifications are spec-only (slice 2+ of dynamic-roster-per-gate will wire them at code level).
- `fit_tags:` remains dormant data until slice 3 (`dynamic-roster-3-tier`) wires the resolver.

## [0.9.0] - 2026-05-05

Pipeline-gate permissiveness — applies the autorun overnight policy framework's per-axis warn/block model to the pipeline gates (`/spec-review`, `/plan`, `/check`). Default flips from de-facto strict (halt-on-anything) to **permissive** with a 7-class finding taxonomy that routes contract / documentation / tests / scope-cuts findings to a `followups.jsonl` artifact instead of blocking. Architectural and security findings continue to halt. Spec / plan / check artifacts: `docs/specs/pipeline-gate-permissiveness/`.

### Added

- Per-axis pipeline-gate policy: `gate_mode: permissive | strict` (default `permissive`) declared in spec frontmatter.
- 7-class finding taxonomy (`architectural`, `security`, `contract`, `documentation`, `tests`, `scope-cuts`, `unclassified`) with per-class warn/block routing.
- `followups.jsonl` artifact at `docs/specs/<feature>/followups.jsonl` — the authoritative store for warn-routed findings; rendered to `followups.md` deterministically.
- `--strict`, `--permissive`, `--force-permissive="<reason>"` CLI flags on `/spec-review`, `/plan`, `/check`.
- `--force-permissive` audit log at `docs/specs/<feature>/.force-permissive-log` (JSONL; NOT gitignored — the audit trail is the auditable artifact).
- `cap_reached + NO_GO` next-steps stderr block (3 options + opinionated lean).
- Migration banners: per-user once-ever (`~/.claude/.gate-mode-default-flip-warned-v0.9.0`) + per-spec one-liner (`docs/specs/<feature>/.gate-mode-warned`).
- New scripts: `_followups_lock.py`, `render-followups.py`, `_gate_helpers.sh`, `build-mark-addressed.py`, `apply-class-tagging-template.sh`, `dry-run-class-coverage.sh`.
- New schemas: `followups.schema.json`.

### Changed

- **DEFAULT FLIP:** pipeline gates default to `permissive` (was: de-facto strict / halt-on-anything in v0.8.x). Specs without an explicit `gate_mode` frontmatter field will route contract / documentation / tests / scope-cuts findings to `followups.jsonl` instead of halting.
- `/check`'s verdict sidecar (`docs/specs/<feature>/check-verdict.json`) bumped to `schema_version: 2`, `prompt_version: "check-verdict@2.0"`. New required fields: `iteration`, `iteration_max`, `mode`, `mode_source`, `class_breakdown`, `class_inferred_count`, `followups_file`, `cap_reached`, `stage` (9 new). Existing fields unchanged.
- `findings.jsonl` rows bumped to `schema_version: 2`, `prompt_version: "findings-emit@2.0"`. New required fields: `class`, `class_inferred`, `source_finding_ids`. Optional `tags` array (open-ended; reserved for `sev:security` parity).
- `/build` wave 1 now reads `followups.jsonl` (filtered to `state: open AND target_phase IN {build-inline, docs-only}`) AFTER verifying the latest `/check` verdict is `GO` or `GO_WITH_FIXES`. Pre-v0.9.0 specs (no sidecar) behave as today.

### Migration

- **To preserve v0.8.x halt-on-anything behavior** on a specific spec: add `gate_mode: strict` to that spec's frontmatter.
- **To opt back into permissive on a strict-flagged spec for one run:** `/check spec-name --force-permissive="<reason>"`. Rejected if `$CI` or `$AUTORUN_STAGE` env vars are truthy (interactive escape-hatch only).
- **Existing in-flight specs without `gate_mode`:** silently default to permissive on first gate run after upgrade. A one-time per-user banner at `~/.claude/.gate-mode-default-flip-warned-v0.9.0` explains the change. A one-line per-spec hint at `docs/specs/<feature>/.gate-mode-warned` is touched on first gate run per spec.
- **`install.sh` upgrade path:** prints a one-time migration note on first run after v0.9.0 install (gated on `~/.claude/.gate-permissiveness-migration-shown` sentinel).
- **Persona-metrics:** historical `findings.jsonl` rows (lacking `class`) are read-defaulted to `unclassified` in `/wrap-insights` Phase 1c and excluded from per-class survival joins.
- **Autorun:** `scripts/autorun/check.sh` now reads `iteration` / `iteration_max` / `cap_reached` from the v2 sidecar; bound-checks the iteration counter; treats `cap_reached: true + NO_GO` as terminal (no further re-cycles). Schema bump + validator update + check.sh handler shipped lockstep in this release.

### Notes on bundling

- v0.9.0 ALSO removes the legacy `grep` fallback in autorun's check-verdict extractor (one-release back-compat per CHANGELOG; see prior `[0.8.0]` entry). The two changes ride v0.9.0 together — clean cut. (OQ3 resolved per /plan: "ride together.")

## [0.5.0] — install.sh rewrite (opinionated, idempotent, owner/adopter-aware) — 2026-05-04

Migration bullets below are the source of truth surfaced by `install.sh`'s upgrade-detect banner (`print_upgrade_message`); diff-clean across both surfaces.

### Changed

- install.sh now installs brew tools for you (was: warn-only)
- cmux added to RECOMMENDED; tmux moved to OPTIONAL

### Added

- Optional shell theme (~/.tmux.conf, cmux config, prompt colors)
- New flags: --no-install, --no-theme, --non-interactive, --no-onboard

### Removed

- macOS-only (Linux guard added)

### Notes

- Full flag surface (incl. `--help`, `--install-theme`, `--force-onboard`) and env-var contract (`MONSTERFLOW_OWNER`, `PERSONA_METRICS_GITIGNORE`) documented in [QUICKSTART.md](QUICKSTART.md#installsh-flags--env-vars).
- Upgrade detection: prior MonsterFlow (or pre-rebrand `claude-workflow`) installs are detected via the `commands/spec.md` symlink target and offered an upgrade prompt with the bullets above.
- Spec / plan / check artifacts: `docs/specs/install-rewrite/`.

## [0.2.0] — Persona Metrics measurement layer

### Added

- **Persona Metrics measurement layer** — every multi-agent gate (`/spec-review`, `/plan`, `/check`) now emits structured artifacts that record which personas raised which findings, whether those findings were unique or shared, and whether they survived revision (or made it through synthesis at `/plan`). Surfaced in `/wrap-insights` as a Persona Drift section showing per-persona `load_bearing_rate`, `survival_rate`, and `silent_rate` across a rolling 10-feature window. The pipeline becomes a measurement loop — *the optimization loop (tiering rules, probe sampling, conditional invocation) lands in the follow-up `persona-tiering` spec.*
  - **Six new artifact types per feature per stage:** `source.<artifact>.md` (pre-review snapshot), `raw/<persona>.md` (per-persona raw output, persisted to disk to retire harness-context-access risk), `findings.jsonl` (clustered, attributed), `participation.jsonl` (every persona that ran, with status), `run.json` (manifest with `run_id`, `prompt_version`, hashes), `survival.jsonl` (next-stage classification).
  - **Three new prompt files** under `commands/_prompts/`: `snapshot.md`, `findings-emit.md`, `survival-classifier.md` (the classifier supports two outcome-semantics modes — addressed-by-revision at `/plan` and `/build`, synthesis-inclusion at `/check`).
  - **Four JSON Schema files** under `schemas/` (draft 2020-12) — machine-checkable contracts referenced by the prompt files.
  - **`/wrap-insights` Phase 1c (Persona Drift)** — diff render against the prior 10-feature window with `↑/↓/→` arrows (5pp deadband). Bare-arg `/wrap-insights personas` renders the full table with `load_bearing_rate` and `survival_rate` side-by-side.
  - **`PERSONA_METRICS_GITIGNORE=1` env var** — adopter-install default flips to opt-in-to-commit (gitignored by default in adopter projects; `MonsterFlow`'s own repo overrides via name-detection in `install.sh`). Protects against accidental commits of verbatim review prose to public repos.
  - **`finding_id` derived from `normalized_signature`** — sha256 of NFC-normalized, lowercased, whitespace-collapsed, sorted source persona-output substrings. Best-effort stable across LLM re-syntheses given identical raw inputs; canonicalization function is deterministic and fixture-tested by `scripts/doctor.sh`.
  - **README and `docs/index.html` mermaid diagrams** updated with the new `Judge · Dedupe · Synth` interstitials between gates and the `Persona Metrics` side observer; all three Judges feed the metrics layer (Tight-C visual recipe).
  - **Spec artifacts:** `docs/specs/persona-metrics/{spec,review,plan,check,diagrams}.md` document the full pipeline cycle. Scope (b) was adopted post-checkpoint via diagram review feedback — `/plan`'s synthesis-inclusion semantics is the new structural piece.

## [0.8.0] — autorun overnight policy framework — 2026-05-05

Per-axis warn/block policy + single-fence verdict extractor + 4-artifact branch reset capture + Python stdlib helper (`_policy_json.py` with AST-audited ban list). **26 acceptance criteria.** Ships via PR #6 after a 4-iteration `/check` pipeline (v1-v3 NO-GO surfaced architectural issues including a nonce mechanism that turned out not to be a trust boundary; v4 GO_WITH_FIXES was documentation/framing only).

Spec / plan / check artifacts: `docs/specs/autorun-overnight-policy/`.

### External adopters: action required

- **Silent default-shift (supervised semantics by default):** existing `queue/autorun.config.json` files without a `policies` block now use **supervised semantics by default** — every policy axis (`verdict`, `branch`, `codex_probe`, `verify_infra`) blocks. Recommended action for overnight runs: add an explicit policies block, OR pass `--mode=overnight`, OR set `AUTORUN_MODE=overnight`.
  ```json
  "policies": {
    "verdict": "warn",
    "branch": "warn",
    "codex_probe": "warn",
    "verify_infra": "warn"
  }
  ```
- **Single-slug breaking change (per AC#24):** `run.sh <slug>` now processes EXACTLY ONE slug per invocation. The legacy queue-loop is gone. Cron'd `run.sh` invocations that depended on multi-slug looping must migrate to `autorun-batch.sh`. Verbatim before/after cron snippet:
  ```
  # Before (v0.x):
  0 22 * * * cd /path/to/repo && scripts/autorun/run.sh
  # After (v0.y):
  0 22 * * * cd /path/to/repo && scripts/autorun/autorun-batch.sh --mode=overnight
  ```
- **`current` symlink rotation in batch mode:** `queue/runs/current` symlink now rotates atomically per slug — intermediate state always points to a valid run-dir (no torn-symlink window).
- **`grep` fallback removal pinned to v0.9.0:** the legacy `OVERALL_VERDICT:`-grep + body-NO-GO-scan fallback (per AC#19) is **one-release back-compat only** and will be removed in v0.9.0. Adopters with custom synthesis prompts MUST emit the fenced ` ```check-verdict ` block before then. After v0.9.0, missing fence → `policy_block check integrity "synthesis omitted check-verdict block"`.
- **`_codex_probe.sh` is the single source for codex availability** (per AC#11). Custom scripts that grep for `command -v codex` should migrate:
  ```sh
  bash scripts/autorun/_codex_probe.sh
  case $? in
    0) ;;             # codex available
    1|2) ;;            # absent / unauthenticated — apply policy
  esac
  ```
- **`queue/autorun.config.json` validation is now fail-fast at startup** (per AC#16). Invalid policy values halt with `INVALID_CONFIG: policies.<axis>="<value>" — must be "warn" or "block"`. Validate your config before the next overnight run.

### Known v1 limitation

> v1 fence extraction rejects multi-fence injection but does not authenticate a single check-verdict fence quoted from reviewed content. Do not use unattended auto-merge on untrusted prompt-bearing content until autorun-verdict-deterministic ships. Mitigation is detection-hardening, not prevention. For repos processing untrusted spec sources (third-party PRs, externally-authored queue items), set `verdict_policy=block` and disable unattended auto-merge.

The architectural fix (deterministic verdict aggregation from structured reviewer outputs, replacing synthesis-emits-sidecar) is carved off to the `autorun-verdict-deterministic` follow-up spec. See `BACKLOG.md` for the XL-sized acceptance bullets.

### Added

- **`wave-sequencer` persona at `/plan`** (7th designer) — owns wave structure and dependency contracts. Codifies the three-gate default surfaced by Codex review: (1) data contract first, (2) UI / behavior closure second, (3) test hardening last. Other `/plan` personas own *what* gets built; `wave-sequencer` owns *the order* and *what each wave commits to*. Flags anti-patterns: polish-bucket waves, schema-as-afterthought, UI-first sequencing, hardening-before-closure, single-mega-wave. Output adds a "Wave decomposition" block per wave with `Closes / Includes / Depends on / Verifier signal / Minimum-shippable test`. Persona-metrics will surface its `load_bearing_rate` over the next ~10 features as the empirical test for whether it earns the slot.
- **Virtuous-loop edges in Diagram 1** (the canonical pipeline mermaid in `docs/specs/persona-metrics/diagrams.md`, propagated to README.md and docs/index.html):
  - `W -. next session reads compiled knowledge .-> S` — closes the knowledge loop. `/wrap` distills graphify graph + wiki + auto-memory; the next session's `/spec` starts smarter.
  - `PM -. drift informs roster decisions .-> K` — closes the measurement loop. `/wrap-insights` Phase 1c surfaces per-persona drift; the human reads it and applies roster decisions at the next `/kickoff` (or via mid-project constitution edit).
  - Both edges are dotted-with-label to distinguish them from the linear forward flow without losing visual weight on what closes the pipeline.

### Changed

- **`/plan` persona count: 6 → 7.** Updated counts everywhere: README "Agent Roster (40 total)" + Plan row (7), docs/index.html h2 + plan card + flow card, install.sh tail summary (29 pipeline personas, 38 pipeline agents), QUICKSTART.md / templates/CLAUDE.md / domains/mobile/CLAUDE.md / commands/_prompts/survival-classifier.md / commands/plan.md (dispatch list + "all 7 agents" / "all 7 designers" prose).
- **Grand total agents: 39 → 40** (29 pipeline personas + 9 domain personas + 2 subagents).

## [0.3.0] — Automation infrastructure + autorun hardening — 2026-05-01

### Added

- **Automation infrastructure: hooks, subagents, skills, test suite** (2026-05-01):
  - **PostToolUse hooks** (`scripts/post-edit-shellcheck.sh`, `scripts/post-edit-json-validate.sh`) wired into `settings/settings.json`. Advisory-only — emit `systemMessage` on findings, never block edits. Catch the PIPESTATUS / quoting / JSON syntax bugs that the recent autorun reviews surfaced *before* commit time.
  - **Subagents** at `.claude/agents/`:
    - `autorun-shell-reviewer` — codifies the 13-pitfall checklist for `scripts/autorun/*.sh` (PIPESTATUS index, `\|\| true` reset, `grep -c` arithmetic, branch invariant, STOP race, slug regex, eval scope, SSH/HTTPS remote, AppleScript injection, `--auto` merge ambiguity, empty-PR loophole, truncated diff, quoting). Returns High/Medium/Low findings with file:line.
    - `persona-metrics-validator` — validates JSONL schema + foreign-key joins + `artifact_hash` freshness across `docs/specs/*/{spec-review,plan,check}/`.
  - **User-only skills** at `.claude/skills/` (both `disable-model-invocation: true` since they have side effects):
    - `autorun-dryrun` — runs the full autorun pipeline in `AUTORUN_DRY_RUN=1` against an isolated tmp git repo with a fixture spec, asserts every artifact lands.
    - `bump-version` — semver bump `VERSION` + commit + annotated tag with dirty-tree / branch / pre-existing-tag pre-conditions and `--dry-run` support.
  - **Test suite** at `tests/` — 5 files, 30+ assertions, all green:
    - `run-tests.sh` (CI runner), `test-hooks.sh`, `test-agents.sh`, `test-skills.sh`, `test-bump-version.sh` (12 assertions), `autorun-dryrun.sh` (full pipeline smoke test).
    - Fixture: `tests/fixtures/autorun-dryrun/sample.spec.md`.
  - **`build.sh` dry-run completeness fix** — stub now writes `pre-build-sha.txt` and invokes `verify.sh` (which has its own dry-run stub) so the full artifact graph lands. Caught by the `autorun-dryrun` test — previously dry-run was a partial simulation.

- **Autorun pipeline correctness — 31 fixes across 3 review rounds** (Sonnet/Opus/Codex, 2026-05-01):
  - **Post-build spec compliance verifier** (`scripts/autorun/verify.sh`) — runs inside the build retry loop after tests pass, checks the cumulative git diff against spec requirements via a second `claude -p` call, injects unmet requirements (`[FAIL]` lines) as explicit context into the next attempt's prompt. Closes the false-done loophole where "routes load + tests pass" was treated as compliance for requirements specifying UI elements / access gates / data fields.
  - **`PIPESTATUS` correctness** — `build.sh:157` now reads `${PIPESTATUS[1]}` (claude) instead of `${PIPESTATUS[0]}` (printf, always 0); `verify.sh` captures inside the `\|\| VAR=...` branch instead of the broken `\|\| true; VAR=${PIPESTATUS[1]}` cross-statement pattern.
  - **`grep -c \|\| echo 0`** replaced with `\|\| true` + `${VAR:-0}` everywhere — prevents "integer expression expected" pipeline aborts when grep finds zero matches.
  - **Branch invariant** — `verify.sh` now fails compliance if `HEAD` is not on `autorun/$SLUG` (catches agents that checked out a different branch).
  - **STOP file race** — `build.sh` re-checks `queue/STOP` after each successful wave; `run.sh` re-checks before PR creation.
  - **Empty-PR loophole** — `verify.sh` now writes `VERDICT: INCOMPLETE` and exits 1 when no commits exist since pre-build SHA, instead of silently exiting 0.
  - **`install.sh` adopter detection** — owner-vs-adopter discriminator changed from `basename "$REPO_DIR"` to `$PWD == $REPO_DIR`. Adopter projects now correctly receive `queue/.gitignore` (previously written only inside the engine repo); persona-metrics gitignore default-flip is robust to clones named "MonsterFlow".
  - **`gh pr merge --auto` state query** — exit 0 means auto-merge *enabled*, not *merged*; `run.sh` now queries `gh pr view --json state` and logs `merge-auto-enabled` if not yet `MERGED`.
  - **SSH remote handling in `gh pr create --repo`** — uses `gh repo view --json nameWithOwner` first, with regex fallback handling both HTTPS and SSH (`git@github.com:owner/repo.git`) URL forms.
  - **AppleScript injection** in `notify.sh` — escapes backslashes and double-quotes before passing the body to `osascript`.
  - **`test_cmd` scope** — `build.sh` and `run.sh` now run `test_cmd` inside `(cd "$PROJECT_DIR" && eval ...)` so adopter tests don't accidentally execute against the engine repo.
  - **Slug regex enforcement** — `run.sh` validates the documented `^[a-z0-9][a-z0-9-]{0,63}$` regex before processing each queue item.
  - **`spec-review` artifact requirement** — `run.sh` treats a missing `review-findings.md` as a failure (was silently allowing risk-analysis to append to a never-created file).
  - **PR-creation failure** now writes `failure.md` (was leaving items in limbo with neither `failure.md` nor `run-summary.md`, causing infinite re-runs).
  - **Stale main fetch** — `run.sh` does `git fetch origin main` and bases the autorun branch on `origin/main` so overnight runs start from a current base.
  - **Codex review context** — both initial and fix-attempt Codex reviews receive the actual `git diff` plus build-log tail (was only the build-log narration, same class of false-done as the original bug).
  - **Webhook JSON escaping** — `notify.sh` uses `python3 json.dumps` for the Slack-compatible payload (was hand-rolled escaping that mangled multi-line content with quotes).
  - **Diff truncation signal** — verifier prompt now warns when the 3000-line cap was hit, so requirements implemented past line 3000 are marked `[FAIL]` rather than silently `[PASS]`.

- **`/spec` Phase 0.2: Adaptive Wiki-Query Callout** (obsidian-wiki integration — **read side of a two-release rollout; write-side `/wrap` Phase 2c ships next**):
  - After Phase 0's context summary, `/spec` invokes the `wiki-query` skill against the raw `$ARGUMENTS` string to surface prior compiled knowledge on the spec topic.
  - Renders a `### Prior wiki knowledge` callout between the context summary and Phase 0.25 / Phase 0.5 Backlog Routing **when `wiki-query` returns ≥1 cited `[[wikilink]]`**. Callout is silent when `wiki-query` returns empty or a "doesn't cover" compensatory tangent — no "no prior wiki" noise.
  - **Max 5 citations** per callout, ranked by `wiki-query`'s own ordering (no re-ranking). Overflow appends *"(N additional pages omitted — run `wiki-query` directly for full results)"*.
  - **Per-page one-liner** sourced from the cited page's `summary:` frontmatter field (capped at 200 chars per obsidian-wiki's contract). Fallback: first non-empty prose line after frontmatter, with leading heading markers stripped, truncated to 200 chars. No agent re-prompting for synthesis at the per-page level.
  - **Stitched-synthesis line** (1-2 sentences across the cited pages) renders **only when the callout has ≥3 citations** — with fewer pages, per-page summaries stand on their own.
  - **Suppress-wins precedence:** if `wiki-query`'s answer contains `"doesn't cover"` / `"not covered"` / `"the wiki doesn't"` phrasing, the callout is suppressed even if wikilinks appear elsewhere. Compensatory "but see..." tangents don't count as affirmative knowledge.
  - **Self-enforced 10s soft timeout.** Claude Code's Skill tool has no runtime timeout primitive — the host agent monitors wall-clock and silently skips the callout if `wiki-query` stalls. On timeout, appends a `QUERY_TIMEOUT` log line to `$OBSIDIAN_VAULT_PATH/log.md` for future latency diagnosis.
  - **Opt-in signal:** existence of `~/.obsidian-wiki/config`. No new config keys, no new env vars. If obsidian-wiki is not installed, Phase 0.2 is a silent no-op.
  - **Host-agent note** added to the top of `spec.md`: the integration assumes Claude Code Skill-tool invocation; other agents (Cursor, Codex, Hermes, OpenClaw) invoke `wiki-query` via their native skill mechanism. Obsidian-wiki already ships per-agent skill discovery via its own `setup.sh`.
- **Spec artifact: `pipeline-wiki-integration`** — full `/spec → /spec-review (2 rounds) → /plan → /check` cycle committed at `docs/specs/pipeline-wiki-integration/`. Documents the integration strategy end-to-end. The planning cycle made a substantive correction during `/plan`: the v1.0 spec's "force-feed source paths into `wiki-update`" mechanism was based on a false assumption about the skill's contract; reading the actual `SKILL.md` revealed `wiki-update` scans cwd + git-delta, not explicit paths. v1.1 redesigned the write-side around host-agent conversational-context steering instead. See `review.md` round 2 for the FAIL → PASS-WITH-NOTES trajectory.
- **`/spec` upgrade** (formerly `/brainstorm`, renamed 2026-04-12 to avoid namespace collision with the deprecated `superpowers` brainstorm command):
  - **Phase 0: Context Exploration** — reads constitution, existing specs, project `CLAUDE.md`, `README`, and the last 20 git commits before the first question. Displays a one-paragraph context summary.
  - **Phase 2: Approach Proposal** (feature-sized work only) — proposes 2-3 distinct approaches with tradeoffs and a recommendation; user picks one before the later Q&A rounds. Skipped for bug-fix and small-change work. If the user declines (*"skip approaches"*), the spec records *"user-directed; no alternatives explored."*
  - **Phase 3: Self-Review Pass** — hybrid behavior after drafting the spec: auto-fixes placeholders and formatting silently; loops one targeted question for semantic contradictions; flags remaining issues in Open Questions.
  - **Recommendation-per-question pattern** — every multiple-choice question includes Claude's lean and reasoning. Codifies what was previously an informal pattern.
  - **Per-command auto-run** — `/spec` can auto-write and auto-invoke `/review` when `auto_enabled` is set AND average confidence ≥ `auto_threshold` (default 0.90) AND minimum single-dimension score ≥ `auto_floor` (default 0.70). Enabled via `--auto` CLI flag or `auto_enabled: true` in the constitution's governance section; CLI overrides.
  - **Symmetry preamble** — `/spec` now carries the same *"Do NOT invoke superpowers skills"* preamble as `/plan`/`/review`/`/check`/`/build`.
- **`/spec`-upgrade feature spec** committed at `docs/specs/spec-upgrade/spec.md` — the specification that drove this upgrade (written via the prior `/spec` command). 0.89 final confidence with 3 Open Questions resolved in this release:
  - User-declines-approaches → record "user-directed" in spec and continue.
  - Auto-run config surface → CLI flag + constitution setting, CLI wins.
  - Commit-read count → fixed at 20 for MVP.
- **Example spec** at `docs/specs/example-feature/spec.md` — reference output demonstrating the upgraded `/spec` flow. Doubles as onboarding documentation.

### Changed

- **`/brainstorm` → `/spec`** — all pipeline commands (`/kickoff`, `/plan`, `/review`, `/check`, `/build`, `/flow`) updated to reference `/spec`. Home `CLAUDE.md` and memory entries updated. Rename was driven by a hard namespace collision with the `superpowers` plugin's deprecated `brainstorm` command; `/spec` is more honest anyway (it produces `spec.md`) and leaves room to extend the command with related spec workflows.

### Deprecated

- None.

### Removed

- None.

### Fixed

- **`/autorun` cross-project support** — the `autorun` CLI and all stage scripts (`run.sh`, `build.sh`, `spec-review.sh`, `plan.sh`, `check.sh`, `risk-analysis.sh`) now cleanly separate `ENGINE_DIR` (where scripts live, always `MonsterFlow`) from `PROJECT_DIR` (the target repo, defaults to `$PWD`). Previously all paths used a single `REPO_DIR` that pointed to `MonsterFlow`, so running `/autorun` from any other project silently operated on the wrong directory. Stage scripts fall back to `REPO_DIR` when `PROJECT_DIR` is unset, so existing single-repo setups are unaffected.
- **`autorun` not on PATH** — `install.sh` now symlinks `scripts/autorun/autorun` → `~/.local/bin/autorun`. Previously the binary was never added to `PATH`, so `autorun start` produced "command not found" outside the repo directory.
- **`autorun` symlink resolution on macOS** — `dirname "$0"` on a symlinked binary resolves to the symlink's directory, not the script's real location. The wrapper now uses a `while [ -L ]` loop (macOS-safe; `readlink -f` is unavailable on stock macOS) to find `ENGINE_DIR` before any path calculation.
- **`/autorun` in-session simulation** — `commands/autorun.md` lacked an explicit action instruction; Claude read the pipeline documentation and attempted to orchestrate each stage interactively. Added an `## Action` block at the top of the command that explicitly delegates to `autorun start` and prohibits in-session simulation.
- **`index.md` PR column placeholder** — `run.sh` was writing `(see 10b)` (a leftover development note) instead of the actual PR URL in the queue summary table. Fixed to read `pr-url.txt`.
- **Namespace collision** between user `/brainstorm` and `superpowers:brainstorm` — resolved by rename.

### Security

- None.

### Known Limitations / Planned for v1.1

- **Approach-proposal trigger heuristic** — during the first smoke-test run (ModelTraining `workflow-map` spec, 2026-04-12), the Phase 2 approach-proposal step **did not fire as a distinct phase** because the feature's structural questions (artifact format, content scope) implicitly carried approach-choice. Need a clearer trigger rule for when the dedicated 2-3-approach proposal runs vs. when structural Qs naturally subsume it. Lean: trigger explicitly when the feature has an architecture / design dimension (e.g., a new service, a new data flow); skip when the feature is essentially "configure X to have shape Y" and structural Qs are the design.

- **Obsidian-wiki integration write side (`/wrap` Phase 2c)** — **planned for the next release.** Adds an auto-evaluated 4-trigger (Karpathy) findings block + free-text comment + `sync/skip` gate when `/wrap` detects session-touched `docs/specs/` files and `~/.obsidian-wiki/config` is present. Also reframes `/wrap`'s header from "be fast — user is leaving" to "compile knowledge for future sessions." Gated behind a read-side dogfood cycle per `docs/specs/pipeline-wiki-integration/plan.md` Decision #6 — write-side ships only after the read-side callout has been validated against real vault content in use.

### Notes

- **Symlink-based install:** `MonsterFlow/install.sh` creates symlinks from `~/.claude/commands/*.md` → this repo's `commands/*.md`. Edits here propagate to the live commands **immediately after `git pull`** — no re-install required. First-time installs over a pre-existing real file auto-backup to `<name>.bak`. Means you can `git pull` this release and `/spec` Phase 0.2 activates on your next `/spec` invocation.
- **Obsidian-wiki is optional infrastructure.** If `~/.obsidian-wiki/config` is absent, Phase 0.2 is a silent no-op — zero behavior change for `/spec` users who haven't set up obsidian-wiki. Install via the upstream repo's `setup.sh` (see [github.com/Ar9av/obsidian-wiki](https://github.com/Ar9av/obsidian-wiki)).
