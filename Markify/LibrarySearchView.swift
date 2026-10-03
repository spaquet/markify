import AppKit
@preconcurrency import CoreSpotlight
import Observation
import SwiftUI

@MainActor @Observable final class SearchSession {
    var results: [SearchMatch] = []
    var searching = false
    var error: String?
    @ObservationIgnored private var query: CSUserQuery?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()

    nonisolated static func filter(attribute: String, value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\(attribute) == \"\(escaped)\""
    }
    func cancel() {
        generation = UUID(); query?.cancel(); task?.cancel(); query = nil; searching = false
    }
    func search(_ text: String, scope: String, type: String, tag: String, service: LibrarySearch) {
        cancel(); results = []; error = nil
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !service.options.paused else { return }
        searching = true
        let token = generation
        let context = CSUserQueryContext()
        context.enableRankedResults = true
        context.disableSemanticSearch = !service.options.related
        context.maxResultCount = 0
        context.maxRankedResultCount = 1000
        context.fetchAttributes = ["title", "contentURL", "contentDescription"]
        var filters = [Self.filter(attribute: "domainIdentifier", value: "markifynotes")]
        if scope != "all" { filters.append(Self.filter(attribute: "markifyScopes", value: scope)) }
        if !type.isEmpty { filters.append(Self.filter(attribute: "markifyType", value: type)) }
        if !tag.isEmpty { filters.append(Self.filter(attribute: "markifyTags", value: tag)) }
        context.filterQueries = filters
        let query = CSUserQuery(userQueryString: text, userQueryContext: context)
        self.query = query
        task = Task {
            do {
                var items: [CSSearchQuery.Results.Item] = []
                for try await item in query.results {
                    guard generation == token, !Task.isCancelled else { return }
                    items.append(item)
                }
                guard generation == token, !Task.isCancelled else { return }
                // The Comparable conformance uses Spotlight's rank, never a Markify score.
                let ordered = items.sorted()
                let notes = Dictionary(uniqueKeysWithValues: service.snapshot.notes.map { ($0.id, $0) })
                var seen = Set<String>()
                let selected = ordered.compactMap { result -> SearchNote? in
                    let item = result.item
                    guard seen.insert(item.uniqueIdentifier).inserted, let note = notes[item.uniqueIdentifier],
                          scope == "all" || note.scopes.contains(scope),
                          type.isEmpty || note.type == type, tag.isEmpty || note.tags.contains(tag) else { return nil }
                    return note
                }
                let enriched = await service.enrich(selected, query: text)
                guard generation == token, !Task.isCancelled else { return }
                results = enriched; searching = false
            } catch {
                guard generation == token else { return }
                self.error = error.localizedDescription; searching = false
            }
        }
    }
}

struct LibrarySearchPanel: View {
    let library: URL?
    let currentBundle: URL?
    let currentFile: URL?
    let browse: AnyView
    let close: () -> Void
    @AppStorage(Shortcuts.storageKey) private var shortcutOverrides = ""
    @State private var service = LibrarySearch.shared
    @State private var session = SearchSession()
    @State private var query = ""
    @State private var scope = ""
    @State private var type = ""
    @State private var tag = ""
    @FocusState private var focused: Bool
    @Environment(\.openSettings) private var openSettings

