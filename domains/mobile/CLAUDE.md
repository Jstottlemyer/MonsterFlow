# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a multi-project iOS workspace. Projects include apps (health, productivity) and children's games, all targeting iOS/iPadOS 18+ with Swift. Each project lives in its own directory with its own git repo.

## Workspace Structure

```
Mobile/                    <- shared workspace config (this repo)
├── Games/                 <- children's games (see Games/CLAUDE.md)
│   └── CosmicExplorer/    <- own git repo
└── Apps/                  <- health, productivity apps (future)
```

## Frameworks

- **SwiftUI** — primary UI framework for apps
- **UIKit** — used where SwiftUI lacks capability or for interop
- **SpriteKit** — 2D games and animations
- **SceneKit / RealityKit** — 3D games and AR experiences

## Project Conventions

- **Minimum deployment target:** iOS 18 / iPadOS 18
- **Language:** Swift (no Objective-C)
- **Package managers:** Swift Package Manager (preferred) and CocoaPods

## Common Commands

### xcodebuild Workaround

If `xcode-select -p` points to CommandLineTools instead of Xcode.app, use the full path:
```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
```

### Building & Running
```bash
# Open a project in Xcode
open ProjectName.xcodeproj
# or for CocoaPods workspaces
open ProjectName.xcworkspace

# Build from command line (replace scheme and destination as needed)
xcodebuild -scheme SchemeName -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Run tests
xcodebuild test -scheme SchemeName -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Run a single test class
xcodebuild test -scheme SchemeName -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TargetName/TestClassName

# Run a single test method
xcodebuild test -scheme SchemeName -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TargetName/TestClassName/testMethodName
```

### Swift Package Manager
```bash
# Resolve packages
swift package resolve

# Update packages
swift package update

# Build a Swift package
swift build

# Test a Swift package
swift test
```

### CocoaPods
```bash
# Install pods
pod install

# Update pods
pod update

# Always open .xcworkspace after pod install/update, not .xcodeproj
```

### Simulator Management
```bash
# List available simulators
xcrun simctl list devices available

# Boot a specific simulator
xcrun simctl boot "iPhone 17 Pro"

# Install app on booted simulator
xcrun simctl install booted path/to/App.app

# Launch app on booted simulator
xcrun simctl launch booted com.bundle.identifier
```

## Architecture Notes

- Prefer SwiftUI `@Observable` (iOS 17+) or `@ObservableObject` for state management
- Use `async/await` and Swift Concurrency (`actor`, `Task`, `AsyncStream`) over callbacks or delegates where possible
- `@Observable @MainActor final class` is the correct ViewModel pattern for iOS 18+; never mix with `@Published`

## Developer Context

The developer is returning to mobile development after a break and relies on Claude for best practice guidance. Claude should:
- Default to modern Swift idioms (Swift Concurrency, `@Observable`, value types, structured concurrency)
- Explain the "why" behind architectural decisions, not just the "what"
- Proactively flag Apple HIG (Human Interface Guidelines) considerations for UI/UX
- Recommend App Store submission requirements and common pitfalls when relevant
- Prefer clarity and maintainability over clever/terse code

## Workflow

Canonical session workflow:

```
/kickoff → /spec → /spec-review → /blueprint → /check → /build
              define    6 PRD        7 design   5 plan    execute
              (Q&A)     agents       agents     agents    (parallel)
```

Work scales to size: bug fix (no spec) → small change (spec + build) → feature (full pipeline) → V2 (revise spec + full pipeline).

**Artifacts:** `docs/specs/constitution.md` + `docs/specs/<feature>/{spec,review,plan,check}.md`

**Two-tier system:**
- **Pipeline commands**: `/spec` → `/spec-review` → `/blueprint` → `/check` → `/build` with 27 parallel agent personas (`/plan` is Claude Code's built-in plan-mode, not MonsterFlow's design gate — use `/blueprint`)
- **Superpowers**: in-session execution discipline — debugging, verification, code review
- **Plugins**: specialized capabilities — firecrawl (research), context7 (docs), code-review (PR), playwright (browser)

**Spec entry:** `/spec` is the canonical entry point. Skip `superpowers:brainstorming`.

**Code review:** `superpowers:requesting-code-review` for in-session review. `/code-review` for GitHub PR review. 9 code-review personas available for comprehensive review.

**Spec artifacts:** `docs/specs/` — living documents, git is the history.

## Skill Invocations

- End-of-session CLAUDE.md update: `claude-md-management:revise-claude-md` (not `/revise-claude-md`)
