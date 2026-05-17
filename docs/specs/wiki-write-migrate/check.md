# Check — wiki-write-migrate (design v2)

OVERALL_VERDICT: GO_WITH_FIXES

**Date:** 2026-05-16
**Reviewers:** risk:opus, scope-discipline:sonnet, completeness:sonnet + codex-adversary (Phase 2b)
**Gate mode:** permissive (frontmatter)
**Iteration:** 1 of 3 at /check (design has gone through /blueprint twice)

## Verdict: GO_WITH_FIXES

3 Claude reviewers PASS WITH NOTES. Codex (Phase 2b) found 4 NEW P1 + 2 P2 — issues design v2 didn't actually close from /blueprint's Codex pass. Most notable:

- **Sidecar race NOT closed (Codex)** — V2's D4.5 reorders sidecars after lock, but D5 still says "before lock" (V2 edit missed this — internal contradiction)
- **linkable_name inconsistency (Codex)** — D3 says slug for projects; D5 frontmatter example stores `linkable_name: Welcome` (capital W key mismatch). Plus old-basenames like `[[PatternCall — iOS Native Rewrite]]` need pre-migration resolution before alias injection runs.
- **importlib.util duplicate-module exception identity (Codex P1, Risk Review)** — when wiki-write.py runs as `__main__` AND `_wiki_migrate.py` loads it as `wiki_write`, the exception classes are NOT the same `id()`. `except MigrationCollisionError` in `__main__` won't catch raises from `_wiki_migrate`.
- **ArchiveThenRenameOp not journaled (Codex P1)** — journal records rename ops only. A crash between `archive_existing_target` and `os.rename(source, target)` cannot be reconstructed from journal+sidecars.
- **Phase B post-Phase-A Ctrl-C gap (Risk Review)** — empty journal + valid sidecars after kill-INT is ambiguous in T8 resume.
- **Per Risk Review:** 18 tasks (correction — not 17) + ~1000 LoC + 381 spec lines = 30-40% over single-build-session budget; needs documented escape-valve.

## Reviewer Verdicts

| Dimension | Verdict | Headline |
|-----------|---------|----------|
| Risk (opus) | PASS WITH NOTES | 7/10 Codex P1s closed; 3 with residual gaps. Sidecar race contradiction in V2 missed. |
| Scope-Discipline | PASS WITH NOTES | T2b/T2c/T12b alias-plumbing flagged as new scope (could defer to v0.17.1); T5 monolith ~450-550 LoC needs T5a/T5b split for parallel waves. Markdown range scanner is correctness-required, not cuttable. |
| Completeness | PASS WITH NOTES | All 11 ACs covered; 3 nits (stderr substring assertions, lint-tail test, sub-case (y) exit-code split). None blocking. |
| Codex /check | 4 P1 + 2 P2 | Half the V1 P1s NOT actually closed by V2 |

## Findings classified

**Architectural (routes to /build wave 1 as inline fixes per permissive mode):**

- ck-sidecar-race-residual: V2 D5 prose still says "before lock"; fix to match D4.5
- ck-linkable-name-frontmatter: D5's frontmatter example mismatches D3 (capital W in key); fix example + pin linkable_name lowercase-key invariant
- ck-import-exception-identity: redesign — either (a) move shared exceptions/slugify into `scripts/_wiki_common.py` (third module) OR (b) `_wiki_migrate.py` owns its own exception classes (Codex's preferred alternative). Pick (a) — cleaner.
- ck-archive-then-rename-journal: extend journal schema with `phase: "archive"` row before `phase: "rename"` for ArchiveThenRenameOp; add resume handling for mid-archive crash
- ck-resume-ctrl-c-gap: T8 schema-validation must accept empty journal + valid sidecars as no-op exit 0 (not corrupt)
- ck-linkable-name-prefix-resolution: pre-migration index must include old-basenames as synthetic aliases so `[[PatternCall — iOS Native Rewrite]]` resolves before injection runs
- ck-archive-path-collision: same-second invocations collide; add uniqueness suffix `<ts>-<pid>` OR fail if archive target exists

**Contract (routes to followups for /build):**

- ck-markdown-scanner-spec: pin exact rules — backtick vs tilde, fence length matching, EOF-unclosed, CRLF, frontmatter-only-at-byte-0, inline code, callout fences
- ck-postinit-validation: __post_init__ duplicate-path check ambiguous with nested ArchiveThenRenameOp; spec the validation correctly
- ck-stderr-substring-tests: explicitly task the 6 stderr substring assertions in T11
- ck-lint-tail-test: T3 needs accompanying test case in test-wiki-write.sh

**Scope (recommendations, not blocking):**

- ck-t5-split: split T5 into T5a (constants + dataclasses) + T5b (logic) for parallel waves
- ck-build-escape-valve: document in design.md a slice-carve point if T5b stalls
- ck-alias-plumbing-defer: T2b + T2c + T12b could carve to v0.17.1 (low risk, simplifies v0.17.0)

## Codex Adversarial View — V1 closure audit

Codex's verdict on whether V2 actually closed V1's findings:

- **Closed:** --alias plumbing scope (T2b/T2c/T12b), convention constants (T2c), vault discovery mode (T8b), explicit linkable_name tests (T10)
- **NOT closed:** sidecar race (D5 contradiction), linkable_name (inconsistency), force-overwrite planning (no journal entry), resume sidecars (Ctrl-C gap), import safety (duplicate-module), code-fence scanner (under-specified)

## Per permissive gate mode

Architectural findings (7 of them) flow to followups.jsonl with `target_phase: build-inline`. /build wave 1 picks them up. If wave 1 stalls (>3 attempts), carve per slice-strategy memory.

---

```check-verdict
{
  "schema_version": 2,
  "prompt_version": "check-verdict@2.0",
  "verdict": "GO_WITH_FIXES",
  "blocking_findings": [],
  "security_findings": [],
  "generated_at": "2026-05-16T00:00:00Z",
  "iteration": 1,
  "iteration_max": 3,
  "mode": "permissive",
  "mode_source": "frontmatter",
  "class_breakdown": {
    "architectural": 7,
    "security": 0,
    "contract": 4,
    "documentation": 0,
    "tests": 2,
    "scope-cuts": 3,
    "unclassified": 0
  },
  "class_inferred_count": 0,
  "followups_file": "docs/specs/wiki-write-migrate/followups.jsonl",
  "cap_reached": false,
  "stage": "check"
}
```

[AUTORUN + /goal] GO_WITH_FIXES with substantial followups. Proceeding to /build wave 1 — wave will be heavy with inline fixes.
