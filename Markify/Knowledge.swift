import AppKit
import OKFKit
import SwiftUI

/// A scanned Open Knowledge Format bundle and its bundle-wide findings.
struct KnowledgeState: Sendable {
    let bundle: OKFBundle
    let issues: [OKFDiagnostic]
}

/// OKF support in the app: bundle discovery, link following and the files Markify writes for a bundle.
@MainActor enum Knowledge {
    /// Settings › General › Knowledge: recorded as `human:<id>` when marking a concept verified.
    static var actor: OKFActor {
        let id = UserDefaults.standard.string(forKey: "okfActorID")?.trimmingCharacters(in: .whitespaces) ?? ""
        return .human(id.isEmpty ? NSUserName() : id)
    }

    /// The bundle root to scan for a document, or nil for a plain note outside any declared bundle.
    static func root(for fileURL: URL?, text: String, boundary: URL?) -> URL? {
        guard let fileURL else { return nil }
        let root = OKFBundle.findRoot(for: fileURL, boundary: boundary)
        let isConcept = (try? OKFConcept.parse(source: text)?.get())?.isConcept == true
        return isConcept || OKFBundle.declaredVersion(at: root) != nil ? root : nil
    }

    static func load(root: URL) async -> KnowledgeState {
        await Task.detached(priority: .utility) {
            let bundle = OKFBundle.load(root: root)
            return KnowledgeState(bundle: bundle, issues: OKFValidator.validate(bundle: bundle))
        }.value
    }

    /// Findings for the text being edited, so they track unsaved changes.
    static func issues(text: String, fileURL: URL?, root: URL?) -> [OKFDiagnostic] {
        let isRoot = fileURL.map { OKFBundle.key($0.deletingLastPathComponent()) } == root.map(OKFBundle.key)
        var found = OKFValidator.validate(source: text, kind: kind(of: fileURL), isBundleRoot: isRoot)
        for link in OKFLinks.extract(from: FrontmatterBlock.body(of: text)) {
            guard let target = OKFLinks.resolve(link.target, from: fileURL, bundleRoot: root),
                  !FileManager.default.fileExists(atPath: target.path) else { continue }
            found.append(OKFDiagnostic(.info, "Links to \(link.target), which does not exist yet."))
        }
        return found
    }

    static func kind(of url: URL?) -> OKFDocument.Kind {
        switch url?.lastPathComponent.lowercased() {
        case "index.md": .index
        case "log.md": .log
        default: .concept
        }
    }

    // MARK: Links

    /// Opens a link destination: web URLs in the browser, Markdown in Markify, other files in their app.
    /// A missing Markdown file can be created as a new concept, since OKF treats broken links as unwritten knowledge.
    static func follow(_ target: String, title: String?, from document: URL?, bundleRoot: URL?) {
        guard let url = OKFLinks.resolve(target, from: document, bundleRoot: bundleRoot) else {
            if let web = URL(string: target), web.scheme != nil { NSWorkspace.shared.open(web) }
            return
        }
        let manager = FileManager.default
        let folder = url.deletingLastPathComponent().path
        // Outside the sandbox's reach a file reads as missing, so only offer to create where the folder is readable.
        let reachable = manager.isReadableFile(atPath: folder) || !manager.fileExists(atPath: folder)
        var isDirectory: ObjCBool = false
        if manager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                let index = url.appendingPathComponent("index.md")
                if manager.fileExists(atPath: index.path) { open(index) } else { NSWorkspace.shared.open(url) }
            } else if ["md", "mdx", "markdown"].contains(url.pathExtension.lowercased()) {
                open(url)
            } else {
                NSWorkspace.shared.open(url)
            }
        } else if !reachable {
            requestAccess(to: url)
        } else if url.pathExtension.lowercased() == "md" {
            offerToCreate(url, title: title)
        } else {
            NSSound.beep()
        }
    }

    static func open(_ url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            // The sandbox only reaches files the person picked or the library; ask for this one.
            if error != nil { Task { @MainActor in requestAccess(to: url) } }
        }
    }

    private static func requestAccess(to url: URL) {
        let panel = NSOpenPanel()
        panel.message = "Markify needs your permission to open “\(url.lastPathComponent)”."
        panel.prompt = "Open"
        panel.directoryURL = url.deletingLastPathComponent()
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        NSDocumentController.shared.openDocument(withContentsOf: chosen, display: true) { _, _, _ in }
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

/// The sidebar's Knowledge section: backlinks and findings for the current concept, then the bundle's.
struct KnowledgeSection: View {
    let state: KnowledgeState?
    let fileURL: URL?
    let issues: [OKFDiagnostic]
    let open: (URL) -> Void
    @State private var showBundleIssues = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Knowledge").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 12)
            if let state {
                let backlinks = fileURL.map { state.bundle.backlinks(to: $0) } ?? []
                Text("\(state.bundle.concepts.count) concepts\(state.bundle.okfVersion.map { " · OKF \($0)" } ?? "")")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                if !backlinks.isEmpty {
                    Text("Linked from").font(.system(size: 11.5, weight: .medium)).padding(.top, 4)
                    ForEach(backlinks) { document in
                        Button { open(document.url) } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(document.title).font(.system(size: 13))
                                Text(document.path).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain).padding(.horizontal, 7).padding(.vertical, 3)
                    }
                }
            }
            ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in row(issue, showPath: false) }
            if let state {
                let others = state.issues.filter { $0.url.map(OKFBundle.key) != fileURL.map(OKFBundle.key) && $0.severity > .info }
                if !others.isEmpty {
                    DisclosureGroup(isExpanded: $showBundleIssues) {
                        ForEach(Array(others.prefix(100).enumerated()), id: \.offset) { _, issue in
                            Button { if let url = issue.url { open(url) } } label: { row(issue, showPath: true) }.buttonStyle(.plain)
                        }
                    } label: {
                        Text("\(others.count) \(others.count == 1 ? "issue" : "issues") in bundle").font(.system(size: 11.5))
                    }
                }
            }
        }
    }

    private func row(_ issue: OKFDiagnostic, showPath: Bool) -> some View {
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