    private var selectedScope: String {
        if !scope.isEmpty { return scope }
        if service.options.defaultScope == "all" { return "all" }
        if service.options.defaultScope == "bundle", let currentBundle { return SearchNote.identifier(currentBundle) }
        return library.map(SearchNote.identifier) ?? "all"
    }
    private var request: String { "\(query)\u{0}\(selectedScope)\u{0}\(type)\u{0}\(tag)\u{0}\(service.revision)" }
    private var scopeName: String {
        if selectedScope == "all" { return "All Folders" }
        if let folder = service.snapshot.folders.first(where: { $0.id == selectedScope }) { return folder.name }
        return service.snapshot.subfolders.first(where: { SearchNote.identifier($0) == selectedScope })?.lastPathComponent ?? "Current Library"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Library").font(.system(size: 15, weight: .bold))
                Spacer()
                Button(action: close) { Image(systemName: "sidebar.left") }.help("Hide Library")
                Button { NSDocumentController.shared.newDocument(nil) } label: { Image(systemName: "plus") }.help("New Document")
                Menu {
                    Button("Refresh") { service.refresh() }
                    Button("Search Settings…", action: showSearchSettings)
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).fixedSize()
            }.buttonStyle(.plain)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search notes", text: $query).textFieldStyle(.plain).focused($focused)
                    .onSubmit { service.remember(query) }
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).help("Clear search")
                }
                Text(Shortcuts.display(Shortcuts.key("searchLibrary", stored: shortcutOverrides))).font(.system(size: 10)).foregroundStyle(.tertiary)
            }.padding(9).background(.background.opacity(0.7), in: .rect(cornerRadius: 10))
            HStack(spacing: 6) {
                Menu {
                    Button("Current Library") { scope = library.map(SearchNote.identifier) ?? "all" }
                    if let currentFile {
                        let folder = currentFile.deletingLastPathComponent()
                        if service.snapshot.subfolders.contains(folder) {
                            Button("Selected Folder: \(folder.lastPathComponent)") { scope = SearchNote.identifier(folder) }
                        }
                    }
                    Menu("Library Subfolders") {
                        ForEach(service.snapshot.subfolders.filter { folder in library.map { SearchNote.contains($0, folder) } ?? false }, id: \.self) { folder in
                            Button(library.map { LibraryNote.path(of: folder, in: $0) } ?? folder.lastPathComponent) { scope = SearchNote.identifier(folder) }
                        }
                    }
                    Section("Projects") {
                        ForEach(service.snapshot.folders.filter { $0.kind == "Project" }) { root in
                            Button(root.name) { scope = root.id }
                        }
                    }
                    Section("OKF bundles") {
                        ForEach(service.snapshot.folders.filter { $0.kind == "OKF bundle" }) { root in
                            Button(root.name) { scope = root.id }
                        }
                    }
                    Button("All Folders") { scope = "all" }
                    Divider()
                    Button("Add Folder…") { service.chooseFolder() }
                } label: { Text("In \(scopeName)").lineLimit(1) }
                Menu(type.isEmpty ? "Type" : type) {
                    Button("All Types") { type = "" }
                    ForEach(Array(Set(service.snapshot.notes.compactMap(\.type))).sorted(), id: \.self) { value in
                        Button(value) { type = value }
                    }
                }
                Menu(tag.isEmpty ? "Tag" : "#\(tag)") {
                    Button("All Tags") { tag = "" }
                    ForEach(Array(Set(service.snapshot.notes.flatMap(\.tags))).sorted(), id: \.self) { value in
                        Button(value) { tag = value }
                    }
                }
            }.font(.system(size: 12)).menuStyle(.borderlessButton)
            if service.indexing {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Indexing · \(service.indexedCount) notes read. More results may appear.").font(.system(size: 12))
                    Spacer()
                }.padding(9).background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(service.snapshot.folders.filter { root in
                        (selectedScope == "all" || selectedScope == root.id) && (service.snapshot.status[root.id]?.contains("Access") == true)
                    }) { root in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(root.name).fontWeight(.semibold)
                            Text("Access to this folder expired. Its notes stay hidden until you grant access again.").foregroundStyle(.secondary)
                            Button("Grant Access…") { service.chooseFolder(replacing: root) }
                        }.font(.system(size: 12)).padding(10).background(.orange.opacity(0.12), in: .rect(cornerRadius: 10))
                    }
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if !service.recents.isEmpty {
                            Text("Recent searches").font(.caption).foregroundStyle(.secondary)
                            ForEach(service.recents, id: \.self) { recent in
                                Button { query = recent } label: { Label(recent, systemImage: "clock.arrow.circlepath") }.buttonStyle(.plain).padding(5)
                            }
                        }
                        browse
                    } else if let error = session.error {
                        ContentUnavailableView("Spotlight search unavailable", systemImage: "exclamationmark.magnifyingglass", description: Text(error))
                    } else if session.results.isEmpty {
                        VStack(spacing: 10) {
                            if service.indexing || session.searching { ProgressView() }
                            Text(service.options.paused ? "Search index deleted" : service.indexing ? "Still indexing" : session.searching ? "Searching Spotlight…" : "No results in \(scopeName)").fontWeight(.semibold)
                            Text(service.indexing ? "No matches yet. Results will update when indexing finishes." : "Spotlight may still be processing submitted notes. Try another phrase or a wider scope.").foregroundStyle(.secondary)
                            if selectedScope != "all" { Button("Search All Folders") { scope = "all" } }
                            Button("Refresh") { service.refresh() }
                        }.font(.system(size: 12)).multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, 55)
                    } else {
                        Text("\(session.results.count) notes · ranked by Spotlight").font(.caption).foregroundStyle(.secondary)
                        ForEach(resultRoots) { root in
                            let results = session.results.filter { group(for: $0.note)?.id == root.id }
                            HStack {
                                Text(root.name).fontWeight(.semibold)
                                Text(root.kind).padding(.horizontal, 6).background(.quaternary, in: .capsule)
                                Spacer()
                                Text("\(results.count)")
                            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 8)
                            ForEach(results) { result in resultRow(result, root: root) }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.scrollIndicators(.never)
            Divider()
            HStack(spacing: 7) {
                Circle().fill(service.indexing ? .blue : .green).frame(width: 7, height: 7)
                Text(service.message).lineLimit(2)
                Spacer(minLength: 0)
                Button(action: showSearchSettings) { Image(systemName: "gearshape") }.buttonStyle(.plain).help("Search Settings")
            }.font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.top, 54).padding(.bottom, 14)
        .frame(width: 356).frame(maxHeight: .infinity)
        .chromeGlass(in: .rect(cornerRadius: 24))
        .task(id: request) {
            session.cancel()
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            session.search(query, scope: selectedScope, type: type, tag: tag, service: service)
        }
        .onAppear { service.start() }
        .onDisappear { session.cancel() }
        .onReceive(NotificationCenter.default.publisher(for: .focusLibrarySearch)) { notification in
            if notification.object as? NSWindow === NSApp.keyWindow { focused = true }
        }
    }
    private func showSearchSettings() {
        SettingsDestination.search = true
        openSettings()
        NotificationCenter.default.post(name: .openSearchSettings, object: nil)
    }
    private func group(for note: SearchNote) -> SearchFolder? {
        let roots = service.snapshot.folders.filter { note.roots.contains($0.id) }
        return roots.first { $0.id == selectedScope } ?? roots.filter { $0.kind == "OKF bundle" }.max { $0.path.count < $1.path.count } ?? roots.first
    }
    private var resultRoots: [SearchFolder] {
        service.snapshot.folders.filter { root in session.results.contains { group(for: $0.note)?.id == root.id } }
    }
    private func highlighted(_ result: SearchMatch) -> AttributedString {
        var text = AttributedString(result.snippet)
        for range in result.ranges {
            if let swiftRange = Range(range, in: result.snippet), let attributedRange = Range(swiftRange, in: text) {
                text[attributedRange].backgroundColor = .yellow.opacity(0.3)
            }
        }
        return text
    }
    private func resultRow(_ result: SearchMatch, root: SearchFolder) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: result.note.type == nil ? "doc.text" : "diamond").foregroundStyle(result.note.type == nil ? Color.secondary : .purple)
                .frame(width: 28, height: 28).background(.quaternary, in: .rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(result.note.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(result.line.map { "L\($0)\(result.count > 1 ? " · \(result.count)×" : "")" } ?? (result.related ? "Related" : "Title / path"))
                        .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(result.related ? .purple : .secondary)
                }
                Text(LibraryNote.path(of: result.note.url, in: URL(fileURLWithPath: root.path)))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                if let heading = result.heading { Text(heading).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
                Text(highlighted(result)).font(.system(size: 12.5)).lineLimit(2)
                if let type = result.note.type {
                    Text(([type] + result.note.tags.map { "#\($0)" }).joined(separator: "  ")).font(.system(size: 11)).foregroundStyle(.purple).lineLimit(1)
                }
            }
        }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(result.note.url == currentFile ? Color.accentColor.opacity(0.15) : .clear, in: .rect(cornerRadius: 10))
            .sidebarRow(result.note.url) {
                service.remember(query)
                Knowledge.open(result.note.url, search: query, related: result.related)
            }
            .help(result.line.map { "Open at line \($0)" } ?? "Open at the top of the note")
    }
}

extension Notification.Name {
    static let openSearchSettings = Notification.Name("MarkifyOpenSearchSettings")
    static let focusLibrarySearch = Notification.Name("MarkifyFocusLibrarySearch")
}
