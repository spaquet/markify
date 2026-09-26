import AppKit
import MarkifyMarkdown
import Testing
@testable import Markify

private final class FixtureBundle {}

/// Characterization of how both lenses style `Fixtures/editor-fixture.md`.
/// The AST refactor must keep these results unless a change is listed in EDITOR_PLAN.md.
@MainActor struct EditorFixtureTests {
    static let source: String = {
        let bundle = Bundle(for: FixtureBundle.self)
        let url = bundle.url(forResource: "editor-fixture", withExtension: "md")
            ?? bundle.url(forResource: "editor-fixture", withExtension: "md", subdirectory: "Fixtures")
        return url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }()

    static func styled(markdownLens: Bool) -> NSTextView {
        let editor = NSTextView(usingTextLayoutManager: true)
        editor.string = source
        NativeEditor(text: .constant(source), fileURL: nil, columnWidth: 640, markdownLens: markdownLens, findQuery: "", matchCase: false,
                     selectedRange: .constant(NSRange(location: 0, length: 0)),
                     textView: .constant(nil), onType: {}, onSlash: { _ in }, onSlashKey: { _, _ in false }, onSelectionRect: { _ in })
            .style(editor)
        return editor
    }

    /// A compact description of the attributes at one offset: size, traits and flags.
    static func describe(_ storage: NSTextStorage, at location: Int) -> String {
        let attributes = storage.attributes(at: location, effectiveRange: nil)
        var parts: [String] = []
        if let font = attributes[.font] as? NSFont {
            parts.append(String(Int(font.pointSize.rounded())))
            let traits = font.fontDescriptor.symbolicTraits
            if traits.contains(.bold) { parts.append("b") }
            if traits.contains(.italic) { parts.append("i") }
            if traits.contains(.monoSpace) { parts.append("m") }
        }
        if let color = attributes[.foregroundColor] as? NSColor {
            if color.alphaComponent == 0 { parts.append("hidden") }
            else if color == EditorTheme().accent { parts.append("accent") }
            else if color == .tertiaryLabelColor { parts.append("dim") }
        }
        if attributes[.strikethroughStyle] != nil { parts.append("strike") }
        if (attributes[.backgroundColor] as? NSColor) == .codeFill { parts.append("code") }
        if attributes[.markifyBlockFill] != nil { parts.append("fill") }
        return parts.joined(separator: " ")
    }

    /// Probes: a name, a unique needle in the fixture, and an offset inside it.
    static let probes: [(name: String, needle: String, offset: Int)] = [
        ("atx marker", "# ATX", 0),
        ("atx text", "# ATX", 2),
        ("setext text", "Setext heading", 0),
        ("setext underline", "--------------", 0),
        ("both marker", "***both***", 0),
        ("both text", "***both***", 3),
        ("underscore marker", "_under_", 0),
        ("underscore text", "_under_", 1),
        ("nested strong", "**a *b* c**", 2),
        ("nested emphasis", "**a *b* c**", 5),
        ("strike marker", "~~struck~~", 0),
        ("strike text", "~~struck~~", 2),
        ("escaped star", "\\*not", 1),
        ("escaped text", "\\*not", 2),
        ("escape backslash", "\\*not", 0),
        ("snake", "snake_case_name", 6),
        ("code tick", "`a*b*c | d`", 0),
        ("code star", "`a*b*c | d`", 2),
        ("link text", "[a link]", 1),
        ("link bracket", "[a link]", 0),
        ("link url", "(other-note.md)", 1),
        ("inline image", "![inline]", 2),
        ("block image caption", "![Block image]", 2),
        ("remote image caption", "![Remote]", 2),
        ("bullet marker", "- bullet one", 0),
        ("bullet text", "- bullet one", 2),
        ("nested bullet marker", "  - nested bullet", 2),
        ("task open box", "- [ ] open task", 3),
        ("task open text", "- [ ] open task", 6),
        ("task done text", "- [x] done task", 6),
        ("nested task box", "  - [ ] nested task", 5),
        ("nested task text", "  - [ ] nested task", 8),
        ("ordered number", "3. three", 0),
        ("ordered text", "3. three", 3),
        ("lazy line", "lazy continuation", 0),
        ("table pipe", "| pipe |", 0),
        ("table cell", "| pipe |", 2),
        ("fence open", "```swift", 0),
        ("fence body", "let x = 1", 4),
        ("tilde fence", "~~~\ntilde", 0),
        ("tilde body", "tilde fence", 0),
        ("indented code", "    indented code", 4),
        ("math fence", "$$\n\\frac", 0),
        ("math body", "\\frac{1}{2}", 1),
        ("inline math", "$x^2$", 1),
        ("inline math dollar", "$x^2$", 0),
        ("callout token", "[!NOTE]", 2),
        ("callout body", "Callout body", 0),
        ("quote marker", "> Plain quote", 0),
        ("quote text", "> Plain quote", 2),
        ("footnote ref", "ref[^1]", 5),
        ("footnote def label", "[^1]: The", 2),
        ("footnote def text", "[^1]: The", 6),
        ("html block", "<div>html", 1),
        ("thematic break", "\n---\n\n[^1]", 1),
        ("frontmatter key", "title: Editor", 0),
    ]

