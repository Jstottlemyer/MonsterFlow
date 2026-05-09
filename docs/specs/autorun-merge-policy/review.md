# Review — autorun-merge-policy

**Reviewers:** ambiguity, docs-clarity, feasibility, gaps, requirements, scope, stakeholders, codex-adversary
**Mode:** strict synthesis (gate_mode resolved: permissive from frontmatter, but stakeholders returned FAIL — so synthesis presents blocker-level findings)
**Generated:** 2026-05-08

---

## Overall Verdict: **NO-GO** — revise spec, then re-run /spec-review

The asymmetric-risk argument is sound and the carve-out from the runtime-validation sibling spec is clean. But six **convergent** issues across multiple reviewers — plus three **file-grounded blockers from Codex** — show the spec is operating against an imagined autorun architecture rather than the one in `scripts/autorun/run.sh`. Until the integration points, file paths, helper names, and the `validated`-fallback safety default are corrected, /plan would design against a fiction.

Stakeholders returned the only outright FAIL — and they're right: the spec flips a behavior-changing default (auto-merge → PR-only) with **no upgrade comms path** for the existing power-user stakeholder (the MonsterFlow author and other current overnight-autorun users). That alone warrants the NO-GO.

---

## Reviewer Verdicts

| Dimension | Verdict | Key Finding |
|---|---|---|
| Requirements | PASS WITH NOTES | "Clean gates" predicate undefined (req-001, blocker class) |
| Gaps | PASS WITH NOTES | Codex-clean source-of-truth missing (gaps-G3); PR backlog ops story absent (gaps-G2) |
| Ambiguity | PASS WITH NOTES | "Zero warnings + no Codex high-severity" both undefined; gate_mode permissive + clean policy re-introduces risk (A3) |
| Feasibility | PASS WITH NOTES | Spec elides four-axis merge gate (`MERGE_CAPABLE`, `RUN_DEGRADED`, `VERDICT`, `PR_CREATED`) at run.sh:1069-1102 (F-1) |
| Scope | PASS WITH NOTES | `validated` ships before its gate exists; scope discipline good elsewhere |
| Stakeholders | **FAIL** | Default flip silently degrades existing overnight users — no migration banner, no CHANGELOG breaking-default callout |
| **Codex adversarial** | **HALT — 3 file-grounded HIGH findings** | (1) `validated → clean` fallback is wrong safety default; (2) live autorun spec path is `queue/<slug>.spec.md` not `docs/specs/<slug>/spec.md`; (3) `docs/specs/constitution.md` doesn't exist — template at `templates/constitution.md`, runtime path is `<project>/docs/specs/constitution.md` |

---

## Must Fix Before /plan (8 items)

### MF1. "Clean gates" predicate is undefined and load-bearing
**Source:** req-001 (blocker), A1, A2, F-1, gaps-G3, DC-3 — **6 reviewers convergent**.
AC#5 says `clean` policy preserves "today's behavior: auto-merge when zero warnings + no Codex high-severity." But "warnings" and "Codex high-severity" never get pinned to:
- Which file the dispatcher reads (`followups.jsonl`? `check-verdict.json`? `codex-review.json`?)
- Which severity vocabulary applies (`{blocker, major, minor, nit}` or `{High, Medium, Low}`)
- What happens if Codex didn't run (timeout, missing CLI) — vacuously clean or unmet?
- How this composes with the existing four-axis merge gate at `scripts/autorun/run.sh:1069-1102` (`MERGE_CAPABLE`, `RUN_DEGRADED`, `VERDICT ∈ {GO, GO_WITH_FIXES}`, `PR_CREATED`)

**Fix:** Add a "Definitions" subsection to Data & State pinning the predicate as a single named function `is_clean_for_merge()`:
```
clean := MERGE_CAPABLE == 1
       AND VERDICT in {GO, GO_WITH_FIXES}
       AND CODEX_HIGH_COUNT == 0
       AND RUN_DEGRADED == 0
       AND policy_allows_merge(resolved_policy)
```
Treat absence of Codex artifact as fail-closed (counts as "Codex review missing → not clean").

