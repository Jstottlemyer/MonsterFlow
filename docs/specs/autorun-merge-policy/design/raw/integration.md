# Integration Analysis — autorun-merge-policy

## Recommendation: Option B — phased release (merge-policy v0.11.0, runtime-validation v0.12.0)

Spec already designs for this: `validated → pr` fallback is first-class behavior with own AC (#6), reason value (`validated_fallback`), and stderr warning. Runtime-validation's AC#19 only requires four cross-spec edits to land in same PR as runtime-validation itself — does NOT require both specs to release together. Phasing reduces blast radius, lets breaking-default flip ship sooner.

## Constraints Identified

- **`scripts/autorun/_merge_policy.sh` source-only**, no top-level side effects, exit 0/2. Both `run.sh` AND `autorun-batch.sh` source it. `merge_policy_*` prefix. `MERGE_POLICY_DISPATCH_OVERRIDE` for PATH-stub tests.
- **`_gh_frontmatter_field` private-prefixed by convention.** Spec commits to using directly (no public wrapper). Inherits YAML-subset semantics from `_gate_helpers.sh:49`.
- **Banner placement:** after `$SPEC_FILE` export (line 667), before Phase 0b dispatch. Resolver runs first; resolved values stashed in env vars; banner reads them.
- **Drift detector in `autorun-batch.sh`** runs at queue-copy step. Must source `_merge_policy.sh` directly (not via `run.sh`).
- **`templates/constitution.md` change is install-time** — new adopters get commented-out example via `install.sh`; existing adopters' constitution.md is NOT modified by upgrade (user-owned).
- **`spec_sha` once-at-run-start.** Computed via `git hash-object queue/<slug>.spec.md`. Immutable for run.
- **Bash 3.2 macOS:** no `${array[-1]}`, no `export -f`, no negative subscripts. PATH-stub for tests.
- **`autorun-shell-reviewer` subagent BEFORE commit** (per `feedback_build_subagent_invocations_must_fire`). Two invocations: wave 1 helper + wave 3 run.sh/autorun-batch.sh.

## Open Questions

- **Q-INT-1:** When `autorun-batch.sh` invoked with `--auto-merge=clean`, does each slug's `merge_policy_resolved` log row record `resolved_from=cli`? Lean: yes (precedence-top regardless of entry point).
- **Q-INT-2:** Drift detector warn on every slug or only when canonical exists AND values differ? Spec says silent-skip when canonical missing; warn only on mismatch. Confirmed.
- **Q-INT-3:** If `_merge_policy.sh` source fails, does autorun halt or fall to legacy four-axis behavior? Lean: halt with clear message ("v0.11.0 helper missing — re-run install.sh").

## Integration Surfaces Table

| Surface | File | Change Type | Risk |
|---|---|---|---|
| Resolver dispatch | `scripts/autorun/run.sh` (after line 667) | Insert | Low (additive) |
| Banner emit | `scripts/autorun/run.sh` (before Phase 0b) | Insert | Low |
| Manual-review escape | `scripts/autorun/run.sh` (before merge dispatch) | Insert | Low |
| Merge call replacement | `scripts/autorun/run.sh:1069-1102` | Wrap | Medium |
| Drift detector | `scripts/autorun/autorun-batch.sh` (queue-copy) | Insert | Low |
| CLI flag parsing | `autorun-batch.sh` + `run.sh` | Insert | Low |
| Helper module | `scripts/autorun/_merge_policy.sh` | New | Medium |
| Frontmatter parser | `scripts/_gate_helpers.sh:49` | Reuse | Low |
| Audit row | `queue/run.log` | Additive event type | Low |
| Template | `templates/constitution.md` | Insert example | Trivial |
| Docs | `commands/autorun.md` | Insert sections | Trivial |
| Version | `VERSION`, `CHANGELOG.md` | Bump 0.11.0 | Trivial |
| Cross-spec slot | `dispatch_validated_merge` body | Stub now (returns pr); replaced by runtime-validation | Designed for replacement |

## Findings (v2 schema)

```yaml
- persona: integration
  finding_id: int-001
  severity: major
  class: architectural
  title: "Phased release recommended: merge-policy v0.11.0 first, runtime-validation v0.12.0"
  body: "Phasing reduces blast radius, lets breaking-default flip ship sooner, smaller PR/review surface. Spec already designs for it (validated→pr fallback is first-class)."
  suggested_fix: "Pin in plan: this spec ships independently as v0.11.0. Cross-spec edits to merge-policy land in the runtime-validation PR (additively extending reason enum, replacing dispatch_validated_merge body)."

- persona: integration
  finding_id: int-002
  severity: major
  class: contract
  title: "Banner placement is hard ordering invariant: after $SPEC_FILE export, before Phase 0b dispatch"
  body: "Banner needs resolved values; resolver needs $SPEC_FILE. Wrong placement breaks AC#10's 'before Phase 0b' guarantee."
  suggested_fix: "Encode in plan as code-comment + test that asserts banner emitted before any reviewer dispatch."

- persona: integration
  finding_id: int-003
  severity: minor
  class: contract
  title: "_gh_frontmatter_field reuse-as-is is the contract surface"
  body: "Pin the existing helper; no public wrapper. Inherits YAML-subset semantics from scripts/_gate_helpers.sh:49."
  suggested_fix: "Plan reads helper implementation, documents accepted YAML subset in commands/autorun.md."

- persona: integration
  finding_id: int-004
  severity: major
  class: architectural
  title: "Bash 3.2 compatibility constraints — violation crashes scripts under set -e"
  body: "No ${array[-1]}, no export -f, no negative subscripts. Per memories feedback_negative_array_subscript_bash32 + feedback_path_stub_over_export_f."
  suggested_fix: "Plan documents at top of helper file. autorun-shell-reviewer subagent verifies."

- persona: integration
  finding_id: int-005
  severity: major
  class: architectural
  title: "autorun-shell-reviewer subagent invocation BEFORE commit"
  body: "Two invocations needed: wave 1 helper skeleton commit + wave 3 run.sh/autorun-batch.sh edits commit. Per memory feedback_build_subagent_invocations_must_fire."
  suggested_fix: "Plan tasks each include explicit autorun-shell-reviewer invocation as the pre-commit step."

- persona: integration
  finding_id: int-006
  severity: minor
  class: contract
  title: "Backward compat for in-flight v0.10.x queue specs"
  body: "v0.10.x queue/<slug>.spec.md mid-flight when user pulls v0.11.0 has no auto_merge_policy key — resolver falls to default 'pr' cleanly. Banner WILL fire on next run. Acceptable noise for one-time upgrade."
  suggested_fix: "Document in commands/autorun.md migration section."
```
