import Foundation
import Yams

/// Lifecycle status (§5.4). Absent means `stable`.
public enum OKFStatus: Hashable, Sendable {
    case draft, stable, deprecated
    /// A value the spec does not define, kept verbatim.
    case other(String)

    public init(_ raw: String?) {
        switch raw?.trimmingCharacters(in: .whitespaces).lowercased() {
        case nil, "", "stable": self = .stable
        case "draft": self = .draft
        case "deprecated": self = .deprecated
        default: self = .other(raw!)
        }
    }

    public var name: String {
        switch self {
        case .draft: "draft"
        case .stable: "stable"
        case .deprecated: "deprecated"
        case .other(let raw): raw
        }
    }
}

/// Trust derived from `verified` (§5.3), lowest to highest.
public enum OKFTrustTier: Int, Comparable, Sendable {
    case unverified, machineConfirmed, humanReviewed

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .unverified: "Unverified"
        case .machineConfirmed: "Machine-confirmed"
        case .humanReviewed: "Human-reviewed"
        }
    }
}

/// A `{ by, at }` record from `generated` or `verified` (§5.2).
public struct OKFStamp: Hashable, Sendable {
    public var by: OKFActor?
    public var at: Date?
    /// `at` as written, kept so validation can check its form.
    public var atRaw: String?

    public init(by: OKFActor?, at: Date?, atRaw: String? = nil) {
        self.by = by
        self.at = at
        self.atRaw = atRaw ?? at.map(OKFTimestamp.format)
    }
}

/// One `sources` entry (§5.1).
public struct OKFSource: Hashable, Sendable {
    public var resource: String?
    public var id: String?
    public var title: String?
    public var author: OKFActor?
    public var usageCount: Int?
    public var lastModified: Date?
}

/// A declared parameter of an Attested Computation (§10.2).
public struct OKFParameter: Hashable, Sendable {
    public var name: String?
    public var type: String?
    public var required: Bool
}

/// The frontmatter of an OKF document, read tolerantly: anything missing is nil, anything unknown is kept by name.
public struct OKFConcept: Hashable, Sendable {
    public enum ParseError: Error, Equatable, Sendable, CustomStringConvertible {
        case invalidYAML(String)
        case notAMapping

        public var description: String {
            switch self {
            case .invalidYAML(let message): "The frontmatter is not valid YAML: \(message)"
            case .notAMapping: "The frontmatter is not a set of key: value pairs."
            }
        }
    }

    /// Keys this package understands; everything else is an extension key (§4.1).
    public static let knownKeys: Set<String> = [
        "type", "title", "description", "resource", "tags", "sources", "usage_window", "generated", "verified",
        "status", "stale_after", "runtime", "parameters", "computation", "executor", "attester", "okf_version"
    ]

    public var type: String?
    public var title: String?
    public var description: String?
    public var resource: String?
    public var tags: [String] = []
    public var sources: [OKFSource] = []
    public var generated: OKFStamp?
    public var verified: [OKFStamp] = []
    public var statusRaw: String?
    public var staleAfter: Date?
    public var staleAfterRaw: String?
    public var runtime: String?
    public var parameters: [OKFParameter] = []
    public var computation: String?
    public var executorResource: String?
    public var receipt: [String] = []
    public var attesterResource: String?
    public var okfVersion: String?
    /// Every top-level key, in file order.
    public var keys: [String] = []

    public init() {}

