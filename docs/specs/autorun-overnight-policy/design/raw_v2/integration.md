# Integration v2 — Raw

**6 task amendments:**
1. 3.0: wrapper deletes legacy `queue/.autorun.lock` + deprecation log.
2. 3.1: explicit slug-arg validation; remove counters; DELETE run-summary.md writer at run.sh:677-686.
3. 3.0b: STOP-file check between iterations; propagate exit code 3 from run.sh; autorun-batch.sh writes `queue/runs/index.md` aggregate.
4. 2.1: `_policy.sh` source-time `command -v python3 >/dev/null || exit 2`.
5. 3.8: `commands/check.md` Phase 2 = clean append; fence universal.
6. CHANGELOG: verbatim before/after cron snippet; document `current` symlink rotation; STOP file remains global.

**Concrete edits to run.sh:**
- :7 comment drop flock example
- :61 update_stage() add export AUTORUN_CURRENT_STAGE
- :611-646 queue loop REMOVE
- :650-669 index.md writer MOVE to autorun-batch.sh
- :677-686 run-summary.md writer DELETE
- :628 STOP check MOVE to autorun-batch.sh
- :301, :314 STOP checks KEEP

**Open:** autorun-batch.sh aggregate index.md (recommend yes); `current` symlink rotation documented.
