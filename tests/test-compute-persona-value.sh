#!/usr/bin/env bash
##############################################################################
# tests/test-compute-persona-value.sh — Wave 3 task 3.1 (token-economics)
#
# Orchestrates Python sub-helpers that exercise compute-persona-value.py
# against tests/fixtures/cross-project/ for the following acceptance
# criteria from docs/specs/token-economics/spec.md (v4.2):
#
#   A1  — cost-sum equality on subagent rows (trivial under fixtures: no
#         real subagent transcripts wired; full A1 calibration ships in
#         /preship pre-release smoke).
#   A2  — three rates ∈ [0,1]∪{null}, run_state_counts shape, value-window
#         sum invariant, cost vs value-window split per M3, insufficient-
#         sample flag.
#   A3  — Project Discovery cascade: cwd-only, explicit-config, and
#         --scan-projects-root + --confirm-scan-roots.
#   A4  — content-hash window reset (best-effort per v4.1 weakening). The
#         engine has no --personas-root override, so this is the partial
#         test the spec calls out: assert persona_content_hash field is
#         populated for at least one row.
#   A7  — edge cases (e1, e9, e10, e11), --scan-projects-root opt-in
#         default-off, soft-cap N/A under fixture sizes (documented).
#   A8  — idempotent re-run: byte-equality after stripping
#         last_artifact_created_at (the documented volatile field).
#   A11 — outcome criterion: ≥1 row per distinct (persona, gate) in source
#         findings.jsonl[s] PLUS explicit e12 fresh-install case.
#
# Isolation: every invocation runs under a tmp XDG_CONFIG_HOME and a tmp
# HOME so neither the user's real ~/.config/monsterflow/ nor their real
# ~/.claude/projects/ contaminate output. MONSTERFLOW_ALLOWED_ROOTS is
# scoped to /private/tmp:/tmp:<repo> so validate_project_root() accepts
# fixture and tmp paths.
#
# Spec: docs/specs/token-economics/spec.md (v4.2 §Acceptance Criteria)
# Plan: docs/specs/token-economics/plan.md (v1.2 — Wave 3 task 3.1)
##############################################################################
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="$REPO_ROOT/scripts/compute-persona-value.py"
FIXTURES_ROOT="$REPO_ROOT/tests/fixtures/cross-project"
ALPHA="$FIXTURES_ROOT/project-alpha"
BETA="$FIXTURES_ROOT/project-beta"

if [ ! -f "$ENGINE" ]; then
  echo "FAIL: engine missing at $ENGINE" >&2
  exit 2
fi
if [ ! -d "$ALPHA" ] || [ ! -d "$BETA" ]; then
  echo "FAIL: cross-project fixtures missing under $FIXTURES_ROOT" >&2
  exit 2
fi

TMP_ROOT="$(mktemp -d -t cpv-test.XXXXXX)"

cleanup() {
  if [ -n "${TMP_ROOT:-}" ] && [ -d "$TMP_ROOT" ]; then
    rm -rf "$TMP_ROOT"
  fi
}
trap cleanup EXIT INT TERM

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

note_pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS: $1"; }
note_fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "FAIL: $1"; }
note_skip() { SKIP_COUNT=$((SKIP_COUNT + 1)); echo "SKIP: $1"; }

# --------------------------------------------------------------------------
# Per-test isolated env helper.
#
# Sets globals SANDBOX, HOME, XDG_CONFIG_HOME, MONSTERFLOW_ALLOWED_ROOTS and
# exports them so subsequent subshell engine invocations inherit a hermetic
# environment. NOTE: must be called as `setup_env <subdir>` directly (NOT
# inside `$(...)` command substitution — that would lose the exports).
# --------------------------------------------------------------------------
setup_env() {
  local sub="$1"
  SANDBOX="$TMP_ROOT/$sub"
  rm -rf "$SANDBOX"
  mkdir -p "$SANDBOX/home/.claude/projects" \
           "$SANDBOX/home/.claude/personas/review" \
           "$SANDBOX/home/.claude/personas/design" \
           "$SANDBOX/home/.claude/personas/check" \
           "$SANDBOX/config/monsterflow"
  export HOME="$SANDBOX/home"
  export XDG_CONFIG_HOME="$SANDBOX/config"
  export MONSTERFLOW_ALLOWED_ROOTS="/private/tmp:/tmp:$REPO_ROOT"
}

