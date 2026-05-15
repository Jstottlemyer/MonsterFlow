#!/bin/bash
##############################################################################
# tests/test-install.sh
#
# End-to-end harness for install.sh + scripts/onboard.sh, covering the 12
# acceptance cases (1, 2, 3, 3a, 4, 5, 6a-e, 7a/b, 8, 9a-c) + 3 negatives
# (N1 unknown flag, N2 Linux guard, N3 brew-fail) from
# docs/specs/install-rewrite/spec.md + plan v1.2 W4.
#
# Mocking model (D11, B1 fix in plan v1.1):
#   - PATH-prepended stub binaries — function-shadow doesn't survive bash
#     subshells, install.sh redefines has_cmd at line ~155 anyway.
#   - MONSTERFLOW_HASCMD_OVERRIDE=$STUB_DIR forces install.sh's has_cmd to
#     check ONLY the stub dir (bypasses /opt/homebrew + /usr/local fallbacks).
#   - Stateful brew stub reads/writes $STUB_STATE so case 4 can simulate
#     `jq:missing → bundle install → jq:installed`.
#   - MONSTERFLOW_FORCE_INTERACTIVE=1 lets us pipe stdin without [ -t 0 ]
#     flipping us to non-interactive.
#   - MONSTERFLOW_INSTALL_TEST=1 short-circuits the recursive plugin/test
#     prompts so we don't fork-bomb.
#
# Each case runs in an isolated $HOME under $BATS_TMPDIR; on failure we
# print the last 20 lines of that case's output and bail with exit 1.
##############################################################################
set -euo pipefail

# Pin /bin/bash for bash 3.2 fidelity (S4 fix). Some macOS users have a
# newer bash via brew; install.sh's shebang is /bin/bash so we test the
# same interpreter the adopter sees.
export BASH=/bin/bash

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
INSTALL_SH="$REPO_DIR/install.sh"
ONBOARD_SH="$REPO_DIR/scripts/onboard.sh"

# Per-suite results
SUITE_PASS=0
SUITE_FAIL=0
SUITE_SKIP=0
FAILED_CASES=()
SKIPPED_CASES=()

# Per-case scratch — reset by setup_test()
BATS_TMPDIR=""
STUB_DIR=""
STUB_LOG=""
STUB_STATE=""
CASE_HOME=""
CASE_OUT=""

##############################################################################
# Setup / teardown
##############################################################################
setup_test() {
    BATS_TMPDIR="$(mktemp -d -t monsterflow-test.XXXXXX)"
    if [ -z "$BATS_TMPDIR" ] || [ ! -d "$BATS_TMPDIR" ]; then
        echo "FAIL setup_test: mktemp -d returned invalid path '$BATS_TMPDIR'" >&2
        exit 1
    fi
    STUB_DIR="$BATS_TMPDIR/stubs"
    STUB_LOG="$BATS_TMPDIR/stub.log"
    STUB_STATE="$BATS_TMPDIR/state"
    CASE_HOME="$BATS_TMPDIR/home"
    CASE_OUT="$BATS_TMPDIR/case.out"
    mkdir -p "$STUB_DIR" "$CASE_HOME"
    : > "$STUB_LOG"
    : > "$CASE_OUT"

    # Isolated HOME — install.sh writes here, never touches the dev machine.
    export HOME="$CASE_HOME"
    mkdir -p "$HOME/.local/bin"

    # PATH stubs win over real binaries; pre-include $HOME/.local/bin so the
    # PATH-sanity check at install.sh:197 doesn't add a phantom RECOMMENDED
    # entry (which would silently inject an extra brew "Proceed?" prompt).
    export PATH="$STUB_DIR:$HOME/.local/bin:$PATH"

    # has_cmd hook (D11): install.sh checks ONLY $STUB_DIR when this is set.
    export MONSTERFLOW_HASCMD_OVERRIDE="$STUB_DIR"

    # Short-circuit recursive prompts (plugin install + test-suite-validate)
    export MONSTERFLOW_INSTALL_TEST=1

    # Clear test-injected env so each case starts clean
    unset MONSTERFLOW_OWNER || true
    unset MONSTERFLOW_FORCE_INTERACTIVE || true
    unset MONSTERFLOW_NON_INTERACTIVE || true
    unset MONSTERFLOW_FORCE_ONBOARD || true
}

teardown_test() {
    # Best-effort cleanup; mktemp ensured uniqueness so rm is safe.
    [ -n "${BATS_TMPDIR:-}" ] && [ -d "$BATS_TMPDIR" ] && rm -rf "$BATS_TMPDIR"
}

##############################################################################
# Stub helpers
##############################################################################

