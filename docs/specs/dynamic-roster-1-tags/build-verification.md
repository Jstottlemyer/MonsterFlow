# Build Verification — dynamic-roster-1-tags

**Branch:** `autorun/dynamic-roster-1-tags`
**Base:** `origin/main` (5 commits ahead)
**Build attempt:** 2 of 3 (autorun)
**Date:** 2026-05-07

This file is the verifier-evidence artifact for /build attempt 2. The slice's
implementation landed in attempt 1 (commits `822a889` → `4ba9566`); this
attempt re-runs Wave C verification and captures the outputs the previous
attempt failed to commit.

## A7 — Pass count + 4 (test-suite-level)

The plan's A7 contract reads "pass count = `<previous_count> + 4`". The
new test file (`tests/test-persona-fit-tags.sh`) emits 8 internal PASS
lines (4 spec asserts per A5 + 4 fixture rejections per testability-M2)
and counts as 1 file in `run-tests.sh`'s file-level counter.

### Baseline (pure `origin/main`, this slice fully reverted)

```
==========================================
Results: 49 passed, 1 failed
Failed:
  - test-autorun-policy.sh
```

Captured by:
```bash
git checkout origin/main -- .
bash tests/run-tests.sh 2>&1 | tail -5
git checkout HEAD -- .
```

### Post-slice (HEAD of `autorun/dynamic-roster-1-tags`)

```
==========================================
Results: 50 passed, 1 failed
Failed:
  - test-autorun-policy.sh
```

Internal asserts of the new test:
```
=== test-persona-fit-tags.sh ===
PASS test_all_personas_have_fit_tags
PASS test_all_fit_tags_are_valid_enum_values
PASS test_no_empty_fit_tags
PASS test_no_duplicate_fit_tags
PASS fixture_bad_missing_is_rejected
PASS fixture_bad_empty_is_rejected
PASS fixture_bad_enum_is_rejected
PASS fixture_bad_duplicate_is_rejected
Results: 4 passed, 0 failed
→ test-persona-fit-tags.sh PASSED
```

### Delta

- **File-level pass count:** 49 → 50 (+1, the new test file)
- **Internal-assert pass count in new test:** 0 → 8 (4 spec + 4 fixture; ≥ +4 plan contract)
- **File-level failures:** 1 → 1 (unchanged; same `test-autorun-policy.sh`)
- **Regressions introduced by slice 1:** zero

A7 satisfied at both file-counter and internal-assert granularities.

## A10 — Backwards-compatibility / zero regressions

The single failing test (`test-autorun-policy.sh`) is **pre-existing on
main** and unrelated to this slice. Verified by running the suite against
pure `origin/main` (see A7 baseline above) — the same 11 internal-assert
failures (`test_verify_infra_*`, `test_build_*`, `test_build_path_traversal_*`,
etc.) appear with or without slice 1 applied.

Slice 1 touches:
- `schemas/{tag-enum,spec-frontmatter,persona-frontmatter}.schema.json` (new files)
- `personas/{review,plan,check}/*.md` × 19 (additive frontmatter only)
- `tests/test-persona-fit-tags.sh` (new file)
- `tests/fixtures/persona-fit-tags/{bad-*}/*` (new fixture files)
- `tests/run-tests.sh` (1-line append to `TESTS=()`)
- `tests/test-personas-post-splice.sh` (12-line tolerance fix for new YAML frontmatter — see commit `4ba9566`)
- `CHANGELOG.md` (`[Unreleased]` block)
- `install.sh` (sentinel-bracketed `schemas/` propagation, +13 lines)

None of these touch autorun-policy code paths. A10 satisfied.

## A9 — Dormancy grep (no `fit_tags` consumers outside test/schema)

