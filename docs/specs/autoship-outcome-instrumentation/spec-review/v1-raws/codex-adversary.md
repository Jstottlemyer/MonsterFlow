# Codex Adversarial Review — autoship-outcome-instrumentation

Verified against actual code in `scripts/_goal_autoship_render.py` and `scripts/autorun/run.sh`.

## Findings

### CX-1 — Single terminal-block call site misses most terminal exits [architectural / blocker]

`docs/specs/autoship-outcome-instrumentation/spec.md:34,59,134` is wrong about "every autorun run" and "exactly one" from a final terminal-block call. `run.sh` has many terminal exits before `complete`:
- STOP exits at `scripts/autorun/run.sh:819-826`
- Stage failures at `874-878`, `928-932`, `948-957`
- Build STOP/failure at `1011-1018`
- PR body/stale-base/PR-create failures at `1106-1182`
- Codex block exits at `1283-1315`

The only true process-wide terminal hook is the `EXIT/INT/TERM` trap at `673-683`. A single call before `exit 0` at `1497-1508` will miss most failed/halted outcomes. **Converges with gaps F1 and scope S1.**

### CX-2 — Helper JSONL write failures return success — AC6 gives false confidence [contract / major]

`docs/specs/autoship-outcome-instrumentation/spec.md:37,124-127,139` assumes helper write failures return non-zero. They do not. `_goal_autoship_render.py` catches JSONL append exceptions, prints `[autoship] warning: JSONL write failed...`, and returns success at `scripts/_goal_autoship_render.py:214-229,369`. The proposed shell `rc != 0` wrapper will not detect permission/fsync/path write failures, so AC6 gives false confidence unless the helper changes or shell inspects stderr/output.

### CX-3 — Wrong variable name `pr_url` (actual: `PR_URL_VAL`); existing canonical extractor unused [contract / blocker]

`docs/specs/autoship-outcome-instrumentation/spec.md:72-80,128,135-136,142` uses the wrong variable and a weaker parser. `run.sh` uses `PR_URL_VAL`, not `pr_url`, and already has robust canonical PR extraction at `scripts/autorun/run.sh:1418-1423`. `${pr_url##*/}` would be empty because `pr_url` is unset; `${PR_URL_VAL##*/}` would still be unsafe for warning blobs, trailing slash, non-GitHub URLs, or malformed `pr-url.txt`. Since helper `--pr` is `type=int` at `scripts/_goal_autoship_render.py:390-394`, any non-empty non-integer causes argparse exit 2 and can drop the outcome row.

### CX-4 — "No helper changes" conflicts with desired failure semantics [architectural / major]

`docs/specs/autoship-outcome-instrumentation/spec.md:41,124-127` says no helper changes are needed, but the desired failure semantics conflict with helper design. Missing spec and invalid args exit non-zero (`load_spec`, argparse), while JSONL append failure is intentionally swallowed. The spec needs to either accept silent best-effort data loss or bring `_goal_autoship_render.py` into scope.

### CX-5 — `gate=build` is wrong for most terminal paths; poisons per-gate analysis [contract / major]

`docs/specs/autoship-outcome-instrumentation/spec.md:82-84,134-138` hard-codes `gate=build`, which is false for most terminal paths. Early failures can end at spec-review/design/check/branch-setup; successful merged outcomes pass through `merging`; `run.sh` even has a `merge` gate enum supported by the helper (`scripts/_goal_autoship_render.py:37-45`). This will poison per-gate analysis and make failures look like build failures.

### CX-6 — `pr-awaiting-review → cancelled` mismaps pr_only/fell_back/merge_failed substates [contract / major]

`docs/specs/autoship-outcome-instrumentation/spec.md:65-70,136` maps `pr-awaiting-review` to `cancelled`. In `run.sh`, `pr-awaiting-review` includes `pr_only`, `fell_back`, and `merge_failed` paths (`scripts/autorun/run.sh:1450-1482`), all of which can still become shipped later. Treating open-review PRs as cancelled will undercount ship rate and make "outcome" mean "state at autorun exit," not final outcome.

### CX-7 — Autoship-active deferral = data pollution for ship-rate learning [scope-cuts / major]

`docs/specs/autoship-outcome-instrumentation/spec.md:43-44,134` explicitly defers autoship-active detection while emitting rows unconditionally. That means dry runs, supervised/manual runs, queue retries, and non-autoship invocations will enter the same dataset as actual autoship decisions. For downstream ship-rate learning, this is data pollution, not a harmless scope cut.

### CX-8 — `schema_version` is int, not string [documentation / nit]

`docs/specs/autoship-outcome-instrumentation/spec.md:86-100` claims the helper row shape was verified, but `schema_version` is an integer, not a string (`scripts/_goal_autoship_render.py:353-359`). Small on its own, but it shows the spec is documenting inferred contract instead of the actual emitted contract.

## Verdict

**FAIL.** Three independent architectural/contract blockers: (CX-1) call-site coverage gap, (CX-3) wrong variable name, and the design ambiguity of (CX-2) silent helper write failure + (CX-4) helper-out-of-scope claim. The spec also makes two mapping decisions (CX-5, CX-6) that will produce systematically wrong data downstream. Recommend revising before /blueprint.
