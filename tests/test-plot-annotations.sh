#!/usr/bin/env bash
##############################################################################
# tests/test-plot-annotations.sh
#
# Functional tests for scripts/_plot_annotations.py (Plot Layer Task 2).
# Spec: docs/specs/plot-document/spec.md
# Plan: docs/specs/plot-document/plan.md
#
# Covers: inject-stale (3 cases), remove-stale (1), inject-draft (1),
#         remove-draft (1), dual-annotation D6 (1), status (1),
#         extract-links (2), Tier 1 diff-scope intersection (1).
#
# Bash 3.2 compatible. No `${arr[-1]}`. No process-substitution shenanigans.
##############################################################################
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$REPO_ROOT/scripts/_plot_annotations.py"
TMPROOT="$(mktemp -d -t "plot-annotations-test.XXXXXX")"
trap 'rm -rf "$TMPROOT"' EXIT

PASS=0
FAIL=0
FAILED=""

ok()    { PASS=$(( PASS + 1 )); printf "  PASS %s\n" "$1"; }
fail()  { FAIL=$(( FAIL + 1 )); FAILED="$FAILED $1"; printf "  FAIL %s -- %s\n" "$1" "$2"; }
case_() { printf "\n--- %s\n" "$1"; }

assert_contains() {
  local label="$1" pattern="$2" file="$3"
  if grep -q "$pattern" "$file"; then
    ok "$label"
  else
    fail "$label" "pattern not found: $pattern"
  fi
}

assert_not_contains() {
  local label="$1" pattern="$2" file="$3"
  if ! grep -q "$pattern" "$file"; then
    ok "$label"
  else
    fail "$label" "pattern should NOT be present: $pattern"
  fi
}

# ---------------------------------------------------------------------------
# 1. inject-stale: inject into clean section
# ---------------------------------------------------------------------------
case_ "1. inject-stale into clean section"
T1="$TMPROOT/case1"
mkdir -p "$T1"
cat > "$T1/doc.md" <<'EOF'
# Plot Document

## Architecture

This section describes the architecture.

## Testing

This section describes testing.
EOF

python3 "$HELPER" inject-stale \
    --file "$T1/doc.md" \
    --section "Architecture" \
    --reason "schema field renamed in PR#42" \
    --date "2026-05-10" \
    >"$T1/stdout" 2>"$T1/stderr"
RC=$?
if [ "$RC" -eq 0 ]; then
    ok "exit code 0"
else
    fail "exit code" "expected 0, got $RC; stderr=$(cat "$T1/stderr")"
fi
assert_contains "STALE callout present" '\[!STALE\]' "$T1/doc.md"
assert_contains "reason (1) present" '(1) schema field renamed in PR#42' "$T1/doc.md"
assert_contains "detected date present" '(detected 2026-05-10)' "$T1/doc.md"
# Verify the other section is untouched
assert_contains "Testing section intact" 'This section describes testing' "$T1/doc.md"

# ---------------------------------------------------------------------------
# 2. inject-stale: inject with existing reasons -> (2) appended
# ---------------------------------------------------------------------------
case_ "2. inject-stale with existing reason -> (2) appended"
T2="$TMPROOT/case2"
mkdir -p "$T2"
cat > "$T2/doc.md" <<'EOF'
# Plot Document

## Architecture

> [!STALE] (1) schema field renamed in PR#42 (detected 2026-05-01).

This section describes the architecture.

## Testing

This section describes testing.
EOF

python3 "$HELPER" inject-stale \
    --file "$T2/doc.md" \
    --section "Architecture" \
    --reason "endpoint moved to v2 namespace" \
    --date "2026-05-10" \
    >"$T2/stdout" 2>"$T2/stderr"
RC=$?
if [ "$RC" -eq 0 ]; then
    ok "exit code 0"
else
    fail "exit code" "expected 0, got $RC"
fi
assert_contains "reason (1) still present" '(1) schema field renamed in PR#42' "$T2/doc.md"
assert_contains "reason (2) appended" '(2) endpoint moved to v2 namespace' "$T2/doc.md"
assert_contains "new detected date" '(detected 2026-05-10)' "$T2/doc.md"

