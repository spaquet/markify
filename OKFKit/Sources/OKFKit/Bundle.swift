import Foundation
import Darwin

/// One Markdown file in a bundle.
public struct OKFDocument: Identifiable, Sendable {
    public enum Kind: Sendable { case concept, index, log }

    public let url: URL
    /// Bundle-absolute path, such as `/tables/orders.md`.
    public let path: String
    public let kind: Kind
    public let source: String
    /// Nil when the file has no frontmatter or it failed to parse.
    public let concept: OKFConcept?
    public let parseError: OKFConcept.ParseError?
    public let hasFrontmatter: Bool
    public let links: [OKFLink]
    /// Standardized paths of the files the links point at, parallel to `links`; nil for external links.
    public let targets: [String?]
    /// Path-valued frontmatter fields, and the standardized paths they resolve to, in parallel.
    public let references: [OKFReference]
    public let referenceTargets: [String?]

    public var id: String { path }
    /// The concept ID: the bundle path without the leading `/` and the `.md` suffix (§2).
    public var conceptID: String { String(path.dropFirst().dropLast(3)) }
    public var title: String {
        if let title = concept?.title, !title.isEmpty { return title }
        return url.deletingPathExtension().lastPathComponent
    }

    init(url: URL, path: String, source: String, root: URL) {
        self.url = url
        self.path = path
        self.source = source
        switch url.lastPathComponent.lowercased() {
        case "index.md": kind = .index
        case "log.md": kind = .log
        default: kind = .concept
        }
        let block = FrontmatterBlock.locate(in: source)
        hasFrontmatter = block != nil
        if let block {
            do { concept = try OKFConcept(yaml: block.yaml); parseError = nil } catch { concept = nil; parseError = error }
        } else {
            concept = nil
            parseError = nil
        }
        let body = block.map { (source as NSString).substring(from: $0.blockRange.upperBound) } ?? source
        links = OKFLinks.extract(from: body)
        targets = links.map { OKFLinks.resolve($0.target, from: url, bundleRoot: root).map(OKFBundle.key) }
        references = concept?.references ?? []
        referenceTargets = references.map { OKFLinks.resolve($0.target, from: url, bundleRoot: root).map(OKFBundle.key) }
    }
}

/// A directory tree of OKF documents (§3).
public struct OKFBundle: Sendable {
    public let root: URL
    /// `okf_version` from the bundle-root `index.md`, if declared.
    public let okfVersion: String?
    public let documents: [OKFDocument]
    /// True when the scan stopped at its file limit.
    public let truncated: Bool

