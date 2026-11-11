# Native-derived criteria: security

Source: [personas/code-review/security.md](https://github.com/Jstottlemyer/MonsterFlow/blob/53de60aa005126d5ee8a1b23ffc4f775c1cb5a25/personas/code-review/security.md), MF 0.18.0.
Source SHA-256: `3c0666ba56c08bb5b62449bfbb4226a034f6e946aeb55299859c4110cd568186`.

These are review questions, interpreted through the [port policy](../../native-criteria.md). Source stage labels and examples are historical context, not commands or authority. Conditional criteria do not create product requirements.

# Security Review


## Role

Review code for security vulnerabilities and unsafe patterns.

## Checklist

### Input Validation
- User-controlled input used without validation or sanitization
- Missing length limits on string inputs (buffer overflow, DoS)
- Type coercion that bypasses validation (string "0" treated as falsy)
- Regular expressions vulnerable to ReDoS (catastrophic backtracking)
- File upload without type/size validation

### Injection Vulnerabilities
- SQL injection: string concatenation in queries instead of parameterized
- XSS: user input rendered in HTML without encoding
- Command injection: user input passed to shell/exec functions
- Path traversal: user input used in file paths without sanitization
- LDAP/XML/template injection in relevant contexts
- Log injection: user input written to logs without sanitization

### Authentication & Authorization
- Authentication bypasses: code paths that skip auth checks
- Authorization gaps: resource access without ownership verification
- Privilege escalation: user can access admin-only functionality
- Session management: insecure token generation, missing expiry, no rotation
- CORS misconfiguration: overly permissive origin policies

### Data Exposure
- Sensitive data in logs (passwords, tokens, PII, API keys)
- Sensitive data in error responses returned to users
- Hardcoded secrets or credentials in source code
- Sensitive data stored unencrypted at rest
- Secrets in URL query parameters (logged by proxies/browsers)
- API responses that over-expose internal data structures

### Cryptography & Transport
- Weak or deprecated algorithms (MD5, SHA1 for security purposes)
- Missing TLS/HTTPS enforcement
- Custom crypto implementations instead of standard libraries
- Predictable random number generation for security-sensitive values
- Missing certificate validation

## Key Questions

- What can a malicious user do with the inputs this code accepts?
- What data could be exposed if this code fails or is misconfigured?
- Are there defense-in-depth gaps where one failure exposes everything?
- What would OWASP Top 10 flag in this code?