# ---------------------------------------------------------------------------
# 3. inject-stale: 3-reason cap with renumber (4th drops oldest)
# ---------------------------------------------------------------------------
case_ "3. inject-stale: 4th reason drops oldest, renumbers to (1)(2)(3)"
T3="$TMPROOT/case3"
mkdir -p "$T3"
cat > "$T3/doc.md" <<'EOF'
# Plot Document

## Architecture

> [!STALE] (1) reason-A (detected 2026-05-01).
> (2) reason-B (detected 2026-05-02).
> (3) reason-C (detected 2026-05-03).

This section describes the architecture.
EOF

python3 "$HELPER" inject-stale \
    --file "$T3/doc.md" \
    --section "Architecture" \
    --reason "reason-D" \
    --date "2026-05-10" \
    >"$T3/stdout" 2>"$T3/stderr"
RC=$?
if [ "$RC" -eq 0 ]; then
    ok "exit code 0"
else
    fail "exit code" "expected 0, got $RC"
fi
# reason-A (the oldest) should be gone
assert_not_contains "oldest reason-A dropped" 'reason-A' "$T3/doc.md"
# Remaining 3 should be renumbered (1), (2), (3)
assert_contains "reason-B renumbered to (1)" '(1) reason-B' "$T3/doc.md"
assert_contains "reason-C renumbered to (2)" '(2) reason-C' "$T3/doc.md"
assert_contains "reason-D is now (3)" '(3) reason-D' "$T3/doc.md"
assert_contains "new date on reason-D" '(detected 2026-05-10)' "$T3/doc.md"

# ---------------------------------------------------------------------------
# 4. remove-stale: remove stale callout
# ---------------------------------------------------------------------------
case_ "4. remove-stale removes entire STALE callout"
T4="$TMPROOT/case4"
mkdir -p "$T4"
cat > "$T4/doc.md" <<'EOF'
# Plot Document

## Architecture

> [!STALE] (1) schema field renamed in PR#42 (detected 2026-05-01).
> (2) endpoint moved to v2 namespace (detected 2026-05-05).

This section describes the architecture.

## Testing

This section describes testing.
EOF

python3 "$HELPER" remove-stale \
    --file "$T4/doc.md" \
    --section "Architecture" \
    >"$T4/stdout" 2>"$T4/stderr"
RC=$?
if [ "$RC" -eq 0 ]; then
    ok "exit code 0"
else
    fail "exit code" "expected 0, got $RC"
fi
assert_not_contains "no STALE callout remains" '\[!STALE\]' "$T4/doc.md"
assert_not_contains "no reason (1) remains" '(1) schema field' "$T4/doc.md"
assert_not_contains "no reason (2) remains" '(2) endpoint moved' "$T4/doc.md"
# Content below the callout should still be there
assert_contains "section content intact" 'This section describes the architecture' "$T4/doc.md"
assert_contains "Testing section intact" 'This section describes testing' "$T4/doc.md"

# ---------------------------------------------------------------------------
# 5. inject-draft: inject into clean section
# ---------------------------------------------------------------------------
case_ "5. inject-draft into clean section"
T5="$TMPROOT/case5"
mkdir -p "$T5"
cat > "$T5/doc.md" <<'EOF'
# Plot Document

## Architecture

This section describes the architecture.

## Testing

This section describes testing.
EOF

python3 "$HELPER" inject-draft \
    --file "$T5/doc.md" \
    --section "Architecture" \
    --date "2026-05-10" \
    >"$T5/stdout" 2>"$T5/stderr"
RC=$?
if [ "$RC" -eq 0 ]; then
    ok "exit code 0"
else
    fail "exit code" "expected 0, got $RC"
fi
assert_contains "DRAFT callout present" '\[!DRAFT\]' "$T5/doc.md"
assert_contains "draft date present" '(drafted 2026-05-10)' "$T5/doc.md"
assert_contains "not yet human-reviewed text" 'not yet human-reviewed' "$T5/doc.md"

# ---------------------------------------------------------------------------
# 6. remove-draft: remove draft callout
# ---------------------------------------------------------------------------
case_ "6. remove-draft removes entire DRAFT callout"
T6="$TMPROOT/case6"
mkdir -p "$T6"
cat > "$T6/doc.md" <<'EOF'
# Plot Document

