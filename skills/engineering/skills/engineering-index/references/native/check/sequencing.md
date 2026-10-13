# Native-derived criteria: sequencing

Source: [personas/check/sequencing.md](https://github.com/Jstottlemyer/MonsterFlow/blob/53de60aa005126d5ee8a1b23ffc4f775c1cb5a25/personas/check/sequencing.md), MF 0.18.0.
Source SHA-256: `10cced6eee9e9b679fbfe1b96bfde961b7de29a91d63ae6957cdf29441703b8b`.

These are review questions, interpreted through the [port policy](../../native-criteria.md). Source stage labels and examples are historical context, not commands or authority. Conditional criteria do not create product requirements.


# Sequencing and Dependencies


## Role

Verify that the plan's sequencing and dependencies are sound and executable.

## Checklist

### Dependency Correctness
- Steps that depend on things not yet built at that point in the plan
- Schema migrations that must happen before code that uses new schema
- API changes that need coordination between consumer and provider
- Infrastructure that needs to exist before application code can run
- Configuration or feature flags needed before the feature itself
- Circular dependencies hiding between tasks

### Parallelization
- Steps listed sequentially that could safely run in parallel
- Steps listed in parallel that actually have a hidden dependency
- Shared state between parallel tasks that could cause conflicts
- Test tasks that depend on implementation tasks but aren't sequenced after them

### Critical Path
- What's the longest chain of dependent tasks? (That's the minimum timeline)
- Are high-risk or high-uncertainty tasks early enough to de-risk?
- Are blocking tasks (things many other tasks depend on) scheduled first?
- Is there a single task that, if delayed, delays everything?

### Integration Points
- Database seed data or test fixtures needed before certain tasks
- External API availability required at specific points
- Cross-team handoffs or approvals needed mid-plan
- Environment setup (staging, CI) as prerequisites
- Feature flag state changes needed at specific sequencing points

## Key Questions

- Can every task start immediately when its listed dependencies are done?
- What would cause a "we can't proceed" moment mid-implementation?
- Which tasks could be reordered to reduce idle time between dependent tasks?
- Is the riskiest work front-loaded or buried at the end?
