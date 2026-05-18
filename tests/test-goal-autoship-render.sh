#!/bin/bash
##############################################################################
# tests/test-goal-autoship-render.sh
#
# V3 autonomous-shipping-defaults — deterministic shell tests for
# scripts/_goal_autoship_render.py helper + AC9 skill-file anchors.
#
# Coverage:
#   AC1  — Helper exit codes (exit 0 / 1 / 2 per subcommand)
#   AC2  — Suitability mapping (3 fixtures: HIGH, MEDIUM, LOW)
#   AC3  — AC count parser (5 fixtures + checkbox sub-case)
#   AC4  — Render-mode block output (4 anchors)
#   AC5  — Render-mode option-line prefix-match
#   AC6  — JSONL row schema (with and without --no-log)
#   AC7  — log-event halt row schema
#   AC8  — log-event outcome row schema
#   AC9  — Skill-prompt anchor table (10+ greps across gate files)
#   AC13 — .gitignore entries (_smoke-* + events.jsonl anchor)
#   AC14 — Canonical-block byte-compare across 4 gate skill files
#
# AC10 (orchestrator wiring in run-tests.sh) — handled by T9.
# AC11 (full suite green) — verified by T13.
# AC12 (chain-invoke present) — subsumed by AC9 greps.
#
# Environment isolation:
#   AUTOSHIP_EVENTS_PATH — redirect JSONL writes to TMPDIR (D15 contract).
#   Spec slug must be a valid identifier: spec lives at <tmpdir>/<slug>/spec.md
#   mktemp -d -t <prefix>.XXXXXX (GNU mktemp compatible, per memory note).
#
# bash 3.2 compatible: no ${arr[-1]}, no declare -A, no export -f.
##############################################################################
set -euo pipefail

export BASH=/bin/bash

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
HELPER="$REPO_DIR/scripts/_goal_autoship_render.py"

##############################################################################
# Python interpreter selection
##############################################################################
PYTHON3=""
for candidate in python3.11 python3.10 python3; do
    if command -v "$candidate" >/dev/null 2>&1; then
        PYTHON3="$candidate"
        break
    fi
done
if [ -z "$PYTHON3" ]; then
    echo "FATAL: no python3 interpreter found; cannot run test suite." >&2
    exit 1
fi

##############################################################################
# Suite-level counters
##############################################################################
PASS_COUNT=0
FAIL_COUNT=0
FAIL_NAMES=()

pass() {
    PASS_COUNT=$(( PASS_COUNT + 1 ))
    echo "  PASS: $1"
}

fail() {
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
    FAIL_NAMES+=("$1")
    echo "  FAIL: $1${2:+ — $2}"
}

##############################################################################
# Skip helper — used when the helper script hasn't been written yet
##############################################################################
skip_if_missing() {
    local path="$1" label="$2"
    if [ ! -f "$path" ]; then
        echo "  SKIP: $label ($(basename "$path") not yet shipped — parallel wave)"
        return 0   # caller: skip this block
    fi
    return 1       # caller: file present, proceed
}

##############################################################################
# Assertion helpers
##############################################################################
assert_exit() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then return 0; fi
    echo "    ASSERT_EXIT FAIL: $label" >&2
    echo "      expected exit: $expected, actual exit: $actual" >&2
    return 1
}

# grep -F -- needle to prevent needle being parsed as flags
assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    if echo "$haystack" | /usr/bin/grep -qF -- "$needle"; then return 0; fi
    echo "    ASSERT_CONTAINS FAIL: $label" >&2
    echo "      needle:   $needle" >&2
    echo "      haystack: $haystack" >&2
    return 1
}

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then return 0; fi
    echo "    ASSERT_EQ FAIL: $label" >&2
    echo "      expected: $expected" >&2
    echo "      actual:   $actual" >&2
    return 1
}

assert_file_contains() {
    local label="$1" needle="$2" path="$3"
    if /usr/bin/grep -qF -- "$needle" "$path" 2>/dev/null; then return 0; fi
    echo "    ASSERT_FILE_CONTAINS FAIL: $label" >&2
    echo "      needle: $needle" >&2
    echo "      path:   $path" >&2
    return 1
}

assert_prefix() {
    # First non-empty line of text must start with prefix (exact string prefix, not regex)
    local label="$1" prefix="$2" text="$3"
    local first_nonempty
    first_nonempty=$(echo "$text" | /usr/bin/grep -v '^$' | head -1 || true)
    case "$first_nonempty" in
        "$prefix"*) return 0 ;;
    esac
    echo "    ASSERT_PREFIX FAIL: $label" >&2
    echo "      prefix:           $prefix" >&2
    echo "      first_nonempty:   $first_nonempty" >&2
    return 1
}

##############################################################################
# run_helper — invoke the helper; suppress Python tracebacks to /dev/null
# Returns exit code without tripping set -e.
##############################################################################
run_helper() {
    local rc=0
    "$PYTHON3" "$HELPER" "$@" >/dev/null 2>&1 || rc=$?
    echo "$rc"
}

