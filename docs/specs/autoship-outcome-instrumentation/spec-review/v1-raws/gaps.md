# Missing Requirements Review — autoship-outcome-instrumentation

## Critical Gaps (block /blueprint)

**None.**

## Important Considerations (non-blocking)

### Finding 1
- **class:** contract
- **severity:** major
- **title:** `exit 3` (STOP-file) bypasses the terminal block — no outcome row emitted

**Body:** `check_stop()` calls `exit 3` directly (run.sh:826) — before the FINAL_STATE terminal block where the spec places the new invocation. The `on_exit` trap fires, but the new emission code will not have run yet. STOP-file halts will produce zero outcome rows, not a `reason=failed` row as the rationale claims. The spec text says "STOP-file halts fold into `failed`" but the wiring position makes this impossible for STOP-file paths that exit early.

**Suggested fix:** Either (a) add the emission call inside `check_stop()` immediately before `exit 3`, guarded the same best-effort way; or (b) move emission into `on_exit` after `FINAL_STATE` is guaranteed set. Option (b) requires confirming `FINAL_STATE` is always non-empty by trap time. Either way, AC1 currently cannot be satisfied by STOP-file runs.

### Finding 2
- **class:** contract
- **severity:** major
- **title:** `--spec-path` argument is not specified in the wiring spec

**Body:** The helper requires `--spec-path` (mandatory, no default). The spec shows the call as `python3 scripts/_goal_autoship_render.py log-event --event-type outcome --reason ... --gate build` but never specifies what value to pass for `--spec-path`. `run.sh` has two spec-path variables: `$SPEC_FILE` (queue copy) and `$CANONICAL_SPEC` (repo canonical). The helper's `load_spec()` reads frontmatter for the `slug` and tags — either path works if the file exists, but `$SPEC_FILE` may not exist if the queue was cleaned. The implementer will have to guess.

**Suggested fix:** Add to the Data & State section: "`--spec-path $CANONICAL_SPEC` — uses the repo-canonical path (`docs/specs/$SLUG/spec.md`) because `$SPEC_FILE` (queue copy) may be absent on retry/resume runs. Fail-path is covered by the existing WARN guard."

### Finding 3
- **class:** contract
- **severity:** major
- **title:** `--pr` type is `int` in the helper, but `${pr_url##*/}` produces a string — malformed URLs pass a non-numeric arg

**Body:** `argparse` declares `--pr type=int` (helper:419). If `pr_url` is set to something unexpected (e.g., `https://github.com/owner/repo/pull/` with a trailing slash, or a branch name), `${pr_url##*/}` returns an empty string or non-numeric token. Passing that as `--pr ""` is blocked by AC9's empty-check, but a non-numeric non-empty string (e.g., `pull`) would slip through the empty guard and cause `argparse` to exit 2 with a type-error message, landing in the WARN path. The spec's empty-guard (AC9) only checks for empty, not non-numeric.

**Suggested fix:** Extend the guard: after `PR_NUMBER="${pr_url##*/}"`, add `[[ "$PR_NUMBER" =~ ^[0-9]+$ ]] || PR_NUMBER=""` so non-numeric strings are treated as absent. Add a test fixture for `pr_url=https://github.com/owner/repo/pull/` (trailing slash).

## Observations (notes)

### Observation A
- **class:** tests
- **severity:** nit
- **title:** AC8 verification is vague — "grep test or comment marker"

**Body:** AC8 says the PIPESTATUS-safe pattern must be verified by "a grep test in the test file or a comment marker." A comment marker provides zero runtime assurance. If `/build` picks the `|| true` anti-pattern, the comment marker will still pass. For a 4-fixture test file this is trivial to make concrete.

**Suggested fix:** Change AC8 to: `grep -q 'rc=\$?' scripts/autorun/run.sh` (or equivalent positive pattern check). One line.

### Observation B
- **class:** documentation
- **severity:** nit
- **title:** Insertion line number (1504) will drift immediately

**Body:** Any future run.sh edit will shift the line number. The actual anchor (after the FINAL_STATE fallback block, before the `echo "[autorun] $SLUG: complete"`) is unambiguous without the line number.

**Suggested fix:** Replace the line number reference with the prose anchor: "after the `if [ -z "$FINAL_STATE" ]` fallback block, before the `echo "[autorun] $SLUG: complete"` line."

### Observation C
- **class:** scope-cuts
- **severity:** nit
- **title:** `autoship_active` omission means outcome rows are uninterpretable for non-autoship autoruns

**Body:** Confirmation that deferral is correct — until `autoship_active` is present, `autorun-suitability-v2`'s ship-rate calc will need to filter via /goal presence or treat all outcome rows equally. No new gap.

## Verdict: PASS WITH NOTES

Three contract gaps (Finding 1 — STOP-file exit bypass; Finding 2 — missing `--spec-path` value; Finding 3 — non-numeric PR string) are major but mechanical. Recommend resolving Finding 1 and 2 in `/blueprint` before implementation; Finding 3 can be addressed inline by the implementer.
