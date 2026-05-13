## Summary (wave-sequencer persona — full output captured in conversation)

**5-wave decomposition (recommended Option B).** Single PR per autorun lockstep; waves = ordered commits within one PR.

**Wave 1 — Data contract + autorun lockstep (load-bearing)**
- `schemas/check-verdict.schema.json` v1→v2 (9 new fields, additionalProperties:false preserved)
- `schemas/findings.schema.json` (additive `class`, `class_inferred`, `source_finding_ids`, optional `tags`)
- `schemas/followups.schema.json` (NEW; full lifecycle + class enum narrowed to 4)
- `scripts/_policy_json.py`: zero code change, add `"followups"` to KNOWN_SCHEMAS
- `scripts/render-followups.py` (NEW; deterministic, sort-keys pinned, exit codes 0/2/3/4)
- `scripts/_followups_lock.py` (NEW; fcntl.flock helper)
- `scripts/autorun/check.sh`: `GO_WITH_FIXES` + `cap_reached` handling + `iteration` bound-check
- `tests/test-autorun-policy.sh` CI guard (A8b) — partial-landing rejection
- Schema fixture tests (golden verdict files round-trip)

Verifier: hand-crafted v2 verdict validates; followups.jsonl fixture round-trips; check.sh against GO_WITH_FIXES fixture exits 0; CI guard rejects synthetic partial landing.

Parallelization within wave: schemas + _policy_json.py + render-followups.py + _followups_lock.py in parallel; check.sh after schemas; CI guard last.

**Wave 2 — Persona template proof-point (1 persona, approved)**
- `personas/_templates/class-tagging.md` (NEW; canonical template)
- ONE representative reviewer persona updated as the template (lean: `personas/review/scope-discipline.md`)
- `personas/judge.md` — highest-class-wins, reclassification authority, tiebreakers, missing/invalid → unclassified coercion
- `personas/synthesis.md` — verdict JSON fence emission, followups.jsonl regenerate-active scoped to source_gate, render-followups.py invocation, lock acquisition

Depends on: Wave 1
Verifier: template reads coherently; Judge applied to 2-reviewer-disagreement fixture produces highest-class-wins verdict; Synthesis fixture run produces v2-schema-valid verdict + well-formed followups.jsonl.
**USER APPROVAL GATE** at the persona template before wave 3 (per `feedback_template_first_batching.md`).

**Wave 3 — Behavior closure: 27-persona batch + gate commands**
- Batch-apply class-tagging via `scripts/apply-class-tagging-template.sh` to remaining ~27 personas
- `commands/{spec-review,plan,check}.md` — frontmatter parse, CLI flag parse (incl. `--force-permissive`), mode resolution, banner emission with `.gate-mode-warned` + `~/.claude/.gate-mode-default-flip-warned-v0.9.0` sentinels, `.force-permissive-log` writes, iteration tracking, Synthesis invocation
- `commands/build.md` — verdict-sidecar read (latest verdict in {GO, GO_WITH_FIXES} required), `state: open` + `target_phase IN (build-inline, docs-only)` filter, plan-revision triggers /plan re-run, post-build → PR-body annotation, pre-v0.9.0 backcompat
- `commands/spec.md` — Phase 3 frontmatter schema gains `gate_mode`, `gate_max_recycles`
- Sidecar naming: `spec-review-verdict.json`, `plan-verdict.json`, `check-verdict.json`
- Shared `commands/_gate-mode.md` include for the truth table

Depends on: Waves 1, 2
Verifier: end-to-end /check on fixture spec produces expected verdict + followups.jsonl; --permissive on strict spec exits with conflict error; --force-permissive writes audit log + emits banner; /build on NO_GO refuses to start.

Parallelization within wave: 27 persona batch-applies fully parallel (template-driven, mechanical); 5 command files largely independent. Suggest 3 parallel agents: (a) persona batch, (b) gate commands, (c) build.md + spec.md.

**Wave 4 — Documentation surfaces (A15a — blocking for v0.9.0)**
- `docs/index.html` mermaid diagram update (three-tier verdict)
- `CHANGELOG.md` v0.9.0 entry (default flip + opt-back-in instructions)
- `install.sh` — one-time upgrade banner with `~/.claude/.gate-permissiveness-migration-shown` sentinel
- `VERSION` bump to 0.9.0
- README narrative deferred to A15b (out of scope for this spec)

Depends on: Wave 3 (final wording depends on observed wave-3 reality)
Verifier: docs/index.html renders; CHANGELOG passes adopter scan; install.sh upgrade-banner test (run twice → second silent).

**Wave 5 — Hardening: tests + orchestrator + edge-case coverage**
- `tests/test-permissiveness.sh` (NEW) — A12 fixture matrix + cross-gate isolation + concurrency lock + addressed→open regression
- `tests/fixtures/permissiveness/*.findings.jsonl` — fixture data
- **Explicit orchestrator wiring task: edit `tests/run-tests.sh` to invoke test-permissiveness.sh** (per `feedback_test_orchestrator_wiring_gap.md` — NAMED responsibility)
- `tests/test-agents.sh` updates if new persona template requires frontmatter validation

Depends on: Waves 1, 2, 3
Verifier: `bash tests/run-tests.sh` runs test-permissiveness.sh; all fixtures pass; `ls tests/test-*.sh | wc -l` matches orchestrator's invocation count.

**Constraints:**
- Single-PR landing (autorun lockstep): waves 1-5 are commits within one PR
- Template-first approval gate between wave 2 and wave 3 (memory directive)
- `additionalProperties: false` requires all 9 verdict fields atomically in wave 1
- Branch-protection: ~1 review cycle for the merge gate
- Test orchestrator wiring is recurring failure mode — explicit named line item in wave 5
- bash 3.2 compatibility for all autorun/*.sh changes
- Tilde expansion in path-write contexts

**Open Questions:**
- OQ1: render-followups.py in wave 1 (data-contract sibling)
- OQ2: defer template-persona choice to /plan-final (any choice works structurally)
- OQ3: `gh release create` is post-/build, not in plan scope
- OQ4: lock primitive — atomic mkdir vs fcntl.flock vs O_EXCL — RESOLVE in wave 2 (lean: fcntl.flock per scalability)
- OQ5: /build sidecar discovery — hardcode check-verdict.json only (option a)

**Cross-dimension hand-offs:** api owns CLI contracts → wave 1 schemas/scripts; data-model owns lifecycle state machine → wave 1 schema, wave 2 Synthesis; ux drafts strings → wave 3 commands + wave 4 CHANGELOG; security pins class:security parity field name → wave 1 findings.schema.json; integration owns CI guard → wave 1.
