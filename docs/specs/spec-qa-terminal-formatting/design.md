# Implementation Plan — spec-qa-terminal-formatting

**Date:** 2026-05-16 (V3 — revised after /check synthesis)
**Designers:** api (opus) · integration (sonnet) · data-model (sonnet) · codex-adversary (Phase 2b @ /blueprint AND @ /check)
**Check reviewers:** risk (opus) · scope-discipline (sonnet) · completeness (sonnet) · codex-adversary
**Gate mode:** permissive (frontmatter)
**Scope:** XS-S markdown formatting refactor — **38 line edits across 6 command files + 1 feature-spec amendment + 1 new test + 1 test-runner edit + 1 CHANGELOG edit**

## V2 → V3 revision context (same session, after /check)

The plan went through `/check` with 3 reviewers + Codex. No FAIL verdicts but 9 substantive findings; all applied inline below.

| ID | Source | Finding | Resolution |
|----|--------|---------|------------|
| M1 | completeness | T8 "spec V3 amendment" too vague — no concrete AC4 diff | T8 now ships an explicit unified-diff against the spec file |
| M2 | completeness | T12 needs minimal-invocation guidance for `/blueprint` and `/check` (they require prior artifacts) | T12 spelled out per-command; non-mutating render-only smoke where prior-gate artifacts are absent |
| S1 | risk | Anti-pattern regex #3 needs negative-fixture binding | T8 fixture list expanded |
| S2 | risk | T12 needs isolation strategy (running `/kickoff /spec /build` real will pollute repo) | T12 uses a throwaway-feature-slug + cleanup; non-mutating render where possible |
| C1 | codex | T11 (CHANGELOG) cannot run parallel with T10 — verifies stale tree | T11 sequenced BEFORE T10; T10 now verifies the final tree |
| C2 | codex | T8 write-target ambiguous — could be `commands/spec.md` (collides with T2) | T8 explicit: edits `docs/specs/spec-qa-terminal-formatting/spec.md`, NOT `commands/spec.md` |
| C3 | codex | `[^]*?` regex fallback I suggested is non-portable | Replaced with space-after-paren discriminator (portable BRE) |
| C4 | codex | Scope accounting inconsistent (omitted spec amendment + CHANGELOG) | Updated top-line scope and the wire-in checklist |
| C5 | codex | T12 mutates state — can't run parallel with T10 | T12 sequenced AFTER T10 |
| C6 | codex | OQ1 still open at /check | RESOLVED: apply D3 (AC4 amendment) inline at T8 |
| C7 | codex | Raw-indented anti-pattern too broad — would catch future code examples | Scoped to known choice contexts; fenced-block exclusion in test |

## Design Decisions

### D1 — Single canonical form (`**a)**`)
Confirmed by all 3 design + 3 check reviewers + Codex (×2). `**a)**` is the only valid lettered-choice form.

### D2 — Normalize all 3 pre-existing variants
38 lines total: 21 bold-bullet + 8 paren-bolded + 9 raw-indented. Scope-discipline reviewer explicitly endorsed the wide plan: "narrow plan would leave 17 non-canonical lines in files where the test is active, forcing either weakened anti-pattern regexes or suppressions."

### D3 — AC4 broadened in spec V3 (RESOLVED at /check — apply inline at T8)
**Path (a) confirmed:** apply the spec V3 amendment to AC4 inline at T8 within this PR. No `/spec-review` V3 cycle. Codex caught the gap; Codex validated the fix; same author/session. The amendment edits `docs/specs/spec-qa-terminal-formatting/spec.md` (NOT `commands/spec.md` — that's T2's file).

**Exact AC4 amendment diff** (T8 applies this verbatim):
```diff
@@ -119,7 +119,7 @@
     SCOPE_FILES=(commands/spec.md commands/spec-review.md commands/blueprint.md commands/check.md commands/build.md commands/kickoff.md)
     FAIL=0

-    # Discovery: every lettered-choice line in any scope file.
+    # Discovery: every lettered-choice line in any scope file — 3 anti-pattern checks.
     for f in "${SCOPE_FILES[@]}"; do
       [ -f "$f" ] || continue
-      # Find lines matching old form: "- **<letter>) <content>**" (bold extends past close-paren)
+      # Anti-pattern 1: old bold-bullet form "- **a) Text**" (bold extends past close-paren).
+      # Discriminator: canonical form has NO space after the close-paren (`a)**`);
+      # old form has a space (`a) `). Portable BSD-grep BRE.
       OLD_FORM=$(grep -nE '^[[:space:]]*-[[:space:]]*\*\*[a-z]\)[[:space:]]' "$f" || true)
       if [ -n "$OLD_FORM" ]; then
         echo "FAIL: $f contains old-form lettered-choice blocks (bold spans option text):"
         echo "$OLD_FORM" | sed 's/^/  /'
         FAIL=1
       fi
+      # Anti-pattern 2: paren-bolded form "- **(a) text**" or "- **(a)** text".
+      PAREN_FORM=$(grep -nE '^[[:space:]]*-[[:space:]]*\*\*\([a-z]\)' "$f" || true)
+      if [ -n "$PAREN_FORM" ]; then
+        echo "FAIL: $f contains paren-bolded lettered-choice blocks:"
+        echo "$PAREN_FORM" | sed 's/^/  /'
+        FAIL=1
+      fi
+      # Anti-pattern 3: raw indented form "  a) text" (no bullet, no bold).
+      # Limited to scope files only (CHANGELOG, README etc. are NOT in SCOPE_FILES);
+      # within scope files, ALL indented "a)" lines must use the canonical bulleted form.
+      RAW_FORM=$(grep -nE '^[[:space:]]+[a-z]\)[[:space:]]' "$f" || true)
+      if [ -n "$RAW_FORM" ]; then
+        echo "FAIL: $f contains raw indented lettered-choice blocks (missing bullet + bold):"
+        echo "$RAW_FORM" | sed 's/^/  /'
+        FAIL=1
+      fi
     done

     if [ "$FAIL" -eq 0 ]; then
-      echo "PASS: all lettered-choice blocks in pipeline commands use V2 form."
+      echo "PASS: all lettered-choice blocks in pipeline commands use V3 canonical form."
     fi
     exit "$FAIL"
```

