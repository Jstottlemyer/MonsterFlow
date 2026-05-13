# Wave Sequencing — Raw

### Key Considerations
1. **Two parallel contracts in Wave 1**: data shape (3 JSON schemas) + API shape (`_policy.sh` signatures). Independent, both prerequisites for stage-script integration.
2. **One genuinely risky unknown**: flock-protected atomic JSON append on macOS bash 3.2 with set -e + traps. macOS flock not preinstalled. Pull forward as Wave 0/1 spike.
3. **autorun-shell-reviewer checklist expansion is itself input to its own audit gate** — chicken-and-egg. Checklist must land before final audit; helpers can land in parallel with it.
4. **Test-orchestrator wiring is named historical failure mode** — assigned-by-name, not implicit.
5. **commands/check.md + synthesis prompt has inversion** — synthesis emits sidecar that check.sh reads. If integration ships before synthesis update, fallback path exercised continuously. Land synthesis WITH integration.
6. **Adopter migration low-code, high-stakes** — final wave alongside tests is correct.

### Options Explored
- **A — Strict 3-gate**: matches default; "behavior" wave becomes 9-file mega. Rejected.
- **B — 6 waves**: spike, schemas, helpers, integration, docs+migration, tests+audit. Heavy.
- **C — 5 waves with Wave 0 spike folded into Wave 1** ✅: spike+schemas, helpers, integration, docs/migration, tests+audit.

### Recommendation
**5 waves. Wave 0 spike folded into Wave 1.**

```
Wave 1: Contract + bash 3.2 spike
  1.1 macOS bash 3.2 flock+atomic-append spike (30-line script under set -e + trap, 2 parallel writers × 100 iters torture test, document flock-fallback) | M | parallel A | depends: none
  1.2 schemas/morning-report.schema.json (NEW) | S | parallel B | depends: none
  1.3 check-verdict.json schema doc + finding_id derivation in docs/specs/<slug>/contracts.md | S | parallel B | depends: none
  1.4 run-state.json schema doc | S | parallel B | depends: none
  1.5 _policy.sh API contract freeze (signatures + STAGE/AXIS enums as comments at top of empty skeleton) | S | parallel B | depends: 1.1
  Hand-off: contracts.md + _policy.sh skeleton + spike-report.md
  Verifier: schemas validate; spike runs green; signatures reviewed
  Min-shippable: no

Wave 2: Helper implementation
  2.1 scripts/autorun/_policy.sh (NEW) — implement per frozen contract, flock atomic-append per spike | L | parallel A | depends: 1.1, 1.5
  2.2 scripts/autorun/_codex_probe.sh (NEW) — autorun-shell-only, exits 0/1/2 | M | parallel A | depends: none
  2.3 queue/autorun.config.json — policies block defaulting all axes "block" | S | parallel A | depends: 1.5
  Hand-off: working helpers + inline smoke tests
  Verifier: source _policy.sh, call policy_act with mock state, observe append; codex_probe exits correctly
  Min-shippable: no

Wave 3: Stage-script integration (behavior wave)
  3.1 run.sh — --mode + run_id + queue/runs/<run-id>/ + lockfile + initial state + auto-merge gate + morning-report render | L | parallel A | depends: 2.1, 2.3
  3.2 check.sh — _json_get on sidecar + ordered grep fallback + integrity blocks + verdict NO_GO + policy_act GO_WITH_FIXES + security block | L | parallel A | depends: 2.1
  3.3 build.sh — branch-owned check + pre-reset SHA/stash/diff + policy_act branch | M | parallel A | depends: 2.1
  3.4 verify.sh — infra classifier + policy_act verify_infra | M | parallel A | depends: 2.1
  3.5 spec-review.sh — replace inline command -v codex with _codex_probe.sh + policy_act on probe failure | S | parallel A | depends: 2.1, 2.2
  3.6 notify.sh — read morning-report.json + final_state mapping | S | parallel A | depends: 2.1
  3.7 commands/check.md — synthesis OVERALL_VERDICT + sidecar emit + sev:security regex + finding_id | M | parallel B | depends: 1.3
  3.8 personas/check/security-architect.md — mandate sev:security tag | S | parallel B | depends: 1.3
  Closing serial step: integration smoke against fixture
  Hand-off: working overnight-mode pipeline
  Verifier: run.sh --mode=overnight on fixture produces expected morning-report.json
  Min-shippable: yes — overnight policy works end-to-end (without docs/tests, but functional)

Wave 4: Adopter migration + subagent checklist
  4.1 .claude/agents/autorun-shell-reviewer.md — +5 pitfalls (sourced helper × set -e × trap; sticky RUN_DEGRADED; policy_act API; flock atomic-append; bash 3.2 parallel-array idiom) | M | parallel A | depends: 2.1
  4.2 scripts/doctor.sh — flag missing policies block + AUTORUN_MODE recommendation | S | parallel A | depends: 2.3
  4.3 CHANGELOG.md — silent default-shift documentation | S | parallel A | depends: 3.1
  Hand-off: doctor.sh emits new warning; subagent has updated checklist
  Verifier: doctor.sh against legacy config emits warning; CHANGELOG diff reviewed; subagent doc lints
  Min-shippable: no — wrappers around Wave 3

Wave 5: Tests + final audit gate
  5.1 tests/fixtures/autorun-policy/ — 4 fixture dirs (clean→merged, infra-timeout→pr-awaiting-review, NO_GO→halted, GO_WITH_FIXES+security→halted) | M | parallel A | depends: 3.1-3.6
  5.2 tests/test-autorun-policy.sh — 7 unit cases (parsing, precedence, sidecar happy/missing/malformed, security carve-out, headline "warn → RUN_DEGRADED → auto-merge skipped") | L | parallel A | depends: 5.1
  5.3 **WIRE INTO ORCHESTRATOR** — tests/run-tests.sh adds test-autorun-policy.sh to TESTS=() array. Verify by running orchestrator. Same agent as 5.2 owns 5.3 (single pair of eyes) | S | parallel A | depends: 5.2
  5.4 /preship — git status clean, ACs verified, --mode help quoted | S | parallel B | depends: 5.3
  5.5 **autorun-shell-reviewer subagent invocation** — invoke on cumulative diff Waves 2+3. Apply High findings inline. Re-invoke until clean. | M | serial last | depends: 5.4, 4.1
  Hand-off: green test suite, clean preship, zero High findings
  Verifier: bash tests/run-tests.sh shows new test fire; subagent returns no High; AC count == 22
  Min-shippable: yes — full deliverable
```

