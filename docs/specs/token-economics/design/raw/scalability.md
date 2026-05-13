# Scalability — token-economics /plan

**Persona:** scalability
**Lens:** Performance + bottleneck analysis at adopter scale.
**Reference numbers (this machine, sampled 2026-05-03):**
- `~/.claude/projects/` total: **341 MB**, 18 sanitized-cwd dirs, biggest single session JSONL **10 MB / 3,820 lines** (RedRabbit), typical busy session **1.4 MB / 700 lines**, idle session 16 KB.
- **927 subagent JSONLs** total across the tree; biggest **796 KB**, typical **60–150 KB**.
- `findings.jsonl` per gate: **8–24 KB** (well under streaming threshold).

## Key Considerations

1. **Two walks, very different cost profiles.** The cost walk (`~/.claude/projects/**/*.jsonl` + `subagents/agent-*.jsonl`) is the **hot path** — it reads MB-scale Claude session transcripts to find Agent dispatches. The value walk (`<project>/docs/specs/<feature>/<gate>/{findings,survival,run.json,raw/}`) is **trivial** — KB-scale per gate, dozens to low-hundreds of gates per project. Optimization effort should overwhelmingly target the cost walk.
2. **The dominant cost is JSON parse, not disk.** A 10 MB session JSONL with 3,820 lines is ~2,600 chars/line average. Python `json.loads` on a 2.6KB line takes ~30µs; whole-file parse ~115ms. Walking 100 such files = ~11s of pure parse time. Disk I/O on SSD at 1+ GB/s reads the whole 341 MB tree in <0.5s. **JSON parse dominates by ~20×.** This is what `<5s` refresh latency must beat.
3. **Most lines are not Agent dispatches.** A session with 73 Agent dispatches in 6,427 lines (RedRabbit fixture from spec) means ~99% of parsed lines get discarded by the filter `tool_use.name == "Agent"`. There is real upside in early-rejecting lines without full JSON parse (substring screen).
4. **Subagent JSONLs are only opened when needed.** The cost walk doesn't need to open all 927 subagent JSONLs upfront — only the ones whose `agentId` was referenced from a parent Agent dispatch in the current scan window. If A1.5 confirms parent annotation == subagent sum (the cheap path), **subagent JSONLs may not need to be opened at all** during the hot path; they become the canonical fallback only.
5. **The 45-window is small. The history is large.** Cost: 45 × ~28 personas × 3 gates ≈ **3,780 contributing artifact directories worst-case**. But each adopter's actual `docs/specs/` history is dozens of features × 3 gates each, not thousands. The window is a **cap**, not a typical size; on most machines the adopter has 5–30 features per project (15–90 gate-dirs), so window is rarely full. Cost walk has to scan **all** session JSONLs to find which ones contributed to the window's most-recent gate-dirs. **The walk is bounded by disk history, not by window size.**
6. **Adopter scale envelope.** Spec asks about 5 projects × 100 gates × 28 personas. Translating: 5 projects × 100 gates / 3 gates-per-feature ≈ 167 features. That's a heavy adopter. The 45-window caps the **per (persona, gate) row count**, but the walk still touches every session JSONL whose Agent dispatches fed those gates. Worst-case: ~500 session JSONLs, ~5 GB total transcript. At 11ms/MB parse = **55 seconds of parse**. **Misses the <5s target by 10×.**
7. **mtime-pruning is the only practical win.** A session JSONL whose mtime is older than the oldest gate-dir in the current 45-window cannot contribute. mtime check is ~1µs per file; even 5,000 files prunes in <10ms. Aggressive pruning likely cuts the working set 10–100×.
8. **Memoization opportunity is small but real.** Within a single `compute-persona-value.py` invocation, we might re-open a session JSONL once per persona-gate row computation. Easy to fix: scan each session JSONL exactly once into an in-memory `(persona, gate, parent_session_uuid) → tokens` table, then aggregate. **Cost-walk pass: 1× per file.**
9. **Atomic-write contention is a non-issue at adopter scale.** `os.replace` is atomic; two `/wrap-insights` racing produce two valid full snapshots, last writer wins. Spec already documents this. Concurrency limit is "human typing in two terminals" — i.e., 2, not 100.
10. **Memory ceiling worst-case (10 projects × 5 yr × 50 personas).** Working set during compute: per (persona, gate, parent_session_uuid) row at ~200 bytes serialized × ~5,000 rows = **~1 MB**. Even with 50 personas × 3 gates × 45 window = 6,750 output rows × ~1 KB JSON = ~7 MB output. **Memory is not a constraint.** The constraint is single-pass parse time over the input transcripts.
11. **Cold start = first run on an adopter machine with months of history.** No prior cache, no pruning baseline. May take 30–60s. **This is an acceptable one-time cost** if amortized via a parse cache (see Recommendation).
12. **Refresh latency target (<5s, Feasibility R3) needs definition.** Is it (a) p50 on a typical adopter (single project, 30 features), or (b) p95 on a heavy adopter (5 projects, 167 features)? They differ by 10×. Plan should assume (a) with explicit "may be slower on first run / heavy adopters" caveat in `/wrap-insights` output. (Open Question 1.)

