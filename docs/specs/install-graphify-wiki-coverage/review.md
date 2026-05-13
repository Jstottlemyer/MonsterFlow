---
feature: install-graphify-wiki-coverage
stage: spec-review
created: 2026-05-13
gate_mode: permissive
gate_mode_source: frontmatter
iteration: 1
iteration_max: 3
roster:
  selected: [gaps, requirements, scope, codex-adversary]
  dropped: [ambiguity, docs-clarity, feasibility, stakeholders]
  budget: 3
  selection_method: rankings
verdict: APPROVED (spec revised to rev1)
overall_health: Concerns (rev0) → Good (rev1)
resolution: All 5 critical findings + 4 important + Obsidian.app addition incorporated into spec rev1 (2026-05-13). See spec.md ## Revisions section.
---

# Review — install-graphify-wiki-coverage

## Overall health: Concerns

Three Claude reviewers (gaps, requirements, scope) returned PASS WITH NOTES. The Codex adversarial pass surfaced two critical contradictions between the spec and existing in-repo authority (`docs/graphify-usage.md`) that materially change the install action. Without those resolved, `/blueprint` would design from incorrect premises.

The bones are good — detection-and-report layout is clean, idempotency is a primary AC, out-of-scope exclusions hold. The blockers are concrete and inline-fixable; no architectural reshape needed.

## Before You Build (5 items)

