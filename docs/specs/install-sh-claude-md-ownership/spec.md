---
tags: []
tags_provenance:
  baseline: []
  llm_added: []
  user_overrides: []
gate_mode: permissive
---

# install-sh-claude-md-ownership Spec

**Created:** 2026-05-14
**Constitution:** none — session roster only
**Status:** Drafted as a prereq for `uninstall-sh` (see `docs/specs/uninstall-sh/design.md` D12 Wave 0; uninstall-sh /spec-review B4). Skipped /spec Q&A — requirements settled at uninstall-sh /spec-review rev2.

## Summary

Move `~/CLAUDE.md` block ownership into `scripts/claude-md-merge.py` with **explicit modes** (`created_file` / `appended_block` / `skipped_manual`), wrap the managed content with `# BEGIN MonsterFlow CLAUDE.md baseline` / `# END MonsterFlow CLAUDE.md baseline` sentinels, and emit the corresponding manifest rows so `uninstall.sh` can reverse cleanly. Bundle a small ride-along: add `bash uninstall.sh` mention to `install.sh`'s opening banner AND end-block Next Steps. Closes uninstall-sh /spec-review B4 (Codex C3 — "CLAUDE.md sentinel retrofit is bigger than 4-6 lines"; real logic lives in claude-md-merge.py's section-based interactive merge).

## Backlog Routing

| # | Item | Source | Routing |
|---|------|--------|---------|
| 1 | this spec | uninstall-sh prereq #5 | (a) in scope |
| 2 | `install-sh-manifest-emit` (sibling prereq) | uninstall-sh prereq #4 | (c) sibling spec — must ship in same release |
| 3 | `uninstall-sh` (consumer) | uninstall-sh design | (c) downstream — blocks on this + sibling |

## Scope

### In scope

1. **`scripts/claude-md-merge.py` — explicit-mode refactor.** Today's section-based interactive merge logic is restructured around three explicit modes:
   - **`created_file`**: pre-install `~/CLAUDE.md` was absent. install copies the whole template to `~/CLAUDE.md`. The entire file is MonsterFlow-authored.
   - **`appended_block`**: pre-install `~/CLAUDE.md` existed. install appends a managed block to the existing file. User's original content surrounds the block.
   - **`skipped_manual`**: user declined the merge (existing interactive prompt path). Nothing written; nothing to reverse.
2. **Sentinel markers** wrap the managed block (in BOTH `created_file` and `appended_block` modes): `# BEGIN MonsterFlow CLAUDE.md baseline` / `# END MonsterFlow CLAUDE.md baseline`. Sentinels appear in the template (so `created_file` mode also has them).
3. **Manifest emission** (depends on sibling prereq `install-sh-manifest-emit`): `claude-md-merge.py` calls `_manifest_emit.py` with the appropriate `op`:
   - `created_file` mode → emit `op:created_file` row with `path: ~/CLAUDE.md`, `created_sha256`, `template_src`.
   - `appended_block` mode → emit `op:appended_block` row with `file: ~/CLAUDE.md`, `begin`, `end`, `block_sha256`.
   - `skipped_manual` mode → emit nothing.
4. **`install.sh` opening banner** — add a one-line mention near the top of the printed banner (around the existing usage area): `"To reverse: bash uninstall.sh (dry-run by default)"`.
5. **`install.sh` end-block Next Steps** — already added in the v0.12.0+ session (commit pending). Verify it lands; otherwise add: `"  7. To remove MonsterFlow entirely: bash uninstall.sh (dry-run by default)"`.

### Out of scope

1. **`link_file` extension to back up pre-existing symlinks** (originally a "rider" for this prereq) — separated. If accepted, becomes its own spec OR rolls into prereq #4. Today's `link_file` only backs up regular files (per uninstall-sh OOS #11).
2. **`scripts/install-hooks.sh --uninstall`** — already exists at lines 16, 17, 31 (per uninstall-sh /check MF1). No work needed; uninstall-sh audit task T9 handles any gaps post-build.
3. **`uninstall.sh` itself** — separate spec.
4. **Changes to which sections of `templates/CLAUDE.md`** get merged — preserve existing behavior verbatim.

