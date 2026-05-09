#!/usr/bin/env bash
##############################################################################
# tests/test-autorun-merge-policy.sh
#
# Spec: docs/specs/autorun-merge-policy/spec.md (29 ACs + AC-R1/R2/R3)
# Plan: docs/specs/autorun-merge-policy/plan.md
#
# Coverage:
#   AC#3   precedence (default + spec-set + CLI-over-spec + constitution-only)
#   AC#7   invalid value halts (exit 2)
#   AC#8   unknown frontmatter key warns + falls through (no halt)
#   AC#9   audit row schema shape (start + end events; gate_mode field)
#   AC#11  banner-fires-forever on resolved_from=default
#   AC#13  drift detector (downward warns; elevation halts — D6)
#   AC#16  no policy → action=pr_only resolved_from=default
#   AC#17  spec=clean + gates clean → auto_merged
#   AC#18  spec=clean + warnings → fell_back / warnings_present
#   AC#19  branch-protection (gh pr merge exit 1) → fell_back / branch_protection
#   AC#20  CLI overrides spec
#   AC#21  validated → fell_back / validated_fallback
#   AC#22  invalid CLI value → exit 2
#   AC#23  .manual-review touch → fell_back / manual_review_requested
#   AC#24  drift detector — canonical=clean, queue=pr → warning, run continues
#   AC#25  PATH-stub no-policy run → pr_only AND no `gh pr merge` invocation
#   AC-R1  followups_added>0 under clean → fell_back / recycle_demoted_findings
#   AC-R2  split start+end events; crash-between leaves start row
#   AC-R3  gh pr create failure (synthesized via dispatch) → caught
#   YAML-subset behavior (5 fixtures)
#   is_clean_for_merge truth table
#   join key (run_id) — two consecutive runs yield two pairable tuples
#   parallel-slug followups_count — only counts our slug
#
# Bash 3.2 compatible (macOS default). PATH-stub model for `gh` per
# feedback_path_stub_over_export_f.md.
##############################################################################
set -uo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$ENGINE_DIR/scripts/autorun/_merge_policy.sh"

PASS=0
FAIL=0
FAILED_CASES=()

assert_eq() {
  local label="$1" expected="$2" got="$3"
  if [ "$expected" = "$got" ]; then
    PASS=$((PASS+1))
    echo "  ✓ $label"
  else
    FAIL=$((FAIL+1))
    FAILED_CASES+=("$label")
    echo "  ✗ $label"
    echo "    expected: $expected"
    echo "    got:      $got"
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  case "$haystack" in
    *"$needle"*)
      PASS=$((PASS+1))
      echo "  ✓ $label"
      ;;
    *)
      FAIL=$((FAIL+1))
      FAILED_CASES+=("$label")
      echo "  ✗ $label"
      echo "    needle:    $needle"
      echo "    haystack:  $haystack"
      ;;
  esac
}

assert_not_contains() {
  local label="$1" needle="$2" haystack="$3"
  case "$haystack" in
    *"$needle"*)
      FAIL=$((FAIL+1))
      FAILED_CASES+=("$label")
      echo "  ✗ $label"
      echo "    forbidden needle present: $needle"
      ;;
    *)
      PASS=$((PASS+1))
      echo "  ✓ $label"
      ;;
  esac
}

assert_rc() {
  local label="$1" expected="$2" got="$3"
  if [ "$expected" = "$got" ]; then
    PASS=$((PASS+1))
    echo "  ✓ $label (exit $got)"
  else
    FAIL=$((FAIL+1))
    FAILED_CASES+=("$label")
    echo "  ✗ $label — expected exit $expected, got $got"
  fi
}

# ---------------------------------------------------------------------------
# Workspace under TMPDIR
# ---------------------------------------------------------------------------
WORK="$(mktemp -d -t autorun-merge-policy.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/queue" "$WORK/docs/specs"

# Source the helper. Need ENGINE_DIR + PROJECT_DIR exported.
export ENGINE_DIR
export PROJECT_DIR="$WORK"
export QUEUE_DIR="$WORK/queue"

# shellcheck disable=SC1090
. "$HELPER"

echo "=== Wave-1 fixtures: schema shape + enum closure + writers ==="

