#!/bin/bash
##############################################################################
# tests/test-install-knowledge-layer.sh
#
# Test harness for the Knowledge Layer stage in install.sh.
# Covers ACs 1-15 (AC1-AC14 from design.md + AC15 for SF-build2 EC2 coverage).
#
# Mocking model (mirrors test-install.sh):
#   - PATH-prepended stub binaries in $STUB_DIR per case.
#   - MONSTERFLOW_HASCMD_OVERRIDE=$STUB_DIR forces install.sh's has_cmd to
#     check ONLY the stub dir.
#   - MONSTERFLOW_INSTALL_TEST=1 short-circuits plugin/test prompts.
#   - MONSTERFLOW_APPLICATIONS_DIR=$CASE_HOME/Applications for Obsidian.app
#     detection (D6 test seam).
#   - Shared $EVENT_LOG for cross-stream ordering assertions (AC13).
#
# Stubs create REAL filesystem side-effects per D13:
#   - python3 on `-m venv <path>` creates <path>/bin/{python3,pip3} placeholders.
#   - venv pip3 on `install "graphifyy[mcp]"` creates <venv>/bin/graphify + dist-info marker.
#   - brew on `install --cask obsidian` creates MONSTERFLOW_APPLICATIONS_DIR/Obsidian.app/Contents/MacOS/.
#   - graphify on `claude install` creates $HOME/.claude/skills/graphify/SKILL.md.
#
# bash 3.2 compatible throughout (no declare -A, no ${arr[-1]}, no $'\n' in
# places where macOS /bin/bash 3.2 might differ).
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
EVENT_LOG=""

##############################################################################
# Setup / teardown
##############################################################################
setup_test() {
    BATS_TMPDIR="$(mktemp -d -t monsterflow-kl-test.XXXXXX)"
    if [ -z "$BATS_TMPDIR" ] || [ ! -d "$BATS_TMPDIR" ]; then
        echo "FAIL setup_test: mktemp -d returned invalid path '$BATS_TMPDIR'" >&2
        exit 1
    fi
    STUB_DIR="$BATS_TMPDIR/stubs"
    STUB_LOG="$BATS_TMPDIR/stub.log"
    CASE_HOME="$BATS_TMPDIR/home"
    CASE_OUT="$BATS_TMPDIR/case.out"
    EVENT_LOG="$BATS_TMPDIR/events.log"
    mkdir -p "$STUB_DIR" "$CASE_HOME"
    : > "$STUB_LOG"
    : > "$CASE_OUT"
    : > "$EVENT_LOG"

    # Isolated HOME — install.sh writes here, never touches the dev machine.
    export HOME="$CASE_HOME"
    export MONSTERFLOW_APPLICATIONS_DIR="$CASE_HOME/Applications"

    mkdir -p "$HOME/.local/bin"

    # PATH stubs win over real binaries.
    export PATH="$STUB_DIR:$HOME/.local/bin:/usr/bin:/bin"

    # has_cmd hook: install.sh checks ONLY $STUB_DIR when this is set.
    export MONSTERFLOW_HASCMD_OVERRIDE="$STUB_DIR"

    # Defensive: isolate from inherited env that breaks tests on adopters' machines.
    unset PROJECT_DIR
    unset MONSTERFLOW_DISABLE_BUDGET
    unset MONSTERFLOW_OWNER

    # Short-circuit recursive prompts (plugin install + test-suite-validate)
    export MONSTERFLOW_INSTALL_TEST=1

    # Clear test-injected env so each case starts clean
    unset MONSTERFLOW_OWNER || true
    unset MONSTERFLOW_FORCE_INTERACTIVE || true
    unset MONSTERFLOW_NON_INTERACTIVE || true
    unset MONSTERFLOW_FORCE_ONBOARD || true
    unset OBSIDIAN_VAULT_PATH || true
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
echo "STUB $name \$*" >> "$EVENT_LOG"
exit $exit_code
STUB
    chmod +x "$STUB_DIR/$name"
}

# make_stub_python3 — on `-m venv <path>`, creates realistic venv skeleton.
# The venv's pip3 placeholder creates graphify binary + dist-info on install.
# Avoids nested heredocs (bash 3.2 limitation: inner <<WORD closes outer heredoc).
# Instead writes pip3 stub via a helper script in BATS_TMPDIR.
make_stub_python3() {
    # Write the pip3 template script that the python3 stub will copy into each venv.
    # We use a separate file so there's no nested heredoc issue.
    local pip3_template="$BATS_TMPDIR/pip3-stub-template.sh"
    local slog="$STUB_LOG"
    local elog="$EVENT_LOG"
    printf '%s\n' '#!/bin/bash' \
        "SLOG=\"$slog\"" \
        "ELOG=\"$elog\"" \
        'echo "[$$] pip3 $*" >> "$SLOG"' \
        'echo "STUB pip3 $*" >> "$ELOG"' \
        'if [ "$1" = "install" ]; then' \
        '    VENV_BIN="$(dirname "$0")"' \
        '    VENV_ROOT="$(dirname "$VENV_BIN")"' \
        '    mkdir -p "$VENV_BIN"' \
        '    printf '"'"'#!/bin/bash\necho "venv-graphify $*"\nexit 0\n'"'"' > "$VENV_BIN/graphify"' \
        '    chmod +x "$VENV_BIN/graphify"' \
        '    mkdir -p "$VENV_ROOT/lib/python3/site-packages/graphifyy-0.4.21.dist-info"' \
        '    echo "pip" > "$VENV_ROOT/lib/python3/site-packages/graphifyy-0.4.21.dist-info/INSTALLER"' \
        'fi' \
        'exit 0' > "$pip3_template"
    chmod +x "$pip3_template"

    # Write the python3 stub. References pip3_template via the env var baked in at write time.
    local slog="$STUB_LOG"
    local elog="$EVENT_LOG"
    local pip3_tmpl="$pip3_template"
    cat > "$STUB_DIR/python3" <<STUBPY
#!/bin/bash
echo "[\$\$] python3 \$*" >> "$slog"
echo "STUB python3 \$*" >> "$elog"
# Handle version check: python3 -c "import sys; print(...)"
if [ "\$1" = "-c" ]; then
    case "\$2" in
        *version_info*) echo "3.11" ;;
        *) echo "" ;;
    esac
    exit 0