run_engine() {
  # Wrapper so the engine invocation is consistent across tests; --best-effort
  # is added because A1.5 mismatches against the fixture-free (or real-data)
  # ~/.claude/projects/ trees are environmental noise, not engine bugs.
  python3 "$ENGINE" "$@"
}

# --------------------------------------------------------------------------
# Generate a baseline rankings JSONL against both fixture roots; reused by
# A2, A4, A7, A11.
# --------------------------------------------------------------------------
generate_baseline() {
  setup_env "baseline"
  local out="$SANDBOX/rankings.jsonl"
  # cd into sandbox so cwd-tier-1 does NOT pick up MonsterFlow's own
  # docs/specs/ (which would contaminate the deterministic fixture output).
  if ! ( cd "$SANDBOX" && run_engine \
      --confirm-scan-roots "$FIXTURES_ROOT" \
      --scan-projects-root "$FIXTURES_ROOT" \
      --best-effort \
      --out "$out" >"$SANDBOX/stderr.log" 2>&1 ); then
    cat "$SANDBOX/stderr.log" >&2
    return 1
  fi
  echo "$out"
}

# ==========================================================================
# A1 — cost-sum equality on subagent rows
# ==========================================================================
test_A1() {
  setup_env "a1"
  local out="$SANDBOX/rankings.jsonl"
  # Empty HOME/.claude/projects → no cost dispatches → no subagent
  # transcripts to compare. Trivially holds at 0=0; full A1 calibration is
  # owned by /preship pre-release smoke (per task 3.1 scope note).
  # cd into sandbox so cwd-tier-1 does NOT pick up MonsterFlow's own
  # docs/specs/ (which would contaminate output and may exercise unrelated
  # engine bugs outside this test's scope).
  if ! ( cd "$SANDBOX" && run_engine \
      --confirm-scan-roots "$FIXTURES_ROOT" \
      --scan-projects-root "$FIXTURES_ROOT" \
      --out "$out" >"$SANDBOX/stderr.log" 2>&1 ); then
    note_fail "A1 (engine invocation failed under hermetic env)"
    cat "$SANDBOX/stderr.log" >&2
    return
  fi
  # A1.5 cross-check did not exit 1 (no --best-effort needed because there
  # were zero dispatches to mismatch). Verify cost side is empty.
  python3 - "$out" <<'PY' || { note_fail "A1 cost-sum trivial equality"; return; }
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1])]
total_cost = sum(r["total_tokens"] for r in rows)
total_cost_runs = sum(r["cost_runs_in_window"] for r in rows)
if total_cost != 0 or total_cost_runs != 0:
    sys.stderr.write(
        "expected zero cost under hermetic HOME, got total_tokens={} "
        "cost_runs_in_window={}\n".format(total_cost, total_cost_runs)
    )
    sys.exit(1)
sys.exit(0)
PY
  note_pass "A1 cost-sum trivial equality (0=0; full calibration deferred to /preship)"
}

