# Security — install-rewrite

**Stage:** /plan (Design) · **Persona:** security
**Subject:** Threat-model the additive-surgery install.sh rewrite (v0.5.0).
**Trust posture:** install.sh runs in the user's shell with the user's privileges, mutates `~/.claude/`, `~/.zshrc`, `~/.tmux.conf`, `~/.config/cmux/cmux.json`, and shells out to `brew bundle` (which can run arbitrary post-install scripts). Blast radius of a compromise is the user's macOS account.

## Threat Model

### T1 — Compromised MonsterFlow repo (supply chain)
- Attacker pushes to `Jstottlemyer/MonsterFlow` (or convinces a victim to clone a fork). Adopter runs `./install.sh`. Anything in repo executes with user privs.
- Vectors: malicious `Brewfile` (pulls a compromised cask), malicious `config/zsh-prompt-colors.zsh` (becomes a permanent shell hook the next time any zsh starts), malicious `scripts/onboard.sh` (runs at install + every manual re-run), malicious `link_file()` source (silently overwrites a path the symlink chain ends at).
- **Worst case:** persistent shell-level RCE that fires on every new terminal until adopter notices. The `.zshrc` `source <repo>/config/zsh-prompt-colors.zsh` line is the persistence anchor — repo can ship arbitrary code there post-install with zero further user interaction.

### T2 — Compromised brew formula / cask
- `brew bundle install` invokes formula install scripts as the user. A compromised `cmux` cask, `gh` formula, etc. runs whatever its install script says. Outside our control once we delegate to brew.
- Mitigation surface available to us: (a) make the user *see* exactly what brew is about to install BEFORE confirm (not after dependency resolution surprises them), (b) refuse to auto-bootstrap brew itself (spec already does this — adopter must run brew's installer themselves), (c) keep Brewfile minimal and reviewable.

### T3 — Malicious environment variables
- `MONSTERFLOW_OWNER=1` flips privacy-sensitive defaults (theme installed without prompt; `PERSONA_METRICS_GITIGNORE` defaults to 0 → metrics get committed). A hostile parent process (compromised dev tool, malicious npm postinstall, etc.) can `export MONSTERFLOW_OWNER=1` then run the installer in the adopter's project — installer believes it's the engine repo and applies owner defaults.
- `PERSONA_METRICS_GITIGNORE=0` in env → adopter's `.gitignore` does NOT get the metrics block → next commit sweeps `findings*.jsonl` (which contains review prose, possibly internal proprietary code paraphrased) into a public repo. This is the same data-leak class as the `feedback_public_repo_data_audit.md` incident.
- `HOME=/tmp/attacker` → installer writes symlinks into a path the attacker controls; on next session these symlinks resolve to attacker payloads.
- `REPO_DIR` is computed, not env-derived, so it's not directly attacker-controlled — but `install.sh` is sourced from `$(dirname "$0")` which is shell-controlled. Running via `bash <(curl ...)` makes `$0` a bash-internal placeholder — current `cd "$(dirname "$0")"` would fail or land in `/dev/fd/...`. Spec rejects `curl|bash` bootstrap (good); plan should make that rejection enforceable.

### T4 — Race conditions during install (TOCTOU)
- `link_file()` does `[ -e "$dst" ] && [ ! -L "$dst" ]` then `mv "$dst" "${dst}.bak"` then `ln -sf`. Between the `[ -e ]` check and the `mv`, an attacker with write access to `$HOME` (i.e., another process in the same session, or a shared-machine attacker) can:
  - Replace `$dst` with a symlink pointing at an arbitrary file → `mv` then renames *the attacker's pointer* to `${dst}.bak`, but the original target is untouched. Low-impact.
  - Replace `$dst` with a hardlink to a sensitive file → `mv` moves the hardlink to `.bak`, then `ln -sf` puts our symlink in place; the attacker now has a hardlink to a privileged file under a known path. Higher-impact if `$dst` was something with restrictive permissions.
- Realistic threat-actor scenario is narrow (single-user macOS dev box), but worth hardening because `link_file()` runs ~50 times per install and the window is bash-interpretation-slow.

### T5 — Symlink-target swap mid-install
- After `ln -sf "$src" "$dst"`, an attacker who can write to `$REPO_DIR` (e.g., the install ran from a network mount, or `$REPO_DIR` is `/tmp/...`) can swap the target file's contents at any time afterward. `~/.zshrc` will then `source` whatever new contents land at `$REPO_DIR/config/zsh-prompt-colors.zsh`.
- This is the *fundamental* property of "symlink to in-repo file." It is by design (re-cloning the repo updates installed pipeline behavior without re-running install). The security implication is that **the repo location must be trusted-write, owner-only, and not under `/tmp`, network mount, or shared workspace.** Spec doesn't currently say this anywhere user-visible.

### T6 — Pre-existing-file deletion via SIGINT trap
- Spec adds: `trap cleanup_partial INT TERM; find "$REPO_DIR" "$CLAUDE_DIR" -name '*.monsterflow.tmp' -delete`.
- Threat: attacker pre-creates `~/.claude/important-file.monsterflow.tmp` (any file matching the glob, anywhere under `$REPO_DIR` or `$CLAUDE_DIR`) BEFORE the user runs install.sh. User hits Ctrl-C. The trap deletes the attacker-named file. If the file is a symlink (`important-file.monsterflow.tmp -> ~/.ssh/id_ed25519`), `find ... -delete` removes the **symlink**, not the target — but the same pattern with `find -L` or `xargs rm` would follow it. Current spec uses `-delete` which is OK; locking that down in code review matters.
- Lower-impact angle: attacker creates `~/.claude/commands/spec.md.monsterflow.tmp` while user is reading the migration prompt. User Ctrl-C's. Trap deletes it (no-op, since it's already attacker-owned). User re-runs; install proceeds. Largely benign in practice, but the trap should be defensive.

