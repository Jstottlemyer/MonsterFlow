# Plan — autorun-merge-policy

**Spec:** `docs/specs/autorun-merge-policy/spec.md` (29 ACs, 0.95 confidence)
**Review:** `docs/specs/autorun-merge-policy/review.md` (refined inline post-NO_GO)
**Designers consulted (8):** api, data-model, ux, scalability, security, integration, wave-sequencer, codex-adversary
**Mode:** permissive (frontmatter-resolved)
**Generated:** 2026-05-08

---

## Design Decisions

### D1. **Phased release** — merge-policy v0.11.0 ships standalone; runtime-validation v0.12.0 extends (integration, scalability)
Spec's `validated → pr` fallback (MF4) is first-class behavior with own AC, reason value, and stderr warning. Runtime-validation's AC#19 only requires the four cross-spec edits to land in the same PR as runtime-validation itself — does NOT require both specs to release together. Phasing reduces blast radius, lets breaking-default flip ship sooner.

### D2. **Mode-aware predicate REFINES the verdict axis only** (Codex #2 hardening)
Live `MERGE_CAPABLE` at `run.sh:1069-1074` already embeds `CODEX_HIGH_COUNT == 0 + RUN_DEGRADED == 0 + VERDICT in {GO, GO_WITH_FIXES}`. The plan does NOT layer four redundant axes; `is_clean_for_merge` refines only the verdict portion under permissive mode (requiring GO, not GO_WITH_FIXES). Composition replaces the existing verdict-acceptance set, not the gate structure.

### D3. **CLI flag rename — `--merge-policy=` canonical, `--auto-merge=` deprecated alias** (api-001, Codex L1)
`--auto-merge=pr` is semantically backwards. Rename canonical to `--merge-policy=<pr|clean|validated>` aligning with frontmatter key (`auto_merge_policy`). Keep `--auto-merge=` as alias mapping to same arg slot, emits one-line stderr deprecation notice each run.

### D4. **Single-entry dispatcher + closed-enum source-of-truth** (api-002, api-003)
`merge_policy_dispatch` is the SOLE emitter of `merge_policy_resolved` JSONL row. `_MP_ACTIONS` and `_MP_REASONS` defined as readonly arrays in `_merge_policy.sh`; tests grep these as schema authority. Sub-dispatchers (`dispatch_pr_only`, `dispatch_clean_merge`, `dispatch_validated_merge`) are private to the helper.

### D5. **Drift detector lives at `run.sh` start, NOT `autorun-batch.sh`** (Codex #5 hardening)
`autorun-batch.sh` does NOT populate the queue (Codex verified at lines 8, 130-141) — it only iterates existing `queue/*.spec.md`. Drift check happens at `run.sh` start when spec is read; compares queue copy `auto_merge_policy` line vs `<project>/docs/specs/<slug>/spec.md` canonical.

### D6. **Asymmetric drift halt** (sec-001 — security blocker)
Drift detector halts (exit 2) when queue copy ELEVATES policy above canonical (e.g., canonical=`pr`, queue=`clean`). Downward drift (canonical=`clean`, queue=`pr`) warns only. Closes the privilege-elevation channel. Cross-project / missing-canonical → silent skip (no false positive).

### D7. **Validate-then-store in resolver** (sec-002)
`merge_policy_resolve` itself enforces the closed enum; `merge_policy_validate` becomes a tautology guard, not the only check. Prevents unvalidated argv from reaching log lines or dispatch on any future code-edit path.

### D8. **`spec_sha` captured once at run start** (scal-002, multiple convergent)
`spec_sha = git hash-object queue/<slug>.spec.md` computed in same shell stanza as `SPEC_FILE` export at `run.sh:670`. Cached in `SPEC_SHA` shell var. Reused at merge-call site. Immutable for the run even if queue file is hand-edited mid-flight.

### D9. **PR conventions extend existing title pattern** (Codex #5 hardening)
Current title is `autorun: $SLUG` at `run.sh:895-898`; no draft handling, no label. Plan extends to: title format `[autorun] <slug>` (matches spec D-decision but normalize), body adds verdict + reviewer summary + spec link + run.log path, draft state mode-aware (`GO_WITH_FIXES` or `fell_back` → draft; `GO` + `pr_only` → ready-for-review), label `autorun`, re-run force-pushes existing branch. **All NEW behavior**, not extensions of existing.

