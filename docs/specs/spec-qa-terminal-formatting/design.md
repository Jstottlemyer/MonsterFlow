# Implementation Plan — spec-qa-terminal-formatting

**Date:** 2026-05-16 (V2 — revised after Codex Phase 2b)
**Designers:** api (opus) · integration (sonnet) · data-model (sonnet) · codex-adversary (Phase 2b)
**Gate mode:** permissive (frontmatter)
**Scope:** XS-S markdown formatting refactor — 38 line edits across 6 files + 1 new test + 1 orchestrator wire-in

## V1 → V2 revision context (same session)

Codex Phase 2b adversary surfaced 4 substantive corrections to V1:
- **C1 (contract):** V1's discovery count was 21 but missed 2 in-scope variants. Real count: 38.
- **C2 (contract):** Spec's AC4 anti-pattern regex only enforces the bold-bullet form. D2 (normalize unbolded + parenthesized variants) is not enforced by any test as currently written. Either broaden AC4 (recommend) or narrow scope.
- **C3 (architectural):** V1's wave-sequencing claimed T1 ran in parallel with T2-T7, but T2-T7 depend on T1's discovery output. Fixed: T1 is blocking first.
- **C4 (tests):** Test orchestrator wiring assumption (`tests/run-tests.sh:164-180` disk-vs-wired parity guard) was VERIFIED correct by Codex.

V2 corrects the counts, sequencing, and surfaces the AC4 gap as a decision point.

## Design Decisions

### D1 — Single canonical form (`**a)**`)
The V2 spec already chose bold-confined-to-letter as the canonical form. API designer reinforced: **`**a)**` is the only valid lettered-choice form going forward.** The AC4 anti-pattern grep test is the enforcement mechanism (but see C2 — it currently only enforces one of three old forms).

### D2 — Normalize ALL pre-existing variants in the same sweep
The codebase currently has three different lettered-choice forms:
- **Bold-bullet (old):** `- **a) Option** — text` (21 occurrences) — V1 spec captured these
- **Paren-bolded:** `- **(a)** — text` (8 occurrences) — V1 spec missed these
- **Raw indented:** `  a) Option — text` (9 occurrences) — V1 spec missed these

All three convert to canonical `- **a)** Option — text`. The build wave sweeps all 38 lines.

### D3 — AC4 broadening required for D2 enforcement (spec amendment needed)
Per Codex C2: the current AC4 regex only catches the bold-bullet form. To enforce D2, the spec needs three anti-pattern tests in AC4:

1. Anti-pattern: `^[[:space:]]*-[[:space:]]*\*\*[a-z]\)[[:space:]][^*]*\*\*` (old bold-bullet form)
2. Anti-pattern: `^[[:space:]]*-[[:space:]]*\*\*\([a-z]\)\*\*` (paren-bolded form)
3. Anti-pattern: `^[[:space:]]+[a-z]\)[[:space:]]` (raw indented form, no bullet)

