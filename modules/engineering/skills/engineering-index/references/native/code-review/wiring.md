# Native-derived criteria: wiring

Source: [personas/code-review/wiring.md](https://github.com/Jstottlemyer/MonsterFlow/blob/53de60aa005126d5ee8a1b23ffc4f775c1cb5a25/personas/code-review/wiring.md), MF 0.18.0.
Source SHA-256: `bf20e7c15100534df8394f4d58ca9d8fee825412641bc27c772e86a14aa20b8c`.

These are review questions, interpreted through the [port policy](../../native-criteria.md). Source stage labels and examples are historical context, not commands or authority. Conditional criteria do not create product requirements.

# Wiring Review


## Role

Detect dependencies, configs, or libraries that were added but not actually used, and old code that should have been replaced.

## Checklist

### New Dependency Not Used
- Swift: package in Package.swift but no `import` in any source file
- Go: module in go.mod but no import in any .go file
- Node: package in package.json but no import/require in source
- Python: package in requirements.txt but no import in source
- Any language: dependency version bumped but no code changes using new API

### Old Code Not Replaced
- New SDK/library added but old manual implementation still in use
- New analytics framework added but old print/log statements remain
- New validation library added but manual validation still inline
- New error handling pattern introduced but old pattern still present
- Feature flag framework added but hardcoded booleans remain

### Config & Environment
- Config key or env var defined but never read in code
- Plist/manifest entry added but never accessed
- Feature flags defined in config but never checked in code
- Default values in config that shadow intended values
- Secrets/API keys referenced in code but not in environment setup docs

### Incomplete Migrations
- Half-migrated patterns: some code uses new approach, some uses old
- Adapter/shim code that was temporary but never cleaned up
- TODO comments marking "replace when X lands" where X has landed
- Import aliases that suggest a migration was planned but not finished
- Database fields added but never populated or read

## Key Questions

- Is every new dependency actually imported and used in source code?
- Are there old patterns that should have been replaced but weren't?
- Is there dead config that suggests an incomplete migration?
- If I deleted every unused import/dependency, would anything break? (It shouldn't.)
