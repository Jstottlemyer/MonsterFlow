#!/bin/bash
set -euo pipefail

# === Block 0: Function Definitions (no execution yet) ===
# These must be defined before they're called below.

parse_flags() {
    # Parse argv into env vars. Defaults: all flags off.
    SHOW_HELP=0
    NO_INSTALL=0
    INSTALL_THEME_FORCED=0   # --install-theme set
    NO_THEME=0               # wins over --install-theme
    NO_ONBOARD=0
    FORCE_ONBOARD=0
    NON_INTERACTIVE_FLAG=0   # explicit --non-interactive
    RECONFIGURE_BUDGET=0     # account-type-agent-scaling

    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|--help)             SHOW_HELP=1 ;;
            --no-install)          NO_INSTALL=1 ;;
            --install-theme)       INSTALL_THEME_FORCED=1 ;;
            --no-theme)            NO_THEME=1 ;;
            --non-interactive)     NON_INTERACTIVE_FLAG=1 ;;
            --no-onboard)          NO_ONBOARD=1 ;;
            --force-onboard)       FORCE_ONBOARD=1 ;;
            --reconfigure-budget)  RECONFIGURE_BUDGET=1 ;;
            *)                     echo "Unknown flag: $1" >&2; echo "Run with --help for usage." >&2; exit 2 ;;
        esac
        shift
    done

    # Resolve --non-interactive (explicit flag wins; else auto-detect via [ -t 0 ];
    # MONSTERFLOW_FORCE_INTERACTIVE=1 overrides auto-detect)
    if [ "$NON_INTERACTIVE_FLAG" = "1" ]; then
        NON_INTERACTIVE=1
    elif [ "${MONSTERFLOW_FORCE_INTERACTIVE:-0}" = "1" ]; then
        NON_INTERACTIVE=0
    elif [ -t 0 ]; then
        NON_INTERACTIVE=0
    else
        NON_INTERACTIVE=1
    fi

    export NO_INSTALL INSTALL_THEME_FORCED NO_THEME NON_INTERACTIVE NO_ONBOARD FORCE_ONBOARD
    # Codex impl review caught: scripts/onboard.sh + W4 tests read
    # MONSTERFLOW_*-prefixed names per documented env contract.
    # Mirror the internal names to the prefixed ones so child processes see both.
    export MONSTERFLOW_NON_INTERACTIVE="$NON_INTERACTIVE"
    export MONSTERFLOW_FORCE_ONBOARD="$FORCE_ONBOARD"
    export MONSTERFLOW_NO_ONBOARD="$NO_ONBOARD"
}

print_help() {
    cat <<'HELP'
MonsterFlow install.sh — Claude Workflow Pipeline installer

Usage: ./install.sh [flags]

Flags:
  -h, --help              Show this help and exit (no I/O)
  --no-install            Bypass ALL detection and enforcement (CI escape hatch)
  --install-theme         Force theme install (overrides default-N for adopters)
  --no-theme              Skip theme install (wins over --install-theme)
  --non-interactive       Disable all prompts; auto-detected when stdin is not a TTY
  --no-onboard            Suppress onboard panel
  --force-onboard         Run onboard panel even under --non-interactive
  --reconfigure-budget    Re-run only the agent-budget Q&A (writes
                          ~/.config/monsterflow/config.json); short-circuits
                          all other install steps. See docs/budget.md.

Env vars:
  MONSTERFLOW_OWNER=1|0           Force owner/adopter mode (test ergonomics)
  MONSTERFLOW_FORCE_INTERACTIVE=1 Override [ -t 0 ] auto-detect
  MONSTERFLOW_INSTALL_TEST=1      Short-circuit plugin/test prompts (test harness only)
  PERSONA_METRICS_GITIGNORE=1|0   Gitignore persona-metrics artifacts (1=adopter default)
  MONSTERFLOW_APPLICATIONS_DIR=<path>  Override /Applications for Obsidian.app detection (test seam; matches MONSTERFLOW_HASCMD_OVERRIDE pattern)

For details: docs/specs/install-rewrite/spec.md
HELP
}

# === Block 1: Flag Parse (no I/O yet) ===
parse_flags "$@"
[ "$SHOW_HELP" = "1" ] && { print_help; exit 0; }