run_helper_stdout() {
    "$PYTHON3" "$HELPER" "$@" 2>/dev/null || true
}

##############################################################################
# Spec factory — spec must live at <tmpdir>/<slug>/spec.md so the parent dir
# name is a valid slug (^[a-z0-9][a-z0-9-]{0,63}$).
#
# Usage:
#   SPEC_DIR=$(make_spec_dir <base-tmpdir> <slug> [extra_frontmatter] [ac_block])
#   Returns the path to the spec.md file.
##############################################################################
make_spec() {
    local basedir="$1"
    local slug="$2"
    local extra_fm="${3:-}"
    local ac_block="${4:-}"
    local specdir="$basedir/$slug"
    mkdir -p "$specdir"
    cat > "$specdir/spec.md" <<SPECEOF
---
tags: [ux, api]
gate_mode: permissive
${extra_fm}
---

# Test Spec

## Summary
A test spec for testing.

${ac_block}
SPECEOF
    echo "$specdir/spec.md"
}

##############################################################################
# Suite-level tmpdir — cleaned at EXIT
##############################################################################
SUITE_TMP=$(mktemp -d -t autoship.XXXXXX)
cleanup() { rm -rf "$SUITE_TMP"; }
trap cleanup EXIT

##############################################################################
# === AC1: Helper exit codes ===
##############################################################################
echo ""
echo "[AC1] Helper exit codes"

if skip_if_missing "$HELPER" "AC1"; then
    :
