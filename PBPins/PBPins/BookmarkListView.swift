//
//  BookmarkListView.swift
//  PBPins
//
//  Created by Long Wei on 22.01.2026.
//

import SwiftUI
import SwiftData
import SafariServices

enum BookmarkFilter: String, CaseIterable {
    case all = "All"
    case unread = "Unread"
    case tags = "Tags"
}

struct BookmarkListView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Bookmark.created, order: .reverse) private var bookmarks: [Bookmark]

    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var showingSettings = false
    @State private var selectedFilter: BookmarkFilter = .all
    @State private var isUpdating = false
    @State private var bookmarkToDelete: Bookmark?
    @State private var currentOffset = 0
    @State private var hasMorePages = true
    @State private var selectedBookmarkID: String?
    @Query(sort: \Tag.count, order: .reverse) private var tags: [Tag]
    @State private var isLoadingTags = false

    private let pageSize = 100

    private var filteredBookmarks: [Bookmark] {
        switch selectedFilter {
        case .all:
            return bookmarks
        case .unread:
            return bookmarks.filter { $0.isUnread }
        case .tags:
            return bookmarks
        }
    }

    private var selectedBookmark: Bookmark? {
        guard let id = selectedBookmarkID else { return nil }
        return bookmarks.first { $0.id == id }
    }

    var body: some View {
        NavigationSplitView {
            Group {
                if selectedFilter == .tags {
                    if isLoadingTags {
                        ProgressView("Loading tags...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if tags.isEmpty {
                        ContentUnavailableView {
                            Label("No Tags", systemImage: "tag")
                        } description: {
                            Text("Your bookmarks don't have any tags yet.")
                        }
                    } else {
                        NavigationStack {
                            List {
                                ForEach(tags) { tag in
                                    NavigationLink {
                                        TagBookmarksView(tag: tag)
                                    } label: {
                                        HStack {
                                            Label(tag.name, systemImage: "tag")
                                            Spacer()
                                            Text("\(tag.count)")
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .navigationTitle("Tags")
                        }
                    }
                } else if filteredBookmarks.isEmpty && !isLoading {
                    ContentUnavailableView {
                        Label(selectedFilter == .unread ? "No Unread Bookmarks" : "No Bookmarks", systemImage: "bookmark")
                    } description: {
                        Text(selectedFilter == .unread ? "You've read all your bookmarks." : "Pull to refresh to load your bookmarks.")
                    }
                } else {
                    List(selection: $selectedBookmarkID) {
                        ForEach(filteredBookmarks) { bookmark in
                            NavigationLink(value: bookmark.id) {
                                BookmarkRowView(bookmark: bookmark)
                            }
                            .contextMenu {
                                if let url = URL(string: bookmark.url) {
                                    Link(destination: url) {
                                        Label("Open in Safari", systemImage: "safari")
                                    }
                                }
                                Button {
                                    Task { await toggleReadStatus(bookmark) }
                                } label: {
                                    Label(
                                        bookmark.isUnread ? "Mark as Read" : "Mark as Unread",
                                        systemImage: bookmark.isUnread ? "checkmark.circle" : "circle"
                                    )
                                }
                            } preview: {
                                if let url = URL(string: bookmark.url) {
                                    SafariPreview(url: url)
                                }
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

                                Button {
                                    bookmarkToDelete = bookmark
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .tint(.red)
                            }
                        }

                        if hasMorePages {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .padding(.vertical, 8)
                                Spacer()
                            }
                            .onAppear {
                                Task { await loadMoreBookmarks() }
                            }
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
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    // Only refresh if a bookmark was saved via share extension
                    if let groupDefaults = UserDefaults(suiteName: "group.ch.longwei.PBPins"),
                       groupDefaults.bool(forKey: "needs_refresh") {
                        groupDefaults.set(false, forKey: "needs_refresh")
                        Task { await refreshBookmarks() }
                    }
                }
            }
        } detail: {
            if let bookmark = selectedBookmark {
                NavigationStack {
                    BookmarkDetailView(bookmark: bookmark)
                }
            } else {
                Text("Select a bookmark")
                    .foregroundStyle(.secondary)
            }
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
        .confirmationDialog("Delete Bookmark", isPresented: .init(
            get: { bookmarkToDelete != nil },
            set: { if !$0 { bookmarkToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let bookmark = bookmarkToDelete {
                    Task { await deleteBookmark(bookmark) }
                }
            }
            Button("Cancel", role: .cancel) {
                bookmarkToDelete = nil
            }
        } message: {
            Text("Are you sure you want to delete this bookmark? This cannot be undone.")
        }
        .onChange(of: selectedFilter) { _, newFilter in
            if newFilter == .tags && tags.isEmpty {
                Task { await fetchTags() }
            }
        }
    }

    private func fetchTags() async {
        guard let api = authManager.createAPI() else { return }

        isLoadingTags = true
        errorMessage = nil

        do {
            let apiTags = try await api.fetchAllTags()
            await MainActor.run {
                syncTags(apiTags)
                isLoadingTags = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoadingTags = false
            }
        }
    }

    private func syncTags(_ apiTags: [(tag: String, count: Int)]) {
        let existingNames = Set(tags.map { $0.name })
        let apiNames = Set(apiTags.map { $0.tag })

        // Delete tags not in API response
        for tag in tags where !apiNames.contains(tag.name) {
            modelContext.delete(tag)
        }

        // Insert or update tags
        for apiTag in apiTags {
            if let existing = tags.first(where: { $0.name == apiTag.tag }) {
                existing.count = apiTag.count
            } else {
                let tag = Tag(name: apiTag.tag, count: apiTag.count)
                modelContext.insert(tag)
            }
        }
    }

    private func refreshBookmarks() async {
        guard let api = authManager.createAPI() else { return }

        isLoading = true
        errorMessage = nil
        currentOffset = 0

        do {
            let apiBookmarks = try await api.fetchAllBookmarks(start: 0, results: pageSize)
            await MainActor.run {
                syncBookmarks(apiBookmarks, isFullRefresh: true)
                hasMorePages = apiBookmarks.count == pageSize
                currentOffset = apiBookmarks.count
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func loadMoreBookmarks() async {
        guard !isLoadingMore, let api = authManager.createAPI() else { return }

        isLoadingMore = true
        errorMessage = nil

        do {
            let apiBookmarks = try await api.fetchAllBookmarks(start: currentOffset, results: pageSize)
            await MainActor.run {
                syncBookmarks(apiBookmarks, isFullRefresh: false)
                hasMorePages = apiBookmarks.count == pageSize
                currentOffset += apiBookmarks.count
                isLoadingMore = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoadingMore = false
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

    private func deleteBookmark(_ bookmark: Bookmark) async {
        guard let api = authManager.createAPI() else { return }

        isUpdating = true

        do {
            try await api.deleteBookmark(url: bookmark.url)
            await MainActor.run {
                modelContext.delete(bookmark)
                isUpdating = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isUpdating = false
            }
        }
    }

    private func syncBookmarks(_ apiBookmarks: [APIBookmark], isFullRefresh: Bool) {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        let existingIDs = Set(bookmarks.map { $0.id })
        let apiIDs = Set(apiBookmarks.map { $0.hash })

        // Parse dates from API bookmarks to find the date range
        let apiDates = apiBookmarks.compactMap { dateFormatter.date(from: $0.time) }
        let oldestDate = apiDates.min()
        let newestDate = apiDates.max()

        // Delete local bookmarks that aren't in the API response
        if let oldest = oldestDate, let newest = newestDate {
            for bookmark in bookmarks {
                // On full refresh (first page), also delete bookmarks newer than the newest API result
                // since those must have been deleted from Pinboard
                let isNewerThanFetched = isFullRefresh && bookmark.created > newest
                let isInDateRange = bookmark.created >= oldest && bookmark.created <= newest
                if (isInDateRange || isNewerThanFetched) && !apiIDs.contains(bookmark.id) {
                    modelContext.delete(bookmark)
                }
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

struct SafariPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

struct SafariWebView: UIViewControllerRepresentable {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let safari = SFSafariViewController(url: url, configuration: config)
        safari.delegate = context.coordinator
        return safari
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}

    class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let dismiss: DismissAction

        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            dismiss()
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
                    Text(bookmark.tags.joined(separator: " "))
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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var bookmark: Bookmark

    @State private var title: String = ""
    @State private var url: String = ""
    @State private var tagsText: String = ""
    @State private var isUnread: Bool = false
    @State private var isPrivate: Bool = false
    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var showingDeleteConfirmation = false
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
                if let validURL = URL(string: url) {
                    NavigationLink {
                        SafariWebView(url: validURL)
                            .ignoresSafeArea()
                            .toolbar(.hidden, for: .navigationBar)
                    } label: {
                        TextField("URL", text: $url)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                    }
                } else {
                    TextField("URL", text: $url)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }
            }

            Section("Tags") {
                TextField("Tags", text: $tagsText)
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

            Section {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        if isDeleting {
                            ProgressView()
                        } else {
                            Text("Delete Bookmark")
                        }
                        Spacer()
                    }
                }
                .disabled(isDeleting)
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
        .confirmationDialog("Delete Bookmark", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { await deleteBookmark() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this bookmark? This cannot be undone.")
        }
    }

    private func loadBookmarkData() {
        title = bookmark.title
        url = bookmark.url
        tagsText = bookmark.tags.joined(separator: " ")
        isUnread = bookmark.isUnread
        isPrivate = bookmark.isPrivate
    }

    private func deleteBookmark() async {
        guard let api = authManager.createAPI() else { return }

        isDeleting = true

        do {
            try await api.deleteBookmark(url: bookmark.url)
            await MainActor.run {
                modelContext.delete(bookmark)
                isDeleting = false
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isDeleting = false
            }
        }
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
