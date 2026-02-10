//
//  TagBookmarksView.swift
//  PBPins
//
//  Created by Long Wei on 23.01.2026.
//

import SwiftUI
import SafariServices

struct TagBookmarksView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.modelContext) private var modelContext

    let tag: Tag

    @State private var bookmarks: [APIBookmark] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var currentOffset = 0
    @State private var hasMorePages = true
    @State private var selectedBookmark: APIBookmark?
    @State private var isUpdating = false
    @State private var bookmarkToDelete: APIBookmark?

    private let pageSize = 100

    var body: some View {
        List {
            ForEach(bookmarks, id: \.hash) { bookmark in
                Button {
                    selectedBookmark = bookmark
                } label: {
                    TagBookmarkRowView(bookmark: bookmark)
                }
                .foregroundStyle(.primary)
                .contextMenu {
                    if let url = URL(string: bookmark.href) {
                        Link(destination: url) {
                            Label("Open in Safari", systemImage: "safari")
                        }
                    }
                    Button {
                        UIPasteboard.general.string = bookmark.href
                    } label: {
                        Label("Copy URL", systemImage: "doc.on.doc")
                    }
                    Button {
                        Task { await toggleReadStatus(bookmark) }
                    } label: {
                        Label(
                            bookmark.toread == "yes" ? "Mark as Read" : "Mark as Unread",
                            systemImage: bookmark.toread == "yes" ? "checkmark.circle" : "circle"
                        )
                    }
                } preview: {
                    if let url = URL(string: bookmark.href) {
                        SafariPreview(url: url)
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        Task { await toggleReadStatus(bookmark) }
                    } label: {
                        Label(
                            bookmark.toread == "yes" ? "Mark Read" : "Mark Unread",
                            systemImage: bookmark.toread == "yes" ? "checkmark.circle" : "circle"
                        )
                    }
                    .tint(bookmark.toread == "yes" ? .green : .blue)

                    Button {
                        bookmarkToDelete = bookmark
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                }
            }

            if hasMorePages && !bookmarks.isEmpty {
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
        .sheet(item: $selectedBookmark) { bookmark in
            NavigationStack {
                TagBookmarkDetailView(bookmark: bookmark)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                selectedBookmark = nil
                            } label: {
                                Image(systemName: "xmark")
                            }
                        }
                    }
            }
        }
        .overlay {
            if isLoading && bookmarks.isEmpty {
                ProgressView("Loading bookmarks...")
            } else if bookmarks.isEmpty && !isLoading {
                ContentUnavailableView {
                    Label("No Bookmarks", systemImage: "bookmark")
                } description: {
                    Text("No bookmarks found with this tag.")
                }
            }
        }
        .navigationTitle(tag.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
        .contentMargins(.top, 0, for: .scrollContent)
        .task(id: tag.name) {
            await refreshBookmarks()
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
    }

    private func refreshBookmarks() async {
        guard let api = authManager.createAPI() else { return }

        isLoading = true
        errorMessage = nil
        currentOffset = 0

        do {
            let apiBookmarks = try await api.fetchAllBookmarks(start: 0, results: pageSize, tag: tag.name)
            await MainActor.run {
                bookmarks = apiBookmarks
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
            let apiBookmarks = try await api.fetchAllBookmarks(start: currentOffset, results: pageSize, tag: tag.name)
            await MainActor.run {
                bookmarks.append(contentsOf: apiBookmarks)
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

    private func toggleReadStatus(_ bookmark: APIBookmark) async {
        guard let api = authManager.createAPI() else { return }

        isUpdating = true
        let newUnreadStatus = bookmark.toread != "yes"
        let tags = bookmark.tags.isEmpty ? [] : bookmark.tags.split(separator: " ").map(String.init)

        do {
            try await api.updateBookmark(
                url: bookmark.href,
                title: bookmark.description,
                description: bookmark.extended,
                tags: tags,
                isPrivate: bookmark.shared == "no",
                isUnread: newUnreadStatus
            )
            await MainActor.run {
                // Update the local bookmark in the array
                if let index = bookmarks.firstIndex(where: { $0.hash == bookmark.hash }) {
                    var updatedBookmark = bookmarks[index]
                    updatedBookmark.toread = newUnreadStatus ? "yes" : "no"
                    bookmarks[index] = updatedBookmark
                }
                isUpdating = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isUpdating = false
            }
        }
    }

    private func deleteBookmark(_ bookmark: APIBookmark) async {
        guard let api = authManager.createAPI() else { return }

        isUpdating = true

        do {
            try await api.deleteBookmark(url: bookmark.href)
            await MainActor.run {
                bookmarks.removeAll { $0.hash == bookmark.hash }
                isUpdating = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isUpdating = false
            }
        }
    }
}

struct TagBookmarkRowView: View {
    let bookmark: APIBookmark

    private var isUnread: Bool {
        bookmark.toread == "yes"
    }

    private var tags: [String] {
        bookmark.tags.isEmpty ? [] : bookmark.tags.split(separator: " ").map(String.init)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isUnread {
                Circle()
                    .fill(.blue)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(bookmark.description.isEmpty ? bookmark.href : bookmark.description)
                    .font(.headline)
                    .fontWeight(isUnread ? .semibold : .regular)
                    .lineLimit(1)

                Text(bookmark.href)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !tags.isEmpty {
                    Text(tags.joined(separator: " "))
                        .font(.caption2)
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct TagBookmarkDetailView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    let bookmark: APIBookmark

    @State private var title: String = ""
    @State private var url: String = ""
    @State private var tagsText: String = ""
    @State private var isUnread: Bool = false
    @State private var isPrivate: Bool = false
    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage: String?
    @State private var isFetchingTitle = false
    @State private var showingArchive = false
    @State private var showingSafari = false

    private var hasChanges: Bool {
        title != bookmark.description ||
        url != bookmark.href ||
        tagsText != bookmark.tags ||
        isUnread != (bookmark.toread == "yes") ||
        isPrivate != (bookmark.shared == "no")
    }

    var body: some View {
        Form {
            Section("Title") {
                TextField("Title", text: $title)
                Button {
                    Task { await fetchTitleFromURL() }
                } label: {
                    HStack {
                        if isFetchingTitle {
                            ProgressView()
                                .controlSize(.small)
                            Text("Fetching title...")
                        } else {
                            Text("Fetch Title from URL")
                        }
                    }
                }
                .disabled(isFetchingTitle || url.isEmpty)
            }

            Section("URL") {
                HStack {
                    TextField("URL", text: $url)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    if URL(string: url) != nil {
                        Button {
                            showingArchive = true
                        } label: {
                            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        Button {
                            showingSafari = true
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
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
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showingArchive) {
            if let archiveURL = URL(string: "https://archive.is/\(url)") {
                SafariWebView(url: archiveURL)
                    .ignoresSafeArea()
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
        .navigationDestination(isPresented: $showingSafari) {
            if let validURL = URL(string: url) {
                SafariWebView(url: validURL)
                    .ignoresSafeArea()
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
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
        title = bookmark.description
        url = bookmark.href
        tagsText = bookmark.tags
        isUnread = bookmark.toread == "yes"
        isPrivate = bookmark.shared == "no"
    }

    private func deleteBookmark() async {
        guard let api = authManager.createAPI() else { return }

        isDeleting = true

        do {
            try await api.deleteBookmark(url: bookmark.href)
            await MainActor.run {
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

    private func fetchTitleFromURL() async {
        guard let targetURL = URL(string: url) else { return }

        isFetchingTitle = true
        defer { isFetchingTitle = false }

        do {
            if let extractedTitle = try await TitleFetcher.fetchTitle(from: targetURL) {
                self.title = extractedTitle
            }
        } catch {
            errorMessage = "Failed to fetch title: \(error.localizedDescription)"
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
                description: bookmark.extended,
                tags: tags,
                isPrivate: isPrivate,
                isUnread: isUnread
            )
            await MainActor.run {
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