else
    # AC1-a: render exits 0 on valid input
    _T=$(mktemp -d -t autoship.XXXXXX)
    _spec=$(make_spec "$_T" "test-spec" "" "## Acceptance Criteria
- item one
- item two")
    _rc=$(AUTOSHIP_EVENTS_PATH="$_T/events.jsonl" run_helper render \
        --spec-path "$_spec" --gate spec-exit --no-log)
    if assert_exit "render/valid/exit-0" "0" "$_rc"; then
        pass "AC1-a: render exits 0 on valid input"
    else
        fail "AC1-a: render exits 0 on valid input"
    fi
    rm -rf "$_T"

    # AC1-b: render exits 1 on missing spec.md
    _T=$(mktemp -d -t autoship.XXXXXX)
    _rc=$(run_helper render --spec-path "$_T/nonexistent/spec.md" --gate spec-exit --no-log)
    if assert_exit "render/missing-spec/exit-1" "1" "$_rc"; then
        pass "AC1-b: render exits 1 on missing spec.md"
    else
        fail "AC1-b: render exits 1 on missing spec.md"
    fi
    rm -rf "$_T"

    # AC1-c: render exits 2 on invalid --gate enum
    _T=$(mktemp -d -t autoship.XXXXXX)
    _spec=$(make_spec "$_T" "test-spec")
    _rc=$(run_helper render --spec-path "$_spec" --gate INVALID_GATE --no-log)
    if assert_exit "render/bad-gate/exit-2" "2" "$_rc"; then
        pass "AC1-c: render exits 2 on invalid --gate enum"
    else
        fail "AC1-c: render exits 2 on invalid --gate enum"
    fi
    rm -rf "$_T"

    # AC1-d: render exits 2 when --surface used on a non-render-bearing gate
    _T=$(mktemp -d -t autoship.XXXXXX)
    _spec=$(make_spec "$_T" "test-spec")
    _rc=$(run_helper render --spec-path "$_spec" --gate blueprint --surface spec-exit --no-log)
    if assert_exit "render/surface-on-non-render-gate/exit-2" "2" "$_rc"; then
        pass "AC1-d: render exits 2 when --surface on non-render-bearing gate"
    else
        fail "AC1-d: render exits 2 when --surface on non-render-bearing gate"
    fi
    rm -rf "$_T"

    # AC1-e: log-event exits 0 on valid halt input
    _T=$(mktemp -d -t autoship.XXXXXX)
    _spec=$(make_spec "$_T" "test-spec")
    _rc=$(AUTOSHIP_EVENTS_PATH="$_T/events.jsonl" run_helper log-event \
        --spec-path "$_spec" --gate merge \
        --event-type halt --reason "branch-protection-block" --stage-at-halt merge)
    if assert_exit "log-event/valid-halt/exit-0" "0" "$_rc"; then
        pass "AC1-e: log-event exits 0 on valid halt input"
    else
        fail "AC1-e: log-event exits 0 on valid halt input"
    fi
    rm -rf "$_T"

    # AC1-f: log-event exits 2 when --reason is missing
    _T=$(mktemp -d -t autoship.XXXXXX)
    _spec=$(make_spec "$_T" "test-spec")
    _rc=$(run_helper log-event \
        --spec-path "$_spec" --gate merge --event-type halt)
    if assert_exit "log-event/missing-reason/exit-2" "2" "$_rc"; then
        pass "AC1-f: log-event exits 2 when --reason is missing"
    else
        fail "AC1-f: log-event exits 2 when --reason is missing"
    fi
    rm -rf "$_T"

    # AC1-g: log-event exits 2 on invalid --event-type
    _T=$(mktemp -d -t autoship.XXXXXX)
    _spec=$(make_spec "$_T" "test-spec")
    _rc=$(run_helper log-event \
        --spec-path "$_spec" --gate merge --event-type BADTYPE --reason "x")
    if assert_exit "log-event/bad-event-type/exit-2" "2" "$_rc"; then
        pass "AC1-g: log-event exits 2 on invalid --event-type"
    else
        fail "AC1-g: log-event exits 2 on invalid --event-type"
    fi
    rm -rf "$_T"
fi

##############################################################################
# === AC2: Suitability mapping (3 fixtures) ===
##############################################################################
echo ""
echo "[AC2] Suitability mapping"

if skip_if_missing "$HELPER" "AC2"; then
    :
else
    # AC2-a: tags: [ux] (no security+migration combo, no strict) → HIGH
    _T=$(mktemp -d -t autoship.XXXXXX)
    mkdir -p "$_T/test-spec"
    cat > "$_T/test-spec/spec.md" <<'SPECEOF'
---
tags: [ux]
gate_mode: permissive
---
# Test Spec
SPECEOF
    OUT=$(AUTOSHIP_EVENTS_PATH="$_T/events.jsonl" \
        run_helper_stdout render --spec-path "$_T/test-spec/spec.md" --gate spec-exit --no-log)
    if assert_contains "suitability-high/output" "HIGH" "$OUT"; then
        pass "AC2-a: tags=[ux] → HIGH suitability"
    else
        fail "AC2-a: tags=[ux] → HIGH suitability" "got: $OUT"
    fi
    rm -rf "$_T"

    # AC2-b: tags: [security, migration] → MEDIUM
    _T=$(mktemp -d -t autoship.XXXXXX)
    mkdir -p "$_T/test-spec"
    cat > "$_T/test-spec/spec.md" <<'SPECEOF'
---
tags: [security, migration]
gate_mode: permissive
---
# Test Spec
SPECEOF
    OUT=$(AUTOSHIP_EVENTS_PATH="$_T/events.jsonl" \
        run_helper_stdout render --spec-path "$_T/test-spec/spec.md" --gate spec-exit --no-log)
    if assert_contains "suitability-medium/output" "MEDIUM" "$OUT"; then
        pass "AC2-b: tags=[security, migration] → MEDIUM suitability"
    else
        fail "AC2-b: tags=[security, migration] → MEDIUM suitability" "got: $OUT"
    fi
    rm -rf "$_T"

    # AC2-c: gate_mode: strict → LOW
    _T=$(mktemp -d -t autoship.XXXXXX)
    mkdir -p "$_T/test-spec"
    cat > "$_T/test-spec/spec.md" <<'SPECEOF'
---
tags: [ux, api]
gate_mode: strict
---
# Test Spec
SPECEOF
    OUT=$(AUTOSHIP_EVENTS_PATH="$_T/events.jsonl" \
        run_helper_stdout render --spec-path "$_T/test-spec/spec.md" --gate spec-exit --no-log)
    if assert_contains "suitability-low/output" "LOW" "$OUT"; then
        pass "AC2-c: gate_mode=strict → LOW suitability"
    else
        fail "AC2-c: gate_mode=strict → LOW suitability" "got: $OUT"
    fi
    rm -rf "$_T"
fi

##############################################################################
# === AC3: AC count parser (5 fixtures + checkbox sub-case) ===
##############################################################################
echo ""
echo "[AC3] AC count parser"

if skip_if_missing "$HELPER" "AC3"; then
    :
else
    # AC3-a: 11 numbered items at column 0 → 11
    _T=$(mktemp -d -t autoship.XXXXXX)
    mkdir -p "$_T/test-spec"
    cat > "$_T/test-spec/spec.md" <<'SPECEOF'
---
tags: [ux]
gate_mode: permissive
---
# Test Spec

## Acceptance Criteria
1. first ac
2. second ac
3. third ac
4. fourth ac
5. fifth ac
6. sixth ac
7. seventh ac
8. eighth ac
9. ninth ac
10. tenth ac
11. eleventh ac

## Next Section
Other content.
SPECEOF
    OUT=$(AUTOSHIP_EVENTS_PATH="$_T/events.jsonl" \
        run_helper_stdout render --spec-path "$_T/test-spec/spec.md" --gate spec-exit --no-log)
    if assert_contains "ac-count-numbered/11" "11" "$OUT"; then
        pass "AC3-a: 11 numbered items at column 0 → count 11"
    else
        fail "AC3-a: 11 numbered items at column 0 → count 11" "got: $OUT"
    fi
    rm -rf "$_T"

    # AC3-b: 5 dash bullets at column 0 → 5
    _T=$(mktemp -d -t autoship.XXXXXX)
    mkdir -p "$_T/test-spec"
    cat > "$_T/test-spec/spec.md" <<'SPECEOF'
---
tags: [ux]
gate_mode: permissive
---
# Test Spec

## Acceptance Criteria
- ac one
- ac two
- ac three
- ac four
- ac five
SPECEOF
    OUT=$(AUTOSHIP_EVENTS_PATH="$_T/events.jsonl" \
        run_helper_stdout render --spec-path "$_T/test-spec/spec.md" --gate spec-exit --no-log)
    if assert_contains "ac-count-bullets/5" "5" "$OUT"; then
        pass "AC3-b: 5 dash bullets at column 0 → count 5"
    else
        fail "AC3-b: 5 dash bullets at column 0 → count 5" "got: $OUT"
    fi
    rm -rf "$_T"

    # AC3-c: missing ## Acceptance Criteria section → null (renders as ?)
    _T=$(mktemp -d -t autoship.XXXXXX)
    mkdir -p "$_T/test-spec"
    cat > "$_T/test-spec/spec.md" <<'SPECEOF'
---
tags: [ux]
gate_mode: permissive
---
# Test Spec

## Summary
No AC section here at all.
SPECEOF
    OUT=$(AUTOSHIP_EVENTS_PATH="$_T/events.jsonl" \
        run_helper_stdout render --spec-path "$_T/test-spec/spec.md" --gate spec-exit --no-log)
    if assert_contains "ac-count-missing/question-mark" "?" "$OUT"; then
        pass "AC3-c: missing ## Acceptance Criteria section → null (renders as ?)"
    else
        fail "AC3-c: missing ## Acceptance Criteria section → null (renders as ?)" "got: $OUT"
    fi
    rm -rf "$_T"

    # AC3-d: only nested/indented bullets (4 spaces leading) → null (renders as ?)
    _T=$(mktemp -d -t autoship.XXXXXX)
    mkdir -p "$_T/test-spec"
    cat > "$_T/test-spec/spec.md" <<'SPECEOF'
---
tags: [ux]
gate_mode: permissive
---
# Test Spec

## Acceptance Criteria
    - indented bullet one
    - indented bullet two
    - indented bullet three
    - indented bullet four
SPECEOF
    OUT=$(AUTOSHIP_EVENTS_PATH="$_T/events.jsonl" \
        run_helper_stdout render --spec-path "$_T/test-spec/spec.md" --gate spec-exit --no-log)
    if assert_contains "ac-count-nested/question-mark" "?" "$OUT"; then
        pass "AC3-d: only indented (nested) bullets → null (renders as ?)"
    else
        fail "AC3-d: only indented (nested) bullets → null (renders as ?)" "got: $OUT"
    fi
    rm -rf "$_T"

    # AC3-e: checkbox items (- [ ] and - [x]) count as AC items (per spec §AC3 + ck-ac3-checkbox-fixture)
    _T=$(mktemp -d -t autoship.XXXXXX)
    mkdir -p "$_T/test-spec"
    cat > "$_T/test-spec/spec.md" <<'SPECEOF'
---
tags: [ux]
gate_mode: permissive
---
# Test Spec

## Acceptance Criteria
- [ ] unchecked criterion one
- [x] checked criterion two
- [ ] unchecked criterion three
SPECEOF
    OUT=$(AUTOSHIP_EVENTS_PATH="$_T/events.jsonl" \
        run_helper_stdout render --spec-path "$_T/test-spec/spec.md" --gate spec-exit --no-log)
    if assert_contains "ac-count-checkbox/3" "3" "$OUT"; then
        pass "AC3-e: checkbox items (- [ ] and - [x]) each counted → 3"
    else
        fail "AC3-e: checkbox items (- [ ] and - [x]) each counted → 3" "got: $OUT"
    fi
    rm -rf "$_T"
fi

##############################################################################
# === AC4: Render-mode block output (4 anchors) ===
##############################################################################
echo ""
echo "[AC4] Render-mode block output (4 anchors)"

if skip_if_missing "$HELPER" "AC4"; then
    :
else
    _T=$(mktemp -d -t autoship.XXXXXX)
    mkdir -p "$_T/test-spec"
    cat > "$_T/test-spec/spec.md" <<'SPECEOF'
---
tags: [ux]
gate_mode: permissive
---
# Test Spec

## Acceptance Criteria
- item one
- item two
SPECEOF
    OUT=$(AUTOSHIP_EVENTS_PATH="$_T/events.jsonl" \
        run_helper_stdout render --spec-path "$_T/test-spec/spec.md" --gate spec-exit --no-log)

    if assert_contains "ac4/spec-written-header" "=== Spec Written:" "$OUT"; then
        pass "AC4-a: output contains '=== Spec Written:'"
    else
        fail "AC4-a: output contains '=== Spec Written:'"
    fi

    if assert_contains "ac4/autorun-suitability" "Autorun suitability:" "$OUT"; then
        pass "AC4-b: output contains 'Autorun suitability:'"
    else
        fail "AC4-b: output contains 'Autorun suitability:'"
    fi

    if assert_contains "ac4/ship-autonomously" "Ship autonomously? Copy + paste this exact line:" "$OUT"; then
        pass "AC4-c: output contains 'Ship autonomously? Copy + paste this exact line:'"
    else
        fail "AC4-c: output contains 'Ship autonomously? Copy + paste this exact line:'"
    fi

    if assert_contains "ac4/or-proceed-manually" "Or proceed manually:" "$OUT"; then
        pass "AC4-d: output contains 'Or proceed manually:'"
    else
        fail "AC4-d: output contains 'Or proceed manually:'"
    fi

    rm -rf "$_T"
fi

##############################################################################
# === AC5: Render-mode option-line prefix-match ===
# Tests the spec-review-option surface which emits the **c)** line.
# The first non-empty output line must begin with '- **c)** Ship autonomously'.
##############################################################################
echo ""
echo "[AC5] Render-mode option-line prefix-match"

if skip_if_missing "$HELPER" "AC5"; then
    :
else
    _T=$(mktemp -d -t autoship.XXXXXX)
    mkdir -p "$_T/test-spec"
    cat > "$_T/test-spec/spec.md" <<'SPECEOF'
---
tags: [ux]
gate_mode: permissive
---
# Test Spec

## Acceptance Criteria
- item one
SPECEOF
    OUT=$(AUTOSHIP_EVENTS_PATH="$_T/events.jsonl" \
        run_helper_stdout render \
        --spec-path "$_T/test-spec/spec.md" \
        --gate spec-review \
        --surface spec-review-option \
        --no-log)
    if assert_prefix "ac5/option-c-prefix" "- **c)** Ship autonomously" "$OUT"; then
        pass "AC5: first non-empty output line begins with '- **c)** Ship autonomously'"
    else
        fail "AC5: first non-empty output line begins with '- **c)** Ship autonomously'" "got: $OUT"
    fi
    rm -rf "$_T"
fi

##############################################################################
# === AC6: JSONL row schema (with and without --no-log) ===
##############################################################################
echo ""
echo "[AC6] JSONL row schema"

if skip_if_missing "$HELPER" "AC6"; then
    :
else
    # AC6-a: without --no-log, exactly one row written
    _T=$(mktemp -d -t autoship.XXXXXX)
    mkdir -p "$_T/test-spec"
    cat > "$_T/test-spec/spec.md" <<'SPECEOF'
---
tags: [ux, api]
gate_mode: permissive
---
# Test Spec

## Acceptance Criteria
- item one
- item two
- item three
SPECEOF
    EVENTS_FILE="$_T/events.jsonl"
    AUTOSHIP_EVENTS_PATH="$EVENTS_FILE" \
        "$PYTHON3" "$HELPER" render \
        --spec-path "$_T/test-spec/spec.md" \
        --gate spec-exit \
        > /dev/null 2>&1 || true

    _row_count=0
    if [ -f "$EVENTS_FILE" ]; then
        _row_count=$(wc -l < "$EVENTS_FILE" | tr -d ' ')
    fi
    if assert_eq "ac6/row-count-without-no-log" "1" "$_row_count"; then
        pass "AC6-a: render without --no-log writes exactly 1 JSONL row"
    else
        fail "AC6-a: render without --no-log writes exactly 1 JSONL row" "row_count=$_row_count"
    fi

    # AC6-b: validate required fields via Python json.loads
    if [ -f "$EVENTS_FILE" ]; then
        _VALID=$("$PYTHON3" - "$EVENTS_FILE" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    row = json.loads(f.readline())
required = ['schema_version', 'ts', 'event_type', 'feature', 'gate',
            'predicted_suitability', 'tags', 'ac_count', 'gate_mode']
missing = [k for k in required if k not in row]
if missing:
    print("MISSING:" + ",".join(missing))
    sys.exit(1)
if row['event_type'] != 'render':
    print("BAD event_type:" + row['event_type'])
    sys.exit(1)
if not isinstance(row['ts'], str) or not row['ts'].endswith('Z'):
    print("BAD ts (no Z suffix):" + str(row.get('ts')))
    sys.exit(1)
if not isinstance(row['schema_version'], int):
    print("BAD schema_version type:" + str(type(row['schema_version'])))
    sys.exit(1)
if row['predicted_suitability'] not in ('HIGH', 'MEDIUM', 'LOW'):
    print("BAD predicted_suitability:" + str(row.get('predicted_suitability')))
    sys.exit(1)
if not isinstance(row['tags'], list):
    print("BAD tags type:" + str(type(row['tags'])))
    sys.exit(1)
print("OK")
PYEOF
        )
        if [ "$_VALID" = "OK" ]; then
            pass "AC6-b: JSONL render row has correct schema and ISO-8601-Z ts"
        else
            fail "AC6-b: JSONL render row has correct schema and ISO-8601-Z ts" "$_VALID"
        fi
    else
        fail "AC6-b: JSONL render row has correct schema" "events file not written"
    fi

    # AC6-c: with --no-log, zero rows written (events file absent or empty)
    EVENTS_FILE_NOLOG="$_T/events-nolog.jsonl"
    AUTOSHIP_EVENTS_PATH="$EVENTS_FILE_NOLOG" \
        "$PYTHON3" "$HELPER" render \
        --spec-path "$_T/test-spec/spec.md" \
        --gate spec-exit \
        --no-log \
        > /dev/null 2>&1 || true
    if [ ! -f "$EVENTS_FILE_NOLOG" ]; then
        pass "AC6-c: render with --no-log writes zero JSONL rows (file absent)"
    else
        _nolog_count=$(wc -l < "$EVENTS_FILE_NOLOG" | tr -d ' ')
        if assert_eq "ac6/row-count-with-no-log" "0" "$_nolog_count"; then
            pass "AC6-c: render with --no-log writes zero JSONL rows"
        else
            fail "AC6-c: render with --no-log writes zero JSONL rows" "row_count=$_nolog_count"
        fi
    fi

    rm -rf "$_T"
fi

##############################################################################
# === AC7: log-event halt row schema ===
##############################################################################
echo ""
echo "[AC7] log-event halt row"

if skip_if_missing "$HELPER" "AC7"; then
    :
else
    _T=$(mktemp -d -t autoship.XXXXXX)
    mkdir -p "$_T/test-spec"
    cat > "$_T/test-spec/spec.md" <<'SPECEOF'
---
tags: [ux]
gate_mode: permissive
---
# Test Spec
SPECEOF
    EVENTS_FILE="$_T/halt-events.jsonl"

    # Capture stdout separately — AC7 requires no stdout output
    _stdout=$(AUTOSHIP_EVENTS_PATH="$EVENTS_FILE" \
        run_helper_stdout log-event \
        --spec-path "$_T/test-spec/spec.md" \
        --gate merge \
        --event-type halt \
        --reason "branch-protection-block" \
        --stage-at-halt merge)

    if assert_eq "ac7/no-stdout" "" "$_stdout"; then
        pass "AC7-a: log-event halt produces no stdout"
    else
        fail "AC7-a: log-event halt produces no stdout" "got: $_stdout"
    fi

    if [ -f "$EVENTS_FILE" ]; then
        _VALID=$("$PYTHON3" - "$EVENTS_FILE" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    row = json.loads(f.readline())
checks = [
    ('event_type==halt', row.get('event_type') == 'halt'),
    ('gate==merge', row.get('gate') == 'merge'),
    ('reason==branch-protection-block', row.get('reason') == 'branch-protection-block'),
    ('stage_at_halt==merge', row.get('stage_at_halt') == 'merge'),
    ('ts-Z-suffix', isinstance(row.get('ts',''), str) and row.get('ts','').endswith('Z')),
    ('schema_version', isinstance(row.get('schema_version'), int)),
]
failed = [name for name, ok in checks if not ok]
if failed:
    print("FAILED:" + ",".join(failed))
    sys.exit(1)
print("OK")
PYEOF
        )
        if [ "$_VALID" = "OK" ]; then
            pass "AC7-b: halt row fields correct (event_type, gate, reason, stage_at_halt, ts-Z)"
        else
            fail "AC7-b: halt row fields correct" "$_VALID"
        fi
    else
        fail "AC7-b: halt row fields correct" "events file not written"
    fi

    rm -rf "$_T"
fi

##############################################################################
# === AC8: log-event outcome row schema ===
##############################################################################
echo ""
echo "[AC8] log-event outcome row"

if skip_if_missing "$HELPER" "AC8"; then
    :
else
    _T=$(mktemp -d -t autoship.XXXXXX)
    mkdir -p "$_T/test-spec"
    cat > "$_T/test-spec/spec.md" <<'SPECEOF'
---
tags: [ux]
gate_mode: permissive
---
# Test Spec
SPECEOF
    EVENTS_FILE="$_T/outcome-events.jsonl"

    _stdout=$(AUTOSHIP_EVENTS_PATH="$EVENTS_FILE" \
        run_helper_stdout log-event \
        --spec-path "$_T/test-spec/spec.md" \
        --gate merge \
        --event-type outcome \
        --reason shipped \
        --pr 23)

    if assert_eq "ac8/no-stdout" "" "$_stdout"; then
        pass "AC8-a: log-event outcome produces no stdout"
    else
        fail "AC8-a: log-event outcome produces no stdout" "got: $_stdout"
    fi

    if [ -f "$EVENTS_FILE" ]; then
        _VALID=$("$PYTHON3" - "$EVENTS_FILE" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    row = json.loads(f.readline())
checks = [
    ('event_type==outcome', row.get('event_type') == 'outcome'),
    ('reason==shipped', row.get('reason') == 'shipped'),
    ('pr==23', row.get('pr') == 23),
    ('ts-Z-suffix', isinstance(row.get('ts',''), str) and row.get('ts','').endswith('Z')),
    ('schema_version', isinstance(row.get('schema_version'), int)),
]
failed = [name for name, ok in checks if not ok]
if failed:
    print("FAILED:" + ",".join(failed))
    sys.exit(1)
print("OK")
PYEOF
        )
        if [ "$_VALID" = "OK" ]; then
            pass "AC8-b: outcome row fields correct (event_type=outcome, reason=shipped, pr=23, ts-Z)"
        else
            fail "AC8-b: outcome row fields correct" "$_VALID"
        fi
    else
        fail "AC8-b: outcome row fields correct" "events file not written"
    fi

    rm -rf "$_T"
fi

##############################################################################
# === AC9: Skill-prompt anchor table (exhaustive, all gate files) ===
# NOTE: These greps WILL FAIL until Wave 2 (T3-T8) edits the skill files.
# Expected at T2 completion: AC9 cases FAIL (Wave 2 not yet done).
# Expected after Wave 2 + T13: all AC9 cases PASS.
##############################################################################
echo ""
echo "[AC9] Skill-prompt anchor table"

_grep_anchor() {
    local label="$1" anchor="$2" filepath="$3"
    local abs_path="$REPO_DIR/$filepath"
    if [ ! -f "$abs_path" ]; then
        fail "AC9/$label" "file not found: $abs_path"
        return
    fi
    if /usr/bin/grep -qF -- "$anchor" "$abs_path" 2>/dev/null; then
        pass "AC9/$label"
    else
        fail "AC9/$label" "anchor not found in $filepath"
    fi
}

# commands/spec.md
_grep_anchor "spec.md/autorun-suitability" \
    "Autorun suitability:" \
    "commands/spec.md"

_grep_anchor "spec.md/ship-autonomously" \
    "Ship autonomously? Copy + paste this exact line:" \
    "commands/spec.md"

# commands/spec-review.md
_grep_anchor "spec-review.md/option-c" \
    "- **c)** Ship autonomously" \
    "commands/spec-review.md"

_grep_anchor "spec-review.md/autoship-active" \
    "[autoship] active goal detected" \
    "commands/spec-review.md"

_grep_anchor "spec-review.md/halt-box" \
    "╔══ autoship halt" \
    "commands/spec-review.md"

# ck-autoship-halt-marker: [AUTOSHIP-HALT] must appear in all 4 gate skill files
_grep_anchor "spec-review.md/autoship-halt-marker" \
    "[AUTOSHIP-HALT]" \
    "commands/spec-review.md"

_grep_anchor "spec-review.md/chain-invoke-blueprint" \
    'Skill(skill="blueprint"' \
    "commands/spec-review.md"

# commands/blueprint.md
_grep_anchor "blueprint.md/autoship-active" \
    "[autoship] active goal detected" \
    "commands/blueprint.md"

_grep_anchor "blueprint.md/halt-box" \
    "╔══ autoship halt" \
    "commands/blueprint.md"

_grep_anchor "blueprint.md/autoship-halt-marker" \
    "[AUTOSHIP-HALT]" \
    "commands/blueprint.md"

_grep_anchor "blueprint.md/chain-invoke-check" \
    'Skill(skill="check"' \
    "commands/blueprint.md"

# commands/check.md
_grep_anchor "check.md/option-c" \
    "- **c)** Ship autonomously" \
    "commands/check.md"

_grep_anchor "check.md/autoship-active" \
    "[autoship] active goal detected" \
    "commands/check.md"

_grep_anchor "check.md/halt-box" \
    "╔══ autoship halt" \
    "commands/check.md"

_grep_anchor "check.md/autoship-halt-marker" \
    "[AUTOSHIP-HALT]" \
    "commands/check.md"

_grep_anchor "check.md/chain-invoke-build" \
    'Skill(skill="build"' \
    "commands/check.md"

# ck-t6b-test-coverage: check-verdict.json filename presence in commands/check.md
_grep_anchor "check.md/check-verdict-json" \
    "check-verdict.json" \
    "commands/check.md"

# commands/build.md
_grep_anchor "build.md/autoship-active" \
    "[autoship] active goal detected" \
    "commands/build.md"

_grep_anchor "build.md/halt-box" \
    "╔══ autoship halt" \
    "commands/build.md"

_grep_anchor "build.md/autoship-halt-marker" \
    "[AUTOSHIP-HALT]" \
    "commands/build.md"

# commands/flow-card.txt (per D4 + D20: locked paragraph goes in flow-card.txt, not flow.md)
_grep_anchor "flow-card.txt/autonomous-shipping-section" \
    "## Autonomous Shipping (autoship via /goal)" \
    "commands/flow-card.txt"

##############################################################################
# === AC13: .gitignore entries ===
##############################################################################
echo ""
echo "[AC13] .gitignore entries"

GITIGNORE="$REPO_DIR/.gitignore"
if [ ! -f "$GITIGNORE" ]; then
    fail "AC13/.gitignore-exists" ".gitignore not found at $GITIGNORE"
else
    # AC13-a: _smoke-* pattern
    if /usr/bin/grep -qF -- "_smoke-*" "$GITIGNORE" 2>/dev/null; then
        pass "AC13-a: .gitignore contains _smoke-* pattern"
    else
        fail "AC13-a: .gitignore contains _smoke-* pattern"
    fi

    # AC13-b: JSONL events file — explicit anchor or broader *.jsonl pattern
    if /usr/bin/grep -qE -- \
        "(dashboard/data/autorun-suitability-events\.jsonl|dashboard/data/\*\.jsonl)" \
        "$GITIGNORE" 2>/dev/null; then
        pass "AC13-b: .gitignore contains events.jsonl anchor or broader *.jsonl pattern"
    else
        fail "AC13-b: .gitignore contains events.jsonl anchor or broader *.jsonl pattern"
    fi
fi

##############################################################################
# === AC14: Canonical-block byte-compare across 4 gate skill files ===
# Extracts content between <!-- BEGIN autoship-detection --> and
# <!-- END autoship-detection --> from each gate skill file; asserts all 4
# are byte-identical (enforces D3 splice-sentinel drift detection).
#
# NOTE: Will FAIL until Wave 2 (T4-T7) adds the canonical blocks.
# The sentinel-absent case is a graceful informational FAIL, not a crash.
##############################################################################
echo ""
echo "[AC14] Canonical-block byte-compare (autoship-detection block)"

_extract_detection_block() {
    local filepath="$1"
    local abs_path="$REPO_DIR/$filepath"
    if [ ! -f "$abs_path" ]; then
        echo "__MISSING__"
        return
    fi
    awk \
        '/<!-- BEGIN autoship-detection -->/{found=1; next}
         found && /<!-- END autoship-detection -->/{exit}
         found{print}' \
        "$abs_path"
}

_BLOCK_DIR=$(mktemp -d -t autoship.XXXXXX)
_all_present=true

# Use positional indexing instead of array refs for bash 3.2 compat
_extract_detection_block "commands/spec-review.md" > "$_BLOCK_DIR/block-1.txt"
_extract_detection_block "commands/blueprint.md"   > "$_BLOCK_DIR/block-2.txt"
_extract_detection_block "commands/check.md"       > "$_BLOCK_DIR/block-3.txt"
_extract_detection_block "commands/build.md"       > "$_BLOCK_DIR/block-4.txt"

for _n in 1 2 3 4; do
    if /usr/bin/grep -qF -- "__MISSING__" "$_BLOCK_DIR/block-$_n.txt" 2>/dev/null; then
        _fname=""
        case $_n in
            1) _fname="commands/spec-review.md" ;;
            2) _fname="commands/blueprint.md"   ;;
            3) _fname="commands/check.md"       ;;
            4) _fname="commands/build.md"       ;;
        esac
        fail "AC14/file-present/$_fname" "file not found: $REPO_DIR/$_fname"
        _all_present=false
    fi