The space-after-paren discriminator (C3) replaces the old `[^*]*\*\*` clause and is more robust — it correctly excludes canonical `- **a)** Text` (no space between `a)` and `**`) while catching old-form `- **a) Text**` (space between `a)` and `Text`).

### D4 — Single-PR sweep, no split (unchanged)
### D5 — Data-model N/A (unchanged)
### D6 — Test orchestrator parity guard wire-in (unchanged)

## Discovery Grep Result (binding count — unchanged from V2)

| File | Bold-bullet | Paren-bolded | Raw indented | Total |
|------|-------------|--------------|--------------|-------|
| `commands/spec.md` | 7 | 4 | 5 | 16 |
| `commands/kickoff.md` | 3 | 4 | 4 | 11 |
| `commands/check.md` | 5 | — | — | 5 |
| `commands/build.md` | 2 | — | — | 2 |
| `commands/blueprint.md` | 2 | — | — | 2 |
| `commands/spec-review.md` | 2 | — | — | 2 |
| **Total** | **21** | **8** | **9** | **38** |

## Implementation Tasks (V3 — re-sequenced per Codex C1, C5)

| # | Task | Depends On | Size | Parallel? |
|---|------|------------|------|-----------|
| **T1** | Run all 3 discovery greps; produce per-file line-list. **BLOCKING — gates T2-T8.** Output format: 6 markdown tables (one per file) with `<filepath>:<lineno>: <verbatim line>` rows. If counts differ from the V3 plan, the line-list overrides — use the live grep result, not the table above (per completeness S3). | — | S | — |
| T2 | Sweep `commands/spec.md` — transform 16 blocks per V3 implementation notes | T1 | S | yes (T3-T7,T8) |
| T3 | Sweep `commands/kickoff.md` — 11 blocks | T1 | S | yes |
| T4 | Sweep `commands/check.md` — 5 blocks | T1 | S | yes |
| T5 | Sweep `commands/build.md` — 2 blocks | T1 | S | yes |
| T6 | Sweep `commands/blueprint.md` — 2 blocks | T1 | S | yes |
| T7 | Sweep `commands/spec-review.md` — 2 blocks | T1 | S | yes |
| T8 | (a) Write `tests/test-spec-qa-formatting.sh` with the 3 anti-pattern bash test above; `chmod +x`. (b) Apply the D3 unified-diff to **`docs/specs/spec-qa-terminal-formatting/spec.md`** (NOT `commands/spec.md` per Codex C2). | T1 | S | yes |
| T9 | Append `test-spec-qa-formatting.sh` to TESTS array in `tests/run-tests.sh` with comment `# spec-qa-terminal-formatting — V3 anti-pattern sweep` | T8 | S | — |
| **T11** | Add CHANGELOG.md `[Unreleased]` entry: `### Changed` section, one-line "Q&A lettered-choice blocks across pipeline commands now use canonical `- **a)** text` form" + reference to spec. **Per Codex C1: this MUST land before T10 so the test suite verifies the final tree.** | T2-T9 | S | — |
| **T10** | Run `tests/run-tests.sh` locally — verifies the final tree (T2-T9 + T11 all applied). New test passes; full suite stays green. **Gate for T12.** | T2-T9, T11 | S | — |
| **T12** | Per-command smoke (AC7), non-mutating where possible. Per Codex C5: runs AFTER T10. (See "T12 smoke playbook" below for exact commands.) | T10 | M | — |

**Total estimated effort:** 40-55 minutes (up from V2's 35-50 — reflects sequential T11 → T10 → T12 ordering vs V2's parallel claims).

## T12 smoke playbook (per M2, S2, Codex C5)

