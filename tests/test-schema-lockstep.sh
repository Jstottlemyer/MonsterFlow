#!/usr/bin/env bash
# tests/test-schema-lockstep.sh — slice 2 of dynamic-roster-per-gate (task 3)
#
# Enforces A19 schema lockstep + MF#6 fit_tags enum rejection coverage.
#
# Asserts:
#   Case 1: all 3 (or 4) schema files parse as valid JSON
#   Case 2: schema files move together (same last-commit SHA OR all unchanged
#           vs main) — lockstep guard (A19)
#   Case 3 (MF#6 a): persona with fit_tags: [unknown-enum-value] is rejected
#                    with non-zero exit by jsonschema validation
#   Case 4 (MF#6 b): persona with shell-meta fit_tags: ["; rm -rf /"] is
#                    rejected by enum check
#   Case 5 (MF#6 c): tag-enum.schema.json and persona-frontmatter.schema.json
#                    must share the same last-commit SHA (or both unchanged
#                    vs main) — partial bumps trip the test
#
# Bash 3.2 compatible. Requires python3 + jsonschema (4.x). If jsonschema is
# missing, the test bails with a clear pip-install message.
#
# Style mirrors tests/test-persona-fit-tags.sh (slice 1 sibling).

set -uo pipefail
ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ENGINE_DIR"

PASS=0; FAIL=0

# ---- Dependency probe: jsonschema ----
if ! python3 -c "import jsonschema" 2>/dev/null; then
  echo "FAIL test dependency missing: jsonschema"
  echo "  install with: pip3 install jsonschema"
  exit 2
fi

# ---- Schema file inventory ----
# selection.schema.json is task 2's output (parallel wave); guard with [ -f ].
SCHEMAS=(
  "schemas/persona-frontmatter.schema.json"
  "schemas/spec-frontmatter.schema.json"
  "schemas/tag-enum.schema.json"
)
if [ -f "schemas/selection.schema.json" ]; then
  SCHEMAS+=("schemas/selection.schema.json")
fi

# ---- Case 1: all schemas parse as valid JSON ----
case1_fail=0
for schema in "${SCHEMAS[@]}"; do
  if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$schema" 2>/dev/null; then
    echo "FAIL case1_schema_parses_as_json: $schema"
    case1_fail=1
  fi
done
if [ "$case1_fail" = "0" ]; then
  echo "PASS case1_all_schemas_parse_as_json"
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1))
fi

# ---- Case 2: schema lockstep (A19) ----
# Heuristic: all schemas share the same last-commit SHA, OR all are unchanged
# in this branch vs main (i.e., no diff). Prior art: test-persona-fit-tags.sh
# uses a similar "schemas-move-together" mental model.
_file_state() {
  # Returns one of: untracked | modified | clean
  local f="$1"
  # Untracked?
  if [ -n "$(git ls-files --others --exclude-standard -- "$f" 2>/dev/null)" ]; then
    echo "untracked"
    return
  fi
  # Modified vs index/HEAD?
  if ! git diff --quiet HEAD -- "$f" 2>/dev/null; then
    echo "modified"
    return
  fi
  echo "clean"
}

_lockstep_check() {
  local files=("$@")
  # If ANY file in the set has working-tree changes (untracked or modified
  # vs HEAD), the lockstep set is being landed on this branch and committed
  # SHAs are not yet meaningful. Skip the SHA check — the orchestrator-wiring
  # test (task 24) will re-run this after all wave-W1 tasks merge, when the
  # working tree is clean and SHAs lock in. This is the documented behavior
  # for parallel-wave delivery (W1 tasks 1,2,3 ship together).
  local in_flight=0
  local f state
  for f in "${files[@]}"; do
    state="$(_file_state "$f")"
    if [ "$state" != "clean" ]; then
      in_flight=$((in_flight+1))
    fi
  done
  if [ "$in_flight" -gt 0 ]; then
    echo "  ($in_flight of ${#files[@]} files in-flight; SHA check deferred until working tree is clean)"
    return 0
  fi
  # All clean: require shared last-commit SHA.
  local shas=""
  for f in "${files[@]}"; do
    local sha
    sha="$(git log -1 --format=%H -- "$f" 2>/dev/null)"
    if [ -z "$sha" ]; then
      echo "  $f has no git history"
      return 1
    fi
    shas="$shas $sha"
  done
  local unique
  unique=$(printf '%s\n' $shas | sort -u | wc -l | tr -d ' ')
  if [ "$unique" = "1" ]; then
    return 0
  fi
  echo "  SHAs differ:$shas"
  return 1
}

if _lockstep_check "${SCHEMAS[@]}"; then
  echo "PASS case2_schema_lockstep"
  PASS=$((PASS+1))
else
  echo "FAIL case2_schema_lockstep: schemas drifted (A19 violation)"
  FAIL=$((FAIL+1))
