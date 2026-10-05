import Foundation
import Markdown
import Testing
@testable import MarkifyMarkdown

/// The shared fixture lives with the app tests so both suites read the same document.
private let fixture: String = {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../../MarkifyTests/Fixtures/editor-fixture.md").standardized
    return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
}()

struct Probe {
    let model: MarkdownModel
    let ns: NSString
    init(_ source: String, mdx: Bool = false) { model = MarkdownModel(source, mdx: mdx); ns = source as NSString }
    func text(_ range: NSRange) -> String { ns.substring(with: range) }
    func spans(_ include: (MarkdownModel.Kind) -> Bool) -> [MarkdownModel.Span] { model.spans(where: include) }
    func contents(_ include: (MarkdownModel.Kind) -> Bool) -> [String] { spans(include).map { text($0.content) } }
    func markers(_ include: (MarkdownModel.Kind) -> Bool) -> [[String]] { spans(include).map { $0.markers.map(text) } }
}

private func isHeading(_ kind: MarkdownModel.Kind) -> Bool { if case .heading = kind { true } else { false } }
private func isLink(_ kind: MarkdownModel.Kind) -> Bool { if case .link = kind { true } else { false } }
private func isImage(_ kind: MarkdownModel.Kind) -> Bool { if case .image = kind { true } else { false } }
private func isCode(_ kind: MarkdownModel.Kind) -> Bool { if case .codeBlock = kind { true } else { false } }
private func isQuote(_ kind: MarkdownModel.Kind) -> Bool { if case .blockQuote = kind { true } else { false } }
private func isCallout(_ kind: MarkdownModel.Kind) -> Bool { if case .callout = kind { true } else { false } }
private func isItem(_ kind: MarkdownModel.Kind) -> Bool { if case .listItem = kind { true } else { false } }
private func isReference(_ kind: MarkdownModel.Kind) -> Bool { if case .footnoteReference = kind { true } else { false } }
private func isDefinition(_ kind: MarkdownModel.Kind) -> Bool { if case .footnoteDefinition = kind { true } else { false } }

struct FixtureModelTests {
    let probe = Probe(fixture)

