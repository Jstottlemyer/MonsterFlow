## Wave Sequencer Output: dynamic-roster-per-gate

### Wave Map

```
PRE-W2 (blocking empirical gate) || W1 (schemas — parallel with PRE-W2)
    └─ W2 (resolver + 3 Python helpers)
        ├─ W3 (spec Phase 3 tag-inference)
        ├─ W4 (gate dispatch wiring — 3 independent sub-trees)
        └─ W5 (dashboard)
            └─ W6 (full test matrix)
```

### PRE-W2: Empirical Dispatch Gate (blocking)

Single task. Must resolve before W4 architecture is finalized. Can run in parallel with W1.

- **Task PRE-1:** Run two probes: (a) `Agent(model: "opus", ...)` with a canary tool call; (b) `claude -p --model opus` with canary prompt. Record model-id in response. Write result to `plan/dispatch-precedence-evidence.md`.
- **Branch:** YES → proceed as planned. NO → W4 must pivot to wrapper-script tier-dispatch model. W2 and W3 unaffected either way.

### W1: Schemas (data contract, parallel with PRE-W2)

All three tasks are independent and run in parallel.

| Task | File | Change |
|---|---|---|
| W1-A | `schemas/spec-frontmatter.schema.json` | Add `tags` enum array + `tier_policy` block |
| W1-B | `schemas/persona-frontmatter.schema.json` | Confirm `fit_tags` required; lineage optional |
| W1-C | `schemas/selection.schema.json` (NEW) | Per-row `tier` field; `tier_policy_applied` audit block |

**Contract lock:** W2 Python helpers import and validate against W1 schemas at load time. W1 must be on disk and passing schema-lint before any W2 file is committed.

### W2: Resolver + Python Helpers (depends on W1 all + PRE-W2)

Three helpers are independent of each other; resolver extension depends on all three.

| Task | File | Notes |
|---|---|---|
| W2-A | `scripts/_tag_baseline.py` | NFKC + frontmatter strip + balanced-fence strip + lowercase + regex; AST-banned; SEC-02 |
| W2-B | `scripts/_persona_score.py` | `fit_score`, `combined_score`; lineage default `"claude"` |
| W2-C | `scripts/_tier_assign.py` | Top-N → tier rule; `validate_tier_pins` SEC-01 floor; SEC-04 baseline recompute |
| W2-D | `scripts/resolve-personas.sh` extension | Calls W2-A/B/C; emits `<persona>:<tier>` per line; writes `selection.json` with tier fields; cold-start fallback |

W2-A, W2-B, W2-C run in parallel. W2-D is sequential after all three.

### W3: /spec Phase 3 Tag-Inference (depends on W2-A only)

Single coherent task.
- `commands/spec.md` extension: post-draft call to `_tag_baseline.py`; LLM-propose; provenance comment; accept/edit/skip; baseline-detected tags non-removable.

### W4: Gate Dispatch Wiring (depends on W2-D; architecture conditional on PRE-W2)

**M2 fix explicit:** Each autorun script deps only on its own command file task.

| Sub-tree | Command task | Autorun task | Dep |
|---|---|---|---|
| W4-SR | `commands/spec-review.md` Phase 0b + stale-tags | `scripts/autorun/spec-review.sh` | W2-D + PRE-W2 result |
| W4-PL | `commands/plan.md` Phase 0b | `scripts/autorun/plan.sh` | W2-D + PRE-W2 result |
| W4-CK | `commands/check.md` Phase 0b | `scripts/autorun/check.sh` | W2-D + PRE-W2 result |

Within each sub-tree: command task first, then autorun task. Across sub-trees: fully parallel.

### W5: Dashboard (depends on W2-D, parallel with W3/W4)

- W5-A: `dashboard/index.html` — "Panel Tier Mix" column
- W5-B: `scripts/judge-dashboard-bundle.py` — read `selection.json` `tier_policy_applied`

### W6: Tests (depends on W1 + W2 + W3 + W4 complete)

All test files independent; orchestrator wiring is single sequential post-step.

| Task | File | Key fixtures |
|---|---|---|
| W6-A | `tests/test-dynamic-roster.sh` (NEW) | tag×tier×budget×opus_min×tier_pins×cold-start |
| W6-B | `tests/test-tier-resolver.sh` (NEW) | `_tier_assign.py` unit tests; N=2..8 panel table |
| W6-C | `tests/test-spec-tags-flow.sh` (NEW) | /spec Phase 3 flow |
| W6-D | `tests/test-security-floor.sh` (NEW) | SEC-01 A21 fixtures |
| W6-E | `tests/test-tag-baseline.sh` (NEW) | SEC-02 A22 + fences + NFKC |
| W6-F | `tests/test-explain-mutation-zero.sh` (NEW) | SEC-03 A23 mutation-zero |
| W6-G | `tests/test-resolve-personas.sh` (extension) | Tier output assertions |
| W6-H | `tests/run-tests.sh` (extension) | Wire W6-A through W6-G; orchestrator post-step |

Target: ≥33 fixtures, <15s wall-clock.

### Sequencing Risks

1. **PRE-W2 NO result:** If dispatch gate fails, W4 command files can still be drafted, but autorun tasks held pending pivot design.
2. **W1-C backward compat:** Existing `resolve-personas.sh` writes `selection.json` today without tier fields. W2-D must treat missing `tier` as `"auto"` at read time during MVP window.
3. **W3 baseline non-removable:** User "cannot remove baseline-detected tags" constraint needs a UX failure mode (warn and re-prompt, not silent drop).
4. **W6-H orchestrator gap (per memory):** Explicitly task one agent with `run-tests.sh` wiring. Do not leave as assumption.
