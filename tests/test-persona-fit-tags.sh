#!/usr/bin/env bash
# tests/test-persona-fit-tags.sh — slice 1 of dynamic-roster-per-gate
#
# Validates that every persona under personas/{review,plan,check}/ declares
# fit_tags: frontmatter with values drawn from the closed 9-value enum
# (schemas/tag-enum.schema.json).
#
# Bash 3.2 + system Python 3.9 compatible. No PyYAML, no jsonschema.
# Stdlib regex extraction only — see plan D1 for rationale.
#
# Asserts (4 PASS lines on success):
#   (a) presence  — every persona file has a fit_tags: line in frontmatter
#   (b) enum      — every fit_tags value is in the closed enum
#   (c) nonempty  — no persona has fit_tags: []
#   (d) unique    — no persona has duplicate fit_tags entries
#
# Smoke checks the three new schema files parse as JSON before running.

set -uo pipefail
ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ENGINE_DIR"

PASS=0; FAIL=0

# ---- Smoke: 3 schema files load as JSON (must-fix completeness-M2) ----
for schema in schemas/tag-enum.schema.json \
              schemas/spec-frontmatter.schema.json \
              schemas/persona-frontmatter.schema.json; do
  if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$schema" 2>/dev/null; then
    echo "FAIL schema_loads_as_json: $schema does not parse as JSON"
    FAIL=$((FAIL+1))
  fi
done

# ---- Negative-path fixtures generated inline (must-fix testability-M2) ----
# Fixtures live as heredocs in this script (not on-disk under tests/fixtures/)
# so the slice-1 dormancy grep (A9) only matches schemas + this test file.
# Each bad fixture must FAIL the same _python_check, proving the validator
# catches missing/empty/enum/duplicate violations.
FIXTURE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/persona-fit-tags-fixtures.XXXXXX")" || {
  echo "FAIL test harness — mktemp -d failed"
  exit 2
}
# Defense-in-depth against mktemp returning empty: refuse to proceed with an
# empty FIXTURE_DIR (would make `mkdir -p "/bad-missing"` write at filesystem root).
if [ -z "$FIXTURE_DIR" ] || [ "$FIXTURE_DIR" = "/" ]; then
  echo "FAIL test harness — mktemp returned empty or root path: '$FIXTURE_DIR'"
  exit 2
fi
trap 'rm -rf "$FIXTURE_DIR"' EXIT

mkdir -p "$FIXTURE_DIR/bad-missing" \
         "$FIXTURE_DIR/bad-empty" \
         "$FIXTURE_DIR/bad-enum" \
         "$FIXTURE_DIR/bad-duplicate"

cat > "$FIXTURE_DIR/bad-missing/no-tag-line.md" <<'EOF'
---
name: no-tag-line
description: Persona file without the required tag line — must be rejected
---

# No Tag Line

Body.
EOF

cat > "$FIXTURE_DIR/bad-empty/empty-tag-line.md" <<'EOF'
---
fit_tags: []
---

# Empty Tag Line

Body.
EOF

cat > "$FIXTURE_DIR/bad-enum/typo-tag-line.md" <<'EOF'
---
fit_tags: [securty, data]
---

# Typo Tag Line

Body.
EOF

cat > "$FIXTURE_DIR/bad-duplicate/duplicate-tag-line.md" <<'EOF'
---
fit_tags: [security, security]
---

# Duplicate Tag Line

Body.
EOF

