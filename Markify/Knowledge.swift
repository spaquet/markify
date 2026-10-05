import AppKit
import OKFKit
import SwiftUI

/// A scanned Open Knowledge Format bundle and its bundle-wide findings.
struct KnowledgeState: Sendable {
    let bundle: OKFBundle
    let issues: [OKFDiagnostic]
}

struct KnowledgeIssueInput: Equatable, Sendable {
    let text: String
    let fileURL: URL?
    let root: URL?
}

/// Concurrent windows share one immutable scan per root; the last departing consumer cancels it.
private actor KnowledgeLoader {
    static let shared = KnowledgeLoader()
    private struct Job {
        let task: Task<KnowledgeState, Never>
        var consumers: Set<UUID>
    }
    private var jobs: [URL: Job] = [:]

    func load(root: URL) async -> KnowledgeState {
        let root = root.standardizedFileURL
        let consumer = UUID()
        if jobs[root] == nil {
            let task = Task.detached(priority: .utility) {
                let bundle = OKFBundle.load(root: root)
                return KnowledgeState(bundle: bundle, issues: OKFValidator.validate(bundle: bundle))
            }
            jobs[root] = Job(task: task, consumers: [])
        }
        jobs[root]?.consumers.insert(consumer)
        let task = jobs[root]!.task
        let state = await withTaskCancellationHandler { await task.value } onCancel: {
            Task { await self.release(root: root, consumer: consumer) }
        }
        release(root: root, consumer: consumer)
        return state
    }

    private func release(root: URL, consumer: UUID) {
        jobs[root]?.consumers.remove(consumer)
        if jobs[root]?.consumers.isEmpty == true {
            jobs.removeValue(forKey: root)?.task.cancel()
        }
    }
}

/// OKF support in the app: bundle discovery, link following and the files Markify writes for a bundle.
@MainActor enum Knowledge {
    /// Settings › General › Knowledge: recorded as `human:<id>` when marking a concept verified.
    static var actor: OKFActor {
        let id = UserDefaults.standard.string(forKey: "okfActorID")?.trimmingCharacters(in: .whitespaces) ?? ""
        return .human(id.isEmpty ? NSUserName() : id)
    }

    /// The bundle root to scan for a document, or nil for a plain note outside any declared bundle.
    /// A folder opened with Open Bundle Folder… is a bundle even without `okf_version`.
    static func root(for fileURL: URL?, text: String, boundary: URL?) -> URL? {
        guard let fileURL else { return nil }
        if let granted = BundleAccess.folder(containing: fileURL) { return OKFBundle.findRoot(for: fileURL, boundary: granted) }
        let root = OKFBundle.findRoot(for: fileURL, boundary: boundary)
        let isConcept = (try? OKFConcept.parse(source: text)?.get())?.isConcept == true
        return isConcept || OKFBundle.declaredVersion(at: root) != nil ? root : nil
    }

    static func load(root: URL) async -> KnowledgeState {
        await KnowledgeLoader.shared.load(root: root)
    }

    /// Findings for the text being edited, so they track unsaved changes.
    nonisolated static func issues(text: String, fileURL: URL?, root: URL?) -> [OKFDiagnostic] {
        let isRoot = fileURL.map { OKFBundle.key($0.deletingLastPathComponent()) } == root.map(OKFBundle.key)
        var found = OKFValidator.validate(source: text, kind: kind(of: fileURL), isBundleRoot: isRoot)
        for link in OKFLinks.extract(from: FrontmatterBlock.body(of: text)) {
            guard !Task.isCancelled else { return found }
            guard let target = OKFLinks.resolve(link.target, from: fileURL, bundleRoot: root),
                  !FileManager.default.fileExists(atPath: target.path) else { continue }
            found.append(OKFDiagnostic(.info, "Links to \(link.target), which does not exist yet."))
        }
        for reference in (try? OKFConcept.parse(source: text)?.get())?.references ?? [] {
            guard !Task.isCancelled else { return found }
            guard let target = OKFLinks.resolve(reference.target, from: fileURL, bundleRoot: root),
                  !FileManager.default.fileExists(atPath: target.path) else { continue }
            found.append(OKFDiagnostic(.warning, "`\(reference.field)` points to \(reference.target), which does not exist."))
        }
        return found
    }