# === Agent-budget Q&A (account-type-agent-scaling) ===
# Gated behind --reconfigure-budget. Short-circuits all other install steps so
# users can re-tune budget/pins without re-running symlink + brew + theme.
# See docs/budget.md for the full schema and reset paths.
prompt_budget_qa() {
    local repo_dir="$1"
    local resolver="$repo_dir/scripts/resolve-personas.sh"
    if [ ! -x "$resolver" ]; then
        echo "✗ resolve-personas.sh not found at $resolver" >&2
        echo "  Re-clone the repo or run install.sh without --reconfigure-budget first." >&2
        return 1
    fi

    local config_dir="$HOME/.config/monsterflow"
    local config_file="$config_dir/config.json"
    mkdir -p "$config_dir"

    echo ""
    echo "=== Agent Budget Configuration ==="
    echo ""
    echo "Per-gate Claude persona cap. Codex-adversary is additive (not counted)."
    echo "Range: 1–8. Higher = more reviewers per gate, more tokens."
    echo ""

    local pro_answer pro_default_budget
    read -rp "Are you on the Claude Pro plan (\$20/mo)? Pro has tighter rate limits. [y/N]: " pro_answer
    if [[ "$pro_answer" =~ ^[Yy]$ ]]; then
        pro_default_budget=3
        local tier_hint="pro"
    else
        pro_default_budget=6
        local tier_hint="free-or-max"
    fi

    local budget
    while :; do
        read -rp "How many Claude personas per gate? [default: $pro_default_budget]: " budget
        budget="${budget:-$pro_default_budget}"
        if ! [[ "$budget" =~ ^[0-9]+$ ]]; then
            echo "  ✗ must be an integer 1–8"
            continue
        fi
        if [ "$budget" -lt 1 ] || [ "$budget" -gt 8 ]; then
            echo "  ✗ out of range; must be 1–8"
            continue
        fi
        break
    done

    # Per-gate pin prompts. Validate against on-disk personas (per the locked
    # qualifying-row definition in docs/specs/account-type-agent-scaling/spec.md).
    declare -a GATES=(spec-review plan check)
    declare -a GATE_DIRS=(review plan check)
    declare -a GATE_DEFAULTS=(requirements integration scope-discipline)
    local pins_json="{}"
    local i=0
    for gate in "${GATES[@]}"; do
        local persona_dir="$repo_dir/personas/${GATE_DIRS[$i]}"
        local available=""
        if [ -d "$persona_dir" ]; then
            available="$(cd "$persona_dir" && ls *.md 2>/dev/null | sed 's/\.md$//' | tr '\n' ' ')"
        fi
        local default_pin="${GATE_DEFAULTS[$i]}"
        echo ""
        echo "Gate: $gate"
        echo "  available: $available"
        local pin_input
        while :; do
            read -rp "  Default pin for $gate (always runs first; blank to skip) [default: $default_pin]: " pin_input
            pin_input="${pin_input:-$default_pin}"
            if [ "$pin_input" = "none" ] || [ "$pin_input" = "-" ]; then
                pin_input=""
                break
            fi
            # Validate against on-disk
            if [ -f "$persona_dir/$pin_input.md" ]; then
                break
            fi
            echo "  ✗ '$pin_input' not in personas/${GATE_DIRS[$i]}/ — try one of: $available"
        done
        if [ -n "$pin_input" ]; then
            pins_json=$(python3 -c "
import json, sys
d = json.loads('''$pins_json''')
d['$gate'] = ['$pin_input']
print(json.dumps(d))
")
        fi
        i=$((i + 1))
    done

    # Atomic write — preserve unknown keys via read-modify-write.
    local tmp="$config_file.tmp.$$"
    python3 - "$config_file" "$tmp" "$budget" "$tier_hint" "$pins_json" <<'PY'
import json, os, sys
config_file, tmp, budget, tier_hint, pins_json = sys.argv[1:6]
existing = {}
if os.path.exists(config_file):
    try:
        with open(config_file) as f:
            existing = json.load(f)
    except Exception:
        existing = {}
existing['$schema_version'] = 1
existing['agent_budget'] = int(budget)
existing['persona_pins'] = json.loads(pins_json)
existing['tier_hint'] = tier_hint
existing.setdefault('codex_disabled', False)
with open(tmp, 'w') as f:
    json.dump(existing, f, indent=2)
    f.write('\n')
    f.flush()
    os.fsync(f.fileno())
os.replace(tmp, config_file)
PY

    chmod 644 "$config_file" 2>/dev/null || true

    echo ""
    echo "✓ Wrote $config_file"
    echo ""
    echo "  agent_budget = $budget   tier_hint = $tier_hint"
    echo ""
    echo "Reset paths:"
    echo "  - Re-run:  bash $repo_dir/install.sh --reconfigure-budget"
    echo "  - Tell Claude:  \"Reconfigure my agent budget\" (Claude calls this same flag)"
    echo "  - Manual:  edit $config_file (schema: bash $repo_dir/scripts/resolve-personas.sh --print-schema)"
    echo ""
    echo "Note: Codex-adversary runs in addition to your budget when authenticated."
    echo "      Disable with codex_disabled=true in config.json or MONSTERFLOW_DISABLE_BUDGET=1 (full kill switch)."
}

if [ "$RECONFIGURE_BUDGET" = "1" ]; then
    BUDGET_REPO_DIR="$(cd "$(dirname "$0")" && pwd -P)"
    if [ -t 0 ]; then
        prompt_budget_qa "$BUDGET_REPO_DIR" || exit $?
        exit 0
    else
        echo "✗ --reconfigure-budget requires an interactive terminal (TTY)." >&2
        echo "  For headless config, edit ~/.config/monsterflow/config.json directly." >&2
        echo "  Schema: bash $BUDGET_REPO_DIR/scripts/resolve-personas.sh --print-schema" >&2
        exit 1
    fi
fi

# === Block 2: OS Guards (no repo I/O yet) ===
if [ "$(uname)" != "Darwin" ]; then
    echo "MonsterFlow install.sh is macOS-only." >&2
    echo "Linux support tracked in BACKLOG.md as out-of-scope for v1." >&2
    exit 1
fi
MACOS_VER="$(sw_vers -productVersion 2>/dev/null || echo 0)"
MACOS_MAJOR="${MACOS_VER%%.*}"
# cmux requires macOS >= 14; if older, demote cmux from RECOMMENDED to OPTIONAL
CMUX_DEMOTE=0
if [ "${MACOS_MAJOR:-0}" -lt 14 ] 2>/dev/null; then
    CMUX_DEMOTE=1
fi

# === Block 3: Repo paths + banner (now safe to do I/O) ===
# Use pwd -P to resolve symlinks consistently with owner-detect logic
REPO_DIR="$(cd "$(dirname "$0")" && pwd -P)"
CLAUDE_DIR="$HOME/.claude"
VERSION="$(cat "$REPO_DIR/VERSION" 2>/dev/null | tr -d '[:space:]' || echo 'unknown')"

# Source the python_pip helper (W1 task 1.6)
# python_pip auto-detects pip3 vs pip vs python3 -m pip; install.sh has zero pip
# calls today but the source is forward-compat plumbing.
[ -f "$REPO_DIR/scripts/lib/python-pip.sh" ] && . "$REPO_DIR/scripts/lib/python-pip.sh"

# Set HOMEBREW_NO_AUTO_UPDATE for the rest of the script — non-negotiable for
# the <3s repeat-run budget when brew is invoked.
export HOMEBREW_NO_AUTO_UPDATE=1

# SIGINT trap + scratch dir (W2 task 2.2): scoped scratch so cleanup_partial
# can rm -rf without nuking attacker-staged files. All atomic writes use
# $INSTALL_SCRATCH/<name>.tmp then mv -f to final.
INSTALL_SCRATCH="$(mktemp -d -t monsterflow-install)"
cleanup_partial() {
    rm -rf "$INSTALL_SCRATCH"
    echo "" >&2
    echo "⚠ install.sh interrupted; partial state cleaned up." >&2
    echo "  Re-run when ready." >&2
    exit 130
}
trap cleanup_partial INT TERM

echo "=== Claude Workflow Pipeline Installer — v${VERSION} ==="
echo ""
echo "Repo:   $REPO_DIR"
echo "Target: $CLAUDE_DIR"
echo ""

# --- Migration detect (W2 task 2.3) ---
# Detect prior MonsterFlow (or pre-rebrand claude-workflow) install via the
# spec.md symlink target. Runs before any symlink mutation so opt-out cleanly
# bails. Pulls version from $VERSION (already loaded above).
PRIOR_INSTALL=0
if [ -L "$CLAUDE_DIR/commands/spec.md" ]; then
    PRIOR_TARGET="$(readlink "$CLAUDE_DIR/commands/spec.md")"
    case "$PRIOR_TARGET" in
        */MonsterFlow/*|*/claude-workflow/*) PRIOR_INSTALL=1 ;;
    esac
fi
if [ "$PRIOR_INSTALL" = "1" ]; then
    echo "⬆ Detected prior MonsterFlow install — upgrading to v${VERSION}."
    cat <<UPGRADE
  What's new in v${VERSION}:
    - install.sh now installs brew tools for you (was: warn-only)
    - Optional shell theme (~/.tmux.conf, cmux config, prompt colors)
    - New flags: --no-install, --no-theme, --non-interactive, --no-onboard
    - cmux added to RECOMMENDED; tmux moved to OPTIONAL
    - macOS-only (Linux guard added)
UPGRADE
    # v0.9.0 one-time migration banner — pipeline-gate-permissiveness default-flip.
    # Sentinel filename includes the version so future flips reuse a NEW sentinel.
    # Per feedback_tilde_expansion_in_bash_config_reads.md: tilde-expand before write.
    GATE_PERMISSIVENESS_SENTINEL="~/.claude/.gate-permissiveness-migration-shown"
    GATE_PERMISSIVENESS_SENTINEL="${GATE_PERMISSIVENESS_SENTINEL/#\~/$HOME}"
    if [ ! -f "$GATE_PERMISSIVENESS_SENTINEL" ]; then
        cat <<'GATE_PERMISSIVENESS_BANNER'
    - Pipeline gates default to permissive (was: strict). Pin gate_mode: strict in any spec frontmatter to preserve old halt-on-anything behavior. See docs/CHANGELOG.md#v090 for migration details.
GATE_PERMISSIVENESS_BANNER
        mkdir -p "$(dirname "$GATE_PERMISSIVENESS_SENTINEL")"
        touch "$GATE_PERMISSIVENESS_SENTINEL"
    fi
    if [ "$NON_INTERACTIVE" = "0" ]; then
        read -rp "Proceed with upgrade? [Y/n]: " UPGRADE_CONFIRM
        [[ "$UPGRADE_CONFIRM" =~ ^[Nn]$ ]] && exit 0
    fi
    echo ""
fi

# --- Prerequisites (warn only, don't block) ---
# bash scripts don't inherit zsh's PATH from .zshrc, so brew-installed
# tools at /opt/homebrew/bin (Apple Silicon) or /usr/local/bin (Intel)
# may not be found by `command -v`. Check both.
has_cmd() {
    # Test hook (D11): when set, ONLY check stub dir — bypass real PATH/brew dirs.
    # In production MONSTERFLOW_HASCMD_OVERRIDE is unset → behaves as today.
    if [ -n "${MONSTERFLOW_HASCMD_OVERRIDE:-}" ]; then
        [ -x "$MONSTERFLOW_HASCMD_OVERRIDE/$1" ] && return 0 || return 1
    fi
    command -v "$1" >/dev/null 2>&1 \
        || [ -x "/opt/homebrew/bin/$1" ] \
        || [ -x "/usr/local/bin/$1" ]
}

# Three tiers: REQUIRED (pipeline broken without), RECOMMENDED (features
# degrade silently — hooks no-op, /autorun can't make PRs, etc.), OPTIONAL
# (silent-skip features like Codex).
REQUIRED_MISSING=()
RECOMMENDED_MISSING=()
OPTIONAL_MISSING=()

# REQUIRED — pipeline cannot function without these
has_cmd git     || REQUIRED_MISSING+=("git — install Xcode CLI tools (xcode-select --install) or brew install git")
has_cmd claude  || REQUIRED_MISSING+=("claude (Claude Code CLI) — https://claude.com/claude-code")
has_cmd python3 || REQUIRED_MISSING+=("python3 — brew install python")
has_cmd brew    || REQUIRED_MISSING+=("brew (Homebrew) — install from https://brew.sh:
      /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"")

# Python version check (≥ 3.9 — older versions miss f-string and walrus features used in scripts)
if has_cmd python3; then
    PY_VER="$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null || echo "0.0")"
    PY_MAJ="${PY_VER%%.*}"
    PY_MIN="${PY_VER#*.}"
    if [ "${PY_MAJ:-0}" -lt 3 ] 2>/dev/null || { [ "${PY_MAJ:-0}" -eq 3 ] && [ "${PY_MIN:-0}" -lt 9 ]; } 2>/dev/null; then
        REQUIRED_MISSING+=("python3 ≥ 3.9 (detected $PY_VER) — brew install python")
    fi
fi

# RECOMMENDED — silently degraded features without them
has_cmd gh         || RECOMMENDED_MISSING+=("gh (GitHub CLI, /autorun needs it for PR ops) — brew install gh && gh auth login")
has_cmd shellcheck || RECOMMENDED_MISSING+=("shellcheck (PostToolUse hook on .sh edits — silently no-ops without it) — brew install shellcheck")
has_cmd jq         || RECOMMENDED_MISSING+=("jq (PostToolUse hook on .json edits — silently no-ops without it) — brew install jq")
has_cmd tmux       || RECOMMENDED_MISSING+=("tmux (recommended for overnight /autorun runs) — brew install tmux")

# PATH sanity — ~/.local/bin must be in PATH for `autorun` symlink to resolve
if ! echo ":$PATH:" | grep -q ":$HOME/.local/bin:"; then
    # shellcheck disable=SC2016  # literal $HOME/$PATH are intentional in the user-facing instruction
    RECOMMENDED_MISSING+=('$HOME/.local/bin not in PATH — add `export PATH="$HOME/.local/bin:$PATH"` to ~/.zshrc so `autorun` runs from anywhere')
fi

# OPTIONAL — features silent-skip when absent
has_cmd codex || OPTIONAL_MISSING+=("codex (adversarial review at /spec-review, /check, /build — silent skip) — npm i -g @openai/codex")

# Display findings, tier by tier
if [ ${#REQUIRED_MISSING[@]} -gt 0 ]; then
    echo "✗ REQUIRED — pipeline will not work without these:"
    for tool in "${REQUIRED_MISSING[@]}"; do echo "  - $tool"; done
    echo ""
fi
if [ ${#RECOMMENDED_MISSING[@]} -gt 0 ]; then
    echo "⚠ RECOMMENDED — features degrade silently without these:"
    for tool in "${RECOMMENDED_MISSING[@]}"; do echo "  - $tool"; done
    echo ""
fi
if [ ${#OPTIONAL_MISSING[@]} -gt 0 ]; then
    echo "○ OPTIONAL — silent skip if absent:"
    for tool in "${OPTIONAL_MISSING[@]}"; do echo "  - $tool"; done
    echo ""
fi

# --- Install missing brew tools (W2 task 2.6 — NEW brew-bundle install stage) ---
# Tier-split decline behavior (2.7): REQUIRED missing → hard-stop unless --no-install;
# RECOMMENDED missing → offer install; decline = loud notice + continue.
do_install_missing() {
    if [ "$NO_INSTALL" = "1" ]; then
        echo "Skipped install per --no-install."
        return 0
    fi
    # If REQUIRED missing, hard-stop UNLESS --no-install (handled above)
    if [ "${#REQUIRED_MISSING[@]}" -ne 0 ]; then
        echo "Install the REQUIRED tools above and re-run install.sh." >&2
        exit 1
    fi
    # If only RECOMMENDED missing, offer install
    if [ "${#RECOMMENDED_MISSING[@]}" -eq 0 ]; then
        return 0
    fi
    echo ""
    echo "About to install via Homebrew (uses Brewfile at repo root):"
    awk '/^brew "/||/^cask "/{print "  -",$0}' "$REPO_DIR/Brewfile"
    echo ""
    echo "Resolved transitive set:"
    BREW_FORMULAS=$(awk -F'"' '/^brew "/{print $2}' "$REPO_DIR/Brewfile")
    BREW_CASKS=$(awk -F'"' '/^cask "/{print $2}' "$REPO_DIR/Brewfile")
    # shellcheck disable=SC2086  # word-splitting intentional: pass list to brew deps
    [ -n "$BREW_FORMULAS" ] && brew deps --include-build --formula $BREW_FORMULAS 2>/dev/null | sed 's/^/    /' | head -30 || true
    if [ -n "$BREW_CASKS" ]; then
        for c in $BREW_CASKS; do
            brew deps --cask "$c" 2>/dev/null | sed "s/^/    [cask:$c] /" || true
        done
    fi
    echo ""
    if [ "$NON_INTERACTIVE" = "0" ]; then
        read -rp "Proceed? [Y/n]: " CONFIRM
        if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
            echo "⚠ Continuing without [${RECOMMENDED_MISSING[*]}]." >&2
            echo "  Features will silently no-op (PR ops, shellcheck hook, etc.)." >&2
            echo "  Re-run install.sh anytime to install." >&2
            return 0
        fi
    fi
    # Codex impl review #4: CMUX_DEMOTE wiring — on macOS <14, generate a
    # filtered Brewfile without the cmux cask line and pass that to brew.
    BREWFILE_FOR_INSTALL="$REPO_DIR/Brewfile"
    if [ "${CMUX_DEMOTE:-0}" = "1" ]; then
        BREWFILE_FOR_INSTALL="$INSTALL_SCRATCH/Brewfile.no-cmux"
        grep -v '^cask "cmux"' "$REPO_DIR/Brewfile" > "$BREWFILE_FOR_INSTALL"
        echo "  (cmux skipped: requires macOS ≥14, detected $MACOS_VER)" >&2
    fi
    if ! HOMEBREW_NO_AUTO_UPDATE=1 brew bundle --file="$BREWFILE_FOR_INSTALL" install; then
        echo "⚠ brew bundle failed for some formulas." >&2
        echo "  Common causes: network, broken bottle, locked Cellar." >&2
        echo "  Fix and re-run install.sh. Symlinks were skipped." >&2
        exit 1
    fi
    echo "✓ brew bundle complete"
}
do_install_missing

# --- Helper ---
link_file() {
    local src="$1"
    local dst="$2"
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
        # S7 fix: timestamped backup so re-runs don't overwrite a prior .bak
        local bak_ts
        bak_ts="${dst}.bak.$(date +%Y%m%d%H%M%S)"
        echo "  BACKUP: $dst → $bak_ts"
        mv "$dst" "$bak_ts"
    fi
    # -n: treat existing symlink-to-directory as a file, replace it
    # (Codex impl review caught: bare -sf would link INTO the target dir)
    ln -sfn "$src" "$dst"
    echo "  LINKED: $dst → $src"
}

# Remove orphaned symlinks under $dir whose target points into a MonsterFlow
# (or pre-rebrand claude-workflow) repo path that no longer exists. Catches
# rename drift like commands/plan.md → commands/blueprint.md, where the new
# link gets created by the loop below but the old link would otherwise linger
# and return stale content. Only touches symlinks pointing into known repo
# paths — never deletes user files or symlinks to unrelated targets.
clean_stale_symlinks() {
    local dir="$1"
    [ -d "$dir" ] || return 0
    local f target
    for f in "$dir"/*; do
        [ -L "$f" ] || continue
        target="$(readlink "$f")"
        case "$target" in
            */MonsterFlow/*|*/claude-workflow/*) ;;
            *) continue ;;
        esac
        if [ ! -e "$target" ]; then
            echo "  REMOVED: $f (stale → $target)"
            rm -f "$f"
        fi
    done
}

# --- Ensure directories exist ---
mkdir -p "$CLAUDE_DIR/commands"
mkdir -p "$CLAUDE_DIR/personas"
mkdir -p "$CLAUDE_DIR/templates"

# --- Pipeline commands ---
echo "Installing pipeline commands..."
clean_stale_symlinks "$CLAUDE_DIR/commands"
for cmd in "$REPO_DIR"/commands/*.md; do
    link_file "$cmd" "$CLAUDE_DIR/commands/$(basename "$cmd")"
done
# Static command assets (e.g., pre-rendered reference cards) — served via cat to skip LLM generation
for asset in "$REPO_DIR"/commands/*.txt; do
    [ -e "$asset" ] || continue
    link_file "$asset" "$CLAUDE_DIR/commands/$(basename "$asset")"
done

# --- Persona Metrics prompts (commands/_prompts/) ---
if [ -d "$REPO_DIR/commands/_prompts" ]; then
    echo ""
    echo "Installing persona-metrics prompts..."
    mkdir -p "$CLAUDE_DIR/commands/_prompts"
    clean_stale_symlinks "$CLAUDE_DIR/commands/_prompts"
    for prompt in "$REPO_DIR"/commands/_prompts/*.md; do
        [ -e "$prompt" ] || continue
        link_file "$prompt" "$CLAUDE_DIR/commands/_prompts/$(basename "$prompt")"
    done
fi

# --- Personas ---
echo ""
echo "Installing agent personas..."
clean_stale_symlinks "$CLAUDE_DIR/personas"
# Top-level personas (judge, synthesis — used by /spec-review, /blueprint, /check)
for persona in "$REPO_DIR"/personas/*.md; do
    [ -e "$persona" ] || continue
    link_file "$persona" "$CLAUDE_DIR/personas/$(basename "$persona")"
done
# Stage-specific personas. Stage dir names mirror personas/<stage>/ on disk:
# review (for /spec-review gate), design (for /blueprint gate), check, code-review.
for stage in check code-review design review; do
    mkdir -p "$CLAUDE_DIR/personas/$stage"
    clean_stale_symlinks "$CLAUDE_DIR/personas/$stage"
    for persona in "$REPO_DIR"/personas/"$stage"/*.md; do
        link_file "$persona" "$CLAUDE_DIR/personas/$stage/$(basename "$persona")"
    done
done
# Clean up pre-rename stage dirs (e.g., personas/plan/ after the plan→design rename).
# Prunes stale symlinks first, then rmdir if the dir is now empty. rmdir refuses
# non-empty dirs, so .bak files from prior installs are preserved.
for stale_stage in plan; do
    if [ -d "$CLAUDE_DIR/personas/$stale_stage" ]; then
        clean_stale_symlinks "$CLAUDE_DIR/personas/$stale_stage"
        rmdir "$CLAUDE_DIR/personas/$stale_stage" 2>/dev/null && \
            echo "  REMOVED: $CLAUDE_DIR/personas/$stale_stage (renamed to design/)" || true
    fi
done

# >>> dynamic-roster-1-tags: schemas/ propagation
# Symlinks JSON Schema files into adopter's ~/.claude/schemas/ so future
# slices can resolve $ref by relative path. Sentinel-bracketed for
# idempotent re-runs (matches feedback_install_adopter_default_flip.md).
mkdir -p "$CLAUDE_DIR/schemas"
echo ""
echo "Installing JSON schemas..."
clean_stale_symlinks "$CLAUDE_DIR/schemas"
for schema in "$REPO_DIR"/schemas/*.json; do
    [ -f "$schema" ] || continue
    link_file "$schema" "$CLAUDE_DIR/schemas/$(basename "$schema")"
done
# <<< dynamic-roster-1-tags: schemas/ propagation

# --- Domain agents ---
# Link into a stable user-agnostic path so /kickoff can always find them
# regardless of where the user cloned the repo.
echo ""
echo "Installing domain agents..."
mkdir -p "$CLAUDE_DIR/domain-agents"
for domain_dir in "$REPO_DIR"/domains/*/agents; do
    [ -d "$domain_dir" ] || continue
    domain_name=$(basename "$(dirname "$domain_dir")")
    mkdir -p "$CLAUDE_DIR/domain-agents/$domain_name"
    clean_stale_symlinks "$CLAUDE_DIR/domain-agents/$domain_name"
    for agent in "$domain_dir"/*.md; do
        [ -e "$agent" ] || continue
        link_file "$agent" "$CLAUDE_DIR/domain-agents/$domain_name/$(basename "$agent")"
    done
done

# --- Templates ---
echo ""
echo "Installing templates..."
clean_stale_symlinks "$CLAUDE_DIR/templates"
for tmpl in "$REPO_DIR"/templates/*.md; do
    link_file "$tmpl" "$CLAUDE_DIR/templates/$(basename "$tmpl")"
done

# --- Settings ---
echo ""
echo "Installing settings..."
link_file "$REPO_DIR/settings/settings.json" "$CLAUDE_DIR/settings.json"

# --- Scripts ---
echo ""
echo "Installing scripts..."
mkdir -p "$CLAUDE_DIR/scripts"
clean_stale_symlinks "$CLAUDE_DIR/scripts"
for script in "$REPO_DIR"/scripts/*.py "$REPO_DIR"/scripts/*.sh; do
    [ -e "$script" ] || continue
    link_file "$script" "$CLAUDE_DIR/scripts/$(basename "$script")"
done

# --- Autorun scripts ---
echo ""
echo "Installing autorun scripts..."
mkdir -p "$REPO_DIR/scripts/autorun"
find "$REPO_DIR/scripts/autorun" -type f \( -name "*.sh" -o -name "autorun" \) -exec chmod +x {} \;
mkdir -p "$HOME/.local/bin"
ln -sf "$REPO_DIR/scripts/autorun/autorun" "$HOME/.local/bin/autorun"
echo "  LINKED: autorun -> $HOME/.local/bin/autorun"

# Top-level helper; used by do_theme_install and install_obsidian_env. Hoisted here so do_knowledge_layer runs cleanly under --no-theme.
posix_quote() {
    local s="$1"
    printf "'%s'" "${s//\'/\'\\\'\'}"
}

# parse_obsidian_config: read ~/.obsidian-wiki/config and emit the expanded OBSIDIAN_VAULT_PATH.
# Returns 0 on success (writes path to stdout); 1 on absent/unparseable.
# SECURITY: never source, never eval — the config file is user-writable; treating
# its bytes as shell would be arbitrary code execution. This parser uses only
# grep/sed/parameter substitution.
#
# Grammar (narrow, per D3 + Codex iter3):
#   Accepts: [export ]OBSIDIAN_VAULT_PATH=value
#            [export ]OBSIDIAN_VAULT_PATH="value"
#   No single quotes. No escaped quotes inside double quotes.
#   # introduces a comment ONLY outside double-quoted strings.
#   Leading whitespace allowed. Trailing whitespace stripped. CRLF tolerated.
#   Last-wins on duplicate keys. Unknown keys silently ignored.
#   Malformed lines: silently skipped; one-line notice to stderr if any skipped.
parse_obsidian_config() {
    local cfg="${HOME}/.obsidian-wiki/config"
    [ -f "$cfg" ] || return 1
    local skipped=0
    local raw value

    # Extract last line matching OBSIDIAN_VAULT_PATH= (handles `export` prefix + leading space)
    raw="$(grep -E '^[[:space:]]*(export[[:space:]]+)?OBSIDIAN_VAULT_PATH=' "$cfg" | tr -d '\r' | tail -1)"
    [ -n "$raw" ] || return 1

    # Strip leading whitespace, optional `export `, and `OBSIDIAN_VAULT_PATH=` prefix
    value="${raw#*OBSIDIAN_VAULT_PATH=}"

    # If double-quoted, take content between first and last `"`; # inside quotes is literal
    if [[ "$value" =~ ^\".*\"[[:space:]]*(#.*)?$ ]]; then
        value="${value%\"*}"
        value="${value#\"}"
    else
        # Detect obviously malformed: starts with single-quote or escaped-quote
        if [[ "$value" =~ ^\' ]] || [[ "$value" =~ ^\\\" ]]; then
            skipped=$((skipped + 1))
            [ "$skipped" -gt 0 ] && echo "  ⚠ parse_obsidian_config: skipped ${skipped} malformed line(s)" >&2
            return 1
        fi
        # Unquoted: strip trailing `#...` comment then trailing whitespace
        value="${value%%#*}"
        value="${value%%[[:space:]]*}"
    fi

    # Tilde expansion (bash tilde doesn't expand in variable assignments from external data)
    value="${value/#\~/$HOME}"

    [ -n "$value" ] || return 1
    echo "$value"
    return 0
}

# --- Wave 2: Detection helpers + renderer ---
# All helpers are read-only; stdout = status token; always return 0.
# Status token grammar (D1):
#   graphify:     "ready" | "can-install"
#   wiki:         "ready" | "manual:N/6"
#   obsidian-env: "ready:<path>" | "can-install" | "warn:<path>"
#   obsidian-app: "ready" | "can-install"
#   cmux:         "ready" | "drift" | "na"

# Task 2.1 — detect_graphify_cli
# Per EC1: any working graphify on PATH counts (brew tap, pipx, manual install, or our venv).
# Uses has_cmd (MF3) — handles MONSTERFLOW_HASCMD_OVERRIDE + Homebrew paths.
detect_graphify_cli() {
    if has_cmd graphify; then
        echo "ready"
    else
        echo "can-install"
    fi
    return 0
}

# Task 2.2 — detect_wiki_skills
# Explicit name array (NOT a glob count) per Completeness OB3.
# If upstream ships a 7th skill, this array is the ONE place to update.
detect_wiki_skills() {
    local names=(wiki-ingest wiki-update wiki-query wiki-export wiki-lint wiki-capture)
    local present=0 n
    for n in "${names[@]}"; do
        [ -f "$HOME/.claude/skills/$n/SKILL.md" ] && present=$(( present + 1 ))
    done
    if [ "$present" -eq 6 ]; then
        echo "ready"
    else
        echo "manual:$present/6"
    fi
    return 0
}

# Task 2.3 — detect_obsidian_env
# Depends on parse_obsidian_config (Wave 1 task 1.3).
# ready    — config parses, vault dir exists
# warn     — config parses, vault path configured but directory doesn't exist (EC4)
# can-install — no config or config is unparseable
detect_obsidian_env() {
    local path
    if path="$(parse_obsidian_config)"; then
        if [ -d "$path" ]; then
            echo "ready:$path"
        else
            echo "warn:$path"
        fi
    else
        echo "can-install"
    fi
    return 0
}

# Task 2.4 — detect_obsidian_app
# Status token: "ready" | "can-install"  (no "manual" token — D11/MF1; brew is REQUIRED-tier).
# Uses ${MONSTERFLOW_APPLICATIONS_DIR:-/Applications} test seam (D6/MF6).
detect_obsidian_app() {
    local dir="${MONSTERFLOW_APPLICATIONS_DIR:-/Applications}"
    if [ -d "$dir/Obsidian.app" ]; then
        echo "ready"
    else
        echo "can-install"
    fi
    return 0
}

# Task 2.5 — detect_cmux_drift
# Uses has_cmd (MF3).
# ready — both config symlink and binary present
# drift — config symlink present but binary absent (the case this spec catches)
# na    — no config symlink (theme stage didn't run; nothing to report)
detect_cmux_drift() {
    local cfg="$HOME/.config/cmux/cmux.json"
    local has_cfg=0
    [ -L "$cfg" ] && has_cfg=1
    if [ "$has_cfg" -eq 0 ]; then
        echo "na"
    elif has_cmd cmux; then
        echo "ready"
    else
        echo "drift"
    fi
    return 0
}

# Task 2.6 — render_knowledge_summary
# Args: <graphify-status> <wiki-status> <obsidian-env-status> <obsidian-app-status> <cmux-status>
# Row order matches spec.md UX exactly so AC1 positional greps work.
# Column width ~20 chars to the colon.
# Closing "all present" line fires ONLY when every row is ready (cmux na counts as ready).
render_knowledge_summary() {
    local g="$1" w="$2" e="$3" a="$4" c="$5"
    echo ""
    echo "=== Knowledge Layer ==="
    # graphify
    case "$g" in
        ready) echo "graphify CLI:        ✓" ;;
        *)     echo "graphify CLI:        ✗ (not installed)" ;;
    esac
    # wiki
    case "$w" in
        ready)      echo "wiki skills:         ✓ (6/6)" ;;
        manual:0/6) echo "wiki skills:         ✗ (0/6)" ;;
        manual:*)   echo "wiki skills:         ✗ (${w#manual:})" ;;
    esac
    # obsidian-env
    case "$e" in
        ready:*)     echo "OBSIDIAN_VAULT_PATH: ✓ → ${e#ready:}" ;;
        warn:*)      echo "OBSIDIAN_VAULT_PATH: ⚠ configured but missing: ${e#warn:}" ;;
        can-install) echo "OBSIDIAN_VAULT_PATH: ✗ (~/.obsidian-wiki/config absent)" ;;
    esac
    # obsidian-app
    case "$a" in
        ready) echo "Obsidian.app:        ✓ (${MONSTERFLOW_APPLICATIONS_DIR:-/Applications}/Obsidian.app)" ;;
        *)     echo "Obsidian.app:        ✗ (not in ${MONSTERFLOW_APPLICATIONS_DIR:-/Applications})" ;;
    esac
    # cmux
    case "$c" in
        ready) echo "cmux drift:          ✓ (config + binary both present)" ;;
        drift) echo "cmux drift:          ⚠ config present but binary absent" ;;
        na)    echo "cmux drift:          ○ N/A (no theme config present)" ;;
    esac
    # closing "all present" line (cmux ready or na both count as no-action)
    if [ "$g" = "ready" ] && [ "$w" = "ready" ] && [[ "$e" == ready:* ]] && [ "$a" = "ready" ] && { [ "$c" = "ready" ] || [ "$c" = "na" ]; }; then
        echo ""
        echo "Knowledge Layer: all present ✓"
    fi
    return 0
}

# --- Wave 3: Action helpers + orchestrator ---

# Task 3.1a — install_graphify_cli_binary
# Per D12: installs the venv + pip + symlink ONLY. Does NOT run `graphify claude install`
# (that is install_graphify_skill_via_cli, wired AFTER the CLAUDE.md baseline merger).
# No helper-level short-circuit — PATH stubs handle isolation under MONSTERFLOW_INSTALL_TEST=1 (D8).
install_graphify_cli_binary() {
    local venv="$HOME/.local/venvs/graphify"
    local symlink="$HOME/.local/bin/graphify"

    # EC2: venv exists + symlink missing → re-create only the symlink
    if [ -d "$venv/bin" ] && [ ! -L "$symlink" ]; then
        echo "  RUNNING: ln -sf $venv/bin/graphify $symlink"
        ln -sf "$venv/bin/graphify" "$symlink"
        echo "  LINKED:  $symlink → $venv/bin/graphify"
        echo "  ✓ graphify CLI symlink restored"
        return 0
    fi

    # EC3: venv dir exists with non-empty contents — refuse-and-notice
    if [ -d "$venv" ] && [ -n "$(ls -A "$venv" 2>/dev/null)" ]; then
        echo "  ⚠ graphify venv already exists at $venv — remove it manually if you want a clean reinstall"
        return 0
    fi

    # mkdir parent for symlink (defense-in-depth per Codex iter3)
    mkdir -p "$HOME/.local/bin"

    # Step 1: create venv (uses system python3)
    echo "  RUNNING: python3 -m venv $venv"
    if ! python3 -m venv "$venv"; then
        echo "  ✗ python3 -m venv failed; skipping graphify install"
        return 1
    fi

    # Step 2: install graphifyy[mcp] via the venv's pip3 (NOT system pip3 — Codex iter2 MF1)
    echo "  RUNNING: $venv/bin/pip3 install \"graphifyy[mcp]\""
    if ! "$venv/bin/pip3" install "graphifyy[mcp]" >/dev/null 2>&1; then
        echo "  ✗ pip3 install failed; venv left in place at $venv for inspection"
        return 1
    fi

    # Step 3: symlink venv's graphify binary into ~/.local/bin/
    echo "  RUNNING: ln -sf $venv/bin/graphify $symlink"
    ln -sf "$venv/bin/graphify" "$symlink"
    echo "  LINKED:  $symlink → $venv/bin/graphify"

    echo "  ✓ graphify CLI installed (skill + hook installed by install_graphify_skill_via_cli AFTER CLAUDE.md merger)"
    return 0
}

# Task 3.1b — install_graphify_skill_via_cli
# Per D12: runs AFTER the CLAUDE.md baseline merger at install.sh:~760.
# Per Codex iter2 MF3 + iter3: gate on BOTH has_cmd graphify AND skill-missing.
# The call-site at install.sh:~760 also gates on the same condition (defense-in-depth).
install_graphify_skill_via_cli() {
    if ! has_cmd graphify; then
        # graphify CLI install at 3.1a may have failed silently (EC3 refuse-and-notice)
        # or never ran (user said no to the prompt). Skip cleanly — no error.
        return 0
    fi
    if [ -f "$HOME/.claude/skills/graphify/SKILL.md" ]; then
        # Already installed by a prior run (or by another path); idempotent skip.
        return 0
    fi
    echo "  RUNNING: graphify claude install"
    if ! graphify claude install >/dev/null 2>&1; then
        echo "  ✗ graphify claude install failed (CLAUDE.md + PreToolUse hook not installed)"
        return 1
    fi
    echo "  ✓ graphify skill installed (~/.claude/skills/graphify/SKILL.md + PreToolUse hook)"
    return 0
}

# Task 3.2 — install_obsidian_env
# Atomic write to ~/.obsidian-wiki/config (same-dir temp per D7/MF8 — INSTALL_SCRATCH
# would cross filesystems and lose atomicity on macOS where mktemp is in /var/folders).
# Also appends sentinel-bracketed export to ~/.zshrc (theme-stage pattern).
install_obsidian_env() {
    local config_dir="$HOME/.obsidian-wiki"
    local config="$config_dir/config"
    mkdir -p "$config_dir"

    # If config already exists, don't clobber
    if [ -f "$config" ]; then
        echo "  ⚠ $config already exists; not overwriting"
    else
        # Determine default vault path (D9: shell env if set, else hardcoded)
        local default_path="${OBSIDIAN_VAULT_PATH:-$HOME/Documents/Obsidian/wiki}"
        local vault_path
        if [ "$NON_INTERACTIVE" = "1" ]; then
            # EC19: non-interactive — only proceed if default resolves to an existing dir
            if [ -d "$default_path" ]; then
                vault_path="$default_path"
            else
                echo "  ⚠ vault path not configured — set OBSIDIAN_VAULT_PATH manually and re-run install.sh" >&2
                return 0
            fi
        else
            read -rp "  Vault path [$default_path]: " vault_path
            vault_path="${vault_path:-$default_path}"
        fi

        # Tilde-expand AFTER read (the user may have typed ~/foo)
        vault_path="${vault_path/#\~/$HOME}"
        # Validate
        if [ ! -d "$vault_path" ]; then
            echo "  ⚠ $vault_path does not exist; not writing config" >&2
            return 0
        fi
        # Soft-warn on missing .obsidian/ subdir but proceed
        if [ ! -d "$vault_path/.obsidian" ]; then
            echo "  ⚠ $vault_path/.obsidian/ not found — open Obsidian.app and create the vault to finish setup"
        fi

        # Same-dir atomic write.
        # Write OBSIDIAN_VAULT_PATH in double-quoted format so parse_obsidian_config can read it.
        # posix_quote is for shell embedding (eval-safe), not for the config file format
        # (which parse_obsidian_config reads with grep/sed, never source/eval).
        local tmp="$config_dir/.config.tmp.$$"
        printf 'OBSIDIAN_VAULT_PATH="%s"\n' "$vault_path" > "$tmp"
        chmod 600 "$tmp"
        mv -f "$tmp" "$config"
        echo "  WROTE:    $config"
    fi

    # Append sentinel-bracketed export to ~/.zshrc (EC5: skip if non-sentinel export exists)
    local zshrc="$HOME/.zshrc"
    local begin="# BEGIN MonsterFlow obsidian-wiki"
    local end="# END MonsterFlow obsidian-wiki"
    [ -f "$zshrc" ] || touch "$zshrc"
    if grep -qF "$begin" "$zshrc"; then
        :   # Already appended; idempotent
    elif grep -qE '^[[:space:]]*(export[[:space:]]+)?OBSIDIAN_VAULT_PATH=' "$zshrc"; then
        echo "  ~/.zshrc already exports OBSIDIAN_VAULT_PATH — leaving your line alone"
    else
        # Re-read the resolved path from the config we just wrote (or pre-existing)
        local resolved_path
        resolved_path="$(parse_obsidian_config 2>/dev/null)" || resolved_path=""
        if [ -n "$resolved_path" ]; then
            {
                echo ""
                echo "$begin"
                echo "export OBSIDIAN_VAULT_PATH=$(posix_quote "$resolved_path")"
                echo "$end"
            } >> "$zshrc"
            echo "  APPENDED: $zshrc (sentinel-bracketed OBSIDIAN_VAULT_PATH export)"
        fi
    fi
    echo "  ✓ Obsidian env configured"
    return 0
}

# Task 3.3 — install_obsidian_app
# brew is REQUIRED-tier (install.sh:342, 399); install.sh exits before we reach
# do_knowledge_layer if absent. No defensive no-brew branch here (D11/MF1).
# EC17 success-oracle: re-check after brew, treat as ✓ regardless of brew exit code.
install_obsidian_app() {
    local app_dir="${MONSTERFLOW_APPLICATIONS_DIR:-/Applications}/Obsidian.app"
    echo "  RUNNING: brew install --cask obsidian"
    local rc=0
    brew install --cask obsidian >/dev/null 2>&1 || rc=$?
    # EC17 success-oracle: re-check after, treat as ✓ regardless of brew exit code
    if [ -d "$app_dir" ]; then
        if [ "$rc" -ne 0 ]; then
            echo "  ⚠ brew exited $rc but Obsidian.app is present; treating as success" >&2
        fi
        echo "  ✓ Obsidian.app installed"
        return 0
    else
        echo "  ✗ Obsidian.app install failed (brew exit=$rc, $app_dir not present)"
        return 1
    fi
}

# Task 3.4 — print_manual_instructions
# Single helper for both wiki and cmux print-only paths (per SD-01).
# No exec — just emits the recommended command + fallback.
print_manual_instructions() {
    local piece="$1"
    case "$piece" in
        wiki)
            echo "  wiki skills (install upstream — install.sh does not auto-exec npx):"
            if has_cmd npx; then
                echo "    npx skills add Ar9av/obsidian-wiki"
            else
                echo "    (npx not on PATH — manual git-clone fallback)"
                echo "    git clone https://github.com/Ar9av/obsidian-wiki ~/Projects/obsidian-wiki"
                echo "    cp -r ~/Projects/obsidian-wiki/.skills/* ~/.claude/skills/"
            fi
            ;;
        cmux)
            echo "  cmux config present but binary missing — re-install via:"
            echo "    brew install --cask cmux"
            ;;
        *)
            echo "  ⚠ print_manual_instructions: unknown piece '$piece'" >&2
            return 1
            ;;
    esac
    return 0
}

# Task 3.7 — do_knowledge_layer (orchestrator)
# classify_knowledge_layer: pure — echoes 5 status tokens (one per line) for testability.
classify_knowledge_layer() {
    detect_graphify_cli
    detect_wiki_skills
    detect_obsidian_env
    detect_obsidian_app
    detect_cmux_drift
}

do_knowledge_layer() {
    # Orchestrator: detect → render → classify into buckets → prompt (when needed) → dispatch → print manual.
    # Sets the global KL_GRAPHIFY_NEWLY_INSTALLED=1 if 3.1a fired, for the post-merger gate at install.sh:~760.
    KL_GRAPHIFY_NEWLY_INSTALLED=0
    export KL_GRAPHIFY_NEWLY_INSTALLED

    # Capture all 5 status tokens
    local g w e a c
    g="$(detect_graphify_cli)"
    w="$(detect_wiki_skills)"
    e="$(detect_obsidian_env)"
    a="$(detect_obsidian_app)"
    c="$(detect_cmux_drift)"

    # Render the summary block
    render_knowledge_summary "$g" "$w" "$e" "$a" "$c"

    # Build buckets
    local can_install=()
    local manual_pieces=()
    [ "$g" = "can-install" ] && can_install+=("graphify CLI")
    [ "$e" = "can-install" ] && can_install+=("OBSIDIAN_VAULT_PATH")
    [ "$a" = "can-install" ] && can_install+=("Obsidian.app")
    [[ "$w" == manual:* ]] && [ "$w" != "manual:6/6" ] && manual_pieces+=("wiki")
    [ "$c" = "drift" ] && manual_pieces+=("cmux")

    # Only prompt when can-install bucket is non-empty
    if [ ${#can_install[@]} -gt 0 ]; then
        local do_install=0
        # Codex review P2: honor the computed OWNER (set by detect_owner) — NOT just
        # the MONSTERFLOW_OWNER env override. detect_owner sets OWNER=1 when running
        # from the repo root; the env override only flips the result for tests.
        if [ "${OWNER:-0}" = "1" ]; then
            do_install=1   # owner: auto-yes
        elif [ "$NON_INTERACTIVE" = "1" ]; then
            do_install=0   # adopter non-interactive: default-N
        else
            local pieces_str
            pieces_str=$(IFS=,; echo "${can_install[*]}")
            local confirm
            read -rp "Install the ${#can_install[@]} pieces install.sh can handle (${pieces_str})? [y/N]: " confirm
            [[ "$confirm" =~ ^[Yy]$ ]] && do_install=1
        fi
        # Codex review P2: --no-install is the documented CI escape hatch; the
        # prerequisite installer honors it (do_install_missing returns early).
        # Knowledge Layer must too — otherwise an owner-mode --no-install run
        # would still pip-install graphifyy and brew-install Obsidian.app.
        if [ "$do_install" = "1" ] && [ "${NO_INSTALL:-0}" = "1" ]; then
            echo "  Knowledge Layer installs skipped per --no-install"
            do_install=0
        fi
        if [ "$do_install" = "1" ]; then
            if [ "$g" = "can-install" ]; then
                install_graphify_cli_binary && KL_GRAPHIFY_NEWLY_INSTALLED=1
            fi
            if [ "$e" = "can-install" ]; then
                install_obsidian_env
            fi
            if [ "$a" = "can-install" ]; then
                install_obsidian_app
            fi
        fi
    fi

    # Print manual-action instructions for the pieces install.sh can't handle
    if [ ${#manual_pieces[@]} -gt 0 ]; then
        echo ""
        echo "Manual action required:"
        local p
        for p in "${manual_pieces[@]}"; do
            print_manual_instructions "$p"
        done
    fi

    return 0
}

# Owner vs adopter detection (D4 augmented helper, W2 task 2.5):
# Env override > PWD primary check > script_dir == git_root secondary confirmation.
# Preserves existing defensive `PWD == REPO_DIR` semantics; secondary check
# catches symlinked-repo edge cases where PWD coincidentally matches REPO_DIR
# by string but the script actually lives elsewhere.
detect_owner() {
    if [ "${MONSTERFLOW_OWNER:-}" = "1" ]; then echo 1; return; fi
    if [ "${MONSTERFLOW_OWNER:-}" = "0" ]; then echo 0; return; fi
    if [ "$PWD" != "$REPO_DIR" ]; then echo 0; return; fi
    local script_dir git_root
    script_dir="$(cd "$(dirname "$0")" && pwd -P)"
    git_root="$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || true)"
    [ -n "$git_root" ] && [ "$script_dir" = "$git_root" ] && echo 1 || echo 0
}
OWNER="$(detect_owner)"
ADOPTER_ROOT=""
if [[ "$OWNER" -eq 0 && -d "$PWD/.git" ]]; then
    ADOPTER_ROOT="$PWD"
fi

# Create queue/ + .gitignore in BOTH the engine repo and the adopter project.
# autorun runs from $PROJECT_DIR (defaults to $PWD), so adopter projects need
# their own queue/.gitignore — otherwise specs, configs, run logs, and PR
# URLs leak into commits despite docs claiming "queue/ is gitignored."
write_queue_gitignore() {
    local target_dir="$1"
    mkdir -p "$target_dir"
    if [ ! -f "$target_dir/.gitignore" ]; then
        cat > "$target_dir/.gitignore" << 'GITIGNORE'
# autorun queue — transient artifacts, never commit
autorun.config.json
*/
STOP
run.log
.current-stage
.autorun.lock
*.spec.md
*.prompt.txt
GITIGNORE
        echo "  CREATED: $target_dir/.gitignore"
    fi
}

