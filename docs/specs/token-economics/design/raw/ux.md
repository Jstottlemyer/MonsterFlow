# UX Design — Persona Insights surfaces (token-economics v4)

**Persona:** ux (plan)
**Scope:** dashboard tab, `/wrap-insights` text section, banners, run_state surfacing, insufficient-sample row visual, fresh-install (e12), stale-cache (e6), privacy warning. CLI ergonomics owned by `api`; data shape owned by `data-model`.

## Key Considerations

1. **Reading order is "scan, sort, drill."** A user opens the tab to answer one of: "which persona is most expensive?", "which persona pulls weight?", "which persona is dead weight?". Sortable columns + clear null/strikethrough states do all three; everything else is secondary.
2. **The dashboard is the source of truth; `/wrap-insights` is the appetizer.** Same numbers, fewer of them, plus the "(never run)" callout. Text section must NOT introduce columns the dashboard lacks (Codex round-3 #6 — three render surfaces is one too many; we already cut bare-arg full-table).
3. **Compression-ratio honesty has to land in the UI, not just the spec.** v4 renamed `judge_survival_rate` → `judge_retention_ratio` precisely because stakeholders overinterpret. The header label and tooltip carry that load — abbreviating to "retention" alone re-invites the misread.
4. **`run_state` is metadata about the row's confidence, not a value dimension.** Surfacing it as a peer column risks users sorting by it (meaningless ranking). It belongs as a small badge in a fixed position so users learn to read it as a footnote, not a metric.
5. **"(never run)" and "deleted" are different failure modes** and must look different. Never-run = roster says it should run, no data exists yet (neutral, expected on day one). Deleted = data exists but the persona file is gone (warning, drift signal). Conflating them in styling makes both useless.
6. **Privacy warning has to be present without being blamed-the-victim.** Users will screenshot anyway; copy should help them screenshot safely (crop hint), not scold.
7. **`file://` constraint is hard** — no fetch, no async chunking. All rendering is synchronous from `window.PERSONA_ROSTER` + bundled JSONL. Sort handlers must be DOM-only.
8. **Existing dashboard idiom:** dark theme, `--accent: #4ec9b0` (teal), `--good`/`--warn`/`--bad` semantic colors, `.badge` pill component, top nav `<button>` tabs. New tab must reuse these or it'll look bolted-on.

## Options Explored

### A. Dashboard tab structure

**Option A1 — Single flat sortable table (recommended).** One `<table>`, all (persona, gate) rows, default sort by gate then persona alphabetical. User clicks column headers to re-sort.
- Pros: matches user's "scan-and-sort" mental model; one visual surface; trivial under `file://`; keyboard-navigable via native table semantics.
- Cons: 28 personas × 3 gates = up to 84 rows; long scroll. Mitigated by gate-column sort grouping.
- Effort: **S**.

**Option A2 — Three accordion panels per gate.** Spec-review / plan / check as collapsible sections, each with its own table.
- Pros: less scroll; gate is the most common filter axis.
- Cons: extra click before users see anything; sort across gates impossible; breaks the "sort by avg cost" use case.
- Effort: M.

**Option A3 — Master-detail with per-persona drill-down panel.** Click row → side panel shows `contributing_finding_ids`, `run_state_counts`, persona hash.
- Pros: drill-down is in spec (`contributing_finding_ids[]` cap of 50).
- Cons: doubles the JS surface; breaks `file://` simplicity; users mostly want the table.
- Effort: L.

**Recommendation: A1** with `contributing_finding_ids` as a `<details>` collapsible inside the row's last cell (no side panel needed).

### B. `run_state` surfacing

**Option B1 — Dedicated column with badge (recommended).** `run_state` column between `runs_in_window` and rate columns; renders as `.badge` pill colored by state class.
- Pros: visible at-a-glance; sortable groups same-state rows; consistent with existing badge idiom.
- Cons: one more column on an already-wide table.
- Effort: S.

**Option B2 — Inline icon next to runs count.** A small symbol (✓/⚠/!) prepended to `runs_in_window`.
- Pros: compact.
- Cons: not screen-reader friendly without aria-label work; no sort affordance; loses the per-state breakdown that `run_state_counts` provides.
- Effort: S.

**Option B3 — Tooltip-only on the row.** Hover row → tooltip lists state counts.
- Pros: zero column footprint.
- Cons: invisible on touch; invisible on first-glance scan; users can't filter/sort by it.
- Effort: M.

**Recommendation: B1.** Single `.badge` showing the **dominant** state for the row (the one with highest count in `run_state_counts`); hover tooltip shows full breakdown. If dominant is `complete_value`, render no badge (signal-by-absence; default state is silent).

### C. Insufficient-sample row visual

**Option C1 — Dim the entire row + render rate cells as "—" (recommended).** Row gets `opacity: 0.55`; rate cells render literal `—`; rate-column sort always sinks these to the bottom (locked in spec).
- Pros: distinguishes "we have a row but can't trust the rates" from "missing data"; preserves cost columns at full clarity (they're trustworthy regardless of sample); uses existing CSS.
- Cons: dimming reduces contrast; need to verify WCAG AA still passes for body text in panel — `#e6e6e6` at 0.55 over `#171a21` ≈ 4.6:1, passes AA for normal text.
- Effort: S.

**Option C2 — Dimmed rate cells only (current spec wording).** Row stays at full opacity; just the rate cells are "—".
- Pros: minimal visual change.
- Cons: a row with `runs_in_window: 2` and three "—" rate cells looks like data-quality bug, not "we honored the threshold." The whole-row dim signals "we deliberately suppressed this."
- Effort: S.

**Option C3 — Separate "Insufficient sample" section below the main table.**
- Pros: cleanest separation.
- Cons: breaks unified sort; user sorting "lowest avg cost" misses cheap-but-low-sample personas; adds a section header.
- Effort: M.

**Recommendation: C1.** Dim the whole row; rate cells "—"; cost cells stay full-clarity. Add an `aria-label="insufficient sample (N runs)"` on the row for screen readers.

### D. Deleted-persona row visual

**Option D1 — Strikethrough on persona name only (recommended, matches spec).** `text-decoration: line-through` on the persona-name cell; row otherwise normal; `.badge red` reading "deleted" in the run_state column position.
- Pros: scannable; sorts correctly; doesn't dim numbers (they're still real history).
- Cons: line-through on a single cell can look like a CSS bug; mitigated by the explicit "deleted" badge.
- Effort: S.

**Option D2 — Whole-row strikethrough.** Uglier; reads as "this row is wrong" rather than "this persona is gone."

**Recommendation: D1.**

### E. `/wrap-insights` text format

**Option E1 — Three-line-per-gate compact (matches spec example, recommended).** Per-gate block with one line per dimension showing top 3, plus one trailing line for "never run this window."
- Pros: matches spec verbatim; predictable terminal width; copy-pasteable.
- Cons: bottom-3 not shown if reusing the spec example. Spec says "top + bottom 3 per gate × per dimension" — need both.
- Effort: S.

**Option E2 — Top-and-bottom-paired lines.** Each dimension gets two lines: "highest …" and "lowest …", both showing 3 personas.
- Pros: literal spec compliance.
- Cons: doubles vertical density; gate block is ~10 lines.
- Effort: S.

**Option E3 — Sparkline / unicode bar visualization.** Replace numeric values with `▁▂▃▅▇`.
- Pros: visually scannable.
- Cons: terminal font fragility; loses precise numbers users want to copy.
- Effort: M.

**Recommendation: E2** with the spec-example abbreviated form for cost (single line, since "highest avg cost" is rarely interesting — it's almost always Codex/large-context personas). See actual format below.

### F. Privacy warning placement

**Option F1 — Persistent banner above the table (recommended, matches spec).** Always-visible muted-yellow banner; not dismissable in v1.
- Pros: present in every screenshot; tied to the surface that leaks.
- Cons: takes vertical space.
- Effort: S.

**Option F2 — Once-per-session dismissable.** localStorage flag.
- Pros: less visual chrome long-term.
- Cons: defeats the purpose — the banner is *for* the screenshot moment, which happens after dismissal.
- Effort: M.

**Recommendation: F1.**

## Recommendation

### Dashboard tab — "Persona Insights"

**Tab placement:** new top-nav button after existing project tabs (and after Judge mode toggle), labeled `Persona Insights`. Activates same-page, swaps `<main>` content via existing `__renderXxxView` pattern. Add `window.__renderPersonaInsightsView` and a `<script src="./persona-insights.js">` plus `<script src="./data/persona-roster.js" onerror="...">` and JSONL bundle (build owns wiring; UX specifies markup).

**Page structure (DOM, top-to-bottom):**

1. **Privacy banner** (always visible):
   ```
   ┌─────────────────────────────────────────────────────────────────────┐
   │ ⓘ  Persona scores reflect this machine's MonsterFlow runs only.    │
   │    Persona names and numbers below are visible in any screenshot — │
   │    review before sharing publicly. Data is gitignored locally.     │
   └─────────────────────────────────────────────────────────────────────┘
   ```
   CSS: reuse `.card` shell with `border-left: 3px solid var(--warn);` and `color: var(--warn);` on the leading icon. No close button.

2. **Stale-cache banner** (conditional — shown only if MAX(`last_seen`) > 14 days ago):
   ```
   ┌─────────────────────────────────────────────────────────────────────┐
   │ ⏱  Last refreshed 18 days ago (2026-04-15). Run /wrap-insights to  │
   │    update — figures below may not reflect recent runs.             │
   └─────────────────────────────────────────────────────────────────────┘
   ```
   CSS: `border-left: 3px solid var(--bad);`. Shown above the privacy banner so users see freshness before content. Date format: `YYYY-MM-DD` (no time — day granularity is what matters at 14+ day staleness).

3. **Empty-state banner** (conditional — shown only when JSONL is empty / missing AND roster has rows; e12 fresh-install case):
   ```
   ┌─────────────────────────────────────────────────────────────────────┐
   │ No persona data yet. The table below shows the personas your       │
   │ pipeline will measure once you run them. To populate:              │
   │   1.  /spec-review,  /plan,  or  /check  on any feature            │
   │   2.  /wrap-insights                                               │
   │ Cross-project aggregation is opt-in — see docs/specs/              │
   │ token-economics/spec.md §Project Discovery.                        │
   └─────────────────────────────────────────────────────────────────────┘
   ```
   Replaces — does NOT duplicate — the privacy banner when data is empty (no personally-identifying numbers to leak yet). CSS: `border-left: 3px solid var(--accent);` (neutral/instructive, not warning).

4. **Table** with these columns left-to-right:

   | Header | Sort | Width | Notes |
   |---|---|---|---|
   | `Persona` | alpha | flex | Strikethrough if deleted. Plain text. |
   | `Gate` | alpha | 110px | `spec-review` / `plan` / `check`. |
   | `State` | enum | 100px | `.badge`. Empty if `complete_value`. See state→class map below. |
   | `Runs` | numeric | 70px | `runs_in_window` / `window_size` rendered as `18 / 45`. |
   | `Retention` | numeric, nulls last | 110px | `judge_retention_ratio` as `0.66` (two decimals). Header tooltip: see copy below. |
   | `Survived` | numeric, nulls last | 110px | `downstream_survival_rate` as `40%`. Header tooltip: see copy below. |
   | `Unique` | numeric, nulls last | 100px | `uniqueness_rate` as `19%`. |
   | `Avg tok` | numeric, nulls last | 100px | `avg_tokens_per_invocation` formatted `15.3k`. |
   | `Total tok` | numeric | 100px | `total_tokens` formatted `274k` / `2.1M`. |
   | `Last seen` | date | 110px | `YYYY-MM-DD` of `last_seen`. |
   | `Findings` | none | 90px | `<details><summary>50 IDs</summary>…</details>` showing `contributing_finding_ids`. If `truncated_count > 0`, summary reads `50 IDs (+N more)`. |

   **Header tooltips (HTML `title` attribute — works under `file://`, screen-reader accessible):**
   - `Retention`: `"Compression ratio: findings emitted by Judge that include this persona ÷ top-level bullets in this persona's raw output. NOT a survival rate — Judge can merge or split bullets."`
   - `Survived`: `"Of this persona's findings that survived Judge clustering, fraction marked 'addressed' in next pipeline artifact. Empty cells may mean 'not yet evaluated' (downstream gate hasn't run)."`
   - `Unique`: `"Findings where this persona is the sole contributor (unique_to_persona)."`
   - `Avg tok`: `"Average tokens per Agent dispatch loading this persona. Use this for cost ranking — totals penalize frequently-run personas."`
   - `State`: `"Row data completeness. Hover any row's badge for the per-state breakdown."`

   **Color bands on rate cells** (visual scan affordance, reuse existing semantic colors):
   - `>= 0.50` (Retention, Survived) or `>= 0.20` (Unique): `color: var(--good);`
   - `0.20–0.50` Retention/Survived, `0.05–0.20` Unique: default fg.
   - `< 0.20` Retention/Survived, `< 0.05` Unique: `color: var(--warn);`
   - Null / "—": `color: var(--muted);`

   These thresholds are **starting heuristics** from spec example numbers (e.g., "ux-flow 0.89 highest retention"). Reviewable post-merge based on real distribution; adopters can tune via CSS override (no settings UI in v1).

5. **State badge color map:**
   - `complete_value` → no badge rendered (silent default).
   - `missing_survival` → `.badge.yellow` text `"survival pending"`.
   - `missing_findings` → `.badge.red` text `"no findings"`.
   - `missing_raw` → `.badge.red` text `"no raw"`.
   - `malformed` → `.badge.red` text `"malformed"`.
   - `cost_only` → `.badge.yellow` text `"cost only"`.
   - **Deleted persona row** (special case — overrides whatever `run_state` says): `.badge.red` text `"deleted"`.

   The badge text shown is for the **dominant** state (max of `run_state_counts`). On hover, browser-native `title` shows full breakdown: `"complete_value: 14 · missing_survival: 3 · cost_only: 1"`.

6. **Insufficient-sample row visual:**
   - Row gets class `.row-low-sample` → `opacity: 0.55;`
   - All four rate/cost-rate cells render as `—` (single em-dash, `color: var(--muted)`).
   - `Runs` cell still shows `2 / 45` so user knows why.
   - `Total tok` and `Last seen` stay full-opacity within the dimmed row (numbers are still trustworthy; opacity applies to the row, individual cells aren't re-brightened — accept as a reasonable tradeoff vs CSS complexity).
   - `aria-label` on the `<tr>`: `"Insufficient sample, N runs of 3 minimum"`.

7. **"(never run)" row visual:**
   - All numeric cells render as `—` (`color: var(--muted)`).
   - `State` badge: `.badge` (neutral grey — define new class `.badge.grey` with `background: var(--border); color: var(--muted);`) text `"never run"`.
   - Row is NOT dimmed (it's expected on day one, not a problem).
   - Sorted to bottom by default within its gate group (rate sorts already sink nulls; numeric sorts on `Runs` put 0 at bottom — naturally lands there).

### `/wrap-insights` Phase 1c text section

```
Persona insights (last 45 (persona, gate) directories, all discovered projects)

  spec-review
    highest retention      ux-flow (0.89), scope-discipline (0.84), cost-and-quotas (0.78)
    lowest retention       legacy-formatter (0.18), gaps (0.22), ambiguity (0.31)
    highest survival       scope-discipline (62%), edge-cases (54%), feasibility (49%)
    lowest survival        ambiguity (8%), gaps (11%), stakeholders (15%)
    most unique            edge-cases (32%), scope-discipline (28%), codex (24%)
    least unique           feasibility (4%), requirements (6%), gaps (9%)
    cheapest per call      cost-and-quotas (8.2k tok), gaps (9.1k tok), ambiguity (10.4k tok)
    never run this window  legacy-reviewer

  plan                     (only 2 qualifying — need 3 runs each)

  check
    highest retention      …
    [continues per the same template]

  Note: "retention" is a compression ratio (Judge clustering density), not a true
  survival rate. "survival" is the addressed-downstream rate. See dashboard
  Persona Insights tab for full table + tooltips.
```

**Format rules:**
- Six top/bottom dimension lines per gate (retention top+bot, survival top+bot, unique top+bot) + one cost line + one "never run" line.
- Cost shows top-3-cheapest only (most actionable; "highest" is uninteresting noise — large-context reviewers always lead).
- When fewer than 3 personas qualify (`runs_in_window >= 3`) for any dimension within a gate, replace the entire gate block with `"  <gate>                     (only N qualifying — need 3 runs each)"` single line.
- "never run this window" line listed only when at least one persona is in roster but absent from window data for that gate.
- Trailing two-sentence note about retention vs survival semantics is present every render — cheap insurance against stakeholder misread.

### Header column hover-tooltips (full copy, repeated for /build implementer)

| Column | `title` attribute |
|---|---|
| Retention | `Compression ratio: findings emitted by Judge that include this persona ÷ top-level bullets in this persona's raw output. NOT a survival rate — Judge can merge or split bullets.` |
| Survived | `Of this persona's findings that survived Judge clustering, fraction marked 'addressed' in next pipeline artifact. Empty cells may mean 'not yet evaluated'.` |
| Unique | `Findings where this persona is the sole contributor (unique_to_persona).` |
| Avg tok | `Average tokens per Agent dispatch loading this persona. Use for cost ranking — totals penalize frequently-run personas.` |
| State | `Row data completeness. Hover any row's badge for per-state breakdown.` |

### Final banner copy (locked, ready for /build)

| Banner | Copy |
|---|---|
| Privacy (persistent) | `ⓘ  Persona scores reflect this machine's MonsterFlow runs only. Persona names and numbers below are visible in any screenshot — review before sharing publicly. Data is gitignored locally.` |
| Stale cache (conditional, >14 days) | `⏱  Last refreshed N days ago (YYYY-MM-DD). Run /wrap-insights to update — figures below may not reflect recent runs.` |
| Empty / fresh install (conditional, e12) | `No persona data yet. The table below shows the personas your pipeline will measure once you run them. To populate: (1) /spec-review, /plan, or /check on any feature, then (2) /wrap-insights. Cross-project aggregation is opt-in — see docs/specs/token-economics/spec.md §Project Discovery.` |

## Constraints Identified

1. **`file://` rules out fetch.** All data must arrive via `<script src>` (JSONL → preprocessed JS bundle by `compute-persona-value.py`, plus `persona-roster.js`). Build owns the bundling step; UX assumes both globals exist on `window`.
2. **No external CSS framework.** Existing dashboard is hand-rolled CSS variables. New tab MUST use only existing variables + add a `.badge.grey` and `.row-low-sample` class. No Tailwind, no CSS-in-JS.
3. **No sortable-table library.** Add ~30 lines of vanilla JS sort handlers (click header → re-sort `state.rows`, re-render `<tbody>`). Build owns the impl; UX specifies behavior (numeric vs alpha vs nulls-last).
4. **Up to 84 rows (28 personas × 3 gates).** No virtual scrolling needed at this size — just plain DOM. Re-validate if persona count grows past ~50.
5. **Color bands are heuristic.** Thresholds (0.20 / 0.50 for rates; 0.05 / 0.20 for uniqueness) come from spec example values, not measured distribution. Acceptable for v1; document in `persona-insights.js` as `// TODO(v1.1): tune from observed distribution`.
6. **WCAG AA at 0.55 opacity.** Verified `#e6e6e6` × 0.55 over `#171a21` ≈ 4.6:1 contrast, passes AA. If `/build` changes the dim factor, re-check.
7. **Screen-reader access for badge state.** `.badge` is a `<span>`; add `aria-label` matching the visible text + the hover-tooltip breakdown so screen readers get the same info as sighted hover users.
8. **No localStorage.** Banner dismissal would need it; we deliberately don't dismiss the privacy banner. Don't introduce localStorage for v1 (one fewer adopter-surface to reason about).

## Open Questions

1. **Should `Persona Insights` be a top-level mode (peer to Graphify/Judge) or a tab under one of those?** Recommendation: top-level mode — it's not project-scoped (cross-project aggregation), so the existing per-project tab nav doesn't fit. Build/integration to confirm with mode-toggle owner.
2. **How does the deleted-persona drill-down handle `contributing_finding_ids`?** If the persona file is gone but findings still reference it, the drill-down details list works as-is (IDs are sha256-derived strings, not persona-dependent). Confirmed no UX change needed; flagged here so build doesn't second-guess.
3. **Should `/wrap-insights` text section be width-aware?** Current format assumes ≥80-column terminal. If users run narrower, the right-aligned values wrap ugly. Recommendation: don't pad to fixed columns; use single-space separators between persona name and value parens. Keeps it readable at 60+ cols.
4. **Do we need a "Cost" sort affordance for the table?** Avg tok is sortable (per spec), but users may also want "show me the persona with the worst retention-per-token" (efficiency proxy). v1 punts: users sort Avg tok ascending and read across to Retention. Composite efficiency metric is explicitly out of scope per spec.

## Integration Points with other dimensions

- **`api`** (CLI ergonomics): I'm assuming `compute-persona-value.py` produces both `dashboard/data/persona-rankings.jsonl` AND a sibling JS bundle file (e.g., `dashboard/data/persona-rankings.js` setting `window.__PERSONA_RANKINGS = [...]`) so the dashboard avoids `fetch()`. If `api` chooses a different bundle name, I just need the global variable name to consume.
- **`data-model`**: I depend on `run_state_counts` being a flat object (`{complete_value: N, ...}`) for the dominant-state computation. If it ships as nested or as an array, the badge logic needs trivial adaptation.
- **`integration`**: `commands/wrap.md` Phase 1c needs to render the text format above. Spec already pins this — UX provides the verbatim template.
- **`testing`**: dashboard rendering tests should cover (a) e12 empty-state shows fresh-install banner not privacy banner, (b) deleted-persona row has both strikethrough + "deleted" badge, (c) insufficient-sample row dims and shows "—" but keeps Total tok readable, (d) stale-cache banner only renders when MAX(last_seen) > 14 days. These are DOM assertions, not visual regression.
- **`ops`** (privacy / public release): banner copy is the user-facing half of the privacy gate that A10 enforces machine-side. Keep them consistent — if A10's allowlist ever drops a field, the banner copy doesn't change (still warns about screenshots), but the empty-state copy's "Data is gitignored locally" claim depends on `dashboard/data/persona-rankings.jsonl` staying gitignored (per A9). Don't change one without the other.
