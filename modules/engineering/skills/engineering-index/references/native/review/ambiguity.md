# Native-derived criteria: ambiguity

Source: [personas/review/ambiguity.md](https://github.com/Jstottlemyer/MonsterFlow/blob/53de60aa005126d5ee8a1b23ffc4f775c1cb5a25/personas/review/ambiguity.md), MF 0.18.0.
Source SHA-256: `f29b9c0023c5248a6d76d7b66aeae488714954c9ad341699637d9fd31db4051c`.

These are review questions, interpreted through the [port policy](../../native-criteria.md). Source stage labels and examples are historical context, not commands or authority. Conditional criteria do not create product requirements.


# Ambiguity Analysis


## Role

Find statements in the spec that are ambiguous or open to multiple interpretations.

## Checklist

### Vague Language
- Weasel words: "fast", "simple", "reasonable", "appropriate", "as needed", "etc."
- Undefined quantities: "many", "some", "a few", "large", "small"
- Hedge words: "usually", "generally", "in most cases" — what about the other cases?
- "Easy" or "intuitive" without defining for whom

### Undefined Terms
- Domain concepts used without definition (jargon, acronyms)
- Technical terms used ambiguously (does "cache" mean in-memory, on-disk, CDN?)
- "User" without distinguishing between user types/personas
- Borrowed terminology from other features that may mean something different here

### Contradictions
- Two requirements that can't both be true simultaneously
- Conflicting priorities without explicit hierarchy
- "Must" in one place, "should" for the same thing elsewhere
- Diagrams or examples that don't match the text description

### Underspecification
- Conditional requirements without defined conditions ("when X" but X isn't defined)
- Scope boundaries stated as "similar to X" without defining what "similar" means
- Undefined ordering when multiple things need to happen
- Missing default behavior: what happens if no choice is made?
- "Should" vs "must" vs "could" used inconsistently: what's required vs optional?

## Key Questions

- Which sentence would two engineers implement differently?
- What will cause a PR review debate because the spec doesn't say?
- If I highlighted every ambiguous word, how much of the spec is yellow?
- What question will someone ask 3 days into implementation that should be answered now?
