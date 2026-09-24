# commands/ — Instructions

Applies in addition to the repo root `CLAUDE.md`.

## Gate approval prompts — render verbatim

Every gate (`/spec`, `/spec-review`, `/blueprint`, `/check`) defines its
post-stage approval prompt inside its command contract. Render the
contract's options verbatim — don't substitute your own framing, drop
options, or "helpfully" suggest a shortcut that omits a canonical option.
Treat each gate's "Phase 3: Present" / approval block as a hard template.
Commentary above or below it is fine; reshaping the options is not.

The autoship `/goal` line is part of the contract at any gate that supports
it. Always surface it when the gate's helper output declares suitability
HIGH or MEDIUM and the gate's approval prompt includes the "ship
autonomously" option. If a spec was refined between gates (AC count
changed, frontmatter edited), re-render the `/goal` line via
`python3 scripts/_goal_autoship_render.py render --spec-path
docs/specs/<feature>/spec.md --gate <gate-name>` before presenting it — the
AC count is baked into the rendered line and goes stale otherwise.

## No slash-command name may collide with a host-harness built-in

Before introducing or renaming a MonsterFlow pipeline command, check it
doesn't collide with a Claude Code (or Codex) built-in slash command, tool,
or skill name. `/plan` was MonsterFlow's original planning gate; it
collided with Claude Code's built-in plan-mode (`EnterPlanMode`/
`ExitPlanMode`) and caused real ambiguity in adopter sessions — a typed
`/plan` was unclear between the two. Resolution (2026-05-12): ceded `/plan`
back to the host entirely — no deprecated alias — and renamed the command
to `/blueprint` (`commands/blueprint.md`). `design` is the internal stage
name only (`personas/design/`, `docs/specs/<feature>/design.md`,
`stage: "design"` in JSONL) — there is no `/design` slash command; don't
introduce one. Before adding a new command name, grep the current session's
skills/tool listing and its system reminders for collisions.

## Shared canonical blocks across command files — splice pattern

When ≥2 files in `commands/*.md` need a byte-identical block (e.g. a
detection block that must match across `spec-review.md`/`blueprint.md`/
`check.md`/`build.md`), don't hand-paste it into each. Write the canonical
content once to `commands/_prompts/<name>.md`, wrapped in HTML-comment
sentinels:

```markdown
<!-- BEGIN <name> -->
... canonical content ...
<!-- END <name> -->
```

Each command file copies the whole fragment (sentinels included) verbatim
at its insertion point — no template engine or include mechanism exists
here. A drift-detection test extracts the sentinel-delimited content from
each command file and byte-compares it against the canonical fragment; this
is what catches divergence when parallel `/build` agents each edit a
sibling command file.
