import Foundation
import Markdown

/// One parse of a Markdown source string, as typed spans in UTF-16 source offsets.
///
/// CommonMark and GFM constructs come from swift-markdown (cmark-gfm). Markify's extensions that cmark does
/// not know — frontmatter, `$$` and `$…$` math, footnotes and callouts — are found first and masked with
/// same-length whitespace, so cmark never misreads them and every offset still points into the original source.
public struct MarkdownModel: Sendable {
    public let source: String
    public let mdx: Bool
    /// Every span, ordered by location. Containers come before what they contain.
    public let spans: [Span]
    public let tables: [Table]
    public let lists: [List]

    /// `mdx` also recognizes MDX's `import`/`export` lines and JSX blocks, which are kept as written.
    public init(_ source: String, mdx: Bool = false) {
        self.source = source
        self.mdx = mdx
        let ns = source as NSString
        let (frontmatter, found, firstParse) = Extensions.all(in: ns, mdx: mdx)
        var masked = Masker(ns)
        if let frontmatter { masked.blank(frontmatter.range) }
        var document = firstParse
        if !found.isEmpty {
            for span in found { masked.mask(span) }
            document = Document(parsing: masked.text)
        }
        var walker = Walker(source: ns, masked: masked.text as NSString, map: MarkdownSourceMap(masked.text))
        walker.visit(document, depth: 0, quoteDepth: 0)
        var spans = walker.spans + found
        if let frontmatter { spans.append(frontmatter) }
        self.spans = spans.sorted { $0.range.location != $1.range.location ? $0.range.location < $1.range.location : $0.range.length > $1.range.length }
        tables = walker.tables
        lists = walker.lists.sorted { $0.range.location < $1.range.location }
    }

    public func spans(where include: (Kind) -> Bool) -> [Span] { spans.filter { include($0.kind) } }

    /// A complete text-storage paragraph containing only inline text styles. No second parse is needed.
    public func styledParagraph(_ range: NSRange) -> MarkdownModel? {
        let source = source as NSString
        guard range.location >= 0, NSMaxRange(range) <= source.length else { return nil }
        guard !tables.contains(where: { NSIntersectionRange($0.range, range).length > 0 }) else { return nil }
        var selected: [Span] = []
        for span in spans where NSIntersectionRange(span.range, range).length > 0 {
            guard span.range.location >= range.location, NSMaxRange(span.range) <= NSMaxRange(range) else { return nil }
            switch span.kind {
            case .strong, .emphasis, .strikethrough, .inlineCode, .escape, .link: break
            // ATX headings sit on one line and style only their own line; setext headings span into the next.
            case .heading(_, setext: false): break
            default: return nil
            }
            func shifted(_ value: NSRange) -> NSRange { NSRange(location: value.location - range.location, length: value.length) }
            selected.append(Span(kind: span.kind, range: shifted(span.range), content: shifted(span.content), markers: span.markers.map(shifted)))
        }
        let text = source.substring(with: range)
        // Definitions aren't spans, but can change links elsewhere in the document.
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") else { return nil }
        return MarkdownModel(source: text, mdx: mdx, spans: selected)
    }

    private init(source: String, mdx: Bool, spans: [Span]) {
        self.source = source; self.mdx = mdx; self.spans = spans
        tables = []; lists = []
    }

    // MARK: Types

    public struct Span: Hashable, Sendable {
        public let kind: Kind
        /// The whole construct, delimiters included.
        public let range: NSRange
        /// The text inside the delimiters: heading text, emphasis text, link text, image alt, code body, math body.
        public let content: NSRange
        /// Syntax tokens: dimmed in the Markdown lens, hidden in the Rendered lens.
        public let markers: [NSRange]

        public init(kind: Kind, range: NSRange, content: NSRange, markers: [NSRange]) {
            self.kind = kind
            self.range = range
            self.content = content
            self.markers = markers.filter { $0.length > 0 }
        }
    }

