# PLAN: Plot Layer — Narrative Context for MonsterFlow

**Spec:** `docs/specs/plot-document/spec.md`
**Review:** `docs/specs/plot-document/spec-review/review.md`
**Gate mode:** permissive (frontmatter)
**Designers:** api, data-model, ux, scalability, security, integration, wave-sequencer (7 agents)
**Date:** 2026-05-11

---

## Architecture Summary

The Plot Layer adds a narrative context system to MonsterFlow through four phased deliverables, centered on a single new data contract: markdown files in `plot/` with inline code links and in-document `[!STALE]`/`[!DRAFT]` annotations. The annotation contract is the load-bearing interface shared across three commands (`/plot`, `/wrap` Phase 2d, `/spec` Phase 0.2c).

The key architectural decision is **annotations-as-state**: no sidecar files, no `findings.jsonl`, no separate status tracking. The document itself is the source of truth. This eliminates the `findings.schema.json` incompatibility flagged as B1 in review and avoids speculative infrastructure.

A deterministic Python helper (`scripts/_plot_annotations.py`) handles all annotation manipulation (injection, dedup, removal, link extraction), ensuring consistency across commands and enabling scripted test coverage. The LLM decides *what* is stale; the helper does *how* the annotation is written.

## Key Design Decisions

### D1. Deterministic annotation helpers (unanimous — 7/7 agents)

**Decided:** Create `scripts/_plot_annotations.py` — a Python 3.9+ stdlib-only module exposing both CLI and importable API for: `inject-stale`, `remove-stale`, `inject-draft`, `remove-draft`, `extract-links`, `status`.

**Alternatives considered:**
- Pure LLM manipulation (no helpers) — rejected because LLMs are unreliable at structured string surgery (S6), and AC26 requires deterministic scripted tests.
- Shell-only helpers (awk/sed) — rejected because multi-line markdown parsing in BSD sed (macOS) is fragile; project already prefers Python for structured text manipulation (`_class_tagging_splice.py` pattern).

**Rationale:** The annotation format is a cross-command contract. Both `/plot` and `/wrap` Phase 2d must produce identical callout syntax. A single helper is the enforcement mechanism. Follows the existing `_class_tagging_splice.py` pattern: structured markdown surgery in Python, atomic writes via `tempfile + os.replace`.

### D2. Diff-scope optimization for `/wrap` Phase 2d (4/7 agents)

**Decided:** Two-tier staleness check in Phase 2d:
1. **Tier 1 (deterministic, always runs):** Extract all link targets from chapters using the helper. Intersect with `git diff --name-only` session diff. If empty → "Plot: intact." and stop.
2. **Tier 2 (LLM, conditional):** Read only chapters whose links intersect the diff + their linked files. Run scoped LLM comparison.

**Alternatives considered:**
- Full LLM check every session — rejected; 30-120s per `/wrap` run, blows the 2-3 minute budget.
- File-existence-only check (no LLM) — rejected; too shallow, misses semantic staleness.
- Per-chapter fingerprint cache — rejected; requires sidecar state file, over-engineered for v1.

**Rationale:** Common case (no chapter-linked files changed) is sub-second. Triggered case is scoped to relevant chapters only. Matches the spec's latency analysis from S5.

### D3. Zero-arg auto-routing with status announcement (3/7 agents)

**Decided:** `/plot` takes no arguments and no flags. Auto-routes based on filesystem state per the B5-clarified state machine. Prints a one-line routing announcement before proceeding:
```
Plot: no document found — bootstrapping from codebase.
Plot: PLOT.md found, 2 of 5 referenced chapters missing — drafting missing chapters.
Plot: all chapters present — running check.
```

**Alternatives considered:**
- Optional override subcommands (`/plot bootstrap`, `/plot check`) — deferred to v1.1 if dogfooding reveals need.
- Confirmation gate for bootstrap — unnecessary because the scope summary (step 4) already serves as the confirmation gate.

