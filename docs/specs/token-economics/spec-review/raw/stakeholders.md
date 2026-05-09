# Stakeholder Analysis Review — token-economics v4.2

## Critical Gaps

- **Persona authors as data subjects are unrepresented.** The spec treats personas as roster entries but a persona has a human author (in MonsterFlow defaults: Justin; in adopter forks: anyone who edits/adds a persona). The dashboard renders "highest/lowest" rankings per persona by name, and the warning banner only addresses *adopters who screenshot*. Nothing addresses *the persona author whose work shows up bottom-3 in someone else's screenshot*. For a public-release repo accepting persona PRs, this is a contributor-ranking surface and the spec doesn't say so. Add: who owns persona-quality narratives, and what's the contributor-facing message when "your persona ranks low on judge-retention."

- **The motivating stakeholder (Pro-tier friend) gets nothing in v1.** Spec opens with "Pro-tier relief comes in v1.1 (BACKLOG #3) immediately after this lands." The person whose pain motivated the work ships measurement only — no cost reduction. There's no commitment in the spec on what "immediately after" means (1 week? 1 month? after ≥10 validated runs — which could be slow on a single user). The "≥10 validated runs" gate could leave the friend on Pro indefinitely if they're not the one accumulating runs. Add an explicit timeline or a fallback (e.g., if 10 runs not reached in 30 days, revisit BACKLOG #3 unblocked).

- **Customer-support / triage path missing.** First adopter question after this ships: "my persona is bottom-3 on every gate — is it broken, or is the metric noise?" There's no documented path from a low score to a diagnosis. The dashboard shows numbers, the wrap-insights text shows top/bottom 3, but no runbook ("low judge-retention with high uniqueness usually means…", "if downstream-survival is null and runs ≥3, check survival.jsonl freshness"). Spec assumes adopters self-interpret; given the ratios are statistically tricky (compression vs survival, machine-local windows, content-hash transients), this is optimistic.

## Important Considerations

- **Non-tty adopters beyond Justin.** M6 added `--confirm-scan-roots` because Justin's tmux pipe-pane defeats the prompt. Other adopters running under CI, cron, `nohup`, or the `/autorun` scheduled-agent path hit the same wall. The stderr message is good, but installing adopters won't see it on first `/wrap-insights` until they trip it. Consider surfacing this in `install.sh` post-install banner or in `commands/wrap.md` itself ("if you run /wrap-insights from a non-interactive context, see…").

- **Linux adopters silently excluded.** Out-of-scope says "Linux support for new scripts (macOS-only)." MonsterFlow's audience isn't documented as macOS-only elsewhere — `os.replace` is cross-platform, the cascade is POSIX, the dashboard is `file://`-loadable everywhere. What specifically is macOS-only? If nothing is, drop the exclusion. If something is (e.g., `~/.claude/projects/` path discovery on Linux Claude Code), name it so Linux adopters know what to fork.

- **Dashboard mental-model shift unaddressed.** Adding a third top-level mode tab ("Persona Insights") changes the dashboard from a single-pane view to a multi-mode tool. Existing dashboard users (who's the population?) get a UI re-org without notice. If the dashboard has any active users beyond Justin, they need a one-line changelog entry. If the population is "Justin only," say so and we can drop this concern.

- **Conflict: privacy strictness vs debuggability.** Counts-only telemetry (Δ4) plus salted finding IDs (Δ3) plus stderr scrubbing (privacy gate 3) means when a real adopter hits a bug ("my row counts look wrong"), they can't share logs with you without the `MONSTERFLOW_DEBUG_PATHS=1` ritual. Consider a `--diagnostic-bundle` flag that produces a redacted-but-shareable artifact deliberately, so support tickets have a path that doesn't require adopters to know about a hidden env var.

- **Persona-metrics-validator subagent owner.** Spec says "invoke `persona-metrics-validator` after first `/wrap-insights` run that produces `persona-rankings.jsonl`." Who is "the invoker"? If this is meant to be automatic, it's not wired. If it's manual, the build instruction needs to say where in the pipeline that invocation lives (post-merge? at /preship? in commands/wrap.md Phase 1c after the compute step?).

- **Conflict: A11 outcome bar vs e12 fresh-install reality.** A11 requires "at least one source row exists" and e12 covers zero-data. But the in-between case — adopter who has run `/spec-review` once, has 1 finding, no `/plan` yet, no `/check` yet — produces a row with `runs_in_window: 1`, `insufficient_sample: true`, all rates rendered "—". Adopter sees a dashboard that looks broken. Banner copy ("No data yet…") doesn't trigger because data does exist; it's just unrenderable. Add a second banner or merge the e12 banner condition to also fire when all rows are insufficient-sample.

## Observations

- **Persona-prompt-author churn signal lost.** Best-effort content-hash reset (A4, e2) is honest about transient pre-edit residue, but if a persona author iterates rapidly during a `/spec` cycle, their score is noise for ~45 invocations. Worth a one-liner in the dashboard tooltip: "score may include pre-edit data for ~45 runs after persona changes."

- **Onboarding stakeholder underserved.** Cascade tier 2 config file is created lazily — adopter must read `docs/specs/token-economics/spec.md` §Project Discovery to know it exists. `install.sh` writing a one-line README at `~/.config/monsterflow/README.md` is mentioned as "out of scope here; opens an issue in onboarding." File the issue in this spec's wake explicitly so it doesn't drop. Onboarding (BACKLOG #2) is named as separate but this is a concrete onboarding-debt item.

- **Multi-machine adopter conflict ack'd but not signposted.** "Cross-machine aggregation is OUT OF SCOPE for v1 — adopters running MonsterFlow on multiple machines see machine-local data on each." Good. Where does this surface to a multi-machine user before they're confused? Suggest: dashboard banner shows the machine hostname and a one-liner ("data is machine-local; other machines maintain separate windows").

- **Notification needs at launch:** existing dashboard users (banner change), persona-PR contributors (new ranking surface), `/wrap-insights` users (new sub-section format), Linux adopters (macOS-only call-out). None of these are currently in a "launch comms" list because there isn't one. For a spec that adds adopter-visible UI surfaces, a 3-bullet "what changes for whom" should sit near the spec's status field.

- **The "never run this window" rendering is a silent contributor-shaming surface.** Dashboard renders deleted personas as strikethrough, "(never run)" personas as a separate row, and bottom-3 rankings name personas explicitly. For a public-release dashboard, all three states tell a story about persona authors. Consider whether "(never run)" should be silenced or surfaced only behind a flag — if a persona is in roster but no one's invoking it, that's roster-design feedback for Justin, not necessarily a public ranking.

## Verdict

**PASS WITH NOTES** — stakeholder coverage is strong on adopter privacy and operator (Justin) ergonomics, but persona authors as a stakeholder class are missing, the motivating Pro-tier user gets no v1 value with no concrete v1.1 timeline, and there's no support runbook for the most likely first adopter question. None block build; all should be addressed in launch comms or a docs follow-up before the public-release sticker goes on.
