# API & Interface Design — autorun-merge-policy

## Recommendation: rename CLI flag + single dispatcher entry + closed-enum source-of-truth

**Public surface (canonical):**

```
# CLI (autorun-batch.sh and run.sh both accept):
--merge-policy=<pr|clean|validated>      # canonical
--auto-merge=<pr|clean|validated>        # deprecated alias; emits one-line stderr deprecation notice; same precedence slot

# Frontmatter (spec.md and constitution.md):
auto_merge_policy: pr | clean | validated   # unchanged (it's the noun, not imperative)

# Helper module: scripts/autorun/_merge_policy.sh (source-only, exit 0/2)
merge_policy_resolve   <spec_path> <cli_flag>   -> "<source>:<value>" on stdout
merge_policy_validate  <value>                  -> exit 0 valid, exit 2 invalid
is_clean_for_merge     <verdict> <merge_capable> <codex_high_count> <run_degraded> <gate_mode>
                                                -> return 0 clean, return 1 not clean (NEVER exit)
merge_policy_render_banner <slug> <policy> <resolved_from> <agent_budget> <abudget_from>
                            <gate_mode> <gmode_from> <max_recycles> <recycles_from>
                                                -> stdout banner; stderr warn only on policy resolved_from=default
merge_policy_dispatch  <policy> <slug> <verdict> <merge_capable> <codex_high_count> <run_degraded>
                                                -> SOLE writer of merge_policy_resolved JSONL row;
                                                   respects MERGE_POLICY_DISPATCH_OVERRIDE for tests
queue_copy_drift_check <canonical_path> <queue_path>
                                                -> stderr warn on mismatch; never halts
```

All function names `merge_policy_*` (or `is_clean_for_merge`, `queue_copy_drift_check`). No top-level side effects; sourcing idempotent.

## Constraints Identified

- **Bash 3.2 portability:** no `${arr[-1]}`, no `declare -A`, no `mapfile`. Positional args.
- **PATH-stub testability:** all `gh` invocations call `"${GH_BIN:-gh}"`; all `git` invocations call `"${GIT_BIN:-git}"`. PATH-stub injection works without `export -f`. Per memory `feedback_path_stub_over_export_f.md`.
- **`set -e` interaction:** `is_clean_for_merge` MUST `return 0/1`, never `exit`. Validation function uses `exit 2` (fatal config error).
- **PIPESTATUS around `gh`:** capture exit into local before any `||`. Per memory `feedback_pipestatus_or_true.md`.
- **JSONL writer atomicity:** single `printf '%s\n' "$json" >> "$RUNLOG"`; no echo, no heredoc.
- **Closed enums sourced from one place:** readonly arrays `_MP_ACTIONS=(pr_only auto_merged fell_back merge_failed)` and `_MP_REASONS=(warnings_present verdict_no_go codex_high_severity run_degraded validated_fallback branch_protection merge_call_failed manual_review_requested)` in `_merge_policy.sh`; tests grep these as schema authority.

## Open Questions

- OQ-API-1: Deprecated `--auto-merge=` alias — every-run stderr notice or once-per-project sentinel? Lean: every run, matches banner forever-until-opt-in.
- OQ-API-2: `is_clean_for_merge` inputs as positional args or env vars? Lean: positional (testable).
- OQ-API-3: Deprecated-alias path counts toward `resolved_from` as `cli` or `cli-deprecated`? Lean: `cli` (keep enum closed; deprecation is stderr concern).

## Integration Points

- Single-entry `merge_policy_dispatch` is the cleanest integration seam for `run.sh`.
- Five public functions × ~2 paths each = 10 unit cases; `MERGE_POLICY_DISPATCH_OVERRIDE` is the test seam.
- `commands/autorun.md` documents canonical flag + Migration section showing both forms.
- Closed `action`/`reason` enums owned by `_merge_policy.sh`'s readonly arrays — data persona references this as schema authority.

## Findings (v2 schema)

```yaml
- persona: api
  finding_id: api-001
  severity: major
  class: contract
  title: "Rename --auto-merge to --merge-policy; keep --auto-merge as deprecated alias"
  body: "Codex L1 flagged --auto-merge=pr as semantically backwards. --merge-policy=<value> reads cleanly with every value and aligns with the frontmatter key. Frontmatter key stays auto_merge_policy."
  suggested_fix: "Update Approach + ACs 2/20. Add AC: '--auto-merge=<value> accepted as deprecated alias; emits one-line stderr deprecation notice; same arg slot, same precedence'."

- persona: api
  finding_id: api-002
  severity: major
  class: contract
  title: "Single dispatcher entry merge_policy_dispatch consolidates JSONL row write"
  body: "Make merge_policy_dispatch the sole emitter of the JSONL row. run.sh never builds the row directly. Prevents action/reason enum drift across sites (the AC#9 risk class)."
  suggested_fix: "Pin signature in spec Approach: merge_policy_dispatch <policy> <slug> <verdict> <merge_capable> <codex_high_count> <run_degraded>. Sub-dispatchers private. Add AC: 'merge_policy_resolved JSONL row emitted from exactly one site (verified by grep of scripts/autorun/*.sh for the literal event name)'."

- persona: api
  finding_id: api-003
  severity: major
  class: contract
  title: "Closed-enum source-of-truth: _MP_ACTIONS and _MP_REASONS readonly arrays in _merge_policy.sh"
  body: "AC#9 specifies closed-set enums but doesn't pin definition site. Define as readonly arrays in helper; tests grep these as schema authority."
  suggested_fix: "Add to Approach: '_MP_ACTIONS and _MP_REASONS readonly arrays in scripts/autorun/_merge_policy.sh. Test asserts no other file in scripts/autorun/ contains these literals as freestanding strings.'"

- persona: api
  finding_id: api-004
  severity: minor
  class: contract
  title: "is_clean_for_merge must use return (not exit) so callers can wrap in if-statements"
  body: "With set -e enabled, predicate functions MUST use return 0/1. exit would terminate the whole script."
  suggested_fix: "Add to Approach (function contracts): 'is_clean_for_merge returns 0/1, never exits. merge_policy_validate exits 2 on invalid input. merge_policy_resolve writes <source>:<value> to stdout and returns 0.'"

- persona: api
  finding_id: api-005
  severity: minor
  class: contract
  title: "PATH-stub seams: GH_BIN and MERGE_POLICY_DISPATCH_OVERRIDE env hooks"
  body: "All gh and git invocations indirected via env vars so PATH-stub injection works without export -f."
  suggested_fix: "Add to Approach: 'All gh invocations use \"${GH_BIN:-gh}\"; all git invocations use \"${GIT_BIN:-git}\". MERGE_POLICY_DISPATCH_OVERRIDE replaces the merge-call path entirely (used in unit tests).'"

- persona: api
  finding_id: api-006
  severity: minor
  class: documentation
  title: "Banner width cap + single-fence convention for v0.10.x extractor compatibility"
  body: "60-col width cap on title/footer. Single === fence. ANSI color only when [ -t 2 ]."
  suggested_fix: "Add to UX subsection."

- persona: api
  finding_id: api-007
  severity: nit
  class: documentation
  title: "--help text discoverability — list --merge-policy first, --auto-merge as [deprecated alias]"
  suggested_fix: "Add AC: '--help on run.sh and autorun-batch.sh lists --merge-policy as canonical and --auto-merge as [deprecated alias]'."
```
