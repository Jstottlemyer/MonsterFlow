# Review — wiki-write-migrate

**Date:** 2026-05-16
**Reviewers dispatched:** gaps:opus, requirements:sonnet, scope:sonnet + codex-adversary
**Budget:** 3 + 1 codex
**Gate mode:** permissive (frontmatter)
**Verdict:** GO_WITH_FIXES — but with one architectural finding that warrants empirical verification before /blueprint

## Overall Health: Significant Gaps (one foundational, several contract)

3 Claude reviewers returned PASS WITH NOTES with substantial findings. Codex returned a heavy adversarial pass: 7 high-risk issues + design gaps, including ONE finding (C4) that questions whether the layout decision from `wiki-write-conventions` Q1 (folder + `index.md` for projects) actually works with Obsidian's link resolver. That finding deserves empirical verification before this spec advances.

## Before You Build — ARCHITECTURAL (must address before /blueprint)

### F1 — [architectural+security] **Foundational: does `[[welcome]]` actually resolve to `projects/welcome/index.md` in Obsidian?**

Source: Codex C4 (highest-risk finding in the entire review).

**The concern:** when `projects/Welcome.md` migrates to `projects/welcome/index.md`, the FILESYSTEM basename of the target is `index`, not `welcome`. Obsidian's link resolver typically matches `[[X]]` against file basenames. So `[[welcome]]` may NOT resolve to `projects/welcome/index.md` — it might resolve to nothing (broken link), or to `concepts/welcome.md` if one exists, or only work if the project page's frontmatter `title:` field is honored as an alternate resolution key.

**The spec's resolver model assumes basename-matching works.** If it doesn't, every project-page migration produces broken links (the old `[[Welcome]]` → rewritten to `[[welcome]]` → resolves to nothing).

**This is upstream of EVERY other finding in this review.** If `index.md` doesn't resolve as `welcome`, the whole approach has to change — either:
- Rewrite all project refs to full-path form: `[[projects/welcome/index|Old Title]]` (verbose but unambiguous)
- Change the layout from `projects/<slug>/index.md` to `projects/<slug>/<slug>.md` (e.g., `projects/welcome/welcome.md` — basename matches the slug)
- Find a different Obsidian resolution mechanism (frontmatter `title:`, aliases, plugin)

**Required action before /blueprint:** empirically verify Obsidian's behavior with a test vault:

1. Create `projects/welcome/index.md` with `title: Welcome` frontmatter
2. Create `concepts/test.md` with `[[welcome]]` in the body
3. Open in Obsidian, check whether the link is highlighted as resolved or broken
4. Document the result in the spec (or carve to V2)

Until this is verified, the spec cannot honestly claim shortest-unique-path will work for migrated project pages.

### F2 — [architectural] Phase B is NOT idempotent under case-insensitive matching

Source: Gaps G2 + Codex C2 (convergent).

The spec claims Phase B is idempotent because "already-rewritten links don't match the old-form pattern." This is false under realistic conditions:

- Obsidian's link resolver is case-insensitive on macOS HFS+/APFS (the dominant adopter platform). Users write `[[welcome]]` to mean `Welcome.md`. The rewriter MUST match case-insensitively to catch these.
- Once the rewriter is case-insensitive, post-rewrite text `[[welcome]]` STILL matches the old-form pattern on a re-run (because matching is case-insensitive, `welcome` matches `Welcome`).
- Result: Phase B re-runs would re-rewrite already-rewritten links, possibly producing duplicate disambiguation suffixes or other corruption.

**Required action:** explicit rewrite-tracking — either (a) journal records each per-file rewrite so re-runs skip them, or (b) rewriter detects "this link is already in the canonical post-migration form" and leaves it alone. Recommend (b): the rewriter computes both old-form-pattern AND new-form-pattern for each (old, new) tuple, only rewrites old → new (never new → new).

### F3 — [architectural] Split-brain references when collisions are skipped

Source: Codex C6.

`projects/Welcome.md` skipped due to collision. `concepts/Welcome.md` migrates to `concepts/welcome.md`. The rewriter sees `[[Welcome]]` references and assumes they target the migrated concept page — but they may have intended the skipped project page.

**Required action:** the rewriter must resolve link TARGETS before rewriting, not just match basenames. For ambiguous refs (where the old basename could have meant either a migrated OR a skipped page), the spec must either (a) skip the rewrite and flag the ref in `migration-report.md` for manual review, or (b) use heuristics (folder proximity, frontmatter `tags:` overlap) to disambiguate.

### F4 — [architectural+security] `--force-overwrite` is destructive without backup

