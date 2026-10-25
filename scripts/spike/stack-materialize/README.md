# Spike: materialize a build as the plan's PR stack

Kept from the Red Rabbit `canon-resolution-and-world-isolation` build
(2026-10-02) for the `build-pr-stack-materialize` backlog item. Not wired into
any command or test; the steps are that project's.

The problem: `/build` commits by wave and task, while `design.md`'s PR stack
groups tasks differently. Publishing the stack meant reordering commits,
splitting one commit that spanned three PRs, and proving each PR's tip green
on its own.

What was done, and what these files are:

1. Rebuild in a separate `git worktree` from the remote base, cherry-picking
   commits in PR order and setting a `stack/pr-<n>` branch at each PR's tip.
2. `split_hunks.py <repo> <commit> <outdir>` splits a mixed commit into
   per-PR patches, by file and by hunk (hunks mixing both kinds are reported
   for hand-fixing). The remaining share of a split can then be applied by
   checking the original post-commit tree's files out, minus paths that move
   to a later PR.
3. `verify-cut.sh <label>` (with `STACK_WORKTREE`, `STACK_LOGS`) runs install,
   builds, typecheck, all tests, lints and the parity harness at one tip.
4. Assert the final tip's tree equals the tested branch tip
   (`git rev-parse <a>^{tree}` = `<b>^{tree}`), so the stack ships exactly the
   verified code.
5. Push the branches and open draft PRs, each based on the previous one; PR
   descriptions quote each tip's own verification logs.

Lessons: dependency declarations and test assertions that pin export lists
move with the first PR that needs them; fixes whose regression tests use later
fixtures belong in the PR that adds those fixtures; and a parity baseline that
embedded the recording machine's checkout path only failed once the stack was
built in a worktree.
