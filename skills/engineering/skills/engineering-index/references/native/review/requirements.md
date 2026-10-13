# Native-derived criteria: requirements

Source: [personas/review/requirements.md](https://github.com/Jstottlemyer/MonsterFlow/blob/53de60aa005126d5ee8a1b23ffc4f775c1cb5a25/personas/review/requirements.md), MF 0.18.0.
Source SHA-256: `3aafb1171c35b1379d66567f6e6abaf37b6a8888bcaf7b5f107c42e6b54f72d0`.

These are review questions, interpreted through the [port policy](../../native-criteria.md). Source stage labels and examples are historical context, not commands or authority. Conditional criteria do not create product requirements.


# Requirements Completeness


## Role

Analyze whether the requirements are complete enough to build from.

## Checklist

### Success Criteria
- Missing definition of "done": how will we know this feature is complete?
- No measurable outcomes: are there metrics, thresholds, or benchmarks?
- Subjective criteria: "fast", "good UX", "reliable" without concrete targets
- No A/B or comparison: how do we know the new version is better than the old?

### Failure & Recovery
- Happy path only: what happens when things go wrong?
- No error states defined: what does the user see on failure?
- Missing rollback requirements: can we undo if it breaks?
- No degradation strategy: what works when a dependency is down?
- Recovery time: how fast must the system recover?

### Non-Functional Requirements
- Performance: response time, throughput, latency targets
- Scale: concurrent users, data volume, growth projections
- Reliability: uptime targets, acceptable error rates
- Security: auth requirements, data sensitivity classification
- Accessibility: compliance level (WCAG), assistive technology support
- Observability: monitoring, alerting, logging requirements

### Testability
- Can someone write an automated test from this spec alone?
- Are edge cases defined well enough to write boundary tests?
- Are acceptance criteria binary (pass/fail) or subjective?

## Key Questions

- If a QA engineer read only this spec, could they write a complete test plan?
- Is "done" clearly defined and verifiable by a machine?
- What implicit requirements exist that nobody stated?
- What would a customer consider a bug that the spec doesn't mention?
