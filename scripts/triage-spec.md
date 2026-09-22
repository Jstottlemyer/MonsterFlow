# Claude Code Release Triage Spec

Spec for the scheduled bi-weekly remote agent (cron `0 16 * * 5`, routine `trig_01FN2uy1oaebprAayQhSL82k`). The agent runs in Anthropic's cloud with a fresh checkout of `Jstottlemyer/MonsterFlow` and zero context — this file is the entire brief.

## Goal

Scan for new Claude Code surface area (built-in slash commands, hook events, plugin/skill capabilities) since the last triage and propose a policy update via PR. Justin reviews and merges.

## Step 1 — Skip-check (effective bi-weekly cadence)

**Tooling note — the cloud sandbox has no `gh`.** Verified 2026-09-22 in env `env_01YByf8LEituZXVfX9YAAJVn`: `which gh` returns nothing and `gh` is `command not found`. `gh` is the convention on Justin's laptop, NOT here. In this environment use `git` for branch/commit/push and the `mcp__github__*` tools for anything requiring the GitHub API (PR search, PR creation). Do not invoke `gh`; do not add an install step for it.

For the Step 1 skip-check call `mcp__github__search_pull_requests`:

```
owner: Jstottlemyer
repo:  MonsterFlow
query: repo:Jstottlemyer/MonsterFlow chore(triage): in:title
sort:  created   order: desc   perPage: 5
fields: number,title,created_at,merged_at,state
```

If any matching PR was created within the last 13 days, exit with the single message:

> Recent triage PR found, skipping this run.

Do not proceed past Step 1.

## Step 2 — Read current policy (the source of truth)

- `commands/flow-card.txt` → find the `BUILT-IN CC COMMANDS` footer block. Every command listed there is already triaged.
- `CLAUDE.md` (repo root) → find the `## Built-in Claude Code commands` paragraph. The policy stance is captured there.
- `settings/settings.json` → enumerate hook events the user already configures.
- `plugins.md` → installed plugin set (treat the names listed as the canonical roster).

## Step 3 — Scan for new surface area

Fetch and diff against Step 2. Sources, in order:

1. Claude Code changelog: try `https://docs.claude.com/en/release-notes/claude-code` first. Fall back to searching `https://docs.claude.com` if that 404s.
2. Commands reference: `https://code.claude.com/docs/en/commands.md` — extract every built-in slash command. Diff against the flow-card footer.
3. Hooks reference: `https://code.claude.com/docs/en/hooks.md` — extract every hook event type. Diff against `settings/settings.json`.
4. For each plugin in `plugins.md` (superpowers, context7, firecrawl, codex, vercel, code-review, ralph-loop, playwright), fetch its README from its public repo and capture *major* capabilities shipped in the last ~30 days. Skip patch-level changes.

For each new item, record: name, type (built-in command / hook event / plugin feature), one-sentence description, source URL, ship date if available.

## Step 4 — Propose policy

For each new item, choose exactly one:

- **USE** — wire into the pipeline. Specify which command (`/spec`, `/plan`, `/check`, `/build`, `/wrap`).
- **OPT-IN** — add behind a flag, like `/insights` is gated by `/wrap insights`.
- **AVOID** — document as off-pipeline (like `/ultraplan` — leaves terminal, no local artifact).
- **EDUCATIONAL** — mention in flow-card footer only, no integration (like `/powerup`).

Justify each in one sentence keyed to Justin's hard constraints, in priority order:

1. Stays in the terminal — no browser handoff.
2. Produces a local artifact when relevant (under `docs/specs/<feature>/` for pipeline work).
3. Does not duplicate an existing pipeline step.
4. Does not add approval-gate noise to `/wrap`.
5. Conservative bias — when in doubt, propose **OPT-IN** or **EDUCATIONAL**, never **USE**.

## Step 5 — Open a PR (or post no-op)

If zero new items: exit with the single message `No new Claude Code surface area since last triage.` Do not open a PR.

If one or more new items:

- Branch: `triage/YYYY-MM-DD-claude-code-release-scan` (use today's UTC date).
- **Append** lines to the `BUILT-IN CC COMMANDS` block in `commands/flow-card.txt`. Do NOT modify existing entries. Match the canonical 64-char box width — each new line MUST be exactly 64 total characters (`║` + 62 chars of content + `║`). Verify with:

  ```bash
  python3 -c "[print(i+1, len(l.rstrip())) for i,l in enumerate(open('commands/flow-card.txt'))]" | grep -v ' 64$' | grep -v ' 0$'
  ```

  Existing pre-triage anomalies at lines 2, 9, 65 (width 63) are pre-existing and must be left alone.
- Update the `## Built-in Claude Code commands` paragraph in `CLAUDE.md` (root) to reflect new policy. Keep it to 2–3 sentences total.
- Commit and push with `git`, then open the PR with `mcp__github__create_pull_request`:

  ```bash
  git checkout -b triage/YYYY-MM-DD-claude-code-release-scan
  git commit commands/flow-card.txt CLAUDE.md -m "chore(triage): claude-code release scan YYYY-MM-DD"
  git push -u origin triage/YYYY-MM-DD-claude-code-release-scan
  ```

  Then `mcp__github__create_pull_request` with `owner: Jstottlemyer`, `repo: MonsterFlow`, `base: main`, `head: triage/YYYY-MM-DD-claude-code-release-scan`.

  **If `git push` fails with a 403**, the Claude GitHub App is missing write access on the repo. Do NOT retry the push in a loop, and do NOT try `mcp__github__create_branch` or `mcp__github__push_files` as a fallback — they authenticate with the same installation token and return `403 Resource not accessible by integration` every time. This exact dead end burned three runs on 2026-09-22. Instead: STOP, and report (1) the verbatim stderr, (2) the local branch name, and (3) the commit SHA, so the work can be recovered from the run log.

  Note the repo is **public**, so a successful `git clone` / `git ls-remote` proves nothing about write access — public reads need no installation at all. Only the push is a real test.
- PR title `chore(triage): claude-code release scan YYYY-MM-DD`, body sections:
  - `## Findings` — one bullet per new item: name, type, proposed policy, one-line rationale.
  - `## Sources` — URLs scanned in Step 3. If a fetch failed, list it here with `(failed)`.
  - `## What changed` — file diffs summarized.
  - Footer line: `Generated by scheduled triage agent.`

## Hard constraints

- Do NOT modify `commands/design.md`, `commands/check.md`, `commands/build.md`, `commands/spec.md`, or any file under `personas/`.
- Do NOT change existing entries in the flow-card footer or the `CLAUDE.md` policy paragraph — append only.
- Do NOT break flow-card box alignment.
- Do NOT merge the PR yourself — leave it open for Justin to review.
- If `WebFetch` fails for any source, continue with the others and note the failed source in the PR body under `## Sources` rather than aborting the entire run.

## Cadence note

Cron fires every Friday at 16:00 UTC (9am PDT during DST, 8am PST otherwise). The Step 1 skip-check provides effective bi-weekly cadence — if the previous triage PR is younger than 13 days, this run no-ops. Never opens two triage PRs in the same fortnight.
