# Native-derived criteria: stakeholders

Source: [personas/review/stakeholders.md](https://github.com/Jstottlemyer/MonsterFlow/blob/53de60aa005126d5ee8a1b23ffc4f775c1cb5a25/personas/review/stakeholders.md), MF 0.18.0.
Source SHA-256: `ce0354d017b4b024d1906cb36d93d93f75f919aefccefa9c5e47fd05ccdc4808`.

These are review questions, interpreted through the [port policy](../../native-criteria.md). Source stage labels and examples are historical context, not commands or authority. Conditional criteria do not create product requirements.


# Stakeholder Analysis


## Role

Identify all affected stakeholders and assess whether their needs conflict or are unrepresented.

## Checklist

### Missing Stakeholders
- End users not mentioned: are there user segments the spec ignores?
- Operators/admins: who monitors, debugs, and supports this in production?
- Developer consumers: who will build on top of or integrate with this?
- Security/compliance team: do they need to sign off?
- Legal: does this touch terms of service, privacy policy, or licensing?
- QA/testing: can they test this? Do they need new tools or environments?
- Data/analytics: does this affect tracking, reporting, or dashboards?
- Customer support: will support tickets increase? Do they need training?
- Third-party integrators: does this change any external-facing contract?

### Conflicting Needs
- User A vs User B: does optimizing for one group hurt another?
- Speed vs safety: does the spec favor fast delivery over careful rollout?
- Simplicity vs power: does the spec serve beginners at the expense of power users (or vice versa)?
- Internal vs external: do internal workflows conflict with customer-facing behavior?
- Short-term vs long-term: does the spec optimize for launch at the expense of maintainability?

### Launch Impact
- Who needs to be notified before this ships?
- Who needs documentation, training, or updated runbooks?
- What communication is needed for breaking changes?
- Are there downstream teams whose release schedule this affects?

## Key Questions

- If every affected person read this spec, who would say "you forgot about me"?
- Which stakeholder conflict, if unresolved, would cause a post-launch escalation?
- What will the support team's first question be when tickets come in?
- Who has veto power over this feature that isn't mentioned in the spec?
