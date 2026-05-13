# Data Model Design — autorun-merge-policy

## Key Considerations

**Core entities** (5 first-class, 2 derived):

1. **Policy declaration** — `auto_merge_policy: pr | clean | validated` in YAML frontmatter, three sources (spec / constitution / CLI), one runtime resolution.
2. **Resolved policy record** — runtime triple `(value, resolved_from, source_path)` materialized at run start, immutable for the run.
3. **Merge intent outcome** — `(action, reason, forensic_fields)` tuple recorded once per slug to `queue/run.log` as a JSONL event.
4. **Drift signal** — transient comparison between `queue/<slug>.spec.md` and `<project>/docs/specs/<slug>/spec.md` at queue-population time (warning-only, not persisted).
5. **Per-run override** — `queue/<slug>/.manual-review` filesystem touch file (existence-only, no content schema).

**Derived/computed:**
- `is_clean_for_merge()` predicate composing four existing axes (`MERGE_CAPABLE`, `CODEX_HIGH_COUNT`, `RUN_DEGRADED`, `VERDICT`) with one new mode-aware verdict tightening — pure function, no storage.
- `spec_sha` forensic field — `git hash-object queue/<slug>.spec.md` taken once at run start; immutable for the run.

**Read patterns:** resolver reads up to 3 frontmatter files at run-start (cache-once); audit consumers grep/jq the new event row; drift detector reads 2 files + extracts one line at queue-population. All sub-millisecond.

## Recommendation: O2 + O5a + O6b

### Frontmatter (additive, optional)
```yaml
auto_merge_policy: pr | clean | validated   # absent → default 'pr'
```
- Validation at resolve-time; unknown value → exit 2 (AC#7); unknown sibling key → stderr warn + fall through (AC#8).
- Parser: `_gh_frontmatter_field` from `scripts/_gate_helpers.sh:49` (reuse; no public wrapper).

### `merge_policy_resolved` JSONL row (new event type on `queue/run.log`)
```json
{
  "ts":            "ISO8601",
  "slug":          "string",
  "event":         "merge_policy_resolved",
  "policy":        "pr|clean|validated",
  "resolved_from": "cli|spec|constitution|default",
  "action":        "pr_only|auto_merged|fell_back|merge_failed",
  "reason":        "<reason-enum>|null",
  "pr_number":     "int|null",
  "merge_sha":     "sha-string|null",
  "spec_sha":      "sha-string"
}
```

Closed enums: `policy` (3), `resolved_from` (4), `action` (4), `reason` (8). `reason` required iff `action ∈ {fell_back, merge_failed}`. `merge_sha` non-null only when `action == auto_merged`. `spec_sha` always non-null (computed once at run-start).

### Per-run override (filesystem signal)
- Path: `queue/<slug>/.manual-review` (existence-only).
- Lifecycle: created by user before `run.sh`; consumed once per run; not deleted by autorun.
- Effect: forces `action=fell_back, reason=manual_review_requested` regardless of resolved policy.

### Drift detector (transient, no persistence)
Read-compare-warn at `autorun-batch.sh` queue-copy step. Compares one frontmatter line. Cross-project / missing canonical → silent skip. Never halts.

### Schema migration: NONE
Old run.log files have no `merge_policy_resolved` rows; readers ignore unknown event types (existing convention). Old spec.md / constitution.md have no `auto_merge_policy` key; resolver returns `default:pr`. Schema validator gains additive rules only.

### TOFU `.trusted-hashes.json`: NOT IN V1
Spec doesn't include it. `spec_sha` in audit row is sufficient v1 forensic primitive.

## Constraints Identified

- **Bash 3.2** (macOS) — no associative arrays for enum validation; use `case` statements.
- **PIPESTATUS index 0 = printf** when reading `git hash-object | head` — capture inline (per `feedback_pipestatus_or_true.md`).
- **Concurrent autorun runs** — `queue/run.log` is append-only JSONL; multi-writer safe (line-buffered append). No lock needed.
- **Closed enum drift risk** — adding a new `reason` later is technically breaking for strict consumers. Mitigation: persona-metrics-validator should warn on unknown enum values, not fail.
- **`spec_sha` immutability** — capture once at run-start, propagate through to merge-call site as shell variable; don't recompute (queue may be hand-edited).

## Open Questions

- **OQ1:** Should `merge_policy_resolved` rows include `gate_mode` for forensic continuity? **Lean: yes** — one extra field, big payoff for asymmetric-risk diagnostic.
- **OQ2:** `stat -f %Su` to capture user who touched `.manual-review`? Probably no for v1 (platform-specific; user identity is in git log).
- **OQ3:** Validator's policy on unknown `reason` literals — warn or fail? Recommend warn (forward-compat).

## Integration Points

- `scripts/_gate_helpers.sh:49` — reuse `_gh_frontmatter_field` (read-only).
- `scripts/autorun/_merge_policy.sh` (NEW, ~120 LoC) — owns `merge_policy_resolve`, `merge_policy_validate`, `is_clean_for_merge`, `merge_policy_render_banner`, `merge_policy_dispatch`, `log_merge_policy_resolved`.
- `scripts/autorun/run.sh:667` — already exports `$SPEC_FILE=$QUEUE_DIR/${SLUG}.spec.md`.
- `scripts/autorun/run.sh:1069-1102` — existing four-axis gate; mode-aware verdict tightening composes, doesn't replace.
- `scripts/autorun/autorun-batch.sh` — `--auto-merge=` CLI flag + drift detector at queue-copy.
- `queue/run.log` — additive event type only.
- `<project>/docs/specs/constitution.md` — runtime read path; created by `install.sh` from `templates/constitution.md`.
- `templates/constitution.md` — commented-out `auto_merge_policy:` example.
- `queue/<slug>/.manual-review` — new touch-file convention; user-managed.
- persona-metrics-validator subagent — additive schema rule; no FK changes; AC#29 verifies unaffected.
- autorun-shell-reviewer subagent — must clean-review new helper + run.sh diff (AC#28).

## Findings (v2 schema)

```yaml
- persona: data-model
  finding_id: dm-001
  severity: minor
  class: contract
  title: "Add gate_mode to merge_policy_resolved JSONL row for post-incident forensics"
  body: "Audit row captures policy/resolved_from/action/reason/pr_number/merge_sha/spec_sha but not the resolved gate_mode. Under permissive+clean composition (the asymmetric-risk axis this spec exists to manage), forensics need to know which mode authorized the merge."
  suggested_fix: "Add 'gate_mode' field (closed enum: strict|permissive) to the merge_policy_resolved row schema. Update AC#9. persona-metrics-validator gains one additive rule."

- persona: data-model
  finding_id: dm-002
  severity: minor
  class: contract
  title: "Document unknown-enum-literal forward-compat policy for run.log readers"
  body: "Closed enums (action 4 values, reason 8 values) protect the schema today but make any v1.1 enum addition technically breaking for strict consumers."
  suggested_fix: "Pin the policy: 'unknown enum literals on additive event types emit a warning, not a failure'. Apply to both action and reason fields."

- persona: data-model
  finding_id: dm-003
  severity: nit
  class: documentation
  title: "TOFU .trusted-hashes.json is out of scope for v1 — note explicitly"
  body: "Plan brief mentioned TOFU trusted-hashes as a possible data element, but spec includes no AC. spec_sha in audit row is sufficient v1 forensic primitive."
  suggested_fix: "Add to Out-of-scope: 'TOFU trusted-hashes file (.trusted-hashes.json) — spec_sha in run.log is the v1 forensic primitive; trust-over-time logic is a future spec.'"
```
