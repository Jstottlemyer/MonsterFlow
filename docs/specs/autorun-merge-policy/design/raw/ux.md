# UX Design — autorun-merge-policy

## Key Considerations

The runtime-config banner is the load-bearing UX surface. Three audiences: (1) Justin at 7am scanning yesterday's runs, (2) future power-users hitting it cold, (3) Justin three months later having forgotten what `validated` means. Banner must serve all three without becoming wall-of-text that gets visually skipped.

Banner-fires-forever-until-opt-in works *because* the silencing action is itself the intent-capture (`auto_merge_policy: pr` written explicitly is meaningfully different from `default:pr` resolved silently). Only works if silence path is one obvious YAML line.

Terminal width: autorun runs over SSH from cmux tabs, in tmux panes, at 80-col laptops. Must render at 80c. ANSI color OK with `[ -t 2 ]` gate; `⚠` glyph (U+26A0) is the only visual signal that survives `| tee` and log capture.

## Recommendation: Option C (two-tier)

Fire **verbose** banner when any knob's `resolved_from=default`; once user expressed intent for everything, drop to **terse** 4-line resolved-state summary. Manual-pipeline pointer + override-instruction footer ride on verbose tier only.

**Verbose tier:**
```
=== autorun runtime config: <slug> ===
auto_merge_policy: pr (resolved_from=default)        <- ⚠ on this line only
agent_budget:      6 (resolved_from=default)
gate_mode:         permissive (resolved_from=default)
gate_max_recycles: 2 (resolved_from=default)

This run will: open a PR but NOT auto-merge (default since v0.11.0).

⚠  v0.11.0 flipped the auto-merge default. To restore pre-v0.11 behavior:
   add  auto_merge_policy: clean  to <project>/docs/specs/constitution.md
   or pass --auto-merge=clean once.  Why: docs/specs/autorun-merge-policy/spec.md

Override paths (precedence: CLI > spec > constitution > default):
   per-run:     scripts/autorun/run.sh <slug> --auto-merge=<pr|clean|validated>
   per-spec:    auto_merge_policy: <value>   in spec.md frontmatter
   project:     auto_merge_policy: <value>   in <project>/docs/specs/constitution.md
   one-shot skip: touch queue/<slug>/.manual-review

Prefer gate-by-gate manual review? Abort and run /spec-review interactively.
```

**Terse tier:**
```
=== autorun runtime config: <slug> ===
auto_merge_policy: clean (resolved_from=spec)  agent_budget: 6 (config)
gate_mode: permissive (spec)                   gate_max_recycles: 2 (default)
```

ANSI yellow on `⚠` line when `[ -t 2 ]`; plain otherwise. Width caps 78 cols.

## Other UX Decisions

- **Default-flip warning tone:** matter-of-fact, not apologetic. "Flipped the default" not "we know this is annoying." Justin's voice (per memory `user_writing_voice.md`).
- **Manual-pipeline pointer:** "abort and invoke /spec-review interactively" reads correctly to a power-user. Keep as drafted.
- **`.manual-review` discoverability:** invisible UX otherwise — surface in banner override-paths block. Document fully in `commands/autorun.md`. Future `pipeline-autorun-final-status-render` should hint when `reason=manual_review_requested`.
- **Invalid policy error wording:** `[autorun] error: invalid auto_merge_policy 'yolo' in queue/<slug>.spec.md (allowed: pr | clean | validated). aborting.` — names actual file path (queue copy), pipe-delimited matches CLI flag form, explicit "aborting".
- **Unknown-key warning:** `[autorun] warning: unknown frontmatter key 'auto_merge_polocy' in queue/<slug>.spec.md (did you mean auto_merge_policy?)`. Hardcoded exact-typo hint for the spec's own key — ~2 LoC, no Levenshtein, small carve-back from spec's "no suggestion" stance.
- **CHANGELOG ⚠ BREAKING DEFAULT:** top of v0.11.0 entry, above all other sections. Factual flip-summary. One-line opt-back-in. Adopters see it in first 100 chars.

## Constraints

- bash 3.2 macOS — no associative arrays for resolved-state; use parallel positional arrays.
- 80-col terminal floor.
- `⚠` U+26A0 must survive `| tee` and `cat`.
- AC#10 mandates four knobs + summary + override footer + manual-pipeline pointer + warn-on-default — Option C honors all.
- AC#11 mandates "fires every run where resolved_from=default" — Option C reads as "fires verbose every run where ANY knob is default" which is stricter than spec letter (spec says "for merge policy"). **Flag divergence.**

## Open Questions

- **Q-UX-1:** Verbose tier on any-default OR only merge-policy-default? Owner call.
- **Q-UX-2:** `--merge-policy=` canonical + `--auto-merge=` alias (per Codex L1)?
- **Q-UX-3:** ANSI color on `⚠` line — confirm `[ -t 2 ]` gate is acceptable.

## Integration Points

- `scripts/autorun/_merge_policy.sh::merge_policy_render_banner` — owns both tiers; chooses based on `any_resolved_from_default` flag.
- `scripts/autorun/run.sh` — calls banner immediately after policy resolution, before Phase 0b dispatch.
- `commands/autorun.md` — banner content (both tiers), four override paths, manual-pipeline rationale, silence-the-warning instruction.
- `CHANGELOG.md` — `### ⚠ BREAKING DEFAULT` heading at top of `## [0.11.0]`.
- `templates/constitution.md` — commented `auto_merge_policy:` example.
- Future: `pipeline-autorun-final-status-render` cross-spec UX continuity for `reason=manual_review_requested`.

## Findings (v2 schema)

```yaml
- persona: ux
  finding_id: ux-banner-tier-divergence
  severity: minor
  class: documentation
  title: "Banner verbose-tier fires on any-default; spec letter says merge-policy-default only"
  body: "Recommendation diverges from AC#11 reading. Owner call needed before /build."
  suggested_fix: "Either tighten recommendation to merge-policy-default only, or update AC#11 to 'fires verbose when any knob resolved_from=default; warns on merge-policy-default specifically'."

- persona: ux
  finding_id: ux-unknown-key-suggestion
  severity: nit
  class: scope-cuts
  title: "Carve-back: hardcoded 'did you mean auto_merge_policy?' for the one collision case"
  body: "Spec drops Levenshtein entirely. A hardcoded exact-typo hint for the spec's own key is ~2 LoC and visibly improves the one error path the user is most likely to hit."
  suggested_fix: "If unknown_key == 'auto_merge_polocy' (or matches a tiny hardcoded set), append '(did you mean auto_merge_policy?)' to the warning. No Levenshtein, no scope creep."

- persona: ux
  finding_id: ux-touch-file-discoverability
  severity: minor
  class: documentation
  title: ".manual-review touch-file path needs banner surface + morning-summary hint"
  body: "Per-run escape hatch is invisible UX unless surfaced. Banner override-paths block should include it; future morning-summary spec should hint when reason=manual_review_requested."
  suggested_fix: "Add 'one-shot skip: touch queue/<slug>/.manual-review' to banner override paths block; cross-reference in commands/autorun.md."
```
