# launchd plist cleanup — claude-workflow → MonsterFlow rebrand

**Status:** standalone local runbook · carved off from `pipeline-pacing-and-prefill` spec per /spec-review B5 (2026-05-14)
**Audience:** Justin (one machine) — local-only cleanup; no repo footprint
**Prerequisite:** `~/Projects/claude-workflow` symlink still exists pointing at `~/Projects/MonsterFlow` (verify before running)

## Context

Per memory `project_monsterflow_rebrand`: launchd plists in
`~/Library/LaunchAgents/` reference `claude-workflow` paths from the
rebrand. They work today because of the compat symlink, but they're stale
paths riding on a workaround.

This runbook executes the cleanup with explicit per-plist confirmation +
backup + revert-on-bootstrap-failure path. Architectural rollback
guarantees (the gap /spec-review flagged) are baked into the procedure
below.

## Procedure (run interactively; do NOT script-and-walk-away)

### Step 1 — Find candidates

```bash
find ~/Library/LaunchAgents -name '*.plist' -exec grep -l claude-workflow {} \;
```

Expected matches per memory: 2 files (graphify weekly benchmark, vault
re-index). If more or fewer, **stop and investigate** before continuing.

### Step 2 — For EACH matched plist, do this loop

```bash
PLIST=<path>
# 1. Show current paths so user can confirm what changes
echo "=== $PLIST ==="
plutil -p "$PLIST" | grep -E "Program|Path"

# 2. Backup
cp "$PLIST" "$PLIST.bak.$(date +%Y%m%d-%H%M%S)"

# 3. Rewrite (macOS BSD sed requires '' after -i)
sed -i '' 's|claude-workflow|MonsterFlow|g' "$PLIST"

# 4. Verify the rewrite happened correctly
echo "=== after rewrite ==="
plutil -p "$PLIST" | grep -E "Program|Path"
# Get explicit confirmation here before proceeding

# 5. Reload — bootout first, then bootstrap
launchctl bootout gui/$UID "$PLIST" 2>&1 || echo "bootout returned non-zero (may be expected if already unloaded)"
launchctl bootstrap gui/$UID "$PLIST"
BOOTSTRAP_EXIT=$?

# 6. Revert path on bootstrap failure
if [ "$BOOTSTRAP_EXIT" -ne 0 ]; then
  echo "!! bootstrap failed for $PLIST — reverting to backup"
  cp "$PLIST.bak."* "$PLIST"
  launchctl bootstrap gui/$UID "$PLIST"
  echo "!! reverted; investigate why MonsterFlow path didn't bootstrap before retrying"
  exit 1
fi

# 7. Verify next-run timestamp is sensible
launchctl list | grep -i "$(basename "$PLIST" .plist)"
```

**Do not proceed to the next plist if any step in the current one's loop fails.** Address the failure (manual edit, path correction, etc.) before the next iteration.

### Step 3 — Verify both plists running on the new path

```bash
launchctl list | grep -iE 'monsterflow|graphify' | head -5
# Expected: each loaded with positive PID or "-" + recent runtime
```

### Step 4 — Cleanup backups (only after a week of clean operation)

Leave `.bak.<ts>` files in place for at least 7 days. Once you've
confirmed all expected runs fired on the new path (check
`~/Library/Logs/` or wherever the agents write), remove the backups:

```bash
find ~/Library/LaunchAgents -name '*.plist.bak.*' -delete
```

### Step 5 — Mark memory resolved

Update `~/.claude/projects/-Users-jstottlemyer-Projects-MonsterFlow/memory/project_monsterflow_rebrand.md`:
- Append `STATUS: RESOLVED 2026-05-14` to the front
- Note in MEMORY.md index that this is closed

## Failure modes

- **`bootout` returns non-zero** — usually fine if the agent was already
  unloaded. Don't treat as a blocker; proceed to bootstrap.
- **`bootstrap` returns non-zero** — REVERT to backup immediately (Step
  2.6). Common causes: typo in rewritten path, SIP block on certain
  paths, missing executable at new location. Investigate before retry.
- **Multiple plists matched (>2)** — STOP. Memory expected 2; if more
  exist, the rebrand may have touched other entries we haven't catalogued.
  Inspect manually.
- **Zero plists matched** — the rebrand symlink may have been removed
  already, or plists were rewritten in a prior session. Verify and update
  memory if so.

## Why this is a runbook, not a script

Per /spec-review B5: the partial-failure rollback gap (sed succeeds,
bootstrap fails permanently, agent in undefined loaded/unloaded state) is
the dominant risk. Interactive confirmation between Steps 2.4 and 2.5
makes this safe. A "fire and forget" script would risk silent launchd
failures going undetected, which would mean the graphify weekly benchmark
could stop running for a week before anyone noticed.