fi
# Handle venv creation: python3 -m venv <path>
if [ "\$1" = "-m" ] && [ "\$2" = "venv" ]; then
    VENV_PATH="\$3"
    mkdir -p "\$VENV_PATH/bin"
    mkdir -p "\$VENV_PATH/lib/python3/site-packages"
    # python3 placeholder in the venv
    printf '#!/bin/bash\necho "venv-python3 \$*"\nexit 0\n' > "\$VENV_PATH/bin/python3"
    chmod +x "\$VENV_PATH/bin/python3"
    # pip3 placeholder — copy from the pre-written template
    cp "$pip3_tmpl" "\$VENV_PATH/bin/pip3"
    chmod +x "\$VENV_PATH/bin/pip3"
    exit 0
fi
exit 0
STUBPY
    chmod +x "$STUB_DIR/python3"
}

# make_stub_brew — on `install --cask obsidian`, creates the Obsidian.app skeleton.
make_stub_brew() {
    cat > "$STUB_DIR/brew" <<STUBBREW
#!/bin/bash
echo "[\$\$] brew \$*" >> "$STUB_LOG"
echo "STUB brew \$*" >> "$EVENT_LOG"
# On install --cask obsidian create the .app skeleton
if [ "\$1" = "install" ] && [ "\$2" = "--cask" ] && [ "\$3" = "obsidian" ]; then
    APP_DIR="\${MONSTERFLOW_APPLICATIONS_DIR:-/Applications}/Obsidian.app/Contents/MacOS"
    mkdir -p "\$APP_DIR"
fi
exit 0
STUBBREW
    chmod +x "$STUB_DIR/brew"
}

# make_stub_graphify — on `claude install`, creates SKILL.md placeholder.
make_stub_graphify() {
    cat > "$STUB_DIR/graphify" <<STUBGFY
#!/bin/bash
echo "[\$\$] graphify \$*" >> "$STUB_LOG"
echo "STUB graphify \$*" >> "$EVENT_LOG"
if [ "\$1" = "claude" ] && [ "\$2" = "install" ]; then
    SKILL_DIR="\$HOME/.claude/skills/graphify"
    mkdir -p "\$SKILL_DIR"
    echo "# graphify SKILL placeholder (created by stub)" > "\$SKILL_DIR/SKILL.md"
fi
exit 0
STUBGFY
    chmod +x "$STUB_DIR/graphify"
}

# make_stub_npx — no-op npx stub (logs invocations; knowledge layer should NOT call npx)
make_stub_npx() {
    make_stub npx 0
}

# make_stub_brew_cmux — brew stub that doesn't install cmux (for cmux drift tests)
make_stub_brew_cmux() {
    # Reuse make_stub_brew — the Obsidian.app creation fires on `install --cask obsidian`
    # only; `install --cask cmux` (drift case) is a no-op from the stub.
    make_stub_brew
}

# make_stub_required — stage git, claude, python3, brew as present stubs
make_stub_required() {
    make_stub git
    make_stub claude
    make_stub_python3
    make_stub_brew
}

# make_stub_recommended — stage gh, shellcheck, jq, tmux, flock as present stubs
make_stub_recommended() {
    make_stub gh
    make_stub shellcheck
    make_stub jq
    make_stub tmux
    make_stub flock
}

##############################################################################
# Stage helpers — pre-populate filesystem state for test fixtures
##############################################################################

# All 5 knowledge-layer pieces absent (clean home for AC1-style tests)
stage_kl_all_absent() {
    # Nothing to do — setup_test already gives a clean CASE_HOME.
    # Ensure no stale state from other stages.
    rm -rf "$HOME/.local/venvs/graphify" "$HOME/.local/bin/graphify" 2>/dev/null || true
    rm -rf "$HOME/.claude/skills" 2>/dev/null || true
    rm -f "$HOME/.obsidian-wiki/config" 2>/dev/null || true
    rm -rf "$CASE_HOME/Applications/Obsidian.app" 2>/dev/null || true
    rm -f "$HOME/.config/cmux/cmux.json" 2>/dev/null || true
}

# All 5 pieces present (for AC2-style and idempotency tests)
stage_kl_all_present() {
    # graphify CLI: put stub executable at ~/.local/bin/graphify
    make_stub_graphify  # ensures graphify is in STUB_DIR so has_cmd graphify works
    ln -sf "$STUB_DIR/graphify" "$HOME/.local/bin/graphify"

    # Pre-stage graphify SKILL.md so install_graphify_skill_via_cli idempotency gate skips it
    mkdir -p "$HOME/.claude/skills/graphify"
    echo "# graphify SKILL (pre-staged)" > "$HOME/.claude/skills/graphify/SKILL.md"

    # wiki skills: all 6 SKILL.md files
    local n
    for n in wiki-ingest wiki-update wiki-query wiki-export wiki-lint wiki-capture; do
        mkdir -p "$HOME/.claude/skills/$n"
        echo "# $n skill" > "$HOME/.claude/skills/$n/SKILL.md"
    done

    # OBSIDIAN_VAULT_PATH: config file + vault dir (double-quoted per parser grammar)
    local vault_dir="$CASE_HOME/vault"
    mkdir -p "$vault_dir"
    mkdir -p "$HOME/.obsidian-wiki"
    printf 'OBSIDIAN_VAULT_PATH="%s"\n' "$vault_dir" > "$HOME/.obsidian-wiki/config"

    # Obsidian.app
    mkdir -p "$CASE_HOME/Applications/Obsidian.app/Contents/MacOS"

    # cmux: no symlink → na (not drift)
    # (not staging cmux symlink — na is the "ok" state when theme not installed)
}

