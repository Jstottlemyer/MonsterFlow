---
feature: install-obsidian-vault-baseline
stage: design
created: 2026-05-15
gate_mode: permissive
gate_mode_source: frontmatter
iteration: 1
iteration_max: 3
roster:
  selected: [gaps, requirements, scope]
  dropped: []
  codex_disabled: false
  budget: 3
  selection_method: spec-review-passthrough
verdict: ready-for-check
---

# Design — install-obsidian-vault-baseline

## Architecture Summary

This feature adds a **marker-based scaffold detection mechanism** to `install.sh`'s existing `install_obsidian_env()` function. When install.sh detects an empty vault (after cruft-stripping), it writes a 0-byte `.scaffold-pending` marker file. Claude reads a global CLAUDE.md instruction that triggers a preflight check before wiki commands — if the marker exists, Claude suggests `/wiki-setup` (upstream skill) and removes the marker on success.

The design is maximally minimal: install.sh writes a breadcrumb; Claude acts on it; upstream `/wiki-setup` does the actual scaffolding. Three independent surfaces compose without coupling:
1. **install.sh** — bash-only, idempotent marker write/sweep
2. **~/CLAUDE.md** — global instruction (cross-project visibility)
3. **upstream wiki-setup** — unchanged, owns the 9-directory structure

## Review Findings Addressed

| Finding | Resolution |
|---------|------------|
| R1/Req#1: CLAUDE.md placement voids feature for non-MonsterFlow sessions | **Target `~/CLAUDE.md`** (global), not MonsterFlow's project-local CLAUDE.md. install.sh appends a sentinel-bracketed block using the same idempotency pattern as the `~/.zshrc` obsidian-wiki export. |
| R2: `parse_obsidian_config` name/signature mismatch | Verified: function exists at install.sh:651, returns 0 on success (emits path to stdout), 1 on failure. Helper uses `|| resolved_path=""` pattern. |
| MR-01/SC-01: Upstream scaffold structure not pinned | Add version comment citing upstream contract. Use relaxed predicate: `>=3 of 7 indicators` tolerates upstream evolution. |
| MR-02: Partial wiki-setup failure | Document: upstream uses `mkdir -p` and is idempotent; re-running completes the scaffold. Marker remains until >=3 indicators present. |
| MR-03: Vault path with spaces | Add test case 7: path contains space. |
| Req#2: "5 scaffold markers" vs "7" inconsistency | Spec text error; implementation uses 7 markers throughout. |
| Req#3: parse_obsidian_config failure path | Add test case 8: config exists but parse returns empty. |
| R3: String vs integer comparison | Use `[ "$non_cruft_count" -eq 0 ]` (arithmetic). |

## Design Decisions

### D1 — Helper function `manage_scaffold_marker()` defined before `install_obsidian_env()`

The marker logic lives in a standalone helper called from the END of `install_obsidian_env()` — after both the `if [ -f "$config" ]` no-op branch and the `else` config-write branch, but before the success echo. This placement ensures the helper fires on every invocation (first-install AND re-run).

**Anchor:** Define helper around install.sh:896 (between `install_graphify_skill()` and `install_obsidian_env()`). Insert call at install.sh:971 (between the final `fi` and `echo "  ✓ Obsidian env configured"`).

