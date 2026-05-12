#!/usr/bin/env bash
##############################################################################
# tests/test-security-floor.sh
#
# SEC-01 floor-enforcement fixtures for dynamic-roster-per-gate Slice 5 (T20).
#
# Plan D7 enforces SEC-01 at two sites:
#   1. `_tier_assign.validate_tier_pins`  (spec-level tier_pins block)
#   2. CLI `--tier-pin` parse site in `_resolve_personas.py`
#
# Spec AC A21 (line 520) covers spec-level rejection; CLI rejection is the
# operational guard that prevents an interactive operator from downgrading a
# security-tagged persona below `security_floor=opus`.
#
# Bash 3.2 portable; isolated fixture dirs via mktemp + trap; wall-clock <5s.
##############################################################################
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
RESOLVER="$REPO_ROOT/scripts/resolve-personas.sh"

if [ ! -x "$RESOLVER" ] && [ ! -f "$RESOLVER" ]; then
  printf "FAIL: resolver missing at %s\n" "$RESOLVER" >&2
  exit 1
fi

# Bypass codex probe so test output is deterministic (no `codex-adversary`
# trailing line in stdout, no auth side-effects).
export MONSTERFLOW_CODEX_AUTH=0

TMPROOT="$(mktemp -d -t "security-floor-test.XXXXXX")"
trap 'rm -rf "$TMPROOT"' EXIT

PASS=0
FAIL=0
SKIP=0
FAILED=()
SKIPPED=()

_ok()   { PASS=$(( PASS + 1 )); printf "  PASS %s\n" "$1"; }
_fail() { FAIL=$(( FAIL + 1 )); FAILED+=("$1"); printf "  FAIL %s -- %s\n" "$1" "$2"; }
_skip() { SKIP=$(( SKIP + 1 )); SKIPPED+=("$1: $2"); printf "  SKIP %s: %s\n" "$1" "$2"; }
case_() { printf "\n--- %s\n" "$1"; }

# Canonical SEC-01 error format (matches scripts/_tier_assign.py:163-167):
#   [tier-policy] SEC-01: persona <p> (fit_tags=[security]) pinned to <t>
#   below security_floor=<floor>; refusing.
SEC01_FIXED='[tier-policy] SEC-01: persona security-architect (fit_tags=[security]) pinned to sonnet below security_floor=opus'

# ---------------------------------------------------------------------------
# Assertion 1: Spec-level `tier_pins` rejection (spec.md frontmatter site)
#
# Per task brief: if the Slice 3/4 resolver does NOT merge spec frontmatter
# tier_pins (it currently does not — `_resolve_personas._read_baseline_and_spec_tags`
# only parses `tags:` + `tags_provenance:`, never `tier_policy.tier_pins`),
# this assertion legitimately deferred. We mark it SKIP rather than FAIL so
# the test file as a whole still exits 0. The deferred assertion remains
# documented inline (gated by `if false`) so a future slice that wires the
# spec frontmatter merge can flip the gate and re-enable.
# ---------------------------------------------------------------------------
case_ "A1 spec.md frontmatter tier_pins triggers SEC-01"

if false; then
  # Deferred: spec-frontmatter tier_pins merge not yet wired through resolver.
  # See plan D7 + spec A21. Re-enable once `_read_baseline_and_spec_tags`
  # (or a sibling reader) returns tier_pins to the --with-tier flow.
  fixture_dir="$TMPROOT/a1"
  mkdir -p "$fixture_dir/docs/specs/sec01-spec"
  cat > "$fixture_dir/docs/specs/sec01-spec/spec.md" <<'EOF'
---
name: sec01-spec
tags: [security]
tier_policy:
  tier_pins:
    check:
      security-architect: sonnet
---
# Body
oauth permissions check here.
EOF
  set +e
  err="$(PROJECT_DIR="$fixture_dir" bash "$RESOLVER" check \
            --feature sec01-spec --with-tier 2>&1 >/dev/null)"
  rc=$?
  set -e
  if [ "$rc" = "4" ] && printf '%s' "$err" | grep -qF "$SEC01_FIXED"; then
    _ok "A1 spec-frontmatter SEC-01 rejection"
  else
    _fail "A1 spec-frontmatter SEC-01 rejection" "rc=$rc err='$err'"
  fi
else
  _skip "A1 spec-frontmatter SEC-01 rejection" \
        "deferred — resolver does not yet merge spec.md tier_pins (plan D7 site 1 pending wiring)"
fi

# ---------------------------------------------------------------------------
# Assertion 2: CLI `--tier-pin security-architect=sonnet` (flat form) rejected
# ---------------------------------------------------------------------------
case_ "A2 CLI --tier-pin security-architect=sonnet rejected (exit 4)"