# make_stub <name> [exit_code]
# Generates an executable at $STUB_DIR/<name> that records argv to $STUB_LOG
# and exits with the given code (default 0).
make_stub() {
    local name="$1" exit_code="${2:-0}"
    cat > "$STUB_DIR/$name" <<STUB
#!/bin/bash
echo "[\$\$] $name \$*" >> "$STUB_LOG"
exit $exit_code
STUB
    chmod +x "$STUB_DIR/$name"
}

# make_stateful_stub_brew
# Brew stub for case 4 (re-install jq) and case 3a (happy path):
# reads $STUB_STATE; on `bundle install` mutates `jq:missing` → `jq:installed`
# AND creates an executable jq stub in $STUB_DIR (so post-install re-detection
# via has_cmd succeeds). All other invocations are no-ops.
make_stateful_stub_brew() {
    local exit_code="${1:-0}"
    cat > "$STUB_DIR/brew" <<STUB
#!/bin/bash
echo "[\$\$] brew \$*" >> "$STUB_LOG"
# Match any invocation that has "bundle" as \$1 AND "install" anywhere in args.
# Real call shape: brew bundle --file=<path> install  (so \$2 is --file=…, not install)
ALL_ARGS="\$*"
if [ "\$1" = "bundle" ] && [[ "\$ALL_ARGS" == *install* ]]; then
    if [ -f "$STUB_STATE" ] && grep -q "jq:missing" "$STUB_STATE"; then
        sed -i.bak 's/jq:missing/jq:installed/' "$STUB_STATE"
        cat > "$STUB_DIR/jq" <<JQSTUB
#!/bin/bash
echo "[\\\$\\\$] jq \\\$*" >> "$STUB_LOG"
exit 0
JQSTUB
        chmod +x "$STUB_DIR/jq"
    fi
    exit $exit_code
fi
# All other invocations (deps, --version, etc.) succeed silently.
exit 0
STUB
    chmod +x "$STUB_DIR/brew"
}

# Pre-stage all REQUIRED tools as present.
stage_required_present() {
    make_stub git
    make_stub claude
    make_stub python3
    # python3 is special — install.sh runs `python3 -c '...'` for version check.
    cat > "$STUB_DIR/python3" <<'PYS'
#!/bin/bash
echo "[$$] python3 $*" >> "$STUB_LOG_PATH"
# Honour the version-check `python3 -c "import sys; print(...)"` invocation
if [ "$1" = "-c" ]; then
    case "$2" in
        *version_info*) echo "3.11" ;;
        *) echo "" ;;
    esac
fi
exit 0
PYS
    # Substitute STUB_LOG path into the stub (heredoc was 'PYS' quoted, so $STUB_LOG isn't expanded)
    sed -i.bak "s|\$STUB_LOG_PATH|$STUB_LOG|g" "$STUB_DIR/python3"
    rm -f "$STUB_DIR/python3.bak"
    chmod +x "$STUB_DIR/python3"
    make_stub brew
}

# Pre-stage all RECOMMENDED tools as present.
stage_recommended_present() {
    make_stub gh
    make_stub shellcheck
    make_stub jq
    make_stub tmux
    make_stub flock
}

# Pre-stage symlinks under $HOME/.claude as if a prior install ran.
# Used by case 1 (idempotency) and case 2 (fast no-op).
# </dev/null: force install.sh to non-interactive even when the test harness
# is run from a TTY (e.g., `./install.sh` triggering tests/run-tests.sh).
# Without it, the CLAUDE.md baseline prompt blocks on stdin forever.
stage_symlinks_present() {
    bash "$INSTALL_SH" </dev/null >/dev/null 2>&1 || true
}

##############################################################################
# Assertion helpers
##############################################################################
assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        return 0
    fi
    echo "ASSERT_EQ FAIL: $label" >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    return 1
}

assert_match() {
    local label="$1" pattern="$2" file="$3"
    if grep -qE "$pattern" "$file" 2>/dev/null; then
        return 0
    fi
    echo "ASSERT_MATCH FAIL: $label" >&2
    echo "  pattern: $pattern" >&2
    echo "  file:    $file" >&2
    echo "  --- last 20 lines ---" >&2
    tail -20 "$file" >&2 2>/dev/null || true
    return 1
}

assert_no_match() {
    local label="$1" pattern="$2" file="$3"
    if grep -qE "$pattern" "$file" 2>/dev/null; then
        echo "ASSERT_NO_MATCH FAIL: $label" >&2
        echo "  pattern (should be absent): $pattern" >&2
        echo "  file:                       $file" >&2
        echo "  --- matching lines ---" >&2
        grep -nE "$pattern" "$file" >&2 2>/dev/null || true
        return 1
    fi
    return 0
}

