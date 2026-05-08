# Spec Review — dynamic-roster-1-tags

**Reviewed:** 2026-05-07
**Reviewers:** ambiguity feasibility gaps requirements scope stakeholders

---

## ambiguity

# Ambiguity Analysis — dynamic-roster-1-tags

## Critical Gaps

**C1. A7 vs A5 pass-count contradiction.** A7 says "total pass count is `<previous_count> + 3` (where 3 is the new validations from A5)." A5 lists **four** assertions: (a) frontmatter present, (b) enum-valid, (c) no empty/missing, (d) no duplicates. So is the new test contributing 3 or 4 PASS lines? An implementer will guess; the test orchestrator wiring (A6) and the `+3`/`+4` arithmetic will diverge. Pin the exact count and which assertions map to which PASS lines.

**C2. "NEW or extension" for `spec-frontmatter.schema.json` is undefined.** §Scope and §Data both say "NEW or extension." Two engineers will implement this differently — one creates a fresh file, another searches for an existing schema and patches it. Grep results aren't shown. Decide: does a `schemas/spec-frontmatter.schema.json` already exist on disk? If yes, extend; if no, create. State the answer, not the disjunction.

**C3. "PyYAML absent → falls back to `ast`-style parser" is hand-wavy.** Edge case 5 says the test uses `python3 yaml.safe_load` but "falls back to `ast`-style parser if PyYAML absent." There is no standard-library `ast`-style YAML parser. System Python 3.9 on macOS does **not** ship PyYAML. Two readings: (a) shell out to a hand-rolled regex parser, (b) require PyYAML and fail loudly. Pick one. This is the single highest-risk ambiguity in the slice because it gates whether the test runs at all on a fresh checkout.

**C4. JSON Schema `$ref` resolution path is unspecified.** All three schemas use `{"$ref": "tag-enum.schema.json"}` (relative). The test validates with `python3 -c` — using which library? `jsonschema` isn't stdlib either. And relative `$ref` resolution depends on a `base_uri` the test must set. Without a chosen validator + base_uri convention, A1/A2/A3 "validates as JSON Schema" is unverifiable.

## Important Considerations

**I1. "Optional in this slice" vs `required: ["fit_tags"]` in persona schema.** §Scope says `fit_tags:` is "Optional for now; slice 3 makes it required for personas dispatched at gates." But §Data's `persona-frontmatter.schema.json` declares `"required": ["fit_tags"]` and A3 reiterates "REQUIRED." Which is true in slice 1? The schema as written is required-from-day-one. If that's intentional, delete the "Optional for now" sentence. If not, drop the `required` array.

**I2. "additionalProperties: true for v1 ... Tightened in later slices."** No later slice mentions tightening this. Without a tracked deferral, "later" means never. Either link to which slice tightens it or drop the promise.

**I3. Test LoC cap "≤80 LoC bash" appears twice but isn't load-bearing.** If the test needs to shell to `python3` for YAML + JSON Schema validation across 19 files with helpful error messages, 80 lines is tight. Is this a hard constraint or a target? Implementer will hit 90 LoC and wonder if that fails review.

**I4. A11 forbids `[[ =~ ]]` but bash 3.2 supports it.** macOS bash 3.2.57 has `[[ =~ ]]` (added in 3.0). The constraint as written is stricter than necessary and may push the implementer toward awkward `case` statements. If the intent is "no bash-4 features," list those (`mapfile`, `${arr[-1]}`, `&>`, associative arrays) and drop `[[ =~ ]]`.

**I5. Mapping rationale undefined for several personas.** The mappings are committed as design decisions but with no rationale. Examples that two reviewers will read differently:
- `risk.md → [scalability, security, integration]` — why not `data` or `migration`?
- `wave-sequencer.md → [refactor, integration]` — wave sequencing is more naturally `scalability` or `api`.
- `testability.md → [refactor]` only — surprising that a testability persona has no `integration` or `data` tag.
The spec says these are "judgment calls" and "fix-forward" (Q-mapping-validation), which is fine, but a one-line "why" per non-obvious mapping would prevent a /check or /code-review debate.

