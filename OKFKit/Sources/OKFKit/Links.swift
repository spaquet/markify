import Foundation

/// A Markdown link found in a document body (§6.1).
public struct OKFLink: Hashable, Sendable {
    public let text: String
    /// The destination as written.
    public let target: String
    /// UTF-16 offsets of the whole link in the scanned text.
    public let range: Range<Int>

    /// True for destinations with a URL scheme (`https:`, `mailto:`), which never point into the bundle.
    public var isExternal: Bool { OKFLinks.hasScheme(target) }
}

public enum OKFLinks {
    /// Inline links and reference definitions, skipping images, footnotes, code spans and fenced code.
    public static func extract(from markdown: String) -> [OKFLink] {
        let ns = markdown as NSString
        let whole = NSRange(location: 0, length: ns.length)
        let code = codeRanges(in: markdown)
        func inCode(_ location: Int) -> Bool { code.contains { $0.contains(location) } }
        var links: [OKFLink] = []
        let inline = try! NSRegularExpression(pattern: #"(!?)\[((?:[^\[\]\n]|\[[^\[\]\n]*\])*)\]\(\s*<?([^)\s>]+)>?(?:\s+(?:"[^"]*"|'[^']*'|\([^)]*\)))?\s*\)"#)
        for match in inline.matches(in: markdown, range: whole) where match.range(at: 1).length == 0 && !inCode(match.range.location) {
            links.append(OKFLink(text: ns.substring(with: match.range(at: 2)), target: ns.substring(with: match.range(at: 3)),
                                 range: match.range.location..<NSMaxRange(match.range)))
        }
        let definition = try! NSRegularExpression(pattern: #"(?m)^[ ]{0,3}\[([^\]^\n][^\]\n]*)\]:[ \t]*<?([^\s>]+)>?"#)
        for match in definition.matches(in: markdown, range: whole) where !inCode(match.range.location) {
            links.append(OKFLink(text: ns.substring(with: match.range(at: 1)), target: ns.substring(with: match.range(at: 2)),
                                 range: match.range.location..<NSMaxRange(match.range)))
        }
        return links.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// The link whose source text covers a UTF-16 offset, for click handling.
    public static func link(at location: Int, in markdown: String) -> OKFLink? {
        extract(from: markdown).first { $0.range.contains(location) }
    }

    /// Resolves a destination to a file URL: `/…` against the bundle root, anything else against the document's folder.
    /// Returns nil for external URLs and in-page anchors.
    public static func resolve(_ target: String, from document: URL?, bundleRoot: URL?) -> URL? {
        guard !hasScheme(target) || target.lowercased().hasPrefix("file:") else { return nil }
        if target.lowercased().hasPrefix("file:") { return URL(string: target)?.standardizedFileURL }
        var path = target
        if let cut = path.firstIndex(where: { $0 == "#" || $0 == "?" }) { path = String(path[..<cut]) }
        path = path.removingPercentEncoding ?? path
        guard !path.isEmpty else { return nil }
        let isDirectory = path.hasSuffix("/")
        if path.hasPrefix("/") {
            guard let base = bundleRoot ?? document?.deletingLastPathComponent() else { return nil }
            return base.appendingPathComponent(String(path.dropFirst()), isDirectory: isDirectory).standardizedFileURL
        }
        guard let document else { return nil }
        return document.deletingLastPathComponent().appendingPathComponent(path, isDirectory: isDirectory).standardizedFileURL
    }

    /// A bundle-absolute path for a file inside the root, such as `/tables/orders.md`.
    public static func bundlePath(of url: URL, root: URL) -> String? {
        let file = url.standardizedFileURL.resolvingSymlinksInPath().path
        let base = root.standardizedFileURL.resolvingSymlinksInPath().path
        let prefix = base.hasSuffix("/") ? base : base + "/"
        guard file.hasPrefix(prefix) else { return nil }
        return "/" + file.dropFirst(prefix.count)
    }

    /// A relative path from one directory to a file, used when writing `index.md` entries.
    public static func relativePath(to url: URL, from directory: URL) -> String {
        let target = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let base = directory.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        var shared = 0
        while shared < min(target.count, base.count), target[shared] == base[shared] { shared += 1 }
        let parts = Array(repeating: "..", count: base.count - shared) + target[shared...]
        return parts.joined(separator: "/")
    }

    static func hasScheme(_ target: String) -> Bool {
        target.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#, options: .regularExpression) != nil
    }

    /// Fenced code blocks and inline code spans, as UTF-16 ranges.
    static func codeRanges(in markdown: String) -> [Range<Int>] {
        let ns = markdown as NSString
        let whole = NSRange(location: 0, length: ns.length)
        var ranges: [Range<Int>] = []
        let fence = try! NSRegularExpression(pattern: #"(?ms)^[ ]{0,3}(`{3,}|~{3,})[^\n]*\n.*?(?:^[ ]{0,3}\1[ \t]*$|\z)"#)
        for match in fence.matches(in: markdown, range: whole) { ranges.append(match.range.location..<NSMaxRange(match.range)) }
        let span = try! NSRegularExpression(pattern: #"(`+)[^`\n](?:.*?[^`])?\1(?!`)"#)
        for match in span.matches(in: markdown, range: whole) where !ranges.contains(where: { $0.contains(match.range.location) }) {
            ranges.append(match.range.location..<NSMaxRange(match.range))
        }
        return ranges
    }
}