write_queue_gitignore "$REPO_DIR/queue"
if [ -n "$ADOPTER_ROOT" ]; then
    write_queue_gitignore "$ADOPTER_ROOT/queue"
fi

# --- Persona Metrics: gitignore default-flip for adopters ---
# Owner (working ON MonsterFlow) → commit metrics (dogfood pattern).
# Adopter (using MonsterFlow) → gitignore metrics (may contain sensitive review prose).
# Override via PERSONA_METRICS_GITIGNORE=0 (commit) or =1 (gitignore).
PERSONA_METRICS_GITIGNORE_DEFAULT=1
if [[ "$OWNER" -eq 1 ]]; then
    PERSONA_METRICS_GITIGNORE_DEFAULT=0
fi
PERSONA_METRICS_GITIGNORE="${PERSONA_METRICS_GITIGNORE:-$PERSONA_METRICS_GITIGNORE_DEFAULT}"

if [[ "$PERSONA_METRICS_GITIGNORE" == "1" && -n "$ADOPTER_ROOT" ]]; then
    GITIGNORE="$ADOPTER_ROOT/.gitignore"
    BLOCK_BEGIN="# BEGIN persona-metrics (MonsterFlow)"
    BLOCK_END="# END persona-metrics"

    # Idempotent: check for sentinel before appending
    if [ ! -f "$GITIGNORE" ] || ! grep -qF "$BLOCK_BEGIN" "$GITIGNORE"; then
        echo ""
        echo "Persona Metrics: appending gitignore block to $GITIGNORE (PERSONA_METRICS_GITIGNORE=1)"
        touch "$GITIGNORE"
        {
            echo ""
            echo "$BLOCK_BEGIN"
            echo "# Auto-added by install.sh — measurement artifacts may contain sensitive review prose."
            echo "# Set PERSONA_METRICS_GITIGNORE=0 and re-run install.sh to commit metrics intentionally."
            echo "docs/specs/*/spec-review/findings*.jsonl"
            echo "docs/specs/*/spec-review/participation.jsonl"
            echo "docs/specs/*/spec-review/survival.jsonl"
            echo "docs/specs/*/spec-review/run.json"
            echo "docs/specs/*/spec-review/raw/"
            echo "docs/specs/*/spec-review/source.spec.md"
            echo "docs/specs/*/plan/findings*.jsonl"
            echo "docs/specs/*/plan/participation.jsonl"
            echo "docs/specs/*/plan/survival.jsonl"
            echo "docs/specs/*/plan/run.json"
            echo "docs/specs/*/plan/raw/"
            echo "docs/specs/*/check/findings*.jsonl"
            echo "docs/specs/*/check/participation.jsonl"
            echo "docs/specs/*/check/survival.jsonl"
            echo "docs/specs/*/check/run.json"
            echo "docs/specs/*/check/raw/"
            echo "docs/specs/*/check/source.plan.md"
            echo "docs/specs/*/.persona-metrics-warned"
            # Added in v0.9.0 for pipeline-gate-permissiveness spec — per-spec followups authoritative store.
            echo "docs/specs/*/followups.jsonl"
            echo "$BLOCK_END"
        } >> "$GITIGNORE"
    fi