**I6. "Each persona must declare at least one fit tag" — is the empty case really impossible?** A general-purpose persona (e.g., a future `coordinator.md`) might legitimately have no domain fit. `minItems: 1` forecloses that. Slice 3 will need a "neutral / always-eligible" mechanism anyway. Worth flagging: is the right primitive a `fit_tags: ["*"]` wildcard or a separate `always_dispatch: true` flag? Not blocking slice 1, but the schema decision constrains slice 3.

## Observations

**O1. "Closed enum" wording is consistent and good.** `tag-enum.schema.json` is the single source of truth, referenced by `$ref` in both downstream schemas. Low ambiguity here.

**O2. A9 dormancy check is well-specified.** "Grep for `fit_tags` across `scripts/`, `commands/`, `tests/` should match only `tests/test-persona-fit-tags.sh` and the schema files." This is unambiguously verifiable.

**O3. Tag enum members `docs` vs `documentation`.** The class-tagging block (spliced) uses `class: documentation`. The fit-tag enum uses `docs`. These are different vocabularies (class-tagging is finding-classification, fit_tags is persona-content-fit) so it's not a contradiction — but flag for readers who may conflate them. A one-line note in the spec would help.

**O4. `default: []` on the spec `tags:` field is harmless but unused.** Nothing in slice 1 reads spec `tags:`, so the default is dormant. Fine to keep, just noting.

**O5. Edge case 1 ("persona file has no frontmatter at all") — current 19 personas all have frontmatter.** The spec acknowledges this is "future-proofing." Good; not ambiguous.

**O6. CHANGELOG entry text is pinned verbatim.** Low ambiguity. Good.

**O7. "Schema lockstep CI guard" (A12) is mentioned but not implemented.** A12 says schemas are "version-pinned (`$id` URLs include schema version)." But the example `$id`s in §Data are `https://monsterflow.dev/schemas/tag-enum.schema.json` — no version segment. Either the `$id`s should be `…/v1/tag-enum.schema.json` or A12 is documenting an intent without a mechanism. Minor; pick one.

## Verdict

**PASS WITH NOTES** — slice is small, additive, and well-scoped, but C1 (pass-count contradiction), C2 (NEW-or-extension), and C3/C4 (YAML + JSON Schema validator choice on system Python 3.9) must be resolved before /build to prevent two engineers writing different tests.

---

## feasibility

## Critical Gaps

None. This is a metadata-only additive slice with concrete schemas, explicit mappings, and a single validation test. The build surface is mechanical.

## Important Considerations

1. **JSON Schema `$ref` resolution across sibling files is non-trivial without a resolver.** A6/A11 prescribe `python3 -c` for validation, but stock `jsonschema` (and certainly the `ast`/yaml fallback the spec hand-waves at) won't auto-resolve `{"$ref": "tag-enum.schema.json"}` from a relative path — you need a `RefResolver` with a `base_uri` of the schemas dir, or you need to inline the enum. Recommend the test inline the 9-value enum as a bash array and validate against it directly (no JSON Schema lib at all), and treat the schema files as documentation/contract artifacts. Keeps A11 (bash-3.2 + system Python 3.9) honest.

2. **A11 says "falls back to `ast`-style parser if PyYAML absent" — this is hand-wavy.** macOS system Python 3.9 does not ship PyYAML. The test must work without `pip install`. Pin the implementation: parse the persona frontmatter with a tiny Python regex that extracts the `fit_tags: [...]` line, or use a here-doc Python that does `yaml.safe_load` only inside a `try:` guarded by `import yaml`. Spec should commit to one. Recommend regex extraction — frontmatter shape is uniform and trivial.

3. **`tests/run-tests.sh` wiring is a known recurring miss** (per `feedback_test_orchestrator_wiring_gap.md`). Make A6 explicit: the /build agent that creates `test-persona-fit-tags.sh` must also append the `run_test "persona-fit-tags"` line to the orchestrator in the same commit. Call it out in §Integration so it doesn't get fan-out-lost.

