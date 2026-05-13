# Integration Analysis — token-economics v4

**Persona:** integration · **Stage:** /plan · **Spec:** token-economics v4

## Key Considerations

The spec touches five existing surfaces: `commands/wrap.md` Phase 1c, `scripts/session-cost.py`, `scripts/judge-dashboard-bundle.py` (pattern lineage), `dashboard/index.html` + sibling JS, and the persona-metrics artifact graph (`findings.jsonl` / `survival.jsonl` / `run.json`). It introduces three new top-level files (`scripts/compute-persona-value.py`, `schemas/persona-rankings.allowlist.json`, `tests/test-allowlist.sh`) and two generated dashboard data files (`dashboard/data/persona-rankings.jsonl`, `dashboard/data/persona-roster.js`). Spec is explicit that `findings-emit.md` and gate command files are NOT touched, and `dashboard-append.sh` is NOT a piggyback target.

The key wiring decisions are: (1) where exactly the new compute step slots into Phase 1c relative to the existing rollup, (2) whether `session-cost.py` is extended in place or paired with a sibling, (3) how the dashboard tab shares chrome with the existing Graphify/Judge mode toggle, and (4) when `persona-metrics-validator` fires given the spec says "after first /wrap-insights run."

The `dashboard-append.sh` carve-out is structural, not stylistic: that script runs on every wrap (not just `/wrap-insights`), regenerates only Graphify + Judge bundles, and prints the dashboard URL — it has no notion of "insights mode." Coupling persona compute to it would (a) burn cycles on `/wrap-quick` runs that explicitly skip 1c, and (b) execute even from contexts where `graphify-out/` exists but persona data doesn't.

## Options Explored (with pros/cons/effort)

### Option A — extend `session-cost.py` in place; add per-persona attribution mode

Add an `--attribute-personas` flag and a new code path in `session-cost.py` that walks `subagents/agent-<id>.jsonl`, joins via `agentId`, and emits per-(persona, gate, parent_session_uuid) cost rows on stdout (or to a JSONL).

- **Pros:** one walker for `~/.claude/projects/`, no duplicate model-pricing tables, follows the existing PRICING dict that already handles model drift.
- **Cons:** `session-cost.py` is currently a *display* tool that prints to stdout — adding a writer side-channel + cross-walking subagent dirs roughly doubles its surface area. The existing functions (`project_dir()`, `dedup_iter()`) all assume one cwd-derived sanitized project dir; persona attribution needs to walk *all* `~/.claude/projects/*/` because a `/spec-review` run in project X dispatches subagents under X's session, but the value artifacts that join to it live under whatever cwd ran `/wrap-insights` (often the same, but not necessarily).
- **Effort:** M. ~150-200 LOC delta; requires careful refactor of `project_dir()` to support both single-cwd (display) and multi-project (attribution) modes without breaking existing callers (`/wrap` Phase 1, `session-insights.py`).

### Option B — leave `session-cost.py` untouched; put cost attribution inside `compute-persona-value.py`

`compute-persona-value.py` becomes the single owner of per-(persona, gate, artifact_dir) attribution. It imports the pricing table + `entry_cost()` helper from `session-cost.py` (or duplicates the small `PRICING` dict if cleaner), but does its own walk of `~/.claude/projects/*/subagents/`.

- **Pros:** zero risk to existing `/wrap` Phase 1 cost display. Single owner per concern: `session-cost.py` = display, `compute-persona-value.py` = persistence. Easier to test (one script, one fixture set).
- **Cons:** mild duplication of the `~/.claude/projects/` walk pattern. Pricing table now has two readers — drift risk if Anthropic adds a new model and only one is updated.
- **Effort:** S-M. New script ~300-400 LOC total (cost walk + value walk + cascade + roster sidecar + safe_log). Pricing table can be `from session_cost import PRICING, entry_cost` with a `sys.path` insert (script already lives in `scripts/`).

### Option C — split into two scripts: `compute-persona-cost.py` + `compute-persona-value.py`

