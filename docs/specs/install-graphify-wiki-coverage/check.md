OVERALL_VERDICT: GO

# Check — install-graphify-wiki-coverage (iteration 2, post-revision)

**Roster (iter1):** risk:opus, completeness:sonnet, scope-discipline:sonnet + codex-adversary
**Roster (iter2 spot-checks):** risk:opus + codex-adversary (focused re-verify on the 8 must-fix items)
**Gate mode:** permissive (frontmatter explicit)
**Iteration:** 2 / 3

## Overall Verdict: GO

Iteration 1 returned NO_GO with 8 architectural must-fix items. Justin chose `fix now`. The design.md was revised inline through three Codex passes (iter2 surfaced 4 precision issues with the fixes; iter3 surfaced 2 wording contradictions; iter4 surfaced 1 final wording cleanup, all resolved). Risk persona iter2 returned PASS with full resolution-matrix coverage. Final Codex pass reports "no material contradictions."

Design is build-ready. 4 waves, 20 tasks (now: 1.1-1.3, 2.1-2.6, 3.1a/3.1b/3.2/3.3/3.4/3.7/3.8/3.9, 4.1-4.3 = 20 tasks), AC1-AC14 (5 new), 10 design decisions (D1-D10) plus 4 architectural additions from /check (D11 drop EC20, D12 split graphify install, D13 stub side-effects, D14 within-wave parallelism rule).

## Reviewer Verdicts (iter2 spot-check)

| Dimension | Verdict | Key Finding |
|---|---|---|
| Risk (iter2) | PASS | All 8 MF1-MF8 resolved with concrete pointers; 2 minor SF + 5 OB notes for /build |
| Codex (iter2) | NO_GO → resolved | 4 precision issues in fixes (venv pip, short-circuit-vs-stub contradiction, has_cmd graphify gate, 3.3 brew-absent leftover) |
| Codex (iter3) | NO_GO → resolved | 2 wording contradictions (Wave 1/D14, 3.9 gate) + 4 SF (stale risks line, AC13 cross-file ordering, stub +x, mkdir -p) |
| Codex (iter4) | GO with one cleanup | 1 ambiguous sentence on cross-wave dependency, resolved inline |

## Resolution Matrix (iteration 1 → 2)

| MF | Status | Where addressed |
|---|---|---|
| MF1 — Drop EC20 (unreachable brew-unavailable path) | RESOLVED | spec.md L253 strikethrough; design.md D11; D1 token grammar; function surface; task 3.4 |
| MF2 — Split graphify install around CLAUDE.md baseline merger | RESOLVED | design.md D12; function surface; tasks 3.1a, 3.1b, 3.9 |
| MF3 — `has_cmd` not raw `command -v` | RESOLVED | D1 paragraph; tasks 2.1, 2.5; function-surface comments |
| MF4 — `posix_quote` hoist static test | RESOLVED | AC12 (3-part assertion); task 4.2; Risks table |
| MF5 — `RUNNING:` contract target (CASE_OUT vs STUB_LOG) | RESOLVED | D5 revised; task 4.2 explicit-target |
| MF6 — Test stubs with fake side effects | RESOLVED | D13; task 4.1 explicit list; AC14 |
| MF7 — graphify CLAUDE.md leak guard (sev:security) | RESOLVED | AC10 (two-part assertion); Risks table tagged sev:security |
| MF8 — Same-filesystem atomic write | RESOLVED | D7 revised; task 3.2 |
| Codex iter2 MF1 — venv pip not system pip3 | RESOLVED | Task 3.1a explicit `~/.local/venvs/graphify/bin/pip3` |
| Codex iter2 MF2 — short-circuit vs stubs contradiction | RESOLVED | D8 revised — no helper-level short-circuits, PATH stubs only |
| Codex iter2 MF3 — has_cmd graphify gate on 3.1b | RESOLVED | Task 3.1b + D12 + task 3.9 — three-site defense-in-depth |
| Codex iter2 MF4 — Drop 3.3 brew-absent branch | RESOLVED | Task 3.3 cleaned of unreachable branch |
| Codex iter3 — Wave 1 vs D14 contradiction | RESOLVED | D14 refined: Wave 1 parallel ok; only Wave 2/3 serialize |
| Codex iter3 — 3.9 gate ambiguity | RESOLVED | Task 3.9 gate text matched to helper's internal gate |
| Codex iter3 — stale "short-circuits" line in Risks | RESOLVED | Risks table line updated |
| Codex iter3 — AC13 cross-file ordering | RESOLVED | Shared `$EVENT_LOG` mechanism |
| Codex iter3 — stub executability | RESOLVED | D13 `chmod +x` requirement |
| Codex iter3 — `mkdir -p ~/.local/bin` | RESOLVED | Task 3.1a as defensive prepended step |
| Codex iter4 — cross-wave dependency wording | RESOLVED | Sequencing rule rewritten with Wave-4-specific exception |

## Must Fix Before Building (0 items)

None.

## Should Fix (2 carryovers — `/build` to address inline)

**SF-build1** — AC4 placeholder `<pre-run-marker>` in spec.md was not audited in /check round 2. `/build` should replace with `MARKER=$(mktemp); sleep 1` (the `sleep 1` handles APFS sub-second mtime per Risk OB).

**SF-build2** — EC2 (symlink-only recovery) now interacts with the D12 split (3.1a binary + 3.1b skill). The recovery path needs to test both halves: when venv exists + symlink missing, only the symlink is recreated; the skill install does not re-fire (3.1b's idempotency gate handles this, but explicit AC coverage would tighten the contract). `/build` may add an AC15 or fold into AC2.

## Accepted Risks (proceeding-with)

- **20-task plan for a "small change" feature** — proportionate per scope-discipline iter1 review. Not blocking.
- **6 wiki skills hardcoded** — explicit name array per task 2.2 (not glob); single update site if upstream ships a 7th.
- **Codex disabled at design gate** but heavily used at spec-review and (extensively) at check — independent-model coverage is present where it matters most.

## Iteration: 2 / 3 (cap NOT reached)

```check-verdict
{
  "schema_version": 2,
  "prompt_version": "check-verdict@2.0",
  "verdict": "GO",
  "blocking_findings": [],
  "security_findings": [],
  "generated_at": "2026-05-13T18:20:00Z",
  "iteration": 2,
  "iteration_max": 3,
  "mode": "permissive",
  "mode_source": "frontmatter",
  "class_breakdown": {
    "architectural": 0,
    "security": 0,
    "contract": 0,
    "documentation": 0,
    "tests": 2,
    "scope-cuts": 0,
    "unclassified": 0
  },
  "class_inferred_count": 0,
  "followups_file": null,
  "cap_reached": false,
  "stage": "check"
}
```

## Next Steps

**Ready for `/build`.** Two test-class should-fixes carry through as inline build notes (not blocking). The design.md is the single source of truth for /build — it contains AC10-AC14 additions, the D11-D14 architectural decisions from this checkpoint round, and the resolution-matrix log of why each fix landed.

Wave order for `/build` dispatch:
1. **Wave 1** parallel: 1.2 + 1.3 with 1.1 (different install.sh regions)
2. **Wave 2** sequential, one agent (all touch same install.sh section)
3. **Wave 3** sequential, one agent
4. **Wave 4** in its own agent: 4.1 may start in parallel with Waves 2-3 (depends only on 1.2); 4.2 waits on 3.7/3.8/3.9; 4.3 waits on 4.2

`go` to proceed, `hold` to pause.
