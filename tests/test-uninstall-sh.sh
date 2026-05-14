#!/usr/bin/env bash
##############################################################################
# tests/test-uninstall-sh.sh
#
# Cold-start / detector-fallback mode tests for uninstall.sh (MVP — manifest
# emission deferred to install-sh-manifest-emit). 8 cases.
#
# Per the feedback_path_stub_over_export_f memory: tests pin BASH=/bin/bash
# and use HOME stubbing (not export -f) to isolate filesystem state.
##############################################################################
set -uo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
UNINSTALL="$ENGINE_DIR/uninstall.sh"
TMPROOT="$(mktemp -d -t monsterflow-uninstall-test)"
trap 'rm -rf "$TMPROOT"' EXIT

PASS=0
FAIL=0
FAILED_CASES=()

# --- Per-case stub helpers ---

mk_case() {
    local case_name="$1"
    CASE_HOME="$TMPROOT/$case_name/HOME"
    CASE_OUT="$TMPROOT/$case_name/out.txt"
    mkdir -p "$CASE_HOME/.claude/commands" "$CASE_HOME/.claude/personas/review" "$CASE_HOME/.config/cmux"
}

mk_monsterflow_symlinks() {
    # Stub: pretend a basic install happened — link from $CASE_HOME/.claude/commands
    # back into the real repo so detector recognizes them as MonsterFlow paths.
    ln -sf "$ENGINE_DIR/commands/spec.md" "$CASE_HOME/.claude/commands/spec.md"
    ln -sf "$ENGINE_DIR/commands/blueprint.md" "$CASE_HOME/.claude/commands/blueprint.md"
    ln -sf "$ENGINE_DIR/personas/review/scope.md" "$CASE_HOME/.claude/personas/review/scope.md"
}

mk_zshrc_with_theme_block() {
    cat > "$CASE_HOME/.zshrc" <<EOF
# User content above
export PATH="\$HOME/bin:\$PATH"

# BEGIN MonsterFlow theme
[ -f /some/path/zsh-prompt-colors.zsh ] && source /some/path/zsh-prompt-colors.zsh
# END MonsterFlow theme

# User content below
alias ll='ls -la'
EOF
}

run_uninstall() {
    local mode="$1"
    if [ "$mode" = "--apply" ]; then
        HOME="$CASE_HOME" bash "$UNINSTALL" --apply >"$CASE_OUT" 2>&1
    else
        HOME="$CASE_HOME" bash "$UNINSTALL" >"$CASE_OUT" 2>&1
    fi
}

assert() {
    local desc="$1"
    local cond="$2"
    if eval "$cond"; then
        echo "  ✓ $desc"
        return 0
    else
        echo "  ✗ $desc"
        echo "    cond: $cond"
        return 1
    fi
}

report_case() {
    local name="$1"
    local result="$2"
    if [ "$result" = "0" ]; then
        echo "[PASS] $name"
        PASS=$((PASS + 1))
    else
        echo "[FAIL] $name (see $CASE_OUT)"
        FAIL=$((FAIL + 1))
        FAILED_CASES+=("$name")
    fi
}

# --- AC1 — dry-run with no side effects ---

case_AC1_dry_run_no_side_effects() {
    mk_case "AC1"
    mk_monsterflow_symlinks
    SNAPSHOT="$TMPROOT/AC1/snapshot"
    cp -R "$CASE_HOME" "$SNAPSHOT"

    run_uninstall ""
    ok=0
    assert "dry-run exits 0" "[ \$? -eq 0 ]" || ok=1
    assert "dry-run output mentions DRY RUN" "grep -q 'DRY RUN' \"$CASE_OUT\"" || ok=1
    assert "dry-run output uses WOULD: prefix" "grep -q 'WOULD: remove' \"$CASE_OUT\"" || ok=1
    assert "no files mutated" "diff -r \"$SNAPSHOT\" \"$CASE_HOME\" >/dev/null 2>&1" || ok=1
    report_case AC1 $ok
}

# --- AC2 — --apply removes MonsterFlow symlinks ---

case_AC2_apply_removes_symlinks() {
    mk_case "AC2"
    mk_monsterflow_symlinks
    run_uninstall --apply
    ok=0
    assert "spec.md symlink removed" "[ ! -e \"$CASE_HOME/.claude/commands/spec.md\" ] && [ ! -L \"$CASE_HOME/.claude/commands/spec.md\" ]" || ok=1
    assert "blueprint.md symlink removed" "[ ! -L \"$CASE_HOME/.claude/commands/blueprint.md\" ]" || ok=1
    assert "scope.md symlink removed" "[ ! -L \"$CASE_HOME/.claude/personas/review/scope.md\" ]" || ok=1
    assert "output uses REMOVED: prefix" "grep -q 'REMOVED:' \"$CASE_OUT\"" || ok=1
    report_case AC2 $ok
}

# --- AC3 — sentinel block stripped from ~/.zshrc; surrounding content preserved ---

case_AC3_zshrc_sentinel_strip() {
    mk_case "AC3"
    mk_zshrc_with_theme_block
    run_uninstall --apply
    ok=0
    assert "BEGIN sentinel gone" "! grep -q 'BEGIN MonsterFlow theme' \"$CASE_HOME/.zshrc\"" || ok=1
    assert "END sentinel gone" "! grep -q 'END MonsterFlow theme' \"$CASE_HOME/.zshrc\"" || ok=1
    assert "user content above preserved" "grep -q 'User content above' \"$CASE_HOME/.zshrc\"" || ok=1
    assert "user content below preserved" "grep -q 'User content below' \"$CASE_HOME/.zshrc\"" || ok=1
    assert "alias line preserved" "grep -q \"alias ll='ls -la'\" \"$CASE_HOME/.zshrc\"" || ok=1
    assert "output uses STRIPPED: prefix" "grep -q 'STRIPPED:' \"$CASE_OUT\"" || ok=1
    report_case AC3 $ok
}

