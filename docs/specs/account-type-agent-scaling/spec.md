---
name: account-type-agent-scaling
description: Per-gate agent budget cap — scale persona roster by user-configured budget, with rankings-based selection and Codex as an additive reviewer
created: 2026-05-04
status: shipped
session_roster: defaults-only (no constitution)
---

# Account-Type Agent Scaling Spec

**Created:** 2026-05-04
**Constitution:** none — session roster only
**Confidence:** Scope 0.92 / UX 0.91 / Data 0.90 / Integration 0.88 / Edges 0.91 / Acceptance 0.90

> Session roster only — run /kickoff later to make this a persistent constitution.

## Summary

Add a user-configurable agent budget that caps how many Claude personas run per gate (`/spec-review`, `/plan`, `/check`). A helper script (`scripts/resolve-personas.sh`) reads `~/.config/monsterflow/config.json` and selects top-N personas from persona-rankings.jsonl, falling back to a fixed per-gate seed list when rankings are absent. Codex-adversary is always additive on top of the budget (not counted against it) when Codex is authenticated. Budget and priority pins are set interactively via `install.sh` and can be reset at any time.

**Sequencing:** ships after token-economics v1 (`docs/specs/token-economics/spec.md`) is live and producing ranking data. The feature is useful without ranking data (seed list is the fallback) but ranking-based selection requires ≥1 completed run.

## Backlog Routing

| # | Item | Source | Routing |
|---|------|--------|---------|
| 1 | Per-plugin cost measurement | BACKLOG.md | (b) Stays — independent methodology, different precondition |
| 2 | Plugin scoping per gate | BACKLOG.md | (b) Stays — depends on per-plugin cost data |
| 3 | Inter-agent debate / Agent Teams | BACKLOG.md | (b) Stays — L-size research, separate spec after this one |

Backlog items 1–3 are unrelated to per-gate persona budgeting and stay in BACKLOG.md.

## Scope

**In scope:**
- `~/.config/monsterflow/config.json` — stores `agent_budget` (integer ≥ 1) and `persona_pins` (per-gate override lists).
- `scripts/resolve-personas.sh <gate>` — reads config + persona-rankings.jsonl, outputs newline-separated persona list capped at budget. Codex-adversary is output as a separate line only if `codex login status` exits 0.
- `install.sh` Q&A additions — budget prompt + per-gate pin prompt at setup. Minimal questions; defer deep tuning to `--reconfigure-budget`.
- `install.sh --reconfigure-budget` flag — re-runs only the budget/pin Q&A, overwrites config.json.
- "Tell Claude to reconfigure" path — Claude reads config.json, runs Q&A inline, writes result.
- Budget and config location documented in QUICKSTART.md and a new `docs/budget.md` reference page.
- All three gate commands updated to call `resolve-personas.sh` in their pre-flight.
- Gate stdout shows selected personas + dropped personas at dispatch time (transparency).
- Interactive recovery prompt on resolver script error (interactive sessions only).

**Out of scope:**
- Auto-detecting account tier from any API or CLI surface (not exposed — confirmed empirically).
- Per-plugin cost measurement or plugin scoping (separate BACKLOG items).
- Roster pruning or auto-removal of low-ranking personas from the repository.
- Per-project config overrides (machine-local config only in v1).
- Linux support (macOS-only, same as token-economics v1).

## Approach

User-configured budget integer, set interactively at install time and stored in a machine-local JSON config. A helper shell script resolves the final persona list at gate dispatch time using rankings data when available, a fixed seed list as fallback. Codex is additive and never counted against the budget.

Alternatives considered:
- **Auto-detect tier from CLI** — rejected; `claude config` has no tier/plan field (verified), and the statusLine JSON only exposes `used_percentage`, not the absolute ceiling.
- **Budget as env var only** — rejected in favor of structured config file; a persona pin list is not a natural env var, and the config file is not a secret.
- **Fixed priority list, no rankings** — rejected; rankings-based selection is the goal. Seed list is the fallback, not the primary mechanism.

## UX / User Flow

### First-time setup (install.sh)
1. install.sh detects it's configuring a new user (or `--reconfigure-budget` flag is passed).
2. Prompts: *"Are you on the Claude Pro plan ($20/mo)? Pro accounts have tighter rate limits."*
3. If yes: *"How many Claude personas per gate? (default: 3, minimum: 1, maximum: 8)"*
4. If no: *"How many Claude personas per gate? (default: 6, minimum: 1, maximum: 8)"*
5. Prompts per gate: *"Which persona should always run in spec-review? (default: requirements)"* etc.
6. Writes `~/.config/monsterflow/config.json`. Shows confirmation: *"Budget set to N. Config at ~/.config/monsterflow/config.json — edit directly or run `install.sh --reconfigure-budget` to change."*
7. Notes: *"Codex-adversary runs in addition to your budget when Codex is authenticated."*

