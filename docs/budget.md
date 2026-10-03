---
title: Agent Budget
created: 2026-05-04
status: reference
---

# Agent Budget

Cap how many Claude personas run per gate (`/spec-review`, `/plan`, `/check`).
Lower = fewer parallel reviewers, fewer tokens; higher = more dimensions of
review per artifact. Codex-adversary is **additive** — never counted against
the budget.

This is the user-facing reference. Source of intent is
[`docs/specs/account-type-agent-scaling/spec.md`](specs/account-type-agent-scaling/spec.md).
The plan with implementation detail is at
[`docs/specs/account-type-agent-scaling/plan.md`](specs/account-type-agent-scaling/plan.md).

## TL;DR

```bash
# Set or change budget
bash install.sh --reconfigure-budget

# Inspect what would be selected for a gate
bash scripts/resolve-personas.sh check --feature my-feature --why

# Emergency kill switch — restore full roster for one run
MONSTERFLOW_DISABLE_BUDGET=1 autorun
```

## Config file

Path: `~/.config/monsterflow/config.json` (machine-local; gitignored;
file mode 0644; directory mode 0755).

Example:

```json
{
  "$schema_version": 1,
  "agent_budget": 3,
  "persona_pins": {
    "spec-review": ["requirements"],
    "plan": ["integration"],
    "check": ["scope-discipline"]
  },
  "codex_disabled": false,
  "tier_hint": "pro"
}
```

### Schema

<!-- BEGIN schema (auto-generated; do not hand-edit between sentinels) -->
<!-- Regenerate via: bash scripts/resolve-personas.sh --print-schema -->
```json
{
  "$schema_version": 1,
  "type": "object",
  "properties": {
    "$schema_version": {"type": "integer", "const": 1},
    "agent_budget": {"type": "integer", "minimum": 1, "maximum": 8},
    "persona_pins": {
      "type": "object",
      "additionalProperties": {
        "type": "array",
        "items": {"type": "string"}
      }
    },
    "codex_disabled": {"type": "boolean"},
    "tier_hint": {"type": "string"},
    "build_workers": {"type": "string", "enum": ["claude", "codex"]},
    "codex_worker_model": {"type": "string"}
  },
  "additionalProperties": true
}
```
<!-- END schema -->

### Keys

| Key | Type | Default | Notes |
|-----|------|---------|-------|
| `$schema_version` | int | `1` | Reserved for future schema migrations |
| `agent_budget` | int (1–8) | absent (= full roster) | Per-gate cap. Floor 1, ceiling 8 |
| `persona_pins` | object | `{}` | Per-gate pin lists. Each entry validated against on-disk personas |
| `codex_disabled` | bool | `false` | Set `true` to opt out of Codex even when authenticated |
| `tier_hint` | string | absent | Display-only context (e.g. `"pro"`, `"free-or-max"`) |
| `build_workers` | `"claude"` \| `"codex"` | `"claude"` | Who implements `/build` tasks. `codex` routes each task to a Codex CLI worker through `scripts/build-codex-worker.sh`; the orchestrator still verifies, commits and owns remote actions. See `commands/build.md` Phase 2 |
| `codex_worker_model` | string | absent (Codex default) | Model for Codex `/build` workers, passed as `codex exec -m`. Check it with `scripts/build-codex-worker.sh --probe-model` |

Unknown top-level keys are preserved across writes (read-modify-write
in `install.sh`), enabling forward-compat with future shared config.

## Per-gate seed lists

Used as the fallback when `dashboard/data/persona-rankings.jsonl` has no
qualifying rows for a gate. Order matters — index 0 is the budget=1 default
when no pin is configured.

| Gate | Persona dir | Seed order |
|------|-------------|-----------|
| `spec-review` | `personas/review/` | requirements, gaps, scope, ambiguity, feasibility, stakeholders |
| `plan` | `personas/plan/` | integration, api, data-model, security, ux, scalability, wave-sequencer |
| `check` | `personas/check/` | scope-discipline, risk, completeness, sequencing, testability |

> The plan-gate seed contains 7 personas, all present on disk.
> Note: `personas/plan/risk.md` does **not** exist — the plan-gate seed
> never includes `risk`.

The "qualifying row" definition (locked in spec):
- `row.gate == <gate>`
- `row.insufficient_sample == false`
- `row.persona != "codex-adversary"` (Codex is additive)
- `personas/<gate-dir>/<row.persona>.md` exists on disk

## Codex-adversary rule

`codex-adversary` is appended to the resolver output as an **extra last line**
when ALL of the following hold:

1. `codex` binary is on `$PATH`.
2. `codex login status` exits 0 (cached for 60s in `~/.cache/monsterflow/codex-auth.<bucket>`).
3. `codex_disabled` in config is `false` (or absent).

It is never ranked, never counted against `agent_budget`, never selected
during the budget cap. Setting `codex_disabled: true` skips the auth probe
entirely.

## Reset paths

Three equivalent ways to change your budget. All write the same config file
through the same Q&A function, so they cannot drift.

### 1. Re-run the installer flag

```bash
bash install.sh --reconfigure-budget
```

Short-circuits all other install steps. Asks Pro y/N → budget → 3× pin
prompts. Validates pins against on-disk personas; rejects typos.

### 2. Tell Claude

In a Claude Code session, say:

> Reconfigure my agent budget