## Options Explored (with pros/cons/effort)

### A. Naive — full re-parse every invocation (S, slow)
Walk all session JSONLs, parse every line, filter Agent dispatches, attribute tokens. Re-walk all `findings.jsonl` etc. Re-emit JSONL.
- **Pros:** dead simple; idempotency falls out for free; no cache invalidation bugs.
- **Cons:** ~55s on heavy adopter; misses <5s target. Re-parses unchanged historical data every time.
- **Effort:** S.
- **Verdict:** acceptable for v1 on **light** adopters (1 project, <30 features). Not viable for heavy.

### B. mtime-pruned single-pass (S+, fast on warm machines)
Same walk as A, but:
- Sort session JSONLs by mtime descending; stop walking once we've seen enough sessions to cover the 45-window's oldest gate-dir's `created_at`.
- Cache the (persona, gate, parent_session_uuid) → tokens table in-memory; never reopen a file.
- Substring pre-filter on each line: skip lines that don't contain `"name":"Agent"` before `json.loads`. Gets ~99% rejection at <1µs per line.
- **Pros:** likely brings heavy-adopter case under 5s; minimal code; no persistent cache to invalidate.
- **Cons:** still re-parses recent sessions every run (but those are the small set).
- **Effort:** S+. Substring screen + mtime sort are ~30 lines each.
- **Verdict:** **recommended baseline.**

### C. On-disk parse cache (M, fast even cold)
Persist a per-session-JSONL-path digest of `(parent_session_uuid, agentId, persona, gate, tokens)` rows to `~/.cache/monsterflow/cost-attribution/<sha1(path)>.json`. Invalidate by mtime or sha1. On rerun, only re-parse JSONLs whose mtime exceeds the cache stamp.
- **Pros:** truly cold-warm consistent; first run pays once; subsequent runs near-instant.
- **Cons:** cache invalidation complexity; adopter machine has another data dir to clean up; race conditions with concurrent runs; XDG path conventions to honor.
- **Effort:** M.
- **Verdict:** **defer to v1.1.** Premature for v1.

### D. Streaming JSON parser (M, marginal win)
Use `ijson` or hand-rolled streaming parser to avoid loading whole-line strings into Python objects when only `message.tool_use.name` is needed.
- **Pros:** could halve parse cost on Agent dispatches (most lines).
- **Cons:** new dependency (`ijson` is C-extension; not stdlib); spec says "no external deps" pattern in `session-cost.py`; complexity for marginal gain over option B's substring screen.
- **Effort:** M.
- **Verdict:** **rejected.** Option B's substring screen captures most of the win without dep cost.

### E. Parallelize the walk (M, fragile win)
`multiprocessing.Pool` over session JSONLs, then merge per-(persona, gate) tables.
- **Pros:** ~4× wall-clock on a 4-core machine.
- **Cons:** Python GIL doesn't matter (each worker re-parses), but startup cost is ~50–100ms per worker; for adopter case (~50 small files) overhead may exceed gain. Also breaks deterministic stderr telemetry ordering (A8 idempotency).
- **Effort:** M.
- **Verdict:** **rejected for v1.** Revisit if option B doesn't hit target.