Cost walker emits intermediate `~/.claude/persona-cost-cache.jsonl`; value walker reads it + the persona-metrics artifacts and emits the final `persona-rankings.jsonl`.

- **Pros:** crisp separation; cost cache reusable for future BACKLOG #3 (per-plugin attribution).
- **Cons:** two scripts to wire into `wrap.md`; intermediate cache adds an idempotency surface (now A8 has to cover two writes, not one); spec only names ONE new script (`compute-persona-value.py`).
- **Effort:** L. Pushes against the spec's stated file list.

### Phase 1c wiring options

#### W1 — invoke after the existing 1c rollup, append a separate "Persona insights" sub-section

Existing 1c renders the legacy `=== Persona drift ===` block. New invocation runs after, renders `=== Persona insights ===` as the spec shows. Both blocks coexist.

- **Pros:** zero disruption to existing drift renderer; new sub-section is a pure addition; users who already read drift get the new view as a sibling.
- **Cons:** two blocks that overlap in concept (both "how are personas doing") — risk of user confusion about which to trust. Mitigated because they answer different questions (drift = week-over-week deltas; insights = absolute window stats including cost).

#### W2 — replace the existing 1c rollup with the new compute output

- **Pros:** single source of truth.
- **Cons:** the existing 1c renders ↑/↓ deltas and load-bearing combinations the new spec explicitly does NOT carry (spec §Approach: "v1 stays static — no week-over-week deltas"). Replacing would be a regression. Out of bounds.

#### W3 — invoke `compute-persona-value.py` *before* Phase 1c's existing rollup so the rollup can read fresh JSONL

The existing rollup reads `findings.jsonl` / `survival.jsonl` directly, not `persona-rankings.jsonl`. So this would only matter if the legacy renderer is later refactored to read the rollup file (out of scope).

### Dashboard integration options

#### D1 — new top-level mode toggle "Persona Insights" alongside Graphify | Judge

Header at line 70 of `index.html` would gain a third button.

- **Pros:** matches the existing pattern; `persona-insights.js` becomes a peer to `dashboard.js` / `judge.js`.
- **Cons:** the existing toggle is "data domain" (graph data vs judge artifact data). Persona Insights is closer to Judge (also reads from `docs/specs/<feature>/<gate>/`). Adding a third top-level mode dilutes the toggle.

#### D2 — new per-project tab inside the Judge mode

Each project tab in Judge mode could gain a "Personas" sub-section.

- **Pros:** stays inside Judge's data domain.
- **Cons:** persona-rankings is *cross-project aggregated*, not per-project — it would render the same data regardless of which project tab is active. Confusing.

#### D3 — new top-level mode "Personas" (recommended)

Add a third button at line 70: `<button data-mode="personas">Personas</button>`. Owns its own tab strip if needed (gate filter: spec-review / plan / check / all). New `dashboard/persona-insights.js` registers a `window.__renderPersonasView` mirroring the existing `__renderJudgeView` / `__renderGraphifyView` contract at line 92-97.

- **Pros:** mirrors existing extensibility pattern exactly; cross-project aggregation belongs at top-level (not nested under a project tab).
- **Cons:** three top-level modes start to crowd the header on narrow terminals — but the nav already wraps (`flex-wrap: wrap` at line 36).

### Script-load ordering for `persona-roster.js` + `persona-rankings.jsonl`

`persona-rankings.jsonl` is **JSONL**, not JS — it cannot be loaded via `<script src>`. Two sub-options:

- **L1 — bundle JSONL into a JS file** (like `data-bundle.js` and `judge-bundle.js`): `compute-persona-value.py` writes BOTH `persona-rankings.jsonl` (canonical, gitignored) AND a sibling `persona-rankings-bundle.js` (`window.__PERSONA_RANKINGS = [...]`). Spec only names the JSONL + roster.js; the bundle.js becomes a third generated artifact.
- **L2 — JSONL stays JSONL, dashboard reads it via `fetch()`** — spec mandates this won't work under `file://` (CORS); explicitly cited Round-3 finding "JS hybrid roster impossible under `file://`".

