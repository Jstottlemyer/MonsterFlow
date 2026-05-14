# uninstall-sh — Design Plan

**Spec:** `docs/specs/uninstall-sh/spec.md` (rev3 — manifest-first hybrid; 22 ACs; A1/A2 inline-fixed; 10 followups)
**Review:** `docs/specs/uninstall-sh/review.md` (rev2 — GO_WITH_FIXES)
**Designers:** api (opus) · data-model (sonnet) · integration (sonnet) · Codex disabled at /blueprint per skill default
**Gate mode:** permissive

---

## Design Decisions

### D1 — CLI surface (api recommendation, adopted verbatim)

| Flag | Effect | Exit |
|------|--------|------|
| (none) | Dry-run: print plan; no side effects | 0 / 2 |
| `--apply` | Commit plan: removals, strips, restores, tombstone | 0 / 1 / 3 |
| `--dry-run` | Explicit no-op alias for default | 0 |
| `--help` / `-h` | Print usage banner (works even when manifest broken) | 0 |

Unknown flag → exit 2. `--help` + `--apply` → help wins, exit 0.

### D2 — Exit-code semantics

| Code | Meaning | Triggers |
|------|---------|----------|
| `0` | Success | Dry-run; clean apply; idempotent re-run (no active manifest) |
| `1` | Partial-dirty (re-runnable) | Some ops succeeded, some failed; manifest NOT tombstoned. **MF6 pin: cold-start partial-apply also returns 1 (re-runnable; monotonic; same semantics as manifest-mode exit 1).** |
| `2` | Invalid invocation | Unknown flag; `$REPO_DIR` resolution failure |
| `3` | Catastrophic | Corrupt manifest schema_version; multi-op permission failures |

`--apply` is **monotonic in observable state** — completed ops stay completed across re-runs. Exit 2 is invocation-only (never missing manifest, never missing backup).

### D3 — Output-string constants (closes O4)

All adopter-visible prefixes + canonical messages defined as readonly bash constants at the top of `uninstall.sh`:

```bash
readonly PFX_REMOVED="REMOVED:"
readonly PFX_STRIPPED="STRIPPED:"
readonly PFX_RESTORED="RESTORED:"
readonly PFX_SAVED="SAVED:"
readonly PFX_SKIPPED="SKIPPED:"
readonly PFX_WARN="WARN:"
readonly MSG_NOTHING_TO_REMOVE="Nothing to remove."
readonly HINT_OBSIDIAN_REMOVE="brew uninstall --cask obsidian"
readonly HINT_GRAPHIFY_REMOVE="rm -rf ~/.local/venvs/graphify ~/.local/bin/graphify"
readonly HINT_CMUX_REMOVE="brew uninstall cmux"
```

AC greps (AC2/3/8/15) reference `$PFX_*` exactly — wording drift becomes a single-source-of-truth edit.

### D4 — Helper-script boundary: `scripts/_uninstall_helpers.py`

Resolved api ↔ integration divergence (api proposed 6 subcommands; integration proposed 4) by **adopting api's 6** — distinct testable concerns + matches `_resolve_personas.py` precedent of one helper covering several internal verbs.

Single-file Python, stdlib-only (`json`, `hashlib`, `os`, `argparse`, `pathlib`, `re`). Positional-subcommand CLI invoked from bash via `$(...)` — heredoc-stdin reserved per `feedback_hook_stdin_heredoc` memory.

| Subcommand | Args | Stdout | Exit |
|------------|------|--------|------|
| `parse-manifest <path> [--repo-dir <dir>]` | manifest + optional repo filter | normalized JSONL reverse-chrono | 0/2/3 |
| `verify-sha256 <file> <hex>` | path + expected | — | 0/1/2 |
| `strip-sentinel-block <file> <begin> <end>` | file + markers | lines-stripped count | 0/1/2 |
| `detect-fallback-symlinks <home> <repo>` | $HOME + $REPO_DIR | synth manifest rows | 0 |
| `detect-fallback-backup <dst>` | one symlink | action JSONL | 0 |
| `tombstone-manifest <path>` | active manifest | new path | 0/1 |