### Gate dispatch (every gate run)
1. Gate command calls `bash scripts/resolve-personas.sh <gate>` in pre-flight.
2. Script outputs selected Claude personas + (optionally) `codex-adversary`.
3. Gate stdout prints: `Selected: requirements, gaps, codex-adversary | Dropped: ambiguity, feasibility, scope, stakeholders`
4. Gate dispatches only the selected personas.

### Reconfiguring
- Run `install.sh --reconfigure-budget` → re-runs steps 2–6 above.
- Tell Claude: *"Reconfigure my agent budget"* → Claude reads config.json, runs Q&A inline, writes result.
- Manual edit: open `~/.config/monsterflow/config.json` directly (schema documented in `docs/budget.md`).

### Recovery on resolver failure
- Interactive (TTY, AUTORUN unset): *"Resolver script failed. Options: (1) reconfigure now, (2) continue with seed list, (3) disable budget for this run."*
- Non-tty / autorun (`AUTORUN=1` or stdin not a TTY): **resolver exits non-zero; gate ABORTS.** No silent fallback. Per `feedback_dryrun_full_graph.md`: stages must not "succeed" with reduced behavior. Operator must fix config and re-run. Kill switch: `MONSTERFLOW_DISABLE_BUDGET=1` (env) bypasses budget entirely and dispatches the full roster.

## Data & State

### Config file: `~/.config/monsterflow/config.json`

```json
{
  "agent_budget": 3,
  "persona_pins": {
    "spec-review": ["requirements"],
    "plan": ["risk"],
    "check": ["scope-discipline"]
  }
}
```

- `agent_budget`: integer, 1–8. Default: 6. Maximum: 8 (enforced at write time with a warning: "8 is the maximum — using 8"). Validated at write time — 0 or negative is rejected.
- `persona_pins`: per-gate list of personas that always run first, regardless of rankings. Each list must fit within budget. User-editable.
- File does not exist → full roster up to 6 (default). Existing users see no change.

### Per-gate seed list (hardcoded fallback when rankings absent)

Used when `dashboard/data/persona-rankings.jsonl` has fewer than 1 qualifying row for the gate.

| Gate | Seed order |
|------|-----------|
| spec-review | requirements, gaps, scope, ambiguity, feasibility, stakeholders |
| plan | integration, api, data-model, security, ux, scalability, wave-sequencer |
| check | scope-discipline, risk, completeness, sequencing, testability |

Budget=1 minimum defaults: spec-review → `requirements`, plan → `integration`, check → `scope-discipline`. Shown to user at install and changeable.

> **Note:** `personas/plan/risk.md` does not exist on disk (verified 2026-05-04). The plan-gate seed list contains 7 personas, all present on disk. A future addition of `risk` to the plan roster would require: (a) creating `personas/plan/risk.md`, (b) updating this seed list, and (c) updating the SEED constant in `scripts/resolve-personas.sh`.

### Qualifying row (locked)

A row in `dashboard/data/persona-rankings.jsonl` is *qualifying for gate G* iff:
- `row.gate == G`
- `row.insufficient_sample == false`
- `row.persona != "codex-adversary"` (Codex is additive, never ranked into the budget)
- `personas/<G>/<row.persona>.md` exists on disk

### Full roster (locked)