So **L1 is mandatory** — the spec already implicitly assumes it for `persona-roster.js`; for symmetry we need a `persona-rankings-bundle.js` too. The roster.js MUST load before the rankings bundle (or both before `persona-insights.js`), since the renderer merges them.

Order in `index.html`:
```html
<script src="./data/persona-roster.js" onerror="window.__PERSONA_ROSTER_MISSING=true"></script>
<script src="./data/persona-rankings-bundle.js" onerror="window.__PERSONA_RANKINGS_MISSING=true"></script>
<script src="./persona-insights.js"></script>
```

### `persona-metrics-validator` triggering options

#### V1 — manual on suspect drift only (current `commands/wrap.md` line 160 pattern)

Today it fires only when 1c "drift looks weird." Spec §Integration says invoke "after first `/wrap-insights` run that produces `persona-rankings.jsonl`."

- **Pros:** zero per-wrap cost.
- **Cons:** "first run" is hard to detect from inside Phase 1c without state. A sentinel file (`dashboard/data/.persona-rankings-validated`) would work but adds a hidden idempotency surface.

#### V2 — fire on every `/wrap-insights` (over-cautious)

Validator is read-only but does cross-project schema walks; on a multi-project laptop this is non-trivial.

- **Cons:** wastes cycles after the first successful validation.

#### V3 — fire when `persona-rankings.jsonl` was just *created* (not on update)

Phase 1c step: if the file did not exist before `compute-persona-value.py` ran, invoke validator after. Implementation: `[ -f dashboard/data/persona-rankings.jsonl ]` check before invocation; if missing-then-present, validate.

- **Pros:** matches spec wording; no sentinel; one-shot; no manual gate to remember.
- **Cons:** if a user deletes the file (gitignored, so they might), it re-validates on next run — acceptable, validator is read-only.

### `install.sh` integration

Spec §Project Discovery: `install.sh` writes `~/.config/monsterflow/README.md` if absent, explaining the cascade. Currently `install.sh` line 214 mentions `autorun.config.json` but has no `~/.config/monsterflow/` setup. This is a NEW responsibility for `install.sh`.

- **R1 — write the README during install** (one liner): `mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/monsterflow" && [ -f "$_/README.md" ] || cat > "$_/README.md" <<EOF`. Idempotent.
- **R2 — let `compute-persona-value.py` lazy-create on first run with a stderr nudge** — spec explicitly says script does NOT create the file; this would violate the spec. Reject.
- **R3 — defer README to a separate onboarding spec** — spec says the README write "is out of scope here; opens an issue in onboarding." So R1 is **optional** for v1; safe default is to NOT touch `install.sh` and let an onboarding follow-up own it.

### BACKLOG #3 (roster scaling) field decisions to commit now

#3 needs to consume `persona-rankings.jsonl` and decide *which personas to drop* under cost pressure. To avoid breaking #3:

- **Keep `persona`, `gate`, `total_tokens`, `avg_tokens_per_invocation`, `runs_in_window`, `judge_retention_ratio`, `downstream_survival_rate`, `uniqueness_rate` as stable typed fields** — already in spec. ✓
- **Add `schema_version: 1`** — already in spec. ✓
- **Ensure `gate` is the canonical command name** (`spec-review`, `plan`, `check`) — not display variants. Already implied; should be asserted in `schemas/persona-rankings.allowlist.json` enum.
- **Sort rows deterministically** — `(gate, persona)` per A8. ✓
- **Reserve a `tier` field name** for #3 (`tier: "core" | "optional" | null`) — NOT emitted in v1, but reserve in the allowlist as nullable so #3 can add it without an allowlist breaking change. **This is the one new decision for plan to make.**

## Recommendation

**B + W1 + D3 + L1 + V3 + R3, plus the `tier` allowlist reservation.**

### Concrete wiring

