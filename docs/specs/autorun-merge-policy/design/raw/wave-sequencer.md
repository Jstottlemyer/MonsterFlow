# Wave Sequencer — autorun-merge-policy

## Wave Decomposition (three-gate default: data → behavior → integration)

### Wave 1 — Data contract closure (S/M)
- `auto_merge_policy` frontmatter key validation against `{pr, clean, validated}`
- `action` enum (4 closed) + `reason` enum (8 closed) defined as readonly arrays in `_merge_policy.sh`
- `merge_policy_resolved` JSONL row schema with forensic fields (`pr_number`, `merge_sha`, `spec_sha`)
- `scripts/autorun/_merge_policy.sh` skeleton: function signatures + stubs + sourcing guard + `MERGE_POLICY_DISPATCH_OVERRIDE` env hook
- Verify `_gh_frontmatter_field` reachable from both `run.sh` and `autorun-batch.sh` source contexts (smoke test)
- AC#9 schema-shape test fixture
**Depends on:** none. **Verifier:** sourcing exits 0; `bash -n` clean; `autorun-shell-reviewer` High==0 on skeleton.
**Minimum-shippable:** Yes — gives `autorun-runtime-validation-gate` a stable contract surface to extend additively.

### Wave 2 — Behavior closure (M/L)
- `merge_policy_resolve` full precedence: CLI > spec > constitution > default; reads `$SPEC_FILE` (queue copy); constitution at `<project>/docs/specs/constitution.md`
- `merge_policy_validate` — reject unknown values exit 2; warn on unknown keys (no Levenshtein per IB2)
- `is_clean_for_merge` — mode-aware predicate; Codex-absent vacuously satisfies
- `merge_policy_render_banner` — all 4 knob lines; warns only on merge-policy `resolved_from=default`
- `merge_policy_dispatch` + 3 sub-dispatchers (`pr_only`, `clean_merge`, `validated_merge`) — `validated_merge` falls back to `pr` per MF4, NOT `clean`
- `queue_copy_drift_check` — silent-skip if canonical absent
- `.manual-review` touch-file detection function
- Test fixtures AC#16-18, 20-24 — each fixture lands with the function it tests; orchestrator wiring (`run-tests.sh`) is single sequential post-step at END of wave
**Depends on:** Wave 1's stable signatures + enums. **Verifier:** all 8 fixtures pass; `tests/run-tests.sh` runs them; `autorun-shell-reviewer` High==0.
**Minimum-shippable:** Partially — dead code without caller. Cannot ship standalone.

### Wave 3 — Integration + ship surface (M)
- `scripts/autorun/run.sh` — call `merge_policy_resolve`, emit banner before Phase 0b, check `.manual-review` before merge, replace `gh pr merge` with `merge_policy_dispatch`. Capture `spec_sha = git hash-object queue/<slug>.spec.md` once at run start.
- `scripts/autorun/autorun-batch.sh` — `--auto-merge=` CLI flag (uniformly applied); call `queue_copy_drift_check` at queue-copy
- `run.sh` — `--auto-merge=` CLI flag (single-slug case)
- AC#19 (branch-protection PATH-stub fixture) + AC#25 (migration PATH-stub no-policy fixture)
- PR conventions wiring: title, body, draft-vs-ready, label
- `commands/autorun.md` — full doc surface
- `templates/constitution.md` — commented-out example
- `CHANGELOG.md` — `## [0.11.0]` under `### ⚠ BREAKING DEFAULT`
- `VERSION` → `0.11.0`
- AC#28 (autorun-shell-reviewer invocation BEFORE commit) + AC#29 (persona-metrics-validator on post-merge fixture)
**Depends on:** Wave 1 contract + Wave 2 logic. Strict sequential.
**Verifier:** end-to-end smoke run produces banner + opens PR + writes correct JSONL row; tests/run-tests.sh green.

## Sequencing Risks

1. **Banner before resolver** — wave-2 banner function takes resolved struct as arg; wave-3 caller passes it. Don't let agent integrate banner into run.sh before resolver returns structured value.
2. **Test fixture / orchestrator race** — per memory `feedback_test_orchestrator_wiring_gap.md` + `feedback_parallel_agents_shared_file_race.md`. Do NOT parallelize edits to `tests/run-tests.sh`. Each wave appends as single sequential closing task.
3. **Validated-fallback regression** — wave 2 acceptance gate MUST grep-assert implementation hits `dispatch_pr_only` (not `dispatch_clean_merge`) on `validated` + missing-gate.
4. **`spec_sha` capture timing** — pin in plan: capture in same shell stanza as `SPEC_FILE` export.
5. **Codex-absent semantics** — wave 2 plan must cite Definitions paragraph verbatim to prevent fail-closed re-litigation.
6. **Schema bump grep drift** — per memory `feedback_schema_bump_grep_prose_drift`, wave-3 doc edits must NOT inline-paste old enum subset. Add wave-3 grep-test against literal old-enum strings.
7. **`gate_max_recycles` interaction** — banner must show this as a knob even though merge-policy doesn't own it. Pin: banner reads each knob via `_gh_frontmatter_field`.

## Open Questions

- OQ1: Plan should confirm and not silently introduce `--merge-policy` alias for `--auto-merge` (Codex L1).
- OQ2: Should banner respect `NO_COLOR` / non-tty stderr (CI logs)? Lean: yes — emit plain always, no ANSI.
- OQ3: Drift detector warn on additive drift (canonical key missing, queue key set)? Lean: silent-skip — canonical might pre-date the feature.

## Integration Points

- **Wave 1 → Wave 2:** function signatures + enum constants + `MERGE_POLICY_DISPATCH_OVERRIDE` hook. Header block in helper documents each signature.
- **Wave 2 → Wave 3:** `merge_policy_dispatch` is single integration handle for `run.sh`. Wave 3 should NOT call sub-dispatchers directly.
- **Wave 1 → cross-spec (`autorun-runtime-validation-gate`):** additively-extensible `reason` enum. Document additive extension in helper header — no closed-case-statement assumption.
- **Wave 3 → release:** single `gh release create v0.11.0 --title "..." --notes "..."` call (per memory `reference_gh_release_create.md`).

## Wave-shape summary

Wave 1 is smallest minimum-shippable surface (contract closure usable by sibling spec). Wave 2 is heaviest (logic + 8 fixtures). Wave 3 is user-visible cutover. Each wave has independent verifier signal. No schema or enum split across waves. Banner and drift detector correctly sequenced behind resolver. Validated-fallback safety inversion (MF4) locked into wave 2 acceptance.
