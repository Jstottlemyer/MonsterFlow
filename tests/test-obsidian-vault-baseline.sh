#!/bin/bash
##############################################################################
# tests/test-obsidian-vault-baseline.sh
#
# Test harness for install-obsidian-vault-baseline feature in install.sh.
#
# Covers:
#   case_1  — empty vault → .scaffold-pending written
#   case_2  — non-empty user content → no marker
#   case_3  — cruft-only vault → marker written
#   case_4  — already-scaffolded vault → no marker
#   case_5  — stale-marker sweep on rerun
#   case_6  — read-only vault → INSTALL_WARNINGS, exit 0
#   case_7  — vault path with spaces → marker written correctly
#   case_8  — config exists but parse fails → silent return, no marker
#   case_9  — ~/CLAUDE.md append idempotency (sentinel appears exactly once)
#   case_10 — existing ~/CLAUDE.md content preserved
#   case_11 — missing ~/CLAUDE.md created with correct content
#   case_12 — predicate-drift guard (install.sh marker list matches CLAUDE.md instruction)
#
# Mocking model mirrors test-install-knowledge-layer.sh:
#   - PATH-prepended stub binaries in $STUB_DIR per case.
#   - MONSTERFLOW_HASCMD_OVERRIDE=$STUB_DIR forces has_cmd to check only STUB_DIR.
#   - MONSTERFLOW_INSTALL_TEST=1 short-circuits plugin/test prompts.
#   - HOME=$CASE_HOME — fully isolated; never touches dev machine.
#
# bash 3.2 compatible: no ${arr[-1]}, no declare -A, no export -f.
##############################################################################
set -euo pipefail

export BASH=/bin/bash

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
INSTALL_SH="$REPO_DIR/install.sh"

# Capture REAL_HOME before any test messes with $HOME.
REAL_HOME="$HOME"

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
CASE_HOME=""
CASE_OUT=""

##############################################################################
# Setup / teardown
##############################################################################
setup_test() {
    BATS_TMPDIR="$(mktemp -d -t monsterflow-vault-test.XXXXXX)"
    if [ -z "$BATS_TMPDIR" ] || [ ! -d "$BATS_TMPDIR" ]; then
        echo "FAIL setup_test: mktemp -d returned invalid path '$BATS_TMPDIR'" >&2
        exit 1
    fi
    STUB_DIR="$BATS_TMPDIR/stubs"
    STUB_LOG="$BATS_TMPDIR/stub.log"
    CASE_HOME="$BATS_TMPDIR/home"
    CASE_OUT="$BATS_TMPDIR/case.out"
    mkdir -p "$STUB_DIR" "$CASE_HOME"
    : > "$STUB_LOG"
    : > "$CASE_OUT"

    # Isolated HOME — install.sh writes here, never touches the dev machine.
    export HOME="$CASE_HOME"
    export MONSTERFLOW_APPLICATIONS_DIR="$CASE_HOME/Applications"

    mkdir -p "$HOME/.local/bin"

    # PATH stubs win over real binaries.
    export PATH="$STUB_DIR:$HOME/.local/bin:/usr/bin:/bin"

    # has_cmd hook: install.sh checks ONLY $STUB_DIR when this is set.
    export MONSTERFLOW_HASCMD_OVERRIDE="$STUB_DIR"

    # Defensive: isolate from inherited env that breaks tests on adopters' machines.
    unset PROJECT_DIR 2>/dev/null || true
    unset MONSTERFLOW_DISABLE_BUDGET 2>/dev/null || true
    unset MONSTERFLOW_OWNER 2>/dev/null || true
    unset OBSIDIAN_VAULT_PATH 2>/dev/null || true

    # Short-circuit recursive prompts (plugin install + test-suite-validate)
    export MONSTERFLOW_INSTALL_TEST=1
    export NON_INTERACTIVE=1
}

teardown_test() {
    [ -n "${BATS_TMPDIR:-}" ] && [ -d "$BATS_TMPDIR" ] && rm -rf "$BATS_TMPDIR"
}

