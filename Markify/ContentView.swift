import AppKit
import FoundationModels
import Markdown
import SwiftUI
import UniformTypeIdentifiers

private typealias Text = SwiftUI.Text

struct ContentView: View {
    @Binding var document: MarkifyDocument
    let fileURL: URL?
    @AppStorage("showWordCount") private var showWordCount = true
    @AppStorage("showStatusCapsule") private var showStatusCapsule = true
    @AppStorage("defaultLens") private var defaultLens = "Rendered"
    @AppStorage("appearance") private var appearance = "Auto"
    @AppStorage("libraryBookmark") private var libraryBookmark = Data()
    @AppStorage("fadeToolbar") private var fadeToolbar = true
    @AppStorage("lineWidth") private var lineWidth = 640.0
    @State private var markdownLens = false
    @State private var sidebarOpen = false
    @State private var chromeVisible = true
    @State private var selectedRange = NSRange(location: 0, length: 0)
    @State private var selectionRect = CGRect.zero
    @State private var formatBarVisible = false
    @State private var formatBarTask: Task<Void, Never>?
    @State private var textView: NSTextView?
    @State private var showFind = false
    @State private var query = ""
    @State private var replacement = ""
    @State private var matchCase = false
    @State private var slashQuery: String?
    @State private var slashSelection = 0
    @State private var showAI = false
    @State private var showWritingMenu = false
    @State private var selectionPrompt = ""
    @State private var writingMenuHeight: CGFloat = 320
    @State private var aiPrompt = ""
    @State private var aiOutput = ""
    @State private var aiBusy = false
    @State private var aiError: String?
    @State private var aiTask: Task<Void, Never>?
    @State private var aiInsertion = 0
    @State private var aiPlacement: AIPlacement = .atCaret
    @State private var aiSelectionSource = ""
    @State private var hasTyped = false
    @State private var librarySearch = ""
    @State private var libraryFolder: URL?
    @State private var libraryNotes: [LibraryNote] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var page: Color { colorScheme == .dark ? Color(red: 30/255, green: 30/255, blue: 32/255) : Color(red: 252/255, green: 251/255, blue: 249/255) }
    private var glassStrong: Color { colorScheme == .dark ? Color(red: 50/255, green: 50/255, blue: 56/255).opacity(0.78) : Color.white.opacity(0.78) }
    private var field: Color { colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05) }
    private var rule: Color { colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.09) }
    private var accentSoft: Color { Color.accentColor.opacity(colorScheme == .dark ? 0.22 : 0.13) }
    private var title: String { fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled" }
    private var wordCount: Int { document.text.split(whereSeparator: \.isWhitespace).count }
    private var aiAvailability: SystemLanguageModel.Availability { SystemLanguageModel.default.availability }

    var body: some View {
        GeometryReader { geometry in
            let columnWidth = min(markdownLens ? lineWidth + 20 : lineWidth, max(geometry.size.width - 48, 280))
            ZStack(alignment: .topLeading) {
                page.ignoresSafeArea()
                NativeEditor(text: $document.text, fileURL: fileURL, columnWidth: columnWidth, markdownLens: markdownLens, findQuery: query, matchCase: matchCase, selectedRange: $selectedRange, textView: $textView, onType: {
                    hasTyped = true
                    if fadeToolbar { withAnimation(.easeOut(duration: 0.4)) { chromeVisible = false } }
                }, onSlash: { query in
                    if slashQuery != query { slashSelection = 0 }
                    slashQuery = query
                }, onSlashKey: handleSlashKey, onSelectionRect: { selectionRect = $0 })
                .frame(width: columnWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 56)

                if document.text.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Untitled").font(.system(size: 36, weight: .bold, design: .serif))
                        Text("Start writing, or type / to insert a block.").font(.system(size: 18, design: .serif))
                    }
                    .foregroundStyle(.tertiary)
                    .padding(.top, 96)
                    .frame(width: min(lineWidth, geometry.size.width - 48), alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .allowsHitTesting(false)
                }
                if document.text.isEmpty && !hasTyped {
                    HStack(spacing: 18) {
                        Text("⌘/ Markdown")
                        Text("⌃⌘S Library")
                        Text("⌘O Open file")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 26)
                    .allowsHitTesting(false)
                }

                if sidebarOpen {
                    sidebar
                        .padding(8)
                        .transition(.move(edge: .leading))
                        .zIndex(2)
                }

                GlassEffectContainer {
                    HStack(spacing: 10) {
                        Button { toggleSidebar() } label: { Image(systemName: "sidebar.left").frame(width: 36, height: 36) }
                            .buttonStyle(.plain)
                            .glassEffect(in: .circle)
                            .accessibilityLabel(sidebarOpen ? "Hide Library" : "Show Library")
                        Menu {
                            Button("Rename…") { NSDocumentController.shared.currentDocument?.rename(nil) }
                            Button("Move To…") { NSDocumentController.shared.currentDocument?.move(nil) }
                            Button("Browse All Versions…") { NSDocumentController.shared.currentDocument?.browseVersions(nil) }
                        } label: {
                            HStack(spacing: 6) {
                                Text(title).font(.system(size: 13, weight: .semibold))
                                if NSApp.keyWindow?.isDocumentEdited == true {
                                    Text("— Edited").font(.system(size: 13)).foregroundStyle(.secondary)
                                }
                            }.padding(.horizontal, 15).frame(height: 36)
                        }
                            .buttonStyle(.plain)
                            .menuIndicator(.hidden)
                            .glassEffect(in: .capsule)
                            .offset(x: sidebarOpen ? 148 : 0)
                        Spacer()
                        HStack(spacing: 3) {
                            if aiAvailability != .unavailable(.deviceNotEligible) {
                                Button { showAI.toggle(); showWritingMenu = false } label: { Image(systemName: "apple.intelligence").symbolRenderingMode(.multicolor).frame(width: 30, height: 30) }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Apple Intelligence")
                            }
                            Toggle("MD", isOn: Binding(get: { markdownLens }, set: { _ in toggleLens() }))
                                .toggleStyle(.button)
                                .buttonStyle(.plain)
                                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(markdownLens ? .white : .primary)
                                .background(markdownLens ? Color.accentColor : .clear, in: .capsule)
                                .frame(height: 30)
                                .help("Show Markdown ⌘/")
                                .accessibilityLabel("Show Markdown")
                            Menu {
                                if let fileURL { ShareLink(item: fileURL) { Text("Share") } }
                                else { Button("Share") { }.disabled(true) }
                                Menu("Export") {
                                    Button("HTML") { exportHTML() }
                                    Button("PDF") { exportPDF() }
                                }
                                Button("Find") { showFind = true }
                                Toggle("Show Word Count", isOn: $showWordCount)
                                SettingsLink { Text("Settings") }
                            } label: { Image(systemName: "ellipsis").frame(width: 30, height: 30) }
                            .buttonStyle(.plain)
                            .menuIndicator(.hidden)
                            .accessibilityLabel("More")
                        }
                        .padding(3)
                        .glassEffect(in: .capsule)
                    }
                    .padding(.leading, 88).padding(.trailing, 12).padding(.top, 4)
                }
                .opacity(chromeVisible ? 1 : 0)
                .allowsHitTesting(chromeVisible)
                .zIndex(3)

                if showStatusCapsule {
                    Text("\(showWordCount ? "\(wordCount) words · " : "")\(markdownLens ? "Markdown" : "Rendered")")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12).frame(height: 28)
                        .glassEffect(in: .capsule)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(.trailing, 16).padding(.bottom, 14)
                        .opacity(chromeVisible ? 1 : 0)
                        .allowsHitTesting(chromeVisible)
                }
                if showFind { findPanel.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(.top, 56).padding(.trailing, 12).zIndex(4) }
                if showAI { aiPanel.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(.top, 56).padding(.trailing, 12).zIndex(4) }
                if formatBarVisible && slashQuery == nil {
                    formatBar
                        .position(x: min(max(selectionRect.midX, 210), geometry.size.width - 210),
                                  y: max(62, selectionRect.minY - 26))
                        .zIndex(5)
                }
                if showWritingMenu && formatBarVisible {
                    let below = selectionRect.maxY + 30
                    let top = below + writingMenuHeight + 12 < geometry.size.height ? below : max(56, selectionRect.minY - 52 - writingMenuHeight)
                    writingMenu
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { writingMenuHeight = $0 }
                        .position(x: min(max(selectionRect.midX, 182), geometry.size.width - 182),
                                  y: top + writingMenuHeight / 2)
                        .zIndex(6)
                }
                if let slashQuery {
                    slashMenu(query: slashQuery)
                        .position(x: min(max(selectionRect.midX + 155, 160), geometry.size.width - 160),
                                  y: selectionRect.maxY + 438 < geometry.size.height ? selectionRect.maxY + 218 : max(218, selectionRect.minY - 218))
                        .zIndex(5)
                }
            }
            .onContinuousHover { phase in
                if case .active = phase { withAnimation(.easeOut(duration: 0.4)) { chromeVisible = true } }
            }
            .onExitCommand { showWritingMenu = false; showAI = false; showFind = false; sidebarOpen = false }
        }
        .frame(minWidth: 520, minHeight: 400)
        .ignoresSafeArea(.container, edges: .top)
        .navigationTitle("")
        .toolbar(removing: .title)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .background(WindowConfiguration())
        .preferredColorScheme(appearance == "Auto" ? nil : appearance == "Dark" ? .dark : .light)
        .onAppear { markdownLens = defaultLens == "Markdown"; loadLibrary() }
        .onDisappear { libraryFolder?.stopAccessingSecurityScopedResource() }
        .onChange(of: libraryBookmark) { _, _ in loadLibrary() }
        .onChange(of: selectedRange) { _, range in
            formatBarTask?.cancel()
            formatBarVisible = false
            if range.length > 0 {
                formatBarTask = Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    if !Task.isCancelled { formatBarVisible = true }
                }
            } else { showWritingMenu = false }
        }
        .background {
            Button("Toggle Markdown") { toggleLens() }.keyboardShortcut("/", modifiers: .command).hidden()
            Button("Toggle Library") { toggleSidebar() }.keyboardShortcut("s", modifiers: [.control, .command]).hidden()
            Button("Find") { showFind = true }.keyboardShortcut("f", modifiers: .command).hidden()
            Button("Replace") { showFind = true }.keyboardShortcut("f", modifiers: [.option, .command]).hidden()
            Button("Bold") { wrap("**") }.keyboardShortcut("b", modifiers: .command).hidden()
            Button("Italic") { wrap("*") }.keyboardShortcut("i", modifiers: .command).hidden()
            Button("Strikethrough") { wrap("~~") }.keyboardShortcut("x", modifiers: [.shift, .command]).hidden()
            Button("Inline Code") { wrap("`") }.keyboardShortcut("e", modifiers: .command).hidden()
            Button("Link") { wrap("[", suffix: "](url)") }.keyboardShortcut("k", modifiers: .command).hidden()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search", text: $librarySearch)
            Text("Open Files").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            ForEach(NSDocumentController.shared.documents.compactMap(\.fileURL).filter {
                librarySearch.isEmpty || $0.lastPathComponent.localizedCaseInsensitiveContains(librarySearch)
            }.prefix(8), id: \.self) { url in
                Button { open(url) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.lastPathComponent).font(.system(size: 13, weight: url == fileURL ? .semibold : .regular))
                        Text(url.deletingLastPathComponent().path).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).padding(7)
            }
            Text("Library").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 12)
            if libraryFolder != nil {
                ForEach(libraryNotes.filter {
                    librarySearch.isEmpty || $0.title.localizedCaseInsensitiveContains(librarySearch) || $0.preview.localizedCaseInsensitiveContains(librarySearch)
                }) { note in
                    Button { open(note.url) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title).font(.system(size: 13))
                            Text(note.preview).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain).padding(7)
                }
            }
            Spacer()
            Button("New Document ⌘N") { NSDocumentController.shared.newDocument(nil) }
        }
        .padding(.horizontal, 12).padding(.top, 54).padding(.bottom, 12)
        .frame(width: 260).frame(maxHeight: .infinity)
        .glassEffect(in: .rect(cornerRadius: 20))
    }

    private func open(_ url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }

    private func loadLibrary() {
        libraryFolder?.stopAccessingSecurityScopedResource()
        libraryFolder = nil
        if !libraryBookmark.isEmpty {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: libraryBookmark, options: .withSecurityScope, bookmarkDataIsStale: &stale), !stale {
                libraryFolder = url
                _ = url.startAccessingSecurityScopedResource()
            }
        }
        if libraryFolder == nil {
            let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("Markify")
            if let folder, FileManager.default.fileExists(atPath: folder.path) { libraryFolder = folder }
        }
        refreshLibrary()
    }

    private func refreshLibrary() {
        guard let libraryFolder,
              let urls = try? FileManager.default.contentsOfDirectory(at: libraryFolder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return }
        libraryNotes = urls.filter { $0.pathExtension == "md" }.compactMap { url in
            guard let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let lines = source.split(separator: "\n", omittingEmptySubsequences: true)
            let heading = lines.first { $0.hasPrefix("# ") }.map { String($0.dropFirst(2)) }
            let preview = lines.first { !$0.hasPrefix("#") && !$0.hasPrefix("---") }.map(String.init) ?? ""
            return LibraryNote(url: url, title: heading ?? url.deletingPathExtension().lastPathComponent, preview: preview)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private var findPanel: some View {
        VStack(spacing: 6) {
            HStack {
                TextField("Find", text: $query).onSubmit(findNext)
                Button("‹", action: findPrevious)
                Button("›", action: findNext)
                Toggle("Aa", isOn: $matchCase).toggleStyle(.button)
            }
            HStack {
                TextField("Replace", text: $replacement)
                Button("Replace", action: replaceOne)
                Button("All", action: replaceAll)
            }
        }
        .padding(8).frame(width: 380)
        .glassEffect(in: .rect(cornerRadius: 18))
    }

    private var formatBar: some View {
        HStack(spacing: 1) {
            if aiAvailability != .unavailable(.deviceNotEligible) {
                Button {
                    showWritingMenu.toggle()
                    showAI = false
                    if showWritingMenu { aiTask?.cancel(); aiBusy = false; aiOutput = ""; aiError = nil }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "apple.intelligence").symbolRenderingMode(.multicolor).font(.system(size: 14))
                        Text("Writing Tools").font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.leading, 10).padding(.trailing, 12).frame(height: 32)
                    .background(showWritingMenu ? field : .clear, in: .capsule)
                    .contentShape(.capsule)
                }
                .help("Writing Tools ⇧⌘W")
                .accessibilityLabel("Writing Tools")
                formatDivider
            }
            Menu {
                ForEach(["Body", "Title", "Heading", "Subheading", "Quote", "Code block", "Callout", "Bulleted", "Numbered", "Task"], id: \.self) { style in
                    Button(style) { applyBlockStyle(style) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(currentBlockStyle)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(.secondary)
                .padding(.leading, 12).padding(.trailing, 10).frame(height: 32)
                .contentShape(.capsule)
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Block style, \(currentBlockStyle)")
            formatDivider
            tool("bold", help: "Bold", marker: "**")
            tool("italic", help: "Italic", marker: "*")
            tool("strikethrough", help: "Strikethrough", marker: "~~")
            tool("chevron.left.forwardslash.chevron.right", help: "Inline Code", marker: "`")
            formatDivider
            Button { wrap("[", suffix: "](url)") } label: { Image(systemName: "link").frame(width: 32, height: 32).contentShape(.circle) }
                .help("Link ⌘K").accessibilityLabel("Link")
        }
        .font(.system(size: 13))
        .buttonStyle(.plain)
        .padding(3)
        .frame(height: 38)
        .background(glassStrong, in: .capsule)
        .glassEffect(in: .capsule)
    }

    private var formatDivider: some View {
        Rectangle().fill(rule).frame(width: 1, height: 18).padding(.horizontal, 2)
    }

    private func tool(_ symbol: String, help: String, marker: String) -> some View {
        let active = isWrapped(marker)
        return Button { wrap(marker) } label: {
            Image(systemName: symbol)
                .frame(width: 32, height: 32)
                .foregroundStyle(active ? Color.accentColor : .primary)
                .background(active ? accentSoft : .clear, in: .circle)
                .contentShape(.circle)
        }
        .help(help).accessibilityLabel(help).accessibilityAddTraits(active ? .isSelected : [])
    }

    private var currentBlockStyle: String {
        let source = document.text as NSString
        guard selectedRange.location <= source.length else { return "Body" }
        let line = source.substring(with: source.lineRange(for: NSRange(location: selectedRange.location, length: 0)))
        for (pattern, style) in [("^# ", "Title"), ("^## ", "Heading"), ("^#{3,6} ", "Subheading"), ("^> \\[!", "Callout"), ("^> ", "Quote"),
                                 ("^```", "Code block"), ("^\\s*[-*+] \\[[ xX]\\] ", "Task"), ("^\\s*[-*+] ", "Bulleted"), ("^\\s*[0-9]+[.)] ", "Numbered")]
        where line.range(of: pattern, options: .regularExpression) != nil { return style }
        return "Body"
    }

    private func isWrapped(_ marker: String) -> Bool {
        let source = document.text as NSString
        let length = (marker as NSString).length
        guard selectedRange.length > 0, selectedRange.location >= length, NSMaxRange(selectedRange) + length <= source.length,
              source.substring(with: NSRange(location: selectedRange.location - length, length: length)) == marker,
              source.substring(with: NSRange(location: NSMaxRange(selectedRange), length: length)) == marker else { return false }
        guard marker == "*" else { return true }
        // A lone `*` is italic only when it is not half of a `**` bold marker, unless it's `***`.
        let before = selectedRange.location >= 2 ? source.substring(with: NSRange(location: selectedRange.location - 2, length: 1)) : ""
        let after = NSMaxRange(selectedRange) + 2 <= source.length ? source.substring(with: NSRange(location: NSMaxRange(selectedRange) + 1, length: 1)) : ""
        let triple = selectedRange.location >= 3 && source.substring(with: NSRange(location: selectedRange.location - 3, length: 3)) == "***"
        return triple || (before != "*" && after != "*")
    }

    private var writingMenu: some View {
        VStack(alignment: .leading, spacing: 6) {
            if aiAvailability == .available {
            HStack(spacing: 8) {
                Image(systemName: "apple.intelligence").symbolRenderingMode(.multicolor).font(.system(size: 14))
                TextField("Describe your change", text: $selectionPrompt)
                    .textFieldStyle(.plain)
                    .onSubmit { generateSelection("Revise the selection as follows: \(selectionPrompt). Return only the revised Markdown text.") }
                Image(systemName: "return").font(.system(size: 12)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12).frame(height: 36)
            .background(field, in: .rect(cornerRadius: 12))
            HStack(spacing: 6) {
                writingTile("Proofread", symbol: "checkmark") { openSystemWritingTools() }
                writingTile("Rewrite", symbol: "arrow.clockwise") { openSystemWritingTools() }
            }
            HStack(spacing: 6) {
                ForEach(["Friendly", "Professional", "Concise"], id: \.self) { tone in
                    Button {
                        generateSelection("Rewrite this selection in a \(tone.lowercased()) tone. Return only the revised Markdown text.")
                    } label: {
                        Text(tone).frame(maxWidth: .infinity).frame(height: 32).contentShape(.rect(cornerRadius: 10))
                    }
                    .buttonStyle(MenuRowStyle(fill: field, hover: field, radius: 10))
                }
            }
            Rectangle().fill(rule).frame(height: 1).padding(.horizontal, 6).padding(.vertical, 2)
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow {
                    writingRow("Summary", symbol: "text.alignleft") { generateSelection("Summarize this selection in one paragraph. Return only Markdown text.") }
                    writingRow("Key Points", symbol: "list.bullet") { generateSelection("Extract the key points as a Markdown list. Return only the list.") }
                }
                GridRow {
                    writingRow("List", symbol: "list.dash") { generateSelection("Turn this selection into a Markdown list. Return only the list.") }
                    writingRow("Table", symbol: "tablecells") { generateSelection("Turn this selection into a Markdown table. Return only the table.") }
                }
            }
            } else if aiAvailability == .unavailable(.appleIntelligenceNotEnabled) {
                Text("Turn on Apple Intelligence in System Settings").foregroundStyle(.secondary)
            } else if aiAvailability == .unavailable(.modelNotReady) {
                HStack { ProgressView(); Text("Preparing on-device model…") }
            }
            if aiBusy { HStack { ProgressView(); Text("Writing on this Mac…"); Button("Stop") { aiTask?.cancel(); aiBusy = false } } }
            if !aiOutput.isEmpty {
                ScrollView { Text(aiOutput).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }.frame(maxHeight: 150)
                HStack {
                    Button("Keep") { keepAIOutput() }.disabled(aiBusy)
                    Button("Discard") { aiOutput = ""; aiTask?.cancel(); aiBusy = false }
                }
            }
            if let aiError { Text(aiError).font(.caption).foregroundStyle(.red) }
            HStack {
                Text("On this Mac")
                Spacer()
                Text("Selection · \(selectionWordCount) \(selectionWordCount == 1 ? "word" : "words")")
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.top, 2).padding(.bottom, 4)
        }
        .font(.system(size: 13))
        .buttonStyle(.plain)
        .padding(8).frame(width: 340)
        .background(glassStrong, in: .rect(cornerRadius: 20))
        .glassEffect(in: .rect(cornerRadius: 20))
    }

    private func writingTile(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(Color.accentColor).frame(height: 18)
                Text(title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(MenuRowStyle(fill: field, hover: field, radius: 12))
    }

    private func writingRow(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 16)
                Text(title)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).frame(height: 30)
            .contentShape(.rect(cornerRadius: 9))
        }
        .buttonStyle(MenuRowStyle(fill: .clear, hover: field, radius: 9))
    }

    private var selectionWordCount: Int {
        guard selectedRange.length > 0, NSMaxRange(selectedRange) <= (document.text as NSString).length else { return 0 }
        return (document.text as NSString).substring(with: selectedRange).split(whereSeparator: \.isWhitespace).count
    }

    private func openSystemWritingTools() {
        showWritingMenu = false
        textView?.showWritingTools(nil)
    }

    private func generateSelection(_ action: String) {
        guard selectedRange.length > 0 else { return }
        generate(action: action, placement: .replaceSelection(selectedRange))
    }

    private var aiPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Apple Intelligence", systemImage: "apple.intelligence").fontWeight(.semibold)
                Spacer()
                Text("Whole document").font(.caption).foregroundStyle(.secondary)
            }
            switch aiAvailability {
            case .available:
                TextField("Describe a change to the document…", text: $aiPrompt)
                    .onSubmit { generate(action: aiPrompt) }
                HStack {
                    Button("Proofread") { textView?.showWritingTools(nil) }
                    Button("Rewrite…") { textView?.showWritingTools(nil) }
                }
                aiRow("Summarize", detail: "Insert at top") {
                    generate(action: "Summarize this document in one concise paragraph. Return only Markdown text.", placement: .atTop)
                }
                aiRow("Key points", detail: "New section") {
                    generate(action: "Extract the key points as a concise Markdown bullet list. Return only Markdown text.", placement: .newSection)
                }
                aiRow("Suggest title & tags", detail: "Frontmatter") {
                    generate(action: "Suggest a clear title and up to five short tags for this document.", placement: .frontmatter)
                }
                aiRow("Continue writing", detail: "At caret · ⌘↩") {
                    generate(action: "Continue this document in the same tone. Return only the continuation as Markdown.")
                }
            case .unavailable(.appleIntelligenceNotEnabled):
                Text("Turn on Apple Intelligence in System Settings").foregroundStyle(.secondary)
            case .unavailable(.modelNotReady):
                HStack { ProgressView(); Text("Preparing on-device model…") }
            case .unavailable(.deviceNotEligible):
                EmptyView()
            @unknown default:
                Text("Apple Intelligence is unavailable.")
            }
            if aiBusy { HStack { ProgressView(); Text("Writing on this Mac…"); Button("Stop") { aiTask?.cancel(); aiBusy = false } } }
            if !aiOutput.isEmpty {
                ScrollView { Text(aiOutput).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                    .frame(maxHeight: 180)
                HStack {
                    Button("Keep") { keepAIOutput() }.disabled(aiBusy)
                    Button("Discard") { aiOutput = ""; aiTask?.cancel(); aiBusy = false }
                }
            }
            if let aiError { Text(aiError).font(.caption).foregroundStyle(.red) }
            Divider()
            Text("Runs on this Mac with Apple Intelligence. Your text never leaves it.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .padding(12).frame(width: 320)
        .glassEffect(in: .rect(cornerRadius: 20))
    }

    private func aiRow(_ title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(title); Spacer(); Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary) }
                .frame(height: 32)
        }
    }

    private func generate(action: String, placement: AIPlacement = .atCaret) {
        guard aiAvailability == .available, !action.isEmpty else { return }
        aiTask?.cancel()
        aiOutput = ""
        aiError = nil
        aiBusy = true
        aiInsertion = selectedRange.location
        aiPlacement = placement
        let source: String
        if case .replaceSelection(let range) = placement, NSMaxRange(range) <= (document.text as NSString).length {
            source = (document.text as NSString).substring(with: range)
        } else { source = document.text }
        aiSelectionSource = source
        aiTask = Task {
            do {
                let session = LanguageModelSession(instructions: "You edit Markdown. Keep the response grounded in the supplied document. Return only the requested Markdown content.")
                if placement == .frontmatter {
                    let response = try await session.respond(to: "\(action)\n\nDocument:\n\(source)", generating: SuggestedFrontmatter.self)
                    if !Task.isCancelled { aiOutput = response.content.markdown }
                } else {
                    for try await snapshot in session.streamResponse(to: "\(action)\n\nDocument:\n\(source)") {
                        if Task.isCancelled { break }
                        aiOutput = snapshot.content
                    }
                }
            } catch {
                if !Task.isCancelled { aiError = error.localizedDescription }
            }
            aiBusy = false
        }
    }

    private func keepAIOutput() {
        guard !aiOutput.isEmpty, let textView else { return }
        let source = textView.string as NSString
        if case .replaceSelection(let range) = aiPlacement {
            guard NSMaxRange(range) <= source.length, source.substring(with: range) == aiSelectionSource else {
                aiError = "The selection changed while writing. Generate again to avoid replacing newer edits."
                return
            }
        }
        let edit = aiPlacement.edit(source: source as String, output: aiOutput, caret: aiInsertion)
        textView.insertText(edit.text, replacementRange: edit.range)
        aiOutput = ""
        showAI = false
        showWritingMenu = false
    }

    private func exportHTML() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = title + ".html"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let safeTitle = title.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            let html = "<!doctype html><meta charset=\"utf-8\"><title>\(safeTitle)</title>" + HTMLFormatter.format(document.text)
            try html.write(to: url, atomically: true, encoding: .utf8)
        } catch { NSAlert(error: error).runModal() }
    }

    private func exportPDF() {
        guard let textView else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = title + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try textView.dataWithPDF(inside: textView.bounds).write(to: url, options: .atomic) }
        catch { NSAlert(error: error).runModal() }
    }

    private func slashMenu(query: String) -> some View {
        let entries = SlashEntry.matching(query)
        return VStack(alignment: .leading, spacing: 2) {
            Text("Insert").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 8)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(Array(entries.enumerated()), id: \.element.title) { index, entry in
                            Button {
                                if let editor = textView, let context = SlashContext.detect(in: editor.string, selection: editor.selectedRange()) {
                                    insertSlash(entry, context: context)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: entry.symbol)
                                        .frame(width: 24, height: 24)
                                        .background(index == slashSelection ? Color.white.opacity(0.16) : Color.secondary.opacity(0.09), in: .rect(cornerRadius: 7))
                                    Text(entry.title).font(.system(size: 13))
                                    Spacer()
                                    Text(entry.shortcut).font(.system(size: 12, design: .monospaced)).opacity(0.7)
                                }
                                .padding(.horizontal, 6).frame(height: 36)
                                .foregroundStyle(index == slashSelection ? .white : .primary)
                                .background(index == slashSelection ? Color.accentColor : .clear, in: .rect(cornerRadius: 11))
                            }
                            .buttonStyle(.plain)
                            .id(entry.title)
                        }
                    }
                }
                .frame(maxHeight: 340)
                .onChange(of: slashSelection) { _, index in
                    if entries.indices.contains(index) { proxy.scrollTo(entries[index].title, anchor: .center) }
                }
            }
            Divider()
            HStack { Text("↑↓ navigate"); Spacer(); Text("↩ insert · esc dismiss") }
                .font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 8)
        }
        .padding(6).frame(width: 310)
        .glassEffect(in: .rect(cornerRadius: 18))
    }

    private func handleSlashKey(_ key: SlashKey, _ context: SlashContext) -> Bool {
        let entries = SlashEntry.matching(context.query)
        switch key {
        case .up:
            slashSelection = max(0, slashSelection - 1)
        case .down:
            slashSelection = min(entries.count - 1, slashSelection + 1)
        case .insert:
            guard entries.indices.contains(slashSelection) else { return false }
            insertSlash(entries[slashSelection], context: context)
        case .dismiss:
            slashQuery = nil
        }
        return true
    }

    private func insertSlash(_ entry: SlashEntry, context: SlashContext) {
        guard let textView else { return }
        entry.apply(to: textView, context: context)
        slashQuery = nil
    }

    private func wrap(_ prefix: String, suffix: String? = nil) {
        guard let textView else { return }
        let range = textView.selectedRange()
        let selected = (textView.string as NSString).substring(with: range)
        let closing = suffix ?? prefix
        let length = (prefix as NSString).length
        if suffix == nil, isWrapped(prefix) {
            let outer = NSRange(location: range.location - length, length: range.length + 2 * length)
            textView.insertText(selected, replacementRange: outer)
            textView.setSelectedRange(NSRange(location: outer.location, length: range.length))
            return
        }
        textView.insertText(prefix + selected + closing, replacementRange: range)
        textView.setSelectedRange(NSRange(location: range.location + (prefix as NSString).length, length: (selected as NSString).length))
    }

    private func applyBlockStyle(_ style: String) {
        guard let textView else { return }
        let source = textView.string as NSString
        let range = source.lineRange(for: textView.selectedRange())
        let line = source.substring(with: range)
        let stripped = line.replacingOccurrences(of: #"^(#{1,6} |[-*+] |[0-9]+\. |> )"#, with: "", options: .regularExpression)
        let prefix = ["Title": "# ", "Heading": "## ", "Subheading": "### ", "Quote": "> ", "Bulleted": "- ", "Numbered": "1. ", "Task": "- [ ] ", "Callout": "> [!NOTE]\n> ", "Code block": "```\n"].first { $0.key == style }?.value ?? ""
        textView.insertText(prefix + stripped + (style == "Code block" ? "\n```" : ""), replacementRange: range)
    }

    private func toggleLens() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) { markdownLens.toggle() }
        chromeVisible = true
    }
    private func toggleSidebar() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.32)) { sidebarOpen.toggle() }
        chromeVisible = true
    }
    private func findNext() { find(backward: false) }
    private func findPrevious() { find(backward: true) }
    private func find(backward: Bool) {
        guard !query.isEmpty, let textView else { return }
        let source = document.text as NSString
        let options: NSString.CompareOptions = matchCase ? [] : [.caseInsensitive]
        let start = backward ? min(selectedRange.location, source.length) : min(selectedRange.location + selectedRange.length, source.length)
        let spans = backward ? [NSRange(location: 0, length: start), NSRange(location: start, length: source.length - start)]
                             : [NSRange(location: start, length: source.length - start), NSRange(location: 0, length: start)]
        for span in spans {
            var cursor = span
            while cursor.length > 0 {
                let found = source.range(of: query, options: backward ? options.union(.backwards) : options, range: cursor)
                if found.location == NSNotFound { break }
                if markdownLens || isVisible(found, in: textView) {
                    textView.setSelectedRange(found)
                    textView.scrollRangeToVisible(found)
                    return
                }
                if backward { cursor.length = found.location - cursor.location }
                else { let end = NSMaxRange(found); cursor = NSRange(location: end, length: NSMaxRange(span) - end) }
            }
        }
    }
    private func isVisible(_ range: NSRange, in textView: NSTextView) -> Bool {
        guard let storage = textView.textStorage else { return true }
        var visible = true
        storage.enumerateAttribute(.foregroundColor, in: range) { value, _, stop in
            if let color = value as? NSColor, color.alphaComponent == 0 { visible = false; stop.pointee = true }
        }
        return visible
    }
    private func replaceOne() {
        guard selectedRange.length > 0, let textView else { return }
        textView.insertText(replacement, replacementRange: selectedRange)
        findNext()
    }
    private func replaceAll() {
        guard !query.isEmpty, let textView else { return }
        let source = document.text
        guard let regex = try? NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: query), options: matchCase ? [] : [.caseInsensitive]) else { return }
        let result = NSMutableString(string: source)
        for match in regex.matches(in: source, range: NSRange(location: 0, length: (source as NSString).length)).reversed() {
            if markdownLens || isVisible(match.range, in: textView) { result.replaceCharacters(in: match.range, with: replacement) }
        }
        textView.insertText(result as String, replacementRange: NSRange(location: 0, length: (source as NSString).length))
    }
}