# --- AC4 — full-file backup written before sentinel strip ---

case_AC4_sentinel_strip_backup() {
    mk_case "AC4"
    mk_zshrc_with_theme_block
    run_uninstall --apply
    ok=0
    backup_count="$(find "$CASE_HOME" -maxdepth 1 -name '.zshrc.uninstall.bak.*' | wc -l | tr -d ' ')"
    assert "exactly 1 backup file exists" "[ \"$backup_count\" = \"1\" ]" || ok=1
    backup_file="$(find "$CASE_HOME" -maxdepth 1 -name '.zshrc.uninstall.bak.*' | head -1)"
    assert "backup contains the sentinel block (pre-strip content)" "grep -q 'BEGIN MonsterFlow theme' \"$backup_file\"" || ok=1
    assert "output uses SAVED: prefix" "grep -q 'SAVED:' \"$CASE_OUT\"" || ok=1
    report_case AC4 $ok
}

# --- AC5 — idempotent re-run ---

case_AC5_idempotent_rerun() {
    mk_case "AC5"
    mk_monsterflow_symlinks
    mk_zshrc_with_theme_block

    # First apply
    run_uninstall --apply
    first_exit=$?

    # Second apply against an already-clean stub
    HOME="$CASE_HOME" bash "$UNINSTALL" --apply >"$CASE_OUT.2" 2>&1
    second_exit=$?

    ok=0
    assert "first apply exits 0" "[ $first_exit -eq 0 ]" || ok=1
    assert "second apply exits 0" "[ $second_exit -eq 0 ]" || ok=1
    assert "second apply says 'Nothing to remove'" "grep -q 'Nothing to remove' \"$CASE_OUT.2\"" || ok=1
    report_case AC5 $ok
}

# --- AC6 — unbalanced sentinel refuses strip ---

case_AC6_unbalanced_sentinel() {
    mk_case "AC6"
    # BEGIN without matching END
    cat > "$CASE_HOME/.zshrc" <<EOF
# Some user content
# BEGIN MonsterFlow theme
[ -f /x ] && source /x
# (no END — truncated)
echo "still here"
EOF
    pre_size="$(wc -c < "$CASE_HOME/.zshrc" | tr -d ' ')"

    run_uninstall --apply
    exit_code=$?
    post_size="$(wc -c < "$CASE_HOME/.zshrc" | tr -d ' ')"

    ok=0
    # Helper returns non-zero on unbalanced; uninstall.sh logs WARN: but does not modify the file via Python
    # AC6 spec: the zshrc strip is refused (file NOT modified by the strip path).
    # We assert the file kept its BEGIN line — strip didn't run.
    assert "BEGIN sentinel still present (strip refused)" "grep -q 'BEGIN MonsterFlow theme' \"$CASE_HOME/.zshrc\"" || ok=1
    assert "uninstall continues for other phases (exits 0 anyway in MVP)" "[ $exit_code -eq 0 ]" || ok=1
    report_case AC6 $ok
}

# --- AC7 — non-MonsterFlow symlink skipped ---

case_AC7_non_monsterflow_symlink_skipped() {
    mk_case "AC7"
    # Set up a non-MonsterFlow symlink under ~/.claude/commands/
    other_target="$TMPROOT/AC7/other-target.md"
    echo "# unrelated" > "$other_target"
    ln -sf "$other_target" "$CASE_HOME/.claude/commands/custom.md"

    run_uninstall --apply
    ok=0
    assert "non-MonsterFlow symlink still present" "[ -L \"$CASE_HOME/.claude/commands/custom.md\" ]" || ok=1
    report_case AC7 $ok
}

# --- AC8 — claude-workflow path (pre-rebrand) recognized ---

case_AC8_claude_workflow_path_recognized() {
    mk_case "AC8"
    # Simulate a pre-rebrand install: symlink target contains /claude-workflow/
    fake_workflow_dir="$TMPROOT/AC8/claude-workflow/commands"
    mkdir -p "$fake_workflow_dir"
    echo "# fake spec.md from pre-rebrand era" > "$fake_workflow_dir/spec.md"
    ln -sf "$fake_workflow_dir/spec.md" "$CASE_HOME/.claude/commands/spec.md"

    run_uninstall --apply
    ok=0
    assert "claude-workflow symlink removed" "[ ! -L \"$CASE_HOME/.claude/commands/spec.md\" ]" || ok=1
    report_case AC8 $ok
}

# --- Run all cases ---

echo "=== test-uninstall-sh.sh — 8 cases (cold-start / detector-fallback) ==="
echo ""

case_AC1_dry_run_no_side_effects
case_AC2_apply_removes_symlinks
case_AC3_zshrc_sentinel_strip
case_AC4_sentinel_strip_backup
case_AC5_idempotent_rerun
case_AC6_unbalanced_sentinel
case_AC7_non_monsterflow_symlink_skipped
case_AC8_claude_workflow_path_recognized

echo ""
echo "=========================================="
echo "Results: $PASS passed, $FAIL failed (of 8 cases)"
if [ "$FAIL" -gt 0 ]; then
    echo "Failed cases:"
    for c in "${FAILED_CASES[@]}"; do
        echo "  - $c"
    done
    exit 1
fi
exit 0