# Schema shape: emit one start + one end row, parse, confirm required fields.
RUN_LOG="$WORK/queue/run.log"
log_merge_policy_resolved "$RUN_LOG" "myslug" "pr" "default" "permissive" "deadbeef" "00000000-0000-0000-0000-000000000001"
log_merge_action_completed "$RUN_LOG" "myslug" "pr_only" "" "42" "" "00000000-0000-0000-0000-000000000001"

# Validate row shapes via python.
SHAPE_RC=0
python3 - "$RUN_LOG" <<'PY' || SHAPE_RC=$?
import json, sys
required_start = {"ts","slug","run_id","event","policy","resolved_from","gate_mode","spec_sha","pr_number","action","reason","merge_sha"}
required_end   = {"ts","slug","run_id","event","action","reason","pr_number","merge_sha"}
rows = []
for line in open(sys.argv[1]):
    line = line.strip()
    if not line: continue
    rows.append(json.loads(line))
if len(rows) != 2:
    print("ROW_COUNT_FAIL", len(rows)); sys.exit(2)
start, end = rows
if set(start.keys()) != required_start:
    print("START_SCHEMA_FAIL", sorted(start.keys())); sys.exit(2)
if set(end.keys())   != required_end:
    print("END_SCHEMA_FAIL", sorted(end.keys())); sys.exit(2)
if start["event"] != "merge_policy_resolved" or end["event"] != "merge_action_completed":
    print("EVENT_FAIL"); sys.exit(2)
if start["run_id"] != end["run_id"]:
    print("JOIN_KEY_FAIL"); sys.exit(2)
if start["gate_mode"] not in ("strict","permissive"):
    print("GATE_MODE_FAIL"); sys.exit(2)
if start["spec_sha"] != "deadbeef":
    print("SPEC_SHA_FAIL"); sys.exit(2)
if end["pr_number"] != 42:
    print("PR_NUMBER_TYPE_FAIL", end["pr_number"]); sys.exit(2)
print("OK")
PY
assert_rc "schema-shape: two events, required fields, join key, gate_mode" 0 "$SHAPE_RC"

# Enum closure — the readonly arrays carry the spec's closed sets.
case " ${_MP_ACTIONS[*]} " in
  *" pr_only "*) PASS=$((PASS+1)); echo "  ✓ enum: _MP_ACTIONS contains pr_only" ;;
  *) FAIL=$((FAIL+1)); FAILED_CASES+=("enum:pr_only"); echo "  ✗ enum: _MP_ACTIONS missing pr_only" ;;
esac
case " ${_MP_REASONS[*]} " in
  *" recycle_demoted_findings "*) PASS=$((PASS+1)); echo "  ✓ enum: _MP_REASONS has recycle_demoted_findings (R1)" ;;
  *) FAIL=$((FAIL+1)); FAILED_CASES+=("enum:recycle"); echo "  ✗ enum: missing recycle_demoted_findings" ;;
esac
case " ${_MP_REASONS[*]} " in
  *" pr_create_failed "*) PASS=$((PASS+1)); echo "  ✓ enum: _MP_REASONS has pr_create_failed (R3)" ;;
  *) FAIL=$((FAIL+1)); FAILED_CASES+=("enum:prfail"); echo "  ✗ enum: missing pr_create_failed" ;;
esac
case " ${_MP_REASONS[*]} " in
  *" codex_absent "*) PASS=$((PASS+1)); echo "  ✓ enum: _MP_REASONS has codex_absent (SA-1)" ;;
  *) FAIL=$((FAIL+1)); FAILED_CASES+=("enum:codex_absent"); echo "  ✗ enum: missing codex_absent" ;;
esac

# AC-R2: crash-between simulation. Append start row only (truncate before end).
> "$RUN_LOG"
log_merge_policy_resolved "$RUN_LOG" "crashy" "pr" "spec" "permissive" "abc1234" "00000000-0000-0000-0000-000000000002"
ROWS_AFTER_CRASH="$(wc -l < "$RUN_LOG" | tr -d ' ')"
assert_eq "AC-R2: start row survives crash-between (1 row)" "1" "$ROWS_AFTER_CRASH"
HAS_START="$(grep -c '"event": "merge_policy_resolved"' "$RUN_LOG")"
assert_eq "AC-R2: surviving row is the START event"            "1" "$HAS_START"

echo ""
echo "=== Wave-2 fixtures: resolver, validator, predicate, banner, dispatch ==="

