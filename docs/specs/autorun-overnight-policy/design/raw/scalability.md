# Scalability Analysis — Raw

### Key Considerations
- Disk-space growth: ~20 KB/run typical, occasional ~1 MB on reset days. 100 runs ≈ 2 MB, 1000 runs ≈ 20 MB. **Negligible at this scale.** Real risk is dir count ergonomics.
- Lock contention: stages run serially → effective contention is zero. flock is correctness insurance for future-Justin.
- Per-stage policy-helper overhead: 50-150 ms per call × 25 calls/run ≈ 2.5s total. Stage envelope is multi-minute. **<0.2% — invisible.**
- pre-reset.patch size: usually <100 KB; pathological case (node_modules dirty) could be hundreds of MB.
- 4 schemas: not over-engineered for personal-tooling repo; real cost is operational (cross-version drift debugging).
- jq vs python3 cold start: jq ~5-15ms, python3 ~50-100ms. Difference real but acceptable.
- Concurrency: slug-scoped lockfile is right grain.
- Cleanup: no policy specified → grows forever. 1 run/week × 5yr = 260 dirs. Tiny on disk; ergonomically annoying.

### Options Explored
- **A — Ship as-is, no cleanup, no patch cap**: minimum surface; pathological case unbounded.
- **B — Soft cap on pre-reset.patch + opportunistic prune** ✅: bounds worst case + browsable dir; ~50 LOC + 2 tests.
- **C — Cap + retention + index.jsonl**: historical visibility; over-engineered for usage profile.
- **D — Cleanup only, no cap**: addresses dir-count; leaves unbounded patch tail.

### Recommendation
**Option B.** Add two small bounds:
1. `pre-reset.patch` soft cap at 5 MB with truncation marker `[truncated; full diff at <stash-sha>]`. The stash SHA is full-fidelity recovery; patch is preview.
2. Opportunistic prune in `run.sh` startup: delete `queue/runs/<run-id>/` dirs where mtime > 30 days AND not pointed at by `current` symlink AND `pre-reset.sha` absent (recovery dirs get 90-day retention). Configurable via `cleanup.max_age_days` (default 30) and `cleanup.recovery_max_age_days` (default 90). `--no-prune` CLI flag for forensic sessions.

Skip index.jsonl. Rest of spec scales correctly.

### Constraints Identified
- bash 3.2 prune: `find queue/runs/ -maxdepth 1 -type d -mtime +N` (no `-newermt`)
- APFS rename atomicity: `mv -f` is correct, no fsync ceremony
- `queue/runs/current` readlink: BSD readlink lacks `-f`, resolve manually
- **flock on macOS only via Homebrew util-linux** — real preflight gap. doctor.sh check needed; fail-fast at sourced-helper time if missing.
- git diff size: 5 MB cap protects against stray large-tree dirty state
- Personal-tooling cadence: 1-5 runs/week, not 1-5 runs/hour

### Open Questions
1. Is flock guaranteed available? Need doctor.sh line.
2. pre-reset.patch cap: hard refuse vs soft truncate? Recommend soft.
3. Retention defaults 30/90 days reasonable? Or count-based?
4. queue/runs/index.jsonl needed? Recommend skip; backlog if /wrap-insights wants historical autorun stats post-cleanup.

### Integration Points
- `scripts/autorun/run.sh` — startup prune step + `--no-prune` flag + cleanup config keys
- `scripts/autorun/build.sh` — pre-reset.patch 5MB cap + truncation marker
- `scripts/autorun/_policy.sh` — preflight `command -v flock` at source time + install hint
- `scripts/doctor.sh` — flock available check
- `queue/autorun.config.json` — `cleanup: { max_age_days: 30, recovery_max_age_days: 90 }`
- tests — prune-respects-current-symlink, prune-keeps-recovery, patch-cap-truncates, --no-prune
- CHANGELOG — note prune behavior under default-shift entry

**Severity calibration:** none are blockers. flock availability is most real concern — would fail at first policy_warn call rather than startup on fresh macOS install.
