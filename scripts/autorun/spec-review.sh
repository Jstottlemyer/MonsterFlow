#!/bin/bash
# scripts/autorun/spec-review.sh
#
# Parallel spec-review: one claude -p per persona, all launched concurrently.
# No --add-dir: spec content is passed inline, keeping each call small and fast.
# Merges raw persona outputs into review-findings.md after all personas complete.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$REPO_DIR}"
source "$REPO_DIR/scripts/autorun/defaults.sh"

: "${SLUG:?SLUG must be set by run.sh}"
: "${QUEUE_DIR:?QUEUE_DIR must be set by run.sh}"
: "${ARTIFACT_DIR:?ARTIFACT_DIR must be set by run.sh}"
: "${SPEC_FILE:?SPEC_FILE must be set by run.sh}"

mkdir -p "$ARTIFACT_DIR"

REVIEW_DIR="$PROJECT_DIR/docs/specs/$SLUG/spec-review"
RAW_DIR="$REVIEW_DIR/raw"
mkdir -p "$RAW_DIR"

# ---------------------------------------------------------------------------
# DRY RUN stub
# ---------------------------------------------------------------------------
if [ "${AUTORUN_DRY_RUN:-0}" = "1" ]; then
  echo "[autorun] spec-review: DRY RUN — writing stub artifacts"
  cat > "$ARTIFACT_DIR/review-findings.md" <<'EOF'
# Spec Review Findings (DRY RUN)
**Verdict:** PASS WITH NOTES
**Note:** Dry-run stub.
EOF
  mkdir -p "$REVIEW_DIR"
  echo '{"status":"ok","mode":"dry_run"}' > "$REVIEW_DIR/run.json"
  exit 0
fi

AUTONOMY_DIRECTIVE="You are running in fully autonomous overnight mode. At every decision point, pick the safest reversible option and execute. If you find yourself about to write \"Should I\", \"Do you want\", \"Which approach\", \"Before I proceed\", \"Approve to proceed\" — stop. Delete the sentence. Make the call. Log your reasoning in the end-of-run summary. Do not ask for approval. Do not pause for user input. Proceed to writing all artifacts now."

SPEC_CONTENT="$(cat "$SPEC_FILE")"

# ---------------------------------------------------------------------------
# Resolve which personas to dispatch (account-type-agent-scaling)
#
# resolve-personas.sh reads ~/.config/monsterflow/config.json + rankings +
# per-feature lock to select a budget-bounded persona list. When the user
# hasn't configured a budget, the resolver emits the full on-disk roster
# (existing behavior — AC1 of the spec).
#
# Per spec AC #8 and plan §3/§4.2: AUTORUN aborts on resolver non-zero.
# No silent seed fallback. Operator must fix config and re-run.
# Kill switch for emergencies: MONSTERFLOW_DISABLE_BUDGET=1 (full roster).
# ---------------------------------------------------------------------------
RESOLVER_ERR="$(mktemp "${TMPDIR:-/tmp}/autorun-spec-review-resolver-XXXXXX.err")"
trap 'rm -f "$RESOLVER_ERR"' EXIT
RESOLVER_EXIT=0
SELECTED_RAW="$(bash "$REPO_DIR/scripts/resolve-personas.sh" spec-review \
                  --feature "$SLUG" --with-tier --emit-selection-json 2>"$RESOLVER_ERR")" \
  || RESOLVER_EXIT=$?
if [ "$RESOLVER_EXIT" -ne 0 ]; then
  echo "[autorun] spec-review: ERROR — resolver exited $RESOLVER_EXIT" >&2
  if [ -s "$RESOLVER_ERR" ]; then
    sed 's/^/  /' "$RESOLVER_ERR" >&2
  fi
  exit 1
fi
# Surface stale-tags warning (dynamic-roster-per-gate Slice 4): the resolver
# writes a one-line "[stale-tags] WARNING ..." to stderr when persona tag
# manifests look out of date relative to the on-disk roster. Mirror it in the
# autorun log so overnight runs leave a breadcrumb.
if [ -s "$RESOLVER_ERR" ]; then
  STALE_LINE="$(grep -m1 '^\[stale-tags\] WARNING' "$RESOLVER_ERR" 2>/dev/null || true)"
  if [ -n "$STALE_LINE" ]; then
    echo "[autorun] spec-review: $STALE_LINE"
  fi
