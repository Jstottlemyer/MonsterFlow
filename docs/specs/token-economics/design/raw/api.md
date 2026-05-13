# API & Interface Design — token-economics

**Persona:** api (plan stage)
**Lens:** adopter / user ergonomics across CLI, JSONL row schema, dashboard tab, `/wrap-insights` text, and `~/.config/monsterflow/projects` config. Public-release week — first-touch surfaces matter more than internals.

## Key Considerations

- **Five surfaces, one mental model.** Adopters touch (1) `compute-persona-value.py` flags, (2) JSONL row fields they read in the dashboard / by hand, (3) the dashboard tab, (4) `/wrap-insights` text section, (5) the projects config file. They will form one mental model from all five — names and defaults must agree.
- **Zero-config day-one.** Cwd-only discovery + lazy config + roster-sidecar emit means a fresh adopter sees their own data on first `/wrap-insights` with no setup. Protect this aggressively; every required flag is a new install-friction bug report.
- **Public-repo screenshots are a UX surface.** Persona names, project names, and persona scores will be screenshotted and posted to GitHub issues / Twitter. Affordances that look fine in private (e.g., a casual `total_tokens` column) become a permanent ergonomic decision the moment the first screenshot ships.
- **`safe_log()` is the privacy contract surface.** It is also the debugging surface — overscrub it and adopters can't diagnose "why no data." Underscrub and we leak finding bodies on the public release. Spec gives it allowlisted field names + counts; implementation must match exactly.
- **Discoverability through `--help`, not docs.** Spec embeds Project Discovery semantics in `spec.md §Project Discovery`. Adopters will not find that. The `--help` text must carry the cascade.
- **Naming consistency between JSONL fields and dashboard column headers and `/wrap-insights` text.** If dashboard says "Judge Retention" and JSONL says `judge_retention_ratio` and `/wrap-insights` says "highest judge-retention", the three must be obviously the same metric. Today's spec is consistent — lock it in.

## Options Explored (with pros/cons/effort)

### Option A — `compute-persona-value.py` flag surface

**Spec mentions:** `--scan-projects-root`, `--best-effort`. Round 3 review and Open Q3 imply we also need `--dry-run`, `--explain`, `--list-projects`. Plus an `--out` for testability.

**A1. Spec-minimum (only `--scan-projects-root` + `--best-effort`).**
- Pros: smallest surface; least to support across versions; matches what `dashboard-append.sh` actually invokes.
- Cons: no way to debug "where did my data come from" without grepping stderr; no way to test compute without writing JSONL; A3 cross-project test forced to use process-level redirection.

**A2. Spec-minimum + `--list-projects` + `--out PATH` + `--dry-run`.**
- Pros: `--list-projects` answers the #1 question adopters will ask ("what's MonsterFlow scanning?") in one command; `--out` lets the test suite write to a temp dir without monkey-patching paths; `--dry-run` lets A8 idempotency verify without disturbing the real artifact.
- Cons: three new flags to document; risk of `--dry-run` semantics being unclear (does it still print stderr telemetry? does it still emit roster sidecar?).

**A3. A2 + `--explain PERSONA[:GATE]` for drill-down debugging.**
- Pros: solves the "why is scope-discipline showing 0.42 retention this week?" question without making the adopter open `findings.jsonl` files by hand; supports the `contributing_finding_ids[]` drill-down that already exists in the row schema.
- Cons: new output format to spec; small risk of leaking finding text if not allowlist-scrubbed (must reuse `safe_log()`).

**Effort:** A1 = S. A2 = S (≈30 LOC argparse + tests). A3 = M (new render path + allowlist-scrub of explain output).

### Option B — JSONL field naming consistency pass

**Spec already nails the big ones** (`judge_retention_ratio` not `judge_survival_rate`; `downstream_survival_rate` not `survival_rate`; `avg_tokens_per_invocation` not `avg_cost`). Remaining ergonomic questions:

