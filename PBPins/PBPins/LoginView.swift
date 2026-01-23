//
//  LoginView.swift
//  PBPins
//
//  Created by Long Wei on 22.01.2026.
//

import SwiftUI

struct LoginView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var apiToken = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("API Token", text: $apiToken)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Pinboard Credentials")
                } footer: {
                    Text("Enter your API token from pinboard.in/settings/password (format: username:TOKEN)")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        login()
                    } label: {
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Log In")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(apiToken.isEmpty || !apiToken.contains(":") || isLoading)
                }
            }
            .navigationTitle("PBPins")
        }
    }

    private func login() {
        guard !apiToken.isEmpty, apiToken.contains(":") else { return }

        isLoading = true
        errorMessage = nil

        Task {
            let api = PinboardAPI(apiToken: apiToken)
            do {
                _ = try await api.fetchRecentBookmarks(count: 1)
                await MainActor.run {
                    authManager.login(apiToken: apiToken)
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Login failed: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
}

#Preview {
    LoginView()
        .environment(AuthManager())
}