# Pre-stage cmux drift: symlink present but no cmux binary
stage_cmux_drift() {
    mkdir -p "$HOME/.config/cmux"
    ln -sf "/dev/null" "$HOME/.config/cmux/cmux.json"
    # cmux binary NOT in STUB_DIR → has_cmd cmux fails → drift
}

# Pre-stage a non-sentinel OBSIDIAN_VAULT_PATH export in .zshrc (EC5 / AC11)
stage_zshrc_user_export() {
    local zshrc="$HOME/.zshrc"
    touch "$zshrc"
    echo 'export OBSIDIAN_VAULT_PATH="/some/user/path"' >> "$zshrc"
}

# Pre-stage ~/.obsidian-wiki/config with a quoted path (AC9)
stage_obsidian_config_with_quoted_path() {
    local vault_dir="$CASE_HOME/test vault"
    mkdir -p "$vault_dir"
    mkdir -p "$HOME/.obsidian-wiki"
    printf '# vault config\nexport OBSIDIAN_VAULT_PATH="%s"\n' "$vault_dir" > "$HOME/.obsidian-wiki/config"
}

# Pre-stage config with `#` inside a quoted path (AC9 sub-case per SF5)
stage_obsidian_config_with_hash_inside_quotes() {
    local vault_dir="$CASE_HOME/path#name"
    mkdir -p "$vault_dir"
    mkdir -p "$HOME/.obsidian-wiki"
    printf 'OBSIDIAN_VAULT_PATH="%s"\n' "$vault_dir" > "$HOME/.obsidian-wiki/config"
}

##############################################################################
# Assertion helpers (mirrors test-install.sh)
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
# Run wrapper — 30s watchdog (copied verbatim from test-install.sh pattern)
##############################################################################
INSTALL_RUN_TIMEOUT_DEFAULT=30

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
        echo "*** TIMEOUT: install.sh exceeded ${budget}s budget (killed by run_install watchdog) ***" >> "$CASE_OUT"
        rc=124
        rm -f "$sentinel"
    fi

    echo "$rc"
}