    static func results(markdownLens: Bool) -> [String: String] {
        let editor = styled(markdownLens: markdownLens)
        let ns = source as NSString
        return Dictionary(uniqueKeysWithValues: probes.map { probe in
            let range = ns.range(of: probe.needle)
            return (probe.name, range.location == NSNotFound ? "missing" : describe(editor.textStorage!, at: range.location + probe.offset))
        })
    }

    @Test func fixtureLoadsAndProbesAreUnique() {
        #expect(!Self.source.isEmpty)
        for probe in Self.probes {
            let ns = Self.source as NSString
            let first = ns.range(of: probe.needle)
            #expect(first.location != NSNotFound, "\(probe.name)")
            let rest = NSRange(location: NSMaxRange(first), length: ns.length - NSMaxRange(first))
            #expect(ns.range(of: probe.needle, range: rest).location == NSNotFound, "\(probe.name) is not unique")
        }
    }

    @Test func stylingKeepsTheSource() {
        for lens in [false, true] { #expect(Self.styled(markdownLens: lens).string == Self.source) }
    }

    @Test func renderedLensMatchesGolden() {
        let results = Self.results(markdownLens: false)
        for probe in Self.probes { #expect(results[probe.name] == Self.renderedGolden[probe.name], "\(probe.name)") }
    }

    @Test func markdownLensMatchesGolden() {
        let results = Self.results(markdownLens: true)
        for probe in Self.probes { #expect(results[probe.name] == Self.markdownGolden[probe.name], "\(probe.name)") }
    }

    @Test func listScanOverFixture() {
        let ns = Self.source as NSString
        let scan = MarkdownList.scan(Self.source)
        #expect(scan.numbers.map(\.value) == ["3", "4"])
        #expect(scan.fixes.isEmpty)
        #expect(scan.lazyLines.map { ns.substring(with: $0.line).trimmingCharacters(in: .newlines) } == ["lazy continuation line"])
    }

    @Test func tableBlocksOverFixture() {
        let ns = Self.source as NSString
        let tables = MarkdownTable.blocks(in: Self.source)
        #expect(tables.count == 1)
        let rows = tables.first?.rows.map { $0.cells.map(ns.substring(with:)) } ?? []
        #expect(rows.count == 4)
        #expect(rows.first == ["Name", "Code"])
        // GFM splits on the pipe inside the code span and drops cells past the header's count.
        #expect(rows.dropFirst(2).first == ["pipe", "`a"])
        #expect(rows.last == ["plain", "text"])
    }

    @Test func footnotesAndFrontmatterOverFixture() {
        let notes = MarkdownModel(Self.source).spans.compactMap { span -> (String, String)? in
            if case .footnoteDefinition(let label, _) = span.kind { (label, (Self.source as NSString).substring(with: span.content)) } else { nil }
        }
        #expect(notes.map(\.0) == ["1"])
        #expect(notes.first?.1 == "The footnote text.")
        let frontmatter = Frontmatter.parse(Self.source)
        #expect(frontmatter?.title == "Editor fixture")
        #expect(frontmatter?.tags == ["fixture", "editor"])
        #expect(frontmatter?.date == "2026-09-26")
    }

    @Test func mdxBlocksAreDimmedInMDXFilesOnly() {
        let source = "import Chart from './chart'\n\n<Chart>\n  **x**\n</Chart>\n"
        for (url, dimmed) in [(URL(fileURLWithPath: "/tmp/a.mdx"), true), (URL(fileURLWithPath: "/tmp/a.md"), false)] {
            let editor = NSTextView(usingTextLayoutManager: true)
            editor.string = source
            NativeEditor(text: .constant(source), fileURL: url, columnWidth: 640, markdownLens: false, findQuery: "", matchCase: false,
                         selectedRange: .constant(NSRange(location: 0, length: 0)),
                         textView: .constant(nil), onType: {}, onSlash: { _ in }, onSlashKey: { _, _ in false }, onSelectionRect: { _ in })
                .style(editor)
            #expect(editor.string == source)
            #expect((Self.describe(editor.textStorage!, at: 0) == "18 dim") == dimmed, "\(url.lastPathComponent)")
            // In a .md file `<Chart>` starts a CommonMark HTML block, dimmed as HTML.
            #expect(Self.describe(editor.textStorage!, at: (source as NSString).range(of: "**x**").location + 2) == "18 dim")
        }
    }

    @Test func imagePathsDecodeBeforeLoading() {
        let document = URL(fileURLWithPath: "/tmp/notes/note.md")
        #expect(MarkdownTextView.imageURL("assets/My%20pic.png", document: document).path == "/tmp/notes/assets/My pic.png")
        #expect(MarkdownTextView.imageURL("assets/plain.png", document: document).path == "/tmp/notes/assets/plain.png")
        #expect(MarkdownTextView.imageURL("/abs/pic.png", document: document).path == "/abs/pic.png")
        #expect(MarkdownTextView.imageURL("100%.png", document: document).path == "/tmp/notes/100%.png")
    }

    /// Guards against a pathological slowdown; Phase 0 baseline: 0.14 s for 3,780 lines, down from 31 s before tables were scanned in one pass.
    @Test func stylingALargeDocumentStaysFast() {
        let large = Array(repeating: Self.source, count: 60).joined(separator: "\n")
        let editor = NSTextView(usingTextLayoutManager: true)
        editor.string = large
        let native = NativeEditor(text: .constant(large), fileURL: nil, columnWidth: 640, markdownLens: false, findQuery: "", matchCase: false,
                                  selectedRange: .constant(NSRange(location: 0, length: 0)),
                                  textView: .constant(nil), onType: {}, onSlash: { _ in }, onSlashKey: { _, _ in false }, onSelectionRect: { _ in })
        let elapsed = ContinuousClock().measure { native.style(editor) }
        #expect(elapsed < .seconds(2), "style() took \(elapsed)")
    }

    /// Hidden syntax must not leave gaps: text after a link, emphasis or code lands where it would without the syntax.
    @Test func hiddenMarkersTakeNoRoom() {
        func distance(_ source: String, from first: String, to last: String) -> CGFloat {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 300), styleMask: [.titled], backing: .buffered, defer: true)
            let editor = NSTextView(usingTextLayoutManager: true)
            editor.frame = window.contentView!.bounds
            window.contentView = editor
            editor.string = source
            NativeEditor(text: .constant(source), fileURL: nil, columnWidth: 640, markdownLens: false, findQuery: "", matchCase: false,
                         selectedRange: .constant(NSRange(location: 0, length: 0)),
                         textView: .constant(nil), onType: {}, onSlash: { _ in }, onSlashKey: { _, _ in false }, onSelectionRect: { _ in })
                .style(editor)
            editor.layoutSubtreeIfNeeded()
            let ns = source as NSString
            func x(_ needle: String) -> CGFloat { editor.firstRect(forCharacterRange: ns.range(of: needle), actualRange: nil).minX }
            return x(last) - x(first)
        }
        let plain = distance("Start link end", from: "Start", to: "end")
        #expect(abs(distance("Start [link](https://example.com/a/rather/long/path.md) end", from: "Start", to: "end") - plain) < 1)
        let code = distance("Start `x` end", from: "Start", to: "end")
        #expect(abs(distance("Start ``x`` end", from: "Start", to: "end") - code) < 1)
        let bold = distance("Start **x** end", from: "Start", to: "end")
        #expect(abs(distance("Start ***x*** end", from: "Start", to: "end") - bold) < 3)
    }

    /// Current styling per probe. Entries marked "expected to change" are known gaps the AST refactor fixes.
    static let renderedGolden: [String: String] = [
        "atx marker": "1 hidden",
        "atx text": "36 b",
        "setext text": "22 b",
        "setext underline": "1 hidden",
        "both marker": "1 hidden",
        "both text": "18 b i",
        "underscore marker": "1 hidden",
        "underscore text": "18 i",
        "nested strong": "18 b",
        "nested emphasis": "18 b i",
        "strike marker": "1 hidden",
        "strike text": "18 strike",
        "escaped star": "18",
        "escaped text": "18",
        "escape backslash": "1 hidden",
        "snake": "18",
        "code tick": "1 hidden",
        "code star": "15 m",
        "link text": "18 accent",
        "link bracket": "1 hidden",
        "link url": "1 hidden",
        "inline image": "12 hidden",
        "block image caption": "13",
        "remote image caption": "13",
        "bullet marker": "18 m hidden",
        "bullet text": "18",
        "nested bullet marker": "18 m hidden",
        "task open box": "10 m hidden",
        "task open text": "17",
        "task done text": "17 dim strike",
        "nested task box": "10 m hidden",
        "nested task text": "17",
        "ordered number": "18 hidden",
        "ordered text": "18",
        "lazy line": "18",
        "table pipe": "1 hidden",
        "table cell": "1 hidden",
        "fence open": "1 hidden",
        "fence body": "14 m fill",
        "tilde fence": "1 hidden",
        "tilde body": "14 m fill",
        "indented code": "14 m fill",
        "math fence": "1 hidden",
        "math body": "1 hidden",
        "inline math": "18 i",
        "inline math dollar": "1 hidden",
        "callout token": "13 b hidden fill",
        "callout body": "15 fill",
        "quote marker": "1 hidden",
        "quote text": "18",
        "footnote ref": "11 b accent",
        "footnote def label": "13 b accent",
        "footnote def text": "13",
        "html block": "18 dim",
        "thematic break": "1 hidden",
        "frontmatter key": "1 hidden",
    ]

    static let markdownGolden: [String: String] = [
        "atx marker": "14 m dim",
        "atx text": "16 b m",
        "setext text": "16 b m",
        "setext underline": "14 m dim",
        "both marker": "14 m dim",
        "both text": "14 b i m",
        "underscore marker": "14 m dim",
        "underscore text": "14 i m",
        "nested strong": "14 b m",
        "nested emphasis": "14 b i m",
        "strike marker": "14 m dim",
        "strike text": "14 m strike",
        "escaped star": "14 m",
        "escaped text": "14 m",
        "escape backslash": "14 m dim",
        "snake": "14 m",
        "code tick": "14 m dim",
        "code star": "14 m",
        "link text": "14 m",
        "link bracket": "14 m dim",
        "link url": "14 m accent",
        "inline image": "14 m",
        "block image caption": "14 m",
        "remote image caption": "14 m",
        "bullet marker": "14 m dim",
        "bullet text": "14 m",
        "nested bullet marker": "14 m dim",
        "task open box": "14 m dim",
        "task open text": "14 m",
        "task done text": "14 m",
        "nested task box": "14 m dim",
        "nested task text": "14 m",
        "ordered number": "14 m dim",
        "ordered text": "14 m",
        "lazy line": "14 m",
        "table pipe": "14 m dim",
        "table cell": "14 m",
        "fence open": "14 m dim",
        "fence body": "14 m code",
        "tilde fence": "14 m dim",
        "tilde body": "14 m code",
        "indented code": "14 m code",
        "math fence": "14 m dim",
        "math body": "14 m",
        "inline math": "14 m",
        "inline math dollar": "14 m dim",
        "callout token": "14 m accent",
        "callout body": "14 m",
        "quote marker": "14 m dim",
        "quote text": "14 m",
        "footnote ref": "14 m accent",
        "footnote def label": "14 m accent",
        "footnote def text": "14 m dim",
        "html block": "14 m dim",
        "thematic break": "14 m dim",
        "frontmatter key": "14 m",
    ]
}
