import AppKit
import CoreSpotlight
import MarkifyMarkdown
import OKFKit
import Observation
import UniformTypeIdentifiers

struct SearchFolder: Codable, Identifiable, Equatable, Sendable {
    var path: String
    var bookmark: Data
    var kind: String
    var id: String { SearchNote.identifier(URL(fileURLWithPath: path)) }
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

struct SearchOptions: Codable, Equatable, Sendable {
    var extensions = ["md", "markdown", "mdx"]
    var metadata = true
    var headings = true
    var related = true
    var skippedFolders = ".git, node_modules, _build"
    var defaultScope = "library"
    var paused = false
    static func load() -> Self {
        UserDefaults.standard.data(forKey: "searchOptions").flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? Self()
    }
}

struct SearchNote: Identifiable, Sendable {
    var url: URL
    var title: String
    var description: String
    var type: String?
    var tags: [String]
    var roots: [String]
    var scopes: [String]
    var modified: Date
    var id: String { Self.identifier(url) }

    static func identifier(_ url: URL) -> String {
        Data(url.standardizedFileURL.resolvingSymlinksInPath().path.utf8).sha256Hex
    }
    static func contains(_ root: URL, _ url: URL) -> Bool {
        let parts = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        return url.standardizedFileURL.resolvingSymlinksInPath().pathComponents.starts(with: parts)
    }
    static func searchableText(_ model: MarkdownModel) -> String {
        let text = NSMutableString(string: model.source)
        // Mask syntax using the same UTF-16 model offsets as the editor; leave code, math and MDX bodies searchable.
        var ranges = model.spans.flatMap(\.markers)
        ranges += model.spans.filter { $0.kind == .frontmatter }.map(\.range)
        for range in ranges where NSMaxRange(range) <= text.length {
            text.replaceCharacters(in: range, with: String(repeating: " ", count: range.length))
        }
        return (text as String).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    static func read(_ url: URL, roots: [SearchFolder], options: SearchOptions) throws -> (Self, String) {
        let source = try String(contentsOf: url, encoding: .utf8)
        let model = MarkdownModel(source, mdx: url.pathExtension.lowercased() == "mdx")
        let metadata = options.metadata ? FrontmatterBlock.locate(in: source).flatMap { try? OKFConcept(yaml: $0.yaml) } : nil
        let headings = DocumentHeading.extract(from: model)
        let text = searchableText(model)
        let title = metadata?.title ?? headings.first?.title ?? url.deletingPathExtension().lastPathComponent
        let memberships = roots.filter { contains(URL(fileURLWithPath: $0.path), url) }
        var scopes = Set(memberships.map(\.id))
        for root in memberships {
            var folder = url.deletingLastPathComponent()
            let boundary = URL(fileURLWithPath: root.path)
            while contains(boundary, folder) {
                scopes.insert(identifier(folder))
                if folder.standardizedFileURL == boundary.standardizedFileURL { break }
                folder.deleteLastPathComponent()
            }
        }
        let note = Self(url: url, title: title, description: metadata?.description ?? String(text.prefix(220)),
                        type: metadata?.type, tags: metadata?.tags ?? [], roots: memberships.map(\.id), scopes: Array(scopes).sorted(),
                        modified: try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast)
        let paths = memberships.map { LibraryNote.path(of: url, in: URL(fileURLWithPath: $0.path)) }
        let context = options.headings ? headings.map(\.title) : []
        return (note, ([text] + paths + [url.lastPathComponent] + context).joined(separator: "\n"))
    }

    func item(text: String, domain: String = "markifynotes") -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .plainText)
        attributes.title = title
        attributes.displayName = title
        attributes.contentDescription = description
        attributes.textContent = text
        attributes.keywords = tags + [type].compactMap { $0 }
        attributes.contentURL = url
        attributes.relatedUniqueIdentifier = url.absoluteString
        attributes.contentModificationDate = modified
        attributes.setValue(scopes as NSArray, forCustomKey: Self.scopeKey)
        attributes.setValue(type as NSString?, forCustomKey: Self.typeKey)
        attributes.setValue(tags as NSArray, forCustomKey: Self.tagKey)
        let item = CSSearchableItem(uniqueIdentifier: id, domainIdentifier: domain, attributeSet: attributes)
        item.expirationDate = .distantFuture
        return item
    }
    static var scopeKey: CSCustomAttributeKey { CSCustomAttributeKey(keyName: "markifyScopes", searchable: true, searchableByDefault: false, unique: false, multiValued: true)! }
    static var typeKey: CSCustomAttributeKey { CSCustomAttributeKey(keyName: "markifyType", searchable: true, searchableByDefault: true, unique: false, multiValued: false)! }
    static var tagKey: CSCustomAttributeKey { CSCustomAttributeKey(keyName: "markifyTags", searchable: true, searchableByDefault: true, unique: false, multiValued: true)! }
}