The set of `*.md` files under `personas/<gate>/` (disk discovery, identical to autorun's existing discovery model). Used when `agent_budget` is unset/absent in the config — NOT the seed list. This preserves existing-user behavior with zero config.

### Codex-adversary rule
Codex is output by `resolve-personas.sh` as a separate entry only when `codex login status` exits 0. It is never counted against `agent_budget`. At budget=1, the effective minimum is: 1 Claude persona + codex-adversary (if authenticated).

## Integration

### Files modified
- `install.sh` — add budget Q&A block + `--reconfigure-budget` flag handler. Write to `~/.config/monsterflow/config.json`.
- `commands/spec-review.md` — add pre-flight call to `resolve-personas.sh spec-review`; replace hardcoded persona list with resolver output.
- `commands/plan.md` — same, `resolve-personas.sh plan`.
- `commands/check.md` — same, `resolve-personas.sh check`.
- `QUICKSTART.md` — add "Agent Budget" section explaining config location, key name, valid values, reset paths.

### Files created
- `scripts/resolve-personas.sh` — main resolver. Args: gate name. Reads config.json + persona-rankings.jsonl. Outputs persona list. Handles all edge cases (see Edge Cases). Exits non-zero only on unrecoverable error.
- `docs/budget.md` — reference page: config file schema, valid values, per-gate seed lists, Codex rule, reset instructions.
- `tests/test-resolve-personas.sh` — unit tests for the resolver (budget=1, budget=N, missing config, missing rankings, codex present/absent, script error paths).

### Dependencies
- `dashboard/data/persona-rankings.jsonl` — produced by token-economics v1. Must exist for rankings-based selection; absent = seed fallback (not an error).
- `codex` CLI — checked via `codex login status`. Not required; absence means Codex is simply not added.
- `~/.config/monsterflow/` directory — created by install.sh if absent. `config.json` is machine-local and gitignored.

## Edge Cases

| Case | Behavior |
|------|----------|
| config.json absent | Full roster dispatched. No warning. Existing behavior preserved. |
| `agent_budget` absent in config | Full roster dispatched. Treat as unconfigured. |
| `agent_budget` = 0 or negative | Rejected at config-write time with error. If somehow present at runtime, treated as 1 (floor). |
| `agent_budget` > 8 | Warned at config-write time ("8 is the maximum"); capped to 8. Runtime cap enforced at 8. |
| `agent_budget` > available personas for gate | All available personas dispatched. No error. |
| Rankings absent / < 1 qualifying row | Seed list used up to budget. Logged to stderr: "No rankings data — using seed list." |
| Codex not authenticated | Codex omitted silently. Budget-N Claude personas only. |
| Resolver script exits non-zero (interactive, TTY) | Recovery prompt: reconfigure / continue with seed / disable for this run. |
| Resolver script exits non-zero (non-tty / autorun) | Gate ABORTS with non-zero exit. No silent seed fallback. |
| `MONSTERFLOW_DISABLE_BUDGET=1` env set | Resolver bypasses budget entirely; dispatches full roster (kill switch for emergency). |
| Pin list longer than budget | Install Q&A validates and rejects. If somehow stored, pins are truncated to budget at runtime with a warning. |
| Persona in pins no longer exists | Skipped at runtime with a warning. Remaining budget filled from rankings/seed. |

## Acceptance Criteria

1. `config.json` absent or `agent_budget` unset → gate dispatches full roster; no behavior change for existing users.
2. `agent_budget=3` → gate dispatches exactly 3 Claude personas (pins first, then rankings top-N, then seed fill-up to 3).
3. `agent_budget=1` → gate dispatches exactly 1 Claude persona (the pin for that gate, or seed[0] if no pin).
4. Codex authenticated → codex-adversary appears in gate dispatch in addition to the budget count.
5. Codex not authenticated → codex-adversary absent; budget-N Claude personas only.
6. Rankings absent → seed list used; no error; stderr note.
7. Resolver script error (interactive, TTY) → recovery prompt with 3 options; none of them silently restore full roster on a budgeted session.
8. Resolver script error (non-tty / autorun) → resolver exits non-zero; gate ABORTS with non-zero exit code; consumer surfaces error. No silent seed fallback. Operator must fix config and re-run. (Kill switch: `MONSTERFLOW_DISABLE_BUDGET=1` env bypasses budget entirely → full roster.)
9. Gate stdout shows: selected personas + dropped personas before dispatch.
10. `install.sh --reconfigure-budget` → re-runs Q&A; overwrites config.json; prints confirmation with config file path.
11. "Tell Claude to reconfigure" → Claude runs Q&A, writes config.json, confirms.
12. Budget floor = 1, ceiling = 8. `install.sh` rejects ≤ 0 and warns on > 8 (caps to 8). Runtime floor enforced at 1; ceiling enforced at 8.
13. `docs/budget.md` documents: config file path (`~/.config/monsterflow/config.json`), key name (`agent_budget`), valid values (1–8, default 6, max 8), per-gate seed defaults, Codex rule, and all three reset paths.
14. All three gates produce consistent behavior from the same resolver script.

## Open Questions

None — confidence above threshold across all dimensions.

## Roster Changes

No roster changes — defaults-only session roster is sufficient for this pipeline-internal feature.
