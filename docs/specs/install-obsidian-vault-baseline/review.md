# review — install-obsidian-vault-baseline V2 (iteration 2 of 3)

**Reviewers:** gaps (opus), requirements (sonnet), scope (sonnet), codex-adversary
**Gate mode:** permissive (frontmatter)
**Dispatched:** 3 Claude personas (budget=3) + Codex (additive)
**Verdict:** FAIL — 2 new architectural blockers (hook anchor location); V1's 5 blockers all resolved in substance

## Overall health: Concerns (much improved from V1)

V2 successfully resolves all 5 V1 architectural blockers in substance — three Claude reviewers and Codex all confirm this. The reshape (defer scaffolding to upstream `/wiki-setup`, install.sh writes a 0-byte marker only) is structurally sound. But Codex caught two new architectural mistakes that all 3 Claude reviewers missed because they couldn't read `install.sh:905` carefully enough: the proposed hook anchor at install.sh:935 is INSIDE the `else` branch of `if [ -f "$config" ]; ... else ... fi`. On every install.sh re-run after the first, that branch is skipped — meaning the spec's claimed "stale-marker sweep on subsequent runs" (test case 5) is structurally impossible at the proposed anchor.

This is the same pattern as V1: Claude reviewers validate the spec against itself; Codex validates the spec against the actual install.sh source. The pipeline is doing what it's designed to do.

## V1 Blocker Carry-Forward

| V1 Blocker | Status in V2 | Confidence |
|---|---|---|
| B1 `.manifest.json` invented | RESOLVED — V2 doesn't write a manifest at all | 4/4 reviewers agree |
| B2 `~/.zshenv.local` invented | RESOLVED — V2 doesn't touch config files | 4/4 |
| B3 hook point too late | **RENAMED, NOT FULLY FIXED** — anchor is now in the wrong branch; sweep can't fire on re-run | 1/4 (Codex only) |
| B4 non-interactive contradiction | RESOLVED — V2 preserves install_obsidian_env's existing behavior verbatim | 4/4 |
| B5 5-file scaffold under-delivered | RESOLVED — V2 doesn't scaffold; upstream owns it | 4/4 |

## Before You Build (2 blockers)

### B1 — install.sh:935 anchor is inside `else { config absent }`; sweep can't fire on re-run
- **Severity:** blocker
- **Class:** architectural
- **Convergence:** Codex (sole catch; all 3 Claude agents missed this because the line-numbered claim looked plausible without re-reading install.sh:905-941)
- **Body:** `install_obsidian_env()` at install.sh:905-906 wraps the entire config-write + path-prompt + soft-warn block in `if [ -f "$config" ]; then : (no-op); else <work>; fi`. The proposed insertion point at install.sh:935 sits inside the `else` body. On install.sh re-runs (`bash install.sh` again), the config exists, the `else` branch is skipped, and the marker write/sweep code never runs. AC5 ("stale-marker sweep on subsequent runs") is structurally impossible at this anchor.
- **Fix:** Refactor the marker logic into a helper that resolves `vault_path` from `parse_obsidian_config` AFTER the `if [ -f "$config" ]` block closes. Pseudo-target: insert around install.sh:970 (after the sentinel-block append, before function return). Or extract the marker logic into its own helper `manage_scaffold_marker()` that's called unconditionally with the resolved path.

### B2 — Spec contradicts itself on insertion order
- **Severity:** blocker
- **Class:** documentation (but it papers over the B1 architectural issue)
- **Convergence:** Codex (sole catch)
- **Body:** Scope section says insert "after config write + `~/.zshrc` sentinel append" (which would be ~line 970+). Integration section says insert at install.sh:935 (which is BEFORE both the atomic config write at line 941 and the sentinel append at line 948). These two statements describe two different anchors. The `/build` agent reading this spec will pick one — and depending on which, may end up with the wrong placement.
- **Fix:** Pick one anchor (per B1 fix above, after the conditional block at ~line 970). Update BOTH Scope and Integration to match. Drop the line-935 anchor entirely or move it.

## Important But Non-Blocking (3 items)

### I1 — CLAUDE.md "check on session start" is too weak as a trigger
- **Severity:** major
- **Class:** documentation
- **Convergence:** Codex (sole catch)
- **Body:** The CLAUDE.md instruction says Claude should check `$OBSIDIAN_VAULT_PATH/.scaffold-pending` "when you start a session." But Claude doesn't proactively inspect filesystem state unprompted — it reads CLAUDE.md but doesn't routinely stat files until a user request triggers relevant behavior. The instruction needs to be reframed as a *preflight check for wiki-related commands*, not a generic session-start action.
- **Fix:** Rewrite the CLAUDE.md paragraph to: "Before responding to any wiki-* command (`wiki-update`, `wiki-query`, `wiki-ingest`, `wiki-capture`) OR before `/wrap`'s Phase 2c wiki integration, check whether `$OBSIDIAN_VAULT_PATH/.scaffold-pending` exists. If yes, suggest the adopter run `/wiki-setup` first." Removing "when you start a session" eliminates the unenforceable contract.

