---
gate_mode: permissive
gate_max_recycles: 2
---

# Autorun Merge Policy Spec — Default to PR, Opt In to Auto-Merge

**Created:** 2026-05-08
**Revised:** 2026-05-08 (post-/spec-review refinement to 0.95 confidence)
**Constitution:** none — session roster only
**Audience:** MonsterFlow contributors and pipeline maintainers — adopter-facing copy is handled in `docs/index.html`.
**Applies to:** autorun only. Manual pipeline runs (`/spec → /spec-review → /plan → /check → /build` invoked interactively) are unaffected by this spec — there is no auto-merge step in manual flow; the user invokes `gh pr merge` themselves.
**Confidence:** Scope 0.90 / UX 0.92 / Data 0.95 / Integration 0.90 / Edges 0.95 / Acceptance 0.93 (avg 0.925)
**gate_mode:** permissive
**gate_max_recycles:** 2

## Summary

Flip autorun's default merge behavior from "auto-merge if clean" to "always open a PR; auto-merge is opt-in per-project." Adds a three-value `auto_merge_policy` knob (`pr` | `clean` | `validated`) read from spec frontmatter (with constitution + CLI overrides). Default is `pr`. The `clean` policy auto-merges when a **mode-aware** predicate is satisfied — `gate_mode: strict` accepts `VERDICT in {GO, GO_WITH_FIXES}`; `gate_mode: permissive` accepts `VERDICT == GO` only — composing with the existing four-axis gate at `scripts/autorun/run.sh:1069-1102` (`MERGE_CAPABLE == 1 AND CODEX_HIGH_COUNT == 0 AND RUN_DEGRADED == 0`). The `validated` value gracefully falls back to `pr` (NOT `clean`) until `autorun-runtime-validation-gate` ships, with a stderr warning. Asymmetric-risk reasoning: silent regression in main is much costlier than morning PR review, especially for downstream projects MonsterFlow runs against.

A run-start **runtime-config banner** displays all resolved runtime knobs (merge policy, agent budget, gate mode, max recycles) so the user sees what will happen before work begins; the merge-policy line warns on every run where `resolved_from=default` until the user explicitly chooses any value (banner fires forever-until-opt-in, no sentinel suppression).

## Backlog Routing

Carved from in-conversation review 2026-05-08. Companion to `autorun-runtime-validation-gate` (separate spec — adds the missing runtime gate; this spec adds the policy that consumes it). Ships independently — landing this first changes the default to a safer baseline regardless of when validation lands.

## Definitions

These predicates and conventions are referenced throughout the spec and pinned here as the single source of truth.

### `is_clean_for_merge()` predicate

```
clean := MERGE_CAPABLE == 1
       AND CODEX_HIGH_COUNT == 0
       AND RUN_DEGRADED == 0
       AND (
            (gate_mode == "strict"     AND VERDICT in {GO, GO_WITH_FIXES})
         OR (gate_mode == "permissive" AND VERDICT == GO)
       )
```

The four-axis gate (`MERGE_CAPABLE`, `CODEX_HIGH_COUNT`, `RUN_DEGRADED`, `VERDICT`) lives at `scripts/autorun/run.sh:1069-1102` today. This spec adds the mode-aware verdict tightening. Rationale: under `gate_mode: permissive`, major findings demote to followups + `GO_WITH_FIXES`; if `clean` accepted `GO_WITH_FIXES` under permissive, `clean` would silently auto-merge code with major findings demoted — exactly the asymmetric-risk this spec exists to prevent.

**Codex absent (timeout, not authenticated, missing CLI):** treated as `CODEX_HIGH_COUNT == 0` — vacuously satisfies the no-Codex-high condition. This matches existing autorun behavior where Codex is silent-skip; if users want Codex to be required, that's a separate future knob.

### `action` enum (run.log JSONL)

