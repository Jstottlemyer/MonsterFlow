#!/bin/bash
# doctor.sh — Generate a diagnostic report and auto-file it as a GitHub Issue.
#
# Usage: ./scripts/doctor.sh
#
# Captures environment + Claude Code install state, writes a markdown report
# to a temp file, then opens a GitHub Issue on Jstottlemyer/MonsterFlow
# via gh. Requires: gh auth login already completed.

set -uo pipefail  # intentionally NOT -e — we want all diagnostics to run even if some probes fail

REPO="Jstottlemyer/MonsterFlow"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKFLOW_VERSION="$(cat "$SCRIPT_DIR/../VERSION" 2>/dev/null | tr -d '[:space:]' || echo 'unknown')"
DIAG_FILE=$(mktemp -t doctor-diagnostic.XXXXXX.md)
trap 'rm -f "$DIAG_FILE"' EXIT

# --- Gather diagnostics into $DIAG_FILE ---

{
    echo "# Install Diagnostic"
    echo ""
    echo "**Generated:** $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "**Pipeline version:** v${WORKFLOW_VERSION}"
    echo "**Host:** \`$(hostname)\`"
    echo "**User:** \`$(whoami)\`"
    echo ""

    echo "## System"
    echo '```'
    uname -a 2>&1 || echo "uname failed"
    sw_vers 2>&1 || echo "sw_vers not available (non-macOS?)"
    echo "SHELL=$SHELL"
    echo "bash: $(bash --version | head -1)"
    echo '```'
    echo ""

    echo "## CLI Versions"
    echo '```'
    echo "claude:  $(claude --version 2>&1 || echo 'NOT INSTALLED')"
    echo "gh:      $(gh --version 2>&1 | head -1 || echo 'NOT INSTALLED')"
    echo "git:     $(git --version 2>&1 || echo 'NOT INSTALLED')"
    echo "python3: $(python3 --version 2>&1 || echo 'NOT INSTALLED')"
    echo '```'
    echo ""

    echo "## ~/.claude/commands/"
    echo '```'
    ls -la "$HOME/.claude/commands/" 2>&1 || echo "(directory missing)"
    echo '```'
    echo ""

    echo "## ~/.claude/personas/ (top-level + subdirs)"
    echo '```'
    ls -la "$HOME/.claude/personas/" 2>&1 || echo "(directory missing)"
    for sub in check code-review plan review; do
        echo ""
        echo "--- personas/$sub ---"
        ls -la "$HOME/.claude/personas/$sub/" 2>&1 || echo "(subdir missing)"
    done
    echo '```'
    echo ""

    echo "## ~/.claude/domain-agents/"
    echo '```'
    if [ -d "$HOME/.claude/domain-agents" ]; then
        ls -la "$HOME/.claude/domain-agents/" 2>&1
        for sub in "$HOME/.claude/domain-agents"/*; do
            [ -d "$sub" ] || continue
            echo ""
            echo "--- $(basename "$sub") ---"
            ls -la "$sub" 2>&1
        done
    else
        echo "(directory missing — install.sh may need re-running with latest pull)"
    fi
    echo '```'
    echo ""

    echo "## ~/.claude/templates/"
    echo '```'
    ls -la "$HOME/.claude/templates/" 2>&1 || echo "(directory missing)"
    echo '```'
    echo ""

    echo "## Symlink Validity Check"
    echo '```'
    broken=0
    for dir in "$HOME/.claude/commands" "$HOME/.claude/personas" "$HOME/.claude/domain-agents" "$HOME/.claude/templates"; do
        [ -d "$dir" ] || continue
        while IFS= read -r -d '' link; do
            target=$(readlink "$link" 2>/dev/null) || continue
            if [ ! -e "$link" ]; then
                echo "BROKEN: $link -> $target"
                broken=$((broken + 1))
            fi
        done < <(find "$dir" -type l -print0 2>/dev/null)
    done
    if [ "$broken" -eq 0 ]; then
        echo "All symlinks resolve ✓"
    else
        echo ""
        echo "$broken broken symlink(s) found."
    fi
    echo '```'
    echo ""

    echo "## Plugin Cache"
    echo '```'
    if [ -d "$HOME/.claude/plugins/cache/claude-plugins-official" ]; then
        ls "$HOME/.claude/plugins/cache/claude-plugins-official/" 2>&1
    else
        echo "(no plugin cache — plugins not installed?)"
    fi
    echo '```'
    echo ""

    echo "## Settings"
    echo '```'
    if [ -L "$HOME/.claude/settings.json" ]; then
        echo "settings.json → $(readlink "$HOME/.claude/settings.json")"
    elif [ -f "$HOME/.claude/settings.json" ]; then
        echo "settings.json is a regular file (install.sh did not symlink)"
    else
        echo "settings.json missing"
    fi
    echo '```'
    echo ""

    echo "## Persona Metrics"
    echo '```'
    REPO="$SCRIPT_DIR/.."
    PM_FAILS=0

    # 1. Prompt symlinks
    echo "--- prompt symlinks ---"
    for p in snapshot findings-emit survival-classifier; do
        target="$HOME/.claude/commands/_prompts/${p}.md"
        if [ -L "$target" ]; then
            echo "ok   $target"
        else
            echo "MISS $target"
            PM_FAILS=$((PM_FAILS+1))
        fi
    done
    echo ""

    # 2. Schema files parse as valid JSON
    echo "--- schemas ---"
    for s in findings participation survival run; do
        schema_file="$REPO/schemas/${s}.schema.json"
        if [ -f "$schema_file" ]; then
            if python3 -c "import json,sys; json.load(open('$schema_file'))" 2>/dev/null; then
                echo "ok   $schema_file (valid JSON)"
            else
                echo "FAIL $schema_file (invalid JSON)"
                PM_FAILS=$((PM_FAILS+1))
            fi
        else
            echo "MISS $schema_file"
            PM_FAILS=$((PM_FAILS+1))
        fi
    done
    echo ""

    # 3. Prompt-version drift grep (compare prompt header version to schema example)
    echo "--- prompt_version drift ---"
    for prompt in snapshot findings-emit survival-classifier; do
        prompt_file="$REPO/commands/_prompts/${prompt}.md"
        if [ -f "$prompt_file" ]; then
            ver=$(grep -oE "${prompt}@[0-9]+\.[0-9]+" "$prompt_file" | head -1)
            if [ -n "$ver" ]; then
                count=$(grep -c "$ver" "$prompt_file")
                echo "ok   ${prompt}.md → $ver (mentioned ${count}× in file)"
            else
                echo "WARN ${prompt}.md → no prompt_version string found"
                PM_FAILS=$((PM_FAILS+1))
            fi
        fi
    done
    echo ""

    # 4. Fixture-based canonicalization check
    echo "--- canonicalization fixture ---"
    fixture_input="$REPO/tests/fixtures/normalized_signature/input.txt"
    fixture_expected="$REPO/tests/fixtures/normalized_signature/expected.hex"
    if [ -f "$fixture_input" ] && [ -f "$fixture_expected" ]; then
        actual=$(python3 -c "
import unicodedata, hashlib, re
with open('$fixture_input') as f:
    lines = [l for l in f.read().split('\n') if l.strip()]
canon = sorted(re.sub(r'\s+', ' ', unicodedata.normalize('NFC', l).lower()).strip() for l in lines)
print(hashlib.sha256('\n'.join(canon).encode('utf-8')).hexdigest())
" 2>/dev/null)
        expected=$(tr -d '[:space:]' < "$fixture_expected")
        if [ "$actual" = "$expected" ]; then
            echo "ok   canonicalization output matches expected.hex"
            echo "     ($actual)"
        else
            echo "FAIL canonicalization drift"
            echo "     expected: $expected"
            echo "     actual:   $actual"
            PM_FAILS=$((PM_FAILS+1))
        fi
    else
        echo "MISS fixture files (run install.sh from a checkout that includes tests/fixtures/)"
        PM_FAILS=$((PM_FAILS+1))
    fi
    echo ""

    # 5. Atomic-write fixture (informational — full sandbox check happens in T23)
    echo "--- atomic-write directive ---"
    for prompt in snapshot findings-emit survival-classifier; do
        prompt_file="$REPO/commands/_prompts/${prompt}.md"
        if [ -f "$prompt_file" ] && grep -q "os.replace" "$prompt_file"; then
            echo "ok   ${prompt}.md mentions os.replace (atomic write)"
        else
            echo "WARN ${prompt}.md missing os.replace mention"
            PM_FAILS=$((PM_FAILS+1))
        fi
    done
    echo ""

    if [ "$PM_FAILS" -eq 0 ]; then
        echo "Persona Metrics: all checks passed ✓"
    else
        echo "Persona Metrics: $PM_FAILS check(s) failed — see above"
    fi
    echo '```'
    echo ""

    echo "## Agent Budget"
    echo '```'
    BUDGET_CONFIG="$HOME/.config/monsterflow/config.json"
    if [ -f "$BUDGET_CONFIG" ]; then
        echo "Path: $BUDGET_CONFIG"
        echo ""
        cat "$BUDGET_CONFIG" 2>&1
        echo ""
        # Validate against current schema
        if [ -x "$SCRIPT_DIR/resolve-personas.sh" ]; then
            echo "--- resolver self-check (gate=check) ---"
            bash "$SCRIPT_DIR/resolve-personas.sh" check --why 2>&1 | head -10 || true
        fi
    else
        echo "(no agent-budget config — full roster dispatched per gate)"
        echo ""
        echo "To configure: bash $SCRIPT_DIR/../install.sh --reconfigure-budget"
        echo "Reference:    docs/budget.md"
    fi
    # Upgrade nudge: check whether the resolver script is present in the
    # installed clone (existing users who pulled before the feature landed
    # never re-run install.sh).
    if [ ! -x "$SCRIPT_DIR/resolve-personas.sh" ]; then
        echo ""
        echo "⚠ resolve-personas.sh missing — run install.sh to update symlinks"
    fi
    echo '```'
    echo ""

    echo "## Environment Pollution Check"
    echo '```'
    POLL_FOUND=0
    if [ -n "${PROJECT_DIR:-}" ]; then
        if [ -d "$PROJECT_DIR/docs/specs" ]; then
            echo "ok   PROJECT_DIR=$PROJECT_DIR (valid adopter project — autorun context expected)"
        else
            echo "WARN PROJECT_DIR=$PROJECT_DIR (no docs/specs/ — resolver auto-unsets at runtime)"
            echo "     This is likely shell pollution from another tool. To silence: unset PROJECT_DIR"
            POLL_FOUND=1
        fi
    fi
    if [ -n "${MONSTERFLOW_DISABLE_BUDGET:-}" ]; then
        echo "WARN MONSTERFLOW_DISABLE_BUDGET=$MONSTERFLOW_DISABLE_BUDGET (kill switch — full roster dispatched)"
        echo "     To restore budget: unset MONSTERFLOW_DISABLE_BUDGET"
        POLL_FOUND=1
    fi
    if [ -n "${MONSTERFLOW_OWNER:-}" ]; then
        echo "WARN MONSTERFLOW_OWNER=$MONSTERFLOW_OWNER (forces owner-mode in install.sh — auto-yes prompts)"
        echo "     Adopters should NOT have this set. To unset: unset MONSTERFLOW_OWNER"
        POLL_FOUND=1
    fi
    if echo "$PATH" | grep -q "coreutils/libexec/gnubin"; then
        echo "WARN coreutils/gnubin in PATH — GNU mktemp/timeout shadow BSD (macOS native)"
        echo "     Our scripts pin .XXXXXX suffix so this is tolerated, but adopter tools may break"
        POLL_FOUND=1
    fi
    if [ "$POLL_FOUND" = "0" ]; then
        echo "ok   no env pollution detected"
    fi
    echo '```'
    echo ""

    echo "## Workflow Clone State"
    echo '```'
    CLONE="$HOME/Projects/MonsterFlow"
    if [ -d "$CLONE/.git" ]; then
        echo "Path: $CLONE"
        echo ""
        echo "--- git log ---"
        git -C "$CLONE" log --oneline -5 2>&1
        echo ""
        echo "--- git status ---"
        git -C "$CLONE" status --short 2>&1 || echo "(clean)"
        echo ""
        echo "--- remote ---"
        git -C "$CLONE" remote -v 2>&1
    else
        echo "(clone not found at $CLONE)"
    fi
    echo '```'
    echo ""

    echo "## User-level CLAUDE.md"
    echo '```'
    if [ -f "$HOME/CLAUDE.md" ]; then
        echo "~/CLAUDE.md exists ($(wc -l < "$HOME/CLAUDE.md") lines)"
    else
        echo "~/CLAUDE.md missing — create one for your personal context (see QUICKSTART section 3)"
    fi
    echo '```'
    echo ""

    echo "## Autorun Policy Health"
    echo '```'
    AUTORUN_CFG="$SCRIPT_DIR/../queue/autorun.config.json"
    AUTORUN_BATCH="$SCRIPT_DIR/autorun/autorun-batch.sh"
    AUTORUN_RUN="$SCRIPT_DIR/autorun/run.sh"

    # Check 1: missing `policies` block in queue/autorun.config.json
    if [ -f "$AUTORUN_CFG" ]; then
        if python3 -c "import json,sys; d=json.load(open('$AUTORUN_CFG')); sys.exit(0 if 'policies' in d else 1)" 2>/dev/null; then
            echo "ok   queue/autorun.config.json has 'policies' block"
        else
            echo "WARN queue/autorun.config.json is missing the 'policies' block."
            echo "     Three ways to fix (pick one):"
            echo "       (a) Run: bash scripts/autorun/run.sh --mode=overnight ...  (explicit per-invocation)"
            echo "       (b) Add to crontab: bash scripts/autorun/autorun-batch.sh  (cron-context default)"
            echo "       (c) Edit queue/autorun.config.json and add a 'policies' block:"
            echo '             "policies": {'
            echo '               "verdict": "block",'
            echo '               "branch":  "block",'
            echo '               "codex_probe":  "block",'
            echo '               "verify_infra": "block"'
            echo '             }'
            echo "     For cron-driven overnight runs, recommend --mode=overnight (option a or b)."
        fi
    else
        echo "MISS queue/autorun.config.json not found at $AUTORUN_CFG"
    fi
    echo ""

    # Check 2: flock availability
    if command -v flock >/dev/null 2>&1; then
        echo "ok   flock available ($(command -v flock))"
    else
        echo "WARN flock not found — autorun will use mkdir-fallback for locking."
        echo "     Correctness is preserved (mkdir is atomic on POSIX), but performance is"
        echo "     slightly worse under contention. Stock macOS has no flock; install via:"
        echo "       brew install flock"
    fi
    echo ""

    # Check 3: timeout (BSD vs GNU). Stock macOS ships neither timeout nor gtimeout.
    if command -v timeout >/dev/null 2>&1; then
        echo "ok   timeout available ($(command -v timeout))"
    elif command -v gtimeout >/dev/null 2>&1; then
        echo "ok   gtimeout available ($(command -v gtimeout)) — Homebrew coreutils"
    else
        echo "WARN neither 'timeout' nor 'gtimeout' is on PATH."
        echo "     TIMEOUT_PERSONA / TIMEOUT_STAGE config values silently do nothing without one."
        echo "     Recommend: brew install coreutils"
    fi
    echo ""

    # Check 4: autorun-batch.sh presence + executable (per AC#24, required for cron'd queue-loop)
    if [ -f "$AUTORUN_BATCH" ]; then
        if [ -x "$AUTORUN_BATCH" ]; then
            echo "ok   scripts/autorun/autorun-batch.sh present + executable"
        else
            echo "WARN scripts/autorun/autorun-batch.sh exists but is not executable."
            echo "     Fix: chmod +x scripts/autorun/autorun-batch.sh"
        fi
    else
        echo "WARN scripts/autorun/autorun-batch.sh missing (required for cron'd queue-loop per AC#24)."
        echo "     Pull latest workflow repo + re-run install.sh."
    fi
    echo ""

    # Check 5: cron entry calls run.sh directly (silent-default-shift catch per AC#21)
    CRON_OUT="$(crontab -l 2>/dev/null)"
    if [ -n "$CRON_OUT" ]; then
        # Match run.sh in crontab — but ONLY if it's not within an autorun-batch.sh line.
        if printf '%s\n' "$CRON_OUT" | grep -E 'autorun/run\.sh' | grep -v 'autorun-batch\.sh' >/dev/null 2>&1; then
            echo "WARN crontab entry calls scripts/autorun/run.sh directly."
            echo "     This risks the silent-default-shift class (AC#21): a non-TTY cron context"
            echo "     defaults to a different policy mode than an interactive run. Recommended:"
            echo "       (a) switch to scripts/autorun/autorun-batch.sh in crontab, OR"
            echo "       (b) pass --mode=overnight explicitly on the run.sh line."
        else
            echo "ok   no risky run.sh-direct cron entries detected"
        fi
    else
        echo "ok   no crontab (or crontab unreadable) — nothing to flag"
    fi
    echo '```'
    echo ""

    echo "## Known Limitations (autorun v1)"
    echo '```'
    echo "[doctor] autorun v1 ships with known prompt-injection residual class (single-fence-spoof). See BACKLOG.md → autorun-verdict-deterministic. For untrusted spec sources, set \`verdict_policy=block\` and disable unattended auto-merge."
    echo '```'
} > "$DIAG_FILE"

# --- Mirror the autorun policy health + R18 line to stdout so the user sees it
#     during normal doctor.sh runs (not just in the filed GitHub issue). ---

echo ""
echo "=== Autorun Policy Health (mirrored from diagnostic) ==="
# Extract the section between the two markers from $DIAG_FILE.
awk '
    /^## Known Limitations/ { exit }
    /^## Autorun Policy Health/ { in_section=1 }
    in_section { print }
' "$DIAG_FILE"

echo ""
echo "=== Known Limitations (autorun v1) ==="
echo "[doctor] autorun v1 ships with known prompt-injection residual class (single-fence-spoof). See BACKLOG.md → autorun-verdict-deterministic. For untrusted spec sources, set \`verdict_policy=block\` and disable unattended auto-merge."
echo ""

# --- File the issue via gh ---

if ! command -v gh >/dev/null 2>&1; then
    echo "Error: gh CLI not installed. Install with: brew install gh && gh auth login" >&2
    echo ""
    echo "Diagnostic written to: $DIAG_FILE"
    echo "Paste this into an issue at https://github.com/${REPO}/issues manually."
    trap - EXIT  # don't delete on error so user can see it
    exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
    echo "Error: gh not authenticated. Run: gh auth login" >&2
    echo ""
    echo "Diagnostic written to: $DIAG_FILE"
    trap - EXIT
    exit 1
fi

TITLE="Diagnostic: $(hostname) $(date -u +%Y-%m-%dT%H:%M:%SZ)"

URL=$(gh issue create \
    --repo "$REPO" \
    --title "$TITLE" \
    --body-file "$DIAG_FILE" \
    --label "diagnostic" 2>&1) || {
    echo "Failed to file issue. Diagnostic written to: $DIAG_FILE" >&2
    echo "Error output above. You can open an issue manually at https://github.com/${REPO}/issues" >&2
    trap - EXIT
    exit 1
}

echo "Diagnostic filed:"
echo "$URL"
