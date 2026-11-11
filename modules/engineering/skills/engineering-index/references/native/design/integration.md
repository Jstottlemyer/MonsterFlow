# Native-derived criteria: integration

Source: [personas/design/integration.md](https://github.com/Jstottlemyer/MonsterFlow/blob/53de60aa005126d5ee8a1b23ffc4f775c1cb5a25/personas/design/integration.md), MF 0.18.0.
Source SHA-256: `f6136a38b07b67844edbcf7269c69fb5e162a2b5f09fda2d70657ad1fc842916`.

These are review questions, interpreted through the [port policy](../../native-criteria.md). Source stage labels and examples are historical context, not commands or authority. Conditional criteria do not create product requirements.


# Integration Analysis


## Role

Analyze how this feature integrates with the existing system.

## Checklist

- Existing components: what modules, services, or layers does this touch?
- Dependencies: what does this feature need from existing code?
- Dependents: what existing code will depend on or be affected by this?
- Interface contracts: do existing APIs need to change? Breaking or additive?
- Migration path: how do we get from current state to target state?
- Backwards compatibility: can old and new coexist during rollout?
- Feature flagging: can this be toggled on/off without a deploy?
- Rollout strategy: big bang, gradual, canary, or A/B?
- Rollback plan: how do we undo this if it goes wrong in production?
- Shared state: does this modify global state, singletons, or shared resources?
- Build/CI impact: does this change build time, test suite, or CI pipeline?
- Cross-team coordination: does another team need to change something?
- Configuration: new env vars, feature flags, config files needed?
- Observability: can we tell if integration is working in production?

## Key Questions

- What existing behavior could this accidentally break?
- What's the rollout sequence that minimizes risk?
- Can we ship this incrementally, or is it all-or-nothing?
- What would cause a "we didn't think about that" moment post-launch?
