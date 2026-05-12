---
description: DEPRECATED — alias for /design. Renamed 2026-05-12 to avoid collision with Claude Code plan-mode.
---

# `/plan` is now `/design`

This slash command was renamed from `/plan` to `/design` on 2026-05-12 to
avoid the long-standing collision with Claude Code's built-in plan-mode
tooling (`EnterPlanMode` / `ExitPlanMode` and `superpowers:writing-plans`).

`/plan` continues to work as a deprecation alias for one release cycle.
The behavior is identical — this file simply delegates to `commands/design.md`.

## What you should do

- **Adopters running interactive sessions:** start using `/design` instead of
  `/plan`. Muscle memory will adapt quickly; the rest of the pipeline names
  (`/spec → /spec-review → /design → /check → /build`) read better with the
  new verb anyway.
- **Autorun configurations:** the autorun shell at `scripts/autorun/plan.sh`
  is unchanged — internal gate identifiers (`plan` in `gate_mode`, `plan` in
  `selection.json`, `personas/plan/` directory) all stay the same to preserve
  on-disk artifact compatibility. Only the user-facing slash command renamed.
- **Custom hooks / scripts:** if you have anything keying off the literal
  string `/plan` in user prompts, leave it for now; the alias will continue
  to fire this stub. Plan to migrate before the alias-removal release.

## Delegation

The full design-planning workflow lives at `commands/design.md`. To honor
this `/plan` invocation, follow that file's instructions verbatim — load
artifacts, dispatch the 7 specialist agents, synthesize, present the plan.

**Argument forwarding:** any `$ARGUMENTS` passed to `/plan` are forwarded
unchanged to `/design`. The argument-parse contract is identical.

## Why the rename

User flagged the collision on 2026-05-12 during PR #11 review:
> "we need to rename /plan in our set of gates and in all of our online
> documentation and all references this is a big miss"

Captured in `feedback_slashcmd_collision_with_claude_builtins` memory and
the CHANGELOG entry. The new name `/design` is parallel to the other
pipeline verbs (`/spec`, `/check`, `/build`), distinctive enough to avoid
future collisions, and reads naturally as the "design how to build what
/spec defined" step.