## Architecture

> [!DRAFT] Agent-drafted content, not yet human-reviewed. (drafted 2026-05-01)

This section describes the architecture.

## Testing

This section describes testing.
EOF

python3 "$HELPER" remove-draft \
    --file "$T6/doc.md" \
    --section "Architecture" \
    >"$T6/stdout" 2>"$T6/stderr"
RC=$?
if [ "$RC" -eq 0 ]; then
    ok "exit code 0"
else
    fail "exit code" "expected 0, got $RC"
fi
assert_not_contains "no DRAFT callout remains" '\[!DRAFT\]' "$T6/doc.md"
# Content below the callout should still be there
assert_contains "section content intact" 'This section describes the architecture' "$T6/doc.md"
assert_contains "Testing section intact" 'This section describes testing' "$T6/doc.md"

# ---------------------------------------------------------------------------
# 7. Dual-annotation D6: inject stale into section with existing DRAFT
# ---------------------------------------------------------------------------
case_ "7. D6: inject-stale into section with existing DRAFT -> both present, stale before draft"
T7="$TMPROOT/case7"
mkdir -p "$T7"
cat > "$T7/doc.md" <<'EOF'
# Plot Document

## Architecture

> [!DRAFT] Agent-drafted content, not yet human-reviewed. (drafted 2026-05-01)

This section describes the architecture.

## Testing

This section describes testing.
EOF

python3 "$HELPER" inject-stale \
    --file "$T7/doc.md" \
    --section "Architecture" \
    --reason "API contract changed" \
    --date "2026-05-10" \
    >"$T7/stdout" 2>"$T7/stderr"
RC=$?
if [ "$RC" -eq 0 ]; then
    ok "exit code 0"
else
    fail "exit code" "expected 0, got $RC"
fi
assert_contains "STALE callout present" '\[!STALE\]' "$T7/doc.md"
assert_contains "DRAFT callout still present" '\[!DRAFT\]' "$T7/doc.md"
# Verify ordering: STALE must appear before DRAFT
STALE_LINE="$(grep -n '\[!STALE\]' "$T7/doc.md" | head -1 | cut -d: -f1)"
DRAFT_LINE="$(grep -n '\[!DRAFT\]' "$T7/doc.md" | head -1 | cut -d: -f1)"
if [ -n "$STALE_LINE" ] && [ -n "$DRAFT_LINE" ] && [ "$STALE_LINE" -lt "$DRAFT_LINE" ]; then
    ok "STALE (line $STALE_LINE) appears before DRAFT (line $DRAFT_LINE)"
else
    fail "D6 ordering" "STALE at line ${STALE_LINE:-?}, DRAFT at line ${DRAFT_LINE:-?} — STALE should come first"
fi

# ---------------------------------------------------------------------------
# 8. status: mixed sections -> correct counts
# ---------------------------------------------------------------------------
case_ "8. status with mixed sections"
T8="$TMPROOT/case8"
mkdir -p "$T8"
cat > "$T8/doc.md" <<'EOF'
# Plot Document

## Stale Only

> [!STALE] (1) something changed (detected 2026-05-01).

Content for stale-only section.

## Draft Only

> [!DRAFT] Agent-drafted content, not yet human-reviewed. (drafted 2026-05-01)

Content for draft-only section.

## Clean Section

This section has no annotations.

## Both Annotations

> [!STALE] (1) outdated info (detected 2026-05-02).

> [!DRAFT] Agent-drafted content, not yet human-reviewed. (drafted 2026-05-03)

Content with both annotations.
EOF

STATUS_OUT="$(python3 "$HELPER" status --file "$T8/doc.md" 2>"$T8/stderr")"
RC=$?
if [ "$RC" -eq 0 ]; then
    ok "exit code 0"
else
    fail "exit code" "expected 0, got $RC"