Source: Codex C1.

Spec says `--force-overwrite` clobbers the existing target. For a wiki, that loses a page. The user might pass `--force-overwrite` to resolve one collision and inadvertently lose a different page they didn't realize was at that path.

**Required action:** instead of clobbering, archive the existing target to `<vault>/_archives/migration-conflicts/<UTC-ts>/<original-path>` before the rename. Lossless. User can recover.

### F5 — [architectural] Concurrent --migrate has a real race

Source: Gaps G3.

Two simultaneous `--migrate` invocations both attempt Phase A on the same source. The loser leaves a permanent `status: "in_flight"` row in the journal. Future `--resume` invocations see this and try to "complete" a rename that already happened.

**Required action:** advisory lock via `fcntl.flock()` on the journal file (Python stdlib supports this). First process holds the lock for the duration of Phase A. Second process exits 1 with `migration already in progress; wait for completion or rm <vault>/.migration-journal.jsonl if no other process is running`.

## Should Fix — Routed to /build inline fixes (followups.jsonl after /check)

### Contract pins

- **F6 [contract]: Journal `schema_version` field missing** (Gaps G1 + Reqs). Each row should include `schema_version: 1` so future tool upgrades can detect and refuse incompatible journals.
- **F7 [contract]: AC #3 uniqueness predicate undefined** (Reqs R1). Pin the predicate: "basename appears exactly once across `<vault>/{projects,concepts,entities}/**/*.md` after the rename plan applies." Document explicitly that `_archives/` and `_raw/` are NOT in the uniqueness denominator.
- **F8 [contract]: `--resume` on vault-absent / `--migrate --dry-run --resume` combos undefined** (Reqs R2). Pin: `--resume` on vault-absent exits 0 silently. `--migrate --dry-run --resume` is illegal — argparse rejects with exit 1 + `--dry-run and --resume are mutually exclusive`.
- **F9 [contract]: Phase B post-run verification pass missing** (Codex C2). At end of Phase B, scan the vault for any remaining wikilinks matching the (old_basename) patterns from the journal. If any found, surface as warnings in stdout AND add to `migration-report.md` as `## Verification Findings`. Doesn't halt; informational.
- **F10 [contract]: Wikilink resolver scope incomplete** (Codex C3). Current spec only handles `[[basename]]` form. Need to handle: `[[projects/Welcome]]`, `[[Welcome.md]]`, `[[../projects/Welcome]]`, `[[Welcome#Heading|Label]]`. Document each form's rewrite rule with a fixture.
- **F11 [contract]: Wikilink edge cases not enumerated** (Gaps). HTML comments (`<!-- [[foo]] -->`), callout blocks (`> [!note] [[foo]]`), whitespace-tolerant brackets (`[[ foo ]]`), nested wikilinks. Decision: HTML comments NOT rewritten (preserve as-is); callouts ARE rewritten; whitespace-tolerant brackets rewritten with whitespace preserved; nested wikilinks rewritten independently (each `[[...]]` is its own match).

### Test scope

- **F12 [tests]: AC #9(e) atomicity test not bash-implementable** (Reqs R3 + Scope SC-006). Revise the AC to: "test runs `--migrate --dry-run` to produce a plan, manually pre-plants an in-flight journal row matching the plan's first rename, runs `--migrate --resume`, asserts the rename completes and the row is marked `completed`." Same coverage, testable from bash.
- **F13 [tests]: AC #9(s) vacuously true on case-sensitive FS** (Reqs R4). Add filesystem detection at test start; SKIP this case with a logged reason when running on case-sensitive systems. Document in the test comment.
- **F14 [tests]: `--force-overwrite` + slug-collision interaction not tested** (Reqs). Add: `--force-overwrite` does NOT bypass slug-collisions (only target-exists). Test fixture: two source files mapping to same canonical slug + `--force-overwrite` → both still skipped.
- **F15 [tests]: Orphan wikilink test missing** (Gaps). Test fixture: a page contains `[[never-existed]]` (pointing to a page that never existed). Rewriter must NOT touch this ref. Verify it remains unchanged after migration.

### Vault discovery

- **F16 [contract]: Vault path with spaces / Unicode characters** (Gaps). Spec doesn't explicitly handle. Confirm `os.path.expanduser` + UTF-8 path handling work end-to-end.
- **F17 [contract]: iCloud Drive `.icloud` placeholder files** (Gaps). On iCloud Drive, not-yet-downloaded files appear as `.<basename>.icloud` placeholders. Migration should detect these and skip with `[wiki-migrate] skip: <path> is an iCloud placeholder — open file in Finder to download, then re-run`.