4. **`additionalProperties: true` on `spec-frontmatter.schema.json` makes the schema almost vacuous** (only validates `tags:` if present). That's fine for slice 1 stated intent, but the `$id` URL versioning (A12) implies forward migration discipline that this loose schema undermines. Either drop the spec-frontmatter schema from slice 1 entirely (it validates almost nothing useful) or note explicitly that v1 is a stub whose only contract is the `tags:` enum constraint.

5. **`$id` URLs reference `https://monsterflow.dev/schemas/...`** — that domain may not exist / may not host these. JSON Schema `$id` is identity, not necessarily a fetchable URL, so this is technically fine, but if any tooling tries to dereference it (some validators do), it will hang or fail. Recommend either a real published location or a URN-style `$id` (`urn:monsterflow:schemas:tag-enum:v1`) to make the no-fetch contract explicit.

6. **Mapping accuracy is deferred to slice 3** (Q-mapping-validation). That's defensible, but the spec should call out that the `personas/check/risk.md → [scalability, security, integration]` (3 tags) mapping is unusually broad — three tags makes risk a near-universal match. If slice 3's selection logic uses tag intersection, risk will be selected on almost every spec. Worth a sanity check now rather than rediscovering in slice 3.

7. **Schema lockstep guard (A12) lacks an enforcement mechanism.** A12 asserts version-pinned `$id`s but doesn't add a CI check. Per `feedback_schema_bump_grep_prose_drift.md`, schema-prose drift is a known footgun. If slice 1 introduces three schemas and the lockstep guard is "we'll be careful," that drift starts immediately. Either defer A12 to a later slice or add a simple grep-test that fails if `$id` versions diverge.

## Observations

- 19 mechanical edits + 3 schema files + 1 test fits a single /build wave comfortably; the slicing rationale is sound.
- A9 (grep for `fit_tags` should only match the test + schemas) is a nice dormancy assertion — cheap to verify, high signal.
- The closed 9-value enum is small enough to memorize, large enough to cover the personas without forcing weird mappings. Good vocabulary choice.
- `personas/plan/ux.md → [ux]` and `personas/plan/security.md → [security]` are single-tag mappings — these will be the canaries for whether the resolver in slice 3 ever picks them up.

## Verdict

**PASS WITH NOTES** — buildable as specified; resolve the `$ref`-resolution + PyYAML-absent ambiguity in A11 and explicitly wire `tests/run-tests.sh` in A6 before /build, or the slice will hit the same orchestrator-wiring and fabricated-tooling pitfalls already captured in MEMORY.md.

---

## gaps

# Missing Requirements Review — dynamic-roster-1-tags

## Critical Gaps

**C1. No specification of YAML parser fallback behavior when PyYAML is absent.**
A11 mandates bash-3.2 compat and §Edge Cases #5 says "falls back to `ast`-style parser if PyYAML absent." But `ast` cannot parse YAML — it parses Python literals. The fallback path is undefined. What happens on a fresh macOS where PyYAML isn't installed? Does the test skip, fail, or attempt a regex-based YAML parse? **The next engineer will hit this on day one.** Specify: (a) is PyYAML a hard dep? (b) if not, what's the actual fallback (custom regex parser? require `python3 -m pip install pyyaml`?)? (c) does `tests/run-tests.sh` install it, document it, or skip the test?

**C2. No CI/precommit enforcement story for "new persona must have fit_tags:".**
Edge case #6 says "CI/test run on PR would fail until added. Acceptable enforcement gate." But MonsterFlow's CI surface isn't specified — is `tests/run-tests.sh` invoked by a GitHub Action? A pre-commit hook? Nothing? If a contributor adds `personas/plan/new-persona.md` without `fit_tags:` and pushes, what stops it from merging? The "enforcement gate" is asserted but not wired.

