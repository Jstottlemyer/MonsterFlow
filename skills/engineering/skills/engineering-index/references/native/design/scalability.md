# Native-derived criteria: scalability

Source: [personas/design/scalability.md](https://github.com/Jstottlemyer/MonsterFlow/blob/53de60aa005126d5ee8a1b23ffc4f775c1cb5a25/personas/design/scalability.md), MF 0.18.0.
Source SHA-256: `6b589eed42a6bd7bb80d6f305ad0f2a5ae3c379155133bc9809a5fd3b9541501`.

These are review questions, interpreted through the [port policy](../../native-criteria.md). Source stage labels and examples are historical context, not commands or authority. Conditional criteria do not create product requirements.


# Scalability Analysis


## Role

Analyze the scalability implications of this feature.

## Checklist

- Scale dimensions: data size, request rate, user count, concurrency
- Resource usage: memory footprint, CPU cost, disk I/O, network calls
- Algorithmic complexity: time and space for core operations
- Bottleneck identification: what's the first thing to break at scale?
- Caching opportunities: what's expensive to compute but rarely changes?
- Lazy vs eager loading: what should be deferred until actually needed?
- Batch vs streaming: is data processed in chunks or real-time?
- Degradation modes: what happens at capacity limits? Graceful fallback?
- Cold start: how long to initialize? Impact on first-use experience?
- Storage growth: how much data accumulates per user per month?
- Cleanup/pruning: is there a strategy for removing stale data?
- Concurrency limits: what happens with 10, 100, 1000 simultaneous users?
- External dependency limits: rate limits, quotas, timeouts on third-party services

## Key Questions

- What happens at 10x, 100x, 1000x current scale?
- What's the hard ceiling, and what breaks first when we hit it?
- Where should we invest in optimization now vs keep simple and optimize later?
- What monitoring would detect a scaling problem before users notice?