    @Test func fixtureLoads() { #expect(!fixture.isEmpty) }

    @Test func headings() {
        #expect(probe.spans(isHeading).map(\.kind) == [.heading(level: 1, setext: false), .heading(level: 2, setext: true)])
        #expect(probe.contents(isHeading) == ["ATX heading", "Setext heading"])
        #expect(probe.markers(isHeading) == [["# "], ["--------------"]])
    }

    @Test func inlineEmphasis() {
        #expect(probe.contents { $0 == .strong } == ["both", "a *b* c"])
        #expect(probe.contents { $0 == .emphasis } == ["***both***", "under", "b"])
        #expect(probe.markers { $0 == .emphasis } == [[], ["_", "_"], ["*", "*"]])
        #expect(probe.contents { $0 == .strikethrough } == ["struck"])
        #expect(probe.markers { $0 == .strikethrough } == [["~~", "~~"]])
        #expect(probe.markers { $0 == .escape } == [["\\"], ["\\"]])
        #expect(!probe.spans { $0 == .emphasis }.contains { probe.text($0.range).contains("snake") })
    }

    @Test func inlineCodeKeepsItsStars() {
        #expect(probe.contents { $0 == .inlineCode } == ["a*b*c | d"])
        #expect(!probe.spans { $0 == .emphasis }.contains { probe.text($0.content) == "b" && probe.text($0.range) == "*b*" && $0.range.location > probe.ns.range(of: "`a*b").location && $0.range.location < probe.ns.range(of: "`a*b").location + 10 })
    }

    @Test func linksAndImages() {
        #expect(probe.spans(isLink).map(\.kind) == [.link(destination: "other-note.md")])
        #expect(probe.markers(isLink) == [["[", "](other-note.md)"]])
        #expect(probe.spans(isImage).map(\.kind) == [
            .image(source: "assets/tiny%20pic.png", block: false),
            .image(source: "assets/My%20pic.png", block: true),
            .image(source: "https://example.com/pic.png", block: true)])
        #expect(probe.contents(isImage) == ["inline", "Block image", "Remote"])
    }

    @Test func lists() {
        let items = probe.spans(isItem).compactMap { span -> MarkdownModel.ListItem? in if case .listItem(let item) = span.kind { item } else { nil } }
        #expect(items.map { probe.text($0.marker) } == ["-", "-", "-", "-", "-", "-", "3.", "4."])
        #expect(items.map(\.depth) == [0, 0, 1, 0, 0, 1, 0, 0])
        #expect(items.compactMap { $0.checkbox.map(probe.text) } == ["[ ]", "[x]", "[ ]"])
        #expect(items.filter { $0.checkbox != nil }.map(\.checked) == [false, true, false])
        #expect(items.compactMap { $0.digits.map(probe.text) } == ["3", "4"])
        #expect(probe.model.lists.map(\.ordered) == [false, false, false, true])
        #expect(probe.model.lists.last?.start == 3)
    }

    @Test func tablesFollowGFM() {
        let rows = probe.model.tables.first?.rows ?? []
        #expect(probe.model.tables.count == 1)
        #expect(rows.map(\.separator) == [false, true, false, false])
        // GFM splits on the pipe inside the code span and drops cells past the header's count.
        #expect(rows.map { $0.cells.map(probe.text) } == [["Name", "Code"], ["---", "---"], ["pipe", "`a"], ["plain", "text"]])
    }

    @Test func codeBlocks() {
        #expect(probe.spans(isCode).map(\.kind) == [.codeBlock(language: "swift", fenced: true), .codeBlock(language: nil, fenced: true), .codeBlock(language: nil, fenced: false)])
        #expect(probe.contents(isCode) == ["let x = 1", "tilde fence", "    indented code"])
        #expect(probe.markers(isCode) == [["```swift", "```"], ["~~~", "~~~"], []])
    }

    @Test func extensions() {
        #expect(probe.contents { $0 == .frontmatter } == ["title: Editor fixture\ntags: [fixture, editor]\ndate: 2026-09-26\n"])
        #expect(probe.contents { $0 == .mathBlock } == ["\\frac{1}{2}"])
        #expect(probe.contents { $0 == .inlineMath } == ["x^2"])
        #expect(probe.spans(isReference).map(\.kind) == [.footnoteReference(label: "1")])
        #expect(probe.markers(isReference) == [["[^", "]"]])
        #expect(probe.contents(isDefinition) == ["The footnote text."])
        #expect(probe.markers(isDefinition) == [["[^", "]:"]])
    }

    @Test func quotesCalloutsAndBlocks() {
        #expect(probe.markers(isQuote) == [["> ", "> "], ["> "]])
        #expect(probe.spans(isCallout).map { if case .callout(let type, let token) = $0.kind { "\(type) \(probe.text(token))" } else { "" } } == ["NOTE [!NOTE]"])
        #expect(probe.contents { $0 == .htmlBlock } == ["<div>html block</div>"])
        #expect(probe.markers { $0 == .thematicBreak } == [["---"]])
    }
}

struct EdgeModelTests {
    @Test func indexedSourceOffsetsMatchScalarWalk() {
        let source = "ASCII **link** é😀e\u{301}終\r\n第二行 🐈\n"
        let map = MarkdownSourceMap(source)
        for (line, text) in map.lines.enumerated() {
            for byte in 0...text.utf8.count + 1 {
                var remaining = byte, utf16 = 0
                for scalar in text.unicodeScalars {
                    if remaining <= 0 { break }
                    remaining -= scalar.utf8.count
                    utf16 += scalar.utf16.count
                }
                let expected: Int? = remaining <= 0 ? map.starts[line] + utf16 : nil
                #expect(map.offset(Markdown.SourceLocation(line: line + 1, column: byte + 1, source: nil)) == expected)
            }
        }
    }

    @Test func offsetsSurviveUnicode() {
        let probe = Probe("😀 intro **bold** é\n# Café 🎉\n")
        #expect(probe.contents { $0 == .strong } == ["bold"])
        #expect(probe.contents(isHeading) == ["Café 🎉"])
        let heading = Markdown.Document(parsing: "😀 intro\n# Café\n").children.compactMap { $0 as? Heading }.first!
        #expect(MarkdownSourceMap("😀 intro\n# Café\n").range(heading.range!).map { ("😀 intro\n# Café\n" as NSString).substring(with: $0) } == "# Café")
    }

    @Test func frontmatterIsNotASetextHeading() {
        let probe = Probe("---\ntitle: T\n---\nBody\n")
        #expect(probe.spans(isHeading).isEmpty)
        #expect(probe.spans { $0 == .thematicBreak }.isEmpty)
        #expect(probe.contents { $0 == .frontmatter } == ["title: T\n"])
    }