**C3. Schema `$ref` resolution path is undefined.**
`spec-frontmatter.schema.json` and `persona-frontmatter.schema.json` use `"$ref": "tag-enum.schema.json"` (relative). Whatever validates these (the test? a future tool?) needs a base URI or filesystem resolution policy. `python3 -c` with no JSON Schema library cannot resolve `$ref`. A12's "schema lockstep CI guard" implies validation, but neither the validator tool nor `$ref` resolution is specified. **Does the test even validate against the schema, or just hand-roll enum checks?**

## Important Considerations

**I1. No audit/provenance for backfill mapping decisions.**
19 persona→tag mappings are committed as judgment calls (Q-mapping-validation acknowledges this). When slice 3 surfaces a wrong mapping, how does the next engineer know *why* `risk.md → [scalability, security, integration]` was chosen? Suggest: a one-line comment per persona above the `fit_tags:` line, or a `docs/specs/dynamic-roster-1-tags/mapping-rationale.md` artifact.

**I2. `additionalProperties: true` on persona-frontmatter is a forward-compat trap.**
Slice 3+ presumably tightens this. Without a deprecation/migration plan documented now, future slices will silently accept typo'd keys (`fit_tag:` singular, `fittags:`) that schema validation won't catch. Consider: log a warning on unknown keys even while `additionalProperties: true`.

**I3. No rollback procedure if mappings prove systematically wrong.**
If slice 3 lights up the resolver and 8/19 mappings are bad, what's the rollback? The §Sequencing Note says "Reverting this slice would require reverting all five" — that's a one-way door. Specify: can mappings be hot-fixed via PR without reverting the schema? (Almost certainly yes, but state it.)

**I4. Concurrent backfill edits → merge conflicts.**
If two contributors both add new personas in flight, both touch frontmatter format conventions but not the same files — low risk. But if someone is concurrently editing persona bodies (say, /spec-review tuning), the frontmatter line addition could conflict. State the convention: backfill commit should be atomic + done before/after any persona-body PR, not interleaved.

**I5. No spec.md `tags:` backfill guidance for existing specs.**
Slice 2 makes `tags:` required for NEW specs. What about the ~10 existing specs in `docs/specs/`? §Edge Cases #7 says "grandfathers existing ones" — but `/wrap-insights` Phase 1c, persona-metrics joins, and future tooling may all need consistent `tags:` across all specs. State explicitly: existing specs are exempt forever, OR they get backfilled in slice 2, OR they get backfilled here.

**I6. `description:` field in persona frontmatter is unmentioned.**
Persona files have a `description:` field (per the diff example). The schema declares `additionalProperties: true` so it passes, but slice 1 is the moment to decide: is `description:` schema-validated, optional, required? Punting it to "later slices" is fine but should be explicit.

## Observations

**O1. Class tagging audit:** This spec itself has `tags: [data, integration, security]` — but slice 1 introduces *no* security surface (no auth, no untrusted input, no secret handling). The `security` tag here is aspirational/inherited from the parent spec. Consider dropping or annotating why it's tagged.

**O2. A7 pass-count assertion is brittle.**
"total pass count is `<previous_count> + 3`" — this couples the spec to current test infrastructure cardinality. If anyone adds a test in flight, A7 falsely fails. Reframe as "all pre-existing tests pass + persona-fit-tags adds 3 new passing assertions."

**O3. Mobile/offline/i18n/accessibility/multi-tenancy/audit-logging/rate-limiting — N/A.**
This slice is local repo metadata. None of those checklist items apply, and the spec is correct to omit them.

**O4. Admin/debug tooling — barely applicable but worth noting.**
When slice 3+ ships and a persona doesn't get selected for a spec it should match, the debug path is "grep `fit_tags:` + `tags:` and intersect by hand." Slice 1 could ship a `scripts/inspect-persona-tags.sh` (one-liner) to make that mechanical. Not blocking — slice 3's concern.

**O5. Versioning in `$id` URLs (A12) is asserted but not shown.**
The example schemas use `https://monsterflow.dev/schemas/tag-enum.schema.json` — no version segment. A12 says version-pinned — should be `.../v1/tag-enum.schema.json` or similar. Inconsistency between example and AC.