# ==========================================================================
# A2 — three rates + run_state_counts shape
# ==========================================================================
test_A2() {
  local out
  if ! out="$(generate_baseline)"; then
    note_fail "A2 (baseline generation failed)"
    return
  fi
  python3 - "$out" <<'PY' || { note_fail "A2 rates + run_state_counts shape"; return; }
import json
import sys

rows = [json.loads(l) for l in open(sys.argv[1])]
if not rows:
    sys.stderr.write("A2: baseline emitted zero rows; expected ≥1\n")
    sys.exit(1)

REQUIRED_STATE_KEYS = {
    "complete_value", "silent", "missing_survival", "missing_findings",
    "missing_raw", "malformed", "cost_only",
}
VALUE_STATES = {
    "complete_value", "silent", "missing_survival", "missing_findings",
    "missing_raw", "malformed",
}

errors = []
for i, r in enumerate(rows):
    tag = "row{}({}@{})".format(i, r.get("persona"), r.get("gate"))
    # Rate range check.
    for k in ("judge_retention_ratio", "downstream_survival_rate",
              "uniqueness_rate"):
        v = r.get(k)
        if v is None:
            continue
        if not isinstance(v, (int, float)) or v < 0.0 or v > 1.0:
            errors.append("{}: {} out of [0,1]: {!r}".format(tag, k, v))
    # run_state_counts shape.
    rsc = r.get("run_state_counts")
    if not isinstance(rsc, dict):
        errors.append("{}: run_state_counts is not an object".format(tag))
        continue
    missing = REQUIRED_STATE_KEYS - set(rsc.keys())
    if missing:
        errors.append(
            "{}: run_state_counts missing keys {}".format(tag, sorted(missing))
        )
    extra = set(rsc.keys()) - REQUIRED_STATE_KEYS
    if extra:
        errors.append(
            "{}: run_state_counts unexpected keys {}".format(tag, sorted(extra))
        )
    # Value-states sum invariant.
    value_sum = sum(rsc.get(s, 0) for s in VALUE_STATES)
    if value_sum != r.get("runs_in_window"):
        errors.append(
            "{}: sum(value_states)={} != runs_in_window={}".format(
                tag, value_sum, r.get("runs_in_window")
            )
        )
    # Cost-window invariant (M3): cost_runs_in_window must be ≥ cost_only
    # contribution. The engine sets cost_only > 0 ONLY when value side is
    # empty for the (persona,gate) — so this is a loose lower-bound check.
    if r.get("cost_runs_in_window", 0) < rsc.get("cost_only", 0):
        errors.append(
            "{}: cost_runs_in_window={} < cost_only={}".format(
                tag, r.get("cost_runs_in_window"), rsc.get("cost_only")
            )
        )
    # insufficient_sample iff runs_in_window < 3.
    expected_ins = r.get("runs_in_window", 0) < 3
    if r.get("insufficient_sample") != expected_ins:
        errors.append(
            "{}: insufficient_sample={} but runs_in_window={}".format(
                tag, r.get("insufficient_sample"), r.get("runs_in_window")
            )
        )

if errors:
    for e in errors:
        sys.stderr.write("A2: " + e + "\n")
    sys.exit(1)
sys.exit(0)
PY
  note_pass "A2 three rates ∈ [0,1]∪null + run_state_counts shape + value-sum invariant"
}

# ==========================================================================
# A3 — Project Discovery cascade (cwd / explicit-config / --scan-projects-root)
# ==========================================================================
test_A3() {
  local out

  # --- A3a: cwd-only path. Run engine from inside project-alpha; expect
  #          rows derived from alpha/feature-x + alpha/feature-y.
  setup_env "a3-cwd"
  out="$SANDBOX/rankings.jsonl"
  ( cd "$ALPHA" && run_engine --out "$out" >"$SANDBOX/stderr.log" 2>&1 ) || {
    note_fail "A3a cwd-only invocation failed"
    cat "$SANDBOX/stderr.log" >&2
    return
  }
  python3 - "$out" "alpha" <<'PY' || { note_fail "A3a cwd-only discovers cwd project"; return; }
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1])]
# Alpha contributes scope-discipline @ spec-review, ux-flow @ spec-review, etc.
# Beta contributes scope-discipline (which would inflate the count).
# In cwd-only mode we expect ux-flow @ spec-review to be present (alpha-only)
# and ambiguity to be ABSENT (beta-only).
have = {(r["persona"], r["gate"]) for r in rows}
if ("ux-flow", "spec-review") not in have:
    sys.stderr.write("A3a: ux-flow@spec-review missing (expected from alpha)\n")
    sys.exit(1)
if ("ambiguity", "spec-review") in have:
    sys.stderr.write("A3a: ambiguity@spec-review present but is beta-only\n")
    sys.exit(1)