assert_file_exists() {
    local label="$1" path="$2"
    if [ -e "$path" ]; then
        return 0
    fi
    echo "ASSERT_FILE_EXISTS FAIL: $label" >&2
    echo "  path: $path" >&2
    return 1
}

assert_no_file() {
    local label="$1" path="$2"
    if [ ! -e "$path" ]; then
        return 0
    fi
    echo "ASSERT_NO_FILE FAIL: $label" >&2
    echo "  path:        $path (should not exist)" >&2
    return 1
}

assert_symlink() {
    local label="$1" path="$2"
    if [ -L "$path" ]; then
        return 0
    fi
    echo "ASSERT_SYMLINK FAIL: $label" >&2
    echo "  path: $path (should be a symlink)" >&2
    return 1
}

assert_not_symlink() {
    local label="$1" path="$2"
    if [ ! -L "$path" ]; then
        return 0
    fi
    echo "ASSERT_NOT_SYMLINK FAIL: $label" >&2
    echo "  path: $path (should NOT be a symlink)" >&2
    return 1
}

assert_exit_code() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        return 0
    fi
    echo "ASSERT_EXIT_CODE FAIL: $label" >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    return 1
}

##############################################################################
# Run wrapper — invokes install.sh, captures stdout+stderr+exit, never bails
##############################################################################
# Bound on a single install.sh invocation. Tests are not expected to need
# more than ~10s per run; anything past this is a hang we should surface
# clearly instead of waiting on. Override per-call by setting RUN_TIMEOUT
# before invoking run_install (e.g., RUN_TIMEOUT=60 run_install ...).
INSTALL_RUN_TIMEOUT_DEFAULT=30

run_install() {
    # Args are passed through to install.sh. Output goes to $CASE_OUT.
    # Watchdog: kill bash + its child sleep cleanly if budget is exceeded.
    # Detection uses a sentinel file (watchdog touches it BEFORE killing) so
    # we don't have to race against the watchdog's own kill follow-up.
    # On timeout returns rc=124 (standard `timeout` exit code) and appends a
    # marker line to $CASE_OUT so case-level failure dumps explain what happened.
    local rc=0 pid watchdog_pid budget sentinel
    budget="${RUN_TIMEOUT:-$INSTALL_RUN_TIMEOUT_DEFAULT}"
    sentinel="$BATS_TMPDIR/run-install.timed-out.$$"
    rm -f "$sentinel"

    # Explicit </dev/null on stdin: when the test suite is invoked from a TTY
    # (e.g., `./install.sh` triggering tests/run-tests.sh interactively),
    # install.sh's `[ -t 0 ]` autodetect would otherwise see the TTY and go
    # interactive, then block on the first read -rp (CLAUDE.md baseline,
    # plugin install, etc.). Tests that want interactive behavior use
    # run_install_with_input — bare run_install is always non-interactive.
    bash "$INSTALL_SH" "$@" >"$CASE_OUT" 2>&1 </dev/null &
    pid=$!
    ( sleep "$budget" ; touch "$sentinel" ; kill -TERM "$pid" 2>/dev/null ; sleep 1 ; kill -KILL "$pid" 2>/dev/null ) 2>/dev/null &
    watchdog_pid=$!
    disown "$watchdog_pid" 2>/dev/null || true

    wait "$pid" 2>/dev/null
    rc=$?

    # Kill the watchdog and its sleep child (avoids leaking the "sleep 1" tail).
    pkill -P "$watchdog_pid" 2>/dev/null
    kill "$watchdog_pid" 2>/dev/null
    wait "$watchdog_pid" 2>/dev/null

    if [ -f "$sentinel" ]; then
        echo "" >> "$CASE_OUT"
        echo "*** TIMEOUT: install.sh exceeded ${budget}s budget (killed by run_install watchdog) ***" >> "$CASE_OUT"
        rc=124
        rm -f "$sentinel"
    fi

    echo "$rc"
}