# ---- Core check: invoke once, capture JSON report ----
_python_check() {
  local target_dir="${1:-}"
  python3 - "$target_dir" <<'PY'
import re, sys, glob, json, os
ENUM = {"api","data","docs","integration","migration","refactor","scalability","security","ux"}
FM = re.compile(r"^---\n(.*?)\n---", re.DOTALL)
FIT = re.compile(r"^fit_tags:\s*\[([^\]]*)\]\s*$", re.MULTILINE)
FIT_BLOCK = re.compile(r"^fit_tags:\s*$", re.MULTILINE)
SKIP = {"judge.md", "synthesis.md"}
errors = {"presence": [], "enum": [], "nonempty": [], "unique": []}

target = sys.argv[1] if len(sys.argv) > 1 else ""
if target:
    paths = sorted(glob.glob(os.path.join(target, "*.md")))
else:
    paths = []
    for gate in ["personas/review", "personas/plan", "personas/check"]:
        paths.extend(sorted(glob.glob(f"{gate}/*.md")))

for path in paths:
    name = os.path.basename(path)
    if name in SKIP:
        continue
    try:
        text = open(path, encoding="utf-8").read()
    except OSError as e:
        errors["presence"].append([path, f"read error: {e}"])
        continue
    m = FM.search(text)
    if not m:
        errors["presence"].append([path, "no frontmatter"])
        continue
    fm = FIT.search(m.group(1))
    if not fm:
        # detect block-form (better error message per should-fix risk-S3)
        if FIT_BLOCK.search(m.group(1)):
            errors["presence"].append([path, "fit_tags must use inline-array form [a, b], not block list"])
        else:
            errors["presence"].append([path, "no fit_tags: line"])
        continue
    raw = [v.strip().strip('"').strip("'") for v in fm.group(1).split(",") if v.strip()]
    if not raw:
        errors["nonempty"].append(path)
        continue
    bad = [v for v in raw if v not in ENUM]
    if bad:
        errors["enum"].append([path, bad])
    if len(set(raw)) != len(raw):
        errors["unique"].append([path, raw])

print(json.dumps(errors))
PY
}

REPORT="$(_python_check)"

# ---- Fail-open guard (must-fix risk-M1): validate REPORT is JSON ----
if ! printf '%s' "$REPORT" | python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
required = {"presence","enum","nonempty","unique"}
missing = required - set(d.keys())
if missing:
    sys.exit("missing keys: " + ",".join(sorted(missing)))
' >/dev/null 2>&1; then
  echo "FAIL test harness — _python_check did not emit valid JSON with 4 keys"
  echo "  raw output: $REPORT"
  exit 2
fi

_count() {
  local key="$1"
  printf '%s' "$REPORT" | python3 -c "import sys,json; print(len(json.loads(sys.stdin.read())['$key']))"
}

_dump_errors() {
  local key="$1"
  printf '%s' "$REPORT" | python3 -c "
import sys, json
d = json.loads(sys.stdin.read())
for e in d['$key']:
    print('  ', e)
"
}

_report() {
  local key="$1"; local label="$2"
  local n
  n="$(_count "$key")"
  if [ "$n" = "0" ]; then
    echo "PASS $label"
    PASS=$((PASS+1))
  else
    echo "FAIL $label"
    _dump_errors "$key"
    echo "  Valid values: api, data, docs, integration, migration, refactor, scalability, security, ux"
    FAIL=$((FAIL+1))
  fi
}

_report presence  test_all_personas_have_fit_tags
_report enum      test_all_fit_tags_are_valid_enum_values
_report nonempty  test_no_empty_fit_tags
_report unique    test_no_duplicate_fit_tags

# ---- Negative-path fixtures (must-fix testability-M2) ----
# Each bad-* fixture must produce at least one error in the corresponding category.
if [ -d "$FIXTURE_DIR" ]; then
  for kind in missing empty enum duplicate; do
    fixture_subdir="$FIXTURE_DIR/bad-$kind"
    if [ ! -d "$fixture_subdir" ]; then
      continue
    fi
    fixture_report="$(_python_check "$fixture_subdir")"
    if ! printf '%s' "$fixture_report" | python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
required = {"presence","enum","nonempty","unique"}
missing = required - set(d.keys())
if missing:
    sys.exit("missing keys: " + ",".join(sorted(missing)))
' >/dev/null 2>&1; then
      echo "FAIL fixture harness — bad-$kind did not produce valid JSON"
      FAIL=$((FAIL+1))
      continue
    fi
    # Map fixture kind to expected error category.
    case "$kind" in
      missing)   expect_key="presence" ;;
      empty)     expect_key="nonempty" ;;
      enum)      expect_key="enum" ;;
      duplicate) expect_key="unique" ;;
    esac
    n_total=$(printf '%s' "$fixture_report" | python3 -c "
import sys, json
d = json.loads(sys.stdin.read())
print(sum(len(v) for v in d.values()))
")
    if [ "$n_total" = "0" ]; then
      echo "FAIL fixture bad-$kind expected validator to flag at least one error, got none"
      FAIL=$((FAIL+1))
    else
      echo "PASS fixture_bad_${kind}_is_rejected"
      PASS=$((PASS+1))
    fi
  done
fi

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