sys.exit(0)
PY
  note_pass "A3a cwd-only cascade discovers cwd project (and only cwd)"

  # --- A3b: explicit config path. Write tmp ~/.config/monsterflow/projects
  #          containing project-alpha. Expect alpha rows; beta absent.
  setup_env "a3-cfg"
  out="$SANDBOX/rankings.jsonl"
  printf '%s\n' "$ALPHA" > "$XDG_CONFIG_HOME/monsterflow/projects"
  # Run from a tmp dir that does NOT have docs/specs (so cwd doesn't add
  # anything).
  ( cd "$SANDBOX" && run_engine --out "$out" >"$SANDBOX/stderr.log" 2>&1 ) || {
    note_fail "A3b explicit-config invocation failed"
    cat "$SANDBOX/stderr.log" >&2
    return
  }
  python3 - "$out" <<'PY' || { note_fail "A3b explicit-config discovers project-alpha"; return; }
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1])]
have = {(r["persona"], r["gate"]) for r in rows}
if ("ux-flow", "spec-review") not in have:
    sys.stderr.write("A3b: ux-flow@spec-review missing (expected from alpha)\n")
    sys.exit(1)
if ("ambiguity", "spec-review") in have:
    sys.stderr.write("A3b: ambiguity@spec-review present but config only listed alpha\n")
    sys.exit(1)
sys.exit(0)
PY
  note_pass "A3b explicit-config (XDG) cascade discovers listed project (and only listed)"

  # --- A3c: --scan-projects-root + --confirm-scan-roots. Pass FIXTURES_ROOT
  #          so the cascade walks both project-alpha and project-beta.
  setup_env "a3-scan"
  out="$SANDBOX/rankings.jsonl"
  ( cd "$SANDBOX" && run_engine \
      --confirm-scan-roots "$FIXTURES_ROOT" \
      --scan-projects-root "$FIXTURES_ROOT" \
      --best-effort \
      --out "$out" >"$SANDBOX/stderr.log" 2>&1 ) || {
    note_fail "A3c --scan-projects-root invocation failed"
    cat "$SANDBOX/stderr.log" >&2
    return
  }
  python3 - "$out" <<'PY' || { note_fail "A3c --scan-projects-root discovers BOTH alpha and beta"; return; }
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1])]
have = {(r["persona"], r["gate"]) for r in rows}
if ("ux-flow", "spec-review") not in have:
    sys.stderr.write("A3c: ux-flow@spec-review missing (alpha-only persona)\n")
    sys.exit(1)
if ("ambiguity", "spec-review") not in have:
    sys.stderr.write("A3c: ambiguity@spec-review missing (beta-only persona)\n")
    sys.exit(1)
sys.exit(0)
PY
  note_pass "A3c --scan-projects-root + --confirm-scan-roots discovers BOTH projects"
}

# ==========================================================================
# A4 — content-hash window reset (best-effort, partial coverage)
# ==========================================================================
test_A4() {
  local out
  if ! out="$(generate_baseline)"; then
    note_fail "A4 (baseline generation failed)"
    return
  fi
  # The engine reads persona files from ~/.claude/personas/ at aggregation
  # time. For our hermetic baseline run, that dir is empty, so
  # persona_content_hash is null for every row. To exercise the field we
  # seed one persona file under the test's HOME and re-run.
  local out2 review_dir
  setup_env "a4-seeded"
  out2="$SANDBOX/rankings.jsonl"
  review_dir="$HOME/.claude/personas/review"
  printf '%s\n' "# scope-discipline (test seed)" \
      "" "Stub persona body for A4 hash test." \
      > "$review_dir/scope-discipline.md"
  if ! ( cd "$SANDBOX" && run_engine \
      --confirm-scan-roots "$FIXTURES_ROOT" \
      --scan-projects-root "$FIXTURES_ROOT" \
      --best-effort \
      --out "$out2" >"$SANDBOX/stderr.log" 2>&1 ); then
    note_fail "A4 seeded re-run failed"
    cat "$SANDBOX/stderr.log" >&2
    return
  fi
  python3 - "$out2" <<'PY' || { note_fail "A4 persona_content_hash populated for seeded persona"; return; }
import json, sys, re
rows = [json.loads(l) for l in open(sys.argv[1])]
hash_re = re.compile(r"^sha256:[0-9a-f]{64}$")
seeded = [r for r in rows if r["persona"] == "scope-discipline" and r["gate"] == "spec-review"]
if not seeded:
    sys.stderr.write("A4: no scope-discipline@spec-review row in output\n")
    sys.exit(1)
h = seeded[0].get("persona_content_hash")
if not h or not hash_re.match(h):
    sys.stderr.write("A4: scope-discipline persona_content_hash not populated: {!r}\n".format(h))
    sys.exit(1)
sys.exit(0)
PY
  note_pass "A4 persona_content_hash populated when persona file present (partial — no --personas-root flag means destructive reset case is deferred)"
  echo "      NOTE: A4 destructive case (post-edit ID clear) requires engine --personas-root override (not yet wired); v1.1 backlog per spec."
}

