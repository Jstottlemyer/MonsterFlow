---
persona: data-model
feature: install-graphify-wiki-coverage
gate: design
created: 2026-05-13
---

# Data Model Design — install-graphify-wiki-coverage

## Key Considerations

- The spec creates or modifies exactly three user-owned files: `~/.obsidian-wiki/config` (new file, if missing), `~/.zshrc` (append-only sentinel block), and `~/.local/bin/graphify` (symlink). Everything else is delegated to external tools (`graphify claude install`, `brew install --cask obsidian`, the venv installer). The data model is therefore thin: the only install.sh-authored persistent state is the config file and the zshrc sentinel block.

- `~/.obsidian-wiki/config` is a shared file that already exists on this machine with TWO keys: `OBSIDIAN_VAULT_PATH` and `OBSIDIAN_WIKI_REPO`. The spec's parser only reads `OBSIDIAN_VAULT_PATH`. The parser must silently skip unknown keys rather than reject the file as malformed. This is a real constraint, not hypothetical — the live file is multi-line.

- The sentinel block pattern is already established at install.sh:744-753 for the theme block (`# BEGIN MonsterFlow theme` / `# END MonsterFlow theme`). The obsidian-wiki block should follow the identical shape: same guard logic (`grep -qF "$BLOCK_BEGIN" "$ZSHRC"`), same heredoc append, same `touch "$ZSHRC"` before append. The only new element is the block sentinel string itself.

- Status classification (Ready / Can install now / Manual action required) is an in-memory enumeration computed fresh on every run. It is NOT persisted to disk. Idempotency comes from re-detecting state each run, not from reading a prior status file.

- The spec's "no new persistent state in MonsterFlow repo" claim is correct. No new config files, no JSONL, no schema bumps. The only persistent outputs are user-home artifacts listed above.

- `posix_quote` being nested inside `do_theme_install` was already flagged in review and resolved in rev1 (hoist to top-level). The data model implication: `install_obsidian_env()` writes quoted paths to both `~/.obsidian-wiki/config` and `~/.zshrc`. Both writes depend on `posix_quote`. The hoist is structurally required, not optional.

- Atomicity: the spec says install.sh uses atomic writes via `$INSTALL_SCRATCH/<name>.tmp` + `mv -f`. This pattern must apply to `~/.obsidian-wiki/config` to prevent a partial write from leaving a malformed file that future runs will fail to parse.

- Concurrency: install.sh is not re-entrant. Two simultaneous runs are not a supported scenario and not worth designing for. The sentinel-block guard (`grep -qF`) is idempotency-safe for sequential re-runs.

## Options Explored

### Option A: Pure-bash `parse_obsidian_config()` using `grep` + `sed`

Implementation: `grep -m1 '^[[:space:]]*\(export[[:space:]]\+\)\?OBSIDIAN_VAULT_PATH=' ~/.obsidian-wiki/config | sed 's/^.*OBSIDIAN_VAULT_PATH=//; s/^"//; s/"$//'`. Tilde expansion is a second step: `VAL="${VAL/#\~/$HOME}"`.

Pros:
- Zero external dependencies beyond what install.sh already uses (grep, sed are POSIX baseline).
- No subprocess startup overhead.
- Stays in the bash idiom already established by the rest of install.sh.
- Trivially auditable: the parsing logic is one or two pipeline expressions.

Cons:
- Handles the common cases but gets hairy for edge inputs: trailing inline comments (`OBSIDIAN_VAULT_PATH="path" # comment`), single-quoted values, unquoted values with spaces (rare but possible).
- Regex in sed must cover `export OBSIDIAN_VAULT_PATH=`, leading whitespace variants, and `OBSIDIAN_VAULT_PATH=` bare — doable but easy to get wrong.
- No good way to error on malformed lines without a third pipeline expression.

Effort: Low — ~10 lines.

### Option B: Inline python3 helper (heredoc or invoked script)

Implementation: a small `python3 -c` or a `python3 - <<'PY'` heredoc that reads the file, strips comments, handles all quote variants, returns the value on stdout.

