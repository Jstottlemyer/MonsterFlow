## Summary (integration persona — full output captured in conversation)

**Integration story holds; 4 gaps and 2 ambiguities to nail before /build:**

**`scripts/autorun/check.sh` analysis:**
- Existing extractor (v6) already handles `verdict ∈ {GO, GO_WITH_FIXES, NO_GO}` cleanly (lines 248-273)
- `GO_WITH_FIXES` already invokes `policy_act verdict "go_with_fixes"` and continues
- **Required new code:** read `iteration` / `iteration_max` / `cap_reached` from sidecar via `python3 _policy_json.py get $SIDECAR /iteration`; use for re-cycle termination if autorun is iteration driver
- **DO NOT TOUCH the `sec_count > 0` block (line 241)** — load-bearing for class:security ↔ sev:security parity (A17). Synthesis populates BOTH `security_findings[]` AND tag findings sev:security so this gate keeps firing without modification.

**`_policy_json.py` validator: zero code change required.**
- The validator is generic. Bumping schemas/check-verdict.schema.json suffices.
- `additionalProperties: false` enforcement already correct (lines 354-361)
- KNOWN_SCHEMAS tuple needs `"followups"` added (1-line edit)
- `cmd_validate` reads whatever schema is on disk and walks it generically

**Schema-version branch: strict v2-only (recommended).** Single-PR lockstep eliminates dual-version case. Refuse v1 verdicts after the bump; CI guard catches partial landings. Don't dual-version the schema (every-future-bump-needs-a-branch debt for single-writer single-reader system).

**Iteration-counter ownership AMBIGUITY: synthesis owns it (option A) with bound-checking at extraction.**
- Two valid designs: (A) Synthesis writes to verdict, autorun reads back; (B) Autorun owns counter
- Spec implies (A); generalizes to interactive /check (no autorun loop counter exists there)
- (A) requires trusting LLM-emitted integers in control flow → mitigation: bound-check (`0 < iteration ≤ iteration_max + 1`) at `extract_and_decide`; block on out-of-range
- 4-line addition

**Persona file batching (Option B recommended): template-first per `feedback_template_first_batching.md`.**
- New `personas/_templates/class-tagging.md` + sed/awk splice script `scripts/apply-class-tagging-template.sh`
- Idempotency sentinel: `<!-- BEGIN class-tagging -->...<!-- END class-tagging -->`
- Splice BEFORE each persona's `## Verdict Format` heading (consistent across personas); end-of-file fallback otherwise
- Personas with semantically unique tags (e.g., security-architect's sev:security block) get the template IN ADDITION (not instead of)
- `tests/test-class-tagging-spliced.sh` greps every persona for sentinels; fails CI on drift

**`personas/judge.md` and `personas/synthesis.md`** are at top-level `personas/`, NOT under `personas/{review,plan,check}/`. The repo file is the source; install.sh's symlink propagates to `~/.claude/personas/`. **Edit the repo file; symlink propagates.**

**`commands/spec.md` Phase 3 frontmatter format mismatch:**
- Template uses human-readable `**Field:**` style; actual spec at `docs/specs/pipeline-gate-permissiveness/spec.md` uses YAML `---` frontmatter blocks
- Plan must reconcile — likely hybrid: YAML frontmatter at top (where gate knobs live), human-readable headers in body
- Insertion point: between `**Confidence:**` and `**Session Roster:**` lines

**`install.sh` upgrade banner:** existing PRIOR_INSTALL detection block (lines 283-305) is symmetric with what spec asks. Add ONE bullet to existing `<<UPGRADE` heredoc:
```
- Pipeline gates default to permissive (was: strict). Pin gate_mode: strict in any spec frontmatter to preserve old halt-on-anything behavior.
```
Idempotency: existing pattern fires on every upgrade run; for "exactly once" semantics, gate the heredoc on absence of `~/.claude/.gate-permissiveness-migration-shown` sentinel.

**`/wrap-insights` Phase 1c integration:** 2-3 line addition in `scripts/_render_persona_insights_text.py`: `row.get('class', 'unclassified')` and filter `if row.get('class') != 'unclassified'` for class-stratified stats. NOT in `compute-persona-value.py`.

**Constraints:**
- Lockstep non-negotiable; partial PRs break autorun on first run after merge
- `personas/judge.md` and `personas/synthesis.md` at top-level; splice script must NOT recurse into them
- `_policy_json.py` AST-banlist-audited (lines 8-10); no new subprocess/eval/dynamic-import
- bash 3.2 compatibility for autorun shell changes
- `autorun-shell-reviewer` subagent must run before committing changes to `scripts/autorun/check.sh`
- `commands/spec.md` template frontmatter format mismatch needs resolution
- `PERSONA_METRICS_GITIGNORE` block in install.sh missing `docs/specs/*/followups.jsonl` — add it
- Highest-class-wins precedence string must appear verbatim in `personas/judge.md`

**Recommended landing order (single PR):**
1. Schema bump first (3 schema files)
2. _policy_json.py: no code change; add v2 fixture test
3. `personas/_templates/class-tagging.md` + splice script
4. `personas/judge.md` + `personas/synthesis.md` (single-file each, hand-edited)
5. `commands/{spec-review,plan,check,build,spec}.md` edits
6. `scripts/autorun/check.sh`: read iteration/iteration_max/cap_reached + bound-check
7. `scripts/render-followups.py` (NEW)
8. `install.sh`: append upgrade bullet
9. `/wrap-insights` Phase 1c: 2-3 lines in `_render_persona_insights_text.py`

**Open Questions:**
- Q1: bound-check only (cross-check is autorun-verdict-deterministic's problem)
- Q2: `commands/spec.md` YAML migration as follow-up (scope-disciplined)
- Q3: `gate_max_recycles` clamp logic in new `scripts/_gate_helpers.sh` sourced by all 4 gate commands
- Q4: migration banner one-shot semantics → sentinel file `.gate-permissiveness-migration-shown` matches AC16