All three portable BRE/ERE. T8 in the task list below assumes the spec is amended (V3); the build wave can apply the amendment as part of its work (it's a 3-line addition to the existing test fixture).

### D4 — Single-PR sweep, no split
38 line-edits across 6 independent markdown files. No coupling risk. One commit, one PR.

### D5 — Data-model: N/A confirmed
Resolver baseline-matched `data` tag (false positive). Zero data-model surface.

### D6 — Test orchestrator wiring constraint (Codex-verified)
`tests/run-tests.sh:164-180` has a disk-vs-wired parity guard that exits 2 on mismatch. The new test file and TESTS array entry MUST land in the same commit.

## Discovery Grep Result (revised, binding count)

```
# Old bold-bullet form
$ grep -rnE '^[[:space:]]*-[[:space:]]*\*\*[a-z]\)' commands/
21 matches

# Paren-bolded form
$ grep -rnE '^[[:space:]]*-[[:space:]]*\*\*\([a-z]\)' commands/
8 matches

# Raw indented form
$ grep -rnE '^[[:space:]]+[a-z]\)[[:space:]]' commands/
9 matches
```

| File | Bold-bullet | Paren-bolded | Raw indented | Total |
|------|-------------|--------------|--------------|-------|
| `commands/spec.md` | 7 (L187-190, 248-250) | 4 (L168-171) | 5 (L38-42) | 16 |
| `commands/kickoff.md` | 3 (L151-153) | 4 (L107-110) | 4 (L98-101) | 11 |
| `commands/check.md` | 5 (L314-315, 321-323) | — | — | 5 |
| `commands/build.md` | 2 (L111-112) | — | — | 2 |
| `commands/blueprint.md` | 2 (L236-237) | — | — | 2 |
| `commands/spec-review.md` | 2 (L245-246) | — | — | 2 |
| **Total** | **21** | **8** | **9** | **38** |

## Implementation Tasks (revised wave sequencing per Codex C3)

| # | Task | Depends On | Size | Parallel? |
|---|------|------------|------|-----------|
| **T1** | **Run all 3 discovery greps; produce the per-file line-list (BLOCKING — gates everything else)** | — | S | — |
| T2 | Sweep `commands/spec.md` — transform 16 blocks (7 bold-bullet + 4 paren-bolded + 5 raw-indented) | T1 | S | yes (with T3-T7) |
| T3 | Sweep `commands/kickoff.md` — 11 blocks (3 + 4 + 4) | T1 | S | yes (with T2,T4-T7) |
| T4 | Sweep `commands/check.md` — 5 blocks (bold-bullet only) | T1 | S | yes (with T2,T3,T5-T7) |
| T5 | Sweep `commands/build.md` — 2 blocks | T1 | S | yes (with T2-T4,T6,T7) |
| T6 | Sweep `commands/blueprint.md` — 2 blocks | T1 | S | yes (with T2-T5,T7) |
| T7 | Sweep `commands/spec-review.md` — 2 blocks | T1 | S | yes (with T2-T6) |
| T8 | Write `tests/test-spec-qa-formatting.sh` with 3 anti-pattern checks (bold-bullet, paren-bolded, raw-indented) + chmod +x. **Spec V3 amendment to AC4 happens here — add D3's 3 regexes to spec's AC4 prose.** | T1 | S | yes (with T2-T7) |
| T9 | Append `test-spec-qa-formatting.sh` to TESTS array in `tests/run-tests.sh` with feature-naming comment (Codex-verified: required to avoid parity-guard exit 2) | T8 | S | — |
| T10 | Run `tests/run-tests.sh` locally — verify new test passes AND full suite stays green | T2-T9 | S | — |
| T11 | Add CHANGELOG.md `[Unreleased]` entry with one-line before/after reference per AC6 | T2-T9 | S | yes (with T10) |
| T12 | Manual smoke (AC7): run each pipeline command (`/spec`, `/spec-review`, `/blueprint`, `/check`, `/build`, `/kickoff`) once with throwaway args; eyeball that each prompt block renders in V2 form. Single-paragraph note in build commit message. (V1 had only `/spec`; expanded per Codex C4.) | T2-T9 | M | yes (with T10,T11) |

**Total estimated effort:** 35-50 minutes (up from 25-40 for V1 plan; reflects 38 lines vs 21 + broader smoke).

## Wave Sequencing (revised per Codex C3)

- **Wave 0 (blocking, ~2 min):** T1 — run all 3 discovery greps. T1 must complete before T2-T8 start.
- **Wave 1 (parallel, ~10 min):** T2-T7 (file sweeps) + T8 (test file write). All independent once T1 has produced the line-list.
- **Wave 2 (sequential, ~2 min):** T9 (orchestrator wire-in) — must follow T8.
- **Wave 3 (mostly sequential, ~15-20 min):** T10 (local test run — the verification gate), T11 (CHANGELOG, parallel-with-T10-OK), T12 (manual smoke across 6 commands, parallel-with-T10/T11-OK).

No data contract precedence (no schemas, no JSONL, no migrations). The three-gate "data → UI → tests" default doesn't apply.

## Codex Adversarial View

Full Codex output at `docs/specs/spec-qa-terminal-formatting/plan/raw/codex-adversary.md`. Substantive findings applied inline above; one additional observation worth flagging:

- **Codex O1 (false-positive risk in AC4 regex):** the `[^*]*` clause in the old bold-bullet regex stops at any `*` before the closing `**`. This could **under-match** old-form lines that have a `*` (single emphasis) inside the option text — e.g., `- **a) Use *advanced* mode**` would not match the anti-pattern even though it's in the old form. Mitigation in T8: add a known-tricky fixture (old-form line with `*single-emphasis*` inside the option text) to verify the regex catches it; if it doesn't, broaden to `[^]*?` (lazy any-char) or split into two regexes.

- **Codex O2 (false-positive risk in canonical form):** canonical `- **a)** Use **advanced** mode` should NOT match the anti-pattern because the regex requires a space immediately after `a)` while canonical has `a)**`. Codex confirmed this risk is overstated — the regex correctly distinguishes them.

## Open Questions

- **OQ1 — D3 spec amendment scope:** the spec V2 was just approved 10 minutes ago. The D3 amendment (broadening AC4) is a substantive change to the binding contract. Two options:
  - **(a) Apply D3 inline as part of T8** — the build wave adds the 2 new anti-patterns to AC4 prose in spec.md alongside the test implementation. No re-/spec-review cycle. Defensible because the gap was caught by Codex at /blueprint and applied inline per `feedback_codex_catches_plan_vs_reality_drift.md` pattern.
  - **(b) Restart at /spec-review V3** — explicitly revise the spec, re-dispatch reviewers. Slower but more rigorous.
  
  **Lean (a)** — same session, same author, Codex already found and validated the gap. Re-running reviewers would mostly confirm what Codex already surfaced.

- **OQ2 — Codex review at /check:** small surface, formatting-only, no runtime code. Default `/check` roster sufficient.

## Risks

- **R1 (low, was minor in V1):** the broadened AC4 (3 anti-pattern checks) is mechanically more surface for false positives. T8 must include fixtures for each known-tricky pattern (raw `a)` inside a code-fenced example; paren-bolded inside a quoted instruction) to verify the test doesn't over-fire.
- **R2 (low):** T12 manual smoke across 6 commands is more time than V1's `/spec`-only smoke. If any command's prompt fails to render in V2 form, the build wave returns to re-sweep before declaring done.
- **R3 (very low — Codex-verified):** the disk-vs-wired parity guard at `tests/run-tests.sh:164-180` could fail T10 if T9 forgets the TESTS entry. D6 captures this; the task list makes T9 explicit and dependent on T8.

## Implementation Notes (for /build wave)

### Bold-bullet transform (existing form → V2)
```diff
- - **a) Bug fix** — skip spec, go straight to fix
+ - **a)** Bug fix — skip spec, go straight to fix
```

### Paren-bolded transform (paren form → V2)
```diff
- - **(a) In scope for this spec** — will be covered by the Q&A and written into the spec
+ - **a)** In scope for this spec — will be covered by the Q&A and written into the spec
```
Strip the parens; otherwise same shape.

### Raw-indented transform (raw form → V2)
```diff
-   a) Bug fix — skip spec, go straight to fix
+ - **a)** Bug fix — skip spec, go straight to fix
```
Replace leading whitespace with `- ` (bullet marker); add `**` around the letter+paren.

### Multi-line note
For lines where the option spans into a parenthetical hint (`- **a) Approve** — accept and continue`), the parenthetical and surrounding em-dash stay in plain text. The bold rescope is only the letter token.