### D4. Layer 1 checking — tiered by context (scalability vs security, resolved)

**Decided:** Layer 1 (`PLOT.md`) checking uses a tiered approach:
- **`/wrap` Phase 2d, graphify present:** Layer 1 checked against `graphify-out/GRAPH_REPORT.md` — cheap file-read comparison that catches structural shifts (new god nodes, disappeared communities). If graphify absent, Layer 1 skipped in Phase 2d.
- **`/plot` interactive:** Layer 1 always checked — uses graphify (if available) *plus* broad code exploration (directory tree, key files, entry points). Full pass, acceptable cost because user is present.

Graphify is an **accelerator, not a dependency.** Projects without graphify still get full Layer 2 checking in Phase 2d and full Layer 1 checking via `/plot`. Removing graphify or changing its format only affects the Phase 2d Layer 1 check — it degrades to "skip," the same behavior as graphify-absent.

**Alternatives considered:**
- Always skip Layer 1 in Phase 2d — rejected; opportunistic graphify check is cheap and catches real structural shifts.
- Use CLAUDE.md as anchor — rejected; different purpose (conventions vs. narrative), risks circular drift between two self-descriptions.
- Use directory tree as anchor — rejected; brittle, no reason to assume directory structure maps to narrative context.
- Require graphify — rejected; creates hard coupling to another knowledge store.

### D5. Post-bootstrap check is report-only (3/7 agents)

**Decided:** Bootstrap step 6 runs check but does not offer updates. Framed as: "Baseline check complete. No findings." or "Baseline check complete. N items noted — address in your first editorial pass." All bootstrapped sections carry `[!DRAFT]` (see OQ3).

**Rationale:** The prose was just derived from the code. Offering updates implies the bootstrap was flawed, which confuses the user. The `[!DRAFT]` tags communicate that content awaits editorial review without blocking value delivery.

### D6. Dual annotation support (3/7 agents)

**Decided:** A section can have both `[!DRAFT]` and `[!STALE]` callouts simultaneously. They mean different things and are managed independently. Ordering: `[!STALE]` first (injected by automation), then `[!DRAFT]` (from human-triggered `/plot`).

**Rationale:** `[!DRAFT]` means "AI-generated, not reviewed." `[!STALE]` means "prose contradicts code." Both can be true. `/spec` Phase 0.2c treats the section as stale (stronger signal wins for confidence).

### D7. Path containment for extracted link targets (deferred)

**Deferred to Phase 4 CI gate.** The current threat model is a single developer running locally on their own repo — path containment adds complexity with no current consumer. The `extract-links` helper resolves relative paths from each chapter's directory and skips non-existent targets. A `# TODO: add path containment when Phase 4 CI gate ships (reject absolute paths, .. traversal, symlink escapes via realpath, URL-scheme links; anchor to git rev-parse --show-toplevel)` comment marks the future work.

**Original rationale (preserved for Phase 4):** In a CI gate context, unsanitized paths from a PR branch could cause a CI runner to read files outside the repo. When Phase 4 ships, implement the `build.sh` path sanitization pattern: reject absolute paths, reject `..` traversal escaping the repo, use `realpath` to catch symlink escapes, reject URL-scheme links (`file://`, `https://`), anchor containment to `git rev-parse --show-toplevel` (not cwd).

## Open Questions — Resolved

### OQ1. Chapter reference format in PLOT.md → Standard markdown links

PLOT.md references its chapters via standard markdown links: `[Payment Flow](chapters/payments.md)`. This reuses the same `extract-links` helper, makes routing fully deterministic, and is clickable in GitHub/IDE. The routing state machine parses these links to determine which chapters should exist vs. which files actually exist.

### OQ2. Layer 1 staleness anchoring → Graphify (opportunistic) + code exploration (interactive)

