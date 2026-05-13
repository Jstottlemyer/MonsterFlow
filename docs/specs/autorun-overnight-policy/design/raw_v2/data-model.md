# Data-Model v2 — Raw

**Recommendations:**
1. Hand-rolled type+enum validator in `_policy_json.py` (no jsonschema hard dep).
2. `pre_reset_recovery` 5-field block; centralize render in `_policy_json.py.render_recovery_hint()`.
3. `_policy_json.py` hybrid API: pure I/O + flock-mutation + derivers + validators + render helpers.
4. Missing fence with sidecar-era spec → `policy_block check integrity`. Grep fallback only for legacy.
5. STAGE enum 11 stays autorun-local; `findings.schema.json.stage` stays 3 values.

**Open:** `untracked_archive` size_bytes companion? autorun-batch.sh aggregate `runs[]` artifact?