Pros:
- Python's `shlex.split` handles all quoting edge cases (single quotes, double quotes, backslash escapes) correctly with no regex.
- Centralizes the "skip unknown keys" behavior cleanly.
- Easier to test in isolation.

Cons:
- The `python3 - <<'PY'` pattern (heredoc stdin) is explicitly flagged in project memory (`feedback_hook_stdin_heredoc`) as a known pitfall: occupies stdin, so piped JSON never reaches `json.load`. The same pitfall applies here — if `parse_obsidian_config` is called inside a function that's already reading from stdin (e.g., during the vault-path prompt), stdin collision is a real risk.
- Fix is to use a temp `.py` file + `python3 /tmp/parse_config_$$.py`, but that adds a mktemp lifecycle to what should be a simple read.
- python3 subprocess has ~100ms startup cost — negligible but non-zero.
- Adds a subprocess-visible call that test stubs would need to handle.

Effort: Medium — ~20 lines including the temp-file lifecycle.

### Option C: `.zshrc` sentinel block as a key-value store (embed vault path in sentinel comment)

This variant stores the vault path INSIDE the sentinel comment line so that the sentinel both guards deduplication AND encodes the configured path:
```
# BEGIN MonsterFlow obsidian-wiki VAULT=/Users/jstottlemyer/Documents/Obsidian/wiki
export OBSIDIAN_VAULT_PATH="/Users/jstottlemyer/Documents/Obsidian/wiki"
# END MonsterFlow obsidian-wiki
```
The `parse_obsidian_config` function would then read `~/.zshrc` for the sentinel comment rather than `~/.obsidian-wiki/config`.

Pros:
- One fewer file (`~/.obsidian-wiki/config` not required for install.sh's own state; it's still written for skill consumption).
- Deduplication guard and stored-path extraction are one grep.

Cons:
- The sentinel comment format is non-standard and fragile — any user editing their `.zshrc` to move the block would lose the metadata.
- The spec's skill stack (`wiki-*`) reads `~/.obsidian-wiki/config`, not `~/.zshrc`. install.sh must write the config file for skill compatibility regardless, so this saves nothing for the spec's actual use case.
- Conflates two concerns (deduplication guard vs config storage). The theme block uses sentinel-only (no embedded data) — deviating would be inconsistent.
- Over-engineers what is simply a two-step: write config file + write zshrc block.

Verdict: Reject. Adds complexity with no reduction in artifact count for this spec.

## Recommendation

**Option A (pure-bash parser) for `parse_obsidian_config()`**, with one precision addition: handle trailing inline comments by stripping everything from `#` onward AFTER unquoting, only when the `#` is preceded by whitespace (to avoid stripping `#` inside paths, which are uncommon but valid).

The parser should cover exactly these input patterns (all observed in the wild from the live config file and AC9 fixture):

```
# comment line — skip
OBSIDIAN_VAULT_PATH="~/Documents/Obsidian/wiki"
OBSIDIAN_VAULT_PATH=~/Documents/Obsidian/wiki
export OBSIDIAN_VAULT_PATH="~/Documents/Obsidian/wiki"
export OBSIDIAN_VAULT_PATH="~/Documents/test vault"   # inline comment
  OBSIDIAN_VAULT_PATH="..."                            # leading whitespace
OBSIDIAN_WIKI_REPO=...                                 # unknown key — skip silently
```

The `${VAR/#\~/$HOME}` tilde expansion is the mandatory final step before any directory-existence check. The parser must NOT `source` the file (AC9).

Rationale for Option A over B: the `python3 - <<'PY'` stdin-collision hazard is a documented project footgun, and the workaround (temp `.py` file) adds lifecycle complexity that isn't justified by the parsing complexity here. The bash pipeline handles all production-observed input formats cleanly when written carefully.

## Constraints Identified

- **Tilde expansion is mandatory before directory-exists check.** `${VAR/#\~/$HOME}` (not eval, not `echo ~$USER`) must be applied to the extracted value before `[ -d "$VAL" ]`. See `feedback_tilde_expansion_in_bash_config_reads` — a literal `~/` returned by grep will NOT expand in `"$VAR"` context and a literal `~/Documents/` directory will not be found.

