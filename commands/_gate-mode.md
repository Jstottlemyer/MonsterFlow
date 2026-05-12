# Gate Mode — Shared Reference (v0.9.0+)

Canonical reference for CLI flag parsing, mode resolution, banner emission, and
audit-log row format. The interactive gate commands (`/spec-review`, `/design`,
`/check`) reference this file in their prose so Claude reads it once and applies
the rules consistently.

This file is **prose reference**, not a prompt. Gate commands tell Claude:
> "Read `commands/_gate-mode.md` and apply the rules below."

The wording in this file is **canonical** — banner strings, error strings, JSONL
field names, and sentinel paths are copy-paste-ready and **lock at v0.9.0** per
spec O3 (open question: banner wording stability).

The classification precedence used by every gate is:

`architectural > security > unclassified > contract > tests > documentation > scope-cuts`

This precedence string is the single source of truth and matches `personas/judge.md`.

---

## 1. Frontmatter fields read at gate entry

Each spec's `docs/specs/<feature>/spec.md` may declare ONE YAML frontmatter
field that governs gate behavior:

| field | type | default | purpose |
|---|---|---|---|
| `gate_mode` | `permissive \| strict` | `permissive` | classification routing for this spec |

`gate_mode: permissive` (or absent → defaults to permissive at v0.9.0+):
- Only `architectural`, `security`, and `unclassified` findings halt the gate.
- `contract`, `tests`, `documentation`, `scope-cuts` route to `followups.jsonl`.

`gate_mode: strict`:
- Any reviewer must-fix → NO_GO (v0.8.x halt-on-anything behavior).

**`gate_max_recycles`** (DEPRECATED 2026-05-09): the per-gate re-cycle ceiling
is hardcoded to `3`, matching `build_max_retries` and `SECURITY_MAX_FIX_ATTEMPTS`
(the uniform "3 attempts before halt" pipeline contract). The
`gate_max_recycles_clamp` helper still resolves to `3` for caller ABI
compatibility but ignores any frontmatter value (emits a one-time deprecation
warning per spec). Strip `gate_max_recycles` from new spec frontmatter — the
field carries no runtime effect.

---

## 2. CLI flags accepted by `/spec-review`, `/design`, `/check`

| flag | effect |
|---|---|
| `--strict` | Force strict mode for this run (overrides `gate_mode: permissive` and absent frontmatter). |
| `--permissive` | Force permissive mode for this run. **Cannot** override `gate_mode: strict` — see `--force-permissive`. |
| `--force-permissive="<reason>"` | The **only** way to override `gate_mode: strict` frontmatter. Reason string is **REQUIRED** (per /check security observation OQ1). Audit-logged. |

Flag parsing rules:
- `--strict` and `--permissive` together → ambiguity error (exit 2).
- `--strict` and `--force-permissive` together → ambiguity error (exit 2).
- `--permissive` against `gate_mode: strict` frontmatter → rejection error (exit 2).
- `--force-permissive` with no reason (or empty reason) → rejection error (exit 2).
- `--force-permissive` when `$CI` or `$AUTORUN_STAGE` is truthy → rejection error
  (exit 2). The audit trail must come from a human at the keyboard, not autorun.

---

## 3. Mode resolution truth table (24 cells)

The Cartesian product of `{frontmatter: absent, permissive, strict}` × `{flags:
none, --strict, --permissive, --force-permissive=X, --strict --permissive,
--strict --force-permissive}` is **24 cells**. All listed below — no row
abbreviated.

| frontmatter | CLI flags | active mode | mode_source | gate behavior | side effects |
|---|---|---|---|---|---|
| absent | (none) | permissive | `default` | permissive | per-user banner once + per-spec banner once |
| absent | `--strict` | strict | `cli` | strict | none |
| absent | `--permissive` | permissive | `cli` | permissive | none (explicit opt-in suppresses default-flip banner) |
| absent | `--force-permissive="X"` | permissive | `cli-force` | permissive | append `.force-permissive-log` row + 4-line warning to stderr |
| absent | `--strict --permissive` | (error) | (n/a) | exit 2 | print ambiguity error |
| absent | `--strict --force-permissive="X"` | (error) | (n/a) | exit 2 | print ambiguity error |
| permissive | (none) | permissive | `frontmatter` | permissive | none |
| permissive | `--strict` | strict | `cli` | strict | none |
| permissive | `--permissive` | permissive | `cli` | permissive | none (redundant but allowed) |
| permissive | `--force-permissive="X"` | permissive | `cli-force` | permissive | append `.force-permissive-log` row + 4-line warning (NOTE: redundant on permissive frontmatter — flag still audits) |
| permissive | `--strict --permissive` | (error) | (n/a) | exit 2 | print ambiguity error |
| permissive | `--strict --force-permissive="X"` | (error) | (n/a) | exit 2 | print ambiguity error |
| strict | (none) | strict | `frontmatter` | strict | none |
| strict | `--strict` | strict | `cli` | strict | none (redundant but allowed) |
| strict | `--permissive` | (error) | (n/a) | exit 2 | print rejection error (`--permissive cannot override a strict-flagged spec`) |
| strict | `--force-permissive="X"` | permissive | `cli-force` | permissive | append `.force-permissive-log` row + 4-line warning to stderr |
| strict | `--strict --permissive` | (error) | (n/a) | exit 2 | print ambiguity error |
| strict | `--strict --force-permissive="X"` | (error) | (n/a) | exit 2 | print ambiguity error |
| absent | `--force-permissive` (no reason) | (error) | (n/a) | exit 2 | print rejection error (reason required) |
| permissive | `--force-permissive` (no reason) | (error) | (n/a) | exit 2 | print rejection error (reason required) |
| strict | `--force-permissive` (no reason) | (error) | (n/a) | exit 2 | print rejection error (reason required) |
| absent | `--force-permissive="X"` + `$CI=true` | (error) | (n/a) | exit 2 | print rejection error (CI/autorun forbids force) |
| permissive | `--force-permissive="X"` + `$CI=true` | (error) | (n/a) | exit 2 | print rejection error (CI/autorun forbids force) |
| strict | `--force-permissive="X"` + `$CI=true` | (error) | (n/a) | exit 2 | print rejection error (CI/autorun forbids force) |

