import AppKit
import SwiftUI

struct SearchSettingsView: View {
    @State private var search = LibrarySearch.shared
    @State private var selected: String?
    @State private var deleting = false

    var body: some View {
        @Bindable var search = search
        Form {
            Section {
                HStack {
                    Image(systemName: "magnifyingglass").font(.title2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(search.indexing ? "Updating Spotlight index…" : "Spotlight search index").fontWeight(.semibold)
                        Text(search.message).font(.caption).foregroundStyle(.secondary)
                        if search.indexing { ProgressView().progressViewStyle(.linear) }
                    }
                    Spacer()
                    Button(search.indexing ? "Cancel" : "Rebuild Index") {
                        if search.indexing { search.cancel() } else { search.rebuild() }
                    }
                }
            }
            Section {
                ForEach(search.snapshot.folders) { folder in
                    HStack(spacing: 10) {
                        Image(systemName: folder.kind == "OKF bundle" ? "diamond" : "folder")
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(folder.name) · \(folder.kind)").fontWeight(.medium)
                            Text(folder.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Text(search.snapshot.status[folder.id] ?? (search.indexing ? "Indexing…" : "Pending")).font(.caption).foregroundStyle(.secondary)
                        if search.snapshot.status[folder.id]?.contains("Access") == true {
                            Button("Grant Access…") { search.chooseFolder(replacing: folder) }
                        }
                    }.padding(4).contentShape(.rect).onTapGesture { selected = folder.id }
                        .background(selected == folder.id ? Color.accentColor.opacity(0.12) : .clear, in: .rect(cornerRadius: 6))
                        .accessibilityAddTraits(.isButton).accessibilityAction { selected = folder.id }
                }
                HStack {
                    Button { search.chooseFolder() } label: { Image(systemName: "plus") }.help("Add Folder")
                    Button {
                        if let folder = search.snapshot.folders.first(where: { $0.id == selected }) { search.remove(folder); selected = nil }
                    } label: { Image(systemName: "minus") }.disabled(selected == nil).help("Remove selected folder from search")
                    Spacer()
                    Text("Removing a folder removes its search entries, never its files.").font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text("Indexed folders") } footer: { Text("Search can only reach folders you’ve granted.") }
            Section("What gets indexed") {
                HStack {
                    Text("File types")
                    Spacer()
                    ForEach(["md", "markdown", "mdx"], id: \.self) { ext in
                        Toggle(".\(ext)", isOn: Binding(get: { search.options.extensions.contains(ext) }, set: { enabled in
                            search.options.extensions.removeAll { $0 == ext }
                            if enabled { search.options.extensions.append(ext) }
                        })).toggleStyle(.checkbox).fixedSize()
                    }
                }
                Toggle(isOn: $search.options.metadata) {
                    Text("Index OKF frontmatter")
                    Text("Title, description, type and tags become searchable and filterable.")
                }
                Toggle(isOn: $search.options.headings) {
                    Text("Index headings as context")
                    Text("Shows which section contains a literal match. Headings remain part of the note’s searchable text.")
                }
                TextField("Skip folders named", text: $search.options.skippedFolders)
                Text("Comma-separated names, applied inside every indexed folder. Hidden files and symlinks are skipped.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Searching") {
                Picker("Default scope", selection: $search.options.defaultScope) {
                    Text("Current Library").tag("library")
                    Text("Current OKF bundle").tag("bundle")
                    Text("All Folders").tag("all")
                }
                Toggle(isOn: $search.options.related) {
                    Text("Include related results")
                    Text("Allows Spotlight to find related meaning when available on this Mac. Related results open at the top of the note.")
                }
            }
            Section("System Spotlight") {
                Text("Notes donated by Markify may also appear in system Spotlight for anyone using this Mac account. The index stays on this Mac. macOS manages Spotlight categories, privacy and ranking.")
                Button("Spotlight Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Spotlight-Settings.extension") { NSWorkspace.shared.open(url) }
                }
            }
            Section {
                Button("Delete Search Index…", role: .destructive) { deleting = true }
                Text("Removes Markify’s search entries and pauses indexing until you rebuild. Your files and macOS’s independent file index are untouched.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
            .onAppear { search.start() }
            .onChange(of: search.options) { _, _ in search.saveOptions() }
            .alert("Delete Search Index?", isPresented: $deleting) {
                Button("Cancel", role: .cancel) {}
                Button("Delete Index", role: .destructive) { search.deleteIndex() }
            } message: { Text("Your notes stay on disk. Choose Rebuild Index to resume Library search.") }
    }
}
