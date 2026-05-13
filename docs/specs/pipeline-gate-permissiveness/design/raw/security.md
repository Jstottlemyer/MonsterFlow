## Summary (security persona — full output captured in conversation)

**Threat model anchoring:** reviewers good-faith, not adversarial. Persona's job is fail-closed against bugs/accidents. Adversarial-injection lives in autorun-verdict-deterministic.

**Trust boundary inventory:**
1. Reviewer persona output (good-faith, possibly malformed) → Judge consumes
2. /build writing addressed_by SHA → followups consumes
3. CLI flag --force-permissive → mode resolver consumes
4. .followups.jsonl.lock filesystem state → all gates consume
5. Constitution gate_policy.mode → mode resolver consumes

**class↔sev parity (recommended Option S4 — hybrid, runtime authoritative):**
- JSON Schema enforces presence + enum-validity of each field independently
- `_policy_json.py` enforces parity in `_enforce_class_sev_parity()` after schema validation, before policy decision
- On mismatch: coerce row to `class: unclassified, sev: unclassified` AND append to `security_findings[]` with `kind: "class_sev_mismatch", original_class, original_sev, persona, finding_id`
- Defense-in-depth via composition with unclassified=block

**`unclassified` fail-closed verification (CRITICAL hardening):**
The fail-closed chain holds **if and only if** `unclassified == block` is HARDCODED, not configurable. If `unclassified` blocking is implemented as just-another-row in the gate_policy table, an adopter can disable it through constitution edits. **Recommend: hardcode `unclassified == block` and explicitly reject any constitution that tries to override it** (constitution-validation failure on attempt). Add invariant test.

**`--force-permissive` audit (recommended F2 + F3 BOTH):**
- Stderr banner (interactive case)
- `security_findings[]` row of `kind: "force_permissive_invoked"` with invoker/timestamp/working_tree_sha/mode_source — propagates through autorun's surfacing path so it's NOT invisible to overnight policy logs
- **Hardening: refuse `--force-permissive` if `$CI` or `$AUTORUN_STAGE` env vars are set** (force-permissive is interactive escape hatch; mixing with automation is almost certainly wrong)

**Lock TTL (recommended Option L3 — PID liveness primary, mtime fallback):**
- Lock file content: `{pid, hostname, started_at, gate, spec}`
- Reclaim rules in order:
  - `hostname != current_hostname AND mtime > 10min ago` → reclaim, log `lock_reclaim_reason: "cross_host_stale"`
  - `hostname == current_hostname AND kill -0 $pid` fails → reclaim, log `lock_reclaim_reason: "pid_dead"`
  - `mtime > 10min ago` regardless → reclaim, log `lock_reclaim_reason: "mtime_exceeded"` (last-resort: handles PID recycling)
- 10 min TTL > TIMEOUT_PERSONA (600s); buffer of 100s slack
- Every reclamation appends to `security_findings[]` with reason

NOTE: scalability persona recommends `fcntl.flock` (kernel auto-cleanup); reconciliation needed. Lean: fcntl.flock primary (kernel handles death cleanup); add lock-file metadata + mtime fallback ONLY if cross-host or PID-recycle scenarios materialize.

**`addressed_by` SHA trust:** acceptable as-is. State explicitly: "Trust derives from git log auditability and the assumption that repo-write access is restricted to trusted contributors. Anyone able to write a fake SHA can already push arbitrary code." One-paragraph spec addition under "Threat Model" section.

**Codex at /check (BACKLOG-mandatory):** /spec-review-level Codex doesn't satisfy /check-level Codex. Different artifact, different drift surface (plan-vs-codebase rather than spec-internal-coherence). **Add a single line to spec body: "This spec's /check MUST include a Codex review pass per BACKLOG codex-review-per-spec (architectural/integrity-sensitive change)."**

**Constraints:**
- `unclassified` MUST be hardcoded `block` floor, not configurable
- Lock file must store `{pid, hostname, started_at}` not just `{pid}`
- Verdict JSON schema must include `security_findings[]` (verify with /plan)
- Autorun stage runners must surface `security_findings[]` to operators
- Lock TTL (10 min) must be longer than TIMEOUT_PERSONA (600s) — currently equal; bump to 700s buffer
- `--force-permissive` with `$CI` or `$AUTORUN_STAGE` set should refuse-with-error

**Open Questions:**
- Q1: verdict JSON schema already defines `security_findings[]`? Yes (verified — autorun v6 schema)
- Q2: autorun's existing surfacing path picks up security_findings today? Yes (hardcoded carve-out at scripts/autorun/check.sh sec_count > 0)
- Q3: `unclassified` hardcoded today? Need to check; likely needs to BE hardcoded as part of this spec
- Q4: --force-permissive require explicit reason string? Lean YES (cheap, useful post-hoc) — `--force-permissive="reason"`
- Q5: cross-host execution today? No (single-host); cross-host arm of L3 is dead code; can simplify

**New ACs proposed:** four explicit fail-closed test cases — class missing, class invalid enum, class+sev mismatch, constitution attempting to demote unclassified. All produce verdict block + security_findings[] entry with correct kind.
