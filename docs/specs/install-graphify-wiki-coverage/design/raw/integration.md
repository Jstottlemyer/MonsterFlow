---
persona: integration
feature: install-graphify-wiki-coverage
gate: design
created: 2026-05-13
---

# Integration Design — install-graphify-wiki-coverage

## Key Considerations

- **Placement at install.sh:757-758 is safe but the ordering invariant must be documented.** `do_knowledge_layer` runs after `do_theme_install` returns and before the CLAUDE.md baseline merge. The theme stage writes `~/.zshrc` (sentinel block for the theme). Knowledge Layer writes a second sentinel block to the same file. Since both writes are sequential and each guards with its own sentinel string, there is no race. But if someone adds a third stage that also writes `.zshrc`, this ordering assumption becomes load-bearing and should be called out in a comment at the call site.

- **`posix_quote` hoist is the highest-risk integration change.** Moving a function from inside `do_theme_install`'s local scope to top-level changes its visibility for the entire script lifetime. If any other function between the current hoist point and install.sh's end uses `posix_quote` as a local name (it doesn't today, but the change is easy to get wrong in a 830-line file), a name collision would silently break. The hoist must land BEFORE the first function that uses it — currently `do_theme_install` at install.sh:711. Recommend defining it around install.sh:490, between `clean_stale_symlinks` and the queue/gitignore section, where no other helpers are defined.

- **`graphify claude install` writes to files the CLAUDE.md baseline merger also touches.** `graphify claude install` writes a section to `~/CLAUDE.md` and a PreToolUse hook to `~/.claude/settings.json`. The baseline merger (`python3 scripts/claude-md-merge.py --target ~/CLAUDE.md --template templates/CLAUDE.md`) runs immediately after `do_knowledge_layer`. The merger is documented as idempotent and additive — it does not strip sections it doesn't own. The integration risk is low but real: if the graphify CLAUDE.md section uses a header that the merger mistakes for a merge target, it could duplicate or mangle the section. Verification: the merger should be checked to confirm it's section-aware and won't clobber graphify's addition. This is a one-time check, not ongoing complexity.

- **`onboard.sh`'s graphify offer block overlaps with the new stage but is NOT redundant.** `onboard.sh` at lines 89-105 gates on `[ -x "$REPO_DIR/scripts/bootstrap-graphify.sh" ]` and offers to run the full cross-project bootstrap (launchd, post-commit hooks, per-project indexing). That is categorically different from what `do_knowledge_layer` does (install the CLI + skill). No change to `onboard.sh` is required for this spec. The offer block is still correct: it fires if graphify IS on PATH (the CLI is already installed), and asks whether to bootstrap projects. The new Knowledge Layer installs the CLI; the onboard offer bootstraps projects after. These are sequential, complementary, non-overlapping.

- **brew bundle is committed before `do_knowledge_layer` runs.** The brew bundle stage (`do_install_missing` at install.sh:393-447) completes — or is declined — before Knowledge Layer fires. This has three integration consequences: (a) cmux drift detection correctly fires AFTER brew bundle has had its chance to install cmux, so a "drift" signal means the user declined the bundle AND the theme stage ran; (b) the Obsidian.app targeted `brew install --cask obsidian` inside Knowledge Layer is genuinely independent from the bundle (the spec explicitly calls this out); (c) if `brew` itself is missing (REQUIRED tier would have aborted install.sh at line 399, so brew missing + reaching Knowledge Layer is impossible unless `--no-install` was passed).

- **`MONSTERFLOW_INSTALL_TEST=1` is the existing test-seam env, already checked at two sites.** The new Knowledge Layer must add a third short-circuit: before the real `python3 -m venv` call and before `brew install --cask obsidian`. The seam for the `graphify claude install` sub-call also needs to be guarded separately (it writes to `~/.claude/` which is outside the isolated `$CASE_HOME`). Piggybacking on the existing env var is correct; no new env var needed.

- **Test file wiring is load-bearing: the orchestrator-wiring guard exits 2 on mismatch.** Adding `test-install-knowledge-layer.sh` to disk without appending it to the `TESTS` array causes every test run to fail with `ERROR: run-tests.sh wiring drift`. This must be a single atomic commit (file creation + array append), not two separate commits. The parallel `/build` memory (`feedback_test_orchestrator_wiring_gap`) makes this a blocking constraint.

- **`~/.config/cmux/cmux.json` detection in Knowledge Layer vs. `do_theme_install`.** The theme stage WRITES the symlink at install.sh:731. Knowledge Layer READS the symlink at detection time. These are in different functions, different call sites, and sequential. The only integration concern: under `--no-theme`, the theme stage returns early before writing the symlink, so Knowledge Layer sees no symlink and correctly reports `cmux drift: ○ N/A`. This is the intended behavior; no guard needed.

- **`/Applications/Obsidian.app` path constant is macOS-only.** install.sh already has a macOS guard (install.sh:62-68 checks `OSTYPE=darwin*`). The entire script aborts on Linux before reaching Knowledge Layer. No multi-platform guard needed inside `do_knowledge_layer`. Tests run on the same macOS host, so the Applications path is real — but under an isolated `$CASE_HOME`, there is no real `/Applications`. Tests must either: (a) mock `[ -d /Applications/Obsidian.app ]` via a `MONSTERFLOW_APPLICATIONS_DIR` override, or (b) pre-stage a mock `$HOME/Applications/Obsidian.app` and patch the path constant. Option (a) is cleaner.

## Options Explored

### Option A: Single test fixture file per AC, all in test-install-knowledge-layer.sh

All 9 ACs live in one test file, sharing the existing `setup_test()` / `teardown_test()` / `run_install()` pattern from `test-install.sh`. Each case calls `setup_test`, builds its specific fixture, calls `run_install`, asserts, calls `teardown_test`.

Pros:
- Consistent with the existing harness model: one test file per feature area (`test-install.sh` covers install-rewrite, `test-install-knowledge-layer.sh` covers this spec).
- The orchestrator-wiring guard counts `test-*.sh` files; one new file = one count increment, straightforward.
- Shared helper functions (`make_stub`, `assert_match`, `stage_required_present`, etc.) are imported by sourcing the parent file or duplicated with a shared lib. Either approach is clean.

Cons:
- 9 ACs × one full install.sh run each = ~270 seconds if each run takes 30s. The existing `INSTALL_RUN_TIMEOUT_DEFAULT=30` per case applies; total runtime for the suite grows by ~4-5 minutes.
- A single failing case in the middle of the file causes all subsequent cases to be skipped if `set -e` is active at file level. The existing test-install.sh handles this via a `SUITE_FAIL` counter that runs through all cases regardless — this pattern must be replicated.

Effort: **S** — direct copy-paste from test-install.sh structure, adapt for KL-specific fixtures.

### Option B: Shared helper lib extracted to tests/lib/install-harness.sh

Extract the 150-line boilerplate (`setup_test`, `teardown_test`, `make_stub`, `assert_*`, `run_install`) from `test-install.sh` into a shared library at `tests/lib/install-harness.sh`. Both `test-install.sh` and `test-install-knowledge-layer.sh` source it.

Pros:
- DRY: no copy-paste of 150 lines of harness.
- Future test files for other install-adjacent specs don't need to re-duplicate the harness.

Cons:
- Introduces a new file (`tests/lib/install-harness.sh`) that the orchestrator-wiring guard ignores (it only counts `test-*.sh` on disk). If the lib file is missing, both test files break with a confusing error.
- Requires modifying `test-install.sh` (source the lib, remove the duplicated helpers) — a refactor that's out of scope for this spec and touches a file with 20 working test cases. Risk of regression.
- The lib would need its own test or verification step — more surface area.

Effort: **M** — the refactor of test-install.sh alone is ~1 hour of careful work.

### Option C: Thin test file that delegates fixture setup to a KL-specific helper script

`test-install-knowledge-layer.sh` is a thin orchestrator that sources a `tests/lib/kl-fixtures.sh` for all fixture-building helpers, keeping the test file itself small (<100 lines). Each case's fixture logic lives in a named function (`fixture_all_absent`, `fixture_all_present`, etc.) in the lib.

Pros:
- Test cases read cleanly: `fixture_all_absent; run_install --non-interactive; assert_match ...`.
- Fixture functions are composable: AC2 and AC3 share the same `fixture_all_present` call.

Cons:
- Same lib-tracking problem as Option B (the lib doesn't count toward the wiring guard).
- For 9 cases, the fixture functions are simple enough that inline setup is readable without a separate lib.
- Premature abstraction for a spec this size.

Effort: **S-M** — similar to Option A for the initial build, but adds the lib extraction step.

**Recommendation: Option A.** The existing harness pattern is proven, the orchestrator-wiring guard works cleanly with one new file, and the 9 ACs don't justify a shared-lib refactor this cycle.

---

### Option D (for `posix_quote` hoist placement): Hoist to top-level near line 490

Two sub-options for WHERE to place the hoisted `posix_quote`:

**D1: Near line 490 (after `clean_stale_symlinks`, before queue/gitignore section).** No other helpers are defined in this block; adding one more top-level helper here is clean.

**D2: Near line 610 (above `detect_owner`).** Keeps all "helper functions" grouped together. `detect_owner` is already the first non-trivial standalone helper.

Pros D1: Further from `do_theme_install` (where it was nested), clearly "not theme-related".
Pros D2: Grouped with `detect_owner` and other helpers — a reader scanning for "what helpers exist" finds them all in one region.

**Recommendation: D2 (near line 610, above `detect_owner`).** The "helper cluster" pattern is more discoverable. The exact line doesn't matter as long as the hoist is before install.sh:711 (`do_theme_install` definition).

---

### Option E (for onboard.sh graphify-offer block): Leave as-is vs update to mention Knowledge Layer

The existing onboard.sh offer at lines 89-105 gates on `bootstrap-graphify.sh` existing. After this spec ships, an adopter who just ran install.sh may already have graphify CLI installed (Knowledge Layer handled it). The onboard offer is still correct (it's about bootstrapping projects, not about CLI install), but the wording implies the offer only fires when graphify is new. A user who declined the Knowledge Layer's CLI install will still see the offer if bootstrap-graphify.sh exists.

**Option E1: Leave onboard.sh unchanged.** The offer is about project bootstrapping, not CLI install. The gate (`-x bootstrap-graphify.sh`) is correct.

**Option E2: Add a secondary gate to onboard.sh: only offer if `command -v graphify` succeeds.** Without graphify on PATH, running bootstrap-graphify.sh would fail anyway. This tightens the gate and avoids offering a bootstrap when the CLI isn't installed.

Pros E2: Better UX — no confusing "bootstrap all your projects?" offer when graphify isn't installed.
Cons E2: A change to onboard.sh is out of spec scope; `bootstrap-graphify.sh` itself already checks for the CLI at runtime.

**Recommendation: E2 is the right long-term behavior but is out of scope for this spec.** Defer to BACKLOG. Capture as an open question below.

## Recommendation

1. **Test fixture pattern**: Option A — one new `test-install-knowledge-layer.sh` file following the existing `test-install.sh` structure. Copy the necessary helpers (or source the existing file in a compatible way) rather than creating a shared lib. Wire into `tests/run-tests.sh` TESTS array after all existing entries, in the same atomic commit as the test file creation.

2. **`posix_quote` hoist placement**: Option D2 — define at ~install.sh:610, immediately above `detect_owner`. Add a one-line comment: `# Top-level helper; used by do_theme_install and do_knowledge_layer. Defined here so --no-theme runs can still call install_obsidian_env().`

3. **Stage wiring**: Call `do_knowledge_layer` at install.sh:758 (after `do_theme_install` at 757). The call site comment should read: `# --- Knowledge Layer (graphify CLI, wiki skills, OBSIDIAN_VAULT_PATH, Obsidian.app, cmux drift) ---`. The new helper functions should be defined as a block above this call, between install.sh:757 and the new call site.

4. **`onboard.sh`**: No change this spec. The existing graphify-offer block is not redundant and does not need to know about Knowledge Layer's CLI install.

5. **`graphify claude install` + CLAUDE.md merger interaction**: Add one explicit call-out in the implementation notes: "run `do_knowledge_layer` before the CLAUDE.md merger so that graphify's CLAUDE.md writes (from `graphify claude install`) are present when `claude-md-merge.py` runs and the merger can see them as existing content to preserve." The merger already runs after `do_knowledge_layer` in the spec's proposed ordering, so this is correct as-specced.

## Constraints Identified

- **bash 3.2 ceiling (per `feedback_negative_array_subscript_bash32`)**: No `${arr[-1]}`, no `declare -A`, no `mapfile`. Status vars for 5 pieces must be scalar locals; the API persona's Option A (5 parallel scalars) is the only compatible choice.

- **`MONSTERFLOW_INSTALL_TEST=1` must short-circuit three new external invocations**: `python3 -m venv` (graphify venv creation), `brew install --cask obsidian`, and `graphify claude install`. All three must emit `RUNNING: <cmd>` BEFORE the short-circuit check so AC8b's STUB_LOG assertions still work.

- **Orchestrator-wiring guard is strict**: `ls tests/test-*.sh | wc -l` vs `WIRED_COUNT` in `run-tests.sh`. File creation and TESTS-array append must land in the same commit.

- **The `MONSTERFLOW_APPLICATIONS_DIR` override (or equivalent) is required for test portability**: Real `/Applications/Obsidian.app` does not exist in the isolated `$CASE_HOME`. Without an override mechanism, `detect_obsidian_app()` always sees "missing" under tests. Options: (a) introduce `MONSTERFLOW_APPLICATIONS_DIR="${MONSTERFLOW_APPLICATIONS_DIR:-/Applications}"` in `detect_obsidian_app`, set to `$CASE_HOME/Applications` in tests; or (b) pre-stage `$CASE_HOME/Applications/Obsidian.app` and point the detection at `$HOME/Applications/Obsidian.app`. Option (a) is cleaner and consistent with `MONSTERFLOW_HASCMD_OVERRIDE`.

- **Sequential `.zshrc` writes do not race, but must not duplicate sentinel blocks**: `do_theme_install` appends `# BEGIN MonsterFlow theme`. `do_knowledge_layer` appends `# BEGIN MonsterFlow obsidian-wiki`. Each guards with its own sentinel string. The fact that both write to the same file sequentially is safe; the invariant is that each sentinel prefix is unique and never written twice (idempotency AC3).

- **`bootstrap-graphify.sh` is out of scope**: Running it from `install.sh` would spend real LLM tokens and modify launchd state across `~/Projects/`. Knowledge Layer is detect-and-install-CLI only. The bootstrap remains a separate user-invoked one-shot (no change).

- **`do_install_missing` (brew bundle) runs before `do_knowledge_layer`**: By the time Knowledge Layer runs, brew bundle has committed. This means: (a) cmux drift detection is valid (any cmux absence is due to bundle decline, not a not-yet-run stage); (b) the `brew install --cask obsidian` inside Knowledge Layer is a targeted call, NOT a re-run of brew bundle; (c) if brew bundle failed with exit non-zero, install.sh already exited at install.sh:443, so `do_knowledge_layer` is unreachable in that case.

- **`set -euo pipefail` is active throughout install.sh**: All detect helpers must `return 0` (status in stdout, not exit code). Failure to honor this causes the helper's non-zero exit to abort the entire install. The API persona's constraint table covers this; the implementation must honor it.

- **`posix_quote` local-function cleanup**: After hoisting, the `posix_quote() { ... }` block must be removed from inside `do_theme_install` (it would otherwise shadow the top-level definition within that function's scope — bash inner-scope definitions win). This is a two-part change: add at top-level, remove from inside `do_theme_install`. Both in the same commit.

## Open Questions

- **`MONSTERFLOW_APPLICATIONS_DIR` override**: Should this be a new env var introduced by this spec (consistent with `MONSTERFLOW_HASCMD_OVERRIDE` and `MONSTERFLOW_INSTALL_TEST`), or should `detect_obsidian_app` use a more generic approach (e.g., `OBSIDIAN_APP_PATH` override)? Recommend the former — keep the pattern (`MONSTERFLOW_*` prefix, test-only use) consistent. Needs `/check` confirmation or implementation-time call.

- **`onboard.sh` graphify-offer secondary gate**: After this spec ships, the onboard offer fires even if the user declined the Knowledge Layer's CLI install (bootstrap-graphify.sh is on disk regardless). Should a future spec add `command -v graphify` as a secondary gate in `onboard.sh`? Recommend deferring to BACKLOG. Capture here so it surfaces in `/check`.

- **Shared helpers between test-install.sh and test-install-knowledge-layer.sh**: The two files will share ~150 lines of identical harness code (`setup_test`, `teardown_test`, `make_stub`, `assert_match`, etc.). Is copy-paste acceptable for now, or should `/build` be tasked to extract the shared lib as a follow-on? Given the memory `feedback_template_first_batching`, recommend flagging this as a known duplication and deferring the lib extraction to a follow-on spec.

- **`graphify claude install` under `MONSTERFLOW_INSTALL_TEST=1`**: The spec says "under tests, mock the binary/cask install at the harness layer." But `graphify claude install` is a CLI subcommand, not a brew call. The stub for `graphify` (already present for the `command -v` detection check) would intercept the `graphify claude install` call and log it to `$STUB_LOG`. This is correct behavior — no explicit guard needed beyond the stub. Confirm this is the intended contract with the `/build` agent.

- **`~/.obsidian-wiki/config` preservation on re-run**: The data-model persona confirms the file must not be overwritten if it already exists (because it may contain `OBSIDIAN_WIKI_REPO` or other keys that install.sh doesn't manage). The detection-then-no-op pattern covers this for the happy path. But what if the detection says "warn: vault path configured but missing" (EC4)? In that case, install.sh should NOT overwrite the config file — the user moved their vault and needs to update the path manually. This is implied by the spec but should be explicit in the implementation note.

## Integration Points with Other Dimensions

- **API persona** (done): Pins the 5-scalar status-token grammar, the function naming convention (`detect_*`, `install_*`, `do_*`, `render_*`), and the `RUNNING: <cmd>` stdout contract. Integration dimension consumes the function signatures and relies on the detection return values being scalar locals (not globals) to avoid state bleed between stages.

- **Data-model persona** (done): Confirms `~/.obsidian-wiki/config` has a second key (`OBSIDIAN_WIKI_REPO`) that the parser must silently skip. Integration dimension adds: install.sh must NOT clobber the existing file if it already exists, even on a re-run where the vault path is misconfigured (EC4 warning path). The atomic-write-only-if-missing invariant is shared state between data and integration.

- **What integration needs from API**: The API persona's recommendation (Option A) is confirmed compatible with the bash 3.2 ceiling and with the sequential install.sh execution model. Integration accepts the 5-scalar interface.

- **What integration needs from data-model**: The `parse_obsidian_config()` function must return an empty string (not a non-zero exit) when the config file is absent — so `detect_obsidian_env()` can branch on the output without tripping `set -e`. Data-model's Option A (grep+sed) can produce empty output cleanly; calling convention confirmed.

- **What api and data-model need from integration**: The placement decision (call site at install.sh:758, after `do_theme_install`) and the `posix_quote` hoist location (D2, near line 610) are integration's deliverables. Both personas assumed "integration will confirm this" — confirmed here.

- **Test dimension** (not a separate persona in this spec's roster): The new test file structure is integration's responsibility (Option A above). The `MONSTERFLOW_APPLICATIONS_DIR` override mechanism is also an integration-owned constraint that the implementation must honor.
