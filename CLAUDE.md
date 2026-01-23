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
- **PBPinsApp.swift**: App entry point, configures SwiftData ModelContainer with `Bookmark` and `Tag` models, initializes AuthManager environment
- **ContentView.swift**: Root view that routes to LoginView or BookmarkListView based on auth state

**Authentication:**
- **AuthManager.swift**: @Observable class managing Pinboard API token storage
  - Uses App Group UserDefaults (`group.ch.longwei.PBPins`) for share extension access
  - Stores token in both standard and App Group UserDefaults
  - Extracts username from API token (splits on ":" character)
  - Validates token format (must contain ":")
  - Factory method `createAPI()` returns authenticated PinboardAPI instance

**API Integration:**
- **PinboardAPI.swift**: Pinboard API client using async/await
  - Base URL: `https://api.pinboard.in/v1`
  - Endpoints implemented:
    - `fetchRecentBookmarks(count:)` - `/posts/recent`
    - `fetchAllBookmarks(start:, results:, tag:)` - `/posts/all` with pagination and optional tag filter
    - `updateBookmark(...)` - `/posts/add` (creates or updates)
    - `deleteBookmark(url:)` - `/posts/delete`
    - `fetchAllTags()` - `/tags/get` returns dictionary of tag names to counts
  - `APIBookmark` struct: href, description, extended, meta, hash, time, shared, toread, tags
  - `PostsResponse` wrapper for `/posts/recent` response
  - `PinboardError` enum: invalidURL, invalidResponse, httpError(Int), decodingError(Error), networkError(Error)

**Data Models:**
- **Bookmark.swift**: SwiftData @Model for persisting bookmarks locally
  - Properties: id (hash), url, title, desc, tags (array), created, updated, isPrivate, isUnread
- **Tag.swift**: SwiftData @Model for caching tag metadata
  - Properties: name (unique identifier), count (bookmark count for this tag)

**Utilities:**
- **TitleFetcher.swift**: Static utility for extracting page titles from URLs
  - Uses URLSession with 10-second timeout and Safari user agent
  - HTML parsing via NSRegularExpression for `<title>` and `og:title` meta tags
  - HTML entity decoding for common entities (&amp;, &lt;, &gt;, &quot;, &ndash;, &mdash;, etc.)

**Views:**
- **LoginView.swift**: API token input form with validation and test API call
- **BookmarkListView.swift**: NavigationSplitView with master-detail layout (iPad-optimized)
  - **Filtering**: All/Unread/Tags segmented picker with `BookmarkFilter` enum
  - **Infinite scroll**: Pagination with 100 bookmarks per page, offset tracking
  - **Sync logic**: Handles deletions (removes local bookmarks not in API response within date range)
  - **Tag management**: Lazy loads tags when Tags filter selected, syncs with API
  - **Scene phase detection**: Checks `needs_refresh` flag in App Group UserDefaults on app resume to auto-refresh after share extension use
  - **Nested views**:
    - `BookmarkRowView`: Blue dot for unread, title/URL/tags display
    - `BookmarkDetailView`: Full edit form (title with fetch button, URL, tags, unread, private), timestamps display, delete with confirmation
    - `SafariPreview` / `SafariWebView`: UIViewControllerRepresentable for URL preview
  - **Interactions**: Pull-to-refresh, swipe actions (mark read/unread, delete), context menus
- **TagBookmarksView.swift**: Tag-filtered bookmarks view (works with APIBookmark directly from API)
  - Displays bookmarks for a specific tag using API filtering
  - Similar features: pagination, pull-to-refresh, swipe actions, context menus
  - Detail view presented as sheet (not navigation)
  - Nested views: `TagBookmarkRowView`, `TagBookmarkDetailView`
- **SettingsView.swift**: Account info and data management
  - Displays username from authManager
  - "Delete All Local Data" button (deletes Bookmark/Tag records, data stays on Pinboard)
  - "Log Out" button (deletes local data and clears authentication)
  - Confirmation dialogs for both destructive actions

### Share Extension (`PBPins/PBPinsShareExtension/`)
- **ShareViewController.swift**: Fully functional share extension
  - UIViewController hosting SwiftUI `ShareExtensionView`
  - **URL extraction**: Supports `UTType.url` and `UTType.plainText`, validates HTTP/HTTPS
  - **Title fetching**: Same logic as TitleFetcher (async HTML fetch with regex extraction)
  - **Form fields**: URL (editable), title (editable with auto-fetch), tags, unread toggle (default: true), private toggle (default: false)
  - **Tracking parameter removal**: Detects and removes 50+ common tracking parameters (utm_*, fbclid, gclid, twclid, msclkid, etc.)
  - **SharePinboardAPI**: Minimal API client for `/posts/add` endpoint
  - **App Group integration**: Reads token from shared UserDefaults, sets `needs_refresh` flag on save
  - **ShareError** enum: invalidURL, invalidResponse, httpError(Int) with localized descriptions

### Key Frameworks
- **SwiftUI**: Declarative UI for the main app and share extension view
- **SwiftData**: Apple's modern persistence framework (successor to Core Data)
- **UIKit**: Share extension host controller
- **SafariServices**: In-app Safari preview

### Data Flow
1. **Authentication**: User enters API token → LoginView validates via test API call → AuthManager stores in standard + App Group UserDefaults
2. **Bookmark Sync**: BookmarkListView triggers refresh → Fetches paginated results from `/posts/all` → Syncs to SwiftData (insert/update/delete)
3. **Tag Sync**: Tags filter selected → Fetches from `/tags/get` → Syncs to SwiftData Tag model (insert/update/delete)
4. **Display**: @Query fetches bookmarks from SwiftData with sorting → NavigationSplitView renders filterable list/detail
5. **Tag Browsing**: Tags filter → TagBookmarksView fetches directly from API with tag filter → Displays without local persistence
6. **Editing**: BookmarkDetailView edits → Syncs changes to API via `/posts/add` → Updates local SwiftData
7. **Deletion**: Swipe or detail view delete → API `/posts/delete` → Removes from SwiftData
8. **Share Extension**: Extracts URL → Optionally removes tracking params → Fetches page title → Posts to API → Sets `needs_refresh` flag → Closes extension
9. **Share Extension Sync**: App resumes → Detects `needs_refresh` flag → Auto-refreshes bookmarks
10. **Logout**: SettingsView deletes all Bookmark/Tag records → AuthManager clears tokens → Routes to LoginView

## Configuration

- Bundle ID: `ch.longwei.PBPins`
- Share Extension Bundle ID: `ch.longwei.PBPins.PBPinsShareExtension`
- App Group ID: `group.ch.longwei.PBPins`
- Deployment Target: iOS 26.2
- Device Families: iPhone and iPad (iPad-optimized)
