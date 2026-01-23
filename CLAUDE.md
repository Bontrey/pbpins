# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PBPins is a native iOS Pinboard client for iPad, built with Swift 5 and SwiftUI. It uses SwiftData for persistence and includes a fully functional share extension for saving bookmarks from other apps.

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
- **AuthManager.swift**: Observable class managing Pinboard API token storage
  - Uses App Group UserDefaults (`group.ch.longwei.PBPins`) for share extension access
  - Stores token in both standard and App Group UserDefaults
  - Extracts username from API token (splits on ":" character)
  - Validates token format (must contain ":")

**API Integration:**
- **PinboardAPI.swift**: Pinboard API client using async/await
  - Base URL: `https://api.pinboard.in/v1`
  - Endpoints implemented:
    - `fetchRecentBookmarks(count:)` - `/posts/recent`
    - `fetchAllBookmarks(start:, results:)` - `/posts/all` with pagination
    - `updateBookmark(...)` - `/posts/add` (creates or updates)
    - `deleteBookmark(url:)` - `/posts/delete`
  - `APIBookmark` struct: href, description, extended, meta, hash, time, shared, toread, tags
  - `PostsResponse` wrapper for `/posts/recent` response
  - `PinboardError` enum: invalidURL, invalidResponse, httpError(Int), decodingError(Error), networkError(Error)

**Data Model:**
- **Bookmark.swift**: SwiftData @Model for persisting bookmarks locally
  - Properties: id (hash), url, title, desc, tags (array), created, updated, isPrivate, isUnread

**Views:**
- **LoginView.swift**: API token input form with validation and test API call
- **BookmarkListView.swift**: NavigationSplitView with master-detail layout (iPad-optimized)
  - **Filtering**: All/Unread segmented picker with `BookmarkFilter` enum
  - **Infinite scroll**: Pagination with 100 bookmarks per page, offset tracking
  - **Sync logic**: Handles deletions (removes local bookmarks not in API response within date range)
  - **Nested views**:
    - `BookmarkRowView`: Blue dot for unread, title/URL/tags display
    - `BookmarkDetailView`: Full edit form (title, URL, tags, unread, private), delete with confirmation
    - `SafariPreview`: UIViewControllerRepresentable for URL preview
  - **Interactions**: Pull-to-refresh, swipe actions (mark read/unread, delete), context menus
- **SettingsView.swift**: Account info display (username extraction) and logout with confirmation

### Share Extension (`PBPins/PBPinsShareExtension/`)
- **ShareViewController.swift**: Fully functional share extension
  - UIViewController hosting SwiftUI `ShareExtensionView`
  - **URL extraction**: Supports `UTType.url` and `UTType.plainText`, validates HTTP/HTTPS
  - **Title fetching**: Async HTML fetch with regex extraction (`<title>`, `og:title`), HTML entity decoding
  - **Form fields**: URL (read-only), title (editable), tags, unread toggle, private toggle
  - **SharePinboardAPI**: Minimal API client for `/posts/add` endpoint
  - **App Group integration**: Reads token from shared UserDefaults

### Key Frameworks
- **SwiftUI**: Declarative UI for the main app and share extension view
- **SwiftData**: Apple's modern persistence framework (successor to Core Data)
- **UIKit**: Share extension host controller
- **SafariServices**: In-app Safari preview

### Data Flow
1. **Authentication**: User enters API token → LoginView validates via test API call → AuthManager stores in standard + App Group UserDefaults
2. **Bookmark Sync**: BookmarkListView triggers refresh → Fetches paginated results from `/posts/all` → Syncs to SwiftData (insert/update/delete)
3. **Display**: @Query fetches bookmarks from SwiftData with sorting → NavigationSplitView renders filterable list/detail
4. **Editing**: BookmarkDetailView edits → Syncs changes to API via `/posts/add` → Updates local SwiftData
5. **Deletion**: Swipe or detail view delete → API `/posts/delete` → Removes from SwiftData
6. **Share Extension**: Extracts URL from share sheet → Fetches page title → Posts to API → Closes extension
7. **Logout**: SettingsView deletes all Bookmark records → AuthManager clears tokens → Routes to LoginView

## Configuration

- Bundle ID: `ch.longwei.PBPins`
- Share Extension Bundle ID: `ch.longwei.PBPins.PBPinsShareExtension`
- App Group ID: `group.ch.longwei.PBPins`
- Deployment Target: iOS 26.2
- Device Families: iPhone and iPad (iPad-optimized)