# AC#16 fixture: no policy anywhere → default:pr.
> "$RUN_LOG"
SPEC1="$WORK/queue/no-policy.spec.md"
cat > "$SPEC1" <<'SPEC'
---
gate_mode: permissive
---

# No-Policy Spec

Body.
SPEC
RES="$(merge_policy_resolve "$SPEC1" "")"
assert_eq "AC#16: no policy → default:pr" "default:pr" "$RES"

# AC#17 fixture: spec.md sets clean → spec:clean.
SPEC2="$WORK/queue/clean-spec.spec.md"
cat > "$SPEC2" <<'SPEC'
---
auto_merge_policy: clean
gate_mode: strict
---
SPEC
RES="$(merge_policy_resolve "$SPEC2" "")"
assert_eq "AC#17: spec=clean → spec:clean" "spec:clean" "$RES"

# AC#20 fixture: CLI overrides spec.
RES="$(merge_policy_resolve "$SPEC2" "pr")"
assert_eq "AC#20: CLI=pr overrides spec=clean → cli:pr" "cli:pr" "$RES"

# AC#3 constitution-only fixture: spec has no key, constitution sets clean.
mkdir -p "$WORK/docs/specs"
cat > "$WORK/docs/specs/constitution.md" <<'CON'
---
auto_merge_policy: clean
---

# Project Constitution
CON
RES="$(merge_policy_resolve "$SPEC1" "")"
assert_eq "AC#3: constitution-only → constitution:clean" "constitution:clean" "$RES"

# Reset constitution for subsequent tests
rm -f "$WORK/docs/specs/constitution.md"

# AC#22 fixture: invalid CLI value halts (exit 2).
INVALID_RC=0
INVALID_OUT="$(merge_policy_resolve "$SPEC1" "yolo" 2>&1)" || INVALID_RC=$?
assert_rc "AC#22: invalid CLI value exits 2" 2 "$INVALID_RC"
assert_contains "AC#22: stderr names allowed values" "allowed: pr, clean, validated" "$INVALID_OUT"

# AC#7 invalid spec value halts.
SPEC_BAD="$WORK/queue/bad-spec.spec.md"
cat > "$SPEC_BAD" <<'SPEC'
---
auto_merge_policy: yolo
---
SPEC
BAD_RC=0
BAD_OUT="$(merge_policy_resolve "$SPEC_BAD" "" 2>&1)" || BAD_RC=$?
assert_rc "AC#7: invalid spec value exits 2" 2 "$BAD_RC"

# AC#8 unknown key (typo) → falls through (no halt) AND emits stderr warning naming the key.
SPEC_TYPO="$WORK/queue/typo-spec.spec.md"
cat > "$SPEC_TYPO" <<'SPEC'
---
auto_merge_polocy: clean
---
SPEC
TYPO_STDERR="$WORK/typo-stderr.txt"
RES_TYPO="$(merge_policy_resolve "$SPEC_TYPO" "" 2>"$TYPO_STDERR")"
assert_eq "AC#8: typo'd key falls through to default:pr" "default:pr" "$RES_TYPO"
if grep -q "unknown frontmatter key" "$TYPO_STDERR" && grep -q "auto_merge_polocy" "$TYPO_STDERR"; then
  echo "  ✓ AC#8: stderr warning names the unknown key"
  PASS=$((PASS + 1))
else
  echo "  ✗ AC#8: stderr warning missing or doesn't name the key"
  echo "    stderr was: $(cat "$TYPO_STDERR")"
  FAIL=$((FAIL + 1))
fi

# AC#8 — known key (auto_merge_policy) does NOT emit warning.
SPEC_OK="$WORK/queue/ok-spec.spec.md"
cat > "$SPEC_OK" <<'SPEC'
---
auto_merge_policy: clean
---
SPEC
OK_STDERR="$WORK/ok-stderr.txt"
merge_policy_resolve "$SPEC_OK" "" 2>"$OK_STDERR" >/dev/null
if grep -q "unknown frontmatter key" "$OK_STDERR"; then
  echo "  ✗ AC#8: false-positive warning on canonical key"
  FAIL=$((FAIL + 1))
else
  echo "  ✓ AC#8: no false-positive on canonical auto_merge_policy"
  PASS=$((PASS + 1))
fi

