## Summary (api persona — full output captured in conversation)

**render-followups.py CLI contract (recommended):**
- `render-followups.py <spec-dir> [--no-lock]`
- Sort: rows grouped by target_phase, then `(class, created_at, finding_id)` within each group
- Filter: `state == "open"` only
- Exit codes: 0 success, 2 malformed JSONL/schema fail, 3 lock contention, 4 missing dir/file
- Empty input → "_No active follow-ups._" body, exit 0
- Lock: `fcntl.flock(LOCK_EX)` via `--no-lock` skip for read-only

**sev:security schema field name (recommended):**
- Add `class: "security"` to findings.jsonl row + `tags: ["sev:security"]` array
- B1 over B2 (severity reuse) and B3 (tags-only); both fields keep their orthogonal semantics
- Schema additive: `class`, `class_inferred`, `source_finding_ids`, `tags`

**CLI flag truth table:** 24-cell table covering frontmatter × CLI × force; pin in `commands/_gate-mode.md` shared include. Identical across the 3 gate commands. `--strict --permissive` and `--strict --force-permissive` exit ambiguous.

**Sidecar naming:** D1 — per-gate sidecars (`spec-review-verdict.json`, `plan-verdict.json`, `check-verdict.json`). Fence label stays `check-verdict` for v1 (label != filename); `stage` field discriminates. Autorun's hardcoded `check-verdict.json` path preserved.

**Error wording:** option E1 — 4-line rejection message naming spec path + override flag + audit-log path.

**Constraints:** `_policy_json.py` validator does NOT support oneOf (single-version-per-file); `additionalProperties: false` is non-negotiable; `severity` enum cannot absorb `security`; `finding_id` regex must be relaxed from `^ck-` to `^(sr|pl|ck)-` for cross-gate compat; bash 3.2 flag parsing avoid `${arr[-1]}`.

**Open Questions:** Q1 fence-label rename to `gate-verdict` deferred to v2; Q2 `/build` reading non-/check sidecars deferred to rightsizing; Q3 `--no-lock` race on .md acceptable; Q4 keep `mode: live | probe`; Q5 `tags[]` open-ended in v1.

**Integration points:** schemas (4 fields findings + 9 fields verdict = 13 total CI-checked), `commands/_gate-mode.md` shared include, autorun finding_id regex relaxation, `/build` reads `check-verdict.json` only.
