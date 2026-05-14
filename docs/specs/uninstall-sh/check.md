# uninstall-sh — Check Verdict (iter2)

**Checked:** 2026-05-14 (iteration 2 of max 3 — inline-fix pass)
**Iter1 verdict:** NO_GO (7 architectural blockers)
**Reviewers:** rev1 raw outputs reused; design.md revised inline (Fix Now path per /check skill — does NOT re-dispatch reviewers)
**Gate mode:** permissive
**Overall verdict:** GO_WITH_FIXES

---

## Summary

All 7 iter1 architectural blockers resolved via inline edits to `design.md`, `spec.md`, and `followups.jsonl`. The 10 should-fix items (SF1-SF10) are routed to `followups.jsonl` under permissive mode and consumed by `/build` wave 1 per the standard verdict-gated followups flow.

## MF Resolution Status

| MF | Title | Resolution |
|----|-------|------------|
| MF1 | T9 + prereq #6 framing factually wrong | design.md D12 + task table revised: T9 reframed to "audit/extend existing `install-hooks.sh --uninstall`"; "prereq #6" deleted from BLOCKING/RIDER framing |
| MF2 | Schema-drift mitigation has no task owner | design.md Wave 0 preconditions adds `schemas/install-manifest.v1.schema.json` + `tests/test-manifest-schema.sh` (owned by prereq #4); T5 description adds `--strict` validation against schema |
| MF3 | Wave 0 ships prereq #4 to adopters before consumer | design.md D12 records `MONSTERFLOW_MANIFEST=1` env-var staging requirement: prereq #4's manifest emission gated default-OFF, flips ON in uninstall.sh release |
| MF4 | T1+T3 are /spec tasks, not /build tasks | design.md Wave 0 replaced with preconditions gate (NOT a build task); T1+T3 deleted from task table; T2+T4 explicitly out-of-scope-of-uninstall-sh-build (they ship in their own pipelines) |
| MF5 | sr-i2 `repo_dir` filter has no task owner | design.md T5 description explicitly names `--repo-dir <dir>` filter obligation; AC23 multi-clone test added (install REPO_A; install REPO_B; uninstall REPO_A; verify only REPO_A reversed) |
| MF6 | OQ2 cold-start exit-code unrecorded | design.md D2 exit-code table records cold-start partial-apply → exit 1; OQ2 marked PINNED |
| MF7 | SKIP_CROSS_SPEC wrong default for blocking prereqs | design.md D9 revised: default behavior hard-fails AC6/AC6b/AC7/AC21 when prereq #5 absent; SKIP_CROSS_SPEC repurposed as opt-in flag for separate cold-start-only test suite |

## SF Followup Routing (10 items — permissive warn-route)

| SF | Disposition | Target Phase |
|----|-------------|--------------|
| SF1 sequencing wording | addressed via MF4 Wave 0 rewrite | docs-only |
| SF2 task sizes underestimated | addressed (T5 L, T6 L, T7 XL in revised table) | docs-only |
| SF3 T7/T8 race | addressed via SF6 split | build-inline |
| SF4 SHA-mismatch INSIDE-block edits | OPEN: T6 to write `<file>.uninstall.sentinel-block-bak.<ts>` sidecar before strip | build-inline |
| SF5 sr-i4 + sr-i5 task naming | addressed (T6 description explicitly names both) | build-inline |
| SF6 T8 split | addressed (T8a wiring / T8b docs in revised table) | docs-only |
| SF7 Python module vs CLI | OPEN: deferred to post-build review | post-build |
| SF8 drop v0 compat | addressed (D6 v0 compat removed; schema_version: 1 from day one) | docs-only |
| SF9 pseudo-open OQs | addressed (OQ2 pinned MF6, OQ4 pinned warn+proceed) | docs-only |
| SF10 D13 claimed edits | addressed (spec.md OOS #14 + OQ #4 added; preamble updated to 22 ACs) | docs-only |

Open followups routed to `/build` wave 1 consumption: SF4 (build-inline), SF7 (post-build), plus the still-open sr-i4 / sr-i5 / sr-i7 / sr-i8 (build-inline tests).

## Recommended Path

Proceed to `/build`. Wave 0 preconditions gate verifies prereq #4 + prereq #5 + `schemas/install-manifest.v1.schema.json` all green before Wave 1 begins. Wave 1 (T5 ∥ T6) builds the helper + uninstall.sh in parallel against the locked schema + subcommand surface. Wave 2 (T7 → T8a sequential; T8b ∥ T7) writes tests, wires `run-tests.sh`, ships docs. Wave 3 (T9) audits the existing `install-hooks.sh --uninstall` mode in parallel with everything else.

`/build` Phase 0c will load `check-verdict.json` (this file emits it below), verdict=GO_WITH_FIXES, and consume the open `followups.jsonl` rows into Wave 1 per target_phase routing.

```check-verdict
{
  "schema_version": 2,
  "prompt_version": "check-verdict@2.0",
  "verdict": "GO_WITH_FIXES",
  "blocking_findings": [],
  "security_findings": [],
  "generated_at": "2026-05-14T00:00:00Z",
  "iteration": 2,
  "iteration_max": 3,
  "mode": "permissive",
  "mode_source": "frontmatter",
  "class_breakdown": {
    "architectural": 0,
    "security": 0,
    "contract": 4,
    "documentation": 5,
    "tests": 4,
    "scope-cuts": 1,
    "unclassified": 0
  },
  "class_inferred_count": 0,
  "followups_file": "docs/specs/uninstall-sh/followups.jsonl",
  "cap_reached": false,
  "stage": "check"
}
```
