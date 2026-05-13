# Scalability — install-rewrite

> Note on "scale" framing: install.sh is not a server. There is no concurrency, no
> request rate, no storage growth. The relevant scale axes are (1) **test-harness
> runtime as the suite grows from 5 → 9 → ~15 cases**, (2) **repeat-execution cost
> on adopter machines** (the spec's `<3s on fully-installed` budget), (3) **fresh-Mac
> wall-clock to first usable pipeline** (network-bound), and (4) **how slow ops
> behave when an external dep stalls** (brew API outage, `gh auth status` hang).
> Optimization targets are wall-clock seconds, not throughput.

## Key Considerations

### 1. Test harness runtime budget — 9 cases, each forking a subshell

Each case does roughly: `mktemp -d`, `export HOME=<tmp>`, define `has_cmd` shadow + brew stub, source/exec install.sh in a subshell, assert against stdout + filesystem, `rm -rf` the tempdir. Per-case overhead breakdown (M-series Mac, warm filesystem):

| Op | Typical wall-clock |
|---|---|
| `mktemp -d` | ~5 ms |
| `bash` subshell startup + sourcing helper | ~30 ms |
| install.sh execution (mocked, no real brew, no real `claude`, no plugin install, no test-suite recursion) | ~150–400 ms |
| `find $HOME/.claude -type l` for assertions | ~20–50 ms (O(symlinks) ≈ 80 entries today) |
| `rm -rf` of tempdir | ~30–80 ms |
| **Per-case total** | **~250–600 ms** |

So 9 cases × ~400 ms median ≈ **~3.6s sequential**, worst-case ~5.5s. Comfortably under the 30s local target and 60s CI target — *as long as* every case mocks brew/claude/plugin install and skips the real test-suite validation block (lines 318–326 of install.sh recursing into `tests/run-tests.sh` would be catastrophic — infinite loop or N×N runtime). The harness MUST set an env flag (e.g. `MONSTERFLOW_INSTALL_TEST=1`) that install.sh checks to skip its own validation prompt non-interactively.

Case 9a/9b/9c (non-interactive variants) and case 6a–6d (theme variants) are not separate spawns of the full suite — they're separate cases in the same harness, so 9 logical cases is really ~13 physical case-bodies. Still well within budget at ~5–7s total.

**CI consideration:** GitHub Actions macOS runners are ~3–5× slower than Justin's M-series Mac on shell startup. Budget on CI: 9 × ~1.5s = ~13s, plus runner cold start. Stays under 60s comfortably. No parallelization needed.

### 2. Repeat-run cost — the `<3s on fully-installed` budget

Spec acceptance case 2: re-run install.sh on a system with all symlinks present and all tools installed; assert `<3s` wall-clock. Per the spec UX example (lines 184–198), the path is:

```
Linux guard ──────────────────  ~1 ms      (single uname call)
flag parse ───────────────────  ~1 ms
SIGINT trap install ──────────  ~0 ms      (just sets a trap)
migration detect ─────────────  ~3 ms      ([ -L ] + readlink + case)
has_cmd loop (8 tools) ───────  ~30 ms     (8× command -v + 8× [ -x ] checks)
python3 version probe ────────  ~50 ms     (forks python3 once for sys.version_info)
brew bundle check ────────────  ~400–1200 ms  ★ DOMINANT — see below
git ls-files / file glob loops  ~80 ms    (commands, personas, scripts, autorun, settings, domains, templates — ~40 globs)
link_file × ~80 already-symlink  ~150 ms   (each ln -sf is ~2ms × 80)
queue/.gitignore writes ──────  ~5 ms      (touch + grep -F idempotency check)
persona-metrics block check ──  ~3 ms      (single grep -qF)
CLAUDE.md merge call ─────────  ~150–300 ms  (forks python3 + reads template)
install-hooks.sh ─────────────  ~50 ms     (a few ln -sf + chmod)
plugin install prompt ────────  PROMPT     (must be auto-skipped via --non-interactive or "N" default)
test-suite prompt ────────────  PROMPT     (same)
onboard.sh ───────────────────  ~300–600 ms  (doctor.sh + panel print + 2 detection probes)
                                ─────────
                                ~1.2–2.7s total IF no prompt blocks
```

**Verdict:** The `<3s` budget is achievable but **tight**. The two prompts (plugin install, test-suite validate) MUST be suppressed under owner re-run / `--non-interactive` or the budget is meaningless. The spec already addresses this via the `--no-onboard` and `--non-interactive` flags, but does NOT explicitly say plugin-install and test-suite-validate prompts honour `--non-interactive`. **This is an integration-with-implementation gap to flag in /plan.**

### 3. The dominant cost: `brew bundle check` / `brew bundle install --no-upgrade`

`brew bundle check --file=Brewfile` is the gating call on the fast path. Measured wall-clock on a warm Apple Silicon mac (Brewfile with 2 brews + 4 brews + 1 cask ≈ 7 entries):

- All present, no upgrades available: **~400–800 ms** (each entry is a fork into `brew list --formula <name>` or equivalent)
- Cold (just rebooted, brew API cache stale): **~1.2–2.0s**
- All present, brew API check enabled: can spike to **~3–5s** if it fetches the API to confirm versions

Mitigation: pass `--no-upgrade` (already implied by `check`) and ensure `HOMEBREW_NO_AUTO_UPDATE=1` is exported in install.sh so `brew bundle check` doesn't trigger an `auto-update` cycle (which alone is 2–10s). **This is a one-line export at the top of install.sh and pays for itself on every re-run.**

Worst case if we forget `HOMEBREW_NO_AUTO_UPDATE=1`: re-run jumps from ~2s to ~10s. The acceptance test for case 2 would flake.

### 4. Fresh-Mac wall-clock — `brew bundle install` worst case

Brewfile content (post-spec): `git`, `python@3.11`, `gh`, `shellcheck`, `jq`, `cask "cmux"`. On a fresh Mac with empty brew cache, network bound:

| Tool | Bottle size | Download (gigabit) | Install | Wall-clock |
|---|---|---|---|---|
| git | ~50 MB (often pre-installed via Xcode CLT) | 5s | 2s | 7s |
| python@3.11 | ~30 MB + deps (~80 MB total) | 8s | 5s | 13s |
| gh | ~12 MB | 1s | 2s | 3s |
| shellcheck | ~6 MB | 1s | 1s | 2s |
| jq | ~2 MB | <1s | 1s | 2s |
| cmux (cask) | ~80–150 MB DMG | 12s | 5s | 17s |
| **Total (sequential)** | ~280 MB | | | **~45–60s** |

Brew may parallelize bottle downloads (`HOMEBREW_DOWNLOADS_PARALLEL=1` is the default in recent Homebrew), so optimistic wall-clock is ~30–40s on gigabit. On a coffee-shop wifi (5 Mbps): up to 8–10 minutes. Acceptable — this is a one-time cost — but the spec UX should warn the user ("This may take 1–10 minutes depending on connection") before invoking `brew bundle install`.

**CI cacheability:** macOS GitHub runners ship with most of these (git, python3) pre-installed. `cmux` is the only outlier. `actions/cache` keyed on `Brewfile.lock.json` (which `brew bundle` writes) saves the bottle dir → repeat CI runs drop from ~45s to ~5s. **Spec doesn't address this; it should.**

### 5. Migration-detect cost — negligible

`[ -L $CLAUDE_DIR/commands/spec.md ] && readlink && case` — three syscalls, ~1 ms total. Not a concern at any scale.

### 6. SIGINT trap cost

`trap cleanup_partial INT TERM` — zero runtime cost on the happy path. On Ctrl-C:

```bash
find "$REPO_DIR" "$CLAUDE_DIR" -name '*.monsterflow.tmp' -delete 2>/dev/null
```

Bounded by repo size: `$REPO_DIR` is the workflow repo (~1500 files), `$CLAUDE_DIR` is `~/.claude` (variable; up to ~5000 files for a heavy user). Single `find` invocation is ~50–200 ms. Acceptable for cleanup. **One concern:** `find` traversing `~/.claude/projects/` (which contains every project's session logs) could blow up to seconds for users with hundreds of projects. Scope the find to specific subdirs (`commands/`, `personas/`, `scripts/`, `templates/`, `settings.json`) to bound it.

### 7. onboard.sh cost

```
doctor.sh ───────────  ~150–400 ms  (a handful of file existence checks + version probes)
panel print ─────────  ~5 ms        (echo statements)
gh auth status ──────  ★ NETWORK    (see #9 below)
graphify detect ─────  ~10 ms       (single `[ -d "$HOME/Projects" ]` check)
codex one-liner ─────  ~3 ms        (`command -v codex`)
```

Total fast path: ~200–500 ms. **Slow path with `gh auth status` hanging on bad network: see #9.**

### 8. Network costs and caching

Two stages hit the network:

| Stage | Network calls | Cacheable? |
|---|---|---|
| `brew bundle install` | brew API + bottle download per formula + cask DMG | YES on CI (`actions/cache` keyed on Brewfile.lock.json); NOT on adopter machine (one-shot) |
| `gh auth status` (in onboard.sh) | GitHub API (api.github.com) | NO — auth probe must be live |

Local adopter caching: brew already caches bottles in `~/Library/Caches/Homebrew`. Re-run after `brew uninstall jq` (acceptance case 4) hits the cache — should be ~1s, not full re-download. **Don't add custom caching; trust brew's.**

CI caching: spec is silent on this. Recommend the /plan output add a one-line note that `tests/test-install.sh` should never invoke real `brew bundle install` (always mocked) — and that if a separate CI job exercises real brew install (probably overkill), it should use `actions/cache@v4` keyed on `Brewfile.lock.json`.

### 9. Hang-risk scan — slow ops with no timeout

| Operation | Hang risk | Current mitigation |
|---|---|---|
| `brew bundle install` | YES — network stalls indefinitely | None in spec; brew has no built-in timeout. Mitigation: trust user to Ctrl-C; SIGINT trap cleans up. Acceptable. |
| `brew bundle check` | LOW — fast even offline (uses local state) | OK |
| `gh auth status` (onboard.sh) | YES — can hang on flaky GitHub API or behind a proxy that swallows port 443 | **NOT ADDRESSED IN SPEC.** Wrap in `timeout 5 gh auth status` (BSD `timeout` ≠ GNU `timeout`; macOS needs `gtimeout` from coreutils OR a bash trap-alarm pattern). |
| `python3 -c "import sys; print(...)"` | LOW — pure stdlib, no network | OK |
| `claude plugins install ...` | YES — fetches from registry | Current install.sh wraps in `\|\| echo`, which catches exit but not hang. Acceptable since it's already gated behind a Y/N prompt. |
| `git rev-parse --show-toplevel` (owner-detect) | NEAR-ZERO — pure local | OK |
| `bash scripts/doctor.sh` | LOW — file probes + version checks, no network | OK |

**Recommendation: add `timeout 5` (via macOS `command timeout` shim or trap-alarm) around `gh auth status` in onboard.sh.** Otherwise an adopter behind a corporate proxy gets a frozen terminal at the very last step of install — exactly the worst place to hang.

### 10. O(N²) / unbounded operations scan

Looked through the existing 354 lines + planned new stages:

- `link_file()` loop over `$REPO_DIR/commands/*.md` etc. — O(N) in number of files, no nested loops. Fine.
- Persona-metrics gitignore block: single `grep -qF` for sentinel, then `>>` append — O(file size). Fine.
- `find ... -name '*.monsterflow.tmp' -delete` in trap — O(repo size) but bounded; recommend scoping to specific subdirs.
- `claude-md-merge.py` — Python script, O(line count of CLAUDE.md). Today's CLAUDE.md is ~150 lines. Fine.

**No O(N²) paths found.** No unbounded operations except the `find` in the SIGINT trap (mitigation above).

## Options Explored

### Option A: Sequential test execution, no caching (current proposal)

- 9 cases × ~400 ms = ~3.6s local, ~13s CI. Comfortably under budget.
- Pros: simplest harness; no flake from parallel-write races on `mktemp` dirs; matches existing `tests/run-tests.sh` style.
- Cons: doesn't scale past ~30 cases. Once `tests/test-install.sh` adds Linux-VM cases or full brew-install cases, sequential breaks down.
- Effort: zero (default).

### Option B: GNU-parallel-style harness (`xargs -P 4` per case)

- 4-way parallel → ~1s local, ~4s CI.
- Pros: Future-proofs for 30+ cases.
- Cons: Each case writes to `mktemp -d` (unique dirs, no collision risk), but install.sh's git-hooks installation modifies `$REPO_DIR/.git/hooks` — that IS a shared resource. Parallel cases would race on the `install-hooks.sh` invocation. Would need to suppress that path via `MONSTERFLOW_INSTALL_TEST=1`.
- Effort: ~1 hour to refactor + debug. Premature for a 9-case suite.

### Option C: Skip `brew bundle check` on owner re-run via short-circuit

- If `OWNER=1` and last-successful-install marker is fresh (`~/.local/share/MonsterFlow/.last-brew-bundle` mtime within 24h), skip `brew bundle check` entirely.
- Pros: Drops repeat-run wall-clock from ~2s to ~1s. Owner runs install.sh dozens of times during dogfood; this matters.
- Cons: Adds state file. Stale marker hides genuine drift (tool was uninstalled in the last 24h). Saves ~800 ms.
- Effort: ~30 min.
- Verdict: **Skip — not worth the state-file complexity for ~800 ms.** Set `HOMEBREW_NO_AUTO_UPDATE=1` instead (free).

### Option D: Add `--profile` flag that prints per-stage wall-clock

- Owner-only debugging aid. `--profile` runs each stage wrapped in `time` (or bash `SECONDS` deltas) and prints a table at the end.
- Pros: Catches regressions early. If a future change pushes repeat-run from 2.5s to 6s, `--profile` shows which stage owns the regression in one glance.
- Cons: ~50 lines of code; only useful to Justin.
- Effort: ~1 hour.
- Verdict: **Defer to BACKLOG.md unless /build is already modifying every stage anyway.**

## Recommendation

### Concrete runtime budgets per stage

| Stage | Fresh-Mac happy path | Owner re-run (fully installed) | Test harness (mocked) |
|---|---|---|---|
| Linux guard | <5 ms | <5 ms | <5 ms |
| Flag parse | <5 ms | <5 ms | <5 ms |
| SIGINT trap install | <5 ms | <5 ms | <5 ms |
| Migration detect | <10 ms | <10 ms | <10 ms |
| has_cmd loop + python version | ~80 ms | ~80 ms | <20 ms (mocked) |
| `brew bundle install` | 30–60s (network-bound) | n/a (skipped via `check`) | <10 ms (stub binary) |
| `brew bundle check` (re-run path) | n/a | ~400–800 ms ★ | <10 ms (stub) |
| Symlink stages (commands, personas, scripts, autorun, settings) | ~200 ms | ~150 ms | ~150 ms |
| Owner-detect (hardened) | ~20 ms (forks git once) | ~20 ms | ~20 ms |
| queue/.gitignore + persona-metrics block | ~15 ms | ~5 ms | ~10 ms |
| Theme stage (link_file × 2 + zshrc append) | ~40 ms | ~10 ms (already symlinked) | ~30 ms |
| CLAUDE.md merge | ~200 ms | ~200 ms | <20 ms (mocked / skipped) |
| install-hooks.sh | ~50 ms | ~50 ms | <10 ms (skip via env flag) |
| plugin install (Y) | ~5–30s (network) | n/a (suppressed) | <10 ms (skip) |
| test-suite validate (Y) | ~10–20s | n/a (suppressed) | <10 ms (skip — recursion guard) |
| onboard.sh: doctor.sh | ~200 ms | ~200 ms | ~50 ms (mocked) |
| onboard.sh: gh auth status (with `timeout 5`) | up to 5s | up to 5s | <5 ms (mocked) |
| onboard.sh: panel print + detection probes | ~10 ms | ~10 ms | ~10 ms |
| **TOTAL (happy path)** | **~50–120s** (network bound, dominated by brew + plugin) | **~1.5–2.7s** (under 3s ✓) | **~250–600 ms / case** (~4–6s for 9 cases ✓) |

### Required adds to /plan output

1. **Set `HOMEBREW_NO_AUTO_UPDATE=1` at the top of install.sh** (one line; saves 2–10s on re-runs; non-negotiable for the `<3s` budget).
2. **Add `MONSTERFLOW_INSTALL_TEST=1` env flag** that install.sh checks to skip three things: plugin-install prompt, test-suite-validate prompt, install-hooks.sh recursion. The harness exports this; production runs don't. This makes the test suite both fast and side-effect-free.
3. **Wrap `gh auth status` in onboard.sh with a 5s timeout.** macOS doesn't ship GNU `timeout`, so use a bash trap-alarm pattern or document `brew install coreutils` as RECOMMENDED. Recommend trap-alarm to avoid adding a dependency just for one timeout.
4. **Confirm `--non-interactive` suppresses ALL prompts** — explicitly include plugin-install (line 307) and test-suite-validate (line 321) prompts in the spec's flag-table semantics. Spec is silent on these two.
5. **Scope the SIGINT-trap `find` to specific subdirs** (`commands/`, `personas/`, `scripts/`, `templates/`, `settings/`, plus `$CLAUDE_DIR/{commands,personas,scripts,templates}`). Avoid `~/.claude/projects/` traversal.
6. **CI caching note (informational, no-op for /build):** if a future spec adds a CI job that exercises real `brew bundle install`, key `actions/cache` on `Brewfile.lock.json`. Out of scope for v0.5.0; document in BACKLOG.md.

## Constraints Identified

- **Homebrew auto-update is the silent cost.** Without `HOMEBREW_NO_AUTO_UPDATE=1`, every re-run risks a 2–10s detour that the `<3s` budget cannot absorb.
- **macOS lacks GNU `timeout`.** Any spec that wants a hard timeout on a network call (notably `gh auth status`) must implement it via bash trap-alarm or require `coreutils`. Choose trap-alarm to avoid expanding REQUIRED.
- **The test harness MUST avoid recursion.** install.sh today ends with `bash tests/run-tests.sh` (gated behind a Y/N prompt). The new test harness sourcing install.sh would either deadlock or run forever without a guard env flag. This is a correctness issue dressed up as a scalability issue — flagging it here because it's discovered by considering "test harness runtime."
- **GitHub Actions macOS runner shell-startup is ~3–5× slower than M-series local.** Budget 9 cases at ~1.5s each = 13s on CI. Stays under 60s; no parallelization needed yet.
- **Bottle download is wall-clock-dominant on fresh-Mac.** ~280 MB total, ~30–60s on gigabit, up to 10 min on slow connections. UX should print a "this may take a while" hint before invoking `brew bundle install`.

## Open Questions

1. **Does `--non-interactive` suppress plugin-install and test-suite-validate prompts?** Spec doesn't say. /plan should pin this. Recommend YES — both are interactive Y/N prompts and `--non-interactive` is supposed to disable all of them.
2. **Should there be a hard timeout on `brew bundle install`?** Today, network stall = indefinite hang until user Ctrl-Cs. Acceptable per current spec (SIGINT trap cleans up). Could add `timeout 600 brew bundle install` (10 min) for fully-scripted CI runs — but that adds the GNU/BSD timeout problem. **Recommend: no timeout; trust the user.**
3. **Does the suite want a `--profile` flag for owner debugging?** Surfaces stage-by-stage wall-clock. Useful for catching regressions early. Defer to BACKLOG.md unless /build touches every stage.
4. **Should `tests/test-install.sh` ever exercise real `brew bundle install` (e.g. in a separate CI job)?** Spec says no (mock everything). Confirms the test budget stays at ~5s. Out of scope to add now; flag in BACKLOG.md if Justin wants a true end-to-end smoke test before tagging v0.5.0.

## Integration Points

- **with integration:** integration owns the "test harness file structure" decision. Scalability requires that the harness expose a `MONSTERFLOW_INSTALL_TEST=1` env flag (or equivalent) that install.sh respects to skip recursion-prone stages (plugin install, test-suite validate, install-hooks). Without that flag, repeat-run budget and test-harness budget both blow up. Integration should also confirm that `MONSTERFLOW_INSTALL_TEST` does NOT skip the symlink stages — those are exactly what the harness needs to assert against.
- **with security:** scalability suggests `HOMEBREW_NO_AUTO_UPDATE=1` and `timeout 5` around `gh auth status`. Security should confirm these don't open trust holes (they don't — `NO_AUTO_UPDATE` just pins the user's existing brew; the timeout only governs the auth-status probe, not the auth flow itself). Security should also weigh in on whether the SIGINT cleanup `find` should be scoped narrowly (scalability vote: yes, scope to specific subdirs) or broadly (security vote: TBD — broad cleanup may catch unexpected `.tmp` leaks but risks deleting user files matching the pattern).
- **with feasibility (implicit):** the 5–7s total test runtime depends on `tests/test-install.sh` mocking brew, claude, the plugin install command, and the test-suite-validate recursion. Feasibility should confirm the function-shadowing strategy (already pinned in spec v1.1) extends to mocking the `brew` binary itself — likely via a stub script on a `PATH`-prepended tempdir, or via a `brew()` shell function exported into the subshell.