##############################################################################
# Stub helpers
##############################################################################

# make_stub <name> [exit_code]
make_stub() {
    local name="$1" exit_code="${2:-0}"
    cat > "$STUB_DIR/$name" <<STUB
#!/bin/bash
echo "[\$\$] $name \$*" >> "$STUB_LOG"
exit $exit_code
STUB
    chmod +x "$STUB_DIR/$name"
}

# make_stub_python3 — minimal python3 stub sufficient for Knowledge Layer
make_stub_python3() {
    local slog="$STUB_LOG"
    cat > "$STUB_DIR/python3" <<STUBPY
#!/bin/bash
echo "[\$\$] python3 \$*" >> "$slog"
if [ "\$1" = "-c" ]; then
    case "\$2" in
        *version_info*) echo "3.11" ;;
        *) echo "" ;;
    esac
    exit 0
fi
if [ "\$1" = "-m" ] && [ "\$2" = "venv" ]; then
    VENV_PATH="\$3"
    mkdir -p "\$VENV_PATH/bin"
    printf '#!/bin/bash\necho "venv-python3 \$*"\nexit 0\n' > "\$VENV_PATH/bin/python3"
    chmod +x "\$VENV_PATH/bin/python3"
    printf '#!/bin/bash\nexit 0\n' > "\$VENV_PATH/bin/pip3"
    chmod +x "\$VENV_PATH/bin/pip3"
    exit 0
fi
exit 0
STUBPY
    chmod +x "$STUB_DIR/python3"
}

# make_stub_brew — minimal brew stub
make_stub_brew() {
    local slog="$STUB_LOG"
    cat > "$STUB_DIR/brew" <<STUBBREW
#!/bin/bash
echo "[\$\$] brew \$*" >> "$slog"
if [ "\$1" = "install" ] && [ "\$2" = "--cask" ] && [ "\$3" = "obsidian" ]; then
    APP_DIR="\${MONSTERFLOW_APPLICATIONS_DIR:-/Applications}/Obsidian.app/Contents/MacOS"
    mkdir -p "\$APP_DIR"
fi
exit 0
STUBBREW
    chmod +x "$STUB_DIR/brew"
}

# make_stub_graphify — minimal graphify stub
make_stub_graphify() {
    local slog="$STUB_LOG"
    cat > "$STUB_DIR/graphify" <<STUBGFY
#!/bin/bash
echo "[\$\$] graphify \$*" >> "$slog"
if [ "\$1" = "claude" ] && [ "\$2" = "install" ]; then
    SKILL_DIR="\$HOME/.claude/skills/graphify"
    mkdir -p "\$SKILL_DIR"
    echo "# graphify SKILL placeholder" > "\$SKILL_DIR/SKILL.md"
fi
exit 0
STUBGFY
    chmod +x "$STUB_DIR/graphify"
}

# make_stub_required — stage git, claude, python3, brew as present stubs
make_stub_required() {
    make_stub git
    make_stub claude
    make_stub_python3
    make_stub_brew
    make_stub_graphify
    make_stub npx
    make_stub gh
    make_stub shellcheck
    make_stub jq
    make_stub tmux
    make_stub flock
}

##############################################################################
# Stage helpers — pre-populate filesystem state
##############################################################################

# stage_obsidian_config <vault_dir> — write ~/.obsidian-wiki/config pointing at vault_dir
stage_obsidian_config() {
    local vault_dir="$1"
    mkdir -p "$HOME/.obsidian-wiki"
    printf 'OBSIDIAN_VAULT_PATH="%s"\n' "$vault_dir" > "$HOME/.obsidian-wiki/config"
    # Pre-stage .zshrc sentinel so zshrc append is idempotent
    local zshrc="$HOME/.zshrc"
    [ -f "$zshrc" ] || touch "$zshrc"
    printf '\n# BEGIN MonsterFlow obsidian-wiki\nexport OBSIDIAN_VAULT_PATH="%s"\n# END MonsterFlow obsidian-wiki\n' \
        "$vault_dir" >> "$zshrc"
}

