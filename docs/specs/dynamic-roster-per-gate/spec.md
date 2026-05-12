---
name: dynamic-roster-per-gate
description: Content-aware best-fit persona selection per gate — tag-matching + load-bearing-rate + (≥1 Opus, ≥1 Sonnet, 50/50 remainder) tier-mix rule with additive Codex, layered constitution + spec.md + CLI overrides
created: 2026-05-06
status: draft
session_roster: defaults-only (no constitution)
gate_mode: permissive
tags: [pipeline, integration, scalability, data]
---

# Dynamic Roster Per Gate Spec

**Created:** 2026-05-06
**Constitution:** none — session roster only
**Confidence:** Scope 0.95 / UX 0.92 / Data 0.92 / Integration 0.92 / Edges 0.90 / Acceptance 0.92

> Session roster only — run /kickoff later to make this a persistent constitution.

## Summary

Extend `scripts/resolve-personas.sh` (shipped in `account-type-agent-scaling`) from budget-driven to **content-aware** persona selection. The resolver reads `spec.md` `tags:` (set at `/spec` time), intersects with each persona's declared `fit_tags`, and ranks the eligible roster by `(fit_score × load_bearing_rate)`. The top-N are dispatched up to `agent_budget`. A tier-mixing rule guarantees **≥1 Opus + ≥1 Sonnet on every panel of N≥2, with the remainder split 50/50** (cost-conscious tiebreak: extra seat → Sonnet). Codex runs **additively** at every gate where it's wired — different lineage, low marginal cost, historically high-value (caught H1/H2 findings on autorun-overnight-policy v6, autorun-verdict-deterministic, dynamic-roster-per-gate run #6). `tier_pins` override at constitution + spec level. Three-tier override precedence — constitution → spec.md → CLI flag — matches the v0.9.0 `gate_mode` pattern.

This is the natural follow-up to `pipeline-gate-permissiveness` (v0.9.0): permissiveness decided *what to do with findings*; dynamic-roster decides *which agents are best-suited to find them in the first place*. A sibling spec (`pipeline-gate-rightsizing`, BACKLOG L) handles the orthogonal axis of *how many* agents to dispatch per work-class — this spec handles *which*.

**Sequencing:** unblocked. `account-type-agent-scaling` (resolver foundation) and `token-economics` (persona-rankings.jsonl source) are both shipped. Cold-start handling means this feature degrades gracefully when ranking data is sparse.

## Backlog Routing

| # | Item | Source | Routing | Reasoning |
|---|------|--------|---------|-----------|
| 1 | `pipeline-gate-rightsizing` lever 2 ("which agents per gate per work-class") | BACKLOG.md | (a) In scope | This IS dynamic-roster-per-gate. Folded in. |
| 2 | `pipeline-gate-rightsizing` levers 1, 3, 4, 5, 6 | BACKLOG.md | (b) Stays | Sibling spec — count/skip/codex-inclusion/iteration-cap/cost-skip are orthogonal axes. |
| 3 | Constitution rename (`constitution.md` → `pipeline-config.md`) | 2026-05-06 chat | (a) In scope | Naturally part of "constitution + spec drive selection" — needs its keys defined. |
| 4 | `account-type-agent-scaling` resolver foundation | shipped (a36f0bb) | (b) Stays | Foundation we extend, not re-spec. |
| 5 | `token-economics` persona-rankings source | shipped | (b) Stays | We consume `dashboard/data/persona-rankings.jsonl`; no new emission. |
| 6 | All other BACKLOG items | BACKLOG.md | (b) Stays | Unrelated. |

## Scope

**In scope:**

- **`spec.md` frontmatter `tags:` field** — closed enum: `[security, data, api, ux, integration, scalability, docs, refactor, migration]`. Multi-value (array). Set by `/spec` Phase 3 self-review pass via LLM-propose-user-confirm flow. Required for new specs created post-feature-ship; existing specs grandfathered (treated as empty intersection → ranking-only fallback).
- **Persona frontmatter `fit_tags:` field** — same closed enum subset per persona. Backfilled into all 19 existing personas (6 review + 7 plan + 6 check) as a one-time migration; LLM proposes, user reviews. Future personas declare at creation.
- **`scripts/resolve-personas.sh` extension** — adds content-tag intersection + `(fit_score × load_bearing_rate)` ranking. Output format extended: stdout emits `<persona>:<tier>` (e.g., `completeness:opus\nsequencing:sonnet`); `selection.json` adds a `tier` field per row. Codex stays unchanged (separate line, no tier suffix).
- **Tier rule (updated 2026-05-07)** — orchestrator (host Claude session) is Opus (already is); reviewer panel must include **≥1 Opus AND ≥1 Sonnet**, with the remainder (N − opus_min − sonnet_min) split **50/50** between Opus and Sonnet. Hard constraint, not preference. Codex runs **additively** at every gate where it's wired — runs whenever authenticated (existing behavior preserved). Coverage extension at /plan + /build wave-final is carved to sibling spec `pipeline-codex-coverage-extension`.
- **Tier-mix algorithm** (deterministic, panel size N):
  ```
  if N == 1:
      panel = [{tier: opus}]                          # opus_min wins; sonnet floor unsatisfiable
  else:
      base_opus    = max(opus_min, floor(N / 2))      # at least opus_min, at least half
      base_sonnet  = N - base_opus
      if base_sonnet < sonnet_min:
          base_sonnet = sonnet_min
          base_opus   = N - base_sonnet
      # Tiebreak for odd remainder: extra seat goes to remainder_tiebreak (default: sonnet, cost-conscious)
      panel = base_opus × {tier: opus} + base_sonnet × {tier: sonnet}
  ```
  Panel-size table at the defaults (`opus_min=1`, `sonnet_min=1`, `remainder_tiebreak: sonnet`):

  | N | Opus | Sonnet | Notes |
  |---|------|--------|-------|
  | 1 | 1 | 0 | opus_min wins; warning emitted (sonnet floor unsatisfiable) |
  | 2 | 1 | 1 | exactly the floors |
  | 3 | 1 | 2 | floor(3/2)=1; extra → Sonnet (cost tiebreak) |
  | 4 | 2 | 2 | clean 50/50 |
  | 5 | 2 | 3 | floor(5/2)=2; extra → Sonnet |
  | 6 | 3 | 3 | clean 50/50 |
  | 7 | 3 | 4 | floor(7/2)=3; extra → Sonnet |
  | 8 | 4 | 4 | clean 50/50 |

  Highest-(fit_score × load_bearing_rate)-ranked personas claim Opus seats first; remaining personas fill Sonnet seats in score order. `tier_pins` honored before the algorithm runs (pinned personas occupy their pinned-tier seat; remaining seats follow the rule).
- **Codex policy** — `codex: additive` (default) runs Codex at every wired gate when authenticated. `codex: disabled` for adopters without Codex set up. No tag-gating in v1 — Codex's track record (H1/H2 saves on autorun-overnight-policy v6, autorun-verdict-deterministic, dynamic-roster-per-gate run #6) doesn't justify the gating complexity.
- **Constitution-level `tier_policy` block** (in renamed `pipeline-config.md`):
  ```yaml
  tier_policy:
    orchestrator: opus
    panel:
      opus_min: 1                                # default; spec/CLI can raise
      sonnet_min: 1                              # default; ≥1 Sonnet on panels of N≥2
      remainder_split: even                      # alternatives: opus-heavy | sonnet-heavy
      remainder_tiebreak: sonnet                 # cost-conscious default for odd remainder
      codex: additive                            # alternative: disabled
    tier_pins:                                   # optional; persona → tier
      # check:
      #   scope-discipline: opus
  ```
- **Spec.md frontmatter override** — same `tier_policy` block valid in `spec.md` frontmatter; constitution-level keys override-merged with spec-level (spec wins on conflict).
- **CLI flag override** — `/spec-review --opus-min 2`, `--tier-pin <gate>:<persona>:opus` (one-off).
- **Constitution-level `spec_overridable_keys` allowlist + raise-not-retarget rule (SEC-01)** — `pipeline-config.md` declares `tier_policy.spec_overridable_keys: [opus_min, tier_pins]` (default). Spec.md may RAISE quality (bump `opus_min`, add new Opus pins) but cannot RETARGET security-class personas downward: any `tier_pins` entry that pins a `fit_tags:[security]` persona below the constitution-level tier (typically Opus) is **rejected at config-load** with a clear error. Constitution acts as the floor; spec can only strengthen. Detection rule lives in `_tier_assign.py`'s pre-flight validation; honored at all three gate dispatch paths and at autorun's resolver invocation. Spec.md frontmatter schema rejects malformed entries before they reach the resolver.
<!-- DEFERRED to v2 / sibling spec `pipeline-security-escape-hatches` per scope-discipline run #6: `--allow-security-downgrade` was MVP-bundling 3 ship-units. SEC-01 keeps the constitution-floor enforcement; the escape hatch is carved out. Spec.md tier_pins targeting security personas below floor are simply rejected in v1. Audit-logged opt-in is v2. -->
- **CLI token enum validation (SEC-01-followup)** — `--tier-pin <gate>:<persona>:<tier>` parses with strict regex + exact-membership allowlists:
  - `<gate>` ∈ {`spec-review`, `plan`, `check`} — exact match against pipeline-stage enum; reject with `error: unknown gate '<got>'; valid: spec-review|plan|check` and exit 2.
  - `<tier>` ∈ {`opus`, `sonnet`} — exact match against tier enum (Haiku is reserved per Out-of-scope); reject similarly.
  - `<persona>` — must match `^[a-z][a-z0-9-]{0,63}$` AND be a member of the discovered persona registry (`personas/<gate-dir>/*.md` filenames). Reject with `error: unknown persona '<got>' for gate <gate>; valid: <comma-joined-list>` and exit 2.
  - Validation lives in `_tier_assign.py` `validate_tier_pins(pins: dict, registry: dict) -> int` (returns 0 ok / 2 invalid). Called from all 6 invocation sites with documented exit-code contract: 0=ok, 2=invalid input (halt with error), 3=registry-load-failed (halt with different error). Sites: `commands/spec-review.md` Phase 0b, `commands/plan.md` Phase 0b, `commands/check.md` Phase 0b, `scripts/autorun/spec-review.sh`, `scripts/autorun/plan.sh`, `scripts/autorun/check.sh`. Shell wrapper at each site: `python3 _tier_assign.py validate-pins <pins.json> <registry.json>; case $? in 0) ;; 2) echo "[tier-policy] invalid --tier-pin"; exit 2;; 3) echo "[tier-policy] persona registry load failed"; exit 3;; *) echo "[tier-policy] unknown validator exit"; exit 4;; esac`.
- **Deterministic tag baseline + additive-only LLM inference (SEC-02)** — `scripts/_tag_baseline.py` computes a regex-based baseline over spec content. **Pre-processing pipeline (mandatory, ordered):** (1) NFKC normalize input string + zero-width strip; (2) Cyrillic-Latin confusables map (`_CYRILLIC_TO_LATIN`, ~30 entries — NFKC alone does NOT fold homoglyphs since U+0430 Cyrillic а ≢ U+0061 Latin a under canonical decomposition; the explicit map closes the `аuth` → `auth` bypass); (3) strip YAML frontmatter (must precede fence-strip so `tags: [security]` in frontmatter doesn't self-trigger); (4) strip balanced code fences (3+ tick, MULTILINE+DOTALL; unbalanced fences fall through to full scan; inline single-tick stays); (5) lowercase; (6) apply `BASELINE_KEYWORDS` regexes; (7) emit detected tags. Keyword regex tracks the closed enum (security: `auth|secret|token|rbac|tier|threat|pii|oauth|credential|cve|injection|permission|session|signing|key-rotation|password|api-key|sql-injection|csrf|xss|rce|untrusted-input|escape-hatch|downgrade|bypass|attack|vuln|exfiltrat|adversari|prompt-injection`; analogous regex per other tag).
- Both interactive `/spec` Phase 3 AND autorun pre-resolver compute baseline + LLM inference; final `tags = baseline ∪ llm_inferred`. **The LLM may ADD tags but cannot REMOVE baseline-detected tags** — closes prompt-injection vector. **Resolver-side recompute (mandatory):** at every gate dispatch, the resolver re-runs `_tag_baseline.py` against the spec content AND asserts `recomputed ⊆ recorded` (every keyword the resolver re-discovers must already appear in the recorded baseline). Halt fires when `recomputed ⊋ recorded` (recomputed has a keyword recorded doesn't = post-write shrinking attack) with `error: tags_provenance.baseline drift; recomputed=[<set>], recorded=[<set>]`. The inverse direction `recorded ⊋ recomputed` (author legitimately removed content) emits `[stale-tags] WARNING` and proceeds (see Edge Case 4). Grandfathered specs with no `tags_provenance` block are exempt — there's nothing to drift against. Author-writability of the provenance comment cannot let attackers shrink the baseline post-write. Provenance comment in spec.md: `tags: [security, data, api]   # baseline: [security, data]; llm-added: [api]` (informational only — resolver trusts the recompute). (Earlier revisions of this paragraph stated the assertion direction inverted; the implementation went with attack-model intent and this prose is now consistent with the resolver code at `_resolve_personas.py:644`.)
- **`/spec` Phase 3 self-review pass extension** — computes baseline first, then LLM proposes additions; user sees both with provenance, accepts/edits in same turn. User cannot manually remove baseline-detected tags via `/spec`'s self-review (would re-trigger baseline regex on next gate dispatch); must edit spec content if baseline match is incorrect.
- **`/spec-review` Phase 1 step 0 stale-tags warning** — at the existing snapshot step, compare current spec content against recorded `tags:`; emit one-line warning if drift detected (heuristic: tag would change under fresh inference). Does NOT auto-rewrite.
- **Cold-start handling** — when `persona-rankings.jsonl` doesn't exist or has fewer than 3 runs per persona, `load_bearing_rate` defaults to 0.5 uniformly → `fit_score` becomes the only differentiator. When `tags:` produces empty intersection, fall back to ranking-only (existing today's behavior).
- **Budget < opus_min handling** — `opus_min` wins; the single selected persona is upgraded to Opus. Gate stdout shows the resolution: `[tier-policy] budget=1, opus_min=1 → completeness:opus (sole panel member)`.
<!-- DEFERRED to sibling spec `monsterflow-pipeline-config-rename` per scope-discipline run #6: constitution rename was MVP-bundling. Carved cleanly — every reference to `constitution.md` in this spec stays as-is and gets renamed in the sibling spec. -->
<!-- DEFERRED to v2 / sibling spec `pipeline-resolver-debugging` per scope-discipline run #6: `--explain` was MVP-bundling. Resolver decisions remain inspectable via `selection.json` (which v1 already writes). Pretty-printer / dry-run formatter is v2. -->
<!-- DEFERRED to v2 / sibling spec `pipeline-security-escape-hatches` per scope-discipline run #6: `--acknowledge-baseline-mismatch` was MVP-bundling. Without the flag in v1, baseline-detected tags cannot be removed by user edit (per Edge Case 17 — resolver-recompute enforces this). User must edit spec content if baseline match is incorrect. -->
- **Dashboard tier-breakdown column** — `dashboard/index.html` adds a "Panel Tier Mix" column to the per-feature table (e.g., "1 Opus / 5 Sonnet + Codex"). Reads `selection.json`.
- **Test suite** — full A12-style matrix: tag×tier×budget×opus_min×tier_pins×Codex-additive×stale-tags×empty-intersection×cold-start, plus security-axis fixtures (SEC-01 downgrade-rejection, SEC-02 baseline-floor adversarial, SEC-03 mutation-zero). Same caliber as v0.9.0 (target: 50-70 fixtures).

**Out of scope (deferred to sibling specs per scope-discipline run #6):**

- **Constitution rename → `pipeline-config.md`** — sibling spec `monsterflow-pipeline-config-rename` (S; mostly find/replace + symlink + install.sh banner).
- **`--explain` flag** — sibling spec `pipeline-resolver-debugging` (S; pretty-printer over selection.json).
- **`--allow-security-downgrade` + `--acknowledge-baseline-mismatch` escape hatches** — sibling spec `pipeline-security-escape-hatches` (M; both hatches share the audit-log + followups-row + interactive-only refusal mechanism).
- **AC#5 NO_GO + all-blocking-axes iterative-resolution loops** — sibling spec `pipeline-iterative-resolution-loops` per BACKLOG (already partially shipped via security-attempts counter; broader spec generalizes).
- **Orchestrator rate-limit (HTTP 429) fallback design** — sibling spec `pipeline-rate-limit-resilience` (M; tier_policy.orchestrator=opus needs documented degradation path; surfaced by risk persona run #6).

**Out of scope (permanent — not carved):**

- Auto-detecting model availability per account tier (Opus may be rate-limited on Pro; user is responsible for setting `opus_min` they can afford).
- Per-persona model-version pinning (e.g., "use Opus 4.6 here, Opus 4.7 there"). v1 uses whatever the active CLI default is for the named tier.
- Haiku tier — the panel is Opus + Sonnet only. Haiku is reserved for non-reviewer roles (e.g., the eligibility-check pre-flight in `code-review` skill); not part of the panel.
- Mid-gate tier escalation ("retry this Sonnet finding with Opus if confidence low") — out of v1; possible v2.
- Cross-gate tier consistency ("if /spec-review chose Opus for security-architect, /check should too") — out of v1; each gate selects independently.
- Persona re-ranking based on tier outcome ("Opus reviewers contribute more; rank them higher") — out of v1; load_bearing_rate already captures this empirically.
- LLM-classifier-based tag inference at resolver dispatch time (rejected in Q3: c).

## Approach

**Chosen approach (user-directed):** content-tag matching + persona-rankings (`load_bearing_rate`) + tier-mixing rule, layered with three-tier override precedence (constitution → spec.md → CLI), matching the v0.9.0 `gate_mode` pattern.

**Rationale:**

- **Why tag-matching + rankings (not pure rankings):** rankings alone are content-blind — a security-heavy spec routes to whichever personas happen to load-bear most often, not the personas best-suited to security work. Tags add the content axis without abandoning the empirical signal.
- **Why ≥1 Opus + ≥1 Sonnet + 50/50 remainder (not all-Sonnet workers, not all-Opus):** Anthropic's 90.2% finding (Opus lead + Sonnet workers) is the published precedent for orchestrator/worker tier-mixing. We extend it within the worker panel: a guaranteed Opus voice preserves architectural depth, a guaranteed Sonnet voice preserves cost discipline, and the 50/50 remainder lets larger panels lean on their natural even-split shape (rather than one tier dominating). Cost discipline at small N comes from the cost-conscious tiebreak (extra seat → Sonnet).
- **Why Codex stays additive (not gated):** Codex's marginal cost is low (ChatGPT subscription + ~30s wall-clock per invocation) while its track record is high — H1/H2 saves on `autorun-overnight-policy` v6 (nonce trust-boundary), `autorun-verdict-deterministic` (4× H1 including unimplementable-execution-model), and `dynamic-roster-per-gate` run #6 (security findings). Different lineage doing a different job (plan-vs-codebase reality check, per memory `feedback_codex_catches_plan_vs_reality_drift.md`); not cost-tunable. Gating risks dropping the saves. The two real knobs are `additive` (default) and `disabled` (adopters without Codex set up). Coverage extension to `/plan` + `/build` is the sibling spec `pipeline-codex-coverage-extension`.
- **Why three-tier override (not constitution-only):** v0.9.0 just shipped this pattern for `gate_mode` — adopters already understand the precedence. Architectural specs genuinely need `opus_min: 2`; docs-only specs could go all-Sonnet. The override layers give the right knobs.
- **Why content-tags persisted (not LLM-inferred at resolver time):** classifier non-determinism means the same spec could route to different personas on different days. Persisted tags are deterministic, auditable, and editable by humans.

**Alternatives considered:**

- **Pure persona-rankings (no tags):** rejected — content-blind dispatch.
- **LLM-classifier at gate dispatch:** rejected — adds runtime cost, opacity, flakiness.
- **Tier-mixing as policy-only (no hard floor):** rejected — without a hard ≥1 Opus rule, cost optimization will drift the panel to all-Sonnet over time.
- **Phased v1 (interactive-only) → v2 (autorun):** rejected — autorun is the highest-cost path; ships with the value.

## Roster Changes

No roster changes. Current 19-persona roster covers the build:
- `data-model` — schema design (frontmatter `tags:` + `fit_tags:`)
- `integration` — resolver dispatch wiring across two paths (Agent tool + `claude -p`)
- `scalability` — cold-start behavior + cost implications of Opus floor
- `api` — CLI flag surface (`--opus-min`, `--tier-pin`)
- `ux` — `/spec` Phase 3 self-review tag-confirmation flow
- `security-architect` — tier-mixing implications + constitution-rename migration safety
- `testability` — A12 matrix design

## UX / User Flow

### `/spec` (creating a new spec)

After Phase 3 draft, self-review pass emits:

```yaml
---
name: my-feature
tags: [security, data]   # inferred from Scope §session-token-storage + Approach §RBAC
---
```

User sees the inferred tags + rationale comment, can accept ("looks right"), edit ("drop data, add api"), or override ("set tags manually"). One-turn confirmation, then write.

### `/spec-review` (running the gate)

```
$ /spec-review my-feature
=== /spec-review: my-feature ===
Resolving panel: tags=[security, data], budget=4, opus_min=1...
Selected: security-architect:opus | gaps:sonnet | requirements:sonnet | feasibility:sonnet
Codex: additive (sev:security adversarial review)
Dropped: ambiguity, scope, stakeholders (low fit_score for security+data)

Dispatching 4 Claude personas (1 Opus, 3 Sonnet) + Codex...
[stale-tags] WARNING: spec content has drifted since tags were set; consider /spec revision flow
```

### Override examples

**Architectural spec wants 2 Opus:**
```yaml
# In spec.md frontmatter
tier_policy:
  panel:
    opus_min: 2
```

**Pin a specific persona to Opus:**
```yaml
tier_policy:
  tier_pins:
    check:
      scope-discipline: opus
```

**One-off CLI override:**
```bash
/spec-review my-feature --opus-min 2 --tier-pin check:scope-discipline:opus
```

## Data & State

### `spec.md` frontmatter additions

```yaml
tags: [security, data, api]                    # closed enum, multi-value
tier_policy:                                   # optional; constitution provides default
  panel:
    opus_min: 1
  tier_pins:
    check:
      scope-discipline: opus
```

### Persona frontmatter additions

In `personas/<gate>/<name>.md`:

```yaml
---
name: security-architect
fit_tags: [security, integration]              # closed enum, multi-value
---
```

### `~/.config/monsterflow/config.json` additions

```json
{
  "agent_budget": 4,
  "persona_pins": { ... },
  "tier_policy": {
    "orchestrator": "opus",
    "panel": {
      "opus_min": 1,
      "sonnet_min": 1,
      "remainder_split": "even",
      "remainder_tiebreak": "sonnet",
      "codex": "additive"
    },
    "tier_pins": {},
    "spec_overridable_keys": ["opus_min", "sonnet_min", "remainder_split", "remainder_tiebreak", "tier_pins"],
    "security_floor": "opus"
  }
}
```

`spec_overridable_keys` (SEC-01) — whitelist of `tier_policy` keys spec.md may override. Default `["opus_min", "tier_pins"]`. Keys outside this list are constitution-only.

`security_floor` (SEC-01) — minimum tier any `fit_tags:[security]` persona must run at. Spec-level `tier_pins` cannot pin a security persona below this floor. Default `opus`.

### `_tag_baseline.py` regex schema (SEC-02)

Closed mapping of tag → regex match pattern (case-insensitive, word-boundary):

```python
BASELINE_KEYWORDS = {
    "security":    r"\b(auth|secret|token|rbac|threat|pii|oauth|credential|cve|injection|permission|session|signing|key[-_ ]rotation|sev:security|tier_policy|tier_pins|password|api[-_ ]key|sql[-_ ]injection|csrf|xss|rce|untrusted[-_ ]input|escape[-_ ]hatch|downgrade|bypass|attack|vuln|exfiltrat|adversari|prompt[-_ ]injection)\b",
    "data":        r"\b(schema|migration|jsonl|sqlite|database|atomic[-_ ]write|fcntl|flock|persisted)\b",
    "api":         r"\b(--[a-z][a-z0-9-]+|cli|flag|subcommand|env(?:ironment)?[-_ ]variable|stdout|stderr|exit[-_ ]code)\b",
    "ux":          r"\b(prompt|approval[-_ ]gate|user[-_ ]flow|confirm|interactive|q&a)\b",
    "integration": r"\b(hook|wrapper|symlink|install\.sh|gate|dispatch[-_ ]path)\b",
    "scalability": r"\b(parallel|wave|race|cold[-_ ]start|backoff|retry|timeout|rate[-_ ]limit)\b",
    "migration":   r"\b(symlink|backfill|deprecation|back[-_ ]compat|legacy[-_ ]fallback)\b",
}
# tags `docs`, `refactor` have no baseline regex — purely LLM- or user-driven.
```

Output: `set` of tag names whose regex matches the spec content (excluding code fences and YAML frontmatter to avoid false positives from documenting the regex itself in spec text).

### `selection.json` additions

Existing rows gain a `tier` field:

```json
{
  "selected": [
    {"persona": "security-architect", "tier": "opus", "fit_score": 2, "load_bearing_rate": 0.78, "combined": 1.56},
    {"persona": "gaps", "tier": "sonnet", "fit_score": 1, "load_bearing_rate": 0.65, "combined": 0.65}
  ],
  "dropped": [
    {"persona": "ambiguity", "fit_score": 0, "reason": "no_tag_intersection"}
  ],
  "tier_policy_applied": {
    "source": "spec",                          // constitution | spec | cli
    "opus_min": 1,
    "opus_count_actual": 1
  }
}
```

### `dashboard/data/persona-rankings.jsonl`

No schema changes. Tier mix surfaces at the dashboard render step (reads `selection.json`).

### `pipeline-config.md` (renamed from `constitution.md`)

```yaml
---
title: MonsterFlow Pipeline Configuration
version: 1.0.0
---

# MonsterFlow Pipeline Configuration

Project-wide pipeline configuration — agent roster, auto-run thresholds, tier policy, gate defaults.

## Tier Policy

```yaml
tier_policy:
  orchestrator: opus
  panel:
    opus_min: 1
    default_worker: sonnet
    codex: additive
  tier_pins: {}
```

[... existing constitution sections ...]
```

## Integration

### Files touched

**Schemas (W1):**
- `schemas/spec-frontmatter.schema.json` (NEW or extension) — `tags` enum + `tier_policy` block
- `schemas/persona-frontmatter.schema.json` (NEW) — `fit_tags` enum
- `schemas/selection.schema.json` (extension) — `tier` field on rows; `tier_policy_applied` block

**Resolver (W2):**
- `scripts/resolve-personas.sh` — content-tag intersection + ranking + tier-assignment logic; `--explain` flag (SEC-03 read-only formatter)
- `scripts/_persona_score.py` (NEW) — `(fit_score × load_bearing_rate)` calculation; cold-start handling
- `scripts/_tier_assign.py` (NEW) — top-N → tier rule; tier_pins override; budget < opus_min handling; **SEC-01 spec-level downgrade rejection** (security-floor enforcement at config-load)
- `scripts/_tag_baseline.py` (NEW) — **SEC-02 deterministic regex baseline**; AST-banlisted (no eval/exec/subprocess/socket); read-only spec text classifier
- `scripts/_explain_format.py` (NEW) — **SEC-03 read-only pretty-printer** over `selection.json` (or dry-mode resolver output); zero-write by construction (no file I/O except read of `selection.json`)

**Personas (W3):**
- `personas/review/*.md` × 6 — backfill `fit_tags:` frontmatter
- `personas/plan/*.md` × 7 — backfill `fit_tags:` frontmatter
- `personas/check/*.md` × 6 — backfill `fit_tags:` frontmatter
- `tests/test-persona-frontmatter.sh` (NEW) — schema validation

**`/spec` extension (W4):**
- `commands/spec.md` — Phase 3 self-review extension: LLM-propose-user-confirm tag flow

**Gate dispatch wiring (W5):**
- `commands/spec-review.md` — Phase 0b resolver call extended; reads `:tier` suffix; passes `model: "opus"` / `model: "sonnet"` to Agent tool dispatches
- `commands/plan.md` — same
- `commands/check.md` — same
- `scripts/autorun/spec-review.sh` — reads `:tier` suffix; passes `--model opus` / `--model sonnet` to `claude -p`
- `scripts/autorun/plan.sh` — same
- `scripts/autorun/check.sh` — same

**Stale-tags warning (W5):**
- `commands/spec-review.md` Phase 1 step 0 — drift detection at snapshot time

**Constitution rename (W6):**
- All references: `commands/*.md`, `scripts/autorun/*.sh`, `docs/index.html`, `install.sh`, `tests/*`, `templates/constitution.md` → rename to `pipeline-config.md`
- Symlink at old path for one release: `docs/specs/constitution.md` → `pipeline-config.md`
- Updated description in install.sh banner + README.md

**Dashboard (W6):**
- `dashboard/index.html` — "Panel Tier Mix" column on per-feature table
- `scripts/judge-dashboard-bundle.py` (or sibling) — read `selection.json` tier data

**Tests (W7 — full matrix):**
- `tests/test-dynamic-roster.sh` (NEW) — A12-style matrix: tag×tier×budget×opus_min×tier_pins×Codex×stale-tags×empty-intersection×cold-start
- `tests/test-tier-resolver.sh` (NEW) — `_tier_assign.py` unit tests
- `tests/test-persona-fit-tags.sh` (NEW) — fit_tags integrity (no orphan enum values, no empty fit_tags)
- `tests/test-resolve-personas.sh` (extension) — extend with tier output assertions
- `tests/test-spec-tags-flow.sh` (NEW) — `/spec` Phase 3 tag-inference flow (baseline ∪ llm union)
- `tests/test-security-floor.sh` (NEW) — **SEC-01** A21 fixtures (spec-level downgrade rejection on security personas)
- `tests/test-tag-baseline.sh` (NEW) — **SEC-02** A22 fixtures (baseline-keyword positive, baseline-keyword negative, adversarial-injection-omits-LLM-but-baseline-restores)
- `tests/test-explain-mutation-zero.sh` (NEW) — **SEC-03** A23 tmpdir mutation-zero fixture (find -newer asserts no changes)

**Docs (W6):**
- `CHANGELOG.md` — `[Unreleased]` section
- `README.md` — feature note + budget/tier-policy reference
- `docs/specs/dynamic-roster-per-gate/spec.md` (this file)
- `docs/budget.md` (existing) — extend with tier-policy reference

### Dependencies

**Existing infrastructure (no changes):**
- `scripts/resolve-personas.sh` budget cap + ranked-selection foundation (shipped in `account-type-agent-scaling`)
- `dashboard/data/persona-rankings.jsonl` (shipped in `token-economics`)
- `selection.json` schema + audit row (shipped in `account-type-agent-scaling`)
- v0.9.0 `gate_mode` precedence pattern (constitution → spec → CLI) — we mirror it
- Agent tool `model` parameter (Claude Code built-in)
- `claude -p --model` CLI flag (Claude Code built-in)

**No new external dependencies.**

## Edge Cases

1. **Budget < opus_min** → opus_min wins; sole selected persona is Opus. Gate stdout shows: `[tier-policy] budget=1, opus_min=1 → <persona>:opus (sole panel)`.

   **N=1 edge with sonnet_min=1** → `opus_min` takes precedence over `sonnet_min` at N=1 (cannot satisfy both with one seat). Gate stdout: `[tier-policy] budget=1, opus_min=1, sonnet_min=1 → opus_min wins; sonnet_min=1 not satisfied (panel size insufficient)`. Warning, not halt.

   **Budget < opus_min + sonnet_min (e.g., budget=1, opus_min=1, sonnet_min=1)** → same as N=1 above; opus_min wins. If `opus_min=2, sonnet_min=1, budget=2` → opus_min wins both seats; sonnet floor not satisfied; warning emitted. Constitution authors choosing aggressive `opus_min` are responsible for budget alignment.

   **Codex policy modes** (Edge 24): `codex: additive` (default) runs Codex whenever authenticated; `codex: disabled` never runs (for adopters without Codex set up); no other modes in v1. When authentication is missing, Codex is silently skipped regardless of policy (existing behavior).

2. **Empty tag intersection** → fall back to ranking-only (today's behavior). One-line warning at gate stdout: `[tier-policy] no fit_tags match spec.tags; falling back to load_bearing_rate ranking`.

3. **Cold-start (no rankings AND no/empty fit_tags)** → resolver uses existing seed-list fallback (the per-gate hardcoded list); tier rule still applied.

4. **Stale tags** → `/spec-review` Phase 1 step 0 emits warning but does NOT auto-rewrite. User triggers `/spec` revision flow (work-size option d) to refresh.

5. **`tier_pins` references unselected persona** → resolver promotes the pinned persona into the selection (overriding budget rank); emits warning: `[tier-policy] tier_pin promoted <persona>:opus into panel; dropped <other-persona>`.

6. **`tier_pins` references nonexistent persona** → resolver errors at config-load time with clear message; refuses to dispatch (different from finding-class block — this is a typo class, halt-and-fix is correct).

7. **`opus_min` > eligible roster size** → `opus_min` clamped to roster size; warning emitted.

8. **Constitution rename rollback** → symlink at old `constitution.md` path remains for one release; install.sh banner mentions both old and new names; CHANGELOG documents.

9. **Codex unavailable** → unchanged from today (silent skip); tier rule unaffected.

10. **Multi-spec session** → each gate dispatch resolves independently using the active `spec.md`'s tags + override layers. No cross-spec state.

11. **Stale tags + auto mode** → warning only (no halt). Auto-mode user sees the warning in run output; can interrupt next turn or accept the drift.

12. **Tier override at constitution + spec + CLI all set** → CLI > spec > constitution; later layer wins on each key (key-level merge, not block-level replacement).

13. **Persona file missing `fit_tags`** → treated as `fit_tags: []`; persona is eligible only via cold-start fallback (ranking-only). One-line warning at resolver invocation.

14. **`tags:` in spec.md uses unknown enum value** → resolver errors at config-load time with the closed-enum list; halt-and-fix.

20. **Per-dispatch model tier MUST be passed at invocation time, NEVER as a persistent wrapper file (D7 anti-pattern from run #6 security finding).** Implementation MUST use the Agent tool's built-in `model` parameter (`Agent(subagent_type: "<persona>", model: "opus" | "sonnet")`) for interactive dispatch and the `--model` CLI flag (`claude -p --model opus`) for headless dispatch. Implementation MUST NOT write per-dispatch wrapper subagent files to `~/.claude/agents/`, `.claude/agents/`, or any persistent location — that pattern enables (a) persistent prompt-injection on a SIGKILL'd dispatch leaving stale wrappers, (b) concurrent-write collision on parallel personas, (c) path-traversal at the write site. Plan stage MUST not introduce wrapper-file fallback as an "if model param doesn't work" path; if the Agent-tool model param fails, halt with a clear error and surface to user — do not silently write to disk.

21. **Code-fence exclusion grammar in `_tag_baseline.py` (SEC-02-followup; addresses run #6 security finding #3).** The pre-processing strip-code-fences step (Step 3 of the SEC-02 mitigation pipeline) uses regex `^(?P<ticks>` + "```" + `{3,})[a-z0-9-]*\n.*?\n(?P=ticks)$` (multiline + dotall) — i.e., 3-or-more backticks, balanced (closing tick count must match opening), language tag optional, content non-greedy. This catches both standard 3-backtick fences AND 4-backtick fences that v0.9.0 uses to quote example fences without inflating the count. Adversary cannot use 4-backtick to "hide" security keywords from the baseline scan — the regex strips them too. Conversely, an adversary cannot use 3-backtick to "show" non-security content as if it were a fence (because content INSIDE fences is excluded from scan, not added to it). Test fixtures MUST cover: (a) 3-tick fence with security keyword inside → keyword IS NOT detected (excluded), (b) 4-tick fence with security keyword inside → keyword IS NOT detected (excluded), (c) malformed unbalanced fences → entire content scanned conservatively (better safe than sorry), (d) inline `\`code\`` (single-tick) → NOT excluded (only triple+ fences strip).

22. **NFKC normalization required before regex match (SEC-02-followup; addresses run #6 security finding #2).** The pre-processing pipeline's Step 1 (NFKC normalize) closes Unicode-homoglyph bypass attacks where an attacker uses Cyrillic `а` (U+0430) instead of Latin `a` (U+0061) to spell `аuth` and evade the security keyword regex. After NFKC normalization, both render to canonical `a`. Test fixture: spec body containing Cyrillic-homoglyphed `аuth`/`tоken`/`раssword` MUST detect the security baseline tag.

23. **Resolver-side recompute of baseline at every dispatch (SEC-02-followup; addresses run #6 security finding #4).** The `tags_provenance.baseline:` field in spec.md frontmatter is author-writable (the spec file is in git, edited by humans). An attacker editing the file post-tag-set could shrink the recorded baseline. **The resolver MUST re-run `_tag_baseline.py` against current spec content at every gate dispatch** and assert `recorded_baseline ⊆ recomputed_baseline`. Strict-subset case (recorded < recomputed) → halt with `error: tags_provenance.baseline drift; recomputed=[<set>], recorded=[<set>]; spec content has security-relevant content not in recorded baseline (possible tampering)`. Equality is fine. The recorded value is informational; the recomputed value is authoritative for dispatch.

15. **Spec-level `tier_pins` attempts to downgrade a `fit_tags:[security]` persona below constitution default (SEC-01)** → rejected at config-load with `[tier-policy] SEC-01: spec.tier_pins[<persona>]=<tier> downgrades security persona below constitution floor (<floor>); spec may RAISE but not RETARGET security pins`. Refuse to dispatch; surface in interactive 3-option recovery prompt; abort in autorun.

16. **LLM tag inference omits a baseline-detected tag (SEC-02)** → final `tags = baseline ∪ llm_inferred` regardless; provenance comment shows both sources. No warning needed (the union IS the defense). Test fixture: adversarial spec body with prompt-injection attempt asserts `security` lands in tags despite LLM omission.

17. **User attempts to manually delete a baseline-detected tag during `/spec` Phase 3 confirmation** → `/spec` re-runs baseline regex on user-edited `tags:`; restores baseline-detected entries with explanation: `[tag-baseline] keyword '<match>' detected in <section>; keeping security in tags. To remove, edit the spec content.`

18. **`--explain` invoked when no `selection.json` exists** → resolver runs in dry-mode (`RESOLVER_DRY_RUN=1`), formats decision rationale to stdout, exits 0 with zero file mutations. No error.

19. **`--explain` invoked alongside other write-triggering flags** (e.g., `--explain --emit-selection-json`) → `--explain` wins; `--emit-selection-json` is silently demoted; one-line note: `[--explain] no-side-effects mode; --emit-selection-json suppressed`.

## Acceptance Criteria

A1. **Tag-matching baseline:** spec with `tags: [security, data]` + budget=4 dispatches the top-4 personas ranked by `(fit_count × load_bearing_rate)` where `fit_count = len(spec.tags ∩ persona.fit_tags)`.

A2. **Opus floor:** every dispatched panel includes ≥1 Opus reviewer when `opus_min ≥ 1`. Verified across all three gates (`/spec-review`, `/plan`, `/check`).

A2b. **Sonnet floor:** every dispatched panel of N≥2 includes ≥1 Sonnet reviewer when `sonnet_min ≥ 1`. At N=1, opus_min wins and sonnet_min is unsatisfied (warning emitted, no halt — per Edge Case 1).

A3. **Top-ranked wins Opus seats:** when `opus_min=1` and panel size N=2, the persona with highest combined score gets Opus; the other gets Sonnet. For N=3, the top score gets Opus, the next two get Sonnet (tiebreak: extra → Sonnet per `remainder_tiebreak: sonnet`).

A3b. **50/50 remainder split:** for the panel-size table at default tier_policy (opus_min=1, sonnet_min=1, remainder_tiebreak=sonnet), the actual Opus/Sonnet counts match the table:

| N | Expected Opus | Expected Sonnet |
|---|--------------|----------------|
| 2 | 1 | 1 |
| 3 | 1 | 2 |
| 4 | 2 | 2 |
| 5 | 2 | 3 |
| 6 | 3 | 3 |
| 7 | 3 | 4 |
| 8 | 4 | 4 |

Test fixture must run the full N=2..8 row set and assert exact tier counts per row.

A4. **Multi-Opus override:** when `opus_min=2`, the top-2 by combined score get Opus, then the 50/50 remainder rule applies to the rest (e.g., `opus_min=2`, N=4 → 2 Opus + 2 Sonnet; `opus_min=2`, N=5 → 2 Opus from the floor + remainder=3 split → 1 more Opus + 2 Sonnet, total 3 Opus + 2 Sonnet via `max(opus_min, floor(N/2))`).

A4b. **Tiebreak override:** when `remainder_tiebreak: opus` (constitution-overridden), N=3 → 2 Opus + 1 Sonnet (extra → Opus). Test asserts both tiebreak directions produce the documented panel.

A4c. **Codex policy:** `codex: additive` (default) runs Codex at every wired gate when authenticated; `codex: disabled` never runs. Test fixtures: (a) `additive` + auth-present → Codex runs; (b) `additive` + auth-missing → Codex silently skipped; (c) `disabled` + auth-present → Codex never runs. Verified across the gates where Codex is currently wired (`/spec-review`, `/check`). Coverage extension to `/plan` + `/build` is sibling-spec scope (`pipeline-codex-coverage-extension`), not v1 of this spec.

A5. **`tier_pins` override:** pinned personas always get pinned tier, regardless of combined score; remaining `opus_min - len(pins)` slots fall through to combined-score rule.

A6. **Constitution → spec → CLI precedence:** mirrors v0.9.0 `gate_mode` test pattern. CLI > spec > constitution; key-level merge.

A7. **Codex additive:** Codex line emitted in resolver stdout (when authenticated) regardless of tier policy; not counted in `opus_count_actual` or panel size budget.

A8. **Budget < opus_min:** sole panel member is Opus; gate stdout shows resolution; no error.

A9. **Empty tag intersection:** ranking-only fallback dispatches; warning emitted; no error.

A10. **Cold-start (no rankings, no fit_tags backfill):** seed-list fallback dispatches; tier rule applied (top of seed list gets Opus); no error.

A11. **Stale-tags warning:** `/spec-review` Phase 1 step 0 detects drift between recorded `tags:` and current spec content (tag heuristic re-inference shows ≥1 enum delta); one-line warning; no auto-rewrite; no halt.

A12. **`/spec` Phase 3 tag-inference:** synthesis pass emits `tags: [...]` with rationale comment; user-confirm path persists; user-edit path overrides; user-skip leaves field empty (treated as empty intersection at gate dispatch).

A13. **Resolver output format:** stdout emits `<persona>:<tier>` per line; `selection.json` includes `tier` field per row + `tier_policy_applied` audit block.

A14. **Both dispatch paths:** Agent tool dispatches receive `model: "opus" | "sonnet"`; `claude -p` invocations receive `--model opus | sonnet`. Verified end-to-end.

A15. **Constitution rename:** `pipeline-config.md` works; `constitution.md` symlink works for one release; install.sh banner shows new name; no broken references in commands/*.md, scripts/autorun/*.sh, docs/, tests/.

A16. **Dashboard tier mix:** per-feature row shows tier breakdown (e.g., "1 Opus / 5 Sonnet + Codex") read from `selection.json`.

A17. **Persona fit_tags backfill:** all 19 existing personas have `fit_tags:` declared; closed-enum validation passes; no empty fit_tags.

A18. **Test matrix:** A12-style fixtures × A1–A14 assertions = 40-60 PASSes; deterministic; <10s wall-clock.

A19. **Schema lockstep:** `spec-frontmatter.schema.json`, `persona-frontmatter.schema.json`, `selection.schema.json` all version-pinned; CI guard rejects partial PR landings (file-pair stubs prove bidirectional, per v0.9.0 precedent).

A20. **Pipeline cycle through itself:** this spec ships under v0.9.0 defaults (permissive gates) AND its own dynamic-roster framework once merged (last-mile dogfood test on /build's verification step against itself? deferred — chicken-and-egg).

A21. **SEC-01 — spec-level downgrade rejection.** Adversarial spec.md with `tier_pins: {security-architect: sonnet}` (where constitution-level default is opus) is rejected at config-load with the documented error string. Resolver does not dispatch. Test fixture: adversarial spec + asserting non-zero exit + asserting error string in stderr. Constitution-floor declaration: `pipeline-config.md` `tier_policy.security_floor: opus` is the source-of-truth for the floor; `_tier_assign.py`'s pre-flight reads it and compares against any `tier_pins` entry whose persona has `fit_tags` containing `security`.

A22. **SEC-02 — baseline floor cannot be removed by LLM.** Adversarial spec body containing security-keyword content (e.g., spec text mentions `auth`, `secret`, `token`, `rbac`, `tier`, `threat`, `pii`, `oauth`, `credential`, `cve`, `injection`, `permission`, `session`, `signing`, `key-rotation`) AND a prompt-injection attempt steering LLM classifier to omit `security` from tags ALWAYS results in `security ∈ final_tags`. Test fixtures: ≥3 keyword-baseline-positive specs (security must be present), ≥2 keyword-negative specs (security absent unless LLM adds for unrelated reasons), ≥2 adversarial-injection specs (LLM omits but baseline restores). Provenance comment in spec.md shows `# baseline: [security, ...]; llm-added: [...]`.

A23. **SEC-03 — `--explain` is mutation-zero.** Test fixture creates a tmpdir with a fixed file tree (containing `selection.json`), invokes `resolve-personas.sh --explain` (and `--explain` combined with every other flag), then asserts:
- exit code 0
- stdout contains all 5 documented sections (eligibility / scores / tier-assignment / dropped-with-reason / override-chain)
- `find <tmpdir> -newer <pre-invocation-marker>` produces zero output (no files created, modified, or deleted)
- when `selection.json` is absent, dry-mode runs and still produces zero file mutations.

## Open Questions

None at confidence ≥ 0.90 across all 6 dimensions. Two minor items deferred:

- **Q-haiku-tier:** Is there ever a case for Haiku in the panel (beyond the Codex-equivalent slot)? Out of scope for v1; revisit if cost data shows Sonnet-saturation.
- **Q-tier-escalation:** Mid-gate "if Sonnet finding has low confidence, escalate to Opus" — out of scope for v1; possible v2 follow-up.

## Constraints from Prior Research (2026-05-06)

- **No "≤3 same-model" cap published by Anthropic** — verified via [multi-agent research system blog](https://www.anthropic.com/engineering/multi-agent-research-system), [anthropic-cookbook agents patterns](https://github.com/anthropics/anthropic-cookbook/tree/main/patterns/agents), and [Subagents docs](https://docs.anthropic.com/en/docs/claude-code/sub-agents). Diversity comes from role-specialization + tier-mixing, not model-tier quotas.
- **Tier mixing endorsed:** *"Claude Opus 4 lead + Claude Sonnet 4 subagents outperformed single-agent Opus 4 by 90.2%"* — drives the orchestrator=Opus + ≥1-Opus-reviewer + Sonnet-workers shape.
- **Role-specialization > model-diversity:** Subagents docs frame the win as different *purposes*, not different *models*. Validates our reliance on `fit_tags` as the primary differentiator.

## Sequencing Note

Ships unblocked. `account-type-agent-scaling` (resolver foundation) and `token-economics` (persona-rankings source) are both shipped. Cold-start handling (A10) means this feature degrades gracefully in environments without ranking data.

Sibling spec `pipeline-gate-rightsizing` (BACKLOG, L) handles the orthogonal axis (count/skip/codex-inclusion per work-class). Recommended sequencing: this spec first → rightsizing second. Rightsizing's lever 2 has been folded into this spec; the remaining levers stand on their own.
