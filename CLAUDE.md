# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PBPins is a native iOS Pinboard client for iPad, built with Swift 5 and SwiftUI. It uses SwiftData for persistence and includes a share extension for saving bookmarks from other apps.

## External Resources

- **Pinboard API Documentation**: https://pinboard.in/api

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

**Core Infrastructure:**
- **PBPinsApp.swift**: App entry point, configures SwiftData ModelContainer and AuthManager environment
- **ContentView.swift**: Root view that routes to LoginView or BookmarkListView based on auth state

**Authentication:**
- **AuthManager.swift**: Observable class managing Pinboard API token storage (UserDefaults), login state, and PinboardAPI factory method

**API Integration:**
- **PinboardAPI.swift**: Pinboard API client using async/await
  - Base URL: `https://api.pinboard.in/v1`
  - Currently implements `fetchRecentBookmarks(count:)` via `/posts/recent`
  - Defines `APIBookmark` and `PostsResponse` Codable structs for response parsing
  - Custom `PinboardError` enum with localized error descriptions

**Data Model:**
- **Bookmark.swift**: SwiftData @Model for persisting bookmarks locally
  - Properties: id (hash), url, title, desc, tags (array), created, updated, isPrivate

**Views:**
- **LoginView.swift**: API token input form with validation and test API call
- **BookmarkListView.swift**: NavigationSplitView with master-detail layout (iPad-optimized)
  - Includes nested `BookmarkRowView` and `BookmarkDetailView`
  - Handles bookmark sync from API to SwiftData
- **SettingsView.swift**: Account info display and logout functionality

### Share Extension (`PBPins/PBPinsShareExtension/`)
- **ShareViewController.swift**: UIKit-based SLComposeServiceViewController (template, not yet functional)

### Key Frameworks
- **SwiftUI**: Declarative UI for the main app
- **SwiftData**: Apple's modern persistence framework (successor to Core Data)
- **UIKit + Social**: Share extension (extensions require UIKit)

### Data Flow
1. **Authentication**: User enters API token → LoginView validates via test API call → AuthManager stores in UserDefaults
2. **Bookmark Sync**: BookmarkListView triggers refresh → AuthManager creates PinboardAPI instance → Fetches from API → Syncs to SwiftData
3. **Display**: @Query fetches bookmarks from SwiftData → NavigationSplitView renders list/detail
4. **Logout**: SettingsView deletes all Bookmark records → AuthManager clears token → Routes to LoginView

## Configuration

- Bundle ID: `ch.longwei.PBPins`
- Share Extension Bundle ID: `ch.longwei.PBPins.PBPinsShareExtension`
- Deployment Target: iOS 26.2
- Device Families: iPhone and iPad (iPad-optimized)