Claude invokes `bash install.sh --reconfigure-budget` — no paraphrased
prompts, single source of truth.

### 3. Edit config.json directly

```bash
$EDITOR ~/.config/monsterflow/config.json
```

Validate after editing:

```bash
bash scripts/resolve-personas.sh check --feature my-feature --why
```

## Selection audit (`selection.json`)

Every gate run writes `docs/specs/<feature>/<gate>/selection.json` (gitignored).
This is read by `persona-metrics-validator` and `/wrap-insights` to distinguish
*budget-dropped* personas from *failed-to-run* personas — preventing the
drift baseline from collapsing post-rollout.

Example:

```json
{
  "schema_version": 1,
  "feature": "account-type-agent-scaling",
  "gate": "check",
  "ran_at": "2026-05-04T08:12:00Z",
  "selection_method": "rankings",
  "selected": ["scope-discipline", "risk", "completeness"],
  "dropped": ["sequencing", "testability"],
  "dropped_pins": [],
  "codex_status": "appended",
  "budget_used": 3,
  "budget_source": "config",
  "locked_from": null,
  "resolver_exit": 0
}
```

`selection_method ∈ {full, rankings, seed, locked}`.
`codex_status ∈ {appended, not_authenticated, missing_binary, disabled, failed}`.

## Per-feature lock (`.budget-lock.json`)

Created on the first budgeted gate run for a feature. Subsequent gates within
the same feature read this file in preference to live `config.json`, so a
mid-pipeline edit can't produce inconsistent rosters across gates.

```bash
# Force a re-lock from current config
bash scripts/resolve-personas.sh check --feature my-feature --unlock-budget
```

The lock is gitignored and machine-local. Never created when `agent_budget`
is absent (existing-user full-roster path stays config-free).

## Troubleshooting

### Why did my gate only run N personas?

Run with `--why`:

```bash
bash scripts/resolve-personas.sh <gate> --feature <slug> --why
```

The stderr output shows: config path, lock state, on-disk personas,
ranking matches, selected/dropped split, Codex status, and the selection
method that fired.

### Resolver fails under autorun

Per spec AC #8, autorun aborts with non-zero exit (no silent fallback).
Common causes:
- Malformed `~/.config/monsterflow/config.json` (exit 2)
- All personas filtered out + empty seed (exit 3) — usually means
  `personas/<gate-dir>/` is missing files
- Internal error (exit 5)

To dispatch the full roster bypassing all budget logic for one run:

```bash
MONSTERFLOW_DISABLE_BUDGET=1 autorun
```

This is an **emergency kill switch** — leaves config untouched.

### Resolver fails interactively (AC #7)

In an interactive session (TTY attached, `AUTORUN` unset), the gate command
applies `commands/_prompts/_resolver-recovery.md` instead of aborting. The
canonical fragment presents three options:

```
Resolver script failed (exit <N>). Options:
  (1) reconfigure now    — re-run install.sh --reconfigure-budget, then retry the gate
  (2) continue with seed — dispatch the per-gate seed list (no rankings, no pins)
  (3) abort gate         — exit non-zero, leave config untouched

Choose [1/2/3]:
```

- **Option (1)** invokes `install.sh --reconfigure-budget` in the foreground
  and re-runs the resolver once. One retry only — looping prompts on
  repeated failure leads to infinite loops in flaky environments.
- **Option (2)** fetches the seed list via
  `bash scripts/resolve-personas.sh <gate> --print-seed` and proceeds with
  dispatch. No rankings, no pins, no Codex (the resolver owns the auth
  probe). Prints a one-line warning so the seed-mode run is auditable.
- **Option (3)** exits non-zero with the resolver's exit code.

Plan decision **D6** drops the originally-spec'd "disable budget for this
run" option (which would have silently restored the full roster) — that
behavior contradicted AC #7's no-silent-restore clause. The kill switch is
now the explicit env var `MONSTERFLOW_DISABLE_BUDGET=1`, set by the user
before the gate runs.

### "pin '<name>' not found in personas/<gate>/"

You configured a pin that doesn't match a `.md` file on disk. The
resolver skips the pin (with stderr warning) and fills the slot from
rankings/seed. Fix:

```bash
bash install.sh --reconfigure-budget   # the Q&A validates against disk
```

## Defaults & limits

- Budget: integer 1–8 (`install.sh` rejects ≤0 and warns on >8 → caps to 8;
  resolver enforces same range at runtime).
- Default budget at install: `3` (Pro plan), `6` (free or Max).
- Budget=1 default per gate: index 0 of the seed list (`requirements`,
  `integration`, `scope-discipline`).
- macOS only (matches token-economics v1 platform target). Linux is
  out-of-scope for v1; tracked in BACKLOG.md.

## v1 limitations

- No per-project override (single machine-local config).
- No per-gate budget (one int caps all three gates).
- No auto-detect of Claude account tier (none of `claude config`,
  statusLine JSON, or any other CLI surface exposes the plan tier —
  verified empirically).
- The `tier_hint` key is display-only; it does not change behavior.

## See also

- [`docs/specs/account-type-agent-scaling/spec.md`](specs/account-type-agent-scaling/spec.md) — full spec
- [`docs/specs/account-type-agent-scaling/plan.md`](specs/account-type-agent-scaling/plan.md) — implementation plan
- [`docs/specs/persona-metrics/spec.md`](specs/persona-metrics/spec.md) — drift analysis that reads `selection.json`