struct SlashEntry {
    let title: String
    let symbol: String
    let shortcut: String
    let insertion: String

    @MainActor func apply(to editor: NSTextView, context: SlashContext) {
        let source = editor.string as NSString
        let line = source.lineRange(for: context.range)
        let prefix = source.substring(with: NSRange(location: line.location, length: context.range.location - line.location))
        var range = context.range
        var inserted = insertion
        if let lastContent = prefix.lastIndex(where: { !$0.isWhitespace }) {
            let trailing = prefix[prefix.index(after: lastContent)...].utf16.count
            range.location -= trailing
            range.length += trailing
            inserted = "\n" + insertion
        }
        editor.insertText(inserted, replacementRange: range)
        let leading = inserted.hasPrefix("\n") ? 1 : 0
        let caret: (Int, Int)? = switch title {
        case "Table": (2, 6)
        case "Code block": (4, 0)
        case "Math": (3, 0)
        case "Image": (2, 0)
        case "Frontmatter": (11, 0)
        default: nil
        }
        if let caret {
            editor.setSelectedRange(NSRange(location: range.location + leading + caret.0, length: caret.1))
        }
    }

    static let all: [Self] = [
        .init(title: "Table", symbol: "tablecells", shortcut: "| — |", insertion: "| Column | Column |\n| --- | --- |\n|  |  |"),
        .init(title: "Task list", symbol: "checklist", shortcut: "- [ ]", insertion: "- [ ] "),
        .init(title: "Code block", symbol: "curlybraces", shortcut: "```", insertion: "```\n\n```"),
        .init(title: "Callout", symbol: "info.circle", shortcut: "> [!NOTE]", insertion: "> [!NOTE]\n> "),
        .init(title: "Math", symbol: "sum", shortcut: "$$", insertion: "$$\n\n$$"),
        .init(title: "Image", symbol: "photo", shortcut: "![]()", insertion: "![]()"),
        .init(title: "Heading 1", symbol: "textformat", shortcut: "#", insertion: "# "),
        .init(title: "Heading 2", symbol: "textformat", shortcut: "##", insertion: "## "),
        .init(title: "Heading 3", symbol: "textformat", shortcut: "###", insertion: "### "),
        .init(title: "Bullet", symbol: "list.bullet", shortcut: "-", insertion: "- "),
        .init(title: "Numbered", symbol: "list.number", shortcut: "1.", insertion: "1. "),
        .init(title: "Quote", symbol: "text.quote", shortcut: ">", insertion: "> "),
        .init(title: "Divider", symbol: "minus", shortcut: "---", insertion: "---"),
        .init(title: "Footnote", symbol: "textformat.superscript", shortcut: "[^1]", insertion: "[^1]: "),
        .init(title: "Frontmatter", symbol: "tag", shortcut: "---", insertion: "---\ntags: []\ndate: \n---")
    ]

