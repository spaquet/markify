import Foundation

/// The comments around a table of contents Markify inserts and keeps up to date:
/// `<!-- toc -->` (or `<!-- toc depth=2 -->`), a nested list of heading links, then `<!-- /toc -->`.
/// Other Markdown tools show the list; Markify's editor and export draw it as a Contents card.
public enum TableOfContentsMarker {
    public static let closing = "<!-- /toc -->"
    /// The deepest heading level, when the comment doesn't name one.
    public static let allLevels = 6

    /// The depth an opening comment asks for, or nil when `text` isn't one.
    public static func depth(ofOpening text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("<!--"),
              let match = openingPattern.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)) else { return nil }
        let depth = match.range(at: 1)
        return depth.location == NSNotFound ? allLevels : Int((trimmed as NSString).substring(with: depth)) ?? allLevels
    }

    public static func isClosing(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("<!--") && closingPattern.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)) != nil
    }

    private static let openingPattern = try! NSRegularExpression(pattern: #"^<!--\s*toc(?:\s+depth\s*=\s*([1-6]))?\s*-->$"#, options: .caseInsensitive)
    private static let closingPattern = try! NSRegularExpression(pattern: #"^<!--\s*/toc\s*-->$"#, options: .caseInsensitive)

    public static func opening(depth: Int) -> String {
        depth >= allLevels ? "<!-- toc -->" : "<!-- toc depth=\(depth) -->"
    }
}
