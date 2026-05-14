# Resolver-error recovery (canonical fragment)

Used by `commands/{spec-review,blueprint,check}.md` Phase 0b when
`scripts/resolve-personas.sh` exits non-zero, is missing, or emits empty stdout.
This is the **single source of truth** for AC #7 (interactive recovery) and AC
#8 (non-tty abort) of the `account-type-agent-scaling` feature spec.

## STOP — tempting wrong recoveries (read this before the decision tree)

The model running this fragment WILL be tempted to invent one of the following
silent recoveries because they sound user-friendly. **Every one is forbidden.**
If you find yourself about to print or do any of these, halt and re-read the
decision tree below — you are off-script:

- ❌ *"Resolver not found — falling back to full roster at sonnet tier (no
  budget config)."* — This conflates a missing-script error with the resolver's
  legitimate no-config-default. They are different cases. A missing/failed
  resolver is **never** "no budget config." Decision D6 explicitly dropped the
  silent full-roster recovery. If you emit this line, you are violating the
  spec — abort the gate or prompt the user instead.
- ❌ *"Emulating the resolver's default behavior since the script is missing."*
  — You are not the resolver. Do not improvise its output. If it is not on
  disk, that is an install drift bug and the user needs to know.
- ❌ *"Dispatching the hardcoded seed list to keep the gate moving."* — Seed
  fallback is only legal as option (2) of the interactive prompt below, and
  only after the user explicitly chose it. Never auto-select it for the user.
- ❌ *"Skipping Phase 0b because the resolver failed."* — Phase 0b is not
  optional. Skipping it produces an unaudited dispatch with no
  `selection.json`.

The single legal recoveries are: interactive 3-option prompt, OR non-TTY
abort. Nothing else. If the friendly-sounding fallback you are about to apply
is not in the decision tree below, you are improvising — stop and follow the
tree.

## Decision tree (apply in order)

1. **Bypass check first.** If env `MONSTERFLOW_DISABLE_BUDGET=1` is set, the
   resolver should never have failed (kill switch already short-circuits in the
   shell wrapper). If we got here with the bypass set, it is a bug — abort the
   gate and surface the resolver stderr verbatim. Do not prompt.

2. **Non-tty / autorun mode.** If any of the following are true, **ABORT the
   gate** with the resolver's exit code (or `1` if exit was 0 but stdout was
   empty). Do not prompt. Do not silently fall back to a seed list. The spec
   forbids reduced-behavior success in headless mode (see
   `feedback_dryrun_full_graph.md`):
   - `AUTORUN=1` is exported in the environment, OR
   - stdin is not a TTY (`[ ! -t 0 ]`), OR
   - stdout is not a TTY (`[ ! -t 1 ]`).
   The consumer's autorun stage script (e.g. `scripts/autorun/spec-review.sh`)
   surfaces the resolver stderr to the run log; the operator must fix config
   and re-run. Kill switch: `MONSTERFLOW_DISABLE_BUDGET=1` bypasses the budget
   entirely (full roster).

3. **Interactive mode (TTY, AUTORUN unset).** Print the resolver's stderr to
   the user, then present the recovery prompt verbatim:

   ```
   Resolver script failed (exit <RESOLVER_EXIT>). Options:
     (1) reconfigure now    — re-run install.sh --reconfigure-budget, then retry the gate
     (2) continue with seed — dispatch the per-gate seed list (no rankings, no pins)
     (3) abort gate         — exit non-zero, leave config untouched

   Choose [1/2/3]:
   ```

   Read one line from stdin. Branch on the user's choice:

   - **(1) reconfigure now** — Run `bash <REPO_DIR>/install.sh --reconfigure-budget`
     in the foreground (inherits the user's TTY). On exit 0, re-invoke the
     resolver once. If it still fails, abort the gate (do not loop the
     prompt — one retry only). On non-zero exit from install.sh, abort the gate.

   - **(2) continue with seed** — Read the gate's seed list from
     `scripts/resolve-personas.sh --print-seed <gate>` (or, if that flag is
     absent, fall back to the hardcoded gate→seed map below). Use the seed
     list as `$SELECTED` and proceed with dispatch. **Do not** retry the
     resolver. Print a one-line warning: `[budget] resolver failed; using seed
     list (no rankings, no pins, no Codex)`. Codex is omitted in seed mode
     because the resolver owns the auth probe.

   - **(3) abort gate** — Exit non-zero with the resolver's exit code.

   - **Any other input** — Re-prompt once. After two invalid responses, abort
     the gate.

## Hardcoded gate→seed fallback (used if resolver cannot print)

| Gate | Seed list (priority order) |
|------|----------------------------|
| spec-review | requirements, gaps, scope, ambiguity, feasibility, stakeholders |
| plan | integration, api, data-model, security, ux, scalability, wave-sequencer |
| check | scope-discipline, risk, completeness, sequencing, testability |

These mirror `docs/specs/account-type-agent-scaling/spec.md` §"Per-gate seed
list". The resolver is the source of truth; this fallback exists only for the
case where the resolver itself cannot run.

## Why no "disable budget for this run"

The original spec listed a third recovery option, *"disable budget for this
run"*, which would have dispatched the full roster. Plan decision **D6** drops
that option (and spec patch **SP3** updates the spec to match): silently
restoring the full roster on a budgeted session contradicts AC #7 ("none of
the recovery options silently restore full roster"). The kill switch is now
the explicit env var `MONSTERFLOW_DISABLE_BUDGET=1`, which the user must set
before the gate runs — it is not exposed as a recovery option after a
resolver failure.

## Exit-code mapping (consumer responsibility)

After this fragment completes, the gate command continues normally with
`$SELECTED` populated, OR exits non-zero. The fragment never silently
"succeeds with reduced behavior" without writing a seed-mode warning.
