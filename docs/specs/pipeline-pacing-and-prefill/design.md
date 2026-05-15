# Design — pipeline-pacing-and-prefill

**Stage:** /blueprint iter1 + /check iter1 inline-fix iter2 · gate_mode: permissive
**Dispatched (blueprint):** api:opus, integration:sonnet, data-model:sonnet (codex skipped at design gate)
**Dispatched (check):** completeness:opus, risk:sonnet, scope-discipline:sonnet, codex-adversary
**Verdict (check iter2 post-fix):** GO_WITH_FIXES — 5 contract/tests/scope-cuts findings route to followups.jsonl; mobile-verify carved to v0.14.1

## Architecture summary

Four v0.14 UX-pacing items ship via two helpers + minimal-diff splices into
12 commands + 4 autorun scripts. Sentinel state = 3 files (one JSON, two
markers). No new schemas, no new JSONL. Mobile-verify deferred to v0.14.1 as
a standalone spec. ETA real-data deferred to v0.15.

## Key design decisions (post-/check)

### D1 — `scripts/_pipeline_banner.sh` (unchanged, expanded bash 3.2 constraints)

Dual-mode sourceable+executable. Positional args `start <gate> <feature>` /
`end <gate> <feature>`. Stdout-vs-stderr routed via `${AUTORUN:-0}` inside.
Cost/ETA/denominator computed inside; optional `--cost`/`--next` overrides.

**Bash 3.2 forbidden constructs** (per /check F7, expanded from blueprint
D1): `${arr[-1]}`, `declare -A`, `local -n`, `mapfile`, `read -a`,
`(?<name>...)` named-group regex, `$'\Q...\E'`. Denominator via `case`.
Test runner pins `BASH=/bin/bash` for any test touching the helper.

### D2 — *DROPPED (mobile-verify carved to v0.14.1)*

The mobile-verify exit-code contract (0/1/2 = PASS/CODE/INFRA) moves to the
v0.14.1 follow-up spec, with refinements per /check (UNKNOWN exit 3, narrowed
INFRA scope, targeted UDID erase).

### D3 — Sidecar files + `/compact` path resolution (post-/check)

Three sidecars:

- **`.compact-mode`** — bare literal `probe` or `suppress`. Written by
  `/blueprint` pre-flight (T6 amended to include this — per /check F2):
  the pre-flight probes whether `scripts/statusline-command.sh:42`'s JSON
  stdin format (`.context_window.used_percentage`) is reachable. Writes
  `probe` if yes, `suppress` if no. **Concrete probe surface, not
  claude-code-guide consultation.**
- **`.last-compact-suggestion`** — JSON `{"last_context_pct": int, "last_emit_ts": iso8601, "path": "A"|"B"}`.
  Both paths throttle through it. Fail-open on parse error.
- **`~/.claude/.banner-disabled`** — user-global empty marker; suppresses
  all banner output.

**Gitignored** (per /check F8): `docs/specs/*/.compact-mode` and
`docs/specs/*/.last-compact-suggestion` patterns in `.gitignore`. Sentinel
files don't leak into git history.

### D4 — ETA fallback-only in v0.14 (wording fixed)

`_pipeline_eta.py` returns hardcoded defaults only. **No "from rankings
history if present" code path or copy in v0.14** (per /check F11). Real-data
ETA carved to v0.15 (`pipeline-eta-from-timing-data` BACKLOG entry).

Spec/banner wording uses "typical estimate" or just shows the value
without history-claim framing.

### D5 — `session-cost.py --cumulative-only` (no `--session-only`; pinned output)

Per /check F10 + F13: drop `--session-only` flag entirely. Sole new flag is
`--cumulative-only`. **Pinned output contract:** outputs exactly one
integer (cents) on stdout, exits 0 on success / 1 on session-data-absent.
Test: `tests/test-session-cost-cumulative-only.sh`.

### D6 — *DROPPED post-/blueprint spike* (unchanged)

`_pipeline_input.sh` retired with Item 4 (tab-prefill).

### D7 — install.sh integration (post-/check)

`scripts/*.sh` glob in install.sh auto-picks up `_pipeline_banner.sh` and
`_pipeline_eta.py`. No new install.sh entries for v0.14. (mobile-verify
skill-wave changes deferred to v0.14.1 spec.)

### D8 — Codex skipped at /blueprint, ran at /check (delivered NO-GO with 7 findings)

Codex critique caught 4 architectural blockers + 3 majors at /check iter1.
All resolved inline per the /check fix set. No re-run needed.

### D9 (new per /check F1) — T6 inventory-first, serialized with T8

