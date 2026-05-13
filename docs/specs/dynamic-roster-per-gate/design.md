---
name: dynamic-roster-per-gate
stage: plan
created: 2026-05-06
revised: 2026-05-12
gate_mode: permissive
revision: 5
revision_reason: "Revision 5 is a post-build docs cleanup (no implementation change): (a) D8 SEC-04 prose direction inverted to match implementation + attack model — ck-implicit, see commit body for the inversion that was caught at Slice 3 build time; (b) D2 NFKC + Cyrillic-Latin confusables map clarified — earlier prose overstated NFKC's coverage; (c) Task 8 'Drop A20' wording corrected — A20 is the unrelated pipeline-cycle-dogfood AC, not the tag-inference placeholder (ck-b8a20a20a2); (d) Open Q#1 wrapper pre-design collapsed since PRE-W2 verdict was YES (ck-1234567890); (e) D14 --tier-pin semantics simplified to last-wins for v1 (ck-2233445566); (f) Open Q#5 added noting PRE-W2 evidence-file persistence is heavier than needed (ck-2345678901). Revision 4 applied 3 plan-revision followups at /build pre-flight; Revision 3 applied 6 must-fix from /check Rev 2."
---

# Plan — dynamic-roster-per-gate (Revision 5)

**Revised:** 2026-05-12 (Rev 2 → Rev 3 → Rev 4, same day)
**Spec:** `docs/specs/dynamic-roster-per-gate/spec.md`
**Prior check verdict (Rev 2):** GO_WITH_FIXES (permissive) — 3 architectural + 3 sev:security must-fix, all inline-tractable
**This revision addresses:** Rev 3 closed 6 must-fix; Rev 4 closes 3 plan-revision followups consumed at /build pre-flight. 14 should-fix items remain in `followups.jsonl` (build-inline + docs-only + post-build).

## Revision Log (Rev 3 → Rev 4, 2026-05-12)

- **`ck-0011223344` [contract] D8 mid-pipeline edit clause** — added explicit "`recomputed ⊊ recorded` → warn-and-proceed (Edge Case 4 pattern); only `recorded ⊊ recomputed` halts" clause to D8. Prevents forcing security-evasive behavior when authors legitimately remove content.
- **`ck-0123456789` [scope-cuts] Task 22 cut** — `tests/test-explain-mutation-zero.sh` removed from W6. `--explain` flag is carved to sibling spec `pipeline-resolver-debugging`; mutation-zero test moves there. Task 24 orchestrator wiring updated.
- **`ck-1122334455` [scope-cuts] Task 23 legacy-fixture trim** — sub-bullet asserting "legacy `selection.json` missing tier field loads" removed. No in-the-wild pre-tier files exist; defensive read in task 16 stays.

## Revision Log (Rev 2 → Rev 3, 2026-05-12)

- **Sequencing MF#1** — line 78 split: tasks 1+2+3 gate W2; task 0 gates W4 only. W2 helpers (tasks 4/5/6) deps changed from `0,1,2,3` to `1,2,3`.
- **Sequencing MF#2** — tasks 9, 11, 13 deps changed from `7` to `0, 7` so PRE-W2 outcome locks before any W4 dispatch code is written.
- **Risk MF#3** — task 0 expanded to 3-cell verdict matrix (Opus parent ‖ Sonnet parent ‖ `claude -p` headless); mixed outcomes classify FLAKY → halt + escalate.
- **Security MF#4 [sev:security]** — NEW task 21a `tests/test-baseline-drift.sh` covers SEC-04 drift-halt path; wired into task 24 orchestrator.
- **Security MF#5 [sev:security]** — Open Q#1 (a) wrapper-pivot fail-fast contract pinned: absent `model` field → exit 5 halt; exact-string OR documented alias-table match (no substring); `--output-format json` pinned; every outcome appends to evidence file.
- **Security MF#6 [sev:security]** — task 3 `test-schema-lockstep.sh` extended with `fit_tags` enum rejection coverage (unknown values, shell-meta values, lockstep enforcement).

---

## Synthesis Posture

