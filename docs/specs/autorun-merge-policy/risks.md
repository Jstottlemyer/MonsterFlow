# Risk Analysis: autorun-merge-policy

**Created:** 2026-05-08
**Scope:** Pre-implementation risk surface beyond the seven /spec-review findings
**Method:** Senior-architect review of spec internals, integration surface, and adopter blast radius

## High-Severity Risks

### R1. Mode-aware predicate inversion under recycle dynamics
**Severity:** High
**Failure mode:** Under `gate_mode: permissive` + `auto_merge_policy: clean`, `gate_max_recycles: 2` allows a NO_GO → GO_WITH_FIXES → GO transition. The predicate evaluates only the terminal verdict, but if the recycle loop *demotes* findings into `followups.jsonl` to coerce the verdict to GO, `clean` auto-merges code whose findings were demoted-not-resolved. The asymmetric-risk argument fails precisely at the boundary the spec is engineered to protect — silent merges with documented-but-unfixed Major issues.
**Mitigation:** Add an AC: under `clean` policy, if any recycle in the run wrote to `followups.jsonl` for this slug, auto-merge is suppressed and `action=fell_back, reason=recycle_demoted_findings` (9th `reason` value). Predicate becomes "terminal verdict GO **AND** zero followups generated this run." Cheap to implement (count `followups.jsonl` lines diff between run-start and run-end); closes the recycle-laundering loop.

### R2. Audit-row write timing leaves crashes invisible
**Severity:** High
**Failure mode:** Spec emits `merge_policy_resolved` at merge-dispatch (end of run). If autorun crashes mid-gate (build phase OOM, network drop on `gh pr create`, force-killed by morning user), no audit row exists for that slug despite resolution having happened at run-start. Forensic question "what policy was in force when we lost slug X overnight?" is unanswerable. The `spec_sha` field — explicitly motivated as forensic — is the first casualty.
**Mitigation:** Emit two events, not one: `merge_policy_resolved` at run-start (captures `policy`, `resolved_from`, `spec_sha`, `pr_number=null`, `action=null`), then `merge_action_completed` at end (captures `action`, `reason`, `pr_number`, `merge_sha`). Closed-set event types means readers can join on `slug+ts_run_start`. Adds one JSONL line per slug; preserves "additive event type" claim because both are additive.

### R3. `gh pr create` body assembly is the load-bearing path now
**Severity:** High
**Failure mode:** Pre-spec, autorun's hot path was `gh pr merge` after `gh pr create`. Post-spec, `gh pr create` is the *primary terminal action* for ~100% of default-config runs. Any latent bug in PR-body assembly (e.g., reviewer-summary truncation crashing on edge multibyte content, spec-link rendering wrong on cross-project runs, label `autorun` not existing in the target repo) now blocks every autorun. Today these bugs were invisible because the merge happened anyway; the PR was a side-effect, not the deliverable.
**Mitigation:** Explicit AC: "PR creation hardening — gh CLI failures during `gh pr create` are caught, run.log records `action=merge_failed, reason=pr_create_failed` (10th `reason` value), branch is preserved, exit 0." Add a fixture stubbing `gh pr create` returning exit 1 with realistic stderr (label-missing, body-too-long, auth-expired). Without this, the default-flip turns one rare-failure path into the rare-failure path that matters.

## Medium-Severity Risks

### R4. CHANGELOG breaking-default heading discoverability
**Severity:** Medium
**Failure mode:** Adopters who pulled MonsterFlow weeks ago and run `git pull` for an unrelated fix won't read CHANGELOG; first contact with the new default is the runtime banner at 2 AM during overnight autorun. The banner mentions the version flip ("Default flipped in v0.11.0") but doesn't link to the *opt-out one-liner* — adopters land on `docs/specs/autorun-merge-policy/spec.md` (550 lines of contributor-facing prose), bounce, set up a workaround.
**Mitigation:** Banner footer must include the literal opt-out line: `To restore v0.10.x behavior: echo 'auto_merge_policy: clean' >> <project>/docs/specs/constitution.md`. One-liner, copy-pasteable, no doc indirection. AC#10 should require this exact restore-line in the default-warning block.

