<!-- BEGIN autoship-detection -->
## Autoship Detection (V3 Path B)

Before this gate's work begins, scan all user messages in the current Claude Code session for the literal substring:

  `is shipped via merged PR with verifier reporting`

If found AND no subsequent `/goal clear` invocation since the most recent trigger:

1. Extract the spec slug from the matched /goal line (regex: `docs/specs/([a-z0-9][a-z0-9-]{0,63})/spec\.md`).
2. If the extracted slug matches this gate's feature argument:
   - Emit exactly: `[autoship] active goal detected — proceeding autonomously through pipeline`
   - Set internal flag: autoship-active = true
   - Skip the manual approval prompt for this gate
3. If slug mismatches:
   - Emit: `[autoship] /goal active for <other-slug>, current gate is <this-slug> — manual mode`
   - autoship-active = false

Otherwise: autoship-active = false; existing AUTORUN=1 env-var check, then existing approval prompt.
<!-- END autoship-detection -->