    static func matching(_ query: String) -> [Self] {
        let letters = Array(query.lowercased())
        guard !letters.isEmpty else { return all }
        return all.filter { entry in
            var remaining = entry.title.lowercased()[...]
            return letters.allSatisfy { letter in
                guard let index = remaining.firstIndex(of: letter) else { return false }
                remaining = remaining[remaining.index(after: index)...]
                return true
            }
        }
    }
}

enum AIPlacement: Equatable {
    case atCaret, atTop, newSection, frontmatter, replaceSelection(NSRange)

    func edit(source: String, output: String, caret: Int) -> (range: NSRange, text: String) {
        let length = (source as NSString).length
        let frontmatter = Self.frontmatterRange(in: source)
        switch self {
        case .replaceSelection(let range):
            return (range, output)
        case .atCaret:
            return (NSRange(location: min(caret, length), length: 0), "\n" + output + "\n")
        case .atTop:
            let location = frontmatter.map(NSMaxRange) ?? 0
            return (NSRange(location: location, length: 0), output + "\n\n")
        case .newSection:
            let separator = source.isEmpty || source.hasSuffix("\n\n") ? "" : source.hasSuffix("\n") ? "\n" : "\n\n"
            return (NSRange(location: length, length: 0), separator + "## Key points\n\n" + output + "\n")
        case .frontmatter:
            return (frontmatter ?? NSRange(location: 0, length: 0), output)
        }
    }

