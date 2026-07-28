//
//  ContentView.swift
//  ghostWriter
//
//  Created by Marco Salsiccia on 7/27/26.
//

import SwiftUI

/// Root of the app. The library is the home screen; everything else is reached
/// from it.
struct ContentView: View {
    var body: some View {
        LibraryView()
    }
}

#Preview {
    ContentView()
        .environment(DocumentStore())
        .environment(AppSettings())
}
