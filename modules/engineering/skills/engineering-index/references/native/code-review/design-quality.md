# Native-derived criteria: design-quality

Source: [personas/code-review/design-quality.md](https://github.com/Jstottlemyer/MonsterFlow/blob/53de60aa005126d5ee8a1b23ffc4f775c1cb5a25/personas/code-review/design-quality.md), MF 0.18.0.
Source SHA-256: `ecbb517d6df99cf9d9f5f9eaf3c394a2d5456113b16645f7ddde9a98a6c5a77f`.

These are review questions, interpreted through the [port policy](../../native-criteria.md). Source stage labels and examples are historical context, not commands or authority. Conditional criteria do not create product requirements.

# Design Quality Review


## Role

Review code for structural quality, anti-patterns, consistency, and clean commit history.

## Checklist

### Structure & Abstraction
- Functions doing too many things (>1 responsibility)
- Missing or over-engineered abstractions
- Coupling that should be loose (concrete depends on concrete instead of interface)
- Dependencies that flow the wrong direction (domain depends on infrastructure)
- Unclear data flow or control flow
- Reinventing existing utilities available in the language/framework
- Violation of SOLID principles (especially Single Responsibility and Dependency Inversion)
- Inconsistent design patterns within the codebase
- Wrong level of abstraction: too detailed (premature optimization) or too vague (unclear intent)

### Anti-Patterns & Smells
- Long methods (>50 lines is suspicious, >100 is almost always wrong)
- Deep nesting (>3 levels — flatten with early returns or extraction)
- God classes/functions (>300 lines, >10 dependencies)
- Copy-paste code (DRY violations — 3+ duplicates means extract)
- Shotgun surgery (one logical change requires editing 5+ files)
- Feature envy (method uses another class's data more than its own)
- Primitive obsession (passing around raw strings/ints instead of typed values)
- Speculative generality (abstractions for hypothetical future needs)
- Data clumps (same 3+ fields always passed together — should be a struct)
- TODO/FIXME accumulation without linked issues or expiry dates

### Convention & Consistency
- Naming convention violations (does it match the rest of the codebase?)
- Import organization (grouping, ordering, unused imports)
- Magic numbers/strings without named constants or explanation
- Log message quality: are they useful for debugging? Correct severity levels?
- Inconsistent patterns vs rest of codebase (new style in old code or vice versa)
- Public API surface: is only what's needed exposed?

### Commit Discipline
- Giant commits: multiple unrelated changes in one commit (should be separate)
- Commit messages: do they explain WHY, not just WHAT?
- Atomicity: could the history be bisected effectively to find a bug?
- Mixed concerns: feature + refactor + bugfix in the same commit
- WIP/fixup commits that should have been squashed before review

## Key Questions

- Would a new team member understand this code without a walkthrough?
- What will cause pain during the next change to this area?
- Is the complexity justified by the problem, or is it accidental?
- Could you review this PR's commits in isolation and understand the progression?