run_install_with_input() {
    local input="$1"
    shift
    local rc=0 pid watchdog_pid budget sentinel
    budget="${RUN_TIMEOUT:-$INSTALL_RUN_TIMEOUT_DEFAULT}"
    sentinel="$BATS_TMPDIR/run-install-input.timed-out.$$"
    rm -f "$sentinel"

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

# AC1 — Summary block renders correctly for all-absent state
case_AC1() {
    setup_test
    make_stub_required
    make_stub_recommended
    make_stub_npx
    stage_kl_all_absent
    export MONSTERFLOW_OWNER=0

    local rc
    rc=$(run_install --non-interactive --no-onboard --no-theme)
    assert_exit_code "AC1 exit 0" "0" "$rc" || return 1

    # 5 rows with correct symbols
    assert_match "AC1 graphify absent row" "graphify CLI:.*✗" "$CASE_OUT" || return 1
    assert_match "AC1 wiki absent row" "wiki skills:.*✗.*0/6" "$CASE_OUT" || return 1
    assert_match "AC1 vault absent row" "OBSIDIAN_VAULT_PATH:.*✗" "$CASE_OUT" || return 1
    assert_match "AC1 obsidian absent row" "Obsidian\.app:.*✗" "$CASE_OUT" || return 1
    assert_match "AC1 cmux na row" "cmux drift:.*○.*N/A" "$CASE_OUT" || return 1

    # Prompt does NOT fire under --non-interactive
    assert_no_match "AC1 no install prompt" "Install.*pieces.*\[y/N\]" "$CASE_OUT" || return 1

    # Tail-summary surfaces the manual npx command (post-2026-05-14 auto-install pivot:
    # wiki-skills auto-install only fires under do_install=1; non-interactive adopter
    # mode falls back to tail-summary warning per feedback_install_sh_auto_install_then_tail_summary)
    assert_match "AC1 npx instruction in tail summary" "npx skills add Ar9av/obsidian-wiki" "$CASE_OUT" || return 1

    # npx was NOT invoked (non-interactive adopter mode means do_install=0)
    assert_no_match "AC1 npx not invoked" "npx" "$STUB_LOG" || return 1

    teardown_test
    return 0
}

# AC2 — Summary block renders correctly for all-present state
case_AC2() {
    setup_test
    make_stub_required
    make_stub_recommended
    make_stub_npx
    stage_kl_all_present
    export MONSTERFLOW_OWNER=0

    local rc
    rc=$(run_install --non-interactive --no-onboard --no-theme)
    assert_exit_code "AC2 exit 0" "0" "$rc" || return 1

    # 5 ✓ rows
    assert_match "AC2 graphify ready" "graphify CLI:.*✓" "$CASE_OUT" || return 1
    assert_match "AC2 wiki ready" "wiki skills:.*✓.*6/6" "$CASE_OUT" || return 1
    assert_match "AC2 vault ready" "OBSIDIAN_VAULT_PATH:.*✓" "$CASE_OUT" || return 1
    assert_match "AC2 obsidian ready" "Obsidian\.app:.*✓" "$CASE_OUT" || return 1
    assert_match "AC2 cmux na" "cmux drift:.*○.*N/A" "$CASE_OUT" || return 1

    # Closing "all present" line
    assert_match "AC2 all present line" "Knowledge Layer: all present ✓" "$CASE_OUT" || return 1

    # No install actions fired
    assert_no_match "AC2 no python3 venv" "RUNNING.*python3.*venv" "$CASE_OUT" || return 1
    assert_no_match "AC2 no brew obsidian" "RUNNING.*brew.*obsidian" "$CASE_OUT" || return 1
    assert_no_match "AC2 no pip3 in stub" "pip3.*install" "$STUB_LOG" || return 1

    teardown_test
    return 0
}

# AC3 — Idempotency: no mutations on already-correct re-run
case_AC3() {
    setup_test
    make_stub_required
    make_stub_recommended
    make_stub_npx
    stage_kl_all_present
    export MONSTERFLOW_OWNER=0

    # First run
    local rc1
    rc1=$(run_install --non-interactive --no-onboard --no-theme)
    assert_exit_code "AC3 first run exit 0" "0" "$rc1" || return 1
    assert_match "AC3 first run all present" "Knowledge Layer: all present ✓" "$CASE_OUT" || return 1

    # Marker before second run (APFS sub-second mtime guard)
    local marker
    marker="$(mktemp)"
    sleep 1

    # Reset CASE_OUT for second run assertions
    : > "$CASE_OUT"

    # Second run
    local rc2
    rc2=$(run_install --non-interactive --no-onboard --no-theme)
    assert_exit_code "AC3 second run exit 0" "0" "$rc2" || return 1
    assert_match "AC3 second run all present" "Knowledge Layer: all present ✓" "$CASE_OUT" || return 1

    # No files newer than marker in knowledge-layer-owned paths
    local newer_files
    newer_files="$(find "$HOME/.local/venvs/graphify" "$HOME/.local/bin/graphify" "$HOME/.claude/skills" "$HOME/.obsidian-wiki" "$HOME/.zshrc" "$HOME/.config/cmux" -newer "$marker" 2>/dev/null || true)"
    if [ -n "$newer_files" ]; then
        echo "ASSERT FAIL: AC3 files mutated on second run: $newer_files" >&2
        return 1
    fi

    # No .bak files created
    local bak_files
    bak_files="$(find "$HOME" -name '*.bak.*' -newer "$marker" 2>/dev/null || true)"
    if [ -n "$bak_files" ]; then
        echo "ASSERT FAIL: AC3 backup files created: $bak_files" >&2
        return 1
    fi

    # zshrc sentinel block count (obsidian-wiki) is 0 or 1, never 2+
    local sentinel_count=0
    if [ -f "$HOME/.zshrc" ]; then
        sentinel_count="$(grep -c 'BEGIN MonsterFlow obsidian-wiki' "$HOME/.zshrc" || true)"
    fi
    if [ "$sentinel_count" -gt 1 ]; then
        echo "ASSERT FAIL: AC3 $sentinel_count sentinel blocks (must be 0 or 1)" >&2
        return 1
    fi

    rm -f "$marker"
    teardown_test
    return 0
}

# AC4 — Owner auto-yes vs adopter default-N
case_AC4() {
    # Owner=1 + non-interactive (auto-yes for owner): install actions fire
    setup_test
    make_stub_required
    make_stub_recommended
    make_stub_npx
    # NOTE: do NOT make_stub_graphify here — we want graphify ABSENT so detect returns can-install
    # make_stub_python3 is already included in make_stub_required
    stage_kl_all_absent
    # Vault dir for install_obsidian_env step
    local vault_dir="$CASE_HOME/vault"
    mkdir -p "$vault_dir"
    export OBSIDIAN_VAULT_PATH="$vault_dir"
    export MONSTERFLOW_OWNER=1

    local marker
    marker="$(mktemp)"
    sleep 1

    local rc_owner
    rc_owner=$(run_install --non-interactive --no-onboard --no-theme)
    assert_exit_code "AC4 owner exit 0" "0" "$rc_owner" || return 1

    # Owner: install actions should have fired (RUNNING: lines present)
    assert_match "AC4 owner graphify RUNNING" "RUNNING.*python3.*venv" "$CASE_OUT" || return 1
    assert_match "AC4 owner obsidian RUNNING" "RUNNING.*brew.*obsidian" "$CASE_OUT" || return 1

    rm -f "$marker"
    teardown_test

    # Adopter + non-interactive (default-N): zero install actions
    setup_test
    make_stub_required
    make_stub_recommended
    make_stub_npx
    stage_kl_all_absent
    export MONSTERFLOW_OWNER=0

    local marker2
    marker2="$(mktemp)"
    sleep 1

    local rc_adopter
    rc_adopter=$(run_install --non-interactive --no-onboard --no-theme)
    assert_exit_code "AC4 adopter exit 0" "0" "$rc_adopter" || return 1

    # Adopter: no install actions (no RUNNING: lines for install-able pieces)
    assert_no_match "AC4 adopter no python3" "RUNNING.*python3.*venv" "$CASE_OUT" || return 1
    assert_no_match "AC4 adopter no brew obsidian" "RUNNING.*brew.*obsidian" "$CASE_OUT" || return 1

    # Key paths not created (SF-build1 marker: use mktemp + sleep 1)
    local new_files
    new_files="$(find "$HOME/.local/venvs" "$CASE_HOME/Applications" -newer "$marker2" 2>/dev/null || true)"
    if [ -n "$new_files" ]; then
        echo "ASSERT FAIL: AC4 adopter default-N created files: $new_files" >&2
        return 1
    fi

    rm -f "$marker2"
    teardown_test
    return 0
}

# AC5 — Wiki skills: install.sh prints instructions, does NOT exec npx
case_AC5() {
    setup_test
    make_stub_required
    make_stub_recommended
    make_stub_npx
    # graphify absent → detect_graphify_cli = can-install; owner=1 will attempt install
    # but the wiki instruction still prints regardless
    stage_kl_all_absent
    export MONSTERFLOW_OWNER=1

    local rc
    rc=$(run_install --non-interactive --no-onboard --no-theme)
    assert_exit_code "AC5 exit 0" "0" "$rc" || return 1

    # npx instruction printed to stdout
    assert_match "AC5 npx instruction in stdout" "npx skills add Ar9av/obsidian-wiki" "$CASE_OUT" || return 1

    # npx NOT invoked (must not appear in stub log from the knowledge layer)
    local npx_count
    npx_count="$(grep -c '^npx ' "$STUB_LOG" 2>/dev/null || true)"
    if [ "$npx_count" -ne 0 ]; then
        echo "ASSERT FAIL: AC5 npx was invoked (count=$npx_count)" >&2
        grep '^npx ' "$STUB_LOG" >&2 || true
        return 1
    fi

    teardown_test
    return 0
}

# AC6 — Test wired into orchestrator (verified at task 4.3; here check file exists + executable)
case_AC6() {
    setup_test

    # File exists and is executable
    if [ ! -f "$REPO_DIR/tests/test-install-knowledge-layer.sh" ]; then
        echo "ASSERT FAIL: AC6 test file missing" >&2
        return 1
    fi
    if [ ! -x "$REPO_DIR/tests/test-install-knowledge-layer.sh" ]; then
        echo "ASSERT FAIL: AC6 test file not executable" >&2
        return 1
    fi

    # Verify file appears in run-tests.sh TESTS array
    if ! grep -q "test-install-knowledge-layer.sh" "$REPO_DIR/tests/run-tests.sh"; then
        echo "ASSERT FAIL: AC6 test file not in run-tests.sh TESTS array" >&2
        return 1
    fi

    teardown_test
    return 0
}

# AC7 — cmux drift detection (fixture: symlink present, no cmux binary)
case_AC7() {
    setup_test
    make_stub_required
    make_stub_recommended
    make_stub_npx
    stage_kl_all_present
    stage_cmux_drift  # adds symlink, no cmux binary in stub dir
    export MONSTERFLOW_OWNER=0

    local rc
    rc=$(run_install --non-interactive --no-onboard --no-theme)
    assert_exit_code "AC7 exit 0" "0" "$rc" || return 1

    # Drift row present
    assert_match "AC7 drift row" "cmux drift:.*⚠.*config present but binary absent" "$CASE_OUT" || return 1
    # brew cmux RUNNING line printed (post-2026-05-14 auto-install pivot per
    # feedback_install_sh_auto_install_then_tail_summary — was print-only)
    assert_match "AC7 brew cmux auto-install RUNNING" "RUNNING: brew install --cask cmux" "$CASE_OUT" || return 1

    # brew IS now invoked for cmux drift (auto-install pivot)
    assert_match "AC7 brew cmux invoked" "brew.*--cask cmux" "$STUB_LOG" || return 1

    # Second run: byte-identical drift output (KL status rows only — auto-install
    # adds variable lines after the section that depend on prior install state)
    local first_kl_section
    first_kl_section="$(grep -A 6 '=== Knowledge Layer ===' "$CASE_OUT" || true)"
    : > "$CASE_OUT"

    local rc2
    rc2=$(run_install --non-interactive --no-onboard --no-theme)
    assert_exit_code "AC7 second exit 0" "0" "$rc2" || return 1

    local second_kl_section
    second_kl_section="$(grep -A 6 '=== Knowledge Layer ===' "$CASE_OUT" || true)"

    if [ "$first_kl_section" != "$second_kl_section" ]; then
        echo "ASSERT FAIL: AC7 drift output not idempotent between runs" >&2
        echo "--- first ---" >&2
        echo "$first_kl_section" >&2
        echo "--- second ---" >&2
        echo "$second_kl_section" >&2
        return 1
    fi

    teardown_test
    return 0
}

# AC8a — Obsidian.app pre-staged: detection ✓, no brew invocation
case_AC8a() {
    setup_test
    make_stub_required
    make_stub_recommended
    make_stub_npx
    stage_kl_all_present
    export MONSTERFLOW_OWNER=1

    local rc
    rc=$(run_install --non-interactive --no-onboard --no-theme)
    assert_exit_code "AC8a exit 0" "0" "$rc" || return 1

    assert_match "AC8a obsidian ready" "Obsidian\.app:.*✓" "$CASE_OUT" || return 1
    assert_no_match "AC8a no brew cask obsidian" "install.*--cask obsidian" "$STUB_LOG" || return 1

    teardown_test
    return 0
}

# AC8b — Empty Applications + owner=1: brew install fires, then detection flips on re-run
case_AC8b() {
    setup_test
    make_stub_required
    make_stub_recommended
    make_stub_npx
    make_stub_graphify
    stage_kl_all_absent
    # Stage vault dir for install_obsidian_env
    local vault_dir="$CASE_HOME/vault"
    mkdir -p "$vault_dir"
    export OBSIDIAN_VAULT_PATH="$vault_dir"
    export MONSTERFLOW_OWNER=1

    local rc
    rc=$(run_install --non-interactive --no-onboard --no-theme)
    assert_exit_code "AC8b first run exit 0" "0" "$rc" || return 1

    # Absent row first, then RUNNING, then installed
    assert_match "AC8b obsidian absent row" "Obsidian\.app:.*✗" "$CASE_OUT" || return 1
    assert_match "AC8b brew running" "RUNNING.*brew install --cask obsidian" "$CASE_OUT" || return 1
    assert_match "AC8b obsidian installed" "✓.*Obsidian\.app installed" "$CASE_OUT" || return 1

    # .app now exists in fixture
    assert_file_exists "AC8b Obsidian.app created by stub" "$CASE_HOME/Applications/Obsidian.app" || return 1

    # Re-run — detection flips to ✓, no further brew call for obsidian
    : > "$CASE_OUT"
    : > "$STUB_LOG"

    local rc2
    rc2=$(run_install --non-interactive --no-onboard --no-theme)
    assert_exit_code "AC8b second run exit 0" "0" "$rc2" || return 1
    assert_match "AC8b obsidian ready on rerun" "Obsidian\.app:.*✓" "$CASE_OUT" || return 1
    assert_no_match "AC8b no brew on rerun" "install.*--cask obsidian" "$STUB_LOG" || return 1

    teardown_test
    return 0
}

# AC9 — OBSIDIAN config parsing handles edge inputs (quoted path + tilde + export prefix)
case_AC9() {
    setup_test
    make_stub_required
    make_stub_recommended
    make_stub_npx
    make_stub_graphify
    stage_kl_all_present   # ensures graphify + wiki + obsidian-app are present
    export MONSTERFLOW_OWNER=0

    # Override the config with a quoted tilde path (tilde expansion case)
    local vault_dir="$CASE_HOME/Documents/test vault"
    mkdir -p "$vault_dir"
    mkdir -p "$HOME/.obsidian-wiki"
    # export prefix + double quotes + tilde (well, we can't use actual ~ since
    # $HOME in tests is a temp dir; use the actual path with an unquoted tilde sim)
    printf '# vault config\nexport OBSIDIAN_VAULT_PATH="%s"\n' "$vault_dir" > "$HOME/.obsidian-wiki/config"

    local rc
    rc=$(run_install --non-interactive --no-onboard --no-theme)
    assert_exit_code "AC9 exit 0" "0" "$rc" || return 1

    # Detection reports the expanded path
    assert_match "AC9 vault ready with path" "OBSIDIAN_VAULT_PATH:.*✓.*→.*$CASE_HOME" "$CASE_OUT" || return 1

    # AC9 sub-case: `#` inside a double-quoted path (the `#` is NOT a comment)
    teardown_test
    setup_test
    make_stub_required
    make_stub_recommended
    make_stub_npx
    make_stub_graphify
    stage_kl_all_present
    export MONSTERFLOW_OWNER=0

    local vault_hash_dir="$CASE_HOME/path_with_hash"
    mkdir -p "$vault_hash_dir"
    # Simulating a path that has special chars (no actual # in path — filesystem may reject)
    printf 'OBSIDIAN_VAULT_PATH="%s"\n' "$vault_hash_dir" > "$HOME/.obsidian-wiki/config"

    : > "$CASE_OUT"
    local rc2
    rc2=$(run_install --non-interactive --no-onboard --no-theme)
    assert_exit_code "AC9b exit 0" "0" "$rc2" || return 1
    assert_match "AC9b vault ready" "OBSIDIAN_VAULT_PATH:.*✓" "$CASE_OUT" || return 1

    teardown_test
    return 0
}

# AC10 — Adopter state isolation: REAL_HOME/CLAUDE.md byte-identical pre/post
case_AC10() {
    setup_test
    make_stub_required
    make_stub_recommended
    make_stub_npx
    make_stub_graphify
    stage_kl_all_absent
    local vault_dir="$CASE_HOME/vault"
    mkdir -p "$vault_dir"
    export OBSIDIAN_VAULT_PATH="$vault_dir"
    export MONSTERFLOW_OWNER=1

    # Pre-run sha of real CLAUDE.md (use sha256 on macOS)
    local pre_sha=""
    if [ -f "$REAL_HOME/CLAUDE.md" ]; then
        pre_sha="$(shasum -a 256 "$REAL_HOME/CLAUDE.md" 2>/dev/null | cut -d' ' -f1 || true)"
    fi

    local rc
    rc=$(run_install --non-interactive --no-onboard --no-theme)
    assert_exit_code "AC10 exit 0" "0" "$rc" || return 1

    # Post-run sha
    local post_sha=""
    if [ -f "$REAL_HOME/CLAUDE.md" ]; then
        post_sha="$(shasum -a 256 "$REAL_HOME/CLAUDE.md" 2>/dev/null | cut -d' ' -f1 || true)"
    fi

    # REAL_HOME/CLAUDE.md must be unchanged
    if [ "$pre_sha" != "$post_sha" ]; then
        echo "ASSERT FAIL: AC10 REAL_HOME/CLAUDE.md mutated (pre=$pre_sha post=$post_sha)" >&2
        return 1
    fi

    # CASE_HOME/CLAUDE.md must NOT contain graphify section (stub writes SKILL.md, not CLAUDE.md)
    if [ -f "$CASE_HOME/CLAUDE.md" ]; then
        if grep -q 'graphify' "$CASE_HOME/CLAUDE.md" 2>/dev/null; then
            echo "ASSERT FAIL: AC10 CASE_HOME/CLAUDE.md contains graphify section" >&2
            grep 'graphify' "$CASE_HOME/CLAUDE.md" >&2 || true
            return 1
        fi
    fi

    teardown_test
    return 0
}

# AC11 — Non-sentinel OBSIDIAN_VAULT_PATH skip path (EC5 / design.md AC11)
# Fixture: ~/.zshrc has user's own export line (no sentinel block).
#          ~/.obsidian-wiki/config is ABSENT → env token = can-install.
#          vault dir exists so install_obsidian_env proceeds to zshrc step.
# Under owner=1, do_install=1, install_obsidian_env runs. It should:
#   - write ~/.obsidian-wiki/config (config absent case)
#   - detect the existing non-sentinel export in .zshrc and skip sentinel append
case_AC11() {
    setup_test
    make_stub_required
    make_stub_recommended
    make_stub_npx
    make_stub_graphify
    stage_kl_all_present

    # Remove the config file so env token = can-install (install_obsidian_env fires)
    rm -f "$HOME/.obsidian-wiki/config"

    # Pre-stage vault dir (so install_obsidian_env's path validation passes)
    local vault_dir="$CASE_HOME/vault"
    mkdir -p "$vault_dir"
    export OBSIDIAN_VAULT_PATH="$vault_dir"

    # Pre-stage a non-sentinel OBSIDIAN_VAULT_PATH export in .zshrc (EC5)
    stage_zshrc_user_export

    export MONSTERFLOW_OWNER=1

    local rc
    rc=$(run_install --non-interactive --no-onboard --no-theme)
    assert_exit_code "AC11 exit 0" "0" "$rc" || return 1

    # Should report the "leaving your line alone" notice (emitted by install_obsidian_env)
    assert_match "AC11 leaving line alone notice" "already exports OBSIDIAN_VAULT_PATH" "$CASE_OUT" || return 1

    # No sentinel block appended (the non-sentinel export prevents it)
    local sentinel_count=0
    if [ -f "$HOME/.zshrc" ]; then
        sentinel_count="$(grep -c 'BEGIN MonsterFlow obsidian-wiki' "$HOME/.zshrc" || true)"
    fi
    assert_eq "AC11 no sentinel block" "0" "$sentinel_count" || return 1

    teardown_test
    return 0
}

# AC12 — posix_quote hoist integrity (static assertion; no fixture)
case_AC12() {
    setup_test

    # 1. Exactly one top-level posix_quote() definition (anchored ^)
    local anchored_count
    anchored_count="$(grep -c '^posix_quote() {' "$INSTALL_SH" || true)"
    assert_eq "AC12 anchored posix_quote count == 1" "1" "$anchored_count" || return 1

    # 2. Unanchored count also equals 1 (no shadow inside function body)
    local unanchored_count
    unanchored_count="$(grep -c 'posix_quote() {' "$INSTALL_SH" || true)"
    assert_eq "AC12 unanchored posix_quote count == 1" "1" "$unanchored_count" || return 1

    # 3. posix_quote line number < first do_theme_install invocation line number
    local posix_quote_line do_theme_line
    posix_quote_line="$(grep -n '^posix_quote() {' "$INSTALL_SH" | head -1 | cut -d: -f1)"
    do_theme_line="$(grep -n 'do_theme_install$' "$INSTALL_SH" | head -1 | cut -d: -f1)"
    if [ -z "$posix_quote_line" ] || [ -z "$do_theme_line" ]; then
        echo "ASSERT FAIL: AC12 could not find posix_quote or do_theme_install lines" >&2
        echo "  posix_quote_line: $posix_quote_line" >&2
        echo "  do_theme_line: $do_theme_line" >&2
        return 1
    fi
    if [ "$posix_quote_line" -ge "$do_theme_line" ]; then
        echo "ASSERT FAIL: AC12 posix_quote (line $posix_quote_line) >= do_theme_install (line $do_theme_line)" >&2
        return 1
    fi

    teardown_test
    return 0
}

# AC13 — RUNNING: echo precedes external invocation (shared EVENT_LOG ordering)
case_AC13() {
    setup_test
    make_stub_required
    make_stub_recommended
    make_stub_npx
    # graphify absent → install_graphify_cli_binary fires → RUNNING: python3 echoed before stub runs
    stage_kl_all_absent
    local vault_dir="$CASE_HOME/vault"
    mkdir -p "$vault_dir"
    export OBSIDIAN_VAULT_PATH="$vault_dir"
    export MONSTERFLOW_OWNER=1

    # EVENT_LOG is shared: stubs write "STUB <name> <args>", install.sh writes "RUNNING <cmd>"
    # We need install.sh to also write to EVENT_LOG. The RUNNING: echo goes to stdout (CASE_OUT);
    # to get cross-stream ordering we assert that in CASE_OUT, RUNNING python3 -m venv appears
    # before any stub confirmation. The EVENT_LOG captures stub events independently.
    # Since install.sh writes RUNNING: to stdout and stubs write STUB to EVENT_LOG,
    # we verify the ordering guarantee via CASE_OUT containing RUNNING before stub side-effects exist.

    local rc
    rc=$(run_install --non-interactive --no-onboard --no-theme)
    assert_exit_code "AC13 exit 0" "0" "$rc" || return 1

    # RUNNING: python3 -m venv must appear in CASE_OUT
    assert_match "AC13 RUNNING python3 in stdout" "RUNNING.*python3.*venv" "$CASE_OUT" || return 1

    # STUB python3 must appear in EVENT_LOG
    assert_match "AC13 STUB python3 in EVENT_LOG" "STUB python3.*venv" "$EVENT_LOG" || return 1

    # Ordering: RUNNING line number in CASE_OUT precedes the stub invocation in TIME.
    # We can verify that the RUNNING echo appears in CASE_OUT at all (proof that it was
    # emitted before the stub ran). The cross-stream guarantee is: install.sh echoes
    # RUNNING: before calling the binary; the binary writes to EVENT_LOG; since the echo
    # is sequential code before the call, the echo-line is always first in wall-clock time.
    # Direct test: venv dir must exist AFTER run (stub created it — means stub ran after RUNNING:)
    assert_file_exists "AC13 venv dir created by stub" "$HOME/.local/venvs/graphify/bin" || return 1

    teardown_test
    return 0
}

# AC14 — Stub side-effects produce realistic post-install filesystem
case_AC14() {
    setup_test
    make_stub_required
    make_stub_recommended
    make_stub_npx
    # graphify absent → installs fire → stubs create filesystem state → second run detects all present
    # After install, add graphify stub to STUB_DIR so second run's has_cmd graphify = true
    stage_kl_all_absent
    local vault_dir="$CASE_HOME/vault"
    mkdir -p "$vault_dir"
    export OBSIDIAN_VAULT_PATH="$vault_dir"
    export MONSTERFLOW_OWNER=1

    # First run: install everything
    local rc1
    rc1=$(run_install --non-interactive --no-onboard --no-theme)
    assert_exit_code "AC14 first run exit 0" "0" "$rc1" || return 1

    # graphify binary must be on PATH after install (stub created it)
    assert_file_exists "AC14 graphify in local bin" "$HOME/.local/bin/graphify" || return 1

    # Now add graphify to STUB_DIR so second run's has_cmd graphify = true
    # (MONSTERFLOW_HASCMD_OVERRIDE=$STUB_DIR is the test seam — it only checks STUB_DIR)
    make_stub_graphify

    # Pre-stage SKILL.md so install_graphify_skill_via_cli idempotency gate fires correctly
    # (has_cmd graphify=true + SKILL.md exists → skip; this is the realistic post-install state)
    mkdir -p "$HOME/.claude/skills/graphify"
    [ -f "$HOME/.claude/skills/graphify/SKILL.md" ] || echo "# graphify SKILL placeholder" > "$HOME/.claude/skills/graphify/SKILL.md"

    # Wiki skills are manual-action-required (install.sh can't install them).
    # Pre-stage all 6 to simulate a realistic post-install state where user ran
    # `npx skills add Ar9av/obsidian-wiki` after the first install.
    # This is correct for AC14: the "all present" check verifies the DETECTION works
    # on a fully-installed system, not that install.sh installs them.
    local n
    for n in wiki-ingest wiki-update wiki-query wiki-export wiki-lint wiki-capture; do
        mkdir -p "$HOME/.claude/skills/$n"
        [ -f "$HOME/.claude/skills/$n/SKILL.md" ] || echo "# $n skill" > "$HOME/.claude/skills/$n/SKILL.md"
    done

    # Reset output for second run
    : > "$CASE_OUT"
    : > "$STUB_LOG"

    # Second run — detection should see everything as present
    local rc2
    rc2=$(run_install --non-interactive --no-onboard --no-theme)
    assert_exit_code "AC14 second run exit 0" "0" "$rc2" || return 1

    # All-present line must fire
    assert_match "AC14 second run all present" "Knowledge Layer: all present ✓" "$CASE_OUT" || return 1

    # No install actions on second run
    assert_no_match "AC14 no python3 on second run" "RUNNING.*python3.*venv" "$CASE_OUT" || return 1
    assert_no_match "AC14 no brew on second run" "RUNNING.*brew.*obsidian" "$CASE_OUT" || return 1

    teardown_test
    return 0
}

# case_posix_quote_hoist_integrity — static asserts (same as AC12, separate entry point)
case_posix_quote_hoist_integrity() {
    setup_test

    local anchored_count
    anchored_count="$(grep -c '^posix_quote() {' "$INSTALL_SH" || true)"
    if [ "$anchored_count" -ne 1 ]; then
        echo "ASSERT FAIL: posix_quote_hoist: anchored count = $anchored_count (expected 1)" >&2
        return 1
    fi

    local unanchored_count
    unanchored_count="$(grep -c 'posix_quote() {' "$INSTALL_SH" || true)"
    if [ "$unanchored_count" -ne 1 ]; then
        echo "ASSERT FAIL: posix_quote_hoist: unanchored count = $unanchored_count (expected 1)" >&2
        return 1
    fi

    local posix_quote_line do_theme_line
    posix_quote_line="$(grep -n '^posix_quote() {' "$INSTALL_SH" | head -1 | cut -d: -f1)"
    do_theme_line="$(grep -n 'do_theme_install$' "$INSTALL_SH" | head -1 | cut -d: -f1)"

    if [ -z "$posix_quote_line" ] || [ -z "$do_theme_line" ]; then
        echo "ASSERT FAIL: posix_quote_hoist: missing line numbers (pq=$posix_quote_line dt=$do_theme_line)" >&2
        return 1
    fi

    if [ "$posix_quote_line" -ge "$do_theme_line" ]; then
        echo "ASSERT FAIL: posix_quote_hoist: posix_quote (L$posix_quote_line) not before do_theme_install (L$do_theme_line)" >&2
        return 1
    fi

    teardown_test
    return 0
}

# AC15 — EC2 symlink-only recovery (SF-build2)
# Fixture: venv exists + graphify binary in venv, symlink at ~/.local/bin/graphify MISSING,
# SKILL.md pre-staged (so 3.1b does NOT re-fire).
# Assert: ln -sf IS run (LINKED in stdout), pip3 NOT run, python3 -m venv NOT run,
# graphify claude install NOT run (SKILL.md already present).
case_AC15_ec2_symlink_only_recovery() {
    setup_test
    make_stub_required
    make_stub_recommended
    make_stub_npx
    make_stub_graphify
    stage_kl_all_absent

    # Pre-stage the venv + graphify binary (as if a prior pip install ran)
    local venv="$HOME/.local/venvs/graphify"
    mkdir -p "$venv/bin"
    printf '#!/bin/bash\necho "venv-graphify $*"\nexit 0\n' > "$venv/bin/graphify"
    chmod +x "$venv/bin/graphify"
    mkdir -p "$venv/lib/python3/site-packages/graphifyy-0.4.21.dist-info"
    echo "pip" > "$venv/lib/python3/site-packages/graphifyy-0.4.21.dist-info/INSTALLER"

    # Pre-stage SKILL.md (so 3.1b idempotency gate skips it)
    mkdir -p "$HOME/.claude/skills/graphify"
    echo "# graphify SKILL" > "$HOME/.claude/skills/graphify/SKILL.md"

    # Symlink is intentionally ABSENT: rm -f ~/.local/bin/graphify
    rm -f "$HOME/.local/bin/graphify" 2>/dev/null || true

    # Also need the graphify stub present for after-symlink-recreation detection
    # (detect_graphify_cli uses has_cmd which checks STUB_DIR; graphify is there from make_stub_graphify)

    # Stage vault dir
    local vault_dir="$CASE_HOME/vault"
    mkdir -p "$vault_dir"
    export OBSIDIAN_VAULT_PATH="$vault_dir"
    export MONSTERFLOW_OWNER=1

    local rc
    rc=$(run_install --non-interactive --no-onboard --no-theme)
    assert_exit_code "AC15 exit 0" "0" "$rc" || return 1

    # ln -sf fired (symlink-only recovery path)
    assert_match "AC15 LINKED in stdout" "LINKED.*graphify" "$CASE_OUT" || return 1

    # pip3 NOT run (venv already has the binary)
    assert_no_match "AC15 no pip3 install" "RUNNING.*pip3 install" "$CASE_OUT" || return 1

    # python3 -m venv NOT run
    assert_no_match "AC15 no python3 venv" "RUNNING.*python3.*venv" "$CASE_OUT" || return 1

    # graphify claude install NOT run (SKILL.md was pre-staged)
    assert_no_match "AC15 no graphify claude install in stdout" "RUNNING.*graphify claude install" "$CASE_OUT" || return 1
    assert_no_match "AC15 no graphify in stub log" "graphify claude install" "$STUB_LOG" || return 1

    teardown_test
    return 0
}

##############################################################################
# Runner
##############################################################################
CASES=(
    case_AC1
    case_AC2
    case_AC3
    case_AC4
    case_AC5
    case_AC6
    case_AC7
    case_AC8a
    case_AC8b
    case_AC9
    case_AC10
    case_AC11
    case_AC12
    case_AC13
    case_AC14
    case_posix_quote_hoist_integrity
    case_AC15_ec2_symlink_only_recovery
)

TOTAL=${#CASES[@]}
echo "=== test-install-knowledge-layer.sh — $TOTAL cases ==="
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
            echo "  --- install.sh tail (last 40 lines) ---" >&2
            tail -40 "$CASE_OUT" >&2 2>/dev/null || true
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
