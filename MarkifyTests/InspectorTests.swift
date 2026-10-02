import AppKit
import MarkifyMarkdown
import Testing
@testable import Markify

/// The Contents and Links pane: outline rows, the inserted table of contents, link targets and checks, and link fixes.
struct InspectorTests {
    static let outline = """
    # Guide
    ## Install
    ### macOS
    #### Details
    ### Linux
    ## Use
    # Appendix
    """

    @Test func outlineRowsFollowDepthCollapseAndFilter() {
        let headings = DocumentHeading.extract(from: MarkdownModel(Self.outline))
        func titles(depth: Int = 6, query: String = "", collapsed: Set<String> = []) -> [String] {
            DocumentOutline.rows(headings, depth: depth, query: query, collapsed: collapsed).map(\.heading.title)
        }
        #expect(titles() == ["Guide", "Install", "macOS", "Details", "Linux", "Use", "Appendix"])
        #expect(titles(depth: 2) == ["Guide", "Install", "Use", "Appendix"])
        #expect(titles(depth: 1) == ["Guide", "Appendix"])
        // Collapsing hides a section's headings down to the next heading at its level or above.
        #expect(titles(collapsed: ["install"]) == ["Guide", "Install", "Use", "Appendix"])
        // A filter shows matches inside their sections, expanded.
        #expect(titles(query: "linux", collapsed: ["install"]) == ["Guide", "Install", "Linux"])
        #expect(titles(query: "nothing").isEmpty)

        let rows = DocumentOutline.rows(headings, depth: 3, query: "", collapsed: [])
        #expect(rows.map(\.indent) == [0, 1, 2, 2, 1, 0])
        // Children count only within the depth: macOS has a level 4 heading under it, hidden at depth 3.
        #expect(rows.map(\.hasChildren) == [true, true, false, false, false, false])
    }

    @Test func activeHeadingAndAncestors() {
        let headings = DocumentHeading.extract(from: MarkdownModel(Self.outline))
        let linux = (Self.outline as NSString).range(of: "Linux").location
        let active = DocumentOutline.active(headings, at: linux + 2)
        #expect(active.map { headings[$0].title } == "Linux")
        #expect(DocumentOutline.ancestors(of: active!, in: headings).map { headings[$0].title }.sorted() == ["Guide", "Install"])
        // Above the first heading, the first one is the one being read.
        #expect(DocumentOutline.active(headings, at: 0) == 0)
        #expect(DocumentOutline.active([], at: 10) == nil)
    }

