//
//  MarkifyApp.swift
//  Markify
//
//  Created by Stéphane PAQUET on 5/5/25.
//

import SwiftUI

@main
struct MarkifyApp: App {
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        DocumentGroup(newDocument: { MarkifyDocument() }) { file in
            ContentView(document: file.document)
                .environmentObject(settings)
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
        }
    }
}
