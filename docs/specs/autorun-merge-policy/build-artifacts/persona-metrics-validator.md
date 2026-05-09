# persona-metrics-validator — contract verification (AC#29)

**Feature:** autorun-merge-policy
**Fixture:** `tests/fixtures/autorun-policy/post-merge-run-log/run.log`

**Verdict: AC#29 SATISFIED — validator contract unaffected by new event type.**

## What was verified

### (1) run.log fixture compatibility — PASS

Fixture path: `tests/fixtures/autorun-policy/post-merge-run-log/run.log`

Contents (4 rows, NDJSON):

| Line | event | run_id | slug | action / policy |
|---|---|---|---|---|
| 1 | `merge_policy_resolved` | `20260508-120000-autorun-merge-policy` | `autorun-merge-policy` | policy=pr |
| 2 | `merge_action_completed` | `20260508-120000-autorun-merge-policy` | `autorun-merge-policy` | action=pr_only, pr_number=42 |
| 3 | `merge_policy_resolved` | `20260508-130000-other-feature` | `other-feature` | policy=clean |
| 4 | `merge_action_completed` | `20260508-130000-other-feature` | `other-feature` | action=auto_merged, merge_sha=f00ba12... |

Properties confirmed:

- All 4 lines parse as well-formed JSON.
- Each `run_id` has exactly **one start (`merge_policy_resolved`) + one end (`merge_action_completed`)** row, joinable on `run_id` per spec D22.
- `slug` field is consistent across each (start, end) pair.
- The new event types (`merge_policy_resolved`, `merge_action_completed`) live in `run.log` only — they are NOT findings/participation/survival schema rows.

### (2) Existing persona-metrics integrity — INFORMATIONAL

The validator's checked schemas are `findings.jsonl`, `participation.jsonl`, and `survival.jsonl` under `docs/specs/<feature>/<stage>/`. The validator never reads `run.log`.

Scanned `docs/specs/autorun-merge-policy/{spec-review,plan,check}/`:

- No `findings.jsonl` / `participation.jsonl` / `survival.jsonl` files exist (this feature predates per-stage persona-metrics emission, or the autorun run did not write the triple).
- `selection.json` (check stage) is well-formed with `selection_method: "full"`, 6 selected personas, no drops — eligible to contribute to the cross-feature drift baseline once persona-metrics JSONLs are emitted.
- No schema, foreign-key, or `artifact_hash` issues.

## Conclusion

The new merge-policy event types (`merge_policy_resolved`, `merge_action_completed`) are confined to `run.log`, which is **out of scope for the persona-metrics-validator**. The validator's schemas (findings/participation/survival) are untouched. No validator code change is required to ingest these new rows.

**AC#29 satisfied: persona-metrics-validator contract verified unaffected by new event type, against the post-merge run.log fixture.**

## Provenance

- Agent id: `a8f11e1ddb2d5ef6e`
- Date: 2026-05-08
