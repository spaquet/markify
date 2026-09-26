import Foundation
import Markdown

/// Converts swift-markdown source locations (1-based line, UTF-8 byte column) into UTF-16 offsets.
public struct MarkdownSourceMap {
    public let lines: [String]
    public let starts: [Int]

    public init(_ source: String) {
        lines = source.components(separatedBy: "\n")
        var starts = [0]
        for line in lines.dropLast() { starts.append(starts.last! + (line as NSString).length + 1) }
        self.starts = starts
    }

    public func offset(_ location: Markdown.SourceLocation) -> Int? {
        let line = location.line - 1
        guard lines.indices.contains(line), location.column > 0 else { return nil }
        var remaining = location.column - 1
        var utf16 = 0
        for scalar in lines[line].unicodeScalars {
            guard remaining > 0 else { break }
            remaining -= scalar.utf8.count
            utf16 += scalar.utf16.count
        }
        guard remaining <= 0 else { return nil }
        return starts[line] + utf16
    }

    public func range(_ range: Markdown.SourceRange) -> NSRange? {
        guard let start = offset(range.lowerBound), let end = offset(range.upperBound), end >= start else { return nil }
        return NSRange(location: start, length: end - start)
    }
}