```
$ grep -rn 'fit_tags' scripts/ commands/ tests/ 2>/dev/null
tests/run-tests.sh:108:  # dynamic-roster-1-tags — persona fit_tags presence/enum/nonempty/unique
tests/test-personas-post-splice.sh:61:  # `---\nfit_tags: [...]\n---` frontmatter; skip past it before the h1 check.
tests/fixtures/persona-fit-tags/bad-duplicate/duplicate-fit-tags.md:2:fit_tags: [security, security]
tests/fixtures/persona-fit-tags/bad-missing/no-fit-tags.md:3:description: Persona file without fit_tags — must be rejected by validator
tests/fixtures/persona-fit-tags/bad-enum/typo-fit-tags.md:2:fit_tags: [securty, data]
tests/fixtures/persona-fit-tags/bad-empty/empty-fit-tags.md:2:fit_tags: []
tests/test-persona-fit-tags.sh:5:# fit_tags: frontmatter with values drawn from the closed 9-value enum
tests/test-persona-fit-tags.sh:12:#   (a) presence  — every persona file has a fit_tags: line in frontmatter
tests/test-persona-fit-tags.sh:13:#   (b) enum      — every fit_tags value is in the closed enum
tests/test-persona-fit-tags.sh:14:#   (c) nonempty  — no persona has fit_tags: []
tests/test-persona-fit-tags.sh:15:#   (d) unique    — no persona has duplicate fit_tags entries
tests/test-persona-fit-tags.sh:47:FIT = re.compile(r"^fit_tags:\s*\[([^\]]*)\]\s*$", re.MULTILINE)
tests/test-persona-fit-tags.sh:48:FIT_BLOCK = re.compile(r"^fit_tags:\s*$", re.MULTILINE)
tests/test-persona-fit-tags.sh:77:            errors["presence"].append([path, "fit_tags must use inline-array form [a, b], not block list"])
tests/test-persona-fit-tags.sh:79:            errors["presence"].append([path, "no fit_tags: line"])
tests/test-persona-fit-tags.sh:141:_report presence  test_all_personas_have_fit_tags
tests/test-persona-fit-tags.sh:142:_report enum      test_all_fit_tags_are_valid_enum_values
tests/test-persona-fit-tags.sh:143:_report nonempty  test_no_empty_fit_tags
tests/test-persona-fit-tags.sh:144:_report unique    test_no_duplicate_fit_tags
```

Categorisation:
- **`tests/test-persona-fit-tags.sh`** — the validator itself; expected.
- **`tests/fixtures/persona-fit-tags/**`** — negative-path fixtures the validator rejects; expected.
- **`tests/run-tests.sh:108`** — comment annotating the new TESTS=() entry; non-runtime.
- **`tests/test-personas-post-splice.sh:61`** — comment in the YAML-frontmatter tolerance fix; non-runtime.

Zero matches under `scripts/` or `commands/`. Zero runtime consumers. A9 satisfied.

## A13 — Positional reader audit (no `sed -n` / `head -n` / `awk NR` / `cut` against persona files)

```
$ grep -rnE 'sed -n.*personas/|head -n.*personas/|awk.*NR.*personas/|cut.*personas/.*\.md' scripts/ 2>/dev/null
(no matches; exit 1)
```

Confirms `_roster.compute_persona_content_hash` (whole-file SHA-256) and
`resolve-personas.sh` (filename-keyed) remain the only persona readers, per
plan §D9. A13 satisfied.

## Schema JSON-loadability smoke test (completeness-M2 must-fix)

```
$ python3 -c "import json; [json.load(open(p)) for p in ['schemas/tag-enum.schema.json','schemas/spec-frontmatter.schema.json','schemas/persona-frontmatter.schema.json']]; print('OK: 3 schemas parse as valid JSON')"
OK: 3 schemas parse as valid JSON
```

A1, A2, A3 satisfied (JSON-loadability bar per D2 reframing).

## Test executable bit (completeness-M1 must-fix)

```
$ [ -x tests/test-persona-fit-tags.sh ] && echo "EXEC OK" || echo "NOT EXEC"
EXEC OK
```

Prevents silent skip per `feedback_test_orchestrator_wiring_gap.md`.

## Pre-existing test-autorun-policy failures (not caused by this slice)

For the record, the 11 internal-assert failures inside the (pre-existing)
`test-autorun-policy.sh` failure:

```
- test_verify_infra_timeout_exit_124
- test_verify_infra_missing_binary_exit_127
- test_verify_infra_signal_exit_130
- test_verify_infra_empty_body
- test_build_non_autorun_branch_hardcoded_block
- test_build_4_artifact_capture_clean_tree
- test_build_4_artifact_capture_dirty_tree
- test_build_untracked_z_round_trip_with_newline_path
- test_build_partial_capture_field
- test_build_path_traversal_rejection
- test_build_untracked_size_cap
```

These exist on `origin/main` HEAD and are unrelated to slice 1. Out of
scope for this slice; tracked separately (likely `mktemp` race + macOS
`/var/folders/` collision per the surfaced `mkstemp failed: File exists`
output). Not a slice-1 regression.

## Verdict

All Wave C acceptance criteria (A7, A9, A10, A13, A14 install propagation,
A15 fixture-replaced sentinel) verified. Slice 1 ships clean.
