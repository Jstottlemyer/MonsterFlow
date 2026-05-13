# Wave-Sequencer v2 — Raw

**Sequencing inversions:**

| Task | Current | Proposed | Rationale |
|------|---------|----------|-----------|
| 2.1 | 1.1, 1.5 | + 2.1b | Wraps _policy_json.py; can't precede wrapped |
| 3.0 | 2.1 | + 3.1 | Wrapper drops AFTER run.sh adopts lock |
| 3.0b | 2.1 | + 3.1 | Batch invokes --mode flag that doesn't exist until 3.1 |
| 3.8/3.9 | Wave 3 | **Promote to Wave 2 as 2.4/2.5** | Contract closes before consumers (3.2 consumes) |
| 4.5 | 4.1-4.4 | **DROP** | Use `5.7 depends-on: 4.1-4.4` directly |

**Additional:** 3.10 smoke must cover autorun-batch.sh; fenced format moves to 1.5.

**Open:** `tests/test-policy-json.sh` separate? `scripts/install.sh` cron rewrite in Wave 4?