```bash
# manage_scaffold_marker — write .scaffold-pending on empty vault; sweep stale marker on scaffolded vault.
# Called unconditionally at end of install_obsidian_env() regardless of which config-write branch ran.
# upstream: Ar9av/obsidian-wiki @ wiki-setup skill (7 scaffold indicators)
manage_scaffold_marker() {
    local resolved_path
    resolved_path="$(parse_obsidian_config 2>/dev/null)" || resolved_path=""
    if [ -z "$resolved_path" ] || [ ! -d "$resolved_path" ]; then
        return 0   # No config or path missing — nothing to mark
    fi

    # Stage A: cruft strip — count non-cruft entries
    local non_cruft_count
    non_cruft_count=$(find "$resolved_path" -mindepth 1 -maxdepth 1 \
        ! -name '.DS_Store' ! -name '.Spotlight-V100' ! -name '.fseventsd' \
        ! -name '.obsidian' ! -name '.git' ! -name '.scaffold-pending' \
        2>/dev/null | wc -l | tr -dc '0-9')
    non_cruft_count="${non_cruft_count:-0}"
    
    if [ "$non_cruft_count" -eq 0 ]; then
        # Empty after cruft strip → write marker
        if ! touch "$resolved_path/.scaffold-pending" 2>/dev/null; then
            add_install_warning "vault read-only — could not write $resolved_path/.scaffold-pending. Run /wiki-setup manually when ready."
            return 0
        fi
        echo "  WROTE:    $resolved_path/.scaffold-pending (run /wiki-setup in your next Claude session)"
        return 0
    fi

    # Stage B: vault has content — check scaffold markers (upstream: Ar9av/obsidian-wiki)
    local scaffold_markers=0
    for m in concepts entities _archives _raw index.md log.md .obsidian; do
        [ -e "$resolved_path/$m" ] && scaffold_markers=$((scaffold_markers + 1))
    done
    if [ "$scaffold_markers" -ge 3 ]; then
        # Already scaffolded → sweep stale marker if any
        if [ -e "$resolved_path/.scaffold-pending" ]; then
            rm -f "$resolved_path/.scaffold-pending"
            echo "  REMOVED:  stale $resolved_path/.scaffold-pending (vault already scaffolded)"
        fi
    fi
    # Stage C (vault has user content but isn't scaffolded): silent no-op
}
```

**Rationale:** The helper resolves `vault_path` via `parse_obsidian_config` rather than reading a local variable from one branch — this is what makes it robust to both first-install and re-run code paths.

### D2 — CLAUDE.md instruction targets `~/CLAUDE.md` (global), sentinel-bracketed

Per R1 and Requirements Finding #1, wiki commands are invoked from any project (career/, CosmicExplorer/, etc.), not just MonsterFlow. The instruction must be in a globally-loaded config.

install.sh appends a sentinel-bracketed block to `~/CLAUDE.md` using the same idempotency pattern already used for `~/.zshrc`:

```bash
# Append wiki-preflight instruction to ~/CLAUDE.md (global — cross-project visibility)
append_wiki_preflight_instruction() {
    local claude_md="$HOME/CLAUDE.md"
    local begin="<!-- BEGIN MonsterFlow wiki-preflight -->"
    local end="<!-- END MonsterFlow wiki-preflight -->"
    
    [ -f "$claude_md" ] || touch "$claude_md"
    if grep -qF "$begin" "$claude_md"; then
        :   # Already appended; idempotent
    else
        cat >> "$claude_md" << 'INSTRUCTION'

<!-- BEGIN MonsterFlow wiki-preflight -->
## Obsidian vault scaffolding (post-install)

**Preflight check for wiki-related work:** Before responding to any wiki-* command (`wiki-update`, `wiki-query`, `wiki-ingest`, `wiki-capture`, `wiki-export`, `wiki-lint`) OR before `/wrap`'s Phase 2c wiki integration, check whether `$OBSIDIAN_VAULT_PATH/.scaffold-pending` exists.

If the marker exists, install.sh detected an empty vault but the upstream wiki structure has not been built yet. Suggest the adopter run `/wiki-setup` (from the upstream `Ar9av/obsidian-wiki` skills) before proceeding with the wiki-related ask.

**Marker cleanup:** After `/wiki-setup` completes successfully — confirmed by the vault now containing at least 3 of: `concepts/`, `entities/`, `_archives/`, `_raw/`, `index.md`, `log.md`, `.obsidian/` — delete the `.scaffold-pending` marker file. Do NOT remove the marker if /wiki-setup did not run or did not complete successfully.

If `/wiki-setup` is unavailable, surface the marker as a one-line note.
<!-- END MonsterFlow wiki-preflight -->
INSTRUCTION
        echo "  APPENDED: $claude_md (wiki-preflight instruction)"
    fi
}
```

**Call site:** Inside `install_obsidian_env()`, immediately after the `manage_scaffold_marker` call (line ~972), before the success echo.

### D3 — Arithmetic comparison for `non_cruft_count` (R3 fix)