# stage_empty_vault — vault dir exists but is empty
stage_empty_vault() {
    local vault_dir="$CASE_HOME/vault"
    mkdir -p "$vault_dir"
    echo "$vault_dir"
}

# stage_user_content_vault — vault has non-cruft content
stage_user_content_vault() {
    local vault_dir="$CASE_HOME/vault"
    mkdir -p "$vault_dir"
    echo "My notes" > "$vault_dir/notes.md"
    echo "$vault_dir"
}

# stage_cruft_only_vault — vault has only .DS_Store + .obsidian/
stage_cruft_only_vault() {
    local vault_dir="$CASE_HOME/vault"
    mkdir -p "$vault_dir"
    touch "$vault_dir/.DS_Store"
    mkdir -p "$vault_dir/.obsidian"
    echo "$vault_dir"
}

# stage_scaffolded_vault — vault has all 7 scaffold markers
stage_scaffolded_vault() {
    local vault_dir="$CASE_HOME/vault"
    mkdir -p "$vault_dir/concepts" "$vault_dir/entities" \
             "$vault_dir/_archives" "$vault_dir/_raw" \
             "$vault_dir/.obsidian"
    echo "# index" > "$vault_dir/index.md"
    echo "# log" > "$vault_dir/log.md"
    echo "$vault_dir"
}

# stage_stale_marker_vault — scaffolded vault + leftover .scaffold-pending
stage_stale_marker_vault() {
    local vault_dir
    vault_dir="$(stage_scaffolded_vault)"
    touch "$vault_dir/.scaffold-pending"
    echo "$vault_dir"
}

##############################################################################
# Assertion helpers
##############################################################################
assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then return 0; fi
    echo "ASSERT_EQ FAIL: $label" >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    return 1
}

assert_match() {
    local label="$1" pattern="$2" file="$3"
    if grep -qE "$pattern" "$file" 2>/dev/null; then return 0; fi
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
    if [ -e "$path" ]; then return 0; fi
    echo "ASSERT_FILE_EXISTS FAIL: $label" >&2
    echo "  path: $path" >&2
    return 1
}

assert_no_file() {
    local label="$1" path="$2"
    if [ ! -e "$path" ]; then return 0; fi
    echo "ASSERT_NO_FILE FAIL: $label" >&2
    echo "  path: $path (should not exist)" >&2
    return 1
}

assert_exit_code() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then return 0; fi
    echo "ASSERT_EXIT_CODE FAIL: $label" >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    return 1
}

##############################################################################
# Run wrapper — 45s watchdog
##############################################################################
INSTALL_RUN_TIMEOUT_DEFAULT=45

run_install() {
    local rc=0 pid watchdog_pid budget sentinel
    budget="${RUN_TIMEOUT:-$INSTALL_RUN_TIMEOUT_DEFAULT}"
    sentinel="$BATS_TMPDIR/run-install.timed-out.$$"
    rm -f "$sentinel"

    bash "$INSTALL_SH" "$@" >"$CASE_OUT" 2>&1 </dev/null &
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
        echo "*** TIMEOUT: install.sh exceeded ${budget}s budget ***" >> "$CASE_OUT"
        rc=124
        rm -f "$sentinel"
    fi

    echo "$rc"
}

##############################################################################
# Test cases
##############################################################################

# case_1: empty vault → .scaffold-pending written
case_1() {
    setup_test
    make_stub_required
    export MONSTERFLOW_OWNER=1   # owner mode: do_install=1 → install_obsidian_env runs
    local vault_dir
    vault_dir="$(stage_empty_vault)"
    export OBSIDIAN_VAULT_PATH="$vault_dir"
    local rc
    rc=$(run_install --non-interactive --no-onboard --no-theme)
    assert_exit_code "case_1 exit" "0" "$rc" || return 1
    assert_file_exists "case_1 marker written" "$vault_dir/.scaffold-pending" || return 1
    assert_match "case_1 WROTE line" "WROTE.*scaffold-pending" "$CASE_OUT" || return 1
    teardown_test
}

