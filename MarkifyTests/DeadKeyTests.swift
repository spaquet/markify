import AppKit
import Testing
@testable import Markify

/// A dead key (Spanish ´, French ^ and ¨, US Option-e) marks its accent and waits for the next key to combine with it.
/// The editor must keep the marked accent through SwiftUI's updates, or the next key arrives unaccented (#125).
/// Part of ReportTests, which runs its document window tests one at a time.
extension ReportTests {
    @Test(arguments: ["Rendered", "Markdown"], ["# Title\n\nSome text ", ""])
    func deadKeyAccentCombinesWithTheNextKey(lens: String, initial: String) async throws {
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