### F. Bypass session-JSONL walk entirely; trust subagent dirs (S, partial)
Walk only `~/.claude/projects/*/*/subagents/agent-*.jsonl` (927 small files instead of session transcripts). Each subagent file already has full `usage` per row. Persona/gate recovery still needs the parent session prompt regex though — so can't fully bypass.
- **Pros:** subagent files are smaller and more uniform.
- **Cons:** linkage back to (persona, gate) requires parent prompt; can't avoid parent walk. Net wash.
- **Verdict:** **rejected.** Would need persona/gate captured at subagent-spawn time (v1.1+ proper-join work).

## Recommendation

**Adopt Option B for v1.** Specifically `compute-persona-value.py` shall:

1. **Project-discovery walk first.** Resolve roots via cascade (cwd + config + `--scan-projects-root`). For each root, walk `docs/specs/*/{spec-review,plan,check}/`. Read `run.json` for `created_at`. **Build the candidate gate-dir list, sort descending by `created_at`, take top 45 per (persona, gate) pair after computing per-row.** This step touches KB-scale files only; should complete in <500ms even at 10 projects × 167 features.
2. **Determine pruning horizon.** `oldest_window_created_at = MAX over (persona,gate) of MIN(created_at among that pair's 45 most-recent gate-dirs)`. Any session JSONL with mtime < `oldest_window_created_at - 24h` (24h slack for clock skew + late writes) is **skipped**.
3. **Cost-walk single pass.** Walk surviving session JSONLs in mtime order. For each line:
   - **Substring pre-filter:** skip if line doesn't contain `"Agent"` AND `"tool_use"`. Bench expectation: 99% rejection at ~0.5µs/line.
   - On match, `json.loads` and check `entry.message.content[*].tool_use.name == "Agent"`.
   - On Agent tool_use: regex-extract `personas/<gate>/<name>.md` from `input.prompt`.
   - On Agent tool_result: regex-extract `agentId: <16hex>` and `total_tokens: N` annotation.
   - Pair tool_use ↔ tool_result by `tool_use_id`; emit `(persona, gate, parent_session_uuid, tokens, agentId)`.
   - **Per-file in-memory dedupe** keyed on `tool_use_id` so re-runs over a streaming-appended JSONL are stable.
4. **Subagent fallback only on disagreement.** Per A1.5: if any (parent annotation == subagent sum) check fails for **any** dispatch in the fixture, the build fails and `/plan` re-opens Q1 — switching `compute-persona-value.py` to canonical subagent reads (open and sum `subagents/agent-<id>.jsonl`). Until then: do NOT open subagent files in the hot path. **Permanent cheap path is parent-annotation-only.**
5. **Aggregate + emit.** Join cost rows to value rows by `(persona, gate, parent_session_uuid → contributing_artifact_dirs)`. The mapping `parent_session_uuid → artifact_dir` comes from `run.json.session_id` if present, else best-effort fuzzy by `created_at` proximity (note open question Q3).
6. **Atomic write.** `os.replace` to final path. (Spec already requires this; just calling it out.)
7. **Telemetry.** stderr line includes `parsed N session JSONLs (M skipped via mtime), K Agent dispatches matched, Tms` — gives adopters an observability hook.

**Performance expectation (with B):**
- Light adopter (1 project, 30 features, ~50 sessions, ~50 MB): **<2s** end-to-end.
- Heavy adopter (5 projects, 167 features, ~500 sessions, but mtime-pruned to ~50 recent): **~3–5s.**
- Cold cache (no skip; first run on year-old history): **~30–60s.** Acceptable; print "(first scan, may take a moment)" line on stderr when scanning >100 sessions.

**`session-cost.py` extension scope:** add `--per-persona-attribution` flag emitting JSON `[{persona, gate, parent_session_uuid, tokens, agentId}, ...]` to stdout. `compute-persona-value.py` shells out to it (or imports it as a module). Reuses existing pricing/usage parsing; adds substring screen + mtime-pruning hooks. Keep both single-purpose; no big-rewrite.

**Memoization within run:** keep a `seen_paths: set[Path]` so the same JSONL is never opened twice in one invocation. Cheap to add, eliminates accidental N×M behavior if the cascade discovers overlapping roots.

**v1 pragmatism gates:**
- **Pragmatic (slow OK):** value walk over `findings.jsonl` etc. Already KB-scale. Don't over-engineer.
- **Pragmatic (slow OK):** A1.5 subagent fallback path — only invoked on build-test failure, not on every refresh.
- **Must be fast:** session JSONL walk + Agent dispatch attribution. This is the inner loop. Substring screen + mtime prune are mandatory, not optional.
- **Must be fast:** atomic write. Already cheap (`os.replace`).