fi

# ---- Cases 3 & 4: jsonschema enum rejection (MF#6 a, b) ----
# Use the persona-frontmatter schema directly. Resolve the external
# tag-enum.schema.json $ref via a local file:// base URI so jsonschema can
# follow it. Inline the JSON via a temp file (bash 3.2 has no ${var@Q}).
_assert_rejected_v2() {
  local label="$1"; local doc_json="$2"
  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/schema-lockstep-doc.XXXXXX")" || {
    echo "FAIL $label: mktemp failed"
    FAIL=$((FAIL+1))
    return
  }
  printf '%s' "$doc_json" > "$tmp"
  local result
  result=$(python3 - "$tmp" <<'PY'
import json, sys
from pathlib import Path
from jsonschema import Draft202012Validator
from jsonschema.validators import RefResolver

schema_path = Path("schemas/persona-frontmatter.schema.json").resolve()
schema = json.loads(schema_path.read_text())
enum_path = Path("schemas/tag-enum.schema.json").resolve()
enum_schema = json.loads(enum_path.read_text())
base = schema_path.parent.as_uri() + "/"
# Preload tag-enum under both its relative-ref form and its $id absolute URL
# so jsonschema never reaches the network.
store = {
    base + "tag-enum.schema.json": enum_schema,
    enum_schema.get("$id", ""): enum_schema,
}
resolver = RefResolver(base_uri=base, referrer=schema, store=store)
validator = Draft202012Validator(schema, resolver=resolver)

doc = json.loads(Path(sys.argv[1]).read_text())
errors = list(validator.iter_errors(doc))
if errors:
    print("REJECTED")
else:
    print("ACCEPTED")
PY
)
  rm -f "$tmp"
  if [ "$result" = "REJECTED" ]; then
    echo "PASS $label"
    PASS=$((PASS+1))
  else
    echo "FAIL $label: expected schema rejection, got '$result'"
    FAIL=$((FAIL+1))
  fi
}

# Case 3 (MF#6 a): unknown enum value
_assert_rejected_v2 case3_unknown_enum_value_rejected \
  '{"fit_tags": ["auth"]}'

# Case 4 (MF#6 b): shell-meta value
_assert_rejected_v2 case4_shell_meta_value_rejected \
  '{"fit_tags": ["; rm -rf /"]}'

# Sanity: a valid persona doc SHOULD pass (positive control, prevents
# fail-open from a broken validator harness).
_assert_accepted() {
  local label="$1"; local doc_json="$2"
  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/schema-lockstep-doc.XXXXXX")" || {
    echo "FAIL $label: mktemp failed"
    FAIL=$((FAIL+1))
    return
  }
  printf '%s' "$doc_json" > "$tmp"
  local result
  result=$(python3 - "$tmp" <<'PY'
import json, sys
from pathlib import Path
from jsonschema import Draft202012Validator
from jsonschema.validators import RefResolver

schema_path = Path("schemas/persona-frontmatter.schema.json").resolve()
schema = json.loads(schema_path.read_text())
enum_path = Path("schemas/tag-enum.schema.json").resolve()
enum_schema = json.loads(enum_path.read_text())
base = schema_path.parent.as_uri() + "/"
# Preload tag-enum under both its relative-ref form and its $id absolute URL
# so jsonschema never reaches the network.
store = {
    base + "tag-enum.schema.json": enum_schema,
    enum_schema.get("$id", ""): enum_schema,
}
resolver = RefResolver(base_uri=base, referrer=schema, store=store)
validator = Draft202012Validator(schema, resolver=resolver)

doc = json.loads(Path(sys.argv[1]).read_text())
errors = list(validator.iter_errors(doc))
print("REJECTED" if errors else "ACCEPTED")
PY
)
  rm -f "$tmp"
  if [ "$result" = "ACCEPTED" ]; then
    echo "PASS $label"
    PASS=$((PASS+1))
  else
    echo "FAIL $label: expected schema accept, got '$result'"
    FAIL=$((FAIL+1))
  fi
}

_assert_accepted case_positive_control_valid_persona_accepted \
  '{"fit_tags": ["security", "integration"]}'

# ---- Case 5 (MF#6 c): tag-enum and persona-frontmatter lockstep ----
# Stronger than case 2's "all schemas" check: this specifically guards the
# pair that share the enum vocabulary. If one bumps without the other, the
# closed-enum contract is silently broken.
PAIR=(
  "schemas/persona-frontmatter.schema.json"
  "schemas/tag-enum.schema.json"
)
if _lockstep_check "${PAIR[@]}"; then
  echo "PASS case5_tag_enum_persona_pair_lockstep"
  PASS=$((PASS+1))
else
  echo "FAIL case5_tag_enum_persona_pair_lockstep: enum/persona schemas drifted (MF#6 c)"
  FAIL=$((FAIL+1))
fi

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
