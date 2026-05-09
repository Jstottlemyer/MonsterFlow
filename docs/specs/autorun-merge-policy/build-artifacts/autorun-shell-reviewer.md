# autorun-shell-reviewer — final review (AC#28)

**Feature:** autorun-merge-policy
**Branch:** `autorun/autorun-merge-policy`
**Diff base:** `origin/main`
**Files in scope:**

- `scripts/autorun/_merge_policy.sh` (NEW)
- `scripts/autorun/run.sh` (MODIFIED)
- `scripts/autorun/autorun-batch.sh` (MODIFIED)

**Verdict: HIGH == 0 (clean to merge).**

This satisfies AC#28: "`autorun-shell-reviewer` subagent passes a clean review against the modified `scripts/autorun/*.sh` and new `scripts/autorun/_merge_policy.sh` per its 13-pitfall checklist."

## Review history

### Pass 1 — found 1 High

- **`scripts/autorun/run.sh` PR_NUMBER extraction (Pitfall #2 / #13)** — the previous extractor applied `sed -E 's|.*/pull/([0-9]+).*|\1|'` to the full `PR_URL_VAL` blob. Because `gh pr create 2>&1` folds stderr into the value, multi-line warnings citing other PR numbers (e.g. "an existing PR #41 was found …") could be captured before the canonical URL line, leaking the wrong PR number into the audit row.

### Fix applied

Wrapped extraction with `grep -Eo 'https://[^ ]+/pull/[0-9]+' | tail -1` to isolate a single canonical URL line before `sed` derives the digits, plus a final `grep -E '^[0-9]+$'` numeric guard. See `scripts/autorun/run.sh` around lines 1266–1276.

### Pass 2 — re-review after fix

- **High: 0** (previously-flagged item correctly fixed)
- **Medium: 2** (advisory only)
  - `_merge_policy.sh:660-665` — `auto_merged` with `merge_sha=null` when `gh pr merge --auto` succeeds but state is not yet `MERGED`. Documented in the schema contract (header lines 91–93). Not blocking.
  - `run.sh:1292-1296` — `LAST_ACTION` parser uses a grep chain against `run.log`. Slug regex (`^[a-z0-9][a-z0-9-]{0,63}$`) prohibits regex metacharacters, so today this is safe; flagged for documentation parity.
- **Low: 2** (parity / duplicate-warning notes; no defect)

## Spot checks (clean)

- No `git add -A` / `git add .` introduced.
- No `osascript` / AppleScript paths in this diff.
- Bash 3.2 portable: no `${arr[-1]}`, no `export -f`, no `&>`.
- Both `--auto-merge=` and `--merge-policy=` flag literals parsed; deprecation notice fires.
- Slug regex / eval scope / SSH-vs-HTTPS / STOP race / branch invariant / empty-PR loophole / truncated diff: not regressed.

## Bottom line

`HIGH == 0`. AC#28 satisfied.

## Provenance

- Pass 1 agent id: `a4bc9d6e12a379fa8`
- Pass 2 agent id: `a105d4187812f4759`
- Date: 2026-05-08
