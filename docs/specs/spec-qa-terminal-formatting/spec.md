---
tags: [api, pipeline, refactor, scalability, security, ux]
tags_provenance:
  baseline: [api, scalability, security, ux]
  llm_added: [pipeline, refactor]
  user_overrides: []
gate_mode: permissive
---

# spec-qa-terminal-formatting Spec (V2 — markdown-bold pivot)

**Created:** 2026-05-16 (V1) · **Revised:** 2026-05-16 (V2 — same session, after spec-review FAIL)
**Constitution:** none — MonsterFlow personal-tooling repo uses pipeline-default personas
**Confidence:** Scope 0.96 · UX 0.95 · Data 0.95 · Integration 0.94 · Edge 0.94 · Acceptance 0.96 · **avg 0.95**

## V2 revision context

V1 (this same session) FAILED `/spec-review` with 3 architectural blockers from Codex + requirements personas:
- **B1:** spec's load-bearing assumption — that Claude Code renders raw ANSI escape codes embedded in model-generated markdown — is unverified and contradicted by `code.claude.com/docs` (theme system is JSON-config-based at the UI layer; status-line ANSI is for shell-script stdout; no documented model-output-ANSI path).
- **B2:** literal `\033[32m` in markdown source = six visible characters, not byte `0x1b`. Emitting them faithfully would render as text, not color.
- **B3:** V1's AC4 grep regex was prose-only, missed indented/non-bold/parenthesized blocks, and depended on non-portable `grep` ANSI expansion that BSD `grep` on macOS doesn't support without `-P`.

Additionally: V1 fabricated an "existing pattern" claim about `commands/check.md` failure banners using ANSI — `grep -rn '\\033' commands/` returns zero matches. Plan-vs-reality drift caught by Codex (memory pattern `feedback_codex_catches_plan_vs_reality_drift.md` fired exactly as documented).

V2 resolves B1/B2 by **dropping ANSI entirely**. The visual intent of Option B (visual anchor on the letter, scannable text) is achievable through existing markdown bold semantics that Claude Code already renders. V2 resolves B3 by specifying a literal portable grep command in AC4 instead of describing one in prose.

## Summary

Change the pipeline command files' lettered-choice prompt template from `**a) Option text** — description` (bold spans the entire option) to `**a)** Option text — description` (bold only on the letter, option text and description in plain markdown). The bolded letter becomes the visual anchor for scanning; the plain option body is more readable. No ANSI codes, no terminal-rendering assumptions — just markdown that Claude Code already renders correctly today. Apply across every lettered-choice block in pipeline command files.

## Scope

**In scope:**
- Editing the Q&A template in `commands/spec.md` Phase 1 (question + recommendation block).
- Editing every approval-prompt block in `commands/spec-review.md`, `commands/blueprint.md`, `commands/check.md`.
- Editing every other lettered-choice block in pipeline command files — work-size selector, Phase 0.25 session-roster prompt, Phase 0.5 backlog routing, Phase 2.5 specialist gap, tag-confirmation prompt, auto-run abort prompt, AND lettered blocks in `commands/build.md` and `commands/kickoff.md` (V1 missed these — surfaced by scope + codex reviewers).
- New test `tests/test-spec-qa-formatting.sh` that performs the portable grep check defined in Acceptance.

**Out of scope:**
- Any color rendering — ANSI codes are out per V2 pivot. Color in Claude Code is owned by the theme system (`~/.claude/themes/`), not by model output.
- Any non-pipeline command files (e.g., `commands/wrap.md`, `commands/flow.md`) UNLESS they contain a lettered-choice block. If they do, they're in scope; grep discovery during build is the binding contract for file enumeration.
- Changing the option-letter convention (`a)`, `b)`, `c)`). Keeping the same letters, just changing what's bold.
- Modifying any non-lettered output (synthesis tables, verdict summaries, error banners). Only lettered-choice prompts are in scope.

## Approach