Cross-platform note: use `hashlib.sha256` directly (not `sha256sum`/`shasum -a 256` subprocess) — closes integration's macOS/Linux divergence concern.

### D5 — `unlink_file` shell adapter (integration recommendation)

Symmetric to `link_file` (install.sh:451). ~10-line bash function in `uninstall.sh`:

```
unlink_file <dst>
  → parse-manifest lookup for dst
  → if manifest row: verify-sha256 against backup_sha256
  → if SHA match: rm dst; mv backup_path dst
  → if SHA mismatch: rm dst; leave backup; warn
  → if no manifest row (cold-start): detect-fallback-backup → execute returned action
```

Shell does `rm`/`mv`; Python does parsing + checksumming + ordering. Matches `claude-md-merge.py` precedent.

### D6 — Manifest schema (normative; closes I1 + I2)

**Header row** (line 1 only, no `op` field):

```json
{"schema_version": 1, "written_by": "install.sh", "written_at": "<iso8601-utc>"}
```

Reader uses **absent `op` field** as the header-row discriminant.

**Common fields on every data row:** `op` (enum), `repo_dir` (absolute path, no trailing slash — closes I2), `created_at` (ISO 8601 UTC — drives Edge Case 13 reverse-chrono ordering), `install_session_id` (UUID v4 — optional in v1; mandatory in schema_version: 2 — addresses data-model OQ1).

**Per-op required + optional fields** (closes I1):

| op | Required (in addition to common) | Optional | Reversal |
|----|----------------------------------|----------|----------|
| `symlink` | `dst`, `src` | `backup_path`, `backup_sha256`, `previous_kind` (`file`/`symlink`) | `rm dst`; restore if SHA match |
| `append_block` | `file`, `begin`, `end`, `block_sha256` | — | full-file backup → strip; for blocks added to user's existing file (e.g. `~/.zshrc`) |
| `appended_block` | `file`, `begin`, `end`, `block_sha256` | — | identical reversal to `append_block`; distinct provenance: emitted alongside `created_file` for the managed block inside install-created files |
| `created_file` | `path`, `created_sha256` | `template_src` | SHA match → delete; SHA mismatch → preserve + sentinel-strip (per A2) |
| `graphify_install` | `binary`, `venv` | `skill_hook` | `readlink binary` must point into `venv/bin/graphify` → `graphify claude uninstall` (fallback: direct strip if subcommand absent) |
| `obsidian_wiki_config_write` | `path` | `format` (`single-line`/`multi-line`), `content_sha256` | Remove only when this row exists; cold-start without manifest = leave with warning |
| `git_hook_install` | `hook_name`, `hook_path` | `backup_path`, `backup_sha256` | `install-hooks.sh --uninstall` if prereq #6 shipped; else direct strip with backup-restore |

**Field-name canonicalization** (drift between rev2 example rows resolved): `backup_path` (not bare `backup`); `backup_sha256`/`block_sha256`/`created_sha256` (not bare `sha256`); `begin`/`end` (sentinel markers — drop the `_marker` suffix variant).

**No v0 compat aliases** (SF8 / scope-discipline sd-f2): prereq #4 ships `schema_version: 1` from day one; no manifests with the old field names ever exist in the wild. Reader strictly requires `schema_version: 1` on the header row and canonical field names on data rows.

### D7 — Tombstone lifecycle (closes A1)

3-state machine:
- **active**: `~/.claude/.monsterflow-install-manifest.jsonl` exists.
- **tombstoned**: `~/.claude/.monsterflow-install-manifest.uninstalled.<ts>` exists, active path absent. Result of clean `--apply` (exit 0).
- **absent**: neither file. Cold-start state OR multiple uninstall cycles past the latest tombstone (older tombstones retained for forensic trail).

Partial-apply failure (exit 1) → **no tombstone**; active manifest stays. Re-run resumes remaining ops.

Multiple uninstall cycles → multiple `.uninstalled.<ts>` tombstones (timestamp differs). Idempotent at user-observable layer; forensic trail at filesystem layer.

### D8 — `created_file` SHA-match policy (closes A2)

Three observable states for a `created_file` row at uninstall time:

