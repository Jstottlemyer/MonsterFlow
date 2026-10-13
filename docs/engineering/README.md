# Portable engineering skills draft

This additive module packages the existing `0.3.3-draft` portable extraction. It provides fourteen focused engineering skills, preserved native criteria, provenance, MIT notices and a skills-only Agent Plugins wrapper. It is a community adaptation by Fadi Chalfoun with Codex assistance, not an official MF release or a claim of native feature parity.

## Source and placement

The single editable source is [skills/engineering](../../skills/engineering/README.md); [SOURCE.json](../../skills/engineering/SOURCE.json) pins its member hashes, source mappings and disclosed host-policy additions. [coverage.json](../../skills/engineering/coverage.json) records 31 native persona references and 2,179 nonblank source-line dispositions. The fourteen skill trees are unchanged from the prepared extraction. Start with [engineering-index](../../skills/engineering/skills/engineering-index/SKILL.md) or a focused entrypoint.

This source home keeps the portable module together and out of `.claude/skills/`, which the native installer and native skill tests consume. [integrations/codex](../../integrations/codex/README.md) holds host metadata and the pinned schema; [the builder](../../scripts/build_engineering_plugin.py) generates distribution directly from the canonical source. The native commands, personas, launcher, installer and runtime configuration are untouched.

The adaptation pins MF 0.18.0 at `53de60aa005126d5ee8a1b23ffc4f775c1cb5a25`. At upstream base `2513b51dab60588b8b0972aeaee934108c0f2b39`, 51 of its 55 mapped source files match, `commands/build.md` differs, and `scripts/build-codex-review.sh`, `scripts/build-codex-worker.sh`, and `templates/build-worker-preamble.md` are absent. This contribution preserves the existing extraction rather than retargeting its criteria. All 55 original source hashes were verified against the pinned native checkout before packaging. Source hash identity is not behavioral validation.

## Local checks and export

Python 3.9+ and PyYAML must already be available; these commands do not install dependencies:

```sh
bash tests/run-tests.sh portable-engineering
python3 scripts/build_engineering_plugin.py --output /tmp/mf-engineering-export
```

The package test is registered in the default runner's `TESTS` array. Its checks cover canonical hashes, source coverage mappings, frontmatter, relative links, MIT notices, manifest/schema rejection controls, forbidden personal paths and symlinks, deterministic ZIP metadata, member inventory and byte-identical extraction. The full native suite was not run in this bounded publication pass because it includes installer/runtime checks beyond the authorized lightweight checks. The exported ZIP and report are generated locally, not committed.

Historical evaluation fixtures, scoring rubrics, behavioral responses, installation records, local marketplace metadata and private project files are excluded. The retained provenance describes generic prior operational lessons; no referenced private project source is bundled. No provider or reviewer was called, no plugin was installed, and no behavioral efficacy or current-host compatibility is certified. This draft adds no standing invocation, runtime enforcement, permissions, automatic dispatch or merge authority.

## Publication-pass evidence

On 2026-10-13, `/bin/bash tests/run-tests.sh portable-engineering` passed all 18 deterministic tests through the registered runner. The existing native `skills` test also passed (2 skills). Shell syntax checks with `/bin/bash -n`, JSON parsing, local Markdown link existence, no-symlink checks and `git diff --check` passed. The canonical extraction tree, wrapper and generator preserve their prepared bytes; the test file omits one historical traceability/behavioral-fixture inventory test because those artifacts are outside this contribution.

The exported archive contains 14 skills, is 1,215,777 bytes, and has SHA-256 `2a4c574ddb9c1f80f18c1908402956f1ffd533967ed3ff1af55118eaad3b8efa`. Repeated archive generation and extraction reproduced every byte. Python 3.9+ and existing PyYAML were used without dependency installation. `graphify` was unavailable in this environment, so the repository-requested AST graph update could not run; no graph tooling was installed. No full-suite, independent semantic review, provider execution, installation or new efficacy evidence is claimed.
