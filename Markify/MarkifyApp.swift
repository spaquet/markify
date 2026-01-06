//
//  MarkifyApp.swift
//  Markify
//
//  Created by Stéphane PAQUET on 5/5/25.
//

import SwiftUI

@main
@MainActor
struct MarkifyApp: App {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        DocumentGroup(newDocument: { MarkifyDocument() }) { file in
            ContentView(document: file.document)
                .environmentObject(settings)
        }
        .commands {
            CommandGroup(replacing: CommandGroupPlacement.appInfo) {
                Button("About Markify") {
                    openWindow(id: "about")
                }
            }
            CommandGroup(replacing: CommandGroupPlacement.help) {
                Button("Markify Help") {
                    openWindow(id: "help")
                }
                .keyboardShortcut("?", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
        }

        Window("About Markify", id: "about") {
            AboutView()
                .frame(maxWidth: 380)
        }
        .windowResizability(.contentSize)

        Window("Markify Help", id: "help") {
            HelpView()
                .frame(minWidth: 500)
        }
        .windowResizability(.contentSize)
    }
}
