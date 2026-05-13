# Weekly Workspace Audit

Run three independent audits in parallel using the Agent tool. Report all findings grouped by audit type. If any audit finds issues, list each file and the specific line or value that triggered it. If an audit finds nothing, write "✓ clean".

## Audit 1 — .md files: personal info

Search all `.md` files in the repo for personal information that shouldn't be committed:
- Full names (e.g., "Justin Stottlemyer", "Justin Hayes Stottlemyer")
- Email addresses (pattern: `\S+@\S+\.\S+`)
- Phone numbers
- Physical addresses, city/state combos tied to a person
- Business names tied to a specific individual (e.g., "Luna's Pavers")
- Social Security numbers or government IDs

Exclude: `personal/` directory (intentionally private, gitignored), `CHANGELOG.md` entries that are historical.

Report: file path, line number, matched text (redact sensitive value with `[REDACTED]` in the report).

## Audit 2 — JSON files: leaked credentials

Search all `.json` files for:
- API keys, tokens, or secrets (patterns: long hex/base64 strings in fields named `key`, `token`, `secret`, `password`, `api_key`, `auth`, `credential`)
- Private key material (`-----BEGIN`)
- Hardcoded bearer tokens
- AWS access key format (`AKIA[0-9A-Z]{16}`)

Exclude: `settings.json` fields that are known-safe command strings (hooks, permissions arrays).

Report: file path, key name, value type (do NOT print the actual value — just confirm its shape, e.g., "32-char hex string").

## Audit 3 — docs/specs/: committed measurement artifacts

The pipeline writes measurement artifacts under `docs/specs/*/` that should be gitignored for most repos. Check for committed files matching:
- `findings*.jsonl`
- `participation.jsonl`
- `survival.jsonl`
- `run.json`
- `raw/` directories
- `source.spec.md` or `source.design.md`
- `.persona-metrics-warned`

Run: `git ls-files docs/specs/ | grep -E "(findings|participation|survival|run\.json|source\.(spec|plan)\.md|\.persona-metrics-warned)"` to check what's actually tracked by git (untracked files in gitignore don't count).

Report: list of committed artifact files found, or "✓ clean".

## Output format

```
=== Weekly Audit — [DATE] ===

### Audit 1: .md personal info
[findings or ✓ clean]

### Audit 2: JSON credentials
[findings or ✓ clean]

### Audit 3: Committed measurement artifacts
[findings or ✓ clean]

### Summary
[X issues found across Y audits — or "All clean"]
```
