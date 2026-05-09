# `~/.config/monsterflow/` — README

This is the literal content `install.sh` will eventually copy to `${XDG_CONFIG_HOME:-$HOME/.config}/monsterflow/README.md` for adopters. Lives here under `docs/specs/token-economics/` for now; install.sh wiring is tracked in BACKLOG.

---

# MonsterFlow config

This directory holds local-only configuration for MonsterFlow scripts. Everything here is per-machine — never committed, never synced.

## Files

- **`finding-id-salt`** — 32-byte random salt, chmod 600. Used by `compute-persona-value.py` to namespace `contributing_finding_ids[]` so the same finding produces a different ID across machines. Auto-generated on first `/wrap-insights` run; auto-regenerated on validation failure (with rankings cleared).
- **`projects`** — optional adopter-maintained file. One absolute project root path per line; `#` comments and blank lines ignored. Adds those projects to `compute-persona-value.py`'s value-side discovery without `--scan-projects-root`.
- **`scan-roots.confirmed`** — written by `compute-persona-value.py` after you confirm a `--scan-projects-root <dir>` interactively (or via `--confirm-scan-roots <dir>`). Subsequent runs skip the prompt.

## To enable cross-project aggregation

Pick one:

```bash
# Option A: explicit list of project paths (deterministic, smallest)
mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/monsterflow"
cat > "${XDG_CONFIG_HOME:-$HOME/.config}/monsterflow/projects" <<'EOF'
/Users/me/Projects/MonsterFlow
/Users/me/Projects/RedRabbit
EOF

# Option B: scan a parent directory once, confirm interactively
scripts/compute-persona-value.py --scan-projects-root ~/Projects

# Option C: scan a parent directory non-interactively (tmux/CI)
scripts/compute-persona-value.py --confirm-scan-roots ~/Projects
```

## To opt a single project OUT of scan-tier discovery

```bash
touch /path/to/sensitive-project/.monsterflow-no-scan
```

The empty sentinel file silently excludes that project from tier-3 (`--scan-projects-root`) cascade regardless of `scan-roots.confirmed`. Tier 1 (cwd) and tier 2 (`projects` config) are unaffected.

## Permissions

All files in this directory should be `chmod 600` (owner read/write only). `finding-id-salt` and `scan-roots.confirmed` are auto-set by the script. `projects` is adopter-maintained — set it yourself:

```bash
chmod 600 "${XDG_CONFIG_HOME:-$HOME/.config}/monsterflow/projects"
```

## To uninstall

Remove the directory:

```bash
rm -rf "${XDG_CONFIG_HOME:-$HOME/.config}/monsterflow"
```

Next `/wrap-insights` run regenerates `finding-id-salt` and clears any stale `dashboard/data/persona-rankings.jsonl`. No other side effects.