    nonisolated static func kind(of url: URL?) -> OKFDocument.Kind {
        switch url?.lastPathComponent.lowercased() {
        case "index.md": .index
        case "log.md": .log
        default: .concept
        }
    }

    // MARK: Links

    /// Opens a link destination: web URLs in the browser, Markdown in Markify, other files in their app.
    /// A missing Markdown file can be created as a new concept, since OKF treats broken links as unwritten knowledge.
    static func follow(_ target: String, title: String?, from document: URL?, bundleRoot: URL?, baseDirectory: URL? = nil) {
        if let baseDirectory, !baseDirectory.isFileURL,
           let remote = URL(string: target, relativeTo: baseDirectory)?.absoluteURL {
            openWeb(remote); return
        }
        guard let url = OKFLinks.resolve(target, from: document, bundleRoot: bundleRoot, baseDirectory: baseDirectory) else {
            if let web = URL(string: target), web.scheme != nil { openWeb(web) }
            return
        }
        guard url.isFileURL else { openWeb(url); return }
        let manager = FileManager.default
        let folder = url.deletingLastPathComponent().path
        // Offer creation when the containing folder is readable or does not exist yet.
        let reachable = manager.isReadableFile(atPath: folder) || !manager.fileExists(atPath: folder)
        var isDirectory: ObjCBool = false
        if manager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                let index = url.appendingPathComponent("index.md")
                if manager.fileExists(atPath: index.path) { open(index) } else { NSWorkspace.shared.open(url) }
            } else if ["md", "mdx", "markdown"].contains(url.pathExtension.lowercased()) {
                open(url, anchor: LinkTarget.fragment(target))
            } else {
                NSWorkspace.shared.open(url)
            }
        } else if !reachable {
            if ["md", "mdx", "markdown"].contains(url.pathExtension.lowercased()) { open(url) }
            else { NSWorkspace.shared.open(url) }
        } else if url.pathExtension.lowercased() == "md" {
            offerToCreate(url, title: title)
        } else {
            NSSound.beep()
        }
    }

    /// Opens a web link with the system, and checks it again so the Links pane shows whether it works now.
    private static func openWeb(_ url: URL) {
        NSWorkspace.shared.open(url)
        if ["http", "https"].contains(url.scheme?.lowercased() ?? "") { Task { await WebLinkChecks.shared.check([url], force: true) } }
    }

    /// Opens a Markdown document, then moves to the heading named by `anchor` once its editor is up.
    static func open(_ url: URL, anchor: String? = nil, search: String? = nil, related: Bool = false) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            Task { @MainActor in
                if let error { NSApp.presentError(error); return }
                guard anchor != nil || search != nil else { return }
                for _ in 0..<40 {
                    if let editor = MarkdownTextView.openEditors.allObjects.first(where: { $0.documentURL?.standardizedFileURL == url.standardizedFileURL && $0.window != nil }) {
                        if let anchor {
                            if !editor.revealAnchor(anchor) { NSSound.beep() }
                        } else if let search {
                            let range = related ? NSRange(location: 0, length: 0) : SearchMatch.literalRanges(in: editor.string, query: search).first ?? NSRange(location: 0, length: 0)
                            editor.setSelectedRange(range)
                            editor.scrollRangeToVisible(range)
                            editor.window?.makeFirstResponder(editor)
                        }
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
        }
    }

    private static func offerToCreate(_ url: URL, title: String?) {
        let alert = NSAlert()
        alert.messageText = "“\(url.lastPathComponent)” doesn’t exist yet."
        alert.informativeText = "Create it as a new concept in \(url.deletingLastPathComponent().lastPathComponent)?"
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = title.flatMap { $0.isEmpty ? nil : $0 } ?? url.deletingPathExtension().lastPathComponent
        let text = OKFEditing.conceptTemplate(type: nil, title: name, author: actor) + "\n# \(name)\n\n"
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
            open(url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    // MARK: Bundle files

    /// Asks for a log entry and adds it to `log.md` beside the document.
    static func addLogEntry(for document: URL, title: String, bundleRoot: URL?) {
        let alert = NSAlert()
        alert.messageText = "Add Log Entry"
        alert.informativeText = "Adds a dated entry to log.md in “\(document.deletingLastPathComponent().lastPathComponent)”."
        let kind = NSPopUpButton(frame: NSRect(x: 0, y: 30, width: 320, height: 26), pullsDown: false)
        kind.addItems(withTitles: ["Update", "Creation", "Deprecation"])
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        let path = bundleRoot.flatMap { OKFLinks.bundlePath(of: document, root: $0) } ?? document.lastPathComponent
        field.stringValue = "Revised [\(title)](\(path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path))."
        let stack = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 58))
        stack.addSubview(kind)
        stack.addSubview(field)
        alert.accessoryView = stack
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let log = document.deletingLastPathComponent().appendingPathComponent("log.md")
        let existing = try? String(contentsOf: log, encoding: .utf8)
        let text = OKFEditing.appendingLogEntry(field.stringValue, label: kind.titleOfSelectedItem ?? "Update", to: existing)
        write(text, to: log)
    }

    /// Regenerates `index.md` for the document's folder from the concepts' frontmatter.
    static func rebuildIndex(for document: URL, bundleRoot: URL) async {
        let folder = document.deletingLastPathComponent()
        let index = folder.appendingPathComponent("index.md")
        let existing = try? String(contentsOf: index, encoding: .utf8)
        if existing != nil {
            let alert = NSAlert()
            alert.messageText = "Replace index.md in “\(folder.lastPathComponent)”?"
            alert.informativeText = "The listing is rebuilt from each concept’s type, title and description. Anything written by hand in index.md is replaced."
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let bundle = await Task.detached(priority: .userInitiated) { OKFBundle.load(root: bundleRoot) }.value
        write(OKFEditing.renderIndex(directory: folder, bundle: bundle, existing: existing), to: index)
    }

    private static func write(_ text: String, to url: URL) {
        do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { NSAlert(error: error).runModal() }
    }
}

/// The sidebar's Knowledge section: a browser for the bundle, then the current concept's provenance, links and findings.
struct KnowledgeSection: View {
    let state: KnowledgeState?
    let fileURL: URL?
    let concept: OKFConcept?
    let text: String
    let issues: [OKFDiagnostic]
    let search: String
    let open: (URL) -> Void
    @AppStorage("okfBrowse") private var browse = "Folders"
    @State private var showBundleIssues = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Knowledge").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 12)
            if let state {
                Text("\(state.bundle.root.lastPathComponent) · \(state.bundle.concepts.count) concepts\(state.bundle.okfVersion.map { " · OKF \($0)" } ?? "")")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                if state.bundle.truncated {
                    Text("Showing the first \(state.bundle.documents.count) files.").font(.system(size: 11)).foregroundStyle(.orange)
                }
                BundleBrowser(bundle: state.bundle, fileURL: fileURL, search: search, mode: $browse, open: open)
            }
            if let concept { ConceptDetails(concept: concept, text: text, fileURL: fileURL, root: state?.bundle.root, open: open) }
            if let state, let fileURL {
                let backlinks = state.bundle.backlinks(to: fileURL)
                if !backlinks.isEmpty {
                    Text("Linked from").font(.system(size: 11.5, weight: .medium)).padding(.top, 4)
                    ForEach(backlinks) { document in DocumentRow(document: document, current: false, detail: document.path) { open(document.url) } }
                }
            }
            ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in IssueRow(issue: issue, showPath: false) }
            if let state {
                let others = state.issues.filter { $0.url.map(OKFBundle.key) != fileURL.map(OKFBundle.key) && $0.severity > .info }
                if !others.isEmpty {
                    DisclosureGroup(isExpanded: $showBundleIssues) {
                        ForEach(Array(others.prefix(100).enumerated()), id: \.offset) { _, issue in
                            Button { if let url = issue.url { open(url) } } label: { IssueRow(issue: issue, showPath: true) }.buttonStyle(.plain)
                        }
                    } label: {
                        Text("\(others.count) \(others.count == 1 ? "issue" : "issues") in bundle").font(.system(size: 11.5))
                    }
                }
            }
        }
    }
}