**B1. `total_*` prefix vs no prefix.**
- Spec uses `total_emitted`, `total_judge_retained`, `total_downstream_survived`, `total_unique`, `total_tokens`. Consistent. Lock in. Do NOT shorten to `emitted` / `retained` — the prefix prevents confusion with rate fields.

**B2. `runs_in_window` vs `directories_in_window`.**
- Spec uses `runs_in_window`. The §Data section explicitly defines unit as "(persona, gate) artifact directories." `runs_in_window` is the term `/wrap-insights` text uses ("last 45 (persona, gate) directories"). Internal mismatch but the §Data table makes it explicit. **Keep `runs_in_window`** — "directories" reads worse in the text section, and the spec already defines the count.

**B3. `last_seen` vs `last_artifact_at`.**
- Spec uses `last_seen` sourced from MAX `run.json.created_at`. The name implies file-mtime which is exactly what spec forbids. Risk: future contributor "fixes" `last_seen` to file mtime. **Recommend rename to `last_artifact_created_at`** — explicit, harder to misread.
- Pros: kills a foot-gun.
- Cons: one more rename; A8 idempotency-allowlist string changes; minor.

**B4. `insufficient_sample` vs `n_below_threshold`.**
- Spec uses `insufficient_sample: bool`. Reads well. Keep.

**Effort:** B1/B2/B4 = S (no change). B3 = S (one rename across spec + tests + dashboard).

### Option C — `/wrap-insights` Phase 1c text format

**Spec format (paraphrased):**
```
Persona insights (last 45 (persona, gate) directories, all discovered projects)
  spec-review:  highest judge-retention → ux-flow (0.89), scope-discipline (0.84), …
                highest downstream-survival → scope-discipline (62%), …
                highest uniqueness → edge-cases (32%), …
                lowest avg cost → cost-and-quotas (8.2k tok/invocation), …
                never run this window: legacy-reviewer (in roster, no data)
```

**C1. Keep as-spec'd.**
- Pros: dense, scannable, six-line block per gate; consistent leader phrases ("highest …", "lowest avg cost").
- Cons: 4 lines × 3 gates = 12 lines minimum + "never run" rows = ~15-20 lines added to every `/wrap-insights`. On busy sessions this pushes the dashboard URL (final wrap line per `b06afc4`) above the fold of the terminal.

**C2. Compress to one line per dimension.**
- Pros: fewer lines.
- Cons: loses the gate grouping which is the actual decision unit (you act on a low spec-review persona differently than a low check persona); harder to scan.

**C3. Spec format + a `--quiet` gate that prints only "(N personas tracked across 3 gates — see dashboard)" when run as part of `/wrap-quick`.**
- Pros: respects the `/wrap-quick` vs `/wrap-insights` vs `/wrap-full` tab-completion split that's already established; full text only on the variant that asked for it.
- Cons: needs `commands/wrap.md` Phase 1c to know which variant invoked it (already does — Phase 1c is `/wrap-insights`-only per spec).

**Decision:** C3 implicitly handled — Phase 1c only runs on `/wrap-insights`. **Recommend C1 as-spec'd** plus adding "(only N qualifying)" rendering when fewer than 3 personas hit threshold (already in spec A6).

**Effort:** S — text generation only.

### Option D — Dashboard tab affordances

**D1. Sortable table (per spec) — clickable column headers.**
- Pros: matches existing dashboard tabs (judge-dashboard pattern); zero new affordance to learn.
- Cons: null-rate cells must always sort to bottom (locked in spec); must verify under both ascending and descending click.

**D2. "(never run)" rows — render or hide?**
- Spec: render. Pros: surfaces personas the adopter forgot they had enabled. Cons: visual noise on day-one when everything is "(never run)."
- **Recommend:** render with subtle visual treatment (italic + dimmed) and a per-table toggle "Show never-run personas (N)" defaulting ON when adopter has data, OFF when adopter has no data (e12). This makes day-one feel curated, not empty.

