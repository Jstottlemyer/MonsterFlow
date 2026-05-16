---
tags: [api, pipeline, refactor, scalability, security, ux]
tags_provenance:
  baseline: [api, scalability, security, ux]
  llm_added: [pipeline, refactor]
  user_overrides: []
gate_mode: permissive
---

# spec-qa-terminal-formatting Spec

**Created:** 2026-05-16
**Constitution:** none — MonsterFlow personal-tooling repo uses pipeline-default personas
**Confidence:** Scope 0.95 · UX 0.95 · Data 0.95 · Integration 0.92 · Edge 0.90 · Acceptance 0.96 · **avg 0.94**

## Summary

Update the pipeline command files (`commands/spec.md`, `commands/spec-review.md`, `commands/blueprint.md`, `commands/check.md`, plus any other pipeline command rendering lettered-choice prompts) so that every interactive lettered-choice block instructs Claude to emit the question line in green ANSI (`\033[32m`), the option letter (`a)`, `b)`, etc.) in green, and the option text in default terminal color. Replaces the current all-default/all-green rendering that the user flagged as hard to scan. No runtime code, no detection logic — these are instruction files; Claude Code owns the terminal rendering layer.

## Scope

**In scope:**
- Editing the Q&A template in `commands/spec.md` Phase 1 (question + recommendation block).
- Editing every approval-prompt block in `commands/spec-review.md`, `commands/blueprint.md`, `commands/check.md` (the `a) Approve / b) Refine` blocks).
- Editing any other lettered-choice block in any pipeline command file (work-size selector at top of `/spec`, Phase 0.25 session-roster prompt, Phase 0.5 backlog routing, Phase 2.5 specialist gap, work-class selector, etc.).
- New test `tests/test-spec-qa-formatting.sh` that performs the token-pair check defined in Acceptance.

**Out of scope:**
- Any non-pipeline command files (e.g., `commands/wrap.md`, `commands/kickoff.md`, `commands/flow.md`) UNLESS they contain a lettered-choice block — if they do, they're in scope; if they don't, they're not touched.
- Detecting `$NO_COLOR`, `$TERM=dumb`, or non-tty stdout. Terminal compatibility is Claude Code's concern, not ours (Q1 resolution).
- Any visual change to non-lettered output (synthesis tables, verdict summaries, error banners). Only lettered-choice prompts are in scope.
- Changing the option-letter convention (`a)`, `b)`, `c)`). Keeping the same letters, just coloring them.

## Approach

N/A — small change. The design was locked in this session via an `AskUserQuestion` mockup comparison: Option B won (question green, letter green, text default, blank line between question and options, no bullets).

## UX / User Flow

Before (current, all-default):
```
**Q1 — Scope: What are we building?**

- **a) Option one** — brief description
- **b) Option two** — brief description
- **c) Option three** — brief description

My lean: (a). ...
```

After (Option B):
```
\033[32m**Q1 — Scope: What are we building?**\033[0m

- \033[32m**a)**\033[0m **Option one** — brief description
- \033[32m**b)**\033[0m **Option two** — brief description
- \033[32m**c)**\033[0m **Option three** — brief description

My lean: (a). ...
```

Visual result in a color-capable terminal: the question line and the three letters appear in green; the option labels and descriptions stay in the default terminal color. The user's eye lands on the question, then on the letters as the choice anchors, with the descriptive text in the most readable color (default). Same pattern applied to every approval prompt and lettered-choice block across the pipeline.

## Data & State

None. No persistence, no config, no env vars. The change is entirely text inside `commands/*.md` instruction files.

## Integration

**Files modified (expected — actual list confirmed during build via grep enumeration):**
- `commands/spec.md` — Phase 1 Q&A template; work-size selector; Phase 0.25 session-roster prompt; Phase 0.5 backlog routing rows; Phase 2.5 specialist gap prompt; tag-confirmation prompt; auto-run abort prompt
- `commands/spec-review.md` — final approval block
- `commands/blueprint.md` — final approval block + any in-phase choices
- `commands/check.md` — final approval block + any in-phase choices
- `tests/test-spec-qa-formatting.sh` — new test file (token-pair grep check)
- `tests/run-tests.sh` — wire new test into orchestrator

