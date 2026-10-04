import Foundation
import Markdown

/// Renders a Markdown source to an HTML fragment, with the same reading of the source as `MarkdownModel`:
/// CommonMark and GFM from cmark, plus Markify's extensions (frontmatter, math, footnotes, callouts, MDX blocks).
///
/// Extensions are found first and replaced by private-use tokens that cmark reads as plain text, then rendered
/// where their token lands. What depends on the app — math, diagrams, image sources, link targets, code colors —
/// comes from `Options`.
public struct MarkdownHTML {
    public struct Options {
        /// Include the fenced code language as a visible label.
        public var codeLabels = true
        /// LaTeX to HTML, `true` for display math; nil shows the LaTeX as code.
        public var math: (_ latex: String, _ display: Bool) -> String?
        /// A fenced block's language and code to HTML, for diagrams; nil renders it as a code block.
        public var diagram: (_ language: String, _ code: String) -> String?
        /// An image source as written to the `src` to write.
        public var image: (_ source: String) -> String
        /// A link destination as written to the `href` to write.
        public var link: (_ destination: String) -> String
        /// Code to highlighted HTML (escaped, with spans); nil escapes it plainly.
        public var highlight: (_ code: String, _ language: String?) -> String?

        public init(math: @escaping (String, Bool) -> String? = { _, _ in nil },
                    diagram: @escaping (String, String) -> String? = { _, _ in nil },
                    image: @escaping (String) -> String = { $0 },
                    link: @escaping (String) -> String = { $0 },
                    highlight: @escaping (String, String?) -> String? = { _, _ in nil }) {
            self.math = math
            self.diagram = diagram
            self.image = image
            self.link = link
            self.highlight = highlight
        }
    }

    public struct Result {
        /// The rendered body, without the frontmatter.
        public let body: String
        /// The text of the first level-1 heading.
        public let firstHeading: String?
    }

    public static func render(_ source: String, mdx: Bool = false, options: Options = Options()) -> Result {
        var renderer = Renderer(options: options)
        let prepared = renderer.prepare(source, mdx: mdx)
        // GFM keeps quotes and dashes as typed; so does the export.
        let document = Document(parsing: prepared, options: .disableSmartOpts)
        renderer.lines = prepared.components(separatedBy: "\n")
        var body = renderer.blocks(document.children)
        if renderer.tableOfContentsOpen { body += "</nav>\n" }
        body += renderer.footnoteSection()
        return Result(body: body, firstHeading: renderer.firstHeading)
    }

    /// Escapes text for HTML content and attribute values.
    public static func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.utf8.count)
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            default: result.append(character)
            }
        }
        return result
    }

    /// A GitHub-style heading anchor: lowercase, punctuation dropped, spaces as hyphens.
    public static func slug(_ text: String) -> String {
        let kept = text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " || $0 == "-" || $0 == "_" }
        return String(String.UnicodeScalarView(kept)).replacingOccurrences(of: " ", with: "-")
    }
}

private struct Renderer {
    enum Item {
        case math(String, display: Bool)
        case footnoteReference(String)
        case footnoteDefinition(String)
        case mdx(String)
    }

    let options: MarkdownHTML.Options
    var items: [Item] = []
    var firstHeading: String?
    /// Inside a `<!-- toc -->` … `<!-- /toc -->` card.
    var tableOfContentsOpen = false
    /// The prepared source's lines, for telling loose lists from tight ones.
    var lines: [String] = []
    private var headingIDs: [String: Int] = [:]
    /// Footnote labels in order of first reference.
    private var footnoteOrder: [String] = []
    private var footnoteReferenceCount: [String: Int] = [:]
    private var definitions: [(label: String, html: String)] = []
    private var definedLabels: Set<String> = []

    static let open: Character = "\u{E000}", close: Character = "\u{E001}"
    /// Marks a footnote definition's start in rendered inline HTML, so a paragraph can be split at it.
    static let definitionMark = "\u{E002}"
    static let token = try! NSRegularExpression(pattern: "\u{E000}([0-9]+)\u{E001}")

