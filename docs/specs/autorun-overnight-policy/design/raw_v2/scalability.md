# Scalability v2 — Raw

**Recommendations:**
1. Cap `pre-reset-untracked.tgz` (REQUIRED): `tar --exclude` for node_modules/.venv/venv/target/build/dist/.next/.nuxt/__pycache__; 100MB hard cap; on overflow → delete + `.SKIPPED` marker.
2. Document Python startup cost ~1.5-2s/run (acceptable).
3. Fenced JSON parser as state machine (depth-tracking).

**Constraints:** BSD `tar --exclude`; `wc -c < file` for size; macOS `/usr/bin/python3` stub.

**Open:** cap configurable (yes); cap-trip continue + marker; nested-fence fixture from real synthesis.