run_install_with_input() {
    # Pipe given input string into install.sh stdin. Forces interactive
    # mode unless the test explicitly wants non-interactive.
    # NOTE: input is fed via printf with %b so embedded \n is interpreted
    # as a real newline (otherwise `read -rp` blocks waiting for newline,
    # then errors out under set -e when stdin closes).
    #
    # DEFENSIVE PADDING: append 20 trailing newlines after the explicit input.
    # If install.sh hits more `read -rp` prompts than the test anticipated
    # (migration banner + brew prompt + CLAUDE.md baseline + ...), each
    # unexpected read consumes one empty line — which `[Y/n]` / `[y/N]`
    # patterns treat as "accept default" instead of blocking on a dry pipe.
    # The dry-pipe behavior on some macOS bash builds is to wait indefinitely
    # on the read syscall rather than return EOF, even though stdin should
    # be closed. Padding sidesteps the platform variance entirely.
    #
    # Same watchdog + sentinel semantics as run_install — see comments there.
    local input="$1"
    shift
    local rc=0 pid watchdog_pid budget sentinel
    budget="${RUN_TIMEOUT:-$INSTALL_RUN_TIMEOUT_DEFAULT}"
    sentinel="$BATS_TMPDIR/run-install-input.timed-out.$$"
    rm -f "$sentinel"

    # Pad with 20 trailing newlines (each = empty answer = accept-default
    # for any unexpected `[Y/n]` or `[y/N]` prompt).
    local padding=$'\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n'
    { printf '%b' "$input"; printf '%s' "$padding"; } | MONSTERFLOW_FORCE_INTERACTIVE=1 \
        bash "$INSTALL_SH" "$@" >"$CASE_OUT" 2>&1 &
    pid=$!
    ( sleep "$budget" ; touch "$sentinel" ; kill -TERM "$pid" 2>/dev/null ; sleep 1 ; kill -KILL "$pid" 2>/dev/null ) 2>/dev/null &
    watchdog_pid=$!
    disown "$watchdog_pid" 2>/dev/null || true

    wait "$pid" 2>/dev/null
    rc=$?

    pkill -P "$watchdog_pid" 2>/dev/null
    kill "$watchdog_pid" 2>/dev/null
    wait "$watchdog_pid" 2>/dev/null

    if [ -f "$sentinel" ]; then
        echo "" >> "$CASE_OUT"
        echo "*** TIMEOUT: install.sh exceeded ${budget}s budget (killed by run_install_with_input watchdog) ***" >> "$CASE_OUT"
        rc=124
        rm -f "$sentinel"
    fi

    echo "$rc"
}

##############################################################################
# Cases
##############################################################################

# Case 1 — Idempotency under repeat runs (state-based)
case_1() {
    setup_test
    stage_required_present
    stage_recommended_present
    export MONSTERFLOW_OWNER=0   # adopter mode → won't auto-install theme

    local rc1 rc2
    rc1=$(run_install --no-onboard --no-theme)
    assert_exit_code "first run exit 0" "0" "$rc1" || return 1

    rc2=$(run_install --no-onboard --no-theme)
    assert_exit_code "second run exit 0" "0" "$rc2" || return 1

    # No duplicate symlinks
    local dupes
    dupes=$(find "$HOME/.claude" -type l -exec readlink {} \; 2>/dev/null | sort | uniq -d)
    if [ -n "$dupes" ]; then
        echo "ASSERT FAIL: duplicate symlinks found" >&2
        echo "$dupes" >&2
        return 1
    fi

    # zsh sentinel block count = 0 (we passed --no-theme) — never 2+
    local sentinel_count=0
    if [ -f "$HOME/.zshrc" ]; then
        sentinel_count=$(grep -c '# BEGIN MonsterFlow theme' "$HOME/.zshrc" || true)
    fi
    if [ "$sentinel_count" -gt 1 ]; then
        echo "ASSERT FAIL: $sentinel_count sentinel blocks (must be 0 or 1)" >&2
        return 1
    fi

    assert_match "Installation complete in run output" "Installation complete" "$CASE_OUT" || return 1

    teardown_test
    return 0
}

# Case 2 — Fast no-op on fully-installed system (<3s)
case_2() {
    setup_test
    stage_required_present
    stage_recommended_present
    export MONSTERFLOW_OWNER=0

    # First run to stage symlinks (</dev/null: force non-interactive — see
    # stage_symlinks_present for rationale).
    bash "$INSTALL_SH" --no-onboard --no-theme </dev/null >/dev/null 2>&1 || true

    local start_ns end_ns elapsed_s
    if date +%s%N 2>/dev/null | grep -q 'N$'; then
        # macOS date doesn't support %N — fall back to whole seconds
        start_ns=$(date +%s)
        local rc
        rc=$(run_install --no-onboard --no-theme)
        end_ns=$(date +%s)
        elapsed_s=$(( end_ns - start_ns ))
    else
        start_ns=$(date +%s%N)
        local rc
        rc=$(run_install --no-onboard --no-theme)
        end_ns=$(date +%s%N)
        elapsed_s=$(( (end_ns - start_ns) / 1000000000 ))
    fi

    assert_exit_code "no-op exit 0" "0" "$rc" || return 1
    assert_match "Installation complete" "Installation complete" "$CASE_OUT" || return 1

    if [ "$elapsed_s" -gt 5 ]; then
        echo "ASSERT FAIL: no-op run took ${elapsed_s}s (budget <5s, target <3s)" >&2
        echo "  --- last 40 lines of install.sh output (where it spent time) ---" >&2
        tail -40 "$CASE_OUT" >&2 2>/dev/null || true
        echo "  --- end install.sh output ---" >&2
        return 1
    fi

    teardown_test
    return 0
}