    init(options: MarkdownHTML.Options) { self.options = options }

    /// Raw HTML uses the same image and link rules as Markdown syntax, including embedded local images.
    private func rawHTML(_ source: String) -> String {
        let pattern = #"(?<=\s)(src|href)\s*=\s*(["'])(.*?)\2"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return source }
        let result = NSMutableString(string: source)
        for match in regex.matches(in: source, range: NSRange(location: 0, length: (source as NSString).length)).reversed() {
            let name = (source as NSString).substring(with: match.range(at: 1)).lowercased()
            let value = (source as NSString).substring(with: match.range(at: 3)).replacingOccurrences(of: "&amp;", with: "&")
            let resolved = name == "src" ? options.image(value) : options.link(value)
            result.replaceCharacters(in: match.range(at: 3), with: MarkdownHTML.escape(resolved))
        }
        return result as String
    }

    // MARK: Preparing the source

    /// The source without frontmatter, each extension replaced by a token naming its item.
    mutating func prepare(_ source: String, mdx: Bool) -> String {
        let ns = source as NSString
        let (frontmatter, found, _) = Extensions.all(in: ns, mdx: mdx)
        var edits: [(NSRange, String)] = []
        if let frontmatter { edits.append((frontmatter.range, "")) }
        for span in found {
            switch span.kind {
            case .mathBlock:
                edits.append((span.range, "\n\n" + token(for: .math(ns.substring(with: span.content), display: true)) + "\n\n"))
            case .inlineMath:
                edits.append((span.range, token(for: .math(ns.substring(with: span.content), display: false))))
            case .footnoteReference(let label):
                edits.append((span.range, token(for: .footnoteReference(label))))
            case .footnoteDefinition(let label, _):
                let prefix = NSRange(location: span.range.location, length: span.content.location - span.range.location)
                edits.append((prefix, token(for: .footnoteDefinition(label))))
                definedLabels.insert(label)
            case .mdxBlock:
                edits.append((span.range, "\n\n" + token(for: .mdx(ns.substring(with: span.range))) + "\n\n"))
            default:
                break
            }
        }
        let result = NSMutableString(string: source)
        for (range, replacement) in edits.sorted(by: { $0.0.location > $1.0.location }) {
            result.replaceCharacters(in: range, with: replacement)
        }
        return result as String
    }

    private mutating func token(for item: Item) -> String {
        items.append(item)
        return "\(Self.open)\(items.count - 1)\(Self.close)"
    }

