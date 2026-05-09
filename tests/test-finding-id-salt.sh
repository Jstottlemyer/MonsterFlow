#!/usr/bin/env bash
##############################################################################
# tests/test-finding-id-salt.sh — Wave 3 Task 3.4 (token-economics, M7)
#
# Privacy regression — verify get_or_create_salt() and salt_finding_id() in
# scripts/compute-persona-value.py meet the M7 contract:
#   - 32-byte salt with chmod 0o600, validate-on-read
#   - deterministic finding IDs for same (salt, signature)
#   - different salts yield different IDs
#   - on corruption (zero-byte / truncated / world-readable):
#       regenerate + truncate dashboard/data/persona-rankings.jsonl
#       + emit safe_log("regenerated_salt_cleared_rankings")
#
# State is fully isolated under a tmp XDG_CONFIG_HOME so the user's real
# ~/.config/monsterflow/finding-id-salt is NEVER touched.
#
# Spec: docs/specs/token-economics/spec.md (v4.2 §Privacy)
# Plan: docs/specs/token-economics/plan.md (v1.2 — Wave 3 task 3.4, M7, Δ3)
##############################################################################
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

TMP_ROOT="$(TMPDIR=/tmp mktemp -d /tmp/test-salt-XXXXXX)"
TMP_ROOT_REAL="$(cd "$TMP_ROOT" && pwd -P)"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

PASS=0
FAIL=0
note_pass() { PASS=$((PASS + 1)); echo "PASS: $1"; }
note_fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }

# --------------------------------------------------------------------------
# 1. Determinism — same (salt, signature) → same finding ID.
# --------------------------------------------------------------------------
DET_OUT="$(python3 - <<'PY'
import sys
sys.path.insert(0, "scripts")
import importlib.util
spec = importlib.util.spec_from_file_location(
    "cpv", "scripts/compute-persona-value.py"
)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

salt = b"a" * 32
sig = "spec-review:scope-discipline:abc123"
id1 = m.salt_finding_id(salt, sig, "sr")
id2 = m.salt_finding_id(salt, sig, "sr")
print("EQ" if id1 == id2 else "NE")
print(id1)
PY
)"
if printf '%s\n' "$DET_OUT" | head -1 | grep -q '^EQ$'; then
  note_pass "deterministic — same (salt, signature) yields same finding ID"
else
  note_fail "NOT deterministic — same inputs yielded different IDs"
fi

# --------------------------------------------------------------------------
# 2. Different salts in isolated XDG paths → different IDs from same input.
# --------------------------------------------------------------------------
XDG_A="$TMP_ROOT/xdg-a"
XDG_B="$TMP_ROOT/xdg-b"
mkdir -p "$XDG_A" "$XDG_B"

DIFF_OUT="$(XDG_A="$XDG_A" XDG_B="$XDG_B" python3 - <<'PY'
import os
import sys
sys.path.insert(0, "scripts")
import importlib.util
spec = importlib.util.spec_from_file_location(
    "cpv", "scripts/compute-persona-value.py"
)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

sig = "spec-review:scope-discipline:abc123"

# Salt A
os.environ["XDG_CONFIG_HOME"] = os.environ["XDG_A"]
salt_a = m.get_or_create_salt()
id_a = m.salt_finding_id(salt_a, sig, "sr")

# Salt B
os.environ["XDG_CONFIG_HOME"] = os.environ["XDG_B"]
salt_b = m.get_or_create_salt()
id_b = m.salt_finding_id(salt_b, sig, "sr")

print("DIFF" if (salt_a != salt_b and id_a != id_b) else "SAME")
print(id_a)
print(id_b)
PY
)"
if printf '%s\n' "$DIFF_OUT" | head -1 | grep -q '^DIFF$'; then
  note_pass "different salts → different finding IDs from same input"
else
  note_fail "different XDG salts produced same ID (or same salt) — collision risk"
  printf '  output:\n%s\n' "$DIFF_OUT"
fi

# --------------------------------------------------------------------------
# 3. Salt file perms == 0o600 (verified via os.stat in Python — portable).
# --------------------------------------------------------------------------
SALT_PATH="$XDG_A/monsterflow/finding-id-salt"
if [ -f "$SALT_PATH" ]; then
  PERM_OK="$(python3 - "$SALT_PATH" <<'PY'