fi

# --- Theme install (W2 task 2.8) ---
# Decisions: --no-theme wins; else owner=auto-on, adopter under non-interactive=skip,
# adopter interactive=prompt-default-N. --install-theme forces install.
do_theme_install() {
    [ "$NO_THEME" = "1" ] && return 0

    local DO_THEME
    if [ "$INSTALL_THEME_FORCED" = "1" ]; then
        DO_THEME=1
    elif [ "$OWNER" = "1" ]; then
        DO_THEME=1   # owner: no prompt
    elif [ "$NON_INTERACTIVE" = "1" ]; then
        DO_THEME=0   # non-interactive adopter: skip
    else
        local THEME_CONFIRM
        read -rp "Install MonsterFlow shell theme (cmux + tmux + zsh prompt + ghostty)? [y/N]: " THEME_CONFIRM
        [[ "$THEME_CONFIRM" =~ ^[Yy]$ ]] && DO_THEME=1 || DO_THEME=0
    fi
    [ "$DO_THEME" = "0" ] && return 0

    echo ""
    echo "Installing MonsterFlow shell theme..."
    mkdir -p "$HOME/.config/cmux"
    link_file "$REPO_DIR/config/cmux.json" "$HOME/.config/cmux/cmux.json"
    link_file "$REPO_DIR/config/tmux.conf" "$HOME/.tmux.conf"
    mkdir -p "$HOME/.config/ghostty"
    link_file "$REPO_DIR/config/ghostty.config" "$HOME/.config/ghostty/config"

    # POSIX single-quote escaping via top-level posix_quote (hoisted above detect_owner).
    # posix_quote returns a fully-quoted string (incl. surrounding '…');
    # use it bare in the heredoc — do NOT add more quotes.
    local ZSHRC_PATH ZSHRC THEME_BLOCK_BEGIN THEME_BLOCK_END
    ZSHRC_PATH="$(posix_quote "$REPO_DIR/config/zsh-prompt-colors.zsh")"
    ZSHRC="$HOME/.zshrc"
    THEME_BLOCK_BEGIN="# BEGIN MonsterFlow theme"
    THEME_BLOCK_END="# END MonsterFlow theme"
    if [ ! -f "$ZSHRC" ] || ! grep -qF "$THEME_BLOCK_BEGIN" "$ZSHRC"; then
        touch "$ZSHRC"
        {
            echo ""
            echo "$THEME_BLOCK_BEGIN"
            echo "[ -f $ZSHRC_PATH ] && source $ZSHRC_PATH"
            echo "$THEME_BLOCK_END"
        } >> "$ZSHRC"
        echo "  APPENDED: ~/.zshrc theme block (sentinel-bracketed)"
    fi
}
do_theme_install