struct SearchMatch: Identifiable, Sendable {
    var note: SearchNote
    var snippet: String
    var ranges: [NSRange]
    var sourceRange: NSRange?
    var line: Int?
    var count: Int
    var heading: String?
    var metadataMatch: Bool
    var id: String { note.id }
    var related: Bool { sourceRange == nil && !metadataMatch }

    static func literalRanges(in source: String, query: String) -> [NSRange] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let range = NSRange(location: 0, length: (source as NSString).length)
        func matches(_ pattern: String) -> [NSRange] {
            (try? NSRegularExpression(pattern: pattern, options: .caseInsensitive))?.matches(in: source, range: range).map(\.range) ?? []
        }
        let phrase = matches(NSRegularExpression.escapedPattern(for: query))
        if !phrase.isEmpty { return phrase }
        // Spotlight also returns lexical matches whose words aren't a contiguous phrase.
        let words = query.components(separatedBy: .alphanumerics.inverted).filter { !$0.isEmpty }
        guard words.count > 1 else { return [] }
        let alternatives = Array(Set(words)).map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        return matches("(?<![\\p{L}\\p{N}_])(?:\(alternatives))(?![\\p{L}\\p{N}_])")
    }

    static func make(note: SearchNote, source: String, query: String, headings: Bool) -> Self {
        let text = source as NSString
        let hits = Self.literalRanges(in: source, query: query)
        let first = hits.first
        var snippet = note.description
        var highlights: [NSRange] = []
        var line: Int?
        var heading: String?
        if let first {
            let lineRange = text.lineRange(for: first)
            let start = max(lineRange.location, first.location - 70)
            let end = min(NSMaxRange(lineRange), max(NSMaxRange(first), start + 230))
            let window = text.rangeOfComposedCharacterSequences(for: NSRange(location: start, length: end - start))
            snippet = text.substring(with: window).trimmingCharacters(in: .newlines)
            highlights = hits.filter { $0.location >= window.location && NSMaxRange($0) <= window.location + (snippet as NSString).length }
                .map { NSRange(location: $0.location - window.location, length: $0.length) }
            line = text.substring(to: first.location).filter { $0 == "\n" }.count + 1
            if headings {
                heading = DocumentHeading.extract(from: MarkdownModel(source, mdx: note.url.pathExtension.lowercased() == "mdx"))
                    .last { $0.range.location <= first.location }?.title
            }
        }
        let metadataMatch = ([note.title, note.url.path, note.description] + note.tags + [note.type].compactMap { $0 })
            .contains { $0.localizedCaseInsensitiveContains(query) }
        return Self(note: note, snippet: snippet, ranges: highlights, sourceRange: first, line: line, count: hits.count,
                    heading: heading, metadataMatch: metadataMatch)
    }
}

struct SearchSnapshot: Sendable {
    var folders: [SearchFolder] = []
    var notes: [SearchNote] = []
    var subfolders: [URL] = []
    var status: [String: String] = [:]
}

