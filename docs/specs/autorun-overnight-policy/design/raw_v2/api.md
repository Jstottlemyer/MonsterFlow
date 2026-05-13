# API v2 — Raw

**Key gaps:** _policy_json.py CLI shape unpinned in 1.5; fenced JSON multi-fence vulnerability; STAGE 11-enum leak; `if ! policy_act` documented once; autorun-batch.sh API unspecified.

**Recommendations:** pin `_policy_json.py` CLI in 1.5 (subcommands: read/append-warning/append-block/validate/finding-id/escape/extract-fence/render-recovery-hint); fenced state-machine algorithm in D33 with last-fence-wins + duplicate-fence-rejection; repeat `if ! policy_act` literal in 3.2/3.3/3.4; pin autorun-batch.sh flags (pass-through --mode, STOP between iters, exit code aggregate, zero-match → exit 0).

**Open:** stdin vs path argv for `_policy_json.py`? `complete` vs `pr` overlap? `prompt_version` emitted by post-processor not LLM.
