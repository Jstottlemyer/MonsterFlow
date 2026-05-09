# Spec Review — autorun-merge-policy

**Reviewed:** 2026-05-08
**Reviewers:** ambiguity docs-clarity feasibility gaps requirements scope stakeholders

---

## ambiguity

# Ambiguity Analysis — autorun-merge-policy

## Critical Gaps

1. **"reviewer summary" in PR body is undefined.** AC#15 / Integration both say PR body = "verdict + reviewer summary + spec link + run.log path." What is "reviewer summary"? The merged Phase 0b output verbatim? A bulleted digest? Per-persona? First N lines? Two engineers will implement this three different ways and the PR template will drift across runs.

2. **Banner is "one-line behavior summary" but example shows four lines.** AC#10 says "one-line behavior summary derived from resolved values." The UX example in Approach renders four indented lines (`This run will: open a PR ...`, `Dispatch 6 reviewers ...`, `Permissive findings → followups.`, `Cap retries at 2.`). Pick one — either AC#10 is wrong or the example is wrong. Currently a literal contradiction.

3. **Banner extension mechanism for future specs is unspecified.** Out-of-scope says "future specs extend the banner with their lines" and Q4 says banner "DISPLAYS" knobs from other specs but "doesn't OWN them." But there is no defined plug-in point: do future specs edit `merge_policy_render_banner()` directly? Register lines via a hook table? Append to a shared array? Without this, every future banner-extending spec becomes a merge-conflict magnet on this one function.

4. **`is_clean_for_merge()` function signature missing.** Definitions block gives the predicate logic, but `_merge_policy.sh` is `source`-only and the inputs (`MERGE_CAPABLE`, `CODEX_HIGH_COUNT`, `RUN_DEGRADED`, `VERDICT`, `gate_mode`) are not declared as parameters or named globals. Implementer must guess: are these exported by `run.sh` before the call, or passed as args? This is the load-bearing predicate for the whole spec.

5. **`run.log` row emission timing is ambiguous.** AC#9 implies one JSONL row per slug with both resolution metadata (`policy`, `resolved_from`) and action metadata (`action`, `reason`, `pr_number`, `merge_sha`). Resolution happens at run-start (banner time); action is determined at end-of-run. If emitted only at end, a mid-run crash loses the audit trail. If emitted twice, that breaks the "additive event type" claim. Spec must say which.

## Important Considerations

6. **`resolved_from` enum drift across knobs.** Merge policy uses `cli|spec|constitution|default`. Banner shows `agent_budget: (resolved_from=~/.config/monsterflow)` — a literal path, not an enum. `gate_mode: (resolved_from=<spec|frontmatter|default>)` — `spec` and `frontmatter` mean the same thing here (gate_mode lives in spec frontmatter). Pick one convention; document it; align all four knob lines.

7. **`merge_sha` value for non-merge actions is unstated.** AC#9's example shows `"merge_sha": null` for `pr_only`. The closed-set semantics of "null when action ∉ {auto_merged}" are never written down — only stated for `reason`. Make explicit: `merge_sha` is non-null iff `action == auto_merged`.

8. **`dispatch_validated_merge` semantics.** Approach lists three sub-dispatchers including `dispatch_validated_merge`, but the validated path always falls back to `pr` until the runtime-validation-gate ships. Is `dispatch_validated_merge` just `dispatch_pr_only` plus a stderr warning, or a distinct function reserved for the future? Right now it has no unique behavior.

9. **CLI flag `--auto-merge=pr` and banner suppression.** AC#11 says "silence requires explicitly setting any value (including `auto_merge_policy: pr`)." Does a CLI override of `--auto-merge=pr` suppress the warning line on that run (since `resolved_from=cli`, not `default`)? Implied yes by the predicate "warn iff `resolved_from=default`," but not explicit. Add a sentence.

10. **Re-run with existing PR — closed/merged branch states.** AC#15 says "force-push existing branch (existing autorun semantics)." Edge cases unspecified: what if the PR is *closed but not merged*? What if the PR was *already merged* and the branch was deleted? What if branch exists but no PR? "Existing autorun semantics" is hand-wave; cite the file:line or restate.

11. **Drift detector — what defines "cross-project"?** Approach has `[ -f "$canonical" ] || return 0` so the heuristic is "canonical file absent." But `<project-root>` resolution under cross-project autorun is not pinned in this spec. If `PROJECT_ROOT` is set wrong, the detector silently no-ops on a real drift. State the `PROJECT_ROOT` resolution rule or cite the existing one.

12. **LoC accounting inconsistency.** Integration says new helper is "~120 LoC" with five named functions plus sub-dispatchers, then later says total delta is "~500-700 LoC." 120 LoC for `merge_policy_resolve` + `merge_policy_validate` + `is_clean_for_merge` + `merge_policy_render_banner` + `merge_policy_dispatch` + 3 sub-dispatchers + banner template strings is tight. Not blocking, but tracked estimate will drift.

## Observations

13. **AC#28 "AppleScript-injection check on macOS path"** — this spec introduces no AppleScript. AC is over-broad; recommend "applicable subset of the 13-pitfall checklist" so the subagent doesn't flag absence-of-AppleScript as a finding.

14. **"Permissive findings → followups" in banner** assumes adopter knows the term. Audience says "MonsterFlow contributors and pipeline maintainers," so probably fine, but `commands/autorun.md` should glossary-link the term.

15. **`spec_sha` mutation across re-runs is intentional but undocumented.** If queue file changes between re-runs of the same slug, `spec_sha` changes per row. Probably the desired behavior (forensics-per-attempt). State it once so future readers don't think it's a bug.