1. **`scripts/compute-persona-value.py` (NEW, ~400 LOC):**
   - Imports `from session_cost import PRICING, canonical_model, entry_cost` via `sys.path.insert(0, str(Path(__file__).parent))` (single-source pricing).
   - Owns: cascade resolution (cwd / `${XDG_CONFIG_HOME:-$HOME/.config}/monsterflow/projects` / `--scan-projects-root`), cost walk (`~/.claude/projects/*/*.jsonl` + `subagents/`), value walk (`docs/specs/*/{spec-review,plan,check}/{findings,survival,run}.json{l}`), roster sidecar emit, rankings bundle emit, safe_log stderr.
   - Writes atomically (tmp + `os.replace`): `dashboard/data/persona-rankings.jsonl`, `dashboard/data/persona-rankings-bundle.js`, `dashboard/data/persona-roster.js`.
   - Stderr telemetry line per spec §Project Discovery: `[persona-value] discovered N projects: ...`.

2. **`scripts/session-cost.py` — DO NOT MODIFY.** Spec §Integration says modify, but the cleaner separation is: leave it as the display tool; `compute-persona-value.py` re-uses its pricing helpers via import. **This deviates from the spec's stated "modify session-cost.py" and is a candidate for `/check` to flag.** Justification: lower blast radius, cleaner test boundary, explicit ownership. The spec line "extend `scripts/session-cost.py` to walk both root families" was written before round-3 narrowed scope to artifact-directory aggregation; the per-row attribution that motivated extending it is now clearly owned by the new script.

3. **`commands/wrap.md` Phase 1c (modify):** insert ONE new code block after line 160 ("Deeper validation..." paragraph) and before line 162 (the `### Emit drift triage candidates` header). The block:
   ```bash
   # token-economics v1: persona insights compute + render
   _had_rankings=$([ -f dashboard/data/persona-rankings.jsonl ] && echo 1 || echo 0)
   python3 ~/Projects/MonsterFlow/scripts/compute-persona-value.py 2>&1 | sed 's/^/[persona-value] /' >&2
   if [ "$_had_rankings" = "0" ] && [ -f dashboard/data/persona-rankings.jsonl ]; then
     # First successful build — invoke validator (V3 trigger).
     # Use Agent tool with subagent_type: persona-metrics-validator.
     :
   fi
   ```
   Then render the "Persona insights (last 45 (persona, gate) directories...)" sub-section per spec §Approach Phase 2.
   - **Unconditional within 1c** per spec. The phase itself is still skipped on `quick` arg (per existing line 19), which is the right behavior — `/wrap-quick` adopters opt out of all measurement.

4. **`dashboard/index.html` (modify):**
   - Line 70-71 area: add `<button data-mode="personas">Personas</button>`.
   - Line 81-84 area: add three `<script src>` tags (roster, rankings bundle, persona-insights.js) in that order, each with an `onerror` sentinel.
   - Line 92-97 area: extend the mode-toggle handler to call `window.__renderPersonasView()`.

5. **`dashboard/persona-insights.js` (NEW):** mirrors `judge.js` shape — registers `window.__renderPersonasView`, reads `window.__PERSONA_RANKINGS` and `window.PERSONA_ROSTER`, performs the hybrid merge (data + roster + deleted strikethrough), renders the sortable table with the warning banner.

6. **`scripts/dashboard-append.sh` — DO NOT MODIFY.** Confirms the spec's "NOT piggybacked" carve-out. Persona compute lives only in `/wrap-insights` Phase 1c, not in every wrap.

7. **`schemas/persona-rankings.allowlist.json` (NEW):** enumerate every field in the spec's §Data row schema PLUS reserve `tier` (nullable string, enum `["core", "optional", null]`) for BACKLOG #3 forward-compat. Adding to the enum later is a non-breaking change; reserving the field name now means #3 doesn't need an allowlist migration.