### D10. **Banner: two-tier (verbose / terse)** (ux-recommendation)
Verbose tier when ANY knob's `resolved_from=default`; terse 4-line summary once user expressed intent for everything. Manual-pipeline pointer + override-instruction footer ride on verbose tier only. ANSI color on `⚠` line gated by `[ -t 2 ]`. 78-col width cap.

### D11. **`.manual-review` touch-file path: `queue/<slug>/.manual-review` with mkdir requirement** (Codex #3 + scal-001)
Live `queue/<slug>/` is the artifact directory created by `run.sh:668-669` (`ARTIFACT_DIR`). Touch-file path is `queue/<slug>/.manual-review`. **First-time use requires `mkdir -p queue/<slug>` from user** if dir doesn't exist yet. Document in `commands/autorun.md` + add a banner hint when the spec is being run for the first time (no prior artifact dir).

### D12. **Use `$PROJECT_DIR` not `$PROJECT_ROOT`** (Codex #5 hardening)
Live autorun exports `PROJECT_DIR` at `run.sh:26-27` and `205-206`. Plan pseudocode that says `$PROJECT_ROOT` is wrong; literal implementation would fail constitution lookup. All references use `$PROJECT_DIR`.

### D13. **`_merge_policy.sh` sources `_gate_helpers.sh` itself** (Codex #5 hardening)
`run.sh` currently sources `defaults.sh` + `_policy.sh` only (line 246-252), NOT `_gate_helpers.sh`. New helper must source `_gate_helpers.sh` at top so it can call `_gh_frontmatter_field`. No top-level side effects — sourcing is idempotent.

### D14. **`gate_mode` mapping to live `AUTORUN_MODE`** (Codex #5 hardening)
Live autorun uses `--mode=overnight|supervised` + policy axes; the manual `gate_mode_resolve` flow exists per `_gate-mode.md` but isn't called from autorun's hot path. Banner showing `gate_mode: permissive` reads from spec frontmatter via `_gh_frontmatter_field` (per spec); plan documents the relationship between `AUTORUN_MODE` and `gate_mode` for forensic clarity in `commands/autorun.md`. **Implementation:** banner reads `gate_mode` from `$SPEC_FILE` directly; `AUTORUN_MODE` is orthogonal.

### D15. **Codex-absent semantics: `CODEX_HIGH_COUNT == 0` vacuously satisfied; mode-qualified** (Codex #5 hardening)
`CODEX_HIGH_COUNT` starts at 0 (`run.sh:491-496`). Missing/auth-failed Codex runs through `policy_act codex_probe` (1000-1016) — supervised mode can halt, warn mode degrades. `is_clean_for_merge` reads `CODEX_HIGH_COUNT` directly — if it's 0 (because Codex didn't run AND policy_act didn't halt), the merge is clean per the existing axis. Plan documents this nuance in helper header.

### D16. **YAML-subset parser semantics — pinned in plan** (sec-003 + Codex #1)
`_gh_frontmatter_field` semantics (per Codex source-grounded read of `scripts/_gate_helpers.sh:55-75`):
- Reads only between first two `---` lines at column 1
- Matches `field: value` with optional leading spaces (first match wins; duplicate keys resolve to first)
- Strips trailing comments only when preceded by whitespace
- Strips one pair of surrounding quotes (single OR double)
- Does NOT support block/multiline values (`|`, `>`)
- Quoted `#` values can be mangled in edge cases

Plan adds 5 test fixtures verifying this behavior. Resolver halts (exit 2) on any non-enum value the parser returns (validate-then-store per D7).

### D17. **Touch-file ordering invariant — encoded as code comment + test** (sec-004)
`.manual-review` check happens in `merge_policy_dispatch`, immediately before `gh pr merge` argv construction — NOT at run start. Mid-run touch must take effect. Test fixture uses `MERGE_POLICY_DISPATCH_OVERRIDE` to touch the file mid-run and verifies merge is skipped.

