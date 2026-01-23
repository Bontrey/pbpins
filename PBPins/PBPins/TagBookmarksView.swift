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
                } preview: {
                    if let url = URL(string: bookmark.href) {
                        SafariPreview(url: url)
                    }
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
        .sheet(item: $selectedBookmark) { bookmark in
            NavigationStack {
                TagBookmarkDetailView(bookmark: bookmark)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                selectedBookmark = nil
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
                    Text(tags.joined(separator: ", "))
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
                TextField("Tags (space-separated)", text: $tagsText)
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
