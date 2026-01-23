//
//  SettingsView.swift
//  PBPins
//
//  Created by Long Wei on 22.01.2026.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingLogoutConfirmation = false
    @State private var showingDeleteDataConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    LabeledContent("Username", value: authManager.username)
                }

                Section {
                    Button("Delete All Local Data", role: .destructive) {
                        showingDeleteDataConfirmation = true
                    }
                } footer: {
                    Text("Deletes all cached bookmarks and tags. Data will be re-fetched from Pinboard.")
                }

                Section {
                    Button("Log Out", role: .destructive) {
                        showingLogoutConfirmation = true
                    }
                } footer: {
                    Text("Logging out will delete all local data.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Log Out", isPresented: $showingLogoutConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Log Out", role: .destructive) {
                    logout()
                }
            } message: {
                Text("Are you sure you want to log out? All local bookmarks will be deleted.")
            }
            .alert("Delete All Local Data", isPresented: $showingDeleteDataConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    deleteAllData()
                }
            } message: {
                Text("This will delete all cached bookmarks and tags. Your data on Pinboard will not be affected.")
            }
        }
    }

    private func deleteAllData() {
        do {
            try modelContext.delete(model: Bookmark.self)
            try modelContext.delete(model: Tag.self)
        } catch {
            print("Failed to delete data: \(error)")
        }
        dismiss()
    }

    private func logout() {
        do {
            try modelContext.delete(model: Bookmark.self)
            try modelContext.delete(model: Tag.self)
        } catch {
            print("Failed to delete data: \(error)")
        }
        authManager.logout()
        dismiss()
    }
}

#Preview {
    SettingsView()
        .environment(AuthManager())
        .modelContainer(for: Bookmark.self, inMemory: true)
}