### R5. `_gh_frontmatter_field` semantics for missing-vs-empty
**Severity:** Medium
**Failure mode:** Helper at `scripts/_gate_helpers.sh:49` returns empty string for both "key absent" and "key present with empty value." The resolver falls through to next layer in either case — fine. But the *drift detector* compares `can_val` and `que_val` both extracted via the same helper; if canonical has `auto_merge_policy:` (empty value, malformed) and queue has the key absent, drift detector swallows it (both render as `""`). Real drift goes undetected. Conversely, if a future contributor adds whitespace-trimming inconsistencies, false-positive drift warnings fire on every run.
**Mitigation:** Add a third return mode to a thin wrapper used by drift detector only: `merge_policy_field_state` returns `present:<val>` | `present_empty` | `absent`. Drift detector compares states, not raw values. Three-line wrapper; locks the contract; doesn't pollute the public helper.

### R6. Test-fixture `gh` PATH-stub doesn't exercise async `--auto` queue semantics
**Severity:** Medium
**Failure mode:** Memory `feedback_branch_protection_external_prs` documents that `gh pr merge --squash --auto` *queues* behind branch protection, returning exit 0 immediately even when the merge hasn't landed. The test fixtures (AC#17, AC#19) stub `gh pr merge` synchronously — they verify exit code and call shape, not the queue-vs-immediate semantics. A fixture passing means nothing about real-world `auto_merged` rows in run.log: under branch protection, `merge_sha` may be null at audit-row write time even though `action=auto_merged`. Forensic schema breaks (AC#9 implies `merge_sha` non-null when action is `auto_merged`).
**Mitigation:** Either (a) explicit AC: "`merge_sha` may be null when action=auto_merged AND merge is queued; populated when merge lands; readers MUST tolerate both states" (preserve schema honesty), or (b) defer `merge_sha` capture to a follow-up `autorun-merge-sha-poller` spec and remove from v1 schema. Today's spec promises a field it cannot reliably populate.

### R7. Banner emitted on stderr collides with reviewer-output capture
**Severity:** Medium
**Failure mode:** Banner is multi-line and (per /spec-review item D-2) likely lands on stderr. Existing `scripts/autorun/run.sh` likely tees stderr for reviewer-output capture (parallel persona dispatch routes stderr). Banner text — including the 4-line override-instruction footer — gets interleaved into per-persona log files. Downstream parsers (dashboard, persona-metrics-validator) currently tolerate unknown lines but the banner's `⚠` and ASCII-art separator (`=== autorun runtime config ===`) may match log-pattern regexes used elsewhere.
**Mitigation:** Banner emits to stdout, not stderr. Warning line within banner is prefixed `⚠` for visual but stays on stdout. Stderr reserved for actual errors and the existing degraded-run signals. Add a fixture: `scripts/autorun/run.sh foo 2>/dev/null` still shows the full banner.

## Low-Severity Risks

### R8. `--auto-merge` flag spelling drift
**Severity:** Low
**Failure mode:** Spec uses `--auto-merge=<value>` (hyphenated). Existing autorun flags trend toward underscore (`--auto-merge` is consistent, but adjacent flags like `--gate-mode` set the precedent). Easy to typo as `--auto_merge` in docs/CHANGELOG/banner footer; copy-paste failures during opt-in.
**Mitigation:** Single grep-test in `tests/test-autorun-merge-policy.sh` asserting the literal `--auto-merge=` appears in `commands/autorun.md`, the banner footer template, the CHANGELOG entry, and `templates/constitution.md` comment. Catches drift at PR time.

### R9. `validated` value silently bit-rots
**Severity:** Low
**Failure mode:** `validated` ships as a forward-compat value falling back to `pr`. Months pass; `autorun-runtime-validation-gate` ships under a different knob name or different semantics. The `validated` value remains accepted but means something other than what the new gate exposes. Adopters who set it early get inconsistent behavior across version bumps.
**Mitigation:** Add a sentinel comment in `_merge_policy.sh` listing the explicit contract `validated` will activate when the gate ships. Cross-link from the future spec back to this commit. Cheap insurance against semantic drift across spec authorship boundaries.

## Summary

Asymmetric-risk thesis is sound and the default flip is the right call. Top implementation risk is **R1 (recycle-demoted findings laundering past `clean`)** — closes a hole the spec's own predicate opened — followed by **R2 (audit timing) and R3 (PR-create as new hot path)**. **GO with R1/R2/R3 inline-resolved before /plan**; remaining risks are addressable during /build with named ACs.
