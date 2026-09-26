import SwiftUI
import AppKit
import FoundationModels
import UniformTypeIdentifiers

struct SettingsView: View {
    @AppStorage("newDocumentLocation") private var newDocumentLocation = "Ask each time"
    @AppStorage("libraryBookmark") private var libraryBookmark = Data()
    @AppStorage("imageFolder") private var imageFolder = "./assets"
    @AppStorage("startup") private var startup = "Reopen last documents"
    @AppStorage("defaultLens") private var defaultLens = "Rendered"
    @AppStorage("rememberLens") private var rememberLens = true
    @AppStorage("proseFont") private var proseFont = "New York"
    @AppStorage("markdownFont") private var markdownFont = "SF Mono"
    @AppStorage("lineWidth") private var lineWidth = 640.0
    @AppStorage("fadeToolbar") private var fadeToolbar = true
    @AppStorage("showWordCount") private var showWordCount = true
    @AppStorage("appearance") private var appearance = "Auto"
    @AppStorage("pageColor") private var pageColor = "Paper"
    @AppStorage("codeTheme") private var codeTheme = "Match appearance"
    @AppStorage("glassStyle") private var glassStyle = "System"
    @AppStorage("accentColor") private var accentColor = "Multicolor"
    @AppStorage("showStatusCapsule") private var showStatusCapsule = true
    @AppStorage("writingTools") private var writingTools = true
    @AppStorage("generateAtCaret") private var generateAtCaret = true
    @AppStorage("suggestTitleTags") private var suggestTitleTags = false
    @AppStorage("generationTone") private var generationTone = "Match document"
    @AppStorage("useSectionContext") private var useSectionContext = true
    @AppStorage(Shortcuts.storageKey) private var shortcutOverrides = ""
    @State private var selectedTab = Tab.general
    @State private var isDefaultApp = false
    @State private var recording: String?
    @State private var recordMonitor: Any?

    private enum Tab { case general, editor, appearance, intelligence, shortcuts }
    private var accent: Color { AccentChoice.color(accentColor) }

    var body: some View {
        TabView(selection: $selectedTab) {
            general.tabItem { Label("General", systemImage: "gearshape") }.tag(Tab.general)
            editor.tabItem { Label("Editor", systemImage: "character.cursor.ibeam") }.tag(Tab.editor)
            appearanceTab.tabItem { Label("Appearance", systemImage: "circle.lefthalf.filled") }.tag(Tab.appearance)
            intelligence.tabItem { Label("Intelligence", systemImage: "apple.intelligence") }.tag(Tab.intelligence)
            shortcuts.tabItem { Label("Shortcuts", systemImage: "keyboard") }.tag(Tab.shortcuts)
        }
        .frame(width: 780, height: 520)
        .tint(accent)
        .preferredColorScheme(appearance == "Auto" ? nil : appearance == "Dark" ? .dark : .light)
        .onAppear { selectedTab = .general; refreshDefaultApp() }
        .onDisappear { selectedTab = .general; stopRecording() }
    }

    // MARK: General

    private var general: some View {
        Form {
            Section("Documents") {
                Picker("New documents are saved to", selection: $newDocumentLocation) {
                    Text("Library").tag("Library")
                    Text("Ask each time").tag("Ask each time")
                }
                LabeledContent {
                    Button("Choose…", action: chooseLibrary)
                } label: {
                    Text("Library location")
                    Text(librarySummary).lineLimit(1).truncationMode(.middle)
                }
                Picker("Save pasted images to", selection: $imageFolder) {
                    Text("./assets").tag("./assets")
                    Text("./images").tag("./images")
                    Text("Same folder as document").tag("./")
                }
            }
            Section("Startup") {
                Picker("On launch", selection: $startup) {
                    Text("Reopen last documents").tag("Reopen last documents")
                    Text("New document").tag("New document")
                    Text("Library").tag("Library")
                }
                LabeledContent {
                    Button("Make Default", action: makeDefaultApp).disabled(isDefaultApp)
                } label: {
                    Text("Default Markdown app")
                    Text(isDefaultApp ? "Markify opens .md files." : "Another app opens .md files.")
                }
            }
        }.formStyle(.grouped)
    }

    private var libraryURL: URL? {
        var stale = false
        if !libraryBookmark.isEmpty, let url = try? URL(resolvingBookmarkData: libraryBookmark, options: .withSecurityScope, bookmarkDataIsStale: &stale), !stale {
            return url
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("Markify")
    }

    private var librarySummary: String {
        guard let url = libraryURL else { return "~/Documents/Markify" }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let count = ((try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "md" }.count
        let path = (url.path as NSString).abbreviatingWithTildeInPath
        return "\(path) · \(count) \(count == 1 ? "note" : "notes")"
    }

    private func chooseLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            libraryBookmark = (try? url.bookmarkData(options: .withSecurityScope)) ?? Data()
        }
    }

