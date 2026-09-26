import SwiftUI
import AppKit
import CryptoKit

@MainActor
final class MarkifyAppDelegate: NSObject, NSApplicationDelegate {
    /// Set at launch when Settings › On launch is "Library"; the first window consumes it to open the sidebar.
    static var showsLibraryOnNextWindow = false
    private static let openDocumentsKey = "openDocumentBookmarks"

    func applicationWillFinishLaunching(_ notification: Notification) {
        // markify:// links, used by the help to open the Welcome tour. A URL handler leaves document opening alone.
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:withReply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    @objc private func handleURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue, let url = URL(string: text), url.scheme == "markify" else { return }
        switch url.host() {
        case "welcome": Self.openWelcome()
        default: break
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        BundleAccess.restore()
        _ = Updates.controller
        // Registered up front so Help menu items that open a page by anchor work on their first use.
        NSHelpManager.shared.registerBooks(in: .main)
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

    /// Copies the bundled Welcome tour into the library (once), with the image it shows, and opens it.
    @discardableResult
    static func openWelcome() -> Bool {
        guard let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("Markify"),
              let target = try? installWelcome(in: folder) else { return false }
        // A tour replaced while it was open shows the new text.
        if let open = NSDocumentController.shared.document(for: target), let type = open.fileType {
            try? open.revert(toContentsOf: target, ofType: type)
        }
        NSDocumentController.shared.openDocument(withContentsOf: target, display: true) { _, _, _ in }
        return true
    }

    /// Writes the tour into `folder` unless the user has made it their own, and returns its file.
    static func installWelcome(in folder: URL, bundle: Bundle = .main) throws -> URL {
        guard let bundled = bundle.url(forResource: "Welcome", withExtension: "md") else { throw CocoaError(.fileNoSuchFile) }
        let target = folder.appendingPathComponent("Welcome to Markify.md")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.copyItem(at: bundled, to: target)
        } else if let data = try? Data(contentsOf: target), previousWelcomes.contains(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()) {
            // An untouched copy of an older tour is replaced by the current one; an edited copy is left alone.
            _ = try FileManager.default.replaceItemAt(target, withItemAt: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).copying(bundled))
        }
        // The tour shows an image the way pasted images are stored: in assets/ beside the document.
        let image = folder.appendingPathComponent("assets/welcome-lenses.webp")
        if let bundledImage = bundle.url(forResource: "welcome-lenses", withExtension: "webp"), !FileManager.default.fileExists(atPath: image.path) {
            try? FileManager.default.createDirectory(at: image.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: bundledImage, to: image)
        }
        return target
    }

    /// SHA-256 of every Welcome.md shipped before the current one. Add the old hash when the tour changes:
    /// `git show HEAD:Markify/Resources/Welcome.md | shasum -a 256`.
    static let previousWelcomes: Set<String> = [
        "4c71c72b97d8f69142e6cfe64f0d865c93d27a2d836f69cbcca75a16807a83f3",
        "cef259e416db6f8237f20e12c46b8215f93912890e3a2b344471ecd697072c9e",
    ]

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
            CommandGroup(replacing: .appInfo) {
                AboutButton()
                CheckForUpdatesButton()
            }
            CommandGroup(after: .newItem) {
                Button("Open Bundle Folder…") { BundleAccess.chooseAndOpen() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(after: .help) {
                Button("Keyboard Shortcuts") { HelpBook.open("shortcuts") }
                Button("Markdown Guide") { HelpBook.open("markdown") }
                Button("Frequently Asked Questions") { HelpBook.open("faq") }
                Divider()
                Button("Welcome to Markify") { MarkifyAppDelegate.openWelcome() }
                Button("Release Notes") { HelpBook.openWeb("https://github.com/spaquet/markify/releases") }
                Button("Markify Website") { HelpBook.openWeb("https://spaquet.github.io/markify/") }
                Button("Report an Issue…") { HelpBook.openWeb("https://github.com/spaquet/markify/issues/new") }
            }
        }
        Window("About Markify", id: "about") {
            AboutView()
                .containerBackground(.thickMaterial, for: .window)
                .toolbar(removing: .title)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .windowBackgroundDragBehavior(.enabled)
        .restorationBehavior(.disabled)
        .defaultPosition(.center)
        .commandsRemoved()
        Settings {
            SettingsView()
        }
    }
}

/// Markify Help, the Apple Help Book built from help/*.md by scripts/build-help.sh. The Help menu's own
/// "Markify Help" item and its search field come from `CFBundleHelpBookName` in Info.plist.
@MainActor enum HelpBook {
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleHelpBookName") as? String ?? "com.stephanepaquet.Markify.help"

    /// Opens a help page by its anchor, the page's file name in help/ without `.md`.
    static func open(_ anchor: String) {
        NSHelpManager.shared.openHelpAnchor(anchor, inBook: name)
    }

    static func openWeb(_ address: String) {
        if let url = URL(string: address) { NSWorkspace.shared.open(url) }
    }
}

private extension URL {
    /// Copies `source` to this URL and returns it.
    func copying(_ source: URL) throws -> URL {
        try FileManager.default.copyItem(at: source, to: self)
        return self
    }
}
