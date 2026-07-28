//
//  ghostWriterApp.swift
//  ghostWriter
//
//  Created by Marco Salsiccia on 7/27/26.
//

import SwiftUI

@main
struct ghostWriterApp: App {
    // The store and settings are created once and shared through the
    // environment, so every screen reads the same state.
    @State private var store = DocumentStore()
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(settings)
                // A theme override applies to the whole app; `nil` means follow
                // the system, which is the default.
                .preferredColorScheme(settings.appearance.colorScheme)
        }
    }
}