## Scope cuts to accept (per scope-discipline)

### Accept

- **SC-007: collapse exit codes 4 and 5 into exit 1** in v1. Stderr still distinguishes (different error messages). Promote to distinct codes when a scripted consumer materializes.
- **SC-008: simplify concurrent-invocation prose** — replace with one line: "single-user assumption; concurrent invocations protected by advisory lock per F5." (One-line replacement; not a real cut, just tightening.)

### Reject (despite scope's proposal — load-bearing)

- **SC-001 reject `--resume` defer:** finding F5 (advisory lock) means crashes are now more likely to occur with state to recover, not less. Resume is the recovery surface for that state. Keep.
- **SC-002 reject aliases defer:** the spec deliberately couples aliases with the rename to preserve discoverability via the OLD human-visible title during the user's transition period. Deferring aliases means users type "PatternCall — iOS Native Rewrite" in the quick-switcher and get nothing — a hard-to-debug bad experience that this spec exists to PREVENT. Per Codex C5, aliases aren't a CORRECTNESS guarantee for link resolution, but they ARE a UX guarantee for discoverability. Worth the schema extension.

## Observations (non-blocking)

- Codex C7 ("dry-run recompute weakens review step") is a real tradeoff but the alternative (plan-handoff via disk) has its own stale-plan issue. Accept the tradeoff; document that user should inspect `git status` on the vault between `--dry-run` and execute if they want to be certain no files changed.
- Codex's recommendation to "split normal-write `--alias` from migration" is reasonable but small — the `--alias` flag on `wiki-write.py` default-write is cheap (~5 LoC) and useful for any user who wants to create a page with aliases. Keep.

## Reviewer Verdicts

| Dimension | Verdict | Headline |
|-----------|---------|----------|
| Gaps (opus) | PASS WITH NOTES | 3 architectural (schema_version, Phase B idempotency, concurrent race) + 5 wikilink edges |
| Requirements (sonnet) | PASS WITH NOTES | 4 contract issues (uniqueness predicate, --resume vault-absent, atomicity test seam, FS-sensitive test) |
| Scope (sonnet) | PASS WITH NOTES | 8 cuts proposed (2 accepted, 4 rejected, 2 revisions); flagged that if cuts ARE accepted, ACs change |
| Codex Adversarial | 7 high-risk + design gaps | **C4 (folder/index resolution) is the foundational risk** — needs empirical verification before /blueprint |

## Conflicts Resolved

- **Scope wanted to defer aliases (SC-002); Codex said aliases don't fix wikilink resolution (C5).** Both correct in their lanes — scope is right that aliases aren't load-bearing for v1 mechanics; Codex is right that aliases don't FIX link resolution. But they SOLVE different problems: aliases fix discoverability (quick-switcher), not resolution. Keep aliases for the discoverability win; don't claim they fix resolution.
- **Scope wanted to defer `--resume` (SC-001); Gaps surfaced concurrent race needing advisory lock (G3).** With advisory lock, crashed runs leave durable state that needs recovery. `--resume` is the recovery path. Keep.

## Codex Adversarial View

The standout finding is **C4 (project folder/index basename ambiguity)** — this could invalidate the entire layout decision from wiki-write-conventions Q1 if Obsidian's link resolver doesn't honor `index.md` as the project's canonical page when linked by the parent folder name.

**Recommended verification:** before /blueprint runs, create a test vault with `projects/welcome/index.md` (frontmatter `title: Welcome`) and `concepts/test.md` containing `[[welcome]]`. Open in Obsidian. If the link resolves, the spec is sound (with the other F1-F5 fixes). If it doesn't, the spec needs V2: either change layout (`projects/<slug>/<slug>.md`) or change rewrite form (full-path links).

This is the kind of empirical question the spec can't answer from prose alone — it depends on Obsidian's actual behavior, which has versioned and is configurable.

---

**Verdict: GO_WITH_FIXES, conditional on empirical resolution of F1.** Six architectural findings (F1-F5 plus the foundational verification F1 implies), eleven contract / tests / vault-discovery refinements, two scope-cut acceptances. F1 (Obsidian link resolution to `projects/<slug>/index.md`) is the unresolved foundational question — recommend empirical test before /blueprint.

[Halted before /blueprint per user's earlier choice (option c: "just /spec-review next, then stop").] Next session: empirically test F1, then either revise the spec to V2 inline OR (if F1 fails) revisit the layout decision in `wiki-write-conventions`.
