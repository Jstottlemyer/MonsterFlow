# raw-edge-cases.md — bullet-regex (D11) exclusion fixture

This file is consumed by `tests/test-compute-persona-value.sh` to assert that the bullet-counting regex excludes the four classes documented in D11. The expected `count_raw_bullets()` result is **3** — only the three top-level bullets under `## Critical Gaps` and `## Important Considerations`.

## Critical Gaps

- top-level bullet — counted (1)
  - nested bullet under top-level — NOT counted
- another top-level bullet — counted (2)

## Important Considerations

* star-prefixed top-level — counted (3)
1. numbered list — NOT counted
2. another numbered — NOT counted
 - leading-space dash — NOT counted (not column-zero)
  - two-space-indented dash — NOT counted

## Verdict

- This bullet under Verdict heading — NOT counted
- Verdict bullets are explicitly excluded by D11
