# CLAUDE.md — Games

Game-specific guidance for children's iOS games (ages 5-12). This layer adds to the universal iOS config at `Mobile/CLAUDE.md`.

## Overview

Children's games targeting ages 5-12, built with SwiftUI + SpriteKit on iOS 18+. Games prioritize accessibility, simplicity, and age-appropriate UX.

## Projects

- **CosmicExplorer** — space exploration/education game (own git repo, uses XcodeGen)

## Game Architecture Notes

- For games: separate game logic from rendering; keep `SKScene`/`SCNScene`/`RealityView` classes lean
- SwiftUI + SpriteKit: embed via `SpriteView`; SwiftUI + SceneKit: embed via `SceneView` or `RealityKit`'s `RealityView`

## Swift Game Architecture Patterns (confirmed)

- Extract game logic into plain `struct`s (e.g., `SpellingEngine`) — keeps them free of `@MainActor`, fully unit-testable
- `GamePhase` enums: use associated values (`case challenge(CelestialObject)`) to make illegal states unrepresentable
- SpriteKit -> ViewModel: pass closures, not direct ViewModel references — required for Swift 6 strict concurrency
- `@Observable @MainActor final class` is the correct ViewModel pattern for iOS 18+; never mix with `@Published`

## Game Project Structure

```
GameName/
+-- Sources/
|   +-- App/          # Entry point, app lifecycle
|   +-- Scenes/       # Game screens (MainMenuScene, GameScene, etc.)
|   +-- Models/       # Pure data structs
|   +-- Views/        # Reusable SwiftUI components
|   +-- ViewModels/   # Game logic (@Observable or @MainActor classes)
|   +-- Services/     # Persistence, audio, FeatureFlags
|   +-- Utilities/    # Extensions, helpers
|   +-- Resources/    # Constants, strings, features.json
```

## Children's UX Standards

All rules below are **required** — fix directly or ask before shipping. No warnings, no exceptions.

### Touch Targets
- Interactive elements: **60pt minimum** (children's hands)
- 44pt absolute floor per Apple HIG — only for non-primary UI (e.g. a close button an adult would use)

### Typography
- Body/interactive text: **20pt minimum** (CosmicFont.body or larger)
- Labels/captions (non-interactive, supplementary): **15pt minimum** (CosmicFont.label)
- Never below 15pt anywhere, period
- Use project font system (CosmicFont), never raw `.system(.rounded)` for visible text
- System fonts acceptable only inside `TextField` input

### Contrast & Color
- Text on dark backgrounds: white at **0.6 opacity minimum**
- Interactive elements: white at **0.5 opacity minimum**
- Disabled/locked states: **0.35 opacity floor**, but must also have a non-color indicator (icon, badge, or text)
- Never convey state through color alone

### Accessibility
- `.accessibilityLabel()` on ALL interactive elements — no exceptions
- Buttons must have text OR icon + label (never icon-only without `.accessibilityLabel`)
- Every `withAnimation`, `.animation`, `.transition`, or custom animation modifier must be gated on `@Environment(\.accessibilityReduceMotion)` — use `animation(reduceMotion ? nil : ...)` or `if !reduceMotion { }`. No exceptions. If it moves, it gets the guard

### Icons
- NEVER use `Image(systemName:)` for icons. Use the project's icon enum (e.g. `CartoonIcon`). If no case exists, add one, generate the asset, and inform the developer. SF Symbols only acceptable as fallbacks inside the icon enum itself

### Theme Colors
- Backgrounds, borders, accents: use theme properties (`theme.primaryAccent`, `theme.secondaryAccent`)
- Mode-specific colors stay hardcoded to their mode (e.g. blue=spelling, purple=sky, orange=quiz)
- Rank colors: use `rank.color` (already per-rank)
- When in doubt: use theme

### Assets
- All icons and images must have **transparent backgrounds** for the dark space aesthetic

## Agent Selection Guide (Game Agents)

| Scenario | Agent | Do NOT use for |
|----------|-------|----------------|
| Game logic architecture, state machines, phase transitions, scoring | `game-state-reviewer` | General Swift patterns or performance profiling |
| New SwiftUI screen, game scene, HUD, menu scaffold | `swiftui-scene-builder` | Reviewing existing views |
| Accessibility check (children's UI) | `accessibility-guardian` | General Swift review |

**Overlap rules:**
- `@Observable` / state patterns -> `game-state-reviewer` (architecture focus) or `swift-mentor` (idiom/language focus) — pick based on whether the question is about game logic or Swift correctness

## Gotchas

- **CosmicExplorer uses XcodeGen**: Run `cd Games/CosmicExplorer && xcodegen generate` after adding/removing files — don't edit .xcodeproj directly

## Known Issue: Agent Discovery
Agent discovery from `Games/CosmicExplorer/` finds 8 of 9 agents (both `.claude/agents/` levels merge). Verify the 9th (likely test-writer) loads — may have been a count discrepancy in manual check.

## Workflow (Games)

Uses the standard pipeline: `/kickoff` → `/spec` → `/spec-review` → `/design` → `/check` → `/build` (`/plan` is Claude Code's built-in plan-mode, not MonsterFlow's design gate — use `/design` for the pipeline)

Game-specific agents (selected at `/kickoff`):
- **game-state-reviewer** — game logic, state machines, scoring
- **swiftui-scene-builder** — new screens, scenes, HUD, menus
- **accessibility-guardian** — children's UI accessibility
- **swift-mentor** — Swift idioms and language correctness
- **performance-advisor** — performance profiling
- **test-writer** — test generation

Pre-ship gates:
- **Required:** accessibility-guardian (every screen, before every TestFlight/App Store build)
- **Recommended:** game-state-reviewer, performance-advisor
