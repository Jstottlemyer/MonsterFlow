## Scalability Persona — dynamic-roster-per-gate

### Key Considerations

**Hot path overhead accumulates.** The resolver runs at every gate invocation (6 sites). Each call incurs: `_tag_baseline.py` parse + `persona-rankings.jsonl` read + `_tier_assign.py` validation. Without caching, I/O alone can push past 500ms on a cold filesystem.

**`persona-rankings.jsonl` read amplification.** If the resolver spawns one Python process per persona to get its ranking, a 10-persona gate makes 10 subprocess calls. File must be read once, cached in-process or passed as a temp file.

**Concurrent write non-issue (SF-5 addressed).** `selection.json` is written by the resolver (single writer, single output, before dispatch). No concurrent writes occur. Add 7 concurrent-read fixtures covering parallel autorun's `&`-backgrounded dispatcher.

**Synthesis timeout (SF-1).** 1800s stage timeout at `/plan` synthesis is adequate for current spec sizes. Binding constraint is the slowest single persona (parallel execution), not sum.

### Options Explored

- Per-invocation subprocess vs. single batched Python call: single call wins (one `python3 _resolve_batch.py` per gate vs. N calls).
- In-memory cache vs. file lock: not needed (single writer, read-only consumers).

### Recommendations

1. Batch all resolver Python work into one subprocess call per gate dispatch. One process reads `persona-rankings.jsonl`, computes fit+tier for all personas, writes `selection.json`.
2. Cache `persona-rankings.jsonl` read via temp variable — assign once, pass as arg.
3. Default missing `lineage` to `"claude"` at read time; no backfill scan.
4. Add 7 concurrent-read fixtures (total ≥40 across suite) simulating parallel autorun.

### Constraints Identified

- `_tag_baseline.py` must remain AST-banned from `eval`/`exec`/`subprocess`/`socket`. Regex-only keeps it under 100ms for 10K chars.
- Test suite <15s wall-clock with ≥33 fixtures achievable only if fixtures avoid real `claude -p` calls (stubs required).

### Open Questions

- Is `persona-rankings.jsonl` ever written mid-dispatch (e.g., by a concurrent `/wrap` session)? If yes, resolver needs advisory `flock` on read.
- Does the plan specify a max persona count per gate? Bounding this bounds worst-case resolver time.

### Integration Points

- `scripts/resolve-personas.sh` calls the resolver batch as one subprocess, not three separate ones.
- `_tag_baseline.py` feeds tag set into the batch script via stdout (pipe), not a temp file.
- Autorun `&`-backgrounded dispatch reads `selection.json` (read-only after resolver writes it); no coordination needed.
