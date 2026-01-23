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

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    LabeledContent("Username", value: authManager.username)
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
        }
    }

    private func logout() {
        do {
            try modelContext.delete(model: Bookmark.self)
        } catch {
            print("Failed to delete bookmarks: \(error)")
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
