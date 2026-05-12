#!/bin/bash
##############################################################################
# tests/test-baseline-drift.sh
#
# Focused SEC-04 coverage for the tags_provenance.baseline drift halt
# implemented in scripts/_resolve_personas.py (Slice 3 W3b, direction
# corrected to recomputed ⊋ recorded). End-to-end through
# scripts/resolve-personas.sh --with-tier against synthetic spec fixtures.
#
# Direction matrix (post Slice 3 final pass):
#   recomputed ⊋ recorded   → HALT exit 6   (post-write shrinking attack)
#   recorded   ⊋ recomputed → WARN exit 0   (author legitimately removed body)
#   recorded == recomputed  → silent exit 0 (clean spec)
#   recorded empty (no provenance block) → exempt exit 0 (grandfathered)
#
# Bash 3.2 / BSD-tools compatible. Wall-clock <5s.
#
# Conventions (mirrors tests/test-resolve-personas.sh):
#   - HOME pinned to a per-run tmpdir so user config never bleeds in.
#   - MONSTERFLOW_REPO_DIR pins the repo (personas/, dashboard/) regardless
#     of cwd; PROJECT_DIR points at the synthetic docs/specs/ fixture tree.
#   - Single mktemp -d root with EXIT trap for cleanup.
#   - One feature slug per fixture; no cross-contamination.
##############################################################################
set -uo pipefail

export BASH=/bin/bash

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
RESOLVER="$REPO_DIR/scripts/resolve-personas.sh"

PASS=0
FAIL=0
FAILED=()

_pass() {
    PASS=$(( PASS + 1 ))
    echo "  PASS — $1"
}
_fail() {
    FAIL=$(( FAIL + 1 ))
    FAILED+=("$1")
    echo "  FAIL — $1" >&2
}

if [ ! -x "$RESOLVER" ] && [ ! -f "$RESOLVER" ]; then
    echo "FATAL: resolver not found at $RESOLVER" >&2
    exit 2
fi

FIXTURE_ROOT="$(mktemp -d -t mf-sec04-XXXXXX)"
FAKE_HOME="$FIXTURE_ROOT/home"
mkdir -p "$FAKE_HOME/.config/monsterflow"

cleanup() {
    [ -n "${FIXTURE_ROOT:-}" ] && [ -d "$FIXTURE_ROOT" ] && rm -rf "$FIXTURE_ROOT"
}
trap cleanup EXIT

# Shared env for every invocation. HOME isolation prevents the user's real
# ~/.config/monsterflow/config.json from steering budget/pins; MONSTERFLOW_REPO_DIR
# anchors persona discovery to the real repo so registry lookup works;
# PROJECT_DIR is overridden per-case to the synthetic docs/specs tree.
export HOME="$FAKE_HOME"
export MONSTERFLOW_REPO_DIR="$REPO_DIR"
export MONSTERFLOW_CODEX_AUTH=0
unset MONSTERFLOW_DISABLE_BUDGET

run_resolver() {
    # $1 = feature slug, $2 = PROJECT_DIR override
    # Captures stderr to a variable via process substitution-free idiom
    # (bash 3.2 safe). Echoes "<rc>|<stderr-base64>" — caller decodes.
    local feature="$1" pdir="$2"
    local err_file="$FIXTURE_ROOT/.err.$$"
    local rc=0
    PROJECT_DIR="$pdir" bash "$RESOLVER" check --feature "$feature" --with-tier \
        >/dev/null 2>"$err_file" || rc=$?
    printf '%s\n' "$rc"
    cat "$err_file"
    rm -f "$err_file"
}

# Simpler: just write stderr to a known path per case.
ERR_FILE="$FIXTURE_ROOT/last.err"

invoke() {
    # $1 = feature slug
    # PROJECT_DIR is always $FIXTURE_ROOT (all fixtures under it).
    local rc=0
    PROJECT_DIR="$FIXTURE_ROOT" bash "$RESOLVER" check --feature "$1" --with-tier \
        >/dev/null 2>"$ERR_FILE" || rc=$?
    echo "$rc"
}

