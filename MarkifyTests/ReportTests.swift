import AppKit
import MarkifyMarkdown
import OKFKit
import Testing
@testable import Markify

@Suite(.serialized) @MainActor struct ReportTests {
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
