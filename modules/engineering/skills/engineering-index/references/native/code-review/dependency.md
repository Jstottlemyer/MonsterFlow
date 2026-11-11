# Native-derived criteria: dependency

Source: [personas/code-review/dependency.md](https://github.com/Jstottlemyer/MonsterFlow/blob/53de60aa005126d5ee8a1b23ffc4f775c1cb5a25/personas/code-review/dependency.md), MF 0.18.0.
Source SHA-256: `b00eecea9b0a6a5f988b0bb8ce3fad2bc6a609628258ded1cd918a7be7d2e74d`.

These are review questions, interpreted through the [port policy](../../native-criteria.md). Source stage labels and examples are historical context, not commands or authority. Conditional criteria do not create product requirements.

# Dependency Review


## Role

Review code for dependency risks and supply chain concerns.

## Checklist

### New Dependency Assessment
- Is the package actively maintained? (Last commit, open issues, response time)
- How many weekly downloads / stars? (Popularity isn't quality, but abandonment is risk)
- Who maintains it? (Individual vs organization, bus factor)
- Does it have a security policy and CVE track record?
- What's the dependency's own dependency tree? (Transitive risk)

### License & Legal
- License compatibility with our project's license
- Copyleft licenses (GPL) in non-copyleft projects
- No license at all (legally ambiguous — avoid)
- License changes between versions (check upgrade path)

### Version Hygiene
- Floating versions (^, ~, *, "latest") instead of pinned
- Major version jumps without reviewing the changelog
- Outdated dependencies with known CVEs
- Lock file committed and up to date (package-lock, Podfile.lock, etc.)

### Necessity & Alternatives
- Is this dependency necessary? Could 20 lines of code replace it?
- Are we using 5% of a large library? Is there a lighter alternative?
- Does this duplicate functionality already in the project or language stdlib?
- Size impact: how much does this add to bundle/binary size?

### Update & Maintenance Strategy
- How will we keep this dependency current?
- Is there a breaking-change history that suggests painful upgrades?
- Would vendoring be safer than registry for stability-critical deps?
- Are there automated tools (Dependabot, Renovate) configured?

### Platform Compatibility
- Does this work on all target platforms (iOS versions, OS versions)?
- Any native dependencies that require special build steps?
- Does it conflict with other dependencies already in the project?

## Key Questions

- If this dependency disappeared tomorrow, how hard is the replacement?
- What's the security track record of this package's maintainers?
- Are we introducing a dependency for convenience that becomes a liability?
- In 2 years, will we regret adding this?
