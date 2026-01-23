//
//  PBPinsApp.swift
//  PBPins
//
//  Created by Long Wei on 22.01.2026.
//

import SwiftUI
import SwiftData

@main
struct PBPinsApp: App {
    @State private var authManager = AuthManager()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Bookmark.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authManager)
        }
        .modelContainer(sharedModelContainer)
    }
}