- **`parse_obsidian_config()` must silently skip unknown keys.** The live `~/.obsidian-wiki/config` file has at least two keys (`OBSIDIAN_VAULT_PATH` and `OBSIDIAN_WIKI_REPO`). A parser that rejects non-`OBSIDIAN_VAULT_PATH` lines would fail on the existing format.

- **`~/.obsidian-wiki/config` must be written atomically.** Write to `$INSTALL_SCRATCH/obsidian-wiki-config.tmp` then `mv -f` to final path. Consistent with the existing install.sh atomic-write contract (W2 task 2.2). A partial write leaves a malformed file that blocks future re-runs.

- **Bash 3.2 compatibility.** install.sh runs on macOS where `/bin/bash` is 3.2. No `${array[-1]}`, no `declare -A` associative arrays, no `printf '%q'` (it exists but behavior differs). The parser must use only bash 3.2-safe constructs. `${VAR/#\~/$HOME}` is safe (parameter substitution, 3.2-compatible).

- **No `source` of user-writable files.** Sourcing `~/.obsidian-wiki/config` executes arbitrary code. The parser must extract `OBSIDIAN_VAULT_PATH` via grep/sed without shell evaluation. This is both a security constraint (the config file is user-writable and potentially unvalidated) and an explicit AC9 requirement.

- **Sentinel block must not be duplicated.** The guard `grep -qF "$BLOCK_BEGIN" "$ZSHRC"` must fire before any append. If the sentinel is present (from any prior run), the block is skipped entirely — no update of the vault path inside the block, no second append. If the user has changed their vault path, they update `~/.obsidian-wiki/config` directly; the zshrc block is not a live mirror.

- **Non-sentinel `OBSIDIAN_VAULT_PATH=` in `.zshrc` must be detected before appending.** Per EC5: if the user already exports `OBSIDIAN_VAULT_PATH` outside a sentinel block, skip the append and print one-line notice. The detection must check for the raw variable name, not just the sentinel string.

- **Config file format is single-assignment-per-line, no shell syntax required.** The spec writes `OBSIDIAN_VAULT_PATH="<path>"` (one line, double-quoted, the value is already expanded at write time — no literal `~` in the written file if the user accepted the default and install.sh resolved it). But the parser must also handle a literal `~` in case the user manually edited the file or it was written by a prior tool version.

- **`posix_quote` must be hoisted before `do_theme_install`.** Both `install_obsidian_env()` and `do_theme_install` call it. Since Knowledge Layer runs after `do_theme_install` but can also run under `--no-theme`, the function must be defined at the top-level scope of install.sh, not inside any function body.

- **`~/.obsidian-wiki/config` is NOT created if the vault path cannot be validated.** Under non-interactive mode with no resolvable default, the file is NOT written (per EC19). The parser must tolerate the file's absence — detection reports `✗` cleanly.

- **The `.zshrc` sentinel block content should embed the fully-expanded path, not the literal `~`.** Write `export OBSIDIAN_VAULT_PATH="/Users/jstottlemyer/Documents/Obsidian/wiki"` (expanded), not `export OBSIDIAN_VAULT_PATH="~/Documents/Obsidian/wiki"` — avoids a second-order tilde-expansion dependency at shell startup.

## Open Questions

1. **Multi-value: what wins when `~/.obsidian-wiki/config` has OBSIDIAN_VAULT_PATH defined twice?** The spec says nothing. Grep `-m1` would return the first occurrence; `grep | tail -1` would return the last. Which wins? Convention in env/config files is "last definition wins" (matches shell semantics), but the MonsterFlow config file is not sourced — it's parsed. Recommend: take the last line matching `OBSIDIAN_VAULT_PATH=` (grep without `-m1`, pipe to `tail -1`), match shell semantics, document the choice.

2. **BOM and CRLF line endings.** The spec doesn't address Windows-edited or BOM-prefixed config files. A `\r` at line end (`OBSIDIAN_VAULT_PATH="path"\r`) would make the grep extract `"path"\r`, and the directory-exists check on a path ending in CR would silently fail. Not a production concern today (this is a macOS-only tool), but the parser should strip `\r` defensively (`tr -d '\r'` on the extracted value). Low effort, prevents a confusing future failure mode.

