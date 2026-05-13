# API & Interface Design — install-graphify-wiki-coverage

**Persona:** api
**Gate:** /blueprint (Design)
**Spec rev:** rev1 (2026-05-13)

## Key Considerations

- **The "API" here is bash function shape + stdout contract + env-var contract.** Adopters never call these helpers directly; the discoverability question is "can a future maintainer scan install.sh and understand what each function returns and what it mutates without reading the body?" Function names + a one-line comment header + a stable stdout pattern carry that weight, not type signatures bash can't enforce.
- **Detection vs. action separation is the load-bearing API decision.** Spec calls out `detect_knowledge_layer()` (pure: status + summary block) and `do_knowledge_layer()` (orchestrator: prompt + dispatch). If detection ever mutates state — even logging a `.bak` — idempotency AC3 breaks. The detect/do split must be enforced by convention: "detect_* is read-only, prints to stdout, never writes."
- **Per-piece classification is the stable contract.** Three buckets (Ready / Can-install-now / Manual-action-required) are the API consumed by the prompt logic, the summary renderer, and the dispatch loop. If callers learn this taxonomy once, every piece reads the same way. Two buckets (Codex's earlier "doctor + fixer" only-fixable framing) collapses cmux drift + wiki skills into a third unnamed category that has to be re-explained at every call site.
- **bash 3.2 ceiling on macOS.** No associative arrays (`declare -A`), no `${arr[-1]}` (per `feedback_negative_array_subscript_bash32` memory), no `mapfile`/`readarray`, no `local -n` nameref returns. Status state for 5 pieces must be carried in parallel scalar vars or positional `$@` shape, not an assoc-array dict.
- **Stdout is the return channel; exit code is a boolean.** bash functions can't return rich data without subshell capture. Detection helpers return status via `echo` of a fixed token (`ready` / `can-install` / `manual`) on stdout, captured at the call site via `$(detect_graphify_cli)`. Exit code stays 0 for success-of-the-detect, NOT 0-for-Ready / 1-for-missing (that conflates "detection ran cleanly" with "piece is present").
- **Idempotency is enforced at the action layer, not just the detect layer.** Even if detect says "Can install now," the per-piece install helper must short-circuit when artifacts already exist (e.g., venv dir present + symlink present → skip; venv dir present + symlink missing → symlink-only). This is API-level: `install_graphify_cli` itself owns the "did anything need doing?" decision, callers don't pre-flight it.
- **No global mutable state.** The existing install.sh pattern uses top-level scalars (`OWNER`, `NON_INTERACTIVE`, `NO_THEME`) set once and read everywhere. Knowledge Layer should not add new exported globals — every per-piece detection result should be local to `do_knowledge_layer`'s scope, passed positionally to the renderer.
- **Test seam is part of the public contract.** `MONSTERFLOW_INSTALL_TEST=1` already exists; the spec reuses it. But the install helpers also need a way for tests to assert "this would have called brew" without actually calling brew. Stdout `RUNNING: brew install --cask obsidian` is the assertion surface (AC8 reads `$STUB_LOG` for argv). The action helpers MUST `echo "RUNNING: <cmd>"` before every external invocation, and that echo line is a load-bearing API affordance — not just polish.

## Options Explored

### Option A: 5 parallel scalar vars + positional render

Each detect helper sets a named global scalar in `do_knowledge_layer`'s scope:

```bash
do_knowledge_layer() {
    local GRAPHIFY_STATUS WIKI_STATUS OBSIDIAN_ENV_STATUS OBSIDIAN_APP_STATUS CMUX_STATUS
    GRAPHIFY_STATUS="$(detect_graphify_cli)"        # echoes "ready" / "can-install" / "manual"
    WIKI_STATUS="$(detect_wiki_skills)"             # also echoes count: "manual:4/6"
    OBSIDIAN_ENV_STATUS="$(detect_obsidian_env)"
    OBSIDIAN_APP_STATUS="$(detect_obsidian_app)"
    CMUX_STATUS="$(detect_cmux_drift)"              # "ready" / "drift" / "na"

    render_knowledge_summary \
        "$GRAPHIFY_STATUS" "$WIKI_STATUS" "$OBSIDIAN_ENV_STATUS" \
        "$OBSIDIAN_APP_STATUS" "$CMUX_STATUS"

    # bucket aggregation
    local CAN_INSTALL=()
    [[ "$GRAPHIFY_STATUS" == can-install* ]] && CAN_INSTALL+=("graphify CLI")
    # ...

    if [ ${#CAN_INSTALL[@]} -gt 0 ]; then
        prompt_and_dispatch "${CAN_INSTALL[@]}"
    fi

    render_manual_action_instructions "$WIKI_STATUS" "$CMUX_STATUS"
}
```

Pros:
- Pure bash 3.2; no assoc arrays. Each detect helper has one stdout token, one exit code.
- Each piece is independently testable: call `detect_graphify_cli` in isolation and grep its output.
- Render is a single function with 5 positional args — readable, matches existing install.sh style.
- The status token (`ready` / `can-install` / `can-install:partial` / `manual:N/M` / `drift` / `na`) carries enough structure for the renderer without a second data trip.

Cons:
- Adding a 6th piece later means a 6th scalar, 6th render arg — friction grows linearly.
- Status-token grammar is informal (string-grep at call sites). A typo in the token name silently routes a piece to the wrong bucket.

Effort: **S** (clean fit, ~70 LoC for the orchestrator + render, ~30 LoC per detect helper).

### Option B: Single stdout protocol with parsed lines

Each detect helper echoes one line in a fixed grammar: `<piece> <status> <detail>`. Orchestrator captures all detect output into one heredoc-ish blob, parses it once, dispatches.

```bash
detect_knowledge_layer() {
    detect_graphify_cli     # echoes "graphify ready" or "graphify can-install"
    detect_wiki_skills      # echoes "wiki manual 4/6"
    detect_obsidian_env     # echoes "obsidian-env ready /Users/.../wiki"
    detect_obsidian_app     # echoes "obsidian-app ready"
    detect_cmux_drift       # echoes "cmux drift" or "cmux na"
}

do_knowledge_layer() {
    local DETECT_OUT
    DETECT_OUT="$(detect_knowledge_layer)"
    render_knowledge_summary "$DETECT_OUT"
    # parse $DETECT_OUT for bucket aggregation via while-read
    ...
}
```

Pros:
- Adding a 7th piece = add one detect helper + one parse case. No N-scalar growth.
- Stdout protocol is the contract — tests can capture detect output once and assert against it line-by-line.
- Detection is composable: `detect_knowledge_layer` is the only public entry point; per-piece detectors are private.

Cons:
- Two-pass parsing (capture, then re-split per line) adds bash 3.2 IFS gymnastics. Spaces in paths (vault path like `~/Documents/test vault`) break naive `read piece status detail`.
- Renderer needs to parse the same blob a second time, or detect needs to return TWO outputs (status lines + a pre-rendered summary block).
- Debugging is harder: if `detect_obsidian_env` echoes a malformed line, the symptom shows up downstream during parse, not at the detect site.

Effort: **M** (parser plumbing + tests for the grammar add ~50 LoC over Option A).

### Option C: Echo-driven side effect, no return values

Each detect helper renders its own summary line directly to stdout AND independently re-detects in the dispatch phase. No shared state.

```bash
detect_graphify_cli() {  # prints summary line, returns 0=ready / 1=can-install / 2=manual
    if has_cmd graphify; then
        echo "graphify CLI:        ✓"; return 0
    else
        echo "graphify CLI:        ✗ (not installed)"; return 1
    fi
}

install_graphify_cli() {  # re-detects, no-ops if already ready
    has_cmd graphify && { echo "  graphify already installed, skipping"; return 0; }
    # ... run install ...
}
```

Pros:
- Simplest API: every helper does its one job, no orchestrator-level state.
- Idempotency falls out naturally — each install helper has its own short-circuit.

Cons:
- Double detection (once for summary, once for install dispatch) is wasted work on hot path. Tolerable for filesystem checks, painful for anything network-bound (none here, so this is a soft con).
- Exit-code-as-bucket-classifier is fragile under `set -euo pipefail` — a return 1 from `detect_graphify_cli` would abort the script unless every call site `|| true`s it. Per the `feedback_pipestatus_or_true` memory, that's a known footgun.
- No central place to ask "what's in the Can-install-now bucket?" — that decision is scattered across each helper.

Effort: **S** (less code) but **higher long-term cost** (the prompt summary "Install these 3 pieces: ..." needs the bucket list, which requires re-detecting all 5 pieces a second time inside `do_knowledge_layer`).

## Recommendation

**Option A** — 5 parallel scalar vars + positional render.

Reasoning:
- The piece count is fixed at 5 for this spec; the Open Question on generalizing the cmux pattern is explicitly deferred. Optimizing for "add a 6th piece later" (Option B's win) is premature.
- Stdout-token-as-return-value is bash 3.2 idiomatic and already used elsewhere in install.sh (`detect_owner()` at install.sh:616 echoes "1" or "0").
- The bucket aggregation step lives in exactly one function (`do_knowledge_layer`) — no scattered re-detection, no exit-code-as-state.
- Each detect helper is independently unit-testable via stdout capture, which the test suite is already structured for.
- Renderer with 5 positional args is verbose but transparent — no parsing layer to debug.

Status-token grammar to pin (this is the API contract between detect and dispatch):

```
graphify:        "ready" | "can-install"
wiki:            "ready" | "manual:N/6"            (N=0..5; ready when N=6)
obsidian-env:    "ready:<path>" | "can-install" | "warn:<path>"   (warn = configured-but-missing)
obsidian-app:    "ready" | "can-install" | "manual"  (manual = brew unavailable, per EC20)
cmux:            "ready" | "drift" | "na"
```

Functions exposed (all defined at top-level so they're callable under `--no-theme`):

```
# Top-level helpers (hoisted, callable from any stage):
posix_quote() { ... }                    # already exists, hoist from do_theme_install
print_step() { echo "  $@"; }            # already exists implicitly; codify

# Detection (read-only, stdout = status token, exit 0):
detect_graphify_cli()                    # echoes "ready" | "can-install"
detect_wiki_skills()                     # echoes "ready" | "manual:N/6"
detect_obsidian_env()                    # echoes "ready:<path>" | "can-install" | "warn:<path>"
detect_obsidian_app()                    # echoes "ready" | "can-install" | "manual"
detect_cmux_drift()                      # echoes "ready" | "drift" | "na"
parse_obsidian_config()                  # echoes resolved vault path; exit 1 if absent/unparseable

# Rendering (read-only, stdout = human-facing summary):
render_knowledge_summary()               # 5 positional args, prints the ===Knowledge Layer=== block

# Action (mutating, stdout = "RUNNING: <cmd>" + "WROTE: <path>" lines):
install_graphify_cli()                   # runs venv + pip + ln + graphify claude install
install_obsidian_env()                   # prompts vault path, writes config + .zshrc block
install_obsidian_app()                   # brew install --cask obsidian + success-oracle check

# Instructions (print-only, no exec):
print_wiki_skills_instructions()         # "npx skills add ..." + git-clone fallback
print_cmux_drift_instructions()          # "brew install --cask cmux"
print_obsidian_app_manual_instructions() # used when brew unavailable (EC20)

# Orchestrator:
do_knowledge_layer()                     # the entry point called from install.sh main flow
```

Naming convention follows existing install.sh:
- `do_<stage>` for entry points (`do_theme_install`, now `do_knowledge_layer`)
- `detect_<piece>` for status probes (new pattern, but reads cleanly against `detect_owner`)
- `install_<piece>` for state-mutating fixers (new; descriptive, low-risk-of-collision)
- `print_<piece>_instructions` for print-only diagnostics (new; the `_instructions` suffix earns its keep — it signals "this function does not act, it documents")
- `render_<thing>` for stdout-only formatters (new; cleanly separable from `print_<x>_instructions` because render is one block, print is per-piece)

Stable stdout contract for action helpers (this is what tests assert against):
- `  RUNNING: <command line>` — before every external command invocation
- `  WROTE:   <path>` — after every file write
- `  APPENDED: <path>` — after every sentinel-bracketed append
- `  LINKED:  <path> → <target>` — already used by `link_file`, reuse
- `  ✓ <piece> installed` — terminal success line per piece
- `  ⚠ <message>` — soft warning, non-fatal
- `  ✗ <message>` — hard failure, also non-fatal at the knowledge layer

These prefixes are not just polish; AC5 and AC8 explicitly assert against `RUNNING:` strings via `$STUB_LOG`. Treat them as part of the public API.

Error-handling shape:
- Action helpers return 0 on success-OR-skip (idempotency), non-zero only on hard failure that should be surfaced.
- `do_knowledge_layer` does NOT `set -e` exit on a single piece's failure — it logs `✗` and continues to the next piece. Adopters with no brew shouldn't be blocked from configuring vault paths. This is consistent with the existing prerequisite-tier model (warn-only at install.sh:319).
- One global non-zero exit only when the user explicitly Ctrl-C'd during a prompt (which the existing SIGINT trap at install.sh:271 already covers).

## Constraints Identified

- **bash 3.2 macOS ceiling.** No assoc arrays, no `${arr[-1]}`, no `mapfile`. Indexed arrays + `${#arr[@]}` only.
- **`set -euo pipefail` is active in install.sh.** Functions returning non-zero abort the script unless explicitly handled. Detect helpers must `return 0` always; status is in stdout, not exit code.
- **PIPESTATUS resets after `|| true`** (per `feedback_pipestatus_or_true` memory). Avoid pipelines in idempotency-critical paths; use `$?` capture instead.
- **Tilde expansion is not implicit in `"$VAR"` reads** (per `feedback_tilde_expansion_in_bash_config_reads`). `parse_obsidian_config` MUST apply `${VAR/#\~/$HOME}` before any `[ -d ]` check or write target.
- **`git add` sweeps the full index** (per `feedback_git_add_then_commit_sweeps_index`). The test for AC3 must `git status` cleanly before asserting "no new files."
- **Atomic writes via `$INSTALL_SCRATCH/<name>.tmp` + `mv -f`** — already an install.sh invariant. `~/.obsidian-wiki/config` must follow it.
- **No `source` of the config file** (per spec EC18 + Codex #7). `parse_obsidian_config` MUST be a grep/sed-based parser, not `. ~/.obsidian-wiki/config`.
- **Posix-quote escaping is the only safe way to write user-provided paths into `~/.zshrc`** (D6/B4 fix already in theme stage at install.sh:737-740). Reuse the hoisted helper, do not roll a second.
- **Sentinel blocks are the only safe re-write pattern for `~/.zshrc`.** Match the existing `# BEGIN MonsterFlow theme` / `# END MonsterFlow theme` style.
- **`MONSTERFLOW_INSTALL_TEST=1` short-circuits real `pip3 install` and `brew install --cask obsidian`.** Test harness stubs the underlying binary; the install helper must check this env var BEFORE invoking the slow path. The user-facing `RUNNING:` echo still fires under test, so AC8b can assert against `$STUB_LOG`.
- **`OWNER` and `NON_INTERACTIVE` are read-only globals set at install.sh top.** Do not re-detect them inside Knowledge Layer; read them.
- **Hoisting `posix_quote` to top-level is non-optional** (Codex #3, spec rev1). Without it, `install_obsidian_env` under `--no-theme` calls an undefined function and aborts under `set -u`.

## Open Questions

- **Should `detect_*` helpers ALSO emit the human-facing summary line, or is rendering strictly the renderer's job?** Option A above keeps render separate (cleaner); Option C colocates them (simpler). Recommend keeping render separate — testability win (you can assert summary format without running detection) outweighs the small DRY cost.
- **Where does the prompt actually live — `do_knowledge_layer` or a helper `prompt_install_confirmation`?** Inline in `do_knowledge_layer` is fine for one prompt. If the prompt grows a second confirmation gate later (e.g., separate "install graphify?" vs "install Obsidian.app?"), extract.
- **Test seam for `graphify claude install`.** The spec gates the pip install behind `MONSTERFLOW_INSTALL_TEST=1`, but `graphify claude install` itself writes to `~/.claude/skills/`, `~/CLAUDE.md`, and `~/.claude/settings.json` — touching adopter state outside install.sh's `$HOME`-isolated test fixture. Decision: under `MONSTERFLOW_INSTALL_TEST=1`, ALSO skip the `graphify claude install` invocation; the test asserts the `RUNNING:` line but does not let graphify actually mutate.
- **Should `render_knowledge_summary` accept arg-by-position or arg-by-flag** (`--graphify ready --wiki manual:4/6 ...`)? Positional is simpler and matches the small fixed arity; flag-style is more discoverable but adds a parser. Positional wins for this spec.
- **Does `install_obsidian_env` write the `~/.obsidian-wiki/config` BEFORE or AFTER appending to `~/.zshrc`?** Recommend config first (atomic via scratch + mv), .zshrc append second. If the .zshrc append fails partway, the config file is still valid and a re-run picks up where the user left off (idempotent recovery).
- **Should the detect/install helpers `echo` to stderr or stdout for `RUNNING:` lines?** Existing `link_file` uses stdout. Keep stdout for consistency; tests capture stdout into `$STUB_LOG`.

## Integration Points with other dimensions

- **data dimension** needs the stdout-token grammar pinned (the `ready` / `can-install` / `manual:N/M` strings). Suggest data persona codify it as a yaml-style mini-schema in the design doc so reviewers can grep for drift.
- **data dimension** also owns the `~/.obsidian-wiki/config` file format. The api recommendation here is "single line, `OBSIDIAN_VAULT_PATH="<path>"`, no other keys, no comments inside the line" — keeps the parser trivial and the file diffable.
- **integration dimension** needs to confirm placement at install.sh:716 doesn't conflict with the CLAUDE.md baseline merge that runs immediately after. Specifically: if `graphify claude install` writes to `~/CLAUDE.md` and the baseline merger runs after, the merger needs to be idempotent over graphify's addition. (It already is per `claude-md-merge.py`, but call this out explicitly.)
- **integration dimension** also owns the test wiring (`tests/run-tests.sh` TESTS array append + orchestrator-wiring guard). The api side here is just "the new test file is named `test-install-knowledge-layer.sh`."
- **scalability dimension** — there is no scalability concern at this layer (5 pieces, sub-second detection). Flagging only so the persona doesn't have to invent one.
- **security dimension** should review the `parse_obsidian_config` grammar and the `posix_quote` reuse. Specifically: can a malicious `~/.obsidian-wiki/config` file (planted by an attacker before install.sh runs) inject code via the parser? Recommendation: parser is grep+sed only, never `source`, never `eval`. Code that goes into `~/.zshrc` is the resolved path passed through `posix_quote`, never the raw config-file bytes.
- **migration dimension** — no migration. New stage, no schema bump, no rename. The only "migration" is: an adopter who previously installed graphify via `bootstrap-graphify.sh` should see `Ready ✓` on graphify CLI and the install action skips (already covered by EC1).
- **edge-cases dimension** owns the 20 ECs in the spec. The api side here is: every EC maps to a specific helper's responsibility. EC1-3 → `detect_graphify_cli` + `install_graphify_cli`. EC4-5 → `detect_obsidian_env` + `install_obsidian_env`. EC16-17 → `detect_obsidian_app` + `install_obsidian_app`. EC18 → `parse_obsidian_config`. The 1:1 mapping is what makes 20 ECs tractable.