### I2 — `/wiki-setup` success predicate (`.env` requirement) may not match upstream output
- **Severity:** major
- **Class:** contract
- **Convergence:** Codex (sole catch)
- **Body:** V2's CLAUDE.md instruction tells Claude that `/wiki-setup` succeeded when the vault has `concepts/, entities/, _archives/, _raw/, .env`. But upstream `wiki-setup` (`~/Projects/obsidian-wiki/.skills/wiki-setup/SKILL.md`) creates `index.md`, `log.md`, `.obsidian/app.json`, and `.obsidian/appearance.json` as part of its core flow; `.env` is described in a separate Step 1 that asks the user about `OBSIDIAN_VAULT_PATH`, `OBSIDIAN_SOURCES_DIR`, etc. — and may write the `.env` to the obsidian-wiki tool repo, NOT to `$OBSIDIAN_VAULT_PATH`. If Claude waits for `$vault/.env`, it may never remove the marker after a valid /wiki-setup completion.
- **Fix:** Change the success predicate to: `concepts/, entities/, _archives/, _raw/, index.md, log.md, .obsidian/`. Drop `.env` from the predicate. Verify by reading the upstream skill before /build.

### I3 — Test case 5 (stale-marker sweep) doesn't exercise the realistic rerun path
- **Severity:** major
- **Class:** tests
- **Convergence:** Codex (sole catch)
- **Body:** Test case 5 as written would pre-stage `.scaffold-pending` + scaffold markers in a test vault and run a fresh install.sh from a clean `~/.obsidian-wiki/config`-absent state. The realistic re-run path is: config EXISTS (from prior install.sh run) + vault is now scaffolded + leftover `.scaffold-pending` from initial run. The test as currently scoped won't exercise the B1 problem.
- **Fix:** Add explicit test setup: pre-stage `~/.obsidian-wiki/config` pointing at a populated `concepts/`-bearing vault that also has `.scaffold-pending`. Run install.sh. Assert marker removal.

## Observations (5 non-blocking)

- **O1** — CLAUDE.md edit lives in MonsterFlow's repo only. Claude sessions launched from `$OBSIDIAN_VAULT_PATH` (a natural spot for `wiki-*` work) won't see MonsterFlow's CLAUDE.md. Consider also writing the instruction to `$OBSIDIAN_VAULT_PATH/CLAUDE.md` if absent (Codex gaps).
- **O2** — No doctor.sh fallback for adopters who decline /wiki-setup and forget the marker exists; the marker becomes invisible state. Q9 decided "no doctor row" — Codex agrees that's fine but flags the trade-off.
- **O3** — Edge Case 3 prescribes `INSTALL_WARNINGS` behavior for read-only vaults, but the 5-case harness doesn't test it AND the code block in the spec has no `||` guard for `touch` failure. Either add a test or drop the EC3 contract.
- **O4** — The marker cleanup is dual-owned (Claude rms after /wiki-setup + install.sh sweep on re-run). Spec should explicitly call this out as a design choice with rationale, not leave it implicit (scope).
- **O5** — Stage C (vault has user content but isn't scaffolded) is a silent no-op. Spec should document whether the silence is intentional and whether the adopter gets any signal (scope).

## Reviewer Verdicts

| Dimension | Verdict | Key Finding |
|-----------|---------|-------------|
| Gaps (opus) | PASS WITH NOTES | CLAUDE.md instruction has no enforcement; cross-repo coverage; EC3 untested |
| Requirements (sonnet) | PASS WITH NOTES | V1 carry-forward all resolved; G1 CLAUDE.md grep-test missing; G2 EC3 test gap |
| Scope (sonnet) | PASS | V1 carry-forward all resolved; IC1 dual-cleanup design implicit; IC2 Stage C silence |
| Codex (adversary) | FAIL | B1 hook anchor in wrong branch; B2 spec self-contradiction on insertion order |

## Conflicts Resolved

No agent disagreements. Three Claude reviewers all agreed V2 substantively resolves V1 blockers and called it PASS WITH NOTES / PASS. Codex extends with two architectural findings none of the Claude agents could see from the spec text alone (requires reading install.sh:905's surrounding control flow). Pattern is identical to V1 — `feedback_codex_catches_plan_vs_reality_drift` is now twice-validated in this single smoke-test session.

## Smoke-test markers (V2 iteration)

This iteration validated:
1. **Persona-metrics rotation** — prior `findings.jsonl` rotated to `findings-2026-05-15T07-27-30Z.jsonl`, prior `raw/` rotated to `raw-iter1/`. Clean separation between iterations 1 and 2.
2. **SEC-04 baseline-drift refusal** — V2's first commit lied about `tags_provenance.baseline` (recorded just `[integration]`); resolver refused to dispatch with `recorded != recomputed` error. Defensive guard fired correctly. Required a follow-up commit to fix.
3. **Budget=3 still capping** — same 3 Claude personas dispatched (gaps, requirements, scope) + Codex additive. Consistent across iterations.
4. **mkdir hoist + atomic writes** — all 4 raw outputs landed cleanly. No "Error writing file."
5. **Codex value-add** — V1: 5 architectural blockers caught. V2: 2 architectural blockers caught. Both runs: blockers exclusively from Codex (Claude blind to install.sh source); ergonomic findings (AC sharpening, log-message wording) caught by Claude agents.

## Verdict: FAIL

The reshape is structurally correct. The execution detail (install.sh anchor location) has a single critical bug: V2 placed the marker logic inside an if-branch that only fires on first install. Fixing this requires moving the helper call outside the conditional and resolving `vault_path` independently — about 5 LoC of additional bash. Plus the I1-I3 polish.

Estimated revision time: 20-30 minutes. The spec is close enough to PASS that a V3 cycle would likely succeed.

**Recommended next step:** revise spec to fix B1 (move anchor) + B2 (resolve internal contradiction) + I1 (reframe CLAUDE.md preflight) + I2 (drop `.env` from success predicate) + I3 (test 5 setup). Then either (a) re-run /spec-review for iteration 3 (within the gate_max_recycles cap of 3), or (b) declare smoke-test done — the goal was validating the pipeline, not shipping this specific spec.
