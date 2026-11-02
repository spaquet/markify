import Foundation

extension MarkdownModel {
    /// Paired HTML disclosure sections, in source coordinates. Unmatched tags stay ordinary HTML.
    public struct Details: Sendable {
        public let range: NSRange
        public let summary: NSRange
        public let body: NSRange
        public let initiallyOpen: Bool

        static func find(in source: NSString, spans: [Span]) -> [Details] {
            let tags = try! NSRegularExpression(pattern: #"(?i)<!--[\s\S]*?-->|</?details\b(?:[^>"']|"[^"]*"|'[^']*')*>|<summary\b(?:[^>"']|"[^"]*"|'[^']*')*>([\s\S]*?)</summary\s*>"#)
            let attributes = try! NSRegularExpression(pattern: #"(?i)\s+([a-z_:][a-z0-9_:.-]*)(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+))?"#)
            var stack: [(start: Int, open: Bool, summary: NSRange?, body: Int)] = []
            var result: [Details] = []
            // Only HTML blocks own disclosure tags: never interpret examples in code or comments.
            for span in spans where span.kind == .htmlBlock {
                let html = source.substring(with: span.range)
                if html.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<!--") { continue }
                for match in tags.matches(in: source as String, range: span.range) {
                    let tag = source.substring(with: match.range)
                    if tag.hasPrefix("<!--") { continue }
                    if tag.lowercased().hasPrefix("</details") {
                        guard let opening = stack.popLast(), let summary = opening.summary else { continue }
                        result.append(Details(range: NSRange(location: opening.start, length: NSMaxRange(match.range) - opening.start),
                                              summary: summary, body: NSRange(location: opening.body, length: match.range.location - opening.body), initiallyOpen: opening.open))
                    } else if tag.lowercased().hasPrefix("<details") {
                        let ns = tag as NSString
                        let open = attributes.matches(in: tag, range: NSRange(location: 0, length: ns.length)).contains {
                            ns.substring(with: $0.range(at: 1)).lowercased() == "open"
                        }
                        stack.append((match.range.location, open, nil, NSMaxRange(match.range)))
                    } else if !stack.isEmpty, stack[stack.count - 1].summary == nil {
                        stack[stack.count - 1].summary = match.range(at: 1)
                        stack[stack.count - 1].body = NSMaxRange(match.range)
                    }
                }
            }
            return result.sorted { $0.range.location < $1.range.location }
        }
    }
}