fi
# Parse "<persona>:<tier>" lines from resolver stdout. Tier-aware dispatch
# (dynamic-roster-per-gate Slice 4): each line is either
#   <persona>:opus            → claude -p --model claude-opus-4-5
#   <persona>:sonnet          → claude -p --model claude-sonnet-4-6
#   codex-adversary           → bare (skipped here; run.sh handles Codex)
# A bare non-codex-adversary line is a resolver contract violation; halt.
SELECTED_PERSONAS=()
SELECTED_TIERS=()
while IFS= read -r line; do
  [ -z "$line" ] && continue
  if [ "$line" = "codex-adversary" ]; then
    continue
  fi
  case "$line" in
    *:*)
      persona_name="${line%%:*}"
      tier_name="${line#*:}"
      SELECTED_PERSONAS+=("$persona_name")
      SELECTED_TIERS+=("$tier_name")
      ;;
    *)
      echo "[autorun:spec-review] resolver emitted bare persona '$line'; expected '<persona>:<tier>' — refusing to dispatch" >&2
      exit 1
      ;;
  esac
done <<< "$SELECTED_RAW"

if [ "${#SELECTED_PERSONAS[@]}" -eq 0 ]; then
  echo "[autorun] spec-review: ERROR — resolver emitted zero Claude personas" >&2
  exit 1
fi

# Build persona-file list from the resolved names. Skip names whose file is
# missing (resolver should not produce these; defensive). spec-review uses
# personas/review/ on disk per CLAUDE.md gate→dir mapping.
PERSONA_FILES=()
PERSONA_TIERS=()
for idx in "${!SELECTED_PERSONAS[@]}"; do
  name="${SELECTED_PERSONAS[$idx]}"
  tier="${SELECTED_TIERS[$idx]}"
  pf="$REPO_DIR/personas/review/$name.md"
  if [ -f "$pf" ]; then
    PERSONA_FILES+=("$pf")
    PERSONA_TIERS+=("$tier")
  else
    echo "[autorun] spec-review: WARN — persona file missing: $pf" >&2
  fi
done

if [ "${#PERSONA_FILES[@]}" -eq 0 ]; then
  echo "[autorun] spec-review: ERROR — no persona files found for resolved set" >&2
  exit 1
fi

ALL_ON_DISK=()
for _f in "$REPO_DIR/personas/review/"*.md; do
  [ -f "$_f" ] && ALL_ON_DISK+=("$(basename "$_f" .md)")
done
DROPPED_PERSONAS=()
for _p in "${ALL_ON_DISK[@]}"; do
  _drop=1
  for _s in "${SELECTED_PERSONAS[@]}"; do [ "$_p" = "$_s" ] && _drop=0 && break; done
  [ "$_drop" -eq 1 ] && DROPPED_PERSONAS+=("$_p")
done
echo "[autorun] spec-review: resolver selected: ${SELECTED_PERSONAS[*]} | dropped: ${DROPPED_PERSONAS[*]:-none}"
echo "[autorun] spec-review: launching ${#PERSONA_FILES[@]} personas in parallel (timeout=${TIMEOUT_PERSONA}s each)"

# ---------------------------------------------------------------------------
# Launch all personas concurrently
# ---------------------------------------------------------------------------
PIDS=()
NAMES=()

for idx in "${!PERSONA_FILES[@]}"; do
  persona_file="${PERSONA_FILES[$idx]}"
  tier="${PERSONA_TIERS[$idx]}"
  persona="$(basename "$persona_file" .md)"
  NAMES+=("$persona")

  # Tier → model translation (dynamic-roster-per-gate Slice 4 canonical table).
  case "$tier" in
    opus)    model="claude-opus-4-5" ;;
    sonnet)  model="claude-sonnet-4-6" ;;
    *)
      echo "[autorun:spec-review] unknown tier '$tier' for persona '$persona'; expected 'opus' or 'sonnet'" >&2
      exit 1
      ;;
  esac

  USER_PROMPT="$(cat "$persona_file")