See D4 above. `/wrap` Phase 2d uses `graphify-out/GRAPH_REPORT.md` as a cheap structural anchor when available, skips Layer 1 when absent. `/plot` interactive mode always checks Layer 1 via graphify (if available) plus broad code exploration. Graphify is an accelerator, not a dependency — no coupling risk.

### OQ3. Bootstrap `[!DRAFT]` default → Draft by default

Bootstrapped content carries `[!DRAFT]` on every section by default. The developer removes `[!DRAFT]` during the editorial pass — either in-session or incrementally across future sessions. This is more honest: unreviewed AI-generated narrative should not be treated as human-verified.

A perpetually `[!DRAFT]` Plot Document causes no problems:
- `/wrap` Phase 2d still detects and annotates staleness (dual annotation, D6)
- `/spec` Phase 0.2c still uses the content as context, just not as authoritative
- `/plot` check still reports findings and surfaces `[!DRAFT]` annotations
- The `/wrap` report line says "Plot: N draft sections" — informational, not blocking

Value flows at a lower confidence tier until the human blesses it. Incremental review is supported — one chapter at a time, over multiple sessions.

## Risk Register

| # | Risk | Probability | Impact | Mitigation |
|---|------|-------------|--------|------------|
| R1 | Annotation format drift between `/plot` LLM output and helper expectations | Medium | High — dedup breaks, duplicate callouts | Both `/plot` and `/wrap` must invoke helpers exclusively (never free-form LLM editing) |
| R2 | Diff-scope false negatives (chapter describes behavior in unlinked files) | Medium | Low — section not checked, staleness persists | Improve link coverage editorially over time; `/plot` interactive check is unscoped |
| R3 | Dogfood gate (AC8) blocks downstream waves | Low | Medium — delays Phases 2-3 | Develop against synthetic fixtures; merge dogfood before production testing |
| R4 | `/wrap` Phase 2d false positives erode trust | Medium | Medium — gate gets ignored | Staleness calibration examples in `commands/plot.md`; evaluate at prose abstraction level |
| R5 | Large Plot Document context consumption in `/spec` | Low | Low — tokens consumed but within 200K budget | Filter chapters by keyword match against `$ARGUMENTS` for relevance |

## Agent Disagreements Resolved

- **Layer 1 in Phase 2d** — Scalability said skip (latency), Security said check (completeness) → **Tiered approach.** Check against graphify when available (cheap); skip when absent. Full check in interactive `/plot` mode. Graphify is an accelerator, not a dependency.
- **Confirmation gate for bootstrap** — API said no confirmation needed; UX considered confirmation banner → **No confirmation.** The scope summary (step 4) is the natural gate; adding a separate confirmation prompt before bootstrap work starts adds friction with no value since the user explicitly typed `/plot`.

## Implementation Tasks

