import AppKit
import MarkifyMarkdown
import Testing
@testable import Markify

@MainActor struct PerformanceFixTests {
    @Test func derivedValuesInvalidateWithSourceAndFindOptions() {
        let cache = DocumentDerivedData()
        for text in ["", "one two\tthree\n", "café 😀\u{a0}four", "é\u{301} final"] {
            #expect(cache.wordCount(in: text) == text.split(whereSeparator: \.isWhitespace).count)
        }
        #expect(cache.matches(in: "One one", query: "one", matchCase: false).count == 2)
        #expect(cache.matches(in: "One one", query: "one", matchCase: true).count == 1)
        #expect(cache.matches(in: "absent", query: "one", matchCase: true).isEmpty)
        let model = cache.model(in: "# Title\n[web](https://example.com)", mdx: false, editor: nil)
        #expect(cache.headings(in: model).first?.title == "Title")
        #expect(cache.documentLinks(in: model).count == 1)
        let changed = cache.model(in: "# New", mdx: false, editor: nil)
        #expect(cache.headings(in: changed).first?.title == "New")
        #expect(cache.documentLinks(in: changed).isEmpty)
    }

    @Test func largeTablesOnlyCreateNearbyCells() {
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.frame = NSRect(x: 0, y: 0, width: 640, height: 400)
        editor.columnWidth = 640
        editor.string = "| A | B |\n| --- | --- |\n" + String(repeating: "| cell | value |\n", count: 500)
        let window = NSWindow(contentRect: editor.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = editor
        IncrementalStyleTests.native(editor.string).style(editor)
        editor.refreshTables()
        #expect(!editor.tableOverlays.isEmpty)
        #expect(editor.tableOverlays.count < 40)
        #expect(editor.tablePresentations.count < 80)
        window.contentView = nil
    }

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

    @Test func tableFootnoteTooltipsRefreshWhenDefinitionsChange() throws {
        let owner = MarkdownTextView(usingTextLayoutManager: true)
        owner.string = "| Note |\n| --- |\n| Citation[^n] |\n\n[^n]: Original footnote."
        let range = try #require(owner.model.tables.first?.rows.last?.cells.first)
        let cell = owner.tablePresentation(range, width: 200)
        let reference = try #require(cell.reading.model.spans.first { if case .footnoteReference = $0.kind { return true }; return false })
        func tip() -> String? { cell.reading.textStorage?.attribute(.toolTip, at: reference.content.location, effectiveRange: nil) as? String }
        #expect(tip() == "Original footnote.")
        owner.textStorage?.replaceCharacters(in: (owner.string as NSString).range(of: "Original"), with: "Updated")
        #expect(owner.tablePresentation(range, width: 200) === cell)
        #expect(tip() == "Updated footnote.")
    }

    @Test func summaryPersistenceFitsItsReloadBudget() async throws {
        let location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: location) }
        let store = LinkSummaryStore(location: location)
        let summary = LinkSummary(text: "Summary", fingerprint: "fingerprint", date: .now)
        try await store.save(summary, for: "small")
        try await store.save(summary, for: String(repeating: "\n", count: 2_000_000))
        #expect(try Data(contentsOf: location).count <= 4_000_000)
        let reloaded = LinkSummaryStore(location: location)
        await reloaded.waitForLoad()
        #expect(reloaded.entries == store.entries)
        #expect(reloaded.entries["small"]?.text == "Summary")
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