The prior plan bundled 4 ship-units (tag-matching, tier policy, constitution rename, escape hatches) and lacked concrete tasks for the 4 security blockers. This revision:
1. Scopes to the core feature only (tag-matching + tier-mixing + dispatch wiring + tests)
2. Adds a PRE-W2 blocking gate (empirical model-param dispatch test) before any dispatch code ships
3. Fixes M2 (autorun task dep graph) and M1 (lineage default in `_persona_score.py`)
4. Carries SEC-02 through SEC-04 inline as concrete `_tag_baseline.py` and resolver tasks

Constitution rename stays in `docs/specs/constitution.md` for all W1-W5 code. The sibling spec `monsterflow-pipeline-config-rename` handles the rename.

---

## Design Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | `fit_score = len(spec.tags ∩ persona.fit_tags)`, `combined_score = fit_score × load_bearing_rate` | Resolves G1 ambiguity; `fit_score` used everywhere (schema JSON, resolver stdout, selection.json, code) |
| D2 | `_tag_baseline.py` pre-processing: NFKC normalize → Cyrillic-Latin confusables map (`_CYRILLIC_TO_LATIN`, ~30 entries) → strip YAML frontmatter → strip balanced fences (3+ tick) → lowercase → regex | Frontmatter strip before fences prevents `tags: [security]` self-triggering (G7 fix). NFKC alone is canonical/compatibility decomposition — it does NOT fold homoglyphs (e.g., U+0430 Cyrillic а ≢ U+0061 Latin a under NFKC); the confusables map closes that bypass for SEC-02. Earlier revisions overstated NFKC's coverage; Rev 5 corrects the pre-processing description to match the implementation. |
| D3 | `<persona>:<tier>` colon-delimited stdout; `codex-adversary` bare | grep-friendly; no jq dependency; backward-breaking change patched at all 6 call sites simultaneously |
| D4 | No wrapper files (D7 / Edge Case 20): model tier via Agent tool `model:` param (interactive) and `--model` flag (headless) only. Halt if model param fails — no disk fallback | Trust boundary; persistent injection risk on SIGKILL outweighs any convenience |
| D5 | PRE-W2 empirical gate: empirically verify `model: "opus"` controls dispatch before any dispatch code ships | MF-1 from check.md; D4 architecture depends entirely on this being true |
| D6 | Tier-mix algorithm: `base_opus = max(opus_min, floor(N/2))`; tiebreak → sonnet; highest `combined_score` claims Opus seats | Deterministic; cost-conscious; matches spec panel-size table |
| D7 | SEC-01 enforced at 2 sites: `_tier_assign.py validate_tier_pins` AND CLI `--tier-pin` parse site (G3 fix) | CLI cannot be a downgrade escape hatch |
| D8 | SEC-04 resolver recompute: `_tag_baseline.py` runs at every gate dispatch; asserts `recomputed ⊆ recorded` (every keyword the resolver re-discovers must already appear in the recorded baseline); drift halts when `recomputed ⊋ recorded` (recomputed has a keyword recorded doesn't = post-write shrinking attack). **Mid-pipeline edit clause (Rev 4 / Rev 5 prose fix):** the inverse direction `recorded ⊋ recomputed` (recorded list claims keywords the body no longer contains because the author legitimately removed content) does NOT halt — it emits `[stale-tags] WARNING: tags_provenance.baseline drifted from current spec body; consider updating frontmatter` (Edge Case 4 pattern) and proceeds. Grandfathered specs with no `tags_provenance` block (recorded set empty) are exempt — there's nothing to drift against. | `tags_provenance.baseline` is author-writable; resolver owns ground truth (S4 / Edge Case 23). Recorded-shrunk-relative-to-recomputed (the attack) is what we defend against; recomputed-shrunk-relative-to-recorded (author cleanup) is benign and warned to avoid forcing security-evasive behavior (keeping stale keywords just to pass the check). Earlier revisions of this row stated the assertion as `recorded ⊆ recomputed` and the halt as `recorded ⊊ recomputed` — those are internally inconsistent (a strict subset still satisfies the assertion); the implementation went with attack-model intent and Rev 5 syncs the prose to match the code. |
| D9 | `lineage` default to `"claude"` at read time in `_persona_score.py` when field absent from rankings row | M1 fix; no backfill required for MVP; one-line guard |
| D10 | M2 corrected dep graph: each autorun gate shell depends on its own command file, not a shared final task | spec-review.sh → resolver + commands/spec-review.md; plan.sh → resolver + commands/plan.md; check.sh → resolver + commands/check.md |
| D11 | Constitution rename OUT of W1-W5: all code reads `docs/specs/constitution.md` as-is. **A15 verification deferred:** spec AC A15 (`pipeline-config.md` works, symlink, install.sh banner) is **not verified by this spec's /check**; it is verified at sibling-spec `monsterflow-pipeline-config-rename` /check. This spec leaves all `constitution.md` references unchanged. | Sibling spec `monsterflow-pipeline-config-rename` owns the rename |
| D12 | Test target: ≥33 fixtures, <15s wall-clock (single normative number) | Resolves contradiction between "50-70" and "40-60" from spec; testability MF-1 from check |
| D13 | Three separate Python helpers (not one batched script) | Testability + AST-banlist isolation per helper; resolver calls them in sequence (one shell process, not per-persona subprocess) |
| D14 | `--tier-pin` flag is **last-wins** in v1 (later flag with same persona-key overwrites earlier). Multiple flags for DIFFERENT personas all apply. The accumulate-promote-drop-lowest behavior originally proposed here was over-spec; carved to BACKLOG via post-build followup `ck-2233445566`. | I6/G6 fix; promote/drop-lowest deferred until a user actually hits the limitation |

---

## Implementation Tasks

```
PRE-W2 ── W1 (schemas, parallel with PRE-W2)
              └── W2 (Python helpers + resolver)
                      ├── W3 (/spec Phase 3 tag-inference)
                      ├── W4 (gate dispatch wiring, 3 parallel sub-trees)
                      └── W5 (dashboard)
                              └── W6 (tests + orchestrator wiring)
```

### Wave PRE-W2: Empirical Gate (blocking; run parallel with W1)

| # | Task | Deps | Size | Parallel? |
|---|------|------|------|-----------|
| 0 | **Empirical model-param routing test (3-cell verdict matrix).** Run probe from **3 distinct contexts** and record each independently: (a) Agent call with `model: "claude-opus-4-5"` from Opus parent session, (b) same Agent call from Sonnet parent session, (c) `claude -p --model claude-opus-4-5` headless invocation (the autorun path). For each cell, capture `model` field from response metadata. Write `docs/specs/dynamic-roster-per-gate/plan/dispatch-precedence-evidence.md` (append-only header sentinel `# PRE-W2 dispatch precedence evidence (append-only)`; columns: `date \| context \| invocation \| --model arg \| response model-id \| match Y/N`). **Verdict:** all 3 cells YES → proceed with D4 (Agent calls); cell (a) NO + cells (b)/(c) YES → wrapper-script pivot per Open Q#1; all NO → carve W4 to follow-up; **any mixed outcome (e.g., works from Opus parent, not Sonnet parent)** → classify FLAKY → halt and escalate (do not ship runtime detection logic). Only Task 0 (PRE-W2) gates W4; W1/W2/W3/W5/W6 are unaffected by probe outcome. | — | S | — |

### Wave W1: Data Contract (parallel with PRE-W2; all 3 tasks parallel)

| # | Task | Deps | Size | Parallel? |
|---|------|------|------|-----------|
| 1 | Extend `schemas/spec-frontmatter.schema.json`: add `tags` (closed enum array, 9 values, `minItems: 0`, `uniqueItems: true`, `$ref: "#/$defs/tag-enum"`), add `tier_policy` block. Define `$defs/tag-enum` shared with persona schema. | — | S | Yes (w/ 2,3) |
| 2 | NEW `schemas/selection.schema.json`: per-row `persona` (string), `tier` (enum `["opus","sonnet"]`), `fit_score` (int ≥0), `combined_score` (float ≥0); top-level `tier_policy_applied` (`source` enum `["constitution","spec","cli"]`, `opus_min`, `opus_count_actual`, `sonnet_count_actual`). `codex` key separate from `selected[]`. `dropped[]` sorted by descending `combined_score`. | — | S | Yes (w/ 1,3) |
| 3 | Extend `schemas/persona-frontmatter.schema.json`: confirm `fit_tags` required, `lineage` optional. NEW `tests/test-schema-lockstep.sh`: asserts all 3 schema files change together or not at all (A19). **`fit_tags` enum rejection coverage (sev:security MF#6):** assert (a) persona file with `fit_tags: [unknown-value]` fails schema validation with non-zero exit, (b) persona file with shell-meta `fit_tags: ["; rm -rf /"]` fails enum check before reaching any consumer, (c) `tag-enum.schema.json` change without corresponding `persona-frontmatter.schema.json` bump trips the lockstep test. | — | S | Yes (w/ 1,2) |

**Gate (corrected per /check sequencing MF#1 + MF#2):**
- Tasks 1+2+3 must complete before W2 begins (W1 schemas → W2 helpers contract lock).
- Task 0 (PRE-W2) must complete before **W4** begins; W2/W3/W5/W6 are independent of probe outcome.

### Wave W2: Python Helpers + Resolver (depends on tasks 1+2+3; task 0 not required)

Tasks 4+5+6 parallel; task 7 sequential after all three.

| # | Task | Deps | Size | Parallel? |
|---|------|------|------|-----------|
| 4 | NEW `scripts/_tag_baseline.py`. Pipeline (normative order): (1) NFKC + zero-width strip, (2) strip YAML frontmatter, (3) strip balanced code fences (3+ tick, MULTILINE+DOTALL), (4) lowercase, (5) apply `BASELINE_KEYWORDS` regexes (fix `\b--` → `(?<!\w)--`), (6) emit `set[str]`. Public API: `compute_baseline(spec_text) -> set[str]`; `assert_baseline_subset(recorded, spec_file) -> None` raises `TagDriftError` on drift. AST-banlisted (no eval/exec/subprocess/socket). CLI: `python3 _tag_baseline.py <spec_file>` → JSON `{"baseline": [...]}`. | 1,2,3 | M | Yes (w/ 5,6) |
| 5 | NEW `scripts/_persona_score.py`. `fit_score = len(set(spec_tags) & set(persona_fit_tags))`. `combined_score = fit_score * (lbr or 0.5)`. **M1 fix:** missing `lineage` in rankings row → default `"claude"` at read time. Cold-start (<3 runs/persona): set all LBR to 0.5 uniformly. CLI: `python3 _persona_score.py <spec_tags_json> <rankings_jsonl>` → JSON array sorted by `combined_score` desc. | 1,2,3 | S | Yes (w/ 4,6) |
| 6 | NEW `scripts/_tier_assign.py`. Tier rule: `base_opus = max(opus_min, floor(N/2))`; top `base_opus` by `combined_score` → opus; rest → sonnet; ties → alphabetical (sonnet-bias per `remainder_tiebreak: sonnet`). `validate_tier_pins(pins, registry, security_floor) -> int` (0/2/3/4). **SEC-01:** `fit_tags:[security]` persona pinned below `security_floor` → return 2. Deep recursive tier_policy merge. SEC-04: calls `assert_baseline_subset` via import of `_tag_baseline`. Exit codes 0/2/3 enforced at all 6 call sites. | 1,2,3 | M | Yes (w/ 4,5) |
| 7 | Extend `scripts/resolve-personas.sh`. New flow: call `_tag_baseline.py` → `_persona_score.py` → `_tier_assign.py` in sequence (one shell process, not per-persona subprocesses). Emit `<persona>:<tier>` per line (`codex-adversary` bare). Write gate-scoped `selection.json` at `docs/specs/<feature>/<gate>/selection.json` when `--emit-selection-json`. New flags: `--opus-min N` (bounded), `--tier-pin` (accumulating; SEC-01 at parse time). **SEC-09:** use `mktemp -d` + trap cleanup for internal temp files. Patch all 6 callers for `:<tier>` suffix in same PR. | 4,5,6 | M | No |

### Wave W3: /spec Phase 3 Tag Inference (depends on task 4 only; parallel with W4/W5)

| # | Task | Deps | Size | Parallel? |
|---|------|------|------|-----------|
| 8 | Extend `commands/spec.md` Phase 3. After spec draft: call `_tag_baseline.py`; LLM proposes additions; prompt: `Tags: [security*, data*, api] — Enter to accept, type list to override, or empty to skip:` (`*` = baseline-locked). Baseline-locked tag removal restores with: `[security] is baseline-detected and cannot be removed.` Write `tags: [...]  # baseline: [...]; llm-added: [...]` to frontmatter. Autorun: auto-accept full inferred set. Grandfathered specs (absent `tags:` key): offer inference on next revision. (Earlier revisions of this row said "Drop A20 from spec's AC list"; that was a wording error — A20 is the unrelated pipeline-cycle-dogfood AC; the tag-inference AC is A12. A12 stays in spec.md, A20 stays in spec.md, no AC drops here. See followup `ck-b8a20a20a2`.) | 4 | M | Yes (w/ W4, W5) |

### Wave W4: Gate Dispatch Wiring (depends on task 7; 3 sub-trees fully parallel)

**Sub-tree SR:**

| # | Task | Deps | Size | Parallel? |
|---|------|------|------|-----------|
| 9 | `commands/spec-review.md` Phase 0b: read `<persona>:<tier>` from resolver; pass `model: "opus"` or `model: "sonnet"` to Agent tool (NO wrapper files unless PRE-W2 forces pivot). Phase 1 step 0: stale-tags warning — run `_tag_baseline.py`, compare to recorded `tags:`, emit `[stale-tags] WARNING: ...` if ≥1 enum delta. | 0, 7 | M | Yes (w/ 11, 13) |
| 10 | `scripts/autorun/spec-review.sh`: read `:<tier>`; pass `--model claude-opus-4-5/claude-sonnet-4-6` to `claude -p`. **M2 fix:** dep is task 9 only. | 9 | S | No |

**Sub-tree PL:**

| # | Task | Deps | Size | Parallel? |
|---|------|------|------|-----------|
| 11 | `commands/plan.md` Phase 0b: same as 9, no stale-tags warning. | 0, 7 | S | Yes (w/ 9, 13) |
| 12 | `scripts/autorun/plan.sh`: same as 10. **M2 fix:** dep is task 11 only. | 11 | S | No |

**Sub-tree CK:**

| # | Task | Deps | Size | Parallel? |
|---|------|------|------|-----------|
| 13 | `commands/check.md` Phase 0b: same as 9, no stale-tags warning. | 0, 7 | S | Yes (w/ 9, 11) |
| 14 | `scripts/autorun/check.sh`: same as 10. **M2 fix:** dep is task 13 only. | 13 | S | No |

### Wave W5: Dashboard (depends on task 7; parallel with W3/W4)

| # | Task | Deps | Size | Parallel? |
|---|------|------|------|-----------|
| 15 | `dashboard/index.html`: "Panel Tier Mix" column (e.g., "1 Opus / 5 Sonnet + Codex"). Read from `selection.json` `tier_policy_applied`. | 7 | S | Yes (w/ 16) |
| 16 | `scripts/judge-dashboard-bundle.py`: read `tier_policy_applied` from gate-scoped `selection.json`. **Defensive read:** absent field → "N/A" (no error during MVP window). | 7 | S | Yes (w/ 15) |

### Wave W6: Full Test Matrix (depends on W1+W2+W3+W4 complete)

All test files parallel; orchestrator wiring sequential after.

| # | Task | Deps | Size | Parallel? |
|---|------|------|------|-----------|
| 17 | NEW `tests/test-dynamic-roster.sh`: tag×tier×budget×opus_min×tier_pins×Codex×stale-tags×empty-intersection×cold-start matrix. Panel table A3b: verify N=2..8 Opus/Sonnet counts exactly. | W4 | M | Yes (w/ 18-23) |
| 18 | NEW `tests/test-tier-resolver.sh`: `_tier_assign.py` unit tests. N=2..8 panel table. SEC-01 rejection (spec + CLI). `--tier-pin` accumulates. Tier-pin promotion drops lowest `combined_score`. | task 6 | M | Yes |
| 19 | NEW `tests/test-spec-tags-flow.sh`: /spec Phase 3 accept/edit/skip. Baseline-protected tag rejection + re-add. Grandfathered spec inference offer. | task 8 | S | Yes |
| 20 | NEW `tests/test-security-floor.sh`: SEC-01 A21. Adversarial `tier_pins: {security-architect: sonnet}` → rejected at config-load. CLI `--tier-pin` path also rejected (G3 fix). | task 6 | S | Yes |
| 21 | NEW `tests/test-tag-baseline.sh`: SEC-02 A22. (a) NFKC Cyrillic `аuth` → `security` detected. (b) 3-tick fence keyword → NOT detected. (c) 4-tick fence keyword → NOT detected. (d) Unbalanced fence → full scan. (e) Inline single-tick → not excluded. (f) YAML frontmatter `tags: [security]` → NOT self-triggered. (g) AST-banlist: `ast` parse asserts no eval/exec/subprocess/socket. (h) Adversarial injection spec → `security` in baseline. | task 4 | M | Yes |
| 21a | NEW `tests/test-baseline-drift.sh` (**sev:security MF#4**): SEC-04 drift-halt path. Fixture pair: (1) spec.md with `security` keyword in body + frontmatter `tags_provenance.baseline: []` → resolver exits with documented distinct drift-halt exit code (non-zero, distinct from schema-error codes), stderr contains canonical error string `[tier-policy] SEC-04: tags_provenance.baseline drift detected; refusing to dispatch`; (2) equality case (recorded == recomputed) → exits 0. Asserts the resolver-side `assert_baseline_subset` enforcement that defends against post-write `tags_provenance.baseline` shrinking. | task 7 | S | Yes |
| ~~22~~ | ~~`tests/test-explain-mutation-zero.sh`~~ **CUT (Rev 4)**: `--explain` is carved to sibling spec `pipeline-resolver-debugging`; mutation-zero test moves there. | — | — | — |
| 23 | Extend `tests/test-resolve-personas.sh`: tier output assertions (`<persona>:<tier>` format). Cold-start. 7 concurrent-read fixtures (parallel autorun `&`-dispatch). | task 7 | S | Yes |
| 24 | Extend `tests/run-tests.sh`: wire tasks 17-21, 21a, 23. **Orchestrator wiring** (per `feedback_test_orchestrator_wiring_gap` memory): verify test count matches `ls tests/test-*.sh` after wiring. | tasks 17-21, 21a, 23 | S | No |

---

## Open Questions

1. ~~**PRE-W2 empirical gate failure path:**~~ **Resolved 2026-05-12.** PRE-W2 verdict was **YES across all 3 cells** (Opus parent, Sonnet parent, `claude -p` headless) — no pivot needed. **Post-build trim (ck-1234567890):** the wrapper-script pre-design that lived here in earlier revisions was over-specified for an outcome that didn't happen; Rev 5 collapses it. If a future re-probe flips to mixed/NO outcome, halt the build and file a follow-up spec for the wrapper pivot rather than re-inlining a multi-requirement design here. (The 5-requirement contract — ≤30 line wrapper, exit-5/6 fail-fast, exact-string + alias match, `--output-format json`, evidence-file append — remains in git history at plan rev4 if needed.)

2. **`--tier-pin` validate-at-parse-time overhead (~50ms):** Acceptable latency vs. lazy validation at dispatch time? **Recommend eager** — fail-fast is better UX.

3. ~~**`/wrap-insights` + dashboard compat:**~~ **Resolved 2026-05-12.** W5-B (`scripts/judge-dashboard-bundle.py`) reads `selection.json` defensively: missing `tier` field → render dash/blank for that row, do not crash, do not auto-migrate older `selection.json` files. Add same guard to `/wrap-insights` if it reads the field. Test fixture: legacy `selection.json` (no tier) loads without error. No file-mutation pass.

4. **Post-build trim (ck-2233445566) — `--tier-pin` accumulate semantics:** D14 originally specified accumulating-multi-flag with promote + drop-lowest. Spec.md L89 only shows single-flag usage. The promote-drop-lowest interaction with SEC-01 floor adds non-trivial branching for a feature no observed user has hit. **Recommendation:** v1 ships **last-wins** semantics for `--tier-pin`; revisit accumulating only if a user demonstrates the limitation. (BACKLOG.md candidate.) Implementation note: as of `2a8c3cf`, the resolver's `cli_tier_pins` dict assignment IS effectively last-wins (later `--tier-pin` flag overwrites earlier same-key); accumulating across-flag was never wired. The Rev 5 prose simplification matches what the code does.

5. **Post-build trim (ck-2345678901) — PRE-W2 evidence file persistence:** Task 0 wrote `plan/dispatch-precedence-evidence.md` as a persistent append-only artifact. For a one-shot probe (PRE-W2 ran once, verdict YES, never re-runs unless a CLI major-version bump), the persistent file is heavier than needed. **Recommendation:** future probes inline-assert the verdict in PR description / commit message rather than persisting a `.md` artifact; only persist when a wrapper pivot fires (the wrapper's runtime mismatch-halt rows are the actual load-bearing evidence, not the one-time probe). The Rev 4 file at `docs/specs/dynamic-roster-per-gate/plan/dispatch-precedence-evidence.md` stays in git history for the audit trail.

---

## Risks

| Risk | Severity | Mitigation |
|------|----------|-----------|
| PRE-W2 empirical gate fails (model param not honored) | High | Branched policy locked in Open Q#1 + **3-cell probe matrix in task 0** (Opus parent ‖ Sonnet parent ‖ `claude -p` headless): mixed outcome → FLAKY → halt. Single-context blind-spot mitigated (/check risk MF#3). |
| Wrapper-pivot model-id assertion bypass (silent downgrade) | High (sev:security) | Open Q#1 (a) pinned: absent field → exit 5 halt; match is exact-string OR documented alias table; `--output-format json` pinned; every outcome audited to evidence file (/check security MF#5). |
| SEC-04 baseline-drift halt path untested | High (sev:security) | NEW task 21a `tests/test-baseline-drift.sh` wired into task 24 orchestrator (/check security MF#4). |
| `fit_tags` enum rejection bypass | High (sev:security) | Task 3 `test-schema-lockstep.sh` extended with adversarial-value + shell-meta + lockstep coverage (/check security MF#6). |
| `schemas/selection.schema.json` not yet created | Medium | W1 task 2 creates it; W2 gates hard on W1 |
| M2 dep error was in old plan | Medium | Explicitly corrected in D10 + task table |
| `persona-rankings.jsonl` untracked in git | Low | lineage default (D9) covers MVP |
| W6-H orchestrator gap | Low | Task 24 named explicitly |

---

## Build Slicing (Slice 1 already shipped)

| Slice | Tasks | Size | Description |
|-------|-------|------|-------------|
| ~~Slice 1~~ | — | Done | fit_tags backfill on 19 personas (shipped as `dynamic-roster-1-tags`) |
| Slice 2 | 0, 1, 2, 3 | S-M | PRE-W2 empirical gate + W1 schemas |
| Slice 3 | 4, 5, 6, 7 | M | W2 Python helpers + resolver extension (SEC-02/03/04 inline) |
| Slice 4 | 8, 9-14, 15-16 | M | W3 /spec Phase 3 + W4 gate dispatch wiring + W5 dashboard |
| Slice 5 | 17-24 | M | W6 full test matrix + orchestrator wiring |

---

## Compatibility

- All W1-W5 code reads `docs/specs/constitution.md` unchanged. Constitution rename is sibling spec.
- No `--allow-security-downgrade` or `--acknowledge-baseline-mismatch` in v1 (carved to `pipeline-security-escape-hatches`).
- No `--explain` formatter in v1 (carved to `pipeline-resolver-debugging`).
- No `specificity_factor` (cut until persona-author drift observed).