**D3. Warning banner copy.**
- Spec text: "Persona scores reflect this machine's MonsterFlow runs only. Screenshots and copy-pastes share persona names + numbers — review before sharing publicly."
- Tone is good. **One ergonomic tweak:** add a line break and a one-line "Window: last 45 (persona, gate) directories. Refreshed at /wrap-insights." so the adopter doesn't have to read the spec to understand the data freshness contract.

**D4. Run-state column rendering.**
- Spec column: `run_state`. But each row has aggregated `run_state_counts: {complete_value: 14, missing_survival: 3, …}`. Single-state column doesn't map.
- **Recommend:** the visible column is "Coverage" rendered as `14/18 complete` with a tooltip showing the full `run_state_counts` breakdown. Sortable by `complete_value / runs_in_window` ratio.

**Effort:** D1 = S. D2 = S (toggle + count). D3 = S (text only). D4 = M (custom cell renderer + tooltip).

### Option E — Config file format (`~/.config/monsterflow/projects`)

**Spec:** one absolute path per line; `#` comments; blank lines ignored; missing paths warned-not-aborted; lazy-created (compute does not create on first run); `XDG_CONFIG_HOME` respected.

**E1. Keep as-spec'd.**
- Pros: simplest possible; matches `~/.gitignore` mental model; trivial to hand-edit.
- Cons: no way to disable a path without deleting the line (commenting works, fine).

**E2. Add JSON / TOML config.**
- Cons: heavyweight; needs schema; needs validation errors. Rejected — over-engineered for a flat path list.

**Decision:** E1. Spec-locked. **Add to docs:** explicit example file content shipped at `docs/persona-ranking.md` (post-merge per spec; not blocking).

**Effort:** S.

### Option F — Error message and `safe_log()` content design

**Spec contract:** `safe_log()` emits only allowlisted field names + counts; never finding titles or bodies.

**F1. Strict allowlist match (spec).**
- Pros: cannot leak.
- Cons: error messages become "[persona-value] malformed: 1 row in unknown_directory" which is undebuggable for adopters.

**F2. Allowlist + safe-by-construction debugging hooks.**
- Pros: tier the messages. Three categories:
  1. **Telemetry** (every run, stderr): `[persona-value] discovered N projects: <path>, <path>, … (sources: cwd, config, scan)` — paths are filesystem paths the adopter typed, not finding bodies; safe.
  2. **Warnings** (per-issue, stderr): `[persona-value] WARN run_state=malformed at <project-relative-path>:<line> field=<allowlisted-field-name>` — path is project-relative, field name is allowlisted, no values.
  3. **Drill-down** (only with `--explain`): scrubbed by `safe_log()` to allowlisted-fields-and-counts only. Surfaces hashed `finding_id`, `persona`, `gate`, the three rate values; never the title/body.
- Pros: useful + leak-proof; matches the spec contract exactly with a clear taxonomy.

**Decision:** F2.

**Effort:** S (≈40 LOC + tests against `LEAKAGE_CANARY_xyz123` fixture per A10).

## Recommendation

**Pick A2 + B1/B2/B3/B4 + C1 + D1/D2/D3/D4 + E1 + F2.** This is the smallest, most-consistent surface that hits all adopter ergonomics without adding scope:

1. **(M)** `compute-persona-value.py` flag set: `--scan-projects-root <dir>` (repeatable), `--best-effort`, `--list-projects`, `--out PATH`, `--dry-run`, `--explain PERSONA[:GATE]`. `--help` text contains the three-tier cascade verbatim. **Per `~/CLAUDE.md` rule:** verify each flag with a `--help` smoke test before declaring shipped.
2. **(S)** Rename `last_seen` → `last_artifact_created_at` across spec + tests + dashboard. Pre-empts a future "fix to file-mtime" regression.
3. **(S)** Lock `/wrap-insights` Phase 1c text format as-spec'd; verify "(only N qualifying)" rendering path; ensure the block fits above the dashboard-URL final line on an 80x24 terminal (≈18-20 lines max).
4. **(M)** Dashboard tab: sortable, "(never run)" toggle (default ON when data exists / OFF when empty), warning banner with appended freshness/window line, `Coverage` column rendering `complete/total` with tooltip.
5. **(S)** Config file format frozen as-spec'd; ship example in `docs/persona-ranking.md` (post-merge).
6. **(S)** `safe_log()` three-tier taxonomy (telemetry / warnings / explain-drill-down), each tier independently allowlist-tested per A10.