# Case 3 — Fresh-Mac REQUIRED hard-stop
case_3() {
    setup_test
    # No stubs at all → has_cmd reports everything missing
    export MONSTERFLOW_OWNER=0

    local rc
    rc=$(run_install --no-onboard --no-theme)
    assert_exit_code "REQUIRED hard-stop exit 1" "1" "$rc" || return 1
    assert_match "REQUIRED panel" "REQUIRED" "$CASE_OUT" || return 1
    assert_match "brew install hint" "brew\\.sh|brew \\(Homebrew\\)" "$CASE_OUT" || return 1

    teardown_test
    return 0
}

# Case 3a — Fresh-Mac happy path (REQUIRED present, RECOMMENDED missing)
case_3a() {
    setup_test
    stage_required_present
    # RECOMMENDED missing — but use stateful brew so `bundle install` flips state
    echo "jq:missing" > "$STUB_STATE"
    make_stateful_stub_brew 0
    export MONSTERFLOW_OWNER=0

    local rc
    # Inputs: brew "Proceed?" → Y; CLAUDE.md baseline copy → Y (default)
    rc=$(run_install_with_input "Y\nY\n" --no-onboard --no-theme)
    assert_exit_code "happy path exit 0" "0" "$rc" || return 1

    # brew bundle invocation recorded
    assert_match "brew bundle invoked" "brew bundle" "$STUB_LOG" || return 1
    assert_match "Installation complete" "Installation complete" "$CASE_OUT" || return 1

    # Symlinks were created
    assert_file_exists "commands dir" "$HOME/.claude/commands" || return 1
    assert_symlink "spec.md symlinked" "$HOME/.claude/commands/spec.md" || return 1

    teardown_test
    return 0
}

# Case 4 — Re-install after `brew uninstall jq` (state diff empty)
case_4() {
    setup_test
    stage_required_present
    # All RECOMMENDED present except jq → brew bundle should flip jq:missing → jq:installed
    make_stub gh
    make_stub shellcheck
    make_stub tmux
    echo "jq:missing" > "$STUB_STATE"
    make_stateful_stub_brew 0
    export MONSTERFLOW_OWNER=0

    # Pre-stage symlinks (so the diff is well-defined)
    bash "$INSTALL_SH" --no-onboard --no-theme </dev/null >/dev/null 2>&1 || true
    local before_symlinks="$BATS_TMPDIR/before.txt"
    find "$HOME/.claude" -type l 2>/dev/null | sort > "$before_symlinks"

    # Now run with jq:missing
    local rc
    # Inputs: brew "Proceed?" → Y; CLAUDE.md baseline → Y
    rc=$(run_install_with_input "Y\nY\n" --no-onboard --no-theme)
    assert_exit_code "re-install exit 0" "0" "$rc" || return 1
    assert_match "brew bundle install invoked" "brew bundle.*install" "$STUB_LOG" || return 1

    local after_symlinks="$BATS_TMPDIR/after.txt"
    find "$HOME/.claude" -type l 2>/dev/null | sort > "$after_symlinks"
    if ! diff -q "$before_symlinks" "$after_symlinks" >/dev/null 2>&1; then
        echo "ASSERT FAIL: symlink graph diff non-empty" >&2
        diff "$before_symlinks" "$after_symlinks" >&2 || true
        return 1
    fi

    teardown_test
    return 0
}

# Case 5 — --no-install bypasses ALL enforcement
case_5() {
    setup_test
    # All REQUIRED missing
    export MONSTERFLOW_OWNER=0

    local rc
    rc=$(run_install --no-install --no-onboard --no-theme)
    assert_exit_code "--no-install exit 0" "0" "$rc" || return 1
    assert_no_match "no hard-stop message" "Install the REQUIRED tools above and re-run" "$CASE_OUT" || return 1

    # Symlinks still created
    assert_symlink "spec.md still linked" "$HOME/.claude/commands/spec.md" || return 1
    assert_match "Installation complete printed" "Installation complete" "$CASE_OUT" || return 1

    teardown_test
    return 0
}

