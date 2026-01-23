//
//  BookmarkListView.swift
//  PBPins
//
//  Created by Long Wei on 22.01.2026.
//

import SwiftUI
import SwiftData

enum BookmarkFilter: String, CaseIterable {
    case all = "All"
    case unread = "Unread"
}

struct BookmarkListView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Bookmark.created, order: .reverse) private var bookmarks: [Bookmark]

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingSettings = false
    @State private var selectedFilter: BookmarkFilter = .all
    @State private var isUpdating = false

    private var filteredBookmarks: [Bookmark] {
        switch selectedFilter {
        case .all:
            return bookmarks
        case .unread:
            return bookmarks.filter { $0.isUnread }
        }
    }

    var body: some View {
        NavigationSplitView {
            Group {
                if filteredBookmarks.isEmpty && !isLoading {
                    ContentUnavailableView {
                        Label(selectedFilter == .unread ? "No Unread Bookmarks" : "No Bookmarks", systemImage: "bookmark")
                    } description: {
                        Text(selectedFilter == .unread ? "You've read all your bookmarks." : "Pull to refresh to load your bookmarks.")
                    }
                } else {
                    List(filteredBookmarks) { bookmark in
                        NavigationLink {
                            BookmarkDetailView(bookmark: bookmark)
                        } label: {
                            BookmarkRowView(bookmark: bookmark)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                Task { await toggleReadStatus(bookmark) }
                            } label: {
                                Label(
                                    bookmark.isUnread ? "Mark Read" : "Mark Unread",
                                    systemImage: bookmark.isUnread ? "checkmark.circle" : "circle"
                                )
                            }
                            .tint(bookmark.isUnread ? .green : .blue)
                        }
                    }
                    .disabled(isUpdating)
                }
            }
            .safeAreaInset(edge: .top) {
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(BookmarkFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
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

    private func toggleReadStatus(_ bookmark: Bookmark) async {
        guard let api = authManager.createAPI() else { return }

        isUpdating = true
        let newUnreadStatus = !bookmark.isUnread

        do {
            try await api.updateBookmark(
                url: bookmark.url,
                title: bookmark.title,
                description: bookmark.desc,
                tags: bookmark.tags,
                isPrivate: bookmark.isPrivate,
                isUnread: newUnreadStatus
            )
            await MainActor.run {
                bookmark.isUnread = newUnreadStatus
                bookmark.updated = Date()
                isUpdating = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isUpdating = false
            }
        }
    }

    private func syncBookmarks(_ apiBookmarks: [APIBookmark]) {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        let existingIDs = Set(bookmarks.map { $0.id })
        let apiIDs = Set(apiBookmarks.map { $0.hash })

        // Delete bookmarks that no longer exist on Pinboard
        for bookmark in bookmarks {
            if !apiIDs.contains(bookmark.id) {
                modelContext.delete(bookmark)
            }
        }

        for apiBookmark in apiBookmarks {
            let created = dateFormatter.date(from: apiBookmark.time) ?? Date()
            let tags = apiBookmark.tags.isEmpty ? [] : apiBookmark.tags.split(separator: " ").map(String.init)
            let isPrivate = apiBookmark.shared == "no"
            let isUnread = apiBookmark.toread == "yes"

            if existingIDs.contains(apiBookmark.hash) {
                if let existing = bookmarks.first(where: { $0.id == apiBookmark.hash }) {
                    existing.url = apiBookmark.href
                    existing.title = apiBookmark.description
                    existing.desc = apiBookmark.extended
                    existing.tags = tags
                    existing.updated = created
                    existing.isPrivate = isPrivate
                    existing.isUnread = isUnread
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
                    isPrivate: isPrivate,
                    isUnread: isUnread
                )
                modelContext.insert(bookmark)
            }
        }
    }
}

struct BookmarkRowView: View {
    let bookmark: Bookmark

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if bookmark.isUnread {
                Circle()
                    .fill(.blue)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(bookmark.title.isEmpty ? bookmark.url : bookmark.title)
                    .font(.headline)
                    .fontWeight(bookmark.isUnread ? .semibold : .regular)
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
        }
        .padding(.vertical, 2)
    }
}

struct BookmarkDetailView: View {
    @Environment(AuthManager.self) private var authManager
    @Bindable var bookmark: Bookmark

    @State private var title: String = ""
    @State private var url: String = ""
    @State private var tagsText: String = ""
    @State private var isUnread: Bool = false
    @State private var isPrivate: Bool = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var hasChanges: Bool {
        title != bookmark.title ||
        url != bookmark.url ||
        tagsText != bookmark.tags.joined(separator: " ") ||
        isUnread != bookmark.isUnread ||
        isPrivate != bookmark.isPrivate
    }

    var body: some View {
        Form {
            Section("Title") {
                TextField("Title", text: $title)
            }

            Section("URL") {
                TextField("URL", text: $url)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
            }

            Section("Tags") {
                TextField("Tags (space-separated)", text: $tagsText)
                    .textInputAutocapitalization(.never)
            }

            Section {
                Toggle("Unread", isOn: $isUnread)
                Toggle("Private", isOn: $isPrivate)
            }

            Section("Info") {
                LabeledContent("Created", value: bookmark.created, format: .dateTime)
                LabeledContent("Updated", value: bookmark.updated, format: .dateTime)
            }
        }
        .navigationTitle("Bookmark")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") {
                        Task { await saveChanges() }
                    }
                    .disabled(!hasChanges || title.isEmpty || url.isEmpty)
                }
            }
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
        .onAppear {
            loadBookmarkData()
        }
        .onChange(of: bookmark.id) {
            loadBookmarkData()
        }
    }

    private func loadBookmarkData() {
        title = bookmark.title
        url = bookmark.url
        tagsText = bookmark.tags.joined(separator: " ")
        isUnread = bookmark.isUnread
        isPrivate = bookmark.isPrivate
    }

    private func saveChanges() async {
        guard let api = authManager.createAPI() else { return }

        isSaving = true
        let tags = tagsText.isEmpty ? [] : tagsText.split(separator: " ").map(String.init)

        do {
            try await api.updateBookmark(
                url: url,
                title: title,
                description: bookmark.desc,
                tags: tags,
                isPrivate: isPrivate,
                isUnread: isUnread
            )
            await MainActor.run {
                bookmark.title = title
                bookmark.url = url
                bookmark.tags = tags
                bookmark.isUnread = isUnread
                bookmark.isPrivate = isPrivate
                bookmark.updated = Date()
                isSaving = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}

#Preview {
    BookmarkListView()
        .environment(AuthManager())
        .modelContainer(for: Bookmark.self, inMemory: true)
}
