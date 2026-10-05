import AppKit
import MarkifyMarkdown
import Testing
@testable import Markify

@MainActor struct PerformanceFixTests {
    @Test func tableCellsKeepTheirStyleAfterUnrelatedEdits() throws {
        let owner = MarkdownTextView(usingTextLayoutManager: true)
        owner.string = "| A | B |\n| --- | --- |\n| **cell** | other |\n\nTail"
        let range = try #require(owner.model.tables.first?.rows.last?.cells.first)
        let presentation = owner.tablePresentation(range, width: 200)
        let version = presentation.reading.textVersion
        owner.textStorage?.replaceCharacters(in: NSRange(location: (owner.string as NSString).length, length: 0), with: "!")
        #expect(owner.tablePresentation(range, width: 200) === presentation)
        #expect(presentation.reading.textVersion == version)
    }

    @Test func teardownRemovesEditingObservers() {
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.string = "another"
        let version = editor.textVersion
        editor.stopObserving()
        editor.stopObserving()
        editor.textStorage?.replaceCharacters(in: NSRange(location: 0, length: 1), with: "A")
        #expect(editor.textVersion == version)
    }

    @Test func clicksFollowRenderedLinkForms() throws {
        for source in ["[web](https://example.com/a_(b))", "<https://example.com>",
                       "[web][site]\n\n[site]: https://example.com"] {
            let editor = MarkdownTextView(usingTextLayoutManager: true)
            editor.string = source
            let span = try #require(editor.model.spans.first { if case .link = $0.kind { return true }; return false })
            #expect(editor.link(at: span.content.location)?.target.hasPrefix("https://example.com") == true)
        }
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.string = "`[code](https://example.com)`"
        #expect(editor.link(at: 3) == nil)
    }
}