/// The bundle as folders, by type, or by tag; a search shows matching concepts in one list.
private struct BundleBrowser: View {
    let bundle: OKFBundle
    let fileURL: URL?
    let search: String
    @Binding var mode: String
    let open: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Picker("Browse", selection: $mode) {
                Text("Folders").tag("Folders")
                Text("Types").tag("Types")
                Text("Tags").tag("Tags")
            }
            .pickerStyle(.segmented).labelsHidden().controlSize(.small).padding(.vertical, 4)
            if !search.isEmpty {
                let matches = bundle.documents.filter {
                    $0.title.localizedCaseInsensitiveContains(search) || ($0.concept?.description ?? "").localizedCaseInsensitiveContains(search)
                        || ($0.concept?.tags ?? []).contains { $0.localizedCaseInsensitiveContains(search) }
                }
                ForEach(matches) { row($0, detail: $0.path) }
                if matches.isEmpty { Text("No matching concepts").font(.system(size: 11.5)).foregroundStyle(.secondary).padding(7) }
            } else if mode == "Types" {
                ForEach(bundle.types, id: \.self) { type in
                    group(type, bundle.concepts.filter { $0.concept?.type == type })
                }
                let untyped = bundle.concepts.filter { !($0.concept?.isConcept ?? false) }
                if !untyped.isEmpty { group("No type", untyped) }
            } else if mode == "Tags" {
                ForEach(bundle.tags, id: \.self) { tag in
                    group("#" + tag, bundle.concepts.filter { $0.concept?.tags.contains(tag) == true })
                }
                if bundle.tags.isEmpty { Text("No tags yet").font(.system(size: 11.5)).foregroundStyle(.secondary).padding(7) }
            } else {
                FolderRows(bundle: bundle, folder: bundle.root, fileURL: fileURL, open: open)
            }
        }
    }

    private func group(_ name: String, _ documents: [OKFDocument]) -> some View {
        DisclosureGroup {
            ForEach(documents) { row($0, detail: nil) }
        } label: {
            Text("\(name)  \(documents.count)").font(.system(size: 12.5, weight: .medium)).lineLimit(1)
        }
    }

    private func row(_ document: OKFDocument, detail: String?) -> some View {
        DocumentRow(document: document, current: fileURL.map(OKFBundle.key) == OKFBundle.key(document.url), detail: detail) { open(document.url) }
    }
}

