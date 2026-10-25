#!/usr/bin/env bash
# Verify one stack cut in the rebuild worktree: install, build libraries,
# typecheck, all tests (sqld required), lints, next lint, parity.
#   STACK_WORKTREE=<worktree> STACK_LOGS=<dir> verify-cut.sh <label>
# Prints one summary block; full logs under $STACK_LOGS/<label>-*.log.
#
# SPIKE: as used to rebuild the Red Rabbit canon-isolation PR stack
# (2026-10-02). The steps (pnpm, sqld, a parity harness, next lint) are that
# project's; a real version would read them from the project.
set -uo pipefail
LABEL="$1"
W="${STACK_WORKTREE:?set STACK_WORKTREE to the rebuild worktree}"
LOG="${STACK_LOGS:?set STACK_LOGS to a log directory}"
mkdir -p "$LOG"
cd "$W" || exit 2
# Never touch production: no Turso/KV/Vercel variables in this process tree.
unset TURSO_DATABASE_URL TURSO_AUTH_TOKEN KV_REST_API_URL KV_REST_API_TOKEN KV_URL REDIS_URL
export CANON_ACCESS_REQUIRE_SQLD=1
fail=0
step() { # name, command...
  local name="$1"; shift
  if "$@" > "$LOG/$LABEL-$name.log" 2>&1; then echo "  ok    $name"; else echo "  FAIL  $name  ($LOG/$LABEL-$name.log)"; fail=1; fi
}
echo "== $LABEL @ $(git rev-parse --short HEAD)"
step install pnpm install --frozen-lockfile
step build-libs pnpm -r --filter './packages/**' build
step typecheck pnpm -r typecheck
step test pnpm -r test
grep -hE '^ +Tests ' "$LOG/$LABEL-test.log" | sed 's/^/        /'
if ls scripts/lint/*.test.mjs >/dev/null 2>&1; then step lint-tests bash -c "node --test scripts/lint/*.test.mjs"; fi
if [ -f scripts/lint/canon-isolation-lint.mjs ]; then step isolation-lint node scripts/lint/canon-isolation-lint.mjs; fi
step next-lint bash -c 'cd apps/cms && ./node_modules/.bin/next lint'
if grep -q '"test:parity"' apps/cms/package.json; then
  step parity bash -c 'pnpm --filter @redrabbit/cms test:parity:build && pnpm --filter @redrabbit/cms test:parity'
  grep -hE '^ +Tests ' "$LOG/$LABEL-parity.log" | sed 's/^/        /'
fi
[ "$fail" -eq 0 ] && echo "== $LABEL GREEN" || echo "== $LABEL RED"
exit $fail
