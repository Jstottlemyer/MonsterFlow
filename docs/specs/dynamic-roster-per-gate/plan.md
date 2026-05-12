---
name: dynamic-roster-per-gate
stage: plan
created: 2026-05-06
revised: 2026-05-12
gate_mode: permissive
revision: 3
revision_reason: "Revision 2 reached /check GO_WITH_FIXES (permissive, 6 must-fix). Revision 3 applies the 6 must-fix items inline: PRE-W2 3-cell probe matrix (risk MF#3), W2 gate decoupled from PRE-W2 (sequencing MF#1), W4 tasks 9/11/13 add task 0 dep (sequencing MF#2), NEW task 21a SEC-04 drift test (sec MF#4), Open Q#1 wrapper-pivot fail-fast contract pinned (sec MF#5), task 3 fit_tags enum rejection coverage (sec MF#6)."
---

# Plan — dynamic-roster-per-gate (Revision 3)

**Revised:** 2026-05-12 (Rev 2 → Rev 3, same day)
**Spec:** `docs/specs/dynamic-roster-per-gate/spec.md`
**Prior check verdict (Rev 2):** GO_WITH_FIXES (permissive) — 3 architectural + 3 sev:security must-fix, all inline-tractable
**This revision addresses:** 6 must-fix items inline — see Revision Log below; 24 should-fix items deferred to `docs/specs/dynamic-roster-per-gate/followups.jsonl`

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
| D2 | `_tag_baseline.py` pre-processing: NFKC normalize → strip YAML frontmatter → strip balanced fences (3+ tick) → lowercase → regex | Frontmatter strip before fences prevents `tags: [security]` self-triggering (G7 fix). NFKC before all else (SEC-02, Edge Case 22) |
| D3 | `<persona>:<tier>` colon-delimited stdout; `codex-adversary` bare | grep-friendly; no jq dependency; backward-breaking change patched at all 6 call sites simultaneously |
| D4 | No wrapper files (D7 / Edge Case 20): model tier via Agent tool `model:` param (interactive) and `--model` flag (headless) only. Halt if model param fails — no disk fallback | Trust boundary; persistent injection risk on SIGKILL outweighs any convenience |
| D5 | PRE-W2 empirical gate: empirically verify `model: "opus"` controls dispatch before any dispatch code ships | MF-1 from check.md; D4 architecture depends entirely on this being true |
| D6 | Tier-mix algorithm: `base_opus = max(opus_min, floor(N/2))`; tiebreak → sonnet; highest `combined_score` claims Opus seats | Deterministic; cost-conscious; matches spec panel-size table |
| D7 | SEC-01 enforced at 2 sites: `_tier_assign.py validate_tier_pins` AND CLI `--tier-pin` parse site (G3 fix) | CLI cannot be a downgrade escape hatch |
| D8 | SEC-04 resolver recompute: `_tag_baseline.py` runs at every gate dispatch; asserts `recorded_baseline ⊆ recomputed_baseline`; drift halts | `tags_provenance.baseline` is author-writable; resolver owns ground truth (S4 / Edge Case 23) |
| D9 | `lineage` default to `"claude"` at read time in `_persona_score.py` when field absent from rankings row | M1 fix; no backfill required for MVP; one-line guard |
| D10 | M2 corrected dep graph: each autorun gate shell depends on its own command file, not a shared final task | spec-review.sh → resolver + commands/spec-review.md; plan.sh → resolver + commands/plan.md; check.sh → resolver + commands/check.md |
| D11 | Constitution rename OUT of W1-W5: all code reads `docs/specs/constitution.md` as-is | Sibling spec `monsterflow-pipeline-config-rename` owns the rename |
| D12 | Test target: ≥33 fixtures, <15s wall-clock (single normative number) | Resolves contradiction between "50-70" and "40-60" from spec; testability MF-1 from check |
| D13 | Three separate Python helpers (not one batched script) | Testability + AST-banlist isolation per helper; resolver calls them in sequence (one shell process, not per-persona subprocess) |
| D14 | `--tier-pin` flag accumulates across multiple invocations (not last-wins); promotes unselected persona, drops lowest `combined_score` non-pinned non-security selection | I6/G6 fix |

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
| 8 | Extend `commands/spec.md` Phase 3. After spec draft: call `_tag_baseline.py`; LLM proposes additions; prompt: `Tags: [security*, data*, api] — Enter to accept, type list to override, or empty to skip:` (`*` = baseline-locked). Baseline-locked tag removal restores with: `[security] is baseline-detected and cannot be removed.` Write `tags: [...]  # baseline: [...]; llm-added: [...]` to frontmatter. Autorun: auto-accept full inferred set. Grandfathered specs (absent `tags:` key): offer inference on next revision. Drop A20 from spec's AC list. | 4 | M | Yes (w/ W4, W5) |

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
| 22 | NEW `tests/test-explain-mutation-zero.sh`: SEC-03 A23. tmpdir + fixed file tree. `find <tmpdir> -newer <marker>` → zero output after resolver invocation. | task 7 | S | Yes |
| 23 | Extend `tests/test-resolve-personas.sh`: tier output assertions (`<persona>:<tier>` format). Cold-start. 7 concurrent-read fixtures (parallel autorun `&`-dispatch). **Legacy fixture (Open Q#3 resolution):** `selection.json` missing `tier` field loads without error in `judge-dashboard-bundle.py`. | task 7 | S | Yes |
| 24 | Extend `tests/run-tests.sh`: wire tasks 17-23 + 21a. **Orchestrator wiring** (per `feedback_test_orchestrator_wiring_gap` memory): verify test count matches `ls tests/test-*.sh` after wiring. | tasks 17-23, 21a | S | No |

---

## Open Questions

1. ~~**PRE-W2 empirical gate failure path:**~~ **Resolved 2026-05-12.** Branched policy by probe outcome:
   - **Both probes YES** → D4 architecture (Agent calls), no pivot.
   - **(a) Agent `model:` NO, (b) `claude -p --model` YES** → Block W4 and pivot to **wrapper-script tier-dispatch**: `scripts/dispatch-persona.sh <persona> <tier> <prompt-file>` thinly wraps `claude -p --model <tier>`. Requirements on the pivot:
     - Wrapper is ≤30 lines, arg-passthrough only (no routing logic); permanent header comment block cites PRE-W2 evidence so the D4 deviation reason cannot rot.
     - Runtime model assertion (**sev:security MF#5** — fail-fast contract pinned):
       - **Absent `model` field in response** → halt with `[dispatch-precedence] response missing model field; cannot verify tier`, exit code 5. (Silent-pass default = downgrade bypass; not acceptable.)
       - **Match semantics:** exact-string match on the response `model` field against the `--model` arg, OR documented alias table loaded from the same constitution loader as `security_floor`. Initial alias table: `{"opus": "claude-opus-4-5", "sonnet": "claude-sonnet-4-6"}` (extend as needed). Partial / substring matches are **not** acceptable.
       - **Output format:** wrapper pins `--output-format json` and reads the `model` field at a documented JSON path (recorded in `dispatch-precedence-evidence.md` at PRE-W2 time; locked thereafter for the spec's lifetime).
       - **Every outcome** (pass / mismatch-halt exit 6 / missing-halt exit 5) appends one row to `plan/dispatch-precedence-evidence.md` so a flaky regression would be noticed.
     - W1/W2/W3/W5/W6 unaffected; only W4-SR/W4-PL/W4-CK rewrite.
     - Re-probe TODO: when CLI major version bumps, re-run PRE-W2; if (a) now YES, retire wrapper.
   - **Both probes NO** → carve W4 to a separate spec; ship W1+W2+W3+W5+W6 with selection.json producing tier metadata that no consumer dispatches on (dashboard renders advisory-only).
   - **Flaky** → halt and escalate; do not ship runtime detection logic.

2. **`--tier-pin` validate-at-parse-time overhead (~50ms):** Acceptable latency vs. lazy validation at dispatch time? **Recommend eager** — fail-fast is better UX.

3. ~~**`/wrap-insights` + dashboard compat:**~~ **Resolved 2026-05-12.** W5-B (`scripts/judge-dashboard-bundle.py`) reads `selection.json` defensively: missing `tier` field → render dash/blank for that row, do not crash, do not auto-migrate older `selection.json` files. Add same guard to `/wrap-insights` if it reads the field. Test fixture: legacy `selection.json` (no tier) loads without error. No file-mutation pass.

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