    private static func frontmatterRange(in source: String) -> NSRange? {
        let ns = source as NSString
        guard source.hasPrefix("---\n"),
              let regex = try? NSRegularExpression(pattern: #"(?m)^---[ \t]*$"#) else { return nil }
        let matches = regex.matches(in: source, range: NSRange(location: 0, length: ns.length))
        guard matches.count > 1, matches[0].range.location == 0 else { return nil }
        var end = NSMaxRange(matches[1].range)
        if end < ns.length, ns.character(at: end) == 10 { end += 1 }
        return NSRange(location: 0, length: end)
    }
}

@Generable
struct SuggestedFrontmatter {
    @Guide(description: "A concise title for the document") var title: String
    @Guide(description: "At most five short topic tags") var tags: [String]

    var markdown: String {
        let titleJSON = String(data: try! JSONEncoder().encode(title), encoding: .utf8)!
        let tagsJSON = String(data: try! JSONEncoder().encode(Array(tags.prefix(5))), encoding: .utf8)!
        return "---\ntitle: \(titleJSON)\ntags: \(tagsJSON)\n---\n"
    }
}

/// Filled row/tile that brightens on hover and dims while pressed, used inside glass popovers.
private struct MenuRowStyle: ButtonStyle {
    let fill: Color
    let hover: Color
    let radius: CGFloat
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(fill, in: .rect(cornerRadius: radius))
            .background(hovering ? hover : .clear, in: .rect(cornerRadius: radius))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .onHover { hovering = $0 }
    }
}

private struct LibraryNote: Identifiable {
    let url: URL
    let title: String
    let preview: String
    var id: URL { url }
}

private struct WindowConfiguration: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.title = ""
            window.styleMask.insert(.fullSizeContentView)
            window.setContentSize(NSSize(width: 980, height: 660))
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.titleVisibility = .hidden
            nsView.window?.titlebarAppearsTransparent = true
            nsView.window?.title = ""
        }
    }
}
