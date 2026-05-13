# Implementation Plan — Autorun Overnight Policy (v6)

**Created:** 2026-05-05 (iteration 6 — applies check v4 GO_WITH_FIXES: MF1 R18 visibility, MF2 R18 framing honesty, Codex M1/M2/M4, SF-O5, cosmetic L1-L4)
**Spec:** `docs/specs/autorun-overnight-policy/spec.md` (v5: 26 ACs; AC#25 amended with detection-hardening framing + adopter recommendation; synthesis prompt requirement #5 rewritten + new requirement #6 for 4-backtick authoring guidance)
**Review:** `docs/specs/autorun-overnight-policy/review.md`
**Prior check:** `docs/specs/autorun-overnight-policy/check.md` (v3 NO-GO: nonce mechanism not actually injection-resistant per Codex H2 — *"don't treat model-echoed secrets as authentication"*)
**Designers:** api, data-model, ux, scalability, security, integration, wave-sequencer (v2 raw at `plan/raw_v2/`)

## Iteration-6 changes vs v5

| Check v4 finding | v6 resolution |
|---|---|
| **MF1 (Codex H1) — R18 not visible to overnight adopters** | **3 surfaces updated:** (a) 3.1 `--help` text includes verbatim v1 limitation notice; (b) 4.2 `doctor.sh` emits R18 visibility line on every run; (c) 4.3 CHANGELOG.md gets new "Known v1 limitation" header. 5.4 `test-doctor.sh` greps for "single-fence-spoof" presence. |
| **MF2 (Codex H2) — R18 mitigation framing too soft** | **Reframed as detection-hardening, not prevention:** spec AC#25 rewritten; synthesis prompt requirement #5 rewritten + new requirement #6 for 4-backtick authoring guidance; plan R18 mitigation column rewritten; CHANGELOG adopter recommendation added. |
| Codex M1 — "deterministic post-processor" wording stale | 3.2 task description renamed to "fenced-output extractor (D33)"; D33 design-decision heading renamed; explicit note that "deterministic verdict" is reserved for follow-up spec. |
| Codex M2 — `autorun-verdict-deterministic` sized L | BACKLOG.md entry resized to **XL** with acceptance bullets (reviewer tag schema; deterministic aggregation precedence; migration from `check-verdict` fences; adversarial single-fence fixture). |
| Codex M4 — NFKC normalize order vs fence detection | D33 algorithm explicitly states **normalize/strip BEFORE scanning**; 3.2 task description includes the order; SF-T5 fuzz table will exercise homoglyph/zero-width fence cases. |
| SF-O5 — 3.1 `--dry-run` should emit stub fence | 3.1 task description amended: dry-run synthesis stub MUST emit a `check-verdict` fence (else 5.5 false confidence). |
| Codex L1 — header v4 → v5 | Plan header rewritten to v6 (referencing spec v5). |
| Codex L2 — D33 v4 labels noisy | Renamed to "D33" or "D33 unchanged from v4". |
| Codex L3 — 5.3 row | Deleted. Wave 5 now has 5.1, 5.2, 5.4-5.7. |
| Codex L4 — R11 likelihood explanation | R11 mitigation now explains: Low *post-implementation* (D33 deterministic; rejects 100%); pre-implementation would be Med-High. |

## Iteration-5 changes vs v4

v4's D42 nonce (the v2-MF6 fix) failed Codex H2: `$AUTORUN_NONCE` is shown to the synthesis model; an adaptive prompt-injection can instruct the model to copy the nonce into a forged fence. The mechanism wasn't a trust boundary. Options A (architectural deterministic post-processor) is the correct long-term fix; Option C ships v1 with multi-fence rejection (D33) as honest mitigation, documenting the residual single-fence-spoof class as a known v1 limitation, and carves the architectural fix into `autorun-verdict-deterministic`.

| Check v3 finding | v5 resolution |
|---|---|
| Codex H1/H2/H4/H5 (nonce architectural) | **D42 dropped; AC#27 dropped; nonce field removed from check-verdict + run-state schemas; openssl/xxd doctor checks dropped; nonce test triad dropped; pitfall #20 dropped.** v2-MF6 documented as known v1 residual; carved off to `autorun-verdict-deterministic` follow-up spec. |
| Codex H3 (`write-key` 11th subcommand) | **Dissolved** — `write-key` was nonce-only. 1.5 freezes 10 subcommands cleanly. |
| Codex M6 (run-state.json mutation rules) | **Dissolved** — without nonce, run-state.json is not a security trust source. |
| Codex M8 (3.2 deps 3.1) | **Applied** — 3.2 now lists 3.1 as build-time dep (run-state path/lifecycle convention). |
| Codex M9 (1.0 sized M, not S) | **Applied** — 1.0 now M; acceptance includes "AC count == 26; AC#12/#13/#14/#25 quoted; no stale 'last fence' or 'AC#27/nonce' language". |
| Codex M10 (3.10 explicit deps) | **Applied** — `3.0,3.0b,3.1,3.2,3.3,3.4,3.5,3.6` enumerated. |
| Codex M7 (AST audit ban list) | **Applied** — 5.2 `test_policy_json_no_shell_out` now enumerates `os.environ.update/setdefault/pop/clear`, `os.putenv`/`unsetenv`, aliased imports (`from os import system as s`), `from subprocess import run`. |
| Codex L11 (critical-path 7 vs 8 stale) | **Fixed** — single statement: 8 hops, 5-7h. |
| Codex L12 (`tar --null -T -` portability) | **Applied** — 3.3 now reads "use the canonical command emitted by 1.1 spike output `queue/.spike-output/tar-untracked.cmd`". |
| Completeness MF-C1 (AC#12 jq drift) | **Applied** — spec AC#12 amended to "Python stdlib reader; no jq dependency"; 1.0 amends AC#12. |
| MF7/MF8/MF9/MF10 from v2 (D38 perm test, D40 multi-block, R14 fail-fast, R15 STOP race) | **Carry forward unchanged** — still in 5.2 / 3.0b / R-register. |
| SF3 (uuidgen lc) + SF5 (`git ls-files -z`) | **Carry forward unchanged.** |
| SF-T2 (`! git grep flock` regression test) | **Promoted into 5.2** — one-line addition. |
| SF-T3 (`update_stage` exports test) | **Promoted into 5.2** — AC#26 unprovable without it. |
| SF-T7 (no-python3 env isolation pin) | **Applied** — 5.2 now specifies `env -i PATH=/nonexistent` (not `/usr/bin:/bin`). |
| Scope cuts SF-CUT1/2/3 | **Not adopted** (consistent with iteration-2 stance). Documented in Open Questions. |

## Architecture Summary

5-wave shell+python implementation. **Critical path: 8 hops**, 5-7 hours single-agent.

```
1.0 spec amend → 1.1 spike → 1.5 API freeze (10 subcommands) → 2.1b _policy_json.py → 2.1 _policy.sh → 3.2 check.sh post-processor → 3.10 self-contained smoke → 5.6 audit → 5.7 preship
```

Synthesis prompt + persona-architect doc promoted to Wave 2. Wrapper drops flock AFTER run.sh adopts lock. Verdict-extraction is text-fenced (D33 single-fence Option A); residual single-fence-spoof class documented as v1 limitation; deterministic post-processor architecture deferred to follow-up spec.

## Design Decisions (v5 deltas only — D1-D41 from v3 carry forward; D42 REVERTED)

### D33 — Fenced-output extractor (Option A; v4 → v5/v6 unchanged)

Synthesis emits prose + ` ```check-verdict\n{json}\n``` ` block somewhere in output. Post-processor:
1. Walk lines for ` ```check-verdict ` openers (case-sensitive, lang-tag exact-match). Other-language fences skipped.
2. **count > 1** → `policy_block check integrity "multiple check-verdict fences (possible prompt injection)"`.
3. **count == 0** AND `OVERALL_VERDICT:` first line present → `policy_block check integrity "synthesis omitted check-verdict block"`.
4. **count == 0** AND first line absent → legacy grep fallback (one-release back-compat).
5. **count == 1** → extract fence to `check-verdict.json`; strip from stream; write remaining to `check.md`.
6. Validate `check-verdict.json` via `_policy_json.py validate`; on failure → integrity block.

**Extraction order (Codex M4):** the extractor performs NFKC-normalize + zero-width-strip on the input stream BEFORE scanning for ` ```check-verdict ` openers. This order matters: normalize-before-detection turns disguised fences (homoglyphs, zero-width-prefixed lang-tags) into real fences that get counted by D33. Normalize-after would let disguised fences slip past the count.

**Known v1 residual (documented, deferred):** the single-fence-spoof class — synthesis omits its own fence; reviewed content quotes a single fake one; count==1 passes — is NOT closed by D33. The mitigation (D33 multi-fence rejection + prompt-hardening language) is **detection-hardening, not prevention**: it raises the cost of the easy attack but does not authenticate a single fence quoted from reviewed content. Architectural fix (deterministic verdict aggregation from structured reviewer outputs, replacing synthesis-emits-sidecar) deferred to `autorun-verdict-deterministic` follow-up spec.

### D34 [v4 → v5 unchanged] — `_policy_json.py` stdlib + AST-audited allow/ban list

(Same as v4: `import os`/`os.path` allowed; `subprocess`/`eval`/`exec`/`os.system`/`os.exec*`/`os.fork*`/`os.spawn*`/`os.popen`/`os.environ` mutators banned; AST-audited.)

**Codex M7 tightening:** AST audit now also rejects `os.environ.update`, `os.environ.setdefault`, `os.environ.pop`, `os.environ.clear`, `os.putenv`, `os.unsetenv`, aliased imports (`from os import system as s` → block call to `s`), and `from subprocess import run`.

### D42 [REVERTED v5]

Per Codex H2: model-echoed secret is not a trust boundary. Removed. AC#27 dropped (spec is now 26 ACs). Single-fence-spoof class documented as known v1 limitation in spec AC#25 and synthesis prompt requirement #5.

### Carve-off — `autorun-verdict-deterministic` (NEW follow-up spec)

Architectural fix for v2-MF6 (single-fence prompt-injection bypass). Drops synthesis-emits-sidecar pattern; reviewer outputs emit structured `sev:security` + verdict tags; post-processor aggregates `check-verdict.json` deterministically. Backlog entry added.

## Implementation Tasks (v5)

### Wave 1 — Contract + portability spike

| # | Task | Depends On | Size |
|---|------|-----------|------|
| 1.0 | **Spec amendments commit (sized M per Codex M9):** apply spec edits for AC#12 (Python-only `_policy_json.py get`; no jq), AC#13 (uuidgen lowercase), AC#14 (`git ls-files -z` mandatory), AC#25 (single-fence Option A — drop "last fence" — and detection-hardening framing per check v4 MF2). **Acceptance: AC count == 26; amended ACs quoted verbatim in commit message; `! git grep -nE 'AC#27\|AUTORUN_NONCE' docs/specs/autorun-overnight-policy/spec.md` returns clean (no stale references); spec body has zero un-negated "last fence" requirement claims; `grep -q 'autorun-verdict-deterministic' BACKLOG.md` returns clean (carve-off entry present).** | — | M |
| 1.1 | macOS bash 3.2 portability spike: flock, timeout, uuidgen (lc-normalize), mktemp, ps -o lstart, jq absent, BSD sed/date/stat/tar `--exclude`, BSD `tar --null -T -` (verify on macOS — emit canonical command to `queue/.spike-output/tar-untracked.cmd` for 3.3 to consume per Codex L12), portable atomic symlink rotation (temp-symlink + `mv -f`, NOT `ln -sfn` per SF4). 30-line script per primitive under set -e + trap; 2-writer × 100-iter atomic-append torture. | 1.0 | L |
| 1.2 | `schemas/morning-report.schema.json` — `final_state` enum, `policy_resolution`, `pre_reset_recovery` (with `untracked_archive_size_bytes`, `partial_capture: bool`) | 1.0 | S |
| 1.3 | `schemas/check-verdict.schema.json` — `verdict` enum, `blocking_findings[]`, `security_findings[]`, `prompt_version: "check-verdict@1.0"`, `finding_id` pattern. **No `nonce` field.** | 1.0 | S |
| 1.4 | `schemas/run-state.schema.json` — `warnings[]`, `blocks[]`, `policy_resolution`, `branch_owned`, `codex_high_count`, STAGE enum 11 values. **No `nonce` field.** | 1.0 | S |
| 1.5 | **API contract freeze:** (a) `_policy.sh` shell function signatures + STAGE/AXIS enums + `if ! policy_act` documented pattern + `policy_block` non-exiting return; (b) `_policy_json.py` CLI surface — **10 subcommands** (`read`, `get`, `append-warning`, `append-block`, `validate`, `finding-id`, `normalize-signature`, `escape`, `extract-fence`, `render-recovery-hint`); stdin/stdout/stderr semantics frozen; (c) **fenced JSON block format** per D33 (one `check-verdict` fence; no last-position constraint; no nonce required) | 1.1, 1.2, 1.3, 1.4 | M |

### Wave 2 — Helpers + synthesis prompt contract

| # | Task | Depends On | Size |
|---|------|-----------|------|
| 2.1b | `scripts/autorun/_policy_json.py` (NEW per D34 v5) — stdlib + `import os`/`os.path` allowed; **AST-audited ban list** (Codex M7 enumerated: subprocess/eval/exec/os.system/os.exec*/os.fork*/os.popen/os.environ mutators incl `update`/`setdefault`/`pop`/`clear`/`putenv`/`unsetenv`/aliased imports/dynamic-imports); 10-subcommand CLI per 1.5; hand-rolled validator; `extract-fence` state machine; `write_json_atomic` via `os.replace()` | 1.1, 1.5 | L |
| 2.1 | `scripts/autorun/_policy.sh` (NEW) — shell API thin wrappers; flock-or-mkdir lock per spike; **source-time `command -v python3 >/dev/null \|\| { echo '[policy] python3 required'; exit 2; }`** | 1.1, 1.5, 2.1b | M |
| 2.2 | `scripts/autorun/_codex_probe.sh` (NEW) | 1.0 | M |
| 2.3 | `queue/autorun.config.json` — `policies` block + `untracked_capture_max_bytes: 104857600` | 1.5 | S |
| 2.4 | `commands/check.md` — synthesis section: `OVERALL_VERDICT:` first line + **single `check-verdict` fence (no last-position constraint, D33)** + NFKC normalize + zero-width strip + `sev:security` regex + `_finding_id` derivation + prompt-injection-resistance language with explicit "v1 known residual: single-fence-spoof class deferred to autorun-verdict-deterministic follow-up". Universal (manual /check + autorun). **No nonce instruction.** | 1.3, 1.5 | M |
| 2.5 | `personas/check/security-architect.md` — mandate `sev:security` tag prefix | 1.3 | S |

### Wave 3 — Stage-script integration

| # | Task | Depends On | Size |
|---|------|-----------|------|
| 3.1 | `scripts/autorun/run.sh` — `--mode` + `--dry-run` flag parsing; **slug-arg validation**; **D39 startup banner if `--mode` absent + non-TTY**; **`RUN_ID="$(uuidgen \| tr 'A-Z' 'a-z')"` BEFORE AC#13 regex match (SF3)**; create `queue/runs/<run-id>/`; `current` symlink (atomic temp+`mv -f`); lockfile (PID+lstart per D20); initial `run-state.json` with `policy_resolution`; auto-merge gate composition (CODEX_HIGH=0 AND RUN_DEGRADED=0); morning-report render at exit; STOP-file path writes morning-report; `update_stage()` exports `AUTORUN_CURRENT_STAGE`; **DELETE run-summary.md writer**; **REMOVE queue-loop + counters**; **MOVE index.md writer to autorun-batch.sh**; run.sh:280-288 destructive reset under branch_policy with same backup pattern as 3.3. **`--help` text MUST include the v1 limitation notice (MF1 from check v4):** *"v1 fence extraction rejects multi-fence injection but does not authenticate a single check-verdict fence quoted from reviewed content. Do not use unattended auto-merge on untrusted prompt-bearing content until autorun-verdict-deterministic ships. See BACKLOG.md."* **`--dry-run` mode emits a stub `check-verdict.json` fence in synthesis stub output (SF-O5)** — without this, 5.5 dry-run smoke gives false confidence that the post-processor extracted a sidecar when in fact it hit the fallback. | 2.1, 2.3 | L |
| 3.0 | Wrapper relocation (D31): `scripts/autorun/autorun` drops `flock`; locking moves to `run.sh`; deletes legacy lock with deprecation log; argument-forward + log-redirect only | 2.1, 3.1 | S |
| 3.0b | autorun-batch.sh (D30): thin queue-loop wrapper; STOP-file check between iterations. **STOP-race documentation (MF10):** *"STOP is honored at iteration boundaries only. An in-flight `run.sh` completes its current slug after STOP is touched; only the N+1 iteration is suppressed. Stage-boundary STOP-check inside run.sh is deferred — see BACKLOG.md."* Propagate exit code 3 from run.sh; on-failure continue + aggregate exit nonzero; zero-match → exit 0 with notice; writes `queue/runs/index.md` aggregate | 2.1, 3.1 | M |
| 3.2 | `scripts/autorun/check.sh` — **fenced-output extractor (D33; renamed from "deterministic post-processor" per Codex M1 — D33 is fence extraction, not deterministic verdict aggregation; that lives in follow-up spec)**: `_policy_json.py extract-fence` performs NFKC-normalize + zero-width-strip BEFORE scanning (Codex M4); count >1 → integrity block; count==0 + marker present → integrity block; count==0 + marker absent → grep fallback; count==1 → extract to JSON sidecar + write remaining stream to check.md; validate sidecar via `_policy_json.py validate`; consume sidecar via `_policy_json.py get`; verdict NO_GO → `policy_block check verdict`; `verdict=GO_WITH_FIXES` → use **`if ! policy_act verdict ...; then render_morning_report; exit 1; fi` pattern (D37)**; security_findings → hardcoded block. **No nonce validation step.** | 2.1, 2.1b, 2.4, **3.1** | L |
| 3.3 | `scripts/autorun/build.sh` — branch-owned check; **four-artifact reset capture (D17 + SF5)**: pre-reset.sha + pre-reset.patch (5MB cap) + pre-reset-untracked.tgz (**use the canonical `git ls-files -z` + `tar --null -T -` command emitted by 1.1 spike at `queue/.spike-output/tar-untracked.cmd`** + capture-side path filter on NUL-stream + 100MB cap with .SKIPPED marker) + recovery_ref via `update-ref refs/autorun-recovery/<run-id>` (only if `git stash create` non-empty; on partial failure between tar and update-ref → `partial_capture: true`); **`if ! policy_act branch ...` pattern (D37)** | 2.1, 1.1 | M |
| 3.4 | `scripts/autorun/verify.sh` — infra-error classifier; **`if ! policy_act verify_infra ...` (D37)** for infra; `policy_block verify` for substantive | 2.1 | M |
| 3.5 | Codex probe consolidation: replace `command -v codex` at run.sh:394 with `_codex_probe.sh`; `policy_act codex_probe` on probe failure. Sequenced after 3.1 | 2.1, 2.2, 3.1 | S |
| 3.6 | `scripts/autorun/notify.sh` — read `morning-report.json` via `_policy_json.py get`; map `final_state` → notification text | 2.1 | S |
| 3.10 | **Closing serial step (self-contained):** integration smoke against hand-staged minimal fixture (1 slug, hardcoded artifacts; NOT 5.1 fixtures). **Asserts:** (a) sidecar extracted (not fallback-logged); (b) `autorun-batch.sh` against 2-spec inline queue → 2 separate `queue/runs/<run-id>/` dirs; (c) STOP-file between iterations honored; (d) `update_stage` exports propagate to subshells. **No nonce roundtrip.** | **3.0, 3.0b, 3.1, 3.2, 3.3, 3.4, 3.5, 3.6** | S |

### Wave 4 — Adopter migration + subagent checklist

| # | Task | Depends On | Size |
|---|------|-----------|------|
| 4.1 | `.claude/agents/autorun-shell-reviewer.md` — append pitfalls 14-19: (14) sourced helper × set -e × trap; (15) sticky RUN_DEGRADED file derivation; (16) `if ! policy_act` pattern (D37); (17) flock atomic-append OR mkdir-fallback + cleanup trap; (18) `_json_escape` Python-pinning + bash-sed forbidden + `_policy_json.py` AST-audited ban list; (19) fenced-block extraction single-fence rule (D33 v4) | 2.1, 2.1b | M |
| 4.2 | `scripts/doctor.sh` — flag missing `policies` block; flag `flock` unavailable; `timeout` BSD vs GNU check; `autorun-batch.sh` presence check; warn if cron entry calls `run.sh` (silent-default-shift catch). **R18 visibility line (MF1 from check v4):** emit on every run — *"autorun v1 ships with known prompt-injection residual class (single-fence-spoof). See BACKLOG.md → autorun-verdict-deterministic. For untrusted spec sources, set `verdict_policy=block` and disable unattended auto-merge."* **No openssl/xxd checks.** | 2.3, 3.0b | S |
| 4.3 | `CHANGELOG.md` — "External adopters: action required" header + silent default-shift + single-slug breaking change with autorun-batch.sh migration path + grep-fallback removal pinned to v0.9.0 + `current` symlink rotation in batch mode + **NEW "Known v1 limitation" section (MF1 from check v4):** verbatim *"v1 fence extraction rejects multi-fence injection but does not authenticate a single check-verdict fence quoted from reviewed content. Do not use unattended auto-merge on untrusted prompt-bearing content until autorun-verdict-deterministic ships. Mitigation is detection-hardening, not prevention. For repos processing untrusted spec sources (third-party PRs, externally-authored queue items), set `verdict_policy=block` and disable unattended auto-merge."* | 3.0b, 3.1 | S |
| 4.4 | `.gitignore` — add `queue/runs/` | 3.1 | S |

### Wave 5 — Tests + final audit gate

| # | Task | Depends On | Size |
|---|------|-----------|------|
| 5.1 | `tests/fixtures/autorun-policy/` — **6 fixture dirs:** (a) clean → merged, (b) verifier infra timeout → pr-awaiting-review, (c) NO_GO → halted, (d) GO_WITH_FIXES + security → halted, (e) **prompt-injection (multi-fence + NFKC homoglyph)** → security carve-out + multi-fence rejection fires, (f) **PR creation failure → completed-no-pr** | 3.10 | M |
| 5.2 | `tests/test-autorun-policy.sh` — **named cases:** parsing, precedence, sidecar happy/missing/malformed/schema-mismatch, security carve-out, headline (warn → RUN_DEGRADED=1 → auto-merge skipped), AC3 first-line regex, AC11 codex-probe, **AC13 lockfile PID+lstart + uuidgen lowercase normalization (SF3)**, **AC14 four-artifact capture + `git ls-files -z` round-trip with newline-in-path fixture (SF5)** + **`test_pre_reset_partial_capture` (SF-T1)**, `_finding_id` derivation fuzz, `_json_escape` fuzz, **`test_policy_json_no_shell_out` (AST-based audit per D34 + Codex M7 enumeration: Import/ImportFrom incl aliased; Call func==Name('eval'\|'exec'\|'compile'); Attribute calls os.system/popen/exec*/fork*/spawn*/putenv/unsetenv; os.environ.update/setdefault/pop/clear; Subscript Assign on os.environ)**, flock-missing → mkdir fallback, **`test_policy_helper_no_python3` (R14; `env -i PATH=/nonexistent bash -c 'source _policy.sh'` → exit 2; stderr 'python3 required'; SF-T7 isolation pin)**, two parallel writers torture, **multi-fence rejection (D33 v4)**, untracked path-traversal rejection, untracked.tgz cap, **`test_renderer_permutations` (MF7: 4×2 table-driven)**, **`test_blocks_multi_render` (MF8: order + length + markdown positional)**, **`test_no_flock_in_wrapper` (SF-T2: `! git grep -nE '\\bflock\\b' scripts/autorun/autorun`)**, **`test_update_stage_export` (SF-T3: bash -c 'echo $AUTORUN_CURRENT_STAGE' returns value after update_stage call — AC#26 verification)**, **`test_d39_banner_non_tty` (SF-T4)** | 5.1 | L |
| 5.4 | `tests/test-doctor.sh` — runs against tmpdir with `policies`-less config; greps for lettered 3-fix block; invalid-config + missing-flock cases; **R18 visibility line presence test (greps doctor.sh output for "single-fence-spoof")** | 4.2 | S |
| 5.5 | `tests/autorun-dryrun.sh` extension — assert `queue/runs/current/run-state.json` + `morning-report.json` valid; `RUN_DEGRADED` derivation; fenced-JSON sidecar extraction works in dry-run stub | 3.10 | S |
| 5.6 | **Audit (terminal precedes preship):** `autorun-shell-reviewer` subagent on cumulative diff (Waves 2 + 3); apply High findings inline; re-invoke until clean | 4.1, 4.2, 4.3, 4.4, 5.2, 5.4, 5.5 | M |
| 5.7 | **Preship (terminal gate after audit):** `git status` clean; **AC count matches 26** (down from 27 — AC#27 nonce dropped); `--mode` help text quoted from `--help` output; `tests/run-tests.sh` green; `autorun-batch.sh` exists; `grep -q "External adopters" CHANGELOG.md` | 5.6 | S |

## Critical Path

```
1.0 spec amend → 1.1 spike → 1.5 API freeze (10 subcommands) → 2.1b _policy_json.py → 2.1 _policy.sh → 3.2 check.sh post-processor → 3.10 self-contained smoke → 5.6 audit → 5.7 preship
```

**8 hops. 5-7 hours single-agent.** (Architecture summary + later mention now consistent per Codex L11.)

## Open Questions

1. `complete` vs `pr` STAGE redundancy — recommend keep both; document in 1.4 schema.
2. `tests/test-policy-json.sh` separate from `test-autorun-policy.sh` — recommend separate; deferred.
3. `scripts/install.sh` cron-rewrite task — defer until adopter signals.
4. `pre-reset-untracked.tgz` 100MB cap default — configurable, recommend yes.
5. **Stage-boundary STOP-check inside run.sh** (R15 follow-up) — BACKLOG.
6. **Scope-discipline cuts SF-CUT1/2/3** (fixture-e, D38 8-perm, D39 banner) — not adopted in v5; documented for visibility. Decision: keep for ship-readiness; revisit if next /check escalates.

## Top Risks (v5)

| # | Risk | L | S | Mitigation |
|---|------|---|---|---|
| R1 | Portability spike finds material BSD/GNU gap | Med | Med | 1.1 expanded; `tar --null -T -` canonical command emitted to spike-output |
| R3 | autorun-batch.sh not delivered → adopter cron breaks | Low | High | 3.0b mandatory; 4.2 doctor.sh; 4.3 CHANGELOG |
| R6 | LLM emits valid JSON with wrong field types | Med | High | `_policy_json.py` hand-rolled validator |
| R10 | `policy_block + set -e` footgun | Low | High | D37 documented at every call site |
| R12 | Untracked archive path-traversal | Low | Med | D17 + SF5 capture-side filter on NUL-stream |
| R13 | Sequencing inversions | Low | Med | v3 corrected edges; v4 reordered Wave 5; v5 added 3.2 deps 3.1 + 3.10 explicit deps |
| R14 | `_policy_json.py` source-time fail-fast | Low | Med | 5.2 `test_policy_helper_no_python3` (env-isolation pinned per SF-T7) |
| R15 | STOP-file race in autorun-batch.sh | Med | Low | 3.0b documents iteration-boundary semantics; stage-boundary STOP follow-up in BACKLOG |
| R17 | uuidgen uppercase fails AC#13 regex | Low | Med | SF3: `tr 'A-Z' 'a-z'` before regex match |
| R11 | Multi-fence prompt injection | Low | High | D33 multi-fence rejection. Likelihood Low *post-implementation* — adversarial multi-fence content is cheap to author, but D33 deterministic detection rejects it 100% of the time. Pre-implementation likelihood would be Med-High. |
| **R18** | **Single-fence-spoof prompt injection (v2-MF6 residual)** | **Med** | **High** | **Mitigation is detection-hardening, not prevention** (clarified per Codex H2 from check v4). D33 multi-fence rejection blocks the easy attack class but does NOT authenticate a single fence quoted from reviewed content. Documented as known v1 limitation in spec AC#25 + synthesis prompt requirement #5; surfaced to adopters via doctor.sh runtime line + CHANGELOG "Known v1 limitation" header + run.sh `--help` notice (MF1 from check v4). Architectural fix carved into `autorun-verdict-deterministic` follow-up spec. **Adopter recommendation:** for repos processing untrusted spec sources, set `verdict_policy=block` and disable unattended auto-merge until follow-up spec ships. |

## Roster

7 designers (full roster). v5 is a delta-only revision (drop nonce + apply 6 contract pin must-fixes); no new design-agent dispatch.

## Approval Gate

Approve to proceed to `/check`? (5 plan reviewer agents will validate.)
