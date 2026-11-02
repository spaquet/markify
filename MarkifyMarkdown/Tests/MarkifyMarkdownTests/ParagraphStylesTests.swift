import Foundation
import Testing
@testable import MarkifyMarkdown

struct ParagraphStylesTests {
    @Test func paragraphsKeepResolvedReferencesAndUTF16Offsets() throws {
        let source = "Intro 👩🏽‍💻\r\n\r\n## Hé **bold** and [note][target]\r\n\r\n[target]: other.md\r\n"
        let model = MarkdownModel(source)
        let index = MarkdownModel.ParagraphStyles(model)
        let ns = source as NSString
        let range = ns.paragraphRange(for: ns.range(of: "## Hé"))
        let paragraph = try #require(index.paragraph(range))
        #expect(paragraph.source == ns.substring(with: range))
        #expect(paragraph.spans.contains { $0.kind == .link(destination: "other.md") })
        #expect(paragraph.spans == model.spans.filter { NSIntersectionRange($0.range, range).length > 0 }.map {
            func shift(_ r: NSRange) -> NSRange { NSRange(location: r.location - range.location, length: r.length) }
            return MarkdownModel.Span(kind: $0.kind, range: shift($0.range), content: shift($0.content), markers: $0.markers.map(shift))
        })
        #expect(index.eagerSpans.isEmpty)
    }

    @Test(arguments: [
        "- **list**\n  continuation *text*\n",
        "> **quote**\n",
        "| **cell** | other |\n| --- | --- |\n| one | two |\n",
        "Setext **heading**\n---\n",
        "**across\nlines**\n",
        "<!-- toc -->\n- [Heading](#heading)\n<!-- /toc -->\n",
    ]) func contextualBlocksAreNotSplit(source: String) {
        let model = MarkdownModel(source)
        let index = MarkdownModel.ParagraphStyles(model)
        let ns = source as NSString
        var location = 0
        while location < ns.length {
            let range = ns.paragraphRange(for: NSRange(location: location, length: 0))
            #expect(index.paragraph(range) == nil)
            location = NSMaxRange(range)
        }
        #expect(index.eagerSpans == model.spans)
    }

    @Test func aBlockDoesNotPreventFollowingProseFromBeingDeferred() throws {
        let source = "```swift\nlet x = 1\n```\n\n**prose**\n\n- item\n\n# Heading\n"
        let model = MarkdownModel(source)
        let index = MarkdownModel.ParagraphStyles(model)
        let ns = source as NSString
        for needle in ["**prose**", "# Heading"] {
            let range = ns.paragraphRange(for: ns.range(of: needle))
            #expect(try #require(index.paragraph(range)).source == ns.substring(with: range))
        }
        #expect(!index.eagerSpans.contains { if case .heading = $0.kind { true } else { $0.kind == .strong } })
        #expect(index.paragraph(NSRange(location: ns.length + 1, length: 0)) == nil)
    }
}
