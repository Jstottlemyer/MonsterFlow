# PRE-W2 dispatch precedence evidence (append-only)

This file records every model-param routing probe + every wrapper-pivot
runtime model-id assertion outcome. Append-only by convention. Schema:

| date | context | invocation | --model arg | response model-id | match |

Probe legend:
- context: opus-parent | sonnet-parent | claude-p-headless
- match: Y (response model-id == --model arg) | N (mismatch) | MISSING (no model field)

PRE-W2 verdict (set after all 3 cells recorded):
- All YES → D4 architecture (Agent tool model: param)
- (opus-parent NO) + (sonnet-parent + claude-p-headless YES) → wrapper-script pivot per Open Q#1
- Any mixed outcome → FLAKY → halt and escalate
- All NO → carve W4 to follow-up

## Evidence rows

Note on `response model-id` extraction: `claude -p --output-format json` does
not emit a top-level `model` field. The authoritative response field is
`modelUsage` (object), whose top-level key is the model id the CLI actually
billed against. All three probes below extract from `modelUsage.<key>`.

| date | context | invocation | --model arg | response model-id | match |
|------|---------|------------|-------------|-------------------|-------|
| 2026-05-12 | opus-parent | `claude -p --model claude-opus-4-5 --output-format json 'Reply exactly: PROBE_RESPONSE'` | claude-opus-4-5 | claude-opus-4-5 (via `modelUsage`) | Y |
| 2026-05-12 | sonnet-parent | `claude -p --model claude-sonnet-4-6 --output-format json 'Reply exactly: PROBE_RESPONSE'` | claude-sonnet-4-6 | claude-sonnet-4-6 (via `modelUsage`) | Y |
| 2026-05-12 | claude-p-headless | `claude -p --model claude-opus-4-5 --output-format json 'Reply exactly: PROBE_RESPONSE_HEADLESS'` | claude-opus-4-5 | claude-opus-4-5 (via `modelUsage`) | Y |

Session IDs (for audit trail):
- opus-parent: 35210b8c-7c5d-4d5f-a8e4-37eed382e4f5
- sonnet-parent: 20d98245-61be-470f-b6ba-5295734a0af5
- claude-p-headless: 93765879-0971-40d9-ac5c-f1835b6e81fc

CLI version: 2.1.139 (Claude Code)

## Verdict

**PRE-W2 verdict: YES (D4 architecture proceeds)**

All three cells confirm `--model` arg routing is honored by the CLI: the
response `modelUsage` top-level key equals the requested model id in every
case. The Agent-tool `model:` param architecture (D4) is unblocked for W2.

Caveat for future probes: if a future CLI version re-introduces a top-level
`model` field in JSON output, prefer that for assertions; until then,
`modelUsage` is the authoritative source.
