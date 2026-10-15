import AppKit
import Testing
@testable import Markify

/// A dead key (Spanish ´, French ^ and ¨, US Option-e) marks its accent and waits for the next key to combine with it.
/// The editor must keep the marked accent through SwiftUI's updates, or the next key arrives unaccented (#125).
/// Part of ReportTests, which runs its document window tests one at a time.
extension ReportTests {
    @Test(arguments: ["Rendered", "Markdown"], ["# Title\n\nSome text ", ""])
    func deadKeyAccentCombinesWithTheNextKey(lens: String, initial: String) async throws {
        try await withDeadKeyEditor(lens: lens, initial: initial) { editor, document in
            // The calls a Spanish layout makes for ´ then e.
            editor.setMarkedText("´", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            // The selection change re-renders the window, and SwiftUI updates the editor with the text it last received.
            try await Task.sleep(for: .milliseconds(300))
            #expect(editor.hasMarkedText())
            #expect(editor.string == initial + "´")
            editor.insertText("é", replacementRange: NSRange(location: NSNotFound, length: 0))
            try await Task.sleep(for: .milliseconds(300))
            #expect(!editor.hasMarkedText())
            // An empty document starts with a title once the composed letter is typed.
            #expect(editor.string == (initial.isEmpty ? "# é" : initial + "é"))
            #expect(try document.fileWrapper(ofType: "net.daringfireball.markdown").regularFileContents == Data(editor.string.utf8))
        }
    }

    /// Both sides of the editor bridge: an unrelated SwiftUI update must not replace the marked accent with the
    /// binding's text, and cancelling the accent (Delete or Escape) must leave the document as it was.
    @Test(arguments: ["Rendered", "Markdown"], ["# Title\n\nSome text ", ""])
    func cancelledDeadKeyAccentLeavesTheDocumentUnchanged(lens: String, initial: String) async throws {
        let defaults = UserDefaults.standard
        let previousLimit = defaults.object(forKey: "limitLineWidth")
        let previousWidth = defaults.object(forKey: "lineWidth")
        defaults.set(false, forKey: "limitLineWidth")
        defer {
            if let previousLimit { defaults.set(previousLimit, forKey: "limitLineWidth") }
            else { defaults.removeObject(forKey: "limitLineWidth") }
            if let previousWidth { defaults.set(previousWidth, forKey: "lineWidth") }
            else { defaults.removeObject(forKey: "lineWidth") }
        }
        try await withDeadKeyEditor(lens: lens, initial: initial) { editor, document in
            editor.setMarkedText("´", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            #expect(editor.hasMarkedText())

            // An unrelated setting change re-renders the window; the new column width shows the editor was updated.
            let widthBefore = editor.columnWidth
            defaults.set(300.0, forKey: "lineWidth")
            defaults.set(true, forKey: "limitLineWidth")
            for _ in 0..<40 {
                if editor.columnWidth != widthBefore { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            #expect(editor.columnWidth != widthBefore)
            #expect(editor.hasMarkedText())
            #expect(editor.string == initial + "´")

            // Delete or Escape on a pending dead key clears the marked text, then ends the composition.
            editor.setMarkedText("", selectedRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            editor.unmarkText()
            try await Task.sleep(for: .milliseconds(300))
            #expect(!editor.hasMarkedText())
            #expect(editor.string == initial)

            // A later update must not bring back the accent or start an empty document's title.
            defaults.set(false, forKey: "limitLineWidth")
            try await Task.sleep(for: .milliseconds(300))
            #expect(editor.string == initial)
            #expect(try document.fileWrapper(ofType: "net.daringfireball.markdown").regularFileContents == Data(initial.utf8))
            #expect(!document.isDocumentEdited)
        }
    }

    /// Opens `initial` in a document window in `lens`, makes its editor first responder with the caret at the end,
    /// and closes the window after `body`.
    private func withDeadKeyEditor(lens: String, initial: String,
                                   _ body: (MarkdownTextView, NSDocument) async throws -> Void) async throws {
        let previous = UserDefaults.standard.object(forKey: "defaultLens")
        UserDefaults.standard.set(lens, forKey: "defaultLens")
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: "defaultLens") }
            else { UserDefaults.standard.removeObject(forKey: "defaultLens") }
        }
        // Let the previous test's closed SwiftUI document window finish its teardown.
        try await Task.sleep(for: .milliseconds(300))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).md")
        try Data(initial.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        var opened: NSDocument?
        DispatchQueue.main.async {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { document, _, _ in opened = document }
        }
        for _ in 0..<100 {
            if opened != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let document = try #require(opened)
        defer { document.updateChangeCount(.changeCleared); document.close() }
        func visibleEditor() -> MarkdownTextView? {
            MarkdownTextView.openEditors.allObjects.first { $0.documentURL == url && $0.window?.isVisible == true }
        }
        for _ in 0..<100 {
            if visibleEditor() != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let editor = try #require(visibleEditor())
        #expect(editor.rendered == (lens == "Rendered"))
        editor.window?.makeKeyAndOrderFront(nil)
        editor.window?.makeFirstResponder(editor)
        try await Task.sleep(for: .milliseconds(300))
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        try await body(editor, document)
    }
}
