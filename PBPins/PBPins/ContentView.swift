//
//  ContentView.swift
//  PBPins
//
//  Created by Long Wei on 22.01.2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        if authManager.isLoggedIn {
            BookmarkListView()
        } else {
            LoginView()
        }
    }
}

#Preview {
    ContentView()
        .environment(AuthManager())
        .modelContainer(for: Bookmark.self, inMemory: true)
}
