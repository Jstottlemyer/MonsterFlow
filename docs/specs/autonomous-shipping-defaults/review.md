# Review — autonomous-shipping-defaults

**Date:** 2026-05-16
**Reviewers:** gaps:opus · requirements:sonnet · scope:sonnet · codex-adversary
**Gate mode:** permissive (frontmatter)
**Overall health:** **Significant Gaps** — architectural redesign + AC tightening required before /blueprint

---

## Verdict summary

| Reviewer | Verdict | Headline |
|---|---|---|
| gaps (opus) | PASS WITH NOTES | 4 critical: post-compact detection, halt-needs-human surface, flow.md wording, constitution migration |
| requirements (sonnet) | **FAIL** | 6 ACs unimplementable as written: AC4, AC6, AC8, AC9, AC10, helper missing `--constitution-path` |
| scope (sonnet) | PASS WITH NOTES | AC8 unsatisfiable; LLM-scan is a security/trust-boundary issue, not just heuristic; item 4 + constitution are strong carve candidates |
| codex-adversary | (effectively FAIL) | LLM-scan trust boundary is the load-bearing architectural concern; helper CLI does 5 jobs; JSONL pollution from every render |

**Consolidated verdict: FAIL.** The spec is well-rationalized but has architectural and contract issues that prevent deterministic /build. Recommend V2 revision.

---

## Before You Build (Blocking — 7 items)

### B1. LLM-scan /goal detection is a trust boundary, not a heuristic [security, architectural]
**Convergent: scope + codex (codex stronger).**

The spec collapses `AUTORUN=1` with "LLM detects active /goal in recent conversation." This is a *privilege transition* based on natural-language context scanning. Failure modes:
- An adversarial spec, review, log, or PR comment containing the literal `/goal ... shipped via merged PR` triggers autorun.
- Auto-compacted contexts may paraphrase the literal trigger away (false negative) or preserve a stale `/goal` while losing its `/goal clear` (false positive).
- Multi-session persistence: if Claude Code persists goals across sessions, yesterday's stale goal could autoship today.
- `/goal clear` detection is also LLM-scanned — same fragility.
- Spec body contents themselves could bias gate behavior on the spec describing them.

**Codex recommendation (which I endorse):** Use a deterministic state marker. Three viable surfaces:
- `.monsterflow/state/active-goal.json` (repo-local)
- `dashboard/data/active-goal.json`
- `docs/specs/<feature>/.active-goal` sentinel

Gate skills check the file, not the conversation. The state is written by either: (a) the user's `/goal` command if MonsterFlow can hook it (unlikely — built-in), or (b) a tiny `/ship-now <slug>` skill the user types instead of `/goal` that writes the marker + emits the `/goal` line.

**At minimum (if deterministic marker is out of scope for v1):** narrow the LLM-scan to "the literal `/goal docs/specs/<slug>/spec.md is shipped via merged PR` substring appearing in the **last user message** only, not anywhere in recent context." This dramatically reduces injection surface — content the user pastes into a single prompt is high-trust.

### B2. AC8 is unsatisfiable as written [contract]
**Convergent: requirements + scope + codex.**

AC8 says: "render-mode `block` output for the merge step omits `--delete-branch`; render-mode `block` with `--gate manual-merge` includes `--delete-branch`." But the helper CLI contract (spec lines 159–165) defines `--gate` as accepting only `spec-exit`, `spec-review`, `check-go`, `check-go-with-fixes`. There is no `manual-merge` gate. Also: the helper emits *render blocks for skill prompts*, not actual `gh pr merge` command strings.

**Fix options:**
- **(a)** Extend helper CLI to include `merge-command` subcommand or `--gate manual-merge` value; redesign AC8 to test it.
- **(b)** Rewrite AC8 to test the actual surface: grep `commands/build.md` (or whichever skill issues the merge) for the presence/absence of `--delete-branch` in the two paths.
- **(c)** Carve item 4 (autoship-merge-preserves-branch) to a follow-up spec entirely.

### B3. AC9 references CLI flags that don't exist [contract]
**Convergent: requirements + codex.**

AC9 says: "fixture invocation with `--event autoship-halt --reason branch-protection-block` writes a row with the expected fields." But the helper CLI has no `--event`, `--reason`, or `--stage-at-halt` arguments. Divergence rows are written *by gate skills at runtime*, not by the helper. Either:
- Add `--emit-divergence --event ... --reason ...` flags to the helper CLI contract, OR
- Restructure AC9 to test whichever skill prompt actually writes divergence rows.

### B4. AC6 — schema content is unspecified [contract]
**requirements flagged.**

AC6 validates JSONL rows against `schemas/autorun-suitability-outcomes.schema.json`, but the schema file is listed as *new* in Integration. The spec gives field names and types inline but never resolves: which fields are required vs optional, what the enum values are for `predicted_suitability` / `gate` / `event` / `reason`, or whether the two row shapes (render rows + divergence rows) are separate `$defs` or a discriminated union. **Fix:** inline the field-level constraints as normative spec content.