### Constraints Identified
- bash 3.2 / macOS — flock, assoc arrays, negative subscripts forbidden. Wave 1 spike must validate.
- No new hard deps (AC#12) — `_json_get` works without jq. Verified Wave 2.
- Subagent checklist precedes audit — 4.1 must land before 5.5.
- Synthesis-emits-sidecar inversion — 3.7 lands with 3.2.
- Hardcoded carve-outs not env-tunable — helper enforces in Wave 2.

### Open Questions
1. macOS flock availability path — `/usr/bin/flock` (BSD has none), Homebrew, or util-linux keg? Wave 1 spike answers. If unavailable, fallback (mkdir-mutex or python-lock) becomes contract — changes API surface — may force spec amendment before Wave 2.
2. Synthesis prompt timing vs interactive `/check` — additive but worth one explicit smoke run.
3. Fixture-vs-real boundary in Wave 5 — stub claude -p outputs (faster, deterministic) vs real CLI? Recommend stubs + one optional integration smoke.

### Integration Points
- Wave 1 → 2: `_policy.sh.contract` + spike report. Wave 2 implements reading only Wave 1 artifacts.
- Wave 2 → 3: sourceable helpers. Wave 3 edits source these.
- Wave 3 → 4: Wave 4.1 reviewer skims Wave 2/3 diffs to know actual function shape.
- Wave 4 → 5: 5.5 audit consumes 4.1 checklist. Hard ordering.
- Wave 5 internal: 5.3 (orchestrator wiring) historically-missed. Same agent as 5.2.

**Critical-path summary:** 1.1 (spike) → 1.5 (API freeze) → 2.1 (helper) → 3.1+3.2 (run.sh + check.sh) → 5.5 (audit). Five hops; everything else parallelizes against this spine.
