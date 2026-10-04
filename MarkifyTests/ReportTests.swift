import AppKit
import MarkifyMarkdown
import OKFKit
import Testing
@testable import Markify

@Suite(.serialized) @MainActor struct ReportTests {
    @Test func openedFileReusesOnlyUntouchedEmptyStartupWindow() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).md")
        try Data("# Opened file".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let startup = try NSDocumentController.shared.openUntitledDocumentAndDisplay(true)
        defer { MarkifyAppDelegate.startupDocument = nil; startup.close() }
        try await Task.sleep(for: .milliseconds(300))
        let window = try #require(startup.windowControllers.first?.window)
        let requestedFrame = NSRect(x: 100, y: 100, width: 1100, height: 800)
        window.setFrame(window.constrainFrameRect(requestedFrame, to: window.screen), display: true)
        let frame = window.frame
        MarkifyAppDelegate.startupDocument = startup
        let opened: NSDocument = try await withCheckedThrowingContinuation { continuation in
            NSDocumentController.shared.openDocument(withContentsOf: url, display: false) { document, _, error in
                if let document { continuation.resume(returning: document) }
                else { continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown)) }
            }
        }
        defer { opened.close() }
        startup.updateChangeCount(.changeDone)
        #expect(!MarkifyAppDelegate.replaceStartupDocument(with: opened))
        startup.updateChangeCount(.changeCleared)
        let report = try MarkifyDocument.makeUntitled(report: .init(text: "User content"), display: true)
        defer { report.close() }
        MarkifyAppDelegate.startupDocument = report
        #expect(!MarkifyAppDelegate.replaceStartupDocument(with: opened))
        MarkifyAppDelegate.startupDocument = startup
        opened.makeWindowControllers()
        opened.showWindows()
        // Native reloading reaches the SwiftUI editor asynchronously, especially on busy CI runners.
        for _ in 0..<200 {
            if MarkdownTextView.openEditors.allObjects.contains(where: {
                $0.window === window && $0.documentURL == url && $0.string == "# Opened file"
            }) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(startup.fileURL == url)
        #expect(startup.windowControllers.first?.window === window)
        #expect(window.frame == frame)
        #expect(!NSDocumentController.shared.documents.contains { $0 === opened })
        #expect(try startup.fileWrapper(ofType: "net.daringfireball.markdown").regularFileContents == Data("# Opened file".utf8))
        #expect(!startup.isDocumentEdited)
        let editor = try #require(MarkdownTextView.openEditors.allObjects.first { $0.window === window && $0.documentURL == url })
        #expect(editor.string == "# Opened file")
        #expect(editor.documentURL == url)
    }

    @Test func externalChangesPromptAndRefreshTheActualDocumentWindow() async throws {
        // Let the previous test's closed SwiftUI document window finish its teardown.
        try await Task.sleep(for: .milliseconds(300))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).md")
        try Data("one\ntwo\nthree\n".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        var opened: NSDocument?
        DispatchQueue.main.async {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { document, _, _ in
                opened = document
            }
        }
        for _ in 0..<100 {
            if opened != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let document = try #require(opened)
        defer { document.updateChangeCount(.changeCleared); document.close() }
        for _ in 0..<100 {
            if MarkdownTextView.openEditors.allObjects.contains(where: { $0.documentURL == url && $0.window?.isVisible == true }) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let initialEditor = try #require(MarkdownTextView.openEditors.allObjects.first { $0.documentURL == url && $0.window?.isVisible == true })
        let window = try #require(initialEditor.window)
        func installedEditor(in view: NSView) -> MarkdownTextView? {
            if let editor = view as? MarkdownTextView { return editor }
            return view.subviews.lazy.compactMap { installedEditor(in: $0) }.first
        }
        var editor: MarkdownTextView {
            window.contentView.flatMap { installedEditor(in: $0) } ?? initialEditor
        }
        func buttons(in view: NSView) -> [NSButton] {
            (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
        }
        func respond(_ title: String) async throws {
            for _ in 0..<100 {
                if window.attachedSheet != nil { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            let sheet = try #require(window.attachedSheet)
            let content = try #require(sheet.contentView)
            let choices = buttons(in: content)
            #expect(choices.map(\.title).contains("Keep My Changes"))
            #expect(choices.map(\.title).contains("Reload"))
            #expect(choices.map(\.title).contains("Merge"))
            let button = try #require(choices.first { $0.title == title })
            button.performClick(nil)
            for _ in 0..<100 {
                if window.attachedSheet == nil { break }
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        // Allow native document registration and the deferred watcher attachment to finish.
        try await Task.sleep(for: .milliseconds(300))
        try Data("one\ntwo\nTHREE\n".utf8).write(to: url, options: .atomic)
        try await respond("Keep My Changes")
        #expect(editor.string == "one\ntwo\nthree\n")
        try Data("one\ntwo\nupdated\n".utf8).write(to: url, options: .atomic)
        try await respond("Reload")
        for _ in 0..<100 {
            if editor.string == "one\ntwo\nupdated\n" { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(editor.string == "one\ntwo\nupdated\n")
        editor.insertText("local ", replacementRange: NSRange(location: 0, length: 0))
        if let undo = editor.undoManager, undo.groupingLevel > 0 { undo.endUndoGrouping() }
        try await Task.sleep(for: .milliseconds(100))
        try Data("one\ntwo\nexternal\n".utf8).write(to: url, options: .atomic)
        try await respond("Merge")
        for _ in 0..<100 {
            if editor.string == "local one\ntwo\nexternal\n" { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(editor.string == "local one\ntwo\nexternal\n")
    }

    @Test func reportURLConsumesOnlyItsEnvelope() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let inbox = ReportInbox(directory: folder)
        let first = try inbox.write(.init(text: "# URL report"))
        let second = try inbox.write(.init(text: "# Another report"))
        let document = try MarkifyAppDelegate.consumeReport(ReportInbox.url(for: first), inbox: inbox)
        defer { document.close() }
        #expect(!FileManager.default.fileExists(atPath: inbox.file(for: first).path))
        #expect(try inbox.read(second).text == "# Another report")
        #expect(throws: (any Error).self) { try MarkifyAppDelegate.consumeReport(ReportInbox.url(for: first), inbox: inbox) }
    }

    @Test func openedReportsHaveIndependentRenderedWindows() async throws {
        let previous = UserDefaults.standard.object(forKey: "defaultLens")
        UserDefaults.standard.set("Markdown", forKey: "defaultLens")
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: "defaultLens") }
            else { UserDefaults.standard.removeObject(forKey: "defaultLens") }
        }
        let first = try MarkifyAppDelegate.openUntitled(report: .init(text: "# First report", title: "First"))
        let second = try MarkifyAppDelegate.openUntitled(report: .init(text: "# Second report", title: "Second"))
        defer { first.close(); second.close() }
        try await Task.sleep(for: .milliseconds(300))
        #expect(first.fileURL == nil && second.fileURL == nil)
        #expect(!first.isDocumentEdited && !second.isDocumentEdited)
        #expect(try first.fileWrapper(ofType: "net.daringfireball.markdown").regularFileContents == Data("# First report".utf8))
        #expect(try second.fileWrapper(ofType: "net.daringfireball.markdown").regularFileContents == Data("# Second report".utf8))
        let editors = MarkdownTextView.openEditors.allObjects.filter { ["# First report", "# Second report"].contains($0.string) }
        #expect(editors.count == 2)
        #expect(editors.allSatisfy { $0.rendered })
        #expect(UserDefaults.standard.string(forKey: "defaultLens") == "Markdown")
        let editor = try #require(editors.first { $0.string == "# First report" })
        editor.window?.makeFirstResponder(editor)
        editor.insertText(" edited", replacementRange: NSRange(location: editor.string.utf16.count, length: 0))
        // A programmatic edit lacks NSApplication's end-of-event undo-group close.
        if let undo = editor.undoManager, undo.groupingLevel > 0 { undo.endUndoGrouping() }
        try await Task.sleep(for: .milliseconds(100))
        let updated = try first.fileWrapper(ofType: "net.daringfireball.markdown").regularFileContents
        #expect(updated == Data("# First report edited".utf8))
        #expect(first.isDocumentEdited, "Undo grouping: \(editor.undoManager?.groupingLevel ?? -1), canUndo: \(editor.undoManager?.canUndo ?? false)")
        first.updateChangeCount(.changeCleared)
    }

    @Test func untitledReportStartsCleanAndOrdinaryNewStaysEmpty() throws {
        let source = "# Report\r\n\r\nUnicode café 🌻"
        let report = MarkifyReport(text: source, title: "Agent report", baseDirectory: "/private/tmp")
        let document = try MarkifyDocument.makeUntitled(report: report)
        defer { document.close() }
        #expect(document.fileURL == nil)
        #expect(!document.isDocumentEdited)
        let wrapper = try document.fileWrapper(ofType: "net.daringfireball.markdown")
        #expect(wrapper.regularFileContents == Data(source.utf8))
        #expect(MarkifyDocument.newDocument().text.isEmpty)
        #expect(MarkifyDocument.newDocument().report == nil)
        document.updateChangeCount(.changeDone)
        #expect(document.isDocumentEdited)
        document.updateChangeCount(.changeCleared)
    }

    @Test func reportResourceBaseIsUsedUntilSaved() throws {
        let base = URL(fileURLWithPath: "/private/tmp/project", isDirectory: true)
        let saved = URL(fileURLWithPath: "/private/tmp/saved/report.md")
        #expect(MarkdownTextView.imageURL("assets/my%20pic.png", document: nil, baseDirectory: base).path == "/private/tmp/project/assets/my pic.png")
        #expect(MarkdownTextView.imageURL("assets/a.png", document: saved, baseDirectory: base).path == "/private/tmp/saved/assets/a.png")
        #expect(OKFLinks.resolve("notes/a.md#part", from: nil, bundleRoot: nil, baseDirectory: base)?.path == "/private/tmp/project/notes/a.md")
        #expect(OKFLinks.resolve("/private/tmp/a.md", from: nil, bundleRoot: nil, baseDirectory: base)?.path == "/private/tmp/a.md")
        #expect(LinkSummaryStore.key("notes/a.md", from: nil, root: nil, baseDirectory: base) == "file:///private/tmp/project/notes/a.md")
        #expect(MarkdownTextView.noteLink(to: base.appendingPathComponent("a.md"), title: "A", from: nil, bundleRoot: nil, baseDirectory: base) == "[A](a.md)")
        let context = DocumentExport.Context(source: "", documentURL: nil, bundleRoot: nil,
            destination: base.appendingPathComponent("out/report.html"), fallbackTitle: "Report", baseDirectory: base)
        #expect(DocumentExport.linkTarget("notes/a.md#part", context: context) == "../notes/a.md#part")
        #expect(DocumentExport.imageSource("assets/missing.png", context: context) == "../assets/missing.png")
    }
}
