//
//  BookmarkListView.swift
//  PBPins
//
//  Created by Long Wei on 22.01.2026.
//

import SwiftUI
import SwiftData

struct BookmarkListView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Bookmark.created, order: .reverse) private var bookmarks: [Bookmark]

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingSettings = false

    var body: some View {
        NavigationSplitView {
            Group {
                if bookmarks.isEmpty && !isLoading {
                    ContentUnavailableView {
                        Label("No Bookmarks", systemImage: "bookmark")
                    } description: {
                        Text("Pull to refresh to load your bookmarks.")
                    }
                } else {
                    List(bookmarks) { bookmark in
                        NavigationLink {
                            BookmarkDetailView(bookmark: bookmark)
                        } label: {
                            BookmarkRowView(bookmark: bookmark)
                        }
                    }
                }
            }
            .navigationTitle("Bookmarks")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Button {
                            Task { await refreshBookmarks() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                }
            }
            .refreshable {
                await refreshBookmarks()
            }
            .task {
                if bookmarks.isEmpty {
                    await refreshBookmarks()
                }
            }
        } detail: {
            Text("Select a bookmark")
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
    }

    private func refreshBookmarks() async {
        guard let api = authManager.createAPI() else { return }

        isLoading = true
        errorMessage = nil

        do {
            let apiBookmarks = try await api.fetchRecentBookmarks(count: 100)
            await MainActor.run {
                syncBookmarks(apiBookmarks)
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func syncBookmarks(_ apiBookmarks: [APIBookmark]) {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        let existingIDs = Set(bookmarks.map { $0.id })

        for apiBookmark in apiBookmarks {
            let created = dateFormatter.date(from: apiBookmark.time) ?? Date()
            let tags = apiBookmark.tags.isEmpty ? [] : apiBookmark.tags.split(separator: " ").map(String.init)
            let isPrivate = apiBookmark.shared == "no"

            if existingIDs.contains(apiBookmark.hash) {
                if let existing = bookmarks.first(where: { $0.id == apiBookmark.hash }) {
                    existing.url = apiBookmark.href
                    existing.title = apiBookmark.description
                    existing.desc = apiBookmark.extended
                    existing.tags = tags
                    existing.updated = created
                    existing.isPrivate = isPrivate
                }
            } else {
                let bookmark = Bookmark(
                    id: apiBookmark.hash,
                    url: apiBookmark.href,
                    title: apiBookmark.description,
                    desc: apiBookmark.extended,
                    tags: tags,
                    created: created,
                    updated: created,
                    isPrivate: isPrivate
                )
                modelContext.insert(bookmark)
            }
        }
    }
}

struct BookmarkRowView: View {
    let bookmark: Bookmark

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(bookmark.title.isEmpty ? bookmark.url : bookmark.title)
                .font(.headline)
                .lineLimit(1)

            Text(bookmark.url)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if !bookmark.tags.isEmpty {
                Text(bookmark.tags.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.blue)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

struct BookmarkDetailView: View {
    let bookmark: Bookmark

    var body: some View {
        Form {
            Section("Title") {
                Text(bookmark.title.isEmpty ? "(No title)" : bookmark.title)
            }

            Section("URL") {
                Text(bookmark.url)
                    .textSelection(.enabled)
            }

            if !bookmark.desc.isEmpty {
                Section("Description") {
                    Text(bookmark.desc)
                }
            }

            if !bookmark.tags.isEmpty {
                Section("Tags") {
                    Text(bookmark.tags.joined(separator: ", "))
                }
            }

            Section("Info") {
                LabeledContent("Created", value: bookmark.created, format: .dateTime)
                LabeledContent("Updated", value: bookmark.updated, format: .dateTime)
                LabeledContent("Private", value: bookmark.isPrivate ? "Yes" : "No")
            }
        }
        .navigationTitle("Bookmark")
    }
}

#Preview {
    BookmarkListView()
        .environment(AuthManager())
        .modelContainer(for: Bookmark.self, inMemory: true)
}