    @Test func tableOfContentsLinksHeadingsToTheDepth() {
        let headings = DocumentHeading.extract(from: MarkdownModel("## Intro [draft]\n### Steps\n## Intro [draft]\n"))
        #expect(DocumentOutline.tableOfContents(headings, depth: 3) == """
        - [Intro \\[draft\\]](#intro-draft)
          - [Steps](#steps)
        - [Intro \\[draft\\]](#intro-draft-1)
        """)
        #expect(DocumentOutline.tableOfContents(headings, depth: 2).components(separatedBy: "\n").count == 2)
        // The anchors are the ones export writes, so the inserted links work in HTML and PDF too.
        let html = MarkdownHTML.render("## Intro [draft]\n### Steps\n## Intro [draft]\n").body
        #expect(html.contains("id=\"intro-draft\"") && html.contains("id=\"intro-draft-1\""))
    }

    @Test func linkTargetsSortIntoAnchorsFilesAndWeb() {
        let document = URL(fileURLWithPath: "/tmp/notes/doc.md")
        func target(_ destination: String, base: URL? = nil) -> LinkTarget? {
            LinkTarget.of(destination, document: base == nil ? document : nil, root: nil, baseDirectory: base)
        }
        #expect(target("#method") == .anchor("method"))
        #expect(target("#caf%C3%A9") == .anchor("café"))
        #expect(target("other.md#real-section") == .file(URL(fileURLWithPath: "/tmp/notes/other.md"), fragment: "real-section"))
        #expect(target("https://example.com/a") == .web(URL(string: "https://example.com/a")!))
        // Mail, phone and app links are not listed.
        #expect(target("mailto:a@b.c") == nil)
        #expect(target("things:///show") == nil)
        // In a document opened from the web, relative links are web links.
        #expect(target("guide.md", base: URL(string: "https://example.com/docs/")!) == .web(URL(string: "https://example.com/docs/guide.md")!))
    }

    @Test @MainActor func linkEntriesKeepSectionsApartAndHideOtherSchemes() {
        let source = "[a](other.md) [b](other.md#x) [c](other.md#x) [d](mailto:a@b.c) [e](#top)"
        let entries = LinkEntry.entries(DocumentLink.extract(from: MarkdownModel(source)), document: URL(fileURLWithPath: "/tmp/doc.md"), root: nil, baseDirectory: nil)
        #expect(entries.map(\.first.text) == ["a", "b", "e"])
        #expect(entries.map(\.group.occurrences.count) == [1, 2, 1])
        // A file's sections share its summary.
        #expect(entries[0].summaryKey == entries[1].summaryKey)
    }

    @Test func localChecksFindMissingHeadingsAndFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let other = folder.appendingPathComponent("other.md")
        try Data("# Other\n\n## Real section\n".utf8).write(to: other)
        let anchors: Set<String> = ["method"]
        func check(_ target: LinkTarget, open: [URL: String] = [:]) -> LinkStatus {
            LocalLinkCheck.status(of: target, anchors: anchors, openTexts: open)
        }
        #expect(check(.anchor("method")) == .ok)
        #expect(check(.anchor("roadmap")) == .broken("No such heading"))
        #expect(check(.file(other, fragment: nil)) == .ok)
        #expect(check(.file(other, fragment: "real-section")) == .ok)
        #expect(check(.file(other, fragment: "nope")) == .broken("No such heading"))
        #expect(check(.file(folder.appendingPathComponent("missing.md"), fragment: nil)) == .broken("File not found"))
        #expect(check(.file(nil, fragment: nil)) == .unknown)
        // An open, unsaved editor's text counts over the file on disk.
        #expect(check(.file(other, fragment: "new-part"), open: [other.standardizedFileURL: "# Other\n## New part\n"]) == .ok)
    }

    @Test func suggestionsRankClosestFirst() throws {
        #expect(LinkSuggestions.ranked(["installation", "usage", "install"], near: "instal").first == "install")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["sync notes.md", "syncing.md", "image.png"] { try Data().write(to: folder.appendingPathComponent(name)) }
        let files = LinkSuggestions.files(replacing: "help/sync.md", missing: folder.appendingPathComponent("sync.md"))
        #expect(files == ["help/syncing.md", "help/sync%20notes.md"])
    }

    @Test func readableTextDropsMarkupAndScripts() {
        let html = "<html><head><style>p{}</style><script>alert(1)</script></head><body><h1>Title</h1><p>One &amp; two</p></body></html>"
        #expect(ReadableText.fromHTML(html) == "Title\nOne & two")
        #expect(ReadableText.fromMarkdown("# Notes\n\n**Bold** text", mdx: false) == "Notes\nBold text")
    }

    @Test func webProbeReadsStatusCodes() async {
        // No network: a URL protocol answers every request.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: configuration)
        func probe(_ path: String) async -> String?? { await WebLinkChecks.probe(URL(string: "https://stub.test/\(path)")!, session: session) }
        #expect(await probe("200") == .some(nil))
        #expect(await probe("404") == .some("Not found (404)"))
        #expect(await probe("403") == .some(nil))
        #expect(await probe("500") == .some("Error 500"))
        // Rate limited says nothing about the link.
        #expect(await probe("429") == nil)
        // A server that refuses HEAD is asked with GET.
        #expect(await probe("head-405") == .some(nil))
    }

    @Test @MainActor func webChecksCacheForADayUnlessForced() async throws {
        let location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: location) }
        let checks = WebLinkChecks(location: location)
        #expect(checks.status(of: URL(string: "https://example.com")!) == .unknown)
        #expect(WebLinkChecks.key(URL(string: "https://example.com/a#part")!) == "https://example.com/a")
    }

    @Test @MainActor func fixingALinkRewritesEveryOccurrenceInOneUndo() {
        let source = "See [one](old.md) and [two](old.md).\n\nRef [three][r].\n\n[r]: old.md\n"
        let (window, editor) = LayoutFragmentTests.makeEditor(source)
        _ = window
        let undo = UndoManager()
        let links = DocumentLink.extract(from: MarkdownModel(source))
        #expect(editor.replaceLinkDestination("old.md", with: "new.md", in: links.map(\.range)) == 3)
        #expect(editor.string == "See [one](new.md) and [two](new.md).\n\nRef [three][r].\n\n[r]: new.md\n")
        _ = undo
    }

    @Test @MainActor func tableOfContentsInsertsAsItsOwnBlock() {
        let (window, editor) = LayoutFragmentTests.makeEditor("Intro text\nmore")
        _ = window
        editor.setSelectedRange(NSRange(location: 10, length: 0))
        editor.insertBlock("- [A](#a)")
        #expect(editor.string == "Intro text\n\n- [A](#a)\n\nmore")
    }

    @Test func tableOfContentsMarkersAndBlock() {
        #expect(TableOfContentsMarker.depth(ofOpening: "<!-- toc -->") == 6)
        #expect(TableOfContentsMarker.depth(ofOpening: "<!--TOC depth=2-->\n") == 2)
        #expect(TableOfContentsMarker.depth(ofOpening: "<!-- toc depth=9 -->") == nil)
        #expect(TableOfContentsMarker.depth(ofOpening: "<!-- note -->") == nil)
        #expect(TableOfContentsMarker.isClosing("<!-- /toc -->\n"))
        #expect(TableOfContentsMarker.opening(depth: 2) == "<!-- toc depth=2 -->")

        let headings = DocumentHeading.extract(from: MarkdownModel("# A\n## B\n"))
        let block = TableOfContentsBlock.text(headings, depth: 6)
        #expect(block == "<!-- toc -->\n- [A](#a)\n  - [B](#b)\n<!-- /toc -->")
        let source = "Intro\n\n" + block + "\n\n# A\n## B\n"
        let found = TableOfContentsBlock.find(in: MarkdownModel(source))
        #expect(found.map { (source as NSString).substring(with: $0.range) } == block)
        #expect(found.map { (source as NSString).substring(with: $0.body) } == "- [A](#a)\n  - [B](#b)\n")
        #expect(found?.depth == 6)
        // Without its closing comment there is no block to keep.
        #expect(TableOfContentsBlock.find(in: MarkdownModel("<!-- toc -->\n- [A](#a)\n")) == nil)
    }

    @Test @MainActor func tableOfContentsFollowsTheHeadings() {
        let source = "<!-- toc -->\n- [Old](#old)\n<!-- /toc -->\n\n# Intro\n\ntext\n\n## Steps\n"
        let (window, editor) = LayoutFragmentTests.makeEditor(source)
        _ = window
        let undo = UndoManager()
        _ = undo
        // The caret after the block keeps its place in the text.
        let text = (source as NSString).range(of: "text").location
        editor.setSelectedRange(NSRange(location: text, length: 0))
        #expect(editor.updateTableOfContents())
        #expect(editor.string.hasPrefix("<!-- toc -->\n- [Intro](#intro)\n  - [Steps](#steps)\n<!-- /toc -->\n\n# Intro"))
        #expect((editor.string as NSString).substring(with: NSRange(location: editor.selectedRange().location, length: 4)) == "text")
        #expect(!editor.updateTableOfContents())
        // Not while the caret is inside it, unless the pane asks.
        editor.setSelectedRange(NSRange(location: 15, length: 0))
        editor.insertText("## New\n", replacementRange: NSRange(location: editor.string.count, length: 0))
        editor.setSelectedRange(NSRange(location: 15, length: 0))
        #expect(!editor.updateTableOfContents())
        #expect(editor.updateTableOfContents(depth: 1))
        #expect(editor.string.hasPrefix("<!-- toc depth=1 -->\n- [Intro](#intro)\n<!-- /toc -->"))
    }

    @Test func tableOfContentsExportsAsACard() {
        let html = MarkdownHTML.render("<!-- toc -->\n- [A](#a)\n  - [B](#b)\n<!-- /toc -->\n\n# A\n## B\n").body
        #expect(html.hasPrefix("<nav class=\"toc\" aria-label=\"Contents\">\n<p class=\"toc-title\">Contents</p>\n<ul>"))
        #expect(html.contains("</ul>\n</nav>\n"))
        #expect(!html.contains("<!--"))
        #expect(MarkdownPage.stylesheet.contains(".toc{"))
    }

    @Test @MainActor func tableOfContentsDrawsAsACardInTheRenderedLens() {
        let source = "<!-- toc -->\n- [Intro](#intro)\n  - [Steps](#steps)\n<!-- /toc -->\n\n# Intro\n\n## Steps\n"
        let (window, editor) = LayoutFragmentTests.makeEditor(source)
        _ = window
        let storage = editor.textStorage!
        let ns = source as NSString
        #expect(editor.string == source)
        // The comments don't show; the entries carry no bullets, sit in one rounded box, and nested ones get a guide.
        #expect(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .clear)
        #expect(storage.attribute(.markifyBullet, at: ns.range(of: "- [Intro]").location, effectiveRange: nil) == nil)
        let steps = ns.range(of: "Steps").location
        #expect(storage.attribute(.markifyBlockFill, at: steps, effectiveRange: nil) != nil)
        #expect((storage.attribute(.markifyGuides, at: steps, effectiveRange: nil) as? MarkdownGuides)?.count == 1)
        #expect((storage.attribute(.font, at: ns.range(of: "Intro").location, effectiveRange: nil) as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    @Test @MainActor func anchorsRevealTheirHeading() {
        let (window, editor) = LayoutFragmentTests.makeEditor("# Top\n\ntext\n\n## Next part\n\nmore\n")
        _ = window
        #expect(editor.revealAnchor("next-part"))
        #expect(editor.selectedRange() == NSRange(location: 16, length: 0))
        #expect(!editor.revealAnchor("missing"))
    }
}

/// Answers each request with the status code named by the path's last component; `head-405` refuses HEAD only.
final class StubProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "stub.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let name = request.url?.lastPathComponent ?? "200"
        let code = name == "head-405" ? (request.httpMethod == "HEAD" ? 405 : 206) : Int(name) ?? 200
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
