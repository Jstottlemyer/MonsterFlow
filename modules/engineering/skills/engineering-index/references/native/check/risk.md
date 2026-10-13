# Native-derived criteria: risk

Source: [personas/check/risk.md](https://github.com/Jstottlemyer/MonsterFlow/blob/53de60aa005126d5ee8a1b23ffc4f775c1cb5a25/personas/check/risk.md), MF 0.18.0.
Source SHA-256: `741afcf5ea68c64f2e1942633a43a77943d627ea2c1141a7f01135e2cd3eda3d`.

These are review questions, interpreted through the [port policy](../../native-criteria.md). Source stage labels and examples are historical context, not commands or authority. Conditional criteria do not create product requirements.


# Risk Assessment


## Role

Identify implementation risks, unknowns, and potential failure modes in the plan.

## Checklist

### Technical Risk
- Steps involving novel technology or approaches the team hasn't used before
- External dependencies with reliability, availability, or rate-limit risk
- Steps that are hard to test or verify until deployed
- Database migrations that are difficult or impossible to reverse
- Breaking changes to existing integrations, APIs, or data formats
- Performance risks with no load testing or benchmarking step
- Security surface expansion without a security review step

### Estimation Risk
- "We'll figure it out" language or vague task descriptions
- Steps with estimates that seem unrealistic for their complexity
- Tasks that assume immediate understanding of unfamiliar code
- No buffer for discovery work or unexpected complexity
- Dependency on undocumented systems or tribal knowledge

### Execution Risk
- Single points of failure in the implementation sequence
- Tasks that can only be done by one specific person
- Long-running tasks with no intermediate checkpoints
- Changes to shared infrastructure affecting other teams/systems
- No escape hatch: if this approach fails at step 5, is there a pivot?

### Blast Radius
- What's the worst realistic outcome if the riskiest step fails?
- How many users/systems are affected by a failure?
- Is the damage reversible or permanent?
- Are there data-loss scenarios?

## Key Questions

- What's the highest-risk step, and does the plan de-risk it early?
- What assumption in this plan is most likely to be wrong?
- What's the recovery plan if the critical step fails mid-implementation?
- If you had to bet against this plan, where would you place the bet?
