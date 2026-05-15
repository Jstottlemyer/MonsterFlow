# MonsterFlow — Homebrew dependency manifest
#
# Usage:
#   brew bundle --file=Brewfile           # install everything below
#   brew bundle check --file=Brewfile     # report missing without installing
#   brew bundle cleanup --file=Brewfile   # show what's installed but not listed
#
# Tier semantics mirror install.sh:
#   REQUIRED    — pipeline cannot function without these
#   RECOMMENDED — features degrade silently when absent (hooks no-op,
#                 /autorun can't make PRs, etc.)
#
# Not managed here:
#   - claude (Claude Code CLI) — install from https://claude.com/claude-code
#   - codex (OPTIONAL adversarial reviewer) — npm i -g @openai/codex
#   - tmux (OPTIONAL — only needed for headless /autorun overnight sessions;
#     install via `brew install tmux` if you use that flow)
#
# Adopters who want a no-install dry run: pass --no-install to install.sh
# (planned in the install.sh rewrite spec) and this file is skipped.

# --- REQUIRED ---
brew "git"
brew "python@3.11"

# --- RECOMMENDED ---
brew "gh"          # /autorun PR ops; gh auth login required after install
brew "shellcheck"  # PostToolUse hook on .sh edits
brew "jq"          # PostToolUse hook on .json edits
brew "flock"       # File-locking; required by scripts/autorun/_policy.sh + scripts/_followups_lock.py for concurrent /build safety. Stock macOS has no flock.
cask "cmux"  # Homebrew cask (not a formula); auto-updates per cask author
