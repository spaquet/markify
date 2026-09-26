import Foundation

/// Who or what performed an action (§7): `<producer>/<version>`, `human:<id>` or `process:<id>`.
public enum OKFActor: Hashable, Sendable, CustomStringConvertible {
    case human(String)
    case process(String)
    case agent(producer: String, version: String)
    /// Anything else, such as `team:ga4-docs`, kept verbatim.
    case other(String)

    public init(_ raw: String) {
        let raw = raw.trimmingCharacters(in: .whitespaces)
        if raw.hasPrefix("human:") {
            self = .human(String(raw.dropFirst(6)))
        } else if raw.hasPrefix("process:") {
            self = .process(String(raw.dropFirst(8)))
        } else if let slash = raw.firstIndex(of: "/"), !raw.contains(":"), slash != raw.startIndex, slash != raw.index(before: raw.endIndex) {
            self = .agent(producer: String(raw[..<slash]), version: String(raw[raw.index(after: slash)...]))
        } else {
            self = .other(raw)
        }
    }

    /// The actor as written in frontmatter.
    public var description: String {
        switch self {
        case .human(let id): "human:\(id)"
        case .process(let id): "process:\(id)"
        case .agent(let producer, let version): "\(producer)/\(version)"
        case .other(let raw): raw
        }
    }

    public var isHuman: Bool { if case .human = self { true } else { false } }

    /// A short label for display: the id, process name or producer.
    public var displayName: String {
        switch self {
        case .human(let id), .process(let id): id
        case .agent(let producer, _): producer
        case .other(let raw): raw
        }
    }
}
