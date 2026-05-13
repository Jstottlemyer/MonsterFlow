## Summary (scalability persona — full output captured in conversation)

**Scale envelope:** dev-tooling repo, single operator, ≤100 specs, ≤50 findings/iteration, ≤20 active rows per spec, autorun 5-10 specs overnight (sequential), ≤3 gates per spec. Concurrency is *coincidence* (autorun + interactive on different specs), not contention (same spec).

**Dominant cost: LLM calls, NOT file I/O.** Every other concern is rounding error against 7 reviewer claude -p calls (≥30s each) + Synthesis (≥30s).

**`followups.jsonl` size growth:** 1000 rows aggregate (50 specs × 20) across 50 files = ~12 KB per file ceiling. Reading 1 syscall, parse sub-millisecond. /build wave-1 disk cost: single-digit milliseconds. **Trivial. Confirmed.** Keep JSONL (parity with findings.jsonl + grep-friendly).

**Lock primitive (real design question): `fcntl.flock` via Python helper.**
- Create `scripts/_followups_lock.py` exposing `acquire <path> [--blocking | --timeout=N]` and `with-lock <path> -- <command>...`
- Synthesis imports as a module + uses `@contextmanager`
- `render-followups.py` runs OUTSIDE the lock (post-rename read of atomic file is stable)
- **Stale-lock recovery: zero work** — `fcntl.flock` releases on FD close; FDs close on any process exit (incl. SIGKILL). No PID file, no timeout, no liveness probe.
- macOS `flock(1)` not available by default → Python helper is the right choice. NOT `flock(1)` shell command.
- NOT mkdir-as-lock (atomic on POSIX but doesn't auto-release; reinvents what kernel does correctly).

**`render-followups.py` execution: ~80-150ms cold start.** Once per Synthesis call (3 invocations per spec lifecycle) is fine. NOT once per finding emission (would be 5s wasted on cold starts).

**Survival-classifier load at /plan time:** 37 findings × LLM call. Spec marks non-blocking (correct). If batched: 1 call, ~5-10s. If wired into /wrap-insights, batch all findings into one call.

**`tests/test-permissiveness.sh` runtime budget:** 14 base cases + 10-15 edge cases = ~25-30 fixtures. **Pure deterministic logic — NO LLM in the test path.** Bash overhead 50ms × 30 = 1.5s; Python startup × N = ~3s. Total <10s wall-clock, well under 30s ceiling. **Pin a hard rule: tests/test-permissiveness.sh MUST NOT invoke claude -p** (comment at top).

**Recommendations:**
1. Lock: fcntl.flock via Python helper
2. Storage: keep JSONL as spec'd
3. Renderer: invoke once per Synthesis end
4. /build wave-1 read: no caching, no batching
5. Survival-classifier: keep non-blocking
6. Tests: deterministic-only with explicit no-claude-p prohibition
7. **No daemons, no caches, no SQLite, no concurrent-writer queue.** Scale doesn't justify them.

**Constraints:**
- macOS Darwin: pick `flock` not `lockf` (lockf doesn't auto-release on FD inheritance)
- Python 3.9+ stdlib only (json + fcntl + argparse)
- No NFS/iCloud (APFS only); document in helper's docstring
- Bash 3.2 traps for synthesis-side bash (prefer Python for lifecycle reconciliation)
- Per-spec lock scope (`.followups.jsonl.lock`) — two specs running concurrently don't contend
- Within-one-spec serialization: pipeline construction guarantees /spec-review → /plan → /check sequence

**Open Questions:**
- OQ-S1: `--timeout=60s` default (kills autorun cleanly with useful error)
- OQ-S2: render-followups.py post-rename read OUTSIDE lock (rename is atomic; content stable)
- OQ-S3: tests sequential not parallel (bash-3.2 + parallel-test-file race)
- OQ-S4: /build wave-1 reads without caching (single-pass throw away)