Closed set, 4 values:
- `pr_only` — autorun opened a PR; no merge attempted (policy intent honored)
- `auto_merged` — autorun opened a PR and successfully merged it
- `fell_back` — autorun intended to merge but did not; `reason` field names why
- `merge_failed` — auto-merge call returned non-zero exit; PR left open

### `reason` enum (run.log JSONL — required when action is `fell_back` or `merge_failed`, null otherwise)

Closed set, 7 values:
- `warnings_present` — `clean` policy, but findings present that fail the predicate
- `verdict_no_go` — verdict is NO_GO; no merge regardless of policy
- `codex_high_severity` — Codex returned ≥1 High finding
- `run_degraded` — `RUN_DEGRADED == 1` somewhere during the run
- `validated_fallback` — `validated` policy, but runtime-validation-gate not shipped → fell back to pr
- `branch_protection` — `gh pr merge` returned non-zero (typically branch-protection refusal)
- `merge_call_failed` — generic merge-call failure (network, auth) not branch-protection-shaped

### Constitution paths

- **Runtime read path:** `<project-root>/docs/specs/constitution.md` — created per-project by `install.sh` from the template; resolver reads here at runtime.
- **Template ship path:** `templates/constitution.md` — lives in MonsterFlow repo; `install.sh` copies into adopter projects. Template changes (e.g., adding a commented-out `auto_merge_policy:` example for new adopters) land here.
- The two paths are distinct files. Spec must not conflate them.

### Runtime spec source-of-truth

Resolver reads `$SPEC_FILE` — i.e., `queue/<slug>.spec.md` (the runtime queue copy that autorun executes), per `scripts/autorun/run.sh:667`. Editing `<project>/docs/specs/<slug>/spec.md` AFTER a queue copy was made does NOT affect the in-flight merge policy — the queue file is canonical for the run.

A drift detector at queue-population time (when `autorun-batch.sh` copies the spec into `queue/`) compares the `auto_merge_policy` line between the queue copy and the canonical at `docs/specs/<slug>/spec.md`; on mismatch, emits a stderr warning naming both values and continues (never halts; minimal — compares only that one line).

## Scope

**Applies to:** autorun only. Manual pipeline is out of scope by definition.

**In scope:**
- New optional frontmatter key `auto_merge_policy: pr | clean | validated` in spec.md.
- Same key honored in `<project-root>/docs/specs/constitution.md` (per-project default if no spec.md key).
- Template at `templates/constitution.md` adds a commented-out `auto_merge_policy:` example with explanatory note.
- CLI override flag `--auto-merge=<pr|clean|validated>` on `autorun-batch.sh` and `run.sh`.
- Resolution precedence: CLI > spec.md > constitution > hardcoded default (`pr`).
- New helper `scripts/autorun/_merge_policy.sh` (per Codex M2 — autorun-subdirectory location matches existing helper convention) using `_gh_frontmatter_field` from `scripts/_gate_helpers.sh:49` (private-prefixed convention preserved; no new public wrapper added).
- `is_clean_for_merge()` predicate (mode-aware) as defined in **Definitions** above.
- `validated` policy gracefully degrades to `pr` (NOT `clean`) when `autorun-runtime-validation-gate` not shipped; banner stderr-warns once at run-start with action recorded as `fell_back, reason=validated_fallback`.
- **Runtime-config banner at run-start** — fires before Phase 0b dispatch; displays all 4 resolved knobs; merge-policy line warns on `resolved_from=default`; other knobs informational; future specs extend the banner with their lines.
- **Drift detector at queue-population** — `autorun-batch.sh` queue-copy step compares `auto_merge_policy` line in queue copy vs canonical at `docs/specs/<slug>/spec.md`; warns on mismatch (never halts); compares only that one line.
- **Per-run escape hatch** — `queue/<slug>/.manual-review` touch file forces auto-merge skip for this slug only (regardless of resolved policy); records `action=fell_back, reason=manual_review_requested` (added 8th reason value).
- Audit row written to `queue/run.log` per slug (JSONL, additive event type `merge_policy_resolved`):
  ```json
  {"ts": "...", "slug": "...", "event": "merge_policy_resolved",
   "policy": "<resolved>", "resolved_from": "<source>",
   "action": "<enum>", "reason": "<enum or null>",
   "pr_number": <int or null>, "merge_sha": "<sha or null>",
   "spec_sha": "<sha of queue/<slug>.spec.md at run start>"}
  ```
