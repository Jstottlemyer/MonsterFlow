# Security v2 — Raw

**Critical findings:**
1. **D33 first-fence vulnerable.** Spec body containing literal check-verdict fence is captured before synthesis. **Use LAST fence; reject if >1 `check-verdict` fence.**
2. **`pre-reset-untracked.tgz` path-traversal:** capture-side filter rejects `/`, `..`, control chars, symlinks-out-of-tree. Recovery uses `mkdir recovery && tar xzf ... -C recovery/`.
3. **`run_id` provenance:** uuidgen-derived, regex `^[0-9a-f]{8}-...`. Validate at startup; fail-fast.
4. **`_policy_json.py` stdlib-only:** no subprocess/os.system/eval/exec. CI grep test.
5. **Centralized lock fail-closed test:** flock-absent + mkdir-fallback race torture.
6. **`gh pr create` mock harness redacts** `gho_*`/`ghp_*`/`github_pat_*`.
7. **`AUTORUN_CURRENT_STAGE` re-validation at consume site:** `policy_act` re-validates every call.

**Spec edits:** AC#13 (run_id format), AC#14 (path-traversal filter), AC#25 (last-fence + reject-multi).

**Open:** strict reject-multi-fence (yes — surfaces injection as integrity_block); ref overwrite policy (no-old-value + suffix `-2`).
