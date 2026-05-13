#!/bin/bash
# scripts/onboard.sh — post-install onboarding panel
#
# Re-run anytime:
#   bash ~/Projects/MonsterFlow/scripts/onboard.sh
#
# Honours env vars set by install.sh:
#   MONSTERFLOW_NON_INTERACTIVE=1  — suppress interactive prompts
#   MONSTERFLOW_FORCE_ONBOARD=1    — run panel even if non-interactive
#
# Standalone and re-runnable: install.sh need not have just run.

set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"

# 1. doctor.sh — verify wiring (failure printed but non-fatal)
# Skip under MONSTERFLOW_INSTALL_TEST=1: tests spawn install.sh ≥20 times and
# doctor.sh's --version probes (claude, gh, git, python3) add up. The CI signal
# from doctor.sh is redundant with the assertions test-install.sh already makes.
if [ "${MONSTERFLOW_INSTALL_TEST:-0}" != "1" ] && [ -x "$REPO_DIR/scripts/doctor.sh" ]; then
    bash "$REPO_DIR/scripts/doctor.sh" || true
fi

# 2. The boxed panel — MUST contain literal substrings /flow, /spec,
# dashboard/index.html (acceptance test asserts these). Per UX spec the
# panel is 64 cols wide; content lines pad to keep right-border alignment
# in modern terminals, but content survives if the box-drawing chars
# render as `?` in a degraded terminal.
cat <<'PANEL'

╭─ MonsterFlow is ready ───────────────────────────────────────╮
│                                                              │
│  Next steps:                                                 │
│    1. cd into a project                                      │
│    2. /flow            — see the workflow card               │
│    3. /spec            — design your first feature           │
│    4. open ~/Projects/MonsterFlow/dashboard/index.html       │
│                                                              │
PANEL

# Per-system optional offers (only when interactive AND signal exists)
NON_INTERACTIVE="${MONSTERFLOW_NON_INTERACTIVE:-0}"
[ ! -t 0 ] && NON_INTERACTIVE=1   # auto-detect

# MONSTERFLOW_FORCE_ONBOARD=1 — let install.sh force the panel even when
# non-interactive (panel still prints; the per-prompt offers below remain
# guarded by NON_INTERACTIVE so we never block on stdin in CI).

# Helper: bash trap-alarm 5s timeout for `gh auth status`
# (per plan D9 — corporate-proxy hang protection; macOS lacks GNU `timeout`).
#
# Two prior bugs fixed inline:
#   1. Orphan-sleep leak: `( sleep 5 && kill ) &` followed by `kill $watchdog`
#      sent SIGTERM to the subshell only; the `sleep` child got reparented to
#      launchd and ran to completion. Replaced with an explicit pkill on the
#      sleep PID so no orphan survives.
#   2. Test-env redundancy: under MONSTERFLOW_INSTALL_TEST=1 the stub gh
#      returns exit 0 (always "authenticated"), so the watchdog is wasted
#      work. Short-circuit returns 0 immediately.
gh_auth_check_with_timeout() {
    if [ "${MONSTERFLOW_INSTALL_TEST:-0}" = "1" ]; then
        return 0
    fi
    local pid result sleep_pid
    ( gh auth status >/dev/null 2>&1 ) &
    pid=$!
    ( sleep 5 ) &
    sleep_pid=$!
    # Race: whichever finishes first wins. If gh finished, kill the sleep.
    # If sleep finished first, kill gh.
    while kill -0 "$pid" 2>/dev/null && kill -0 "$sleep_pid" 2>/dev/null; do
        sleep 0.1
    done
    if kill -0 "$pid" 2>/dev/null; then
        # sleep won — gh is hung; kill it
        kill "$pid" 2>/dev/null
        wait "$pid" 2>/dev/null
        return 124  # standard timeout exit code
    fi
    wait "$pid" 2>/dev/null
    result=$?
    kill "$sleep_pid" 2>/dev/null
    wait "$sleep_pid" 2>/dev/null
    return "$result"
}

if [ "$NON_INTERACTIVE" = "0" ]; then
    echo "│  Optional:                                                   │"
    # graphify offer — gates on ~/.local/share/MonsterFlow/.last-graphify-run mtime
    if [ -x "$REPO_DIR/scripts/bootstrap-graphify.sh" ]; then
        STAMP="$HOME/.local/share/MonsterFlow/.last-graphify-run"
        OFFER_GRAPHIFY=1
        if [ -f "$STAMP" ] && [ -n "$(find "$STAMP" -mtime -7 2>/dev/null)" ]; then
            OFFER_GRAPHIFY=0   # ran recently
        fi
        if [ "$OFFER_GRAPHIFY" = "1" ]; then
            GIDX=""
            read -rp "    • Index ~/Projects/ for the dashboard? [y/N]: " GIDX || GIDX=""
            if [[ "$GIDX" =~ ^[Yy]$ ]]; then
                bash "$REPO_DIR/scripts/bootstrap-graphify.sh" || true
                mkdir -p "$(dirname "$STAMP")"
                touch "$STAMP"
            fi
        fi
    fi
    # gh offer — only if installed AND unauthenticated (with timeout)
    if command -v gh >/dev/null 2>&1; then
        if ! gh_auth_check_with_timeout; then
            GAUTH=""
            read -rp "    • Authenticate gh CLI now? [y/N]: " GAUTH || GAUTH=""
            if [[ "$GAUTH" =~ ^[Yy]$ ]]; then
                gh auth login || true
            fi
        fi
    fi
fi

# Codex one-line opt-in (no prompt — informational)
if ! command -v codex >/dev/null 2>&1; then
    echo "│    • Want adversarial review? Run /codex:setup               │"
fi

cat <<'PANEL'
│                                                              │
╰──────────────────────────────────────────────────────────────╯

PANEL