# Case 6a — Owner: theme installed without prompt
case_6a() {
    setup_test
    stage_required_present
    stage_recommended_present
    export MONSTERFLOW_OWNER=1

    local rc
    rc=$(run_install --no-onboard)
    assert_exit_code "owner exit 0" "0" "$rc" || return 1

    assert_symlink "tmux.conf symlinked" "$HOME/.tmux.conf" || return 1
    assert_no_match "no theme prompt for owner" "Install MonsterFlow shell theme" "$CASE_OUT" || return 1

    teardown_test
    return 0
}

# Case 6b — Adopter: prompt-default-N (empty input → declined)
case_6b() {
    setup_test
    stage_required_present
    stage_recommended_present
    export MONSTERFLOW_OWNER=0

    local rc
    # Inputs: theme prompt → empty (default N); CLAUDE.md baseline → Y
    rc=$(run_install_with_input "\nY\n" --no-onboard)
    assert_exit_code "adopter exit 0" "0" "$rc" || return 1

    assert_no_file "tmux.conf NOT created" "$HOME/.tmux.conf" || return 1

    teardown_test
    return 0
}

# Case 6c — Adopter --install-theme: no prompt, theme installed
case_6c() {
    setup_test
    stage_required_present
    stage_recommended_present
    export MONSTERFLOW_OWNER=0

    local rc
    rc=$(run_install --no-onboard --install-theme)
    assert_exit_code "adopter --install-theme exit 0" "0" "$rc" || return 1
    assert_symlink "tmux.conf symlinked" "$HOME/.tmux.conf" || return 1
    assert_no_match "no prompt under --install-theme" "Install MonsterFlow shell theme" "$CASE_OUT" || return 1

    teardown_test
    return 0
}

# Case 6d — Existing real file backed up with timestamp
case_6d() {
    setup_test
    stage_required_present
    stage_recommended_present
    export MONSTERFLOW_OWNER=0

    # Pre-stage real file
    echo "original-content-marker" > "$HOME/.tmux.conf"

    local rc
    rc=$(run_install --no-onboard --install-theme)
    assert_exit_code "backup case exit 0" "0" "$rc" || return 1

    # Find any .bak.YYYYMMDDHHMMSS file
    local bak_file
    bak_file=$(find "$HOME" -maxdepth 1 -name '.tmux.conf.bak.*' -type f 2>/dev/null | head -1)
    if [ -z "$bak_file" ]; then
        echo "ASSERT FAIL: no .bak.YYYYMMDDHHMMSS file created" >&2
        ls -la "$HOME" >&2
        return 1
    fi

    if ! grep -q "original-content-marker" "$bak_file"; then
        echo "ASSERT FAIL: backup did not preserve original content" >&2
        cat "$bak_file" >&2
        return 1
    fi

    assert_symlink "tmux.conf is now a symlink" "$HOME/.tmux.conf" || return 1

    teardown_test
    return 0
}

# Case 6e — Already a symlink: ln -sf overwrites, NO .bak created
case_6e() {
    setup_test
    stage_required_present
    stage_recommended_present
    export MONSTERFLOW_OWNER=0

    # Pre-stage as symlink to a fixture
    local fixture="$BATS_TMPDIR/fake-tmux.conf"
    echo "# fake" > "$fixture"
    ln -s "$fixture" "$HOME/.tmux.conf"

    local rc
    rc=$(run_install --no-onboard --install-theme)
    assert_exit_code "symlink-overwrite exit 0" "0" "$rc" || return 1

    # No .bak.* must have been created
    local bak_file
    bak_file=$(find "$HOME" -maxdepth 1 -name '.tmux.conf.bak.*' 2>/dev/null | head -1)
    if [ -n "$bak_file" ]; then
        echo "ASSERT FAIL: existing-symlink case created backup $bak_file" >&2
        return 1
    fi

    assert_symlink "tmux.conf still symlink" "$HOME/.tmux.conf" || return 1

    teardown_test
    return 0
}

# Case 7a — onboard.sh under TTY: graphify offer fires (via expect)
case_7a() {
    setup_test
    if ! command -v expect >/dev/null 2>&1; then
        echo "  SKIP: expect not installed" >&2
        SUITE_SKIP=$(( SUITE_SKIP + 1 ))
        SKIPPED_CASES+=("7a (expect not installed)")
        teardown_test
        return 0
    fi

    # Pre-stage ~/Projects/test-proj/some.py so the offer-condition holds
    mkdir -p "$HOME/Projects/test-proj"
    : > "$HOME/Projects/test-proj/some.py"

    # bootstrap-graphify.sh must exist + be executable for the offer-block to fire
    if [ ! -x "$REPO_DIR/scripts/bootstrap-graphify.sh" ]; then
        echo "  SKIP: bootstrap-graphify.sh missing/not-executable" >&2
        SUITE_SKIP=$(( SUITE_SKIP + 1 ))
        SKIPPED_CASES+=("7a (bootstrap-graphify.sh not exec)")
        teardown_test
        return 0
    fi

    local exp_script="$REPO_DIR/tests/fixtures/expect/onboard-tty.exp"
    if [ ! -f "$exp_script" ]; then
        echo "ASSERT FAIL: expect fixture missing at $exp_script" >&2
        return 1
    fi

    local rc=0
    expect "$exp_script" "$REPO_DIR" >"$CASE_OUT" 2>&1 || rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "ASSERT FAIL: expect script exited $rc" >&2
        echo "  --- last 20 lines ---" >&2
        tail -20 "$CASE_OUT" >&2 || true
        return 1
    fi

    teardown_test
    return 0
}

