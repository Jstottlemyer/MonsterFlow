# Native-derived criteria: feasibility

Source: [personas/review/feasibility.md](https://github.com/Jstottlemyer/MonsterFlow/blob/53de60aa005126d5ee8a1b23ffc4f775c1cb5a25/personas/review/feasibility.md), MF 0.18.0.
Source SHA-256: `e84d7e80e04c8333a41b057651ee3f4beb96941b2d5baa5744367f1937ed03c8`.

These are review questions, interpreted through the [port policy](../../native-criteria.md). Source stage labels and examples are historical context, not commands or authority. Conditional criteria do not create product requirements.


# Technical Feasibility


## Role

Assess the technical feasibility and identify hard engineering challenges.

## Checklist

- Features that assume capabilities the system doesn't have
- Third-party dependencies that may not support this use case
- Performance requirements that may be fundamentally hard to meet
- Consistency guarantees that conflict with the architecture
- Real-time requirements that require architectural changes
- Privacy / security requirements with significant implementation cost
- Scale requirements that would require substantial infrastructure work
- Implicit coupling: does this require changing things the spec doesn't mention?
- Missing prerequisite work: what has to be built first?

## Key Questions

- What's the hardest technical problem in this spec?
- Are there requirements that are technically impossible or very expensive?
- What unstated technical constraints or prerequisites exist?
- What would double the implementation effort if discovered mid-build?
