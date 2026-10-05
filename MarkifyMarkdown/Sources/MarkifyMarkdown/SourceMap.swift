import Foundation
import Markdown

/// Converts swift-markdown source locations (1-based line, UTF-8 byte column) into UTF-16 offsets.
public struct MarkdownSourceMap {
    public let lines: [String]
    public let starts: [Int]
    private struct Boundary {
        let start: Int
        let end: Int
        let utf16: Int
    }
    private let boundaries: [[Boundary]]
    private let byteCounts: [Int]

    public init(_ source: String) {
        lines = source.components(separatedBy: "\n")
        var starts = [0]
        for line in lines.dropLast() { starts.append(starts.last! + (line as NSString).length + 1) }
        self.starts = starts
        var indexed: [[Boundary]] = []
        var counts: [Int] = []
        for line in lines {
            var bytes = 0, utf16 = 0
            var entries: [Boundary] = []
            for scalar in line.unicodeScalars {
                let start = bytes
                bytes += scalar.utf8.count
                utf16 += scalar.utf16.count
                if scalar.utf8.count > 1 { entries.append(Boundary(start: start, end: bytes, utf16: utf16)) }
            }
            indexed.append(entries)
            counts.append(bytes)
        }
        boundaries = indexed
        byteCounts = counts
    }

    public func offset(_ location: Markdown.SourceLocation) -> Int? {
        let line = location.line - 1
        guard lines.indices.contains(line), location.column > 0 else { return nil }
        let byte = location.column - 1
        guard byte <= byteCounts[line] else { return nil }
        let entries = boundaries[line]
        var low = 0, high = entries.count
        while low < high {
            let middle = (low + high) / 2
            if entries[middle].end < byte { low = middle + 1 } else { high = middle }
        }
        if low < entries.count, byte > entries[low].start { return starts[line] + entries[low].utf16 }
        let correction = low > 0 ? entries[low - 1].utf16 - entries[low - 1].end : 0
        return starts[line] + byte + correction
    }

    public func range(_ range: Markdown.SourceRange) -> NSRange? {
        guard let start = offset(range.lowerBound), let end = offset(range.upperBound), end >= start else { return nil }
        return NSRange(location: start, length: end - start)
    }
}
