import AppKit
import Markdown
import SwiftUI
import Testing
@testable import Markify

struct MarkifyTests {
    @Test @MainActor func lensStylingPreservesMarkdownSource() {
        let source = "---\ntags: [essay]\n---\n# Title\n\n**Bold** and [link](https://example.com)\n"
        let editor = NSTextView(usingTextLayoutManager: true)
        editor.string = source
        for lens in [false, true] {
            NativeEditor(text: .constant(source), fileURL: nil, markdownLens: lens, findQuery: "", matchCase: false,
                         selectedRange: .constant(NSRange(location: 0, length: 0)),
                         textView: .constant(nil), onType: {}, onSlash: { _ in }, onSlashKey: { _, _ in false }, onSelectionRect: { _ in })
                .style(editor)
            #expect(editor.string == source)
        }
    }

    @Test func sourceAnchorPreservesOffsets() {
        let source = "# Title\n\nSecond line\nThird line\n"
        let anchor = SourceAnchor(source: source, selection: NSRange(location: 17, length: 4), topOffset: 11)
        #expect(anchor.selection(in: source) == NSRange(location: 17, length: 4))
        #expect((source as NSString).substring(with: anchor.topLine) == "Second line\n")
        #expect(anchor.selection(in: "short") == NSRange(location: 5, length: 0))
    }

    @Test func markdownSourceRangesMapThroughUnicode() {
        let source = "😀 intro\n# Café\n"
        let heading = Markdown.Document(parsing: source).children.compactMap { $0 as? Markdown.Heading }.first!
        let range = MarkdownSourceMap(source).range(heading.range!)!
        #expect((source as NSString).substring(with: range) == "# Café")
    }

    @Test func slashContextAndFuzzyMenu() {
        let source = "Hello /tbl" as NSString
        let slash = SlashContext.detect(in: source as String, selection: NSRange(location: source.length, length: 0))
        #expect(slash?.range == NSRange(location: 6, length: 4))
        #expect(slash?.query == "tbl")
        #expect(SlashEntry.matching("tbl").map(\.title) == ["Table"])
        #expect(SlashContext.detect(in: "https://example.com", selection: NSRange(location: 8, length: 0)) == nil)
        #expect(SlashContext.detect(in: "/task list", selection: NSRange(location: 10, length: 0)) == nil)
    }

    @Test @MainActor func slashCanStartAnEmptyDocument() {
        let source = ""
        let view = NativeEditor(text: .constant(source), fileURL: nil, markdownLens: false, findQuery: "", matchCase: false,
                                selectedRange: .constant(NSRange(location: 0, length: 0)), textView: .constant(nil),
                                onType: {}, onSlash: { _ in }, onSlashKey: { _, _ in false }, onSelectionRect: { _ in })
        let editor = NSTextView(usingTextLayoutManager: true)
        #expect(view.makeCoordinator().textView(editor, shouldChangeTextIn: NSRange(location: 0, length: 0), replacementString: "/"))
    }

    @Test @MainActor func slashReturnRoutesToSelectedCommand() {
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.string = "/tab"
        editor.setSelectedRange(NSRange(location: 4, length: 0))
        var handled: SlashContext?
        editor.onSlashKey = { key, context in
            if key == .insert { handled = context; return true }
            return false
        }
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                     windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
                                     isARepeat: false, keyCode: 36)!
        editor.keyDown(with: event)
        #expect(handled?.query == "tab")
    }
}