# Case 7b — onboard.sh non-interactive: no graphify offer
case_7b() {
    setup_test
    mkdir -p "$HOME/Projects/test-proj"
    : > "$HOME/Projects/test-proj/some.py"

    local rc=0
    MONSTERFLOW_NON_INTERACTIVE=1 bash "$ONBOARD_SH" </dev/null >"$CASE_OUT" 2>&1 || rc=$?
    assert_exit_code "onboard non-interactive exit 0" "0" "$rc" || return 1

    local count
    count=$(grep -c "Index ~/Projects" "$CASE_OUT" || true)
    if [ "$count" -ne 0 ]; then
        echo "ASSERT FAIL: graphify offer fired under non-interactive (count=$count)" >&2
        return 1
    fi

    teardown_test
    return 0
}

# Case 8 — v0.4.x → v0.5.0 migration messaging
case_8() {
    setup_test
    stage_required_present
    stage_recommended_present
    export MONSTERFLOW_OWNER=0

    # Simulate prior install: spec.md symlink targeting */MonsterFlow/*
    mkdir -p "$BATS_TMPDIR/MonsterFlow"
    : > "$BATS_TMPDIR/MonsterFlow/spec.md"
    mkdir -p "$HOME/.claude/commands"
    ln -s "$BATS_TMPDIR/MonsterFlow/spec.md" "$HOME/.claude/commands/spec.md"

    local rc
    # Inputs: upgrade "Proceed?" → Y; CLAUDE.md baseline → Y
    rc=$(run_install_with_input "Y\nY\n" --no-onboard --no-theme)
    assert_exit_code "migration exit 0" "0" "$rc" || return 1
    assert_match "migration banner" "Detected prior MonsterFlow install" "$CASE_OUT" || return 1
    assert_match "What's new line" "What's new in v" "$CASE_OUT" || return 1

    teardown_test
    return 0
}

# Case 9a — TTY absent: no read -rp prompts in stdout
case_9a() {
    setup_test
    stage_required_present
    stage_recommended_present
    export MONSTERFLOW_OWNER=0

    local rc=0
    bash "$INSTALL_SH" --no-onboard </dev/null >"$CASE_OUT" 2>&1 || rc=$?
    assert_exit_code "TTY-absent exit 0" "0" "$rc" || return 1

    # No prompt strings should appear
    assert_no_match "no [Y/n] prompts" "\\[Y/n\\]" "$CASE_OUT" || return 1
    assert_no_match "no [y/N] prompts" "\\[y/N\\]" "$CASE_OUT" || return 1

    # Theme not installed (default-N applied silently)
    assert_no_file "no tmux.conf" "$HOME/.tmux.conf" || return 1

    teardown_test
    return 0
}

# Case 9b — --non-interactive flag with TTY: same as 9a
case_9b() {
    setup_test
    stage_required_present
    stage_recommended_present
    export MONSTERFLOW_OWNER=0

    local rc
    rc=$(run_install --non-interactive --no-onboard)
    assert_exit_code "--non-interactive exit 0" "0" "$rc" || return 1
    assert_no_match "no [Y/n] prompts" "\\[Y/n\\]" "$CASE_OUT" || return 1
    assert_no_match "no [y/N] prompts" "\\[y/N\\]" "$CASE_OUT" || return 1
    assert_no_file "no tmux.conf" "$HOME/.tmux.conf" || return 1

    teardown_test
    return 0
}

# Case 9c — --non-interactive --force-onboard: panel runs but no sub-prompts
case_9c() {
    setup_test
    stage_required_present
    stage_recommended_present
    export MONSTERFLOW_OWNER=0

    local rc
    rc=$(run_install --non-interactive --force-onboard)
    assert_exit_code "force-onboard exit 0" "0" "$rc" || return 1

    # Panel ran (signal: "MonsterFlow is ready" string from onboard.sh)
    assert_match "panel ran" "MonsterFlow is ready" "$CASE_OUT" || return 1
    # No sub-prompts (graphify offer must be silent)
    assert_no_match "no graphify prompt" "Index ~/Projects" "$CASE_OUT" || return 1

    teardown_test
    return 0
}

