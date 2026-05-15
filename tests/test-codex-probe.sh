#!/bin/bash
##############################################################################
# tests/test-codex-probe.sh
#
# Unit tests for scripts/autorun/_codex_probe.sh — Codex availability + auth
# probe (Task 2.2 of autorun-overnight-policy plan v6).
#
# Contract under test:
#   exit 0 = available + authenticated
#   exit 1 = unavailable (binary not on PATH)
#   exit 2 = auth-failed (binary present, `codex login status` non-zero)
#
# Mocking model (per memory feedback_path_stub_over_export_f):
#   PATH-stub for `codex` binary. We build per-case stub dirs with executable
#   `codex` scripts and prepend to PATH; never `export -f codex`.
#
# Bash 3.2 portability: pin BASH=/bin/bash; no ${array[-1]}.
##############################################################################
set -uo pipefail

export BASH=/bin/bash

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
PROBE="$REPO_DIR/scripts/autorun/_codex_probe.sh"

PASS=0
FAIL=0
FAILED_CASES=()

# Per-case scratch
CASE_DIR=""

setup_case() {
    CASE_DIR="$(mktemp -d -t mf-codex-probe-test.XXXXXX)"
    if [ -z "$CASE_DIR" ] || [ ! -d "$CASE_DIR" ]; then
        echo "  FAIL: mktemp -d returned invalid path '$CASE_DIR'" >&2
        return 1
    fi
    mkdir -p "$CASE_DIR/bin"
}

teardown_case() {
    if [ -n "$CASE_DIR" ] && [ -d "$CASE_DIR" ]; then
        rm -rf "$CASE_DIR"
    fi
    CASE_DIR=""
}

# write a stub `codex` that exits with a chosen status when invoked with
# `login status`. Other subcommands also exit with that same status (probe
# only ever calls `login status` so this is fine).
make_codex_stub() {
    local exit_code="$1"
    cat > "$CASE_DIR/bin/codex" <<EOF
#!/bin/bash
exit $exit_code
EOF
    chmod +x "$CASE_DIR/bin/codex"
}

run_probe() {
    # Use only the case bin + minimal system PATH so a real codex on the
    # tester's machine cannot leak in.
    PATH="$CASE_DIR/bin:/usr/bin:/bin" bash "$PROBE" "$@"
}

run_probe_no_codex() {
    # Bare PATH with no stub at all → probe should report unavailable.
    PATH="/usr/bin:/bin" bash "$PROBE" "$@"
}

assert_exit() {
    local name="$1"
    local expected="$2"
    local actual="$3"
    if [ "$actual" -eq "$expected" ]; then
        echo "  ok: $name (exit $actual)"
        PASS=$(( PASS + 1 ))
    else
        echo "  FAIL: $name (expected exit $expected, got $actual)"
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("$name")
    fi
}

# ---------------------------------------------------------------------------
# test_codex_present_authed
# ---------------------------------------------------------------------------
test_codex_present_authed() {
    echo "test_codex_present_authed"
    setup_case
    make_codex_stub 0
    local got=0
    run_probe >/dev/null 2>&1 || got=$?
    assert_exit "stub codex returns 0 → probe exits 0" 0 "$got"
    teardown_case
}

# ---------------------------------------------------------------------------
# test_codex_absent — no codex on PATH
# ---------------------------------------------------------------------------
test_codex_absent() {
    echo "test_codex_absent"
    setup_case
    local got=0
    run_probe_no_codex >/dev/null 2>&1 || got=$?
    assert_exit "no codex on PATH → probe exits 1" 1 "$got"
    teardown_case
}

# ---------------------------------------------------------------------------
# test_codex_unauthed — codex present but login status nonzero
# ---------------------------------------------------------------------------
test_codex_unauthed() {
    echo "test_codex_unauthed"
    setup_case
    make_codex_stub 1
    local got=0
    run_probe >/dev/null 2>&1 || got=$?
    assert_exit "stub codex returns 1 → probe exits 2" 2 "$got"
    teardown_case
}

# ---------------------------------------------------------------------------
# test_verbose_emits_to_stderr — --verbose writes one line, stdout empty
# ---------------------------------------------------------------------------
test_verbose_emits_to_stderr() {
    echo "test_verbose_emits_to_stderr"
    setup_case
    make_codex_stub 0
    local stdout_file="$CASE_DIR/stdout"
    local stderr_file="$CASE_DIR/stderr"
    local got=0
    PATH="$CASE_DIR/bin:/usr/bin:/bin" bash "$PROBE" --verbose \
        >"$stdout_file" 2>"$stderr_file" || got=$?
    assert_exit "verbose available → exit 0" 0 "$got"
    if [ ! -s "$stdout_file" ]; then
        echo "  ok: stdout empty"
        PASS=$(( PASS + 1 ))
    else
        echo "  FAIL: stdout not empty"
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("verbose stdout empty")
    fi
    if grep -q '^\[codex_probe\] available$' "$stderr_file"; then
        echo "  ok: stderr has [codex_probe] available"
        PASS=$(( PASS + 1 ))
    else
        echo "  FAIL: stderr missing expected line — got: $(cat "$stderr_file")"
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("verbose stderr line")
    fi
    teardown_case
}

# ---------------------------------------------------------------------------
# test_silent_default — no flags = no stderr output
# ---------------------------------------------------------------------------
test_silent_default() {
    echo "test_silent_default"
    setup_case
    make_codex_stub 0
    local stderr_file="$CASE_DIR/stderr"
    local got=0
    PATH="$CASE_DIR/bin:/usr/bin:/bin" bash "$PROBE" \
        >/dev/null 2>"$stderr_file" || got=$?
    assert_exit "silent mode exit 0" 0 "$got"
    if [ ! -s "$stderr_file" ]; then
        echo "  ok: stderr empty in silent mode"
        PASS=$(( PASS + 1 ))
    else
        echo "  FAIL: stderr not empty — got: $(cat "$stderr_file")"
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("silent default stderr")
    fi
    teardown_case
}

# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------
if [ ! -x "$PROBE" ]; then
    echo "FAIL: probe not executable: $PROBE"
    exit 1
fi

test_codex_present_authed
test_codex_absent
test_codex_unauthed
test_verbose_emits_to_stderr
test_silent_default

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    echo "Failed cases:"
    for c in "${FAILED_CASES[@]}"; do
        echo "  - $c"
    done
    exit 1
fi
exit 0
