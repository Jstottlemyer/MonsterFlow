# [PROJECT_NAME] Constitution

**Version:** 1.0
**Created:** [DATE]
**Last Amended:** [DATE]

## Core Principles

### I. [PRINCIPLE_1]
[Description — what this principle means and why it matters]

### II. [PRINCIPLE_2]
[Description]

### III. [PRINCIPLE_3]
[Description]

## Quality Standards

### Testing
[Required testing approach — TDD, integration tests, coverage expectations]

### Accessibility
[Accessibility requirements — platform-specific guidelines, compliance level]

### Performance
[Performance expectations — response times, memory usage, scale targets]

## Agent Roster

Default pipeline agents (27) are always active. Project-specific agents listed below are added at `/kickoff`.

### Project-Specific Agents
- [agent-name] — [role description] — used at [pipeline stage]

## Constraints

### In Scope
[What this project covers]

### Out of Scope
[What this project explicitly does NOT cover]

### Technical Constraints
[Language, platform, deployment, dependencies]

## Autorun

# auto_merge_policy: pr  # default; uncomment and set to 'clean' only if you've reviewed the trade-off in commands/autorun.md

Optional knobs the autorun pipeline reads from this file's frontmatter:

- `auto_merge_policy` — `pr` | `clean` | `validated`. Default `pr` (autorun
  opens a PR but does not auto-merge). Set to `clean` to auto-merge when the
  four-axis gate is satisfied (`MERGE_CAPABLE == 1 AND CODEX_HIGH_COUNT == 0
  AND RUN_DEGRADED == 0` AND mode-aware verdict). `validated` falls back to
  `pr` until `autorun-runtime-validation-gate` ships.
- Per-spec frontmatter overrides this constitution; `--merge-policy=` CLI
  flag overrides spec.

## Governance

- Constitution supersedes informal preferences for this project
- Amendments require updating this file and incrementing the version
- All specs created under this constitution reference its version
