import Foundation
import CryptoKit

extension Data {
    /// The SHA-256 digest as lowercase hex.
    var sha256Hex: String { SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined() }
}

/// Rendered Mermaid diagrams on disk, one file per digest of source, theme and renderer: `<digest>.pdf` for a diagram,
/// `<digest>.error` for Mermaid's message about one it cannot parse. Every file can be rebuilt, so the system may purge them.
/// Reads, writes and hashing run on a utility queue, never on the main thread.
final class DiagramDiskCache: @unchecked Sendable {
    enum Entry: Sendable {
        case pdf(Data)
        case error(String)
    }

    /// Bumped when Markify's rendering changes what a cached diagram looks like.
    static let renderVersion = 1

    let directory: URL
    /// The bytes the cache keeps; the least recently used files go first.
    let limit: Int
    private let bundle: Bundle
    private let queue = DispatchQueue(label: "Markify.DiagramDiskCache", qos: .utility)
    // Touched only on `queue`.
    private var total: Int?
    private var cachedRendererVersion: String?

    /// The user's cache, or a throwaway folder under tests so they never share or pollute it.
    static let standard: DiagramDiskCache = {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return temporary() }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return DiagramDiskCache(directory: caches.appendingPathComponent(Bundle.main.bundleIdentifier ?? "Markify").appendingPathComponent("Mermaid"))
    }()

    static func temporary(limit: Int = 50_000_000) -> DiagramDiskCache {
        DiagramDiskCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent("MarkifyMermaid-" + UUID().uuidString), limit: limit)
    }

    init(directory: URL, limit: Int = 50_000_000, bundle: Bundle = .main) {
        self.directory = directory
        self.limit = limit
        self.bundle = bundle
        queue.async { self.prune() }
    }

    /// The file name for a diagram: a change to its source, theme, the bundled Mermaid or `renderVersion` gives a new one.
    static func digest(of source: String, dark: Bool, rendererVersion: String) -> String {
        Data([source, dark ? "dark" : "light", rendererVersion, String(renderVersion)].joined(separator: "\0").utf8).sha256Hex
    }

    /// The diagram's digest and what the cache holds for it.
    func load(_ source: String, dark: Bool) async -> (digest: String, entry: Entry?) {
        await withCheckedContinuation { continuation in
            queue.async {
                let digest = Self.digest(of: source, dark: dark, rendererVersion: self.rendererVersion())
                continuation.resume(returning: (digest, self.read(digest)))
            }
        }
    }

    func store(_ entry: Entry, for digest: String) {
        queue.async {
            try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            let data: Data
            switch entry {
            case .pdf(let pdf): data = pdf
            case .error(let message): data = Data(message.utf8)
            }
            guard (try? data.write(to: self.file(digest, entry), options: .atomic)) != nil else { return }
            self.total = (self.total ?? 0) + data.count
            if self.total ?? 0 > self.limit { self.prune() }
        }
    }

    /// Deletes a diagram's files, as when one cannot be read.
    func remove(_ digest: String) {
        queue.async {
            for name in ["\(digest).pdf", "\(digest).error"] { try? FileManager.default.removeItem(at: self.directory.appendingPathComponent(name)) }
            self.total = nil
        }
    }

    /// Waits for the reads and writes queued so far.
    func flush() async {
        await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
    }

    private func file(_ digest: String, _ entry: Entry) -> URL {
        if case .pdf = entry { return directory.appendingPathComponent("\(digest).pdf") }
        return directory.appendingPathComponent("\(digest).error")
    }

    private func read(_ digest: String) -> Entry? {
        let pdf = directory.appendingPathComponent("\(digest).pdf")
        let error = directory.appendingPathComponent("\(digest).error")
        let entry: (URL, Entry)?
        if let data = try? Data(contentsOf: pdf) { entry = (pdf, .pdf(data)) }
        else if let data = try? Data(contentsOf: error), let message = String(data: data, encoding: .utf8) { entry = (error, .error(message)) }
        else { entry = nil }
        // The modification date records use, so pruning removes the least recently used files.
        if let (url, _) = entry { try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path) }
        return entry?.1
    }

    /// The bundled Mermaid and its page, hashed once: an update renders every diagram again.
    private func rendererVersion() -> String {
        if let cachedRendererVersion { return cachedRendererVersion }
        var data = Data()
        for (name, ext) in [("mermaid.min", "js"), ("mermaid", "html")] {
            if let url = bundle.url(forResource: name, withExtension: ext), let contents = try? Data(contentsOf: url) { data.append(contents) }
        }
        let version = data.sha256Hex
        cachedRendererVersion = version
        return version
    }

    /// Deletes the least recently used files until the cache is within three quarters of its limit, so pruning runs rarely.
    private func prune() {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys, options: .skipsHiddenFiles) else {
            total = 0
            return
        }
        var files = urls.compactMap { url -> (url: URL, date: Date, size: Int)? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, values.contentModificationDate ?? .distantPast, values.fileSize ?? 0)
        }
        var size = files.reduce(0) { $0 + $1.size }
        if size > limit {
            files.sort { $0.date < $1.date }
            for file in files where size > limit * 3 / 4 {
                guard (try? FileManager.default.removeItem(at: file.url)) != nil else { continue }
                size -= file.size
            }
        }
        total = size
    }
}
