#!/bin/bash
# scripts/resolve-personas.sh — resolve which personas a gate should dispatch
#
# Public surface for the agent-budget feature. Reads ~/.config/monsterflow/
# config.json + dashboard/data/persona-rankings.jsonl + personas/<gate>/*.md
# and emits a newline-separated persona list (capped at agent_budget),
# optionally followed by `codex-adversary` if Codex is authenticated.
#
# This shell wrapper handles two things Python can't do cleanly:
#   1. Probe `codex login status` (with a 60s mtime-bucket cache).
#   2. Honor MONSTERFLOW_DISABLE_BUDGET=1 even before Python loads.
#
# All other logic lives in scripts/_resolve_personas.py (the heavy lifting:
# JSON, ranking sort, lock file, selection.json, --why, --print-schema).
#
# Stdout grammar (locked):
#   <persona-name>\n+ <codex-adversary>?
#   - persona names: [a-z][a-z0-9-]*
#   - codex-adversary: only as the last line, only when authenticated
#   - empty stdout = contract violation (caller MUST exit non-zero)
#
# Exit codes (mirrored from python helper):
#   0 — ≥1 Claude persona emitted
#   2 — config malformed
#   3 — degenerate state (no personas selectable)
#   4 — --feature arg missing or feature dir absent
#   5 — internal/unexpected
#
# AUTORUN/non-tty: caller must check $? AND verify wc -l > 0. No silent fallback.
#
# Tests: tests/test-resolve-personas.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
HELPER="$REPO_DIR/scripts/_resolve_personas.py"

if [ ! -f "$HELPER" ]; then
    echo "resolve-personas: missing helper at $HELPER" >&2
    exit 5
fi

# --- Codex auth probe (cached 60s) ---
# Wrapper sets CODEX_AUTH=1 env var if `codex login status` exits 0; otherwise
# unset. Also sets CODEX_BINARY_MISSING=1 when the binary is absent (so the
# Python helper can distinguish missing-binary from not-authenticated for
# selection.json's codex_status field).
#
# Cache: $HOME/.cache/monsterflow/codex-auth.<bucket-of-60s>. Touch-only;
# content is irrelevant — mtime bucket gates re-probing.
#
# Override hook for tests: set MONSTERFLOW_CODEX_AUTH={1,0} to bypass the
# probe entirely (PATH-stub model from feedback_path_stub_over_export_f).
# Also: a `codex` PATH stub is the standard mock; the real probe runs
# `codex login status` so the stub controls the outcome.
codex_probe() {
    if [ "${MONSTERFLOW_CODEX_AUTH:-}" = "1" ]; then
        export CODEX_AUTH=1
        return 0
    fi
    if [ "${MONSTERFLOW_CODEX_AUTH:-}" = "0" ]; then
        unset CODEX_AUTH
        return 0
    fi
    if ! command -v codex >/dev/null 2>&1; then
        export CODEX_BINARY_MISSING=1
        unset CODEX_AUTH
        return 0
    fi
    local cache_dir="$HOME/.cache/monsterflow"
    # 60s buckets: floor(epoch / 60). Bash 3.2 supports $((..)) arithmetic.
    local bucket=$(( $(date +%s) / 60 ))
    local cache_file="$cache_dir/codex-auth.$bucket"
    if [ -f "$cache_file" ]; then
        export CODEX_AUTH=1
        return 0
    fi
    if codex login status >/dev/null 2>&1; then
        mkdir -p "$cache_dir"
        : > "$cache_file"
        export CODEX_AUTH=1
    else
        unset CODEX_AUTH
    fi
}

codex_probe

export MONSTERFLOW_REPO_DIR="$REPO_DIR"

# SEC-09: internal temp dir (cleaned on exit). Helpers must not leak temp state.
# The Python helper does not write temp files yet in Slice 3, but the env var
# is exported so future callers can rely on a per-invocation scratch path.
# A trap cleans up on natural exit (EXIT), Ctrl-C (INT), TERM, and HUP.
MF_RESOLVE_TMPDIR="$(mktemp -d -t monsterflow-resolve.XXXXXX)" || {
    echo "resolve-personas: mktemp failed" >&2; exit 5;
}
trap 'rm -rf "$MF_RESOLVE_TMPDIR"' EXIT INT TERM HUP
export MF_RESOLVE_TMPDIR

# Hand off to the Python helper. With the trap in place we can't `exec` (that
# would replace this shell and skip the cleanup trap), so we run + propagate
# the helper's exit code.
python3 "$HELPER" "$@"
exit $?