Use `[ "$non_cruft_count" -eq 0 ]` instead of `[ "$non_cruft_count" = "0" ]`. Also pipe through `tr -dc '0-9'` (strip all non-digit characters) rather than just `tr -d ' '` to handle locale variations in `wc -l` output.

### D4 — 7 scaffold markers with >=3 threshold

The scaffold indicators (from upstream `Ar9av/obsidian-wiki`):
1. `concepts/`
2. `entities/`
3. `_archives/`
4. `_raw/`
5. `index.md`
6. `log.md`
7. `.obsidian/`

Threshold of `>=3` balances false-positive (user has 2 unrelated dirs) vs false-negative (partial wiki-setup). The upstream comment in the helper documents the version contract.

### D5 — Test harness `tests/test-obsidian-vault-baseline.sh`

8 test cases total (spec's 6 + MR-03 spaces + Req#3 parse failure):

| # | Case | Assertion |
|---|------|-----------|
| 1 | Empty vault | `.scaffold-pending` written |
| 2 | Non-empty user content | No marker written |
| 3 | Cruft-only (`.DS_Store` + `.obsidian/`) | Marker written |
| 4 | Already-scaffolded vault | No marker written |
| 5 | Stale-marker sweep on rerun | Marker removed |
| 6 | Read-only vault | `INSTALL_WARNINGS` populated, exit 0 |
| 7 | Vault path with spaces | Marker written correctly |
| 8 | Config exists but parse fails | Silent return, no marker |

Harness pattern: copy from `test-install-knowledge-layer.sh` (setup_test, teardown_test, STUB_DIR, CASE_HOME, $HOME isolation). bash 3.2 compatible (no `${arr[-1]}`, no `declare -A`).

### D6 — No doctor.sh row (deferred per spec Q9)

The marker is transient (scaffold-once action), not ongoing state. Not worth health-check overhead.

## Function Surface

```
install.sh (modifications only):
  manage_scaffold_marker()           # NEW — ~35 LoC, define at :896
  append_wiki_preflight_instruction() # NEW — ~25 LoC, define at :897
  install_obsidian_env()             # MODIFIED — 2 lines added at end

tests/test-obsidian-vault-baseline.sh:
  setup_test()                       # ~45 LoC (copied pattern)
  teardown_test()                    # ~5 LoC
  stage_empty_vault()                # ~5 LoC
  stage_user_content_vault()         # ~5 LoC
  stage_cruft_only_vault()           # ~10 LoC
  stage_scaffolded_vault()           # ~15 LoC
  stage_stale_marker_vault()         # ~20 LoC
  make_stub_required()               # ~30 LoC (inherited pattern)
  run_install()                      # ~15 LoC
  case_1_empty_vault()               # ~25 LoC
  case_2_user_content()              # ~25 LoC
  case_3_cruft_only()                # ~25 LoC
  case_4_already_scaffolded()        # ~25 LoC
  case_5_stale_marker_sweep()        # ~35 LoC
  case_6_readonly_vault()            # ~30 LoC
  case_7_path_with_spaces()          # ~25 LoC
  case_8_parse_failure()             # ~25 LoC
  main()                             # ~30 LoC

~/CLAUDE.md:
  Obsidian vault scaffolding section # ~15 lines (sentinel-bracketed)
```

## Wave Sequencing

### Wave 1 — Helper definitions + CLAUDE.md instruction (parallelizable)

| Task | File | Description | LoC |
|------|------|-------------|-----|
| 1.1 | install.sh | Define `manage_scaffold_marker()` at :896 | ~35 |
| 1.2 | install.sh | Define `append_wiki_preflight_instruction()` at :897 | ~25 |
| 1.3 | install.sh | Add calls inside `install_obsidian_env()` at :971 | ~2 |

**Parallelism:** Tasks 1.1 and 1.2 add distinct functions to adjacent lines; no merge conflict. Task 1.3 depends on 1.1+1.2 being defined.

### Wave 2 — Test harness scaffold (can parallel with Wave 1)

| Task | File | Description | LoC |
|------|------|-------------|-----|
| 2.1 | tests/test-obsidian-vault-baseline.sh | Harness scaffold (setup/teardown/stubs/run_install) | ~100 |
| 2.2 | tests/test-obsidian-vault-baseline.sh | Stage helpers (empty, user-content, cruft, scaffolded, stale-marker) | ~55 |

### Wave 3 — Test cases (sequential within wave, depends on Wave 2)

| Task | File | Description | LoC |
|------|------|-------------|-----|
| 3.1 | tests/test-obsidian-vault-baseline.sh | Cases 1-4 (core happy paths) | ~100 |
| 3.2 | tests/test-obsidian-vault-baseline.sh | Cases 5-6 (rerun sweep, read-only) | ~65 |
| 3.3 | tests/test-obsidian-vault-baseline.sh | Cases 7-8 (spaces, parse failure) | ~50 |
| 3.4 | tests/test-obsidian-vault-baseline.sh | main() + TESTS array | ~30 |

### Wave 4 — Wiring + housekeeping (depends on Waves 1-3)

| Task | File | Description | LoC |
|------|------|-------------|-----|
| 4.1 | tests/run-tests.sh | Register test-obsidian-vault-baseline.sh | 1 |
| 4.2 | BACKLOG.md | Remove item #1 (install-obsidian-vault-baseline) | ~2 |
| 4.3 | CHANGELOG.md | Add `[0.15.0]` entry (read VERSION at build time) | ~5 |

## Acceptance Criteria Mapping

| AC | Wave.Task | Verification |
|----|-----------|--------------|
| AC1 (empty vault → marker) | 1.1, 1.3, 3.1 | case_1 asserts `.scaffold-pending` exists |
| AC2 (user content → no marker) | 1.1, 3.1 | case_2 asserts no marker |
| AC3 (cruft-only → marker) | 1.1, 3.1 | case_3 asserts marker |
| AC4 (scaffolded → no marker) | 1.1, 3.1 | case_4 asserts no marker |
| AC5 (stale sweep) | 1.1, 3.2 | case_5 pre-stages config+scaffold+marker, asserts marker removed |
| AC6 (read-only) | 1.1, 3.2 | case_6 asserts INSTALL_WARNINGS, exit 0 |
| AC7 (CLAUDE.md instruction) | 1.2, 1.3 | Manual verification + grep for sentinel |
| Test gap: spaces | 3.3 | case_7 |
| Test gap: parse failure | 3.3 | case_8 |

## Edge Cases (from spec, annotated)

1. **Vault path is a symlink** — `parse_obsidian_config` returns the path as-written in config; bash `-d` test follows symlinks. No canonicalization needed.

2. **Vault contains only `.git/`** — `.git/` is in the cruft allowlist, so counts as empty → marker written. `/wiki-setup` uses `mkdir -p`, preserving the git repo.

3. **Vault is read-only** — `touch` fails; `add_install_warning` called; function continues. Test case 6 covers this. Guard for root in test: `[ "$(id -u)" -eq 0 ] && skip`.

4. **Concurrent install.sh runs** — `touch` is idempotent; sentinel-block append uses `grep -qF` guard. No `flock` needed.

5. **Adopter runs /wiki-setup without marker** — Fine; CLAUDE.md instruction only prompts when marker exists.

6. **Marker survives /wiki-setup (Claude forgot to rm)** — Belt-and-suspenders sweep in Stage B catches this on next install.sh run.

7. **Vault has 1-2 of 7 scaffold markers** — Stage B's `>=3` threshold means NOT scaffolded. Probably partial/aborted /wiki-setup OR coincidental user dirs. Stage C (silent no-op) applies.

8. **Partial wiki-setup failure** — Upstream uses `mkdir -p` and is idempotent. Re-running completes the scaffold. Marker remains until >=3 indicators present, which is correct recovery behavior.

## Risk Mitigations

| Risk | Mitigation |
|------|------------|
| R1: CLAUDE.md scope | Target ~/CLAUDE.md (global), sentinel-bracketed (D2) |
| R2: parse_obsidian_config mismatch | Verified exists at install.sh:651; test case 8 covers failure path |
| R3: wc -l locale string | Use `-eq` arithmetic + `tr -dc '0-9'` (D3) |
| R4: Multiple return paths in install_obsidian_env | Reviewed: only one `return 0` at :972 after the fi; early returns at :918 and :930 handle missing-path edge cases that correctly skip marker logic |
| R5: Test as root | Guard with `[ "$(id -u)" -eq 0 ] && skip` in case_6 |
| R6: Stale marker persists | Belt-and-suspenders sweep; document manual `rm` escape hatch |
| SC-01: Hardcoded upstream names | Comment cites `Ar9av/obsidian-wiki`; >=3 threshold tolerates evolution |

## Open Questions

None. All spec questions resolved in V3; all review findings addressed above.

## Codex Adversary Integration

This design will receive a Codex adversarial critique per the autorun architecture. Findings will be appended below if the resolver emits `codex-adversary` for the design gate.

---

## Implementation Notes for /build

1. **Read VERSION at build time** — CHANGELOG entry must use actual version from `VERSION` file (currently 0.14.1; this ships as 0.15.0).

2. **Test harness bash 3.2 constraints** — No `${array[-1]}`, no `declare -A`, no `export -f`. Use PATH-stub model per existing test-install-knowledge-layer.sh.

3. **install.sh line numbers are approximate** — Verify current line numbers before inserting; the function boundaries may have shifted.

4. **Pre-commit autorun-shell-reviewer** — This spec does NOT modify `scripts/autorun/*.sh`, so no subagent invocation required.

5. **Sentinel block format** — Use HTML comments (`<!-- BEGIN ... -->`) for CLAUDE.md (markdown), not shell comments.


---

## Adversarial Design Critique (Codex)

**High [scope-cuts]:** Plan adds `append_wiki_preflight_instruction()` that writes to `~/CLAUDE.md`, but the spec’s in-scope files list does not include global home-file mutation. This is a material scope expansion with user-global side effects, not just “move CLAUDE.md placement.”

**High [contract]:** Appending to `~/CLAUDE.md` assumes Claude/Codex loads that file globally. The plan treats that as fact without proving the loader contract for target environments. If global CLAUDE.md is not loaded, R1 remains unfixed.

**High [architectural]:** The design creates two independent marker-management actors: `install.sh` and future Claude sessions. There is no single source of truth for the scaffold predicate or cleanup semantics; the 7-marker `>=3` rule is duplicated in bash and prose, guaranteeing drift.

**High [security]:** Writing installer-managed content into `~/CLAUDE.md` lets a repo install script mutate global AI behavior for every project. The plan lacks consent, backup, diff visibility, opt-out, or uninstall path for that global instruction.

**High [tests]:** No test verifies the `~/CLAUDE.md` mutation is idempotent, preserves existing content, handles missing/unwritable home CLAUDE.md, or avoids duplicate/conflicting sentinel blocks.

**Medium [architectural]:** “Relaxed predicate tolerates upstream evolution” is false. `>=3 of 7 hardcoded names` only tolerates additive upstream changes, not renames/removals. The upstream contract remains unpinned.

**Medium [contract]:** Plan claims upstream `/wiki-setup` uses `mkdir -p` and is idempotent, but provides no verification source. That assumption is load-bearing for partial failure and duplicate-run safety.

**Medium [tests]:** Test case 8 “config exists but parse fails” is underspecified. If the test corrupts config, it may exercise `parse_obsidian_config`, but not the actual install path that writes a fresh valid config before helper execution.

**Medium [tests]:** Read-only vault test may not work on macOS if the parent directory permissions still allow unexpected behavior or ACLs differ. The plan only guards root, not filesystem/ACL variance.

**Medium [scope-cuts]:** BACKLOG removal and CHANGELOG update are in Wave 4, but the design does not require updating the original spec text that still says MonsterFlow `CLAUDE.md`. Build agents may follow stale spec over plan.

**Low [documentation]:** The sentinel string `MonsterFlow wiki-preflight` in a global file does not document ownership, removal instructions, or version. Future users will not know whether it is safe to delete.

**Low [tests]:** No negative test ensures Stage C with an existing `.scaffold-pending` plus user content below threshold does not remove or rewrite the marker.