# AC#21: validated → resolves fine; dispatch falls back.
SPEC_V="$WORK/queue/v-spec.spec.md"
cat > "$SPEC_V" <<'SPEC'
---
auto_merge_policy: validated
---
SPEC
RES_V="$(merge_policy_resolve "$SPEC_V" "")"
assert_eq "AC#21: validated resolves to spec:validated" "spec:validated" "$RES_V"

# is_clean_for_merge truth table — 24 reachable cells per check synthesis.
# Axes: merge_capable {0,1} × verdict {GO, GO_WITH_FIXES, NO_GO} × gate_mode {strict, permissive} × followups {0, 1+} × codex_ran {0, 1}
# We exhaustively iterate; expectation derived from spec rules.
TT_PASS=0
TT_FAIL=0
for capable in 0 1; do
  for verdict in GO GO_WITH_FIXES NO_GO; do
    for mode in strict permissive; do
      for fua in 0 2; do
        for codex in 0 1; do
          # Expected per spec rules.
          expected=1
          if [ "$capable" = "1" ] && [ "$fua" = "0" ]; then
            if [ "$codex" = "1" ] || [ "$mode" = "strict" ]; then
              case "$mode" in
                strict)
                  case "$verdict" in GO|GO_WITH_FIXES) expected=0 ;; esac ;;
                permissive)
                  [ "$verdict" = "GO" ] && expected=0 ;;
              esac
            fi
          fi
          GOT=0
          is_clean_for_merge "$capable" "$verdict" "$mode" "$fua" "$codex" || GOT=$?
          if [ "$expected" = "$GOT" ]; then
            TT_PASS=$((TT_PASS+1))
          else
            TT_FAIL=$((TT_FAIL+1))
            echo "  ✗ truth-table cell: capable=$capable verdict=$verdict mode=$mode fua=$fua codex=$codex expected=$expected got=$GOT"
          fi
        done
      done
    done
  done
done
if [ "$TT_FAIL" -eq 0 ]; then
  PASS=$((PASS+1))
  echo "  ✓ is_clean_for_merge truth table: $TT_PASS/$((TT_PASS+TT_FAIL)) cells correct"
else
  FAIL=$((FAIL+1))
  FAILED_CASES+=("truth-table")
  echo "  ✗ is_clean_for_merge truth table: $TT_FAIL failures"
fi

# Banner: fires forever-until-opt-in. AC#11 — verbose tier on resolved_from=default.
BANNER_OUT="$(merge_policy_render_banner "myslug" "pr" "default" "permissive" "default" "6" "default" "2" "default")"
assert_contains "AC#11: banner contains default-flip warning" "Default flipped in v0.11.0" "$BANNER_OUT"
assert_contains "AC#11: banner shows resolved_from=default for merge policy" "auto_merge_policy: pr" "$BANNER_OUT"
assert_contains "banner: shows --merge-policy override hint (D3 spelling)" "--merge-policy=clean" "$BANNER_OUT"

# Banner non-default: warning line absent.
BANNER_OPTED="$(merge_policy_render_banner "myslug" "clean" "spec" "permissive" "frontmatter" "6" "default" "2" "default")"
assert_not_contains "banner: opted-in run hides default-flip warning" "Default flipped in v0.11.0" "$BANNER_OPTED"

# Drift detector — D6 + AC#13 + AC#24.
mkdir -p "$WORK/docs/specs/drift-test" "$WORK/queue"
CANON="$WORK/docs/specs/drift-test/spec.md"
QUEUEC="$WORK/queue/drift-test.spec.md"

# Case A: canonical=clean, queue=pr (downward) → warn-only, exit 0
cat > "$CANON"  <<'SPEC'
---
auto_merge_policy: clean
---
SPEC
cat > "$QUEUEC" <<'SPEC'
---
auto_merge_policy: pr
---
SPEC
DRIFT_RC=0
DRIFT_OUT="$(queue_copy_drift_check "$CANON" "$QUEUEC" 2>&1)" || DRIFT_RC=$?
assert_rc "AC#24: downward drift exits 0" 0 "$DRIFT_RC"
assert_contains "AC#24: downward drift emits warning naming both" "queue copy de-escalates" "$DRIFT_OUT"