**O6. Deprecation/cleanup story for old behavior — N/A here, but flag it for slice 3.**
Slice 1 removes nothing. When slice 3 lights up dispatch, the prior "all personas always run" behavior gets deprecated. Not slice 1's job, but worth noting for the parent spec tracker.

## Verdict

**PASS WITH NOTES** — Scope is genuinely additive metadata + one test, edge cases are mostly enumerated, and the slicing rationale is sound. Resolve C1 (YAML parser fallback) and C3 (`$ref` resolution / actual validator) before /build, since both directly block the test from working on a fresh machine; C2 (CI enforcement wiring) can be punted to a follow-up issue if explicitly logged.

---

## requirements

# Requirements Completeness Review — dynamic-roster-1-tags

## Critical Gaps

**None.** This is a metadata-only slice with explicit acceptance criteria; nothing blocks implementation.

## Important Considerations

1. **A7 pass-count arithmetic is ambiguous.**
   - persona: requirements
   - finding_id: req-01
   - severity: major
   - class: contract
   - title: "A7 says +3 validations but A5 enumerates 4 (a/b/c/d)"
   - body: A5 lists four assertions (presence, enum-valid, non-empty, no-duplicates), but A7 expects `<previous_count> + 3`. A QA engineer cannot resolve whether A5(d) is folded into A5(b)'s enum check or counts as its own test case. This determines whether `tests/run-tests.sh` exits with 3 or 4 new PASS lines.
   - suggested_fix: Reconcile to a single number — either drop A5(d) (uniqueItems is purely schema-level) or bump A7 to `+4`.

2. **A11 forbids `[[ =~ ]]` but bash 3.2 supports it.**
   - persona: requirements
   - finding_id: req-02
   - severity: minor
   - class: documentation
   - title: "Bash 3.2 compat list over-restricts"
   - body: `[[ =~ ]]` is available since bash 3.2; the real hazards are `mapfile`/`readarray` (4.0+), `${arr[-1]}` (4.2+), `&>` redirection (works but quirky), associative arrays (4.0+). Listing `[[ =~ ]]` as forbidden will cause needless test-author churn.
   - suggested_fix: Remove `[[ =~ ]]` from the forbidden list; add `mapfile`/associative arrays explicitly.

3. **No failure-mode definition for the YAML parser fallback.**
   - persona: requirements
   - finding_id: req-03
   - severity: minor
   - class: tests
   - title: "Edge case 5 says 'falls back to ast-style parser if PyYAML absent' — undefined behavior"
   - body: There is no `ast`-style YAML parser in stdlib. The fallback path is unspecified, so a CI runner without PyYAML would hit undefined territory. Given the personas' frontmatter is trivial (one-line `fit_tags: [a, b]`), a regex parser would be more honest than claiming a non-existent fallback.
   - suggested_fix: Either (a) declare PyYAML a hard requirement and check at test start with a clear error, or (b) specify a regex extraction for the `fit_tags:` line and drop the YAML claim.

4. **No observability/failure-message contract.**
   - persona: requirements
   - finding_id: req-04
   - severity: minor
   - class: tests
   - title: "Test failure messages aren't specified"
   - body: Edge cases 1-4 promise "clear messages" / "lists the offender + valid enum" but A5 doesn't pin the exact format. Two implementations could both pass A5 with wildly different error UX. Not a blocker — but pinning at least the offender-file path + offending-value format would make the test reproducible across re-implementations.
   - suggested_fix: Add A5(e): "On failure, message includes file path, line number (best-effort), offending value, and full enum list."

## Observations

- **Success criteria are strong.** A1–A12 are largely binary, machine-verifiable, and a QA engineer could write the test plan from the spec alone (§Edge Cases enumerates 8 boundary conditions explicitly).
- **A9 dormancy assertion is excellent** — the `grep fit_tags` precondition gives a hard, automatable proof that this slice introduces zero behavior.
- **Rollback story is implicit but correct** — metadata-only + one new test means revert = `git revert <sha>`; no migration to undo. Worth one explicit sentence in §Sequencing Note for completeness.
- **No performance/scale NFRs** — appropriate for a 19-file metadata slice; calling out N/A would be defensive but not required.
- **No security NFRs** — also appropriate; the only "untrusted input" is persona-author YAML, validated by the schema itself.
- **Tag mappings are spec'd as design-time decisions** — good call per `feedback_obvious_decisions.md`. Q-mapping-validation correctly defers empirical correction to slice 3.
- **CHANGELOG entry (A8)** is required but the exact text isn't pinned. Minor; the §Scope already gives the message verbatim.