# case_2: non-empty user content → no marker
case_2() {
    setup_test
    make_stub_required
    export MONSTERFLOW_OWNER=1   # owner mode: install_obsidian_env runs
    local vault_dir
    vault_dir="$(stage_user_content_vault)"
    export OBSIDIAN_VAULT_PATH="$vault_dir"
    local rc
    rc=$(run_install --non-interactive --no-onboard --no-theme)
    assert_exit_code "case_2 exit" "0" "$rc" || return 1
    assert_no_file "case_2 no marker" "$vault_dir/.scaffold-pending" || return 1
    assert_file_exists "case_2 user content preserved" "$vault_dir/notes.md" || return 1
    teardown_test
}

# case_3: cruft-only vault → marker written
case_3() {
    setup_test
    make_stub_required
    export MONSTERFLOW_OWNER=1   # owner mode: install_obsidian_env runs
    local vault_dir
    vault_dir="$(stage_cruft_only_vault)"
    export OBSIDIAN_VAULT_PATH="$vault_dir"
    local rc
    rc=$(run_install --non-interactive --no-onboard --no-theme)
    assert_exit_code "case_3 exit" "0" "$rc" || return 1
    assert_file_exists "case_3 marker written" "$vault_dir/.scaffold-pending" || return 1
    assert_file_exists "case_3 DS_Store preserved" "$vault_dir/.DS_Store" || return 1
    teardown_test
}

# case_4: already-scaffolded vault → no marker written (cold first install)
case_4() {
    setup_test
    make_stub_required
    export MONSTERFLOW_OWNER=1   # owner mode: install_obsidian_env runs
    local vault_dir
    vault_dir="$(stage_scaffolded_vault)"
    export OBSIDIAN_VAULT_PATH="$vault_dir"
    local rc
    rc=$(run_install --non-interactive --no-onboard --no-theme)
    assert_exit_code "case_4 exit" "0" "$rc" || return 1
    assert_no_file "case_4 no marker on scaffolded vault" "$vault_dir/.scaffold-pending" || return 1
    assert_file_exists "case_4 scaffold content preserved: concepts" "$vault_dir/concepts" || return 1
    teardown_test
}

# case_5: stale-marker sweep on rerun
# Pre-stages config + scaffolded vault + leftover .scaffold-pending.
# Simulates a prior install.sh run where Claude failed to clean up the marker.
# No MONSTERFLOW_OWNER needed: config pre-staged → detect_obsidian_env="ready" →
# install_obsidian_env not called, but do_knowledge_layer unconditionally calls manage_scaffold_marker.
case_5() {
    setup_test
    make_stub_required
    local vault_dir
    vault_dir="$(stage_stale_marker_vault)"
    # Pre-stage config (simulates prior install.sh run)
    stage_obsidian_config "$vault_dir"
    local rc
    rc=$(run_install --non-interactive --no-onboard --no-theme)
    assert_exit_code "case_5 exit" "0" "$rc" || return 1
    assert_no_file "case_5 stale marker removed" "$vault_dir/.scaffold-pending" || return 1
    assert_file_exists "case_5 scaffold content preserved" "$vault_dir/concepts" || return 1
    assert_match "case_5 REMOVED line" "REMOVED.*scaffold-pending" "$CASE_OUT" || return 1
    teardown_test
}

# case_6: read-only vault → INSTALL_WARNINGS, exit 0
case_6() {
    # Skip if running as root (chmod 555 won't prevent root writes)
    if [ "$(id -u)" -eq 0 ]; then
        SUITE_SKIP=$(( SUITE_SKIP + 1 ))
        SKIPPED_CASES+=("case_6 (root)")
        return 0
    fi
    setup_test
    make_stub_required
    export MONSTERFLOW_OWNER=1   # owner mode: install_obsidian_env runs
    local vault_dir="$CASE_HOME/readonly-vault"
    mkdir -p "$vault_dir"
    chmod 555 "$vault_dir"
    export OBSIDIAN_VAULT_PATH="$vault_dir"
    local rc
    rc=$(run_install --non-interactive --no-onboard --no-theme)
    # Restore perms for teardown
    chmod 755 "$vault_dir"
    assert_exit_code "case_6 exit" "0" "$rc" || return 1
    assert_no_file "case_6 no marker on read-only vault" "$vault_dir/.scaffold-pending" || return 1
    assert_match "case_6 vault read-only warning" "(vault read-only|could not write)" "$CASE_OUT" || return 1
    teardown_test
}

