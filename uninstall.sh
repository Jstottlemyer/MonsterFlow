#!/usr/bin/env bash
##############################################################################
# uninstall.sh — reverse of install.sh (cold-start / detector-fallback mode)
#
# Default: dry-run. Re-run with --apply to commit.
#
# What it reverses:
#   - Symlinks under ~/.claude/{commands,agents,personas,templates,hooks,
#     scripts,skills,schemas,domain-agents} + ~/.claude/settings.json whose
#     readlink target resolves into $REPO_DIR (or pre-rebrand claude-workflow)
#   - Theme stage symlinks: ~/.tmux.conf, ~/.config/cmux/cmux.json,
#     ~/.config/ghostty/config
#   - ~/.local/bin/autorun (the launcher symlink only)
#   - ~/.zshrc sentinel blocks: "MonsterFlow theme", "MonsterFlow obsidian-wiki"
#   - ~/CLAUDE.md sentinel block: "MonsterFlow CLAUDE.md baseline"
#
# What it does NOT touch (per spec OOS):
#   - Third-party tools: Obsidian.app, ~/.local/venvs/graphify, ~/.local/bin/graphify
#     (these are standalone utilities that may now be load-bearing on this
#     machine; dry-run prints manual-removal hints)
#   - $OBSIDIAN_VAULT_PATH (user data)
#   - ~/.zshenv.local (secrets file)
#   - ~/.config/monsterflow/ (user config — agent_budget knob)
#   - ~/.claude/projects/<slug>/memory/ (user-authored auto-memory)
#   - ~/.claude/usage-data/ (Claude Code telemetry)
##############################################################################
set -uo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd -P)"
HELPERS="$REPO_DIR/scripts/_uninstall_helpers.py"

# --- Output-string constants (single source for AC greps) ---
readonly PFX_REMOVED="REMOVED:"
readonly PFX_STRIPPED="STRIPPED:"
readonly PFX_RESTORED="RESTORED:"
readonly PFX_SAVED="SAVED:"
readonly PFX_SKIPPED="SKIPPED:"
readonly PFX_WARN="WARN:"
readonly PFX_WOULD="WOULD:"
readonly MSG_NOTHING_TO_REMOVE="Nothing to remove."
readonly HINT_OBSIDIAN_REMOVE="brew uninstall --cask obsidian"
readonly HINT_GRAPHIFY_REMOVE="rm -rf ~/.local/venvs/graphify ~/.local/bin/graphify"
readonly HINT_CMUX_REMOVE="brew uninstall cmux"

# --- Flag parsing ---
APPLY=0
SHOW_HELP=0
for arg in "$@"; do
    case "$arg" in
        --apply)    APPLY=1 ;;
        --dry-run)  APPLY=0 ;;
        --help|-h)  SHOW_HELP=1 ;;
        *)
            echo "uninstall.sh: unknown flag '$arg'" >&2
            echo "Usage: bash uninstall.sh [--apply | --dry-run | --help]" >&2
            exit 2
            ;;
    esac
done

if [ "$SHOW_HELP" = "1" ]; then
    cat <<EOF
uninstall.sh — reverse of install.sh (cold-start mode)

Usage:
    bash uninstall.sh              # dry-run (default; no side effects)
    bash uninstall.sh --apply      # commit the plan
    bash uninstall.sh --dry-run    # explicit no-op alias for default
    bash uninstall.sh --help       # this banner

Exit codes:
    0 — success (dry-run; clean apply; idempotent re-run)
    1 — partial-apply failure (re-runnable)
    2 — invalid invocation
    3 — catastrophic (manual cleanup required)

Repo source at $REPO_DIR is NEVER touched. rm -rf it after if desired.
EOF
    exit 0
fi

# --- Banner ---
if [ "$APPLY" = "1" ]; then
    echo "=== uninstall.sh — APPLY ==="
else
    echo "=== uninstall.sh — DRY RUN ==="
    echo "(No side effects. Re-run with --apply to commit.)"
fi
echo ""

# --- Manifest probe (cold-start: stub returns exit 2, we fall through to detector) ---
MANIFEST="$HOME/.claude/.monsterflow-install-manifest.jsonl"
USE_DETECTOR=1
if [ -f "$MANIFEST" ]; then
    # Cold-start MVP: helper returns exit 2 either way; falling through to detector regardless.
    python3 "$HELPERS" parse-manifest "$MANIFEST" >/dev/null 2>&1 || true
fi
if [ "$USE_DETECTOR" = "1" ]; then
    echo "(no install manifest yet — using filesystem-detector mode)"
    echo ""
fi

# --- Phase 1: symlinks under ~/.claude/ + theme + autorun ---
echo "Symlinks (detector — target resolves into \$REPO_DIR):"
SYMLINK_PLAN="$(python3 "$HELPERS" detect-fallback-symlinks "$HOME" "$REPO_DIR")"
SYMLINK_COUNT=0
if [ -n "$SYMLINK_PLAN" ]; then
    while IFS= read -r row; do
        [ -z "$row" ] && continue
        dst="$(python3 -c "import json,sys;print(json.loads(sys.stdin.read())['dst'])" <<< "$row")"
        src="$(python3 -c "import json,sys;print(json.loads(sys.stdin.read())['src'])" <<< "$row")"
        SYMLINK_COUNT=$((SYMLINK_COUNT + 1))
        if [ "$APPLY" = "1" ]; then
            rm -f "$dst" && echo "  $PFX_REMOVED $dst"
        else
            echo "  $PFX_WOULD remove $dst -> $src"
        fi
    done <<< "$SYMLINK_PLAN"
