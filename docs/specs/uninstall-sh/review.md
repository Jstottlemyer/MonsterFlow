# uninstall-sh — Spec Review (rev2)

**Reviewed:** 2026-05-13 (rev2; rev1 review preserved at `review-rev1.md` reference below)
**Reviewers:** gaps (opus) · requirements (sonnet) · scope (sonnet) · codex-adversary
**Gate mode:** permissive
**Overall health:** Concerns (rev1 architectural blockers cleared; remaining items mostly contract/tests/scope-cuts class)

---

## Summary

The rev1 → rev2 pivot to manifest-first + detector-fallback hybrid landed cleanly at the Claude-reviewer layer: **all 17 rev1 findings across gaps/requirements/scope are marked resolved**. Codex's adversarial pass surfaces 6 HIGH-class findings that are mostly refinements within the new architecture (not architecture-rejection). Under permissive gate-mode classification, the load-bearing question is which of Codex's findings are true architectural vs contract/documentation. Read carefully, 2 of the 6 are genuinely architectural; the other 4 are contract/documentation/scope drift inside prereqs.

---

## Before You Build (2 items — architectural)

**A1 — Manifest lifecycle / idempotency** (Codex C1; class: architectural)

Spec says manifest is append-only and "never modified post-install" (line 80-82 of spec.md), but idempotent re-run expects "Nothing to remove" output. With no tombstone semantics, the second `--apply` reprocesses the same rows. Fix needed in this spec: define the post-apply manifest handling. Recommended: `--apply` finishes with `mv ~/.claude/.monsterflow-install-manifest.jsonl ~/.claude/.monsterflow-install-manifest.uninstalled.<ts>`. AC8 (idempotency) becomes "no manifest present → exit 0 with canonical 'Nothing to remove'." Forensic trail preserved at the timestamped path.

**A2 — `created_file` reversal policy for user-edited files** (Codex C4; class: architectural)

`~/CLAUDE.md` written via `op:created_file` may be edited by the user post-install. Spec doesn't say what reversal does. Blind delete = data loss; checksum-only "leave if modified" creates a half-uninstall ambiguity and would fail AC6 (round-trip diff) if the user's edits aren't in the snapshot. Fix needed: explicit policy. Recommended: delete only if current SHA256 matches install-recorded `created_sha256`; on mismatch, preserve the file in place AND move the managed-block strip to its standard sentinel-strip path (i.e., the file becomes "user-owned with no managed content"). AC6 needs a parallel "user-edited" variant.

---

## Important But Non-Blocking (10 items — contract / tests / scope-cuts)

These route to `followups.jsonl` under permissive gate mode; `/build` wave 1 consumes them as `build-inline` or `docs-only` tasks.

### Contract findings (warn route)

**I1 — Manifest schema normalization** (Codex C5)

Field names inconsistent across the spec: `backup` vs `backup_path` vs `backup_sha256`; `append_block` vs `appended_block`; `sha256` vs `block_sha256` vs `created_sha256`. Fix in this spec: publish one normative schema table with required/optional fields per op. Examples in Approach + Data&State must conform.

**I2 — Multi-clone manifest path collision** (Gaps G-N2)

Manifest at fixed `~/.claude/.monsterflow-install-manifest.jsonl` — if user clones MonsterFlow into two separate `$REPO_DIR`s and runs install.sh from each, both append to the same file. Edge case 13 reverses chronologically but doesn't address `src` paths pointing into a different `$REPO_DIR` than the one running uninstall. Fix options: (a) include `repo_dir` per manifest row + filter by `$REPO_DIR` match; (b) explicit OOS in spec; (c) refuse-with-warning when manifest contains rows from a different `$REPO_DIR`. Lean: (a) + add an AC.

**I3 — Migration path for pre-manifest installs** (Gaps G-N1)

Acknowledged in OQ#2 but the spec's "safe restore" guarantees apply to manifest-mode only; cold-start trades safety for cold-start support. State this explicitly in Scope so adopter expectations are calibrated.

**I4 — AC18 missing `$dst` disposition** (Requirements CG-NEW-2)

AC18 says "refuse-restore; symlink still removed. Exit 0" but doesn't assert `$dst` is gone post-apply. Add `test ! -L "$dst" && test ! -e "$dst"`, plus "backup file remains untouched at manifest-recorded path."

**I5 — AC11 omits `~/.obsidian-wiki/config` from continuing-operations list** (Requirements IC-NEW-1)

The "continuing operations" enumeration in AC11 should explicitly state whether obsidian config removal proceeds or aborts when zshrc strip fails.

**I6 — Manifest file itself not in "uninstall removes" list** (Gaps G-N4)

Either remove it (recommend: rename to `.uninstalled.<ts>` per A1) or explicitly OOS.

### Tests-class findings (warn route)

**I7 — Split AC19 into AC19a/b/c/d** (Requirements CG-NEW-1)

5-scenario omnibus AC will produce a flaky or oversized test. Either split or require labeled sub-case emissions.

**I8 — Split AC20 into AC20a/b/c** (Requirements CG-NEW-3)

3-fixture omnibus. Same fix shape as I7.

### Scope-cuts findings (warn route)