# case_7: vault path with spaces → marker written correctly
case_7() {
    setup_test
    make_stub_required
    export MONSTERFLOW_OWNER=1   # owner mode: install_obsidian_env runs
    local vault_dir="$CASE_HOME/my vault with spaces"
    mkdir -p "$vault_dir"
    export OBSIDIAN_VAULT_PATH="$vault_dir"
    local rc
    rc=$(run_install --non-interactive --no-onboard --no-theme)
    assert_exit_code "case_7 exit" "0" "$rc" || return 1
    assert_file_exists "case_7 marker written with spaces in path" "$vault_dir/.scaffold-pending" || return 1
    teardown_test
}

# case_8: config exists but parse returns empty path → silent return, no marker
# Pre-stages config with empty OBSIDIAN_VAULT_PATH value.
case_8() {
    setup_test
    make_stub_required
    local vault_dir="$CASE_HOME/vault"
    mkdir -p "$vault_dir"
    # Write config with empty path value — parse_obsidian_config will return empty
    mkdir -p "$HOME/.obsidian-wiki"
    printf 'OBSIDIAN_VAULT_PATH=""\n' > "$HOME/.obsidian-wiki/config"
    # Pre-stage .zshrc sentinel so zshrc append is idempotent
    local zshrc="$HOME/.zshrc"
    touch "$zshrc"
    printf '\n# BEGIN MonsterFlow obsidian-wiki\nexport OBSIDIAN_VAULT_PATH=""\n# END MonsterFlow obsidian-wiki\n' >> "$zshrc"
    local rc
    rc=$(run_install --non-interactive --no-onboard --no-theme)
    assert_exit_code "case_8 exit" "0" "$rc" || return 1
    assert_no_file "case_8 no marker when parse returns empty" "$vault_dir/.scaffold-pending" || return 1
    teardown_test
}

# case_9: ~/CLAUDE.md append idempotency — sentinel appears exactly once after two runs
case_9() {
    setup_test
    make_stub_required
    export MONSTERFLOW_OWNER=1   # owner mode: install_obsidian_env runs → CLAUDE.md append fires
    local vault_dir
    vault_dir="$(stage_empty_vault)"
    export OBSIDIAN_VAULT_PATH="$vault_dir"
    # First run
    run_install --non-interactive --no-onboard --no-theme
    # Second run — idempotency check
    run_install --non-interactive --no-onboard --no-theme
    local claude_md="$HOME/CLAUDE.md"
    assert_file_exists "case_9 ~/CLAUDE.md exists" "$claude_md" || return 1
    local sentinel_count
    sentinel_count=$(grep -cF "BEGIN MonsterFlow wiki-preflight" "$claude_md" 2>/dev/null || echo "0")
    # Trim whitespace for bash 3.2 compat (tr -dc digits)
    sentinel_count=$(echo "$sentinel_count" | tr -dc '0-9')
    sentinel_count="${sentinel_count:-0}"
    if [ "$sentinel_count" -ne 1 ]; then
        echo "ASSERT FAIL case_9: sentinel count=$sentinel_count (expected 1)" >&2
        return 1
    fi
    teardown_test
}

