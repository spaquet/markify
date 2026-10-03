import AppKit
import SwiftUI
import UniformTypeIdentifiers
import MarkifyMarkdown

extension UTType {
    static let markdown = UTType(importedAs: "net.daringfireball.markdown")
}

struct MarkifyDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.markdown]
    var text = ""
    var report: MarkifyReport?
    var sourceURL: URL?
    var remoteBase: URL?

    /// Only set around synchronous native document opening; ordinary ⌘N stays empty.
    private static let factory = ReportDocumentFactory()

    static func newDocument() -> MarkifyDocument { factory.document() }

    @MainActor static func makeUntitled(report: MarkifyReport, sourceURL: URL? = nil, remoteBase: URL? = nil, display: Bool = false) throws -> NSDocument {
        factory.set(report, sourceURL: sourceURL, remoteBase: remoteBase)
        defer { factory.set(nil) }
        return try NSDocumentController.shared.openUntitledDocumentAndDisplay(display)
    }

    init(text: String = "") { self.text = text }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// Watch the parent folder so atomic replacements keep being observed.
@MainActor final class DocumentFileRefresh {
    private let watcher = BundleWatcher()
    private weak var document: NSDocument?
    private var url: URL?
    private let refreshSearch: () -> Void

    init(refreshSearch: @escaping () -> Void = { LibrarySearch.shared.refresh() }) {
        self.refreshSearch = refreshSearch
    }

    func watch(_ document: NSDocument) {
        guard self.document !== document || url != document.fileURL else { return }
        self.document = document
        url = document.fileURL
        watcher.watch(url?.deletingLastPathComponent()) { [weak self] in
            self?.refresh()
        }
    }

    func refresh() {
        guard let document, let url, document.fileURL == url,
              let type = document.fileType,
              let disk = try? Data(contentsOf: url),
              let current = try? document.fileWrapper(ofType: type).regularFileContents,
              disk != current else { return }
        refreshSearch()
        // Never replace local edits with an external version.
        guard !document.isDocumentEdited else { return }
        do { try document.revert(toContentsOf: url, ofType: type) }
        catch { NSApp.presentError(error) }
    }
}

private final class ReportDocumentFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: MarkifyReport?
    private var sourceURL: URL?
    private var remoteBase: URL?
    func set(_ report: MarkifyReport?, sourceURL: URL? = nil, remoteBase: URL? = nil) {
        lock.withLock { pending = report; self.sourceURL = sourceURL; self.remoteBase = remoteBase }
    }
    func document() -> MarkifyDocument {
        lock.withLock {
            var document = MarkifyDocument(text: pending?.text ?? "")
            document.report = pending
            document.sourceURL = sourceURL
            document.remoteBase = remoteBase
            return document
        }
    }
}
