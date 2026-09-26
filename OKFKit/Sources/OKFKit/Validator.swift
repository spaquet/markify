import Foundation

/// A finding about a document. Only `.error` makes a bundle non-conformant (§11); nothing makes it unreadable.
public struct OKFDiagnostic: Hashable, Sendable, Identifiable {
    public enum Severity: Int, Comparable, Sendable {
        case info, warning, error
        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public let severity: Severity
    public let message: String
    /// The document's bundle path, when the finding is about one file.
    public let path: String?
    public let url: URL?

    public var id: String { "\(path ?? "")|\(severity)|\(message)" }

    public init(_ severity: Severity, _ message: String, path: String? = nil, url: URL? = nil) {
        self.severity = severity
        self.message = message
        self.path = path
        self.url = url
    }
}

public enum OKFValidator {
    /// Checks one document's own content. `isBundleRoot` allows `okf_version` in an `index.md`.
    public static func validate(source: String, kind: OKFDocument.Kind, isBundleRoot: Bool = false, now: Date = Date()) -> [OKFDiagnostic] {
        switch kind {
        case .concept: validateConcept(source: source, now: now)
        case .index: validateIndex(source: source, isBundleRoot: isBundleRoot)
        case .log: validateLog(source: source)
        }
    }

    /// Every document, plus broken links as information.
    public static func validate(bundle: OKFBundle, now: Date = Date()) -> [OKFDiagnostic] {
        bundle.documents.flatMap { validate(document: $0, in: bundle, now: now) }
    }

    public static func validate(document: OKFDocument, in bundle: OKFBundle, now: Date = Date()) -> [OKFDiagnostic] {
        let isRoot = OKFBundle.key(document.url.deletingLastPathComponent()) == OKFBundle.key(bundle.root)
        var found = validate(source: document.source, kind: document.kind, isBundleRoot: isRoot, now: now)
        for link in bundle.brokenLinks(in: document) {
            found.append(OKFDiagnostic(.info, "Links to \(link.target), which does not exist yet."))
        }
        return found.map { OKFDiagnostic($0.severity, $0.message, path: document.path, url: document.url) }
    }

    static func validateConcept(source: String, now: Date) -> [OKFDiagnostic] {
        guard let result = OKFConcept.parse(source: source) else {
            return [OKFDiagnostic(.error, "Missing YAML frontmatter; every concept needs a `type`.")]
        }
        let concept: OKFConcept
        switch result {
        case .failure(let error): return [OKFDiagnostic(.error, error.description)]
        case .success(let parsed): concept = parsed
        }
        var found: [OKFDiagnostic] = []
        if !concept.isConcept { found.append(OKFDiagnostic(.error, "Frontmatter has no `type`.")) }
        if concept.okfVersion != nil {
            found.append(OKFDiagnostic(.warning, "`okf_version` belongs in the bundle-root index.md, not in a concept."))
        }
        if case .other(let raw) = concept.status {
            found.append(OKFDiagnostic(.warning, "Unknown status \"\(raw)\"; use draft, stable or deprecated."))
        }
        if let raw = concept.staleAfterRaw {
            if concept.staleAfter == nil { found.append(OKFDiagnostic(.warning, "`stale_after` is not an ISO 8601 date-time.")) }
            else if !OKFTimestamp.hasOffset(raw) { found.append(OKFDiagnostic(.warning, "`stale_after` needs a time with a UTC offset, such as 2026-06-30T14:00:00Z.")) }
        }
        if concept.isStale(at: now) { found.append(OKFDiagnostic(.info, "Stale since \(concept.staleAfterRaw ?? "")."))  }
        if let generated = concept.generated {
            if generated.by == nil { found.append(OKFDiagnostic(.warning, "`generated` is missing `by`.")) }
            found += timestampIssues(generated, field: "generated.at")
        }
        for stamp in concept.verified {
            if stamp.by == nil { found.append(OKFDiagnostic(.warning, "A `verified` entry is missing `by`.")) }
            if stamp.atRaw == nil { found.append(OKFDiagnostic(.warning, "A `verified` entry is missing `at`.")) }
            found += timestampIssues(stamp, field: "verified.at")
        }
        for (index, source) in concept.sources.enumerated() where source.resource == nil {
            found.append(OKFDiagnostic(.warning, "Source \(source.id ?? "#\(index + 1)") is missing `resource`."))
        }
        let sourceIDs = Set(concept.sources.compactMap(\.id))
        for label in footnoteLabels(in: FrontmatterBlock.body(of: source)) where !concept.sources.isEmpty && !sourceIDs.contains(label) {
            found.append(OKFDiagnostic(.info, "Footnote [^\(label)] does not match a `sources` id."))
        }
        if concept.isAttestedComputation && (concept.runtime ?? "").isEmpty {
            found.append(OKFDiagnostic(.warning, "An Attested Computation needs a `runtime`."))
        }
        return found
    }

    static func validateIndex(source: String, isBundleRoot: Bool) -> [OKFDiagnostic] {
        guard let block = FrontmatterBlock.locate(in: source) else { return [] }
        guard isBundleRoot else { return [OKFDiagnostic(.error, "Only the bundle-root index.md may have frontmatter.")] }
        guard case .success(let concept)? = OKFConcept.parse(source: source) else {
            return [OKFDiagnostic(.error, "The index frontmatter is not valid YAML.")]
        }
        let extra = concept.keys.filter { $0 != "okf_version" }
        if !extra.isEmpty || block.yaml.isEmpty {
            return [OKFDiagnostic(.error, "The root index.md frontmatter may only hold `okf_version`.")]
        }
        return []
    }

    static func validateLog(source: String) -> [OKFDiagnostic] {
        var found: [OKFDiagnostic] = []
        var dates: [String] = []
        for line in FrontmatterBlock.body(of: source).components(separatedBy: .newlines) where line.hasPrefix("## ") {
            let heading = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
            if heading.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) == nil {
                found.append(OKFDiagnostic(.error, "Log heading \"\(heading)\" is not a YYYY-MM-DD date."))
            } else {
                dates.append(heading)
            }
        }
        if dates != dates.sorted(by: >) { found.append(OKFDiagnostic(.warning, "Log dates should run newest first.")) }
        return found
    }

    private static func timestampIssues(_ stamp: OKFStamp, field: String) -> [OKFDiagnostic] {
        guard let raw = stamp.atRaw else { return [] }
        if stamp.at == nil { return [OKFDiagnostic(.warning, "`\(field)` is not an ISO 8601 date-time.")] }
        if !OKFTimestamp.hasOffset(raw) { return [OKFDiagnostic(.warning, "`\(field)` needs a time with a UTC offset.")] }
        return []
    }

    private static func footnoteLabels(in body: String) -> Set<String> {
        let ns = body as NSString
        let regex = try! NSRegularExpression(pattern: #"\[\^([^\]\s]+)\](?!:)"#)
        return Set(regex.matches(in: body, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) })
    }
}