### B5. AC4 grep pattern unspecified [contract]
**requirements flagged.**

AC4 says "verified by grep on output" without naming the grep patterns. UX examples at spec lines 82–87 contain candidate strings but they aren't canonicalized as the test contract. **Fix:** enumerate exact grep patterns in AC4 OR point to template constants in the helper as normative.

### B6. flow.md wording is unspecified [contract]
**Convergent: gaps + requirements ("Feature 2 has no AC").**

The spec says "one-paragraph addition" / "~10-line paragraph" but never says *what* the paragraph says, *where in flow.md* it goes, or what anchor string AC10 should grep for. Each reviewer + build agent would invent different prose. **Fix:** lock the wording OR specify required anchor phrase + section heading.

### B7. AC10 anchor strings not exhaustively enumerated [tests]
**Convergent: requirements + scope.**

AC10 uses `e.g.` framing — illustrative, not normative. Test author picks arbitrary strings, coverage varies by implementer. Also: AC10 covers only `spec.md`, `spec-review.md`, `check.md` but the spec edits 8 skill-prompt surfaces across 5 files (adds `blueprint.md`, `build.md` to that list). **Fix:** normative table mapping anchor strings → target files.

---

## Important But Non-Blocking (Major — 8 items)

### I1. Post-compact /goal recovery (gaps)
Edge case 12 covers multi-goal stacks but not the auto-compact case where the literal `/goal docs/.../spec.md is shipped via merged PR` is summarized away to "user set an autoship goal earlier." If B1 is resolved via deterministic state file, this dissolves. If LLM-scan is kept, need explicit "fail-closed if literal phrase not visible verbatim in current context" rule.

### I2. "Halt — needs human" surface beyond JSONL (gaps)
Tonight's branch-protection-block case is what motivated this spec, yet the only halt signal defined is a JSONL row. The spec says "halt, surface 'needs --admin auth'" but never specifies *where* (stdout? terminal bell? PushNotification?). If the user is asleep, JSONL is silent. **Fix:** explicit halt-surface contract — at minimum, a visible stdout block. Consider PushNotification for /goal-driven autorun.

### I3. Bundle size is L, not M (scope)
13 files touched, 1 new helper (~200 LoC), 1 new schema, 1 new test (~150 LoC), 5 skill edits, flow.md, constitution template, .gitignore, CHANGELOG, BACKLOG. At/over the "≤300 spec lines + ≤200 LoC" slicing threshold. /build should treat as 3 waves: (A) helper + schema + test; (B) `/spec` + `/spec-review` + `/blueprint` edits; (C) `/check` + `/build` autorun-detection + flow.md + housekeeping.

### I4. Helper does 5 jobs (codex)
The helper is simultaneously: renderer, suitability scorer, instrumentation logger, divergence logger, merge-command flag oracle. Too much for one CLI unless interface is expanded. **Fix options:** split into subcommands (`render`, `log-render`, `log-halt`, `merge-command`) OR narrow v1 to render+score only.

### I5. JSONL pollution from every render (codex)
Naming says "outcomes" but rows get written on every render — including test runs, preview/cancel cycles, repeated /spec-review invocations. The file accumulates non-outcome events that drown the actual outcome signal. **Fix:** rename to `autorun-suitability-events.jsonl` OR only write on user-visible render (not on test-mode invocations) OR add an `event_type: render|outcome|halt` discriminator.

### I6. Constitution migration path missing (gaps)
Spec adds optional `autorun_suitability:` block to constitution schema but says nothing about existing constitutions. Does `install.sh` touch existing `docs/specs/constitution.md`? Does `/kickoff` re-templating preserve user edits? Memory `install.sh: backup configs + ship uninstall.sh` is directly relevant.

### I7. AC count parsing semantics (codex)
"First-level items under `## Acceptance Criteria`" — needs exact Markdown rules. Are checkbox items counted? Nested bullets? `AC1 - ...` paragraphs? Numbered lists interrupted by text? **Fix:** specify or point to a regex.

### I8. Constitution-path flag missing from helper CLI (requirements)
AC7 tests constitution overrides but the helper CLI has no `--constitution-path` flag. Tests have no way to inject a controlled constitution without reading the real `docs/specs/constitution.md`. **Fix:** add `--constitution-path <path>` to CLI contract (or `--no-constitution` for tests).

---

## Observations (Non-blocking notes)

- **Carve recommendations (scope + codex):** Item 4 (autoship-merge-preserves-branch) and the constitution extension are both strong deferral candidates. Cutting both brings this to a clean M with 10 ACs and no cross-surface contract ambiguity. The `/branch-cleanup` BACKLOG callout the spec already mentions can absorb item 4 into a separate `autoship-merge-hygiene` spec.

- **LOW rendering conflict at downstream gates (codex):** if `gate_mode: strict` suppresses /goal-line at /spec exit, what about /spec-review and /check? Spec implies helper renders option-c everywhere, but LOW says no /goal-line rendered. Resolve.

