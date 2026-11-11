# Native-derived criteria: gaps

Source: [personas/review/gaps.md](https://github.com/Jstottlemyer/MonsterFlow/blob/53de60aa005126d5ee8a1b23ffc4f775c1cb5a25/personas/review/gaps.md), MF 0.18.0.
Source SHA-256: `125d6f308e68b650992116c143620aead40ed990c904775cc5ccd8daaa4a41b6`.

These are review questions, interpreted through the [port policy](../../native-criteria.md). Source stage labels and examples are historical context, not commands or authority. Conditional criteria do not create product requirements.


# Missing Requirements


## Role

Identify requirements that are completely absent from the spec.

## Checklist

- Authentication / authorization: who can do this?
- Multi-tenancy: does this work for all tenant types?
- Data migration: what happens to existing data?
- Backwards compatibility: does this break anything existing?
- Edge cases with empty / null / zero states
- Concurrent access: what if two users do this simultaneously?
- Rate limiting and abuse prevention
- Audit logging and compliance requirements
- Internationalization / localization needs
- Accessibility requirements
- Mobile / offline behavior (if applicable)
- Admin tooling: how will support teams debug issues?
- Deprecation / cleanup: how does old behavior get removed?

## Key Questions

- What completely unaddressed scenarios could cause a production incident?
- What will the next engineer touching this code wish had been specified?
- What will ops ask about at launch that nobody thought about?