T6 is **inventory-first**: enumerate all active prompts across `commands/*.md`
(12 files: spec, spec-review, blueprint, check, build, wrap, wrap-quick,
wrap-insights, wrap-full, kickoff, autorun, flow — excluding preship.md
which doesn't exist). Generated manifest at
`tests/fixtures/prompt-inventory.txt`. Patches per-command. T6 covers
grammar normalize on all commands **except** `commands/build.md`. T8 owns
`build.md` exclusively (grammar normalize + autorun-shell-reviewer hook).
Serialize: T6 → T8.

### D10 (new per /check F3) — autorun-shell-reviewer wired in commands/build.md

T8 amends `commands/build.md` Phase 3 with an explicit instruction:
when `scripts/autorun/*.sh` has uncommitted changes (detect via
`git diff --name-only HEAD scripts/autorun/`), dispatch
`autorun-shell-reviewer` subagent BEFORE pre-commit. Halt-on-High via
3-attempt iterative-resolution loop. AC15 amends to grep for this
instruction text.

## Implementation tasks (post-/check)

3 waves, **8 tasks** (was 11 → 8: T4 / T5 / T11 retired, T8 expanded, T9 reconciled).

| # | Task | Depends on | Size | Wave | Parallel? |
|---|---|---|---|---|---|
| T1 | `scripts/_pipeline_banner.sh` (dual-mode, expanded bash 3.2 forbidden list) | — | M | 1 | yes |
| T2 | `scripts/_pipeline_eta.py` (fallback-only, no rankings-history code) | — | S | 1 | yes |
| T3 | `~/.claude/scripts/session-cost.py` add `--cumulative-only` (pinned output: integer cents on stdout) | — | S | 1 | yes |
| T6 | **Single agent, inventory-first, sequential.** (i) Generate `tests/fixtures/prompt-inventory.txt` from `commands/*.md` (excluding preship/build); (ii) splice grammar normalize + banner emission across 11 files (spec, spec-review, blueprint, check, wrap*, kickoff, autorun, flow); (iii) ADD `/blueprint` pre-flight `.compact-mode` write step (per F2/D3); (iv) append CLAUDE.md "## Tab-accept suggestions" paragraph. NO build.md. | T1 | L | 2 | within-T6 sequential; T6 parallel with T7 |
| T7 | `scripts/autorun/*.sh` (spec-review, design, check, build) — banner stderr emission when `$AUTORUN=1` | T1 | M | 2 | yes |
| T8 | **commands/build.md exclusive owner.** Grammar normalize + Phase 3 autorun-shell-reviewer hook (per F3/D10). Serialized after T6. | T1, T6 | M | 2 | runs after T6 finishes |
| T9 | Test suite — 16 new files (per AC22 enumeration). Includes `test-prompt-inventory.sh`, all banner+compact+session-cost+CLAUDE.md+bash32+build.md tests | T1-T8 | L | 3 | yes |
| T10 | `.gitignore` adds sentinel patterns (F8); `tests/run-tests.sh` wires 16 tests; `CHANGELOG.md` v0.14.0 entry; `VERSION` 0.14.0; `BACKLOG.md` adds 2 entries (mobile-verify-skill v0.14.1, pipeline-eta-from-timing-data v0.15) | T9 | S | 3 | yes |

**Wave 1:** T1, T2, T3 parallel.
**Wave 2:** T6 → T8 serialized (both touch CLAUDE.md / build.md respectively but T6 inventory must complete first for build.md grammar parity). T7 parallel alongside T6.
**Wave 3:** T9 → T10.

**autorun-shell-reviewer invocation** is baked into T8 itself (and into commands/build.md as Phase 3 hook); not a separate task.

## Followups.jsonl content (5 contract/tests/scope-cuts items per /check)

Routed to `docs/specs/pipeline-pacing-and-prefill/followups.jsonl` for /build Phase 0c consumption:

| finding_id | class | target_phase | summary |
|---|---|---|---|
| ck-pacing-009 | contract | (carved with mobile-verify) | Mobile classification narrow — moves to v0.14.1 spec |
| ck-pacing-010 | contract | build-inline | `--cumulative-only` output contract pinned + test (T3) |
| ck-pacing-011 | contract | build-inline | ETA wording change (drop "from rankings history") — folded into T2 + T6 |
| ck-pacing-012 | tests | build-inline | 5 missing test files + count reconcile — folded into T9 + AC22 |
| ck-pacing-013 | scope-cuts | build-inline | Drop `--session-only` flag — folded into T3 + D5 |

All 5 are addressed by tasks already in the plan; no new followups need /build re-derivation.

## Open Questions

None remaining. OQ4-OQ7 all resolved at /check iter1.

## Risk register (post-/check)

| # | Risk | Likelihood | Impact | Mitigation status |
|---|---|---|---|---|
| ~~R1~~ | tab-prefill empty-Enter | — | — | RESOLVED via spike; Item 4 dropped |
| ~~R2~~ | mobile-verify detection misses valid project | — | — | N/A; mobile-verify carved to v0.14.1 |
| R3 | banner stderr breaks fence-extractor | low | high | AC18 + integration test (test-banner-autorun-stderr.sh) |
| R4 | `.last-compact-suggestion` JSON parse error | low | low | D3 fail-open contract |
| ~~R5~~ | session-cost flag conflict | — | — | RESOLVED via pinned output contract (D5 / AC21) |
| R6 | Wave 2 T6 8-file splice drift | medium | low | Inventory-first manifest (D9) + AC1b inventory test |
| ~~R7~~ | bash 3.2 incompat | — | — | RESOLVED via expanded D1 + AC20 |
| ~~R8~~ | autorun-shell-reviewer Wave 3 block | — | — | RESOLVED — wired into T8/D10 directly |

3 active risks (R3, R4, R6) all with explicit AC-level mitigations.

## Codex critique placeholder

Codex critique ran at /check Phase 2b and produced NO-GO with 7 findings (full
text at `check/raw/codex-adversary.md`). All 7 addressed in the iter2 inline
fix set above. Codex re-run not needed pre-/build; will run again at /check
iter2 verdict re-emit if requested.