---

Review the following spec from your perspective above. Output your findings using your standard format (Critical Gaps / Important Considerations / Observations / Verdict).

## Spec

$SPEC_CONTENT"

  printf '%s' "$USER_PROMPT" | timeout "$TIMEOUT_PERSONA" claude -p \
    --dangerously-skip-permissions \
    --model "$model" \
    --system-prompt "$AUTONOMY_DIRECTIVE" \
    > "$RAW_DIR/$persona.md" \
    2>"$RAW_DIR/$persona.err" &

  pid=$!
  PIDS+=("$pid")
  echo "[autorun] spec-review: launched $persona [$tier→$model] (pid=$pid)"
done

# ---------------------------------------------------------------------------
# Wait for all — collect exit codes
# ---------------------------------------------------------------------------
FAILED=()
for i in "${!PIDS[@]}"; do
  pid="${PIDS[$i]}"
  persona="${NAMES[$i]}"
  exit_code=0
  wait "$pid" || exit_code=$?
  if [ "$exit_code" -eq 0 ]; then
    lines="$(wc -l < "$RAW_DIR/$persona.md" 2>/dev/null || echo 0)"
    echo "[autorun] spec-review: $persona done (${lines} lines)"
  else
    echo "[autorun] spec-review: $persona FAILED (exit $exit_code)"
    FAILED+=("$persona")
    if [ -s "$RAW_DIR/$persona.err" ]; then
      echo "[autorun] spec-review: $persona stderr:" && tail -5 "$RAW_DIR/$persona.err" | sed 's/^/  /'
    fi
  fi
done

if [ "${#FAILED[@]}" -gt 0 ]; then
  echo "[autorun] spec-review: WARN — ${#FAILED[@]} persona(s) failed: ${FAILED[*]}"
fi

# Abort if all personas failed
if [ "${#FAILED[@]}" -eq "${#PIDS[@]}" ]; then
  echo "[autorun] spec-review: ERROR — all personas failed; cannot produce review" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Merge raw outputs → review.md
# ---------------------------------------------------------------------------
REVIEW_MD="$REVIEW_DIR/review.md"
{
  echo "# Spec Review — $SLUG"
  echo ""
  echo "**Reviewed:** $(date +%Y-%m-%d)"
  echo "**Reviewers:** ${NAMES[*]}"
  echo ""
  for persona in "${NAMES[@]}"; do
    raw_file="$RAW_DIR/$persona.md"
    [ -f "$raw_file" ] || continue
    echo "---"
    echo ""
    echo "## $persona"
    echo ""
    cat "$raw_file"
    echo ""
  done
} > "$REVIEW_MD"

cp "$REVIEW_MD" "$ARTIFACT_DIR/review-findings.md"
echo "[autorun] spec-review: review-findings.md written ($(wc -l < "$ARTIFACT_DIR/review-findings.md") lines)"

# ---------------------------------------------------------------------------
# Gate: count Verdict: FAIL across all raw persona files
# ---------------------------------------------------------------------------
FAIL_COUNT=0
for persona in "${NAMES[@]}"; do
  raw_file="$RAW_DIR/$persona.md"
  [ -f "$raw_file" ] || continue
  if grep -qi "^Verdict: FAIL" "$raw_file" 2>/dev/null; then
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "[autorun] spec-review: FAIL verdict from $persona"
  fi
done

echo "[autorun] spec-review: FAIL verdict count=$FAIL_COUNT (threshold=$SPEC_REVIEW_FATAL_THRESHOLD)"

echo '{"status":"ok","personas":'"${#NAMES[@]}"',"failed":'"${#FAILED[@]}"',"fail_verdicts":'"$FAIL_COUNT"'}' \
  > "$REVIEW_DIR/run.json"

if [ "$FAIL_COUNT" -ge "$SPEC_REVIEW_FATAL_THRESHOLD" ]; then
  echo "[autorun] spec-review: threshold exceeded — halting item"
  exit 2
fi

echo "[autorun] spec-review: complete"
exit 0
