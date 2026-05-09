# Scope Discipline — /check Review

**Verdict:** PASS WITH NOTES — plan is largely proportionate to spec v4.2, but several plan-introduced items are gold-plating, premature future-proofing, or duplicated test surface that should be cut or folded before /build dispatches.

---

## Must Fix

None. No item is structurally load-bearing enough to block /build, but several Should-Fix cuts will trim 3–5 tasks from Wave 2/3 with zero spec risk.

---

## Should Fix

**SF-1 — Cut T-DOC-4 (`config-readme.md`).**
- **finding_id:** scope-T-DOC-4-premature
- **class:** scope-cuts
- **severity:** minor
- **body:** Spec §Project Discovery / Lifecycle explicitly says the `~/.config/monsterflow/README.md` is *"out of scope here; opens an issue in onboarding"* — i.e., it belongs to the install.sh spec that hasn't been written. Plan T-DOC-4 pre-writes content for that future install.sh wiring. This is the textbook "while we're in there" cleanup the persona checklist warns against, and it adds a committed file (`docs/specs/token-economics/config-readme.md`) that has no consumer in v1.
- **suggested_fix:** Drop T-DOC-4. Add one BACKLOG line: *"install.sh writes `~/.config/monsterflow/README.md` — content TBD when install.sh spec lands."* Move on.

**SF-2 — Defer T-CORE-13 (`--explain PERSONA[:GATE]`) to v1.1.**
- **finding_id:** scope-explain-flag-deferral
- **class:** scope-cuts
- **severity:** minor
- **body:** `--explain` is listed in the spec's post-M5 CLI surface, but D3 reveals it's interactive-debug surface that's TTY-gated, prints plaintext finding titles, and never feeds the JSONL/bundle/`/wrap-insights`. The two render surfaces this spec actually ships are the dashboard tab and the `/wrap-insights` text section — those are the value delivery. `--explain` is a debugging affordance for a maintainer (Justin) who can already grep `findings.jsonl` directly with one shell line. Adds a TTY-gating code path, a privacy-posture carve-out (titles allowed here but nowhere else), and a separate verification path. Net new value vs. complexity is low.
- **suggested_fix:** Cut `--explain` from the v1 CLI surface (now 5 flags); move to BACKLOG with a one-line rationale ("local-debug; v1 maintainers grep findings.jsonl directly"). Update T-CORE-1 argparse to drop it; remove T-CORE-13 entirely. Update spec §Project Discovery / CLI surface in T-DOC-1 appendix to reflect 5 flags, not 6.

**SF-3 — Cut T-CORE-12's `--quiet` flag.**
- **finding_id:** scope-quiet-flag-creep
- **class:** scope-cuts
- **severity:** nit
- **body:** Plan adds `--quiet` to T-CORE-12 *"resolves gaps #6"*, but spec §Project Discovery / CLI surface lists the canonical 5 flags + `--confirm-scan-roots`. `--quiet` is plan-introduced scope and isn't load-bearing — `safe_log()` is already counts-only and a single line per invocation. Adopters who want silence can `2>/dev/null`.
- **suggested_fix:** Drop `--quiet` from T-CORE-12. Keep `safe_log()` and the raw-print ban; that's the spec's actual ask.

**SF-4 — Fold T-TEST-9 (dashboard recovery) into T-TEST-6 (salt).**
- **finding_id:** scope-test-9-dup
- **class:** tests
- **severity:** nit
- **body:** T-TEST-9 simulates salt corruption + regen + dashboard fresh-install banner render. Salt corruption is already T-TEST-6's domain; the dashboard fresh-install banner is already T-UI-3's e12 path. T-TEST-9 sits in the seam and creates a third test file for behavior the other two cover. Cross-test coupling (T-TEST-9 depends on T-UI-2) also breaks Wave 2 parallelism.
- **suggested_fix:** Delete T-TEST-9. Add one assertion to T-TEST-6: after corruption + regen, assert `persona-rankings.jsonl` is cleared and `persona-insights-bundle.js` `__PERSONA_RANKINGS` is `[]`. Banner-render check is already T-UI-3's responsibility against e12.