## Approach

**Mode-explicit refactor** in `claude-md-merge.py`. The script today returns a single result; refactor it to return `(mode, sha256, metadata)` where `mode ∈ {"created_file", "appended_block", "skipped_manual"}`. `install.sh` calls the manifest-emit helper based on the returned mode.

Template-side: edit `templates/CLAUDE.md` to wrap MonsterFlow content with the sentinel pair. The sentinel pair is INSIDE the template (so `created_file` mode produces a file with sentinels) AND is what `appended_block` mode wraps around the appended content.

Test surface mirrors `tests/test-install-knowledge-layer.sh`: stub `$HOME` with various pre-install states (no `~/CLAUDE.md`, existing user-only `~/CLAUDE.md`, existing user-edited-MonsterFlow `~/CLAUDE.md`), run install, assert filesystem state + manifest content.

## Roster Changes

No roster changes.

## UX / User Flow

User experience is unchanged — same interactive prompt when `~/CLAUDE.md` exists, same silent copy when absent. The internal data model changes; visible behavior does not.

```bash
$ bash install.sh
... (existing install output) ...
# When ~/CLAUDE.md doesn't exist:
  COPIED: ~/CLAUDE.md from templates/CLAUDE.md (mode: created_file)
# When ~/CLAUDE.md exists, user accepts merge:
  MERGED: ~/CLAUDE.md (mode: appended_block; added MonsterFlow baseline block)
# When user declines:
  SKIPPED: ~/CLAUDE.md (mode: skipped_manual; existing content untouched)
```

`install.sh` opening banner gains one line:
```
=== MonsterFlow installer ===
To reverse: bash uninstall.sh (dry-run by default)
...
```

## Data & State

### `claude-md-merge.py` return contract (new)

```python
def merge_claude_md(home: str, template_path: str, interactive: bool) -> dict:
    """
    Returns: {
      "mode": "created_file" | "appended_block" | "skipped_manual",
      "path": "~/CLAUDE.md",  # absolute, post-tilde-expansion
      "sha256": "<64-hex>",   # of the final block content (created_file: whole file; appended_block: just the block)
      "template_src": "<path>",  # only for created_file mode
      "begin_marker": "# BEGIN MonsterFlow CLAUDE.md baseline",
      "end_marker":   "# END MonsterFlow CLAUDE.md baseline",
    }
    """
```

### Sentinel sentinels

Exact strings (locked):
- BEGIN: `# BEGIN MonsterFlow CLAUDE.md baseline`
- END:   `# END MonsterFlow CLAUDE.md baseline`

Both appear:
- In `templates/CLAUDE.md` (around the managed content)
- In install-time written `~/CLAUDE.md` (both modes)
- In uninstall-sh's strip-block lookup (per its D8)

### `templates/CLAUDE.md` structural change

Today: a single template body.
After: same body, with the sentinel pair wrapping all MonsterFlow-managed content (everything from the start of the file to before user-customization placeholder section, inclusive of the standard pipeline preamble).

## Integration

### Touches

