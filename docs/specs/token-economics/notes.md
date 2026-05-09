# Token Economics — Operator Notes

Companion runbook to `spec.md` v4.2. One-page; covers what the spec doesn't say in prose: how to read the dashboard, how to recover from failure modes, what the numbers do and don't mean.

## What this is, what it isn't

`compute-persona-value.py` produces a snapshot of how each persona has been performing on **this machine**, across discovered MonsterFlow projects. It is:

- **Sample-noisy.** A persona that ran 3 times in the window (the minimum for `insufficient_sample: false`) is showing a 3-sample rate. Treat it as directional, not authoritative.
- **Machine-local.** Each machine maintains its own window. `dashboard/data/persona-rankings.jsonl` is gitignored. Running on multiple machines does not pool data — that's `v1.1+` scope.
- **Not a personal evaluation.** Scores reflect prompt-and-Judge interactions on aggregate work, not the persona author's craft. A low judge-retention ratio often means the persona's bullets cluster heavily (Judge merging is correct) — not that they're wrong.

The only honest summary is: this dashboard is a tool for **you** to ask "is this persona pulling its weight on the kinds of work I'm doing right now?"

## Interpreting low scores

| Symptom | Likely cause | Confirm by |
|---|---|---|
| `judge_retention_ratio` near 0 | Persona emits many bullets that Judge clusters together (one finding from N bullets). NOT a quality signal. | Look at one of the persona's `findings.jsonl` entries — does Judge's title cover several of the persona's raw bullets? |
| `downstream_survival_rate` near 0 | Findings exist but downstream stages don't address them. Either the persona is raising things outside the actual blast radius, OR `survival.jsonl` hasn't been written for that gate yet. | Check `run_state_counts.missing_survival` — if non-trivial, low rate is a **timing artifact**, not a value signal. |
| `uniqueness_rate` near 0 | This persona overlaps with others on the same gate. May be redundant in the current roster, OR may be a generalist that intentionally restates. | Compare with adjacent personas on the same gate — if one strict subset, consider pruning. |
| `silent_runs_count` high | Persona ran successfully but raised nothing. Healthy in moderation; suspicious if dominant. | If `silent_runs_count > complete_value` count, the persona may be over-narrow on this project's work. |

Do **not** prune personas based solely on these scores. Rankings are inputs to a discussion, not decisions.

## Salt rotation procedure

`finding-id-salt` lives at `${XDG_CONFIG_HOME:-$HOME/.config}/monsterflow/finding-id-salt` (32 bytes, chmod 600). It defines the namespace for `contributing_finding_ids[]` drill-down.

**When to rotate:**

- After accidental disclosure of a JSONL file (the salted IDs are local-only but rotation closes any lingering correlation paths).
- Suspected file-perm tampering (perm 0o644 instead of 0o600 — the script auto-detects and regenerates, but you can pre-empt).
- Migrating to a new machine when you want a clean drill-down namespace.

**How to rotate (manual):**

```bash
rm "${XDG_CONFIG_HOME:-$HOME/.config}/monsterflow/finding-id-salt"
# Next /wrap-insights run regenerates a fresh 32-byte salt and CLEARS:
#   dashboard/data/persona-rankings.jsonl
#   dashboard/data/persona-rankings-bundle.js
#   dashboard/data/persona-insights-bundle.js (if present)
# Drill-down continuity is reset by design — old IDs no longer link.
```

The script defaults to **automatic regen-and-clear** on validation failure (size != 32, mode != 0o600, all-zero bytes, missing). If you want regen to require explicit confirmation in a future v1.1+, see `followups.jsonl` MF-3.

## `--scan-projects-root` first-time walkthrough

Default discovery is conservative: cwd only.

To opt in to scanning a parent directory of project repos:

```bash
# Interactive (TTY required):
scripts/compute-persona-value.py --scan-projects-root ~/Projects

# Non-interactive (tmux pipe-pane, dev-session.sh, autorun):
scripts/compute-persona-value.py --confirm-scan-roots ~/Projects
# Then on subsequent runs, the regular invocation skips the prompt.
```

The first interactive invocation prints discovered project paths to stderr and prompts:

```
Confirm scan of these N roots? Append to scan-roots.confirmed? [y/N]
```

`y` appends to `${XDG_CONFIG_HOME:-$HOME/.config}/monsterflow/scan-roots.confirmed` (chmod 600). `N` exits, no scan, no append.

Per-project opt-out: place an empty `.monsterflow-no-scan` file at any project root to silently exclude it from tier-3 scanning regardless of `scan-roots.confirmed`.

## Multi-machine semantics

The JSONL is gitignored. There is no merge across machines. `persona_content_hash` reflects the persona file's content at the time of the most-recent run **on this machine** — it does not detect whether a different machine ran a different version.

If you want cross-machine aggregation: that's tracked in BACKLOG (post-v1.1).

## Linux disclaimer

`compute-persona-value.py` is tested on macOS only. The code uses POSIX primitives (`os.replace`, `O_CREAT|O_EXCL`, `os.urandom`) that should work on Linux, but no CI coverage exists yet. Patches welcome.

## v1.1 unblock criterion

This v1 ships measurement only. The v1.1 spec (account-type agent scaling, BACKLOG #3) unblocks when the data has accumulated enough to be useful for decisions:

- **≥10 personas per gate** have `runs_in_window ≥ 3` within a 30-day window.
- At least one persona shows a clearly outlier `downstream_survival_rate` (high or low) that operator considers actionable.

Until both hold, v1.1 stays parked.

## When to call `persona-metrics-validator`

The `persona-metrics-validator` subagent (defined at `.claude/agents/persona-metrics-validator.md`) does a read-only audit of the freshly emitted `persona-rankings.jsonl`:

- Schema correctness against `schemas/persona-rankings.allowlist.json`.
- Joinable foreign keys (`contributing_finding_ids[]` resolve to known findings).
- `artifact_hash` freshness across `docs/specs/*/{spec-review,plan,check}/`.

Invoke it after any `/wrap-insights` run that produces suspect drift (a persona suddenly at 0%, all features showing `artifact_hash` mismatches, etc.):

```
Agent(subagent_type: "persona-metrics-validator")
```

It's read-only. Run on demand; it isn't auto-scheduled.
