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
                         textView: .constant(nil), onType: {}, onSlash: { _ in }, onSelectionRect: { _ in })
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
}
