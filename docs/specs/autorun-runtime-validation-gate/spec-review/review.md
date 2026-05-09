# Spec Review — autorun-runtime-validation-gate

**Reviewed:** 2026-05-09
**Reviewers:** ambiguity docs-clarity feasibility gaps requirements scope stakeholders

---

## ambiguity

# Ambiguity Analysis — autorun-runtime-validation-gate (Revision 2)

## Critical Gaps

1. **SF4 contradicts T4.** SF4 (Scope cuts) defers "PID file machinery" — `setsid + trap-EXIT only` for v1. But T4 fixture explicitly tests `queue/.runtime-pids` PID-sweep + truncation. Either keep the PID file or cut the test; spec ships incoherent.

2. **Status enum drift between Definitions and JSON schema.** Definitions section adds `skipped_external_author` as a fifth status value. The `schemas/runtime-validation.schema.json` block in Data & State still lists `["pass","fail","skipped","error"]`. Same gap for `details.runtime_status` enum extension. Two engineers would implement two different validators.

3. **iOS default timeout: 5 min or 15 min?** AC#8 says "5-min default per target." R1 says "bump iOS-specific default `timeout_seconds` to 900s … baked-in default." These are mutually exclusive. Spec must state per-target defaults table (web=300, cli=300, ios=900) and update AC#8 wording.

4. **Screenshot attachment policy is stated three times, three different ways.**
   - Trust Model: "screenshots opt-in via `attach_screenshots: true` (default off)"
   - AC#16: PR body unconditionally "links to log + sidecar + screenshot (if web/ios)"
   - SF2: "base64-embedded screenshot thumbnail" (chosen variant)
   Resolve to one rule + define `attach_screenshots` field on the schema (currently absent).

5. **External-author predicate logic is internally inconsistent.** Trust Model: skip when "no `.github/CODEOWNERS` exists" (an OR branch). AC#37: "when CODEOWNERS exists AND most-recent commit … non-CODEOWNERS → skipped." AC#37 doesn't cover the no-CODEOWNERS case at all. Pick one: (a) no CODEOWNERS = skip everything (fail-closed), (b) no CODEOWNERS = run everything (fail-open). Currently both are implied in different sections.

6. **"CODEOWNERS-listed user" identity matching is undefined.** GitHub login? git committer email? git author? Signed-by trailer? GH API lookup? The whole external-PR defense rests on this predicate; it must be pinned. Edge: maintainer commits via secondary email not in CODEOWNERS → flagged external.

7. **`autorun-stamp.json` is undefined.** F6 introduces it as the replacement for the in-body autorun-stamp directive, but spec gives no schema, no write timing, no reader. AC says "stamp emission verified by file existence + JSON shape" — what shape?

## Important Considerations

8. **TOFU display flow gap.** UX shows `Display full content? [y/n]` then `Trust this validator? [y/N]`. F8 says "no answer `n` to display then `y` to trust path." What does `n` to display do — reject? Re-prompt? Spec doesn't say.

9. **"Local hosts" matcher is mixed regex+glob.** `localhost\|127.0.0.1\|::1\|*.test\|*.localhost` — is this anchored regex, alternation, DNS-suffix match, or shell glob? `0.0.0.0`, `[::]`, hostname containing `localhost` as substring all underspecified.