## Verdict

**PASS WITH NOTES** — acceptance criteria are testable and complete; the +3-vs-+4 reconciliation (req-01) and the YAML-fallback ambiguity (req-03) should be resolved during /plan but neither blocks slice progression.

---

## scope

# Scope Analysis — dynamic-roster-1-tags

## Critical Gaps

None. The slice is unusually well-bounded: metadata + one schema family + one validation test, with explicit dormancy (A9) and explicit deferrals to slices 2–5.

## Important Considerations

1. **`tags:` on spec frontmatter is in-scope but orphaned.** The slice adds `spec-frontmatter.schema.json` with an optional `tags:` field, but nothing in slice 1 consumes it, validates it against existing specs, or writes it. Slice 2 is named as the consumer (LLM-propose for spec tags), but this slice doesn't even add a test that the schema *parses*. Either (a) cut `spec-frontmatter.schema.json` entirely from slice 1 and move it to slice 2 where it has a consumer, or (b) add an AC that asserts the schema file is valid JSON Schema 2020-12 (parallel to A1/A3). Right now A2 says "Schema is valid JSON Schema" but no test enforces it. **Recommend: cut to slice 2.** Smaller surface, tighter slice, fewer files to review.

2. **Inevitable day-after asks not addressed.** Three predictable requests once this lands:
   - "Why does `requirements.md` have `[docs, integration]` and not `[docs, scalability]`?" — bikeshed risk on the 19 mappings. Spec acknowledges this in Q-mapping-validation but doesn't establish a *non-blocking* review channel. Add: "mapping disputes are PR comments on slice 3, not slice 1 blockers."
   - "Can I add a 10th tag?" — no governance for enum extension. The enum is closed but the spec doesn't say *how* it gets extended (new spec? PR + ADR? slice 2 owns it?). One sentence under §Scope would close this.
   - "What about `commands/code-review/*` personas?" — slice scopes to `personas/{review,plan,check}/` (19 files). The `code-review/` personas (4 files per CLAUDE.md) are silent. State explicitly out-of-scope.

3. **Phasing seam between A4 (mappings) and A9 (dormancy) is fine, but the mappings themselves are a phase-2-in-disguise.** The 19 mappings are inference judgment that won't be validated until slice 3's resolver runs. That's acknowledged, but the slice is effectively shipping *unvalidated data* under the cover of "schema-correct." Mitigation: add a pointer in the CHANGELOG entry that mappings are provisional and will be empirically refined in slice 3.

## Observations

- **MVP is already at the floor.** You cannot cut further without breaking the foundation contract for slice 3. The validation test (A5) is correctly included — removing it would defer typo-detection to the resolver, which is exactly the false-economy this slicing strategy is preventing.
- **`additionalProperties: true` in the spec frontmatter schema** is a deliberate v1 choice and correct here, but flag it so slice 2+ remembers to tighten it. Add a `# TODO(slice-2)` comment in the schema file or a note in §Out of Scope.
- **Backlog routing table is exemplary** — every parent-derived slice is enumerated with explicit dependency. No scope ambiguity about what belongs where.
- **A11 (bash-3.2 compat)** correctly cites the prior memory item. Good defensive scoping.
- **A12 (`$id` version pinning)** is forward-thinking but the spec doesn't show what the version segment looks like (e.g., `/v1/tag-enum.schema.json` vs. `/tag-enum.schema.json`). The shown `$id` URLs have no version segment. Either drop A12 or show the versioned URL form in §Data & State.
- **Out-of-scope list is thorough** — explicitly defers 8 distinct items to slices 2–5. Low risk of "while we're in there" creep.