### D18. **`gate_mode` field added to audit row** (dm-001)
Forensic audit row includes `gate_mode: strict | permissive` so post-incident forensics can see which mode authorized the merge. One additional field; persona-metrics-validator gains one additive rule.

### D19. **Out-of-scope explicitly:** TOFU `.trusted-hashes.json` (dm-003), Levenshtein typo suggestion (carved to BACKLOG per IB2), env-var escape hatch (`MONSTERFLOW_PRESERVE_LEGACY_AUTOMERGE`), banner-noise reduction at N≥50 (scal-005), `run.log` rotation (scal-006 — separate backlog item `run-log-rotation`).

### D20. **Cross-spec PR-backlog triage wall mitigation** (scal-004)
Default flip + 10-100 slug overnight = triage wall without `pipeline-autorun-final-status-render` (already in backlog). Plan recommends: ship v0.11.0 with CHANGELOG note recommending soft batch-size ceiling (≤10) until summary lands. Add `commands/autorun.md` recipe `gh pr list -l autorun --json number,title,isDraft` for interim manual triage.

---

## Implementation Tasks

Three waves (data → behavior → integration). Within each wave, parallelizable tasks marked. Test fixtures land WITH their corresponding logic per memory `feedback_test_orchestrator_wiring_gap.md`; orchestrator wiring (`tests/run-tests.sh` registration) is single sequential post-step at end of each wave.

