---
tags: []
tags_provenance:
  baseline: []
  llm_added: []
  user_overrides: []
gate_mode: permissive
---

# install-sh-manifest-emit Spec

**Created:** 2026-05-14
**Constitution:** none — session roster only
**Status:** Drafted as a prereq for `uninstall-sh` (see `docs/specs/uninstall-sh/design.md` D6 + D12 Wave 0). Skipped /spec Q&A — requirements settled at uninstall-sh /blueprint + /check iter2.

## Summary

Add an append-only JSONL **install manifest** at `~/.claude/.monsterflow-install-manifest.jsonl` that records every mutation `install.sh` makes (symlinks created, sentinel blocks appended, files created from templates, graphify installed, obsidian-wiki config written, git hooks installed). The manifest is the cross-spec contract that `uninstall.sh` reads to perform safe, ownership-provable reversals. Emission is gated behind `MONSTERFLOW_MANIFEST=1` env var defaulting OFF; flips to default-ON in the release that ships `uninstall.sh` (prevents in-the-wild unvalidated manifests).

## Backlog Routing

| # | Item | Source | Routing |
|---|------|--------|---------|
| 1 | this spec | uninstall-sh prereq #4 | (a) in scope |
| 2 | `install-sh-claude-md-ownership` (sibling prereq) | uninstall-sh prereq #5 | (c) sibling spec |
| 3 | `uninstall-sh` (consumer) | uninstall-sh design | (c) downstream — blocks on this + sibling |

## Scope

### In scope

1. **`~/.claude/.monsterflow-install-manifest.jsonl`** at install-time. Append-only; never modified post-install (uninstall-sh tombstones it via `mv` per its D7).
2. **`schemas/install-manifest.v1.schema.json`** at repo root — JSON Schema 2020-12 — the normative contract that both install.sh emit calls and uninstall.sh `parse-manifest --strict` validate against. Closes uninstall-sh /check MF2 + Codex F4.
3. **`tests/test-manifest-schema.sh`** — grep-test asserting `install.sh`'s emit calls reference only canonical schema field names (`backup_path`, `block_sha256`, `created_sha256`, etc.) — catches drift between schema file and install.sh at CI time.
4. **`MONSTERFLOW_MANIFEST=1` staging gate** (per uninstall-sh /check MF3). Without the env var, `install.sh` runs unchanged (no manifest written). With the env var, every mutation site appends a row. The env var flips to default-ON in the release that ships uninstall.sh.
5. **Manifest schema** (normative; copied verbatim from uninstall-sh design.md D6 — schema file is the canonical source):
   - **Header row (line 1, no `op`):** `{"schema_version": 1, "written_by": "install.sh", "written_at": "<iso8601-utc>"}`
   - **Common fields** on every data row: `op` (enum), `repo_dir` (absolute path, no trailing slash), `created_at` (ISO 8601 UTC), `install_session_id` (UUID v4 — optional in v1 per uninstall-sh OQ1)
   - **Per-op required + optional:** see schema file. Ops: `symlink`, `append_block`, `appended_block`, `created_file`, `graphify_install`, `obsidian_wiki_config_write`, `git_hook_install`.
