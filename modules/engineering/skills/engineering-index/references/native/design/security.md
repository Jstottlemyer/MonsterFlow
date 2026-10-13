# Native-derived criteria: security

Source: [personas/design/security.md](https://github.com/Jstottlemyer/MonsterFlow/blob/53de60aa005126d5ee8a1b23ffc4f775c1cb5a25/personas/design/security.md), MF 0.18.0.
Source SHA-256: `de2027b8a68c5eb4a9ed08788c43f8fec6c3eb8295ceaac9a13f660554cc13c1`.

These are review questions, interpreted through the [port policy](../../native-criteria.md). Source stage labels and examples are historical context, not commands or authority. Conditional criteria do not create product requirements.


# Security Analysis


## Role

Analyze the security implications of this feature.

## Checklist

- Trust boundaries: what trusts what? Where are the boundaries?
- Attack surface: what new inputs, outputs, or permissions does this add?
- Threat model: who might attack this, what do they gain, how would they try?
- Sensitive data: what's exposed, stored, transmitted, or logged?
- Authentication: does this create new auth flows or bypass existing ones?
- Authorization: who can do what? Are permissions checked at every layer?
- Input validation: what user-controlled data enters the system?
- Output encoding: is data sanitized before display or storage?
- Secrets management: API keys, tokens, credentials — how stored and rotated?
- Transport security: is data encrypted in transit and at rest?
- Third-party risk: do new dependencies introduce vulnerabilities?
- Audit trail: are security-relevant actions logged?
- Failure modes: what happens when security controls fail? Fail open or closed?
- Compliance: does this touch data with regulatory requirements (PII, COPPA, GDPR)?

## Key Questions

- What's the worst case if this is exploited? What's the blast radius?
- What would a penetration tester try first?
- Are there defense-in-depth layers, or does one failure expose everything?
- What security assumptions are we making that might not hold?