/// One folder of the bundle; subfolders on the current document's path start expanded.
private struct FolderRows: View {
    let bundle: OKFBundle
    let folder: URL
    let fileURL: URL?
    let open: (URL) -> Void

    var body: some View {
        let contents = bundle.contents(of: folder)
        ForEach(contents.subdirectories, id: \.self) { subfolder in
            FolderGroup(bundle: bundle, folder: subfolder, fileURL: fileURL, open: open)
        }
        ForEach(contents.documents) { document in
            DocumentRow(document: document, current: fileURL.map(OKFBundle.key) == OKFBundle.key(document.url),
                        detail: document.concept?.type) { open(document.url) }
        }
    }
}

private struct FolderGroup: View {
    let bundle: OKFBundle
    let folder: URL
    let fileURL: URL?
    let open: (URL) -> Void
    @State private var expanded: Bool?

    var body: some View {
        let onPath = fileURL.map { OKFBundle.contains(folder, $0) } ?? false
        DisclosureGroup(isExpanded: Binding(get: { expanded ?? onPath }, set: { expanded = $0 })) {
            FolderRows(bundle: bundle, folder: folder, fileURL: fileURL, open: open)
        } label: {
            Label(folder.lastPathComponent, systemImage: "folder").font(.system(size: 12.5)).lineLimit(1)
        }
    }
}

private struct DocumentRow: View {
    let document: OKFDocument
    let current: Bool
    let detail: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: document.kind == .concept ? "doc.text" : document.kind == .index ? "list.bullet.rectangle" : "clock")
                .font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(document.title).font(.system(size: 13, weight: current ? .semibold : .regular)).lineLimit(1)
                if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
            }
            Spacer(minLength: 0)
            if document.concept?.status == .deprecated { Image(systemName: "archivebox").font(.system(size: 10)).foregroundStyle(.secondary) }
            if document.concept?.trustTier == .humanReviewed { Image(systemName: "checkmark.seal").font(.system(size: 10)).foregroundStyle(.green) }
        }
        .padding(.horizontal, 5).padding(.vertical, 3)
        .sidebarRow(document.url, open: action)
    }
}

/// Provenance and computation details from the current concept's frontmatter (§5.1, §10).
private struct ConceptDetails: View {
    let concept: OKFConcept
    let text: String
    let fileURL: URL?
    let root: URL?
    let open: (URL) -> Void