/// File enumeration, Markdown parsing, reading results, and index maintenance all run on this actor, away from MainActor.
actor SpotlightWorker {
    private let index: CSSearchableIndex
    private let domain: String
    private let persistenceKey: String?
    private var fingerprints: [String: String]
    private struct CachedNote {
        let stamp: FileStamp
        let configuration: String
        let note: SearchNote
        let fingerprint: String
    }
    private var cachedNotes: [String: CachedNote] = [:]

    init(name: String = "com.stephanepaquet.Markify.NoteSearch", domain: String = "markifynotes", persistenceKey: String? = "searchFingerprints") {
        index = CSSearchableIndex(name: name)
        self.domain = domain
        self.persistenceKey = persistenceKey
        fingerprints = persistenceKey.flatMap { UserDefaults.standard.dictionary(forKey: $0) as? [String: String] } ?? [:]
    }

    func refresh(folders: [SearchFolder], options: SearchOptions, rebuild: Bool,
                 progress: @Sendable (SearchSnapshot) async -> Void) async throws -> SearchSnapshot {
        if rebuild || options.paused {
            try await index.deleteSearchableItems(withDomainIdentifiers: [domain])
            fingerprints = [:]
            cachedNotes = [:]
            persist()
        }
        var snapshot = SearchSnapshot(folders: folders)
        guard !options.paused else {
            snapshot.status = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, "Paused") })
            return snapshot
        }
        var accessible: [SearchFolder] = []
        var accesses: [URL] = []
        defer { accesses.forEach { $0.stopAccessingSecurityScopedResource() } }
        for folder in folders {
            var stale = false
            let url: URL?
            if folder.bookmark.isEmpty { url = URL(fileURLWithPath: folder.path) }
            else { url = try? URL(resolvingBookmarkData: folder.bookmark, options: .withSecurityScope, bookmarkDataIsStale: &stale) }
            guard let url, !stale else { snapshot.status[folder.id] = "Access expired"; continue }
            if url.startAccessingSecurityScopedResource() { accesses.append(url) }
            guard FileManager.default.isReadableFile(atPath: url.path) else { snapshot.status[folder.id] = "Access needed"; continue }
            accessible.append(folder)
            snapshot.status[folder.id] = "Indexing…"
        }
        await progress(snapshot)
        var seen = Set<String>()
        var updates: [CSSearchableItem] = []
        var nextFingerprints = fingerprints
        var failed = false
        let skipped = Set(options.skippedFolders.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        let optionKey = String(data: try JSONEncoder().encode(options), encoding: .utf8) ?? ""
        let configuration = optionKey + accessible.map(\.path).sorted().joined(separator: "\n")
        var lastProgress = ContinuousClock.now
        for folder in accessible {
            let root = URL(fileURLWithPath: folder.path)
            var scanFailed = false
            guard let enumerator = FileManager.default.enumerator(at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in scanFailed = true; return true }) else {
                snapshot.status[folder.id] = "Unable to read folder"; failed = true; continue
            }
            var count = 0
            while let url = enumerator.nextObject() as? URL {
                try Task.checkCancellation()
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
                // Never follow a symlink beyond the grant, or import the same physical note twice.
                if values?.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                if values?.isDirectory == true {
                    if skipped.contains(url.lastPathComponent) { enumerator.skipDescendants() }
                    else { snapshot.subfolders.append(url) }
                    continue
                }
                guard values?.isRegularFile == true, options.extensions.contains(url.pathExtension.lowercased()) else { continue }
                let id = SearchNote.identifier(url)
                count += 1
                guard seen.insert(id).inserted else { continue }
                do {
                    let stamp = FileStamp(at: url)
                    if let cached = cachedNotes[id], cached.stamp == stamp, cached.configuration == configuration,
                       fingerprints[id] == cached.fingerprint {
                        snapshot.notes.append(cached.note)
                        nextFingerprints[id] = cached.fingerprint
                        continue
                    }
                    let (note, text) = try SearchNote.read(url, roots: accessible, options: options)
                    snapshot.notes.append(note)
                    let fingerprint = Data((text + note.title + note.description + note.scopes.joined() + note.tags.joined() + (note.type ?? "") + optionKey + note.modified.description).utf8).sha256Hex
                    if let stamp, FileStamp(at: url) == stamp {
                        cachedNotes[id] = CachedNote(stamp: stamp, configuration: configuration, note: note, fingerprint: fingerprint)
                    }
                    if fingerprints[id] != fingerprint {
                        updates.append(note.item(text: text, domain: domain))
                        nextFingerprints[id] = fingerprint
                    }
                    if updates.count >= 100 {
                        try await index.indexSearchableItems(updates)
                        fingerprints.merge(nextFingerprints) { _, new in new }; persist(); updates.removeAll()
                    }
                    if ContinuousClock.now - lastProgress >= .milliseconds(250) {
                        await progress(snapshot)
                        lastProgress = .now
                    }
                } catch is CancellationError { throw CancellationError() }
                catch { scanFailed = true }
            }
            snapshot.status[folder.id] = scanFailed ? "Some notes could not be read" : "\(count) notes"
            failed = failed || scanFailed
        }
        if !updates.isEmpty { try await index.indexSearchableItems(updates) }
        try Task.checkCancellation()
        // An incomplete scan must not delete records for files that temporarily couldn't be read.
        if !failed {
            let removed = Set(fingerprints.keys).subtracting(snapshot.notes.map(\.id))
            if !removed.isEmpty { try await index.deleteSearchableItems(withIdentifiers: Array(removed)) }
            nextFingerprints = nextFingerprints.filter { !removed.contains($0.key) }
            cachedNotes = cachedNotes.filter { seen.contains($0.key) }
        }
        fingerprints = nextFingerprints; persist()
        snapshot.subfolders = Array(Set(snapshot.subfolders)).sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        return snapshot
    }
    private func persist() { if let persistenceKey { UserDefaults.standard.set(fingerprints, forKey: persistenceKey) } }
    func delete() async throws {
        try await index.deleteSearchableItems(withDomainIdentifiers: [domain])
        fingerprints = [:]; cachedNotes = [:]; persist()
    }
    nonisolated func matches(_ notes: [SearchNote], query: String, options: SearchOptions) -> [SearchMatch] {
        var matches: [SearchMatch] = []
        for note in notes {
            guard !Task.isCancelled else { break }
            guard let source = try? String(contentsOf: note.url, encoding: .utf8) else { continue }
            matches.append(SearchMatch.make(note: note, source: source, query: query, headings: options.headings))
        }
        return matches
    }
}