import os
import sys
st = os.stat(sys.argv[1])
mode = st.st_mode & 0o777
print("OK" if mode == 0o600 else "BAD:{:o}".format(mode))
PY
)"
  if [ "$PERM_OK" = "OK" ]; then
    note_pass "salt file perms == 0o600"
  else
    note_fail "salt file perms wrong: $PERM_OK"
  fi
else
  note_fail "salt file missing at $SALT_PATH after get_or_create_salt()"
fi

# --------------------------------------------------------------------------
# 4. M7 corruption regen — three failure modes.
# --------------------------------------------------------------------------
# Helper: run get_or_create_salt() once with a given XDG and rankings path,
# capturing stderr and returning the salt's resulting size.
regen_check() {
  local xdg="$1"
  local rankings="$2"
  local label="$3"

  # Pre-populate rankings file with content so we can verify it gets cleared.
  mkdir -p "$(dirname "$rankings")"
  printf 'pre-existing-row\n' > "$rankings"

  # Run the salt fetch. The script's get_or_create_salt() always uses
  # Path.cwd() / "dashboard/data/persona-rankings.jsonl" — so we cd into a
  # tmp project root for this call.
  local proj_root
  proj_root="$(dirname "$(dirname "$rankings")")"  # rankings = <proj>/dashboard/data/...
  proj_root="$(dirname "$proj_root")"

  local stderr_capture
  stderr_capture="$(
    XDG_CONFIG_HOME="$xdg" python3 - <<PY 2>&1 >/dev/null
import os
os.chdir("$proj_root")
import sys
sys.path.insert(0, "$REPO_ROOT/scripts")
import importlib.util
spec = importlib.util.spec_from_file_location(
    "cpv", "$REPO_ROOT/scripts/compute-persona-value.py"
)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
# MF-3 — destructive regen requires explicit consent in the corruption test.
salt = m.get_or_create_salt(accept_salt_reset=True)
assert len(salt) == 32, "salt length wrong: {}".format(len(salt))
PY
  )"

  # Verify regen event emitted.
  if printf '%s\n' "$stderr_capture" | grep -qF 'regenerated_salt_cleared_rankings'; then
    note_pass "M7 [$label] emitted safe_log('regenerated_salt_cleared_rankings')"
  else
    note_fail "M7 [$label] did NOT emit regenerated_salt_cleared_rankings"
    printf '  stderr:\n%s\n' "$stderr_capture" | head -10
  fi

  # Verify salt is now exactly 32 bytes with mode 600.
  local salt_path="$xdg/monsterflow/finding-id-salt"
  if [ -f "$salt_path" ]; then
    local salt_size
    salt_size="$(python3 -c "import os; print(os.stat('$salt_path').st_size)")"
    if [ "$salt_size" = "32" ]; then
      note_pass "M7 [$label] regenerated salt is 32 bytes"
    else
      note_fail "M7 [$label] regenerated salt size = $salt_size (expected 32)"
    fi
    local mode
    mode="$(python3 -c "import os; print(oct(os.stat('$salt_path').st_mode & 0o777))")"
    if [ "$mode" = "0o600" ]; then
      note_pass "M7 [$label] regenerated salt has mode 0o600"
    else
      note_fail "M7 [$label] regenerated salt mode = $mode (expected 0o600)"
    fi
  else
    note_fail "M7 [$label] salt file missing after regen"
  fi

  # Verify rankings file got truncated (cleared).
  if [ -f "$rankings" ]; then
    if [ ! -s "$rankings" ]; then
      note_pass "M7 [$label] persona-rankings.jsonl truncated"
    else
      note_fail "M7 [$label] persona-rankings.jsonl NOT truncated (still has content)"
    fi
  else
    # Acceptable — script may have left it non-existent; we only require
    # "old rows are gone".
    note_pass "M7 [$label] persona-rankings.jsonl cleared (file removed)"
  fi
}