    var body: some View {
        let citations = concept.sources.isEmpty ? OKFLinks.legacyCitations(in: FrontmatterBlock.body(of: text)) : []
        VStack(alignment: .leading, spacing: 4) {
            if let changed = concept.lastChanged {
                let by = concept.generated?.by.map { " by \($0.isHuman ? $0.displayName : $0.description)" } ?? ""
                Text("Changed \(changed.formatted(date: .abbreviated, time: .omitted))\(by)").font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            if let verified = concept.lastVerified, let by = verified.by {
                Text("Verified\(verified.at.map { " \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "") by \(by.displayName)")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            if !concept.sources.isEmpty || !citations.isEmpty {
                Text("Sources").font(.system(size: 11.5, weight: .medium)).padding(.top, 4)
                ForEach(Array(concept.sources.enumerated()), id: \.offset) { _, source in
                    linkRow(source.title ?? source.resource ?? source.id ?? "Source", target: source.resource, detail: signals(source))
                }
                ForEach(Array(citations.enumerated()), id: \.offset) { _, link in
                    linkRow(link.text, target: link.target, detail: "Citation (OKF 0.1)")
                }
            }
            if concept.isAttestedComputation || concept.runtime != nil {
                Text("Computation").font(.system(size: 11.5, weight: .medium)).padding(.top, 4)
                Text("Runs on \(concept.runtime ?? "an unspecified runtime")").font(.system(size: 11.5))
                if !concept.parameters.isEmpty {
                    Text(concept.parameters.map { "\($0.name ?? "?"): \($0.type ?? "any")\($0.required ? "" : "?")" }.joined(separator: ", "))
                        .font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary)
                }
                if let computation = concept.computation { linkRow("Computation", target: computation, detail: computation) }
                if let executor = concept.executorResource {
                    linkRow("Executor", target: executor, detail: concept.receipt.isEmpty ? executor : "Returns " + concept.receipt.joined(separator: ", "))
                }
                if let attester = concept.attesterResource { linkRow("Attester", target: attester, detail: attester) }
                Text("Markify shows the contract; it doesn't run computations.").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
    }

    private func signals(_ source: OKFSource) -> String? {
        var parts: [String] = []
        if let author = source.author { parts.append(author.displayName) }
        if let count = source.usageCount { parts.append("\(count.formatted()) uses") }
        if let modified = source.lastModified { parts.append("updated \(modified.formatted(date: .abbreviated, time: .omitted))") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func linkRow(_ title: String, target: String?, detail: String?) -> some View {
        Button {
            if let target { Knowledge.follow(target, title: title, from: fileURL, bundleRoot: root) }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12.5)).foregroundStyle(target == nil ? Color.primary : Color.accentColor).lineLimit(2)
                if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain).padding(.horizontal, 5).padding(.vertical, 2)
        .disabled(target == nil)
    }
}

private struct IssueRow: View {
    let issue: OKFDiagnostic
    let showPath: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: issue.severity == .error ? "xmark.octagon.fill" : issue.severity == .warning ? "exclamationmark.triangle.fill" : "info.circle")
                .foregroundStyle(issue.severity == .error ? Color.red : issue.severity == .warning ? Color.orange : Color.secondary)
                .font(.system(size: 11))
            VStack(alignment: .leading, spacing: 1) {
                if showPath, let path = issue.path { Text(path).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
                Text(issue.message).font(.system(size: 11.5)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7).padding(.vertical, 2)
    }
}

/// Folders opened with Knowledge › Open Bundle Folder…, remembered with bookmarks for later launches.
@MainActor enum BundleAccess {
    private static let key = "okfBundleBookmarks"
    private(set) static var folders: [URL] = []

    /// Starts access to every remembered folder; called once at launch.
    static func restore() {
        let bookmarks = UserDefaults.standard.array(forKey: key) as? [Data] ?? []
        var kept: [Data] = []
        for bookmark in bookmarks {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &stale),
                  url.startAccessingSecurityScopedResource() else { continue }
            folders.append(url)
            kept.append(stale ? (try? url.bookmarkData(options: .withSecurityScope)) ?? bookmark : bookmark)
        }
        UserDefaults.standard.set(kept, forKey: key)
    }

    static func folder(containing url: URL) -> URL? {
        folders.filter { OKFBundle.contains($0, url) }.max { $0.path.count < $1.path.count }
    }

    /// Asks for a bundle folder, remembers it, and opens its root index.md (or first concept) with the sidebar showing.
    static func chooseAndOpen() {
        let panel = NSOpenPanel()
        panel.message = "Choose the root folder of an OKF knowledge bundle."
        panel.prompt = "Open Bundle"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !folders.contains(where: { OKFBundle.key($0) == OKFBundle.key(url) }), let bookmark = try? url.bookmarkData(options: .withSecurityScope) {
            _ = url.startAccessingSecurityScopedResource()
            folders.append(url)
            UserDefaults.standard.set((UserDefaults.standard.array(forKey: key) as? [Data] ?? []) + [bookmark], forKey: key)
        }
        let index = url.appendingPathComponent("index.md")
        let first = FileManager.default.fileExists(atPath: index.path) ? index : OKFBundle.load(root: url, limit: 200).concepts.first?.url
        guard let first else {
            let alert = NSAlert()
            alert.messageText = "“\(url.lastPathComponent)” has no Markdown files."
            alert.informativeText = "An OKF bundle is a folder of .md concepts. Create one with Knowledge › Rebuild Index after adding concepts."
            alert.runModal()
            return
        }
        MarkifyAppDelegate.showsLibraryOnNextWindow = true
        Knowledge.open(first)
    }
}

/// Watches a bundle folder recursively and reports changes, coalesced over a second.
@MainActor final class BundleWatcher {
    private var stream: FSEventStreamRef?
    private var onChange: (() -> Void)?

