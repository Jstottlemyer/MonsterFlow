# UX Design — Raw

### Key Considerations
- 7am triage problem — open one file, know in <30s. 3 failure modes: ambiguous final state; buried recovery path; silent default-shift for adopters.
- 4-state mental model is one too many: `merged`/`halted` are clean poles; `pr-awaiting-review`/`completed-no-pr` both mean "no merge" for opposite reasons.
- Stderr policy log lines vs morning-report — different audiences (live tail vs triage).
- `AUTORUN_INTEGRITY_POLICY`/`AUTORUN_SECURITY_POLICY` startup error must teach, not just reject.

### Options Explored
- **Option A — Headline-first morning-report** ✅: `## <Status>` headline + one action sentence + tables for warnings/policy + artifacts list.
- **Option B — Timeline-style** (one row per stage): debug-friendly but buries headline.
- **Option C — Slack-style notification block**: 4 distinct first-words (MERGED, PR awaiting review, HALTED, no PR created).

### Recommendation
**Option A morning-report shape + Option C notifications + Timeline as sub-section.**

Renderer rules:
1. Headline by `final_state`:
   - `merged` → `## Merged to main`
   - `pr-awaiting-review` → `## PR awaiting review — degraded run`
   - `halted-at-stage` → `## Halted at <stage> — needs attention`
   - `completed-no-pr` → `## No PR created — artifacts only`
2. Headline followed by ONE sentence telling Justin what to do.
3. Branch reset recovery: inline copy-paste commands with **resolved absolute paths and actual SHA** (not template placeholders).
4. Error format: 3-line shape (what failed, why, how to fix):
   ```
   INVALID_FLAG: --mode="overnigth" — must be "overnight" or "supervised"
     config layer: cli
     fix: scripts/autorun/run.sh --mode=overnight <slug>
   ```
5. Hybrid composition example block in spec + README showing env-override + policy_resolution table.
6. Deprecation warnings go to BOTH stderr AND morning-report `## Deprecation notices` section.
7. doctor.sh adopter warning: lettered three-fix block (a/b/c) — three complete copy-pastes, each a one-line fix.

### Constraints Identified
- morning-report.md is rendered (not authored) — deterministic from morning-report.json
- Notification strings <120 chars (macOS truncates ~256)
- `final_state` enum is wire format; renaming requires schema bump
- Resolve absolute paths and SHA values in templates
- bash 3.2: heredocs with `${VAR}` substitution only

### Open Questions
1. Include `OVERALL_VERDICT` first paragraph? Recommend: only when `halted-at-stage` AND `blocks[].axis=verdict` (truncated 280 chars).
2. notify.sh: one notification per run (with summary count), not per-warning.
3. Previous-run comparison ("3rd consecutive degraded") — backlog warn-streak counter.
4. PR CI status at completion — add `pr_checks_at_completion` field.

### Integration Points
- `commands/morning-report.md` (new) or section in `commands/autorun.md` — pin renderer mapping
- `scripts/autorun/_render_morning_report.sh` (new) — isolated renderer, lean run.sh
- `scripts/autorun/notify.sh` — 4-line lookup table inline in spec
- README §Autorun — hybrid composition example + adopter callout
- `scripts/doctor.sh` — three-option lettered fix block
- `personas/check/security-architect.md` — UX example block showing tag's exact syntax
- CHANGELOG.md — "External adopters: action required" header
- `plan.md` — §Renderer Contract section pinning the headline mapping

The 30-second triage test: open `queue/runs/current/morning-report.md`, read first 5 lines, know what to do.
