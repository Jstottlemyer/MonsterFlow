# Spec Review — install-obsidian-vault-baseline

**Reviewed:** 2026-05-15
**Reviewers:** gaps requirements scope

---

## gaps

## Critical Gaps

### MR-01: Upstream scaffold structure not pinned to a contract
- **finding_id:** mr-01
- **severity:** major
- **class:** contract
- **title:** No contract pins the upstream wiki-setup directory structure
- **body:** The spec depends on `/wiki-setup` (from `Ar9av/obsidian-wiki`) producing specific directories (`concepts/`, `entities/`, `_archives/`, `_raw/`, `index.md`, `log.md`, `.obsidian/`). Both `install.sh`'s Stage B sweep and the CLAUDE.md success predicate use this 7-item list. If the upstream skill changes its output structure (adds directories, renames them, changes the threshold), MonsterFlow's marker logic silently breaks — either leaving stale markers forever or prematurely removing them.
- **suggested_fix:** Add a comment in install.sh and CLAUDE.md explicitly citing the upstream version or commit that defines this structure. Alternatively, add a `## Upstream dependencies` section to this spec documenting: (1) the skill repo, (2) the expected output contract, (3) who owns updating the predicate if upstream changes.

### MR-02: Partial wiki-setup failure leaves vault in limbo
- **finding_id:** mr-02
- **severity:** major
- **class:** architectural
- **title:** No recovery path for partial /wiki-setup failure
- **body:** Edge Case 7 addresses "1 of 5 scaffold markers" as Stage C (silent no-op). But what if `/wiki-setup` runs, creates 2 markers, then crashes mid-execution? The vault now has `concepts/` and `entities/` but nothing else. The marker remains because `scaffold_markers < 3`. The CLAUDE.md instruction keeps suggesting `/wiki-setup`. If wiki-setup is not idempotent (doesn't check for existing directories before creating), the adopter could face errors or duplicate structures. The spec doesn't address: (a) whether upstream wiki-setup is idempotent, (b) what the adopter should do if they're stuck in this state.
- **suggested_fix:** Add to Edge Cases: "Partial wiki-setup failure — upstream wiki-setup uses `mkdir -p` and is idempotent; re-running it completes the scaffold. If scaffold_markers is 1-2 after a failed run, the marker remains and CLAUDE.md continues suggesting /wiki-setup, which is the correct recovery path." If upstream is NOT idempotent, document the manual recovery steps.

---

## Important Considerations

### MR-03: Vault path with spaces not explicitly tested
- **finding_id:** mr-03
- **severity:** minor
- **class:** tests
- **title:** No test case for vault path containing spaces
- **body:** The bash code uses `$resolved_path` in `find` and `touch` commands. While the code appears to quote variables properly, macOS users commonly have paths like `~/Documents/Obsidian Vault/wiki`. None of the 6 test cases exercise this path shape. A quoting bug in the shell code would pass all tests but fail in the wild.
- **suggested_fix:** Add test case 7: vault path is `$TMPDIR/Obsidian Vault Test/wiki` (space in middle component). Assert marker written correctly, path logged correctly with quotes, no word-splitting errors.

### MR-04: CLAUDE.md instruction has no enforcement or observability
- **finding_id:** mr-04
- **severity:** minor
- **class:** documentation
- **title:** CLAUDE.md preflight relies on Claude's compliance with no fallback
- **body:** The spec's UX flow depends on Claude reliably checking `$OBSIDIAN_VAULT_PATH/.scaffold-pending` before wiki commands. Claude is non-deterministic; long sessions or complex prompts may cause it to skip the preflight check. The spec has no observability into whether the check happened, no logging, and no fallback if Claude proceeds without checking. The belt-and-suspenders sweep only catches this on the NEXT install.sh run, which could be weeks later.
- **suggested_fix:** This is likely acceptable for personal tooling, but acknowledge in Notes or Edge Cases: "If Claude ignores the CLAUDE.md instruction, the marker persists until the next install.sh run or manual deletion. No user-facing harm occurs — wiki commands may fail with 'directory not found' errors, which are self-explanatory."

### MR-05: Race condition between Claude marker removal and concurrent sessions
- **finding_id:** mr-05
- **severity:** minor
- **class:** contract
- **title:** Two concurrent Claude sessions could race on marker check/remove
- **body:** If the adopter has two Claude sessions open (e.g., one in MonsterFlow, one in another project), both might check the marker, both suggest `/wiki-setup`, and both attempt to remove it. The removal itself is safe (rm is idempotent), but the UX is confusing — both sessions claim "marker removed" or one fails silently. More problematic: if both suggest /wiki-setup and the user runs it in both, upstream wiki-setup runs twice (may or may not be idempotent).
- **suggested_fix:** Add to Edge Cases: "Concurrent Claude sessions — marker removal is idempotent (rm -f). If /wiki-setup runs twice, upstream's mkdir -p pattern makes this safe. The UX may be confusing (both sessions suggest the same action), but no data corruption occurs."

### MR-06: No test for `$OBSIDIAN_VAULT_PATH` unset vs empty string
- **finding_id:** mr-06
- **severity:** minor
- **class:** tests
- **title:** Edge case distinction between unset and empty-string env var not tested
- **body:** The helper calls `parse_obsidian_config` which reads from `~/.obsidian-wiki/config`. But the CLAUDE.md instruction references `$OBSIDIAN_VAULT_PATH` directly. If the adopter has `export OBSIDIAN_VAULT_PATH=""` (empty string) vs the variable being unset, behavior may differ. The spec's test cases always pre-stage the config file; none test the "config exists but env var is weird" state.
- **suggested_fix:** Clarify in Integration: "`parse_obsidian_config` is the canonical source; the `$OBSIDIAN_VAULT_PATH` env var is only set by the sentinel block in `.zshrc` which sources the config. Direct manipulation of the env var is unsupported." Optionally add a defensive test.

---

## Observations

### MR-07: doctor.sh omission is deliberate and documented
- **finding_id:** mr-07
- **severity:** nit
- **class:** scope-cuts
- **title:** doctor.sh row explicitly deferred (Q9 reference)
- **body:** The spec explicitly notes "doctor.sh row for this marker (Q9 decision held: scaffold-once action, not ongoing state)" in Out of Scope. This is reasonable — the marker is transient and not worth ongoing health-check overhead.
- **suggested_fix:** None needed; this is a well-reasoned deferral.

### MR-08: No versioning on marker file
- **finding_id:** mr-08
- **severity:** nit
- **class:** scope-cuts
- **title:** Marker file has no version or metadata
- **body:** The marker is 0-byte. If the scaffold predicate changes in the future (e.g., upstream adds a new required directory), old markers from pre-change installs would be evaluated against the new predicate. This could cause false "already scaffolded" or false "not yet scaffolded" results.
- **suggested_fix:** Acceptable for V1. If this becomes a problem, future spec can add a version number to the marker file content (e.g., `echo "1" > .scaffold-pending`).

### MR-09: `find` command could behave differently on Linux
- **finding_id:** mr-09
- **severity:** nit
- **class:** documentation
- **title:** find flags are POSIX but behavior may vary
- **body:** The `find ... -mindepth 1 -maxdepth 1 ! -name ...` pattern is portable, but some BSD/GNU find implementations handle symlinked directories differently. The spec targets macOS (explicit in Manual acceptance), but MonsterFlow could have Linux adopters.
- **suggested_fix:** Add to Notes or Edge Cases: "Tested on macOS; Linux users should verify find behavior if vault is on an unusual filesystem."

---

## Verdict

**PASS WITH NOTES**

The spec is thorough and V3 addresses all prior blockers. The missing requirements identified are primarily edge-case documentation and test coverage gaps, not architectural holes. MR-01 (upstream contract) and MR-02 (partial failure recovery) are the most important to address before ship — both are documentation/contract-class fixes that require ~2-3 sentences each, not code changes. The remaining items are minor hardening that can ship in a follow-up or be accepted as known limitations for personal tooling.

---

## requirements

## Requirements Completeness Review — `install-obsidian-vault-baseline` V3

---

### Critical Gaps

None that block implementation of the core mechanism. The spec is precise enough to build from.

---

### Important Considerations

**1. CLAUDE.md instruction placement — scope mismatch (class: architectural, severity: major)**

The spec places the new paragraph in `~/Projects/MonsterFlow/CLAUDE.md` (project-local). Claude loads project-level CLAUDE.md files only when opened in that directory. Wiki commands (`/wiki-update`, `/wiki-query`, `/wrap`'s Phase 2c) are invoked from *any* project context (career/, CosmicExplorer/, etc.). In those sessions, MonsterFlow's CLAUDE.md is not loaded, so the preflight check is silently skipped — the marker exists but Claude never sees the instruction to act on it.

The instruction should target a globally-loaded config: `~/CLAUDE.md` (which IS loaded cross-project per session context) or should be written by install.sh to `~/.claude/CLAUDE.md`. The spec says "for MonsterFlow we'll add the instruction to MonsterFlow's own CLAUDE.md" without acknowledging this scope constraint.

**Suggested fix:** Target `~/CLAUDE.md` (the global user config already loaded in all projects) rather than the MonsterFlow project-local file. Alternatively, have install.sh append a sentinel-bracketed block to `~/CLAUDE.md` using the same idempotency pattern already used for `~/.zshrc`.

---

**2. "5 scaffold markers" vs "7 scaffold markers" — internal inconsistency (class: documentation, severity: major)**

Edge Case #7 reads: *"Vault has 1 of the **5** scaffold markers (e.g., only `concepts/`)"*. But the bash code loops over 7 items (`concepts entities _archives _raw index.md log.md .obsidian`), the CLAUDE.md success predicate lists the same 7, and test case 4 sets up 7 scaffold markers. The count "5" is stale and wrong. An implementer reading Edge Case #7 in isolation would write the wrong loop.

**Suggested fix:** Replace "1 of the 5 scaffold markers" with "1 of the 7 scaffold markers" throughout.

---

**3. `parse_obsidian_config` failure path has no test coverage (class: tests, severity: major)**

The helper function silently returns 0 when `parse_obsidian_config` fails (`|| resolved_path=""`). This is correct behavior, but none of the 6 test cases exercises it: all cases pre-stage either a fresh run (config written during run) or a pre-existing config. The case where config exists but `parse_obsidian_config` exits non-zero (malformed config, missing key, etc.) is untested. Given that the helper's entire correctness hinges on this parse step, a 7th case ("config file present but parse fails → silent return, no marker written, no error") would close the gap.

---

### Observations

**4. CHANGELOG version is ambiguous (class: documentation, severity: nit)**

The spec says `[0.15.0]` (or current minor) — the parenthetical makes the acceptance criterion non-deterministic. The "shipped" checklist should either pin the version or state the rule for determining it ("increment current `VERSION` minor").

---

**5. `add_install_warning` function contract is assumed, not verified (class: contract, severity: nit)**

The spec calls `add_install_warning` for the read-only vault path (test case 6) and references it as "per existing pattern." If the function signature or buffer name in install.sh differs, the warning silently drops. Worth adding a one-line cross-reference (install.sh:LINE) or quoting the function signature alongside the call in the spec.

---

**6. Test harness lacks bash 3.2 compatibility notes (class: tests, severity: nit)**

The spec says "modeled on `test-install-knowledge-layer.sh`" but doesn't carry forward the bash 3.2 constraints this codebase has documented: avoid `${array[-1]}`, avoid `export -f`, use PATH-stub mocking, pin `BASH=/bin/bash`. For a 180 LoC harness, an explicit statement that it must pass under `/bin/bash` (bash 3.2, macOS system) would prevent the known class of failures seen in earlier test iterations.

---

**7. Stage C (user content, not scaffolded) has no explicit test assertion (class: tests, severity: nit)**

The spec describes Stage C as "silent no-op (intentional)." Test case 2 covers the "has `notes.md`" variant, but the assertion is "no marker written" — it doesn't also assert no INSTALL_WARNINGS entry, no `rm` of existing user content, and exit 0. Adding those explicit assertions to test 2 would make the Stage C invariant machine-verifiable rather than implicit.

---

### Verdict

**PASS WITH NOTES** — The core mechanism (marker write/sweep, CLAUDE.md hint, belt-and-suspenders on rerun) is buildable as written. Finding #1 (CLAUDE.md placement) is the load-bearing issue: the feature's runtime path depends on Claude seeing the instruction, and project-local CLAUDE.md placement silently voids it for the majority of wiki-command invocations. Addressing that placement before `/build` avoids shipping a feature that appears to work in MonsterFlow sessions but silently does nothing everywhere else.

---

## scope

## Scope Analysis — install-obsidian-vault-baseline (V3)

---

### Critical Gaps

**[SC-01] Hardcoded upstream directory names with no version pin**
- **class:** contract · **severity:** major
- The success predicate in both `install.sh` (Stage B) and `CLAUDE.md` hardcodes `concepts/`, `entities/`, `_archives/`, `_raw/`, `index.md`, `log.md`, `.obsidian/` — names owned by the upstream `Ar9av/obsidian-wiki` skill. The spec doesn't pin a commit hash, tag, or version of that upstream. If upstream renames `_archives/` to `archive/` or splits `.obsidian/` into a subdirectory, Stage B silently fails to sweep the marker and CLAUDE.md's cleanup check never fires — adopter is permanently stuck with a stale `.scaffold-pending`.
- **Suggested fix:** Add a `# upstream: Ar9av/obsidian-wiki @ <commit-or-tag>` comment beside the predicate lists in both files, and note the version in the spec. Alternatively, relax the predicate to `≥3 non-cruft entries of any kind` (vault has content → probably post-/wiki-setup), accepting that it won't fire on a vault with exactly 2 personal files.

---

### Important Considerations

**[SC-02] Stage C leaves pre-existing-vault adopters with zero guidance**
- **class:** scope-cuts · **severity:** minor
- An adopter who already has personal Obsidian notes (Stage C: `non_cruft_count > 0`, `scaffold_markers < 3`) gets a silent no-op. They then open Claude, run `/wiki-update` or `/wiki-query`, and get wiki-skill failures — with no pointer to `/wiki-setup`. The spec explicitly punts this: "adopter's content, not our concern." That's a defensible call, but it's worth confirming: the post-ship stakeholder ask-rate for "why does wiki-* fail on my existing vault?" is predictable.
- **Suggested fix** (if desired): Add a no-op-with-hint path — if `non_cruft_count > 0` but `scaffold_markers < 3`, write to `INSTALL_NOTES` (not `INSTALL_WARNINGS`) that wiki-structure is absent and `/wiki-setup` can add it non-destructively. This is a one-liner and doesn't cross into Stage A's marker semantics.

**[SC-03] CLAUDE.md "/wiki-setup not available" branch is partial implementation of the sibling spec**
- **class:** documentation · **severity:** minor
- The CLAUDE.md paragraph includes: *"If /wiki-setup is not available… surface the marker once with a one-line note and proceed."* This branch exists solely to handle the gap that `install-obsidian-wiki-auto-clone` fills. Once that sibling spec ships, the branch becomes dead guidance — and the framing ("future spec") ages poorly as prose. It's also mildly contradictory: CLAUDE.md says "proceed with wiki-related ask using whatever capability is installed" while a `.scaffold-pending` marker means the capability isn't installed.
- **Suggested fix:** Trim the unavailable-/wiki-setup branch to a single sentence: *"If /wiki-setup is unavailable, surface the marker as a one-line note."* The full resolution belongs in the sibling spec, not here.

---

### Observations

- The spec's scope trajectory (V1 → V2 → V3) is exemplary. V2 correctly identified that install.sh was trying to own work that belongs to upstream, and V3 fixed the remaining anchor/predicate issues. The result is a genuinely minimal deliverable: ~25 LoC in install.sh, ~12 lines in CLAUDE.md, one new test file.
- **Belt-and-suspenders sweep (Stage B)** adds complexity for a failure mode (Claude forgetting to delete the marker) that CLAUDE.md already handles. It's defensible for idempotency guarantees, but could be cut entirely without affecting first-install or post-/wiki-setup correctness. Flagging as a future deferral candidate, not a blocker.
- **Test case 6 (read-only vault)** added in V3 is appropriate — it's not scope creep, it's gap-closing for a real edge on shared/networked filesystems.
- `parse_obsidian_config` is referenced in the spec but not shown. Confirm it exists in install.sh before `/build` starts; the spec assumes it, but if it's named differently the helper silently falls through.
- The `wc -l | tr -d ' '` idiom for `non_cruft_count` is correct on BSD and GNU — no portability concern.

---

### Verdict

**PASS WITH NOTES** — SC-01 (hardcoded upstream names with no version pin) is the one finding worth addressing before `/build`: a one-line version comment and a decision about predicate flexibility closes it. SC-02 and SC-03 are minor and can be addressed inline during implementation without revisiting the spec.