8. **`install.sh` — DO NOT MODIFY in this spec.** Defer the `~/.config/monsterflow/README.md` write to the onboarding follow-up spec (BACKLOG #2). Adopters discover the cascade via the stderr telemetry line on first `/wrap-insights` run, which is documented in spec §Project Discovery.

9. **`.gitignore`:** add `dashboard/data/persona-rankings.jsonl`, `dashboard/data/persona-rankings-bundle.js`, `dashboard/data/persona-roster.js`. Existing `dashboard/data/*.jsonl` rule covers (1); (2) and (3) need explicit lines (or extend the glob to `dashboard/data/persona-*`).

## Constraints Identified

- **`file://` CORS** forbids `fetch()` for the rankings JSONL — mandates the bundle.js sidecar (L1). Spec acknowledges this for `persona-roster.js` but doesn't extend the same logic to `persona-rankings.jsonl` itself; the plan must.
- **`persona-roster.js` MUST load before the rankings bundle** so renderer can compute the hybrid merge in one pass without re-firing on async load (no async — both `<script src>` tags are synchronous).
- **`session-cost.py`'s `project_dir()` function (line 53-57) is hardcoded to cwd-sanitization.** Any extension would need to handle multi-project walks. This is the structural reason Option B beats A.
- **Phase 1c skip-conditions in `wrap.md` line 119** (`docs/specs/` contains fewer than 3 features with measured data) currently gate the *legacy drift renderer*. The new persona-insights compute MUST run unconditionally per spec — so the new code block goes INSIDE Phase 1c but BEFORE the existing skip check, OR Phase 1c's skip is rewritten to gate only the legacy block. **Recommended: keep the legacy skip on its own block; the new compute block is independent and runs always when 1c fires.**
- **`persona-metrics-validator` V3 trigger requires a pre-check + post-check** of the rankings file's existence — a 3-line bash dance, but stable.
- **The `tier` field reservation is forward-compat only** — emitting it in v1 (even as `null`) would be in spec scope creep. Reserve in allowlist schema; do not emit. #3 can populate later.
- **`dashboard-append.sh` regenerates `judge-bundle.js` on every wrap** (line 156-157). The new persona bundle is regenerated only on `/wrap-insights` — so the dashboard's persona tab can stale by hours/days if user only runs `/wrap-quick`. The spec's e6 stale-cache banner covers this; adopters see "last refreshed 14d ago" rather than wrong numbers.

## Open Questions

1. **Should `compute-persona-value.py` be invokable standalone for testing/manual refresh, or only via `/wrap-insights`?** Spec implies standalone (the `--scan-projects-root` flag, A3 test invocation). Recommendation: standalone-first; `/wrap-insights` is just one caller. No flag changes needed for the wrap caller — defaults work.
2. **Where does `persona-rankings-bundle.js` get regenerated if the user manually edits `persona-rankings.jsonl`?** Recommendation: don't optimize for this — `/wrap-insights` is the only sanctioned writer; manual edits are unsupported. Document in spec §Multi-machine sync follow-up.
3. **Should we deviate from the spec's stated "modify `scripts/session-cost.py`" line in §Integration?** This recommendation does. `/check` should explicitly flag this so user can confirm or reject. If rejected, fall back to Option A with a careful refactor.
4. **`install.sh` README write — really defer to onboarding spec, or sneak it in?** Adding 3 lines to `install.sh` is cheap; the risk is cross-spec coupling. Recommendation: defer (R3); onboarding spec is BACKLOG #2 and is "stays" routing — still on the radar.

## Integration Points with other dimensions

- **data-model:** owns the `persona-rankings.jsonl` row schema and the `schemas/persona-rankings.allowlist.json` field list. Integration recommends adding a reserved nullable `tier` field to the allowlist enum (forward-compat for BACKLOG #3) but NOT emitting it in v1. Data-model should confirm the allowlist enum approach is compatible with their schema design.
- **ux:** owns the dashboard tab visual design and the `/wrap-insights` text section formatting. Integration commits to a third top-level mode button (D3); ux owns whether it's labeled "Personas" or "Persona Insights" and the in-tab gate filter UX.
- **api / scalability / security:** the script-load order constraint (roster before rankings bundle before renderer) is a hard ordering dependency security/scalability personas should validate doesn't introduce a race under any future async-load refactor.
- **All dimensions:** the deviation from spec §Integration's "modify `scripts/session-cost.py`" line (Option B over A) is a cross-cutting decision; all design personas should weigh in if they have an opinion before `/check` runs.