### T7 — Migration message version downgrade
- Spec: hardcoded "v0.5.0" in migration message. If an attacker ships a v0.4.99 tarball that pretends to be a "v0.5.0 → v0.6.0 upgrade," the script blindly trusts its own version string. Not a real downgrade attack on the running script (the script *is* the attacker in this scenario), but worth noting: there is no signature or version-floor check. We can't defend against a malicious shipped install.sh by inspecting that same install.sh.
- Realistic concern is the inverse: an adopter on `main` who pulled v0.4.x sees the v0.5.0 message because the spec hardcodes it. If `git pull` brings v0.5.0 down later, the upgrade banner will have already fired. Cosmetic, not security-critical.

### T8 — `read -rp` input handling
- Bash `read -rp` with `-r` (raw) is the right default — disables backslash-as-escape. Already used throughout. New stages must continue using `-r`.
- The captured variable is then matched with `[[ "$var" =~ ^[Yy]$ ]]`. Regex-anchored match on a single character is safe — no command substitution, no eval. Pattern-matching globs (`[[ "$var" == y* ]]`) would also be safe. Avoid `eval`, `$(<<<"$var")`, or unquoted expansion in command position.
- New flag: `--non-interactive` auto-detect via `[ -t 0 ]`. If stdin is a terminal, prompt; otherwise default. **Edge case:** stdin is a pipe carrying attacker-chosen content (`./install.sh < attacker-script`). Today's `read -rp` reads one line and matches `^[Yy]$` — attacker can answer Y to every prompt but cannot inject arbitrary commands via `read`. Safe.