**I9 — Prereq #5 granularity** (Scope S-IC1; also overlaps Codex's "prereq #5 missing git-hook uninstall mode")

Prereq #5 bundles four concerns of unequal weight: (a)+(b) deep `claude-md-merge.py` surgery, (c) ~10-line banner update, (d) optional symlink-backup, AND (per Codex) `scripts/install-hooks.sh --uninstall` mode. Either split into 2-3 prereqs OR label (a)+(b) as the only blocking items + treat (c)/(d)/(e) as non-blocking riders. Codex's specific point on git-hook prereq: add to #5's required list (currently missing) OR carve a `#6 install-hooks-uninstall-mode`.

**I10 — Detector-fallback should be sunset, not indefinite** (Codex finding)

Substring heuristics `/MonsterFlow/` or `/claude-workflow/` are acceptable for cold-start rescue but not permanent. Add to OQ or Scope: detector-fallback supported for 1-2 releases post-prereq #4; then require manifest. Add a `migrate-to-manifest` path (this becomes prereq #4's scope, flag there).

---

## Observations (8 nits)

- **O1 — AC4 wording** ("newest-by-name backup recorded in manifest wins") implies filename-sort tiebreaker that doesn't exist. Rephrase to "manifest-named backup is restored."
- **O2 — AC6 cross-spec test** should guard with `SKIP_CROSS_SPEC` when prereq #5 not on test machine.
- **O3 — AC17 "exits 0"** should note it assumes no other failures in the same run (avoid apparent contradiction with AC19 partial-apply → exit 1).
- **O4 — AC15 hint strings should be script constants**, not inline literals, so grep is resilient to wording drift.
- **O5 — `created_at` in manifest rows not consumed anywhere** — Edge case 13 reverse-chronological ordering doesn't pin a driving field. Pin in prereq #4 blueprint.
- **O6 — Edge case 11 (`~/.zshrc` is symlink)** doesn't address read-only/root-owned target. Falls out as exit-1 partial failure but worth /blueprint thought.
- **O7 — `tags: []`** leaves /wrap-insights Phase 1c with no signal for uninstall-class specs. Follow-up enum extension if more uninstall-style specs land.
- **O8 — AC21/AC22 cross-cutting** overlap with prereq #5 tests — fine for belt-and-suspenders but worth flagging.

---

## Reviewer Verdicts

| Dimension | Verdict | Key Finding |
|-----------|---------|-------------|
| Requirements | PASS WITH NOTES | All rev1 resolved; 3 new omnibus-AC issues (split AC19/AC20; AC18 disposition) — tests/contract class |
| Gaps | PASS WITH NOTES | All 4 rev1 G-findings resolved; multi-clone manifest collision + migration path acknowledgement — contract class |
| Scope | PASS WITH NOTES | All 5 rev1 S-findings resolved; prereq #5 granularity / git-hook prereq decomposition — scope-cuts class |
| Codex (adversarial) | "not ready until manifest lifecycle, schema normalization, created-file reversal, prereq hook ownership fixed" | 6 HIGH findings; under classification 2 are architectural (A1 + A2), 4 route to contract/scope/documentation |

---

## Conflicts Resolved

**Codex's "rev2 not ready" verdict vs Claude reviewers' "PASS WITH NOTES":**

Codex maintains the strongest adversarial stance. Reading the 6 HIGH findings under `commands/_gate-mode.md` classification precedence:

- **C1 (manifest idempotency)** — architectural. Lifecycle of the install-time artifact is part of the architecture. Promoted to A1 above.
- **C2 (manifest exhaustiveness assertion vs enforcement)** — this is prereq #4's concern, not this spec's. Flagged in I9 / I10.
- **C4 (`created_file` reversal)** — architectural. Data-loss surface needs explicit policy. Promoted to A2 above.
- **C5 (schema normalization)** — documentation/contract. The architecture decision is locked; the spec just needs one normative table. Demoted to I1.
- **Prereq #5 git-hook missing** — scope-cuts. Demoted to I9.
- **Detector fallback sunset** — scope-cuts + future-roadmap. Demoted to I10.

Resolution: 2 of Codex's 6 are genuinely architectural (A1, A2); the other 4 are contract/scope drift inside prereqs or documentation polish.

---

## Verdict

**Overall: GO_WITH_FIXES**

Two architectural findings (A1 manifest lifecycle, A2 created_file reversal policy) need inline fixes before /blueprint. They're surgical: A1 adds ~5 lines to spec.md's apply-completion semantics + revises AC8; A2 adds an explicit policy paragraph to Data&State + revises AC6.

Ten warn-route findings (I1-I10) route to `followups.jsonl` under permissive gate mode; `/build` wave 1 consumes them as `build-inline` (I4, I5, I7, I8) or `docs-only` (I1, I2, I3, I6, I9, I10) tasks.

Eight observations stay as polish notes.

**Recommended path:** address A1 + A2 inline in spec.md (5-10 min), emit `followups.jsonl` for I1-I10, then proceed to `/blueprint`. The prereq #4 (manifest-emit) and prereq #5 (uninstall-prep, possibly split per I9) blueprints will absorb the remaining concerns at their gates.

(approve / refine `<what to change>` / fix-A1-A2-and-proceed)