fi
# total=5 (Plot Document, Stale Only, Draft Only, Clean Section, Both Annotations)
TOTAL="$(echo "$STATUS_OUT" | grep '^total:' | awk '{print $2}')"
STALE="$(echo "$STATUS_OUT" | grep '^stale:' | awk '{print $2}')"
DRAFT="$(echo "$STATUS_OUT" | grep '^draft:' | awk '{print $2}')"
CLEAN="$(echo "$STATUS_OUT" | grep '^clean:' | awk '{print $2}')"
if [ "$TOTAL" = "5" ]; then
    ok "total=5 (including top-level heading)"
else
    fail "total count" "expected 5, got $TOTAL (output: $STATUS_OUT)"
fi
if [ "$STALE" = "2" ]; then
    ok "stale=2 (Stale Only + Both)"
else
    fail "stale count" "expected 2, got $STALE"
fi
if [ "$DRAFT" = "2" ]; then
    ok "draft=2 (Draft Only + Both)"
else
    fail "draft count" "expected 2, got $DRAFT"
fi
if [ "$CLEAN" = "2" ]; then
    ok "clean=2 (Plot Document + Clean Section)"
else
    fail "clean count" "expected 2, got $CLEAN"
fi

# ---------------------------------------------------------------------------
# 9. extract-links: chapter with links to existing files
# ---------------------------------------------------------------------------
case_ "9. extract-links from chapter with existing file targets"
T9="$TMPROOT/case9"
mkdir -p "$T9/plot/chapters" "$T9/src/payments"
echo "// controller" > "$T9/src/payments/controller.ts"
echo "// schema" > "$T9/src/payments/schema.ts"

cat > "$T9/plot/chapters/ch-payments.md" <<'EOF'
# Payments Chapter

This chapter covers the payment system.

