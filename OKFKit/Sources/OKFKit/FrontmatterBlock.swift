import Foundation

/// Namespace for format-wide constants.
public enum OKF {
    /// The OKF revision this package implements.
    public static let specVersion = "0.2"
    /// Filenames with defined meaning at any level of a bundle (§3.1).
    public static let reservedFilenames: Set<String> = ["index.md", "log.md"]
}

/// The YAML block delimited by `---` lines at the top of a Markdown file.
///
/// Offsets are UTF-16, matching `NSString` and `NSRange`, so the editor can splice edits in place.
public struct FrontmatterBlock: Equatable, Sendable {
    /// The YAML between the fences.
    public let yaml: String
    /// Offset and length of the whole block, fences and trailing newline included.
    public let blockRange: Range<Int>
    /// Offset and length of the YAML between the fences.
    public let yamlRange: Range<Int>

    /// Locates the frontmatter at the start of `source`, or nil when the file has none.
    public static func locate(in source: String) -> FrontmatterBlock? {
        let ns = source as NSString
        let opening: Int
        if source.hasPrefix("---\n") { opening = 4 } else if source.hasPrefix("---\r\n") { opening = 5 } else { return nil }
        guard let regex = try? NSRegularExpression(pattern: #"(?m)^---[ \t]*\r?$"#) else { return nil }
        // An empty block closes on the line right after the opening fence.
        guard let close = regex.firstMatch(in: source, range: NSRange(location: opening, length: ns.length - opening))?.range else { return nil }
        var end = NSMaxRange(close)
        if end < ns.length, ns.character(at: end) == 13 { end += 1 }
        if end < ns.length, ns.character(at: end) == 10 { end += 1 }
        let yamlRange = opening..<max(opening, close.location)
        let yaml = ns.substring(with: NSRange(location: yamlRange.lowerBound, length: yamlRange.count))
        return FrontmatterBlock(yaml: yaml, blockRange: 0..<end, yamlRange: yamlRange)
    }

    /// Everything after the block.
    public static func body(of source: String) -> String {
        guard let block = locate(in: source) else { return source }
        return (source as NSString).substring(from: block.blockRange.upperBound)
    }
}