**Total complexity: M.** Implementation slots into the existing `scripts/compute-persona-value.py` + `dashboard/index.html` + `commands/wrap.md` files. No new top-level architecture.

## Constraints Identified

- **`--help` is the docs.** Adopters will not read `spec.md`. The cascade, the `--scan-projects-root` opt-in semantics, the `--best-effort` failure threshold, and the lazy config path must all be in `--help` output.
- **`/wrap-insights` text and dashboard column headers must use the same words.** `judge_retention_ratio` field → "Judge Retention" column → "highest judge-retention" in text. Do not let the three drift across iterations.
- **`safe_log()` is enforced by A10's `LEAKAGE_CANARY_xyz123` test.** Every new stderr/stdout path in `compute-persona-value.py` must route through `safe_log()`. CI catches violations; design for it.
- **Dashboard renders under `file://`.** No `fetch()`. `persona-roster.js` sidecar via `<script src>` is the only option (already locked in spec). API design must not introduce any new fetches.
- **`~/.config/monsterflow/projects` is adopter-owned, not tool-owned.** Compute does not create it. `install.sh` may seed it (out of scope here per spec). Do not regress to auto-creation in a future iteration.
- **`run_state_counts` aggregation forces a custom dashboard cell renderer.** The naive single-`run_state` column doesn't represent the per-window mix. Plan accordingly.
- **Memory feedback `feedback_unverified_commands.md`** — do not document any `compute-persona-value.py` flag in spec or `--help` without first running `python3 scripts/compute-persona-value.py --help` against the implementation and quoting actual output.

## Open Questions

1. **Should `--scan-projects-root` be repeatable (`--scan-projects-root ~/Projects --scan-projects-root ~/Work`) or accept a comma-separated list (`--scan-projects-root ~/Projects,~/Work`)?** Repeatable is the argparse-idiomatic choice and matches `--volume` in Docker / `-I` in gcc. Recommend repeatable. *(Mostly a decision, not a real question — flagging only because spec uses singular form in the example.)*
2. **Does `--explain` need its own output format spec, or can it reuse the JSONL row format with one row per matching (persona, gate)?** Reusing the row format is safer (already allowlist-tested). Recommend reuse + a one-line human-readable summary header. *(Resolvable in `/build`.)*
3. **Should the dashboard "(never run)" toggle persist in localStorage?** Pro: respects user preference across sessions. Con: another piece of state to test. Defer: ship without persistence; add if adopters ask. *(Genuine open Q for future.)*

## Integration Points with other dimensions

- **data-model:** owns the JSONL row shape. This persona's B3 rename (`last_seen` → `last_artifact_created_at`) needs their concurrence; everything else in §Options B is naming consistency on top of their data shape.
- **scalability:** owns the windowing + I/O. This persona's D4 `Coverage` column derives from `run_state_counts` they emit; they must keep that field in v1.
- **architecture:** owns the file layout. This persona's F2 `safe_log()` taxonomy assumes a single helper module they'll structure; do not let it spread across multiple modules.
- **risk:** owns the failure modes. A1.5's "build fails on disagreement" is the forcing function; this persona's `--best-effort` flag is the user-facing escape hatch the risk persona will want documented.
- **observability:** owns the telemetry. This persona's F2 telemetry tier is exactly the observability surface they should adopt as-is — it's already designed for their use case.