See the [controller](../../src/payments/controller.ts) for request handling.
The [schema](../../src/payments/schema.ts) defines the data model.
Also see [external docs](https://example.com/docs) for reference.
EOF

LINKS_OUT="$(python3 "$HELPER" extract-links \
    --file "$T9/plot/chapters/ch-payments.md" \
    --repo-root "$T9" 2>"$T9/stderr")"
RC=$?
if [ "$RC" -eq 0 ]; then
    ok "exit code 0"
else
    fail "exit code" "expected 0, got $RC; stderr=$(cat "$T9/stderr")"
fi
# Should contain the two repo-relative paths
if echo "$LINKS_OUT" | grep -q "src/payments/controller.ts"; then
    ok "controller.ts link extracted"
else
    fail "controller.ts link" "not found in output: $LINKS_OUT"
fi
if echo "$LINKS_OUT" | grep -q "src/payments/schema.ts"; then
    ok "schema.ts link extracted"
else
    fail "schema.ts link" "not found in output: $LINKS_OUT"
fi
# Should NOT contain the external URL
if echo "$LINKS_OUT" | grep -q "example.com"; then
    fail "external URL excluded" "external URL should not appear in output"
else
    ok "external URL excluded"
fi

# ---------------------------------------------------------------------------
# 10. extract-links: skip non-existent targets
# ---------------------------------------------------------------------------
case_ "10. extract-links skips non-existent file targets"
T10="$TMPROOT/case10"
mkdir -p "$T10/plot/chapters" "$T10/src/payments"
echo "// controller" > "$T10/src/payments/controller.ts"
# NOTE: schema.ts intentionally NOT created

cat > "$T10/plot/chapters/ch-payments.md" <<'EOF'
# Payments Chapter

See the [controller](../../src/payments/controller.ts) for request handling.
The [schema](../../src/payments/schema.ts) defines the data model.
The [config](../../src/payments/config.yaml) is also relevant.
EOF

LINKS_OUT="$(python3 "$HELPER" extract-links \
    --file "$T10/plot/chapters/ch-payments.md" \
    --repo-root "$T10" 2>"$T10/stderr")"
RC=$?
if [ "$RC" -eq 0 ]; then
    ok "exit code 0"
else
    fail "exit code" "expected 0, got $RC"
fi
# Should contain only the existing file
if echo "$LINKS_OUT" | grep -q "src/payments/controller.ts"; then
    ok "existing controller.ts link present"
else
    fail "existing link" "controller.ts not found in output: $LINKS_OUT"
fi
# Non-existent files should NOT appear
if echo "$LINKS_OUT" | grep -q "schema.ts"; then
    fail "non-existent schema.ts excluded" "schema.ts should NOT appear (file does not exist)"
else
    ok "non-existent schema.ts excluded"
fi
if echo "$LINKS_OUT" | grep -q "config.yaml"; then
    fail "non-existent config.yaml excluded" "config.yaml should NOT appear (file does not exist)"
else
    ok "non-existent config.yaml excluded"
fi

# ---------------------------------------------------------------------------
# 11. Tier 1 diff-scope intersection: chapter links x mock diff -> correct
#     chapters selected
# ---------------------------------------------------------------------------
case_ "11. Tier 1 diff-scope intersection"
T11="$TMPROOT/case11"
mkdir -p "$T11/plot/chapters" "$T11/src/payments" "$T11/src/auth"
echo "// pay controller" > "$T11/src/payments/controller.ts"
echo "// pay schema" > "$T11/src/payments/schema.ts"
echo "// auth handler" > "$T11/src/auth/handler.ts"
echo "// auth config" > "$T11/src/auth/config.ts"

# Chapter 1: links to payments files
cat > "$T11/plot/chapters/ch-payments.md" <<'EOF'
# Payments Chapter

See the [controller](../../src/payments/controller.ts) for request handling.
The [schema](../../src/payments/schema.ts) defines the data model.
EOF

# Chapter 2: links to auth files
cat > "$T11/plot/chapters/ch-auth.md" <<'EOF'
# Auth Chapter

See the [handler](../../src/auth/handler.ts) for auth flow.
The [config](../../src/auth/config.ts) sets auth parameters.
EOF

# Simulate a diff that only touches payments files
cat > "$T11/diff-files.txt" <<'EOF'
src/payments/controller.ts
src/payments/schema.ts
README.md
EOF

# Step 1: Extract links from each chapter
LINKS_PAY="$(python3 "$HELPER" extract-links \
    --file "$T11/plot/chapters/ch-payments.md" \
    --repo-root "$T11" 2>/dev/null)"
LINKS_AUTH="$(python3 "$HELPER" extract-links \
    --file "$T11/plot/chapters/ch-auth.md" \
    --repo-root "$T11" 2>/dev/null)"

# Step 2: Write chapter link lists to temp files for intersection
echo "$LINKS_PAY" | sort > "$T11/links-payments.txt"
echo "$LINKS_AUTH" | sort > "$T11/links-auth.txt"
sort "$T11/diff-files.txt" > "$T11/diff-sorted.txt"

# Step 3: Intersect each chapter's links with the diff
PAY_OVERLAP="$(comm -12 "$T11/links-payments.txt" "$T11/diff-sorted.txt")"
AUTH_OVERLAP="$(comm -12 "$T11/links-auth.txt" "$T11/diff-sorted.txt")"

# Payments chapter should have overlap (its links are in the diff)
if [ -n "$PAY_OVERLAP" ]; then
    ok "ch-payments overlaps with diff"
else
    fail "ch-payments overlap" "expected overlap, got none"
fi
# Auth chapter should have NO overlap (its links are not in the diff)
if [ -z "$AUTH_OVERLAP" ]; then
    ok "ch-auth does NOT overlap with diff"
else
    fail "ch-auth no overlap" "expected no overlap, got: $AUTH_OVERLAP"
fi

# Simulate the actual selection logic: list chapters with non-empty overlap
SELECTED_CHAPTERS=""
if [ -n "$PAY_OVERLAP" ]; then
    SELECTED_CHAPTERS="ch-payments.md"
fi
if [ -n "$AUTH_OVERLAP" ]; then
    SELECTED_CHAPTERS="$SELECTED_CHAPTERS ch-auth.md"
fi
SELECTED_CHAPTERS="$(echo "$SELECTED_CHAPTERS" | xargs)"

if [ "$SELECTED_CHAPTERS" = "ch-payments.md" ]; then
    ok "only ch-payments.md selected (correct Tier 1 result)"
else
    fail "Tier 1 selection" "expected 'ch-payments.md', got '$SELECTED_CHAPTERS'"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf "\n=== test-plot-annotations.sh: %d passed, %d failed ===\n" "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
    printf "Failed:%s\n" "$FAILED"
    exit 1
fi
exit 0
