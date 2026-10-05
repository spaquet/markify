import Foundation
import MarkifyMarkdown

/// Source-derived values survive selection, scrolling and other view updates.
@MainActor final class DocumentDerivedData {
    private var source: String?
    private var words: Int?
    private var parsed: MarkdownModel?
    private var outline: [DocumentHeading]?
    private var links: [DocumentLink]?
    private var find: (query: String, matchCase: Bool, ranges: [NSRange])?

    private func prepare(_ text: String) {
        guard source != text else { return }
        source = text
        words = nil; parsed = nil; outline = nil; links = nil; find = nil
    }

    func wordCount(in text: String) -> Int {
        prepare(text)
        if let words { return words }
        var count = 0, inWord = false
        for scalar in text.unicodeScalars {
            let whitespace = scalar.properties.isWhitespace
            if !whitespace && !inWord { count += 1 }
            inWord = !whitespace
        }
        words = count
        return count
    }

    func model(in text: String, mdx: Bool, editor: MarkdownTextView?) -> MarkdownModel {
        prepare(text)
        if let parsed, parsed.mdx == mdx { return parsed }
        let model = editor.flatMap { $0.string == text ? $0.model : nil } ?? MarkdownModel(text, mdx: mdx)
        parsed = model
        outline = nil; links = nil
        return model
    }

    func headings(in model: MarkdownModel) -> [DocumentHeading] {
        prepare(model.source)
        if let outline { return outline }
        let result = DocumentHeading.extract(from: model)
        outline = result
        return result
    }

    func documentLinks(in model: MarkdownModel) -> [DocumentLink] {
        prepare(model.source)
        if let links { return links }
        let result = DocumentLink.extract(from: model)
        links = result
        return result
    }

    func matches(in text: String, query: String, matchCase: Bool) -> [NSRange] {
        prepare(text)
        if let find, find.query == query, find.matchCase == matchCase { return find.ranges }
        let regex = try? NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: query), options: matchCase ? [] : [.caseInsensitive])
        let result = regex?.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).map(\.range) ?? []
        find = (query, matchCase, result)
        return result
    }
}

/// A heading for the Contents outline. `range` is the heading's text in source offsets.
struct DocumentHeading: Identifiable, Equatable, Sendable {
    let range: NSRange
    let title: String
    let level: Int
    let line: Int
    /// The GitHub-style anchor export gives this heading, numbered like export when titles repeat.
    let anchor: String
    var id: String { anchor }

    static func extract(from model: MarkdownModel) -> [Self] {
        let source = model.source as NSString
        // Inline syntax inside a heading (emphasis markers, link destinations, inline HTML) stays out of its title.
        var hidden = IndexSet()
        for span in model.spans {
            if case .heading = span.kind { continue }
            if case .inlineHTML = span.kind { hidden.insert(integersIn: span.range.location..<NSMaxRange(span.range)) }
            for marker in span.markers { hidden.insert(integersIn: marker.location..<NSMaxRange(marker)) }
        }
        let starts = MarkdownSourceMap(model.source).starts
        var line = 0
        var used: [String: Int] = [:]
        return model.spans
            .compactMap { span -> (span: MarkdownModel.Span, level: Int)? in
                guard case let .heading(level, _) = span.kind else { return nil }
                return (span, level)
            }
            .sorted { $0.span.range.location < $1.span.range.location }
            .map { span, level in
                let content = span.content
                var text = ""
                for piece in IndexSet(integersIn: content.location..<NSMaxRange(content)).subtracting(hidden).rangeView {
                    text += source.substring(with: NSRange(location: piece.lowerBound, length: piece.count))
                }
                let title = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                while line + 1 < starts.count, starts[line + 1] <= span.range.location { line += 1 }
                var anchor = MarkdownHTML.slug(title)
                if let count = used[anchor] { used[anchor] = count + 1; anchor += "-\(count)" } else { used[anchor] = 1 }
                return Self(range: content, title: title, level: level, line: line + 1, anchor: anchor)
            }
    }
}

/// The Contents outline: which headings show for a depth, filter and collapsed sections, and where the reader is.
enum DocumentOutline {
    struct Row: Identifiable, Equatable {
        let index: Int
        let heading: DocumentHeading
        /// Tree guides before the row, one per level below the document's top level.
        let indent: Int
        let hasChildren: Bool
        let collapsed: Bool
        var id: String { heading.id }
    }

