---
gate_mode: permissive
gate_max_recycles: 2
---

# Autorun Merge Policy Spec — Default to PR, Opt In to Auto-Merge

**Created:** 2026-05-08
**Constitution:** none — session roster only
**Confidence:** Scope 0.95 / UX 0.95 / Data 0.95 / Integration 0.92 / Edges 0.92 / Acceptance 0.95
**gate_mode:** permissive
**gate_max_recycles:** 2

## Summary

Flip autorun's default merge behavior from "auto-merge if clean" to "always open a PR; auto-merge is opt-in per-project." Adds a three-value `auto_merge_policy` knob (`pr` | `clean` | `validated`) read from spec frontmatter (with constitution + CLI overrides). Default is `pr`. The current "clean gates → auto-merge" path becomes the `clean` opt-in. The future runtime-validation gate (separate spec) becomes the `validated` opt-in. Asymmetric-risk reasoning: silent regression in main is much costlier than morning PR review, especially for downstream projects MonsterFlow runs against (iOS apps, business code, user-facing surfaces).

## Backlog Routing

Carved from in-conversation review 2026-05-08. User flagged that the pipeline lacks post-build runtime validation (playwright/E2E/smoke), so "clean gates" doesn't mean "validated end-to-end" — auto-merge under that condition is over-aggressive. Companion to `autorun-runtime-validation-gate` (separate spec drafted same session — adds the missing gate; this spec adds the policy that consumes it). Ships independently — landing this first changes the default to a safer baseline regardless of when validation lands.

## Scope

**In scope:**
- New frontmatter key `auto_merge_policy: pr | clean | validated` in spec.md.
- Same key honored in `docs/specs/constitution.md` (project-wide default if no spec.md key).
- CLI override flag `--auto-merge=<pr|clean|validated>` on `autorun-batch.sh` and `run.sh`.
- Resolution precedence: CLI > spec.md > constitution > hardcoded default (`pr`).
- `scripts/autorun/run.sh` (or wherever the merge call lives) reads the resolved policy and branches:
  - `pr` → push branch, open PR via `gh pr create`, never call `gh pr merge`. Always.
  - `clean` → today's behavior: auto-merge only when zero warnings + no Codex high-severity. Otherwise PR.
  - `validated` → auto-merge only when (a) `clean` conditions met AND (b) runtime-validation gate passed (depends on `autorun-runtime-validation-gate` shipping; until then, `validated` falls back to `clean` with a stderr warning).
- One-line audit row to `queue/run.log` per slug: `<timestamp> <slug> merge_policy=<resolved> resolved_from=<spec|constitution|cli|default> action=<pr_only|auto_merged|fell_back>`.
- Migration: existing repos with no `auto_merge_policy` set anywhere get `pr` (safer default), NOT today's auto-merge behavior. Opt-in is explicit; opt-out is impossible (you must affirmatively choose `clean` or `validated`).
- Tests: 8 fixtures covering each precedence path + each policy value + the `validated` fallback case.