    /// Parses frontmatter YAML. An empty block yields an empty concept.
    public init(yaml: String) throws(ParseError) {
        let root: Node?
        do { root = try Yams.compose(yaml: yaml) } catch { throw .invalidYAML(Self.message(for: error)) }
        guard let root else { return }
        guard let keyNodes = root.mapping?.keys else { throw .notAMapping }
        let mapping = root
        keys = keyNodes.compactMap(\.string)
        type = mapping["type"]?.text
        title = mapping["title"]?.text
        description = mapping["description"]?.text
        resource = mapping["resource"]?.text
        tags = mapping["tags"]?.strings ?? []
        sources = (mapping["sources"]?.sequence ?? []).compactMap { node in
            guard node.mapping != nil else { return nil }
            let entry = node
            return OKFSource(resource: entry["resource"]?.text, id: entry["id"]?.text, title: entry["title"]?.text,
                             author: entry["author"]?.text.map(OKFActor.init), usageCount: entry["usage_count"]?.int,
                             lastModified: entry["last_modified"]?.text.flatMap(OKFTimestamp.parse))
        }
        generated = mapping["generated"].flatMap(Self.stamp)
        // A bare mapping is a one-element list (§5.2).
        if let single = mapping["verified"].flatMap(Self.stamp) {
            verified = [single]
        } else {
            verified = (mapping["verified"]?.sequence ?? []).compactMap(Self.stamp)
        }
        statusRaw = mapping["status"]?.text
        staleAfterRaw = mapping["stale_after"]?.text
        staleAfter = staleAfterRaw.flatMap(OKFTimestamp.parse)
        runtime = mapping["runtime"]?.text
        parameters = (mapping["parameters"]?.sequence ?? []).compactMap { node in
            guard node.mapping != nil else { return nil }
            let entry = node
            return OKFParameter(name: entry["name"]?.text, type: entry["type"]?.text, required: entry["required"]?.bool ?? false)
        }
        computation = mapping["computation"]?.text
        executorResource = mapping["executor"]?["resource"]?.text
        receipt = mapping["executor"]?["receipt"]?.strings ?? []
        attesterResource = mapping["attester"]?["resource"]?.text
        okfVersion = mapping["okf_version"]?.text
    }

    /// Parses the frontmatter at the top of a Markdown source, or nil when there is none.
    public static func parse(source: String) -> Result<OKFConcept, ParseError>? {
        guard let block = FrontmatterBlock.locate(in: source) else { return nil }
        do { return .success(try OKFConcept(yaml: block.yaml)) } catch { return .failure(error) }
    }

    /// True when `type` is present and non-empty, the one requirement for a concept (§4.1).
    public var isConcept: Bool { !(type ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
    public var status: OKFStatus { OKFStatus(statusRaw) }
    public var isAttestedComputation: Bool { type?.caseInsensitiveCompare("Attested Computation") == .orderedSame }
    /// Keys outside the spec, which must be preserved and never rejected.
    public var extensionKeys: [String] { keys.filter { !Self.knownKeys.contains($0) } }

    public var trustTier: OKFTrustTier {
        if verified.isEmpty { return .unverified }
        return verified.contains { $0.by?.isHuman == true } ? .humanReviewed : .machineConfirmed
    }

    /// The most recent verification, since "how recently" is the latest `at` (§5.2).
    public var lastVerified: OKFStamp? {
        verified.max { ($0.at ?? .distantPast) < ($1.at ?? .distantPast) }
    }

    /// Stale when `now >= stale_after` (§5.5).
    public func isStale(at now: Date = Date()) -> Bool {
        guard let staleAfter else { return false }
        return now >= staleAfter
    }

    private static func stamp(_ node: Node) -> OKFStamp? {
        guard node.mapping != nil else { return nil }
        let raw = node["at"]?.text
        return OKFStamp(by: node["by"]?.text.map(OKFActor.init), at: raw.flatMap(OKFTimestamp.parse), atRaw: raw)
    }

    private static func message(for error: Error) -> String {
        if let error = error as? YamlError, case let .scanner(_, problem, mark, _) = error { return "\(problem) (line \(mark.line))" }
        if let error = error as? YamlError, case let .parser(_, problem, mark, _) = error { return "\(problem) (line \(mark.line))" }
        return String(describing: error)
    }
}

/// ISO 8601 timestamps with an explicit offset (§5).
public enum OKFTimestamp {
    public static func parse(_ raw: String) -> Date? {
        let raw = raw.trimmingCharacters(in: .whitespaces)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: raw)
    }

    /// True when the timestamp carries `Z` or a `±hh:mm` offset, as the spec requires.
    public static func hasOffset(_ raw: String) -> Bool {
        raw.range(of: #"T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})$"#, options: .regularExpression) != nil
    }

    /// Seconds precision in UTC, the form Markify writes.
    public static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

extension Node {
    /// A scalar as a string, or nil for maps, lists and YAML null.
    var text: String? {
        guard let scalar, !(scalar.style == .plain && ["", "~", "null", "Null", "NULL"].contains(scalar.string)) else { return nil }
        return scalar.string
    }

    /// A list of scalars, or a single scalar as a one-element list.
    var strings: [String]? {
        if let sequence { return sequence.compactMap(\.text) }
        return text.map { [$0] }
    }
}
