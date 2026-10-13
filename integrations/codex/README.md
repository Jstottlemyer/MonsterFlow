# Skills-only host wrapper

`plugin.json` targets [Agent Plugins 1.0 schema](https://agent-plugins.org/schemas/1.0.0/plugin.schema.json). The schema snapshot preserves the assertions read from that official URL on 2026-10-06, with normalized JSON formatting. Its hash is the local snapshot hash, not a claimed upstream raw-response hash. Browser retrieval succeeded; shell retrieval failed due to DNS. The small validator implements only the assertion vocabulary in this pinned schema, rejects unknown assertions, and additionally checks strict SemVer, lower-kebab names and optional OpenAI short-description length. It is not a general JSON Schema library.

The wrapper contains no top-level `skills`, `interface`, or `mcpServers` keys. The generator exports `skills/<name>/SKILL.md` using Agent Plugins skill discovery. No account dependencies or MCP server are required. No optional interface extension, icons, branding, homepage or public listing claim is included. Attribution is an independently prepared community draft by Fadi Chalfoun with Codex assistance; Justin's upstream MIT copyright is preserved without claiming his authorship or endorsement of this adaptation.

Build from the contribution root with `python3 scripts/build_engineering_plugin.py`. Python 3.9+ and PyYAML are prerequisites; the build does not install dependencies. Canonical member and generator hash mismatches fail. ZIP entries are sorted, regular files, stored without compression, fixed at 1980-01-01 with mode 0644. Roundtrip extraction must reproduce every byte. Only approved wrapper metadata, source identity, README/license and the canonical skill subtree are emitted; tests, rubrics, reports, caches, secrets, dependencies and symlinks are excluded. `dist/` is generated and must not be hand edited.

No host install, upload, runtime enforcement or MF machine-contract compatibility is established by package validation. A wrapper schema change must update its snapshot/validator, emitted metadata, README examples and consumer checks together; a validator alone does not prove prose/example compatibility. There is one editable portable skill source, under `skills/engineering/`; distribution text is generated directly from it.

## Local marketplace installation and discovery

The repository [marketplace entry](../../.agents/plugins/marketplace.json) reuses the existing local entry's plugin name, local source type, `AVAILABLE` / `ON_INSTALL` policies and `Productivity` category. Its marketplace name is `mf-engineering-draft`; its relative source points to the generated plugin directory `./dist/mf-engineering-skills-draft`, resolved from the repository root. Private registration paths, enabled-state/config records, installed caches and smoke transcripts are excluded. `ON_INSTALL` is the existing marketplace timing policy; this skills-only plugin has no service connection to authenticate.

From a local checkout of this draft, with Python 3.9+ and PyYAML already available, first build and extract the package. Run from the repository root:

```sh
python3 scripts/build_engineering_plugin.py
python3 -m zipfile -e dist/mf-engineering-skills-draft-0.3.3-draft.zip dist
```

This produces `dist/mf-engineering-skills-draft/plugin.json` and fourteen `skills/<name>/SKILL.md` entries. Generated files are ignored by Git; regenerate them from the canonical core rather than editing the extracted copy. Build and extract before registering or browsing: the marketplace entry alone has no loadable payload in a fresh checkout. Registering the remote Git repository directly is not an installation route for this source-only draft.

When the adopter chooses to install, the existing CLI route is:

```sh
codex plugin marketplace add . --json
codex plugin add mf-engineering-skills-draft@mf-engineering-draft --json
```

Then start a new Codex session and open `/plugins`; select the marketplace and confirm the plugin is installed. In a fresh task, confirm `engineering-index` is available and can be read before claiming host discovery. The desktop app's Plugins Directory can also show repo marketplace entries; restart it after changing local plugin files. These are adopter instructions, not operations performed by this PR.

The [official packaging guide](https://developers.openai.com/plugins/build/plugins#marketplace-metadata) documents repo marketplaces, relative paths and required policy/category fields; the [official plugin guide](https://learn.chatgpt.com/docs/plugins#plugin-browser-in-codex-cli) documents the CLI browser and new-session use. CLI registration/install syntax was checked against the installed `codex plugin marketplace add --help` and `codex plugin add --help` on 2026-10-13.

Focused deterministic checks resolve the marketplace selector/path against a freshly generated and extracted package, verify manifest identity and all fourteen discovered skill paths, and retain canonical/package byte checks. Actual registration, installation, runtime discovery and a fresh-session skill load were not run for this upstream marketplace. Earlier private local installation evidence is not verification of this new marketplace path.
