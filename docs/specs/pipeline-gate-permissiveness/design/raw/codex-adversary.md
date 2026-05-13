**Findings**

1. **Blocker: v2-only schema bump can break all legacy consumers at once.**  
Strict v2-only is clean, but the plan still says pre-v0.9.0 `/build` behaves “as today” while `/build` also starts reading the most-recent sidecar. That needs an explicit legacy-detection branch: missing sidecar, v1 sidecar, malformed v2 sidecar, and stale `check-verdict.json` from another gate must not collapse into either “proceed” or “hard fail” accidentally.

2. **Blocker: sidecar naming is underspecified for non-`/check` gates.**  
Reusing `check-verdict` for `/spec-review`, `/plan`, and `/check` risks overwriting the “latest verdict” with the wrong stage. `/build` verifying `check-verdict.json or equivalent stage sidecar` is too vague. If `/plan` emits `check-verdict.json`, then `/build` may accept a plan verdict even when `/check` never passed. Require per-stage files, e.g. `spec-review-verdict.json`, `plan-verdict.json`, `check-verdict.json`, with `/build` checking the required stage explicitly.

3. **Major: flock correctness depends on filesystem and shell boundary details not yet specified.**  
`fcntl.flock` via Python is fine on local POSIX filesystems, but the plan needs the helper contract: open mode, blocking timeout, stale-lock behavior, lock held across read/mutate/write/rename/render, and whether `followups.md` rendering is inside the same critical section. Also avoid relying on lock-file deletion for release; release should be fd close. On NFS/sync folders, `flock` semantics may be weak, so at minimum document local-worktree assumption.

4. **Major: strict mode leaving old `followups.jsonl` intact creates audit clarity but poor state semantics.**  
The plan says strict mode does not regenerate followups, but still references existing `followups_file`. That can mislead humans and tooling: open warn-routed rows from a permissive run may remain visible even though the current strict verdict blocks them. Consider writing a verdict-scoped `followups_consumable: false` or having `/build` require both `verdict ∈ {GO, GO_WITH_FIXES}` and `verdict.mode != strict || followups_generated_at == verdict.generated_at`.

5. **Major: iteration ownership is split enough to produce off-by-one bugs.**  
“Synthesis owns iteration counter” but autorun extraction bound-checks it. The examples use `iteration: 3`, `iteration_max: 2`, `cap_reached: true`, while edge case 3 says clean reinvocation resets to 1. That distinction needs a persisted/run-local source of truth. Otherwise manual reruns, failed Synthesis retries, or validator re-emits can increment incorrectly and auto-promote too early.

6. **Major: `unclassified=block` is right, but it can deadlock rollout during persona migration.**  
Template-first batching means one approved template then 27 edits. Any missed persona, old cached prompt, or nonconforming reviewer output turns into `unclassified` and blocks every permissive gate. Add a migration fixture that runs every modified persona/template path, plus a temporary diagnostics mode that reports which persona omitted/invalidated `class:` without requiring a full gate rerun.

7. **Major: taxonomy scope-cuts defer real operational risks into vague buckets.**  
Deferring data-loss, migration-risk, performance, observability, rollback, and supply-chain to v2 is a dangerous scope cut because this feature changes gate behavior. “Architectural if structural, contract if pin-shaped” is subjective and easy to warn-route. At minimum add explicit v1 carve-outs: data loss, irreversible migration, release rollback failure, and supply-chain risk must block.

8. **Minor: persona-prompt drift is likely across three gate families.**  
Updating `personas/{review,plan,check}/*.md` by batch can create subtly different class definitions, precedence orders, and output schemas. Put the taxonomy in one included/shared prompt fragment if the system supports it; otherwise add a generated checksum/sentinel block so drift is detectable in review and CI.