- **GO_WITH_FIXES autoship semantics (codex):** if fixes are required, who applies and verifies before merge? Spec should state.

- **Spec slug derivation (codex):** from filename? Parent directory? H1? Helper says "computes feature slug" but doesn't define how.

- **JSONL row write atomicity (gaps):** macOS append-mode atomic only up to PIPE_BUF (~512 bytes). Long tags arrays could exceed. Use `fcntl.flock` or guarantee single-writer.

- **`shipped via merged PR` substring collision (gaps):** "Contains the literal" is too loose. Anchor with regex `is shipped via merged PR with verifier reporting`.

- **`_smoke-DELETE-ME` artifacts could land on main (requirements):** S1 cancel-before-commit is unenforceable. Add `_smoke-*` to `.gitignore` or pre-commit lint.

- **JSONL schema future-queryability (gaps):** Missing likely-wished-for fields: `project_root`, `loc_estimate`, `wave_count`, `pr_number`, `duration_to_halt_seconds`. Cheap to add now; expensive to retrofit.

- **Self-Learning Loop section risks over-investing /build (scope):** Section is detailed enough that /build might build v2 analysis tooling "while in there." One-line clarification that the section is read-only design intent for v2.

- **No CI/pre-commit guard for the gitignore entry (scope):** If the line drifts, `git add .` stages project data. A one-line assertion would close this.

- **Self-contained smoke fixture (requirements):** S4 depends on `wiki-write-conventions` being stable. A fixture spec would be more durable than relying on a live shipped spec.

---

## Codex Adversarial View (cumulative)

Codex's load-bearing concern is **B1 (LLM-scan trust boundary)**. Codex's "bottom line":

> The product direction is reasonable, but v1 should not make freeform LLM context a source of autorun authority. Make active `/goal` state deterministic first, or keep `/goal` as a copy-paste convenience only.

Codex's recommended cleanup before implementation:
1. Replace LLM-scan with deterministic state file (or narrow scan to last-user-message-only).
2. Split helper CLI into subcommands matching its 5 responsibilities, OR narrow v1 to renderer+scorer only.
3. Add CLI flags: `--constitution-path`, `--emit-divergence --event ... --reason ...`, or `merge-command` subcommand.
4. Inline JSON schema content as normative spec text.
5. Lock flow.md paragraph wording.
6. Defer constitution extension to v2.

---

## Reviewer Verdicts Table

| Dimension | Verdict | Key Finding |
|-----------|---------|-------------|
| gaps | PASS WITH NOTES | 4 blockers: post-compact detection, halt-needs-human surface, flow.md wording, constitution migration |
| requirements | FAIL | 6 ACs unimplementable as written (AC4, AC6, AC8, AC9, AC10) + missing `--constitution-path` |
| scope | PASS WITH NOTES | AC8 unsatisfiable; LLM-scan = trust boundary; item 4 + constitution carve candidates |
| codex | FAIL (de facto) | LLM-scan trust boundary; helper does 5 jobs; JSONL pollution; ACs reference nonexistent CLI flags |

---

## Conflicts Resolved

- **Item 4 fate** — gaps did not flag; scope + codex recommended carving. **Resolution:** carve recommendation goes into Important (I3), user decides at refine step.
- **LLM-scan severity** — scope called it "security:major"; gaps called it "R1:medium" mitigated by acknowledgment line. Codex called it the #1 architectural concern. **Resolution:** promote to B1 (blocking).
- **Bundle size** — scope said L, codex implied carve, gaps did not flag. **Resolution:** keep as Important (I3); user decides at refine.

---

## Recommended Path: V2 revision

This is the same pattern as wiki-write-migrate V1→V2 (Codex-finding-folded-inline). Specifically:
1. **Replace LLM-scan with last-user-message-only narrowing OR deterministic state file** (architectural — pick one in user discussion).
2. **Fix ACs 4, 6, 8, 9, 10** with concrete contracts.
3. **Lock flow.md wording** as a literal block in the spec.
4. **Add helper CLI flags:** `--constitution-path`, divergence-emit flags, OR split into subcommands.
5. **Inline JSON schema content** (or carve to its own schemas file with required-fields list inline).
6. **Decide carve question:** keep item 4 + constitution in v1, or defer? Recommendation: carve both (10 ACs, clean M).
7. **Add halt-surface contract** (B2 / I2): JSONL alone is insufficient.
8. **Lock AC count parsing rules** + spec slug derivation rules.

This is one Q&A round + spec rewrite (~30-40 min). Cheaper than discovering these issues mid-/build.

---

[AUTORUN MODE: If AUTORUN=1 is set, skip this approval prompt. Per spec OQ1 (resolved), outcomes JSONL is gitignored.]

Approve to proceed to /blueprint?

- **a)** Approve — accept the review and continue (will hit /blueprint with known blockers)
- **b)** Refine — name what to change (`b discuss B1 trust-boundary fix + carve question`)
- **c)** Ship autonomously — *not appropriate for FAIL verdict; LLM-scan architectural choice needs human decision*

Reply with `a` or `b <change>` + Enter.
