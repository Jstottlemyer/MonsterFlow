Verified against `/Users/jstottlemyer/Projects/MonsterFlow`.

**Answers**

1. **Yes, `_gh_frontmatter_field` exists at [scripts/_gate_helpers.sh:49](/Users/jstottlemyer/Projects/MonsterFlow/scripts/_gate_helpers.sh:49).**  
   But the plan must pin its actual YAML subset:
   - only reads between first two `---` delimiter lines at column 1, [lines 55-62](/Users/jstottlemyer/Projects/MonsterFlow/scripts/_gate_helpers.sh:55)
   - matches `field: value` with optional leading spaces, [lines 63-66](/Users/jstottlemyer/Projects/MonsterFlow/scripts/_gate_helpers.sh:63)
   - strips trailing comments only when preceded by whitespace, strips one pair of surrounding quotes, first matching key wins, [lines 67-75](/Users/jstottlemyer/Projects/MonsterFlow/scripts/_gate_helpers.sh:67)
   - not real YAML: duplicate keys resolve to first, block/multiline values are not supported, quoted `#` values can be mangled.

2. **Mostly yes, the cited merge gate exists at [scripts/autorun/run.sh:1069](/Users/jstottlemyer/Projects/MonsterFlow/scripts/autorun/run.sh:1069)-[1102](/Users/jstottlemyer/Projects/MonsterFlow/scripts/autorun/run.sh:1102).**  
   Drift: it is not really “`MERGE_CAPABLE == 1 AND CODEX_HIGH_COUNT == 0 AND RUN_DEGRADED == 0`” as four independent checks. `MERGE_CAPABLE` already embeds `CODEX_HIGH_COUNT == 0`, `RUN_DEGRADED == 0`, and `VERDICT in {GO, GO_WITH_FIXES}` at [1069-1074](/Users/jstottlemyer/Projects/MonsterFlow/scripts/autorun/run.sh:1069). The dispatch path then checks dry-run, PR existence, and `MERGE_CAPABLE`, [1076-1102](/Users/jstottlemyer/Projects/MonsterFlow/scripts/autorun/run.sh:1076). The plan’s new mode-aware predicate should replace/refine the verdict portion, not layer redundant axes unclearly.

3. **Live layout is flat for queued specs: `queue/<slug>.spec.md`; per-slug directories are artifacts.**  
   Confirmed in docs and scripts:
   - batch iterates `queue/*.spec.md`, [scripts/autorun/autorun-batch.sh:8](/Users/jstottlemyer/Projects/MonsterFlow/scripts/autorun/autorun-batch.sh:8), [130-133](/Users/jstottlemyer/Projects/MonsterFlow/scripts/autorun/autorun-batch.sh:130)
   - `/autorun` docs say copy `docs/specs/<slug>/spec.md` to `queue/<slug>.spec.md`, [commands/autorun.md:9](/Users/jstottlemyer/Projects/MonsterFlow/commands/autorun.md:9), [61-64](/Users/jstottlemyer/Projects/MonsterFlow/commands/autorun.md:61)
   - `queue/<slug>/` exists for artifacts, [commands/autorun.md:244](/Users/jstottlemyer/Projects/MonsterFlow/commands/autorun.md:244)-[260](/Users/jstottlemyer/Projects/MonsterFlow/commands/autorun.md:260)
   
   So `queue/<slug>/.manual-review` is viable only after `run.sh` creates `ARTIFACT_DIR` at [scripts/autorun/run.sh:668](/Users/jstottlemyer/Projects/MonsterFlow/scripts/autorun/run.sh:668)-[669](/Users/jstottlemyer/Projects/MonsterFlow/scripts/autorun/run.sh:669). If the user wants to touch it before a first run, the directory may not exist. Safer path: `queue/<slug>.manual-review` or require `mkdir -p queue/<slug>` in docs/tests.

4. **Yes, [scripts/autorun/run.sh:667](/Users/jstottlemyer/Projects/MonsterFlow/scripts/autorun/run.sh:667) sets `SPEC_FILE="$QUEUE_DIR/${SLUG}.spec.md"` and exports it at [670](/Users/jstottlemyer/Projects/MonsterFlow/scripts/autorun/run.sh:670).**  
   The “queue copy is source of truth” assumption is correct.

5. **Other plan-vs-code drift / broken assumptions**
   - `autorun-batch.sh` does **not** populate the queue today. It only iterates existing `queue/*.spec.md`, [scripts/autorun/autorun-batch.sh:126](/Users/jstottlemyer/Projects/MonsterFlow/scripts/autorun/autorun-batch.sh:126)-[141](/Users/jstottlemyer/Projects/MonsterFlow/scripts/autorun/autorun-batch.sh:141). The proposed “drift detector at queue-population time when `autorun-batch.sh` copies the spec” has no live hook. Put the drift check either in docs/manual copy tooling, the `autorun` CLI if it copies elsewhere, or at `run.sh` start.
   - The pseudocode uses `$PROJECT_ROOT`, but live autorun exports `PROJECT_DIR`, not `PROJECT_ROOT`, at [scripts/autorun/run.sh:26](/Users/jstottlemyer/Projects/MonsterFlow/scripts/autorun/run.sh:26)-[27](/Users/jstottlemyer/Projects/MonsterFlow/scripts/autorun/run.sh:27) and [205-206](/Users/jstottlemyer/Projects/MonsterFlow/scripts/autorun/run.sh:205). Literal implementation would fail constitution lookup.
   - `run.sh` currently sources `defaults.sh` and `_policy.sh`, not `_gate_helpers.sh`, [scripts/autorun/run.sh:246](/Users/jstottlemyer/Projects/MonsterFlow/scripts/autorun/run.sh:246)-[252](/Users/jstottlemyer/Projects/MonsterFlow/scripts/autorun/run.sh:252). New `_merge_policy.sh` must source `scripts/_gate_helpers.sh` itself or `run.sh`/`autorun-batch.sh` must do it before calling helpers.
   - PR conventions in the plan do not match live behavior. Current title is `autorun: $SLUG`, [scripts/autorun/run.sh:895](/Users/jstottlemyer/Projects/MonsterFlow/scripts/autorun/run.sh:895)-[898](/Users/jstottlemyer/Projects/MonsterFlow/scripts/autorun/run.sh:898); no draft handling or `autorun` label is present.
   - Codex-absent semantics are nuanced. `CODEX_HIGH_COUNT` starts at `0`, [scripts/autorun/run.sh:491](/Users/jstottlemyer/Projects/MonsterFlow/scripts/autorun/run.sh:491)-[496](/Users/jstottlemyer/Projects/MonsterFlow/scripts/autorun/run.sh:496), but missing/auth-failed Codex runs through `policy_act codex_probe`, [1000-1016](/Users/jstottlemyer/Projects/MonsterFlow/scripts/autorun/run.sh:1000). In supervised mode that can halt; in warn mode it degrades the run. Do not describe it simply as “silent-skip” without mode qualification.
   - Runtime `docs/specs/constitution.md` is absent in this repo; only [templates/constitution.md](/Users/jstottlemyer/Projects/MonsterFlow/templates/constitution.md) exists. The spec’s adopter-project model may be right, but tests need to seed project-local constitution explicitly.
   - The banner wants `gate_mode` / `gate_max_recycles` resolved from `$SPEC_FILE`, but live autorun mode is currently `--mode=overnight|supervised` plus policy axes, not the manual `gate_mode_resolve` flow. If the banner claims `gate_mode: permissive`, implementation must define how that maps to current `AUTORUN_MODE` and `check-verdict.json.mode`.