**Out of scope:**
- Adding the runtime validation gate itself (separate spec — `autorun-runtime-validation-gate`).
- Per-axis merge policy (e.g., "auto-merge if security clean but human-review if scope-discipline warned") — single-knob v1; per-axis is a possible v2.
- Repository-level branch protection rules (those are GitHub-side; this spec only governs autorun's intent).
- Non-autorun (manual) pipeline runs — manual runs already require the user to invoke `gh pr merge` or `git merge` themselves; nothing to change.

## Approach

**Chosen:** additive frontmatter key with hardcoded-conservative default and explicit opt-in path.

Resolution function in shell (small bash helper, similar to `_gate_helpers.sh` pattern):

```bash
resolve_merge_policy() {
  local spec_path="$1"
  local cli_flag="$2"  # value of --auto-merge or empty
  # Precedence: CLI > spec frontmatter > constitution > default
  if [ -n "$cli_flag" ]; then echo "cli:$cli_flag"; return; fi
  local spec_val=$(extract_frontmatter_key "$spec_path" auto_merge_policy)
  if [ -n "$spec_val" ]; then echo "spec:$spec_val"; return; fi
  local const_val=$(extract_frontmatter_key docs/specs/constitution.md auto_merge_policy)
  if [ -n "$const_val" ]; then echo "constitution:$const_val"; return; fi
  echo "default:pr"
}
```

Validate the resolved value against `{pr, clean, validated}`; reject unknown values with exit 2 + stderr message naming the source.

Rejected alternatives:
- *Three separate flags (`--auto-merge`, `--never-merge`, `--validated-merge`)* — explosion of flag combinations; one knob with an enum is cleaner.
- *Default `clean` (preserve today's behavior)* — defeats the asymmetric-risk argument that motivated the spec. Default must flip.
- *Per-axis merge policy in v1* — premature; we don't have data on which axes should gate merge separately. Add when there's demand.
- *Github branch protection rules instead of pipeline-level policy* — repo-level rules are right but external; the pipeline still needs to know what intent to communicate. Both can coexist; this spec governs the intent.

## Roster Changes

No persistent roster changes. Existing `autorun-shell-reviewer` subagent gates the shell script changes per repo CLAUDE.md.

## UX / User Flow

**Today (current behavior, what we're flipping):**
```
$ scripts/autorun/run.sh my-feature
... gates run ...
[autorun] gates clean — auto-merging
[autorun] gh pr create + gh pr merge --squash --auto
[autorun] merged: https://github.com/.../pull/42
```

**With this spec, default behavior (no opt-in):**
```
$ scripts/autorun/run.sh my-feature
... gates run ...
[autorun] gates clean — opening PR (auto_merge_policy=pr [default])
[autorun] gh pr create
[autorun] PR opened: https://github.com/.../pull/42
[autorun] review and merge when ready
```

**Opt-in to clean-merge (per spec):**
```yaml
# spec.md frontmatter
auto_merge_policy: clean
```
Behavior matches today's auto-merge.

**Opt-in to validated-merge (per spec, requires runtime-validation gate):**
```yaml
auto_merge_policy: validated
```
If runtime-validation gate hasn't shipped yet, autorun emits stderr warning and falls back to `clean`. Once it ships, `validated` requires both clean gates AND runtime check passing.

**CLI override (one-off run, doesn't touch frontmatter):**
```
$ scripts/autorun/run.sh my-feature --auto-merge=clean
```

## Data & State

**Frontmatter schema additive:** `auto_merge_policy` becomes optional in spec.md and constitution.md. No existing schema breaks. No migration needed (absent key → default `pr`).

**Audit log additive:** one new row type in `queue/run.log` (existing JSONL stream):
```json
{"ts": "2026-05-08T22:34:11Z", "slug": "my-feature", "event": "merge_policy_resolved", "policy": "pr", "resolved_from": "default", "action": "pr_only"}
```

No new files. No new sidecar schemas.

## Integration

- `scripts/autorun/run.sh` — replace direct `gh pr merge` call with `merge_policy_dispatch` helper.
- `scripts/autorun/autorun-batch.sh` — accept `--auto-merge=<value>` CLI flag; pass through to `run.sh`.
- New helper: `scripts/_merge_policy.sh` (~80 LoC): `resolve_merge_policy`, `validate_policy_value`, `dispatch_pr_only`, `dispatch_clean_merge`, `dispatch_validated_merge` (with fallback warning).
- Frontmatter parser: reuse existing `_gate_helpers.sh` `extract_frontmatter_key` if present; otherwise add a small awk helper.
- Tests: `tests/test-autorun-merge-policy.sh` (~150 LoC, 8 fixtures).
- `commands/autorun.md` — update doc to describe the new key + precedence.
- `docs/specs/constitution.md` template — note the new optional key.
- `docs/index.html` — already updated in this session's docs-only honesty fix; no further change required.

Touched files: 3 shell scripts + 1 new helper + 1 test file + 2 doc files. Estimated ~250-400 LoC delta.

## Edge Cases

- **Spec frontmatter has typo (`auto_merge_polocy: clean`):** key is unknown → fall through to constitution → default `pr`. Emit stderr warning at autorun start: `[autorun] warning: unknown frontmatter key 'auto_merge_polocy' in <slug>/spec.md — did you mean 'auto_merge_policy'?` (Levenshtein distance ≤ 2 triggers the suggestion.) Don't fail the run; the default is safe.
- **Spec frontmatter has invalid value (`auto_merge_policy: yolo`):** reject at resolve-time with exit 2 + clear stderr: `[autorun] error: invalid auto_merge_policy 'yolo' in <slug>/spec.md (allowed: pr, clean, validated)`. Don't silently fall back — invalid intent should halt, not default-down.
- **CLI flag conflicts with spec frontmatter:** CLI wins (top of precedence). Log the override to run.log so the audit trail shows which won.
- **Constitution sets `clean`, spec sets `pr`:** spec wins (per precedence). The user explicitly downgraded for this feature.
- **`auto_merge_policy: validated` but runtime-validation gate hasn't shipped:** fall back to `clean` with stderr warning + run.log note (`action: fell_back`). Gives users a clean migration path: they can write `validated` in their specs today, the gate becomes load-bearing once it ships.
- **PR creation itself fails (gh CLI error, network):** existing failure path preserved — autorun marks the slug failed, leaves artifacts, surfaces the error. Merge policy doesn't change the failure-mode shape.
- **Branch protection requires PR review even on auto-merge:** GitHub will refuse the auto-merge call; autorun catches the non-zero exit and downgrades to PR-only with a log line. User sees the PR; nothing breaks.
- **Squash-merge convention:** `clean` and `validated` paths both call `gh pr merge --squash` (preserves today's behavior). `pr` path doesn't merge, so the human chooses squash/rebase/merge per their PR.
- **Concurrent autorun runs on same repo:** each opens its own branch + PR. No new conflict surface.
- **Re-running autorun on a slug that already has an open PR:** existing logic unchanged — autorun-rotate-artifacts handles the prior run's artifacts; new PR is opened or existing one is updated per existing semantics.

## Acceptance Criteria

1. New optional frontmatter key `auto_merge_policy: pr | clean | validated` accepted in `spec.md` and `docs/specs/constitution.md`.
2. CLI flag `--auto-merge=<pr|clean|validated>` accepted by `autorun-batch.sh` and `run.sh`.
3. Resolution precedence: CLI > spec.md > constitution > hardcoded default (`pr`). Verified by 4 test fixtures (one per precedence layer).
4. **Default behavior (no opt-in anywhere) is `pr`** — autorun opens a PR but does NOT auto-merge, regardless of gate cleanliness. This is the safety flip.
5. `clean` policy preserves today's behavior: auto-merge when zero warnings + no Codex high-severity; otherwise PR.
6. `validated` policy: auto-merge requires both `clean` conditions AND a passing runtime-validation gate. Until `autorun-runtime-validation-gate` ships, `validated` falls back to `clean` semantics with a single stderr warning per run.
7. Invalid frontmatter value (e.g., `auto_merge_policy: yolo`) halts the run with exit 2 and a clear stderr message naming the allowed values.
8. Typo'd frontmatter key (Levenshtein ≤ 2 to `auto_merge_policy`) emits a warning + suggestion but does NOT halt — falls through to next-precedence layer.
9. One row written to `queue/run.log` per slug: `merge_policy_resolved` event with `policy`, `resolved_from`, `action` fields.
10. `commands/autorun.md` documents the new key, the precedence, and the CLI flag.
11. Test fixture: bare slug with no policy anywhere → `pr` action, run.log records `resolved_from: default`.
12. Test fixture: spec.md sets `clean`, gates clean → auto-merge fires, run.log records `resolved_from: spec, action: auto_merged`.
13. Test fixture: spec.md sets `clean`, gates have warnings → falls to PR, run.log records `action: pr_fallback_warnings`.
14. Test fixture: CLI passes `--auto-merge=pr` while spec.md says `clean` → CLI wins, no merge, run.log records `resolved_from: cli`.
15. Test fixture: spec.md sets `validated`, gate not shipped → fallback to `clean` with stderr warning, run.log records `action: fell_back_validated_to_clean`.
16. Test fixture: invalid value `--auto-merge=foo` → exit 2, stderr lists allowed values, no PR opened.
17. Migration verification: running autorun against a pre-spec repo (no `auto_merge_policy` anywhere) on a clean spec produces a PR (not a merge). Confirmed by integration test against a fresh `git init` fixture.
18. `autorun-shell-reviewer` subagent passes a clean review against the modified `scripts/autorun/*.sh` per its 13-pitfall checklist (especially: PIPESTATUS handling around the `gh` CLI calls, explicit pathspec when committing).

## Open Questions

- **Q1:** should `auto_merge_policy: clean` require the spec's `gate_mode: strict` to qualify? (i.e., overnight permissive runs by definition can't auto-merge.) **Lean: no** — `gate_mode` is about which findings are blockers, `auto_merge_policy` is about what to do once gates have decided. Orthogonal axes; let users compose them. Revisit if data shows permissive+auto-merge causes regression problems.
- **Q2:** should we add a global escape hatch flag (`--never-merge` regardless of any policy) for paranoid one-off runs? **Lean: no** — `--auto-merge=pr` already does this. Avoid flag-aliasing.
- **Q3 (resolved):** should the default flip be gated behind a major version bump (v0.11.0)? **Lean: yes** — this is a behavior-changing default; semver minor at minimum. Implementation note for /build: bump VERSION and CHANGELOG accordingly.