# case_10: existing ~/CLAUDE.md content is preserved when appending
case_10() {
    setup_test
    make_stub_required
    export MONSTERFLOW_OWNER=1   # owner mode
    local vault_dir
    vault_dir="$(stage_empty_vault)"
    export OBSIDIAN_VAULT_PATH="$vault_dir"
    # Pre-populate ~/CLAUDE.md with user content
    local claude_md="$HOME/CLAUDE.md"
    printf '# My existing CLAUDE.md\n\nSome existing instructions.\n' > "$claude_md"
    local rc
    rc=$(run_install --non-interactive --no-onboard --no-theme)
    assert_exit_code "case_10 exit" "0" "$rc" || return 1
    assert_match "case_10 existing content preserved" "My existing CLAUDE.md" "$claude_md" || return 1
    assert_match "case_10 sentinel appended" "BEGIN MonsterFlow wiki-preflight" "$claude_md" || return 1
    assert_match "case_10 APPENDED line in output" "APPENDED.*CLAUDE" "$CASE_OUT" || return 1
    teardown_test
}

# case_11: missing ~/CLAUDE.md is created with correct content
case_11() {
    setup_test
    make_stub_required
    export MONSTERFLOW_OWNER=1   # owner mode
    local vault_dir
    vault_dir="$(stage_empty_vault)"
    export OBSIDIAN_VAULT_PATH="$vault_dir"
    local claude_md="$HOME/CLAUDE.md"
    # Ensure ~/CLAUDE.md does NOT exist before run
    rm -f "$claude_md"
    local rc
    rc=$(run_install --non-interactive --no-onboard --no-theme)
    assert_exit_code "case_11 exit" "0" "$rc" || return 1
    assert_file_exists "case_11 ~/CLAUDE.md created" "$claude_md" || return 1
    assert_match "case_11 sentinel present" "BEGIN MonsterFlow wiki-preflight" "$claude_md" || return 1
    assert_match "case_11 wiki-preflight content" "wiki-setup" "$claude_md" || return 1
    teardown_test
}

# case_12: predicate-drift guard — manage_scaffold_marker's for-loop list and
# CLAUDE.md instruction heredoc list both reference all 7 canonical markers.
case_12() {
    setup_test
    # Verify manage_scaffold_marker loop has all 7 canonical markers
    local found_all=1
    for m in concepts entities _archives _raw index.md log.md .obsidian; do
        if ! grep -qF "$m" "$INSTALL_SH"; then
            echo "ASSERT FAIL case_12: marker '$m' not found in install.sh" >&2
            found_all=0
        fi
    done
    if [ "$found_all" -ne 1 ]; then
        return 1
    fi

    # Verify the manage_scaffold_marker for-loop exists with the full list
    local loop_line
    loop_line=$(grep -n 'for m in concepts entities _archives' "$INSTALL_SH" | head -1)
    if [ -z "$loop_line" ]; then
        echo "ASSERT FAIL case_12: manage_scaffold_marker for-loop not found in install.sh" >&2
        return 1
    fi

    # Verify CLAUDE.md heredoc instruction references the same marker set
    local heredoc_line
    heredoc_line=$(grep -n 'concepts.*entities.*_archives.*_raw.*index\.md.*log\.md.*\.obsidian' "$INSTALL_SH" | head -1)
    if [ -z "$heredoc_line" ]; then
        echo "ASSERT FAIL case_12: CLAUDE.md instruction list not found in install.sh" >&2
        return 1
    fi

    teardown_test
}

##############################################################################
# Main — run all cases
##############################################################################

CASES=(
    case_1
    case_2
    case_3
    case_4
    case_5
    case_6
    case_7
    case_8
    case_9
    case_10
    case_11
    case_12
)

TOTAL=${#CASES[@]}
echo "=== test-obsidian-vault-baseline.sh — $TOTAL cases ==="
echo ""

for c in "${CASES[@]}"; do
    case_rc=0
    if (
        set +e
        $c
    ); then
        echo "[PASS] $c"
        SUITE_PASS=$(( SUITE_PASS + 1 ))
    else
        case_rc=$?
        echo "[FAIL] $c (rc=$case_rc)"
        SUITE_FAIL=$(( SUITE_FAIL + 1 ))
        FAILED_CASES+=("$c")
        if [ -f "$CASE_OUT" ] && [ -s "$CASE_OUT" ]; then
            echo "  --- install.sh tail (last 30 lines) ---" >&2
            tail -30 "$CASE_OUT" >&2 2>/dev/null || true
            echo "  --- end tail ---" >&2
        fi
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