fi
echo "  ($SYMLINK_COUNT symlinks)"
echo ""

# --- Phase 2: backup-restore for theme files (detector-conservative) ---
echo "Backup restore (detector — conservative single-backup-older-than-symlink rule):"
BACKUP_RESTORED=0
for target in "$HOME/.tmux.conf" "$HOME/.config/cmux/cmux.json" "$HOME/.config/ghostty/config"; do
    # Skip if the symlink wasn't ours / already removed
    [ -e "$target" ] || [ -L "$target" ] || continue

    BACKUP_DECISION="$(python3 "$HELPERS" detect-fallback-backup "$target")"
    action="$(python3 -c "import json,sys;print(json.loads(sys.stdin.read()).get('action',''))" <<< "$BACKUP_DECISION" 2>/dev/null)"
    backup="$(python3 -c "import json,sys;print(json.loads(sys.stdin.read()).get('backup',''))" <<< "$BACKUP_DECISION" 2>/dev/null)"
    reason="$(python3 -c "import json,sys;print(json.loads(sys.stdin.read()).get('reason',''))" <<< "$BACKUP_DECISION" 2>/dev/null)"

    case "$action" in
        restore)
            BACKUP_RESTORED=$((BACKUP_RESTORED + 1))
            if [ "$APPLY" = "1" ]; then
                # Already removed in Phase 1 if it was our symlink; just restore
                [ -L "$target" ] && rm -f "$target"
                mv "$backup" "$target" && echo "  $PFX_RESTORED $target <- $backup"
            else
                echo "  $PFX_WOULD restore $target <- $backup"
            fi
            ;;
        skip)
            echo "  $PFX_SKIPPED $target ($reason)"
            ;;
        none)
            # No backup; symlink already removed in Phase 1 (cold-start fine — user lost the original)
            ;;
    esac
done
echo "  ($BACKUP_RESTORED restored)"
echo ""

# --- Phase 3: sentinel-block strip in ~/.zshrc + ~/CLAUDE.md ---
echo "Sentinel-block strip (full-file backup written before strip):"
STRIPPED_COUNT=0
for entry in \
    "$HOME/.zshrc:# BEGIN MonsterFlow theme:# END MonsterFlow theme" \
    "$HOME/.zshrc:# BEGIN MonsterFlow obsidian-wiki:# END MonsterFlow obsidian-wiki" \
    "$HOME/CLAUDE.md:# BEGIN MonsterFlow CLAUDE.md baseline:# END MonsterFlow CLAUDE.md baseline"
do
    file="${entry%%:*}"
    rest="${entry#*:}"
    begin="${rest%%:*}"
    end="${rest#*:}"

    [ -f "$file" ] || continue
    # Only act if the BEGIN sentinel is actually present
    if ! grep -qF "$begin" "$file" 2>/dev/null; then
        continue
    fi

    if [ "$APPLY" = "1" ]; then
        ts="$(date -u +%Y%m%d%H%M%S)"
        bak="${file}.uninstall.bak.${ts}"
        cp "$file" "$bak" && echo "  $PFX_SAVED $bak"
        if out="$(python3 "$HELPERS" strip-sentinel-block "$file" "$begin" "$end" 2>&1)"; then
            n="${out#stripped=}"
            STRIPPED_COUNT=$((STRIPPED_COUNT + n))
            echo "  $PFX_STRIPPED \"${begin#\# BEGIN }\" block from $file ($n region(s))"
        else
            echo "  $PFX_WARN $out" >&2
        fi
    else
        line_no="$(grep -nF "$begin" "$file" | head -1 | cut -d: -f1)"
        echo "  $PFX_WOULD strip \"${begin#\# BEGIN }\" block from $file (BEGIN at line $line_no)"
        echo "  $PFX_WOULD save backup to $file.uninstall.bak.<ts>"
    fi
done
echo "  ($STRIPPED_COUNT blocks stripped)"
echo ""

# --- Phase 4: third-party tools left in place (hints only) ---
echo "Third-party tools left in place (manual removal if desired):"
echo "  Obsidian.app   -> $HINT_OBSIDIAN_REMOVE"
echo "  graphify CLI   -> $HINT_GRAPHIFY_REMOVE"
echo "  cmux           -> $HINT_CMUX_REMOVE"
echo ""

# --- Tombstone (cold-start stub: prints "no-manifest") ---
if [ "$APPLY" = "1" ]; then
    python3 "$HELPERS" tombstone-manifest "$MANIFEST" >/dev/null 2>&1 || true
fi

# --- Summary ---
TOTAL=$((SYMLINK_COUNT + STRIPPED_COUNT))
if [ "$TOTAL" -eq 0 ]; then
    echo "$MSG_NOTHING_TO_REMOVE"
    echo "(MonsterFlow appears to be uninstalled already.)"
    exit 0
fi

if [ "$APPLY" = "1" ]; then
    echo "=== Uninstall complete ==="
    echo "Open a new shell so ~/.zshrc changes take effect."
    echo "Sentinel-block backups at ~/*.uninstall.bak.* — delete when satisfied."
else
    echo "Re-run with --apply to perform the above. No changes made."
fi
exit 0