16. **`reason` enum has 8 values; AC#9 lists 8** — matches. But the "Definitions" block introducing the enum lists only 7 (`manual_review_requested` is added later in the Data section). Move `manual_review_requested` into the Definitions enum block too so the canonical list is in one place.

17. **Q6 lean-yes** for roster-info-in-banner contradicts the "doesn't own" framing. Fine to defer, but note that the answer to Q6 will retroactively determine the extension mechanism (gap #3).

## Verdict

**PASS WITH NOTES** — spec is high-confidence and implementable, but the banner format contradiction (gap #2), undefined "reviewer summary" (gap #1), missing banner-extension mechanism (gap #3), and `is_clean_for_merge()` signature (gap #4) will cause implementer-level interpretation drift if not pinned before `/plan`.

---

## docs-clarity

# Docs Clarity Review — autorun-merge-policy spec

**Framing note:** this spec is explicitly contributor-facing ("Audience: MonsterFlow contributors and pipeline maintainers"), so the 30-second-stranger test doesn't apply directly to the spec body. I'm reviewing through two lenses: (1) the **adopter-facing artifacts the spec creates** — runtime banner, CHANGELOG breaking-default callout, `commands/autorun.md` guidance, `templates/constitution.md` comment — which DO get the clarity treatment; (2) clarity of the spec itself for a contributor who hasn't been in this conversation.

## Critical Gaps

1. **The runtime banner is the single most adopter-facing artifact this spec ships, and its copy hasn't been clarity-reviewed.** Every autorun user sees it on every run. Specific issues in the example shown (UX section + AC#10):
   - `resolved_from=default` is internal jargon. A sleepy user at 7am parsing log output doesn't know what "resolved_from" means. Plain-language alternative: `(using default — no policy set)`.
   - `Permissive findings → followups` references two pieces of jargon (permissive, followups) without context. A first-time autorun user will not know what a "followup" is or why they should care.
   - `Dispatch 6 reviewers per gate` — "gate" is undefined for adopter audience.
   - The override instructions list THREE places to set the policy but don't tell the reader **which one to choose for their situation**. A first-time reader sees three knobs and freezes.
   - `For gate-by-gate manual review instead, abort and invoke /spec-review interactively` assumes the reader knows what `/spec-review` is and what "gate-by-gate" means. This line is the spec's "escape route for confused users" and it's the most jargon-dense line on the screen.

2. **CHANGELOG "⚠ BREAKING DEFAULT" callout (AC#26) has no acceptance criteria for *content* — only for *structure*.** A breaking-default heading that says "auto-merge default flipped" without telling a user *what they need to do to preserve old behavior* is a 30-second-test failure. AC#26 should require the entry to include: (a) what changed, (b) the literal command/frontmatter line to restore old behavior, (c) link to spec. Otherwise users will land on the CHANGELOG, see "BREAKING," and not know whether they need to act.

3. **No adopter-facing definition of "auto-merge" in `commands/autorun.md` is required by the ACs.** AC#12 says "documents the new key, precedence, CLI flag, banner content, per-run escape hatch, manual-pipeline pointer, and how to silence the banner" — but doesn't require the doc to explain *what auto-merge does in the first place* or *why someone would want one policy vs another*. A new adopter reading the doc will know how to set the knob but not which value to pick. This is a "what is it / why would I install it" failure for the doc this spec ships.

4. **Banner footer mentions `/spec-review` interactively as the manual-review path, but the spec scope explicitly says manual pipeline is out of scope.** A reader following that pointer will hit a cliff — they're told manual is the escape, but the spec doesn't promise manual will keep working as-is, and `commands/autorun.md` won't have a manual-flow walkthrough. Either remove the pointer or add an AC requiring `commands/autorun.md` to link to the manual-flow doc.

## Important Considerations

5. **Acronyms used without expansion** in spec body (acceptable for contributors but worth tightening since the spec will be read by future contributors who don't have today's context): AC, CLI, PR (could mean PR-the-feature or pull-request — context disambiguates but a glossary line would help), CG. The Definitions section is excellent for the *technical* terms (predicates, enums) but doesn't cover the workflow vocabulary.

6. **"Asymmetric-risk reasoning"** appears in Summary and Approach but is never defined inline. A first-time reader has to infer that "silent regression in main is much costlier than morning PR review" *is* the asymmetric-risk argument. The Summary already states this — just label it explicitly: "Asymmetric-risk reasoning: silent regressions are much costlier than..."

7. **`templates/constitution.md` comment line (AC#27) is doing double duty as inline education and is too dense:**
   `# auto_merge_policy: pr  # default; uncomment and set to 'clean' only if you've reviewed the trade-off in commands/autorun.md`
   By the time a user is editing constitution.md they may not have `commands/autorun.md` open. Consider: split into two comment lines — one stating the default, one stating *the actual trade-off in 10 words* (e.g., `# 'clean' auto-merges when gates pass; 'pr' opens a PR for human review`).

8. **The phrase "mode-aware predicate"** is excellent shorthand but appears 6+ times before its first formal definition (which is in Definitions, not at first use). Either move the predicate definition to first mention or add a one-liner gloss the first time it appears in Summary.

9. **Banner says "This run will: open a PR but NOT auto-merge."** The "but NOT" is doing a lot of work — for someone who didn't know auto-merge was ever the default, this sentence is confusing (why is it telling me what it WON'T do?). Plain-language alt: `This run will: open a PR for review. No auto-merge.`

10. **"Forever-until-opt-in"** banner behavior (AC#11) is a strong UX choice but the spec should explicitly justify it once. A contributor reading AC#11 will wonder "is this annoying-by-design or did someone forget to add suppression?" One sentence in Approach naming the choice as deliberate would prevent a future PR adding suppression "to fix the noise."

## Observations

11. **Repetition between Summary, Definitions, Approach, and AC#5** — the mode-aware predicate is restated four times in slightly different phrasings. The Definitions version is the canonical one; consider trimming the others to point at it.

12. **Confidence scores are great**, and the gate_mode/gate_max_recycles frontmatter on the spec itself is a nice eat-your-own-dogfood touch.

13. **Voice is consistent** with project tone — long comma-stitched sentences in body, tight imperatives in AC list. Good.

14. **The spec is unusually well-structured for a behavior-flipping change**, especially the closed-set enums for `action` and `reason` and the explicit forensic fields. This will hold up under future audit.

15. **One leaked-from-development phrase to flag for adopter docs:** "Codex H1" appears in Approach (rejected alternatives). Fine in the spec, but make sure it doesn't leak into `commands/autorun.md` or the CHANGELOG entry — adopters don't know who Codex is or what H1 is.

## The 30-Second Test

The spec is contributor-facing, so the questions reframe to "can a contributor who hasn't been in this conversation understand what to build?":

1. **What is it?** ✓ Summary nails this — "Flip autorun's default merge behavior from 'auto-merge if clean' to 'always open a PR; auto-merge is opt-in per-project.'"
2. **Who is it for?** ✓ Audience and Applies-to lines are explicit and the manual-vs-autorun boundary is named twice.
3. **Why would I build this?** ✓ Asymmetric-risk argument is stated, though never labeled.
4. **What's the first thing to implement?** Partially — the Integration section lists files but doesn't sequence them. A contributor opening this spec doesn't know whether to start with the helper, the resolver, or the banner. Not a Critical Gap because that's `/plan`'s job, but worth noting.

For the **adopter** running into the runtime banner unprepared:
1. What is auto_merge_policy? ✗ The banner doesn't say.
2. Who decides? ✗ The banner shows three override paths but no guidance.
3. Why did this just change? ✓ The "Default flipped in v0.11.0" line covers this.
4. What's the first thing I'd do? ✗ Three options presented, no recommended path.

## Verdict

**PASS WITH NOTES** — the spec is internally rigorous and the technical design is sound, but the four adopter-facing artifacts it ships (banner copy, CHANGELOG breaking-default entry, `commands/autorun.md` guidance, `templates/constitution.md` comment) need explicit clarity ACs requiring plain-language treatment of "what / who / why / what to do" before this lands. The banner especially — it's the highest-impact UX surface in this spec and the example copy is jargon-dense.

---

## feasibility

# Technical Feasibility — Spec Review

## Critical Gaps

**1. Banner depends on resolvers that don't all exist yet.** The runtime-config banner displays four knobs: `auto_merge_policy`, `agent_budget`, `gate_mode`, `gate_max_recycles`. This spec only owns the first one. Spec says it "DISPLAYS but doesn't OWN" the others, but the banner is rendered *by code in this spec's PR*. If `agent_budget` (account-type-agent-scaling) is shipped but `tier_policy` resolution from `dynamic-roster-per-gate` is "forthcoming," the banner code must either (a) fail soft on missing resolvers, or (b) hard-depend on those specs landing first. Spec doesn't pick. Need: explicit "if resolver not present, render line as `<unset>`" rule, or call out the dependency order.

**2. `gate_mode` resolution lifecycle vs. banner timing.** The banner fires "before Phase 0b reviewer dispatch," but `is_clean_for_merge()` reads `gate_mode` and that value comes from spec frontmatter. AC#10 implies `gate_mode` is already resolved at banner-render time. Where is it resolved today, and does the resolved value reach `_merge_policy.sh` via env-var or sourced state? Without a named handoff variable, this is a hidden coupling. Pin: `GATE_MODE` env var, set by `run.sh` immediately after frontmatter parse, consumed by `merge_policy_render_banner` and `is_clean_for_merge`.

**3. `_gh_frontmatter_field` line-number citation is fragile.** Spec pins it to `scripts/_gate_helpers.sh:49`. Line numbers drift on every refactor. Cite by function name only; if behavior matters, lock with a unit test, not a line number. Also: confirm it actually exists today (the persona can't verify; reviewer should grep) and that it handles the cases this spec needs — comments after value, quoted strings, missing key vs. empty key. The drift detector relies on `_gh_frontmatter_field` returning empty for both "key missing" and "key present but empty," which makes the warn message in §Approach ambiguous when canonical has the key absent and queue has it absent — both render as `""` in the warning string.

## Important Considerations

**4. `spec_sha` via `git hash-object` assumes git context.** `queue/<slug>.spec.md` lives under `queue/`, which is gitignored in MonsterFlow but the working tree is still inside the repo, so `git hash-object` works on any path. But for cross-project autorun runs (different repo's queue dir), `git hash-object` may run outside the project's git repo. `git hash-object` actually works without a repo (it computes the hash of file content), so OK — but confirm with `git hash-object --no-filters` to avoid CRLF surprises on macOS, and capture stderr in case the call fails.

**5. `action=fell_back, reason=manual_review_requested` under `pr` policy is semantically odd.** `fell_back` means "intended to merge but did not." Under `auto_merge_policy: pr`, there was no merge intent to fall back from. AC#14 says "regardless of resolved policy," which papers over the inconsistency. Two options: (a) under `pr` policy, touch file is a no-op and emits `action=pr_only` with a separate `manual_review_acknowledged: true` field; (b) accept the slight semantic stretch and document it. Either is fine; pick one.

**6. Touch-file race window.** `.manual-review` is checked "once before merge dispatch." If user creates it during gate execution (10–30 min runs), it's caught. If user creates it *after* `gh pr merge` is invoked but before `gh pr merge --auto` queues the merge, it's not. AC#14 should explicitly say: "checked immediately before `merge_policy_dispatch`; no protection after that point." Otherwise users will expect it to be a kill switch.

**7. Closed `reason` enum may need an extension hatch.** Eight values today, all reasonable. But future merge-policy variants (e.g., `validated` once it ships will add new fail modes) will need new enum values. Either document the extension contract ("new reason values are non-breaking; readers MUST tolerate unknown values") or accept the coupling.

**8. PR conventions: `gh pr create` body assembly is unchanged?** AC#15 specifies title/body/draft/label, but doesn't say whether the existing PR-body construction code is reused or replaced. If `merge_policy_dispatch` now owns PR creation under the `pr` policy path, the existing PR-body assembly code path needs to be lifted into the helper or shared. Spec should name which.

**9. Banner LoC + 9 fixtures inflate from "minimal"  to a real test surface.** The original ~250–400 LoC estimate became ~500–700. With banner rendering, drift detector, escape hatch, and 9 fixtures, this is firmly mid-size. The `autorun-shell-reviewer` subagent must run pre-commit per repo CLAUDE.md (AC#28) — confirmed feasible, but the parallel-/build memory note (`feedback_build_subagent_invocations_must_fire`) means orchestrator wiring must be explicit, not assumed.

**10. `gh pr merge --squash --auto` vs. `--admin` for owner runs.** Memory `feedback_branch_protection_external_prs` notes default merge path is `--auto` (queue) not `--admin` (bypass). Spec doesn't say which `merge_policy_dispatch` uses. Under `clean` policy, the user explicitly opted in to auto-merge — `--auto` is right (respects branch protection). Pin this.

## Observations

**11. Drift detector only compares the merge-policy line.** Reasonable v1 scope. Worth noting in commands/autorun.md so users don't expect general drift detection.

**12. Bash 3.2 compat looks clean.** Single-bracket tests, no `${array[-1]}`, no `export -f`, PATH-stub for `gh`. Good.

**13. JSONL additive event type — readers must tolerate unknown events.** `persona-metrics-validator` is named (AC#29) but `dashboard/` consumers and any other run.log readers should be enumerated and confirmed. One grep for `run.log` consumers would close this.

**14. `validated` falling back to `pr` (not `clean`) is the right call.** Codex H1 was right; spec correctly closes the "silent severity-creep" hole.

**15. Banner forever-until-opt-in is a deliberate UX choice.** The `feedback_missed_instructions` memory pattern says hard requirements need confirmation; the banner is essentially a permanent confirmation prompt for an unset default. Acceptable, but be ready for adopter friction — a single low-noise warn line is cheap to ignore, but make sure the line isn't buried under reviewer dispatch noise.

**16. Cross-project canonical-missing case.** Drift detector silent-skips when `<project>/docs/specs/<slug>/spec.md` is absent. Right call.

## Verdict

**PASS WITH NOTES** — the policy semantics, predicate composition, and audit shape are sound; remaining work is plumbing (banner-resolver coupling, named env-var handoffs, and one minor enum-vs-action consistency choice) rather than architecture.

---

## gaps

# Missing Requirements — Review of autorun-merge-policy spec

## Critical Gaps

**C1. Authorization for `.manual-review` touch file unspecified.** AC#14 makes presence of `queue/<slug>/.manual-review` force a merge skip, but the spec never says *who* can create this file or under what trust model. In overnight autorun, the queue dir is writable by any process running as the user; if a build-phase agent (or a malicious dependency in a sandboxed step) writes that file, it silently downgrades the merge policy. Specify: who creates it, when it gets cleaned up, and whether re-runs of the same slug should clear stale touch files. Without lifecycle, this becomes a latent "stuck PR" mode.

**C2. Concurrent re-run race on touch file + force-push.** Edges note "re-run with existing open PR: force-push existing branch" and "touch file checked once per run (no race)" — but two autorun invocations on the same slug (overnight cron + manual kickoff) both force-push the branch and both read/write run.log. There's no lock file, no PID guard, no run.log append-atomicity statement. Specify whether concurrent runs on the same slug are forbidden (and how that's enforced) or supported (and how interleaving is reasoned about).

**C3. `spec_sha` collection point ambiguous when queue file doesn't yet exist.** Definitions say `spec_sha = git hash-object queue/<slug>.spec.md` taken once at run start — but `autorun-batch.sh` *creates* the queue copy. If `run.sh` is invoked directly (without batch), does it expect the queue copy to exist? What if the user runs `run.sh` against `docs/specs/<slug>/spec.md` and there is no queue copy? AC#9 requires `spec_sha` non-null; the path through `run.sh` standalone needs spelling out.

**C4. run.log atomicity / corruption recovery unspecified.** New JSONL event type `merge_policy_resolved` is appended to `queue/run.log`. Spec says "additive event type, no breaks to existing readers" but doesn't specify: (a) is append atomic on macOS APFS for lines < PIPE_BUF? (b) what does `persona-metrics-validator` do if it sees a partially-written line from a crashed run? (c) is run.log rotated, truncated, or unbounded? AC#29 only verifies the validator passes on a *clean* fixture — not a crash-mid-write fixture.

**C5. PR re-open / closed-PR-with-same-branch semantics undefined.** "Re-run with existing open PR: force-push existing branch" — but what if the prior PR was *closed* (not merged)? Force-pushing reopens? Creates a new PR? GitHub-side behavior here is non-obvious and varies with the `gh` version. Pin it.

## Important Considerations

**I1. Branch-protection detection is regex-fragile.** AC#19 distinguishes `reason=branch_protection` from `merge_call_failed`, but the spec doesn't say *how* the dispatcher tells them apart. `gh pr merge` returns the same exit code for both; you'd have to grep stderr for protection-shaped strings, which drifts across `gh` versions. Either (a) accept a single `merge_call_failed` reason and drop `branch_protection`, or (b) document the detection regex + version pin.

**I2. No audit trail when banner is silenced.** Once user adds `auto_merge_policy: pr` (explicit), banner stops warning. But if a future contributor *removes* that line, banner returns. There's no record in run.log distinguishing "explicit pr" from "default pr" beyond `resolved_from` — which is good — but the rendered banner text isn't captured anywhere in run.log. If a user later asks "what did autorun tell me on the run that merged X," there's no replay. Suggest archiving the banner text to a `banner` field on the resolved event.

**I3. Cross-project queue case under-specified.** Drift detector silently skips when `<project>/docs/specs/<slug>/spec.md` doesn't exist. But what does this *mean* operationally? Does autorun support running against a queue file that has no canonical home (e.g., `gh issue` → spec extraction)? If yes, it deserves a paragraph in commands/autorun.md so users know the canonical-edit workflow doesn't apply. If no, the drift detector should warn instead of silent-skip.

**I4. Migration: how do existing in-flight queues behave?** A user with `queue/foo.spec.md` already populated under v0.10.x runs `git pull` → v0.11.0. On next `run.sh foo`, `auto_merge_policy` is absent → falls to default `pr`. Is this the intended migration path? It silently flips behavior on in-flight work. Specify: do we recommend draining the queue before upgrading, or is silent-flip-to-safer-default acceptable? (Probably acceptable — it's the safer direction — but say so.)

**I5. Banner warning fatigue.** "Fires forever-until-opt-in, no sentinel suppression" is principled, but for a daily-autorun user who deliberately wants the default, the banner becomes noise that trains them to ignore output. Consider explicitly documenting that `auto_merge_policy: pr` is a valid opt-in (AC#11 mentions this) — and add a one-liner to the banner itself: "to silence: set auto_merge_policy: pr explicitly."

**I6. Test for `agent_budget` / `gate_mode` banner display.** AC#10 requires the banner display all 4 knobs with `resolved_from`, but the test fixtures (AC#16-24) only assert merge-policy behavior. Add a banner-rendering test that asserts all 4 lines present + correct `resolved_from` annotations. Otherwise a future refactor breaks the multi-knob display silently.

**I7. `--auto-merge` flag at `autorun-batch.sh` is uniformly applied — but what about per-slug overrides at batch level?** Out-of-scope is fine, but call out: "batch-level CLI applies to every slug in the batch; per-slug override requires separate run.sh invocation." Otherwise users will assume `--auto-merge=clean` on batch only flips the slugs whose specs allow it.

**I8. PR body content is summarized but not pinned.** AC#15 says "Body: verdict + reviewer summary + spec link + run.log path" — but reviewer-summary content can be huge (multi-persona dump). Is there a length cap? A truncation rule? GitHub PR bodies have a ~65KB limit. Either pin a max-length convention or explicitly defer to a follow-up.

## Observations

**O1. Locale / timestamp format.** `ts` field uses ISO-8601 UTC ("2026-05-08T22:34:11Z") — good. Worth noting in the schema that all timestamps are UTC, so cross-machine audit aggregation works.

**O2. `merge_sha` for `pr_only` action.** The example row has `merge_sha: null` for `action=pr_only` — correct. Worth adding to AC#9 explicitly: "merge_sha is null when action != auto_merged."

**O3. Asymmetric-risk framing is strong.** The Summary's "silent regression in main is much costlier than morning PR review" framing is well-pitched — keep it in the CHANGELOG breaking-default callout verbatim if possible.

**O4. Helper LoC estimate may be light.** `_merge_policy.sh` at ~120 LoC for: resolve + validate + predicate + banner + dispatch + 3 sub-dispatchers + drift detector + escape-hatch + log emit. Estimate is closer to 200-250. Not a blocker; just don't get pinched if implementation runs over.

**O5. Memory citations are well-applied.** AC#25 (PATH-stub), AC#26 (CHANGELOG bump), and the bash-3.2 considerations all reflect lessons-learned. Good signal.

**O6. `validated` policy is documented but inert.** Worth a one-line note in commands/autorun.md: "v0.11.0 ships `validated` as a forward-compat value that gracefully falls back to `pr`. Set it now if you want zero-config upgrade behavior when `autorun-runtime-validation-gate` ships."

**O7. Accessibility / i18n / mobile not applicable.** This is a CLI/shell feature with no UI surface; standard i18n/a11y checklist items don't apply. Stderr messages are English-only (matches MonsterFlow convention).

## Verdict

**PASS WITH NOTES** — The spec is thorough and the asymmetric-risk argument is sound. The critical gaps are operational (touch-file authorization, concurrent-run race, run.log atomicity, branch-protection detection) rather than design — addressable inline before /plan without a full re-spec.

---

## requirements

# Requirements Completeness — Spec Review

## Critical Gaps

1. **AC#11 "fires forever-until-opt-in" is not testable as written.** The fixture set covers "fires once on a default-resolved run" but does not exercise the multi-run / non-suppression invariant. Either add an AC like "AC#11.1: two consecutive runs with `resolved_from=default` both emit the banner; no sentinel file is created in `~/.claude/`, `queue/`, or project root between them" or weaken AC#11 to the single-run claim.

2. **Banner output stream is unspecified.** AC#10 and the UX section show banner text but never pin whether it lands on stdout or stderr. This matters for CI log capture, for `grep`-based test assertions, and for the warning-line semantics (warnings conventionally go to stderr; the rest of the banner is informational, conventionally stdout). Pin: "banner is emitted to stderr in its entirety; the warn line is not stylistically distinguished from informational lines beyond the leading `⚠`."

3. **`merge_policy_resolved` event emission cardinality is unstated.** Spec says "audit row written … per slug" but never says *exactly once per slug*. Re-tries, recycles, and the `gate_max_recycles: 2` loop create real ambiguity — does the event fire once at resolve-time, once at merge-dispatch-time, or once per recycle? Pin: "emitted exactly once per slug, at merge-dispatch site (after final verdict), regardless of recycle count."

4. **Resolver behavior on missing `$SPEC_FILE` is undefined.** `merge_policy_resolve` is documented assuming the queue file exists. If `queue/<slug>.spec.md` is absent (cross-project, hand-queued failure, race with cleanup), `_gh_frontmatter_field` returns empty and the resolver silently falls through to constitution → default. This is probably correct, but should be an explicit AC + fixture so a future refactor doesn't accidentally `exit 2` on missing file.

5. **`.manual-review` race window is not pinned.** AC#14 says "presence … at merge-dispatch time forces skip-merge." If a user touches the file mid-run (after Phase 0b but before merge dispatch), is that honored? Spec implies yes ("checked once per run") but the UX example shows `touch` *before* invocation. Pin the contract: "checked at merge-dispatch site only; pre-existing or mid-run creation both honored; deletion mid-run does not un-skip."

## Important Considerations

6. **No performance budget on banner + drift detector.** Each adds at minimum one frontmatter parse (~10–50ms on bash 3.2 with shell-based YAML extraction). For autorun-batch over 20 slugs that's ~1s of pure overhead. Likely fine, but unstated. Consider adding "banner + drift check together add <100ms per slug on macOS bash 3.2" as a non-blocking target.

7. **Rollback story for the default flip is implicit.** v0.11.0 flips the default; if a downstream user has 50 specs running on autorun nightly and the new default breaks their morning workflow, the documented escape is "set `auto_merge_policy: clean` in `<project>/docs/specs/constitution.md`". Make this explicit in the CHANGELOG breaking-default callout per AC#26 — name the one-line constitution opt-out as the official "preserve v0.10 behavior" path.

8. **`spec_sha` forensic field has no consumer named.** AC#9 captures it but no AC verifies anyone reads it. If it's purely for post-hoc forensic grep, fine — say so. Otherwise wire a "given two run.log rows for the same slug with different `spec_sha`, audit query X works" AC, or remove the field and reduce schema surface.

9. **Banner override-instruction footer is content-fragile.** The UX example shows four bullets ("To override this run / per-spec / project-wide / abort and invoke /spec-review"). AC#10 says "override-instruction footer + manual-pipeline pointer" but doesn't pin the exact strings. A test that greps banner output for these literals will lock the wording — either the spec pins exact strings (and tests grep them) or AC#10 is loosened to "footer mentions: per-run CLI flag, per-spec frontmatter, project-wide constitution, manual-pipeline option."

10. **Drift detector failure mode on parse error is unspecified.** If `_gh_frontmatter_field` errors out (malformed YAML in canonical or queue), drift detector currently swallows via `|| echo ""` and would warn `auto_merge_policy=` mismatch — noisy false positive. Either add: "drift detector treats parse-error from either side as silent-skip" or "parse-error becomes a louder dedicated warning."

11. **Codex-absent semantics carry asymmetric-risk.** The "vacuously satisfies CODEX_HIGH_COUNT == 0" rule is documented, but means a network blip during a `clean`-policy run can auto-merge code that Codex would have flagged. This is the existing autorun convention, but given this spec's stated asymmetric-risk thesis ("silent regression in main is much costlier than morning PR review"), worth either an explicit AC pinning the existing behavior OR a callout: "future spec `autorun-codex-required` may tighten this; v0.11.0 preserves status quo."

12. **`gate_max_recycles` interaction with policy is unaddressed.** If gates recycle and the verdict changes between recycle-1 (NO_GO) and recycle-2 (GO), which verdict feeds the predicate? Implied: final. Pin: "predicate evaluated on terminal verdict only; intermediate recycle verdicts do not trigger merge dispatch."

## Observations

13. **AC#28 (autorun-shell-reviewer "passes clean review") is subjective.** Reviewer findings are High/Medium/Low; "clean" is undefined. Suggest: "AC#28: zero High findings; Medium findings either resolved or annotated in PR description with rationale."

14. **The 7-finding `reason` enum grew to 8 (manual_review_requested) mid-spec.** AC#9 names the 8-value set but the **Definitions** section header still says "7 values." Cosmetic — fix the header to "8 values" or use "closed set, current values:" framing.

15. **Test count claim drift.** Scope says "9 test fixtures + 1 schema-validation test" but ACs #16–24 enumerate 9 test fixtures and #25 (PATH-stub migration) is a 10th, plus #26–29 implicitly need fixture coverage. Either bump the count to "13+ fixtures" or reclassify the validation/audit/subagent-contract ACs as not-fixture-backed.

16. **Banner extension contract is informal.** Q4-resolution and Scope both say "future specs extend the banner with their lines" but no ABI is pinned (line ordering, alignment column, source field naming). A one-paragraph banner-extension contract would prevent future specs from each inventing their own format.

17. **No test for the `--auto-merge` flag on `autorun-batch.sh` propagating to per-slug runs.** AC#2 says both scripts accept the flag; no fixture verifies the multi-slug propagation case (batch sets `clean`, slug-1's spec.md says `pr`, expected: CLI wins for both).

18. **"QA could write test plan from spec alone" check: passes with caveats.** Definitions block, predicate pseudocode, and ACs are tight enough that an outside engineer could draft most fixtures unaided. The fragility lives in banner exact-wording (item 9) and emission cardinality (item 3).

## Verdict

**PASS WITH NOTES** — requirements are largely complete and testable; the critical gaps are emission-cardinality, banner-stream, and forever-until-opt-in test coverage, all of which can be closed inline without re-architecting the spec.

---

## scope

# Scope Analysis Review — Autorun Merge Policy Spec

## Critical Gaps

**Banner ownership / cross-spec contract is ambiguous**
- `class: contract`, `severity: major`
- The runtime-config banner displays 4 knobs but this spec only OWNS 1 (`auto_merge_policy`). The other 3 (`agent_budget`, `gate_mode`, `gate_max_recycles`) belong to `account-type-agent-scaling`, the gate-mode work, and an unspecified recycles owner. Spec does not pin: **how** does `merge_policy_render_banner()` discover their resolved values? Is there a shared resolver contract? An env-var convention? A sourced helper per knob?
- Without that contract, the banner either (a) duplicates resolution logic that lives in those other specs, or (b) reaches into their internals — both are coupling that will break the next time one of them ships.
- **Suggested fix:** declare the banner discovery contract explicitly — e.g., "each owning spec exposes a `<knob>_resolve()` function in a sourced helper; banner sources them and calls each; missing function → display `unknown`." Or reduce v1 banner scope to merge-policy-only and let future specs append their own lines. Either is fine; *not* picking one is the gap.

**MVP cut-line is not declared**
- `class: scope-cuts`, `severity: major`
- Spec acknowledges scope expanded from ~250-400 LoC to ~500-700 LoC and adds 9 fixtures, but does not say **what gets cut if implementation hits the 3-attempt /build budget**. The load-bearing safety win is: default flip + frontmatter key + audit row + CHANGELOG. Everything else (banner, drift detector, `.manual-review` hatch, `validated` fallback) is additive polish.
- Per memory `feedback_slice_strategy_for_autorun_build`, specs that approach this size benefit from an explicit slice plan.
- **Suggested fix:** add a "Phasing" sub-section under Scope: "If /build cannot land all 29 ACs in 3 attempts, ship Slice A (default flip + frontmatter + audit row + CHANGELOG = ACs 1-9, 26-28) first; Slice B (banner = ACs 10-12) and Slice C (drift detector + escape hatch + `validated` fallback = ACs 13-14, 6, 21, 23-24) follow." Names the cut order in advance instead of discovering it under pressure.

## Important Considerations

**Drift detector is scope creep into queue-integrity territory**
- `class: scope-cuts`, `severity: minor`
- The detector compares `auto_merge_policy` between canonical and queue copy — but if queue copies *can* drift from canonicals, that's a queue-population problem affecting **every** frontmatter field, not just merge policy. Solving it for one field is a per-spec patch on a platform-level issue.
- **Suggested fix:** either (a) carve to BACKLOG as `queue-canonical-drift-detector` covering all frontmatter fields, or (b) keep but note explicitly: "v1 detects only `auto_merge_policy`; full-frontmatter drift is BACKLOG."

**`.manual-review` touch file is speculative**
- `class: scope-cuts`, `severity: minor`
- No user has asked for this. The use-case ("I want to review this one slug manually even though my project default is `clean`") is solvable today by `--auto-merge=pr` on the CLI. Adding a touch-file mechanism creates a second escape hatch and an 8th `reason` enum value before anyone has hit the need.
- **Suggested fix:** defer to follow-up; cite asymmetric-risk reasoning consistently — if `pr` is the default, the per-run override needed is "force clean for this run" (already covered by CLI `--auto-merge=clean`), not "force pr for this run" (vacuous when default is already `pr`).

**Banner-no-suppression has a hidden UX cost**
- `class: documentation`, `severity: minor`
- "Fires forever-until-opt-in" is defensible for a one-time safety nudge, but the banner shows 4 lines every run *forever* even after the user opts in (they only silence the default-warning, not the banner). On shared CI or for users running 10 autoruns/day, that's noise.
- **Suggested fix:** clarify in `commands/autorun.md` (AC#12) that opting in silences only the warning, not the banner itself; if banner-quiet mode is desired, that's a future spec. Or add a single-line `--quiet-banner` flag now to head off the inevitable ask.

**Inevitable day-after-launch asks not surfaced**
- `class: scope-cuts`, `severity: minor`
- Once default is PR-with-no-auto-merge, users running batched autoruns will accumulate unmerged PRs. Predictable follow-up requests:
  - "Notify me when an autorun PR opens" (Slack/email/desktop)
  - "Bulk-merge all green autorun PRs" helper
  - "Auto-merge after N human approvals within T hours"
- None are blockers for this spec, but worth noting in a "Follow-ups likely" section so they're tracked rather than rediscovered.

## Observations

- Out-of-scope section is unusually thorough (10 explicit exclusions with rationale) — good defensive scoping; this is the right pattern.
- Q1-Q5 are cleanly resolved with rationale embedded; Q6 properly defers to `pipeline-autorun-final-status-render`. Open Questions section is doing real work.
- 29 ACs is on the high end; some could be combined without losing precision (e.g., AC#16-24 are all test-fixture entries that read like a fixture matrix, not 9 separate ACs).
- AC#10-11 split banner-content from banner-firing-frequency — that's good, those are separate failure modes.
- VERSION + CHANGELOG handled as a coded AC (#26) per memory `feedback_auto_bump_changelog_warning` — properly defensive.
- `autorun-shell-reviewer` invocation pre-commit (AC#28) per memory `feedback_build_subagent_invocations_must_fire` — correctly wired.
- The mode-aware predicate (Definitions section) is the load-bearing technical move and is precisely specified — strong.

## Verdict

**PASS WITH NOTES** — scope is well-bounded and the safety win is real, but the spec needs an explicit MVP slice plan and a banner-discovery contract before /plan can produce a coherent build sequence; everything else is polish-grade.

---

## stakeholders

# Stakeholder Analysis Review — autorun-merge-policy spec

## Critical Gaps

**1. Upgrade-time notification path is undefined (Adopters / install.sh users)** — `class: documentation`, `severity: major`. The spec is a behavior-changing default flip shipped via `install.sh` to adopter projects. The runtime-config banner fires at autorun *run-time*, but adopters who upgrade MonsterFlow and don't run autorun for a week won't see the warning until then. Spec says `docs/index.html` "no further change required" (Integration §) — disagree from a stakeholder POV: the *headline* autorun behavior is changing. Either (a) `install.sh` prints a one-time post-install notice when version crosses 0.10.x → 0.11.0, or (b) `docs/index.html` and CHANGELOG `### ⚠ BREAKING DEFAULT` are explicitly named as the adopter-notification surface in Integration §. Pick one and pin it.

**2. Banner spam in autorun-batch.sh runs (Justin, primary user)** — `class: contract`, `severity: major`. AC#11 says banner fires "every run where `resolved_from=default`." For `autorun-batch.sh my-feat-1 my-feat-2 my-feat-3 my-feat-4 my-feat-5` on a fresh adopter project with no policy set, that's 5 identical default-warning banners interleaved with reviewer output. Either (a) AC clarifies banner is per-slug (current text is ambiguous; "every run" could mean "every batch invocation"), or (b) batch wrapper de-duplicates the default-warning line to once-per-batch while still printing the resolved-knob lines per-slug. Worth pinning before /plan.

## Important Considerations

**3. Future-banner-extension contract is implicit (Future spec authors)** — `class: documentation`, `severity: minor`. Spec says future specs (`agent_count`, `tier_policy`) "extend the banner with their own lines" and "decide their own warn behavior" (Out of scope §). Without a documented contract — line format, warn-eligibility rules, ordering — each future spec re-derives from first principles and the banner drifts. Add a 5-line "banner extension contract" subsection to Integration §: line shape `<key>: <value> (resolved_from=<source>)`, warn-eligibility owned by the extending spec, ordering matches resolution-precedence-source layering.

**4. Per-run escape hatch discoverability is low (Justin, debugging mode)** — `class: documentation`, `severity: minor`. `queue/<slug>/.manual-review` touch file is documented in `commands/autorun.md` (AC#12) but the UX flow shows `touch queue/my-feature/.manual-review` directly. First-time use during a 2 AM debugging session is unlikely without a CLI affordance. Consider whether `scripts/autorun/run.sh --skip-merge=<slug>` is a follow-up backlog item, or whether the touch-file is genuinely the right grain. Not a blocker; flag for /plan to size.

**5. `validated` advertises an unbuilt feature (Documentation consumers, Adopters)** — `class: documentation`, `severity: minor`. `commands/autorun.md` will list `validated` as a valid value (AC#1, AC#2) before the runtime-validation gate ships. New adopters reading the docs will reasonably try `validated`, get the `validated_fallback` warning per-run, and wonder if their config is broken. Doc copy must explicitly mark `validated` as "forward-looking; falls back to `pr` until autorun-runtime-validation-gate ships." AC#12 should reference this requirement.

**6. Cross-project queue stakeholders absent (Downstream projects)** — `class: scope-cuts`, `severity: minor`. Spec mentions "cross-project queue (no canonical at `<project>/docs/specs/<slug>/spec.md`): drift detector silently skips" (Edge Cases). But cross-project autorun runs are exactly where silent regression-in-main is *most* costly (Justin's day-job projects vs MonsterFlow itself). Consider whether cross-project runs should default-deny `clean` policy entirely until canonical-resolution is wired, or at minimum log a higher-severity audit row. Not a blocker; surface for /plan judgment.

## Observations

**7. `autorun-shell-reviewer` subagent gets new file** — AC#28 covers it. Stakeholder is represented.

**8. `persona-metrics-validator` subagent unaffected** — AC#29 verifies. Stakeholder is represented.

**9. PR reviewers = Justin** — Asymmetric-risk argument is sound; morning PR review is cheap relative to silent main regression. Stakeholder need is met by the default flip itself.

**10. Constitution template drift risk** — Memory `project_workflow_install_drift` notes some workflow-repo template files may not be symlinked into adopter projects. AC#27 ships `templates/constitution.md` change but doesn't verify install.sh actually delivers it. Worth a /plan-time check that the template path is part of install.sh's copy set.

## Verdict

**PASS WITH NOTES** — stakeholder coverage is solid for the primary user (Justin) and audit/forensics consumers; gaps are around upgrade-notification path (Critical #1), batch banner spam (Critical #2), and the implicit future-banner-extension contract (Important #3). All three are addressable inline at /plan without spec rework.

