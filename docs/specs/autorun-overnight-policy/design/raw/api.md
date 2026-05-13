# API Design — Raw

### Key Considerations
1. Helper API surface symmetry — `policy_warn`/`policy_block` imperative; `policy_for_axis` declarative; `policy_act` collapses both. Three call shapes for one concept invites callers to pick the wrong one. Doc-comment block at top of `_policy.sh` explaining "use `policy_act` for axis-tunable; `policy_block` directly only for hardcoded carve-outs."
2. `policy_act` infers stage from `$AUTORUN_CURRENT_STAGE` — if unset, stderr emits empty stage field and warnings[] entry has empty `stage`. Spec gap: no fail-fast for missing stage context.
3. No explicit getter for `RUN_DEGRADED` or warn count — every caller re-implements `_json_get .warnings[] | wc -l`. Add `policy_run_degraded` (returns 0 if degraded, 1 if clean) and `policy_warn_count`.
4. `_json_get` exit-code semantics double-duty — callers can't distinguish "key absent" from "file missing" from "JSON malformed." Need distinct codes (1=key absent, 2=file missing, 3=malformed).
5. CLI surface is `--mode` only — no `--dry-run`, no `--state-dir`, no `--run-id`. For testability, `--state-dir` override + `--dry-run` (validate config + exit) useful.
6. Stderr format human-grep-able but not structured — risk: reasons containing `"` break grep grammar. Reason should be JSON-encoded in BOTH places (stderr and JSON write).
7. Schema versioning has no negotiation protocol — when v2 ships, does autorun emit v1+v2 during overlap? Or hard cutover?
8. `finding_id` derivation shared across schemas but no shared helper — drift risk. Worth a `_finding_id NORMALIZED_TEXT` helper.

### Recommendation
**Option B — Add three additive helpers to spec's 6-function contract:**
- `policy_run_degraded` — returns 0 if `len(warnings) > 0`, 1 otherwise
- `policy_warn_count` — echoes integer count of warnings
- `_finding_id NORMALIZED_TEXT` — echoes `ck-<10-hex sha256 prefix>`

Plus three contract clarifications:
- Stderr `reason` is JSON-encoded
- `policy_act` fail-fasts if `AUTORUN_CURRENT_STAGE` unset
- `_json_get` exit codes: 0 success, 1 malformed, 2 missing, 3 key absent

Add `--dry-run` and `--state-dir=<path>` to `run.sh` CLI.

### Constraints Identified
- bash 3.2: no assoc arrays, `${arr[-1]}` is bash 4
- Sourced helper × set -e × trap interactions
- flock availability via Homebrew util-linux
- uuidgen availability fallback (`od -An -N16 -tx1 /dev/urandom`)
- jq optional, python3 floor
- Existing autorun convention: `_<name>.sh` for sourced helpers
- CLI parsing hand-rolled in bash (no getopt)

### Open Questions
1. Should `policy_act` fail-fast on missing `AUTORUN_CURRENT_STAGE`?
2. Should `--state-dir` override be supported?
3. Schema-version evolution: hard cutover or overlap?
4. Should `_finding_id` be in `_policy.sh` or separate?
5. `policy_for_axis` on hardcoded axes — echo `block` or fail-fast?

### Integration Points
- data-model: `_json_get`/`_json_escape` are read/write contract; `finding_id` derivation must match `findings.schema.json`
- ux: `--mode`, stderr lines, `morning-report.md` are user surfaces
- security: hardcoded carve-outs bypass `policy_for_axis`; refuse `AUTORUN_SECURITY_POLICY`/`AUTORUN_INTEGRITY_POLICY`
- integration: 5 stage scripts source `_policy.sh`; uniform sourcing convention
- wave-sequencer: `_policy.sh` Wave 1 foundation; tests ship same wave