`mode_source` values are recorded in the verdict sidecar (`verdict.json`) so
post-mortem readers can reconstruct **why** the gate ran in the mode it did.

---

## 4. Truthy-value whitelist for `$CI` and `$AUTORUN_STAGE`

(Per /check risk S1.)

`$CI` is "set to a truthy value" iff the value is in the whitelist:

`{true, 1, yes, TRUE, YES}`

Any other value — including `CI=false`, `CI=0`, `CI=""`, or `CI` unset — is
**NOT-CI**. Same whitelist applies to `$AUTORUN_STAGE`.

`--force-permissive` refuses (exit 2) if **either** env-var is truthy. The
forbidding is intentional: the audit trail (`.force-permissive-log`) is only
auditable when a human typed the reason. Letting autorun set the reason
launders the trail.

Rationale: a future operator running `CI=false ./script.sh` should not be
treated as in-CI — but `CI=true ./script.sh` (the GitHub Actions default) must
be. The whitelist is conservative-permissive: rejects ambiguity ("yeah",
"sure", "on") and accepts only the documented values.

---

## 5. Banner suppression sentinels

Four sentinel files govern banner emission. All are zero-byte touches. The
`v0.9.0` suffix on the per-user default-flip sentinel is intentional — a future
default change (e.g., adding an `unclassified` axis to the halt set) bumps the
suffix, re-firing the banner once.

| sentinel path | scope | fires when | banner |
|---|---|---|---|
| `~/.claude/.gate-mode-default-flip-warned-v0.9.0` | per-user, per-version | first gate run with absent frontmatter on this machine since v0.9.0 | verbose ~5-line explanation |
| `docs/specs/<feature>/.gate-mode-warned` | per-spec, per-session | absent frontmatter, AFTER per-user has fired | one-line nudge |
| `docs/specs/<feature>/.recycles-deprecated` | per-spec, per-session | spec frontmatter still pins `gate_max_recycles` (DEPRECATED 2026-05-09; ignored) | one-line nudge |
| `~/.claude/.gate-permissiveness-migration-shown` | per-user, one-shot | fired once by `install.sh` upgrade path | install-time migration notice |

Per-spec sentinels live inside `docs/specs/<feature>/` so a `git clean -fdx` of
that spec's directory resets per-spec state without touching machine-global
state. Per-spec sentinels are NOT gitignored — but they're zero-byte and rare.

---

## 6. Banner wording (canonical, locked at v0.9.0)

