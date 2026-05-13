## API & Interface Design — dynamic-roster-per-gate

### Key Considerations

1. **Stdout contract for `resolve-personas.sh`** — `<persona>:<tier>` is simple but callers must handle the new format without breaking existing piped usage. Every caller (`spec-review.sh`, `plan.sh`, `check.sh`) currently reads bare persona names; the colon-delimited format is a breaking change requiring simultaneous updates.

2. **`validate_tier_pins` exit codes** — exit 2 (invalid) vs 3 (registry-load-failed) is a meaningful distinction; callers must branch on both. exit 3 halts the full gate — registry failure is not recoverable silently.

3. **`--tier-pin` parsing site** — G3 requires SEC-01 floor validation at parse time, not just config-load. This means `_tier_assign.py::validate_tier_pins` must be callable from bash argument-parsing context (subprocess call), not only from within the Python helpers.

4. **`--opus-min N` semantics** — N must be bounded: `1 <= N <= panel_size - 1`. Unbounded N is a user error needing clear halt message. Flag interacts with tier-mixing rule; `--opus-min` raises the floor, never lowers it.

### Options Explored

**`<persona>:<tier>` vs JSON stdout for resolve-personas.sh**
- Colon-delimited: minimal diff to existing callers, grep-friendly, no `jq` dependency. Con: fragile if persona names ever contain colons (they currently don't).
- JSON array: structured, extensible. Con: all 3 gate scripts need `jq` wiring; higher change surface.
- **Recommendation:** colon-delimited with a guard assertion (persona names must not contain `:`).

**Merge semantics (G4) in bash vs Python**
- Bash `envsubst`-style overlay: error-prone for nested keys. Python deep-merge callable from bash subprocess: correct and testable.
- **Recommendation:** `_tier_assign.py` owns merge; bash passes raw JSON blobs as positional args.

### Recommendations

1. Emit `<persona>:<tier>` from `resolve-personas.sh`; add a single sed-based compat shim in each gate script to split on `:` before passing model flag to `claude -p`.
2. `validate_tier_pins` returns 0/2/3; gate scripts treat non-zero as hard halt with message to stderr.
3. `--tier-pin` calls `_tier_assign.py validate` as subprocess at parse time; non-zero exits abort before any stage runs.
4. `--opus-min` capped at `panel_size - 1`; conflict with tier-mixing rule resolved by taking `max(opus_min, tier_mix_floor)`.
5. `selection.json` adds `tier` string field per entry and a top-level `tier_policy_applied` object with keys: `source` (`constitution|spec|cli`), `pins_applied` (array), `mixing_rule_triggered` (bool).

### Constraints Identified

- SEC-01 floor is non-negotiable; `--tier-pin` cannot override it even with explicit user intent (escape hatch carved to sibling spec).
- YAML frontmatter strip (G7) must precede regex in `_tag_baseline.py`; order is load-bearing.
- `--tier-pin` accumulates (multiple flags per invocation) per G6/I6 fix.

### Open Questions

- Does `panel_size` vary per gate or is it a fixed constant? If variable, `--opus-min` bound check needs gate-awareness.

### Integration Points

- **Data-model persona:** owns `selection.json` schema additions; must coordinate field names before W2.
- **Security persona:** must sign off on SEC-01 floor enforcement at CLI parse site.
- **Integration persona:** owns the compat shim pattern and gate-script call-site changes.