# Corrupt 1 — zero-byte salt.
XDG_C1="$TMP_ROOT/xdg-c1"
mkdir -p "$XDG_C1/monsterflow"
: > "$XDG_C1/monsterflow/finding-id-salt"
chmod 0o600 "$XDG_C1/monsterflow/finding-id-salt" 2>/dev/null || \
  chmod 600 "$XDG_C1/monsterflow/finding-id-salt"
PROJ_C1="$TMP_ROOT/proj-c1"
mkdir -p "$PROJ_C1/dashboard/data"
regen_check "$XDG_C1" "$PROJ_C1/dashboard/data/persona-rankings.jsonl" "zero-byte"

# Corrupt 2 — truncated salt (16 bytes).
XDG_C2="$TMP_ROOT/xdg-c2"
mkdir -p "$XDG_C2/monsterflow"
python3 -c "
import os
p = '$XDG_C2/monsterflow/finding-id-salt'
fd = os.open(p, os.O_WRONLY|os.O_CREAT|os.O_TRUNC, 0o600)
os.write(fd, os.urandom(16))
os.close(fd)
"
PROJ_C2="$TMP_ROOT/proj-c2"
mkdir -p "$PROJ_C2/dashboard/data"
regen_check "$XDG_C2" "$PROJ_C2/dashboard/data/persona-rankings.jsonl" "truncated-16"

# Corrupt 3 — world-readable perms (0644).
XDG_C3="$TMP_ROOT/xdg-c3"
mkdir -p "$XDG_C3/monsterflow"
python3 -c "
import os
p = '$XDG_C3/monsterflow/finding-id-salt'
fd = os.open(p, os.O_WRONLY|os.O_CREAT|os.O_TRUNC, 0o644)
os.write(fd, os.urandom(32))
os.close(fd)
os.chmod(p, 0o644)
"
PROJ_C3="$TMP_ROOT/proj-c3"
mkdir -p "$PROJ_C3/dashboard/data"
regen_check "$XDG_C3" "$PROJ_C3/dashboard/data/persona-rankings.jsonl" "world-readable"

# --------------------------------------------------------------------------
# 5. MF-3 — destructive regen REFUSES without --accept-salt-reset.
# Set up a corrupt salt; call get_or_create_salt() (no flag); expect
# SystemExit(2) and rankings file UNTOUCHED.
# --------------------------------------------------------------------------
XDG_MF3="$TMP_ROOT/xdg-mf3"
mkdir -p "$XDG_MF3/monsterflow"
: > "$XDG_MF3/monsterflow/finding-id-salt"   # zero-byte (corrupt)
chmod 600 "$XDG_MF3/monsterflow/finding-id-salt"
PROJ_MF3="$TMP_ROOT/proj-mf3"
mkdir -p "$PROJ_MF3/dashboard/data"
RANKINGS_MF3="$PROJ_MF3/dashboard/data/persona-rankings.jsonl"
printf 'must-not-clear\n' > "$RANKINGS_MF3"

set +e
MF3_OUT="$(
  XDG_CONFIG_HOME="$XDG_MF3" python3 - <<PY 2>&1
import os
os.chdir("$PROJ_MF3")
import sys
sys.path.insert(0, "$REPO_ROOT/scripts")
import importlib.util
spec = importlib.util.spec_from_file_location(
    "cpv", "$REPO_ROOT/scripts/compute-persona-value.py"
)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
try:
    m.get_or_create_salt()  # no --accept-salt-reset → expect SystemExit(2)
    print("UNEXPECTED_RETURN")
except SystemExit as e:
    print("EXIT:{}".format(e.code))
PY
)"
MF3_RC=$?
set -e

if printf '%s\n' "$MF3_OUT" | grep -qE '^EXIT:2$'; then
  note_pass "MF-3 refuses destructive regen without --accept-salt-reset (SystemExit 2)"
else
  note_fail "MF-3 did NOT refuse — output: $MF3_OUT (rc=$MF3_RC)"
fi
if [ -s "$RANKINGS_MF3" ]; then
  note_pass "MF-3 left persona-rankings.jsonl untouched on refusal"
else
  note_fail "MF-3 cleared rankings file even though regen was refused"
fi

echo ""
echo "test-finding-id-salt: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