    static func rows(_ headings: [DocumentHeading], depth: Int, query: String, collapsed: Set<String>) -> [Row] {
        let top = headings.map(\.level).min() ?? 1
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        // A filter keeps matching headings and the sections they sit in, and shows them expanded.
        var keep = Set<Int>()
        if !query.isEmpty {
            for (index, heading) in headings.enumerated() where heading.level <= depth && heading.title.lowercased().contains(query) {
                keep.insert(index)
                keep.formUnion(ancestors(of: index, in: headings))
            }
        }
        var rows: [Row] = []
        var hideBelow = Int.max
        for (index, heading) in headings.enumerated() {
            if heading.level <= hideBelow { hideBelow = .max }
            guard heading.level <= hideBelow, heading.level <= depth, query.isEmpty || keep.contains(index) else { continue }
            let next = headings[(index + 1)...].first { $0.level <= depth }
            let hasChildren = next.map { $0.level > heading.level } ?? false
            let isCollapsed = hasChildren && query.isEmpty && collapsed.contains(heading.anchor)
            if isCollapsed { hideBelow = heading.level }
            rows.append(Row(index: index, heading: heading, indent: heading.level - top, hasChildren: hasChildren, collapsed: isCollapsed))
        }
        return rows
    }

    static func ancestors(of index: Int, in headings: [DocumentHeading]) -> Set<Int> {
        var result = Set<Int>()
        var level = headings[index].level
        for candidate in stride(from: index - 1, through: 0, by: -1) where headings[candidate].level < level {
            result.insert(candidate)
            level = headings[candidate].level
        }
        return result
    }

    /// The heading being read: the last one that starts at or before `offset`, the source offset at the top of the page.
    static func active(_ headings: [DocumentHeading], at offset: Int) -> Int? {
        headings.lastIndex { $0.range.location <= offset } ?? (headings.isEmpty ? nil : 0)
    }

    /// A nested Markdown list linking to every heading down to `depth`, as Insert Table of Contents writes it.
    static func tableOfContents(_ headings: [DocumentHeading], depth: Int) -> String {
        let included = headings.filter { $0.level <= depth }
        let top = included.map(\.level).min() ?? 1
        return included.map { heading in
            let title = heading.title.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
            return String(repeating: "  ", count: heading.level - top) + "- [\(title)](#\(heading.anchor))"
        }.joined(separator: "\n")
    }
}

/// A table of contents in the document: `<!-- toc -->`, the list Markify keeps in step with the headings, `<!-- /toc -->`.
struct TableOfContentsBlock: Equatable {
    /// From the opening comment through the closing one.
    let range: NSRange
    let opening: NSRange
    let closing: NSRange
    /// The lines between the comments.
    let body: NSRange
    let depth: Int

    static func find(in model: MarkdownModel) -> Self? {
        let source = model.source as NSString
        // A comment's range without the line break after it.
        func trimmed(_ range: NSRange) -> NSRange {
            var length = range.length
            while length > 0, [10, 13, 32, 9].contains(source.character(at: range.location + length - 1)) { length -= 1 }
            return NSRange(location: range.location, length: length)
        }
        var open: (range: NSRange, depth: Int)?
        for span in model.spans where span.kind == .htmlBlock {
            let text = source.substring(with: span.range)
            if open == nil, let depth = TableOfContentsMarker.depth(ofOpening: text) {
                open = (trimmed(span.range), depth)
            } else if let opening = open, TableOfContentsMarker.isClosing(text) {
                let bodyStart = NSMaxRange(source.lineRange(for: NSRange(location: opening.range.location, length: 0)))
                let closing = trimmed(span.range)
                return Self(range: NSRange(location: opening.range.location, length: NSMaxRange(closing) - opening.range.location),
                            opening: opening.range, closing: closing,
                            body: NSRange(location: bodyStart, length: max(0, closing.location - bodyStart)), depth: opening.depth)
            }
        }
        return nil
    }

    /// The whole block for these headings, as inserted and kept up to date.
    static func text(_ headings: [DocumentHeading], depth: Int) -> String {
        let list = DocumentOutline.tableOfContents(headings, depth: depth)
        return TableOfContentsMarker.opening(depth: depth) + "\n" + (list.isEmpty ? "" : list + "\n") + TableOfContentsMarker.closing
    }
}
