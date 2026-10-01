import Foundation
import Testing
@testable import MarkifyMarkdown

struct PreviewLinksTests {
    @Test func localPreviewLinksResolveAndOnlyReferencedMarkdownCanOpen() throws {
        let document = URL(fileURLWithPath: "/tmp/project/notes/README.md")
        let target = URL(fileURLWithPath: "/tmp/project/other café.md")
        let destination = "../other%20caf%C3%A9.md#section"
        let request = try #require(URL(string: PreviewLinks.target(destination, relativeTo: document)))
        #expect(PreviewLinks.fileToOpen(request) == target)
        for invalid in ["markify-preview://open?file=https://example.com/a.md", "markify-preview://open?file=file:///tmp/a.md&file=file:///tmp/b.md", "markify-preview://open/path?file=file:///tmp/a.md", "markify-preview://user@open?file=file:///tmp/a.md"] {
            #expect(PreviewLinks.fileToOpen(try #require(URL(string: invalid))) == nil)
        }
        #expect(PreviewLinks.target("#section", relativeTo: document) == "#section")
        #expect(PreviewLinks.target("https://example.com/page#part", relativeTo: document) == "https://example.com/page#part")
        #expect(PreviewLinks.target("mailto:reader@example.com", relativeTo: document) == "mailto:reader@example.com")
        let source = "[Note][note]\n\n[note]: \(destination)\n"
        #expect(try PreviewLinks.referencedMarkdown(target, in: source, from: document) == target)
        #expect(try PreviewLinks.referencedMarkdown(target, in: "<a href=\"\(destination)\">HTML link</a>", from: document) == target)
        #expect(try PreviewLinks.referencedMarkdown(target, in: "Text[^one]\n\n[^one]: [Note](\(destination))\n", from: document) == target)
        for ext in ["md", "markdown", "mdx"] {
            let file = URL(fileURLWithPath: "/tmp/project/notes/a.\(ext)")
            #expect(try PreviewLinks.referencedMarkdown(file, in: "[A](a.\(ext))", from: document) == file)
        }
        #expect(throws: (any Error).self) { try PreviewLinks.referencedMarkdown(document, in: source, from: document) }
        #expect(throws: (any Error).self) { try PreviewLinks.referencedMarkdown(target, in: "![image](\(destination))\n`[code](\(destination))`", from: document) }
        #expect(throws: (any Error).self) { try PreviewLinks.referencedMarkdown(URL(fileURLWithPath: "/tmp/a.sh"), in: "[Run](/tmp/a.sh)", from: document) }
        for invalid in ["javascript:alert(1)", "markify://welcome", "file://server/share/a.md", "file:///tmp/a%00.md", "a%00.md", "a%GG.md"] {
            #expect(PreviewLinks.localURL(invalid, relativeTo: document) == nil)
            #expect(PreviewLinks.target(invalid, relativeTo: document) == "#")
        }
        #expect(PreviewLinks.localURL(target.absoluteString, relativeTo: document) == target)
    }
}
