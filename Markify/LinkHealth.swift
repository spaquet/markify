import Foundation
import MarkifyMarkdown
import OKFKit
import Observation

/// Where a link points, for grouping, checking and opening. Links with other schemes (mailto:, tel:, app links) have none.
enum LinkTarget: Equatable, Sendable {
    /// A heading in this document.
    case anchor(String)
    /// A local file, with the heading named after `#`. The URL is nil when a relative path has nothing to resolve against.
    case file(URL?, fragment: String?)
    case web(URL)

    enum Kind: String, CaseIterable, Sendable { case anchor, file, web }
    var kind: Kind {
        switch self {
        case .anchor: .anchor
        case .file: .file
        case .web: .web
        }
    }

    static func of(_ destination: String, document: URL?, root: URL?, baseDirectory: URL?) -> Self? {
        if destination.hasPrefix("#") { return .anchor(fragment(destination) ?? "") }
        if let baseDirectory, !baseDirectory.isFileURL {
            guard let url = URL(string: destination, relativeTo: baseDirectory)?.absoluteURL, isWeb(url) else { return nil }
            return .web(url)
        }
        if let url = URL(string: destination), url.scheme != nil, !destination.lowercased().hasPrefix("file:") {
            return isWeb(url) ? .web(url) : nil
        }
        return .file(OKFLinks.resolve(destination, from: document, bundleRoot: root, baseDirectory: baseDirectory), fragment: fragment(destination))
    }

    /// The decoded part after `#`, if any.
    static func fragment(_ destination: String) -> String? {
        guard let mark = destination.firstIndex(of: "#") else { return nil }
        let fragment = String(destination[destination.index(after: mark)...])
        return fragment.isEmpty ? nil : fragment.removingPercentEncoding ?? fragment
    }

    private static func isWeb(_ url: URL) -> Bool { ["http", "https"].contains(url.scheme?.lowercased() ?? "") }
}

enum LinkStatus: Equatable, Sendable {
    case ok
    case broken(String)
    /// Not checked yet, or can't be (offline, rate limited, nothing to resolve against).
    case unknown

    var reason: String? { if case let .broken(reason) = self { reason } else { nil } }
}

/// Local checks: headings in this document, and files (with their headings) on disk. Run off the main thread.
enum LocalLinkCheck {
    static func status(of target: LinkTarget, anchors: Set<String>, openTexts: [URL: String]) -> LinkStatus {
        switch target {
        case let .anchor(fragment):
            return anchors.contains(fragment) ? .ok : .broken("No such heading")
        case let .file(url, fragment):
            guard let url else { return .unknown }
            var isDirectory: ObjCBool = false
            let open = openTexts[url.standardizedFileURL]
            guard open != nil || FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return .broken("File not found") }
            guard let fragment, !isDirectory.boolValue, ["md", "markdown", "mdx"].contains(url.pathExtension.lowercased()) else { return .ok }
            guard let text = open ?? (try? String(contentsOf: url, encoding: .utf8)) else { return .unknown }
            let headings = DocumentHeading.extract(from: MarkdownModel(text, mdx: url.pathExtension.lowercased() == "mdx"))
            return headings.contains { $0.anchor == fragment } ? .ok : .broken("No such heading")
        case .web:
            return .unknown
        }
    }
}

/// Web link checks shared by every window, kept on disk for 24 hours. A click on a link checks it again at once.
@MainActor @Observable final class WebLinkChecks {
    static let shared = WebLinkChecks()
    nonisolated static let lifetime: TimeInterval = 24 * 60 * 60

    struct Entry: Codable, Equatable, Sendable {
        /// The reason a link is broken; nil when it answered.
        var broken: String?
        var date: Date
    }

    private(set) var entries: [String: Entry]
    private(set) var inFlight: Set<String> = []
    @ObservationIgnored let location: URL
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var pending: [String: URL] = [:]
    @ObservationIgnored private var persistence: Task<Void, Never>?

    init(location: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Markify/link-checks.json"), session: URLSession? = nil) {
        self.location = location
        entries = [:]
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.httpMaximumConnectionsPerHost = 2
        self.session = session ?? URLSession(configuration: configuration)
        let read = Task.detached(priority: .utility) {
            let data = try? FileRead.data(at: location, maximumBytes: 2_000_000)
            let decoded = data.flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
            return Self.pruned(decoded)
        }
        loading = Task { [weak self] in
            self?.entries = await read.value
            self?.loading = nil
        }
    }

    nonisolated private static func pruned(_ entries: [String: Entry]) -> [String: Entry] {
        Dictionary(uniqueKeysWithValues: entries.filter { Date.now.timeIntervalSince($0.value.date) < lifetime * 7 }
            .sorted { $0.value.date > $1.value.date }.prefix(2048).map { ($0.key, $0.value) })
    }

