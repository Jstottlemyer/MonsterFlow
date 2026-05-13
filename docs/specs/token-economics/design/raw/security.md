# Security — token-economics plan

**Persona:** security
**Scope:** threat model + attack surface for a public-repo measurement system that reads private session JSONLs, private project paths, and committed redacted fixtures.
**Out of scope:** UI affordances (ux), perf (scalability).

## Key Considerations

**Trust boundaries** (in trust order, highest → lowest):
1. **Adopter's local files** under `~/.claude/projects/*` and discovered project roots — fully trusted as inputs, but contain prompts, finding bodies, file paths, project names. *They are the secret material.* Anything that escapes this boundary is the leak.
2. **Generated artifacts** `dashboard/data/persona-rankings.jsonl`, `dashboard/data/persona-roster.js` — gitignored, machine-local, but treated as *staging area for public exposure* because adopters screenshot the dashboard, copy-paste `/wrap-insights` text, and may accidentally `git add -f` them.
3. **Committed fixtures** `tests/fixtures/persona-attribution/*.jsonl` — public the moment the repo is public. **Strongest gate.**
4. **stderr/stdout of `compute-persona-value.py`** — third surface, often pasted into chat / issues / `/wrap` logs without thought.

**Adversary model** (who, what they gain, how):
- **Curious public-repo browser** — reads `tests/fixtures/persona-attribution/`, `git log`, dashboard screenshots in PRs/issues. Gains: knowledge of the adopter's project names, persona names, work patterns, model usage, costs. *Most likely actual attacker — passive recon at scale.*
- **Targeted social-engineering attacker** — wants to know which projects an adopter is working on, which clients (Luna's Pavers, RedRabbit, career), what hours they work (timestamps), what they're paying Anthropic. Combines rankings file with public profile.
- **Adopter accidentally publishing their own private data** — own foot, own gun. The system must make this hard.
- **Malicious config-file contributor** — someone with PR access who edits a fixture or adds a `~/Projects/` path entry that reads from a sensitive location. *Lower probability for a personal repo, real for a multi-contributor fork.*

**Blast radius (worst case, no mitigation):**
- Spec lets `compute-persona-value.py` walk arbitrary paths (config tier 2, scan flag tier 3) and read `findings.jsonl` rows that contain finding titles, bodies, file paths, persona-emitted prose. If those leak through stderr or fixture commits or rankings JSONL, **the attacker gets a snapshot of every gate the adopter has run on every project under those roots — including client repos under `~/Projects/clients/*` an unaware adopter pointed at.**
- Multi-machine: each machine's gitignored JSONL is isolated, but if an adopter ever does `git add -f dashboard/data/persona-rankings.jsonl` to share with a friend ("look at my numbers"), they leak the union of *every* `--scan-projects-root` they've ever run.

**Defense posture:** the privacy constraints **are** the security posture — there are no auth boundaries to harden, no secrets to rotate. The job is **input-side scope control + output-side allowlist + redaction pipeline correctness**, full stop.

## Options Explored (with pros/cons/effort)

### O1 — Allowlist schema for `persona-rankings.jsonl` + fixtures (A10) (S)

The core gate. Field-level allowlist enforced by `tests/test-allowlist.sh`. Below is the **concrete proposed allowlist**, derived from the spec's row schema with everything finding-content-derived stripped.

**ALLOWED fields in `dashboard/data/persona-rankings.jsonl` rows** (exhaustive — every other field rejected):

| Field | Type | Rationale |
|---|---|---|
| `schema_version` | int | Forward-compat marker; constant |
| `persona` | string | Roster name (e.g. `scope-discipline`) — public knowledge in `personas/` |
| `gate` | enum `{spec-review,plan,check}` | Public knowledge |
| `runs_in_window` | int | Aggregate count; no path/title content |
| `window_size` | int | Constant 45 |
| `run_state_counts` | object<state,int> | State enum + counts only |
| `total_emitted` | int | Aggregate count |
| `total_judge_retained` | int | Aggregate count |
| `total_downstream_survived` | int | Aggregate count |
| `total_unique` | int | Aggregate count |
| `total_tokens` | int | Aggregate count (cost) |
| `judge_retention_ratio` | float\|null | Derived rate |
| `downstream_survival_rate` | float\|null | Derived rate |
| `uniqueness_rate` | float\|null | Derived rate |
| `avg_tokens_per_invocation` | float | Derived rate |
| `last_seen` | ISO-8601 UTC string | Source = `MAX(run.json.created_at)`; **truncated to date-hour** (see O3) |
| `persona_content_hash` | string `sha256:<64hex>` \| null | Hash of public file under `personas/` — safe |
| `window_start_artifact_dir` | string | **REJECTED** — see below |
| `contributing_finding_ids` | array<string> ≤50 | sha256-derived finding IDs (see O5) |
| `truncated_count` | int | Aggregate |
| `insufficient_sample` | bool | Derived flag |

**Field needing change from spec:** `window_start_artifact_dir` is currently spec'd as a path. *That's a leak.* It contains adopter's project name + feature name + gate name. **Replace with `window_start_artifact_dir_hash` (sha256 of absolute path, salted)** OR drop the field entirely — its only use is debugging idempotency, and the (persona, gate) pair already identifies the row. **Recommendation: drop `window_start_artifact_dir`; keep nothing path-derived.**

**REJECTED in fixtures + rankings (explicit denylist for clarity, even though allowlist is the actual gate):** any field name matching `prompt`, `text`, `body`, `content`, `title`, `description`, `summary`, `path`, `file`, `cwd`, `note`, `comment`, `quote`, `context`, `excerpt`, `snippet`, `message`, `email`, `name` (when not in allowlist), `project`, `feature`, `repo`, `branch`, `user`, `author`, `cluster_label`, `normalized_signature`, anything ending in `_path` or `_text`.

**ALLOWED fields in `tests/fixtures/persona-attribution/*.jsonl`** (separate, narrower allowlist — fixture is parent-session JSONL excerpts for spike replay, not rankings rows):

| Field | Notes |
|---|---|
| `type` (`assistant`/`tool_use`/`tool_result`) | Structural |
| `agentId` | 16-hex linkage ID — opaque |
| `tool_use_id` | opaque ID |
| `parent_session_uuid` | UUID — already in path though, see fixture filename rule |
| `model` | e.g. `claude-opus-4-7` — public model name |
| `usage` (object: `input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens`) | Pure ints |
| `duration_ms` | Pure int |
| `tool_uses` (count) | Pure int |
| `total_tokens` | Pure int |
| `persona_path` | **MUST match regex** `^personas/(spec-review\|plan\|check)/[a-z0-9-]+\.md$` — only the public roster path |
| `gate` | enum |
| `timestamp` | **truncated to date-hour** before commit |

**Fixture filename rule:** files MUST be named `gate-<gate>-persona-<persona>-<seq>.jsonl` — no UUIDs, no project names. The `parent_session_uuid` field inside is allowed for linkage testing but is itself opaque (not the on-disk filename).

- Pros: deny-by-default, schema-anchored, future-proof against new finding-content fields, satisfies blocker #5 from review.
- Cons: need to maintain when v1.1 adds fields; one extra schema file.
- Effort: S.

### O2 — `safe_log()` wrapper contract (S)

A single helper in `compute-persona-value.py`. **All stderr/stdout goes through it; raw `print()` and `sys.stderr.write()` are banned by lint** (grep gate in test).

**Contract:**

```python
def safe_log(event: str, **counts_only: int | str) -> None:
    """
    event: a fixed enum string from SAFE_EVENTS (compile-time set).
    counts_only kwargs: int values, or string values matching SAFE_VALUE_PATTERNS:
        - persona name (matches ^[a-z0-9-]+$, must be in current roster)
        - gate (matches ^(spec-review|plan|check)$)
        - run_state enum value
        - sha256 hex (matches ^sha256:[0-9a-f]{64}$)
        - integer counts
        - ISO date (no time)
    Anything else raises at call site (caught by tests).
    """
```

**SAFE_EVENTS (the exhaustive set — adding new events requires PR + allowlist test update):**
- `discovered_projects` — emits count only, NOT paths. (Telemetry line replacement: `[persona-value] discovered N projects (sources: cwd, config:M, scan:K)` — counts per source, not paths. **This contradicts the spec's "<path>, <path>, …" telemetry line — flag as integration with adopter UX.**)
- `malformed_artifact` — emits `gate=`, `persona=`, run_state, **NOT path**. To debug, adopter re-runs with `--debug-paths` env var which logs paths to local-only `~/.cache/monsterflow/debug.log` (gitignored, not part of stderr capture).
- `missing_artifact` — same shape.
- `window_rolled` — persona, gate, count.
- `wrote_rankings` — row count only.
- `truncated_finding_ids` — persona, gate, truncated_count.

**Banned:** any `print(f"... {path} ...")`, any logging of `finding.title`, any logging of file contents.

- Pros: forces structural discipline; canary test in A10 catches regressions.
- Cons: slightly less convenient debugging — but `--debug-paths` env escape valve handles it.
- Effort: S.

### O3 — Timestamp truncation (S)

Spec stores `last_seen` as full ISO-8601 (`2026-05-02T18:14:00Z`). That's a **work-pattern leak** — combined with persona+gate, an attacker can profile when an adopter works.

**Recommendation:** truncate to **date-hour** (`2026-05-02T18:00:00Z`) for `last_seen` in rankings JSONL AND in committed fixtures. Idempotency is unaffected (round to hour bucket). Sub-hour granularity has no analytical value for a 45-window aggregate.

- Pros: cheap, removes a real signal.
- Cons: minor info loss; very last-write-wins races within an hour become indistinguishable (already last-writer-wins per spec).
- Effort: S.

### O4 — Project Discovery: scan dry-run + allowlist confirmation (M)

The spec correctly opt-in-flips `~/Projects/*` scan. But `--scan-projects-root ~/Projects` is *one flag away* from scanning client repos. Adopters who type it once won't realize their Luna's Pavers folder, career repo, etc., are now being read.

**Recommendation:** add `--scan-projects-root <dir>` two-step affordance:

1. **Dry-run by default on first use:** if `~/.config/monsterflow/scan-roots.confirmed` does not contain `<dir>`, the script:
   - Walks `<dir>/*/docs/specs/` and **prints the discovered project root list to stderr** (paths allowed here — this is interactive bootstrap, not steady-state telemetry).
   - Refuses to read any `findings.jsonl` content.
   - Prompts: "Confirm scan of these N roots? Append to `scan-roots.confirmed`? [y/N]"
   - On `y`: append `<dir>\n` to `scan-roots.confirmed` (chmod 600).
   - On `N` or non-tty: exit 0 with instructions.
2. **Subsequent runs** with the same `--scan-projects-root` arg skip the prompt (the dir is in `scan-roots.confirmed`).
3. Adopter can also pre-populate `scan-roots.confirmed` manually (documented).
4. **Per-project opt-out file:** any project root containing `.monsterflow-no-scan` (a zero-byte sentinel file) is silently excluded from cascade tier 3. Documented for client-confidential repos.

`--scan-projects-root` invoked from `dashboard-append.sh` / non-interactive contexts: **never auto-confirms**; if not in `scan-roots.confirmed`, log `[persona-value] scan-roots not confirmed; skipping <count> roots` (count only, per O2) and proceed with cwd + config tiers.

- Pros: friction-aligned with risk; one-time confirmation per dir; opt-out sentinel is dead-simple.
- Cons: extra file under `~/.config/monsterflow/`; first-run interactivity (mitigated by non-tty fallback).
- Effort: M.

### O5 — `contributing_finding_ids[]` salted hash (S)

Spec: `sr-9a4b1c2d8e` style IDs are sha256-derived from `normalized_signature`. **Threat:** `normalized_signature` is the finding's title-ish text. An attacker who can guess plausible finding titles ("missing rate-limit", "no input validation", "use sql parameterization") can rainbow-table the IDs and confirm whether a given adopter's project produced that finding. Low-value for most cases, real for high-stakes targeted recon.

**Recommendation:** **per-machine salt** for finding IDs in the public allowlist surface.
- On first `compute-persona-value.py` run, generate `~/.config/monsterflow/finding-id-salt` (256-bit random, chmod 600).
- IDs in `dashboard/data/persona-rankings.jsonl` = `sha256(salt || normalized_signature)[:10]` prefixed with gate.
- Salt is **machine-local**, never in JSONL, never in fixtures.
- Fixtures use a **fixed test salt** baked into the test runner — not the same as production salt.
- Cross-machine: IDs no longer match across machines. *That's fine* — drill-down is a single-machine feature anyway (machine-local JSONL).

- Pros: kills the rainbow-table attack; matches threat-vs-utility tradeoff.
- Cons: cross-machine ID stability lost (it wasn't a documented feature anyway); one extra secret file.
- Effort: S.

### O6 — Path-traversal hardening for config tier 2 (S)

Spec tier 2: `${XDG_CONFIG_HOME:-$HOME/.config}/monsterflow/projects`, "one absolute path per line." If an adversary writes `..` / symlink-laden / non-absolute entries, `compute-persona-value.py` could be steered into reading `/etc/`, `/var/db/`, etc., looking for `docs/specs/*/` — unlikely to match much but path strings flow through `safe_log()` and could leak in error messages.

**Recommendation:** strict input validation in tier 2 reader:
- Reject lines that don't start with `/` (must be absolute).
- Reject lines containing `..` segment after normalization.
- After `Path(line).resolve()`, **reject if not under `$HOME`** (configurable allowlist of root prefixes, default `$HOME` only).
- Reject if resolved path is a symlink OR if any parent component is a symlink that escapes `$HOME` (use `Path.resolve(strict=True)` then re-check `is_relative_to($HOME)`).
- Log rejections via `safe_log("rejected_config_entry", reason=…)` — reason is enum, not the path.

Same validation for `--scan-projects-root <dir>` arg.

- Pros: defense-in-depth; closes path-traversal class.
- Cons: power users with intentional `/Volumes/external-ssd/projects/` will need to set `MONSTERFLOW_ALLOWED_ROOTS=/Volumes/external-ssd:$HOME` env var. Document.
- Effort: S.

### O7 — Worktree symlink containment (S)

Spec dedupes via absolute `realpath`. Threat: symlink farm under an opted-in scan root pointing **outside** the intended scope (e.g., adopter creates `~/Projects/old → /Users/shared/clientwork/`). Realpath dedup *follows* the symlink, which is exactly what the attack wants.

**Recommendation:**
- After `Path(candidate).resolve()`, apply the same "must be under allowed roots" check as O6.
- Worktrees specifically: detect git-worktree `.git` files (not dirs), follow to canonical, but **only accept** if both the worktree's display path AND its canonical path are under allowed roots.
- Reject (with `safe_log("rejected_symlink_escape", …)`) anything that escapes.

- Pros: closes the realpath-follow attack.
- Cons: minor; legitimate cross-volume worktrees need `MONSTERFLOW_ALLOWED_ROOTS`.
- Effort: S.

### O8 — Pre-commit hook + CI for fixture allowlist (S)

A10 covers the test, but tests don't run on `git commit` by default. An adopter who edits a fixture and force-commits past the test gate ships the leak.

**Recommendation:**
- Add `tests/test-allowlist.sh` to `tests/run-tests.sh` (already implied by spec).
- Document and ship a `scripts/install-precommit-hooks.sh` that wires a pre-commit hook running `tests/test-allowlist.sh` whenever `tests/fixtures/persona-attribution/**` or `dashboard/data/**` (defense-in-depth — gitignored but `-f` happens) are staged.
- CI workflow (if present) runs the same gate. **For this repo specifically, since `autorun-shell-reviewer` is the existing review subagent, add `allowlist-fixture-reviewer` to the build-stage subagent pool to read every fixture diff.** *Optional — pre-commit + test gate may suffice.*

- Pros: prevents the "I forgot to run tests" leak.
- Cons: hook setup is opt-in for adopters (acceptable — repo owner runs it).
- Effort: S.

## Recommendation

**Adopt all of O1–O7 in v1.** O8 ship as docs + script, hook install is opt-in.

**Build order:**
1. **O1** (allowlist schema) and **O2** (`safe_log()`) first — they gate everything else. Write `schemas/persona-rankings.allowlist.json` with the field set above (including the **drop `window_start_artifact_dir`** change). Write `safe_log()` with the SAFE_EVENTS enum. Write `tests/test-allowlist.sh`.
2. **O3** (timestamp truncation) — one-line change in the row writer, one-line change in the fixture redactor.
3. **O5** (salted finding IDs) — `~/.config/monsterflow/finding-id-salt` generation + use in ID hashing.
4. **O6 + O7** (path-traversal + symlink containment) — shared validator function `validate_project_root(path) -> Path | None`.
5. **O4** (scan dry-run + opt-out sentinel) — `scan-roots.confirmed` file + interactive prompt + `.monsterflow-no-scan` sentinel.
6. **O8** (pre-commit + reviewer) — last; documentation-heavy.

**Spec deltas to flag for /plan synthesis:**
- **Drop `window_start_artifact_dir` field** (or hash-and-salt it). Spec's current path-on-row leaks adopter project structure.
- **Truncate `last_seen` to hour granularity** in both rankings JSONL and fixtures.
- **Telemetry line in §Project Discovery** currently spec'd as `(sources: cwd, config, scan)` with paths → **change to counts only** to honor `safe_log()`. Paths only emitted in interactive `--scan-projects-root` confirmation prompt and behind `--debug-paths` env.
- **Per-machine salt for `contributing_finding_ids[]`** — minor schema clarification on the ID format.
- **`scan-roots.confirmed` + `.monsterflow-no-scan`** are new adopter-facing files — mention in §Project Discovery.

## Constraints Identified

1. **Public-repo-week deadline:** O1 + O2 + O8 (test gate) MUST be in the v1 ship; everything else can be follow-up patches but should be in too — they're all small.
2. **Idempotency contract** (A8) must include the truncated timestamp + dropped path field; otherwise diff-stable invariant breaks. Update §Idempotency contract diff-stable list.
3. **Multi-machine semantics** unchanged; salted IDs reinforce machine-locality (good).
4. **Dashboard rendering** must not display `window_start_artifact_dir` (since dropped) — UX integration point.
5. **Fixture filename convention** locks adopters out of one-off "let me drop this real session in to debug" — they MUST run `scripts/redact-persona-attribution-fixture.py` first. *Document loudly.*
6. **`safe_log()` ban on raw `print()`** is enforced by grep test; new contributors will hit it. Document in `CONTRIBUTING.md` (new) or `CLAUDE.md`.
7. **Hooks/CI for allowlist** — `tests/run-tests.sh allowlist` should be runnable standalone.

## Open Questions

1. **Does the dropped `window_start_artifact_dir` break any v1 functionality the dashboard or `/wrap-insights` text actually uses?** UX persona owns this — flag for synthesis. (Best guess: no; it was a debug field.)
2. **Should `--debug-paths` env be `MONSTERFLOW_DEBUG_PATHS=1` or a CLI flag?** Env var is harder to accidentally enable in scripts. Recommend env.
3. **Per-machine finding-ID salt — what's the rotation story if the salt file leaks?** Probably "regenerate, drill-down breaks for old rows, doesn't matter." Documented behavior, no code.
4. **Is `tests/fixtures/persona-attribution/` actually needed in the public repo, or can it move to a private fixture repo referenced in `.gitignore` with a generation script?** Most secure option; weighs against test-portability. **Recommendation: stay public + allowlist-enforced** (matches spec's existing decision), but flag for `/plan` synthesis if the security/ops trade is worth revisiting.
5. **`autorun-shell-reviewer` precedent — do we want an `allowlist-fixture-reviewer` subagent?** Optional in O8. Defer to /plan synthesis based on operations persona's read.

## Integration Points with other dimensions

- **architecture:** `safe_log()` is a small singleton in `compute-persona-value.py`; `validate_project_root()` is a shared util. New module `scripts/_security.py` (or inline) — architecture decides placement. The path-validation + salted-ID helpers are reusable across the Python scripts; consider whether `redact-persona-attribution-fixture.py` shares them.
- **data:** allowlist schema (`schemas/persona-rankings.allowlist.json`) IS the data contract. Any new field added in v1.1 means an allowlist PR + test update. Schema versioning aligns with the existing `schema_version: 1` field.
- **scalability:** path validation adds O(roots) syscalls; negligible. Salted ID hashing is one extra sha256 per ID — negligible. No perf impact.
- **ux:** **dashboard warning banner is already in spec** but should also note "this machine's data is salted — IDs won't match other machines' rankings." Also: scan dry-run prompt is interactive UX; needs a non-tty docs path. The dropped `window_start_artifact_dir` removes a debug column from the dashboard table.
- **operations:** `~/.config/monsterflow/{projects,scan-roots.confirmed,finding-id-salt,README.md}` are now four adopter-facing files. `install.sh` should create the README + chmod 600 the salt; also document `.monsterflow-no-scan` sentinel for client-repo opt-out. `scripts/install-precommit-hooks.sh` is new install affordance.
- **observability:** `safe_log()` SAFE_EVENTS list IS the observability surface. Anything not in SAFE_EVENTS needs a security-review PR. The `--debug-paths` escape hatch logs to `~/.cache/monsterflow/debug.log` (new path; gitignored implicitly because outside repo).
- **testing:** `tests/test-allowlist.sh` (already in spec) covers O1+O2. **New tests needed:** `tests/test-path-validation.sh` (O6+O7 — fixtures with symlinks escaping `$HOME`, `..` segments, non-absolute entries), `tests/test-scan-confirmation.sh` (O4 — non-tty mode, pre-confirmed roots, sentinel files), `tests/test-finding-id-salt.sh` (O5 — same input + different salts → different IDs; salt file perms = 600).

**Complexity rollup: M overall** (S parts, but 7 of them with cross-cutting wiring to scripts + tests + adopter docs + install.sh).