10. **`queue/.runtime-pids` writer never described.** T4 asserts behavior on this file but no section in Approach/Integration mentions creating it. (Compounds Critical #1.)

11. **iOS "non-empty screenshot" check after SF1.** New rule: "file > 0 bytes AND not all-black via 50-pixel sample." Sample location? Random seed? Deterministic coords? RGB threshold for "black"?

12. **Console error allowlist match semantics undefined.** Example looks like substring; spec never says substring vs regex vs glob.

13. **`expected_stdout_contains` regex flavor undefined.** POSIX BRE? ERE? Python `re`? Perl? Anchored? Multiline?

14. **`xcodeproj` walk-up rules.** "From spec or by walking up to find a `.xcodeproj`" — walk-up from `$PWD`? Spec dir? Repo root? Behavior on multiple matches?

15. **Kill-switch + non-validated policy interaction.** `AUTORUN_DISABLE_RUNTIME_VALIDATION=1` with `auto_merge_policy: pr` — does run.log still record `kill_switch: true`? R2 only describes the `validated` case.

16. **AC#16 trigger condition.** C3 in Revision 2 pins it to `(non-pass AND auto_merge_policy: validated)`, but AC#16's own text and the Scope/UX prose still say "when validated fails (validator non-pass)" without the explicit conjunction. Update wording everywhere for parity.

17. **`scripts/_validate_runtime_validation_sidecar.py` language choice.** Spec is otherwise shell-first ("Python validators … rejected — adds a dependency layer"). One Python validator alone in `scripts/` deserves an explicit "why this one is OK" sentence, or move to shell.

18. **`approved_by: "tty:user@host"` string format.** What produces it — `$USER@$(hostname)`? `id -un`? `whoami`? Pin the helper.

19. **External `target_url` scheme allowlist.** Only `http(s)`? `file://`? `ws://`? Currently silent.

## Observations

20. `gate_mode: permissive` + `gate_max_recycles: 2` frontmatter keys assume reader knows autorun-overnight-policy v6 semantics — cross-link in body would help future readers.
21. `is_clean_for_merge()` predicate is borrowed from autorun-merge-policy without a definition stub here; reader of this spec alone can't fully evaluate AC#10.
22. AC#33 mentions "AppleScript-injection check on macOS path" — confirm any of `web.sh`/`ios.sh`/`cli.sh` actually invokes `osascript`; otherwise this is a leftover from the reviewer's generic checklist.
23. `wait_for_selector` default `body` — fine, but pin: does that mean playwright's default-load behavior, or an explicit `page.waitForSelector('body')` call?
24. Confidence math reconciles cleanly (sum/6 = 0.945) — no arithmetic gap.

## Verdict

**PASS WITH NOTES** — Revision 2 closes the structural security blockers cleanly via the external-author skip; remaining ambiguities are all narrow contract/wording gaps that won't reshape the architecture, but Critical Gaps 1–7 will produce divergent implementations or fixture failures if not resolved before /plan freezes.

---

## docs-clarity

# Docs Clarity Review — autorun-runtime-validation-gate

**Frame:** This is a contributor-facing spec, not adopter-facing copy (per `Audience` line). The four-question test adapts: instead of "first command I'd run" the question becomes "first thing I'd do to ship/consume this." I'm reading as a MonsterFlow contributor seeing this spec cold.

## Critical Gaps

1. **Forward-reference codes are unresolvable from this document alone.** The Revision 2 appendix cites `F1-F9`, `C1-C4`, `T1-T4`, `S1-S3`, `R1-R3`, `SF1-SF6`, `D4`, `D8`, `D10`, `D11`, `D16`, `D18`, `D19`, `D23`, and `Codex H1`. None are defined inline; all live in `check.md` / `plan.md` / sibling spec sessions. A contributor opening this spec for the first time hits "F2 (external-PR provenance → unattended RCE) is the parent finding" without prior context — they have to chase `docs/specs/autorun-runtime-validation-gate/check.md` to decode it. **Fix:** prefix the appendix with a one-sentence pointer ("Codes F#/C#/T#/S#/R#/SF# refer to findings in `check.md`; D# refers to plan decisions") OR inline the finding title on first use (e.g., "F2 — *external-PR provenance allows unattended RCE on maintainer's host* — is the parent finding").

2. **The "first action a contributor takes" is unstated.** Summary tells me what the gate does and that it's opt-in via frontmatter, but a contributor wanting to *consume* this gate in their own project doesn't see a 30-second answer to "what do I add to my spec.md to turn this on?" The `runtime: ios` example is buried under UX/User Flow halfway through the document. **Fix:** add a 4-line "Quickstart" block right after the Summary with the minimal `runtime: cli` frontmatter example — that's the closest analog to "first command."

## Important Considerations

- **No table of contents on a ~600-line spec with 14 top-level sections.** Anchors for `Trust Model`, `Definitions`, `Acceptance Criteria`, `Revision 2` would let readers jump.
- **`sidecar`, `engine validator`, `shadow validator`, `TOFU`, `blast radius` undefined inline.** These are MonsterFlow-internal jargon. `TOFU` (Trust On First Use) appears 9 times before being expanded parenthetically — and only in the UX section, never in Approach where it's first used. Define on first appearance in Approach.
- **"Cross-spec contract" is named but its location is implicit.** The phrase "per cross-spec contract" appears 7 times referring to `autorun-merge-policy` semantics; a contributor who hasn't read that spec doesn't know whether the contract is one paragraph or one section there. **Fix:** first occurrence should link `autorun-merge-policy` by relative path and name the specific section/AC being referenced.
- **Revision 2 appendix duplicates content already merged into the body.** The header says "Section content above has been updated to match. This section preserves the audit trail" — good intent, but a reader doesn't know which to trust on conflict. Consider moving Revision 2 to `CHANGELOG.md` or a sibling `revisions.md` and leaving a one-paragraph pointer, so the spec body is the single source of truth.
- **Status enum `skipped_external_author` is load-bearing but easy to miss.** It's defined in Definitions, then used throughout Trust Model, ACs, and cross-spec changes. The schema's `status` enum (Data & State section, line in JSON block) does NOT include it — it lists only `["pass", "fail", "skipped", "error"]`. **This is a real schema/prose drift bug**, not just a clarity issue: per memory `feedback_schema_bump_grep_prose_drift.md`, schema enum and prose-described enum must match. AC#37 references `skipped_external_author`; the schema rejects it.
- **AC count drift.** Body says "34 ACs" then "6 new ACs to existing 34" → 40 total, but ACs 1-34 are listed and Revision 2 adds 35-40. The "34" number appears in `VERSION + CHANGELOG bump` (AC#34) which is itself the 34th. Just say "40 ACs" up front.

## Observations

- **Voice matches project tone** (long comma-stitched sentences in body, imperative ACs). Consistent with `user_writing_voice.md`.
- **Trust Model cascade table is the strongest piece of writing in the spec** — it converts 5 dense security findings into a scannable "Was → Now closed by" matrix. Consider this pattern for future spec revisions.
- **UX/User Flow worked examples are excellent.** Five concrete frontmatter blocks + four autorun-output transcripts answer the "what does this look like in practice" question well.
- **Edge Cases section is exhaustive (22 cases).** Some are scenarios already covered in ACs (e.g., "static_dir + dev_server_cmd both set" appears in AC#4 implicitly and Edge Cases explicitly). Light dedup pass would help.
- **"Pricing / cost / tier reality" check N/A** — internal spec, no pricing surface.
- **Worst sentence from a contributor's perspective** (quote): *"Cascade — this single decision closes 5 sev:security blockers from the /check synthesis"* — opens with an unsignaled term ("Cascade"), references "/check synthesis" without naming the file. Rewrite: *"This one decision closes five security blockers (F1-F5) raised in `check.md`; the cascade is:"*.

## The 30-Second Test (adapted for contributor audience)

Reading only the Summary + Backlog Routing + Cross-Spec Dependencies (≈first viewport equivalent):

1. **What is it?** ✓ "post-`/build` runtime validation step that smoke-checks the assembled artifact before declaring a run validated"
2. **Who is it for?** ✓ "MonsterFlow contributors and pipeline maintainers" (frontmatter); autorun-using projects (body)
3. **Why would I install it?** ✓ "deepest validation today is unit-test discipline inside `/build` — catches code-level regressions but misses UI/integration/runtime issues"
4. **What's the first thing I'd do?** ✗ Not answered in first viewport. A contributor has to scroll to UX/User Flow to see the opt-in frontmatter shape. **This is the Critical Gap #2 above.**

## Verdict

**PASS WITH NOTES** — the spec is technically rigorous and the four-question test passes 3/4 for a contributor audience, but the schema/prose drift on the `status` enum (`skipped_external_author` missing from `runtime-validation.schema.json`) is a load-bearing defect that needs an inline fix, and the F#/C#/D# forward-reference soup makes Revision 2 unreadable without `check.md` open in another tab. Add a Quickstart block, expand `skipped_external_author` into the schema enum, and prefix the appendix with a code-decoder pointer — then this is a clean PASS.

---

## feasibility

# Technical Feasibility Review — autorun-runtime-validation-gate (Revision 2)

## Critical Gaps

### TF-C1 — `class: security`, `severity: blocker`, `tags: ["sev:security"]` — CODEOWNERS author check uses git authorship, which is forgeable

The Trust Model resolves F2 by checking "the branch's most recent author" and "the spec.md was last modified by a non-CODEOWNERS user." Git author/committer fields are arbitrary strings (`git commit --author='Maintainer <m@x.com>'` works for anyone with push access to a fork). On an external PR the only authoritative identity is the **GitHub PR author** (and reviewers' approval state), retrievable via `gh pr view --json author,reviewDecision`, not via `git log`. AC#37 says "most-recent commit on branch (or last spec.md modifier) is non-CODEOWNERS user" — both are git-side checks. A hostile contributor opens a PR, sets `--author` to a maintainer's name, and the gate believes them → unattended RCE on the maintainer's host. **The single architectural decision that closes F1-F5 is structurally sound; the implementation pin given in AC#37 reintroduces F2.** Suggested fix: replace git-author check with `gh pr view --json author --jq .author.login` and require that login appear in CODEOWNERS. Treat `gh` failure (rate limit, no PR for branch) as `skipped_external_author`, not as "no CODEOWNERS therefore proceed."

### TF-C2 — `class: contract`, `severity: blocker` — CODEOWNERS file location and parsing are underspecified

GitHub honors CODEOWNERS at three paths: `.github/CODEOWNERS`, `CODEOWNERS` (repo root), and `docs/CODEOWNERS`. Trust Model only mentions `.github/CODEOWNERS`. Repos using the other two locations would be treated as "no CODEOWNERS exists" and — depending on which fail-closed branch the implementation picks — either every PR is "external" (validation never runs for owner-authored PRs either) or every PR is "internal" (gate is bypassed). Additionally, CODEOWNERS supports team handles (`@org/team`) which require an org-scoped GH token to resolve to a user list, glob path patterns, and multi-owner lines. The spec doesn't say which path to read, what to do with team handles, or what "is a CODEOWNERS-listed user" means when patterns scope ownership per-path. Suggested fix: pin one canonical location, document team-handle resolution path (or reject team handles for the gate's purpose), and add an AC fixture for "CODEOWNERS at root, not `.github/`."

### TF-C3 — `class: contract`, `severity: blocker` — `playwright --ignore-https-errors` is not a `npx playwright` CLI flag

The spec's `web.sh` mechanics state "playwright invoked with `--ignore-https-errors` for dev convenience." This flag exists in two places: the JS API (`browser.newContext({ ignoreHTTPSErrors: true })`) and the **`playwright test`** test-runner CLI. There is no top-level `npx playwright --ignore-https-errors` invocation that navigates a URL and asserts a selector — playwright's CLI surface is `install`, `codegen`, `screenshot`, `test`, etc., none of which match the spec's described behavior (navigate + wait_for_selector + console-error scan + HTTP-200 + screenshot). To do what's described, `web.sh` either (a) shells into a small Node script that uses the playwright API, or (b) generates a `*.spec.ts` file on the fly and runs `playwright test`. Neither is in the spec. This is the kind of unstated implementation work that doubles effort mid-build. Suggested fix: ship a small `scripts/runtime-validators/_web-driver.mjs` (Node, ~80-120 LoC) that takes target_url + selector + allowlist via env vars; have `web.sh` invoke it. List that file in the touched-files manifest; add an AC for its existence.

### TF-C4 — `class: architectural`, `severity: blocker` — TOFU "open-once + fstat + hash-from-fd + exec-from-fd" hardening is not implementable in bash on macOS

The Trust Model section keeps F3 hardening: "open-once + fstat + hash-from-fd + exec-from-fd." Bash cannot `exec` from a file descriptor — `exec` resolves a pathname. The standard mitigation on Linux is `exec /proc/self/fd/N`, but **macOS has no `/proc`**. Workable patterns are (a) read the file fully into memory, hash, write to a private tmp dir under `mktemp -d` with mode 700, chmod 500, and execute from the tmp path; or (b) accept the residual TOCTOU on shadow validators since the threat surface no longer reaches external attackers. Spec's current language implies option (a)-ish but the "exec-from-fd" phrasing won't survive contact with macOS. Suggested fix: rewrite the hardening as "read+hash, write to `mktemp -d -p $TMPDIR mfshadow.XXXXXX` with chmod 500, exec the tmp copy, unlink on EXIT trap." Or downgrade the hardening claim and rely on the per-host trust file + skip-on-external-author as the primary defense.

### TF-C5 — `class: contract`, `severity: major` — `$SPEC_FILE` definition referenced but the canonical-vs-queue check for "spec.md last modifier" collapses

Trust Model says external-author check uses "the spec.md was last modified by a non-CODEOWNERS user." Definitions section says `$SPEC_FILE = queue/<slug>.spec.md`. The queue file is written by autorun itself during stage 0; `git log -1 --format=%an queue/<slug>.spec.md` will show whoever last touched the queue dir, which on a fresh autorun will be... autorun's commit user (typically the maintainer running autorun). So the queue-file modifier check **always passes** regardless of who authored the canonical spec. The check has to run against `<project>/docs/specs/<slug>/spec.md` (canonical), but the spec elsewhere says "Editing canonical after queue copy was made does NOT affect in-flight runtime validation — queue file is canonical for the run." These two contracts contradict for the security-relevant question. Suggested fix: explicitly state that the **author check** uses the canonical file's git history, while the **content** the validator consumes comes from the queue file. Document the precedence.

## Important Considerations

### TF-I1 — `class: contract`, `severity: major` — Process-group cleanup vs PID cleanup for `dev_server_cmd`

`npm run dev` typically spawns: npm → node (run script) → vite/webpack-dev-server → file-watcher children. Killing the tracked PID kills npm; the dev server keeps running and holds the port, so subsequent autorun iterations fail with EADDRINUSE. Spec mentions "tracked PID + child processes" but the resolved approach (SF4: `setsid + trap-EXIT only`) is correct only if `setsid` runs on the dev_server_cmd invocation specifically and the trap kills the entire process group (`kill -TERM -- -$PGID`). Recommend a worked example in `_lib.sh` doc-comment or a fixture that asserts port-free after teardown.

### TF-I2 — `class: contract`, `severity: major` — `gtimeout` Homebrew dependency is unstated as a prerequisite

`scripts/runtime-validators/_lib.sh` enforces hard timeouts via `gtimeout` on macOS. `gtimeout` ships with Homebrew `coreutils`, which is not in macOS by default. Without it, `_lib.sh` either silently degrades (timeouts don't fire) or errors out at first invocation. Add a doctor-check on autorun startup: if `runtime:` is set and the platform is macOS, verify `gtimeout` is on PATH; emit an actionable error before dispatching. Or fall back to a bash-native timeout via background + sleep + kill (`( cmd & ) ; sleep $TO ; kill ...`).

### TF-I3 — `class: tests`, `severity: major` — Validator status × autorun-captured exit code cross-check (F9 / AC#39) needs all four cells fixtured

The cross-check has four cells: {exit=0, status=pass}, {exit=0, status=fail}, {exit≠0, status=pass}, {exit≠0, status=fail}. Plus two no-sidecar cells (exit=0, no sidecar; exit≠0, no sidecar). T1-T4 fixtures cover specific scenarios but not the full matrix. A buggy validator that exits 0 yet writes `status: fail` is the named failure mode; without a fixture for the inverse (exit≠0 yet writes `status: pass`) the implementation can drift. Add a 6-row fixture table.

### TF-I4 — `class: architectural`, `severity: major` — Cumulative wall-clock impact on overnight autorun cycles

Validator timeouts: web 300s, cli 300s, ios 900s. Each /build attempt fails up to 3× before slicing (per session memory). With `runtime: ios`, three attempts × 900s = 45 min per slice purely in runtime validation, not counting build/test time. A four-slice autorun could lose three hours to validation alone. Not a defect — the gate is doing what it's designed to — but worth (a) documenting the budget impact in `commands/autorun.md`, and (b) considering whether validation should fire only on the final (post-/check-pass) /build attempt rather than every attempt. Spec is silent on this. Recommend AC: "validator runs once per slice after /build's final verification phase, not per /build attempt."

### TF-I5 — `class: contract`, `severity: major` — Sidecar atomic-write is bash, not Python

Data section says "atomic write via tmp + `os.replace`." `os.replace` is Python's `shutil`-adjacent API. The validators are bash. Atomic file replacement in bash is `mv tmp final` on the same filesystem (atomic per POSIX rename). Either change the prose to say `mv` or specify that the helper is a Python invocation. Minor but contract-relevant.

### TF-I6 — `class: contract`, `severity: minor` — `runtime: foo` invalid-value rejection point underspecified (AC#28)

AC#28: "invalid `runtime: foo` value → exit 2 at frontmatter parse, no validator dispatched." Which step parses? If it's the validator, dispatch already happened. Should be a frontmatter-validation step in `run.sh` before the dispatcher branch. Pin the location in the AC.

### TF-I7 — `class: tests`, `severity: minor` — Schema-per-event-type approach for run.log needs a discriminator pattern

C4 ships `schemas/run-log-runtime-validated.schema.json`. run.log is JSONL with multiple event types coexisting. Validating a heterogeneous JSONL against per-event schemas requires a dispatcher (read each line, switch on `event` discriminator, pick schema). The contract isn't laid out. If `/wrap-insights` Phase 1c is going to consume this, document the dispatcher pattern or use a single schema with a `oneOf` on `event`.

## Observations

### TF-O1 — `class: scope-cuts`, `severity: minor` — External-PR validation skip is a defensible v1 ergonomic but worth flagging the ceiling

Skip-on-external-author is the right v1 call given the asymmetric risk. The trade-off documented in the Trust Model — external contributors don't get runtime-validated PRs — means external contributors will see CI green from autorun's other gates but no runtime signal. For projects expecting external contributions (the user's MonsterFlow case explicitly does), this puts the runtime-validation burden on the maintainer at review time. Acceptable for v1; flag in `commands/autorun.md` migration notes so adopters set expectations correctly.

### TF-O2 — `class: documentation`, `severity: minor` — `_web-driver.mjs` (or equivalent) belongs in the touched-files manifest

If TF-C3 is resolved by adding a small Node driver, it counts toward the LoC delta and toward the test surface. ~1000-1400 LoC estimate is reasonable; the driver doesn't blow it.

### TF-O3 — `class: tests`, `severity: minor` — TOFU display-then-trust prompt (F8) testability is good; consider also asserting the pager exit path

AC#34 fixture description has "fixture sends `n` to display, asserts trust-grant prompt is NOT shown." Also worth: user pages content, exits pager, then sees the trust-grant prompt. That's the happy path; missing it leaves an unhappy "did the prompt appear after the pager?" regression risk.

### TF-O4 — `class: documentation`, `severity: minor` — `runtime: cli` working-directory and PATH inheritance is documented but spec author guidance is thin

Spec says "PATH inherited from autorun's environment. Spec author responsible for ensuring `<cmd>` is resolvable." A worked example of a relative-path build-artifact (e.g., `cmd: build/Release/MyTool`) in `commands/autorun.md` would prevent the most common adopter mistake.

### TF-O5 — `class: scope-cuts`, `severity: minor` — Iteration budget after 23 must-fix fold-in

Confidence delta lands at 0.945; iteration budget consumed is "1 of 2." Five blocker-level items above (TF-C1 through TF-C5) suggest one more iteration is warranted before /plan. Don't burn the second iteration on cosmetics; spend it on TF-C1 (CODEOWNERS via `gh pr view`) and TF-C3 (Node driver scope) since those reshape the task graph.

## Verdict

**FAIL** — five blocker-class technical-feasibility findings (TF-C1 forgeable git authorship undermines the F2 resolution, TF-C2 CODEOWNERS parsing underspecified, TF-C3 playwright invocation as described doesn't exist, TF-C4 macOS-incompatible TOCTOU hardening, TF-C5 canonical-vs-queue contradiction for the modifier check) need closure before /plan can route the task graph correctly; recommend one more spec iteration scoped to those five items.

---

## gaps

## Critical Gaps

**G1 — CODEOWNERS self-promotion attack unaddressed.** AC#37 detects external authors via "non-CODEOWNERS user," but the threat model never carves out the case where an external contributor's PR *itself modifies `.github/CODEOWNERS`* to add their handle. The check must read CODEOWNERS from `main` (or the PR base ref), never from the PR head. Not specified.

**G2 — CODEOWNERS parsing semantics undefined.** Spec doesn't say how to interpret: team handles (`@org/team`), wildcards (`* @user`), comments, malformed lines, multiple owners per path, or the case where `.github/CODEOWNERS` is empty/whitespace-only. Each ambiguity produces a different fail-open vs fail-closed behavior. Trust Model says "no `.github/CODEOWNERS` exists" → external; but doesn't say what "exists" means (zero bytes? no matching rule for `spec.md`?).

**G3 — Author vs committer not pinned.** "most recent author of branch" is ambiguous. Git distinguishes Author (`%an`) from Committer (`%cn`); rebases preserve Author but rewrite Committer. CI bots often appear as Committer with the human as Author. Pick one and document it. Force-push scenarios (ghost commits no longer in reflog) also unspecified.

**G4 — Branch-only autorun vs PR-context.** Autorun also fires on branches without an open PR (manual queue). Trust Model is written as if PR always exists. What's the behavior when `gh pr view` returns no PR? Default-skip? Default-run-as-owner? Default-run-as-external? Currently undefined → silent fail-open risk.

**G5 — Subprocess env inheritance leaks secrets.** `dev_server_cmd: "npm run dev"` and `cmd: "..."` inherit autorun's full environment, which routinely contains `GITHUB_TOKEN`, `ANTHROPIC_API_KEY`, etc. An owner-authored but careless `dev_server_cmd` (e.g., one that prints env on boot, or a malicious npm postinstall hook) exfiltrates them. No env-scrubbing/allowlist specified for validator subprocesses.

**G6 — CODEOWNERS-absent default unstated.** Trust Model says "no `.github/CODEOWNERS` exists" triggers external-skip, but combined with G4, a repo with no CODEOWNERS and a local-only branch never validates. Is that intended? Many MonsterFlow-adopter projects won't have CODEOWNERS at all. Need an explicit default policy + an opt-in for "trust all owner-pushed branches when CODEOWNERS absent."

## Important Considerations

- **Migration of pre-Revision-2 trust files.** AC#40 mandates `~/.claude/runtime-validators-trusted-hashes.json`, but install.sh still gitignores `.monsterflow/runtime-validators/.trusted-hashes.json`. No cleanup of the old per-repo file or migration of approved hashes to the new location.
- **Concurrent autorun batches.** Two autorun loops (e.g., tmux + launchd) writing `~/.claude/runtime-validators-trusted-hashes.json` simultaneously — no lock specified for the trust file itself. Lock at `queue/.runtime-validators.lock/` is per-project queue, not per-trust-file.
- **Regex inputs as DoS / injection vectors.** `console_error_allowlist[]` and `expected_stdout_contains` are user-provided regexes evaluated against potentially large output. Catastrophic-backtracking patterns can hang validators within timeout. No regex validation step.
- **Static_dir path traversal (owner mistake).** `static_dir: ../../../etc` from an owner-authored spec serves arbitrary host filesystem on a port. CODEOWNERS gating doesn't help here. Need a containment check (`realpath` under repo root).
- **xcodeproj walking ambiguity.** "walking up to find a `.xcodeproj`" — first-found may be wrong in monorepos. Require explicit path in `runtime_config.ios.xcodeproj` and reject auto-discovery.
- **PR body length limit (~65k chars).** AC#16 templates log + screenshot link + status block. Long failure logs + base64 thumbnail (per SF2 chosen path) can exceed GitHub's body limit. Truncation/fallback unspecified.
- **Screenshot/log retention policy.** `queue/<slug>/runtime-{pass,fail}.png` accumulates; nightly autorun grows queue dir indefinitely. No TTL or sweep step.
- **Schema v2 forward path.** `schema_version: const 1` is fine for now, but no documented upgrade path (validator behavior on v2 sidecar? v1 fallback semantics?).
- **iOS simulator state pollution between runs.** Cookies, defaults, keychain entries persist across `xcodebuild test` invocations. Repeatability + cross-spec contamination not addressed.
- **Admin debugging surface.** When a maintainer asks "why was this PR's runtime not validated?" — no single command surfaces the decision (CODEOWNERS lookup, kill-switch state, sidecar coercions). `run.log` has the data but no tool reads it.

## Observations

- Engine validators (`scripts/runtime-validators/*.sh`) are trusted unconditionally — a local tamper (e.g., compromised `npm install` modifying a checked-out file) bypasses the entire TOFU model. A startup integrity check against `git ls-files` HEAD hash would close this.
- `approved_by: "tty:user@host"` is forgeable (hostnames are user-controlled). Treat as advisory only; document.
- Playwright sends UA + Chromium version to external `target_url` hosts when `allow_external_url: true`. Minor info leak; worth a doc note.
- Bash 3.2 macOS compat (per memory: PIPESTATUS, tilde expansion, negative array subscripts) is not called out as a hard requirement for new validator scripts. Add to AC#33's reviewer checklist explicitly.
- `runtime_config.timeout_seconds` per-target default of 5min documented for web/cli, 15min for ios — but `_lib.sh`'s `enforce_timeout` doesn't have a max-cap; a spec with `timeout_seconds: 86400` would be honored and stall autorun indefinitely.
- `runtime: none` and "absent" produce same runtime behavior but different audit clarity — worth a one-line lint that `/spec` warns when `runtime` is absent on a project that has e.g. an `.xcodeproj` or `package.json` with `dev` script.
- Q11 "skip-on-external-author" is a sound v1 call, but the sentence "external PRs do not get runtime-validated by autorun" should be louder in `commands/autorun.md` adopter docs — it's a meaningful behavioral gap from the naive read of the spec.

## Verdict

**FAIL** — six critical gaps in the just-introduced Trust Model (CODEOWNERS source-of-truth, parsing semantics, author-vs-committer, branch-only fallback, env inheritance, CODEOWNERS-absent default) leave the security posture under-specified despite Revision 2 collapsing the named blockers; resolve before implementation.

---

## requirements

# Requirements Completeness Review — autorun-runtime-validation-gate

## Critical Gaps

1. **CODEOWNERS-absent → never-validate is undocumented ergonomic.** AC#37's third OR branch ("no `.github/CODEOWNERS` exists") means any adopter repo without CODEOWNERS gets runtime validation **silently disabled forever**. This is a load-bearing default that is not surfaced in `commands/autorun.md` requirements, not in the migration section, and not in any AC. Either AC#37 needs a "and surfaces a one-time stderr nag on first autorun in a CODEOWNERS-less repo" requirement, or `install.sh` needs an AC requiring it to seed a minimal CODEOWNERS, or the spec must call out "v1 requires CODEOWNERS to enable validation; without it, validation is a no-op." Pick one — currently spec is silent.

2. **Schema drift on validator status enum.** `schemas/runtime-validation.schema.json` declares `status enum: [pass, fail, skipped, error]` (Data section). Trust Model + Definitions add `skipped_external_author`. AC#37 records it in run.log. No AC requires the sidecar schema to include it. Either schema accepts it, or the run.log row is the only place it appears (then sidecar status drops back to `skipped` and `details.external_author: true` carries the signal). Schema vs. enum membership must be reconciled; currently ambiguous.

3. **`attach_screenshots` default-off is in prose only.** Trust Model F4 mitigation says "screenshots opt-in via `attach_screenshots: true` (default off)." No AC enforces this. AC#16 says PR body links to screenshot "if web/ios" with no opt-in gate. Without an AC, the F4 security mitigation is unenforceable; QA cannot write a test that fails when screenshots are uploaded by default.

## Important Considerations

4. **AC#39 cross-check side effect undefined.** When validator exit ≠ sidecar status, spec says "coerce to error with `details.crosscheck_failed: true`." Coerce *where* — overwrite sidecar in place, or write a sibling `runtime-validation.crosscheck.json`? Forensic auditability favors the sibling; atomic simplicity favors overwrite. Pick one.

5. **`runtime:` totally absent has no test fixture.** AC#11 covers behavior; AC#21 fixtures `runtime: none` only. The unset case (most adopter specs) has no fixture proving the no-op path is wired. Add a fixture or fold into AC#21.

6. **PR body content on `skipped_external_author`.** AC#16 fires on "non-pass + validated policy." `skipped_external_author` is non-pass. PR body would surface "Runtime validation: SKIPPED_EXTERNAL_AUTHOR" on an external contributor's PR — leaks CODEOWNERS membership signal back to the external author. Either suppress the section for this status, or use generic "skipped" copy.

7. **Kill-switch + validated policy + PR body.** With `AUTORUN_DISABLE_RUNTIME_VALIDATION=1` set, status is `skipped`, fallback is `pr`, AC#16 fires — PR body says "validation: SKIPPED" with a log path that doesn't exist (validator never ran). Spec needs to either skip the PR-body section when kill-switch is engaged, or template a kill-switch-aware message.

8. **Interactive TOFU prompt has no timeout.** Autorun (non-tty) silent-skips. Interactive blocks indefinitely. Specify a prompt timeout (e.g., 60s → treat as `n` + skip shadow) or document "TOFU prompts block until answered."

9. **SIGTERM grace period unspecified.** "PID-tracked SIGTERM then SIGKILL" — what's the interval? 5s? 30s? Matters for dev servers with cleanup hooks (DB connections, lockfiles).

## Observations

10. **Concurrency model implicit.** Mutex covers same-slug cross-validator; cross-slug autorun batching is unstated. If autorun is strictly serial per-slug, say so in Scope.

11. **`additionalProperties` not set on schema.** `runtime-validation.schema.json` doesn't declare `additionalProperties: false`. Forward-compat extension surface is fine, but spec should say which way — strict (false) for v1 + bump schema_version on extension is the cleaner contract.

12. **External-host allowlist completeness.** AC#36 enumerates `localhost | 127.0.0.1 | ::1 | *.test | *.localhost`. Worth deciding on `0.0.0.0` and `host.docker.internal` now — adopter Docker setups will hit this immediately.

13. **iOS 900s default + 5min web/cli default in same `timeout_seconds` field.** R1 fix says iOS bakes in 900s baseline; AC#8 says "5-min default." AC#8 should be updated to "default per-target (300s web/cli, 900s ios), override via `runtime_config.timeout_seconds`."

14. **`/wrap-insights` Phase 1c dependency.** C4 introduces `schemas/run-log-runtime-validated.schema.json` — confirm `/wrap-insights` Phase 1c parser is updated in the same PR or a follow-up; spec is silent.

## Verdict

**PASS WITH NOTES** — Revision 2 closes the security & contract gaps from `/check` and the AC count (40) is unusually thorough; remaining issues are completeness ambiguities (schema-vs-enum drift, default-off enforcement, CODEOWNERS-absent default, PR-body-templating edge cases) that can be resolved with targeted AC additions in this iteration's remaining budget rather than another full revision.

---

## scope

# Scope Analysis — autorun-runtime-validation-gate

**Stage:** /review (PRD Review)
**Persona:** scope-analysis
**Verdict (preview):** PASS WITH NOTES

---

## Critical Gaps

**S-C1: No phasing strategy for a 1000-1400 LoC, 40-AC spec.** The spec ships three target validators (`web`, `ios`, `cli`) plus shared lib plus TOFU plus external-author detection plus kill switch plus status cross-check plus secret scrubber plus PR templating plus 4 cross-spec edits to merge-policy — all in one PR. Per the slicing memo (`feedback_slice_strategy_for_autorun_build.md`), `/build` carves work that can't ship in 3 attempts into ≤300 spec-line + ≤200 LoC slices. This spec is ~2-3× that envelope. **Decide before plan:** is v1 (a) all three targets + full Trust Model, (b) `cli` only as MVP with `web`/`ios` as follow-up specs, or (c) Trust Model + scaffolding first and per-target validators as separate specs? Without an explicit answer, `/plan` will pick for you and `/build` will likely thrash.

**S-C2: MVP definition is implicit.** The Summary frames the gap as "page didn't render, CLI exits non-zero on its own help text, simulator fails to launch the new build" — three symptoms across three runtimes. But the smallest version that delivers value is arguably just `cli` for MonsterFlow itself (the dogfooding repo) — that single target proves the dispatcher pattern, sidecar schema, cross-spec contract with merge-policy, TOFU model, and external-author skip without taking on playwright (browser-execution attack surface) or xcodebuild (cold-build timing risk, 900s timeouts). Make the MVP boundary explicit in the spec, or accept that v1 is "all three at once" and own that scope.

## Important Considerations

**S-I1: External-author skip is a feature reversal masquerading as a security fix.** Revision 2's Trust Model means external PRs *don't get runtime-validated by autorun* — which is the exact case where you'd most want a smoke check before merge (you trust your own work more than a stranger's). The spec acknowledges this as "explicit v1 ergonomic" and routes the harder version to a future `autorun-runtime-validation-sandboxed-external` spec. That's defensible, but the README/docs copy needs to make this loud: **"runtime validation only runs on owner-authored branches; external PRs need manual review."** Otherwise adopters will assume they're protected when they aren't.

**S-I2: Cross-spec coupling expands scope into autorun-merge-policy.** AC#19 lists 4 edits to merge-policy (reason enum, audit-row field, dispatch helper, banner) "in the same PR as this spec." Plus Revision 2 adds 2 more enum values (`runtime_pr_external_author`, `skipped_external_author`). That's 6 cross-spec touches, all atomic with this spec's own ~1400 LoC. If merge-policy has shipped (per the spec's "ships after merge-policy" framing), these are amendments to a shipped spec — fine, but call out clearly that this PR amends merge-policy's contract (which adopters may have built on). If merge-policy hasn't shipped yet, consider folding the runtime-aware fields into merge-policy's initial schema instead of an additive amendment.

**S-I3: Phase 2 features hiding in v1.** Three items feel like they belong in follow-up specs but landed in v1:
- **iOS smoke-launch + screenshot capture (even post-SF1):** the simpler "file > 0 bytes AND not all-black via 50-pixel sample" check is still a screenshot pipeline. For v1's first iOS user, just `xcodebuild test -testPlan` passing is meaningful smoke. Defer screenshot-existence-check to `runtime-validators-visual-regression`.
- **PR-body templating with embedded base64 screenshot thumbnail (AC#16, SF2 resolution):** post-SF2 it's "link + thumbnail." A plain log link is sufficient for v1; thumbnail rendering can land with the visual-regression spec.
- **Secret scrubber regex (F4 resolution):** lives inside this spec but is reusable across any autorun output upload. Could be its own tiny spec/utility for cleaner reuse.

**S-I4: "While we're in there" — `install.sh` edit (AC#20).** Adding `.monsterflow/runtime-validators/.trusted-hashes.json` to project gitignore is mostly fine, but Revision 2 moved the trust file to `~/.claude/runtime-validators-trusted-hashes.json` (per-host, not per-repo) — so the install.sh edit is now obsolete. Either remove AC#20 or update it (gitignore the now-renamed-or-deleted directory). Currently inconsistent.

**S-I5: Prioritization between requirements unclear.** If `/build` runs into trouble (e.g., playwright integration is harder than estimated), which AC is droppable vs load-bearing? The spec lists 40 ACs flat. Suggested triage tier:
- **Must-ship for v1 to be useful:** AC#1-3, #6-12, #19 (cli + cross-spec contract)
- **Must-ship for security claims:** #13-14, #37-40 (TOFU + external-author + kill switch + cross-check)
- **Nice-to-have (carveable to follow-ups):** #4-5 (web/ios validators), #16 (PR templating), #25-26 (web/ios fixtures)

Make this triage explicit so a stuck `/build` knows what to keep and what to defer.

## Observations

**S-O1: "Cross-spec dependencies" framing is solid.** The spec's explicit "Cross-Spec Dependencies" section + the additive enum extension model is exactly right for two specs that ship in sequence. Other specs in the pipeline could adopt this pattern.

**S-O2: Out-of-scope list is unusually disciplined.** 7 deferred items, each with a backlog slug. This is good practice; flag it as a model for future specs.

**S-O3: Open Questions section is exemplary.** 11 questions, each marked resolved/deferred with the resolution and date. Future spec authors should mimic this template.

**S-O4: Watch for `validator_path` audit value collisions.** The sidecar's `validator_path` field stores either an engine path or a shadow path. If a project has both engine and shadow versions (engine fallback after autorun-mode silent skip), the audit row records the engine path with `shadow_trust: shadow_untrusted_skipped`. That's correct, but `/wrap-insights` consumers reading the run.log will need to join on `shadow_trust` to detect the "shadow existed but skipped" case. Document the join pattern in `commands/autorun.md` so dashboards don't undercount shadow usage.

**S-O5: Stakeholder day-after-launch ask (predicted).** "Why did my external contributor's PR not get validated?" — front-run this with copy in the merge-policy banner and the failed-validation PR-body template ("validation skipped: external author").

## Verdict

**PASS WITH NOTES** — scope is well-articulated with strong out-of-scope discipline, but v1 boundary is implicit and the spec ships ~2-3× the recommended slice envelope; resolve S-C1 (phasing) and S-C2 (MVP) before `/plan`, and triage S-I3 candidates to follow-up specs.

---

## stakeholders

# Stakeholder Analysis Review — autorun-runtime-validation-gate

## Critical Gaps

**SH-C1 — External PR contributors get silent skip with no feedback signal**
- class: contract, severity: major
- AC#37 records `skipped_external_author` to run.log, but the external contributor whose PR triggered autorun has no idea their PR was skipped vs. validated-and-passed. No PR-comment, no status check, no body section. Maintainer must manually communicate "I'll review this myself" every time. Spec is silent on this UX.
- Suggested fix: add an AC requiring a templated PR comment (or PR-body section, parallel to AC#16's `## Runtime validation: <STATUS>`) reading `## Runtime validation: SKIPPED — external contributor; maintainer will review manually` whenever `runtime_pr_external_author` fires. This is the "support team's first question" — except the support team is the maintainer.

**SH-C2 — Repos without `.github/CODEOWNERS` get blanket-skipped runtime validation**
- class: contract, severity: major
- Trust Model says external-author detection treats "no CODEOWNERS exists" as external. MonsterFlow itself has no CODEOWNERS at the moment (verify), and most personal/iOS repos don't either. Net effect: shipping this spec to a fresh adopter without CODEOWNERS = `validated` policy never resolves to runtime-pass; every PR falls back to `pr`. AC#37 fixture only covers the CODEOWNERS-exists path.
- Suggested fix: add a fixture for "CODEOWNERS absent" path with explicit semantics (recommended: when CODEOWNERS absent AND repo has no external PRs in last N days, treat owner-authored branches as trusted via `git config user.email` match against repo owner). Or document loudly in `commands/autorun.md` that CODEOWNERS is a hard prerequisite for `validated`.

**SH-C3 — Multi-machine users have no trust-file portability**
- class: documentation, severity: major
- Revision 2 F7 moved trust to `~/.claude/runtime-validators-trusted-hashes.json` (chmod 600, per-host). Justin runs on multiple machines (per `~/CLAUDE.md` Apple cert matrix + dev-session.sh patterns). Each machine re-prompts on first encounter for every shadow. There's no documented migration path ("scp the file?" "is that even safe?"). No AC pins the multi-machine UX.
- Suggested fix: add explicit `commands/autorun.md` section "Sharing trust across your own machines" with the recommended path (manual scp of the file is fine because the file itself IS the audit decision; sha256 matching is what gates exec). One paragraph; AC asserts the section exists.

## Important Considerations

**SH-I1 — `risk` reviewer persona at /check has no updated rubric**
- class: documentation, severity: minor
- "Roster Changes" says the existing `risk` persona already evaluates runtime concerns — but pre-this-spec, "runtime concerns" were abstract. Post-spec, /check should ask: "does this spec set `runtime:` if it ships a runnable artifact?" Without rubric update, the persona keeps reviewing at the old abstraction level and won't catch missing-runtime-on-runnable-artifact specs.
- Suggested fix: add one AC requiring `personas/check/risk.md` to gain a checklist item: "If the spec ships a runnable artifact (web page, iOS app, CLI tool) and `runtime:` is unset or `none`, flag as a Critical Gap — the asymmetric risk model applies."

**SH-I2 — Shadow-validator drift from engine has no detection mechanism**
- class: scope-cuts, severity: minor
- A spec author copies `web.sh` content into their shadow, approves via TOFU, then the engine ships a bugfix six months later. Their shadow runs the old, buggy code forever — TOFU only verifies "this is what I approved," not "this is current with engine." Stakeholder: future-Justin who fixes a `web.sh` bug and assumes all consumers picked it up.
- Suggested fix: out-of-scope for v1 is fine, but add to Open Questions or Backlog Routing: "Q12 (deferred): shadow-vs-engine drift detection — backlog item `runtime-validators-shadow-drift-warning` to surface 'shadow is N commits behind engine' on autorun startup." Closes the loop without scope creep.

**SH-I3 — `autorun-shell-reviewer` subagent's 13-pitfall checklist may not cover new patterns**
- class: contract, severity: minor
- AC#33 requires the subagent to pass clean review on the new validators — but the checklist was written against `scripts/autorun/*.sh` (claude/git/gh wrappers), not `playwright`/`xcodebuild`/`gtimeout` specifically. Stakeholder: subagent maintainer (Justin), and any future contributor relying on it as a gate. Risk: subagent rubber-stamps validators with patterns it wasn't trained against.
- Suggested fix: extend the subagent's frontmatter or checklist with playwright-specific (CDP teardown, screenshot path quoting) and xcodebuild-specific (test-plan injection sanitization, derived-data path) items as part of this spec's deliverables. Or explicitly defer with a backlog entry. AC#33 should pin which version of the checklist is being asserted.

**SH-I4 — Adopter-facing docs scope is unpinned**
- class: documentation, severity: minor
- Spec says "adopter-facing copy is handled in `docs/index.html`" but no AC requires a specific section to land in `docs/index.html` in this same PR. Stakeholder: adopters scanning the marketing/feature page. Risk: feature ships invisibly to non-MonsterFlow-contributor users.
- Suggested fix: add AC#41: "`docs/index.html` autorun section gains a 'Runtime validation gate' subsection summarizing the opt-in flow + trust model + supported targets, landing in same PR as the spec implementation."

**SH-I5 — `/wrap-insights` Phase 1c is a downstream consumer; schema change is backward-compatible but unverified**
- class: tests, severity: minor
- Revision 2 C4 adds `schemas/run-log-runtime-validated.schema.json`. `/wrap-insights` Phase 1c parses run.log. Stakeholder: anyone running `/wrap-insights` against historical run.log files (pre-this-spec) — they'll have rows without `runtime_validated` events. Spec doesn't assert "Phase 1c handles missing rows gracefully" or "old run.log files still parse."
- Suggested fix: add a fixture asserting `/wrap-insights` against a pre-v0.12.0 run.log doesn't error on missing runtime_validated rows. One-line addition to test plan.

## Observations

**SH-O1 — Conflicting need surfaced cleanly: external PRs vs unattended exec**
- class: scope-cuts, severity: nit
- The Trust Model section is unusually well-argued — explicit asymmetric-risk framing, named cascade (F1-F5 closed by single decision), explicit deferral via backlog (`autorun-runtime-validation-sandboxed-external`). This is the right shape for a v1 stakeholder tradeoff. No fix needed; flagging as exemplary so future specs can mirror the structure.

**SH-O2 — iOS-asymmetric 900s default is a hidden expectation for non-iOS contributors**
- class: documentation, severity: nit
- R1 raised iOS default to 900s; web/cli stay at 300s. Stakeholder: a contributor adding their first iOS spec who doesn't read the migration section will see a mysterious "this took 12 minutes vs my web spec took 30 seconds" and not understand why. Spec mentions documenting in `commands/autorun.md`; a constitution-template comment near the iOS example would catch the on-ramp user too.

**SH-O3 — The kill switch (`AUTORUN_DISABLE_RUNTIME_VALIDATION=1`) is a great escape hatch but underdocumented as an SRE pattern**
- class: documentation, severity: nit
- R2's kill switch is the right shape, but stakeholder framing missing: "if the gate is wedged at 3 AM and you need autorun to keep flowing, here's the env var" — that's an SRE/operator scenario. `commands/autorun.md` migration section is mentioned; consider also surfacing in a "Troubleshooting" section.

## Verdict

**PASS WITH NOTES** — spec is unusually mature for revision 2 and the Trust Model resolution is structurally sound; the gaps above are stakeholder-communication and downstream-consumer issues, not architectural problems, and can be addressed inline before /plan.