| # | Task | Wave | Depends On | Size | Parallel |
|---|------|------|------------|------|----------|
| **W1.1** | Create `scripts/autorun/_merge_policy.sh` skeleton — sourcing guard, source `_gate_helpers.sh`, `_MP_ACTIONS` + `_MP_REASONS` readonly arrays, `_MP_RESOLVED_FROM` enum, function signatures + stubs returning sentinel | 1 | — | S | — |
| **W1.2** | Document YAML-subset semantics of `_gh_frontmatter_field` in helper header (5 acceptance bullets per Codex source-read) | 1 | W1.1 | S | yes (with W1.3) |
| **W1.3** | Define `merge_policy_resolved` JSONL row schema in helper comment + test fixture validating shape (10 fields incl. `gate_mode`) | 1 | W1.1 | S | yes (with W1.2) |
| **W1.4** | Wave 1 orchestrator wiring: register schema-shape test in `tests/run-tests.sh`; invoke `autorun-shell-reviewer` subagent on helper skeleton; verify High==0 BEFORE commit | 1 | W1.1, W1.2, W1.3 | S | — (sequential closer) |
| **W2.1** | Implement `merge_policy_resolve` — full precedence (CLI > spec > constitution > default); reads `$SPEC_FILE`; constitution at `$PROJECT_DIR/docs/specs/constitution.md`; **validate-then-store** per D7 | 2 | W1.4 | M | yes |
| **W2.2** | Implement `merge_policy_validate` — closed-enum check; exit 2 on invalid; stderr warn on unknown key (no Levenshtein) | 2 | W1.4 | S | yes |
| **W2.3** | Implement `is_clean_for_merge` — mode-aware predicate; refines verdict axis (per D2); `return 0/1` never `exit` (per api-004) | 2 | W1.4 | M | yes |
| **W2.4** | Implement `merge_policy_render_banner` — two-tier (verbose if any default, terse otherwise); ANSI gated `[ -t 2 ]`; 78-col cap | 2 | W1.4 | M | yes |
| **W2.5** | Implement `merge_policy_dispatch` + 3 sub-dispatchers (`dispatch_pr_only`, `dispatch_clean_merge`, `dispatch_validated_merge` — fallback to `pr` per MF4); SOLE writer of JSONL row; respects `MERGE_POLICY_DISPATCH_OVERRIDE` test hook | 2 | W2.1, W2.2, W2.3 | L | — |
| **W2.6** | Implement `queue_copy_drift_check` — asymmetric: halt on elevation, warn on downward (per D6); silent-skip if canonical absent | 2 | W2.1 | M | yes (with W2.4) |
| **W2.7** | Implement `.manual-review` detection helper — checked immediately before merge dispatch (per D17) | 2 | W2.5 | S | — |
| **W2.8** | Test fixtures: AC#16 (no policy → pr_only), AC#17 (clean+gates-clean → auto_merged), AC#18 (clean+warnings → fell_back/warnings_present), AC#20 (CLI overrides spec), AC#21 (validated → pr fallback), AC#22 (invalid value exit 2), AC#23 (manual-review touch file), AC#24 (drift detector); plus 5 YAML-subset fixtures (D16) | 2 | W2.1-2.7 | L | yes (each fixture independent) |
| **W2.9** | Wave 2 orchestrator wiring: register all wave-2 fixtures in `tests/run-tests.sh` (single sequential edit); invoke `autorun-shell-reviewer` on now-implemented helper; verify High==0 + grep-assert validated→pr_only path; verify enum closure | 2 | W2.1-W2.8 | S | — (sequential closer) |
| **W3.1** | Wire `merge_policy_resolve` into `run.sh` after `$SPEC_FILE` export (line 670); export `RESOLVED_POLICY` + `RESOLVED_FROM`; capture `SPEC_SHA = git hash-object` (per D8) | 3 | W2.9 | S | yes |
| **W3.2** | Wire banner emission in `run.sh` immediately after resolution, before Phase 0b dispatch (per int-002 ordering invariant) | 3 | W2.9 | S | yes |
| **W3.3** | Wire `queue_copy_drift_check` at start of `run.sh` (per D5; NOT in `autorun-batch.sh`); after canonical resolved | 3 | W2.9 | S | yes |
| **W3.4** | Wire `.manual-review` check + `merge_policy_dispatch` replacing `gh pr merge` call at `run.sh:1069-1102`; preserve four-axis gate as-is, refine only verdict via `is_clean_for_merge` | 3 | W2.9 | M | — |
| **W3.5** | Wire `--merge-policy=<value>` CLI flag in `autorun-batch.sh` and `run.sh` arg-parse; `--auto-merge=` deprecated alias (per D3); pass through from batch to run.sh | 3 | W2.9 | S | yes (with W3.6) |
| **W3.6** | PR conventions: title `[autorun] <slug>` (replacing `autorun: $SLUG`), body template, draft-state logic, `autorun` label, force-push re-run (per D9) | 3 | W3.4 | M | — |
| **W3.7** | Test fixtures: AC#19 (branch-protection PATH-stub) + AC#25 (migration PATH-stub no-policy); use existing `*_OVERRIDE` env-hook pattern | 3 | W3.1-W3.4 | M | yes |
| **W3.8** | `commands/autorun.md` — full doc surface: new key + precedence + CLI flag + banner content (both tiers) + escape hatch + manual-pipeline pointer + how to silence banner + YAML-subset semantics + interim PR-backlog triage recipe | 3 | W3.1-W3.6 | M | yes |
| **W3.9** | `templates/constitution.md` — commented-out `auto_merge_policy:` example with explanatory note | 3 | W3.8 | S | yes (with W3.10) |
| **W3.10** | `CHANGELOG.md` — `## [0.11.0] - <date>` under `### ⚠ BREAKING DEFAULT` heading; soft-batch-size note; `VERSION` → `0.11.0` | 3 | W3.8 | S | yes (with W3.9) |
| **W3.11** | Wave 3 orchestrator wiring: register AC#19 + AC#25 fixtures in `tests/run-tests.sh`; grep-test against literal old-enum strings in docs (per memory `feedback_schema_bump_grep_prose_drift`); invoke `autorun-shell-reviewer` on `run.sh` + `autorun-batch.sh` BEFORE commit; invoke `persona-metrics-validator` on post-merge run.log fixture (AC#29) | 3 | W3.1-W3.10 | S | — (sequential closer) |
| **W3.12** | End-to-end smoke run on a no-policy fixture spec — produce banner + open PR + write correct JSONL row; verify all 11 sections present | 3 | W3.11 | S | — |
| **W3.13** | Release: `gh release create v0.11.0 --title "v0.11.0 — autorun-merge-policy: PR by default" --notes "..."` (per memory `reference_gh_release_create.md`) | 3 | W3.12 | S | — |