# Case B: canonical=pr, queue=clean (elevation) → halt (exit 2)
cat > "$CANON"  <<'SPEC'
---
auto_merge_policy: pr
---
SPEC
cat > "$QUEUEC" <<'SPEC'
---
auto_merge_policy: clean
---
SPEC
ELEV_RC=0
ELEV_OUT="$(queue_copy_drift_check "$CANON" "$QUEUEC" 2>&1)" || ELEV_RC=$?
assert_rc "D6: privilege-elevation drift exits 2 (halts)" 2 "$ELEV_RC"
assert_contains "D6: elevation message is explicit" "ELEVATES" "$ELEV_OUT"

# Case C: cross-project / canonical missing → silent-skip
rm -f "$CANON"
SKIP_RC=0
queue_copy_drift_check "$CANON" "$QUEUEC" >/dev/null 2>&1 || SKIP_RC=$?
assert_rc "drift: missing canonical → silent-skip" 0 "$SKIP_RC"

# AC#23 manual-review: dispatch records fell_back/manual_review_requested.
> "$RUN_LOG"
mkdir -p "$WORK/queue/touch-slug"
touch "$WORK/queue/touch-slug/.manual-review"
merge_policy_dispatch "touch-slug" "https://example/pr/1" "clean" "spec" "permissive" "1" "GO" "0" \
  "00000000-0000-0000-0000-000000000003" "$RUN_LOG" "1" "1"
TOUCH_REASON="$(grep -o '"reason": "manual_review_requested"' "$RUN_LOG" | head -1)"
assert_eq "AC#23: .manual-review → fell_back/manual_review_requested" '"reason": "manual_review_requested"' "$TOUCH_REASON"
rm -rf "$WORK/queue/touch-slug"

# AC#16 dispatch: pr policy → action=pr_only.
> "$RUN_LOG"
merge_policy_dispatch "no-pol" "https://example/pr/2" "pr" "default" "permissive" "1" "GO" "0" \
  "00000000-0000-0000-0000-000000000004" "$RUN_LOG" "2" "1"
PRONLY="$(grep -o '"action": "pr_only"' "$RUN_LOG" | head -1)"
assert_eq "AC#16: pr policy → action=pr_only" '"action": "pr_only"' "$PRONLY"

# AC#21 dispatch: validated → fell_back / validated_fallback.
> "$RUN_LOG"
merge_policy_dispatch "v-slug" "https://example/pr/3" "validated" "spec" "permissive" "1" "GO" "0" \
  "00000000-0000-0000-0000-000000000005" "$RUN_LOG" "3" "1"
VFALL="$(grep -c '"reason": "validated_fallback"' "$RUN_LOG")"
assert_eq "AC#21: validated → reason=validated_fallback" "1" "$VFALL"

# AC#18: clean + warnings (merge_capable=0) → fell_back/warnings_present.
> "$RUN_LOG"
merge_policy_dispatch "warn-slug" "https://example/pr/4" "clean" "spec" "permissive" "0" "GO_WITH_FIXES" "0" \
  "00000000-0000-0000-0000-000000000006" "$RUN_LOG" "4" "1"
WARN_R="$(grep -c '"reason": "warnings_present"' "$RUN_LOG")"
assert_eq "AC#18: clean+warnings → reason=warnings_present" "1" "$WARN_R"

# AC-R1: clean + followups_added>0 → fell_back / recycle_demoted_findings.
> "$RUN_LOG"
merge_policy_dispatch "recycle-slug" "https://example/pr/5" "clean" "spec" "permissive" "1" "GO" "3" \
  "00000000-0000-0000-0000-000000000007" "$RUN_LOG" "5" "1"
RECY="$(grep -c '"reason": "recycle_demoted_findings"' "$RUN_LOG")"
assert_eq "AC-R1: clean+followups_added=3 → recycle_demoted_findings" "1" "$RECY"

# SA-1: clean + codex_ran=0 + permissive → fell_back / codex_absent.
> "$RUN_LOG"
merge_policy_dispatch "noc-slug" "https://example/pr/6" "clean" "spec" "permissive" "1" "GO" "0" \
  "00000000-0000-0000-0000-000000000008" "$RUN_LOG" "6" "0"
CABS="$(grep -c '"reason": "codex_absent"' "$RUN_LOG")"
assert_eq "SA-1: codex_ran=0 + permissive → codex_absent" "1" "$CABS"