# Knowledge Layer: runs AFTER theme stage (depends on theme's cmux.json symlink for drift detection)
# and BEFORE the CLAUDE.md baseline merger (graphify skill install runs after the merger per D12).
do_knowledge_layer

# --- CLAUDE.md baseline ---
echo ""
GLOBAL_CLAUDE="$HOME/CLAUDE.md"
if [ ! -f "$GLOBAL_CLAUDE" ]; then
    COPY_CLAUDE="Y"   # safe default under non-interactive: copy baseline
    if [ "$NON_INTERACTIVE" = "0" ]; then
        read -rp "No ~/CLAUDE.md found. Copy baseline template? [Y/n]: " COPY_CLAUDE
    fi
    if [[ ! "$COPY_CLAUDE" =~ ^[Nn]$ ]]; then
        cp "$REPO_DIR/templates/CLAUDE.md" "$GLOBAL_CLAUDE"
        echo "  Copied templates/CLAUDE.md → ~/CLAUDE.md"
        echo "  Edit it to add your name, role, and personal context."
    fi
elif [ "${MONSTERFLOW_INSTALL_TEST:-0}" != "1" ]; then
    # Skip under MONSTERFLOW_INSTALL_TEST=1: a python3 subprocess per case adds
    # up across the 20-case suite. The merge logic has its own tests
    # (test-allowlist*, etc.) that exercise the merger directly.
    python3 "$REPO_DIR/scripts/claude-md-merge.py" --target "$GLOBAL_CLAUDE" --template "$REPO_DIR/templates/CLAUDE.md"
