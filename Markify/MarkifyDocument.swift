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

/// Observe the folder for atomic saves, with polling for missed/coalesced file events.
@MainActor final class DocumentFileRefresh {
    enum Choice { case keep, reload, merge }
    private let watcher = BundleWatcher()
    private weak var document: NSDocument?
    private weak var window: NSWindow?
    private var url: URL?
    private var lastDisk: Data?
    private var lastStamp: FileStamp?
    private var readTask: Task<Void, Never>?
    private var readGeneration = UUID()
    private var readAgain = false
    private var timer: Timer?
    private(set) var presenting = false
    private let refreshSearch: () -> Void
    private let readText: (() -> String)?
    private let writeText: ((String) -> Void)?
    private let choose: ((NSDocument, @escaping (Choice) -> Void) -> Void)?

    init(refreshSearch: @escaping () -> Void = { LibrarySearch.shared.refresh() },
         readText: (() -> String)? = nil, writeText: ((String) -> Void)? = nil,
         choose: ((NSDocument, @escaping (Choice) -> Void) -> Void)? = nil) {
        self.refreshSearch = refreshSearch
        self.readText = readText
        self.writeText = writeText
        self.choose = choose
    }

    func stop() {
        readTask?.cancel()
        readTask = nil
        readGeneration = UUID()
        readAgain = false
        watcher.stop()
        timer?.invalidate()
        timer = nil
        document = nil
        url = nil
        window = nil
    }

    func watch(_ window: NSWindow) {
        guard let document = NSDocumentController.shared.document(for: window) else { return }
        self.window = window
        watch(document)
    }