### T9 — `.zshrc` append (the PEM-in-`.secrets` class of bug)
- **Prior incident** (per `~/CLAUDE.md`, 2026-04-20): a session wrote a GitHub App RSA key to `~/.secrets`, which `.zshrc` was sourcing as shell. The PEM echoed to stdout on every new terminal. Hardening since: `.zshrc` content-validates `~/.zshenv.local` before sourcing (refuses if perms ≠ 600 or content looks like PEM).
- **This spec adds** `source <repo>/config/zsh-prompt-colors.zsh` to `~/.zshrc`. Same class of bug — a different file is now in the user's shell-init trust chain. Mitigations:
  1. **Path quoting:** the `source` line MUST be `source "<absolute-path>"` with double quotes, because `$REPO_DIR` can contain spaces (e.g., `~/Library/Mobile Documents/...`). Without quotes, `source /Users/x/My Code/MonsterFlow/...` becomes `source /Users/x/My` (file not found, silent shell-init failure). With quotes, `source "/Users/x/My Code/MonsterFlow/..."` works.
  2. **Content discipline:** `config/zsh-prompt-colors.zsh` ships in-repo, is reviewable in git history, contains zero network calls, no key material. Plan must enforce this at code-review time. Add a CI check: `grep -E '(curl|wget|nc |bash <\(|eval )' config/zsh-prompt-colors.zsh` returns empty.
  3. **Permissions:** the file is 644 (group/world readable, owner-write). That's correct for theme content (no secrets). If it ever holds secrets, the answer is *don't put secrets there* — not chmod 600, which would just mask the problem.
  4. **Sentinel-bracketed:** `# BEGIN MonsterFlow theme` / `# END MonsterFlow theme` makes the block detectable and removable. Idempotent re-runs OK.
  5. **The compat-symlink rule** (`feedback_settings_file_relocation.md`): if a future spec moves `config/zsh-prompt-colors.zsh` elsewhere in the repo, the *running* zsh sessions cached the path at startup and will keep finding the old location until the user logs out. Leave a symlink. (Same class of bug as relocating files referenced in `settings.json`.)

### T10 — `gh auth login` invocation
- `gh auth login` opens a browser OAuth flow. It writes the resulting OAuth token to `~/.config/gh/hosts.yml` (chmod 600 by `gh` itself). The token is **not** echoed to stdout; install.sh doesn't redirect or `tee` `gh auth login`'s output.
- Risk: if anyone redirects install.sh's stdout to a log (`./install.sh > install.log 2>&1`) and `gh auth login` ever changed to print the token (it doesn't today, but versions move), that log would leak the token. Mitigation: when invoking `gh auth login`, route its stdout/stderr to the user's TTY, not to install.sh's piped stream:

```bash
if [ -t 1 ]; then
    gh auth login   # fine, TTY
else
    echo "  (skipping gh auth login: not a TTY)" >&2
fi
```

This already aligns with the spec's `[ -t 0 ]` non-interactive gate; just confirm in plan that the gate is `&&`-ed with the auth-status check and that we never redirect `gh`'s output through `tee`.

### T11 — `eval`, command substitution in heredocs
- Audit of new constructs in spec:
  - No `eval` is proposed anywhere. Good.
  - Heredoc in `write_queue_gitignore()` uses `<< 'GITIGNORE'` (single-quoted delimiter) — disables interpolation. Existing pattern, plan should use the same form for the new `.zshrc` block:

```bash
# CORRECT — delimiter quoted, no interpolation:
cat >> "$HOME/.zshrc" << 'EOF'
# BEGIN MonsterFlow theme
source "REPO_DIR_PLACEHOLDER/config/zsh-prompt-colors.zsh"
# END MonsterFlow theme
EOF

# Then sed-substitute REPO_DIR_PLACEHOLDER. Or use << "EOF" + escape.
# WRONG — unquoted delimiter expands:
cat >> "$HOME/.zshrc" << EOF
source "$REPO_DIR/..."   # If $REPO_DIR has $(curl ...) embedded — RCE.
EOF
```

  - `$REPO_DIR` is computed via `cd "$(dirname "$0")" && pwd`. `pwd` is a builtin returning a real path, not an attacker-controlled string. Spec's hardened owner-detect uses `pwd -P` (resolves symlinks) — same property holds. **Safe to interpolate** `$REPO_DIR` in *quoted* contexts. Unsafe to inline-expand it in unquoted contexts (word-splitting on spaces).

### T12 — Test harness function-shadowing leakage
- Spec test strategy: `has_cmd() { return 1; }` defined in test before sourcing install.sh, mocking it to report tools missing. Risk: test sources install.sh into the same shell, the mock shadows the real `has_cmd` for the rest of that shell's lifetime. If the test then sources another script that depends on `has_cmd`, that script gets the mock.
- Mitigation: run each test in a subshell `(...)`. Subshell scope confines function-shadowing. The spec's test strategy already implies subshell isolation (`HOME=$(mktemp -d) bash tests/test-install.sh` runs the whole thing in a child process), but plan should explicitly require:

