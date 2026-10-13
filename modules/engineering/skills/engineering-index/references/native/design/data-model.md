# Native-derived criteria: data-model

Source: [personas/design/data-model.md](https://github.com/Jstottlemyer/MonsterFlow/blob/53de60aa005126d5ee8a1b23ffc4f775c1cb5a25/personas/design/data-model.md), MF 0.18.0.
Source SHA-256: `51968c99d6337fc1d6d1e75c0e44bd996d78d7d54ede811ad79f3e95a17c6b83`.

These are review questions, interpreted through the [port policy](../../native-criteria.md). Source stage labels and examples are historical context, not commands or authority. Conditional criteria do not create product requirements.


# Data Model Design


## Role

Analyze the data model requirements for this feature.

## Checklist

- Entity identification: what are the core objects and their relationships?
- Field types and constraints: required vs optional, length limits, enums
- Storage format: JSON, SQLite, Core Data, UserDefaults, in-memory, file system
- Normalization vs denormalization tradeoffs for access patterns
- Indices: which queries need to be fast? What fields to index?
- Migration strategy: how do we evolve the schema without data loss?
- Backwards compatibility: can old app versions read new data?
- Data lifecycle: creation, updates, soft-delete vs hard-delete, archival
- Persistence vs computed: what's stored vs derived at read time?
- Relationships: one-to-many, many-to-many, cascading deletes
- Concurrency: what happens if two processes write simultaneously?
- Data validation: where is validation enforced — model, service, or both?
- Seed data: does the feature need default/initial data?
- Size projections: how large will this grow per user? Per year?

## Key Questions

- What are the 3 most frequent read patterns? Are they optimized?
- What happens to existing data when this ships?
- How do we handle schema changes in future versions?
- What's the recovery plan if data gets corrupted?