- `scripts/claude-md-merge.py` — refactor to return mode + sha256 + metadata. Wave 1 task.
- `templates/CLAUDE.md` — wrap content with sentinel pair. Wave 1 task (parallel with claude-md-merge.py refactor as long as the sentinel strings are locked).
- `install.sh` — call updated claude-md-merge.py; pipe mode + metadata to `_manifest_emit.py`. Wave 2 task (depends on prereq #4 being shipped, OR on `MONSTERFLOW_MANIFEST=1` defaulting OFF so this can ship pre-manifest-emit-default-flip).
- `install.sh` opening banner — one-line addition. Wave 2 task.
- `tests/test-claude-md-ownership.sh` (new) + `tests/run-tests.sh` wiring same commit. Wave 2 task.
- `CHANGELOG.md` [Unreleased]. Wave 2 task.

### Sibling-prereq coupling

`scripts/claude-md-merge.py`'s manifest emission requires `scripts/_manifest_emit.py` (from prereq #4). Ship ordering: either (a) prereq #4 ships first, then this; or (b) this ships with `MONSTERFLOW_MANIFEST=1`-gated emission so the refactor lands independently of #4's adopter rollout. **Lean: (b)** — refactor + sentinels can land standalone; manifest emission is gated.

### Does NOT touch

- `uninstall.sh` (separate spec).
- `install.sh`'s other do_* functions.
- Any other template under `templates/`.

## Edge Cases

1. **User has hand-edited content INSIDE existing sentinel-bracketed block** (from a prior install with sentinels): treat as `appended_block` mode on re-install; the existing block is replaced. User's in-block edits are lost. Mitigation: install-time backup of pre-existing `~/CLAUDE.md` (link_file pattern) preserved. uninstall-sh's `<file>.uninstall.sentinel-block-bak.<ts>` policy (per its /check SF4) is the symmetric protection on the reversal side.
2. **User has hand-edited content OUTSIDE the sentinel-bracketed block**: preserved — only the bracketed range is replaced.
3. **Existing `~/CLAUDE.md` is missing the END sentinel** (corruption / partial edit): `appended_block` mode refuses with a clear error; user manually resolves.
4. **`templates/CLAUDE.md` is itself missing sentinels** (developer error): pre-commit test `tests/test-claude-md-ownership.sh` AC1 catches it; CI fails before merge.
5. **`~/CLAUDE.md` is a symlink** (some users do this with dotfile managers): follow the symlink for both read and write; atomic write via same-dir tmp.

## Acceptance Criteria

10 cases in `tests/test-claude-md-ownership.sh`:

1. **AC1** — `templates/CLAUDE.md` contains both BEGIN and END sentinels, in that order.
2. **AC2** — `created_file` mode: pre-install `~/CLAUDE.md` absent → merge returns `mode: created_file`, file content matches template byte-for-byte, sentinels present.
3. **AC3** — `appended_block` mode: pre-install user content `[USER LINE]` exists → merge returns `mode: appended_block`, file contains `[USER LINE]` AND the BEGIN/END-bracketed managed block; user content preserved.
4. **AC4** — `skipped_manual` mode: user declines interactive prompt → no file written, return `mode: skipped_manual`.
5. **AC5** — `sha256` returned matches manual `sha256sum` of the appropriate content (whole file for `created_file`; just the bracketed block for `appended_block`).
6. **AC6** — Sentinel sentinels match exact strings (regex test).
7. **AC7** — Re-install over existing `created_file` install: sentinels still intact; managed content idempotent; user content (if any added after install) outside block preserved.
8. **AC8** — `install.sh` opening banner contains the literal string `bash uninstall.sh` (grep test).
9. **AC9** — `install.sh` end-block Next Steps section contains the literal string `bash uninstall.sh` (grep test).
10. **AC10** — When `MONSTERFLOW_MANIFEST=1` is set AND prereq #4's `scripts/_manifest_emit.py` is present: manifest emission fires correctly for each mode (created_file → `op:created_file` row; appended_block → `op:appended_block` row; skipped_manual → no row).

## Open Questions

1. **Sentinel exact wording** — locked as `# BEGIN MonsterFlow CLAUDE.md baseline` / `# END MonsterFlow CLAUDE.md baseline` here. Cross-referenced from uninstall-sh design D8. Any change requires both specs to update in lockstep.
2. **`appended_block` content placement in user's existing file** — append at end (current behavior) vs prepend at top vs insert before user's first section heading? Lean: append at end (preserve current install.sh semantics). Confirm in /blueprint.
3. **`templates/CLAUDE.md` structural reshaping** — does adding sentinels imply restructuring the template content itself? Lean: NO — just wrap existing content. Minimize blast radius.

## Notes

- `gate_max_recycles` omitted (deprecated).
- `tags: []` — no clean 10-enum fit.
- The autorun-shell-reviewer subagent MUST run before any commit that modifies `install.sh` (per `feedback_build_subagent_invocations_must_fire` memory).
- Sentinel sentinels are **part of the cross-spec contract** with uninstall-sh — any wording change requires updating uninstall-sh's design D8 in the same commit.
