OVERALL_VERDICT: GO_WITH_FIXES

---

# Plan Checkpoint Review — install-obsidian-vault-baseline

## Reviewer Verdicts

| Reviewer | Verdict | Blocking Findings | Key Concern |
|----------|---------|-------------------|-------------|
| Risk Assessment | FAIL | 2 | Unverified global CLAUDE.md loader contract; global config mutation without consent/backup |
| Completeness | FAIL | 3 | Missing tests for CLAUDE.md mutation; parallel agents modifying same file; VERSION bump missing |
| Scope Discipline | PASS WITH NOTES | 0 | Spec/plan target mismatch needs orchestrator clarification |

---

## Must Fix

### 1. Unverified global CLAUDE.md loader contract (architectural)
**Sources:** ra-02

The entire feature depends on Claude loading `~/CLAUDE.md` for sessions outside MonsterFlow. This is stated as fact but never verified. If Claude only loads project-local CLAUDE.md files, the feature silently fails for its primary use case (wiki commands from career/, CosmicExplorer/, etc.).

**Required action:** Before implementing, verify the loader contract:
1. Create `~/CLAUDE.md` with a test instruction
2. Open Claude in a different project directory  
3. Confirm Claude reads and acts on the instruction

If not loaded, pivot to alternative approach (symlinks, per-project injection, or marker-only with manual doc reference).

---

### 2. Global CLAUDE.md mutation lacks consent, backup, and uninstall (security)
**Sources:** ra-01, SF-2, SD-03

Writing installer-managed content to `~/CLAUDE.md` affects AI behavior in every project. No consent prompt, no backup, no documented removal mechanism. Per project MEMORY ("install.sh: backup configs + ship uninstall.sh + opinionated-changes banner"), this pattern requires explicit safeguards.

**Required action:**
1. Add backup: `cp ~/CLAUDE.md ~/CLAUDE.md.bak.$(date +%s)` before first modification
2. Add info line to install.sh output when block is appended: `"APPENDED: ~/CLAUDE.md — wiki-preflight instruction (remove <!-- BEGIN MonsterFlow wiki-preflight --> block to undo)"`
3. Enhance sentinel block with removal guidance

---

### 3. Parallel agents targeting same file (architectural)
**Sources:** MF-2

Wave 1.1 and 1.2 are marked parallelizable but both modify `install.sh` at adjacent anchor points (:896, :897). Per project MEMORY ("Parallel agents — no shared-file appends, no global git ops"), this is the exact scenario that caused stray-file artifacts previously.

**Required action:** Collapse 1.1 + 1.2 into a single sequential task, or make 1.2 explicitly depend on 1.1 completion.

---

### 4. Duplicated scaffold predicate guarantees drift (contract)
**Sources:** ra-03

The "≥3 of 7 markers" predicate is hardcoded in two independent locations (install.sh and ~/CLAUDE.md prose) with no single source of truth. Per project MEMORY ("Schema bumps need a grep-test for prose drift"), this is a documented failure mode.

**Required action:** Either:
- Have install.sh write the marker list into the marker file, and CLAUDE.md instruction reads from file
- Add grep-test to `tests/run-tests.sh` that fails if marker lists diverge

---

### 5. VERSION file increment missing (contract)
**Sources:** MF-3

Wave 4.3 references `[0.15.0]` CHANGELOG entry but no task updates the VERSION file. This breaks the versioning contract ("VERSION file is source of truth").

**Required action:** Add Wave 4.0 task: `echo "0.15.0" > VERSION`

---

### 6. Spec/plan target mismatch (documentation)
**Sources:** ra-06, SF-3, SD-01

Spec says "MonsterFlow's CLAUDE.md"; plan targets `~/CLAUDE.md`. Build agents following the spec will write to the wrong location.

**Required action:** Either update spec V4 to authorize `~/CLAUDE.md` mutation, or add explicit note at Wave 1.2 top: "Target is `~/CLAUDE.md` (global), NOT MonsterFlow's project-local CLAUDE.md — see D2."

---

### 7. No tests for CLAUDE.md mutation function (tests)
**Sources:** MF-1, ra-04, SD-02

`append_wiki_preflight_instruction()` mutates a globally-loaded file. Zero test coverage for: idempotency, preservation of existing content, creation from scratch, or handling of unwritable file.

**Required action:** Add test cases 9-12:
- case_9: idempotency (run twice, sentinel appears exactly once)
- case_10: existing content preserved
- case_11: missing ~/CLAUDE.md created with correct content
- case_12: read-only ~/CLAUDE.md logs warning, exits 0

---

## Should Fix

| Finding | Class | Summary |
|---------|-------|---------|
| SF-1 | documentation | BACKLOG.md update incomplete — missing v0.12.0 follow-up note update |
| SF-4 | architectural | Codex adversary High findings have no disposition table |
| ra-05 | contract | Upstream wiki-setup idempotency assumed, not verified |
| N-1/ra-08 | tests | Stage C negative test missing (marker + user content below threshold) |
| N-3 | documentation | Wave 1.3 LoC estimate undercounted (says ~2, actually ~3-4) |

---

## Decision Path

All three reviewers agree the fundamental approach (marker file + CLAUDE.md instruction) is sound. The blockers are:

1. **Verification gap** (ra-02) — a pre-implementation validation step, not architectural rework
2. **Safety gap** (ra-01) — one-liner backup + info message, not redesign
3. **Process gap** (MF-2) — task sequencing fix, not code change
4. **Invariant gap** (ra-03) — add grep-test or single-source pattern, ~10 LoC
5. **Contract gap** (MF-3) — one-liner VERSION bump
6. **Documentation gap** (ra-06) — clarify in orchestrator prompt or spec
7. **Test gap** (MF-1) — ~40 LoC of additional test cases

None require fundamental architectural rework. All are surgical edits addressable in the current build wave structure. The scope expansion from spec (MonsterFlow CLAUDE.md) to plan (~/CLAUDE.md) is correct per R1 but needs explicit acknowledgment.

**Recommendation:** Address all Must Fix items before dispatching build agents. The verification step (ra-02) should be a Wave 0 pre-flight; if it fails, the plan pivots to an alternative approach before any code is written.

---

