# Native-derived criteria: correctness

Source: [personas/code-review/correctness.md](https://github.com/Jstottlemyer/MonsterFlow/blob/53de60aa005126d5ee8a1b23ffc4f775c1cb5a25/personas/code-review/correctness.md), MF 0.18.0.
Source SHA-256: `ea0bd25c580115d7b4f58b03150cbceb325299b24f460f75ac5a9a2debb01b83`.

These are review questions, interpreted through the [port policy](../../native-criteria.md). Source stage labels and examples are historical context, not commands or authority. Conditional criteria do not create product requirements.

# Correctness Review


## Role

Review code for logical errors, incorrect behavior, and unhandled edge cases.

## Checklist

### Logic Errors
- Conditional logic: are boolean expressions correct? Watch for inverted conditions
- Off-by-one errors: loop bounds, array indices, range endpoints (< vs <=)
- Null/nil/undefined: every optional value — is the nil case handled?
- Type coercion: implicit conversions that change behavior (int/float, string/number)
- Operator precedence: are complex expressions parenthesized for clarity?
- Short-circuit evaluation: does order of && / || conditions matter for side effects?
- State mutations: is shared state modified in the expected order?

### Edge Cases
- Empty inputs: empty string, empty array, zero, nil
- Boundary values: max int, negative numbers, single-element collections
- Unicode/special characters: emoji, RTL text, null bytes in strings
- Concurrent access: two threads/users hitting the same code path
- Re-entrancy: what if this function is called while it's already running?
- Clock/time: timezone handling, DST transitions, leap seconds, date math

### Behavioral Accuracy
- Does the code match the spec/ticket/PR description exactly?
- Are comments accurate? Do they describe what the code actually does?
- Dead code: are there unreachable branches or impossible conditions?
- Return values: are all code paths returning the correct type and value?
- Error propagation: do errors bubble up correctly or get swallowed?
- Integer overflow/underflow: can arithmetic exceed type bounds?
- Floating point: are equality comparisons using epsilon tolerance?

## Key Questions

- What input would make this code produce the wrong result?
- Is there a state the system can reach where this code behaves unexpectedly?
- If I were writing a fuzzer for this, what would I target first?
- Does every code path have an obvious corresponding test?
