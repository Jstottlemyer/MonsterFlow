# MonsterFlow Backlog

Ideas not yet scheduled. Newest at the top. Each item: one-liner, **Why:**, **Size:** (S / M / L), and any concrete entry point.

Move an item to a `docs/specs/<feature>/spec.md` (via `/spec`) when you're ready to work on it; delete from here once it lands.

> **2026-05-04:** install.sh rewrite shipped (v0.5.0) — see CHANGELOG.md.
> **2026-05-13:** install-graphify-wiki-coverage shipped (v0.12.0) — see CHANGELOG.md.
> **2026-05-15:** install-obsidian-vault-baseline shipped (v0.15.0) — see CHANGELOG.md.

---

## Captured 2026-05-15 (session ideas)

- **`dashboard-actionable-surface` (spec candidate, S-M)** — current dashboard lets you "click around and think 'oh that's interesting'" but doesn't answer the decision-facing questions a user actually has at session start or post-overnight-run. Replace or supplement the data display with a top-of-page "what do I need to know right now" panel: active spec status, last autorun verdict, flagged loose ends, next recommended action. **Why:** discovery-mode browsing is low-value; the dashboard should surface the answer, not require the user to find it. **Entry points:** `dashboard/index.html` + `scripts/judge-dashboard-bundle.py`. **Size:** S-M (mostly render + surfacing existing data differently; no new data pipeline). **Sequencing:** unblocked.

- **`pipeline-user-wait-time-metric` (spec candidate, S-M)** — track time spent waiting on user input vs. Claude working, across pipeline stages. Store as `wait_seconds` per stage in `dashboard/data/gate-timing.jsonl`. Use as the primary ROI signal for autorun: "this spec took 47 min of your active attention; autorun would have done it overnight while you slept." Expose in `/wrap` summary and on the dashboard as a per-feature "your time invested" line. **Why:** wait-time is the concrete, person-hours cost of the manual pipeline; quantifying it makes the autorun value proposition legible rather than abstract. **Entry points:** extend `scripts/session-cost.py` or add a separate `scripts/_wait_time.py`; hook into existing gate-timing work (`pipeline-eta-from-timing-data` is a sibling). **Size:** S-M. **Sequencing:** pairs naturally with `pipeline-eta-from-timing-data` (v0.15).

- **`autorun-suitability-indicator` (spec candidate, S)** — at `/spec` completion and at the start of `/blueprint`, emit an "autorun suitability" score for the feature (High / Medium / Low) based on: spec complexity, security surface, estimated gate count, and whether the feature has mobile/external-service dependencies that require human-in-loop. If High, present autorun as the recommended next step with a projected wait-time savings estimate (seeded from `gate-timing.jsonl` medians once that data exists, fallback to hardcoded tier estimates until then). Frame as a pro feature: "this spec is autorun-ready — run overnight and ship without waiting on gates." **Why:** autorun adoption is low because users don't know when it's appropriate; a suitability signal at the point where the decision matters (end of `/spec`) drives the right behavior. ROI is the hook — time saved = hours of user waiting at gate prompts. **Entry points:** `commands/spec.md` Phase 3 exit block + `commands/blueprint.md` Phase 0 preflight; new `scripts/_autorun_suitability.py`. **Size:** S (heuristic scoring, no ML). **Sequencing:** depends on `pipeline-user-wait-time-metric` for the ROI number; suitability classification can ship first with static estimates.

- **`spec-qa-terminal-formatting` (spec candidate, XS-S)** — improve `/spec` Q&A phase terminal rendering. **Chosen design (2026-05-16):** question line in green, option letter (`a)`, `b)`, `c)`) in green, option text in default terminal color, blank line between question and options, `[default: x]` hint in default color. No bullets — the green letter carries the visual weight. Example: `\033[32mHow should X work?\033[0m` then `\033[32ma)\033[0m option text`. Apply same pattern to any interactive choice prompt in `/blueprint` and `/check`. **Why:** external user feedback 2026-05-16 — all-green rendering makes options hard to scan; contrast between question/letter (green) and option text (default) is the fix. **Entry points:** `commands/spec.md` Q&A emit blocks; matching blocks in `commands/blueprint.md` and `commands/check.md`. **Size:** XS-S (formatting only, no logic). **Sequencing:** unblocked.

- **`flow-goal-autoship-pattern` (doc update, XS)** — document the `/goal "shipped via merged PR"` pattern in the `/flow` reference card. Pattern: run `/spec` → get spec-review → type `/goal "shipped via merged PR"` to hand control to autorun for the remainder (design → check → build → PR → merge). The pipeline's autonomy loop picks up from the current stage. This was used in session 2026-05-15 to auto-ship the wiki-write-conventions release without waiting on each gate interactively. Also note: `/goal` authorizes the merge action but NOT branch-protection bypass (per memory `feedback_goal_mode_doesnt_imply_admin_merge.md`). **Entry points:** `commands/flow.md`. **Size:** XS (~10 lines). **Sequencing:** unblocked.

---

## From wiki-write-migrate V2 session (2026-05-16)