```bash
test_required_missing() {
    (
        export HOME="$(mktemp -d)"
        has_cmd() { return 1; }   # shadow lives only in this subshell
        export -f has_cmd          # children (install.sh) see the shadow
        bash "$REPO_DIR/install.sh" || rc=$?
        [ "${rc:-0}" = "1" ] || fail "expected exit 1"
    )
}
```

`export -f` is required for the bash child (`bash "$REPO_DIR/install.sh"`) to inherit the shadow; without it, the child reads the real PATH-augmenting `has_cmd`. Plan should pin this in the test contract.

## Key Considerations

1. **The persistence anchor is the `~/.zshrc` `source` line.** Every other mutation (symlinks under `~/.claude/`) is dormant until Claude Code reads them. The `.zshrc` line fires on every new shell. It deserves the strictest review discipline of any line install.sh writes.
2. **`MONSTERFLOW_OWNER=1` env override is convenient but dangerous.** It exists so agent-driven runs (autorun, /build) can deterministically claim owner identity without filesystem heuristics. But it also lets any process in the user's session flip privacy defaults. Plan should at minimum log the env-override path loudly: `if [ "${MONSTERFLOW_OWNER:-0}" = "1" ]; then echo "[security] owner mode forced via MONSTERFLOW_OWNER env var" >&2; fi`. Adopters seeing that line in unexpected contexts can investigate.
3. **`brew bundle install` confirm is the user's last consent gate.** They must see the resolved package list (formulas + casks + their dependencies) BEFORE confirming, not after. `brew bundle` itself doesn't print a dependency tree pre-install. Plan should call `brew bundle list --file=Brewfile` before the confirm prompt, parse the output, and show the user the actual install set.
4. **Repo location matters for trust.** A repo cloned to `/tmp/MonsterFlow` (world-writable parent) or `~/Downloads/MonsterFlow` is materially riskier than `~/Projects/MonsterFlow`. install.sh could refuse to run from `/tmp/*` or warn loudly. Adopter UX cost is real but security cost of arbitrary-location install is also real. Recommendation: warn (don't refuse) if `$REPO_DIR` is under `/tmp`, `/var/tmp`, or any path NOT owned by `$USER`.
5. **Compat-symlink discipline applies to `config/` files too.** If a future spec relocates `config/zsh-prompt-colors.zsh` to `themes/zsh-prompt-colors.zsh`, every running zsh session has cached the old path. Leave a symlink at the old path until the user opens a new shell. (Same rule the `feedback_settings_file_relocation.md` incident codified for `settings.json` paths.)
6. **PEM-in-`.zshrc` can't recur if we stay disciplined.** The 2026-04-20 incident wrote key material to a file that was then sourced as shell. Defense is the same here: NEVER write anything starting with `-----BEGIN` to `~/.zshrc` or any file appended to it. Theme files contain `setopt`, `PROMPT=...`, color escape codes — nothing more. Add a build-time grep gate.

## Options Explored

### Option A: Status quo (spec as-written, plan-time clarifications only)
- Pros: minimal plan churn; relies on code review at /build time to catch each issue.
- Cons: leaves `MONSTERFLOW_OWNER` env-override unaudited; SIGINT trap glob (`*.monsterflow.tmp`) is permissive; no repo-location trust check; no brew dependency-tree preview before confirm.
- Effort: 0 plan-side, ~2 hours review at /build.

### Option B: Hardened install.sh (recommended)
- Pros: closes T3 (env-override logged), T6 (SIGINT trap scoped to known files), T9 (`.zshrc` line quoted + content-grep CI check), T10 (`gh auth login` TTY-gated explicitly), T12 (test harness uses `export -f` in subshells).
- Cons: ~6 added lines in install.sh; one CI check; test contract gets stricter.
- Effort: ~3 hours at /build (spread across 4 stages).

### Option C: Sandboxed install (defense-in-depth, deferred)
- Run install.sh inside a restricted shell (`bash --restricted` or a chroot via `sudo systemd-run --scope --uid=$USER`). Drops privileges further, blocks PATH escapes.
- Pros: meaningful blast-radius reduction.
- Cons: install.sh genuinely needs to write to `~/.claude/`, `~/.zshrc`, run brew. Restricted bash blocks too much. Effort >> value.
- **Reject for this spec.** Revisit if MonsterFlow grows a "security-conscious adopter" segment.

### Option D: GPG-signed Brewfile + config files
- Verify `Brewfile`, `config/*` against a checked-in detached signature before install proceeds. Catches mid-install repo tampering on shared machines.
- Pros: defends T1 if repo is on a network mount.
- Cons: requires a signing key in CI; adopters mostly ignore signature warnings; brew itself doesn't sign casks. Doesn't compose with the trust model (we're already trusting the repo when we cloned it).
- **Reject for v1.** Too much process for a one-developer pipeline.

## Recommendation

**Adopt Option B.** Concrete hardening, per threat:

### Against T3 (malicious env vars)
- **Log the override:** when `MONSTERFLOW_OWNER=1` flips defaults, emit one stderr line: `[security] owner mode forced via MONSTERFLOW_OWNER env var`. Adopters can spot unexpected forced-owner runs in install logs.
- **Validate `$HOME`:** add at top of install.sh: `[ -d "$HOME" ] && [ "$(stat -f %u "$HOME")" = "$(id -u)" ] || { echo "HOME=$HOME is not owned by current user; refusing." >&2; exit 1; }`. macOS `stat -f %u` returns owner UID. Catches `HOME=/tmp/attacker` cases.
- **Don't trust env-derived booleans for security boundaries** beyond the override pattern already in spec. `--no-install` is a CLI flag (visible in process list); env vars aren't.

### Against T5 (symlink target swap, repo-location trust)
- **Warn on untrusted parent:** if `$REPO_DIR` is under `/tmp`, `/var/tmp`, or any directory not owned by `$USER`, print a warning before the brew confirm:

```bash
parent_owner="$(stat -f %u "$(dirname "$REPO_DIR")")"
if [ "$parent_owner" != "$(id -u)" ] || [[ "$REPO_DIR" == /tmp/* ]] || [[ "$REPO_DIR" == /var/tmp/* ]]; then
    echo "⚠ MonsterFlow repo is at $REPO_DIR — parent directory is not owned by you." >&2
    echo "  Symlinks installed by this script will point into that directory permanently." >&2
    echo "  Recommend cloning to ~/Projects/MonsterFlow instead." >&2
    if [ "$NON_INTERACTIVE" = "0" ]; then
        read -rp "  Proceed anyway? [y/N]: " UNTRUSTED_OK
        [[ "$UNTRUSTED_OK" =~ ^[Yy]$ ]] || exit 1
    fi
fi
```

### Against T6 (SIGINT trap deletes attacker-named files)
- **Scope the cleanup glob** to a single known directory, not a `find` across `$REPO_DIR` + `$CLAUDE_DIR`:

```bash
TMP_STATE_DIR="$(mktemp -d -t monsterflow-install.XXXXXX)"
trap 'rm -rf "$TMP_STATE_DIR" 2>/dev/null; echo "⚠ install.sh interrupted; partial state cleaned up." >&2; exit 130' INT TERM
```

All atomic file writes go to `$TMP_STATE_DIR/<name>`, then `mv` into final location at the end. Trap removes only `$TMP_STATE_DIR`. No glob across user-writable directories. No collision with attacker-pre-staged files.

### Against T9 (`.zshrc` append — the PEM-class bug)
- **Quote the source path** in the appended line (handles `$REPO_DIR` with spaces):

```bash
{
    echo ""
    echo "# BEGIN MonsterFlow theme"
    echo "# Auto-added by install.sh — remove the block (BEGIN..END) to uninstall."
    printf 'source %q\n' "$REPO_DIR/config/zsh-prompt-colors.zsh"
    echo "# END MonsterFlow theme"
} >> "$HOME/.zshrc"
```

`printf %q` is the safe quoter — produces a shell-reusable representation of the path even if it contains spaces, quotes, or shell metacharacters. Better than manual `echo "source \"$REPO_DIR/...\""`.
- **Add a CI grep gate** at `tests/test-config-content.sh`:

```bash
# Reject any network or eval primitive in shipped theme files
for f in config/*.zsh config/*.conf config/*.json; do
    if grep -qE '(curl|wget|nc |bash <\(|eval |source <\()' "$f"; then
        echo "FAIL: $f contains a network/eval primitive" >&2
        exit 1
    fi
done
```

Run from `tests/run-tests.sh`. Catches future drift if someone "innocently" adds a `curl` to the theme.

### Against T10 (`gh auth login` log leak)
- Gate `gh auth login` on `[ -t 1 ]` (stdout is a TTY) AND `[ -t 0 ]` (stdin is a TTY) before invoking. If install.sh's output is being captured (`./install.sh | tee install.log`), suppress the auth offer with a one-line stderr note. Spec already gates on `[ -t 0 ]`; add `[ -t 1 ]` to the same condition.
- Never `tee` or redirect `gh auth login`'s output. Let it own the terminal directly.

### Against T11 (heredoc interpolation discipline)
- All new heredocs use `<< 'EOF'` (quoted delimiter, no interpolation). Variables substituted post-write via `printf` or `sed -i ''` (macOS BSD sed requires the empty `''` arg).
- No `eval` anywhere in install.sh, onboard.sh, or the python-pip helper. CI gate: `grep -n '\beval\b' install.sh scripts/onboard.sh scripts/lib/python-pip.sh && exit 1 || true`.

### Against T12 (test harness shadow leakage)
- Each test case wraps in `(...)` subshell. `export -f has_cmd` inside the subshell so the bash child running install.sh inherits the shadow. Document the pattern in `tests/test-install.sh` header comment so future contributors don't break it.

### Against T2 (brew dependency-tree surprises)
- Before the brew confirm prompt, show resolved install set:

```bash
echo "About to install via Homebrew:"
brew bundle list --file="$REPO_DIR/Brewfile" | sed 's/^/  - /'
echo ""
echo "Plus any transitive dependencies brew resolves at install time."
read -rp "Proceed? [Y/n]: " BREW_OK
```

Doesn't fully prevent dependency surprises (brew resolves transitively at install time), but the user sees the *named* set we asked for. If a Brewfile commit adds something unexpected, they catch it here.

### Against T7 (version downgrade in migration message)
- Read the version dynamically: `VERSION="$(cat "$REPO_DIR/VERSION" | tr -d '[:space:]')"` (already done at line 9). Migration message uses `"Upgrading MonsterFlow to v$VERSION"` — never hardcoded. Spec's "v0.5.0" string moves into the VERSION file as the source of truth.

## Constraints Identified

- **Repo-location trust assumption must become explicit.** Spec implicitly assumes `$REPO_DIR` is under user control. The plan needs a one-liner warning when it isn't (T5 mitigation above). README install one-liner clones into `~/Projects/MonsterFlow` — keep that the canonical path.
- **`MONSTERFLOW_OWNER` env override is now a documented security-relevant flag.** Plan must add it to the flag-table in spec with a security note: "Forces owner-mode defaults regardless of filesystem location. Only set in agent-driven runs you trust."
- **`config/` files become part of the trusted shell-init chain** the moment install.sh adds the `source` line to `.zshrc`. They must remain auditable, network-call-free, and CI-gated against drift. Plan should add `tests/test-config-content.sh` to the test suite.
- **`gh auth login` requires TTY for both stdin AND stdout.** Spec's `[ -t 0 ]` gate is necessary but not sufficient. Add `[ -t 1 ]`.
- **Test harness contract:** every test case runs in a subshell with `export -f` for any function-shadow it installs. Mock leakage between cases is a test-correctness bug, not just a security bug.
- **No new `eval`. No new heredoc with unquoted delimiter. No new `read` without `-r`.** These are CI-enforceable.

## Open Questions

1. **Should install.sh refuse to run as root?** Currently it doesn't check. If a user `sudo ./install.sh`, the script writes symlinks into `/var/root/.claude/`, sources a path into `/var/root/.zshrc`, mutates `$HOME` for root not user. Recommend adding `[ "$EUID" -ne 0 ] || { echo "Do not run as root."; exit 1; }` at top. Adopters who want root MonsterFlow are an empty set.
2. **Should the warning on untrusted `$REPO_DIR` parent be a hard fail under `--non-interactive`?** Pro-fail: CI runners that clone to `/tmp/MonsterFlow` get loud; adopter has to explicitly opt in. Con-fail: breaks legitimate CI patterns. Recommend warn-only under `--non-interactive`, hard-prompt under interactive.
3. **Does the `.zshrc` block need a permission check?** If `~/.zshrc` is group-writable (`chmod g+w ~/.zshrc`), another user on the machine could append malicious lines that the user's next shell sources. We could refuse to append if `~/.zshrc` perms are looser than `644`. Practical?: most macOS `~/.zshrc` files are `644`; the check is cheap. Recommend: warn (don't refuse), tell the user to `chmod 644 ~/.zshrc`.
4. **Should `config/*.zsh` ship with a SHA256 checksum file** (`config/CHECKSUMS`) so adopters can verify post-clone? Effort low, value low (they're trusting the repo when they clone). Recommend: defer. Revisit if MonsterFlow ever ships a binary release.
5. **Can we attest that `brew bundle list` faithfully prints the install set BEFORE resolution?** Need to verify against actual `brew bundle` behavior at /plan time — I haven't run `brew bundle list --help` in this session. If `list` only shows what's already installed, we need a different command (maybe parse the Brewfile ourselves: `awk '/^(brew|cask)/ {print $2}' Brewfile`).
6. **Does the SIGINT trap fire on `kill -9`?** No — SIGKILL is uncatchable. So a process that gets `kill -9`'d mid-install leaves `$TMP_STATE_DIR` orphaned. Acceptable: `mktemp -d` puts it under `$TMPDIR` which macOS reaps eventually. Worth one line in the plan acknowledging this.

## Integration Points

- **with api (CLI flags / env vars):** The new `MONSTERFLOW_OWNER` env override needs documentation parity with the flag table (spec.md L295-304 already includes the row). Security recommendation: add a column "security-relevant: yes" to that row. The new `--non-interactive` flag must propagate to all sub-prompts uniformly — security boundary is "no interactive prompt fires when this flag set," and missing one prompt means a CI run hangs (denial-of-service against your own CI).
- **with data-model (state on disk):** The state-changes table (spec.md L317-323) is the security-relevant inventory. Plan should add a column "trust impact" to each row:
  - `~/.tmux.conf` symlink → reads at next tmux start (low impact, theme only)
  - `~/.config/cmux/cmux.json` symlink → reads at next cmux start (low impact, theme only)
  - **`~/.zshrc` append** → reads on EVERY shell start (HIGH impact, persistent shell-init)
  - `~/.claude/commands/*.md` symlinks → reads on next Claude Code session (medium impact)
  - `~/.local/bin/autorun` symlink → reads when user invokes `autorun` (medium impact)
  - `<adopter-project>/.gitignore` append → reads on every `git status`/`git add` (low impact for the file itself; high impact if MISSING — leaks `findings*.jsonl`)
- **with build (test contract):** Every threat above maps to a test or CI gate. Plan should add to `tests/run-tests.sh`:
  - `tests/test-config-content.sh` (CI grep gate against network/eval primitives in `config/*`)
  - `tests/test-install.sh` case 10: "untrusted repo parent triggers warning" — pre-stage `REPO_DIR=/tmp/test-monsterflow`, assert warning printed.
  - `tests/test-install.sh` case 11: "MONSTERFLOW_OWNER=1 logs to stderr" — set env var, assert `[security] owner mode forced` substring in stderr.
  - `tests/test-install.sh` case 12: "non-root only" — run as root (skipped on dev box; documented manual check).
- **with synthesis (judge dedup):** This security writeup overlaps with reliability (SIGINT trap design), data-model (`.zshrc` append shape), and api (env-var contract). Judge should merge the SIGINT trap discussion (T6) with reliability's SIGINT recommendation, and merge the `.zshrc` append shape (T9) with data-model's idempotency design. The owner-detect env override (T3) is mine; reliability and data-model don't touch it.