fi

# Per D12: graphify claude install runs AFTER the baseline merger so its CLAUDE.md additions are
# the last write and survive. Gated on (has_cmd graphify OR direct ~/.local/bin/graphify exists)
# AND skill-missing. Codex review P2: first-run users may not have ~/.local/bin on PATH yet
# (RECOMMENDED-tier warning already covers this); has_cmd alone would miss the symlink we just
# created. Direct stat is a fallback for that first-run case.
if { has_cmd graphify || [ -x "$HOME/.local/bin/graphify" ]; } \
       && [ ! -f "$HOME/.claude/skills/graphify/SKILL.md" ]; then
    # Add ~/.local/bin to PATH for this invocation so install_graphify_skill_via_cli's
    # internal `has_cmd graphify` gate also passes when first-run PATH hadn't picked it up.
    case ":$PATH:" in
        *":$HOME/.local/bin:"*) ;;
        *) PATH="$HOME/.local/bin:$PATH" ;;
    esac
    install_graphify_skill_via_cli
fi

# --- Git hooks (auto-bump VERSION + tag) ---
# Wires up scripts/hooks/post-commit which auto-bumps VERSION + tags
# based on conventional-commit prefix (feat → minor, fix/docs/etc →
# patch, BREAKING CHANGE → major). Only fires on `main` branch.
# Idempotent — re-runs replace the symlink.
if [ -x "$REPO_DIR/scripts/install-hooks.sh" ] && [ -d "$REPO_DIR/.git/hooks" ]; then
    echo ""
    echo "Installing git hooks (auto-bump VERSION on commit)..."
    bash "$REPO_DIR/scripts/install-hooks.sh" 2>&1 | sed 's/^/  /'
