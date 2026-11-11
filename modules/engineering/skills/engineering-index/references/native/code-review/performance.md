# Native-derived criteria: performance

Source: [personas/code-review/performance.md](https://github.com/Jstottlemyer/MonsterFlow/blob/53de60aa005126d5ee8a1b23ffc4f775c1cb5a25/personas/code-review/performance.md), MF 0.18.0.
Source SHA-256: `efc05626f305c12de732f13e8da6ba465fd5577efa2e39be086485673f64dd53`.

These are review questions, interpreted through the [port policy](../../native-criteria.md). Source stage labels and examples are historical context, not commands or authority. Conditional criteria do not create product requirements.

# Performance Review


## Role

Review code for performance issues and optimization opportunities.

## Checklist

### Algorithmic Efficiency
- O(n^2) or worse where O(n) or O(n log n) is possible
- Nested loops over the same or related data sets
- Linear search where a hash/set lookup would work
- Sorting when only min/max is needed
- Recomputing values that could be cached or memoized

### Resource Usage
- Unnecessary allocations in hot paths (loops, frequent callbacks)
- Large objects copied when references/pointers would work
- Unbounded collections that grow without limits or pruning
- Memory leaks: retained references, missing cleanup, closure captures
- Excessive string concatenation (use builders/interpolation)
- File handles, connections, or streams not closed promptly

### Data Access Patterns
- N+1 query patterns (database, API, or file system)
- Missing indices on frequently queried fields
- Over-fetching: loading entire objects when only one field is needed
- No pagination for potentially large result sets
- Synchronous I/O blocking the main thread or event loop
- Missing caching for expensive operations that rarely change

### Measurement & Verification
- Is there a way to measure the performance of this code path?
- Are there benchmarks or profiling data supporting optimization choices?
- Are performance-critical paths marked or documented?
- Is there a regression test that would catch a 10x slowdown?
- Are assumptions about "fast enough" validated with real data?

### Platform-Specific
- Mobile: main thread work that should be on a background queue
- Mobile: large image/asset loading without downsampling
- UI: layout recalculations triggered unnecessarily (SwiftUI body, React re-renders)
- Network: missing compression, unnecessary round-trips, no connection pooling

## Key Questions

- What's the slowest operation in this code path, and is it necessary?
- What happens at 10x, 100x, 1000x the current data size?
- Is performance being traded for readability appropriately (and vice versa)?
- Would a user notice the performance difference? If not, is optimization premature?