These strings are **copy-paste exact**. Do not paraphrase. Banner output goes
to **stderr** (so it doesn't pollute stdout pipelines).

### 6.1 Per-user verbose banner

Emitted when `~/.claude/.gate-mode-default-flip-warned-v0.9.0` does **not**
exist:

```
[gate] First gate run on v0.9.0+ — pipeline gate defaults changed.
[gate]
[gate]   v0.8.x: any reviewer must-fix → NO_GO (halt-on-anything)
[gate]   v0.9.0: only architectural/security/unclassified findings halt;
[gate]           contract/docs/tests/scope-cuts route to followups.jsonl
[gate]
[gate] To preserve old behavior on a spec, add to its frontmatter:
[gate]   gate_mode: strict
[gate]
[gate] CHANGELOG: docs/CHANGELOG.md#v0.9.0
[gate] (this banner shows once per machine; per-spec hint shows once per spec)
```

After emission, `touch ~/.claude/.gate-mode-default-flip-warned-v0.9.0`.

### 6.2 Per-spec one-liner

Emitted when the per-user sentinel **already exists** and absent frontmatter is
detected and `docs/specs/<feature>/.gate-mode-warned` doesn't exist for this
session:

```
[gate] <feature>: no gate_mode pinned — running permissive (default).
```

After emission, `touch docs/specs/<feature>/.gate-mode-warned`.

### 6.3 `--force-permissive` warning (4 lines to stderr)

Emitted whenever `--force-permissive="<reason>"` resolves successfully (i.e.,
mode_source becomes `cli-force`):

```
[gate] WARNING: --force-permissive overriding gate_mode: strict on <spec-path>.
[gate]          Audit row appended to docs/specs/<feature>/.force-permissive-log
[gate]          Verdict will record mode_source: cli-force.
[gate]          architectural / security / unclassified findings still block.
```

`<spec-path>` is the literal path (e.g., `docs/specs/foo/spec.md`).

### 6.4 `--permissive` rejection on strict frontmatter (exit 2)

```
ERROR: spec docs/specs/<feature>/spec.md declares gate_mode: strict.
       --permissive cannot override a strict-flagged spec.
       To proceed anyway, re-run with --force-permissive="<reason>" (audit-logged to docs/specs/<feature>/.force-permissive-log).
```

### 6.5 `--strict --permissive` ambiguity (exit 2)

```
ERROR: ambiguous flags: --strict and --permissive given together.
```

The same ambiguity error applies to `--strict --force-permissive` — the message
text is the same except substitute `--force-permissive` for `--permissive`.

### 6.6 `cap_reached AND verdict: NO_GO` next-steps (2 options + recommendation)

(Per ux Option E.) Emitted when the gate hits the hardcoded cap (3) AND still has
unresolved blocking findings:

```
[gate] Re-cycle cap reached (cap=3, hardcoded). <K> architectural finding(s) remain:
[gate]   <ck-id>: <persona> — <title>
[gate]
[gate] Next steps (pick one):
[gate]   1. Address inline:    edit spec.md, re-run /<gate>
[gate]   2. Force-permissive:  /<gate> <feature> --force-permissive="<reason>" (audited)
[gate]
[gate] Recommended: option 1 — architectural findings rarely improve on iteration.
```

`<gate>` is one of `spec-review`, `plan`, `check`. `<N>` is the active cap
(post-clamp). `<K>` is the remaining-blocker count. List one line per remaining
blocker (so 3 blockers = 3 finding lines between header and blank).

---

## 7. `.force-permissive-log` JSONL row format

One row per `--force-permissive` invocation, appended to
`docs/specs/<feature>/.force-permissive-log`:

```jsonl
{"timestamp": "<ISO-8601 UTC>", "iteration": <int>, "gate": "<spec-review|plan|check>", "user": "<git config user.email>", "spec": "<feature-name>", "verdict_sidecar": "<path-to-verdict.json>", "reason": "<--force-permissive value>"}
```

Field reference:

| field | type | source |
|---|---|---|
| `timestamp` | string | ISO-8601 UTC, e.g. `2026-05-05T17:30:00Z` |
| `iteration` | integer | gate's current re-cycle counter (1-indexed) |
| `gate` | string | one of `spec-review`, `plan`, `check` |
| `user` | string | `git config user.email` (best-effort; empty string if unset) |
| `spec` | string | feature slug (basename of `docs/specs/<feature>/`) |
| `verdict_sidecar` | string | relative path to the `verdict.json` this run produced |
| `reason` | string | the verbatim `--force-permissive="<reason>"` value (truncate at 500 chars) |

**Important:** `.force-permissive-log` is **NOT gitignored** (per /check
security S2 — the audit trail is the auditable artifact). If it's gitignored,
the audit trail can be silently destroyed by `git clean -fdx`. Keep it tracked.

---

## 8. Verdict sidecar fields (downstream of mode resolution)

The verdict sidecar (`verdict.json`) records the mode-resolution outcome so
post-mortem readers can reconstruct gate behavior:

- `mode` — `permissive` or `strict` (the **active** mode)
- `mode_source` — one of `frontmatter`, `cli`, `cli-force`, `default` (per `schemas/check-verdict.schema.json` v2)
- `iteration` — 1-indexed counter (sourced from `.iteration-state.json`)
- `iteration_max` — integer (hardcoded `3` since 2026-05-09; was clamp range [1, 5])
- `cap_reached` — boolean (true iff iteration > iteration_max — auto-promotion fired)
- `class_breakdown` — object with all 7 class keys (architectural / security / contract / documentation / tests / scope-cuts / unclassified) → integer counts
- `class_inferred_count` — integer (findings coerced to unclassified at Judge step due to missing/invalid class field)
- `followups_file` — path to `<spec-dir>/followups.jsonl` (or `null` iff that file does not exist on disk)
- `stage` — one of `spec-review`, `plan`, `check` (the gate that emitted this verdict)

The `--force-permissive` reason string is captured in `docs/specs/<feature>/.force-permissive-log` (JSONL audit trail; one row per invocation; NOT in the verdict sidecar). See Section 7.

These fields are read by `/wrap-insights` Phase 1c persona-metrics rendering
and by the `persona-metrics-validator` subagent for foreign-key joins.