##############################################################################
# Negatives
##############################################################################

# N1 — Unknown flag → exit 2
case_N1() {
    setup_test

    local rc=0
    # </dev/null: defense-in-depth — bogus-flag exits before any read, but the
    # rule across this file is "no bare install.sh invocation that could see a TTY".
    bash "$INSTALL_SH" --bogus-flag </dev/null >"$CASE_OUT" 2>&1 || rc=$?
    assert_exit_code "unknown flag exit 2" "2" "$rc" || return 1
    assert_match "Unknown flag in stderr" "Unknown flag" "$CASE_OUT" || return 1

    teardown_test
    return 0
}

# N2 — Linux guard via PATH-stub uname (Codex re-pass: PATH stub, NOT function-shadow)
case_N2() {
    setup_test

    # Stub uname to echo "Linux"
    cat > "$STUB_DIR/uname" <<'STUB'
#!/bin/bash
echo "Linux"
exit 0
STUB
    chmod +x "$STUB_DIR/uname"

    local rc=0
    bash "$INSTALL_SH" --no-onboard >"$CASE_OUT" 2>&1 || rc=$?
    assert_exit_code "Linux guard exit 1" "1" "$rc" || return 1
    assert_match "macOS-only message" "macOS-only" "$CASE_OUT" || return 1

    teardown_test
    return 0
}

# N3 — brew bundle install fails → exit 1 with stderr message
case_N3() {
    setup_test
    stage_required_present
    # RECOMMENDED missing → triggers brew bundle install; stub returns 1
    echo "jq:missing" > "$STUB_STATE"
    make_stateful_stub_brew 1
    export MONSTERFLOW_OWNER=0

    local rc
    rc=$(run_install_with_input "Y\n" --no-onboard --no-theme)
    assert_exit_code "brew-fail exit 1" "1" "$rc" || return 1
    assert_match "brew bundle failed message" "brew bundle failed" "$CASE_OUT" || return 1

    teardown_test
    return 0
}

##############################################################################
# Runner
##############################################################################
CASES=(
    case_1
    case_2
    case_3
    case_3a
    case_4
    case_5
    case_6a
    case_6b
    case_6c
    case_6d
    case_6e
    case_7a
    case_7b
    case_8
    case_9a
    case_9b
    case_9c
    case_N1
    case_N2
    case_N3
)

TOTAL=${#CASES[@]}
echo "=== test-install.sh — $TOTAL cases ==="
echo ""

for c in "${CASES[@]}"; do
    # Run in a subshell so a teardown miss doesn't poison subsequent cases.
    case_rc=0
    if (
        set +e
        $c
    ); then
        echo "[PASS] $c"
        SUITE_PASS=$(( SUITE_PASS + 1 ))
    else
        case_rc=$?
        # SKIPPED cases return 0 but increment SUITE_SKIP inside the case.
        # Distinguish real failures: re-check by counting failures so far.
        echo "[FAIL] $c (rc=$case_rc)"
        SUITE_FAIL=$(( SUITE_FAIL + 1 ))
        FAILED_CASES+=("$c")
        # Dump install.sh output BEFORE teardown nukes $BATS_TMPDIR. Per-assertion
        # helpers (assert_match etc.) already dump locally; this catches cases
        # that fail via non-assert returns (timeout, unexpected exit).
        if [ -f "$CASE_OUT" ] && [ -s "$CASE_OUT" ]; then
            echo "  --- install.sh tail (last 40 lines) ---" >&2
            tail -40 "$CASE_OUT" >&2 2>/dev/null || true
            echo "  --- end tail ---" >&2
        fi
        # Best-effort cleanup so subsequent cases still get a fresh dir
        teardown_test 2>/dev/null || true
    fi
done

echo ""
echo "=========================================="
echo "Results: $SUITE_PASS passed, $SUITE_FAIL failed, $SUITE_SKIP skipped (of $TOTAL cases)"
if [ "${#FAILED_CASES[@]}" -gt 0 ]; then
    echo "Failed cases:"
    for c in "${FAILED_CASES[@]}"; do echo "  - $c"; done
fi
if [ "${#SKIPPED_CASES[@]}" -gt 0 ]; then
    echo "Skipped cases:"
    for c in "${SKIPPED_CASES[@]}"; do echo "  - $c"; done
fi

[ "$SUITE_FAIL" -eq 0 ] && exit 0 || exit 1
