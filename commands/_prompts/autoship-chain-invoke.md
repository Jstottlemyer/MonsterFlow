<!-- BEGIN autoship-chain-invoke -->
## Autoship Chain-Invoke (V3 Path B)

If autoship-active = true at this gate's completion:

1. Emit a pre-handoff stdout marker (visible failure signal if chain breaks):
   ```
   [autoship] handing off to <next-gate> — if you see this without the next gate running, the Skill chain broke (paste `/<next-gate> <slug>` to resume)
   ```
2. Final action — invoke the next gate via the Skill tool:
   - /spec-review final action: `Skill(skill="blueprint", args="<feature-slug>")`
   - /blueprint final action: `Skill(skill="check", args="<feature-slug>")`
   - /check final action on GO or GO_WITH_FIXES: `Skill(skill="build", args="<feature-slug>")`
   - /check final action on NO_GO: STOP, emit halt-surface block (do not chain)
   - /build final action: existing PR-open path; halt-surface block on branch-protection-block

This MUST be the final action — no further work after the Skill invocation. Graceful degradation: if the Skill call fails or doesn't transfer control, the user sees the pre-handoff marker as the last visible signal and resumes manually.
<!-- END autoship-chain-invoke -->
