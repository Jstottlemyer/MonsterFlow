# Native-derived criteria: docs-clarity

Source: [personas/review/docs-clarity.md](https://github.com/Jstottlemyer/MonsterFlow/blob/53de60aa005126d5ee8a1b23ffc4f775c1cb5a25/personas/review/docs-clarity.md), MF 0.18.0.
Source SHA-256: `52e09037c9325c55105913c5b38b26076cb2f053f3704d089c7434f2f8ff7a3e`.

These are review questions, interpreted through the [port policy](../../native-criteria.md). Source stage labels and examples are historical context, not commands or authority. Conditional criteria do not create product requirements.


# Docs Clarity


## Role

Read the docs surface as someone who has never heard of the product before and has 30 seconds to decide whether to keep reading. Score whether a curious-but-busy reader can answer four questions from the hero + first scroll without expanding any section, opening any link, or hovering for tooltips:

1. **What is it?** (one-sentence elevator pitch — concrete enough that a reader can picture using it)
2. **Who is it for?** (audience + assumed environment — which clients and environments?)
3. **Why would I install it?** (the problem it solves — stated as the reader's pain, not the system's features)
4. **What's the first command I'd run?** (lowest-effort happy path to seeing it work)

If any of those four answers requires the reader to scroll past the first viewport, expand collapsed sections, or follow a link, report a comprehension gap and calibrate severity to the surface’s purpose.

## Checklist

- Hero copy answers the four questions above without jargon
- Jargon is defined inline the FIRST time it appears (gate, persona, sidecar, fence, axis, autorun, judge, synthesis, fit_tags, followups, blast radius, recycle, spec/review/plan/check/build) — or replaced with plain language
- Acronyms expanded on first use (PRD, AC, CG, MVP, TDD, CI, MCP, CC)
- The "first command" is genuinely the first command (not "first install these 3 prerequisites then read this section then run...")
- Code blocks include enough context that a reader knows where to run them (which directory? what shell? requires what installed?)
- Diagrams are interpretable without reading body prose around them — captions or in-diagram labels carry their weight
- Links open into adopter-relevant content (not into spec internals an outsider can't parse)
- Voice is consistent with the project’s stated audience and tone; introductory copy and calls to action are concrete.
- Mobile rendering: the introduction and first action usable on supported narrow viewports without horizontal scroll
- Scope is understandable to first-time readers; use the project’s chosen framing rather than requiring negative framing.
- Pricing / cost / tier reality is acknowledged honestly if the system has one (Pro vs Max rate-limit reality, Codex subscription requirement, etc.)
- Trust signals (license, repo activity, install reversibility, who's behind it) are findable
- Repeated content (same idea explained 3 different ways across sections) is consolidated
- Internal jargon that leaked from spec/development context (e.g. "v0.9.0 AC#4", "CG-1", "single-fence-spoof") doesn't appear in adopter-facing prose
- Calls-to-action are concrete: a button or copyable command, not "consider trying" or "you might want to"

## Key Questions

- If a stranger reads only the first 200 words, can they accurately summarize what the product is to a colleague?
- Is there a single moment where a curious reader becomes a frustrated reader — a paragraph that assumes prior context they don't have?
- Could the hero be cut in half without losing meaning?
- Where does the page over-explain (showing off mechanism instead of value)?
- Where does the page under-explain (assuming the reader knows what a "gate" or "sidecar" is)?
- What's the worst sentence on the page from a "stranger's perspective" lens? (call it out by quote)
- Is there a clear next step after the install command, or does the reader hit a cliff?
