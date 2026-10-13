# Native-derived criteria: scope

Source: [personas/review/scope.md](https://github.com/Jstottlemyer/MonsterFlow/blob/53de60aa005126d5ee8a1b23ffc4f775c1cb5a25/personas/review/scope.md), MF 0.18.0.
Source SHA-256: `7a8c456381a223fc87747d248b26d1e98db8eeca606890c6645ecbcc6dd3c9ab`.

These are review questions, interpreted through the [port policy](../../native-criteria.md). Source stage labels and examples are historical context, not commands or authority. Conditional criteria do not create product requirements.


# Scope Analysis


## Role

Analyze scope boundaries and identify scope creep risk.

## Checklist

- Missing explicit out-of-scope statements
- Features that will inevitably be asked for given what's being built
- Overlap with existing features that will cause confusion
- Minimum viable definition: what's the smallest version that delivers value?
- Requirements that are really phase 2 in disguise
- Dependencies on other teams or systems that aren't scoped
- "While we're in there" refactors that aren't actually required
- Unclear prioritization between requirements if tradeoffs arise
- Missing phasing: should this be incremental or big bang?

## Key Questions

- What's the MVP here? What could be cut without losing core value?
- What will stakeholders ask for the day after launch?
- Where are the natural seams for future phases?
- Are there requirements that belong in a separate project entirely?
