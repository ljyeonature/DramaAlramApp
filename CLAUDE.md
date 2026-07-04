# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Status

Fresh Xcode 26.2 scaffold — `ViewController` is empty, `Main.storyboard` is the default template, and `DramaAppTests` contains only a placeholder test. There is no production code yet, so most "where does X live" questions don't have an answer in this repo; assume greenfield unless something has been added since.

## Build & test

No Makefile, no SPM `Package.swift`, no Fastlane — drive everything through `xcodebuild` from the repo root, or open `DramaApp.xcodeproj` in Xcode.

```sh
# Build for the simulator
xcodebuild -project DramaApp.xcodeproj -scheme DramaApp \
  -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run unit tests (Swift Testing) + UI tests (XCTest)
xcodebuild -project DramaApp.xcodeproj -scheme DramaApp \
  -destination 'platform=iOS Simulator,name=iPhone 16' test

# Run a single Swift Testing test (use the fully qualified name)
xcodebuild ... test -only-testing:DramaAppTests/DramaAppTests/example

# Run a single XCTest UI test
xcodebuild ... test -only-testing:DramaAppUITests/DramaAppUITests/testExample
```

The iPhone simulator name above must exist locally — list available destinations with `xcrun simctl list devices available`.

## Project layout quirks

- **Synchronized folders (Xcode 16+).** All three groups — `DramaApp/`, `DramaAppTests/`, `DramaAppUITests/` — are `PBXFileSystemSynchronizedRootGroup`s in `project.pbxproj`. **Adding a `.swift` file to the folder is enough; it's auto-included in the target. Do not hand-edit `project.pbxproj` to register new sources** (the old `PBXBuildFile` / `PBXFileReference` entries don't exist here). The only file explicitly excluded from the target is `Info.plist` (see `PBXFileSystemSynchronizedBuildFileExceptionSet`).
- **UIKit + Storyboards, not SwiftUI.** Entry point is `@main AppDelegate` + `SceneDelegate`; the initial view controller comes from `Main.storyboard` (`INFOPLIST_KEY_UIMainStoryboardFile = Main`), with `LaunchScreen.storyboard` as the launch screen. If you add SwiftUI, you'll need to wire it up through the scene or replace the storyboard entry point.
- **Two test frameworks side-by-side.** `DramaAppTests` uses **Swift Testing** (`import Testing`, `@Test`, `#expect`). `DramaAppUITests` uses **XCTest** (`XCUIApplication`). Don't mix them in the same target.

## Swift / build settings worth knowing

These come from `project.pbxproj` and shape how new code should be written:

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — **types are `@MainActor` by default**. Off-main work needs an explicit `nonisolated` or actor annotation; don't assume background isolation.
- `SWIFT_APPROACHABLE_CONCURRENCY = YES` and `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES` — Swift 6-style concurrency diagnostics and stricter member-import visibility are on.
- `IPHONEOS_DEPLOYMENT_TARGET = 26.2`, `SWIFT_VERSION = 5.0`, `TARGETED_DEVICE_FAMILY = "1,2"` (iPhone + iPad).
- `LOCALIZATION_PREFERS_STRING_CATALOGS = YES` + `SWIFT_EMIT_LOC_STRINGS = YES` — use `.xcstrings` String Catalogs for any user-facing strings, not `.strings` files.
- Bundle IDs: app `com.code.review.public.DramaApp`, unit tests `…DramaAppTests`, UI tests `…DramaAppUITests`.
- Code signing is `Automatic` with no team set — device builds will need a team configured in Xcode.

## Not a git repository

`git` commands won't work here until `git init` is run. Mention this to the user before suggesting any git-based workflow.