# ==========================================================================
# A7 — edge cases (e1, e9, e10, e11) + scan opt-in default-off
# ==========================================================================
test_A7() {
  local out
  if ! out="$(generate_baseline)"; then
    note_fail "A7 (baseline generation failed)"
    return
  fi
  python3 - "$out" <<'PY' || { note_fail "A7 edge case coverage"; return; }
import json, sys

rows = [json.loads(l) for l in open(sys.argv[1])]

# e1 — insufficient_sample (runs_in_window < 3).
e1 = [r for r in rows if r.get("insufficient_sample") and r.get("runs_in_window", 0) < 3]
if not e1:
    sys.stderr.write("A7/e1: no row with insufficient_sample=True AND runs_in_window<3\n")
    sys.exit(1)

# e10 — total_emitted == 0 → judge_retention_ratio is null.
e10 = [r for r in rows if r.get("total_emitted") == 0 and r.get("judge_retention_ratio") is None]
if not e10:
    sys.stderr.write("A7/e10: no row with total_emitted=0 AND judge_retention_ratio=None\n")
    sys.exit(1)

# e11 — total_judge_retained == 0 → downstream_survival_rate is null.
e11 = [r for r in rows if r.get("total_judge_retained") == 0 and r.get("downstream_survival_rate") is None]
if not e11:
    sys.stderr.write("A7/e11: no row with total_judge_retained=0 AND downstream_survival_rate=None\n")
    sys.exit(1)

# Soft-cap: only triggers if any persona has >50 contributing findings.
trunc = [r for r in rows if r.get("truncated_count", 0) > 0]
# Document N/A; assert truncated_count >= 0 + maxItems(50) holds via schema.
for r in rows:
    fids = r.get("contributing_finding_ids") or []
    if len(fids) > 50:
        sys.stderr.write("A7/soft-cap: row {}@{} has {} ids (>50)\n".format(
            r.get("persona"), r.get("gate"), len(fids)))
        sys.exit(1)

# All passed.
sys.exit(0)
PY
  note_pass "A7 edge cases e1/e10/e11 covered + soft-cap (maxItems<=50) holds"
  echo "      NOTE: A7 e2 (content-hash reset) and e12 (fresh-install) covered by A4 + A11 respectively. Soft-cap trunc>0 is N/A under fixture sizes (no persona has >50 findings)."

  # e9 — "(never run)" personas: roster has personas not in JSONL.
  # Seed one persona file under HOME's personas/ that does NOT appear in any
  # fixture findings.jsonl (`never-run-persona`), then verify the roster
  # carries it as a key absent from rankings.
  setup_env "a7-e9"
  printf '%s\n' "# never-run-persona" "" "Stub persona body." \
    > "$HOME/.claude/personas/check/never-run-persona.md"
  local out roster
  out="$SANDBOX/rankings.jsonl"
  ( cd "$SANDBOX" && run_engine \
      --confirm-scan-roots "$FIXTURES_ROOT" \
      --scan-projects-root "$FIXTURES_ROOT" \
      --best-effort \
      --out "$out" >"$SANDBOX/stderr.log" 2>&1 ) || {
    note_fail "A7/e9 baseline (with seeded never-run persona) failed"
    cat "$SANDBOX/stderr.log" >&2
    return
  }
  roster="$(dirname "$out")/persona-roster.js"
  if [ ! -f "$roster" ]; then
    note_fail "A7/e9 roster sidecar not emitted"
    return
  fi
  python3 - "$out" "$roster" <<'PY' || { note_fail "A7/e9 roster has personas not in rankings"; return; }
import json, sys, re
rows = [json.loads(l) for l in open(sys.argv[1])]
roster_text = open(sys.argv[2]).read()
m = re.search(r"window\.PERSONA_ROSTER\s*=\s*(\[.*?\]);", roster_text, re.S)
if not m:
    sys.stderr.write("A7/e9: cannot parse roster sidecar JSON\n")
    sys.exit(1)
roster_rows = json.loads(m.group(1))
roster_keys = {(r["persona"], r["gate"]) for r in roster_rows}
ranking_keys = {(r["persona"], r["gate"]) for r in rows}
never_run = roster_keys - ranking_keys
if not never_run:
    sys.stderr.write(
        "A7/e9: roster ({}) has zero personas absent from rankings ({}); "
        "expected at least one 'never run' persona\n".format(
            len(roster_keys), len(ranking_keys)
        )
    )
    sys.exit(1)
sys.exit(0)
PY
  note_pass "A7/e9 roster carries 'never run' personas (present in roster.js, absent from rankings)"

  # --scan-projects-root opt-in default-off.
  local out_off
  setup_env "a7-scan-off"
  out_off="$SANDBOX/rankings.jsonl"
  ( cd "$SANDBOX" && run_engine --out "$out_off" >"$SANDBOX/stderr.log" 2>&1 ) || {
    note_fail "A7 scan default-off invocation failed"
    cat "$SANDBOX/stderr.log" >&2
    return
  }
  python3 - "$out_off" <<'PY' || { note_fail "A7 --scan-projects-root opt-in default-off"; return; }
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1])]
have = {(r["persona"], r["gate"]) for r in rows}
if ("ambiguity", "spec-review") in have:
    sys.stderr.write("A7: ambiguity present without --scan-projects-root; opt-in default broken\n")
    sys.exit(1)