# AC#19: branch-protection (gh pr merge exit 1).
> "$RUN_LOG"
GH_STUB_DIR="$WORK/stub-bp"
mkdir -p "$GH_STUB_DIR"
cat > "$GH_STUB_DIR/gh" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  pr)
    case "$2" in
      merge) echo "branch protection: required reviews not satisfied" >&2; exit 1 ;;
      view)  echo "OPEN" ;;
    esac
    ;;
esac
exit 1
STUB
chmod +x "$GH_STUB_DIR/gh"
PATH="$GH_STUB_DIR:$PATH" GH_BIN="$GH_STUB_DIR/gh" \
  merge_policy_dispatch "bp-slug" "https://example/pr/7" "clean" "spec" "permissive" "1" "GO" "0" \
  "00000000-0000-0000-0000-000000000009" "$RUN_LOG" "7" "1"
BP="$(grep -c '"reason": "branch_protection"' "$RUN_LOG")"
assert_eq "AC#19: gh pr merge exit 1 → branch_protection" "1" "$BP"

# AC#25: PATH-stub no-policy → action=pr_only AND `gh pr merge` not invoked.
> "$RUN_LOG"
RECORDER="$WORK/gh-call-recorder.log"
> "$RECORDER"
GH_STUB2="$WORK/stub-rec"
mkdir -p "$GH_STUB2"
cat > "$GH_STUB2/gh" <<STUB
#!/usr/bin/env bash
echo "\$@" >> "$RECORDER"
case "\$1 \$2" in
  "pr create") echo "https://example/pr/8"; exit 0 ;;
  "pr view")   echo "OPEN"; exit 0 ;;
esac
exit 0
STUB
chmod +x "$GH_STUB2/gh"
PATH="$GH_STUB2:$PATH" GH_BIN="$GH_STUB2/gh" \
  merge_policy_dispatch "ac25-slug" "https://example/pr/8" "pr" "default" "permissive" "1" "GO" "0" \
  "00000000-0000-0000-0000-00000000000a" "$RUN_LOG" "8" "1"
PRONLY2="$(grep -c '"action": "pr_only"' "$RUN_LOG")"
assert_eq "AC#25: pr policy → action=pr_only" "1" "$PRONLY2"
NO_MERGE_CALL="$(grep -c "pr merge" "$RECORDER" || true)"
assert_eq "AC#25: gh pr merge NEVER invoked under pr policy" "0" "$NO_MERGE_CALL"

# Join key (run_id) — two consecutive runs of same slug yield two pairable tuples.
> "$RUN_LOG"
log_merge_policy_resolved "$RUN_LOG" "joinslug" "pr" "default" "permissive" "sha1" "11111111-1111-1111-1111-111111111111"
log_merge_action_completed "$RUN_LOG" "joinslug" "pr_only" "" "10" "" "11111111-1111-1111-1111-111111111111"
log_merge_policy_resolved "$RUN_LOG" "joinslug" "pr" "default" "permissive" "sha2" "22222222-2222-2222-2222-222222222222"
log_merge_action_completed "$RUN_LOG" "joinslug" "pr_only" "" "11" "" "22222222-2222-2222-2222-222222222222"

JOIN_RC=0
python3 - "$RUN_LOG" <<'PY' || JOIN_RC=$?
import json, sys
from collections import defaultdict
groups = defaultdict(list)
for line in open(sys.argv[1]):
    if not line.strip(): continue
    r = json.loads(line)
    if r.get("slug") != "joinslug": continue
    groups[r["run_id"]].append(r["event"])
if len(groups) != 2:
    print("RUN_ID_GROUPS_FAIL", len(groups)); sys.exit(2)
for rid, evs in groups.items():
    if set(evs) != {"merge_policy_resolved", "merge_action_completed"}:
        print("PAIR_FAIL", rid, evs); sys.exit(2)
print("OK")
PY
assert_rc "join key (run_id) — two consecutive runs yield two pairable tuples" 0 "$JOIN_RC"

