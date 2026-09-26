import SwiftUI
import AppKit

@MainActor
final class MarkifyAppDelegate: NSObject, NSApplicationDelegate {
    /// Set at launch when Settings › On launch is "Library"; the first window consumes it to open the sidebar.
    static var showsLibraryOnNextWindow = false
    private static let openDocumentsKey = "openDocumentBookmarks"

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            let startup = UserDefaults.standard.string(forKey: "startup") ?? "Reopen last documents"
            let urls = startup == "Reopen last documents" ? Self.lastOpenDocuments() : []
            guard !urls.isEmpty else { return Self.openInitialDocument(startup: startup) }
            var remaining = urls.count
            for url in urls {
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in
                    remaining -= 1
                    if remaining == 0 { Self.openInitialDocument(startup: startup) }
                }
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let bookmarks = NSDocumentController.shared.documents.compactMap(\.fileURL).compactMap {
            try? $0.bookmarkData(options: .withSecurityScope)
        }
        UserDefaults.standard.set(bookmarks, forKey: Self.openDocumentsKey)
        return .terminateNow
    }

    private static func openInitialDocument(startup: String) {
        guard NSDocumentController.shared.documents.isEmpty else { return }
        showsLibraryOnNextWindow = startup == "Library"
        NSDocumentController.shared.newDocument(nil)
    }

    private static func lastOpenDocuments() -> [URL] {
        let bookmarks = UserDefaults.standard.array(forKey: openDocumentsKey) as? [Data] ?? []
        let open = Set(NSDocumentController.shared.documents.compactMap(\.fileURL))
        return bookmarks.compactMap { data in
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale),
                  !open.contains(url), url.startAccessingSecurityScopedResource() else { return nil }
            return url
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