    func watch(_ folder: URL?, onChange: @escaping () -> Void) {
        stop()
        guard let folder else { return }
        self.onChange = onChange
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            // The stream delivers on the main queue (below).
            guard let address = info.map({ UInt(bitPattern: $0) }) else { return }
            MainActor.assumeIsolated {
                guard let pointer = UnsafeRawPointer(bitPattern: address) else { return }
                Unmanaged<BundleWatcher>.fromOpaque(pointer).takeUnretainedValue().onChange?()
            }
        }
        guard let stream = FSEventStreamCreate(nil, callback, &context, [folder.path] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0,
                                               FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer)) else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    isolated deinit { stop() }
}

/// The current document's OKF frontmatter, reparsed only when the YAML changes.
final class ConceptCache {
    private var yaml: String?
    private var concept: OKFConcept?

    func concept(in text: String) -> OKFConcept? {
        let block = FrontmatterBlock.locate(in: text)
        if block?.yaml == yaml { return concept }
        yaml = block?.yaml
        concept = block.flatMap { try? OKFConcept(yaml: $0.yaml) }.flatMap { $0.isConcept ? $0 : nil }
        return concept
    }
}

/// Apple Intelligence's frontmatter suggestion, merged key by key so the rest of the frontmatter survives.
struct FrontmatterSuggestion: Equatable {
    var title: String
    var tags: [String]
    /// Only suggested for OKF documents that have no type yet.
    var type: String? = nil
    var description: String? = nil

    private var entries: [(key: String, line: String)] {
        var entries: [(String, String)] = []
        if let type, !type.isEmpty { entries.append(("type", "type: \(OKFEditing.scalar(type))")) }
        if !title.isEmpty { entries.append(("title", "title: \(OKFEditing.scalar(title))")) }
        if let description, !description.isEmpty { entries.append(("description", "description: \(OKFEditing.scalar(description))")) }
        let tags = tags.prefix(5).map { OKFEditing.scalar($0.trimmingCharacters(in: .whitespaces)) }.filter { !$0.isEmpty }
        if !tags.isEmpty { entries.append(("tags", "tags: [\(tags.joined(separator: ", "))]")) }
        return entries
    }

    /// The YAML shown before Keep.
    var preview: String { entries.map(\.line).joined(separator: "\n") }

    /// Sets the suggested keys; `type` never replaces one already written, since it routes the concept.
    func merged(into yaml: String) -> String {
        entries.reduce(yaml) { yaml, entry in
            if entry.key == "type" && OKFEditing.hasKey("type", in: yaml) { return yaml }
            // A new type leads the block, as in the spec's examples.
            if entry.key == "type" { return entry.line + "\n" + yaml }
            return OKFEditing.setting(entry.key, to: entry.line, in: yaml)
        }
    }
}

extension Knowledge {
    /// The actor for text Apple Intelligence wrote; the on-device model ships with the OS, so its version names the model.
    static var aiActor: OKFActor {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return .agent(producer: "apple-intelligence", version: "macos-\(version.majorVersion).\(version.minorVersion)")
    }
}