done

if [ "$_all_present" = "true" ]; then
    _block1_size=$(wc -c < "$_BLOCK_DIR/block-1.txt" | tr -d ' ')
    if [ "$_block1_size" -le 1 ]; then
        # Block 1 is empty/newline-only — sentinel not yet present (Wave 2 not done)
        fail "AC14/sentinel-present" \
            "autoship-detection sentinel not found in gate files (Wave 2 not yet complete)"
    else
        _mismatch=false
        for _j in 2 3 4; do
            _fname=""
            case $_j in
                2) _fname="commands/blueprint.md" ;;
                3) _fname="commands/check.md"     ;;
                4) _fname="commands/build.md"     ;;
            esac
            if ! cmp -s "$_BLOCK_DIR/block-1.txt" "$_BLOCK_DIR/block-$_j.txt"; then
                fail "AC14/byte-compare/block-1-vs-block-$_j" \
                    "commands/spec-review.md and $_fname autoship-detection blocks differ"
                _mismatch=true
            fi
        done
        if [ "$_mismatch" = "false" ]; then
            pass "AC14: autoship-detection block is byte-identical across all 4 gate skill files"
        fi
    fi
fi
rm -rf "$_BLOCK_DIR"

##############################################################################
# === Summary ===
##############################################################################
echo ""
echo "=== test-goal-autoship-render.sh summary ==="
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
if [ "${#FAIL_NAMES[@]}" -gt 0 ]; then
    echo "Failed cases:"
    for _fn in "${FAIL_NAMES[@]}"; do
        echo "  - $_fn"
    done
fi
[ "$FAIL_COUNT" -eq 0 ]