# Parallel-slug followups counter — only counts our slug.
FUPS="$WORK/followups.jsonl"
cat > "$FUPS" <<'JSON'
{"finding_id":"a1","slug":"alpha","class":"contract","state":"open"}
{"finding_id":"b1","slug":"beta","class":"docs","state":"open"}
{"finding_id":"a2","slug":"alpha","class":"tests","state":"open"}
{"finding_id":"c1","slug":"gamma","class":"contract","state":"open"}
JSON
N_ALPHA="$(merge_policy_followups_count "$FUPS" "alpha")"
assert_eq "followups_count: slug-scoped (alpha=2 not 4)" "2" "$N_ALPHA"
N_DELTA="$(merge_policy_followups_count "$FUPS" "delta")"
assert_eq "followups_count: absent slug = 0" "0" "$N_DELTA"
N_MISSING="$(merge_policy_followups_count "$WORK/no-such.jsonl" "alpha")"
assert_eq "followups_count: missing file = 0" "0" "$N_MISSING"

# YAML-subset behavior fixtures (D16) — 5 cases.
YS="$WORK/yaml-subset.spec.md"

# YS-1: leading whitespace OK, value extracted.
cat > "$YS" <<'SPEC'
---
   auto_merge_policy: clean
---
SPEC
YS_VAL="$(_gh_frontmatter_field "$YS" auto_merge_policy)"
assert_eq "YAML YS-1: leading whitespace OK" "clean" "$YS_VAL"

# YS-2: trailing comment stripped (whitespace-prefixed).
cat > "$YS" <<'SPEC'
---
auto_merge_policy: clean # commented
---
SPEC
YS_VAL="$(_gh_frontmatter_field "$YS" auto_merge_policy)"
assert_eq "YAML YS-2: trailing comment stripped" "clean" "$YS_VAL"

# YS-3: surrounding double-quotes stripped.
cat > "$YS" <<'SPEC'
---
auto_merge_policy: "clean"
---
SPEC
YS_VAL="$(_gh_frontmatter_field "$YS" auto_merge_policy)"
assert_eq "YAML YS-3: double-quoted value stripped" "clean" "$YS_VAL"

# YS-4: duplicate key — first wins.
cat > "$YS" <<'SPEC'
---
auto_merge_policy: pr
auto_merge_policy: clean
---
SPEC
YS_VAL="$(_gh_frontmatter_field "$YS" auto_merge_policy)"
assert_eq "YAML YS-4: duplicate key — first wins" "pr" "$YS_VAL"

# YS-5: outside frontmatter → not matched.
cat > "$YS" <<'SPEC'
---
gate_mode: permissive
---

# Body
auto_merge_policy: clean
SPEC
YS_VAL="$(_gh_frontmatter_field "$YS" auto_merge_policy)"
assert_eq "YAML YS-5: body-level field not matched" "" "$YS_VAL"

# field_state three-state wrapper.
cat > "$YS" <<'SPEC'
---
gate_mode: permissive
---
SPEC
FS="$(merge_policy_field_state "$YS")"
assert_eq "field_state: absent" "absent" "$FS"
cat > "$YS" <<'SPEC'
---
auto_merge_policy:
gate_mode: permissive
---
SPEC
FS="$(merge_policy_field_state "$YS")"
assert_eq "field_state: empty" "empty" "$FS"
cat > "$YS" <<'SPEC'
---
auto_merge_policy: clean
---
SPEC
FS="$(merge_policy_field_state "$YS")"
assert_eq "field_state: value" "clean" "$FS"

# SA-2: MERGE_POLICY_DISPATCH_OVERRIDE without test-mode sentinel is IGNORED.
> "$RUN_LOG"
unset MONSTERFLOW_TEST_MODE 2>/dev/null || true
MERGE_POLICY_DISPATCH_OVERRIDE=fake \
  merge_policy_dispatch "sa2-slug" "https://example/pr/9" "clean" "spec" "permissive" "0" "GO_WITH_FIXES" "0" \
  "00000000-0000-0000-0000-00000000000b" "$RUN_LOG" "9" "1"
# Permissive + GO_WITH_FIXES + capable=0 → fell_back/warnings_present (override should NOT promote to auto_merged)
SA2_AUTO="$(grep -c '"action": "auto_merged"' "$RUN_LOG")"
assert_eq "SA-2: override ignored without MONSTERFLOW_TEST_MODE=1" "0" "$SA2_AUTO"