V1 attempted ANSI codes; V2 pivots to markdown-bold-only after `/spec-review` exposed that the ANSI assumption was unverified. Codex (Phase 2b adversary) recommended exactly this pivot path in the review. Bold-on-the-letter, plain-on-the-text gives the same scanability win as colored letters with no rendering risk.

## UX / User Flow

Before (current, bold spans entire option):
```markdown
**Q1 — Scope: What are we building?**

- **a) Option one** — brief description
- **b) Option two** — brief description
- **c) Option three** — brief description

My lean: (a). ...
```

After V2 (bold on letter only):
```markdown
**Q1 — Scope: What are we building?**

- **a)** Option one — brief description
- **b)** Option two — brief description
- **c)** Option three — brief description

My lean: (a). ...
```

Visual result in any terminal Claude Code supports: the question line stays bold (markdown `**...**` already bolds it), the three letters appear bolder than the surrounding text, the option labels and descriptions render in plain weight. The user's eye lands on the question, then on the bolded letters as choice anchors, with the descriptive text in the most readable plain weight. Works regardless of theme, color support, or `NO_COLOR` env — no ANSI to break.

## Data & State

None. No persistence, no config, no env vars. The change is entirely text inside `commands/*.md` instruction files.

## Integration

**Files modified (expected — grep discovery at build is the binding contract per OQ1):**
- `commands/spec.md` — Phase 1 Q&A template; work-size selector; Phase 0.25 session-roster prompt; Phase 0.5 backlog routing rows; Phase 2.5 specialist gap prompt; tag-confirmation prompt; auto-run abort prompt; any other lettered-choice block in this file
- `commands/spec-review.md` — final approval block + any other lettered choices
- `commands/blueprint.md` — final approval block + Phase 0/1 lettered choices (incl. indented blocks inside fenced templates)
- `commands/check.md` — final approval block + Phase 0/1 lettered choices
- `commands/build.md` — any lettered-choice block (added in V2 per scope review)
- `commands/kickoff.md` — domain-agent selector and any other lettered-choice block (added in V2 per scope + codex)
- `tests/test-spec-qa-formatting.sh` — new test file (portable grep check, see AC4)
- `tests/run-tests.sh` — wire new test into orchestrator

**Discovery contract (V2, binding):** at build time, run `grep -rE '^[[:space:]]*-[[:space:]]*\*\*[a-z]\)' commands/` to enumerate every lettered-choice block across all pipeline command files. Every match must be transformed to the V2 form. The discovery grep is the source of truth — the file list above is a lower bound, not an exhaustive enumeration.

**No code changes** — Claude Code already renders markdown bold correctly in model output. We're changing where the bold spans within existing markdown, not adding new rendering.

## Edge Cases

- **NO_COLOR / dumb terminal / piped output:** completely irrelevant under V2 — markdown bold renders consistently across terminal capabilities; no ANSI to strip.
- **Multi-line option descriptions:** the V2 form binds bold to the letter token only (`**a)**`), so option bodies can span lines without breaking the test contract.
- **New lettered-choice blocks added in future commits:** the AC4 test fails CI if a new block uses the old `**a) ...**` form. This is the backstop against drift.
- **Indented lettered blocks inside fenced templates** (e.g., `commands/spec-review.md:245`): the AC4 grep uses `^[[:space:]]*-[[:space:]]*` to match indented bullets — V1 missed these per Codex finding #4.
- **Non-bold or parenthesized letter forms** (e.g., raw `(a)` or unbolded `a)`): the AC4 test treats these as in-scope if they appear in a "choice" context. Build wave converts them to V2 form.
- **The `My lean:` recommendation line and the `[default: x]` hint:** unchanged. Stay outside the lettered-choice block.

## Acceptance Criteria