6. **`scripts/_manifest_emit.py`** helper called from install.sh at every mutation site (per `feedback_hook_stdin_heredoc` memory — real file, not python3 heredoc). Atomic-append via tempfile + `os.replace` (cross-platform safe).
7. **Mutation sites instrumented** (audit list — must match install.sh's actual mutation surface; verify with `autorun-shell-reviewer` subagent):
   - Symlink wave (`link_file` calls at install.sh:~451): commands/, agents/, personas/, templates/, hooks/, scripts/, skills/, schemas/, domain-agents/, commands/_prompts/, settings.json, ~/.local/bin/autorun, ~/.local/bin/graphify
   - Theme stage symlinks: cmux.json, tmux.conf, ghostty config
   - `~/.zshrc` sentinel blocks: theme + obsidian-wiki (op:`append_block`)
   - `~/CLAUDE.md`: depending on prereq #5 modes — `created_file` (template copy) or `appended_block` (managed block in existing file)
   - Knowledge Layer: `graphify_install`, `obsidian_wiki_config_write`
   - `scripts/install-hooks.sh` invocation: emits `git_hook_install` rows
8. **`migrate-to-manifest.sh`** (optional v1; mandatory before detector-fallback sunset per uninstall-sh OQ#4): one-shot script that reads current `~/.claude/` filesystem state on a pre-manifest install and synthesizes a manifest from detected symlinks + sentinel blocks. Best-effort; checksum fields filled where possible.

### Out of scope

1. **Backward compat for pre-v1 manifest formats** — there are none; ship `schema_version: 1` from day one (closes uninstall-sh /check SF8).
2. **`schema_version: 2`** — future revision; not addressed here.
3. **`uninstall.sh` itself** — consumer spec.
4. **Reading the manifest** — uninstall-sh owns the reader.
5. **Multi-machine state sync** — local machine only (matches uninstall-sh OOS).
6. **`~/.claude/projects/<slug>/memory/`** — not install state; user-authored auto-memory.

## Approach

**Single helper script** at `scripts/_manifest_emit.py` invoked from install.sh at every mutation site. Helper takes `op` + key-value args, validates against schema (defense-in-depth — schema file is the contract; helper enforces locally), appends a row atomically. install.sh calls the helper via positional CLI:

```bash
manifest_emit_symlink() {
  [ "${MONSTERFLOW_MANIFEST:-0}" = "1" ] || return 0
  python3 "$REPO_DIR/scripts/_manifest_emit.py" symlink \
    --dst "$1" --src "$2" --backup-path "${3:-}" --backup-sha256 "${4:-}" --previous-kind "${5:-}"
}
# similar wrappers per op
```

Each mutation site in install.sh wraps its existing logic with a manifest-emit call AFTER the mutation succeeds (emit-after-success — never record a phantom row for a failed write).

**Why this shape** (rejected alternatives):
- Inline JSONL in bash (no Python): brittle quoting, no schema validation, fails `feedback_hook_stdin_heredoc` constraint.
- One mega-helper that wraps all mutation logic (replaces link_file etc.): too much surface change in install.sh; risks regressions in the v0.12.0 install paths.
- Manifest in TOML / YAML: install.sh ecosystem is already JSONL-oriented (findings.jsonl, survival.jsonl, etc.); consistency wins.

## Roster Changes

No roster changes.

## UX / User Flow

install-time:
```bash
$ MONSTERFLOW_MANIFEST=1 bash install.sh
... (existing install output) ...
=== Installation complete ===
Manifest: ~/.claude/.monsterflow-install-manifest.jsonl (47 rows)
```

Without the env var (default until uninstall-sh release):
```bash
$ bash install.sh
... (existing install output, no manifest mention) ...
```

Re-install on machine with existing manifest:
```bash
$ MONSTERFLOW_MANIFEST=1 bash install.sh
Manifest: appended 12 new rows (was 47; now 59). install_session_id: <uuid>
```

## Data & State

### Manifest JSONL row format

Header row (line 1, written on first install, never modified):
```json
{"schema_version": 1, "written_by": "install.sh", "written_at": "2026-05-14T10:22:31Z"}
```

Data row examples:
```json
{"op":"symlink","dst":"/Users/jstottlemyer/.tmux.conf","src":"/Users/jstottlemyer/Projects/MonsterFlow/config/tmux.conf","repo_dir":"/Users/jstottlemyer/Projects/MonsterFlow","created_at":"2026-05-14T10:22:33Z","install_session_id":"a3f8...","backup_path":"/Users/jstottlemyer/.tmux.conf.bak.20260514102233","backup_sha256":"abc...","previous_kind":"file"}
{"op":"append_block","file":"/Users/jstottlemyer/.zshrc","begin":"# BEGIN MonsterFlow theme","end":"# END MonsterFlow theme","block_sha256":"def...","repo_dir":"...","created_at":"...","install_session_id":"..."}
{"op":"created_file","path":"/Users/jstottlemyer/CLAUDE.md","created_sha256":"012...","template_src":".../templates/CLAUDE.md","repo_dir":"...","created_at":"...","install_session_id":"..."}
```

Full per-op required/optional table lives in `schemas/install-manifest.v1.schema.json`.

### `schemas/install-manifest.v1.schema.json`

JSON Schema 2020-12 document. Top-level schema is `oneOf`: header row (line 1) OR data row (lines 2+). Header row schema requires `schema_version`, `written_by`, `written_at`. Data row schema is a discriminated union on `op`. Each `op` value has its own subschema with required + optional field constraints. All checksum fields are `^[a-f0-9]{64}$` (sha256 hex). `created_at` is ISO 8601 UTC with `Z` suffix. `repo_dir` is absolute path with no trailing slash.

### Append semantics

`_manifest_emit.py`:
1. Read existing manifest (if any) — header row's `schema_version` determines compat.
2. Build new row dict; validate against schema (raises if invalid).
3. Open manifest for append in binary mode.
4. `fcntl.flock(fd, LOCK_EX)` advisory lock (handles concurrent emits from parallel install steps).
5. Write `json.dumps(row, separators=(',', ':')) + '\n'`.
6. `fsync` then unlock.

## Integration

### Touches

- `install.sh` — wraps every mutation site (~20 sites) with a manifest-emit call. Wave 1 task.
- `scripts/_manifest_emit.py` (new file). Wave 1 task.
- `schemas/install-manifest.v1.schema.json` (new file at repo root). Wave 1 task — owns the contract.
- `scripts/migrate-to-manifest.sh` (new file). Wave 2 task (lower priority — needed before detector-fallback sunset).
- `tests/test-manifest-schema.sh` (new file) + `tests/run-tests.sh` wiring in same commit (per memory). Wave 2 task.
- `CHANGELOG.md` [Unreleased] entry. Wave 2.

### Does NOT touch

- `uninstall.sh` (separate spec).
- Existing `link_file` / `do_*` functions — wrapped, not refactored.
- Adopter behavior when `MONSTERFLOW_MANIFEST=0` (the default until uninstall.sh release): identical to today.

## Edge Cases

1. **install.sh interrupted mid-flight** (SIGINT, kill): manifest contains rows for completed ops only; subsequent re-install appends new rows. uninstall sees partial install correctly.
2. **`~/.claude/` doesn't exist yet** on first install: `_manifest_emit.py` does `mkdir -p` before first write.
3. **Manifest file unreadable** (corrupted previous write): `_manifest_emit.py` exits non-zero with explicit error; install.sh proceeds but logs the failure (manifest emission is best-effort — install must not block on it). uninstall in cold-start mode handles the case.
4. **Concurrent install.sh runs** (paranoid case — adopter runs in two terminals): `flock` serializes appends; both runs see consistent header row.
5. **`$REPO_DIR` has trailing slash**: helper strips before writing (schema requires no trailing slash).
6. **Multi-install on same machine**: each install session has a new `install_session_id` UUID. uninstall reverses in reverse-chronological order (newest session first) per uninstall-sh edge case 13.
7. **install.sh `--no-onboard` / `--no-install` / `--no-theme` paths**: each guard wraps its own emit calls — no row written if the mutation didn't happen.
8. **`schema_version` already 1 from existing manifest, but a new install ships v1+ extension**: header row left alone; new rows include the new optional fields. Forward-compat by additive-only schema evolution.

## Acceptance Criteria

15 cases in `tests/test-install-sh-manifest-emit.sh`:

1. **AC1** — `MONSTERFLOW_MANIFEST=0` (default): no manifest written; `~/.claude/.monsterflow-install-manifest.jsonl` absent post-install.
2. **AC2** — `MONSTERFLOW_MANIFEST=1`: manifest written with valid header row at line 1.
3. **AC3** — Every symlink created by `link_file` produces a corresponding `op:symlink` row with `dst`, `src`, `repo_dir`, `created_at`.
4. **AC4** — `~/.tmux.conf` symlink (replacing pre-existing user file) records `backup_path` + `backup_sha256` + `previous_kind: "file"`.
5. **AC5** — `~/.zshrc` theme sentinel block produces `op:append_block` row with `begin`, `end`, `block_sha256`.
6. **AC6** — `~/CLAUDE.md` template-copy (when pre-install absent) produces `op:created_file` with `created_sha256` + `template_src`.
7. **AC7** — `~/CLAUDE.md` baseline-merge (when pre-install present) produces `op:appended_block` (not `created_file`).
8. **AC8** — graphify install produces `op:graphify_install` with `binary` + `venv`.
9. **AC9** — obsidian-wiki config write produces `op:obsidian_wiki_config_write` with `path` + `format`.
10. **AC10** — Schema validation: every emitted row validates against `schemas/install-manifest.v1.schema.json`.
11. **AC11** — `tests/test-manifest-schema.sh` grep-test passes: every emit call in install.sh references canonical field names only.
12. **AC12** — Multi-install: second install with `MONSTERFLOW_MANIFEST=1` appends new rows with new `install_session_id`; header row unchanged.
13. **AC13** — `--no-onboard` install: only mutations actually performed appear in manifest; no phantom rows.
14. **AC14** — `--no-install` install (CI escape hatch): no manifest written even with env var (no mutations to record).
15. **AC15** — `migrate-to-manifest.sh` smoke test: stub `$HOME` with detected MonsterFlow state but no manifest → migrate produces a manifest that validates against the schema.

## Open Questions

1. **`install_session_id` mandatory in v1?** — Recommendation: optional in v1 (helper generates UUID v4 when omitted but allows callers to skip it). Mandatory at `schema_version: 2`.
2. **Should `_manifest_emit.py` be importable as a Python module** (per uninstall-sh /check SF7 deferred recommendation)? Defer until Wave 1 implementer pushback.
3. **Migrate-to-manifest tooling priority**: ship in v1 (this spec) or as a follow-up after uninstall.sh ships? Lean: follow-up (uninstall.sh detector-fallback covers pre-manifest installs for the sunset window).

## Notes

- `gate_max_recycles` omitted (deprecated).
- `tags: []` — 10-enum closed set has no fit; `data` is closest but the spec is more about tooling than data modeling per se.
- The autorun-shell-reviewer subagent MUST run before commits to install.sh (per `feedback_build_subagent_invocations_must_fire` memory).