sys.exit(0)
PY
  note_pass "A7 --scan-projects-root opt-in default-off (no scan-flag → no beta rows)"
}

# ==========================================================================
# A8 — idempotent re-run (byte-equality excluding last_artifact_created_at)
# ==========================================================================
test_A8() {
  local out1 out2
  setup_env "a8"
  out1="$SANDBOX/rankings1.jsonl"
  out2="$SANDBOX/rankings2.jsonl"
  # cd into sandbox so cwd-tier-1 does NOT contaminate output across runs.
  if ! ( cd "$SANDBOX" && run_engine \
      --confirm-scan-roots "$FIXTURES_ROOT" \
      --scan-projects-root "$FIXTURES_ROOT" \
      --best-effort \
      --out "$out1" >"$SANDBOX/run1.log" 2>&1 ); then
    note_fail "A8 first run failed"
    cat "$SANDBOX/run1.log" >&2
    return
  fi
  if ! ( cd "$SANDBOX" && run_engine \
      --confirm-scan-roots "$FIXTURES_ROOT" \
      --scan-projects-root "$FIXTURES_ROOT" \
      --best-effort \
      --out "$out2" >"$SANDBOX/run2.log" 2>&1 ); then
    note_fail "A8 second run failed"
    cat "$SANDBOX/run2.log" >&2
    return
  fi
  # Strip last_artifact_created_at from each row (the documented volatile
  # field per §Idempotency contract) and compare.
  python3 - "$out1" "$out2" "$SANDBOX" <<'PY' || { note_fail "A8 byte-equality on stripped rows"; return; }
import json, sys, os
def strip(path, dst):
    with open(path) as fh, open(dst, "w") as out:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            row = json.loads(line)
            row.pop("last_artifact_created_at", None)
            out.write(json.dumps(row, sort_keys=True) + "\n")
out1, out2, sandbox = sys.argv[1], sys.argv[2], sys.argv[3]
s1 = os.path.join(sandbox, "stripped1.jsonl")
s2 = os.path.join(sandbox, "stripped2.jsonl")
strip(out1, s1)
strip(out2, s2)
b1 = open(s1, "rb").read()
b2 = open(s2, "rb").read()
if b1 != b2:
    sys.stderr.write("A8: stripped JSONL diverges across re-runs\n")
    # Surface a small diff hint.
    import difflib
    d = list(difflib.unified_diff(
        b1.decode().splitlines(), b2.decode().splitlines(),
        fromfile="run1", tofile="run2", lineterm=""))
    for line in d[:20]:
        sys.stderr.write(line + "\n")
    sys.exit(1)
sys.exit(0)
PY
  note_pass "A8 idempotent re-run (byte-equal after stripping last_artifact_created_at)"
}