// Spotlight supplies an immutable callback, invoked once on MainActor after the queued reindex finishes.
private final class SpotlightAcknowledgement: @unchecked Sendable {
    let call: () -> Void
    init(_ call: @escaping () -> Void) { self.call = call }
}

@MainActor @Observable final class LibrarySearch: NSObject, CSSearchableIndexDelegate {
    static let shared = LibrarySearch()
    var options = SearchOptions.load()
    var snapshot = SearchSnapshot()
    var indexing = false
    var indexedCount = 0
    var message = "Waiting for Spotlight indexing"
    var revision = 0
    var recents: [String] = UserDefaults.standard.stringArray(forKey: "recentLibrarySearches") ?? []
    @ObservationIgnored private let worker = SpotlightWorker()
    @ObservationIgnored private let index = CSSearchableIndex(name: "com.stephanepaquet.Markify.NoteSearch")
    @ObservationIgnored private var job: Task<Void, Never>?
    @ObservationIgnored private var requestVersion = 0
    @ObservationIgnored private var requested = false
    @ObservationIgnored private var rebuildRequested = false
    @ObservationIgnored private var watchers: [BundleWatcher] = []
    @ObservationIgnored private var configuration = Data()
    @ObservationIgnored private var rootAccesses: [URL] = []
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var acknowledgements: [() -> Void] = []