**Total:** 27 tasks. Wave 1: 4 (S only). Wave 2: 9 (S/M/L mix). Wave 3: 13 (S/M, integration-heavy). Estimated ~500-700 LoC + 13 test fixtures.

---

## Open Questions

1. **OQ1 (deferred to /check):** Banner verbose-tier triggers on any-default OR only merge-policy-default? Spec letter is the latter; UX recommendation is former. Owner call before /build.
2. **OQ2 (deferred to /check):** Drift detector additive case (canonical key missing, queue key set) — silent-skip or warn? Lean: silent-skip per Codex framing.
3. **OQ3 (open):** PR-backlog triage wall — sequence-coordinate v0.11.0 with `pipeline-autorun-final-status-render`, or ship now with documented gap? Lean: ship now + interim recipe; coordinate cross-spec at `pipeline-autorun-final-status-render` time.
4. **OQ4 (resolved by D14):** `gate_mode` vs live `AUTORUN_MODE` — pin via doc relationship in `commands/autorun.md`; banner reads from spec frontmatter directly.

---

## Risks

| # | Risk | Severity | Mitigation |
|---|------|----------|------------|
| R1 | Validated-fallback regression — agent ships `validated → clean` (original spec position) | major | W2.9 grep-asserts implementation hits `dispatch_pr_only` not `dispatch_clean_merge` |
| R2 | Banner placement before resolver returns — breaks AC#10 ordering invariant | major | W2.4 banner takes resolved struct as arg; W3.2 wiring tested with run.sh ordering grep |
| R3 | Test orchestrator race (parallel agents append to run-tests.sh) | major | Per-wave single sequential closer; test files are agent-owned, orchestrator wiring is closer-only |
| R4 | Bash 3.2 portability violations (`${arr[-1]}`, `export -f`) | major | `autorun-shell-reviewer` subagent at W1.4, W2.9, W3.11 — three invocations; PATH-stub for tests |
| R5 | Drift detector misplaced (`autorun-batch.sh` has no live queue-copy hook per Codex #5) | major | D5 + W3.3 place at `run.sh` start; documented |
| R6 | `$PROJECT_ROOT` vs `$PROJECT_DIR` literal-pseudocode-fail | major | D12 + grep-assert in W2.1 |
| R7 | YAML-subset edge case bites at runtime (multiline value, duplicate key) | minor | D16 + 5 test fixtures in W2.8; resolver halts on non-enum |
| R8 | Touch-file TOCTOU between dispatch and merge | minor | D17 + W2.7 test using `MERGE_POLICY_DISPATCH_OVERRIDE` |
| R9 | PR-backlog triage wall on first overnight after default flip | major | D20 + interim recipe in W3.8; coordinate with `pipeline-autorun-final-status-render` |
| R10 | Prompt-injection blast radius grows under `clean` | minor | sec-005 acknowledged; carved `prompt-injection-resistance` to BACKLOG |
| R11 | Existing PR title `autorun: $SLUG` vs new `[autorun] <slug>` — backward compat for in-flight PRs | minor | W3.6 uses force-push on existing branch (existing semantics); old PRs keep their title |

---

## Cross-Spec Coordination

`autorun-runtime-validation-gate` (separate spec, drafted at 0.93 confidence) extends this spec's `reason` enum with `runtime_not_pass` and adds `details.runtime_status` field. Per D1 (phased release), this spec ships v0.11.0 first; the runtime-validation PR additively extends:
- Adds `runtime_not_pass` to `_MP_REASONS` array (additive; no break)
- Adds `details.runtime_status` to JSONL row schema (optional field; null when cause is not runtime)
- Replaces `dispatch_validated_merge` body to read `runtime-validation.json.status == "pass"` instead of falling back to `pr`
- Updates banner to reflect runtime-validation requirement when policy is `validated`

All four cross-spec edits land in the same PR as `autorun-runtime-validation-gate` per its AC#19.

---

## Approve to proceed to /check? (approve / adjust <what to change>)