# ==========================================================================
# A11 — outcome criterion + e12 fresh-install case
# ==========================================================================
test_A11() {
  local out
  if ! out="$(generate_baseline)"; then
    note_fail "A11 (baseline generation failed)"
    return
  fi
  python3 - "$out" "$ALPHA" "$BETA" <<'PY' || { note_fail "A11 ≥1 row per source (persona, gate) pair"; return; }
import json, sys, os, glob

out_path, alpha, beta = sys.argv[1], sys.argv[2], sys.argv[3]
rankings = [json.loads(l) for l in open(out_path)]
ranking_keys = {(r["persona"], r["gate"]) for r in rankings}

# Walk source findings.jsonl across both fixture roots. Map gate dir name
# (spec-review|plan|check) directly to the row's gate field.
source_keys = set()
for root in (alpha, beta):
    for f in glob.glob(os.path.join(root, "docs", "specs", "*", "*", "findings.jsonl")):
        gate = os.path.basename(os.path.dirname(f))
        if gate not in ("spec-review", "plan", "check"):
            continue
        with open(f) as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                row = json.loads(line)
                for p in row.get("personas") or []:
                    source_keys.add((p, gate))

missing = source_keys - ranking_keys
if missing:
    sys.stderr.write(
        "A11: rankings missing rows for source pairs: {}\n".format(sorted(missing))
    )
    sys.exit(1)
if not source_keys:
    sys.stderr.write("A11: source has no (persona, gate) pairs; precondition not met\n")
    sys.exit(1)
sys.exit(0)
PY
  note_pass "A11 ≥1 row per distinct (persona, gate) in source findings.jsonl[s]"

  # e12 — fresh install: no source data, no roster → empty rankings, exit 0.
  local out_e12
  setup_env "a11-e12"
  out_e12="$SANDBOX/rankings.jsonl"
  # Run from a sandbox cwd (no docs/specs/), no scan flag, empty HOME.
  if ! ( cd "$SANDBOX" && run_engine --out "$out_e12" >"$SANDBOX/stderr.log" 2>&1 ); then
    note_fail "A11/e12 fresh-install run did not exit cleanly"
    cat "$SANDBOX/stderr.log" >&2
    return
  fi
  if [ ! -f "$out_e12" ]; then
    note_fail "A11/e12 expected empty rankings file; not written"
    return
  fi
  if [ -s "$out_e12" ]; then
    note_fail "A11/e12 expected empty rankings; got non-empty"
    head -3 "$out_e12" >&2
    return
  fi
  note_pass "A11/e12 fresh-install: no source + no roster → empty JSONL, clean exit"
}

# --------------------------------------------------------------------------
# Run all tests in declared order.
# --------------------------------------------------------------------------
test_A1
test_A2
test_A3
test_A4
test_A7
test_A8
test_A11

echo ""
echo "test-compute-persona-value: $PASS_COUNT passed, $FAIL_COUNT failed, $SKIP_COUNT skipped"
if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