    func start() {
        guard observer == nil else { return }
        index.indexDelegate = self
        CSUserQuery.prepare()
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.configurationChanged() }
        }
        refresh()
    }
    private func configurationChanged() {
        let folders = configuredFolders()
        let current = (try? JSONEncoder().encode(folders)) ?? Data()
        if current != configuration { refresh() }
    }
    func configuredFolders() -> [SearchFolder] {
        let defaults = UserDefaults.standard
        var folders = defaults.data(forKey: "searchFolders").flatMap { try? JSONDecoder().decode([SearchFolder].self, from: $0) } ?? []
        let library = defaults.data(forKey: "libraryBookmark") ?? Data()
        var stale = false
        let libraryURL = library.isEmpty ? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("Markify")
            : try? URL(resolvingBookmarkData: library, options: .withSecurityScope, bookmarkDataIsStale: &stale)
        if let libraryURL { folders.insert(SearchFolder(path: libraryURL.path, bookmark: library, kind: "Library"), at: 0) }
        for bookmark in defaults.array(forKey: "okfBundleBookmarks") as? [Data] ?? [] {
            if let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &stale) {
                folders.append(SearchFolder(path: url.path, bookmark: bookmark, kind: "OKF bundle"))
            }
        }
        let excluded = Set(defaults.stringArray(forKey: "searchExcludedRoots") ?? [])
        var seen = Set<String>()
        return folders.filter { !excluded.contains($0.id) && seen.insert($0.id).inserted }
    }
    func includeBundle(_ url: URL) {
        guard !configuredFolders().contains(where: { $0.id == SearchNote.identifier(url) }),
              let bookmark = try? url.bookmarkData(options: .withSecurityScope) else { return }
        storeFolder(SearchFolder(path: url.path, bookmark: bookmark, kind: "OKF bundle"))
    }
    func chooseFolder(replacing folder: SearchFolder? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.message = folder == nil ? "Choose a folder of Markdown notes to search." : "Grant access to \(folder!.name)."
        if let folder { panel.directoryURL = URL(fileURLWithPath: folder.path) }
        guard panel.runModal() == .OK, let url = panel.url,
              let bookmark = try? url.bookmarkData(options: .withSecurityScope) else { return }
        if let folder, folder.id != SearchNote.identifier(url) {
            NSApp.presentError(NSError(domain: "MarkifySearch", code: 1, userInfo: [NSLocalizedDescriptionKey: "Choose the same folder to renew its access."]))
            return
        }
        if folder?.kind == "Library" { UserDefaults.standard.set(bookmark, forKey: "libraryBookmark") }
        else {
            if folder?.kind == "OKF bundle" {
                var bookmarks = UserDefaults.standard.array(forKey: "okfBundleBookmarks") as? [Data] ?? []
                bookmarks.removeAll { $0 == folder?.bookmark }
                bookmarks.append(bookmark)
                UserDefaults.standard.set(bookmarks, forKey: "okfBundleBookmarks")
            }
            storeFolder(SearchFolder(path: url.path, bookmark: bookmark, kind: folder?.kind ?? "Project"))
        }
        var excluded = UserDefaults.standard.stringArray(forKey: "searchExcludedRoots") ?? []
        excluded.removeAll { $0 == SearchNote.identifier(url) }
        UserDefaults.standard.set(excluded, forKey: "searchExcludedRoots")
        refresh()
    }
    private func storeFolder(_ folder: SearchFolder) {
        var folders = UserDefaults.standard.data(forKey: "searchFolders").flatMap { try? JSONDecoder().decode([SearchFolder].self, from: $0) } ?? []
        folders.removeAll { $0.id == folder.id }; folders.append(folder)
        UserDefaults.standard.set(try? JSONEncoder().encode(folders), forKey: "searchFolders")
        refresh()
    }
    func remove(_ folder: SearchFolder) {
        var excluded = UserDefaults.standard.stringArray(forKey: "searchExcludedRoots") ?? []
        excluded.append(folder.id)
        UserDefaults.standard.set(excluded, forKey: "searchExcludedRoots")
        // Hide immediately; the worker updates memberships and deletes unowned items asynchronously.
        snapshot.folders.removeAll { $0.id == folder.id }
        snapshot.notes = snapshot.notes.compactMap { note in
            var note = note
            note.roots.removeAll { $0 == folder.id }
            note.scopes.removeAll { $0 == folder.id }
            return note.roots.isEmpty ? nil : note
        }
        revision += 1
        refresh()
    }
    func saveOptions() {
        UserDefaults.standard.set(try? JSONEncoder().encode(options), forKey: "searchOptions")
        refresh()
    }
    func refresh(rebuild: Bool = false) {
        requestVersion += 1
        requested = true; rebuildRequested = rebuildRequested || rebuild
        guard job == nil else { return }
        job = Task { [self] in
            var succeeded = false
            while requested && !Task.isCancelled {
                requested = false
                let version = requestVersion
                let rebuilding = rebuildRequested; rebuildRequested = false
                let folders = configuredFolders()
                let nextConfiguration = (try? JSONEncoder().encode(folders)) ?? Data()
                if configuration != nextConfiguration {
                    rootAccesses.forEach { $0.stopAccessingSecurityScopedResource() }
                    rootAccesses = folders.compactMap { folder in
                        guard !folder.bookmark.isEmpty else { return nil }
                        var stale = false
                        guard let url = try? URL(resolvingBookmarkData: folder.bookmark, options: .withSecurityScope, bookmarkDataIsStale: &stale),
                              !stale, url.startAccessingSecurityScopedResource() else { return nil }
                        return url
                    }
                }
                configuration = nextConfiguration
                watchers.forEach { $0.stop() }
                watchers = folders.map { folder in
                    let watcher = BundleWatcher()
                    watcher.watch(URL(fileURLWithPath: folder.path)) { [weak self] in self?.refresh() }
                    return watcher
                }
                indexing = true; indexedCount = 0; message = rebuilding ? "Rebuilding Spotlight index…" : "Indexing · more results may appear"
                do {
                    let result = try await worker.refresh(folders: folders, options: options, rebuild: rebuilding) { [weak self] partial in
                        await self?.progress(partial, version: version)
                    }
                    guard version == requestVersion else { indexing = false; continue }
                    snapshot = result
                    let needsAttention = result.status.values.contains { !$0.hasSuffix("notes") }
                    message = options.paused ? "Search index deleted · rebuild to resume" : needsAttention ? "Some folders need attention · see Search Settings" : "Spotlight · \(result.notes.count) notes submitted"
                    revision += 1
                    succeeded = true
                } catch is CancellationError { succeeded = false; message = "Indexing cancelled · rebuild to finish" }
                catch { succeeded = false; message = "Spotlight indexing failed: \(error.localizedDescription)" }
                indexing = false
            }
            job = nil
            if requested { refresh(); return }
            if succeeded { acknowledgements.forEach { $0() }; acknowledgements.removeAll() }
        }
    }
    private func progress(_ partial: SearchSnapshot, version: Int) {
        guard version == requestVersion else { return }
        indexedCount = partial.notes.count
        let usableRoots = Set(partial.status.filter { !$0.value.contains("Access") && !$0.value.contains("Unable") }.keys)
        let currentIDs = Set(partial.notes.map(\.id))
        let retained = snapshot.notes.filter { note in !currentIDs.contains(note.id) && note.roots.contains(where: usableRoots.contains) }
        snapshot = partial
        snapshot.notes += retained
        revision += 1
    }
    func cancel() { requested = false; rebuildRequested = false; job?.cancel() }
    func rebuild() { options.paused = false; saveOptions(); refresh(rebuild: true) }
    func deleteIndex() {
        options.paused = true
        saveOptions()
        snapshot.notes = []
    }
    func remember(_ query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        recents.removeAll { $0 == query }; recents.insert(query, at: 0); recents = Array(recents.prefix(8))
        UserDefaults.standard.set(recents, forKey: "recentLibrarySearches")
    }
    func enrich(_ notes: [SearchNote], query: String) async -> [SearchMatch] {
        let worker = worker, options = options
        let work = Task.detached(priority: .userInitiated) { worker.matches(notes, query: query, options: options) }
        return await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
    }
    nonisolated func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexAllSearchableItemsWithAcknowledgementHandler acknowledgementHandler: @escaping () -> Void) {
        let acknowledgement = SpotlightAcknowledgement(acknowledgementHandler)
        Task { @MainActor in acknowledgements.append(acknowledgement.call); refresh(rebuild: true) }
    }
    nonisolated func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexSearchableItemsWithIdentifiers identifiers: [String], acknowledgementHandler: @escaping () -> Void) {
        let acknowledgement = SpotlightAcknowledgement(acknowledgementHandler)
        Task { @MainActor in acknowledgements.append(acknowledgement.call); refresh(rebuild: true) }
    }
}