3. **CRLF in `.zshrc` heredoc.** If install.sh itself is edited on Windows (unlikely but the repo is public), the heredoc lines would embed `\r`. Not guarding for this in the write path is acceptable given macOS-only scope; call it out in the constraints rather than adding complexity.

4. **What happens when both `~/.obsidian-wiki/config` and `$OBSIDIAN_VAULT_PATH` shell env var are set and disagree?** The spec's detection reads the config file (not the shell env). If `$OBSIDIAN_VAULT_PATH` is already set in the environment (from a prior session or a user's own export), the detection reads the config file, resolves the path, and compares. But the spec doesn't say: if the env var is set and points to a real directory, does install.sh skip the config-write entirely? Current spec language says "write `~/.obsidian-wiki/config` if missing" — so the env var being present doesn't affect the file write. This is correct but should be called out explicitly: the config file is the authoritative install.sh state; the env var is the runtime consequence of the zshrc block.

5. **Sentinel string collision risk with obsidian-wiki upstream.** The spec's open question notes the sentinel choice: `# BEGIN MonsterFlow obsidian-wiki` / `# END MonsterFlow obsidian-wiki`. The upstream `Ar9av/obsidian-wiki` project may emit its own `.zshrc` modifications during `npx skills add`. The sentinel string should be distinct enough that it doesn't collide. The proposed string (MonsterFlow-prefixed) is safe: the upstream installer writes skill files, not shell config. Worth a one-time verification when the upstream installer runs.

6. **Config file permission.** The spec doesn't specify. `~/.obsidian-wiki/config` should be `chmod 600` on write (it may contain a path that reveals vault location — not a secret per se, but consistent with the `~/.claude/*.apikey` pattern). The atomic-write sequence should include `chmod 600` before `mv -f` so the file is never world-readable even transiently.

## Integration Points with Other Dimensions

- **API persona:** The three install.sh helper functions that write persistent state (`install_obsidian_env()`, and the sentinel-block append) are the "write API" that other dimensions depend on. The API persona needs to know: (a) `parse_obsidian_config()` returns the expanded vault path as a stdout string (empty on failure), not via a global variable — this keeps it testable and avoids bash global-state pollution; (b) the detection return values (Ready/Can-install-now/Manual-action-required) are communicated as local variables or return codes, not written to disk — the API persona needs to decide the internal calling convention.

- **Integration persona:** The `install_obsidian_env()` function's write to `~/.zshrc` must not race with the theme stage's `do_theme_install` (which also writes `~/.zshrc`). Since `do_knowledge_layer` runs AFTER `do_theme_install` returns (install.sh:757-758 ordering confirmed), the writes are sequential. The integration persona should confirm the call-site ordering is preserved and that `do_theme_install`'s `posix_quote` local function is definitionally gone before `do_knowledge_layer` runs (only the hoisted top-level version is in scope).

- **Integration persona:** `~/.obsidian-wiki/config` is read by the `wiki-*` skill stack at runtime (not by install.sh). The format install.sh writes must be compatible with what the skills parse. The skills presumably `source` or `grep` this file; install.sh must write a format the skills accept. Current live format (`OBSIDIAN_VAULT_PATH="..."` bare assignment, one key per line) is what install.sh should reproduce. The second key `OBSIDIAN_WIKI_REPO` that exists in the live file is NOT written by install.sh — it was presumably written by the obsidian-wiki installer or manually. install.sh must not clobber it on re-run (atomic-write must only write the `OBSIDIAN_VAULT_PATH` line if the file is absent; if the file exists, touch nothing).

- **Security persona (dropped from roster but relevant):** The no-source constraint is a security boundary. If any future iteration relaxes this (e.g., "just source the config, it's user-writable anyway"), the attack surface is arbitrary code execution via `~/.obsidian-wiki/config`. The constraint must be documented at the `parse_obsidian_config()` function header, not just in the spec.
