import SwiftUI
import AppKit

@MainActor
final class MarkifyAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            if NSDocumentController.shared.documents.isEmpty {
                NSDocumentController.shared.newDocument(nil)
            }
        }
    }
}

@main
struct MarkifyApp: App {
    @NSApplicationDelegateAdaptor(MarkifyAppDelegate.self) private var appDelegate

    var body: some Scene {
        DocumentGroup(newDocument: MarkifyDocument()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
        }
        .defaultLaunchBehavior(.suppressed)
        Settings {
            SettingsView()
        }
    }
}