    private func refreshDefaultApp() {
        isDefaultApp = NSWorkspace.shared.urlForApplication(toOpen: .markdown)?.standardizedFileURL.path == Bundle.main.bundleURL.standardizedFileURL.path
    }

    private func makeDefaultApp() {
        Task {
            for type in [UTType.markdown, UTType(importedAs: "com.mdx")] {
                try? await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type)
            }
            refreshDefaultApp()
        }
    }

    // MARK: Editor

    private var editor: some View {
        Form {
            Section("Lenses") {
                Picker("Open documents in", selection: $defaultLens) {
                    Text("Rendered").tag("Rendered")
                    Text("Markdown").tag("Markdown")
                    Text("Last used").tag("Last used")
                }
                Toggle(isOn: $rememberLens) {
                    Text("Remember lens per document")
                    Text("Reopens each file the way you left it.")
                }
            }
            Section("Typography") {
                Picker("Prose font", selection: $proseFont) {
                    Text("New York").tag("New York")
                    Text("SF Pro").tag("SF Pro")
                }
                Picker("Markdown font", selection: $markdownFont) {
                    Text("SF Mono").tag("SF Mono")
                    Text("Menlo").tag("Menlo")
                }
                LabeledContent("Line width") {
                    HStack {
                        Text("Narrow").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $lineWidth, in: 560...860, step: 10).frame(width: 220)
                        Text("Wide").font(.caption).foregroundStyle(.secondary)
                        Text("\(Int(lineWidth)) pt").monospacedDigit().frame(width: 52, alignment: .trailing)
                    }
                }
            }
            Section("Window") {
                Toggle("Fade toolbar while typing", isOn: $fadeToolbar)
                Toggle("Show word count", isOn: $showWordCount)
            }
        }.formStyle(.grouped)
    }

    // MARK: Appearance

    private var appearanceTab: some View {
        Form {
            Section("Appearance") {
                LabeledContent("Theme") {
                    HStack(spacing: 14) {
                        ForEach(["Light", "Dark", "Auto"], id: \.self) { themeThumbnail($0) }
                    }
                }
                Picker("Page color", selection: $pageColor) {
                    Text("Paper").tag("Paper")
                    Text("White").tag("White")
                    Text("System").tag("System")
                }
                Picker("Code theme", selection: $codeTheme) {
                    Text("Match appearance").tag("Match appearance")
                    Text("Monochrome").tag("Monochrome")
                }
            }
            Section("Controls") {
                Picker("Glass style", selection: $glassStyle) {
                    Text("System").tag("System")
                    Text("Clear").tag("Clear")
                    Text("Tinted").tag("Tinted")
                }.pickerStyle(.segmented).frame(maxWidth: 360)
                LabeledContent("Accent color") {
                    HStack(spacing: 8) {
                        ForEach(AccentChoice.all, id: \.self) { accentSwatch($0) }
                    }
                }
                Toggle("Show status capsule", isOn: $showStatusCapsule)
            }
        }.formStyle(.grouped)
    }

    private func themeThumbnail(_ name: String) -> some View {
        let selected = appearance == name
        return Button { appearance = name } label: {
            VStack(spacing: 6) {
                ZStack {
                    switch name {
                    case "Light": thumbnailPage(dark: false)
                    case "Dark": thumbnailPage(dark: true)
                    default:
                        HStack(spacing: 0) { thumbnailPage(dark: false); thumbnailPage(dark: true) }
                    }
                }
                .frame(width: 78, height: 50)
                .clipShape(.rect(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))
                .padding(3)
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(selected ? accent : .clear, lineWidth: 3))
                Text(name).font(.system(size: 12, weight: selected ? .semibold : .regular))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name) theme")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func thumbnailPage(dark: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            PageColor.color(pageColor, dark: dark)
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 2).frame(width: 26, height: 5)
                RoundedRectangle(cornerRadius: 2).frame(width: 40, height: 3)
                RoundedRectangle(cornerRadius: 2).frame(width: 34, height: 3)
            }
            .foregroundStyle(dark ? Color.white.opacity(0.6) : Color.black.opacity(0.45))
            .padding(10)
        }
    }

    private func accentSwatch(_ name: String) -> some View {
        let selected = accentColor == name
        return Button { accentColor = name } label: {
            Group {
                if name == "Multicolor" {
                    Circle().fill(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red], center: .center))
                } else {
                    Circle().fill(AccentChoice.color(name))
                }
            }
            .frame(width: 16, height: 16)
            .padding(2)
            .background(Circle().fill(selected ? Color.white : .clear))
            .overlay(Circle().strokeBorder(selected ? AccentChoice.color(name) : .clear, lineWidth: 1.5).padding(-1.5))
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel("\(name) accent")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Intelligence

    private var intelligence: some View {
        Form {
            Section { statusCard }
            if SystemLanguageModel.default.availability != .unavailable(.deviceNotEligible) {
                Section("Features") {
                    Toggle("Writing Tools in the format bar", isOn: $writingTools)
                    Toggle(isOn: $generateAtCaret) {
                        Text("Generate at caret with \(Shortcuts.display(Shortcuts.key("generate", stored: shortcutOverrides)))")
                        Text("Also available as /write in the insert menu.")
                    }
                    Toggle(isOn: $suggestTitleTags) {
                        Text("Suggest title & tags for new documents")
                        Text("Written to frontmatter only after you accept.")
                    }
                }
                Section("Generation") {
                    Picker("Default tone", selection: $generationTone) {
                        ForEach(["Match document", "Friendly", "Professional", "Concise"], id: \.self) { Text($0).tag($0) }
                    }
                    Toggle(isOn: $useSectionContext) {
                        Text("Use surrounding section as context")
                        Text("Helps generated text match your voice.")
                    }
                }
            }
        }.formStyle(.grouped)
    }

    private var statusCard: some View {
        let status: (title: String, detail: String) = switch SystemLanguageModel.default.availability {
        case .available: ("Apple Intelligence is on", "On-device model ready. Markify never sends your text off this Mac.")
        case .unavailable(.appleIntelligenceNotEnabled): ("Apple Intelligence is off", "Turn on Apple Intelligence in System Settings to use these features.")
        case .unavailable(.modelNotReady): ("Preparing Apple Intelligence", "The on-device model is downloading. Features turn on when it's ready.")
        case .unavailable(.deviceNotEligible): ("Apple Intelligence isn't available", "This Mac can't run Apple Intelligence.")
        @unknown default: ("Apple Intelligence is unavailable", "Check Apple Intelligence in System Settings.")
        }
        return HStack(spacing: 12) {
            Image(systemName: "apple.intelligence")
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 18))
                .frame(width: 36, height: 36)
                .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(status.title).fontWeight(.semibold)
                Text(status.detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer()
            if SystemLanguageModel.default.availability == .unavailable(.modelNotReady) { ProgressView().controlSize(.small) }
            Button("System Settings…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") { NSWorkspace.shared.open(url) }
            }
        }
    }

    // MARK: Shortcuts

    private var shortcuts: some View {
        Form {
            Text("Double-click a shortcut to change it").font(.system(size: 12)).foregroundStyle(.secondary)
            ForEach(Shortcuts.sections, id: \.self) { section in
                Section(section) {
                    if section == "Editor" { LabeledContent("Insert block") { keycap("/") } }
                    ForEach(Shortcuts.actions.filter { $0.section == section }) { action in
                        LabeledContent(action.title) {
                            keycap(recording == action.id ? "Type shortcut…" : Shortcuts.display(Shortcuts.key(action.id, stored: shortcutOverrides)),
                                   active: recording == action.id)
                                .onTapGesture(count: 2) { startRecording(action.id) }
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Restore Defaults") { shortcutOverrides = ""; stopRecording() }.disabled(shortcutOverrides.isEmpty || shortcutOverrides == "{}")
            }
        }.formStyle(.grouped)
    }

    private func keycap(_ text: String, active: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .padding(.vertical, 2).padding(.horizontal, 8)
            .background(active ? accent.opacity(0.18) : Color.primary.opacity(0.06), in: .rect(cornerRadius: 6))
            .overlay(alignment: .bottom) { RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.12)).frame(height: 1).padding(.horizontal, 2) }
    }

    /// Records the next ⌘ or ⌃ key press as the action's shortcut; Esc cancels.
    private func startRecording(_ id: String) {
        stopRecording()
        recording = id
        recordMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stopRecording(); return nil }
            guard let spec = Shortcuts.spec(from: event) else { NSSound.beep(); return nil }
            var overrides = Shortcuts.overrides(shortcutOverrides)
            let defaultKey = Shortcuts.actions.first { $0.id == id }?.key
            // A key taken by another action moves here; that action falls back to nothing until reassigned.
            for other in Shortcuts.actions where other.id != id && Shortcuts.key(other.id, stored: shortcutOverrides) == spec {
                overrides[other.id] = ""
            }
            overrides[id] = spec == defaultKey ? nil : spec
            shortcutOverrides = Shortcuts.encode(overrides)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let recordMonitor { NSEvent.removeMonitor(recordMonitor) }
        recordMonitor = nil
        recording = nil
    }
}