**No code changes** — Claude Code owns the terminal rendering layer. The command files are instruction prose telling Claude what literal characters to emit; Claude renders the ANSI escape codes as-typed when running interactive sessions.

## Edge Cases

- **NO_COLOR / dumb terminal / piped output:** not our concern. Claude Code handles terminal capability detection at its rendering layer. Files emit ANSI as instructed; downstream rendering does the right thing. (Q1 resolution.)
- **Markdown rendering inside the instruction file itself:** the `\033[32m` codes are written as literal backslash-escape sequences in the markdown source. They're not rendered by markdown viewers, but they ARE faithfully emitted by Claude when reading the instruction. Existing specs already use raw ANSI codes in similar places (see `commands/check.md` failure banners) — this pattern is established.
- **New lettered-choice blocks added in future commits:** the grep test fails CI if a new block lacks the green pattern. This is the desired backstop — no rot.
- **Multi-line option descriptions:** the test's token-pair check binds the green ANSI code to the letter token specifically (`\033\[32m` immediately preceding `**[a-z])`), so multi-line option bodies don't confuse it.
- **The `My lean:` recommendation line and the `[default: x]` hint:** stay in default color. Only the question and the letter prefixes are colored. (Per Option B.)

## Acceptance Criteria

1. **AC1 — Q&A template updated.** `commands/spec.md` Phase 1 Q&A template literal contains `\033[32m` immediately preceding the `**Q[N]` marker AND immediately preceding each `**a)`, `**b)`, `**c)` etc. token.
2. **AC2 — All pipeline approval blocks updated.** `commands/{spec-review,blueprint,check}.md` final approval blocks (`a) Approve / b) Refine`) contain the green-question + green-letter pattern.
3. **AC3 — All other lettered-choice blocks in pipeline commands updated.** Work-size selector, Phase 0.25 session roster, Phase 0.5 backlog routing, Phase 2.5 specialist gap, tag-confirmation prompt, auto-run abort prompt — each contains the green-question + green-letter pattern.
4. **AC4 — Token-pair test exists and passes.** `tests/test-spec-qa-formatting.sh` exists, is executable, runs under `tests/run-tests.sh`, and asserts via grep:
   - Every `^- \*\*[a-z]\) ` line in scope files is immediately preceded (within the same line) by `\033\[32m`.
   - Every `\*\*Q[0-9]+` marker is preceded by `\033\[32m`.
   - Every approval prompt's interrogative line is preceded by `\033\[32m`.
   Failure messages report `<file>:<line>` for the exact offending block.
5. **AC5 — Test wired into orchestrator.** `tests/run-tests.sh` includes the new test file in its run sequence.
6. **AC6 — Visual smoke note in CHANGELOG.** CHANGELOG.md entry under `[Unreleased]` notes the change with a one-line "before/after" reference so future readers can verify.
7. **AC7 — No regression in non-lettered output.** Synthesis tables, verdict summaries, and error banners in pipeline commands are NOT modified — grep test asserts no NEW ANSI codes appear outside lettered-choice block contexts. (Defensive: prevents over-eager sweep.)

## Open Questions

- **OQ1 — Exact file enumeration:** the build wave will discover the full list of lettered-choice blocks by grepping for `^- \*\*[a-z]\) ` across `commands/*.md`. The Integration section lists expected files but does not bound them; the grep test (AC4) is the binding contract.
- **OQ2 — Codex review:** small surface, formatting-only, no runtime code path. Default `/check` roster sufficient; Codex optional.

## Backlog Routing

Skipped (small-change rule). The parent backlog item (`spec-qa-terminal-formatting`) IS this spec — it gets removed from `BACKLOG.md` when this spec ships.