- **`pipeline-goal-wrap-default` (spec candidate, S)** — `/spec-review`'s Phase 3 approval gate (and parallel surface in `/check`) auto-emits a copy-pasteable "ship under /goal" option alongside the existing approve / refine choices. The skill computes the feature slug from cwd and the AC count from the spec's `## Acceptance Criteria` section, producing a ready-to-paste line:
  ```
  export AUTORUN=1
  /goal docs/specs/<slug>/spec.md is shipped via merged PR with verifier reporting <N>/<N> ACs PASS
  ```
  User pastes verbatim into their next message; Claude Code sets the goal condition; pipeline drives `/blueprint → /check → /build → PR → merge` autonomously. **Why:** tonight's wiki-write-conventions ship (v0.16.0, PR #21) demonstrated the pattern works end-to-end under /goal-wrapped autonomy. The friction was the user having to remember the /goal syntax + correct feature slug + correct AC count. Surfacing the line at the gate where the human decision was just made (review/check verdict in hand, spec fresh) makes autonomy the natural default rather than an obscure power-user invocation. **Size:** S. Touches: `commands/spec-review.md` (~10 LoC Phase 3 addition), `commands/check.md` (parallel addition in the GO/GO_WITH_FIXES branches), `commands/_gate-mode.md` if the prose belongs in a single canonical source, tests for both skills (assert the suggested line is emitted with the correct slug+count format). **Open questions for `/spec`:** (1) does `/check`'s "ship under /goal" suggestion fire on GO_WITH_FIXES too (probably yes — that's the permissive-mode normal-flow) or only GO? (2) should the suggested line also surface `--auto-merge=clean` flag guidance when the repo's `auto_merge_policy` is `pr` (default) — i.e., tell the user the PR will queue rather than auto-merge unless they want admin-merge? (3) any other gate where the same surfacing applies — `/spec` Phase 4 auto-run already has a similar shape (auto-invoke /spec-review when confidence ≥ threshold); could be unified. **Entry point:** `/spec pipeline-goal-wrap-default` next session.

---

## From doctor.sh Resolver Health diagnosis (2026-05-15)

- **`resolver-recovery-shell-owned` (spec candidate, S-M)** — move the resolver-recovery prompt out of `commands/_prompts/_resolver-recovery.md` and into `scripts/resolve-personas.sh` itself, so the shell prints the 3 legal options (`reconfigure / seed / abort`) directly on failure. Skill prompts in `commands/{spec-review,blueprint,check}.md` Phase 0b stop saying "apply the recovery fragment" and instead "display the resolver's stderr verbatim, then read one line from stdin." **Why:** evidence on 2026-05-15 — adopter (Tom) hit a recovery banner reading `"1) Full roster, sonnet tier — all 6 reviewers at claude-sonnet-4-6 (recommended) 2) Full roster, opus tier — all 6 reviewers at claude-opus-4-6 ..."`. After `git pull` + `doctor.sh --no-issue` his Resolver Health was fully green (script present, helper present, config valid, agent_budget=3, persona counts 7/7/6, all 3 gates dispatch 3 personas). So the resolver was healthy. Yet the model on his box authored: (a) a forbidden recovery option — "Full roster, sonnet tier" is one of the explicitly-banned phrases in the canonical fragment's STOP block, (b) the stale pre-2026-05-14 roster count of 6, (c) a recovery path that would have dispatched 6 personas despite `agent_budget=3`. Three improvisations stacked, with no actual resolver failure to trigger them. This is the `host-sessions-improvise-around-negative-recovery-paths` pattern firing in production. The structural fix: remove model authorship from the recovery surface entirely — if the prompt lives in shell stderr, the model can only echo it. **Size:** S-M. Touches: `scripts/resolve-personas.sh` (add stderr recovery prompt emission on exit codes 2/3/4/5/6 — see existing exit-code mapping), `scripts/_resolve_personas.py` (parallel recovery-prompt emission so direct-Python callers also see it), `commands/{spec-review,blueprint,check}.md` Phase 0b (replace "apply commands/_prompts/_resolver-recovery.md" with "surface stderr verbatim + read one stdin line"), `commands/_prompts/_resolver-recovery.md` (keep as historical reference + decision-tree doc, but remove from runtime path). **Open questions for `/spec`:** (1) does the shell prompt also need to handle the `(1) reconfigure now` branch (re-run install.sh as subprocess) or punt that to a "tell the user this command and abort" model? (2) seed-list emission — does the shell print the per-gate seed list directly, or does the skill prompt still own seed dispatch? (3) is the canonical fragment archived to `docs/historical/` or kept in place with a "RUNTIME PATH MOVED" banner? **Entry point:** `/spec resolver-recovery-shell-owned` next session. Memory `host-sessions-improvise-around-negative-recovery-paths` is the load-bearing prior.

---

## Inbound PRs to review (2026-05-14)

- **PR #10 (DRAFT) — `feat(plot): add Plot Document layer`** by tbilsborrow. +2965/-9. Narrative knowledge layer (`plot/PLOT.md` + `plot/chapters/*.md`) with inline code links and staleness tracking via `[!STALE]`/`[!DRAFT]` annotations. Adds `/plot` command, `commands/wrap.md` Phase 2d (staleness check, two-tier — extract links from chapters, intersect with session diff, LLM only on overlap), `commands/spec.md` Phase 0.2c (Plot Document as prior-knowledge source). New: `scripts/_plot_annotations.py` (700 LoC, 6 ops, atomic writes, D6 dual-annotation ordering), `tests/test-plot-annotations.sh` (11 cases / 49 assertions). Pitched as the fifth knowledge store alongside CLAUDE.md / auto-memory / graphify / Obsidian wiki — the narrative layer between architecture and source. **Why review:** novel /spec context-feed mechanism + adds a new always-on /wrap phase + significant surface area (2965 LoC). **Concerns to check:** (1) /wrap Phase 2d cost when chapters get large; (2) interaction with existing graphify digest layer (overlap?); (3) does it use the rename-era `design.md` artifact or still reference `plan.md` (the spec dir name in the PR is `plot-document/`, files include `plan.md` and `plot-layer-design.md` — pre-rename); (4) test orchestrator wiring (memory: parallel-agents shared-file race). **Size:** L review pass; promote to /spec if we want to fold + extend. **Entry point:** `gh pr checkout 10` + `/code-review` plugin or 9-persona code-review pass.

---

## From v0.12.0 follow-up (2026-05-13)

- **`uninstall.sh` reverter (spec candidate, M)** — `install.sh` modifies adopter defaults (CLAUDE.md baseline, `~/.claude/{commands,agents,personas,templates,settings,hooks,scripts,skills}` symlinks, `~/.zshrc` sentinel blocks for theme + obsidian-wiki, `~/.config/{cmux,ghostty}/` symlinks, `~/.obsidian-wiki/config`, `~/.local/venvs/graphify/` + `~/.local/bin/graphify` symlink, graphify skill via `graphify claude install`). Today the only reversal path is "run install on a different machine and diff" plus the timestamped `.bak.<ts>` files `link_file` leaves behind. Ship a real `uninstall.sh` that walks all install side-effects in reverse, with `--dry-run`, backup-restore prompt (keep current / restore newest `.bak` / list backups), and a banner at the top of `install.sh` telling adopters the uninstaller exists. **Why:** the existing install banner promises reversibility we don't actually have; if anything breaks on an adopter machine they have no escape hatch. **Size:** M (Knowledge Layer reversal + sentinel-block stripping in `~/.zshrc` + symlink wave teardown + restore-from-`.bak` flow + tests mirroring the 17-case knowledge-layer harness). **Entry point:** `/spec uninstall-sh` next session; the install-graphify-wiki-coverage spec is the closest structural precedent (5-piece detect → classify → render → dispatch shape inverts cleanly to detect-installed → classify-removable → render → reverse-dispatch).
- **`install-obsidian-wiki-auto-clone` (spec candidate, S-M)** — close the `manual:N/6` wiki-skills gap from v0.12.0. Today `detect_obsidian_wiki_skills` reports `manual:0/6` on fresh adopters because the 6 skills (wiki-update, wiki-query, wiki-ingest, wiki-export, wiki-lint, wiki-capture) live in an upstream **tool repo** (`github.com/Ar9av/obsidian-wiki`) whose `setup.sh` symlinks them to `~/.claude/skills/`. Add a `do_obsidian_wiki_clone` helper inside `do_knowledge_layer` that, when `manual:*`, prompts to clone `Ar9av/obsidian-wiki` to `~/Projects/obsidian-wiki` (or `git pull` if already present at `OBSIDIAN_WIKI_REPO`) and runs its `setup.sh`. **Critical privacy guard:** this clones the *tool* repo only (skills + setup.sh, no personal content). The *vault* (the user's actual notes, at `OBSIDIAN_VAULT_PATH`) is per-user and must be created by each adopter inside their own Obsidian.app. install.sh must NEVER pull anyone's personal wiki content; the existing manual vault-creation step (now documented in `install.sh` end-block + `docs/index.html`) is the only correct path. **Why:** the spec deliberately scoped v0.12.0 as detect-only; v0.12.0 is shipped, so the deferred wiki-install path is the right next slice. Reduces the "one manual step" footprint to truly just the vault-creation GUI action. **Size:** S-M (one new install action + adopter prompt-N default + same chmod 600 / sentinel-block discipline as `install_obsidian_env` + 2-3 new test cases mirroring AC-shape from coverage spec). **Open questions for `/spec`:** (1) does install.sh shell out to `bash obsidian-wiki/setup.sh` (trust the upstream installer), or re-implement the 6 skill-symlinks here (avoids second-installer audit but duplicates logic)? (2) is the upstream repo URL pinned in `install.sh` or read from a config knob? (3) does the cloned-vs-pulled detection check `git remote get-url origin` against the expected upstream to catch the case where `~/Projects/obsidian-wiki` is a fork or someone else's content? **Entry point:** `/spec install-obsidian-wiki-auto-clone` next session; previous spec is the structural template.

---

## Audited clean — no action needed

- **github.io page `/design` vs `/blueprint` audit (2026-05-13)** — checked docs/index.html, README.md, QUICKSTART.md for stale `/design` slash-command refs after the /design → /blueprint rename (PR #15). **Result: clean.** docs/index.html has 9 `/blueprint` references (correct user-facing) and 1 `docs/specs/<feature>/design.md` reference at line 1222 — that's the intentional artifact filename per CLAUDE.md's internal-gate-identifier guard, not a stale slash-command ref. README + QUICKSTART have zero `/design` references. No work to do; flagged here so a future audit doesn't re-investigate.

---

## ULTRAPROMPT extraction (parked at root, 2026-05-12)

- **ULTRAPROMPT extraction plan** — port useful operating-system ideas from the ULTRAPROMPT prompt into MonsterFlow without replacing MonsterFlow's core identity. Original 10KB plan was at `extractionplan.md` (root) generated by Codex 2026-05-06. **Why:** durable proof, resumability, feature-local state where MonsterFlow already has strong concepts but weaker mechanical enforcement. **Size:** L (multi-slice; needs scope-down before promotion). **Entry point:** restore the original draft from commit `2933100` (`git show 2933100:extractionplan.md`) when ready to scope; promote sections as separate specs rather than one mega-spec. Non-goals captured in original draft: do NOT copy ULTRAPROMPT's client/payment/legal model, do NOT import its bundled MCP servers, do NOT convert MonsterFlow into a project-manager runtime with orchestrator-only control plane.

---

## From dynamic-roster-per-gate /check (2026-05-12)

- **Revisit `--tier-pin` accumulate vs last-wins semantics** — D14 currently ships accumulate-with-promote-and-drop-lowest. Spec.md:89 shows only single-flag usage; nothing in AC requires accumulation. Scope-discipline reviewer flagged this as invented semantics. **Why:** the promote-and-drop algorithm interacts with SEC-01 security-floor preservation and is non-trivially testable. **Size:** S (3-5 line change in `_tier_assign.py`). **Trigger:** revisit if a user actually files an issue using `--tier-pin` multiple times in one invocation, OR after 90 days of usage telemetry shows zero multi-flag invocations (then simplify). Followup row: `ck-2233445566` in `docs/specs/dynamic-roster-per-gate/followups.jsonl`.

---

## Parked specs (from 2026-05-09 cleanup pass)

Spec dirs deleted under `docs/specs/` because they were idea-only drafts (no implementation, never went through pipeline). Reasoning preserved here so the design thinking isn't lost. Re-promote via `/spec` when ready.

- **`autorun-runtime-validation-gate` (parked, 2026-05-09; spec was internally inconsistent)** — post-build runtime smoke check before merge; opt-in per-project via `runtime:` frontmatter; status enum `pass | fail | skipped | error | skipped_external_author`. Carved Revision 2 closed sev:security blockers F1-F5 via skip-on-non-CODEOWNERS-author trust model. **Park reason:** failed at autorun build attempt 4-of-3 (49 min wallclock); spec has internal AC inconsistency (5min vs 900s timeouts). Was 478 lines / 40 ACs — over-scoped for one autorun. **When re-promoted:** carve into smaller slices (e.g., web-only smoke, then iOS, then external-PR trust extension). Each carve-off needs full re-scope, not lift from the parked spec — internal inconsistency means lift would propagate the bug.
- **`pipeline-granular-commits` (parked, 2026-05-09; idea-only draft)** — commit-per-persona blast-radius reduction at /spec-review + /plan + /check. Each persona's raw output committed individually so a bad reviewer's contribution can be reverted without unwinding the whole gate. **Park reason:** 130-line draft, no plan/check/review artifacts; competes with simpler "just don't commit raw outputs by default" path. **When re-promoted:** decide first whether raw outputs need to be in git at all (vs `queue/` ephemeral), then design granularity.
- **`pipeline-iterative-resolution-loops` (parked, 2026-05-09; idea-only draft)** — generalize the SECURITY_MAX_FIX_ATTEMPTS=3 counter to all blocking finding-axes; user-selectable count; integrity-class exempt. **Park reason:** 322-line draft with no implementation; partially superseded by 2026-05-09 inline fix to Codex post-PR binary block (which is the "blocking-axes need warn route" pattern this spec was generalizing). **When re-promoted:** scope down to just the axes that still hard-block after the post-PR Codex warn-route lands.
- **`pipeline-per-gate-confidence` (parked, 2026-05-09; idea-only draft)** — emit per-gate 6-dimension confidence scores at /spec-review, /plan, /check (analogous to /spec's confidence tracking). **Park reason:** 168-line draft, no implementation; depends on persona-metrics extension to gate stages (currently spec-only). **When re-promoted:** sequence after dynamic-roster-per-gate ships.
- **`spec-upgrade` (parked, 2026-05-09; old draft from 2026-04-12)** — upgrade `/spec` with context-first exploration, approach proposal, self-review pass, recommendation-with-reasoning per-question, auto-run mode. **Park reason:** 128-line draft from before MonsterFlow rebrand; portions of this design landed implicitly via /spec evolution (context summary, approach proposal, auto-run all exist now). **When re-promoted:** audit which parts of the original spec are still missing, scope down to those only.
- **`autonomous-overnight-pipeline` (superseded, 2026-05-09)** — original framing for the autorun overnight pipeline. Superseded by `autorun-overnight-policy` (shipped v6, PR #6) which implemented the operational shape. **Park reason:** historical precursor, not a forward-looking idea. Reference if archaeology needed.

## Deferred from 2026-05-09 cleanup pass

- **`docs/specs/_shipped/` archive (S, deferred)** — move shipped spec dirs (account-type-agent-scaling, autorun-merge-policy, autorun-overnight-policy, docs-rewrite, install-rewrite, persona-metrics, pipeline-gate-permissiveness, pipeline-wiki-integration) under `docs/specs/_shipped/<slug>/` so the top-level `docs/specs/` listing means "active/current" instead of "museum." **Why deferred:** 74 external references across CHANGELOG.md, CLAUDE.md, tests/, dashboard, install.sh, docs/index.html. A clean `sed` sweep + grep-test verification is ~30-45 min, not the 10-15 min the cleanup-pass review estimated. Defer to a focused session. **Sequencing:** unblocked. **Size:** S-M (mostly mechanical rename + reference-update sweep + lockstep grep test asserting no `docs/specs/<shipped-slug>/` paths remain outside `_shipped/`).
- **`queue/` vs `docs/specs/` source-of-truth consolidation** — already in backlog further down (see `pipeline-autorun-source-of-truth-consolidation`). Today's 2026-05-09 evidence: the parked `autorun-runtime-validation-gate` had simultaneous `queue/autorun-runtime-validation-gate.spec.md` AND `docs/specs/autorun-runtime-validation-gate/spec.md` AND `queue/autorun-runtime-validation-gate/{plan.md,check.md,spec.md}` — three copies of overlapping content. This is the operational shape of the user's "documentation state has to follow" complaint. Hold today (M-L scope) but flag with concrete evidence.

---

## Pipeline knob harmonization (from 2026-05-09 cleanup pass)

- **`pipeline-gate-max-recycles-harmonize-default-3` (NEW spec candidate, S)** — bump `gate_max_recycles` default from `2` to `3` to match the rest of the pipeline's "3 attempts before halt" pattern. Today three counters disagree:
  - `build_max_retries: 3` (autorun config — build-wave retries)
  - `SECURITY_MAX_FIX_ATTEMPTS: 3` (per `pipeline-security-n-attempts` shipped inline)
  - `gate_max_recycles: 2` (per `pipeline-gate-permissiveness` v0.9.0)
  - **Why:** spec authors writing new specs see `gate_max_recycles: 2` and don't realize the rest of the system uses 3. Footgun for /check-NO_GO refinement loops where 1 cycle of refinement isn't always enough (see runtime-validation-gate Revision 2 — needed 1 cycle and only had 2 budget total).
  - **Scope:** edit `commands/_gate-mode.md` `gate_max_recycles_clamp` default; update `_gate_helpers.sh`'s default; update all spec frontmatter that explicitly sets `gate_max_recycles: 2` to either remove the line (inherit new default) OR explicitly pin to 2 if author intended that.
  - **Out of scope:** changing `build_max_retries` or `SECURITY_MAX_FIX_ATTEMPTS` (already 3); adding a new pipeline-global default knob (per-spec override stays).
  - **Sequencing:** unblocked. Cheap. Could ship in same PR as a small documentation pass on the "3-attempt pattern" as a uniform pipeline contract.
  - **Size:** S (~30-50 LoC + grep-test in `tests/run-tests.sh` asserting all references show 3 not 2; ~5 spec frontmatter touch-ups).
  - **Codex review optional** — small surface; standard /check sufficient.

---

## Cross-model adversarial review (from 2026-05-08 docs-rewrite session)

- **`openrouter-qwen-roster-integration` via claude-code-router (NEW spec candidate, 2026-05-08; integration architecture confirmed)** — wire Qwen 3.6 27B (`qwen/qwen3.6-27b` on OpenRouter — 262K context / 80K output, $0.32/$3.20 per M tokens, Apache 2.0, agentic-coding marketed) into MonsterFlow's persona dispatch as the "remainder slot" model in the per-axis tier-mix rule (≥1 Opus + ≥1 Sonnet + 50/50 remainder, per `dynamic-roster-per-gate`).
  - **Integration path: claude-code-router (CCR), not adversarial-sidecar** — `@musistudio/claude-code-router` is a local HTTP proxy daemon (port 3456) that translates Anthropic API calls to OpenAI-compatible backends including OpenRouter. Setup: `npm i -g @musistudio/claude-code-router` + `~/.ccr/config.json` mapping default/reasoning/background tiers + `ANTHROPIC_BASE_URL=http://127.0.0.1:3456` in `~/.claude/settings.json`. Reuses existing `claude` CLI invocations rather than building a parallel curl pipeline; replaces the earlier-considered `_openrouter_probe.sh` sidecar approach.
  - **Roster scope (recommended):** Qwen fills the "remainder" slot at `/spec-review` and `/check` as an independent perspective. **NOT a primary reviewer. NOT used for /check synthesis.** Pilot on one spec; gate promotion on observed tool-use behavior.
  - **Trade-offs / footguns (validated, not speculative):**
    - **Prompt caching disabled end-to-end** — CCR's translation layer breaks Anthropic's prompt cache. Real cost + latency hit; persona-metrics dashboard should track per-model cost-per-finding to surface the gap.
    - **Tool-use parity vs Claude is UNDOCUMENTED** — Qwen's "agentic coding" claims unverified against Claude's tool schema. Fragile for bash/file ops. Test before trusting at any gate where tool calls matter (especially /check where reviewer agents may inspect the codebase).
    - **Thinking-mode mismatch** — Opus extended-thinking budget doesn't map to Qwen. Personas that depend on thinking degrade silently. Either restrict Qwen-eligible personas to non-thinking ones, or accept the degradation and measure.
    - **Caching loss compounds at /check synthesis** — even if Qwen sits at /spec-review remainder slot, any pipeline call routed through CCR loses caching. Constitution-level: keep `ANTHROPIC_BASE_URL` env unset for default Claude calls; set ONLY for Qwen-tagged subagent dispatches via per-call env override.
  - **Unaffected surfaces** (CCR is HTTP-only): MCP, sub-agents, slash commands, hooks all keep working.
  - **Resolver integration:** `dynamic-roster-per-gate`'s tier resolver (`scripts/resolve-personas.sh` + tier_policy frontmatter) gains a `qwen` tier value mapped to Qwen3.6-27b. Per-persona dispatch decides whether to route through CCR (set `ANTHROPIC_BASE_URL=http://127.0.0.1:3456` for that single subagent invocation) or talk to Anthropic directly (default for Opus/Sonnet personas).
  - **Constraint preserved: must not increase agent max count.** Qwen replaces a Sonnet slot in the remainder, not adds to it. With per-axis tier-mix, a /spec-review with 6 personas might be: 1 Opus + 1 Sonnet + 2 Sonnet + 1 Qwen + 1 Codex = 6 total + Codex additive (existing pattern).
  - **Wiring surfaces:** `scripts/resolve-personas.sh` (add `qwen` to tier enum); `scripts/autorun/_dispatch_persona.sh` or equivalent (per-persona env override for `ANTHROPIC_BASE_URL`); `commands/_prompts/findings-emit.md` (record `model_dispatched` per persona for cost-attribution); `dashboard/data/persona-rankings.jsonl` (extend with model column). CCR install/config gets a small `scripts/install-ccr.sh` helper.
  - **Schema additions:**
    - `participation.jsonl`: add `model_dispatched: opus | sonnet | qwen | codex` (additive).
    - `findings.jsonl`: same (additive).
    - `~/.config/monsterflow/config.json`: optional `ccr_endpoint: http://127.0.0.1:3456` override (default to standard CCR port).
  - **Out of scope for v1:** Qwen as primary reviewer; Qwen at /check synthesis; tool-use shimming if Qwen breaks Claude's tool schema (separate spec if needed); MCP-based alternative integration (CCR path is preferred); auto-installation of CCR (v1 documents the npm install; v2 could automate).
  - **Sequencing:** depends on `dynamic-roster-per-gate` shipping (the tier_policy + resolver are the integration seams). Can be drafted in parallel; cannot ship before that lands.
  - **Size:** M (CCR config + resolver tier extension + per-persona env override + persona-metrics schema additive + 6-8 test fixtures including Qwen-routed dispatch + tool-use parity smoke test). ~300-500 LoC.
  - **Codex review recommended** — touches dispatch path + new external dependency (CCR); class:integrity risk if env override leaks across personas.
  - **References:**
    - `~/.claude/Openrouter.apikey` (chmod 600, 74 bytes; OPENROUTER_API_KEY env loaded from this file at CCR start)
    - `@musistudio/claude-code-router` on npm; issues active May 5-8, 2026
    - Memory: `project_multi_model_roster.md` (original exploration framing)
  - **Smoke test results (2026-05-08, ~$0.002 total cost):** GO on integration architecture.
    - **Setup:** CCR v2.0.0 installed via `npm i -g @musistudio/claude-code-router`. Config schema is v2 (`Providers[]` + `Router{}` at `~/.claude-code-router/config.json`, NOT the simpler `~/.ccr/config.json` shape from the user's recipe). Env-var interpolation via `$OPENROUTER_API_KEY` works. `chmod 600` on config. CCR daemon listened on 127.0.0.1:3456.
    - **Test 1 (plain chat):** PASS. Anthropic-shape POST to `/v1/messages` routed to Qwen3.6-27b returned correct `type: message` + `content: [{type: text, text: ...}]` shape. Model identifies as "Qwen, large language model developed by Alibaba Group's Tongyi Lab." 23 in / 334 out tokens. Actual model ID returned: `qwen/qwen3.6-27b-20260422` (date-suffixed; `qwen/qwen3.6-27b` is an alias).
    - **Test 2 (tool use, Anthropic schema):** PASS. Qwen received Anthropic `tools[]` array with `Read` tool definition + `input_schema`, emitted correct `tool_use` block with `id`, `name: "Read"`, `input: {file_path: ...}`, and `stop_reason: tool_use`. 316 in / 145 out.
    - **Test 3 (tool use, multi-turn round trip):** PASS. Submitted `tool_result` block with the Read tool output; Qwen synthesized final response with markdown formatting and correct `stop_reason: end_turn`. 367 in / 89 out.
    - **Caching: confirmed DISABLED** (`cache_read_input_tokens: 0` across all 3 calls, as the user's research predicted). Real cost + latency hit on multi-turn cache reuse paths.
    - **Verbose-output concern flagged:** Test 1 burned 334 output tokens for "Hello, I'm Qwen..." — Qwen likely emits internal reasoning that gets compacted. Raw output-token-rate cost advantage (4.7x cheaper than Sonnet) may erode on prompts where Qwen runs long internal chains. **Measure on a real spec-review prompt before promoting** — could blow up output costs vs Sonnet despite the per-token rate.
    - **Cost vs Sonnet (raw rates):** input $0.32/M vs $3/M (9.4× cheaper); output $3.20/M vs $15/M (4.7× cheaper). On the smoke-test workload (706 in / 568 out): Qwen $0.002 vs Sonnet ~$0.011. Real-world ratio depends on output verbosity.
    - **Tool-use parity: GO for Read schema.** Other Claude tools (Edit, Write, Grep, Glob, Bash) NOT yet tested — spec must include parity smoke tests for each tool the persona dispatch path uses before promoting Qwen to /check-eligible status.
    - **Status:** parked per (c) decision until `dynamic-roster-per-gate` ships. Smoke test confirmed the architecture works and the tool-use floor is high enough for /spec-review remainder slot.

---

## ULTRAPROMPT extraction plan (from 2026-05-06 Codex session; recovered 2026-05-07)

- **`ultraprompt-extraction` (NEW spec candidate — meta-plan; spawns 6 child specs)** — full extraction plan lives at `extractionplan.md` (project root, 294 lines). Six durable-proof / resumability / feature-local-state additions sequenced in rollout order. Each is independently shippable; #1-#3 are observational/mechanical (low-risk), #4-#6 change workflow behavior more visibly.
  1. **Feature Artifact Index** (S-M) — `scripts/build-feature-artifact-index.py` writes `docs/specs/<feature>/artifact-index.yaml` after every stage transition. Aggregates spec/review/plan/check artifacts + verdict summary + followup counts + raw paths + survival metrics + latest commit. Read-only over existing files. Tests: complete / partial / malformed / missing-followups fixtures.
  2. **Build Evidence Checker** (M) — `scripts/check-build-evidence.py` mechanical proof checker before `/build` declares done. Catches missing screenshots/test logs, unresolved followups, NO_GO verdicts, security findings without disposition, claimed-but-absent evidence paths. JSON + Markdown reports. New schema `build-evidence.schema.json`.
  3. **Check Gate Packet** (M) — `scripts/build-check-gate-packet.py` writes `check/gate-packet.yaml` before `/check` synthesis. Hashes spec/review/plan + selected personas from `selection.json` + raw output paths + gate mode/source/iteration + Codex path + sidecar schema version. Makes the trust boundary explicit instead of inferred.
  4. **Manual Pipeline Checkpoints** (S) — `scripts/feature-checkpoint.py` appends to `docs/specs/<feature>/run.md` per stage with timestamp + status + artifact paths + verdict. Cheap manual resumption parity with autorun's `run-state.json`.
  5. **Optional Feature Tickets** (M) — opt-in `docs/specs/<feature>/tickets/T-001-*.md` for `/build` wave tasks. Frontmatter (id/feature/status/wave/blocked_by/owner/file_paths/evidence/handoff). Generated from plan.md task breakdown. Closeout requires evidence-checker pass. Tickets included in artifact-index.
  6. **Deterministic Research Trigger** (S) — `scripts/research-trigger.py` preflight at `/spec` + `/plan` flagging when terms (current/latest/API/vendor/model/version/regulation/pricing/etc.) require live research. No network access itself; just produces `research-trigger.json`. `/plan` warns when triggered but no research evidence recorded.
  - **Why:** durable proof + resumability + feature-local state are the gaps Codex surfaced after scanning the repo. MonsterFlow already has strong concepts (persona gates, autorun state, gate-mode, dashboard) but weaker mechanical enforcement at the trust boundaries. Each priority closes a specific honesty gap (#2: false-completion; #3: trust-packet inferred-vs-explicit; #6: stale-memory dependency drift).
  - **Non-goals (explicit):** do NOT copy ULTRAPROMPT's client/payment workspace model, MCP server bundling, project-manager orchestrator-only control plane, or vault-repo separation. Do NOT weaken existing persona-metrics / gate-mode / autorun / dashboard contracts.
  - **Sequencing:** rollout order is the spec sequence (#1 → #6). #1-#3 unblocked. #5 depends on #1+#2 stable (tickets included in artifact-index, closeout uses evidence-checker). #4 + #6 unblocked but lower priority per Codex.
  - **Compatibility rules:** legacy feature directories must continue to work; new scripts warn (don't fail) when optional artifacts missing; hard failures reserved for integrity issues / invalid slugs / claimed-but-absent proof.
  - **Size:** L total (six children S-M each); recommend opening as 6 separate `/spec` runs rather than one mega-spec. Start with #1 (lowest risk, observational).
  - **Source:** `extractionplan.md` at project root (Codex-authored 2026-05-06; full text). Read in full before opening child specs.
  - **Codex review recommended on #2 (Build Evidence Checker)** — touches /build completion semantics; class:integrity risk if checker misses a false-completion path. Standard /check sufficient for the other five.

---

## Pipeline + install discipline (from 2026-05-05 autorun-overnight-policy session)

- **`pipeline-codex-coverage-extension` (NEW spec candidate, 2026-05-07)** — extend Codex adversarial review from its current `/spec-review` + `/check` surface to `/plan` and `/build` wave-final. Codex is silently skipped today at `/plan` (per `findings.schema.json`'s `personas[]` description: *"Codex doesn't run at /plan in v1"*) and absent at `/build` entirely.
  - **Why:** Codex catches plan-vs-codebase-reality drift — a different job than Claude reviewers do (Claude verifies plan-against-itself; Codex verifies plan-against-Python/CLI/codebase, per memory `feedback_codex_catches_plan_vs_reality_drift.md`). Track record: H1/H2 saves on autorun-overnight-policy v6 (nonce trust-boundary), autorun-verdict-deterministic (4× H1 including unimplementable-execution-model gap), dynamic-roster-per-gate run #6 (security findings). 3 confirmed saves at the gates where it's wired; `/plan` likely has the same hit rate (synthesizer-against-pseudocode is exactly the drift class Codex catches). `/build` wave-final adds an end-of-implementation reality check — does the diff match the plan's ACs?
  - **Cost reality:** ChatGPT subscription + ~30s wall-clock per invocation. Materially cheaper than an Opus dispatch. The "Codex is always-on if authenticated" default in `dynamic-roster-per-gate` (additive policy) makes coverage extension a net win, not a cost burden.
  - **Spec needs:**
    - `/plan` Phase 2b (new) — Codex adversarial review of synthesized `plan.md` against `spec.md` + relevant codebase paths. Output to `docs/specs/<feature>/plan/raw/codex-adversary.md`. Adversarial prompt: challenge plan's pseudocode field names against actual schemas, plan's CLI flags against actual `--help` output, plan's import paths against actual files.
    - `/build` wave-final — Codex review of accumulated wave commits against the plan's ACs. Output to `docs/specs/<feature>/build/raw/codex-adversary.md`. Adversarial prompt: which ACs are unaddressed by the diff? Which commits violate the plan's stated approach?
    - `commands/_codex_probe.sh` — extend invocation paths (currently 2 callers; will be 4).
    - `findings.schema.json` description update — drop the *"Codex doesn't run at /plan in v1"* note.
    - Test fixtures: 3 per new gate (auth-present-runs, auth-missing-skips, prompt-version-bump).
  - **Sequencing:** unblocked. Independent of `dynamic-roster-per-gate` shipping; Codex is `additive` by default in both worlds.
  - **Size:** M (mostly plumbing extension to 2 new gates + adversarial-prompt design + ~6 test fixtures).
  - **Codex review optional** — meta-irony aside, this spec mostly extends an existing pattern; standard /check sufficient.

## Carved from `dynamic-roster-per-gate` MVP scope (2026-05-06; per scope-discipline run #6 recommendation)

- **`pipeline-autorun-final-status-render` (NEW spec candidate)** — when `autorun-batch.sh` exits, render a single-screen final summary: per-slug verdict (shipped/failed/halted), PR URLs, failure stage + reason, total wallclock, total cost (token + dollar if available), and the `/flow` workflow reference card so the user re-loads context for the next session in one screen instead of `autorun status` + `tail run.log` + `cat queue/index.md` + per-slug `check.md` reads. Should also handle: graceful "no slugs ran" / STOP-file-halt / partial-completion cases.
  - **Why:** today the closing state of an autorun batch is scattered across 4-5 files and 2-3 tmux windows. After a long overnight run, reconstructing what shipped vs failed vs is mid-rollback is friction at the exact moment the user wants clarity (morning standup, planning the next slice, etc.). A single-screen final render closes the observability loop.
  - **Entry points:** `scripts/autorun/autorun-batch.sh` exit path (terminal `[autorun-batch] done` line); new `scripts/_render_final_status.py` (or sh) that aggregates `queue/run.log` + per-slug `check-verdict.json` + `pr-url.txt` + `failure.md` + flow card; possible integration with macOS notification body for the same content.
  - **Sequencing:** unblocked. Independent of heartbeat work (different concern: that one's failure-detection during a run; this is end-of-run synthesis).
  - **Size:** S (mostly aggregation + render; flow card is a static include from `commands/flow.md`).
  - **Codex review optional** — small surface, mostly read-only file aggregation.

- **`pipeline-autorun-heartbeat-and-restart-loop-detection` (NEW spec candidate)** — current `autorun` retry semantics can burn 3 × `timeout_stage` (default 90min) on repeated timeouts of the same hang pattern, OR on repeated verifier INCOMPLETE verdicts citing the same unsatisfiable evidence ACs. `claude -p` is intrinsically I/O-bound (low CPU is normal even while productive), so CPU% isn't a reliable hang signal. Needs (a) heartbeat surface emitting progress events at known cadence, (b) restart-loop detection that bails after 2 consecutive timeouts vs trying 3rd, (c) per-wave timeout split (e.g., 600s × 3 waves) so single wedge fails fast instead of consuming the whole budget, (d) optional Anthropic token-usage poll if the API exposes one, (e) **verifier-evidence-pedantry detection** — if `verify-gaps.md` keeps citing the same set of `[FAIL]` ACs across 2+ retries (FAIL-set-hash unchanged), bail early instead of burning all attempts on the same wedge. Detection rule: hash the `[FAIL]` lines per attempt; if attempt N's hash equals attempt N-1's hash, retries are not converging — emit `[policy] block: stage=verify axis=verify_infra reason="convergence-stall: identical FAIL set across N retries"` and exit before attempt N+1, preserving in-flight build commits for human-in-loop review.
  - **Why (heartbeat):** in slice 1 of dynamic-roster (2026-05-08), saw `claude -p` PID at 11min elapsed + 1.2% CPU + 36-byte build-log.md → unclear if making progress or stuck. Same shape risks 30-90min waste per stuck slug.
  - **Why (verifier-pedantry detection):** slice 1 of dynamic-roster (2026-05-08) — verifier flagged A7/A9/A10 as INCOMPLETE on diff-inspection grounds (verifier wants test-run output IN the diff to prove "all tests still pass"; that's not how tests work — passing is established by RUNNING tests, not by emitting their stdout into commits). /build attempt 2 retried with FAIL items injected; attempts 2 and 3 would have hit the same wall; then `git reset --hard` would have rolled back 5 perfectly-good commits. Manual STOP + the integrity-block-on-branch-mismatch guard (in `scripts/autorun/build.sh`) saved the run — but only because I had already switched off the autorun branch to verify tests. The structural fix is per-retry FAIL-set-hash comparison: identical wedge → bail.
  - **Entry points:** `scripts/autorun/build.sh:569` (claude -p invocation site); `scripts/autorun/run.sh` retry loop; new `scripts/_autorun_heartbeat.sh` wrapper; `queue/<slug>/.heartbeat` sentinel; possibly extend `queue/run.log` JSONL with per-N-second progress rows; new `scripts/_verify_convergence.py` (hash `[FAIL]` lines from `verify-gaps.md`, compare attempt N vs N-1).
  - **Sequencing:** unblocked. Independent of any in-flight spec.
  - **Size:** M (heartbeat wrapper + restart-loop detection + per-wave timeout split + verifier-convergence-stall detection + tests).
  - **Codex review optional** — small surface, mostly shell glue + one small Python helper.

- **`pipeline-autorun-source-of-truth-consolidation` (NEW spec candidate — supersedes earlier `pipeline-autorun-run-archive` framing)** — autorun today double-writes the same artifacts to BOTH `queue/<slug>/` (operational copies, gitignored) AND `docs/specs/<slug>/` (canonical paths, committed). Stages including `/spec-review`, `/plan`, `/check` write to both surfaces; readers (downstream stages, manual workflow) sometimes pick the wrong one; "which copy is authoritative" is a recurring debugging tax. Reframe with a single source of truth + explicit promotion step.
  - **Target architecture:**
    - `queue/<slug>/` is the **single source of truth during autorun**. All stage scripts write here. Working scratch only.
    - `docs/specs/<slug>/` holds **only the human-authored `spec.md`** (the input) prior to ship.
    - On **successful slug ship** (PR merged into main), a promotion step COPIES the relevant subset (`spec.md`, `plan.md`, `check.md`, `check-verdict.json`, `spec-review/`, `plan/`, `check/`) from `queue/<slug>/` to `docs/specs/<slug>/` and commits them as the durable record. Run logs (`build-log.md`, `verify-gaps.md`, `check-synthesis.raw`, `failure.md`, `.security-attempts*`, `.verdict-attempts*`) STAY in `queue/<slug>/` (forensic; never get committed to docs/specs/).
    - After promotion, `queue/<slug>/` is wiped (or moved to `queue/<slug>.archive/` for one-run paranoia, then GC'd on next successful ship of any slug).
    - Failed runs: `queue/<slug>/` keeps the failure-state artifacts. Re-queuing rotates prior failure to `queue/<slug>/runs/<prev-run_id>/` (the wrapper at `scripts/autorun-rotate-artifacts.sh` already does this).
    - Net effect: git history of `docs/specs/<slug>/` + main branch IS the multi-level archive. No additional ring-buffer needed at queue level.
  - **Why:** during dynamic-roster-per-gate session (2026-05-06–08) the duplication caused multiple "did I edit the right copy" moments + a near-rollback of 5 good commits when the verifier read out-of-sync. Per-slug rotation alone (without consolidating sources) doesn't fix the root cause; it just preserves more copies of an ambiguous truth. Decision (2026-05-08): keep this consolidation as the spec-worthy work; drop the small "add `queue/archive[1-2]/` dirs" idea as throwaway since git history of `docs/specs/` already provides multi-level archive durability.
  - **Already shipped (inline tooling — useful regardless of which framing wins):** `scripts/autorun-rotate-artifacts.sh` (manual invocation; ~50 LoC). Will be wired into `autorun-batch.sh` per-slug failure path as part of this spec.
  - **Spec needs to add:** stage-script audit (which paths each `scripts/autorun/*.sh` writes today; which need to switch); promotion-step design (where in the pipeline does it fire — after Stage 8 squash-merge?); failed-vs-shipped branching logic; retention design for `queue/<slug>/runs/<run_id>/` (cap depth, optional tar.gz archive); migration path for any in-flight specs that are pre-promoted; tests covering the consolidation.
  - **Sequencing:** unblocked. Independent of in-flight specs (slices 2-5 of dynamic-roster-per-gate can land before or after).
  - **Size:** M-L (touches every stage script's write paths; promotion step is new code; retention/GC is design-heavy; tests must cover both shipped + failed paths).
  - **Codex review recommended at /spec-review and /check** — touches every stage's I/O; class:integrity risk if a stage writes to the old path on a partial deploy.
  - **Sequencing:** unblocked. Wrapper script is in production via this session.
  - **Size:** S–M (mostly autorun-batch.sh integration + retention design + index render).
  - **Codex review optional** — small surface, mostly file ops.



These five items were removed from `dynamic-roster-per-gate` v1 to keep the MVP focused on content-aware persona selection + tier-mixing rule. Each is independently shippable; collectively they restore the "full" feature surface the original spec drafted.

- **`pipeline-iterative-resolution-loops` (NEW spec candidate — supersedes `pipeline-security-n-attempts` below — broader scope per 2026-05-06 user direction)** — generalize the security-axis 3-attempt counter (already shipped inline in check.sh) to ALL blocking finding-axes: AC#5 NO_GO verdict, class:architectural blocks, any future class-axis blocks. **User-selectable count** via `tier_policy.max_fix_attempts` (per-axis if needed) at constitution → spec.md → CLI precedence. **Highlight as feature:** "self-healing pipeline — 3-attempt automatic resolution loops per blocking axis, audit-logged, configurable." Integrity-class blocks (malformed sidecar, fence detection, bound-check failures) are EXEMPT — those indicate synthesizer/parser drift, not work-in-progress, and iterating on them just burns tokens.
  - **Why:** v0.9.0's hardcoded-block invariants (AC#4 security, AC#5 NO_GO) caused 6 wasted autorun cycles in the dynamic-roster-per-gate session before security counter was added inline. AC#5 still hardcoded → run #6 halted on NO_GO despite the security counter working correctly.
  - **Already shipped (inline patch):** `scripts/autorun/check.sh` 3-attempt counter for class:security only (AC#4 path).
  - **Spec needs:** generalized counter at every block site (AC#5 verdict gate, future architectural blocks); `tier_policy.max_fix_attempts` schema in `pipeline-config.md` and spec.md frontmatter; CLI flag (`--max-fix-attempts N`); per-axis counter files (e.g., `.verdict-attempts`, `.architectural-attempts`); test fixtures for each axis; CHANGELOG; version bump (v0.10.0 likely).
  - **Sequencing:** unblocked. Security-counter inline patch demonstrates the pattern.
  - **Size:** M (mostly mechanical extension of the existing pattern; main complexity is per-axis counter file design + frontmatter override).
  - **Codex review optional** — small code surface; standard /check sufficient.

- **`monsterflow-pipeline-config-rename` (NEW spec candidate)** — rename `docs/specs/constitution.md` → `docs/specs/pipeline-config.md` everywhere (commands/, scripts/autorun/, docs/, tests/, install.sh banner). Symlink at old path for one release. Tightened description: *"project-wide pipeline configuration — agent roster, auto-run thresholds, tier policy, gate defaults"*.
  - **Why:** "constitution" suggests a code-of-conduct; the file is actually project-wide pipeline config (agent roster, auto_threshold/floor, tier policy). Rename improves discoverability for adopters.
  - **Sequencing:** unblocked, but coordinate with `dynamic-roster-per-gate` (which references the renamed file). Land EITHER before OR after dynamic-roster — both work; dynamic-roster spec uses old name pending this rename.
  - **Entry points:** find/replace via `grep -lr "constitution.md"` + symlink + install.sh banner update + CHANGELOG.
  - **Size:** S (mostly find/replace + symlink + tests).

- **`pipeline-security-escape-hatches` (NEW spec candidate)** — add two interactive-only audit-logged escape hatches deferred from `dynamic-roster-per-gate` MVP:
  1. `--allow-security-downgrade <reason>` — permits spec.md `tier_pins` to downgrade `fit_tags:[security]` personas below constitution floor with mandatory reason. Refused in `$CI`/`$AUTORUN_STAGE` truthy env (mirrors v0.9.0 `--force-permissive`). Emits `class:security state:open tags:[security-downgrade-acknowledged]` row to followups.jsonl + audit line at `.security-downgrade-log`.
  2. `--acknowledge-baseline-mismatch <reason>` — permits `/spec` Phase 3 to remove a baseline-detected `tags:` entry (false-positive case). Same env-refusal, same audit shape (`tags:[baseline-mismatch-acknowledged]` + `.baseline-mismatch-log`).
  - **Why:** in v1 dynamic-roster, baseline floor + spec_overridable_keys are HARD walls. False-positive cases (e.g., spec uses `auth` only in passing) force users to edit spec content, which may distort intent. Hatches give an audit-logged opt-out for known-safe cases.
  - **Sequencing:** depends on `dynamic-roster-per-gate` shipping (these extend its mechanisms).
  - **Size:** M (both hatches share the followups-row + audit-log + env-refusal pattern; ~150-300 LoC + tests).

- **`pipeline-resolver-debugging` (NEW spec candidate)** — `resolve-personas.sh --explain` flag — read-only stdout pretty-printer over `selection.json` (or dry-mode resolver output if no selection.json exists). No-side-effects by construction (no write capability in code path). Sections: eligibility / scores / tier-assignment / dropped-with-reason / override-chain. tmpdir-mutation-zero test fixture pins HOME/XDG_*/TMPDIR before find -newer assertion.
  - **Why:** debuggability of resolver decisions. Today users have `selection.json` but no human-readable formatter. Helps with "why did persona X get dropped?" investigations.
  - **Sequencing:** depends on `dynamic-roster-per-gate` (extends its `selection.json` schema).
  - **Size:** S (read-only formatter; ~50-100 LoC + 1 test fixture).

- **`pipeline-rate-limit-resilience` (NEW spec candidate)** — design + implement HTTP 429 fallback for orchestrator + workers when `tier_policy.orchestrator=opus`. Today: no documented degradation path. Ask: when Opus rate-limits, do we (a) fall back to Sonnet for orchestrator, (b) backoff + retry, (c) queue + halt, (d) per-axis configurable.
  - **Why:** surfaced by risk persona in `dynamic-roster-per-gate` /check run #6. Without a rate-limit fallback, Pro-tier users will hit 429 mid-gate and the autorun aborts with no recovery.
  - **Sequencing:** depends on `dynamic-roster-per-gate` (rate-limit on the new tier-mixing path is the trigger).
  - **Size:** M (design-heavy; need to choose strategy, instrument retries, decide whether to silently degrade tier or surface to user).

- **`pipeline-security-n-attempts` (NEW spec candidate — formal documentation of patch already in production)** — formal spec for the policy framework change applied inline during 2026-05-06 dynamic-roster-per-gate session: class:security findings get N=3 logged resolution attempts before hardcoded block, instead of v0.9.0 AC#4's first-cycle hardcoded block. Counter at `$SIDECAR_DIR/.security-attempts`, log at `.security-attempts.log` (JSONL). Reset semantics: clean check (0 sec findings) resets to 0 + logs reset event; integrity blocks intentionally do NOT reset.
  - **Why:** v0.9.0 AC#4 caused costly iteration loops (5 autorun cycles in dynamic-roster-per-gate session, each catching deeper-but-real security findings, with no opportunity for /build to attempt fixes between cycles). The "security findings are blockers" intent is preserved — they ARE blockers if unresolved after N attempts — but first-cycle halt was the wrong default.
  - **Already shipped (inline patch):** `scripts/autorun/check.sh` lines 237-310 (counter logic + audit log + JSON-escape via python json.dumps + write-failure handling). Memory: `feedback_security_n_attempts_before_block.md`.
  - **Spec needs to add:** test fixtures (3-attempt happy path, cap-exhausted block, counter-reset on clean check, counter-persists-on-integrity-block, env override `SECURITY_MAX_FIX_ATTEMPTS`), schema for `.security-attempts` + `.security-attempts.log`, frontmatter override (`security_max_fix_attempts:` per spec), interactive-mode parity (commands/check.md should honor same counter), CHANGELOG entry, version bump (likely v0.10.0).
  - **Sequencing:** unblocked. Patch is in production via dynamic-roster-per-gate session; spec formalizes + tests + documents.
  - **Size:** S–M (mostly tests + docs; the code is shipped).
  - **Codex review optional** — small code surface; standard /check sufficient.

- **`pipeline-gate-rightsizing` (NEW spec candidate — sibling to permissiveness)** — match gate weight to work class. `/spec` already picks bug-fix / small-change / feature / V2 at Phase 2; downstream gates don't honor that. A 3-line bug fix should not dispatch 6 PRD reviewers + 7 designers + 5 validators (28+ persona invocations). **Six levers in scope:**
  1. **Work-class → gate-intensity mapping.** Bug-fix: skip /spec-review + /plan + /check (go straight to /build). Small-change: 2-reviewer /spec-review, no /plan, 2-validator /check. Feature: full default roster. V2: full + Codex mandatory.
  2. **Which agents per gate per work-class** (not just count — selection). The persona roster has different fitness-for-purpose:
     - Security-flavored work → security-architect + Codex must run; ux/ambiguity/stakeholders skippable
     - UX-polish small change → ux + ambiguity sufficient; security-architect + Codex skippable
     - Architectural feature → completeness + sequencing + scope-discipline + Codex; specialists optional
     - Bug fix → none, OR just one targeted reviewer matching the bug class

     This subsumes part of `account-type-agent-scaling`'s resolver (which today is budget-driven only) — work-class becomes a second resolver input alongside `agent_budget`.
  3. **Codex inclusion per gate is a first-class decision, not "always-on if installed."** Codex is high-cost, high-signal — should run on architectural specs, security work, V2 revisions; should NOT run on docs-only or trivial work. The 4-iteration autorun-overnight-policy session was Codex-load-bearing (caught H2 nonce trust-boundary failure). Future architectural specs (autorun-verdict-deterministic XL, this rightsizing spec L) should mandate Codex; install-sh-backup-uninstall (M, mostly plumbing) does not need it.
  4. **Per-gate skip rules** declared at spec.md frontmatter; honored by gate scripts.
  5. **Adaptive iteration cap by domain.** Hard cap at 2 (from permissiveness) too rigid for security; too loose for typo fixes. Cap of `min(work_class_max, persona_budget_max, 5)`.
  6. **Cost-aware self-skip.** Gates know their token cost (per `holistic-token-cost-instrumentation` instrumentation); a small change shouldn't burn $20 in /check synthesis.
  - **Why:** the autorun-overnight-policy session ran the FULL pipeline 4× over 2 days for what was ultimately ~2,300 LoC of policy framework. About half of the gate cycles were structurally wasted because the work didn't need that much review. ^[inferred] Combined with `pipeline-gate-permissiveness`, rightsizing closes the "stop overweight gating" problem from the other direction (don't over-dispatch in the first place; don't over-halt on what was dispatched).
  - **Entry points:** `commands/{spec,spec-review,check,plan,build}.md` (work-class read + gate-skip honors); spec.md frontmatter schema (`work_class:` field); resolver integration (work-class as another input alongside `agent_budget`); test fixtures for each work-class flow.
  - **Sequencing:** unblocked. `pipeline-gate-permissiveness` shipped 2026-05-06 as v0.9.0 (PR #7); rightsizing is now the natural follow-up — same command/persona surface, same instrumentation, narrower architectural risk.
  - **Size:** L (similar shape to permissiveness; touches same command skills + adds frontmatter schema + resolver integration).
  - See memory `feedback_pipeline_gate_permissiveness.md` (overlapping rationale; rightsizing is the dispatch-side of the same overweight-gating problem) and `project_pipeline_gate_permissiveness.md` (shipped status).

- **`install-sh-backup-uninstall` (NEW spec candidate)** — install.sh currently modifies adopter defaults (CLAUDE.md, .claude/settings.json, .claude/agents/, commands/, hooks, doctor.sh, queue scaffolding) without backups or a revert path. Add (a) pre-flight banner with explicit consent gate explaining we're making opinionated changes, (b) backup every modified file to `.monsterflow-backups/<timestamp>/manifest.json` BEFORE modification, (c) ship `scripts/uninstall.sh` that reads the manifest and reverts (idempotent; supports `--restore-from <timestamp>`), (d) document revert path in README + CHANGELOG as a trust signal.
  - **Why:** adopters who try MonsterFlow and decide it's not for them are stuck cleaning up by hand. Reversibility is a trust signal. The pipeline + agents + hooks are *opinionated* defaults — without explicit messaging adopters may not realize how much we're stamping on their existing config.
  - **Entry points:** `install.sh` (banner + backup machinery); new `scripts/uninstall.sh`; `README.md` + `CHANGELOG.md` updates; smoke test `tests/test-install-uninstall-roundtrip.sh`.
  - **Sequencing:** independent of other backlog items. Can start any time.
  - **Size:** M (mostly file enumeration + JSON manifest + reverter; ~200-400 LoC + tests).
  - **Codex review optional** — mostly plumbing (file enumeration + JSON manifest + reverter). Standard /check roster is sufficient; Codex would be belt-and-suspenders on a low-architectural-risk spec.
  - See memory `project_install_sh_backup_uninstall.md` for the file-surface enumeration and design notes.

---

## Autorun follow-ups (deferred from autorun-overnight-policy v4-v5)

- **`autorun-verdict-deterministic` (REJECTED 2026-05-07 after /spec-review)** — proposed replacing the synthesis-emits-fence verdict path at /spec-review, /plan, /check with deterministic aggregation over per-reviewer JSON sidecars. Closes the v2-MF6 single-fence-spoof residual that autorun-overnight-policy v6 documents as a known v1 limitation. **Outcome:** /spec-review surfaced 8 critical gaps + 4× H1 from Codex; the cost of closing the residual exceeds its narrow attack-surface value (the realized attack requires the spec author to also be the attacker, which doesn't match how users actually run their own specs). Decision: accept the v6 residual as documented; do not pursue this restructure.
  - **Gaps surfaced (preserved for any future attempt):**
    - **CG-1 (load-bearing):** sidecar emission unimplementable in current execution model — `claude -p` reviewers have stdout, not file-write authority. Any future attempt must define the wrapper protocol (stdout-JSON-only? two-output runner? wrapper-managed file-write via env var?) before /plan.
    - **CG-2:** aggregator `raw/*.json` glob trusts directory contents — needs roster manifest enforcement + fresh dir per run + persona/stage validation.
    - **CG-3:** dual security path (`findings[].class=="security"` AND separate `security_findings`) creates a downgrade bypass.
    - **CG-4:** sidecar enums (`polish` severity + `polish` class) collide with existing `findings.schema.json` (`nit` severity, no `polish` class).
    - **CG-5:** AC#24 conflated schema-validation failure (resilience path) with aggregator-internal-error (trusted-code crash).
    - **CG-6:** Codex sidecar emission undefined — `_codex_probe.sh` produces prose, not JSON.
    - **CG-7:** quorum rule pathological at N=2 / N=3 — needs `min_survivors = max(2, ceil(N*ratio))` + mandatory-persona block.
    - **CG-8:** in-flight migration breaks `findings.jsonl` / `followups.jsonl` id-stability across cutover — needs `aggregation_version` field + /build/run.sh staleness gate.
  - **What v6 already provides (the actual baseline):** multi-fence detection, NFKC normalization, zero-width stripping, count==0 + first-line-marker absent → integrity block. The realized residual is specifically the case where a reviewer's prose contains exactly one perfectly-crafted forged GO fence AND synthesis omits its own fence.
  - **If revisited in the future:** start by answering CG-1 (sidecar emission model) — the rest of the gaps are addressable but inert until the execution-model gap is closed. Consider whether the narrow attack surface justifies the XL effort, OR whether a much smaller "synthesis hardening" framing (instruct synthesis to ignore fences in reviewer raws; tighten one-fence requirement) would close most of the realized risk at S-size.
  - **Artifacts (preserved in git history at commits e9422cc / 7be3782):** `docs/specs/autorun-verdict-deterministic/spec.md`, `review.md`, 6 reviewer raws + `codex-adversary.md` raw, `run.json`. Recover via `git show` if a future attempt wants to start from this baseline.

- **Stage-boundary STOP-check inside `run.sh`** — current `autorun-batch.sh` honors STOP only at iteration boundaries (an in-flight `run.sh` finishes its slug after STOP is touched). Adding a STOP-check inside `run.sh` between stages would cut overnight halt latency from "next slug" to "next stage."
  - **Why:** R15 documented at autorun-overnight-policy/plan.md v4 — iteration-boundary semantics are correct but coarse. Adopters expecting STOP to halt mid-slug will be surprised.
  - **Entry points:** `scripts/autorun/run.sh` `update_stage()` function; add `[[ -e queue/STOP ]]` check after each stage transition.
  - **Size:** S.

- **Promote `tests/test-policy-json.sh` to its own file** — currently 5.2's `_policy_json.py` audit + extract-fence + validator tests live in `test-autorun-policy.sh`. Splitting isolates Python failures from shell failures.
  - **Why:** Codex /check v2 SF — keeping Python CLI/schema/fence tests inside the shell policy suite slows debugging when one breaks.
  - **Size:** S (mostly file split + run-tests.sh wiring).

---

## Token economics (cross-cutting)

> **2026-05-04:** Per-persona instrumentation (cost + survival + uniqueness as separate columns) promoted to `docs/specs/token-economics/spec.md` (instrumentation-only after `/spec-review` round 1 narrowed scope). Per-plugin cost measurement and roster-scaling action stay here, both depending on the instrumentation spec landing first. Items #4 (Agent Teams) and #2 (Onboarding) remain unscheduled.

- **Per-plugin cost measurement** — extend `scripts/session-cost.py` (or sister script) to attribute token spend by enabled plugin (superpowers, vercel, codex, context7, etc.). Required before "plugin scoping per gate" below has any data to act on.
  - **Why:** External user feedback (2026-05-03) hypothesized superpowers' per-message skill-description injection is the dominant cost; instrumentation spec round-1 review verified there is no per-plugin marker in session JSONL and `attributionSkill` is per-message, not per-plugin. Methodology is genuinely undecided — needs design (baseline-vs-installed diffing? a logging shim around plugin loads? something else?).
  - **Sequencing:** *do not start* until `token-economics/spec.md` Phase 0 spike completes — that spike answers whether MonsterFlow has per-subagent JSONL access at all, which is a precondition.
  - **Entry points:** `scripts/session-cost.py`, `dashboard/data/plugin-costs.jsonl` (proposed sister artifact, not mixed with `persona-rankings.jsonl`).
  - **Size:** M (methodology design dominates; instrumentation itself is small once the signal source is identified).

- **Plugin scoping per gate (action half — depends on per-plugin cost measurement)** — once per-plugin cost data exists, decide which plugins to scope out of which gates (e.g., disable superpowers SessionStart skill for non-`/build` subagents). Pure cost-vs-value action that the data unlocks.
  - **Why:** Friend on Pro plan diagnosed superpowers as the main rate-limit consumer; if data confirms, scoping superpowers to `/build`-time only would directly reduce Pro-tier spend. Per global CLAUDE.md, superpowers is already supposed to be `/build`-only; the harness doesn't currently enforce that per-gate.
  - **Sequencing:** *do not start* until per-plugin cost measurement above has shipped ≥10 runs of data.
  - **Entry points:** `settings/settings.json` `enabledPlugins`, possibly per-gate plugin overrides if Claude Code supports them (verify), `commands/{spec-review,plan,check}.md` if scoping is dispatch-time.
  - **Size:** S–M (small if `enabledPlugins` is gate-scopable; medium if we have to wrap dispatch).

- **Holistic token-cost instrumentation + value-vs-benefit judging** *(partially promoted → docs/specs/token-economics/spec.md — per-persona dimension only; per-plugin and per-/wrap dimensions remain here)* — measure where MonsterFlow's token budget actually goes, then make scope-trimming decisions on data instead of guesses. Per-persona half is now a real spec; per-plugin and per-`/wrap insights` cost dimensions still need their own specs (above and below).
  - **Why:** External user feedback (forwarded 2026-05-03) — friend on Claude $20 Pro plan ran two prompts in MonsterFlow and went from 3% → 60% of the rate-limit budget. Their own Claude session diagnosed the superpowers plugin as the main consumer ("injects all those skill descriptions on every message") and offered to disable superpowers + vercel + codex from `enabledPlugins`. So: (a) the cost is real and measurable, (b) the heaviest tax may be plugin auto-injection, not agent fan-out, (c) we currently have no way to *prove* which lever matters most. Without instrumentation we'll keep guessing wrong.
  - **What to investigate:**
    - Per-message system-prompt size by enabled plugin (superpowers, vercel, codex, context7, etc.) — measure once, compare against value each delivers in the pipeline.
    - Per-gate agent-fan-out cost (6 reviewers × full spec read) vs. finding-yield from `findings.jsonl`.
    - Per-/wrap insights cost vs. signal value.
    - Cost-of-Codex-adversarial vs. unique findings it surfaces (already partially measurable from `codex-adversary.md` files).
  - **Already taken (free wins, no data needed):**
    - **2026-05-03:** Disabled `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` in `~/.claude/settings.local.json` (renamed to `_DISABLED_…` with inline `_NOTE_AGENT_TEAMS` explaining why). The flag spawns full independent CC instances per teammate ("token-intensive" per official docs) and our pipeline uses zero peer-messaging / shared-task-list / TeammateIdle hooks. Pure cost, no benefit.
  - **Possible levers (in order of likely impact, to be confirmed by data):**
    1. Slim or scope-narrow `enabledPlugins` for pipeline use — superpowers might be turn-able-off outside the execution-discipline phase of `/build`.
    2. Reduced persona roster on Pro accounts (overlaps with the agent-scaling item below — likely solved together).
    3. Skip `/insights` on Pro by default (already opt-in via `/wrap-insights`).
    4. Lazy-load personas — only read the persona md inside the agent that runs it, not in the orchestrator.
  - **Where the metric lives:** extend Judge dashboard with a "Token economics" tab (per gate: prompt tokens in, completion tokens out, findings emitted, cost-per-finding). Same `dashboard-append.sh` plumbing.
  - **Tightly related to:** "Account-type agent scaling" below — the data this produces tells us the right Pro roster size, so investigate first.
  - **Entry points:** `dashboard/`, `scripts/judge-dashboard-bundle.py` (extend run.json read to pull token counts if Anthropic SDK exposes them), `commands/wrap.md` (Phase 1 already records cost via `session-cost.py` — extend), `settings/settings.json` `enabledPlugins`.
  - **Size:** M–L (instrumentation + dashboard tab + decision framework).

## Pipeline

- **Account-type agent scaling** *(deferred — depends on token-economics/spec.md instrumentation landing first; combined-spec attempt rolled back 2026-05-04 after `/spec-review` round 1 found 7 blockers)* — auto-detect the active Claude account tier (Pro vs Max vs API) and scale agents-per-gate accordingly. Max/API can run the full 6+6+5 roster; Pro hits rate limits faster and should use a reduced roster (e.g. 3+3+3). The `/spec-review` round-1 findings (`docs/specs/token-economics/spec-review/findings.jsonl`) inform this spec when it gets written: (a) tier-detection cascade must be designed against verified CLI surface, not guesses; (b) the resolver should ship in report-only mode first per Codex's recommendation; (c) summary↔ceiling defaults must be reconciled (Max≠full if ceiling<roster size); (d) value formula must include severity weighting and a divisor floor; (e) deterministic tie-break required.
  - **Why:** Pro accounts hit rate limits mid-gate and the run aborts, leaving partial artifacts. A budget-aware roster keeps the pipeline usable on Pro without forcing every adopter onto Max.
  - **External signal:** Pro user forwarded feedback 2026-05-03 — two prompts moved their rate-limit budget 3% → 60% in MonsterFlow flows. Their own Claude session pinpointed the superpowers plugin's per-message skill-description injection as the main consumer (see token-economics item above). Confirms Pro is the constrained tier worth designing for.
  - **Detection signal:** check `claude config` or env for account type, or expose a `PIPELINE_AGENT_BUDGET` override.
  - **Entry points:** `commands/spec-review.md`, `commands/plan.md`, `commands/check.md` (the persona-list section in each).
  - **Size:** S–M (mostly slicing the persona list + reading one env var).
  - **Sequencing note:** wait on the token-economics investigation above before picking the Pro roster size — measure first, then trim.

## Future architecture (research-grade, not near-term)

- **Inter-agent debate via Claude Code Agent Teams** — investigate whether the Judge stage produces meaningfully better findings if reviewer personas can message each other directly during a gate (e.g., scope-discipline challenges completeness in real time, two personas converge on a merge before reaching the orchestrator) instead of all reconciliation happening post-hoc in Judge + Synthesis.
  - **Why:** Today every reviewer is a one-shot return to the orchestrator; Judge does dedup/contradiction-resolution after the fact, often with less context than the original reviewer had. Real peer messaging could surface stronger merges and stronger disagreements with audit trails.
  - **Mechanism:** `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` (CC ≥ v2.1.32, currently research preview) enables peer messaging by name, shared task list, and `TeammateIdle` / `TaskCreated` / `TaskCompleted` hooks. Each teammate is a full independent CC session — own context, own CLAUDE.md, own MCP/skills. Token cost scales linearly with team size.
  - **Disabled today:** the flag was on without us using any of its primitives, pure cost-no-benefit (see token-economics "Already taken" note). Stays off until/unless this experiment is approved.
  - **What to test:** A/B a single `/spec-review` gate with team-mode peer messaging vs. the current orchestrator-mediated flow. Measure: (a) finding quality (does Judge have less work to do?), (b) token cost delta, (c) wall-clock time, (d) whether `Agent Disagreements Resolved` becomes richer.
  - **Entry points:** `commands/spec-review.md` (Phase 1 dispatch section), `personas/judge.md`, `personas/synthesis.md`. Would need a separate `commands/spec-review-team.md` variant to A/B against, not a destructive rewrite.
  - **Sequencing:** *do not start* until token-economics + account-scaling items above are done. This adds cost; we need the budget framework in place first.
  - **Size:** L (research project, not a feature ship).
  - **Prior research (2026-05-05):** docs reread + reframe captured. Memory: `project_agent_teams_refit.md` (debate-not-fan-out framing, 3 concrete fits: adversarial /check, personas-as-subagent-defs, hook-enforced invariants). Wiki: `_raw/2026-05-05-1037-agent-teams-refit-monsterflow.md` (general Claude Code primitives, splits at ingest). Read these before opening a `/spec` so we don't restart from a blank page.

---

## From pipeline-pacing-and-prefill /check (2026-05-14)

- **`mobile-verify-skill` (v0.14.1 spec candidate, M)** — Carved off from
  pipeline-pacing-and-prefill per /check ck-005 (2026-05-14). Mobile-build
  +launch verify via hub-and-spoke skill. Detection: *.xcodeproj OR
  *.xcworkspace OR constitution stack:mobile OR Package.swift declaring
  iOS app product (drop naked Package.swift). Exit-code contract: 0 PASS /
  1 CODE / 2 INFRA / 3 UNKNOWN (halt with classification text). Targeted
  UDID erase on INFRA, not erase-all. Skill location at repo
  .claude/skills/mobile-verify/ (not ~/.claude/), install.sh adds explicit
  skills wave. **Entry points:** new skill dir + scripts/verify.sh + 4
  test fixtures (good/bad/infra-stuck/infra-missing-runtime) +
  tests/test-skills.sh coverage + commands/build.md Phase 3 detection
  branch.

- **`pipeline-eta-from-timing-data` (v0.15 spec candidate, S-M)** — Carved
  off from pipeline-pacing-and-prefill per /blueprint OQ7 (2026-05-14).
  Replaces v0.14's fallback-only ETA in scripts/_pipeline_eta.py with
  per-gate medians from real timing data. **Entry points:** add stage
  duration tracking to session-cost.py (or new timing emitter at gate
  boundaries) → new dashboard/data/gate-timing.jsonl → _pipeline_eta.py
  real-data branch reading the JSONL with cold-start fallback to current
  hardcoded defaults.