| Current file SHA | Action |
|------------------|--------|
| Matches `created_sha256` | Delete file. File is byte-identical to what install wrote. |
| Differs from `created_sha256` | Preserve file in place. Run sentinel-strip on the matching `appended_block` row's `begin`/`end` markers (managed content gone; user content kept). |
| File absent | Skip with warning. User already deleted; nothing to do. |

AC6 covers SHA-match (round-trip diff → empty); AC6b covers SHA-mismatch (file present + sentinel-strip evidence + full-file backup).

### D9 — Cross-spec test isolation: `SKIP_CROSS_SPEC` (revised iter2 per MF7)

Default behavior: AC6/AC6b/AC7/AC21 **hard-fail** when prereq #5 artifacts (sentinel-bracketed CLAUDE.md block grep in `install.sh` or `claude-md-merge.py`) are absent. Wave 0 preconditions gate is the protection: uninstall-sh CI cannot run until prereqs are green. `SKIP_CROSS_SPEC` is repurposed as an **opt-in flag for a separate cold-start-only test suite** (`bash tests/test-uninstall-sh.sh --cold-start-only` or env `MONSTERFLOW_TEST_COLD_START=1`); that suite skips AC6/AC6b/AC7/AC21 and runs only the no-manifest detector-fallback paths. Closes Codex F5 + risk pl-risk-03.

### D10 — Memory-derived constraints (integration's named-memory list)

Hard constraints carried verbatim into implementation:
- `feedback_hook_stdin_heredoc`: NO `python3 - <<'PY'` heredoc; always invoke `scripts/_uninstall_helpers.py` as a real file.
- `feedback_path_stub_over_export_f`: tests use PATH-stub model; pin `BASH=/bin/bash` in test cases; no `export -f`.
- `feedback_dryrun_full_graph`: dry-run prints exact would-be paths/operations (line ranges for strips, sha256-verify status for restores) even without side effects.
- `feedback_negative_array_subscript_bash32`: no `${arr[-1]}` — use `$!` for last-launched PID; index from `$((${#arr[@]}-1))` when needed.
- `feedback_subagent_cwd_pollution`: build sub-agents must use absolute paths in all stub-write operations.

### D11 — Test seam: `MONSTERFLOW_UNINSTALL_TEST`

Env-var test seam mirroring `MONSTERFLOW_INSTALL_TEST` in install.sh. Toggles:
- `MONSTERFLOW_UNINSTALL_TEST=1` → graphify-binary invocation skipped (test-stub PATH may not have it); test fixture asserts the invocation would have happened via dry-run output grep.
- Other test-time overrides: `MONSTERFLOW_APPLICATIONS_DIR` (for Obsidian.app detection), `MONSTERFLOW_HASCMD_OVERRIDE` (per existing precedent).

### D12 — Build wave sequencing (revised iter2 per /check MF1 + MF3 + MF4)

**Wave 0 — preconditions gate (NOT a build task per MF4):**

Before Wave 1 begins, verify the following preconditions exist with green CI. uninstall-sh's `/build` is gated on these but does NOT author them — each prereq is its own /spec → /spec-review → /blueprint → /check → /build pipeline run that ships independently:

- Prereq #4 `install.sh-manifest-emit` shipped (spec + design + check + build all green). MF3 staging requirement: prereq #4's manifest emission is gated behind `MONSTERFLOW_MANIFEST=1` env var defaulting OFF; the env var flips to default-ON in the same release that ships uninstall.sh. Prevents in-the-wild unvalidated manifests on adopter machines between prereq #4 ship and uninstall.sh ship.
- Prereq #5 `install.sh-claude-md-ownership` shipped (spec + design + check + build all green).
- `schemas/install-manifest.v1.schema.json` (per MF2) committed at repo root + `tests/test-manifest-schema.sh` grep-test green. Owned by prereq #4's /build wave; closes Codex F4 + risk pl-risk-01 schema-drift-no-enforcement.

**MF1 correction:** `scripts/install-hooks.sh --uninstall` already exists (lines 16, 17, 31). uninstall-sh's `git_hook_install` reversal calls the existing script. There is no prereq #6 build task; what was framed as "prereq #6" is now T9 in Wave 3 — an audit + small extension if needed.

