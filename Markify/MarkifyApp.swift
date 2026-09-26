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
        if !UserDefaults.standard.bool(forKey: "didShowWelcome") {
            UserDefaults.standard.set(true, forKey: "didShowWelcome")
            if openWelcome() { return }
        }
        showsLibraryOnNextWindow = startup == "Library"
        NSDocumentController.shared.newDocument(nil)
    }

    /// Copies the bundled Welcome document into the library (once) and opens it.
    @discardableResult
    static func openWelcome() -> Bool {
        guard let bundled = Bundle.main.url(forResource: "Welcome", withExtension: "md"),
              let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("Markify") else { return false }
        let target = folder.appendingPathComponent("Welcome to Markify.md")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: target.path) { try FileManager.default.copyItem(at: bundled, to: target) }
        } catch { return false }
        NSDocumentController.shared.openDocument(withContentsOf: target, display: true) { _, _, _ in }
        return true
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
        .commands {
            CommandGroup(after: .help) {
                Button("Welcome to Markify") { MarkifyAppDelegate.openWelcome() }
            }
        }
        Settings {
            SettingsView()
        }
    }
}
