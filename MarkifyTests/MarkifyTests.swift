import AppKit
import Markdown
import SwiftUI
import Testing
@testable import Markify

struct MarkifyTests {
    @Test @MainActor func lensStylingPreservesMarkdownSource() {
        let source = "---\ntags: [essay]\n---\n# Title\n\n**Bold** and [link](https://example.com)\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n\n$$\n\\frac{1}{2}\n$$\n"
        let editor = NSTextView(usingTextLayoutManager: true)
        editor.string = source
        for lens in [false, true] {
            NativeEditor(text: .constant(source), fileURL: nil, columnWidth: 640, markdownLens: lens, findQuery: "", matchCase: false,
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
        let view = NativeEditor(text: .constant(source), fileURL: nil, columnWidth: 640, markdownLens: false, findQuery: "", matchCase: false,
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

    @Test @MainActor func slashInsertionStartsABlockAndPlacesCaret() {
        let editor = NSTextView(usingTextLayoutManager: true)
        editor.string = "Hello /tab"
        let context = SlashContext.detect(in: editor.string, selection: NSRange(location: 10, length: 0))!
        SlashEntry.matching("tab")[0].apply(to: editor, context: context)
        #expect(editor.string == "Hello\n| Column | Column |\n| --- | --- |\n|  |  |")
        #expect((editor.string as NSString).substring(with: editor.selectedRange()) == "Column")
    }

    @Test @MainActor func tableTabMovesCellsAndAddsRow() {
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.string = "| A | B |\n| --- | --- |\n| C | D |"
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        #expect(editor.navigateTable(backward: false))
        #expect((editor.string as NSString).substring(with: editor.selectedRange()) == "B")
        #expect(editor.navigateTable(backward: false))
        #expect((editor.string as NSString).substring(with: editor.selectedRange()) == "C")
        #expect(editor.navigateTable(backward: false))
        #expect((editor.string as NSString).substring(with: editor.selectedRange()) == "D")
        #expect(editor.navigateTable(backward: false))
        #expect(editor.string.hasSuffix("\n|  |  |"))
    }

    @Test @MainActor func tableCellEditsTrackTheirSourceRange() {
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.string = "| A | B |\n| --- | --- |\n| C | D |"
        var cell = NSRange(location: 2, length: 1)
        for value in ["Al", "Alp", "Alpha"] { cell = editor.replaceTableCell(cell, with: value) }
        #expect(editor.string == "| Alpha | B |\n| --- | --- |\n| C | D |")
        #expect((editor.string as NSString).substring(with: cell) == "Alpha")
    }

    @Test @MainActor func returnContinuesAndEndsLists() {
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.string = "1. First"
        editor.setSelectedRange(NSRange(location: 8, length: 0))
        #expect(editor.continueList())
        #expect(editor.string == "1. First\n2. ")
        #expect(editor.continueList())
        #expect(editor.string == "1. First\n")
        editor.string = "- [x] Done"
        editor.setSelectedRange(NSRange(location: 10, length: 0))
        #expect(editor.continueList())
        #expect(editor.string == "- [x] Done\n- [ ] ")
        editor.string = "Plain"
        editor.setSelectedRange(NSRange(location: 5, length: 0))
        #expect(!editor.continueList())
    }

    @Test @MainActor func displayMathRendersLocally() {
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        let image = editor.renderMath(#"\frac{1}{2}"#, dark: false)
        #expect(image?.size.width ?? 0 > 0)
        #expect(image?.size.height ?? 0 > 0)
        #expect(image?.size.width ?? 0 < 100)
    }

    @Test func aiAcceptanceKeepsOneFrontmatterBlock() {
        let source = "---\ntags: [old]\n---\n# Title\n"
        let replacement = "---\ntitle: New\ntags: [new]\n---\n"
        let edit = AIPlacement.frontmatter.edit(source: source, output: replacement, caret: 0)
        let result = (source as NSString).replacingCharacters(in: edit.range, with: edit.text)
        #expect(result == replacement + "# Title\n")
        let summary = AIPlacement.atTop.edit(source: source, output: "Summary", caret: 0)
        #expect(summary.range.location == edit.range.length)
    }
}
