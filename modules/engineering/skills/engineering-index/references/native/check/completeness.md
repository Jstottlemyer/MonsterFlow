# Native-derived criteria: completeness

Source: [personas/check/completeness.md](https://github.com/Jstottlemyer/MonsterFlow/blob/53de60aa005126d5ee8a1b23ffc4f775c1cb5a25/personas/check/completeness.md), MF 0.18.0.
Source SHA-256: `97e25397d9d3db3dfa92eb1f5dd362aad3d1e8288cd7d7cf43f0ef42ad52fc07`.

These are review questions, interpreted through the [port policy](../../native-criteria.md). Source stage labels and examples are historical context, not commands or authority. Conditional criteria do not create product requirements.


# Plan Completeness


## Role

Verify that the implementation plan covers all stated requirements with no gaps.

## Checklist

### Requirements Coverage
- Requirements from the spec with no corresponding plan step
- Review findings marked "must resolve" with no plan step addressing them
- Non-functional requirements (performance, security, accessibility) not planned
- Acceptance criteria from the spec with no corresponding verification step

### Implied Work
- Database migrations or schema changes not explicitly planned
- Tests not mentioned as part of any task (unit, integration, e2e)
- Documentation updates not planned for user-facing changes
- Configuration changes (env vars, feature flags, config files) not planned
- Build/CI changes needed but not listed
- Seed data or fixtures needed for new features

### Operational Readiness
- No monitoring or alerting plan for new code paths
- No rollback plan for risky changes
- No post-launch validation step (how do we know it works in prod?)
- No error handling or graceful degradation planned
- Missing clean-up or deprecation tasks for old behavior
- No capacity planning for expected load changes

### Completeness of Each Task
- Tasks with vague descriptions ("set up the thing", "handle edge cases")
- Tasks missing clear done-criteria
- Tasks that are actually multiple tasks bundled together
- Tasks that reference dependencies not in the plan

## Key Questions

- Which spec requirement has no plan step covering it?
- What will be obviously missing when the last task is marked done?
- What would an engineer ask "wasn't this supposed to be included?" about?
- If we shipped exactly this plan and nothing more, what would break?
