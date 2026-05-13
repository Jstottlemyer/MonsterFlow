## User Experience — dynamic-roster-per-gate

### Key Considerations

1. Tag-confirmation interaction needs an unambiguous prompt format (O4 was flagged by prior /check).
2. Baseline vs. LLM provenance must be visually distinct — users need to know which tags are locked.
3. Stale-tags warning placement: gate dispatch is correct (spec-save too early, drift hasn't occurred yet).
4. Tier-policy recovery must not feel like a trap. SEC-01 rejection gets a 3-option prompt; options must have consequences, not terse codes. Do NOT list unavailable options (v1 has no escape hatch for downgrade).

### Options Explored

**Tag confirmation prompt:**
- A) Free-form edit field (high friction, error-prone)
- B) Numbered selection (breaks at 10+ tags)
- C) Accept/override/skip with typed list (recommended — matches shell-native conventions)

**Stale-tags placement:**
- At gate dispatch (current plan) vs. at spec-save vs. both. Gate dispatch is correct.

### Recommendations

- Prompt wording: `Tags: [security*, data*, api] — Enter to accept, type comma list to override, or empty to skip:` where `*` = baseline-locked tags
- Baseline-locked tags rejected by the user re-appear with: `[security] is baseline-detected and cannot be removed.`
- Stale-tags warning: one line, prefixed `[stale-tags]`, ends with `run /spec revision flow to refresh`
- Drop A20 from any task list — not a real AC
- SEC-01 recovery options: inline in banner; remove any option that doesn't exist in v1

### Constraints Identified

- Baseline-locked tags are non-negotiable in the UI; rejection handling must be synchronous and inline
- Empty input = `tags: []` (unset), which is valid; gate dispatch must handle gracefully (empty intersection → ranking-only fallback)
- Autorun mode: auto-accept full inferred set (no interactive prompt)

### Open Questions

- Should SEC-01 recovery options appear inline in the banner or as a separate prompt block?

### Integration Points

- `_tag_baseline.py` output drives both the `*`-marker display and stale-tags detection; plan tasks must reference this single source