    @Test func footnoteDefinitionTextStillParsesInline() {
        let probe = Probe("Claim[^a].\n\n[^a]: See *this*.\n")
        #expect(probe.contents { $0 == .emphasis } == ["this"])
        #expect(probe.spans(isLink).isEmpty)
        #expect(probe.contents(isReference) == ["a"])
    }

    @Test func footnoteDefinitionsKeepLabelAndText() {
        let probe = Probe("Body[^1]\n\n[^1]: The note.\n[^two]: Second\n")
        #expect(probe.spans(isDefinition).map(\.kind) == [.footnoteDefinition(label: "1", labelRange: NSRange(location: 12, length: 1)),
                                                          .footnoteDefinition(label: "two", labelRange: NSRange(location: 28, length: 3))])
        #expect(probe.contents(isDefinition) == ["The note.", "Second"])
    }

    @Test func mathFollowsPandocDollarRules() {
        #expect(Probe("Costs $5 and $10 today.").spans { $0 == .inlineMath }.isEmpty)
        #expect(Probe("Area $\\pi r^2$ here.").contents { $0 == .inlineMath } == ["\\pi r^2"])
        #expect(Probe("`$x$` and\n\n```\n$$\na\n$$\n```\n").spans { $0 == .inlineMath || $0 == .mathBlock }.isEmpty)
        // Emphasis characters inside math are not Markdown.
        #expect(Probe("See $a*b*c$ now.").spans { $0 == .emphasis }.isEmpty)
        #expect(Probe("$x$ starts a line\n").spans { if case .codeBlock = $0 { true } else { false } }.isEmpty)
    }

    @Test func escapesInsideMathAreNotEscapes() {
        #expect(Probe("Set $\\{x\\}$ here.").spans { $0 == .escape }.isEmpty)
    }

    @Test func tablesWithoutOuterPipes() {
        let probe = Probe("a | b\n--- | ---\n1 | 2\n")
        #expect(probe.model.tables.first?.rows.map { $0.cells.map(probe.text) } == [["a", "b"], ["---", "---"], ["1", "2"]])
    }

    @Test func emptyCellIsAnEmptyRangeAtItsClosingPipe() {
        let probe = Probe("| a | b |\n| - | - |\n|  | x |\n")
        let cell = probe.model.tables.first!.rows[2].cells[0]
        #expect(cell.length == 0)
        #expect(probe.ns.character(at: cell.location) == 124)
    }

    @Test func nestedContainersKeepTheirOwnMarkers() {
        let probe = Probe("> # Title\n> > inner\n\n- ```\n  code\n  ```\n")
        #expect(probe.markers(isHeading) == [["# "]])
        #expect(probe.markers(isQuote) == [["> ", "> "], ["> "]])
        #expect(probe.spans(isCode).first.map { probe.text($0.markers[0]) } == "```")
        #expect(probe.contents(isCode) == ["  code"])
    }

    @Test func unclosedFenceRunsToTheEnd() {
        let probe = Probe("```\nopen\nstill code")
        #expect(probe.contents(isCode) == ["open\nstill code"])
        #expect(probe.markers(isCode) == [["```"]])
    }

    @Test func autolinkMarkers() {
        #expect(Probe("<https://a.b>").markers(isLink) == [["<", ">"]])
    }

    @Test func mdxBlocksAreKeptAsWritten() {
        let source = "import Chart from './chart'\nexport const meta = { title: 'x' }\n\n# Title\n\n<Chart data={[1, 2]}>\n  **not markdown**\n</Chart>\n\n```js\nimport x from 'y'\n```\n\nText with <Inline/> JSX.\n"
        let mdx = Probe(source, mdx: true)
        #expect(mdx.contents { $0 == .mdxBlock } == ["import Chart from './chart'\nexport const meta = { title: 'x' }", "<Chart data={[1, 2]}>\n  **not markdown**\n</Chart>"])
        #expect(mdx.spans { $0 == .strong }.isEmpty)
        #expect(mdx.contents(isHeading) == ["Title"])
        #expect(mdx.spans(isCode).count == 1)
        // A plain Markdown file reads the same text as Markdown and HTML.
        #expect(Probe(source).spans { $0 == .mdxBlock }.isEmpty)
    }

    @Test func largeDocumentParsesQuickly() {
        let large = Array(repeating: fixture, count: 60).joined(separator: "\n")
        let elapsed = ContinuousClock().measure { _ = MarkdownModel(large) }
        #expect(elapsed < .seconds(1), "model took \(elapsed)")
    }
}
