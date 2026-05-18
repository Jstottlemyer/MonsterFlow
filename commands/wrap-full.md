---
description: /wrap thorough mode — insights + force-run conditional phases (use when stepping away for a stretch)
allowed-tools: Bash, Read, Edit, Glob, Grep, Write
---

This is the most thorough variant of `/wrap`. Read `commands/wrap.md` in this repo and execute it now as if `$ARGUMENTS` contained `insights full`.

Full mode = insights mode + override the in-phase skip-rules:

- Phase 5 (CLAUDE.md health check) runs even when the session was trivial.
- Phase 2b (style rules lint) runs even without screenshot reviews this session.
- Phase 4 (permission audit) already runs by default.

Hard prerequisites still apply — Phase 2c (wiki) needs `~/.obsidian-wiki/config`, Phase 2d (plot gate) needs `plot/PLOT.md`, Phase 3 (loose ends) needs a git repo, Phase 3b (deps) needs an actual install during the session. Full mode does not fabricate triggers; it only suppresses the soft skip-rules inside phases that would otherwise auto-pass.

Use when stepping away for the day or before a long break, when you want every drift-catching phase to fire even if the session looked light.

This file exists as a tab-completion shortcut. Behavior is identical to typing `/wrap insights full`.