For each command, the smoke is "render the lettered-choice prompt once and visually confirm V3 canonical form." Use a throwaway-feature-slug `_smoke-test-DELETE-ME` and clean up after:

1. **`/spec` smoke (Phase 1 Q&A):** in a fresh Claude Code session, run `/spec _smoke-test-DELETE-ME-1`. Confirm Q1's `**a)** ... **b)** ... **c)** ...` form renders with bolded letter, plain option text. Cancel with Ctrl+C before any commit. No artifacts written.
2. **`/spec` work-size selector smoke:** in the same fresh session, run `/spec install-obsidian-vault-baseline` (an EXISTING spec — triggers the work-size selector at spec.md:38-42). Confirm work-size options render in V3 form. Cancel before any action.
3. **`/kickoff` smoke (product-structure selector, lines 98-101):** run `/kickoff _smoke-test-DELETE-ME-2`. Confirm the product-structure selector renders in V3 form. Cancel before any project init action.
4. **`/spec-review`, `/blueprint`, `/check` smoke (non-mutating render check):** these commands require prior-gate artifacts. Use the existing spec dir `docs/specs/wiki-write-conventions/` (shipped, has all gates). Run `/spec-review wiki-write-conventions`. The final approval prompt should render in V3 form. **Important: cancel BEFORE replying with `a` or `b` to avoid mutating the existing spec.**
5. **`/build` smoke:** run `/build wiki-write-conventions` against the same existing spec. Cancel before any commit. Lettered choices in `commands/build.md:111-112` should render in V3 form.

If any command renders an old-form lettered-choice block during smoke, T12 fails — return to T1 with the offending line.

Single-paragraph note in the final commit message: `Smoke verified: V3 form rendered correctly in /spec Q&A, /spec work-size selector, /kickoff product-structure selector, /spec-review approval, /build approval. No mutating actions taken.`

## Wave Sequencing (V3 — corrected)

| Wave | Tasks | Order | ~Time |
|------|-------|-------|-------|
| Wave 0 | T1 (blocking) | sequential | 2 min |
| Wave 1 | T2-T7, T8 | parallel | 10 min |
| Wave 2 | T9 | sequential after T8 | 2 min |
| Wave 3 | T11 (CHANGELOG) | sequential after T2-T9 — **must precede T10 per C1** | 3 min |
| Wave 4 | T10 (test suite) | sequential after T11 — verifies final tree | 5 min |
| Wave 5 | T12 (smoke) | sequential after T10 — non-mutating per C5 | 20 min |

## Open Questions

None remaining at /check. OQ1 (D3 path) resolved inline above.

## Risks

- **R1 (low):** the broadened AC4 (3 anti-pattern checks) — T8 must include the 3 fixtures (canonical-with-nested-bold, paren-form, raw-form) to verify no false positives. Failure mode would be CI tripping on legitimate future markdown.
- **R2 (low):** T12 smoke runs against existing committed specs (wiki-write-conventions). If those specs have been modified mid-session, smoke could match against an unintended state. Mitigation: T12 runs only after T10 verifies the test suite is green.
- **R3 (very low — Codex-verified):** disk-vs-wired parity guard at `tests/run-tests.sh:164-180`. D6 captures; T9 is explicit.

## Implementation Notes (for /build wave — unchanged from V2 except where noted)

Three transform patterns. Examples:

### Bold-bullet transform
```diff
- - **a) Bug fix** — skip spec, go straight to fix
+ - **a)** Bug fix — skip spec, go straight to fix
```

### Paren-bolded transform
```diff
- - **(a) In scope for this spec** — will be covered by the Q&A
+ - **a)** In scope for this spec — will be covered by the Q&A
```
Strip parens; otherwise same shape.

### Raw-indented transform
```diff
-   a) Bug fix — skip spec, go straight to fix
+ - **a)** Bug fix — skip spec, go straight to fix
```
Replace leading whitespace with `- ` bullet marker; add `**` around letter+paren.

For lines where the bold close marker spans across a multi-word option (the common bold-bullet case), the bold rescope is from `**a) text**` → `**a)** text`. The em-dash and description after stay plain.

## Codex Adversarial View (cumulative across /blueprint + /check passes)

Codex ran twice on this design — once at /blueprint Phase 2b (caught 4 corrections: count 21→38, sequencing, AC4 gap, smoke breadth), once at /check Phase 2b (caught 7 more corrections, all applied in V3). Full outputs at `docs/specs/spec-qa-terminal-formatting/plan/raw/codex-adversary.md` and `docs/specs/spec-qa-terminal-formatting/check/raw/codex-adversary.md`.

The cumulative pattern is the canonical `feedback_codex_catches_plan_vs_reality_drift.md` memory firing: Codex verified plan-against-codebase + plan-against-self at both gates, catching ambiguities Claude reviewers (who verify plan-against-itself) consistently missed (specifically: write-target ambiguity, portability of regex constructs, file-edit-vs-test-suite ordering, scope-accounting drift).
