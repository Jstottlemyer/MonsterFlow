# Data Model Design — Raw

### Key Considerations
- Schema family alignment: 3 new JSON artifacts must coexist with existing `findings.schema.json` — `schema_version` integer, `prompt_version` string, `finding_id: <stage-prefix>-<10+ hex>` from sha256(normalized_signature).
- Three artifacts, three lifecycles: `run-state.json` mutable append-only; `morning-report.json` immutable write-once; `check-verdict.json` immutable, lives in spec dir (not run dir).
- `finding_id` for check-verdict: degenerate single-element case of cluster algorithm — same canonicalization, single input.
- `check-verdict.json` should also carry `prompt_version: "check-verdict@1.0"`.

### Options Explored
1. **run-state.json location** — (a) `queue/runs/<run-id>/` ✅ (spec choice); (b) per-slug; (c) global single. Recommend (a).
2. **Atomic-update pattern** — (a) flock + tmp + mv ✅ + reserve `events.jsonl` shadow path for future; (b) append-only JSONL events; (c) sqlite. Recommend (a) with future shadow.
3. **policy_resolution storage** — (a) resolve once at startup ✅; (b) recompute per-call. Recommend (a).
4. **Schema evolution** — (a) strict-reject ✅; (b) best-effort. Recommend (a).
5. **Run retention** — (a) never auto-delete + gitignore + doctor.sh nudge ✅; (b) keep last N; (c) merged-PR rotation. Recommend (a) with size warning at 500MB.
6. **pre-reset.patch format** — (a) git diff text; (b) git stash create SHA; (c) Both + anchor stash to ref ✅. Recommend (c) with `git update-ref refs/autorun-recovery/<run-id>`.

### Recommendation
1. Add `prompt_version: "check-verdict@1.0"` to check-verdict.json schema.
2. Pin finding_id derivation explicitly: NFC-normalize, lowercase, whitespace-collapse, sha256, first 10 hex, prefix `ck-`.
3. Author `schemas/morning-report.schema.json`, `schemas/run-state.schema.json`, `schemas/check-verdict.schema.json` together with `$defs` for shared shapes.
4. Reserve `events.jsonl` shadow path for future recovery aid.
5. Persist resolved policy at startup, never re-resolve.
6. Strict-reject schema_version mismatch via shared `_json_check_schema_version()` helper.
7. `git update-ref refs/autorun-recovery/<run-id>` to anchor stash; add `recovery_ref` to morning-report.
8. Gitignore `queue/runs/` + doctor.sh size nudge at 500MB.
9. Migration: fresh start, no backfill.
10. Schema evolution: dual-version readers explicitly switch on schema_version when v2 ships.

### Constraints Identified
- bash 3.2 + jq optional
- flock availability on macOS
- POSIX rename atomicity (APFS provides)
- finding_id collision: 10 hex = 40 bits ≈ 1 in 1M at 1000 findings — acceptable
- `current` symlink staleness — readers must check liveness via lockfile PID
- check-verdict.json location: `docs/specs/<slug>/`, NOT `queue/runs/<run-id>/`
- schema_version is integer, not string

### Open Questions
1. `run-state.json` `completed_at` field — null initially, set on final write
2. `model_per_persona` map for forward-compat
3. morning-report `warnings[]`/`blocks[]` — verbatim copy or filter? Recommend verbatim
4. `policy_resolution.<axis>.source` enum: `["cli-mode", "env", "config", "default", "hardcoded"]`
5. Where does `codex_high_count` come from? presumably spec-review.sh writer, run.sh reader

### Integration Points
- `findings.schema.json` — existing precedent
- `run.sh` — generates run_id, creates per-run dir, manages `current` symlink, lockfile
- `_policy.sh` — owns all run-state.json mutations; houses `_json_get`, `_json_escape`, `_json_check_schema_version`
- `commands/check.md` — synthesis emits both artifacts
- `notify.sh` — sole consumer of morning-report.json
- `doctor.sh` — config + flock + queue/runs/ size checks
- `.gitignore` — `queue/runs/`
- Future `autorun-artifact-contracts` — finding_id derivation enables zero-cost join
- `.claude/agents/autorun-shell-reviewer.md` — schema_version strict-reject pattern, atomic-write idiom, JSON-escape
