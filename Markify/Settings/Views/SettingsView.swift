import SwiftUI
import AppKit

struct SettingsView: View {
    @AppStorage("newDocumentLocation") private var newDocumentLocation = "Ask each time"
    @AppStorage("libraryBookmark") private var libraryBookmark = Data()
    @AppStorage("reloadExternalChanges") private var reloadExternalChanges = true
    @AppStorage("startup") private var startup = "Reopen last documents"
    @AppStorage("defaultLens") private var defaultLens = "Rendered"
    @AppStorage("rememberLens") private var rememberLens = true
    @AppStorage("lineWidth") private var lineWidth = 640.0
    @AppStorage("fadeToolbar") private var fadeToolbar = true
    @AppStorage("showWordCount") private var showWordCount = true
    @AppStorage("appearance") private var appearance = "Auto"
    @AppStorage("showStatusCapsule") private var showStatusCapsule = true
    @AppStorage("writingTools") private var writingTools = true
    @AppStorage("generateAtCaret") private var generateAtCaret = true
    @AppStorage("suggestTitleTags") private var suggestTitleTags = false
    @AppStorage("generationTone") private var generationTone = "Match document"
    @AppStorage("useSectionContext") private var useSectionContext = true
    @State private var selectedTab = Tab.general

    private enum Tab { case general, editor, appearance, intelligence, shortcuts }

    var body: some View {
        TabView(selection: $selectedTab) {
            Form {
                Section("Documents") {
                    Picker("New documents are saved to", selection: $newDocumentLocation) {
                        Text("Ask each time").tag("Ask each time")
                        Text("Library").tag("Library")
                    }
                    HStack {
                        Text("Library location")
                        Spacer()
                        Text(libraryPath).foregroundStyle(.secondary).lineLimit(1)
                        Button("Choose…", action: chooseLibrary)
                    }
                    Toggle("Reload when changed on disk", isOn: $reloadExternalChanges)
                }
                Section("Startup") {
                    Picker("On launch", selection: $startup) {
                        Text("Reopen last documents").tag("Reopen last documents")
                        Text("New document").tag("New document")
                        Text("Library").tag("Library")
                    }
                }
            }.formStyle(.grouped).tabItem { Label("General", systemImage: "gearshape") }.tag(Tab.general)

            Form {
                Section("Lenses") {
                    Picker("Open documents in", selection: $defaultLens) {
                        Text("Rendered").tag("Rendered")
                        Text("Markdown").tag("Markdown")
                        Text("Last used").tag("Last used")
                    }
                    Toggle("Remember lens per document", isOn: $rememberLens)
                }
                Section("Typography") {
                    HStack { Text("Line width"); Slider(value: $lineWidth, in: 560...860, step: 10); Text("\(Int(lineWidth)) pt").monospacedDigit() }
                }
                Section("Window") {
                    Toggle("Fade toolbar while typing", isOn: $fadeToolbar)
                    Toggle("Show word count", isOn: $showWordCount)
                }
            }.formStyle(.grouped).tabItem { Label("Editor", systemImage: "character.cursor.ibeam") }.tag(Tab.editor)

            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        Text("Light").tag("Light")
                        Text("Dark").tag("Dark")
                        Text("Auto").tag("Auto")
                    }.pickerStyle(.segmented)
                }
                Section("Controls") { Toggle("Show status capsule", isOn: $showStatusCapsule) }
            }.formStyle(.grouped).tabItem { Label("Appearance", systemImage: "circle.lefthalf.filled") }.tag(Tab.appearance)

            Form {
                Section("Apple Intelligence") {
                    Label("Runs on this Mac. Your text never leaves it.", systemImage: "apple.intelligence")
                    Toggle("Writing Tools in the format bar", isOn: $writingTools)
                    Toggle("Generate at caret with ⌘↩", isOn: $generateAtCaret)
                    Toggle("Suggest title & tags", isOn: $suggestTitleTags)
                }
                Section("Generation") {
                    Picker("Default tone", selection: $generationTone) {
                        ForEach(["Match document", "Friendly", "Professional", "Concise"], id: \.self) { Text($0).tag($0) }
                    }
                    Toggle("Use surrounding section as context", isOn: $useSectionContext)
                }
            }.formStyle(.grouped).tabItem { Label("Intelligence", systemImage: "apple.intelligence") }.tag(Tab.intelligence)

            Form {
                Section("Editor") {
                    LabeledContent("Toggle Markdown", value: "⌘/")
                    LabeledContent("Library", value: "⌃⌘S")
                    LabeledContent("Find", value: "⌘F")
                    LabeledContent("Replace", value: "⌥⌘F")
                }
                Section("Formatting") {
                    LabeledContent("Bold", value: "⌘B")
                    LabeledContent("Italic", value: "⌘I")
                    LabeledContent("Link", value: "⌘K")
                }
            }.formStyle(.grouped).tabItem { Label("Shortcuts", systemImage: "keyboard") }.tag(Tab.shortcuts)
        }
        .frame(width: 780, height: 480)
        .onAppear { selectedTab = .general }
        .onDisappear { selectedTab = .general }
    }

    private var libraryPath: String {
        var stale = false
        if let url = try? URL(resolvingBookmarkData: libraryBookmark, options: .withSecurityScope, bookmarkDataIsStale: &stale), !stale {
            return url.path
        }
        return "~/Documents/Markify"
    }

    private func chooseLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            libraryBookmark = (try? url.bookmarkData(options: .withSecurityScope)) ?? Data()
        }
    }
}
