## Security Persona — Dynamic Roster Per Gate (Revision)

### Threat Model by Surface

**Model-tier dispatch (S1):** Tier string flows from spec frontmatter → resolver → Agent tool param or `--model` flag. Risk: wrapper file written to persistent agents directory overrides tier on later dispatch. Empirical evidence that `model:` param controls dispatch is missing before any code ships.

**`_tag_baseline.py` (S2, S3, S5):** Tagger consumes author-controlled spec content. Two bypass vectors: homoglyph substitution (Cyrillic lookalikes evade ASCII regex) and keyword smuggling inside code fences. AST-banlist prevents the tagger itself from becoming an execution surface.

**`tags_provenance.baseline` (S4):** Author-writable field in spec.md. Resolver must own ground truth, not defer to recorded value.

**`tier_pins` + constitution floor (SEC-01):** Spec-author can pin a security-tagged persona to `sonnet` below the constitution floor. Must be rejected at two sites: frontmatter parse and `--tier-pin` CLI flag.

### Concrete Plan Tasks

**Pre-W2 empirical gate (S1, Risk MF-1) — blocks all dispatch code:**
- Verify `model: "opus"` in Agent tool param controls actual model used. Record evidence in `plan/dispatch-precedence-evidence.md`. Hard gate; W2 cannot open without it.

**S1 — No wrapper files:**
- Implement `--model <tier>` flag passing at all 6 dispatch sites (3 interactive commands + 3 autorun scripts).
- CI assertion: after full test suite run, assert `~/.claude/agents/_dispatch-*.md` does not exist.
- If Agent tool model param unsupported, halt with explicit error — no silent disk fallback.

**S2 — NFKC normalization:**
- `_tag_baseline.py` Step 1: `unicodedata.normalize("NFKC", content)` + strip zero-width chars (`​`, `‌`, `‍`, `﻿`) before any regex.
- Fixture: Cyrillic-homoglyphed `аuth` and `tоken` must produce `security` tag hit.

**S3 — Code-fence exclusion grammar:**
- Strip balanced 3-tick and 4-tick fences using `^(?P<ticks>\`{3,})[a-z0-9-]*\n.*?\n(?P=ticks)$` (MULTILINE + DOTALL).
- 4 required fixtures: keyword in 3-tick fence (not detected), keyword in 4-tick fence (not detected), unbalanced fence (full content scanned conservatively), inline single-tick (not excluded).

**S4 — Resolver recomputes baseline:**
- At every gate dispatch, resolver re-runs `_tag_baseline.py` on the spec file and asserts `recorded_baseline ⊆ recomputed_baseline`. If recomputed has MORE tags than recorded (drift), halt: `error: tags_provenance.baseline drift`.

**S5 — AST banlist for tagger:**
- CI test: parse `_tag_baseline.py` with `ast` module and assert no `eval`, `exec`, `subprocess`, `socket` nodes present.

**S6 — Audit write durability:**
- SEC-01 followup-row writes use atomic pattern: write to `<file>.tmp`, `fsync`, then `os.rename` to final path.

**S7 — Backup-dir permissions:**
- `chmod 700` on sec artifact backup dir at creation; `chmod 600` on individual artifact files.

**SEC-01 — Constitution floor at all 6 sites:**
- `_tier_assign.py` pre-flight: for every `tier_pins` entry, if persona carries `fit_tags: [security]`, reject if proposed tier is below `security_floor` from constitution.
- Same rejection at `--tier-pin` CLI parse site (G3 fix).

### Task Ordering

1. Dispatch-precedence evidence (pre-W2 gate, unblocks everything).
2. NFKC + fence-strip + banlist (tagger hardened before processing real specs).
3. Resolver recompute + subset assertion (S4).
4. Constitution-floor checks at both sites (SEC-01).
5. Atomic audit write + permissions (can parallelize).

### Constraints

- Empirical gate output must be a committed file, not verbal assertion.
- `tags_provenance.baseline` drift halt must surface a machine-readable exit code distinct from schema errors.

### Open Questions

- Does the Agent tool `model:` param accept arbitrary model IDs or only aliases (`opus`, `sonnet`)? Empirical gate resolves this.
- Is there a constitution schema field for `security_floor` today, or does the pre-flight check need to define it?

### Integration Points

- `_tag_baseline.py` hooks into resolver before tier assignment; must run before `_tier_assign.py`.
- SEC-01 floor check hooks into `_tier_assign.py` AND CLI flag parser; both must import from same constitution loader to avoid drift.