    /// Reads every `.md` file under `root`, skipping hidden files and packages.
    public static func load(root: URL, limit: Int = 5000, maximumBytes: Int = 50_000_000) -> OKFBundle {
        let root = root.standardizedFileURL
        var documents: [OKFDocument] = []
        var truncated = false
        var bytes = 0
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                                        options: [.skipsHiddenFiles, .skipsPackageDescendants])
        while let url = enumerator?.nextObject() as? URL {
            guard !Task.isCancelled else { truncated = true; break }
            guard url.pathExtension.lowercased() == "md",
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            guard documents.count < limit else { truncated = true; break }
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size <= maximumBytes - bytes else { truncated = true; break }
            guard let source = boundedSource(at: url, maximumBytes: maximumBytes - bytes),
                  let path = OKFLinks.bundlePath(of: url, root: root) else { continue }
            guard source.utf8.count <= maximumBytes - bytes else { truncated = true; break }
            bytes += source.utf8.count
            documents.append(OKFDocument(url: url.standardizedFileURL, path: path, source: source, root: root))
        }
        documents.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        return OKFBundle(root: root, okfVersion: declaredVersion(at: root), documents: documents, truncated: truncated)
    }

    /// The bundle root for a file: the nearest ancestor whose `index.md` declares `okf_version`,
    /// else `boundary` when it contains the file, else the file's own folder.
    public static func findRoot(for file: URL, boundary: URL? = nil) -> URL {
        let folder = file.deletingLastPathComponent().standardizedFileURL
        let limit = boundary.map { key($0) }
        var directory = folder
        while true {
            guard !Task.isCancelled else { return folder }
            if declaredVersion(at: directory) != nil { return directory }
            if key(directory) == limit || directory.path == "/" { break }
            directory = directory.deletingLastPathComponent().standardizedFileURL
        }
        if let boundary, contains(boundary, file) { return boundary.standardizedFileURL }
        return folder
    }

    /// `okf_version` from a directory's `index.md` frontmatter.
    public static func declaredVersion(at directory: URL) -> String? {
        let index = directory.appendingPathComponent("index.md")
        guard let source = boundedSource(at: index, maximumBytes: 2_000_000),
              case .success(let concept)? = OKFConcept.parse(source: source) else { return nil }
        return concept.okfVersion
    }

    /// This package is independent of the editor model; bound reads even if a file grows during scanning.
    private static func boundedSource(at url: URL, maximumBytes: Int) -> String? {
        guard maximumBytes >= 0, !Task.isCancelled else { return nil }
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size <= maximumBytes else { return nil }
        var data = Data()
        do {
            while let chunk = try handle.read(upToCount: min(65_536, maximumBytes - data.count + 1)), !chunk.isEmpty {
                guard !Task.isCancelled, chunk.count <= maximumBytes - data.count else { return nil }
                data.append(chunk)
            }
        } catch { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// True when `url` sits inside `directory`.
    public static func contains(_ directory: URL, _ url: URL) -> Bool {
        let base = key(directory)
        return key(url).hasPrefix(base.hasSuffix("/") ? base : base + "/")
    }

    public var concepts: [OKFDocument] { documents.filter { $0.kind == .concept } }

    public func document(for url: URL) -> OKFDocument? {
        let target = Self.key(url)
        return documents.first { Self.key($0.url) == target }
    }

    /// Documents linking to `url` from their body or a path-valued field such as `sources[].resource`, in path order.
    public func backlinks(to url: URL) -> [OKFDocument] {
        let target = Self.key(url)
        return documents.filter { ($0.targets.contains(target) || $0.referenceTargets.contains(target)) && Self.key($0.url) != target }
    }

    /// Path-valued fields pointing at files that do not exist.
    public func brokenReferences(in document: OKFDocument) -> [OKFReference] {
        zip(document.references, document.referenceTargets).compactMap { reference, target in
            guard let target, !FileManager.default.fileExists(atPath: target) else { return nil }
            return reference
        }
    }

    /// Concept types in use, most used first.
    public var types: [String] {
        let counts = Dictionary(grouping: concepts.compactMap { $0.concept?.type }.filter { !$0.isEmpty }, by: { $0 }).mapValues(\.count)
        return counts.keys.sorted { counts[$0]! != counts[$1]! ? counts[$0]! > counts[$1]! : $0 < $1 }
    }

    /// Tags in use, alphabetically, for a tag view synthesized from frontmatter (§3.1).
    public var tags: [String] {
        Set(concepts.flatMap { $0.concept?.tags ?? [] }).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Links from a document that point at bundle files which do not exist.
    public func brokenLinks(in document: OKFDocument) -> [OKFLink] {
        zip(document.links, document.targets).compactMap { link, target in
            guard let target, !FileManager.default.fileExists(atPath: target) else { return nil }
            return link
        }
    }

    /// Documents directly inside a directory, and its immediate subdirectories that hold Markdown.
    public func contents(of directory: URL) -> (documents: [OKFDocument], subdirectories: [URL]) {
        let base = Self.key(directory)
        let prefix = base.hasSuffix("/") ? base : base + "/"
        var documents: [OKFDocument] = []
        var subdirectories = Set<String>()
        for document in self.documents {
            let path = Self.key(document.url)
            guard path.hasPrefix(prefix) else { continue }
            let rest = path.dropFirst(prefix.count)
            if let slash = rest.firstIndex(of: "/") { subdirectories.insert(prefix + rest[..<slash]) } else { documents.append(document) }
        }
        return (documents, subdirectories.sorted().map { URL(fileURLWithPath: $0, isDirectory: true) })
    }

    /// A comparable path: standardized with symlinks resolved, so `/private/var` and `/var` agree.
    public static func key(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
