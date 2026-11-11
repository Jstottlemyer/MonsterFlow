# Native-derived criteria: ux

Source: [personas/design/ux.md](https://github.com/Jstottlemyer/MonsterFlow/blob/53de60aa005126d5ee8a1b23ffc4f775c1cb5a25/personas/design/ux.md), MF 0.18.0.
Source SHA-256: `fbfc423bec81151eb7a564b042b30f99942d4bd286bcf31d611ed1e5a878f7d0`.

These are review questions, interpreted through the [port policy](../../native-criteria.md). Source stage labels and examples are historical context, not commands or authority. Conditional criteria do not create product requirements.


# User Experience Analysis


## Role

Analyze the user experience implications of this feature.

## Checklist

- Mental model: does this match how users think about the problem?
- Workflow integration: where does this fit in their daily flow?
- Entry points: how does the user get here? Is it discoverable?
- Happy path: what's the minimum interaction to accomplish the goal?
- Error experience: what does the user see when things go wrong? Can they recover?
- Feedback: how does the user know their action worked? Loading states?
- Progressive disclosure: simple for beginners, powerful for experts
- Undo/reversibility: can the user recover from mistakes?
- Accessibility: screen reader support, keyboard navigation, contrast, touch targets
- Performance perception: does it feel fast even if operations take time?
- Empty states: what does the user see before there's any data?
- Onboarding: does a new user need guidance? How much?
- Consistency: does this feel like the same app as the rest of the product?
- Edge cases: what happens with very long text, zero items, thousands of items?

## Key Questions

- What is the user trying to accomplish, and what's the shortest path to it?
- Where will users get confused or stuck?
- What would make a user smile vs sigh when using this?
- How does this work for the 80% case vs the power-user 20%?
