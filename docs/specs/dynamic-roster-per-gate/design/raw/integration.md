## Integration Persona — dynamic-roster-per-gate

### What is shipped vs. pending:
- `fit_tags:` frontmatter on all 19 personas: DONE (commits 25c8cd2 + 2d0a005)
- `schemas/persona-frontmatter.schema.json` with `fit_tags` required field: PRESENT
- `schemas/selection.schema.json`: NOT FOUND — this is a W1 deliverable that has NOT shipped; everything downstream gates on it
- `scripts/_persona_score.py`, `_tier_assign.py`, `_tag_baseline.py`: NOT PRESENT — all W2
- `scripts/resolve-personas.sh`: EXISTS but has no tier/tag-matching logic yet

### Integration Risks

**M1 (lineage default) — MEDIUM:** `persona-rankings.jsonl` rows may lack `lineage` field. Fix: `_persona_score.py` must default `missing lineage → "claude"` at load time. One-line guard, not a schema change.

**M2 (autorun dep graph) — HIGH, BLOCKING:** Old plan had task 23 (`autorun/spec-review.sh`) depending on `12,16` (spurious dep on check-gate backfill task). Correct deps:
- Task for `autorun/spec-review.sh`: depends on resolver (task 12) + `commands/spec-review.md` task
- Task for `autorun/plan.sh`: depends on task 12 + `commands/plan.md` task
- Task for `autorun/check.sh`: depends on task 12 + `commands/check.md` task

**MF-1 (empirical model dispatch test) — HIGH, BLOCKING:** Task 7 currently in W2 parallel. Must move to W1.5 blocking gate. `plan/dispatch-precedence-evidence.md` must exist before any resolver or tier-dispatch code is written.

**MF-3 (constitution rename) — RESOLVED:** Constitution rename carved to sibling spec. No W1-W5 code touches `docs/specs/constitution.md`.

### Recommendations on Wave Ordering

1. Add W1.5 blocking slot: task 0 (empirical precedence test). W2 gates hard on W1.5 output.
2. Fix task 23 dep: change from `12,16` to `12,[spec-review-command-task]`.
3. Add lineage guard to `_persona_score.py` description explicitly.
4. Tasks `_tag_baseline.py` + resolver coordination: `_tag_baseline.py` must expose `recompute_baseline(spec_body)` so resolver can call it at dispatch for SEC-04 assertion.
5. `selection.schema.json` is W1 blocker: all W2+ gates on task 2 (schema creation).

### Constraints Identified

- `schemas/selection.schema.json` does not exist yet — all schema guards and lockstep CI depend on it being created in W1
- `persona-rankings.jsonl` in `dashboard/data/` is untracked in git; confirm it's gitignored (per existing memory)
- Dashboard tasks must read `selection.json` defensively (field absent = "N/A") during MVP window

### Open Questions

1. Does moving task 7 to W1.5 create a timeline problem (empirical test requires live Claude API call — cannot be stubbed)? If so, document as manual gate with required sign-off artifact.
2. If D7 fallback needed (model param ignored): block W4 or carve to follow-up? Recommend: block and pivot.
3. Dashboard task reads `tier_policy_applied` — confirm defensive read (field absent → "N/A") so dashboard doesn't break during MVP window.

### Integration Points Summary

| Layer | Status | Gap |
|---|---|---|
| `schemas/persona-frontmatter.schema.json` | SHIPPED | — |
| `schemas/selection.schema.json` | NOT FOUND | W1 task 2; everything downstream gates |
| `scripts/resolve-personas.sh` | EXISTS (no tier logic) | W2 extends it |
| `commands/{spec-review,plan,check}.md` | EXISTS (no Phase 0b) | W4 tasks; each depends on resolver only |
| `scripts/autorun/{spec-review,plan,check}.sh` | EXISTS | M2 dep fix needed |
| Python helpers | NOT PRESENT | W2 tasks; gate on W1 schemas + W1.5 empirical |
| `dashboard/index.html` + bundle script | EXISTS | W5; read selection.json defensively |
| `persona-rankings.jsonl` | UNTRACKED | lineage default covers MVP window |
