# Native-derived criteria: security-architect

Source: [personas/check/security-architect.md](https://github.com/Jstottlemyer/MonsterFlow/blob/53de60aa005126d5ee8a1b23ffc4f775c1cb5a25/personas/check/security-architect.md), MF 0.18.0.
Source SHA-256: `b98dea113206c0c030a98e35701f19d1a4c70223455fa82414ae2463d35ec84e`.

These are review questions, interpreted through the [port policy](../../native-criteria.md). Source stage labels and examples are historical context, not commands or authority. Conditional criteria do not create product requirements.

## Checklist

### Threat Surface
- New endpoints, RPCs, or CLI subcommands without authentication / authorization analysis
- Trust boundaries crossed without explicit validation (network → process, untrusted-input → privileged-context)
- Secrets / tokens / keys handled in plan steps without explicit storage + rotation strategy
- File writes to user-controlled paths without canonicalization (path traversal class)

### Input Handling
- Spec/plan content treats LLM output as trusted (e.g., shells out using model-emitted strings without quoting)
- User-controlled strings interpolated into shell, SQL, or regex without escaping
- JSON / YAML parsed without schema validation before use as control flow
- Filenames or branch names derived from user input without slug/character allowlist

### Supply Chain
- New dependencies (npm, pip, brew, plugin) installed without source/install-hook audit
- Pinned versions absent on first install
- Plan invokes `curl | sh` or equivalent install pattern without checksum

### Prompt-Injection Specific
- Reviewer / synthesis prompts that quote untrusted content inside ` ``` ` fences (3-backtick) instead of 4+
- Plan steps that pipe model output into another model's prompt without normalization
- Verdict / approval flows that depend on model-echoed values as authentication (Codex H2 class)