**SF-5 — Defer T-CORE-11 (schema-version reader guard) until v1.1 ships.**
- **finding_id:** scope-schema-guard-premature
- **class:** scope-cuts
- **severity:** nit
- **body:** D6 specifies `compute-persona-value.py` refuses to read non-v1 rows. There is no v1.1 yet; nothing emits `schema_version != 1`. The full-rebuild contract (D5) means readers regenerate from source on every invocation anyway — the JSONL is never *read* by `compute-persona-value.py` itself, only emitted. The guard fires for a non-existent input. v1.1 build can add the guard at the same time it adds the new schema field; A12 currently asserts a v1-only behavior with no v1.1 to compare against.
- **suggested_fix:** Drop T-CORE-11 and A12 from this plan; move both to v1.1 BACKLOG with note *"add schema-version reader guard when introducing schema_version: 2"*. Saves a task + an AC + the inverted-fixture work to verify.

**SF-6 — Trim T-DOC-2 (`notes.md`) to two essentials.**
- **finding_id:** scope-notes-md-six-topics
- **class:** scope-cuts
- **severity:** minor
- **body:** D16 lists six sub-topics (interpreting low scores, salt rotation, persona-author posture, `--scan-projects-root` walkthrough, Linux disclaimer, v1.1-unblock criterion). Two — persona-author posture (R12) and `--scan-projects-root` onboarding (R11) — close concrete review gaps. The other four are speculative content for problems no one has hit yet. Salt-rotation procedure has zero adopters today; Linux disclaimer is contradicted by the spec's macOS-only stance (Open Q3); v1.1-unblock is a planning artifact, not user-facing docs; "interpreting low scores" overlaps with the dashboard warning banner already specified in A5.
- **suggested_fix:** Cut `notes.md` to two sections: persona-author posture (one paragraph) + `--scan-projects-root` first-time walkthrough (5–10 lines). Drop the rest. If the cut sections become real questions post-merge, write them then.

---

## Notes

**N-1 — Open Q3 (Linux stance) is internally contradictory.**
- **class:** documentation
- The spec says macOS-only is out of scope. Plan Open Q3 then recommends *"add a one-line 'should work on Linux but untested' note to T-DOC-2."* Either Linux is in scope (then test it) or out of scope (then don't document it). Pick one — recommendation is to align with spec and drop the Linux note from T-DOC-2 entirely (compounds with SF-6).

**N-2 — Plan-introduced ACs (A12, A13, A14) are reasonable but should be reflected in spec, not just plan.**
- **class:** documentation
- A13 (multi-persona +1 each, D10) and A14 (silent retention semantics, D8) pin real spec ambiguities the reviewers found. T-DOC-1's "Build-time clarifications" appendix is the right home — confirm those ACs land in spec.md so future builders aren't reading the plan to learn the contract. A12 should be cut alongside SF-5.

**N-3 — D9 `cost_window_size: 45` field is fine but symmetrical-with-existing.**
- **class:** scope-cuts
- **severity:** nit
- The spec already pins window=45 for value and explicitly separates value vs cost windows (M3). Adding a parallel field is honest schema, not creep. Keep, but verify it earns its allowlist slot in T-SCHEMA-1.

**N-4 — Wave 2 has 10 tests; Wave 3 has 3 docs files + 1 spec appendix.**
- **class:** scope-cuts
- After SF-4 + SF-5 + SF-6 + SF-1, Wave 2 drops to 8 tests, Wave 3 drops to 1–2 docs files. That's a more proportionate distribution for a measurement-only v1.

**N-5 — Cut candidate confidence: high.**
- All six Should-Fix cuts are reversible (re-add post-merge in v1.1 if pain emerges) and remove ~5 tasks + 1 AC + 1 schema field + 1 CLI flag from /build's plate. None touch the data-layer correctness path (T-CORE-5/7/8/10) or the privacy gates (T-SCHEMA-1, T-TEST-3/4). Net effect: smaller PR, faster /build, same v1 value.

---

**Verdict:** PASS WITH NOTES — accept the plan and proceed to /build, applying SF-1 through SF-6 inline before dispatching wave 0.
