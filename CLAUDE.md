# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PBPins is a native iOS Pinboard client for iPad, built with Swift 5 and SwiftUI. It uses SwiftData for persistence and includes a share extension for saving bookmarks from other apps.

## Build Commands

Build from command line:
```bash
xcodebuild -project PBPins/PBPins.xcodeproj -scheme PBPins -configuration Debug build
```

Run tests:
```bash
xcodebuild -project PBPins/PBPins.xcodeproj -scheme PBPins test -destination 'platform=iOS Simulator,name=iPad Pro'
```

Open in Xcode:
```bash
open PBPins/PBPins.xcodeproj
```

## Architecture

### Main App (`PBPins/PBPins/`)
- **PBPinsApp.swift**: App entry point, configures SwiftData ModelContainer
- **ContentView.swift**: Root view using NavigationSplitView (master-detail layout)
- **Item.swift**: SwiftData model (currently a template, will be replaced with Pinboard bookmark model)

### Share Extension (`PBPins/PBPinsShareExtension/`)
- **ShareViewController.swift**: UIKit-based SLComposeServiceViewController for iOS share sheet integration
- Allows saving URLs to Pinboard from Safari and other apps

### Key Frameworks
- **SwiftUI**: Declarative UI for the main app
- **SwiftData**: Apple's modern persistence framework (successor to Core Data)
- **UIKit + Social**: Share extension (extensions require UIKit)

### Data Flow
- SwiftData `ModelContainer` is configured in PBPinsApp and injected via `.modelContainer()` modifier
- Views access data via `@Environment(\.modelContext)` and `@Query` property wrappers
- Model mutations use `modelContext.insert()` and `modelContext.delete()`

## Configuration

- Bundle ID: `ch.longwei.PBPins`
- Share Extension Bundle ID: `ch.longwei.PBPins.PBPinsShareExtension`
- Deployment Target: iOS 26.2
- Device Families: iPhone and iPad (iPad-optimized)
