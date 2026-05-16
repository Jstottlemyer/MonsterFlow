# Review V2 — wiki-write-migrate

OVERALL_VERDICT: GO_WITH_FIXES (V3 produced inline)

**Date:** 2026-05-16
**Reviewers dispatched:** gaps:opus, requirements:sonnet, scope:sonnet + codex-adversary
**Gate mode:** permissive
**Iteration:** 2 of 3 (V2 reviewed after V1 → V2 revision; V3 written inline addressing V2 review)

## Verdict: GO_WITH_FIXES (folded inline to V3)

3 reviewers PASS WITH NOTES on V2. Codex returned a sharp finding: V2's F2 idempotency algorithm was internally self-defeating — the case-insensitive both-sets check skipped the canonical `[[Welcome]] → [[welcome]]` rewrite on pass 1, contradicting V2's own narration. Plus V2's F3 split-brain resolver was under-specified (declared the function but didn't pin the pre-migration vault-state reconstruction mechanism).

V3 (written inline this turn) fixes:

### Architectural

- **F2 algorithm rewritten:** idempotency check is now exact-text equality between current link and computed new form (`link_text == compute_new_form_for_this_link()`), NOT case-insensitive set membership. The canonical Welcome→welcome case now works: pass 1 sees `[[Welcome]]`, computes new=`welcome`, text differs → rewrite; pass 2 sees `[[welcome]]`, computes new=`welcome`, text matches → skip. Byte-stable idempotent.
- **F3 pre-migration vault index made explicit:** scan-before-Phase-A persists `(basename → path)` + `(alias → path)` maps to `<vault>/.migration-vault-index.json`. Collision-skip set persists to `<vault>/.migration-collisions.json`. Phase B reads both for split-brain resolution. Both sidecars archived alongside journal on completion. Resolver function `resolve_link_target_pre_migration(link, vault_index, collisions)` has a deterministic spec.
- **F5 lock span:** Codex argued the lock should span Phase A AND Phase B, not just Phase A. Concurrent rewriter invocations during Phase B could interleave file writes. V3 holds the lock from journal-open through Phase B verification completion.
- **Journal fsync:** Codex correctness finding — `f.flush()` + `os.fsync()` after each row append, BEFORE the `os.rename()` call. Survives kernel-buffer crashes.

### Contract pins

- **CG-1 stderr message contract:** V3 AC #2 lists the 6 sub-cause stderr messages verbatim. Test cases assert both exit code AND stderr substring.
- **CG-2 archive-timestamp scope:** V3 pins `<UTC-ts>` as ONE timestamp per `--migrate` invocation (constant across all collisions in this run).
- **G-V2-3 iCloud placeholder detection:** V3 Edge Cases adds explicit `.<basename>.icloud` zero-byte detection with refuse-the-whole-migration error.
- **First-invocation flock ordering:** V3 specifies `open(path, O_CREAT | O_APPEND)` then `fcntl.flock(fd, LOCK_EX | LOCK_NB)` — creates the file if absent, locks it regardless.

### Scope cuts accepted

- **SC-V2-003:** drop whitespace-padded + nested wikilink test cases from AC #11 (zero-probability in Justin's vault per scope review).

### Scope cuts rejected

- **SC-V2-001 (simpler split-brain):** scope wanted a 15-LoC set-membership replacement for the full pre-migration resolver. Codex was correct that the resolver needs more state than scope wanted to admit (skipped files + archived files + pre-injection aliases all need to be accessible to disambiguate `[[Welcome]]` references). Keep the V3 pre-migration index sidecar approach.
- **SC-V2-002 (defer verification scan):** scope wanted to defer F9 post-run verification to v1.1. Verification scan is the only mechanical catch for rewriter bugs; cost is one O(N) walk; well-spent. Keep.

## Reviewer Verdicts (V2)

| Dimension | Verdict | Headline |
|-----------|---------|----------|
| Gaps (opus) | PASS WITH NOTES | 3 new arch findings (F3 reconstruction, F5 first-invocation flock, F17 iCloud not picked up) + spike-cleanup observation |
| Requirements (sonnet) | PASS WITH NOTES | 3 contract gaps (stderr pin, archive timestamp scope, F3 reconstruction ambiguous) |
| Scope (sonnet) | PASS WITH NOTES | 3 cuts proposed (1 accepted, 2 rejected); single-session-buildable confirmed |
| Codex | F2 algorithm self-defeating + F3 reconstruction under-spec'd + lock-span + fsync | Most surgical of the 4 reviewers — caught the algorithmic bug others missed |

## Spike fixture cleanup

Per Gaps V2 observation: the F1 spike fixtures at `~/Projects/_spike-f1-wiki-write-migrate/` and `~/Documents/Obsidian/wiki/_spike-f1-wiki-write-migrate/` would have polluted `wiki-write.py --lint` during /build (the `_spike-f1` paths contain pages that violate the lint's 4 types). Cleaned via `rm -rf` before /blueprint.

---

```check-verdict
{
  "schema_version": 2,
  "prompt_version": "check-verdict@2.0",
  "verdict": "GO_WITH_FIXES",
  "blocking_findings": [],
  "security_findings": [],
  "generated_at": "2026-05-16T00:00:00Z",
  "iteration": 2,
  "iteration_max": 3,
  "mode": "permissive",
  "mode_source": "frontmatter",
  "class_breakdown": {
    "architectural": 0,
    "security": 0,
    "contract": 3,
    "documentation": 0,
    "tests": 1,
    "scope-cuts": 1,
    "unclassified": 0
  },
  "class_inferred_count": 0,
  "followups_file": "",
  "cap_reached": false,
  "stage": "spec-review"
}
```

[AUTORUN + /goal] V3 inline. All architectural findings closed. Proceeding to /blueprint.