- PR conventions when policy=`pr` or fallback to PR:
  - Title: `[autorun] <slug>`
  - Body: includes verdict + reviewer summary + spec link + run.log path
  - Draft state: `draft` if `verdict==GO_WITH_FIXES` OR `action==fell_back`; `ready-for-review` if `verdict==GO` AND `action==pr_only`
  - Label: `autorun`
  - Re-run with existing open PR: force-push existing branch (existing autorun semantics; branch name deterministic from slug)
- Migration: existing repos with no `auto_merge_policy` set anywhere get `pr` (safer default). The runtime-config banner fires every run where `resolved_from=default`; silence requires explicitly setting any value (including `auto_merge_policy: pr`).
- VERSION + CHANGELOG bump to v0.11.0 with explicit "⚠ BREAKING DEFAULT" callout.
- 9 test fixtures + 1 schema-validation test (covers each precedence path, each policy value, drift detector, branch-protection fallback, validated fallback, per-run override).

**Out of scope:**
- Adding the runtime validation gate itself (separate spec — `autorun-runtime-validation-gate`).
- Per-axis merge policy (single-knob v1; per-axis is possible v2).
- Repository-level branch protection rules (GitHub-side; this spec only governs autorun's intent).
- Manual (non-autorun) pipeline runs.
- Env-var escape hatch (e.g., `MONSTERFLOW_PRESERVE_LEGACY_AUTOMERGE=1`) — constitution-level setting is the single opt-in path; no second mechanism.
- Sentinel-file banner suppression — banner fires every run where policy is unset; user silences by explicit choice.
- Levenshtein typo-suggestion for misspelled frontmatter keys — replaced with simpler "unknown key warning" (carved to BACKLOG as `frontmatter-typo-suggestion-helper`).
- `agent_count` / roster knob in this spec — already handled by `account-type-agent-scaling` (`agent_budget`) and forthcoming `dynamic-roster-per-gate` (`tier_policy`); banner DISPLAYS these but doesn't OWN them.
- Per-knob warn semantics for non-merge-policy banner lines — those specs decide their own warn behavior when they extend the banner.

## Approach

**Chosen:** additive frontmatter key + runtime-config banner at run-start + mode-aware predicate + minimal drift detector.

**Resolution function** in shell (`scripts/autorun/_merge_policy.sh`, source-only, no top-level side effects, exit codes 0/2 only, functions prefixed `merge_policy_*`, override hook env var `MERGE_POLICY_DISPATCH_OVERRIDE` for tests):

```bash
merge_policy_resolve() {
  local spec_path="$1"          # $SPEC_FILE — queue/<slug>.spec.md
  local cli_flag="$2"           # value of --auto-merge or empty
  # Precedence: CLI > spec frontmatter > constitution > default
  if [ -n "$cli_flag" ]; then echo "cli:$cli_flag"; return; fi
  local spec_val
  spec_val=$(_gh_frontmatter_field "$spec_path" auto_merge_policy 2>/dev/null || true)
  if [ -n "$spec_val" ]; then echo "spec:$spec_val"; return; fi
  local const_val
  const_val=$(_gh_frontmatter_field "$PROJECT_ROOT/docs/specs/constitution.md" auto_merge_policy 2>/dev/null || true)
  if [ -n "$const_val" ]; then echo "constitution:$const_val"; return; fi
  echo "default:pr"
}
```

Validate the resolved value against `{pr, clean, validated}`; reject unknown values with exit 2 + stderr message naming the source.

**`is_clean_for_merge()`** — implemented as mode-aware predicate per **Definitions**. Composes with existing four-axis gate at `scripts/autorun/run.sh:1069-1102`; doesn't replace it.

**Runtime-config banner** — emitted by a new function `merge_policy_render_banner()` called from `run.sh` immediately after policy resolution, before Phase 0b reviewer dispatch:

```
=== autorun runtime config: <slug> ===
auto_merge_policy: <pr|clean|validated> (resolved_from=<cli|spec|constitution|default>)
agent_budget:      <n> (resolved_from=<config|default>)
gate_mode:         <permissive|strict> (resolved_from=<spec|frontmatter|default>)
gate_max_recycles: <n> (resolved_from=<spec|default>)

This run will: <one-line summary derived from resolved values>

To override this run:  scripts/autorun/run.sh <slug> --auto-merge=clean
To set per-spec:       add to spec.md frontmatter
To set project-wide:   add to <project>/docs/specs/constitution.md
For gate-by-gate manual review instead, abort and invoke /spec-review interactively.

[only if resolved_from=default for merge policy:]
⚠ Default flipped in v0.11.0 — auto-merge is now opt-in.
  See: docs/specs/autorun-merge-policy/spec.md
```

**Drift detector** — runs in `autorun-batch.sh` queue-copy step:

```bash
queue_copy_drift_check() {
  local canonical="$1"   # docs/specs/<slug>/spec.md
  local queue="$2"       # queue/<slug>.spec.md
  [ -f "$canonical" ] || return 0   # cross-project / hand-queued: skip silently
  local can_val que_val
  can_val=$(_gh_frontmatter_field "$canonical" auto_merge_policy 2>/dev/null || echo "")
  que_val=$(_gh_frontmatter_field "$queue" auto_merge_policy 2>/dev/null || echo "")
  if [ "$can_val" != "$que_val" ]; then
    >&2 echo "[autorun] drift warning: <slug>/spec.md auto_merge_policy=$can_val but queue copy auto_merge_policy=$que_val (queue copy will be used; edit queue/<slug>.spec.md if you intended the canonical value)"
  fi
}
```

**Per-run escape hatch** — `run.sh` checks for `queue/<slug>/.manual-review` immediately before merge dispatch:

```bash
if [ -f "queue/${SLUG}/.manual-review" ]; then
  log_run_event slug=$SLUG event=merge_policy_resolved \
    policy=$RESOLVED_POLICY resolved_from=$RESOLVED_FROM \
    action=fell_back reason=manual_review_requested ...
  # Skip merge dispatch; PR stays open
  return 0
fi
```

Rejected alternatives:
- *Three separate flags (`--auto-merge`, `--never-merge`, `--validated-merge`)* — one knob with an enum is cleaner.
- *Default `clean` (preserve today's behavior)* — defeats asymmetric-risk argument.
- *Per-axis merge policy in v1* — premature; no data on which axes should gate merge separately.
- *`validated → clean` fallback* — recreates the very risk this spec exists to prevent (Codex H1).
- *Sentinel-file banner suppression* — over-engineered for one user; banner fires every run until explicit choice silences it.
- *Env-var escape hatch* — constitution-level setting IS the env-var equivalent; second mechanism is redundant.
- *Levenshtein typo detector* — pure-bash Levenshtein on bash 3.2 is ~40 LoC of footgun for one error message; demoted to plain unknown-key warning.

## Roster Changes

No persistent roster changes. Existing `autorun-shell-reviewer` subagent gates the shell script changes per repo CLAUDE.md (verified to exist at `.claude/agents/autorun-shell-reviewer.md`). `persona-metrics-validator` subagent contract is unaffected (additive event type only on run.log JSONL).

## UX / User Flow

**Today (current behavior — being flipped):**
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
=== autorun runtime config: my-feature ===
auto_merge_policy: pr (resolved_from=default)
agent_budget:      6 (resolved_from=~/.config/monsterflow)
gate_mode:         permissive (resolved_from=default)
gate_max_recycles: 2 (resolved_from=default)

This run will: open a PR but NOT auto-merge.
                Dispatch 6 reviewers per gate.
                Permissive findings → followups.
                Cap retries at 2.

⚠ Default flipped in v0.11.0 — auto-merge is now opt-in.
  See: docs/specs/autorun-merge-policy/spec.md

To override this run:  scripts/autorun/run.sh my-feature --auto-merge=clean
To set per-spec:       add to spec.md frontmatter
To set project-wide:   add to <project>/docs/specs/constitution.md
For gate-by-gate manual review instead, abort and invoke /spec-review interactively.

... gates run ...
[autorun] PR opened: https://github.com/.../pull/42
[autorun] action=pr_only resolved_from=default
```

**Opt-in to clean-merge (per spec):**
```yaml
# spec.md frontmatter
auto_merge_policy: clean
```
Run output: same banner shape with `auto_merge_policy: clean (resolved_from=spec)` and no warning line; merge proceeds when predicate satisfied.

**Per-run manual-review escape (touch file):**
```
$ touch queue/my-feature/.manual-review
$ scripts/autorun/run.sh my-feature
... gates run ...
[autorun] manual-review touch file detected — skipping merge dispatch
[autorun] PR opened: https://github.com/.../pull/42
[autorun] action=fell_back reason=manual_review_requested
```

## Data & State

**Frontmatter schema additive:** `auto_merge_policy` becomes optional in spec.md and constitution.md. No existing schema breaks. No migration needed (absent key → default `pr`).

**run.log row schema (additive event type, no breaks to existing readers):**
```json
{"ts": "2026-05-08T22:34:11Z",
 "slug": "my-feature",
 "event": "merge_policy_resolved",
 "policy": "pr",
 "resolved_from": "default",
 "action": "pr_only",
 "reason": null,
 "pr_number": 42,
 "merge_sha": null,
 "spec_sha": "098905d3a..."}
```

`action` enum: `{pr_only, auto_merged, fell_back, merge_failed}` (closed).
`reason` enum: `{warnings_present, verdict_no_go, codex_high_severity, run_degraded, validated_fallback, branch_protection, merge_call_failed, manual_review_requested}` — required when action is `fell_back` or `merge_failed`, null otherwise.

**Per-run touch file:** `queue/<slug>/.manual-review` — presence forces skip-merge; recorded as `action=fell_back, reason=manual_review_requested`.

**Audit forensic fields:** `pr_number`, `merge_sha`, `spec_sha` captured at merge-call site. `spec_sha = git hash-object queue/<slug>.spec.md` taken once at run start (immutable for the run even if queue file is hand-edited mid-flight).

No new schema files. No breaking changes to existing sidecars.

## Integration

- `scripts/autorun/run.sh` — read `$SPEC_FILE` for policy resolution; emit runtime-config banner before Phase 0b; check `.manual-review` before merge dispatch; replace direct `gh pr merge` call with `merge_policy_dispatch` helper.
- `scripts/autorun/autorun-batch.sh` — accept `--auto-merge=<value>` CLI flag (uniformly applied to every slug — CLI is precedence top); add drift detector at queue-copy step.
- `scripts/autorun/_merge_policy.sh` — new helper (~120 LoC): `merge_policy_resolve`, `merge_policy_validate`, `is_clean_for_merge`, `merge_policy_render_banner`, `merge_policy_dispatch` (with sub-dispatchers `dispatch_pr_only`, `dispatch_clean_merge`, `dispatch_validated_merge`).
- Frontmatter parser: use `_gh_frontmatter_field` from `scripts/_gate_helpers.sh:49` directly (per Q7-II — no new public wrapper).
- Tests: `tests/test-autorun-merge-policy.sh` (~300 LoC, 9 fixtures + 1 schema-validation test).
- `commands/autorun.md` — document the new key + precedence + CLI flag + banner content + per-run escape hatch + manual-pipeline pointer.
- `docs/specs/constitution.md` template (= `templates/constitution.md`) — add commented-out `auto_merge_policy:` example with explanatory note.
- `docs/index.html` — already updated in this session's docs-only honesty fix; no further change required.
- `CHANGELOG.md` — `[Unreleased]` section converts to `## [0.11.0] - <date>` entry with explicit `### ⚠ BREAKING DEFAULT` heading.
- `VERSION` — bump to `0.11.0`.

Touched files: 4 shell scripts + 1 new helper + 1 test file + 4 doc/config files. Estimated ~500-700 LoC delta (banner + drift detector + escape hatch + 9 fixtures expand the surface vs original ~250-400 estimate).

## Edge Cases

- **Spec frontmatter has typo (`auto_merge_polocy: clean`):** key is unknown → fall through to constitution → default `pr`. Emit stderr warning at autorun start: `[autorun] warning: unknown frontmatter key 'auto_merge_polocy' in <slug>/spec.md (no Levenshtein suggestion in v1; carved to BACKLOG)`. Don't fail the run; default is safe.
- **Spec frontmatter has invalid value (`auto_merge_policy: yolo`):** reject at resolve-time with exit 2 + clear stderr: `[autorun] error: invalid auto_merge_policy 'yolo' in <slug>/spec.md (allowed: pr, clean, validated)`. Don't silently fall back — invalid intent should halt.
- **CLI flag conflicts with spec frontmatter:** CLI wins (top of precedence). Logged to run.log so audit trail shows which won.
- **Constitution sets `clean`, spec sets `pr`:** spec wins (per precedence). User explicitly downgraded for this feature.
- **`auto_merge_policy: validated` but runtime-validation gate hasn't shipped:** fall back to `pr` (NOT `clean`) per Codex H1. Banner stderr-warns once at run start. run.log records `action=fell_back, reason=validated_fallback`.
- **PR creation itself fails (gh CLI error, network):** existing failure path preserved — autorun marks the slug failed, leaves artifacts, surfaces the error.
- **Branch protection refuses auto-merge:** `gh pr merge` returns non-zero. Autorun catches the failure, leaves PR open, run.log records `action=fell_back, reason=branch_protection`. Test fixture covers this (AC#19).
- **`gate_mode: permissive` + `auto_merge_policy: clean` composition:** mode-aware predicate handles automatically — under permissive, `clean` requires `VERDICT == GO` (not `GO_WITH_FIXES`). No additional warn needed; the predicate self-documents the safer behavior.
- **Squash-merge convention:** `clean` and `validated` paths both call `gh pr merge --squash` (preserves today's behavior). `pr` path doesn't merge.
- **Concurrent autorun runs on same repo:** each opens its own branch + PR. No new conflict surface (inherited behavior).
- **Re-running autorun on a slug with open PR:** force-push existing branch (existing autorun semantics — branch name deterministic from slug). PR auto-updates rather than spawning duplicate.
- **Drift between canonical spec and queue copy:** drift detector at queue-population time emits stderr warning naming both values; never halts; queue copy wins for the run.
- **Cross-project queue (no canonical at `<project>/docs/specs/<slug>/spec.md`):** drift detector silently skips (no canonical to compare). No false positive.
- **`.manual-review` touch file present:** merge dispatch skipped; PR stays open; recorded as `action=fell_back, reason=manual_review_requested`. Touch file is checked once per run (no race).
- **Codex absent (timeout/auth/missing):** `CODEX_HIGH_COUNT == 0` vacuously satisfied; `is_clean_for_merge()` evaluates as if Codex passed clean. Per existing autorun convention.
- **`spec_sha` for forensic field:** computed once at run start via `git hash-object queue/<slug>.spec.md`. Immutable for the run.

## Acceptance Criteria

1. New optional frontmatter key `auto_merge_policy: pr | clean | validated` accepted in `spec.md` and `<project>/docs/specs/constitution.md`.
2. CLI flag `--auto-merge=<pr|clean|validated>` accepted by `autorun-batch.sh` and `run.sh`.
3. Resolution precedence: CLI > spec.md > constitution > hardcoded default (`pr`). Verified by 4 test fixtures (one per precedence layer).
4. **Default behavior (no opt-in) is `pr`** — autorun opens a PR but does NOT auto-merge, regardless of gate cleanliness.
5. `clean` policy auto-merges per the **mode-aware** `is_clean_for_merge()` predicate defined in **Definitions**:
   - `gate_mode: strict` accepts `VERDICT in {GO, GO_WITH_FIXES}`
   - `gate_mode: permissive` accepts `VERDICT == GO` only
   - All modes require `MERGE_CAPABLE == 1 AND CODEX_HIGH_COUNT == 0 AND RUN_DEGRADED == 0`
6. `validated` policy: when `autorun-runtime-validation-gate` not shipped, falls back to `pr` (NOT `clean`); banner stderr-warns once at run start; run.log records `action=fell_back, reason=validated_fallback`.
7. Invalid frontmatter value (e.g., `auto_merge_policy: yolo`) halts the run with exit 2 and a clear stderr message naming the allowed values.
8. Unknown frontmatter key (e.g., `auto_merge_polocy`) emits a stderr warning naming the key and falls through to next-precedence layer; does NOT halt.
9. Audit row written to `queue/run.log` per slug with closed-set `action` enum + closed-set `reason` enum + forensic fields (`pr_number`, `merge_sha`, `spec_sha`):
   - `action ∈ {pr_only, auto_merged, fell_back, merge_failed}` (closed)
   - `reason ∈ {warnings_present, verdict_no_go, codex_high_severity, run_degraded, validated_fallback, branch_protection, merge_call_failed, manual_review_requested}` (closed; required when action is `fell_back` or `merge_failed`, null otherwise)
   - Forensic fields captured at merge-call site
10. **Runtime-config banner** emitted at run-start (before Phase 0b reviewer dispatch) displays all 4 resolved knobs (merge policy, agent budget, gate mode, max recycles) + one-line behavior summary + override-instruction footer + manual-pipeline pointer; merge-policy line warns on `resolved_from=default`; other knob lines informational only.
11. Banner fires every run where `resolved_from=default` for merge policy. Silence requires explicitly setting any value (including `auto_merge_policy: pr`). No sentinel file. Fires forever-until-opt-in.
12. `commands/autorun.md` documents the new key, precedence, CLI flag, banner content, per-run escape hatch, manual-pipeline pointer, and how to silence the banner.
13. **Drift detector at queue-population time:** `autorun-batch.sh` queue-copy step compares `auto_merge_policy` line in `queue/<slug>.spec.md` vs `<project>/docs/specs/<slug>/spec.md`; on mismatch, emits stderr warning naming both values; never halts; cross-project / missing-canonical case silent-skips.
14. **Per-run escape hatch:** presence of `queue/<slug>/.manual-review` at merge-dispatch time forces skip-merge regardless of resolved policy; PR stays open; run.log records `action=fell_back, reason=manual_review_requested`.
15. **PR conventions** when policy is `pr` or fallback to PR:
   - Title: `[autorun] <slug>`
   - Body: verdict + reviewer summary + spec link + run.log path
   - Draft state: `draft` if `verdict==GO_WITH_FIXES` OR `action==fell_back`; `ready-for-review` if `verdict==GO` AND `action==pr_only`
   - Label: `autorun`
   - Re-run with existing open PR: force-push existing branch (existing autorun semantics)
16. Test fixture: bare slug with no policy anywhere → `action=pr_only, reason=null, resolved_from=default`; banner fires with default warning.
17. Test fixture: spec.md sets `clean`, gates clean (mode-aware predicate satisfied) → auto-merge fires; run.log records `action=auto_merged, resolved_from=spec`.
18. Test fixture: spec.md sets `clean`, gates have warnings (predicate fails) → falls to PR; run.log records `action=fell_back, reason=warnings_present`.
19. Test fixture: spec.md sets `clean`, gates clean, mocked `gh pr merge` returns exit 1 → autorun catches the failure, leaves PR open, run.log records `action=fell_back, reason=branch_protection`, exit 0.
20. Test fixture: CLI passes `--auto-merge=pr` while spec.md says `clean` → CLI wins, no merge, run.log records `action=pr_only, resolved_from=cli`.
21. Test fixture: spec.md sets `validated`, runtime-gate not shipped → fallback to `pr` with stderr warning, run.log records `action=fell_back, reason=validated_fallback`.
22. Test fixture: invalid value `--auto-merge=foo` → exit 2, stderr lists allowed values, no PR opened.
23. Test fixture: `queue/<slug>/.manual-review` present → merge dispatch skipped, run.log records `action=fell_back, reason=manual_review_requested`.
24. Test fixture: drift detector — canonical says `clean`, queue says `pr` → stderr warning emitted naming both values, run continues with queue value (`pr`).
25. **Migration verification (PATH-stub):** with `gh` shimmed via PATH-stub returning a fake PR URL, autorun on a no-policy spec produces `action=pr_only` in run.log AND never invokes `gh pr merge` (verified by stub call recorder). Per memory `feedback_path_stub_over_export_f.md`.
26. **VERSION + CHANGELOG bump as code change:** VERSION bumps to `0.11.0`; CHANGELOG.md `[Unreleased]` converts to `## [0.11.0] - <date>` entry under explicit `### ⚠ BREAKING DEFAULT` heading describing the auto-merge default flip + opt-in path. Per memory `feedback_auto_bump_changelog_warning`.
27. `templates/constitution.md` includes a commented-out `auto_merge_policy:` example with explanatory comment: `# auto_merge_policy: pr  # default; uncomment and set to 'clean' only if you've reviewed the trade-off in commands/autorun.md`.
28. `autorun-shell-reviewer` subagent passes a clean review against the modified `scripts/autorun/*.sh` and new `scripts/autorun/_merge_policy.sh` per its 13-pitfall checklist (PIPESTATUS handling around `gh` CLI calls, explicit pathspec, no `git add -A`, AppleScript-injection check on macOS path).
29. `persona-metrics-validator` subagent contract verified unaffected by running its schema check against a post-merge run.log fixture containing the new event type.

## Open Questions

- **Q1 (resolved):** should `auto_merge_policy: clean` require the spec's `gate_mode: strict` to qualify? **Resolved: no.** Mode-aware predicate handles the composition automatically — under `permissive`, `clean` requires `VERDICT == GO` (the safer outcome), preserving the asymmetric-risk argument without requiring the user to coordinate two separate frontmatter keys.
- **Q2 (resolved):** should we add a global escape hatch flag (`--never-merge`) for paranoid one-off runs? **Resolved: no.** `--auto-merge=pr` already does this; avoid flag-aliasing.
- **Q3 (resolved):** should the default flip be gated behind a major version bump (v0.11.0)? **Resolved: yes** — semver minor at minimum for a behavior-changing default. AC#26 wires the bump + breaking-default CHANGELOG callout.
- **Q4 (resolved):** should `agent_count` / roster knob be added to this spec? **Resolved: no.** Already handled by `account-type-agent-scaling` (`agent_budget`) and forthcoming `dynamic-roster-per-gate` (`tier_policy`); the runtime-config banner DISPLAYS these but doesn't OWN them. Future specs extend the banner with their own lines.
- **Q5 (resolved):** should manual-pipeline (non-autorun) be retired entirely? **Resolved: no, narrow scope explicitly.** Manual is lower-value than autorun for production but remains the onboarding ramp + debugging escape hatch + right tool for novel/complex specs. This spec's "Applies to: autorun only" scope note makes the boundary explicit; broader manual-vs-autorun strategy is a separate backlog concern.
- **Q6 (deferred to follow-up):** should the runtime-config banner also surface roster-resolution decisions (which personas selected, why) at run start? **Lean: yes for `pipeline-autorun-final-status-render`** (already in backlog) — that spec covers per-slug morning summary; extending it to include start-of-run roster info closes the loop. Out of scope for this spec.