1. **AC1 — Q&A template updated.** `commands/spec.md` Phase 1 Q&A template uses the V2 form: `- **a)** Option text — description` (bold confined to the letter+paren token). Verified by AC4 grep.
2. **AC2 — All pipeline approval blocks updated.** `commands/{spec-review,blueprint,check}.md` final approval blocks use the V2 form.
3. **AC3 — All other lettered-choice blocks in pipeline commands updated.** Every match of the AC4 discovery grep is in V2 form.
4. **AC4 — Portable grep test exists and passes.** `tests/test-spec-qa-formatting.sh` exists, is executable, runs under `tests/run-tests.sh`, and contains the following portable shell test (works on macOS BSD grep + GNU grep alike):

    ```bash
    #!/bin/bash
    # Assert every lettered-choice block in pipeline commands uses the V2 form.
    # V2 form: optional leading whitespace, "- **a)** " (bold confined to letter)
    # Anti-pattern: "- **a) something**" (bold spans letter + content) — must NOT appear.
    set -euo pipefail
    SCOPE_FILES=(commands/spec.md commands/spec-review.md commands/blueprint.md commands/check.md commands/build.md commands/kickoff.md)
    FAIL=0

    # Discovery: every lettered-choice line in any scope file.
    for f in "${SCOPE_FILES[@]}"; do
      [ -f "$f" ] || continue
      # Find lines matching old form: "- **<letter>) <content>**" (bold extends past close-paren)
      OLD_FORM=$(grep -nE '^[[:space:]]*-[[:space:]]*\*\*[a-z]\)[[:space:]][^*]*\*\*' "$f" || true)
      if [ -n "$OLD_FORM" ]; then
        echo "FAIL: $f contains old-form lettered-choice blocks (bold spans option text):"
        echo "$OLD_FORM" | sed 's/^/  /'
        FAIL=1
      fi
    done

    if [ "$FAIL" -eq 0 ]; then
      echo "PASS: all lettered-choice blocks in pipeline commands use V2 form."
    fi
    exit "$FAIL"
    ```

   The test uses BRE/ERE compatible regex only (no `-P`, no `\x1b`, no `\033` — all portable). Line-precise failure messages report `file:line` for offending blocks.
5. **AC5 — Test wired into orchestrator.** `tests/run-tests.sh` includes the new test file in its run sequence.
6. **AC6 — Visual smoke note in CHANGELOG.** CHANGELOG.md entry under `[Unreleased]` notes the change with a one-line "before/after" reference.
7. **AC7 — Backwards compatibility: no functional regression.** The change is markdown-only; `/spec`, `/spec-review`, `/blueprint`, `/check`, `/build`, `/kickoff` continue to dispatch correctly. Verified by running each command interactively once after the sweep (manual smoke, single-paragraph note in build commit message).

## Open Questions

- **OQ1 — Exact file enumeration:** the build wave discovers blocks by grep across `commands/`. The Integration section's list is a lower bound. (Same as V1; preserved.)
- **OQ2 — Codex review at /check:** small surface, formatting-only, no runtime code path. Default `/check` roster sufficient; Codex optional.

## Backlog Routing

Skipped (small-change rule). The parent backlog item (`spec-qa-terminal-formatting`) IS this spec.

## Lessons captured (V1 → V2)

- **Don't fabricate "existing pattern" claims.** V1 invented a `commands/check.md failure banners use ANSI` precedent that didn't exist. Codex caught it in 5 minutes. Memory `feedback_codex_catches_plan_vs_reality_drift.md` is exactly this pattern; should have read it before claiming.
- **Verify load-bearing assumptions before spec, not at /spec-review.** A 30-second `WebFetch` of `code.claude.com/docs` would have surfaced the ANSI-vs-theme distinction before V1 was written. The cheap research happens before the spec, not as a review finding.
- **The user's "what's next" pattern recognition.** When feedback asks for visual contrast in Claude Code output, the supported levers are: (a) Claude Code theme tokens (for fixed UI roles), (b) markdown formatting in model text (bold, italic, code). Inline ANSI from the model is NOT a supported lever.