## Constraints Identified

- **C1:** `<5s` refresh latency only achievable for typical adopters (≤30 features × ≤2 projects). Heavy adopters (`5 projects × 167 features`) need mtime-pruning to land in 3–5s; cold first-run on year-old history is 30–60s and that should be visible in stderr telemetry, not silent.
- **C2:** `compute-persona-value.py` must remain stdlib-only (no `ijson`, no `orjson`) to match `session-cost.py`'s "no external deps" precedent. Substring screen is the substitute.
- **C3:** Substring screen tokens (`"Agent"`, `"tool_use"`) must be quoted strings to avoid false matches in user prose. Verify on the leakage-canary fixture.
- **C4:** mtime-pruning has a clock-skew failure mode if adopter restored from backup or rsync'd between machines. 24h slack window mitigates; document that adopters who manipulate mtimes manually should `--no-prune`.
- **C5:** Determinism (A8 idempotency) requires single-threaded walk. **No multiprocessing in v1.** If we ever need parallelism, the merge step must sort outputs deterministically before serialization.
- **C6:** Working memory is a non-issue at all envisioned scales. The script can hold the entire working set in dicts; no need for streaming output.
- **C7:** `~/.claude/projects/` paths can be 200+ chars (sanitized full paths). The cost walk should `glob` not `walk` to skip hidden subdirs (`.git`, etc.). `Path.glob("*/*.jsonl")` and `Path.glob("*/*/subagents/agent-*.jsonl")` are sufficient.
- **C8:** Subagent JSONLs (max 796 KB) are still small enough to slurp into memory line-by-line on the canonical-fallback path. No streaming parser needed even there.

## Open Questions

1. **Refresh-latency target precision.** Is `<5s` p50 on typical adopter or p95 on heavy adopter? Recommend **p50 on typical, with stderr telemetry surfacing actual time** so heavy-adopter cases are visible without failing the contract.
2. **`run.json.session_id` field — does it exist today?** If not, the `parent_session_uuid → artifact_dir` join is fuzzy (by `created_at` proximity). May need `findings-emit` directive to start writing session_id (small additive change). **Defer to data-model persona** — if data-model says it's not in the schema, scalability flags this as needing v1.1 add.
3. **First-run UX.** Should `compute-persona-value.py` print a one-line "first scan over X session files, this may take Y seconds" warning when it detects a cold cold start (>100 sessions and no recent mtime-prune was possible)? **Recommend yes.** Cheap, prevents adopter confusion.
4. **Heavy-adopter explicit benchmark in tests.** Should `tests/test-compute-persona-value.sh` include a synthetic heavy-adopter fixture (~500 session JSONLs of size 1 MB each)? Adds ~500 MB to test fixtures (bad). **Recommend skipping** — test on small fixtures, document expected scaling behavior in code comments. Defer benchmark to a manual `scripts/bench-persona-value.sh`.
5. **Should `dashboard-append.sh` cache the previous output and only invoke `compute-persona-value.py` when source files have changed?** Would help dashboard-bundle stage. **Defer to v1.1**; v1 spec mandates unconditional refresh on `/wrap-insights`.

## Integration Points with other dimensions

- **data-model:** owns the `run.json.session_id` decision (Q2). Owns whether `parent_session_uuid` is a stable join key. Owns whether `contributing_finding_ids[]` cap (50) is right; if data-model lifts it, parse cost grows linearly — heads up.
- **ux:** owns "first scan may take Y seconds" copy + dashboard banner for stale data (>14 days). Scalability provides the underlying timing telemetry; ux decides how it surfaces.
- **edges-and-fallbacks:** owns the malformed-JSONL skip behavior (already in spec e3) and the cold-start "no data yet" path (e12). Scalability defers to those decisions.
- **api-contract:** if `compute-persona-value.py` exposes `--scan-projects-root`, `--no-prune`, `--best-effort` flags, api-contract owns the flag surface; scalability owns what each flag does to runtime.
- **observability:** stderr telemetry format is shared. Scalability proposes `[persona-value] parsed N session JSONLs (M skipped via mtime), K Agent dispatches matched, Tms`; observability persona may want JSON-shaped telemetry for downstream `/insights` ingestion. Negotiate format.