| # | Task | Wave | Depends On | Size | Parallel? |
|---|------|------|-----------|------|-----------|
| 1 | Create `scripts/_plot_annotations.py` — deterministic helpers for: inject-stale (with dedup + 3-reason cap + oldest-drop renumber), remove-stale, inject-draft, remove-draft, extract-links (resolve relative paths from chapter dir, skip non-existent targets; `# TODO` comment for Phase 4 path containment per D7), status. Atomic writes via `tempfile.mkstemp(dir=target_dir) + os.replace`. | W1 | — | M | — |
| 2 | Create `tests/test-plot-annotations.sh` — scripted tests: inject-stale into clean section, inject-stale with existing reasons, 3-reason cap with renumber, remove-stale, inject-draft into clean section, remove-draft, dual-annotation (inject-stale into section with existing [!DRAFT] per D6), status sub-command (verify correct counts for mixed stale/draft/clean sections), extract-links (verify repo-relative paths compatible with `git diff --name-only`), Tier 1 diff-scope intersection (fixture chapter + mock diff → correct chapter selection). Register in `tests/run-tests.sh` TESTS array; `chmod +x` the test file. | W1 | 1 | M | — |
| 3 | Write staleness calibration examples (3-5 labeled stale/not-stale with reasoning) for inclusion in `commands/plot.md` | W1 | — | S | Yes (with 1) |
| 4 | Create `commands/plot.md` — full command definition: frontmatter, auto-routing state machine, bootstrap flow (6 steps with draft-by-default), check flow (7 steps), broken link handling, editorial pass semantics, post-bootstrap report-only check. PLOT.md uses markdown links to reference chapters. Invokes helpers for all annotation manipulation. | W2 | 1, 3 | L | — |
| 5 | Dogfood: run `/plot` on MonsterFlow, bootstrap Plot Document, perform editorial pass, commit `plot/PLOT.md` + `plot/chapters/*.md` | W2b | 4 | L | — |
| 6 | Add Phase 2d to `commands/wrap.md` — new section between Phase 2c and Phase 3. Skip conditions: quick mode, `plot/PLOT.md` absent. Diff-scope Tier 1 + scoped LLM Tier 2. Report line. Silent, no interaction. Also update all phase enumerations: add "2d" to the default phase list in the wrap.md header block, the quick-mode skip list, and the quick-argument description. Update `wrap-quick.md`, `wrap-full.md`, and `wrap-insights.md` if they reference phase lists. | W3 | 1, 5 | M | — |
| 7 | Add Phase 0.2c to `commands/spec.md` — new sub-phase after 0.2b. Skip if no `plot/PLOT.md`. Tag-aware confidence (clean/stale/draft). Render callout block. | W4 | 1 | M | Yes (with 6) |
| 8 | Update `/flow` reference card — add `/plot` as standalone on-demand command | W5 | 4 | S | Yes (with 7) |
| 9 | Update CLAUDE.md — mention Plot Document as fifth knowledge store, `/plot` command | W5 | 4 | S | Yes (with 8) |
| 10 | Manual smoke tests (AC27) — bootstrap, check, update, `/wrap` Phase 2d, `/spec` Phase 0.2c | W5 | 6, 7 | M | — |

## Wave Summary

| Wave | What Ships | Contract Closed | Standalone Value? |
|------|-----------|----------------|-------------------|
| W1 | Annotation helpers + tests + calibration examples | Annotation format, file structure, link extraction | Yes — testable annotation toolkit |
| W2 | `/plot` command | Bootstrap, check, update flows | Yes — interactive Plot Document management |
| W2b | Dogfood on MonsterFlow | Real-world format validation | Yes — Plot Document exists in repo |
| W3 | `/wrap` Phase 2d | Automated staleness detection | Yes — every session gets plot health check |
| W4 | `/spec` Phase 0.2c | Plot-as-prior-knowledge | Yes — specs get narrative context |
| W5 | Flow card, CLAUDE.md, smoke tests | Documentation + hardening | No — depends on W1-W4 |

---

## Consolidated Verdict

7 of 7 design agents passed. Strong convergence on the deterministic helpers approach (unanimous) and diff-scope optimization (4/7). The plan follows the spec's phased structure with one sub-wave addition (W2b for dogfood). All review findings (B1-B5, S1-S7) are addressed:

- B1 (findings.jsonl): resolved by spec — no findings file, annotations are state
- B2 (phase numbering): resolved by spec — note added
- B3 (quick-mode skip): Phase 2d added to skip list
- B4 (AC27 scoping): tests cover deterministic mechanics only
- B5 (routing state machine): 4 explicit boolean conditions
- S1 (Layer 1 anchoring): tiered — graphify in Phase 2d (opportunistic), graphify + code exploration in `/plot`
- S2 (dual annotations): both allowed, independent lifecycle
- S3 (post-bootstrap check): report-only, no update offer
- S4 (dedup procedure): helper implements oldest-drop + renumber
- S5 (Phase 2d latency): diff-scope optimization
- S6 (deterministic helpers): `scripts/_plot_annotations.py`
- S7 (flow card + schema AC): flow card update in W5; no schema changes needed

Plan is ready for `/check`.