echo "=== SEC-04 baseline drift direction-matrix tests ==="

# ---------------------------------------------------------------------------
# Case 1 — HALT: recomputed ⊋ recorded (post-write shrinking attack)
#   Body has BOTH oauth (security) AND jsonl (data); recorded baseline lists
#   only [security]. Recomputed = {security, data}; recorded = {security}.
#   {security, data} is NOT a subset of {security} → exit 6.
# ---------------------------------------------------------------------------
echo "Case 1: HALT — recomputed superset of recorded (shrinking attack)"
mkdir -p "$FIXTURE_ROOT/docs/specs/sec04-halt"
cat > "$FIXTURE_ROOT/docs/specs/sec04-halt/spec.md" <<'EOF'
---
name: sec04-halt
tags: [security, data]
tags_provenance:
  baseline: [security]
---
# Body has BOTH security AND data keywords
We support oauth tokens and store events in a jsonl database schema.
EOF
rc=$(invoke sec04-halt)
err_content=$(cat "$ERR_FILE")

if [ "$rc" = "6" ]; then
    _pass "Case 1: exit 6 on shrinking-attack drift"
else
    _fail "Case 1: expected exit 6 (SEC-04 halt), got $rc"
    echo "    --- stderr ---" >&2
    echo "$err_content" >&2
fi

if printf '%s' "$err_content" | grep -q "SEC-04"; then
    _pass "Case 1: stderr contains canonical SEC-04 token"
else
    _fail "Case 1: stderr missing SEC-04 canonical message"
fi

if printf '%s' "$err_content" | grep -q "refusing to dispatch"; then
    _pass "Case 1: stderr contains 'refusing to dispatch'"
else
    _fail "Case 1: stderr missing 'refusing to dispatch'"
fi

# Case 6 — Direction string in error message must show recorded= and
# recomputed= sets. Piggy-backs on Case 1's captured stderr per task spec.
if printf '%s' "$err_content" | grep -qE "recorded=\[.*\]; recomputed=\[.*\]"; then
    _pass "Case 6: stderr exposes recorded=[…]; recomputed=[…] direction"
else
    _fail "Case 6: SEC-04 error must show recorded= and recomputed= sets"
fi

# ---------------------------------------------------------------------------
# Case 2 — WARN: recorded ⊋ recomputed (author removed content)
#   Body has only oauth (security). Recorded baseline lists [security, data].
#   Recomputed = {security}; recorded = {security, data}. recomputed IS a
#   subset of recorded → SEC-04 does NOT fire. recorded != recomputed → D8
#   warn-and-proceed.
# ---------------------------------------------------------------------------
echo "Case 2: WARN — recorded superset of recomputed (D8 mid-pipeline edit)"
mkdir -p "$FIXTURE_ROOT/docs/specs/sec04-warn"
cat > "$FIXTURE_ROOT/docs/specs/sec04-warn/spec.md" <<'EOF'
---
name: sec04-warn
tags: [security, data]
tags_provenance:
  baseline: [security, data]
---
# Body has only security content
We support oauth tokens.
EOF
rc=$(invoke sec04-warn)
err_content=$(cat "$ERR_FILE")

if [ "$rc" = "0" ]; then
    _pass "Case 2: exit 0 on warn-and-proceed (author removed content)"
else
    _fail "Case 2: expected exit 0 (warn-and-proceed), got $rc"
    echo "    --- stderr ---" >&2
    echo "$err_content" >&2
fi

if printf '%s' "$err_content" | grep -q "stale-tags"; then
    _pass "Case 2: stderr contains [stale-tags] WARNING"
else
    _fail "Case 2: stderr missing [stale-tags] WARNING"
fi

# Negative: case 2 must NOT carry the SEC-04 halt token (would mean direction
# was reversed). Belt-and-suspenders given how easy it is to flip the test.
if printf '%s' "$err_content" | grep -q "SEC-04"; then
    _fail "Case 2: stderr should NOT contain SEC-04 (this is the warn path)"
else
    _pass "Case 2: stderr correctly free of SEC-04 token"
fi

