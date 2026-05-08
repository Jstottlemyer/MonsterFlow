---
gate_mode: permissive
gate_max_recycles: 2
---

# Docs Rewrite Spec — Autonomous-Coding-First Landing Page

**Created:** 2026-05-08
**Constitution:** none — session roster only
**Confidence:** Scope 0.95 / UX 0.92 / Data 0.95 / Integration 0.95 / Edges 0.90 / Acceptance 0.95
**gate_mode:** permissive
**gate_max_recycles:** 2

## Summary

Rewrite the MonsterFlow landing page (`docs/index.html`) to lead with the autonomous-coding value proposition, pass the docs-clarity persona's 30-second skim test, and present a professional first impression. The current page failed the skim test on 3 of 4 questions (what / who / first command). The rewrite preserves the existing visual identity (cyan/coral radial gradients, Inter + JetBrains Mono typography, monster mascot, dark theme) but reframes the hero around the headline differentiator — overnight unattended pipeline runs — and removes implementor jargon that leaked from spec/development context.

## Backlog Routing

Carved from in-conversation review 2026-05-08. Baseline gap report from `docs-clarity` review persona dispatch is preserved at `## Baseline Findings` below as the input to this spec. No prior backlog entry; no items to route.

## Scope

**In scope:**
- `docs/index.html` — hero, eyebrow, tagline, sticky nav, CTA buttons, autorun section, install section, jargon-strip across all body sections.
- Headline reframe: lead with autonomous coding (overnight unattended pipeline) as the differentiator, not "multi-agent review at every gate" (which is plumbing, not outcome).
- Inline install snippet in hero (not buried below 5 narrative sections).
- One-line "who it's for" under tagline.
- Inline definitions for jargon on first use (gate, persona, autorun) OR replacement with plain language.
- Strip implementor jargon from public-facing prose: `D33`, `RUN_DEGRADED`, `NFKC-normalize`, `AC#24`, `single-fence-spoof`, `v0.9.0 AC#4`, `_policy_json.py`, `extract-fence`, fenced-block mechanics. (These are real engineering details and stay in spec docs; they don't belong on the landing page.)
- "What this is NOT" stripe.
- Confidence-parity stripe (mirroring the /spec confidence-score signal): "Pipeline core: stable since v0.7. Persona Metrics: shipping. Dynamic roster: in flight."
- Fix typo / dead reference: `/autobuild` mentioned once but doesn't exist anywhere else (likely `/autorun`).
- Consolidate 41/30/9/2 reviewer count repetition (3x today) into one canonical place.
- De-Justin-machine-specific paths: `~/Projects/MonsterFlow/` in dashboard section assumes adopter has cloned to that exact path.
- CTA hierarchy cleanup: pick a single primary action (Install) over the current split between two buttons + a competing "jump to pipeline" link.
- Mobile rendering: hero, four-question section, install snippet all visible on a 375px-wide viewport without horizontal scroll (per docs-clarity checklist).

**Out of scope:**
- Visual redesign — keep gradients, mascot, fonts, color palette, spacing system. This is content rewrite + structural reorder, not a brand refresh.
- `docs/dashboard.html` — separate page, separate concerns.
- `docs/social-card.html` + `docs/social-image.png` — OG image stays.
- Ancillary `docs/*.md` files (budget, graphify-usage, persona-ranking, why-monsterflow) — they're long-form supporting reads, not the landing page.
- README.md — separate spec candidate if it has the same problem.
- `docs/specs/*` content — internal artifacts, not adopter-facing.
- New visual primitives (no new icon set, no shipping a CSS framework, no Tailwind migration). Inline `<style>` block in `index.html` stays inline.
- Adding analytics or telemetry. Plain GitHub Pages.

## Approach

**Chosen:** in-place content rewrite of `docs/index.html` with iterative local-server feedback loop:

1. Branch unnecessary — work directly on `main` is fine for a docs-only rewrite (low blast radius; gh-pages auto-deploys on push). Local preview at `http://localhost:8765/` (already running, PID 4081 from earlier).
2. Draft the hero rewrite first (highest impact per docs-clarity findings). Optionally use the `frontend-design` skill (recently installed) to explore polish-level layout refinements within the existing visual system.
3. Dispatch the `docs-clarity` review persona after each non-trivial edit pass (hero done → review; autorun-section done → review; full pass → review). Iterate until verdict is `PASS` or `PASS WITH NOTES`.
4. Push to `main` to trigger gh-pages deploy. Visual verify on `https://jstottlemyer.github.io/MonsterFlow/`.

Rejected alternatives:
- *Full visual redesign with the `frontend-design` skill from scratch* — overkill; the existing visual system is good. The problem is content + structure, not aesthetics.
- *Multi-page split (separate landing + docs)* — increases adopter friction. Single page is the right shape.
- *A/B branch with PR* — for a content-only rewrite to a personal-tool landing page, the PR ceremony costs more than it returns.

## Roster Changes

No persistent roster changes. The just-shipped `personas/review/docs-clarity.md` is the right gate for this spec's iterations and for future docs touch-ups.

## UX / User Flow

**Hero target shape (draft, will iterate):**

```
[eyebrow] Autonomous coding for Claude Code · v0.10.10
[h1] From "add OAuth" to a merged PR — while you sleep.
[tagline] MonsterFlow is an 8-command pipeline that takes a one-line
          feature request through spec → review → plan → check → build,
          with parallel reviewer agents at every gate. Queue features
          tonight, wake up to ready-to-merge PRs.
[who] Built for solo developers and small teams using Claude Code on
      personal or production projects. MIT-licensed. Local install.
[install snippet, copyable]
  git clone https://github.com/Jstottlemyer/MonsterFlow.git
  cd MonsterFlow && ./install.sh
[primary CTA] Install · [secondary] View on GitHub
```

**Autorun-as-headline section (next after hero):**

Currently the autorun section sits low on the page, after Pipeline / Self-learning / Knowledge loop / Wrap / Commands. Move it to position #2 (right after hero), reframed:

```
=== Autorun: the unattended pipeline ===
Queue 1-5 features, walk away, wake up to PRs.
[diagram: queue → autorun-batch → 8 stages × N slugs → PR(s) on main]
What happens overnight:
- Each feature runs spec-review → plan → check → build sequentially
- Multi-agent review at every gate; 3-attempt resolution loops on
  blocking findings before halting
- STOP file aborts cleanly between iterations
- Failed runs preserved for morning triage; shipped runs squash-merged
[CTA: see how to queue your first feature]
```

**Confidence-parity stripe:**

```
[Pipeline core: stable since v0.7] · [Persona Metrics: shipping]
· [Dynamic roster: in flight] · [Single-developer project, MIT]
```

(Mirrors the /spec confidence-row signal: small, specific, honest.)

**"What this is NOT" stripe (somewhere in first scroll):**

```
Not a Claude Code replacement · not a chat UI · not a hosted service
Just slash commands and agents that live in your repo.
```

## Data & State

No new persistent state. No schema changes. No new files outside the spec dir.

The page stays a single static HTML file at `docs/index.html`. Inline `<style>` block stays inline. Inline mermaid diagrams stay inline. No build step.

## Integration

- `docs/index.html` — primary file, ~944 lines today, expect ~750-1000 lines after rewrite (some sections shorten, some shift).
- `personas/review/docs-clarity.md` — review gate, used unchanged.
- `python3 -m http.server 8765 --directory docs/` — local preview, already running.
- `https://jstottlemyer.github.io/MonsterFlow/` — gh-pages deploy on `main` push, automatic.
- No CI changes. No `gh` workflow changes.
- `frontend-design` plugin (just installed) — optional consultation on layout polish during draft. Not load-bearing.

Touched files: 1 (`docs/index.html`) + this spec.

## Edge Cases

- **Visual regression on push:** gh-pages deploys ~30-60s after push. Worst case: typo in inline `<style>` breaks the page. Mitigation: local server preview catches this before push; visual diff against http://localhost:8765/ before each push.
- **Mermaid diagram changes:** the existing pipeline diagram has 17 nodes + classDefs. Touching it risks layout drift. Constraint: preserve diagram source text unless it's the typo fix (`/autobuild` → `/autorun`). Diagram renders client-side via mermaid.js@10 from cdn.jsdelivr.net (already loaded).
- **Mobile breakage:** hero rewrite must verify at 375px viewport (iPhone SE width). Local browser dev tools simulator suffices; no need for real-device test.
- **Footer / final-status / agent-roster sections:** these are accurate but dense. Leave structure intact; only strip implementor jargon.
- **Backwards-incompatible URL changes:** the page has anchor links (`#install`, `#pipeline`, `#commands`, etc.). Preserve anchor IDs even if section order changes — external links and the existing nav rely on them.
- **Mascot + OG image:** unchanged. The monster mascot stays in hero; social-image.png is referenced only by OG meta tags; no edits.
- **`v0.10.10` version pin in eyebrow:** the value is auto-bumped by post-commit hook (`scripts/auto-bump.sh` likely). Preserve the substitution token / pattern.
- **gh-pages caching:** GitHub's CDN caches for ~10 min. After push, force-refresh in browser may be needed. Not a spec concern.

## Acceptance Criteria

1. `docs-clarity` review of the rewritten `docs/index.html` returns verdict `PASS` or `PASS WITH NOTES` (no Critical Gaps).
2. The 30-Second Test answers all four questions cleanly from content visible in the first viewport (hero + first scroll, no expansion):
   - What is it? — answered in concrete terms (CLI / slash commands / for Claude Code), not slogan.
   - Who is it for? — explicit one-line audience statement.
   - Why would I install it? — stated as reader pain or reader outcome (autonomous coding, overnight PRs).
   - First command? — copyable install snippet visible in hero.
3. Hero leads with autonomous coding as the headline differentiator. The phrase "autonomous", "overnight", "unattended", or equivalent appears in the eyebrow, h1, or tagline.
4. Autorun section moved to position #2 (immediately after hero), reframed for adopter outcomes (queue/walk-away/wake-up framing) rather than implementor mechanics (sidecar/fence/extract-fence framing).
5. Implementor jargon stripped from public sections: `D33`, `RUN_DEGRADED`, `NFKC-normalize`, `AC#24`, `single-fence-spoof`, `_policy_json.py`, `extract-fence`. None of these literals appear in the rendered page.
6. Inline definition (or plain-language replacement) for: `gate`, `persona`, `autorun` — defined on first use.
7. "What this is NOT" stripe present in first scroll.
8. Confidence-parity stripe present (stability snapshot per major component).
9. `/autobuild` typo fixed (replaced with `/autorun` or removed).
10. Reviewer count (41/30/9/2) appears in exactly one canonical place, not three.
11. Dashboard section de-Justinified: `~/Projects/MonsterFlow/` replaced with a generic `<your-clone-path>` placeholder or removed in favor of "the example dashboard at the link above."
12. CTA hierarchy: one primary action (Install). Secondary (View on GitHub) preserved. The "jump to pipeline" tertiary link removed or de-emphasized.
13. Mobile rendering at 375px viewport: hero, install snippet, autorun-headline section all visible without horizontal scroll. Visual verify in browser dev tools.
14. Anchor IDs preserved: `#install`, `#pipeline`, `#commands`, `#autorun`, etc. — existing internal links don't break.
15. Mermaid diagrams render correctly post-edit (no syntax errors in diagram source).
16. Version eyebrow (`v0.10.10`) substitution unchanged — auto-bump hook still works.
17. Visual identity preserved: gradients, fonts, mascot, color palette, dark theme, OG image — none of these change.

## Baseline Findings

The `docs-clarity` review persona was dispatched against the current `docs/index.html` on 2026-05-08. Verdict: **FAIL**. Three of four 30-second-test questions failed. Quoted findings below; full review preserved in conversation history.

### Critical Gaps (4)

1. **Hero never answers "what is it?" in plain language.** H1 `"You say WHAT. Claude handles HOW."` is a slogan, not a description. Eyebrow `"8-command pipeline · Claude Code · v0.10.10"` leans on undefined jargon. Tagline assumes reader knows what a "pipeline for Claude Code" is.
2. **Hero-hook actively confuses first-time readers.** `"Multi-agent review at every review gate. And then the system measures whether those reviews are worth anything."` — stranger parses "review at the review gate" as tautological + "gate" never defined inline. Worst sentence on the page from stranger's-perspective lens.
3. **First command buried.** Install section at line 769 — past Why, Pipeline, Self-learning, Knowledge loop, Wrap, Commands, Autorun, Requirements. Reader hits ~10,000px of dense narrative before seeing `git clone`.
4. **Who is it for?** Requires inference. Aside mentions "I built it for myself" which paradoxically makes a stranger wonder if it's for them.

### Important Considerations (8)

- Jargon density in first scroll: gate, persona, fence, axis, autorun all undefined.
- Hero numbers without meaning: `41 reviewers — 30 always-available pipeline personas, 9 domain personas, plus 2 focused Claude Code subagents` — system audit, not value pitch.
- Internal jargon leaks heavily in autorun section: `v0.9.0 sessions taught me`, `D33`, `single-fence-spoof`, `AC#24`, `RUN_DEGRADED=1`, `CODEX_HIGH_COUNT`, `NFKC-normalize`. Implementor-facing prose pasted into public landing page.
- No "What this is NOT" framing.
- Confidence-score parity missing — /spec exposes confidence as a clarity signal; landing page doesn't.
- CTA hierarchy split (two buttons + competing tertiary link).
- Dashboard reference assumes adopter has cloned to `~/Projects/MonsterFlow/`.
- Reviewer count repetition (OG description, hero tagline, agent roster header) — pick one.

### Observations (7)

- "Why this exists" aside is well-pitched, keep it. `"I don't ship code anymore, I ship outcomes"` is the strongest line.
- Mermaid pipeline diagram is dense (17 nodes, 5 sidecar boxes, 4 link styles, 11 classDefs).
- `/autobuild` mentioned once, doesn't exist elsewhere (likely typo for `/autorun`).
- v0.10.10 in eyebrow is a trust signal (actively shipped).
- `/flow` reference card at bottom is good but redundant with Commands table.
- 41/30/9/2 reviewer count repeated 3x.
- Mobile install snippet uses `&&` chain — verify clipboard copies cleanly at 375px.

## Open Questions

- **Q1:** should the autorun-headline reframe use a hero-internal carousel/tab to show "interactive vs autorun" both on equal footing, or commit fully to autorun-as-headline with interactive as the secondary mode? **Lean: commit to autorun-as-headline.** The interactive mode is the conventional Claude Code workflow — adopters who want it already understand it. Autorun is the differentiator; lead with what's different. Revisit if this confuses readers who expected an interactive tool.
- **Q2:** should we link to a 30-second autorun demo video / asciinema cast in the hero? **Lean: yes if cheap to produce; no if it requires a separate spec.** Asciinema cast of `autorun-batch.sh` running through one slug would be high-signal. Defer to follow-up if it requires recording infrastructure.
- **Q3:** should the rewrite expose the v0.10.x version eyebrow more prominently as a "actively shipped" trust signal, e.g. with a "last commit X days ago" badge? **Lean: no.** GitHub already does this on the repo page. Noise on the landing page.