## Verdict

**PASS WITH NOTES** — scope is tight, dormancy is enforced, and deferrals are explicit; recommend cutting `spec-frontmatter.schema.json` to slice 2 (no consumer here), declaring `code-review/` personas explicitly out-of-scope, and reconciling A12's version-pinning claim with the actual `$id` URLs shown.

---

## stakeholders

# Stakeholder Analysis — dynamic-roster-1-tags

## Critical Gaps

**None.** This slice is metadata-only, dormant data, with no runtime behavior change. No stakeholder is materially affected at ship time.

## Important Considerations

**1. Persona authors (future contributors) — onboarding doc missing.**
A6/A12 require `fit_tags:` on every new persona, and the schema enforces it (`required` + `minItems:1`). But no stakeholder-facing doc tells a new persona author:
- What the 9 enum values mean (e.g., `refactor` vs `migration` boundary)
- How to pick 1-3 tags vs all-applicable
- Where to look up the canonical enum

Without a `personas/README.md` update or a comment block in `persona-frontmatter.schema.json`, the next person adding a persona hits a schema rejection with no guidance. **Add a short "tag taxonomy" note** — could be 10 lines in `personas/README.md` or expanded `description:` fields inside the schema.

**2. Adopters of the install.sh / MonsterFlow consumers — silent schema enforcement.**
External adopters who run `install.sh` get the new persona-frontmatter.schema.json with `required: [fit_tags]`. If any of *their* customized personas lack `fit_tags:`, `tests/run-tests.sh` will start failing on next run. Spec doesn't mention:
- Whether `install.sh` warns adopters their custom personas need backfill
- Whether `tests/test-persona-fit-tags.sh` only walks the shipped `personas/` dirs or also adopter overrides

**Resolution:** explicitly scope the test to repo-shipped personas in slice 1, OR add a CHANGELOG note flagging adopter-side persona backfill as a breaking change.

**3. Slice 2+ spec authors — mapping accuracy is unowned.**
A4 commits specific persona→tag mappings (e.g., `risk.md → [scalability, security, integration]`). Q-mapping-validation defers correctness to slice 3's empirical signal. But there's no named owner for "review the 19 mappings before slice 3 ships" — it's an implicit follow-up. Recommend logging a `followups.jsonl` entry at slice-1 ship so slice 3's plan picks it up.

**4. CI / test orchestrator — new test wiring is the historically risky step.**
Per `feedback_test_orchestrator_wiring_gap.md`, parallel /build agents have repeatedly written test files but forgotten to wire them into `tests/run-tests.sh`. A6 calls this out, which is good — but recommend the /build wave assigns orchestrator wiring as a *named, sequential, post-wave step* (not parallelized), and `/preship` verifies `ls tests/test-*.sh | wc -l` matches the run-tests.sh invocation count.

## Observations

- **Security stakeholder:** no signoff needed — no auth, secrets, or untrusted-input surface. `tags: [security]` in spec frontmatter is taxonomy-only.
- **Operators/dashboard consumers:** unaffected in this slice (slice 5 is where the dashboard column lands).
- **Support/docs:** no user-facing changes; no support-ticket impact.
- **Conflicting needs:** none surfaced. The only tension is between *strict enforcement* (`required: [fit_tags]` is good for slice 3 readiness) vs *adopter friction* (custom personas break tests). Spec leans strict — appropriate given §A9's dormancy guarantee, but worth a CHANGELOG callout.
- **Veto power:** none in this slice. Slice 3 is where persona-roster owners (you) have veto on whether mappings are accurate; that gate is correctly deferred.
- **First support question post-launch:** "I added a new persona and tests/run-tests.sh fails — what's `fit_tags`?" Mitigated by Important Consideration #1.

## Verdict

**PASS WITH NOTES** — slice is well-scoped, dormancy is verifiable (A9), and stakeholder surface is minimal because no behavior changes ship; address the persona-author onboarding doc and adopter-side test-scope question before /build to avoid post-merge friction.

