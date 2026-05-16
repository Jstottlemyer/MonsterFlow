# Check — wiki-write-conventions

OVERALL_VERDICT: GO_WITH_FIXES

**Date:** 2026-05-15
**Reviewers dispatched:** risk:opus, completeness:sonnet, scope-discipline:sonnet + codex-adversary
**Budget:** 3 + 1 codex (agent_budget=3)
**Gate mode:** permissive (frontmatter)
**Iteration:** 1 of 3

## Overall Verdict: GO_WITH_FIXES

3 Claude reviewers returned PASS WITH NOTES (no FAILs). Codex returned 10 findings, 4 of which were architectural (install sequencing, /wrap gating model, lint type-count contract, Python version handling). Per gate_mode: permissive + AUTORUN, architectural findings were folded into spec.md and design.md inline rather than re-running /blueprint. Contract findings routed to the build wave as inline fixes. Scope-discipline cuts accepted (drop _prune_old_backups, drop spaces-in-filename lint type, make --entity-type optional, drop --topic-title flag entirely).

## Reviewer Verdicts

| Dimension | Verdict | Key Finding (resolved) |
|-----------|---------|------------------------|
| Risk (opus) | PASS WITH NOTES | YAML emission gap for omitted fields + AC #7 vs D14 contradiction + T7 needs verifier grep-assertion (all folded into design.md V2) |
| Completeness (sonnet) | PASS WITH NOTES | D13 flags not in AC #2; D6 lint type count drift (both pinned in spec.md V2) |
| Scope-Discipline (sonnet) | PASS WITH NOTES | 7 scope cuts proposed — 3 accepted (backup retention drop, spaces-lint drop, entity-type default + topic-title drop); 4 deferred to follow-up |
| Codex Adversarial | 10 findings (4 P1, 4 P2, 2 P3) | install sequencing fix (Codex P1#1 — confirmed at install.sh:1421 vs :1440), Python 3.9 compat (P1#4), /wrap gating decision (P1#2), VaultNotConfigured dual exit code (P2#6) — all folded into design.md V2 |

## Must Fix Before Building — RESOLVED INLINE

All four architectural findings from Codex P1 have been resolved by editing spec.md + design.md before this verdict was written:

1. **[architectural] Install sequencing wrong** (Codex P1 #1) — RESOLVED in spec AC #7: `install_wiki_conventions` writes vault `_convention.md` files inside `do_knowledge_layer`, but the ~/CLAUDE.md sentinel-block injection moves AFTER the `claude-md-merge.py` baseline merge at install.sh:1440. Two-stage split documented in AC #7.
2. **[architectural] /wrap Phase 2c gating model** (Codex P1 #2) — RESOLVED in design.md D15 (added): lint runs in `/wrap` and `/wrap-insights` when vault is configured; SKIPPED in `/wrap-quick`. Runs regardless of whether Phase 2c wrote vault content this session.
3. **[contract] D6 lint type count mismatch** (Risk R3 + Completeness C2 + Codex P1 #3) — RESOLVED in spec AC #6 + design D6: locked at exactly 4 violation types (em-dash, mixed-case, projects-flat-file 3a, projects-folder-no-index 3b). "Spaces in filename" dropped per scope-discipline SD-6 (false-positive risk on Obsidian filenames).
4. **[architectural] Python 3.10+ shebang failure path** (Codex P1 #4) — RESOLVED in design.md D16 (added): `scripts/wiki-write.py` is Python 3.9-compatible. No `|` union types, no `match` statements, no parenthesized context managers. Drops the version-check requirement from `_install_vault_conventions` entirely.

## Should Fix — Routed to /build inline fixes (followups.jsonl)

Non-architectural findings that route to the build wave as inline TODOs:

- [contract] YAML emission gap: pin omitted-optional behavior (omit key entirely, never `null`); empty tags emit `tags: []` (Risk R1 — fold into T3)
- [contract] AC #7 vs D14 frontmatter contradiction (Risk R2) — RESOLVED in spec AC #7 above; remove `exclude: true` reference from convention seeding
- [tests] T7 verifier assertion needed (Risk R3): add `grep -q test-wiki-write.sh tests/run-tests.sh` test case in T11
- [contract] `VaultNotConfiguredError` dual exit code (Codex P2 #6): split into `VaultNotConfiguredError` (exit 1, default-write) and `VaultNotConfiguredSkip` (exit 0, --lint). Two classes inheriting from `WikiWriteError`. Update T3.
- [contract] Backup dedupe scope (Codex P2 #8): the run-scoped `WIKI_CONV_CLAUDE_MD_BACKED_UP` guard must cover ALL three ~/CLAUDE.md writers (`append_wiki_preflight_instruction`, `claude-md-merge.py`, the new sentinel-block injector). Move backup creation to the top of Zone B before any writer runs.
- [scope-cuts] Drop `_prune_old_backups` + `MONSTERFLOW_BACKUP_RETAIN_DAYS` (SD-3): remove from design.md D10 entirely. Defer until backups accumulate in practice.
- [scope-cuts] `--entity-type` default `other` + drop `--topic-title` (SD-4 + Completeness C1): update D13 in design.md.
- [tests] Add Python version test case dropped (no longer needed — see arch fix #4 above)
- [documentation] T1 should mention D14's Obsidian "Excluded files" manual step in templates/wiki-conventions.md (Completeness C4)
- [scope-cuts] T11 test scope (Codex P2 #7): KEEP T11 in test-wiki-write.sh for v1 — re-splitting now risks orchestrator wiring drift. Re-evaluate after v1 ships.

## Observations (non-blocking)

- Codex P2 #5 (CLI complexity higher than estimated): T3 may exceed 200 LoC. Acceptable — AUTORUN time available.
- Codex P3 #9 (`_replace_sentinel_block.py` vs claude-md-merge.py redundancy): two different ops (whole-file merge vs single-block replace). Keep both; document distinction.
- Codex P3 #10 (estimate optimism): T3 likely 250-300 LoC, T9 stays M. Acceptable for v1.
- All 7 scope-discipline cuts evaluated; 3 accepted, 4 deferred (T2 keep, T6 keep per D7, T7 keep per orchestrator-wiring memory, D14 frontmatter hint keep).

## Codex Adversarial View

Codex's 10-finding pass was load-bearing. P1 #1 (install sequencing) was a structural blocker that all 3 Claude reviewers missed — Codex verified the line numbers against the actual install.sh file and correctly identified that `do_knowledge_layer` runs BEFORE `claude-md-merge.py`. Without that catch, the install would have written the wiki-conventions block, then `claude-md-merge.py` would have potentially overwritten or normalized the sentinels in a downstream test failure. Fix folded into AC #7.

Codex's "better approach" recommendation (narrow v1 to helper + --lint only, defer install.sh integration) was considered but rejected: that would revert /spec Q2's decision (c) install.sh-derived authority. The simpler fix is to handle the sequencing correctly, which the V2 AC #7 now does.

---

```check-verdict
{
  "schema_version": 2,
  "prompt_version": "check-verdict@2.0",
  "verdict": "GO_WITH_FIXES",
  "blocking_findings": [],
  "security_findings": [],
  "generated_at": "2026-05-15T00:00:00Z",
  "iteration": 1,
  "iteration_max": 3,
  "mode": "permissive",
  "mode_source": "frontmatter",
  "class_breakdown": {
    "architectural": 0,
    "security": 0,
    "contract": 5,
    "documentation": 1,
    "tests": 2,
    "scope-cuts": 4,
    "unclassified": 0
  },
  "class_inferred_count": 0,
  "followups_file": "docs/specs/wiki-write-conventions/followups.jsonl",
  "cap_reached": false,
  "stage": "check"
}
```

[AUTORUN] GO_WITH_FIXES. Architectural fixes applied inline; remaining findings flow to /build as inline TODOs via followups.jsonl. Proceeding to /build.