fi

# --- Plugin installation ---
# W2 task 2.9 + 2.9b: skip prompt under non-interactive (safe default = N);
# short-circuit entirely under MONSTERFLOW_INSTALL_TEST=1 to prevent test
# harness recursion (tests invoke install.sh; without this guard the inner
# `claude plugins install` call would either hang or hit the network).
echo ""
if [ "${MONSTERFLOW_INSTALL_TEST:-0}" = "1" ]; then
    echo "Plugin install: (skipped under MONSTERFLOW_INSTALL_TEST=1)"
elif [ "$NON_INTERACTIVE" = "1" ]; then
    echo "Plugin install: (skipped under --non-interactive; run install.sh interactively to install plugins)"
else
    read -rp "Install required plugins now? [y/N]: " INSTALL_PLUGINS
    if [[ "$INSTALL_PLUGINS" =~ ^[Yy]$ ]]; then
        echo "Installing required plugins..."
        claude plugins install superpowers context7 || echo "  Plugin install requires Claude Code CLI"

        read -rp "Also install recommended plugins? [y/N]: " INSTALL_REC
        if [[ "$INSTALL_REC" =~ ^[Yy]$ ]]; then
            claude plugins install firecrawl code-review ralph-loop playwright || echo "  Some plugins may have failed"
        fi
    fi
