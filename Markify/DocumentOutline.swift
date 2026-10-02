import Foundation
import MarkifyMarkdown

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