    public enum Kind: Hashable, Sendable {
        case heading(level: Int, setext: Bool)
        case strong, emphasis, strikethrough, inlineCode
        /// A backslash escape; its marker is the backslash.
        case escape
        case link(destination: String)
        /// `block` is true for an image alone in its paragraph on one line.
        case image(source: String, block: Bool)
        case codeBlock(language: String?, fenced: Bool)
        case blockQuote(depth: Int)
        /// A GitHub alert blockquote; `token` is the `[!NOTE]` text.
        case callout(type: String, token: NSRange)
        case listItem(ListItem)
        case thematicBreak
        case htmlBlock, inlineHTML
        case frontmatter
        case mathBlock, inlineMath
        case footnoteReference(label: String)
        case footnoteDefinition(label: String, labelRange: NSRange)
        /// An MDX `import`/`export` block or JSX block.
        case mdxBlock
    }

    public struct ListItem: Hashable, Sendable {
        public let ordered: Bool
        /// Nesting depth, 0 for a top-level list.
        public let depth: Int
        /// The bullet or the number with its delimiter.
        public let marker: NSRange
        /// The digits of an ordered item.
        public let digits: NSRange?
        /// The `[ ]` or `[x]` of a task item.
        public let checkbox: NSRange?
        public let checked: Bool
    }

    public struct Table: Hashable, Sendable {
        public enum Alignment: Hashable, Sendable { case left, center, right }
        public struct Row: Hashable, Sendable {
            public let start: Int
            /// End of the line's contents, before the newline.
            public let end: Int
            public let cells: [NSRange]
            public let separator: Bool
        }
        public let range: NSRange
        public let rows: [Row]
        public let alignments: [Alignment?]
    }

    public struct List: Hashable, Sendable {
        public let ordered: Bool
        public let start: Int
        public let depth: Int
        public let range: NSRange
        public let items: [ListItem]
    }
}

// MARK: - Masking

/// A copy of the source in which ranges are replaced by whitespace of the same UTF-16 length.
private struct Masker {
    private let storage: NSMutableString
    var text: String { storage as String }

    init(_ source: NSString) { storage = source.mutableCopy() as! NSMutableString }

    /// Spaces for block constructs: masked lines become blank lines, newlines stay.
    mutating func blank(_ range: NSRange) { fill(range, with: " ") }

    /// No-break spaces for inline constructs: they neither indent a line nor end a paragraph.
    mutating func inline(_ range: NSRange) { fill(range, with: "\u{00A0}") }

    mutating func mask(_ span: MarkdownModel.Span) {
        switch span.kind {
        case .mathBlock, .mdxBlock: blank(span.range)
        case .inlineMath: inline(span.range)
        // Only the `[^label]:` prefix, so the definition text is still parsed as inline Markdown.
        case .footnoteDefinition: inline(NSRange(location: span.range.location, length: span.content.location - span.range.location))
        default: break
        }
    }

    private func fill(_ range: NSRange, with filler: String) {
        for index in range.location..<NSMaxRange(range) where storage.character(at: index) != 10 && storage.character(at: index) != 13 {
            storage.replaceCharacters(in: NSRange(location: index, length: 1), with: filler)
        }
    }
}

// MARK: - Extensions

enum Extensions {
    /// Frontmatter and every extension span, plus the parse of the source with only the frontmatter masked.
    static func all(in source: NSString, mdx: Bool) -> (frontmatter: MarkdownModel.Span?, found: [MarkdownModel.Span], document: Document) {
        let frontmatter = frontmatter(in: source)
        var masked = Masker(source)
        if let frontmatter { masked.blank(frontmatter.range) }
        let document = Document(parsing: masked.text)
        let map = MarkdownSourceMap(masked.text)
        var literals = Literals.collect(document, map: map)
        if let frontmatter { literals.append(frontmatter.range) }
        // JSX parses as HTML, so MDX blocks are only kept out of code.
        let mdxBlocks = mdx ? Extensions.mdx(in: source, outside: Literals.collect(document, map: map, html: false)) : []
        literals += mdxBlocks.map(\.range)
        return (frontmatter, find(in: source, outside: literals) + mdxBlocks, document)
    }