    func watch(_ document: NSDocument) {
        guard self.document !== document || url != document.fileURL else { return }
        timer?.invalidate()
        readTask?.cancel()
        readTask = nil
        readGeneration = UUID()
        self.document = document
        url = document.fileURL
        // Native document contents are available without disk I/O; the SwiftUI binding may still
        // show the previous document during revert. Confirm the disk baseline on a worker.
        lastDisk = document.fileType.flatMap { try? document.fileWrapper(ofType: $0).regularFileContents } ?? nil
        lastStamp = nil
        if let url {
            let generation = readGeneration
            let initialStamp = FileStamp(at: url)
            let work = Task.detached(priority: .utility) { () -> (FileStamp, Data)? in
                guard !Task.isCancelled, let stamp = FileStamp(at: url),
                      let data = try? FileRead.data(at: url, maximumBytes: 50_000_000),
                      FileStamp(at: url) == stamp else { return nil }
                return (stamp, data)
            }
            readTask = Task { [weak self] in
                let baseline = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
                guard !Task.isCancelled, let self, self.readGeneration == generation else { return }
                self.readTask = nil
                if self.lastStamp == nil, let (stamp, disk) = baseline {
                    self.lastStamp = stamp
                    if stamp == initialStamp { self.lastDisk = disk }
                    else { self.refresh(disk: disk) }
                }
                if self.readAgain { self.readAgain = false; self.scheduleRefresh() }
            }
        }
        watcher.watch(url?.deletingLastPathComponent()) { [weak self] in self?.scheduleRefresh() }
        guard url != nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.scheduleRefresh() }
        }
        timer?.tolerance = 2
    }

    /// One read at a time, with a trailing check for events that arrive during I/O.
    func scheduleRefresh() {
        guard !presenting, let document, !document.isBrowsingVersions, !document.isInViewingMode,
              let url, document.fileURL == url else { return }
        guard readTask == nil else { readAgain = true; return }
        let previous = lastStamp
        let generation = readGeneration
        let work = Task.detached(priority: .utility) { () -> (FileStamp, Data)? in
            guard !Task.isCancelled, let stamp = FileStamp(at: url), stamp != previous,
                  let disk = try? FileRead.data(at: url, maximumBytes: 50_000_000), !Task.isCancelled,
                  FileStamp(at: url) == stamp else { return nil }
            return (stamp, disk)
        }
        readTask = Task { [weak self] in
            let result = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            guard let self, !Task.isCancelled, self.readGeneration == generation else { return }
            self.readTask = nil
            if let (stamp, disk) = result { self.lastStamp = stamp; self.refresh(disk: disk) }
            if self.readAgain { self.readAgain = false; self.scheduleRefresh() }
        }
    }

    func refresh() {
        guard let url, let stamp = FileStamp(at: url), stamp != lastStamp,
              let disk = try? Data(contentsOf: url), FileStamp(at: url) == stamp else { return }
        // Don't consume an event while Versions or the external-change sheet owns the document.
        guard !presenting, let document, !document.isBrowsingVersions, !document.isInViewingMode else { return }
        lastStamp = stamp
        refresh(disk: disk)
    }

    private func refresh(disk: Data) {
        guard !presenting, let document, !document.isBrowsingVersions, !document.isInViewingMode,
              let url, document.fileURL == url,
              let type = document.fileType,
              disk != lastDisk else { return }
        let base = lastDisk
        guard let current = (readText?()).map({ Data($0.utf8) })
                ?? (try? document.fileWrapper(ofType: type).regularFileContents) else { return }
        if disk == current { lastDisk = disk; return } // Our own save.
        guard String(data: disk, encoding: .utf8) != nil else { return }
        refreshSearch()
        presenting = true
        @MainActor func complete(_ choice: Choice) {
            DispatchQueue.main.async { [weak self, weak document] in
                guard let self, let document, self.document === document,
                      self.url == url, document.fileURL == url else { return }
                do {
                    let disk = try Data(contentsOf: url)
                    guard let external = String(data: disk, encoding: .utf8) else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    let local = try self.readText?() ?? String(decoding: document.fileWrapper(ofType: type).regularFileContents ?? current, as: UTF8.self)
                    switch choice {
                    case .keep: break
                    case .reload:
                        try Self.preserveVersions(at: url, local: Data(local.utf8), external: disk, document: document)
                        try document.revert(toContentsOf: url, ofType: type)
                        self.writeText?(external)
                    case .merge:
                        guard let base, self.writeText != nil else { self.presenting = false; return }
                        let retry: @MainActor @Sendable (Choice) -> Void = { complete($0) }
                        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak document] in
                            let result = Result {
                                try Self.merge(local: local, base: String(decoding: base, as: UTF8.self),
                                               external: String(decoding: disk, as: UTF8.self))
                            }
                            DispatchQueue.main.async {
                                guard let self else { return }
                                guard let document, self.document === document, self.url == url,
                                      document.fileURL == url else { self.presenting = false; return }
                                guard (try? Data(contentsOf: url)) == disk,
                                      (self.readText?() ?? local) == local else {
                                    retry(choice)
                                    return
                                }
                                do {
                                    let merged = try result.get()
                                    try Self.preserveVersions(at: url, local: Data(local.utf8), external: disk, document: document)
                                    let undo = document.undoManager
                                    undo?.beginUndoGrouping()
                                    undo?.registerUndo(withTarget: self) { target in target.writeText?(local) }
                                    self.writeText?(merged)
                                    undo?.setActionName("Merge External Changes")
                                    undo?.endUndoGrouping()
                                    self.lastDisk = disk
                                } catch { NSApp.presentError(error) }
                                self.presenting = false
                            }
                        }
                        return
                    }
                    self.lastDisk = disk
                } catch { NSApp.presentError(error) }
                self.presenting = false
            }
        }
        if let choose { choose(document, complete); return }
        guard let window = self.window ?? document.windowControllers.first?.window else {
            presenting = false
            return
        }
        let alert = NSAlert()
        alert.messageText = "This file changed outside Markify"
        alert.informativeText = "Choose how to handle changes to \(url.lastPathComponent). Reload uses the latest external text. Merge combines it with your current text; overlapping edits are marked for you to resolve. Both versions are saved in Browse All Versions before Reload or Merge."
        alert.addButton(withTitle: "Keep My Changes")
        alert.addButton(withTitle: "Reload")
        if base != nil, writeText != nil { alert.addButton(withTitle: "Merge") }
        alert.beginSheetModal(for: window) { response in
            // Let AppKit finish dismissing the sheet before replacing the SwiftUI document.
            DispatchQueue.main.async {
                complete(response == .alertSecondButtonReturn ? .reload : response == .alertThirdButtonReturn ? .merge : .keep)
            }
        }
    }

    /// Save snapshots without writing over the externally edited file.
    static func preserveVersions(at url: URL, local: Data, external: Data, document: NSDocument) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = directory.appendingPathComponent(url.lastPathComponent)
        let coordinator = NSFileCoordinator(filePresenter: document)
        var coordinationError: NSError?
        var snapshotError: Error?
        coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            do {
                for contents in [local, external] {
                    try contents.write(to: snapshot)
                    _ = try NSFileVersion.addOfItem(at: coordinatedURL, withContentsOf: snapshot)
                }
            } catch { snapshotError = error }
        }
        if let error = coordinationError ?? snapshotError { throw error }
    }

    /// Combine line edits against the last disk version; overlapping edits remain explicit conflicts.
    nonisolated static func merge(local: String, base: String, external: String) throws -> String {
        struct Edit {
            var range: Range<Int>
            var lines: [String]
            var local: Bool
        }
        let original = base.components(separatedBy: "\n")
        func edits(_ source: String, local: Bool) -> [Edit] {
            let lines = source.components(separatedBy: "\n")
            var removed = Set<Int>(), inserted = Set<Int>()
            for change in lines.difference(from: original) {
                switch change {
                case .remove(let offset, _, _): removed.insert(offset)
                case .insert(let offset, _, _): inserted.insert(offset)
                }
            }
            var result: [Edit] = []
            var old = 0, new = 0
            while old < original.count || new < lines.count {
                if removed.contains(old) || inserted.contains(new) {
                    let start = old
                    var replacement: [String] = []
                    repeat {
                        if removed.contains(old) { old += 1 }
                        if inserted.contains(new) { replacement.append(lines[new]); new += 1 }
                    } while removed.contains(old) || inserted.contains(new)
                    result.append(Edit(range: start..<old, lines: replacement, local: local))
                } else { old += 1; new += 1 }
            }
            return result
        }
        let changes = (edits(local, local: true) + edits(external, local: false)).sorted {
            $0.range.lowerBound == $1.range.lowerBound
                ? $0.range.upperBound < $1.range.upperBound : $0.range.lowerBound < $1.range.lowerBound
        }
        func version(_ changes: [Edit], in range: Range<Int>, local: Bool) -> [String] {
            var result: [String] = []
            var cursor = range.lowerBound
            for change in changes where change.local == local {
                result += original[cursor..<change.range.lowerBound]
                result += change.lines
                cursor = change.range.upperBound
            }
            result += original[cursor..<range.upperBound]
            return result
        }
        var result: [String] = []
        var cursor = 0, index = 0
        while index < changes.count {
            let first = changes[index]
            var end = first.range.upperBound
            var group = [first]
            index += 1
            while index < changes.count {
                let next = changes[index]
                let sameInsertion = first.range.isEmpty && next.range.isEmpty && next.range.lowerBound == first.range.lowerBound
                guard next.range.lowerBound < end || sameInsertion else { break }
                group.append(next)
                end = max(end, next.range.upperBound)
                index += 1
            }
            let range = first.range.lowerBound..<end
            result += original[cursor..<range.lowerBound]
            let before = Array(original[range])
            let mine = version(group, in: range, local: true)
            let theirs = version(group, in: range, local: false)
            if mine == theirs || theirs == before { result += mine }
            else if mine == before { result += theirs }
            else {
                result += ["<<<<<<< My Changes"] + mine + ["||||||| Original"] + before
                    + ["======="] + theirs + [">>>>>>> External Changes"]
            }
            cursor = end
        }
        result += original[cursor..<original.count]
        return result.joined(separator: "\n")
    }

    isolated deinit { timer?.invalidate() }
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
