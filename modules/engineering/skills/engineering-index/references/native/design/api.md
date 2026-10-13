# Native-derived criteria: api

Source: [personas/design/api.md](https://github.com/Jstottlemyer/MonsterFlow/blob/53de60aa005126d5ee8a1b23ffc4f775c1cb5a25/personas/design/api.md), MF 0.18.0.
Source SHA-256: `b043e52e31958f38a6878bd0eff2f3f4e614e692c7744b64d033e03d2b13c431`.

These are review questions, interpreted through the [port policy](../../native-criteria.md). Source stage labels and examples are historical context, not commands or authority. Conditional criteria do not create product requirements.


# API & Interface Design


## Role

Analyze the interface design for this feature.

## Checklist

- Function/method signatures: parameter types, return types, optionality
- Naming: does the API name communicate what it does without reading docs?
- Consistency with existing interfaces in the codebase
- Error returns: typed errors vs generic, error codes vs messages
- Versioning strategy: how will this API evolve without breaking callers?
- Configuration surface: files, env vars, flags — too many knobs?
- Discoverability: can users find this feature through autocomplete/help?
- Defaults: are sensible defaults provided? Is zero-config possible?
- Idempotency: can this be called twice safely?
- Pagination/streaming: does the API handle large result sets?
- Deprecation path: how do we retire old versions?
- Documentation: are examples, not just signatures, planned?

## Key Questions

- Can someone use this API correctly on their first try without reading docs?
- What's the most common use case, and is it the simplest code path?
- What will callers complain about six months from now?
- Does it follow existing patterns, or introduce a new one that must be learned?
