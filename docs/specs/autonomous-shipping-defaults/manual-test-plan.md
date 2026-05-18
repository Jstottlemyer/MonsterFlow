# Manual Test Plan — autonomous-shipping-defaults V3

Shipped 2026-05-17 via PR #24 (`0995706`). To validate the runtime behavior beyond the 82/82 deterministic test suite, run these three layers in a **fresh Claude Code session** (this session's context will pollute autoship detection).

## Layer 1 — Helper CLI directly (~30 sec, deterministic)

```bash
cd ~/Projects/MonsterFlow

# Render at /spec exit (HIGH suitability test — this spec itself)
python3 scripts/_goal_autoship_render.py render \
  --spec-path docs/specs/autonomous-shipping-defaults/spec.md \
  --gate spec-exit

# Render option-line for /spec-review
python3 scripts/_goal_autoship_render.py render \
  --spec-path docs/specs/autonomous-shipping-defaults/spec.md \
  --gate spec-review --surface spec-review-option

# Test MEDIUM (security + migration both tagged)
python3 scripts/_goal_autoship_render.py render \
  --spec-path docs/specs/wiki-write-migrate/spec.md \
  --gate spec-exit

# Test log-event halt row with env-var redirect
AUTOSHIP_EVENTS_PATH=/tmp/test-events.jsonl python3 scripts/_goal_autoship_render.py log-event \
  --spec-path docs/specs/autonomous-shipping-defaults/spec.md \
  --gate merge --event-type halt --reason branch-protection-block --stage-at-halt merge
cat /tmp/test-events.jsonl  # see the row
```

Validates: helper exits 0, renders blocks correctly, JSONL schema works, env-var override works.

## Layer 2 — Skill-prompt render (interactive, ~2 min)

In a **fresh Claude Code session**:

```
/spec-review wiki-write-conventions
```

Watch for: Phase 3 approval prompt with **3 options** including `c) Ship autonomously` with correct `/goal` line, slug, and suitability score. Cancel before replying.

Same for `/check wiki-write-conventions` — GO_WITH_FIXES should show option **c)**.

Validates: Wave 2 skill edits actually render in real prompts.

## Layer 3 — End-to-end autoship chain (~5-10 min, load-bearing)

Pick a tiny throwaway spec (or use an existing simple one). In a fresh session:

1. `/spec test-autoship-smoke` (or similar)
2. Complete Q&A. At Phase 4 exit, verify HIGH-suitability block + correct /goal line
3. Paste the /goal line literally as your next message
4. Type `/spec-review test-autoship-smoke`

**Path B works:**
- `[autoship] active goal detected — proceeding autonomously through pipeline` emits
- Skips approval, writes review artifacts
- `[autoship] handing off to blueprint — if you see this without the next gate running, the Skill chain broke ...` emits
- `/blueprint` fires automatically via Skill tool
- Chain continues through /check → /build

**Path B is inert (R1 firing — graceful degradation):**
- `[autoship] active goal detected` fires
- Approval skipped, gate work completes
- `[autoship] handing off` marker visible
- Then nothing — `/blueprint` doesn't fire
- User runs `/blueprint test-autoship-smoke` manually, autoship resumes from that gate

Either outcome is valid for V3 — the visible failure signal is the whole point of D18.

## Quickest "did the static infra ship" check

```bash
# AC14 byte-compare across 4 gate skills
for f in commands/{spec-review,blueprint,check,build}.md; do
  echo "=== $f ==="
  sed -n '/<!-- BEGIN autoship-detection -->/,/<!-- END autoship-detection -->/p' "$f" | wc -l
done
# All should report the same line count

# Halt-surface markers in all 4
grep -l "\[AUTOSHIP-HALT\]" commands/{spec-review,blueprint,check,build}.md

# Chain-invoke Skill calls
grep "Skill(skill=" commands/{spec-review,blueprint,check}.md
```

All clean = static infrastructure solid. Runtime Skill-tool behavior remains the unknown (Layer 3 tests it).

## Where to find the spec/design/check trail

- Spec: `docs/specs/autonomous-shipping-defaults/spec.md` (V3)
- Review iterations: `review.md`
- Design + Codex: `design.md`
- /check verdict + followups: `check.md`, `check-verdict.json`, `followups.jsonl`
- Raw reviewer outputs: `spec-review/raw/`, `plan/raw/`, `check/raw/`