**Wave 1 — core uninstall (2 tasks parallel after Wave 0 preconditions green):**
- Wave 1a: `scripts/_uninstall_helpers.py` (the 6-subcommand helper). Independent of `uninstall.sh` once subcommand surface + manifest schema are locked (this design + prereq #4's published schema file).
- Wave 1b: `uninstall.sh` (top-level script + `unlink_file` adapter). Calls Wave 1a helpers via `$(...)`.

**Wave 2 — tests + docs (T7 sequential before T8a; T8b parallel):**
- Wave 2a: `tests/test-uninstall-sh.sh` (22 ACs including AC19a/b/c/d + AC20a/b/c splits per I7/I8, plus new AC23 multi-clone per MF5) + `tests/run-tests.sh` wiring **in the same commit** (per the `feedback_test_orchestrator_wiring_gap` memory).
- Wave 2b: `README.md` + `docs/index.html` + `CHANGELOG.md [Unreleased]` updates. Runs in parallel with 2a — does NOT touch `tests/run-tests.sh` (per Codex F9 race fix; SF6 split).

**Wave 3 — audit/extend existing install-hooks uninstall mode (MF1 reframe):**
- T9: audit `scripts/install-hooks.sh --uninstall` against D6 `git_hook_install` reversal contract; verify ownership checks + backup restore + `push.followTags` handling. Extend if any gap found. NOT a "prereq" — this is post-build polish on existing functionality.

**Cross-wave constraint:** Wave 1 sub-agents must NOT operate on shared files (only on their own task's output files). Wave 2 orchestrator wiring is a single sequential post-step (per `feedback_parallel_agents_shared_file_race` memory).

### D13 — followups.jsonl resolution mapping

How the 10 spec-review followup rows are addressed by this design:

| Followup | Resolution |
|----------|------------|
| sr-i1-schema-norm | D6 normative table |
| sr-i2-multiclone | D6 `repo_dir` per data row |
| sr-i3-migration-oos | added to spec.md Scope explicit-OOS row at `/check` revision |
| sr-i4-ac18-disposition | AC18 assertion enrichment at `/check` revision (build-inline) |
| sr-i5-ac11-obsidian | AC11 enumeration enrichment at `/check` revision (build-inline) |
| sr-i6-manifest-removal | D7 tombstone (already addressed = closed) |
| sr-i7-ac19-split | Wave 2a writes AC19a/b/c/d sub-cases |
| sr-i8-ac20-split | Wave 2a writes AC20a/b/c sub-cases |
| sr-i9-prereq5-granularity | already addressed (user picked option b, 3-prereq split) |
| sr-i10-detector-sunset | added to spec.md OQ row referencing prereq #4 blueprint |

## Implementation Tasks (revised iter2 per MF1 + MF4 + MF5 + SF2 + SF6)

T1 and T3 removed — they were /spec tasks misclassified as /build (MF4). T2 and T4 (build prereq #4, build prereq #5) are NOT under uninstall-sh's `/build` — they ship in their own pipeline runs and become Wave 0 preconditions per D12.

| # | Task | Wave | Depends On | Size | Parallel? |
|---|------|------|------------|------|-----------|
| T5 | `scripts/_uninstall_helpers.py` — 6 subcommands; stdlib-only; positional CLI per D4. **MF5: parse-manifest MUST implement `--repo-dir <dir>` filter; rows with non-matching `repo_dir` are excluded.** Validates against `schemas/install-manifest.v1.schema.json` with `--strict` flag (MF2). | 1a | Wave 0 preconditions | L | Yes (with T6) |
| T6 | `uninstall.sh` — top-level script; flag parsing; output constants per D3; `unlink_file` adapter per D5; orchestration per D7+D8. Apply build-inline followups sr-i4 ($dst disposition) and sr-i5 (AC11 obsidian enumeration). | 1b | Wave 0 preconditions | L | Yes (with T5) |
| T7 | `tests/test-uninstall-sh.sh` — 22 ACs (AC1-AC18, AC6b, AC19a-d, AC20a-c, AC21, AC22) **plus new AC23 multi-clone (per MF5: install from REPO_A; install from REPO_B; uninstall from REPO_A; verify only REPO_A's mutations reversed)** + PATH-stub fixtures; harness mirrors `test-install-knowledge-layer.sh`. **MF7: SKIP_CROSS_SPEC is OPT-IN for a cold-start-only suite; default behavior hard-fails AC6/AC6b/AC7/AC21 when prereq #5 artifacts absent.** | 2a | T5, T6 | XL | NO (sequential before T8a) |
| T8a | `tests/run-tests.sh` wiring — same commit as T7 (SF6 split; resolves SF3 race) | 2a | T7 | S | NO (sequential with T7) |
| T8b | `README.md` + `docs/index.html` + `CHANGELOG.md [Unreleased]` doc updates. **SF10: also apply spec.md text for sr-i3 (migration explicit-OOS) and sr-i10 (detector-fallback sunset OQ).** Does NOT touch `tests/run-tests.sh`. | 2b | T6 | S | Yes (parallel with T7) |
| T9 | Audit existing `scripts/install-hooks.sh --uninstall` mode (already shipped at lines 16, 17, 31) against D6 `git_hook_install` reversal contract; extend if gap found (ownership checks, backup restore, `push.followTags` handling). **NOT a prereq — post-build polish on existing functionality (MF1 reframe).** | 3 | — | S | Yes (independent) |

**Total tasks:** 6 (was 9 before MF4 removed T1/T3 and split T8 into T8a/T8b).

## Open Questions (resolved at /check iter2)

1. **`install_session_id` mandatory in v1 or v2?** (data-model OQ1) — Deferred to prereq #4 blueprint per design body. Not blocking uninstall-sh.
2. ~~Cold-start partial-failure exit code~~ **PINNED at /check (MF6): exit 1** (re-runnable; monotonic). D2 table updated.
3. ~~Prereq #6 rider detection~~ **OBSOLETED by MF1**: `scripts/install-hooks.sh --uninstall` already exists. T9 reframed to audit/extend, not new build.
4. ~~`block_sha256` mismatch policy~~ **PINNED at /check (SF9): warn + proceed** (sentinel strings are authoritative; SHA is integrity audit, not gating).

## Risks

- **Schema drift between prereq #4 and uninstall-sh** (was highest risk; now mitigated by MF2): if prereq #4's blueprint emits fields with names that diverge from D6's normative table, both specs ship but break at integration. Mitigation **owned by Wave 0 preconditions**: `schemas/install-manifest.v1.schema.json` is the single source of truth; `tests/test-manifest-schema.sh` grep-test asserts prereq #4's emit calls match the schema's required fields by name; uninstall's `parse-manifest --strict` validates manifests against the same schema. Closes risk pl-risk-01 + Codex F4.
- **Prereq #5's `claude-md-merge.py` refactor depth**: if the section-based interactive merge logic resists clean sentinel-retrofit, prereq #5 may slip its size estimate (currently M). Mitigation: prereq #5's `/blueprint` explicitly scopes the refactor; if surgery >M, carve into prereq #5a (sentinel-only) + #5b (mode-explicit refactor).
- **Test fixture complexity for AC6b** (user-edited `~/CLAUDE.md`): post-install user edit simulation needs precise byte content + sentinel-block intact + outside-block edit. Fixture-builder helper in `test-uninstall-sh.sh` to standardize.
- **Multi-clone manifest collision under adversarial use** (covered by D6 `repo_dir`): a user who pre-creates a manifest with malicious `repo_dir` rows can't trick uninstall into reversing the wrong files because each row's `repo_dir` is asserted to equal the current `$REPO_DIR` before reversal. Trust boundary: install-time manifest is install-authored; uninstall verifies row ownership.
- **`graphify` binary identity false-positive**: `readlink ~/.local/bin/graphify` returning a path containing `venvs/graphify/bin/graphify` could in principle be spoofed by a user creating a venv at that exact path. Mitigation: this is owner's-own-machine context — the threat model doesn't include the owner attacking themselves. Document; don't engineer against it.

Approve to proceed to `/check`? (approve / adjust `<what to change>`)