fi

# --- Validate install via test suite ---
# W2 task 2.9b: short-circuit under MONSTERFLOW_INSTALL_TEST=1 — second site
# critical to prevent fork-bomb (tests/run-tests.sh runs tests/test-install.sh
# which spawns install.sh; without this guard we'd recurse infinitely).
if [ -x "$REPO_DIR/tests/run-tests.sh" ]; then
    echo ""
    if [ "${MONSTERFLOW_INSTALL_TEST:-0}" = "1" ]; then
        echo "Test suite: (skipped under MONSTERFLOW_INSTALL_TEST=1)"
    elif [ "$NON_INTERACTIVE" = "1" ]; then
        echo "Test suite: (skipped under --non-interactive; run 'bash tests/run-tests.sh' to validate)"
    else
        read -rp "Run test suite to validate install? [Y/n]: " RUN_TESTS
        if [[ ! "$RUN_TESTS" =~ ^[Nn]$ ]]; then
            echo ""
            bash "$REPO_DIR/tests/run-tests.sh" || echo "⚠ some tests failed — investigate via 'bash tests/run-tests.sh'"
        fi
    fi
fi

echo ""
echo "=== Installation complete ==="
echo ""
echo "Installed:"
echo "  - 38 pipeline agents:"
echo "      29 pipeline personas (review 6, plan 7, check 5, code-review 9, judge, synthesis)"
echo "       9 domain agents (mobile 6, games 3) — available to /kickoff for per-project install"
echo "  - 10 pipeline commands (/kickoff → /spec → /spec-review → /plan → /check → /build + /autorun + /flow + /wrap + /bump-version)"
echo "  - 2 focused subagents (autorun-shell-reviewer, persona-metrics-validator)"
echo "  - 2 user-only skills (/autorun-dryrun, /bump-version)"
echo "  - 2 PostToolUse hooks (shellcheck on .sh, jq empty on .json) — advisory-only"
echo "  - 1 git post-commit hook (auto-bump VERSION + tag on main, conventional-commit driven)"
echo "  - 3 templates (constitution, repo-signals, CLAUDE.md baseline)"
echo "  - Settings with pipeline-optimized permissions"
echo "  - Scripts (session-cost.py, doctor.sh, statusline-command.sh, bump-version.sh)"
echo "  - Autorun pipeline (scripts/autorun/ + queue/ with .gitignore)"
echo "  - Test suite (tests/run-tests.sh — 5 files, 30+ assertions)"
echo ""
echo "Next steps:"
echo "  1. Customize ~/CLAUDE.md (copied from templates/CLAUDE.md — fill in your name, role, dev env)"
echo "  2. Review ~/.claude/settings.json and adjust permissions"
echo "  3. See plugins.md for optional plugins"
echo "  4. See QUICKSTART.md if this is your first time"
echo "  5. Auto-bump rules: feat:→minor · fix:/docs:/etc.→patch · type!: or BREAKING CHANGE:→major"
echo "  6. If anything looks off, run ./scripts/doctor.sh to file a diagnostic"
echo "  7. To reverse: bash uninstall.sh (dry-run by default; --apply commits)"

# Obsidian vault hint — fires when the env was detected as warn/can-install.
# Re-classify cheaply (pure detect, no side effects) so we don't depend on
# captured state from do_knowledge_layer earlier in the run.
_obsidian_post_status="$(detect_obsidian_env 2>/dev/null || echo can-install)"
case "$_obsidian_post_status" in
    warn:*|can-install)
        echo ""
        echo "Obsidian vault — one-time manual step:"
        echo "  • Launch Obsidian.app → 'Create new vault'"
        echo "  • Path: ~/Documents/Obsidian/wiki  (install.sh default; or whatever you set in ~/.obsidian-wiki/config)"
        echo "  • After the vault exists, re-run 'bash install.sh' — it will append OBSIDIAN_VAULT_PATH to ~/.zshrc"
        ;;
esac
unset _obsidian_post_status

echo ""

# --- Onboard panel (W2 task 2.10, last stage) ---
# Run scripts/onboard.sh if present (W3 authors it in parallel; [ -x ] guard
# handles the not-yet-shipped case). Skipped under --no-onboard or when
# non-interactive without --force-onboard.
if [ "$NO_ONBOARD" != "1" ] && { [ "$NON_INTERACTIVE" = "0" ] || [ "$FORCE_ONBOARD" = "1" ]; }; then
    if [ -x "$REPO_DIR/scripts/onboard.sh" ]; then
        echo ""
        bash "$REPO_DIR/scripts/onboard.sh" || {
            echo "⚠ onboard.sh exited non-zero; re-run anytime via bash scripts/onboard.sh" >&2
        }
    fi
fi

echo "Run /flow in Claude Code to see the workflow reference card."