    static func frontmatter(in source: NSString) -> MarkdownModel.Span? {
        guard source.hasPrefix("---\n"), let regex = try? NSRegularExpression(pattern: #"(?m)^---[ \t]*$"#),
              let close = regex.firstMatch(in: source as String, range: NSRange(location: 4, length: source.length - 4))?.range else { return nil }
        var end = NSMaxRange(close)
        if end < source.length, source.character(at: end) == 10 { end += 1 }
        return .init(kind: .frontmatter, range: NSRange(location: 0, length: end),
                     content: NSRange(location: 4, length: max(0, close.location - 4)),
                     markers: [NSRange(location: 0, length: 3), close])
    }

    /// Math, footnote definitions and footnote references outside code, HTML and frontmatter.
    static func find(in source: NSString, outside literals: [NSRange]) -> [MarkdownModel.Span] {
        let text = source as String
        let whole = NSRange(location: 0, length: source.length)
        var taken = IndexSet()
        for range in literals { taken.insert(integersIn: range.location..<NSMaxRange(range)) }
        func free(_ range: NSRange) -> Bool {
            range.length == 0 ? !taken.contains(range.location) : !taken.intersects(integersIn: range.location..<NSMaxRange(range))
        }
        var spans: [MarkdownModel.Span] = []

        let block = try! NSRegularExpression(pattern: #"(?ms)^\$\$[ \t]*\n?(.*?)\n?\$\$[ \t]*$"#)
        for match in block.matches(in: text, range: whole) where free(match.range) {
            let body = match.range(at: 1)
            spans.append(.init(kind: .mathBlock, range: match.range, content: body,
                               markers: [NSRange(location: match.range.location, length: 2), NSRange(location: NSMaxRange(match.range) - 2, length: 2)]))
            taken.insert(integersIn: match.range.location..<NSMaxRange(match.range))
        }
        let definition = try! NSRegularExpression(pattern: #"(?m)^(\[\^)([^\]\n]+)(\]:)[ \t]*(.*)$"#)
        var definitionPrefixes: [NSRange] = []
        for match in definition.matches(in: text, range: whole) where free(match.range) {
            let label = match.range(at: 2)
            spans.append(.init(kind: .footnoteDefinition(label: source.substring(with: label), labelRange: label),
                               range: match.range, content: match.range(at: 4), markers: [match.range(at: 1), match.range(at: 3)]))
            definitionPrefixes.append(NSRange(location: match.range.location, length: NSMaxRange(match.range(at: 3)) - match.range.location))
        }
        for range in definitionPrefixes { taken.insert(integersIn: range.location..<NSMaxRange(range)) }
        // Pandoc's rule: no space inside either dollar, and no digit right after the closing one, so "$5 and $10" stays text.
        let inline = try! NSRegularExpression(pattern: #"(?<![\\$])\$(?![\s$])((?:\\.|[^$\n\\])+?)(?<![\s\\])\$(?![$\d])"#)
        for match in inline.matches(in: text, range: whole) where free(match.range) {
            spans.append(.init(kind: .inlineMath, range: match.range, content: match.range(at: 1),
                               markers: [NSRange(location: match.range.location, length: 1), NSRange(location: NSMaxRange(match.range) - 1, length: 1)]))
            taken.insert(integersIn: match.range.location..<NSMaxRange(match.range))
        }
        let reference = try! NSRegularExpression(pattern: #"(\[\^)([^\]\n]+)(\])(?!:)"#)
        for match in reference.matches(in: text, range: whole) where free(match.range) {
            spans.append(.init(kind: .footnoteReference(label: source.substring(with: match.range(at: 2))), range: match.range,
                               content: match.range(at: 2), markers: [match.range(at: 1), match.range(at: 3)]))
        }
        return spans
    }
}

extension Extensions {
    /// MDX blocks at the start of a line: ESM (`import`, `export`) and JSX (`<Component`, `</Component`, `<>`), each up to the next blank line.
    static func mdx(in source: NSString, outside code: [NSRange]) -> [MarkdownModel.Span] {
        let start = try! NSRegularExpression(pattern: #"^(?:import\s|export\s|<[A-Z>]|</[A-Z>])"#)
        var spans: [MarkdownModel.Span] = []
        var location = 0
        while location < source.length {
            let line = source.lineRange(for: NSRange(location: location, length: 0))
            defer { location = max(NSMaxRange(line), location + 1) }
            guard start.firstMatch(in: source as String, options: .anchored, range: line) != nil,
                  !code.contains(where: { NSLocationInRange(line.location, $0) }) else { continue }
            var end = line
            while NSMaxRange(end) < source.length {
                let next = source.lineRange(for: NSRange(location: NSMaxRange(end), length: 0))
                guard !source.substring(with: next).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { break }
                end = next
            }
            var stop = NSMaxRange(end)
            while stop > line.location, [10, 13].contains(source.character(at: stop - 1)) { stop -= 1 }
            let range = NSRange(location: line.location, length: stop - line.location)
            spans.append(.init(kind: .mdxBlock, range: range, content: range, markers: []))
            location = NSMaxRange(end)
        }
        return spans
    }
}

/// Source ranges whose text is literal: code and HTML never contain extensions.
enum Literals {
    static func collect(_ document: Document, map: MarkdownSourceMap, html: Bool = true) -> [NSRange] {
        var ranges: [NSRange] = []
        func visit(_ node: Markup) {
            switch node {
            case is CodeBlock, is InlineCode:
                if let range = node.range.flatMap(map.range) { ranges.append(range) }
            case is HTMLBlock, is InlineHTML:
                if html, let range = node.range.flatMap(map.range) { ranges.append(range) }
            default:
                for child in node.children { visit(child) }
            }
        }
        visit(document)
        return ranges
    }
}

// MARK: - Walker

private struct Walker {
    let source: NSString
    /// The text cmark parsed; it differs from `source` only where extensions were masked.
    let masked: NSString
    let map: MarkdownSourceMap
    var spans: [MarkdownModel.Span] = []
    var tables: [MarkdownModel.Table] = []
    var lists: [MarkdownModel.List] = []

    init(source: NSString, masked: NSString, map: MarkdownSourceMap) {
        self.source = source
        self.masked = masked
        self.map = map
    }

    func range(_ node: Markup) -> NSRange? { node.range.flatMap(map.range) }

    /// The union of the children's ranges, or nil when there are none.
    func childrenRange(_ node: Markup) -> NSRange? {
        node.children.compactMap(range).reduce(nil) { union, next in union.map { NSUnionRange($0, next) } ?? next }
    }

    func lineRange(at location: Int) -> NSRange { source.lineRange(for: NSRange(location: min(location, source.length), length: 0)) }

    /// A line's range without its line ending.
    func contentsRange(at location: Int) -> NSRange {
        var start = 0, contentsEnd = 0
        source.getLineStart(&start, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: min(location, source.length), length: 0))
        return NSRange(location: start, length: contentsEnd - start)
    }

    /// Delimiters around `content` inside `whole`.
    func around(_ whole: NSRange, _ content: NSRange) -> [NSRange] {
        [NSRange(location: whole.location, length: content.location - whole.location),
         NSRange(location: NSMaxRange(content), length: NSMaxRange(whole) - NSMaxRange(content))]
    }

    mutating func visitChildren(_ node: Markup, depth: Int, quoteDepth: Int) {
        for child in node.children { visit(child, depth: depth, quoteDepth: quoteDepth) }
    }

    mutating func visit(_ node: Markup, depth: Int, quoteDepth: Int) {
        guard let whole = range(node) else { return visitChildren(node, depth: depth, quoteDepth: quoteDepth) }
        switch node {
        case let heading as Heading:
            // From the heading's own start, so a container's `>` or list marker is not part of it.
            let line = contentsRange(at: whole.location)
            let firstLine = NSRange(location: whole.location, length: NSMaxRange(line) - whole.location)
            let setext = NSMaxRange(whole) > NSMaxRange(firstLine) + 1
            if setext {
                let content = childrenRange(heading) ?? firstLine
                let underline = contentsRange(at: NSMaxRange(whole) - 1)
                let range = NSRange(location: whole.location, length: NSMaxRange(underline) - whole.location)
                spans.append(.init(kind: .heading(level: heading.level, setext: true), range: range, content: content, markers: [underline]))
            } else {
                let content = childrenRange(heading) ?? NSRange(location: NSMaxRange(firstLine), length: 0)
                let opening = NSRange(location: firstLine.location, length: content.location - firstLine.location)
                let closing = NSRange(location: NSMaxRange(content), length: NSMaxRange(firstLine) - NSMaxRange(content))
                spans.append(.init(kind: .heading(level: heading.level, setext: false), range: firstLine, content: content, markers: [opening, closing]))
            }
            visitChildren(node, depth: depth, quoteDepth: quoteDepth)

        case is Strong, is Emphasis, is Strikethrough:
            let kind: MarkdownModel.Kind = node is Strong ? .strong : node is Emphasis ? .emphasis : .strikethrough
            let content = childrenRange(node) ?? NSRange(location: whole.location + whole.length / 2, length: 0)
            spans.append(.init(kind: kind, range: whole, content: content, markers: around(whole, content)))
            visitChildren(node, depth: depth, quoteDepth: quoteDepth)

        case is InlineCode:
            var ticks = 0
            while ticks < whole.length / 2, source.character(at: whole.location + ticks) == 96 { ticks += 1 }
            let content = NSRange(location: whole.location + ticks, length: whole.length - 2 * ticks)
            spans.append(.init(kind: .inlineCode, range: whole, content: content, markers: around(whole, content)))

        case let link as Link:
            let content = childrenRange(link) ?? NSRange(location: whole.location + 1, length: 0)
            spans.append(.init(kind: .link(destination: link.destination ?? ""), range: whole, content: content, markers: around(whole, content)))
            visitChildren(node, depth: depth, quoteDepth: quoteDepth)

        case let image as Image:
            let content = childrenRange(image) ?? NSRange(location: whole.location + 2, length: 0)
            let paragraph = image.parent as? Paragraph
            let block = paragraph?.childCount == 1 && contentsRange(at: whole.location) == contentsRange(at: NSMaxRange(whole))
            spans.append(.init(kind: .image(source: image.source ?? "", block: block), range: whole, content: content, markers: around(whole, content)))

        case let text as Text:
            addEscapes(in: whole, text: text.string)

        case let code as CodeBlock:
            addCodeBlock(code, whole)

        case is BlockQuote:
            addBlockQuote(node, whole, quoteDepth: quoteDepth)
            visitChildren(node, depth: depth, quoteDepth: quoteDepth + 1)

        case is UnorderedList, is OrderedList:
            let ordered = node is OrderedList
            var items: [MarkdownModel.ListItem] = []
            for case let item as Markdown.ListItem in node.children {
                guard let itemRange = range(item), let info = listItem(item, itemRange, ordered: ordered, depth: depth) else { continue }
                items.append(info)
                spans.append(.init(kind: .listItem(info), range: itemRange, content: NSRange(location: NSMaxRange(info.checkbox ?? info.marker), length: 0),
                                   markers: [info.marker]))
                visitChildren(item, depth: depth + 1, quoteDepth: quoteDepth)
            }
            lists.append(.init(ordered: ordered, start: Int((node as? OrderedList)?.startIndex ?? 1), depth: depth, range: whole, items: items))

        case let table as Markdown.Table:
            addTable(table, whole)
            visitChildren(node, depth: depth, quoteDepth: quoteDepth)

        case is ThematicBreak:
            let line = contentsRange(at: whole.location)
            spans.append(.init(kind: .thematicBreak, range: line, content: NSRange(location: NSMaxRange(line), length: 0), markers: [line]))

        case is HTMLBlock:
            spans.append(.init(kind: .htmlBlock, range: whole, content: whole, markers: []))

        case is InlineHTML:
            spans.append(.init(kind: .inlineHTML, range: whole, content: whole, markers: []))

        default:
            visitChildren(node, depth: depth, quoteDepth: quoteDepth)
        }
    }

    /// Backslash escapes: a text node's source is longer than its string by one backslash per escape.
    mutating func addEscapes(in whole: NSRange, text: String) {
        guard whole.length > (text as NSString).length else { return }
        var index = whole.location
        while index < NSMaxRange(whole) - 1 {
            let next = source.character(at: index + 1)
            if masked.character(at: index) == 92, next < 128, let scalar = UnicodeScalar(next), CharacterSet.punctuationCharacters.union(.symbols).contains(scalar) {
                spans.append(.init(kind: .escape, range: NSRange(location: index, length: 2), content: NSRange(location: index + 1, length: 1),
                                   markers: [NSRange(location: index, length: 1)]))
                index += 2
            } else {
                index += 1
            }
        }
    }

    mutating func addCodeBlock(_ code: CodeBlock, _ whole: NSRange) {
        let first = NSRange(location: whole.location, length: NSMaxRange(contentsRange(at: whole.location)) - whole.location)
        let opening = source.substring(with: first).trimmingCharacters(in: .whitespaces)
        let fenced = opening.hasPrefix("```") || opening.hasPrefix("~~~")
        let language = code.language.flatMap { $0.isEmpty ? nil : $0 }
        guard fenced else {
            // Indented code: whole lines, without the blank lines cmark includes after it.
            let body = code.code.hasSuffix("\n") ? String(code.code.dropLast()) : code.code
            let lines = body.components(separatedBy: "\n").count
            var end = lineRange(at: whole.location)
            for _ in 1..<max(lines, 1) { end = lineRange(at: NSMaxRange(end)) }
            let start = lineRange(at: whole.location).location
            let content = NSRange(location: start, length: NSMaxRange(contentsRange(at: end.location)) - start)
            spans.append(.init(kind: .codeBlock(language: language, fenced: false), range: content, content: content, markers: []))
            return
        }
        let fence = opening.hasPrefix("`") ? "`" : "~"
        let fenceLength = opening.prefix { String($0) == fence }.count
        let last = contentsRange(at: max(whole.location, NSMaxRange(whole) - 1))
        let closingText = source.substring(with: last).trimmingCharacters(in: .whitespaces)
        let closed = last.location != first.location && closingText.count >= fenceLength && closingText.allSatisfy { String($0) == fence }
        let bodyStart = min(NSMaxRange(lineRange(at: first.location)), NSMaxRange(whole))
        var bodyEnd = closed ? last.location : NSMaxRange(whole)
        if bodyEnd > bodyStart, source.character(at: bodyEnd - 1) == 10 { bodyEnd -= 1 }
        let content = NSRange(location: bodyStart, length: max(0, bodyEnd - bodyStart))
        let range = NSRange(location: first.location, length: NSMaxRange(closed ? last : whole) - first.location)
        spans.append(.init(kind: .codeBlock(language: language, fenced: true), range: range, content: content, markers: closed ? [first, last] : [first]))
    }

    mutating func addBlockQuote(_ node: Markup, _ whole: NSRange, quoteDepth: Int) {
        let column = whole.location - lineRange(at: whole.location).location
        var markers: [NSRange] = []
        var line = lineRange(at: whole.location)
        while line.location < NSMaxRange(whole) {
            // The `>` sits at the quote's column on each line; lazy continuation lines have none.
            var index = line.location + column
            while index < NSMaxRange(line), index < line.location + column + 3, source.character(at: index) == 32 { index += 1 }
            if index < NSMaxRange(line), source.character(at: index) == 62 {
                let spaced = index + 1 < NSMaxRange(line) && [32, 9].contains(source.character(at: index + 1))
                markers.append(NSRange(location: index, length: spaced ? 2 : 1))
            }
            guard NSMaxRange(line) > line.location, NSMaxRange(line) < source.length else { break }
            line = lineRange(at: NSMaxRange(line))
        }
        let content = NSRange(location: NSMaxRange(markers.first ?? NSRange(location: whole.location, length: 0)),
                              length: NSMaxRange(whole) - NSMaxRange(markers.first ?? NSRange(location: whole.location, length: 0)))
        spans.append(.init(kind: .blockQuote(depth: quoteDepth), range: whole, content: content, markers: markers))
        let alert = try! NSRegularExpression(pattern: #"^\[!(NOTE|TIP|WARNING|IMPORTANT)\]"#)
        if let match = alert.firstMatch(in: source as String, options: .anchored, range: NSRange(location: content.location, length: NSMaxRange(whole) - content.location)) {
            spans.append(.init(kind: .callout(type: source.substring(with: match.range(at: 1)), token: match.range), range: whole,
                               content: NSRange(location: NSMaxRange(match.range), length: NSMaxRange(whole) - NSMaxRange(match.range)), markers: []))
        }
    }

    func listItem(_ item: Markdown.ListItem, _ whole: NSRange, ordered: Bool, depth: Int) -> MarkdownModel.ListItem? {
        let pattern = ordered ? #"[0-9]{1,9}[.)]"# : #"[-*+]"#
        guard let marker = try! NSRegularExpression(pattern: pattern).firstMatch(in: source as String, options: .anchored, range: whole)?.range else { return nil }
        let digits = ordered ? NSRange(location: marker.location, length: marker.length - 1) : nil
        var checkbox: NSRange?
        if item.checkbox != nil,
           let box = try! NSRegularExpression(pattern: #"[ \t]+(\[[ xX]\])"#).firstMatch(in: source as String, options: .anchored,
                                                                                    range: NSRange(location: NSMaxRange(marker), length: NSMaxRange(whole) - NSMaxRange(marker))) {
            checkbox = box.range(at: 1)
        }
        return .init(ordered: ordered, depth: depth, marker: marker, digits: digits, checkbox: checkbox, checked: item.checkbox == .checked)
    }

    mutating func addTable(_ table: Markdown.Table, _ whole: NSRange) {
        let columns = table.maxColumnCount
        var rows: [MarkdownModel.Table.Row] = []
        func row(at location: Int, separator: Bool) -> MarkdownModel.Table.Row {
            let line = contentsRange(at: location)
            return .init(start: line.location, end: NSMaxRange(line), cells: Array(cells(in: line).prefix(columns)), separator: separator)
        }
        let head = contentsRange(at: whole.location)
        rows.append(row(at: head.location, separator: false))
        rows.append(row(at: NSMaxRange(lineRange(at: head.location)), separator: true))
        for body in table.body.children {
            guard let range = range(body) else { continue }
            rows.append(row(at: range.location, separator: false))
        }
        let end = rows.last.map { $0.end } ?? NSMaxRange(whole)
        let alignments: [MarkdownModel.Table.Alignment?] = table.columnAlignments.map { alignment in
            switch alignment {
            case .left: .left
            case .center: .center
            case .right: .right
            case nil: nil
            }
        }
        tables.append(.init(range: NSRange(location: head.location, length: end - head.location), rows: rows, alignments: alignments))
    }

    /// Cell contents between unescaped pipes, trimmed; an empty cell is an empty range at its closing pipe.
    func cells(in line: NSRange) -> [NSRange] {
        var pipes: [Int] = []
        for index in line.location..<NSMaxRange(line) where source.character(at: index) == 124 {
            if index == line.location || source.character(at: index - 1) != 92 { pipes.append(index) }
        }
        let text = source.substring(with: line).trimmingCharacters(in: .whitespaces)
        var bounds = pipes
        if !text.hasPrefix("|") { bounds.insert(line.location - 1, at: 0) }
        if !text.hasSuffix("|") || bounds.count < 2 { bounds.append(NSMaxRange(line)) }
        func blank(_ index: Int) -> Bool { UnicodeScalar(source.character(at: index)).map(CharacterSet.whitespaces.contains) ?? false }
        return zip(bounds, bounds.dropFirst()).map { left, right in
            var first = left + 1, last = right
            while first < last, blank(first) { first += 1 }
            while last > first, blank(last - 1) { last -= 1 }
            return NSRange(location: first, length: last - first)
        }
    }
}