### MF2. Spec uses wrong autorun spec path — `queue/<slug>.spec.md` is the runtime location
**Source:** Codex H2 (file-grounded against `scripts/autorun/run.sh:667`).
The resolver in this spec reads `docs/specs/<slug>/spec.md`. But autorun's runtime reads `$SPEC_FILE = $QUEUE_DIR/${SLUG}.spec.md` per `run.sh:667`, and `commands/autorun.md:9` instructs users to copy canonical specs into `queue/`. If the merge-policy resolver reads from `docs/specs/`, copied queue specs can drift from canonical docs and resolve a different merge intent than the file actually being executed.

**Fix:** Update Approach + Integration to: resolver reads `$SPEC_FILE` (the queue copy) for its frontmatter authority. Constitution path stays `<project>/docs/specs/constitution.md`. Document the implication: editing `docs/specs/<slug>/spec.md` after a queue copy was made does NOT affect the in-flight merge policy — the queue file is canonical for the run.

### MF3. `docs/specs/constitution.md` does not exist in this repo — runtime vs template confusion
**Source:** Codex H3 (file-grounded — actual path is `templates/constitution.md`).
The spec says "constitution.md template" but conflates two different files: (a) the template at `templates/constitution.md` (shipped with MonsterFlow), and (b) the per-project runtime file at `<project-root>/docs/specs/constitution.md` (created when `install.sh` copies the template into a new adopter's project).

**Fix:** Update Integration: "Resolver reads `<project-root>/docs/specs/constitution.md` at runtime. Template changes (e.g., adding a commented-out `auto_merge_policy:` example for new adopters) belong in `templates/constitution.md`." Update test fixtures to seed a project-local constitution file, not the engine template.

### MF4. `validated` fallback to `clean` recreates the risk this spec exists to prevent
**Source:** Codex H1 (architectural), gaps-G5, scope-IC-1, stakeholders-006 — 4 sources.
Today's spec says `validated` falls back to `clean` until the runtime-validation gate ships. The asymmetric-risk argument in the Summary explicitly says auto-merge without runtime validation is too aggressive. Falling back to `clean` therefore recreates exactly that risk for any user who opts into `validated` and watches it silently auto-merge under weaker semantics.

**Fix:** Change fallback target from `clean` to `pr` (or exit 2). Update AC#6 and AC#15 accordingly. Optional knob `validated_fallback: pr | clean` defaulting to `pr` if user wants to preserve the cushioned path.

### MF5. Stakeholder upgrade-communication path is missing — default-flip is silent
**Source:** stakeholders-001 (blocker, FAIL verdict), stakeholders-002 (major), gaps-G7 (minor).
The spec ships v0.11.0 with a default-changing behavior. Existing power users (the MonsterFlow author himself) running autorun overnight on personal-tooling repos will pull the update and find their next overnight run produces unmerged PRs instead of merged work — with no warning, no banner, no migration prompt.

**Fix:** Add three ACs:
- AC: First run after upgrade where resolved policy is `default:pr` AND no project-local sentinel exists → emit a one-time stderr banner explaining the default flip, point at `auto_merge_policy: clean` opt-in, then `touch <project>/.autorun/migrated-v0.11.0` to suppress on subsequent runs.
- AC: CHANGELOG entry under explicit "⚠ BREAKING DEFAULT (v0.11.0)" heading.
- AC: `commands/autorun.md` includes a "Migration" section instructing existing power users on how to preserve pre-v0.11 behavior with one constitution-level setting.

### MF6. `action` enum is inconsistent across Scope, Data, and ACs — pick one closed set
**Source:** req-002 (major), F-2 (minor), DC-2 (minor), scope-IC-3 (minor), stakeholders-003 (major), Codex M3 — **6 sources convergent**.
- Scope says: `pr_only | auto_merged | fell_back`
- Data section says: ts/slug/event/policy/resolved_from/action JSONL with no enum
- AC#13 introduces `pr_fallback_warnings`
- AC#15 introduces `fell_back_validated_to_clean`
- Stakeholders' branch-protection-fallback case adds `fell_back_branch_protection`

**Fix:** Pin closed enum in Data & State: `{pr_only, auto_merged, pr_fallback_warnings, pr_fallback_verdict, pr_fallback_codex_high, pr_fallback_run_degraded, fell_back_validated_to_clean, fell_back_branch_protection, merge_failed}`. Update all ACs to use only these literals. Drop the inline KV-format reference in Scope; align everything to the JSONL shape from Data section.

### MF7. Helper name `extract_frontmatter_key` does not exist — actual is `_gh_frontmatter_field`
**Source:** Codex M1, req-005, A8.
Spec says "reuse existing `_gate_helpers.sh` `extract_frontmatter_key` if present." Actual helper at `scripts/_gate_helpers.sh:49` is `_gh_frontmatter_field` (private-prefixed). /plan and /build will be confused.

**Fix:** Either (a) commit to using `_gh_frontmatter_field` and document its semantics in the spec, or (b) add a public wrapper `extract_frontmatter_key` to `_gate_helpers.sh` and pin its YAML-subset acceptance criteria.

### MF8. AC#17 fresh-`git init` fixture is unrunnable
**Source:** req-004 (major), F-5 (minor).
A fresh `git init` directory has no `gh` remote — `gh pr create` fails before reaching merge-policy code. The fixture verifies the wrong path.

**Fix:** Replace AC#17 with: "Integration test mocks `gh` via PATH-stub (per `feedback_path_stub_over_export_f.md`) returning a fake PR URL. Autorun on a no-policy spec produces `action=pr_only` in run.log AND never invokes `gh pr merge` (verified by stub call recorder)."

---

## Important But Non-Blocking (6 items)

### IB1. VERSION + CHANGELOG bump must be an AC, not an Open Question
**Source:** req-004, A7, DC-4. v0.11.0 bump is in Q3-resolved prose but absent from ACs. Per memory `feedback_auto_bump_changelog_warning`, this is a recurring blocker if not pinned. **Fix:** Add AC#19: VERSION bumps to 0.11.0; CHANGELOG.md `[Unreleased]` converts to `## [0.11.0]` entry under explicit BREAKING-DEFAULT heading.

### IB2. Levenshtein typo-detection is over-scoped for v1
**Source:** A4, F-3, scope-IC-2, gaps-G6 — 4 reviewers convergent. Pure-bash Levenshtein on bash 3.2 is ~40 LoC of footgun for one error message. **Fix:** Drop AC#8's Levenshtein specifics. Replace with: "Unknown frontmatter key emits a stderr warning naming the key; falls through to next-precedence layer." Carve the suggestion to `BACKLOG.md` as `frontmatter-typo-suggestion-helper`.

### IB3. `gate_mode: permissive` + `auto_merge_policy: clean` re-introduces the asymmetric risk
**Source:** A3 (major architectural). Permissive gate_mode demotes major findings to warn; `clean` policy auto-merges on no-warnings. Composition allows a `clean` run under permissive to auto-merge code with class:contract major findings. **Fix:** Add Edge Case explicitly: "If resolved policy is `clean` or `validated` AND resolved gate_mode is `permissive`, emit a stderr warning + run.log entry (`action: clean_under_permissive_warned`) but proceed. Re-evaluate after one month of telemetry."

### IB4. PR lifecycle conventions undefined
**Source:** gaps-G2, A6. With default `pr`, every overnight batch leaves N open PRs. No spec for PR title format, body content, draft-vs-ready state, label, or re-run-with-existing-PR behavior. **Fix:** Add "PR Conventions" subsection: title `[autorun] <slug>`, body includes verdict + followups summary, marked draft if verdict=GO_WITH_FIXES else ready-for-review, label `autorun`. Re-run on same slug force-pushes the existing branch (existing semantics).

### IB5. Branch-protection auto-merge-refusal needs an AC + fixture
**Source:** req-003, stakeholders-003, Codex L2. Spec mentions branch-protection in Edge Cases but no AC verifies the path. MonsterFlow's own repo has branch protection — this is a real path that fires on this very repo. **Fix:** Add AC#20: "Test fixture: spec.md sets `clean`, gates clean, mocked `gh pr merge` returns exit 1 → autorun catches the failure, leaves PR open, run.log records `action=fell_back_branch_protection`, exit 0."

### IB6. Audit row should capture forensic context — commit SHA, PR number, spec SHA
**Source:** gaps-G4 (security-tagged). Current row captures policy/resolved_from/action only. If a regression lands via `clean` auto-merge, post-incident forensics need 'which spec content authorized this merge?' — and spec.md is mutable. **Fix:** Add `pr_number`, `merge_sha`, `spec_sha` to the `merge_policy_resolved` JSONL event.

---

## Observations (5)

- **O1. Scope discipline is otherwise excellent** — out-of-scope section names per-axis merge policy and branch-protection rules as deliberate exclusions with reasoning.
- **O2. Carve-out from sibling spec is clean** — `autorun-merge-policy` owns intent/dispatch; `autorun-runtime-validation-gate` owns the validation signal. No leakage.
- **O3. Helper location should be `scripts/autorun/_merge_policy.sh`** (Codex M2) — not repo-root `scripts/_merge_policy.sh`. Matches existing autorun helper convention; easier on test fixtures that copy the autorun subtree.
- **O4. Naming consideration: `--auto-merge=pr` is semantically awkward** (Codex L1) — "auto-merge to do-not-auto-merge" is confusing. Consider `--merge-policy=<pr|clean|validated>` as the canonical flag, with `--auto-merge=` as a compatibility alias.
- **O5. Codex L3 false-positive** — Codex claimed `autorun-shell-reviewer` agent doesn't exist; in fact `.claude/agents/autorun-shell-reviewer.md` is present. Discount this finding.

---

## Conflicts Resolved

- **req-001 + A1 + A2 + F-1 + gaps-G3 + DC-3 (clean predicate undefined):** all converging on the same gap with slightly different framings — merged into MF1 with the most concrete fix from F-1 (compose with the four-axis gate).
- **req-002 + F-2 + DC-2 + scope-IC-3 + stakeholders-003 + Codex-M3 (action enum):** six different action-enum critiques merged into MF6 with the most complete enumeration.
- **gaps-G5 vs Codex H1 (validated fallback):** both arrive at the same conclusion (`clean` is the wrong fallback target). Codex's framing is sharper because it ties to the spec's own asymmetric-risk argument — used Codex's framing in MF4.
- **stakeholders FAIL vs Claude reviewers' PASS WITH NOTES:** stakeholders' FAIL is correct *given* its scope (silent default flip). The other reviewers focused on internal contract/tech issues and didn't fully weigh the migration angle. Verdict promoted to NO-GO at synthesis level.
- **scope-IC-1 cuts `validated` from v1; Codex H1 changes its fallback:** chose Codex's path (keep `validated` in v1 enum but flip fallback to `pr`). Cutting it entirely loses forward-compat for spec authors writing `validated` today; flipping the fallback solves the safety problem without that loss. scope-IC-1 demoted to acceptable.

---

## Codex Adversarial View (file-grounded against the live repo)

Codex independently verified three blockers against actual files:
1. **`validated → clean` fallback recreates the risk** — same conclusion as Claude reviewers but framed sharpest as a safety default contradiction (MF4 above).
2. **Wrong spec path** — `run.sh:667` exports `SPEC_FILE="$QUEUE_DIR/${SLUG}.spec.md"`; spec assumes `docs/specs/<slug>/spec.md`. Resolver MUST read `$SPEC_FILE` (MF2 above).
3. **Constitution template vs runtime path confusion** — `docs/specs/constitution.md` doesn't exist in this repo; template lives at `templates/constitution.md`; runtime is `<project>/docs/specs/constitution.md` (MF3 above).

Plus 4 Mediums (helper name `_gh_frontmatter_field` not `extract_frontmatter_key`; helper location `scripts/autorun/`; audit format double-spec; morning-report state should include merge-policy resolution) and 2 Lows (flag naming, branch-protection edge-case underspec'd).

Net: Codex's verification against the live repo turns three speculative concerns into hard blockers.

---

Approve to proceed to /plan? (approve / refine <what to change>)
