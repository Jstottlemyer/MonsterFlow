# Phase 0 Spike Q1 — Result

**Question:** Does the parent session's `Agent` tool_result trailing-text annotation
(`<usage>total_tokens: N</usage>`) equal the sum of `usage` blocks across all
assistant rows in the linked `subagents/agent-<agentId>.jsonl` transcript?

## Source paths examined

- Parent JSONL: `~/.claude/projects/-Users-jstottlemyer-Projects-RedRabbit/42dcaafa-1fbb-4d52-9344-1899381a205c.jsonl` (6427 lines, 73 Agent dispatches)
- Subagent transcript: `~/.claude/projects/-Users-jstottlemyer-Projects-RedRabbit/42dcaafa-1fbb-4d52-9344-1899381a205c/subagents/agent-a7a7e0fffe160b273.jsonl`
- Meta sidecar: `~/.claude/projects/-Users-jstottlemyer-Projects-RedRabbit/42dcaafa-1fbb-4d52-9344-1899381a205c/subagents/agent-a7a7e0fffe160b273.meta.json` → `{agentType: general-purpose, description: Requirements reviewer}`

## Probe dispatch

- Tool-use ID (parent): `toolu_01KhtYFfgLt5pwJMMTT4HTUD` (line 344 of parent JSONL)
- Persona prompt fragment: `personas/review/requirements.md` (regex-recoverable, matches spec §Phase 0 Q-on-persona-recovery)
- Linkage: parent's tool_result trailing text reads `agentId: a7a7e0fffe160b273\n<usage>total_tokens: 37759\ntool_uses: 3\nduration_ms: 64888</usage>`

## Measurements (concrete tuple)

| Source | Computation | Tokens |
|---|---|---|
| `parent_total_tokens` (annotation) | parsed from tool_result trailing text | **37759** |
| `subagent_sum` — narrow (sum input+output across 5 assistant rows) | 25 + 3289 | 3314 |
| `subagent_sum` — broad (sum input+output+cache_read+cache_create across 5 assistant rows) | 25 + 3289 + 15571 + 81472 | 100357 |
| `subagent_sum` — **final-row** (input+output+cache_read+cache_create from the LAST assistant row only) | 1 + 2999 + 15571 + 19188 | **37759** |

| (parent_total_tokens, subagent_final_row_sum, delta) | **(37759, 37759, 0)** |

Per-row breakdown (subagents/agent-a7a7e0fffe160b273.jsonl):

| line | input | output | cache_read | cache_create | broad_sum |
|---|---|---|---|---|---|
| 2 | 6 | 4 | 0 | 15571 | 15581 |
| 3 | 6 | 4 | 0 | 15571 | 15581 |
| 5 | 6 | 4 | 0 | 15571 | 15581 |
| 7 | 6 | 278 | 0 | 15571 | 15855 |
| 9 | 1 | 2999 | 15571 | 19188 | **37759** |

## Interpretation

The Anthropic API exposes per-message `usage` as the **cumulative state at that
turn** — `cache_read_input_tokens` and `cache_creation_input_tokens` re-appear
across rows because the same cache blocks get re-billed (or re-referenced) on
each subsequent assistant turn. Naively summing every row's broad usage
**double-counts** cache. The parent-session annotation `total_tokens: 37759` is
identical to the **final** assistant row's broad sum, which is the
billing-truthful number Anthropic reports for that subagent invocation.

## Verdict

Verdict: Q1 CLOSED — parent annotation is canonical (cheap path).

**Q1 CLOSED — parent annotation is canonical (cheap path).** The parent
session's `<usage>total_tokens: N</usage>` annotation equals the final
assistant row of the corresponding `subagents/agent-<id>.jsonl` (delta = 0
on the probed dispatch). Row-by-row summation across the subagent transcript
**must not** be used as an independent verification — it conflates per-turn
cumulative `usage` reporting with per-turn incremental cost and produces a
broad sum 2.66× larger than truth on this fixture.

## Recommendation for `compute-persona-value.py` cost-walk

1. **Primary path:** parse `total_tokens: N` from the parent's `Agent`
   tool_result trailing text. Treat this as authoritative cost per dispatch.
   Cheap: one regex on the parent JSONL, no subagent file open required for
   cost.
2. **Subagent file usage limited to:** linkage validation + persona recovery
   sanity-check (`agent-<id>.meta.json` description match) + duration. The
   `subagents/agent-<id>.jsonl` body is NOT a cost source for v1.
3. **A1.5 verifier (still required by spec):** when both surfaces are
   readable, compare parent annotation vs. final-assistant-row broad sum
   (input+output+cache_read+cache_create) of the linked transcript. Tolerance
   = 0 tokens (this probe shows exact equality). On disagreement on any
   future fixture: A1.5 fails the build, `/plan` re-opens Q1, and the cost
   walk falls back to the final-row reading from the subagent transcript
   (still cheap; one-row tail-read).
4. **Do not** sum the full subagent transcript broad usage. Document this
   in the script as `# WARN: per-row usage is cumulative, not incremental`.

Probe captured 2026-05-03 by Wave 0 Agent A under /build for token-economics v4.2.