    /// The item when `text` is exactly one token.
    private func soleItem(_ text: String) -> Item? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = Self.token.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)),
              match.range.length == (trimmed as NSString).length, let index = Int((trimmed as NSString).substring(with: match.range(at: 1))) else { return nil }
        return items[index]
    }

    // MARK: Blocks

    mutating func blocks(_ nodes: some Sequence<Markup>, tight: Bool = false) -> String {
        nodes.map { block($0, tight: tight) }.joined()
    }

    mutating func block(_ node: Markup, tight: Bool = false) -> String {
        switch node {
        case let paragraph as Paragraph:
            return self.paragraph(paragraph, tight: tight)
        case let heading as Heading:
            let text = heading.children.map(headingText).joined().trimmingCharacters(in: .whitespacesAndNewlines)
            if heading.level == 1, firstHeading == nil { firstHeading = text }
            var id = MarkdownHTML.slug(text)
            if let count = headingIDs[id] { headingIDs[id] = count + 1; id += "-\(count)" } else { headingIDs[id] = 1 }
            return "<h\(heading.level) id=\"\(MarkdownHTML.escape(id))\">\(inlines(heading.children))</h\(heading.level)>\n"
        case let quote as BlockQuote:
            return blockQuote(quote)
        case let code as CodeBlock:
            return codeBlock(code)
        case is ThematicBreak:
            return "<hr>\n"
        case let html as HTMLBlock:
            // Markify's table of contents comments wrap the list in a Contents card.
            if TableOfContentsMarker.depth(ofOpening: html.rawHTML) != nil, !tableOfContentsOpen {
                tableOfContentsOpen = true
                return "<nav class=\"toc\" aria-label=\"Contents\">\n<p class=\"toc-title\">Contents</p>\n"
            }
            if TableOfContentsMarker.isClosing(html.rawHTML) {
                guard tableOfContentsOpen else { return "" }
                tableOfContentsOpen = false
                return "</nav>\n"
            }
            return rawHTML(html.rawHTML)
        case let list as OrderedList:
            let start = list.startIndex != 1 ? " start=\"\(list.startIndex)\"" : ""
            return "<ol\(start)>\n\(listItems(list))</ol>\n"
        case let list as UnorderedList:
            let tasks = list.listItems.contains { $0.checkbox != nil } ? " class=\"tasks\"" : ""
            return "<ul\(tasks)>\n\(listItems(list))</ul>\n"
        case let table as Markdown.Table:
            return self.table(table)
        default:
            return blocks(node.children, tight: tight)
        }
    }

    private func headingText(_ node: Markup) -> String {
        if node is InlineHTML { return "" }
        if let text = node as? Text { return text.string }
        if let code = node as? InlineCode { return code.code }
        if let image = node as? Image { return image.plainText }
        if node is SoftBreak || node is LineBreak { return " " }
        return node.children.map(headingText).joined()
    }

    private mutating func paragraph(_ paragraph: Paragraph, tight: Bool) -> String {
        if let item = soleItem(paragraph.plainText), paragraph.children.allSatisfy({ $0 is Text || $0 is SoftBreak }) {
            switch item {
            case .math(let latex, true):
                return "<div class=\"math display\">\(math(latex, display: true))</div>\n"
            case .mdx(let code):
                return "<pre class=\"mdx\"><code>\(MarkdownHTML.escape(code))</code></pre>\n"
            default:
                break
            }
        }
        // A paragraph may hold footnote definitions, one per line; each becomes a footnote and leaves the page.
        let parts = inlines(paragraph.children).components(separatedBy: Self.definitionMark)
        var html = ""
        let lead = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        if !lead.isEmpty {
            let image = paragraph.childCount == 1 && paragraph.child(at: 0) is Image
            html = tight ? lead + "\n" : "<p\(image ? " class=\"image\"" : "")>\(lead)</p>\n"
        }
        for part in parts.dropFirst() {
            let end = part.firstIndex(of: "\n") ?? part.endIndex
            let label = String(part[..<end])
            let rest = part[end...].trimmingCharacters(in: .whitespacesAndNewlines)
            definitions.append((label, rest))
        }
        return html
    }

    private mutating func blockQuote(_ quote: BlockQuote) -> String {
        let alert = try! NSRegularExpression(pattern: #"^\[!(NOTE|TIP|WARNING|IMPORTANT)\][ \t]*"#)
        guard let first = quote.child(at: 0) as? Paragraph, let text = first.child(at: 0) as? Text,
              let match = alert.firstMatch(in: text.string, range: NSRange(location: 0, length: (text.string as NSString).length)) else {
            return "<blockquote>\n\(blocks(quote.children))</blockquote>\n"
        }
        let type = (text.string as NSString).substring(with: match.range(at: 1))
        let remainder = (text.string as NSString).substring(from: match.range.length)
        var rest = Array(first.children.dropFirst())
        if remainder.isEmpty, rest.first is SoftBreak || rest.first is LineBreak { rest.removeFirst() }
        var lead = MarkdownHTML.escape(remainder).replacingTokens(with: { renderToken($0) })
        lead += inlines(rest)
        lead = lead.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = type.prefix(1) + type.dropFirst().lowercased()
        var html = "<div class=\"callout callout-\(type.lowercased())\" role=\"note\" aria-label=\"\(title)\">\n<p class=\"callout-title\">\(title)</p>\n"
        if !lead.isEmpty { html += "<p>\(lead)</p>\n" }
        html += blocks(quote.children.dropFirst())
        return html + "</div>\n"
    }

    private mutating func codeBlock(_ code: CodeBlock) -> String {
        let language = code.language.flatMap { $0.isEmpty ? nil : $0 }
        var body = code.code
        if body.hasSuffix("\n") { body.removeLast() }
        if let language, let diagram = options.diagram(language, body) {
            return "<figure class=\"diagram\">\(diagram)</figure>\n"
        }
        let attribute = language.map { " class=\"language-\(MarkdownHTML.escape($0))\"" } ?? ""
        let label = (options.codeLabels ? language : nil).map { "<span class=\"code-label\" aria-hidden=\"true\">\(MarkdownHTML.escape($0))</span>" } ?? ""
        let highlighted = options.highlight(body, language) ?? MarkdownHTML.escape(body)
        return "<pre>\(label)<code\(attribute)>\(highlighted)</code></pre>\n"
    }

    private mutating func listItems(_ list: Markup) -> String {
        let tight = !isLoose(list)
        var html = ""
        for case let item as Markdown.ListItem in list.children {
            let content = blocks(item.children, tight: tight)
            if let checkbox = item.checkbox {
                let checked = checkbox == .checked ? " checked" : ""
                html += "<li class=\"task\"><input type=\"checkbox\" disabled\(checked) aria-label=\"\(checked.isEmpty ? "Not done" : "Done")\"> \(content)</li>\n"
            } else {
                html += "<li>\(content)</li>\n"
            }
        }
        return html
    }

    /// CommonMark's loose list: a blank line between items or between the blocks of an item.
    private func isLoose(_ list: Markup) -> Bool {
        /// A blank line right before `b`, which follows `a`.
        func gap(_ a: Markup, _ b: Markup) -> Bool {
            guard let first = a.range?.lowerBound.line, let start = b.range?.lowerBound.line, start - 2 >= first, start - 2 < lines.count else { return false }
            return lines[start - 2].trimmingCharacters(in: .whitespaces).isEmpty
        }
        let items = Array(list.children)
        for (a, b) in zip(items, items.dropFirst()) where gap(a, b) { return true }
        for item in items {
            let children = Array(item.children)
            for (a, b) in zip(children, children.dropFirst()) where gap(a, b) { return true }
        }
        return false
    }

    private mutating func table(_ table: Markdown.Table) -> String {
        let alignments = table.columnAlignments
        func style(_ column: Int) -> String {
            guard column < alignments.count, let alignment = alignments[column] else { return "" }
            switch alignment {
            case .left: return " style=\"text-align:left\""
            case .center: return " style=\"text-align:center\""
            case .right: return " style=\"text-align:right\""
            }
        }
        var html = "<div class=\"table\"><table>\n<thead>\n<tr>"
        for (column, cell) in table.head.cells.enumerated() {
            html += "<th scope=\"col\"\(style(column))>\(inlines(cell.children))</th>"
        }
        html += "</tr>\n</thead>\n"
        if !table.body.isEmpty {
            html += "<tbody>\n"
            for row in table.body.rows {
                html += "<tr>"
                for (column, cell) in row.cells.enumerated() {
                    html += "<td\(style(column))>\(inlines(cell.children))</td>"
                }
                html += "</tr>\n"
            }
            html += "</tbody>\n"
        }
        return html + "</table></div>\n"
    }

    // MARK: Inlines

    mutating func inlines(_ nodes: some Sequence<Markup>) -> String {
        nodes.map { inline($0) }.joined()
    }

    mutating func inline(_ node: Markup) -> String {
        switch node {
        case let text as Text:
            return MarkdownHTML.escape(text.string).replacingTokens(with: { renderToken($0) })
        case let code as InlineCode:
            return "<code>\(MarkdownHTML.escape(code.code))</code>"
        case is Emphasis:
            return "<em>\(inlines(node.children))</em>"
        case is Strong:
            return "<strong>\(inlines(node.children))</strong>"
        case is Strikethrough:
            return "<del>\(inlines(node.children))</del>"
        case let link as Link:
            let href = link.destination.map { " href=\"\(MarkdownHTML.escape(options.link($0)))\"" } ?? ""
            let title = link.title.flatMap { $0.isEmpty ? nil : " title=\"\(MarkdownHTML.escape($0))\"" } ?? ""
            return "<a\(href)\(title)>\(inlines(node.children))</a>"
        case let image as Image:
            let source = options.image(image.source ?? "")
            let title = image.title.flatMap { $0.isEmpty ? nil : " title=\"\(MarkdownHTML.escape($0))\"" } ?? ""
            return "<img src=\"\(MarkdownHTML.escape(source))\" alt=\"\(MarkdownHTML.escape(image.plainText))\"\(title)>"
        case let html as InlineHTML:
            return rawHTML(html.rawHTML)
        case is LineBreak:
            return "<br>\n"
        case is SoftBreak:
            return "\n"
        case let symbol as SymbolLink:
            return "<code>\(MarkdownHTML.escape(symbol.destination ?? ""))</code>"
        default:
            return inlines(node.children)
        }
    }

    private mutating func renderToken(_ index: Int) -> String {
        switch items[index] {
        case .math(let latex, let display):
            return "<span class=\"math\(display ? " display" : "")\">\(math(latex, display: display))</span>"
        case .footnoteReference(let label):
            guard definedLabels.contains(label) else { return MarkdownHTML.escape("[^\(label)]") }
            if !footnoteOrder.contains(label) { footnoteOrder.append(label) }
            let number = footnoteOrder.firstIndex(of: label)! + 1
            let count = footnoteReferenceCount[label, default: 0] + 1
            footnoteReferenceCount[label] = count
            let slug = MarkdownHTML.escape(MarkdownHTML.slug(label))
            let id = count == 1 ? "fnref-\(slug)" : "fnref-\(slug)-\(count)"
            return "<sup class=\"footnote-ref\"><a href=\"#fn-\(slug)\" id=\"\(id)\" aria-describedby=\"footnotes-label\">\(number)</a></sup>"
        case .footnoteDefinition(let label):
            return Self.definitionMark + label + "\n"
        case .mdx(let code):
            return "<code class=\"mdx\">\(MarkdownHTML.escape(code))</code>"
        }
    }

    private func math(_ latex: String, display: Bool) -> String {
        let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        return options.math(trimmed, display) ?? "<code>\(MarkdownHTML.escape(trimmed))</code>"
    }

    // MARK: Footnotes

    func footnoteSection() -> String {
        guard !definitions.isEmpty else { return "" }
        let ordered = definitions.sorted { a, b in
            (footnoteOrder.firstIndex(of: a.label) ?? .max) < (footnoteOrder.firstIndex(of: b.label) ?? .max)
        }
        var html = "<section class=\"footnotes\" aria-labelledby=\"footnotes-label\">\n<h2 id=\"footnotes-label\" class=\"visually-hidden\">Footnotes</h2>\n<ol>\n"
        for definition in ordered {
            let slug = MarkdownHTML.escape(MarkdownHTML.slug(definition.label))
            let back = footnoteOrder.contains(definition.label)
                ? " <a href=\"#fnref-\(slug)\" class=\"footnote-back\" aria-label=\"Back to reference\">↩</a>" : ""
            html += "<li id=\"fn-\(slug)\"><p>\(definition.html)\(back)</p></li>\n"
        }
        return html + "</ol>\n</section>\n"
    }
}

private extension String {
    /// Replaces each extension token with `render(index)`.
    func replacingTokens(with render: (Int) -> String) -> String {
        guard contains(Renderer.open) else { return self }
        let ns = self as NSString
        var result = ""
        var last = 0
        for match in Renderer.token.matches(in: self, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            result += render(Int(ns.substring(with: match.range(at: 1)))!)
            last = NSMaxRange(match.range)
        }
        return result + ns.substring(from: last)
    }
}