# ---------------------------------------------------------------------------
# Case 3 — EQUALITY: recorded == recomputed (clean spec)
#   Body has only oauth (security). Recorded = recomputed = {security}.
#   No SEC-04 halt, no stale-tags warn.
# ---------------------------------------------------------------------------
echo "Case 3: EQUALITY — recorded matches recomputed (clean)"
mkdir -p "$FIXTURE_ROOT/docs/specs/sec04-eq"
cat > "$FIXTURE_ROOT/docs/specs/sec04-eq/spec.md" <<'EOF'
---
name: sec04-eq
tags: [security]
tags_provenance:
  baseline: [security]
---
# Body
oauth tokens only.
EOF
rc=$(invoke sec04-eq)
err_content=$(cat "$ERR_FILE")

if [ "$rc" = "0" ]; then
    _pass "Case 3: exit 0 on equality"
else
    _fail "Case 3: equality case should exit 0, got $rc"
    echo "    --- stderr ---" >&2
    echo "$err_content" >&2
fi

if printf '%s' "$err_content" | grep -qE "SEC-04|stale-tags"; then
    _fail "Case 3: equality should produce no SEC-04/stale-tags noise"
    echo "    --- stderr ---" >&2
    echo "$err_content" >&2
else
    _pass "Case 3: stderr free of SEC-04 and stale-tags chatter"
fi

# ---------------------------------------------------------------------------
# Case 4 — GRANDFATHERED: no tags_provenance block, body has keywords
#   Pre-feature specs (or any spec authored before SEC-04 enforcement) have
#   no tags_provenance.baseline at all. Per Slice 3 P1 fix, recorded_set is
#   empty → falsy → SEC-04 block skipped → exit 0.
# ---------------------------------------------------------------------------
echo "Case 4: GRANDFATHERED — no tags_provenance block (exempt)"
mkdir -p "$FIXTURE_ROOT/docs/specs/sec04-grand"
cat > "$FIXTURE_ROOT/docs/specs/sec04-grand/spec.md" <<'EOF'
---
name: sec04-grand
---
# Pre-feature spec — no tags_provenance
oauth and jsonl content here.
EOF
rc=$(invoke sec04-grand)
err_content=$(cat "$ERR_FILE")

if [ "$rc" = "0" ]; then
    _pass "Case 4: grandfathered spec exits 0 (recorded empty is exempt)"
else
    _fail "Case 4: grandfathered spec should pass, got $rc"
    echo "    --- stderr ---" >&2
    echo "$err_content" >&2
fi

# ---------------------------------------------------------------------------
# Case 5 — EXPLICIT EMPTY BASELINE: tags_provenance.baseline: []
#   TODO(soft-spot): Author EXPLICITLY records an empty baseline while body
#   contains keywords. Per Slice 3 P1 fix, `set([])` is falsy so SEC-04 is
#   skipped — same path as Case 4. This MIGHT be an attack vector in future
#   (a malicious author could ship `baseline: []` to claim no security
#   surface while body has oauth content), but currently it's treated as
#   grandfathered for compat. Test pins current behavior; flip if policy
#   tightens.
# ---------------------------------------------------------------------------
echo "Case 5: EXPLICIT-EMPTY baseline — current behavior is exempt (soft-spot)"
mkdir -p "$FIXTURE_ROOT/docs/specs/sec04-empty"
cat > "$FIXTURE_ROOT/docs/specs/sec04-empty/spec.md" <<'EOF'
---
name: sec04-empty
tags: [security]
tags_provenance:
  baseline: []
---
# Body
oauth content here.
EOF
rc=$(invoke sec04-empty)
err_content=$(cat "$ERR_FILE")

if [ "$rc" = "0" ]; then
    _pass "Case 5: explicit-empty baseline currently exempt (per Slice 3 P1 fix)"
else
    _fail "Case 5: explicit empty baseline should exit 0 (current behavior), got $rc"
    echo "    --- stderr ---" >&2
    echo "$err_content" >&2
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    echo "Failed cases:" >&2
    for c in "${FAILED[@]}"; do
        echo "  - $c" >&2
    done
    exit 1
fi
exit 0
