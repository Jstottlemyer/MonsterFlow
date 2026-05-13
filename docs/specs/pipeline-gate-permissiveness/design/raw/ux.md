## Summary (ux persona — full output captured in conversation)

**Banner split (Option A — recommended):** TWO sentinels.
- `~/.claude/.gate-mode-default-flip-warned-v0.9.0` (per-user, per-version): once-ever-per-machine verbose explanation (~5 lines stderr)
- `docs/specs/<feature>/.gate-mode-warned` (per-spec, existing): one-line nudge after per-user has fired

Verbose wording: explain v0.8 halt-on-anything → v0.9 architectural-only-blocks; opt back in via `gate_mode: strict`; CHANGELOG link; sentinel filename pinned to v0.9.0 so future flips re-fire.

Per-spec one-liner: `[gate] feature-xyz: no gate_mode pinned — running permissive (default).`

**`--force-permissive` UX (Option D — recommended): three-layer disclosure.**
1. **Stderr banner at invocation** (4 lines): names override, audit-log path, mode_source, plus reminder "architectural / security / unclassified findings still block."
2. **Audit log row format** (JSONL, NOT plaintext): `{"timestamp", "iteration", "gate", "user", "spec", "verdict_sidecar"}`. Greppable, parsable by `/wrap`.
3. **`/wrap` surface** (Phase 2 git-loose-ends adjacent — defer-able to v0.9.1 if `commands/wrap.md` work isn't in scope): `[wrap] Force-permissive overrides since last /wrap: 2` + per-row spec/gate/timestamp.

**`cap_reached` user-action path (Option E — recommended):** 3-line "next steps" block when `verdict: NO_GO AND cap_reached: true`. Lists 3 options with opinionated lean ("Recommended: option 1 — architectural findings rarely improve on iteration"). Stays silent when verdict is `GO_WITH_FIXES AND cap_reached`.

**`followups.md` rendering (Option F — recommended):**
- Header: provenance block (spec name, last gate, mode, iteration, links to JSONL + verdict.json), counts (Open / Addressed / Superseded hidden), brief "why this file exists"
- Sections: by `target_phase` first (build-inline, docs-only, plan-revision, post-build), then by `class` within
- Each row: finding_id, title, source-gate+iteration+persona in italics, suggested fix
- `regression: true` rows get `⚠ regressed (was addressed in <SHA>)` marker (only emoji exception)
- `addressed` and `superseded` rows hidden but counted in header
- Footer: one-line "rows close automatically when /build's wave-final commit references the finding_id"

**Error message tone:** keep `ERROR:` for genuine refusals (`--permissive` rejection); keep `WARNING:` for `--force-permissive`; use `[gate]` prefix for informational. Matches MonsterFlow voice (no emoji except regression marker, no color in stderr).

**Constraints:** sentinels are filesystem state not config; stderr-only for banners (stdout reserved for verdict JSON fence); plain-text JSONL audit logs; render-followups.py must be deterministic (same JSONL → same MD bytes).

**Open Questions:**
- OQ-UX-1: per-user sentinel filename `.gate-mode-default-flip-warned-v0.9.0` (just upgraded-to)
- OQ-UX-2: `/wrap-quick` includes force-permissive surface (security-adjacent audit signal, not opt-in)
- OQ-UX-3: footer says "rows close automatically when /build's wave-final commit references the finding_id"
- OQ-UX-4: cap_reached + GO_WITH_FIXES → silent (user is unblocked)
- OQ-UX-5: don't read working-tree gate_mode for banner suppression (negligible benefit)

**New ACs proposed:** A18 per-user sentinel fires once-ever; A19 per-spec sentinel after per-user; A20 force-permissive writes JSONL audit row; A21 cap_reached+NO_GO prints next-steps block; A22 followups.md header has provenance + counts; A23 regression rows get ⚠ marker.
