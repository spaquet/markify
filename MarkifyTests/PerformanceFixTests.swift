import AppKit
import MarkifyMarkdown
import Testing
@testable import Markify

@MainActor struct PerformanceFixTests {
    @Test func editorsReleaseTheirNotificationObservers() {
        weak var released: MarkdownTextView?
        autoreleasepool {
            let editor = MarkdownTextView(usingTextLayoutManager: true)
            editor.string = "temporary"
            released = editor
        }
        #expect(released == nil)
        // Posting after destruction must also be harmless.
        let storage = NSTextStorage(string: "another")
        storage.replaceCharacters(in: NSRange(location: 0, length: 1), with: "A")
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