    nonisolated static func key(_ url: URL) -> String {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return url.absoluteString }
        parts.fragment = nil
        return parts.url?.absoluteString ?? url.absoluteString
    }

    func status(of url: URL) -> LinkStatus {
        guard let entry = entries[Self.key(url)] else { return .unknown }
        return entry.broken.map(LinkStatus.broken) ?? .ok
    }

    func date(of url: URL) -> Date? { entries[Self.key(url)]?.date }

    func waitForLoad() async { await loading?.value }

    /// Checks links whose result is missing or older than a day, or all of them when `force` is set; at most four at a time.
    func check(_ urls: [URL], force: Bool) async {
        await loading?.value
        for url in urls {
            let key = Self.key(url)
            guard !inFlight.contains(key), key.utf8.count <= 8192, pending.count < 1000,
                  force || (entries[key].map({ Date.now.timeIntervalSince($0.date) > Self.lifetime }) ?? true) else { continue }
            inFlight.insert(key)
            pending[key] = url
        }
        guard !pending.isEmpty else { return }
        if worker == nil { worker = Task { await drain() } }
        await worker?.value
    }

    /// The singleton owns the group, so simultaneous windows share four slots.
    private func drain() async {
        let session = session
        await withTaskGroup(of: (String, String??).self) { group in
            @MainActor func next() {
                guard let (key, url) = pending.first else { return }
                pending[key] = nil
                group.addTask { (key, await Self.probe(url, session: session)) }
            }
            for _ in 0..<4 { next() }
            while let (key, result) = await group.next() {
                inFlight.remove(key)
                if let result { entries[key] = Entry(broken: result, date: .now) }
                next()
            }
        }
        save()
        worker = nil
    }

    private func save() {
        entries = Self.pruned(entries)
        let entries = entries, location = location, previous = persistence
        persistence = Task.detached(priority: .utility) {
            await previous?.value
            guard let data = try? JSONEncoder().encode(entries) else { return }
            try? FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: location, options: .atomic)
        }
    }

    /// nil: no verdict. `.some(nil)`: the link works. `.some(reason)`: broken.
    nonisolated static func probe(_ url: URL, session: URLSession) async -> String?? {
        func request(_ method: String) -> URLRequest {
            var request = URLRequest(url: url)
            request.httpMethod = method
            if method == "GET" { request.setValue("bytes=0-0", forHTTPHeaderField: "Range") }
            return request
        }
        do {
            var (bytes, response) = try await session.bytes(for: request("HEAD"))
            bytes.task.cancel()
            var code = (response as? HTTPURLResponse)?.statusCode ?? 200
            // Some servers refuse HEAD; ask for one byte instead.
            if code >= 400 {
                (bytes, response) = try await session.bytes(for: request("GET"))
                bytes.task.cancel()
                code = (response as? HTTPURLResponse)?.statusCode ?? 200
            }
            switch code {
            case ..<400, 401, 403: return .some(nil) // The page exists; access is restricted.
            case 429: return nil
            case 404: return .some("Not found (404)")
            case 410: return .some("Gone (410)")
            default: return .some("Error \(code)")
            }
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .cancelled, .internationalRoamingOff, .dataNotAllowed: return nil
            case .timedOut: return .some("Timed out")
            case .cannotFindHost, .dnsLookupFailed: return .some("Server not found")
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid,
                 .serverCertificateHasUnknownRoot: return .some("Certificate error")
            default: return .some("Unreachable")
            }
        } catch {
            return .some("Unreachable")
        }
    }
}

/// Readable text for summaries, extracted off the main thread (NSAttributedString's HTML import must run on it).
enum ReadableText {
    static func fromMarkdown(_ source: String, mdx: Bool) -> String {
        fromHTML(MarkdownHTML.render(source, mdx: mdx).body)
    }

    static func fromHTML(_ html: String) -> String {
        var text = html
        for pattern in ["(?is)<(script|style|noscript|template)\\b.*?</\\1>", "(?s)<!--.*?-->"] {
            text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        text = text.replacingOccurrences(of: "(?i)<(br|/p|/div|/li|/h[1-6]|/tr)\\b[^>]*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " "]
        for (entity, character) in entities { text = text.replacingOccurrences(of: entity, with: character) }
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        return text.replacingOccurrences(of: "\\s*\\n\\s*", with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Destinations to offer when fixing a broken link, closest first.
enum LinkSuggestions {
    static func ranked(_ candidates: [String], near target: String, limit: Int = 5) -> [String] {
        let target = target.lowercased()
        let scored: [(candidate: String, score: Int)] = Set(candidates).map { ($0, distance($0.lowercased(), target)) }
        let sorted = scored.sorted { $0.score != $1.score ? $0.score < $1.score : $0.candidate < $1.candidate }
        return sorted.prefix(limit).map(\.candidate)
    }

    /// Markdown files beside a missing file, written with the original destination's folder part. Reads the disk.
    static func files(replacing destination: String, missing url: URL) -> [String] {
        let folder = url.deletingLastPathComponent()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let prefix = destination.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let directory = prefix.lastIndex(of: "/").map { String(prefix[...$0]) } ?? ""
        let markdown = names.filter { ["md", "markdown", "mdx"].contains(($0 as NSString).pathExtension.lowercased()) }
        return ranked(markdown, near: url.lastPathComponent).map {
            directory + ($0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0)
        }
    }

    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}