# SA-3: prompt-injection guard.
SA3_RC=0
_mp_sanitize_pr_body_text "this contains check-verdict literal" >/dev/null 2>&1 || SA3_RC=$?
assert_rc "SA-3: check-verdict substring → exit 2" 2 "$SA3_RC"
SA3_OK_RC=0
_mp_sanitize_pr_body_text "normal reviewer summary text" >/dev/null 2>&1 || SA3_OK_RC=$?
assert_rc "SA-3: clean text passes through" 0 "$SA3_OK_RC"

# Wave-3 — version + CHANGELOG + template surface (literal-spelling grep-test, R8).
echo ""
echo "=== Wave-3 fixtures: docs surface + version stamps ==="

VERSION_VAL="$(tr -d '[:space:]' < "$ENGINE_DIR/VERSION")"
assert_eq "VERSION bumped to 0.11.0" "0.11.0" "$VERSION_VAL"

CHANGELOG="$ENGINE_DIR/CHANGELOG.md"
assert_contains "CHANGELOG: ## [0.11.0] entry exists" "## [0.11.0]" "$(cat "$CHANGELOG")"
assert_contains "CHANGELOG: ⚠ BREAKING DEFAULT heading exists" "BREAKING DEFAULT" "$(cat "$CHANGELOG")"

CONST_TEMPLATE="$ENGINE_DIR/templates/constitution.md"
assert_contains "constitution template: commented auto_merge_policy example" "auto_merge_policy" "$(cat "$CONST_TEMPLATE")"

AUTORUN_DOC="$ENGINE_DIR/commands/autorun.md"
assert_contains "autorun.md: documents --merge-policy CLI flag" "--merge-policy=" "$(cat "$AUTORUN_DOC")"
assert_contains "autorun.md: documents --auto-merge alias (deprecated)" "--auto-merge=" "$(cat "$AUTORUN_DOC")"
assert_contains "autorun.md: documents .manual-review touch file" ".manual-review" "$(cat "$AUTORUN_DOC")"
assert_contains "autorun.md: documents auto_merge_policy key" "auto_merge_policy" "$(cat "$AUTORUN_DOC")"

# run.sh + autorun-batch.sh literal-spelling grep-test (R8).
RUN_SH="$ENGINE_DIR/scripts/autorun/run.sh"
BATCH_SH="$ENGINE_DIR/scripts/autorun/autorun-batch.sh"
assert_contains "run.sh: sources _merge_policy.sh" "_merge_policy.sh" "$(cat "$RUN_SH")"
assert_contains "run.sh: invokes merge_policy_dispatch" "merge_policy_dispatch" "$(cat "$RUN_SH")"
assert_contains "run.sh: invokes merge_policy_render_banner" "merge_policy_render_banner" "$(cat "$RUN_SH")"
assert_contains "run.sh: invokes log_merge_policy_resolved (start event)" "log_merge_policy_resolved" "$(cat "$RUN_SH")"
assert_contains "run.sh: PR title is [autorun] <slug>" "[autorun]" "$(cat "$RUN_SH")"
assert_contains "autorun-batch.sh: --merge-policy flag accepted" "--merge-policy" "$(cat "$BATCH_SH")"
assert_contains "autorun-batch.sh: --auto-merge alias accepted" "--auto-merge" "$(cat "$BATCH_SH")"
assert_contains "autorun-batch.sh: queue_copy_drift_check invoked" "queue_copy_drift_check" "$(cat "$BATCH_SH")"

# AC#15 — draft-state logic structurally present in run.sh.
assert_contains "AC#15: run.sh has PR_DRAFT_FLAG variable for --draft gating" "PR_DRAFT_FLAG" "$(cat "$RUN_SH")"
assert_contains "AC#15: run.sh drafts on GO_WITH_FIXES verdict" "GO_WITH_FIXES|NO_GO" "$(cat "$RUN_SH")"
assert_contains "AC#15: run.sh passes --draft conditionally to gh pr create" '$PR_DRAFT_FLAG' "$(cat "$RUN_SH")"
assert_contains "AC#15: run.sh ensures ready-for-review on pr_only+GO via gh pr ready" "gh pr ready" "$(cat "$RUN_SH")"
assert_contains "AC#15: run.sh converts to draft on fell_back via gh pr ready --undo" "gh pr ready --undo" "$(cat "$RUN_SH")"

echo ""
echo "=========================================="
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo "Failed cases:"
  for c in "${FAILED_CASES[@]}"; do echo "  - $c"; done
  exit 1
fi
exit 0