set +e
err="$(bash "$RESOLVER" check --feature dynamic-roster-per-gate --with-tier \
          --tier-pin security-architect=sonnet 2>&1 >/dev/null)"
rc=$?
set -e

if [ "$rc" = "4" ]; then
  _ok "A2 exit code is 4"
else
  _fail "A2 exit code is 4" "got rc=$rc"
fi

if printf '%s' "$err" | grep -qE "SEC-01.*security-architect"; then
  _ok "A2 stderr matches /SEC-01.*security-architect/"
else
  _fail "A2 stderr matches /SEC-01.*security-architect/" "err='$err'"
fi

if printf '%s' "$err" | grep -qF "$SEC01_FIXED"; then
  _ok "A2 stderr contains canonical SEC-01 fixed string"
else
  _fail "A2 stderr contains canonical SEC-01 fixed string" "err='$err'"
fi

# ---------------------------------------------------------------------------
# Assertion 3: CLI `--tier-pin security-architect=opus` accepted (no-op pin)
# Pinning a security persona AT the floor is allowed; only BELOW-floor pins
# trigger SEC-01.
# ---------------------------------------------------------------------------
case_ "A3 CLI --tier-pin security-architect=opus accepted (exit 0)"

set +e
bash "$RESOLVER" check --feature dynamic-roster-per-gate --with-tier \
     --tier-pin security-architect=opus >/dev/null 2>&1
rc=$?
set -e

if [ "$rc" = "0" ]; then
  _ok "A3 security-architect=opus accepted"
else
  _fail "A3 security-architect=opus accepted" "got rc=$rc (expected 0)"
fi

# ---------------------------------------------------------------------------
# Assertion 4: CLI gate-qualified form `check.security-architect=sonnet` rejected
# Both flat and nested pin shapes must enforce SEC-01.
# ---------------------------------------------------------------------------
case_ "A4 CLI --tier-pin check.security-architect=sonnet rejected (exit 4)"

set +e
err="$(bash "$RESOLVER" check --feature dynamic-roster-per-gate --with-tier \
          --tier-pin check.security-architect=sonnet 2>&1 >/dev/null)"
rc=$?
set -e

if [ "$rc" = "4" ]; then
  _ok "A4 gate-qualified pin exit 4"
else
  _fail "A4 gate-qualified pin exit 4" "got rc=$rc err='$err'"
fi

if printf '%s' "$err" | grep -qE "SEC-01.*security-architect"; then
  _ok "A4 gate-qualified SEC-01 message present"
else
  _fail "A4 gate-qualified SEC-01 message present" "err='$err'"
fi

# ---------------------------------------------------------------------------
# Assertion 5: Non-security persona CAN be pinned to sonnet (negative control)
# `scope-discipline` has fit_tags=[docs, refactor] — pinning to sonnet is fine.
# This guards against an over-broad SEC-01 check that rejected every pin.
# ---------------------------------------------------------------------------
case_ "A5 non-security persona scope-discipline=sonnet accepted (exit 0)"

set +e
bash "$RESOLVER" check --feature dynamic-roster-per-gate --with-tier \
     --tier-pin scope-discipline=sonnet >/dev/null 2>&1
rc=$?
set -e

if [ "$rc" = "0" ]; then
  _ok "A5 scope-discipline=sonnet accepted"
else
  _fail "A5 scope-discipline=sonnet accepted" "got rc=$rc (expected 0)"
fi

# ---------------------------------------------------------------------------
# Assertion 6: SEC-01 error string is canonical (regression guard)
# The exact format from _tier_assign.py:163-167 must remain stable — downstream
# log scrapers + dashboard renderers parse this fixed prefix.
# ---------------------------------------------------------------------------
case_ "A6 SEC-01 message format is canonical"

set +e
err="$(bash "$RESOLVER" check --feature dynamic-roster-per-gate --with-tier \
          --tier-pin security-architect=sonnet 2>&1 >/dev/null)"
set -e

if printf '%s' "$err" | grep -qF "$SEC01_FIXED"; then
  _ok "A6 canonical fixed-string match"
else
  _fail "A6 canonical fixed-string match" \
        "expected substring='$SEC01_FIXED' actual='$err'"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n'
printf 'Results: %d passed, %d failed' "$PASS" "$FAIL"
if [ "$SKIP" -gt 0 ]; then
  printf ', %d skipped' "$SKIP"
fi
printf '\n'

if [ "$SKIP" -gt 0 ]; then
  printf 'Skipped:\n'
  for s in "${SKIPPED[@]}"; do
    printf '  - %s\n' "$s"
  done
fi

if [ "$FAIL" -gt 0 ]; then
  printf 'Failed assertions:\n'
  for f in "${FAILED[@]}"; do
    printf '  - %s\n' "$f"
  done
  exit 1
fi
exit 0
