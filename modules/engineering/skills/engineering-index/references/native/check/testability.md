# Native-derived criteria: testability

Source: [personas/check/testability.md](https://github.com/Jstottlemyer/MonsterFlow/blob/53de60aa005126d5ee8a1b23ffc4f775c1cb5a25/personas/check/testability.md), MF 0.18.0.
Source SHA-256: `d9531251af86ed71892baae4e84c20848d8f4dfb9d5c901307490eca15da1401`.

These are review questions, interpreted through the [port policy](../../native-criteria.md). Source stage labels and examples are historical context, not commands or authority. Conditional criteria do not create product requirements.


# Testability and Verifiability


## Role

Assess whether the implementation will be verifiable once complete.

## Checklist

### Test Coverage Gaps
- Plan steps with no associated test strategy
- Features that are hard to test in isolation (tightly coupled)
- End-to-end flows with no integration test planned
- No definition of what "passing" looks like for each step
- Edge cases identified in review but no corresponding test planned

### Verification Strategy
- Unit tests: are pure logic paths tested without mocking everything?
- Integration tests: do components work together as planned?
- UI/visual tests: are user-facing changes verified (screenshots, snapshots)?
- Performance tests: are load/scale claims verified with benchmarks?
- Smoke tests: what's the minimum check that proves deployment worked?
- Regression tests: does existing behavior remain intact?
- Manual vs automated: which tests MUST be automated vs acceptable manual?

### Observability
- How will we know this is working in production? Metrics? Logs? Alerts?
- What's the first signal that something went wrong?
- Are error rates, latency, and throughput monitored for new code paths?
- Can we distinguish "feature is broken" from "feature is unused"?

### Platform-Specific
- Mobile: are device-specific behaviors tested (different screen sizes, OS versions)?
- API: are contract tests in place for consumers?
- CLI: are command-line args, flags, and error outputs tested?
- Data: are migration tests run against realistic data sets?

## Key Questions

- After all tasks are closed, how do we prove the feature works end-to-end?
- Which plan steps have acceptance criteria verifiable by a machine?
- What would a test failure look like for the riskiest part of this plan?
- If we skip testing step X, what's the worst realistic outcome?