1. **Graphify install command is wrong against the project's own authority** (Codex #1)
   The spec proposes `pip install graphifyy && [graphify install-skill]`. `docs/graphify-usage.md:39,141` is explicit: `pip install "graphifyy[mcp]"` (note the `[mcp]` extras) AND the skill installer is `graphify claude install` (NOT `graphify install-skill` — that subcommand doesn't exist). Open Question #1 deferred this to /blueprint; that deferral was premature. Update the spec's CLI install action and skill install action to match the documented contract, then close Open Question #1.

2. **Graphify CLI detection is internally contradictory** (Codex #2 + gaps follow-up)
   Scope section requires BOTH `command -v graphify` AND `~/.local/venvs/graphify/bin/graphify --help`. Edge Case 1 says "graphify CLI present but venv dir absent (binary from some other source) → mark CLI as ✓". These contradict. Pick one: "any working `graphify` on PATH counts" (matches EC1, more lenient) or "MonsterFlow-managed venv required" (stricter, simpler invariant). Recommend the former — matches user reality, supports pipx/brew-tap users.

3. **`posix_quote` reuse is unsafe** (Codex #3)
   The spec proposes reusing `posix_quote` from the theme stage (install.sh:711). But `posix_quote` is defined INSIDE `do_theme_install`'s function body — it only exists in scope when the theme stage runs. The spec also says Knowledge Layer runs regardless of `--no-theme`. Under `--no-theme`, `install_obsidian_env()` would call an undefined function. Fix: hoist `posix_quote` to top-level (or duplicate the trivial logic in `install_obsidian_env`).

4. **"Install missing pieces?" prompt overpromises** (Codex #4)
   Most missing pieces are print-only (graphify skill, wiki skills, cmux drift). A user answers Y, sees "setup complete," and on re-run sees the same warnings — confusing UX. Split summary into "Can install now" vs "Manual action required"; prompt only when the former is non-empty.

5. **cmux drift fold-in placement needs justification** (scope)
   cmux drift is structurally different from the other four checks — it's a post-install coherence problem between `do_theme_install` and the brew-bundle stage. Spec puts the detection in `do_knowledge_layer`. Either justify in one sentence why detection lives at the knowledge-layer site (knowledge-layer is just where the catch-all summary block already lives — argument: yes, that's actually fine), or move the check into `do_theme_install` and drop EC12-15 + AC7 from this spec. Recommend justifying-in-place: knowledge layer is the right "post-install drift surface" home. Add one sentence to the spec under "Approach" or as a footnote on the cmux entry.

## Important But Non-Blocking (7 items)

1. **AC1 missing cmux row assertion** (requirements) — AC1 asserts four `✗` lines for graphify/skill/wiki/env; says nothing about the expected `cmux drift: ○ N/A` row when theme stage didn't run. Add `Assert stdout contains 'cmux drift:' followed by '○ N/A'` to AC1.

2. **AC4 adopter default-N is not binary** (requirements) — "no installs run" is vague. Specify: `find $HOME -newer <pre-run-marker>` for `~/.local/venvs/graphify`, `~/.local/bin/graphify`, `~/.obsidian-wiki/config` returns empty.

3. **Idempotency AC3 marker undefined** (gaps + requirements) — `<marker>` is a placeholder; "tracked paths" undefined. Pin: marker = `touch /tmp/idempotency_marker.$$`; tracked paths = `~/.zshrc`, `~/.obsidian-wiki/`, `~/.local/venvs/graphify/`, `~/.local/bin/graphify`, `~/.config/cmux/`.

4. **Owner auto-yes + missing vault path under `--non-interactive`** (Codex #5 + gaps) — `install_obsidian_env()` prompts for a vault path. Under non-interactive owner / CI, behavior is unspecified. Define: skip with stderr notice ("vault path not configured, set OBSIDIAN_VAULT_PATH manually") and proceed.

5. **cmux drift vs `--no-theme` with prior state** (Codex #6) — EC12 says `--no-theme` → no warning. But if the symlink exists from a prior install run, `--no-theme` doesn't remove it, so the warning fires. Decide: does `--no-theme` suppress only new theme writes, or also drift diagnostics for theme-managed config? Recommend: detect-only, warn regardless (it's still drift the user should know about).

6. **OBSIDIAN config parsing rules unspecified** (Codex #7) — `grep succeeds for OBSIDIAN_VAULT_PATH=` doesn't define handling for quoted paths, `export` prefix, spaces, comments, literal `~`. `/wrap` already hit the tilde-expansion pitfall (per Justin's memory `feedback_tilde_expansion_in_bash_config_reads`). Add a small parser spec or pin to `${VAR/#\~/$HOME}` expansion + double-quoted-string rules.

7. **"6 wiki skills" hardcoding is fragile** (gaps + Codex #8) — local `~/Projects/obsidian-wiki/.skills/` has 11 skills (wiki-status, wiki-setup, wiki-rebuild, cross-linker, openclaw-history-ingest, etc.) beyond the 6 the spec lists. Either pin "the 6 skills MonsterFlow uses" with a one-line rationale, or detect against a manifest. Recommend the former — it's explicit and stable.

## Observations (5 items)

- **Test harness seam needed for graphify install** (Codex #9) — AC4 owner-auto-yes path would need `python3 -m venv` + venv `pip3` + a generated binary. Current `tests/test-install.sh` stubs python3 at version level only. Add `MONSTERFLOW_KNOWLEDGE_LAYER_TEST_SEAM` (or reuse `MONSTERFLOW_INSTALL_TEST=1`) to short-circuit the venv install path in tests, mocking the binary directly.

- **Edge case 5 has no AC** (requirements) — non-sentinel `OBSIDIAN_VAULT_PATH=` in `~/.zshrc` is non-trivial logic without coverage. Add AC8.

- **Vault validation too weak** (Codex #12) — directory-existence-only lets users point at `~/Downloads`. Add a soft warning if `.obsidian/` subdir missing.

- **`tests/run-tests.sh:22-126` line-range pointer will rot** (requirements + scope) — replace with "append to TESTS array after all existing entries".

- **Wiki skill set could be runtime-required, not upstream-complete** (Codex #8) — `/wrap` needs `wiki-ingest` + config, `/spec` needs `wiki-query`, graphify digest needs vault writeability. Detection could match what MonsterFlow features actually consume.

## Reviewer Verdicts

| Dimension | Verdict | Key Finding |
|---|---|---|
| Gaps | PASS WITH NOTES | graphify-skill install action unspecified; cmux non-symlink detection; AC3 marker undefined |
| Requirements | PASS WITH NOTES | AC1 missing cmux row; AC4 not binary; EC5 has no AC |
| Scope | PASS WITH NOTES | cmux fold-in placement needs justification; "five pieces" inconsistent count |
| Codex Adversary | (additive) | Graphify contract conflicts with `docs/graphify-usage.md`; CLI detection contradictory; `posix_quote` scope leak; prompt overpromises; vault-path UX in non-interactive owner; cmux drift vs `--no-theme`; config parsing rules |

## Codex Adversarial View

Codex's 12 findings include four that line up with Claude reviewers (graphify-skill, prompt UX, vault validation, idempotency scope) and four that no Claude reviewer caught:

- **`pip install "graphifyy[mcp]"` (with extras) + `graphify claude install`** — verified against `docs/graphify-usage.md:39,141`. This is the most pivotal finding; without it, the build action calls a non-existent subcommand.
- **`posix_quote` is nested inside `do_theme_install`** — verified against `install.sh:694-697`. Would silently fail under `--no-theme`.
- **cmux drift vs `--no-theme` + prior symlink state** — real coherence gap.
- **Config-file parsing semantics** — tilde, quotes, `export` prefix, spaces, comments all undefined.

Codex also proposes a Better Shape: reframe `do_knowledge_layer` as a **doctor + fixer** with three output buckets — `Ready` / `Can fix now` / `Manual action required` / `Skipped non-interactive`. This maps cleanly to Codex #4 (split the overpromising prompt) and would clarify the cmux/wiki/skill print-only category without restructuring the detection logic. Worth considering in `/blueprint`.

## Conflicts Resolved

No disagreements between Claude reviewers (they each took different angles without overlap). Codex extended on four findings the Claude personas raised; no contradictions.

The cmux fold-in question (scope finding sc-01) was the closest call:
- **Resolution:** Keep cmux in this spec. The detection-surface argument (knowledge layer is the post-install drift summary) is strong enough; doesn't justify carving out a separate spec. But require the one-sentence justification in the spec text under "Approach" so the placement decision is recorded, not implicit.

---

Approve to proceed to /blueprint? (approve / refine `<what to change>`)

---

## Resolution (2026-05-13)

**Approved with refine.** Spec revised to rev1 with all 5 critical findings + 4 important + 1 new addition (Obsidian.app, surfaced by a parallel session) incorporated:

- Graphify install commands fixed per `docs/graphify-usage.md:39,141` (`pip3 install "graphifyy[mcp]" && graphify claude install`).
- Graphify CLI detection simplified to `command -v graphify` (matches EC1, supports brew/pipx users).
- `posix_quote` hoisted to top-level (works under `--no-theme`).
- Prompt split into Can-install-now vs Manual-action-required (Codex's doctor + fixer reshape).
- cmux placement justified in Summary.
- Obsidian.app added as 6th detection. Detection is filesystem-based (`[ -d /Applications/Obsidian.app ]`) — catches manual installs that brew doesn't track. Install action is `brew install --cask obsidian` with success-oracle override for the brew-collision-with-manual-install case (EC17).
- AC1 cmux row pinned, AC3 marker + path list defined, AC4 binary mutation assertions, AC8 Obsidian.app coverage, AC9 config parser edge cases.
- EC16–20 added: manual Obsidian install, brew collision, `brew` unavailable fallback, non-interactive vault path, config parsing rules.

Confidence 0.85 → 0.90. Ready for `/blueprint`.
