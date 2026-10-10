import AppKit
import FoundationModels
import Markdown
import MarkifyMarkdown
import OKFKit
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
    @AppStorage("limitLineWidth") private var limitLineWidth = false
    @AppStorage("rememberLens") private var rememberLens = true
    @AppStorage("lastLens") private var lastLens = "Rendered"
    @AppStorage("newDocumentLocation") private var newDocumentLocation = "Ask each time"
    @AppStorage("writingTools") private var writingTools = true
    @AppStorage("generateAtCaret") private var generateAtCaret = true
    @AppStorage("suggestTitleTags") private var suggestTitleTags = false
    @AppStorage("generationTone") private var generationTone = "Match document"
    @AppStorage("useSectionContext") private var useSectionContext = true
    @AppStorage("recordAIGenerated") private var recordAIGenerated = true
    @AppStorage("recordHumanGenerated") private var recordHumanGenerated = true
    @AppStorage("proseFont") private var proseFont = "New York"
    @AppStorage("markdownFont") private var markdownFont = "SF Mono"
    @AppStorage("proseSize") private var proseSize = 18.0
    @AppStorage("accentColor") private var accentColor = "Multicolor"
    @AppStorage("pageColor") private var pageColor = "Paper"
    @AppStorage("codeTheme") private var codeTheme = "Match appearance"
    @AppStorage(Shortcuts.storageKey) private var shortcutOverrides = ""
    @State private var markdownLens = false
    @State private var sidebarOpen = false
    @State private var linksOpen = false
    @State private var chromeVisible = true
    /// How far the top controls and the page move down while the window tab bar shows (#82).
    /// The page reaches under the titlebar and the controls share its row, so the tab bar would cover them.
    @State private var tabBarInset: CGFloat = 0
    @State private var selectedRange = NSRange(location: 0, length: 0)
    @State private var selectionRect = CGRect.zero
    @State private var formatBarVisible = false
    @State private var formatBarTask: Task<Void, Never>?
    @State private var textView: NSTextView?
    @State private var showFind = false
    private enum FindField { case find, replace }
    @FocusState private var findFocus: FindField?
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
    @State private var aiSuggestion: FrontmatterSuggestion?
    /// Read once off the main thread (MARKIFY-14): `SystemLanguageModel.default.availability` loads an eligibility plist, too slow for `body`.
    @State private var aiAvailability: SystemLanguageModel.Availability = .unavailable(.deviceNotEligible)
    @State private var hasTyped = false
    @State private var isNewDocument = false
    @State private var offeredTitleTags = false
    /// Frontmatter tags last mirrored onto the file's Finder tags.
    @State private var mirroredTags: [String] = []
    @State private var tagsTask: Task<Void, Never>?
    @State private var showBlockMenu = false
    @State private var blockMenuQuery = ""
    @State private var blockMenuSelection = 0
    @State private var blockMenuHeight: CGFloat = 360
    @FocusState private var blockMenuFocused: Bool
    @State private var showComposer = false
    @State private var showsTelemetryOnboarding = false
    @State private var composerPrompt = ""
    @State private var composerLength = "Medium"
    @State private var composerTone = "Match document"
    @State private var composerFormat = "Paragraphs"
    @State private var composerHeight: CGFloat = 120
    @FocusState private var composerFocused: Bool
    @State private var review: AIReview?
    @State private var reviewTitle = ""
    @State private var lastAIAction = ""
    @State private var scrollTick = 0
    /// Where the reader is, for the Contents pane: the source offset at the reading line and the scroll fraction.
    @State private var reading = (offset: 0, progress: 0.0)
    @State private var aiEdit = AIEditGuard()
    @State private var libraryFolder: URL?
    @State private var librarySubfolders: [URL] = []
    @State private var libraryNotes: [LibraryNote] = []
    @State private var knowledge: KnowledgeState?
    /// The bundle's other documents, for link completion; worked out when the bundle loads, not on every body update.
    @State private var linkTargets: [String] = []
    @State private var bundleRoot: URL?
    @State private var knowledgeTask: Task<Void, Never>?
    @State private var retargetTask: Task<Void, Never>?
    @State private var exportTask: Task<Void, Never>?
    /// The brief confirmation after Copy All, and the task that dismisses it.
    @State private var copyNotice: CopyNotice?
    @State private var copyNoticeTask: Task<Void, Never>?
    @State private var conceptCache = ConceptCache()
    @State private var derived = DocumentDerivedData()
    @State private var documentIssues: [OKFDiagnostic] = []
    @State private var watcher = BundleWatcher()
    @State private var watchedRoot: URL?
    /// The body as of the last `generated` stamp, so only content edits count as a new change.
    @State private var stampedBody: String?
    @State private var humanStampTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var page: Color { PageColor.color(pageColor, dark: colorScheme == .dark) }
    private var accent: Color { AccentChoice.color(accentColor) }
    private var strong: Double { contrast == .increased ? 1.8 : 1 }
    private var glassStrong: Color { colorScheme == .dark ? Color(red: 50/255, green: 50/255, blue: 56/255).opacity(0.78) : Color.white.opacity(0.78) }
    private var field: Color { colorScheme == .dark ? Color.white.opacity(0.08 * strong) : Color.black.opacity(0.05 * strong) }
    private var rowSel: Color { colorScheme == .dark ? Color.white.opacity(0.14 * strong) : Color.black.opacity(0.07 * strong) }
    private var rule: Color { colorScheme == .dark ? Color.white.opacity(0.12 * strong) : Color.black.opacity(0.09 * strong) }
    private var accentSoft: Color { accent.opacity(colorScheme == .dark ? 0.22 : 0.13) }
    private var title: String { fileURL?.deletingPathExtension().lastPathComponent ?? document.report?.title ?? suggestedName ?? "Untitled" }
    private var reportBase: URL? { document.remoteBase ?? (fileURL == nil ? document.report?.baseDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) } : nil) }
    /// The frontmatter title, else the first H1; names an untitled document and seeds its save panel.
    private var suggestedName: String? {
        (document.report?.title ?? Frontmatter.parse(document.text)?.title
            ?? document.text.split(separator: "\n", maxSplits: 40).first { $0.hasPrefix("# ") }
                .map { $0.dropFirst(2).trimmingCharacters(in: .whitespaces) })
            .flatMap { $0.isEmpty ? nil : $0.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: " -") }
    }
    private var theme: EditorTheme {
        EditorTheme(proseFont: proseFont, monoFont: markdownFont, proseSize: CGFloat(proseSize),
                    accent: AccentChoice.nsColor(accentColor), monochromeCode: codeTheme == "Monochrome")
    }
    /// Visible find matches: every match in the Markdown lens, only rendered text in the Rendered lens.
    private var findMatches: [NSRange] {
        guard showFind, !query.isEmpty, let textView else { return [] }
        return derived.matches(in: document.text, query: query, matchCase: matchCase)
            .filter { markdownLens || isVisible($0, in: textView) }
    }
    private func shortcut(_ id: String) -> KeyboardShortcut? { Shortcuts.keyboardShortcut(id, stored: shortcutOverrides) }
    private func shortcutLabel(_ id: String) -> String { Shortcuts.display(Shortcuts.key(id, stored: shortcutOverrides)) }
    private var wordCount: Int { derived.wordCount(in: document.text) }
    /// The document's OKF reading, when its frontmatter has a `type`.
    private var concept: OKFConcept? { conceptCache.concept(in: document.text) }
    private var documentModel: MarkdownModel {
        derived.model(in: document.text, mdx: fileURL?.pathExtension.lowercased() == "mdx", editor: textView as? MarkdownTextView)
    }

    var body: some View {
        let _ = UpdateRate.tick("ContentView")
        GeometryReader { geometry in
            // Text fills the page between margins that grow with it (5% a side, 16–96pt), unless Settings limits the line width.
            // The side panes slide over the page and never move the text.
            let fill = max(geometry.size.width - 2 * min(max(geometry.size.width * 0.05, 16), 96), 280)
            let columnWidth = limitLineWidth ? min(markdownLens ? lineWidth + 20 : lineWidth, fill) : fill
            ZStack(alignment: .topLeading) {
                page.ignoresSafeArea()
                NativeEditor(text: $document.text, fileURL: fileURL, columnWidth: columnWidth, markdownLens: markdownLens, findQuery: showFind ? query : "", matchCase: matchCase, selectedRange: $selectedRange, textView: $textView, onType: {
                    hasTyped = true
                    // Typing after a rewrite accepts it.
                    if review != nil && !aiEdit.active {
                        review = nil
                        DispatchQueue.main.async { stampAIGenerated() }
                    } else if !aiEdit.active && textView?.undoManager?.isUndoing != true && textView?.undoManager?.isRedoing != true {
                        scheduleHumanStamp()
                    }
                    if fadeToolbar { withAnimation(.easeOut(duration: 0.4)) { chromeVisible = false } }
                }, onSlash: { query in
                    if slashQuery != query { slashSelection = 0 }
                    slashQuery = query
                }, onSlashKey: handleSlashKey, onSelectionRect: { selectionRect = $0 },
                theme: theme, currentMatch: showFind && findMatches.contains(selectedRange) ? selectedRange : nil, bundleRoot: bundleRoot,
                linkTargets: linkTargets, baseDirectory: reportBase,
                // Any ⌘ shortcut brings faded chrome back.
                onCommandKey: { if !chromeVisible { withAnimation(.easeOut(duration: 0.4)) { chromeVisible = true } } },
                onWritingToolsBegin: { humanStampTask?.cancel() }, onWritingToolsEnd: { changed in
                    if changed {
                        stampAIGenerated()
                        // Even with AI recording off, these edits must not become a delayed human stamp.
                        stampedBody = FrontmatterBlock.body(of: textView?.string ?? document.text)
                    } else {
                        scheduleHumanStamp()
                    }
                }, onCodeCopied: { copied in showCopyNotice(.code, copied: copied) })
                .frame(width: columnWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 56 + tabBarInset)

                if document.text.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Untitled").font(Font(theme.prose(36, bold: true)))
                        Text("Start writing, or type / to insert a block.").font(Font(theme.prose(18)))
                    }
                    .foregroundStyle(.tertiary)
                    .padding(.top, 96 + tabBarInset)
                    .frame(width: columnWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .allowsHitTesting(false)
                }
                if document.text.isEmpty && !hasTyped {
                    HStack(spacing: 18) {
                        Text("\(shortcutLabel("toggleMarkdown")) Markdown")
                        Text("\(shortcutLabel("library")) Library")
                        Text("⌘O Open file")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 26)
                    .allowsHitTesting(false)
                }

                if sidebarOpen {
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture { toggleSidebar() }
                        .zIndex(1)
                    sidebar
                        .padding(12)
                        .padding(.top, tabBarInset)
                        .ignoresSafeArea(.container, edges: .top)
                        .transition(.move(edge: .leading))
                        .zIndex(2)
                }
                if linksOpen {
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture { toggleLinks() }
                        .zIndex(1)
                    let model = documentModel
                    let editor = textView as? MarkdownTextView
                    DocumentInspector(
                        headings: derived.headings(in: model), links: derived.documentLinks(in: model),
                        documentURL: fileURL, bundleRoot: bundleRoot, baseDirectory: reportBase,
                        readingOffset: reading.offset, readingProgress: reading.progress, accent: accent,
                        jump: { editor?.reveal($0) },
                        hasTableOfContents: TableOfContentsBlock.find(in: model) != nil,
                        insertTableOfContents: { depth in
                            guard let editor else { return }
                            if TableOfContentsBlock.find(in: editor.model) != nil { editor.updateTableOfContents(depth: depth) }
                            else { editor.insertBlock(TableOfContentsBlock.text(DocumentHeading.extract(from: editor.model), depth: depth)) }
                        },
                        fixLink: { occurrences, old, new in editor?.replaceLinkDestination(old, with: new, in: occurrences.map(\.range)) },
                        follow: { link in Knowledge.follow(link.destination, title: link.text, from: fileURL, bundleRoot: bundleRoot, baseDirectory: reportBase) })
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(12)
                    .padding(.top, tabBarInset)
                    .onAppear(perform: updateReading)
                    .onChange(of: document.text) { _, _ in updateReading() }
                    .ignoresSafeArea(.container, edges: .top)
                    .transition(.move(edge: .trailing))
                    .zIndex(2)
                }

                GlassEffectContainer {
                    HStack(spacing: 10) {
                        Button { toggleSidebar() } label: {
                            Image(systemName: "sidebar.left")
                                .foregroundStyle(sidebarOpen ? accent : .primary)
                                .frame(width: 36, height: 36)
                                .background(sidebarOpen ? accentSoft : .clear, in: .circle)
                                .contentShape(.circle)
                        }
                            .buttonStyle(.plain)
                            .chromeGlass(in: .circle)
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
                            .chromeGlass(in: .capsule)
                            .offset(x: sidebarOpen ? 244 : 0)
                        Spacer()
                        HStack(spacing: 3) {
                            Button { toggleLinks() } label: {
                                Image(systemName: "sidebar.right")
                                    .foregroundStyle(linksOpen ? accent : .primary)
                                    .frame(width: 30, height: 30)
                                    .contentShape(.circle)
                            }
                            .buttonStyle(.plain)
                            .help("Contents and Links")
                            .accessibilityLabel(linksOpen ? "Hide Contents and Links" : "Show Contents and Links")
                            if aiAvailability != .unavailable(.deviceNotEligible) {
                                Button { showAI.toggle(); showWritingMenu = false } label: { Image(systemName: "apple.intelligence").symbolRenderingMode(.multicolor).frame(width: 30, height: 30).contentShape(.circle) }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Apple Intelligence")
                            }
                            // The whole capsule is clickable, not just the letters.
                            Button { toggleLens() } label: {
                                Text("MD")
                                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(markdownLens ? .white : .primary)
                                    .frame(minWidth: 36, minHeight: 30)
                                    .background(markdownLens ? accent : .clear, in: .capsule)
                                    .contentShape(.capsule)
                            }
                                .buttonStyle(.plain)
                                .help("Show Markdown \(shortcutLabel("toggleMarkdown"))")
                                .accessibilityLabel("Show Markdown")
                                .accessibilityAddTraits(markdownLens ? .isSelected : [])
                            Menu {
                                if let fileURL { ShareLink(item: fileURL) { Text("Share") } }
                                else { Button("Share") { }.disabled(true) }
                                if let source = document.sourceURL {
                                    Menu("Source") {
                                        Button("Open Original in Browser") { NSWorkspace.shared.open(source) }
                                        Button("Copy Source URL") {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(source.absoluteString, forType: .string)
                                        }
                                    }
                                }
                                Button("Copy All as Markdown") { copyAll() }
                                Button("Copy All for Medium") { copyAll(medium: true) }
                                Menu("Export") {
                                    Button("HTML") { exportHTML() }
                                    Button("PDF") { exportPDF() }
                                }
                                Menu("Knowledge") { knowledgeMenu }
                                Button("Find") { openFind(.find) }
                                Toggle("Show Word Count", isOn: $showWordCount)
                                SettingsLink { Text("Settings") }
                            } label: { Image(systemName: "ellipsis").frame(width: 30, height: 30).contentShape(.circle) }
                            .accessibilityLabel("More")
                            .buttonStyle(.plain)
                            .menuIndicator(.hidden)
                            .frame(width: 30, height: 30)
                            .contentShape(.circle)
                            .accessibilityLabel("More")
                        }
                        .padding(3)
                        .chromeGlass(in: .capsule)
                    }
                    // Clear of the traffic lights, which sit above the tab bar when it shows.
                    .padding(.leading, tabBarInset > 0 ? 12 : 88).padding(.trailing, 12).padding(.top, 14 + tabBarInset)
                }
                .opacity(chromeVisible ? 1 : 0)
                .allowsHitTesting(chromeVisible)
                .zIndex(3)

                if showStatusCapsule {
                    Text("\(showWordCount ? "\(wordCount) words · " : "")\(markdownLens ? "Markdown" : "Rendered")")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12).frame(height: 28)
                        .chromeGlass(in: .capsule)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(.trailing, 16).padding(.bottom, 14)
                        .opacity(chromeVisible ? 1 : 0)
                        .allowsHitTesting(chromeVisible)
                }
                if let copyNotice {
                    Label(copyNotice.message, systemImage: copyNotice.failed ? "exclamationmark.triangle" : "checkmark.circle")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(copyNotice.failed ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                        .padding(.horizontal, 14).frame(height: 32)
                        .chromeGlass(in: .capsule)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 14)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                        .zIndex(7)
                }
                if showFind { findPanel.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(.top, 56 + tabBarInset).padding(.trailing, 12).zIndex(4) }
                if let review, let frame = reviewFrame(review, geometry: geometry, columnWidth: columnWidth) {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(aiGradient, lineWidth: 1.5)
                        .shadow(color: Color.purple.opacity(colorScheme == .dark ? 0.22 : 0.13), radius: 10)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .allowsHitTesting(false)
                        .zIndex(4)
                    reviewCapsule(review)
                        .position(x: geometry.size.width / 2, y: min(frame.maxY + 27, geometry.size.height - 30))
                        .zIndex(5)
                }
                if showComposer {
                    composer
                        .frame(width: columnWidth)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { composerHeight = $0 }
                        .position(x: geometry.size.width / 2,
                                  y: min(selectionRect.maxY + 10 + composerHeight / 2, geometry.size.height - composerHeight / 2 - 12))
                        .zIndex(6)
                }
                if showAI { aiPanel.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(.top, 56 + tabBarInset).padding(.trailing, 12).zIndex(4) }
                if formatBarVisible && slashQuery == nil {
                    let barX = min(max(selectionRect.midX, 210), geometry.size.width - 210)
                    let barY = max(62, selectionRect.minY - 26)
                    formatBar
                        .position(x: barX, y: barY)
                        .zIndex(5)
                    if showBlockMenu {
                        blockMenu
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { blockMenuHeight = $0 }
                            .position(x: min(max(barX - 40, 135), geometry.size.width - 135), y: barY + 19 + 10 + blockMenuHeight / 2)
                            .zIndex(6)
                    }
                }
                if showWritingMenu && formatBarVisible && writingTools {
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
            .onExitCommand {
                if review != nil { return revertReview() }
                if showComposer { return closeComposer() }
                // Closing find from one of its fields hands the keyboard back to the page.
                if findFocus != nil, let textView { textView.window?.makeFirstResponder(textView) }
                showWritingMenu = false; showAI = false; showFind = false; sidebarOpen = false; linksOpen = false; closeBlockMenu()
            }
        }
        .frame(minWidth: 520, minHeight: 400)
        .ignoresSafeArea(.container, edges: .top)
        .focusedSceneValue(\.documentCopy, DocumentCopyActions(
            markdown: { copyAll() }, medium: { copyAll(medium: true) }))
        .navigationTitle("")
        .toolbar(removing: .title)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .background(WindowConfiguration(text: $document.text, tabTitle: title, tabBarInset: $tabBarInset))
        .preferredColorScheme(appearance == "Auto" ? nil : appearance == "Dark" ? .dark : .light)
        .tint(accent)
        .onReceive(NotificationCenter.default.publisher(for: NSView.boundsDidChangeNotification)) { notification in
            guard (notification.object as? NSView) === textView?.enclosingScrollView?.contentView else { return }
            if review != nil { scrollTick += 1 }
            if linksOpen { updateReading() }
        }
        .task { aiAvailability = await Task.detached { SystemLanguageModel.default.availability }.value }
        .onAppear {
            markdownLens = initialLens()
            isNewDocument = document.text.isEmpty && fileURL == nil
            if MarkifyAppDelegate.showsLibraryOnNextWindow {
                MarkifyAppDelegate.showsLibraryOnNextWindow = false
                sidebarOpen = true
            }
            loadLibrary()
            if Telemetry.needsOnboarding && !TelemetryOnboarding.presentedThisLaunch {
                TelemetryOnboarding.presentedThisLaunch = true
                showsTelemetryOnboarding = true
            }
        }
        .sheet(isPresented: $showsTelemetryOnboarding) {
            TelemetryOnboarding { joined in
                Telemetry.setEnabled(joined)
                Telemetry.hasOnboarded = true
                showsTelemetryOnboarding = false
            }
            .interactiveDismissDisabled()
        }
        .onDisappear {
            knowledgeTask?.cancel()
            retargetTask?.cancel()
            exportTask?.cancel()
            humanStampTask?.cancel()
            aiTask?.cancel()
            formatBarTask?.cancel()
            mirrorTags()
            rememberDocumentLens()
            libraryFolder?.stopAccessingSecurityScopedResource()
            watcher.stop()
        }
        .onChange(of: fileURL, initial: true) { old, new in
            rememberDocumentLens()
            mirrorTags()
            if let old, let new, old != new { offerToUpdateLinks(movedFrom: old, to: new) }
            refreshKnowledge()
        }
        .onChange(of: concept != nil) { _, _ in refreshKnowledge() }
        .onChange(of: sidebarOpen) { _, open in if open { refreshLibrary(); refreshKnowledge() } }
        .onChange(of: Frontmatter.parse(document.text)?.tags ?? []) { _, _ in mirrorTagsAfterTyping() }
        .onChange(of: document.text) { _, _ in offerTitleTagsIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willBeginSheetNotification)) { notification in
            prepareSavePanel(notification.object as? NSWindow)
        }
        .onReceive(NotificationCenter.default.publisher(for: MarkifyAppDelegate.libraryFolderOpened)) { notification in
            if notification.object as? NSWindow === textView?.window { sidebarOpen = true }
        }
        .onChange(of: LibrarySearch.shared.revision) { _, _ in updateLibraryBrowse() }
        .onChange(of: libraryBookmark) { _, _ in loadLibrary() }
        .onChange(of: selectedRange) { _, range in
            formatBarTask?.cancel()
            formatBarVisible = false
            showBlockMenu = false
            if range.length > 0 {
                formatBarTask = Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    if !Task.isCancelled { formatBarVisible = true }
                }
            } else { showWritingMenu = false }
        }
        .background {
            Button("Toggle Markdown") { toggleLens() }.keyboardShortcut(shortcut("toggleMarkdown")).hidden()
            Button("Search Library") {
                sidebarOpen = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NotificationCenter.default.post(name: .focusLibrarySearch, object: textView?.window)
                }
            }.keyboardShortcut(shortcut("searchLibrary")).hidden()
            Button("Toggle Library") { toggleSidebar() }.keyboardShortcut(shortcut("library")).hidden()
            Button("Find") { openFind(.find) }.keyboardShortcut(shortcut("find")).hidden()
            Button("Replace") { openFind(.replace) }.keyboardShortcut(shortcut("replace")).hidden()
            Button("Find Next") { showFind = true; findNext() }.keyboardShortcut(shortcut("findNext")).hidden()
            Button("Find Previous") { showFind = true; findPrevious() }.keyboardShortcut(shortcut("findPrevious")).hidden()
            Button("Zoom In") { zoom(by: 1) }.keyboardShortcut(shortcut("zoomIn")).hidden()
            Button("Zoom In") { zoom(by: 1) }.keyboardShortcut("+", modifiers: [.command, .shift]).hidden()
            Button("Zoom Out") { zoom(by: -1) }.keyboardShortcut(shortcut("zoomOut")).hidden()
            Button("Actual Size") { proseSize = 18 }.keyboardShortcut(shortcut("actualSize")).hidden()
            Button("Bold") { wrap("**") }.keyboardShortcut(shortcut("bold")).hidden()
            Button("Italic") { wrap("*") }.keyboardShortcut(shortcut("italic")).hidden()
            Button("Strikethrough") { wrap("~~") }.keyboardShortcut(shortcut("strikethrough")).hidden()
            Button("Inline Code") { wrap("`") }.keyboardShortcut(shortcut("code")).hidden()
            Button("Link") { wrap("[", suffix: "](url)") }.keyboardShortcut(shortcut("link")).hidden()
            ForEach(["Body", "Title", "Heading", "Subheading"], id: \.self) { style in
                Button(style) { applyBlockStyle(style) }.keyboardShortcut(shortcut(style.lowercased())).hidden()
            }
            ForEach(MarkdownTable.Edit.allCases, id: \.self) { edit in
                Button(edit.title) {
                    if (textView as? MarkdownTextView)?.editTable(edit) != true { NSSound.beep() }
                }.keyboardShortcut(shortcut(edit.rawValue)).hidden()
            }
            if writingTools && aiAvailability != .unavailable(.deviceNotEligible) {
                Button("Writing Tools") { toggleWritingMenu() }.keyboardShortcut(shortcut("writingTools")).hidden()
            }
            // Accepting a review or keeping output works even with Generate at caret off.
            if (generateAtCaret && aiAvailability == .available) || review != nil || (!aiOutput.isEmpty && !aiBusy) {
                Button("Continue Writing") { generateAtCaretOrKeep() }.keyboardShortcut(shortcut("generate")).hidden()
            }
        }
    }

    private var sidebar: some View {
        LibrarySearchPanel(library: libraryFolder, currentBundle: bundleRoot, currentFile: fileURL,
                           browse: AnyView(libraryBrowse), close: toggleSidebar)
    }

    private var libraryBrowse: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
            Text("Open Files").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            ForEach(NSDocumentController.shared.documents.compactMap(\.fileURL).prefix(8), id: \.self) { url in
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.lastPathComponent).font(.system(size: 13, weight: url == fileURL ? .semibold : .regular))
                    Text(url.deletingLastPathComponent().path).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(7)
                .sidebarRow(url) { open(url) }
            }
            if concept != nil || knowledge != nil {
                KnowledgeSection(state: knowledge, fileURL: fileURL, concept: concept, text: document.text,
                                 issues: documentIssues, search: "", open: open)
                    .task(id: KnowledgeIssueInput(text: document.text, fileURL: fileURL, root: bundleRoot)) {
                        let source = document.text, file = fileURL, root = bundleRoot
                        let work = Task.detached(priority: .utility) { Knowledge.issues(text: source, fileURL: file, root: root) }
                        let issues = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
                        if !Task.isCancelled { documentIssues = issues }
                    }
            }
            Text("Library").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 12)
            if let libraryFolder {
                ForEach(librarySubfolders, id: \.self) { folder in
                    HStack(spacing: 7) {
                        Image(systemName: "folder").foregroundStyle(.secondary)
                        Text(LibraryNote.path(of: folder, in: libraryFolder))
                            .font(.system(size: 13)).lineLimit(1)
                        Spacer(minLength: 0)
                        Button { newDocument(in: folder) } label: { Image(systemName: "plus") }
                            .buttonStyle(.plain).help("New document in \(folder.lastPathComponent)")
                            .accessibilityLabel("New document in \(folder.lastPathComponent)")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(7)
                }
                ForEach(libraryNotes) { note in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.title).font(.system(size: 13))
                        Text(note.folder.isEmpty ? note.preview : note.preview.isEmpty ? note.folder : "\(note.folder) · \(note.preview)")
                            .font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(7)
                    .sidebarRow(note.url) { open(note.url) }
                }
            }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { NSDocumentController.shared.newDocument(nil) } label: {
                HStack {
                    Text("New Document")
                    Spacer()
                    Text("⌘N")
                }
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .padding(8)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private func open(_ url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }

    private func loadLibrary() {
        libraryFolder?.stopAccessingSecurityScopedResource()
        libraryFolder = nil
        if let url = Bookmarks.url(libraryBookmark) {
            libraryFolder = url
            _ = url.startAccessingSecurityScopedResource()
        }
        if libraryFolder == nil {
            let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("Markify")
            if let folder, FileManager.default.fileExists(atPath: folder.path) { libraryFolder = folder }
        }
        refreshLibrary()
        refreshKnowledge()
    }

    /// Rescans the OKF bundle around the document; plain notes outside a declared bundle skip the scan.
    private func refreshKnowledge() {
        if stampedBody == nil { stampedBody = FrontmatterBlock.body(of: document.text) }
        knowledgeTask?.cancel()
        let file = fileURL, source = document.text, boundary = libraryFolder
        knowledgeTask = Task {
            let root = await Knowledge.root(for: file, text: source, boundary: boundary)
            guard !Task.isCancelled else { return }
            bundleRoot = root
            if let root { LibrarySearch.shared.includeBundle(root) }
            if root != watchedRoot {
                watchedRoot = root
                watcher.watch(root) { refreshKnowledge() }
            }
            guard let root else { knowledge = nil; linkTargets = []; return }
            let state = await Knowledge.load(root: root)
            guard !Task.isCancelled else { return }
            knowledge = state
            let own = file?.standardizedFileURL
            linkTargets = state.bundle.documents.filter { $0.url != own }.map(\.path)
        }
    }

    private func refreshLibrary() {
        LibrarySearch.shared.start()
        LibrarySearch.shared.refresh()
        updateLibraryBrowse()
    }

    private func updateLibraryBrowse() {
        guard let libraryFolder else { librarySubfolders = []; libraryNotes = []; return }
        let snapshot = LibrarySearch.shared.snapshot
        librarySubfolders = snapshot.subfolders.filter { SearchNote.contains(libraryFolder, $0) }
        libraryNotes = snapshot.notes.filter { $0.roots.contains(SearchNote.identifier(libraryFolder)) }.map { note in
            LibraryNote(url: note.url, title: note.title, preview: note.description,
                        folder: LibraryNote.path(of: note.url.deletingLastPathComponent(), in: libraryFolder))
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func newDocument(in folder: URL) {
        let panel = NSSavePanel()
        panel.directoryURL = folder
        panel.nameFieldStringValue = "Untitled.md"
        panel.allowedContentTypes = [.markdown]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard !FileManager.default.fileExists(atPath: url.path), FileManager.default.createFile(atPath: url.path, contents: Data()) else {
            let alert = NSAlert()
            alert.messageText = "The document couldn’t be created."
            alert.informativeText = "Choose another name or folder."
            alert.runModal()
            return
        }
        refreshLibrary()
        open(url)
    }

    private var findPanel: some View {
        let matches = findMatches
        let current = matches.firstIndex(of: selectedRange)
        return VStack(spacing: 6) {
            HStack(spacing: 4) {
                HStack {
                    TextField("Find", text: $query).textFieldStyle(.plain).focused($findFocus, equals: .find).onSubmit(findNext)
                    if !query.isEmpty {
                        Text(matches.isEmpty ? "No results" : current.map { "\($0 + 1) of \(matches.count)" } ?? "\(matches.count) found")
                            .font(.system(size: 11.5)).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .padding(.horizontal, 10).frame(height: 30)
                .background(field, in: .rect(cornerRadius: 9))
                Button(action: findPrevious) { Image(systemName: "chevron.left").frame(width: 28, height: 28).contentShape(.rect) }
                    .help("Find Previous \(shortcutLabel("findPrevious"))").accessibilityLabel("Previous match")
                Button(action: findNext) { Image(systemName: "chevron.right").frame(width: 28, height: 28).contentShape(.rect) }
                    .help("Find Next \(shortcutLabel("findNext"))").accessibilityLabel("Next match")
                Button { matchCase.toggle() } label: {
                    Text("Aa").font(.system(size: 12, weight: .semibold)).frame(width: 30, height: 28)
                        .foregroundStyle(matchCase ? accent : .primary)
                        .background(matchCase ? accentSoft : .clear, in: .rect(cornerRadius: 8))
                }
                .accessibilityLabel("Match case").accessibilityAddTraits(matchCase ? .isSelected : [])
            }
            HStack(spacing: 4) {
                TextField("Replace", text: $replacement).textFieldStyle(.plain).focused($findFocus, equals: .replace)
                    .padding(.horizontal, 10).frame(height: 30)
                    .background(field, in: .rect(cornerRadius: 9))
                Button(action: replaceOne) { Text("Replace").padding(.horizontal, 10).frame(height: 28).background(field, in: .rect(cornerRadius: 8)) }
                Button(action: replaceAll) {
                    Text("All").fontWeight(.semibold).foregroundStyle(.white).padding(.horizontal, 12).frame(height: 28).background(accent, in: .rect(cornerRadius: 8))
                }
            }
        }
        .font(.system(size: 13))
        .buttonStyle(.plain)
        .padding(8).frame(width: 380)
        .chromeGlass(in: .rect(cornerRadius: 18))
    }

    private var formatBar: some View {
        HStack(spacing: 1) {
            if writingTools && aiAvailability != .unavailable(.deviceNotEligible) {
                Button { toggleWritingMenu() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "apple.intelligence").symbolRenderingMode(.multicolor).font(.system(size: 14))
                        Text("Writing Tools").font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.leading, 10).padding(.trailing, 12).frame(height: 32)
                    .background(showWritingMenu ? field : .clear, in: .capsule)
                    .contentShape(.capsule)
                }
                .help("Writing Tools \(shortcutLabel("writingTools"))")
                .accessibilityLabel("Writing Tools")
                formatDivider
            }
            Button {
                if showBlockMenu { closeBlockMenu() } else { openBlockMenu() }
            } label: {
                HStack(spacing: 4) {
                    Text(currentBlockStyle)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(.secondary)
                .padding(.leading, 12).padding(.trailing, 10).frame(height: 32)
                .background(showBlockMenu ? field : .clear, in: .capsule)
                .contentShape(.capsule)
            }
            .fixedSize()
            .accessibilityLabel("Block style, \(currentBlockStyle)")
            formatDivider
            tool("bold", help: "Bold", marker: "**")
            tool("italic", help: "Italic", marker: "*")
            tool("strikethrough", help: "Strikethrough", marker: "~~")
            tool("chevron.left.forwardslash.chevron.right", help: "Inline Code", marker: "`")
            formatDivider
            Button { wrap("[", suffix: "](url)") } label: { Image(systemName: "link").frame(width: 32, height: 32).contentShape(.circle) }
                .help("Link \(shortcutLabel("link"))").accessibilityLabel("Link")
        }
        .font(.system(size: 13))
        .buttonStyle(.plain)
        .padding(3)
        .frame(height: 38)
        .background(glassStrong, in: .capsule)
        .chromeGlass(in: .capsule)
    }

    private var formatDivider: some View {
        Rectangle().fill(rule).frame(width: 1, height: 18).padding(.horizontal, 2)
    }

    private var blockMenu: some View {
        let entries = BlockStyle.all.filter { blockMenuQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(blockMenuQuery) }
        return VStack(alignment: .leading, spacing: 1) {
            ForEach(["Text", "Lists"], id: \.self) { section in
                let rows = entries.filter { $0.section == section }
                if !rows.isEmpty {
                    if section == "Lists" && entries.contains(where: { $0.section == "Text" }) {
                        Rectangle().fill(rule).frame(height: 1).padding(.horizontal, 6).padding(.vertical, 4)
                    }
                    Text(section).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 2)
                    ForEach(rows) { style in
                        let index = entries.firstIndex { $0.name == style.name } ?? 0
                        blockRow(style, current: style.name == currentBlockStyle, highlighted: index == blockMenuSelection)
                    }
                }
            }
            if entries.isEmpty { Text("No matching style").foregroundStyle(.secondary).padding(10) }
        }
        .padding(6).frame(width: 250)
        .background(glassStrong, in: .rect(cornerRadius: 18))
        .chromeGlass(in: .rect(cornerRadius: 18))
        .focusable()
        .focusEffectDisabled()
        .focused($blockMenuFocused)
        .onKeyPress(.upArrow) { blockMenuSelection = max(0, blockMenuSelection - 1); return .handled }
        .onKeyPress(.downArrow) { blockMenuSelection = min(entries.count - 1, blockMenuSelection + 1); return .handled }
        .onKeyPress(.return) {
            if entries.indices.contains(blockMenuSelection) { chooseBlockStyle(entries[blockMenuSelection].name) }
            return .handled
        }
        .onKeyPress(.escape) { closeBlockMenu(); return .handled }
        .onKeyPress(.delete) { if !blockMenuQuery.isEmpty { blockMenuQuery.removeLast(); blockMenuSelection = 0 }; return .handled }
        .onKeyPress(characters: .letters.union(.whitespaces)) { press in
            blockMenuQuery += press.characters
            blockMenuSelection = 0
            return .handled
        }
    }

    private func blockRow(_ style: BlockStyle, current: Bool, highlighted: Bool) -> some View {
        Button { chooseBlockStyle(style.name) } label: {
            HStack(spacing: 0) {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).frame(width: 14).opacity(current ? 1 : 0)
                    .padding(.trailing, 6)
                Text(style.name).font(style.font)
                    .foregroundStyle(current ? .white : style.name == "Quote" ? .secondary : .primary)
                Spacer()
                Text(style.name == "Body" ? shortcutLabel("body") : style.prefix)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(current ? .white.opacity(0.8) : .secondary)
            }
            .padding(.horizontal, 8).frame(height: style.name == "Title" ? 38 : 32)
            .foregroundStyle(current ? .white : .primary)
            .background(current ? accent : highlighted ? rowSel : .clear, in: .rect(cornerRadius: 11))
            .contentShape(.rect(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.name)
        .accessibilityAddTraits(current ? .isSelected : [])
    }

    private func openBlockMenu() {
        blockMenuQuery = ""
        blockMenuSelection = BlockStyle.all.firstIndex { $0.name == currentBlockStyle } ?? 0
        showBlockMenu = true
        showWritingMenu = false
        DispatchQueue.main.async { blockMenuFocused = true }
    }

    private func closeBlockMenu() {
        guard showBlockMenu else { return }
        showBlockMenu = false
        if let textView { textView.window?.makeFirstResponder(textView) }
    }

    private func chooseBlockStyle(_ name: String) {
        closeBlockMenu()
        applyBlockStyle(name)
    }

    private func tool(_ symbol: String, help: String, marker: String) -> some View {
        let active = isWrapped(marker)
        return Button { wrap(marker) } label: {
            Image(systemName: symbol)
                .frame(width: 32, height: 32)
                .foregroundStyle(active ? accent : .primary)
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
                    .onSubmit { generateSelection("Revise the selection as follows: \(selectionPrompt). Return only the revised Markdown text.", title: "Edit") }
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
                        generateSelection("Rewrite this selection in a \(tone.lowercased()) tone. Return only the revised Markdown text.", title: "Rewrite · \(tone)")
                    } label: {
                        Text(tone).frame(maxWidth: .infinity).frame(height: 32).contentShape(.rect(cornerRadius: 10))
                    }
                    .buttonStyle(MenuRowStyle(fill: field, hover: field, radius: 10))
                }
            }
            Rectangle().fill(rule).frame(height: 1).padding(.horizontal, 6).padding(.vertical, 2)
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow {
                    writingRow("Summary", symbol: "text.alignleft") { generateSelection("Summarize this selection in one paragraph. Return only Markdown text.", title: "Summary") }
                    writingRow("Key Points", symbol: "list.bullet") { generateSelection("Extract the key points as a Markdown list. Return only the list.", title: "Key Points") }
                }
                GridRow {
                    writingRow("List", symbol: "list.dash") { generateSelection("Turn this selection into a Markdown list. Return only the list.", title: "List") }
                    writingRow("Table", symbol: "tablecells") { generateSelection("Turn this selection into a Markdown table. Return only the table.", title: "Table") }
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
        .chromeGlass(in: .rect(cornerRadius: 20))
    }

    private func writingTile(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(accent).frame(height: 18)
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

    private func generateSelection(_ action: String, title: String) {
        guard selectedRange.length > 0 else { return }
        reviewTitle = title
        generate(action: action, placement: .replaceSelection(selectedRange))
    }

    private var aiPanel: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                HStack(spacing: 7) {
                    Image(systemName: "apple.intelligence").symbolRenderingMode(.multicolor).font(.system(size: 14))
                    Text("Apple Intelligence").fontWeight(.semibold)
                }
                Spacer()
                Text("Whole document")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(field, in: .capsule)
            }
            .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 8)
            switch aiAvailability {
            case .available:
                TextField("Describe a change to the document…", text: $aiPrompt)
                    .textFieldStyle(.plain)
                    .onSubmit { generate(action: aiPrompt) }
                    .padding(.horizontal, 12).frame(height: 36)
                    .background(field, in: .rect(cornerRadius: 12))
                    .padding(.bottom, 6)
                HStack(spacing: 6) {
                    writingTile("Proofread", symbol: "checkmark") { textView?.showWritingTools(nil) }
                    writingTile("Rewrite…", symbol: "arrow.clockwise") { textView?.showWritingTools(nil) }
                }
                .padding(.bottom, 6)
                aiRow("Summarize", detail: "Insert at top") {
                    generate(action: "Summarize this document in one concise paragraph. Return only Markdown text.", placement: .atTop)
                }
                aiRow("Key points", detail: "New section") {
                    generate(action: "Extract the key points as a concise Markdown bullet list. Return only Markdown text.", placement: .newSection)
                }
                aiRow(concept != nil || knowledge != nil ? "Suggest title, type & tags" : "Suggest title & tags", detail: "Frontmatter") {
                    generate(action: "Suggest a clear title and up to five short tags for this document.", placement: .frontmatter)
                }
                aiRow("Continue writing", detail: generateAtCaret ? "At caret · \(shortcutLabel("generate"))" : "At caret") { continueWriting() }
            case .unavailable(.appleIntelligenceNotEnabled):
                Text("Turn on Apple Intelligence in System Settings").foregroundStyle(.secondary).padding(.horizontal, 10)
            case .unavailable(.modelNotReady):
                HStack { ProgressView().controlSize(.small); Text("Preparing on-device model…") }.padding(.horizontal, 10)
            case .unavailable(.deviceNotEligible):
                EmptyView()
            @unknown default:
                Text("Apple Intelligence is unavailable.").padding(.horizontal, 10)
            }
            if aiBusy {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Writing on this Mac…").foregroundStyle(.secondary)
                    Spacer()
                    Button("Stop") { aiTask?.cancel(); aiBusy = false }
                        .padding(.horizontal, 10).frame(height: 26)
                        .buttonStyle(MenuRowStyle(fill: field, hover: field, radius: 8))
                }
                .padding(.horizontal, 10).padding(.top, 6)
            }
            if !aiOutput.isEmpty {
                ScrollView { Text(aiOutput).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                    .frame(maxHeight: 180)
                    .padding(10)
                    .background(field, in: .rect(cornerRadius: 12))
                    .padding(.top, 6)
                HStack(spacing: 6) {
                    Spacer()
                    Button("Discard") { aiOutput = ""; aiTask?.cancel(); aiBusy = false }
                        .padding(.horizontal, 12).frame(height: 28)
                        .buttonStyle(MenuRowStyle(fill: field, hover: field, radius: 999))
                    Button { keepAIOutput() } label: {
                        Text("Keep").fontWeight(.semibold).foregroundStyle(.white)
                            .padding(.horizontal, 14).frame(height: 28)
                            .background(accent, in: .capsule)
                    }
                    .disabled(aiBusy)
                }
                .padding(.top, 6)
            }
            if let aiError { Text(aiError).font(.system(size: 11.5)).foregroundStyle(.red).padding(.horizontal, 10).padding(.top, 4) }
            Rectangle().fill(rule).frame(height: 1).padding(.horizontal, 8).padding(.vertical, 6)
            Text("Runs on this Mac with Apple Intelligence. Your text never leaves it.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10).padding(.top, 2).padding(.bottom, 6)
        }
        .font(.system(size: 13))
        .buttonStyle(.plain)
        .padding(8).frame(width: 320)
        .background(glassStrong, in: .rect(cornerRadius: 20))
        .chromeGlass(in: .rect(cornerRadius: 20))
    }

    private func aiRow(_ title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).frame(height: 32)
            .contentShape(.rect(cornerRadius: 9))
        }
        .buttonStyle(MenuRowStyle(fill: .clear, hover: rowSel, radius: 9))
    }

    private func continueWriting() {
        generate(action: "Continue this document from the caret. Return only the continuation as Markdown.")
    }

    /// ⌘↩: accepts a rewrite under review, keeps finished output, or opens the composer at the caret.
    private func generateAtCaretOrKeep() {
        if review != nil { return acceptReview() }
        if !aiOutput.isEmpty && !aiBusy { return keepAIOutput() }
        if generateAtCaret { openComposer() }
    }

    private func openComposer() {
        guard aiAvailability == .available else { return }
        aiTask?.cancel(); aiBusy = false; aiOutput = ""; aiError = nil
        composerPrompt = ""
        composerTone = generationTone
        showAI = false
        showWritingMenu = false
        showComposer = true
        DispatchQueue.main.async { composerFocused = true }
    }

    private func closeComposer() {
        aiTask?.cancel(); aiBusy = false; aiOutput = ""; aiError = nil
        showComposer = false
        if let textView { textView.window?.makeFirstResponder(textView) }
    }

    private func runComposer() {
        let request = composerPrompt.trimmingCharacters(in: .whitespaces)
        let task = request.isEmpty ? "Continue this document from the caret." : "Write the following at the caret: \(request)."
        let tone = composerTone == "Match document" ? "Match the document's tone." : "Use a \(composerTone.lowercased()) tone."
        let length = ["Short": "Keep it to a sentence or two.", "Medium": "Write about one paragraph.", "Long": "Write several paragraphs."][composerLength] ?? ""
        let format = ["Paragraphs": "Write prose paragraphs.", "List": "Format it as a Markdown list.", "Table": "Format it as a Markdown table."][composerFormat] ?? ""
        generate(action: "\(task) \(tone) \(length) \(format) Return only the new Markdown text.")
    }

    private var aiGradient: LinearGradient {
        LinearGradient(colors: [Color(red: 1, green: 159/255, blue: 10/255), Color(red: 1, green: 55/255, blue: 95/255),
                                Color(red: 191/255, green: 90/255, blue: 242/255), Color(red: 10/255, green: 132/255, blue: 1)],
                       startPoint: .leading, endPoint: .trailing)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "apple.intelligence").symbolRenderingMode(.multicolor).font(.system(size: 14))
                TextField("Describe what to write, or press ↩ to continue", text: $composerPrompt)
                    .textFieldStyle(.plain)
                    .focused($composerFocused)
                    .onSubmit { if !aiOutput.isEmpty && !aiBusy { keepAIOutput(); closeComposer() } else { runComposer() } }
                Text("esc").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            HStack(spacing: 6) {
                composerChip("Length", value: $composerLength, options: ["Short", "Medium", "Long"])
                composerChip("Tone", value: $composerTone, options: ["Match document", "Friendly", "Professional", "Concise"])
                composerChip("Format", value: $composerFormat, options: ["Paragraphs", "List", "Table"])
            }
            if !aiOutput.isEmpty {
                Text("\(Text(aiOutput).foregroundStyle(.secondary))\(Text(aiBusy ? " ▍" : "").foregroundStyle(aiGradient))")
                    .font(Font(theme.prose(16)))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            if let aiError { Text(aiError).font(.system(size: 11.5)).foregroundStyle(.red) }
            HStack(spacing: 6) {
                if aiBusy {
                    ProgressView().controlSize(.small)
                    Text("Writing on this Mac…").foregroundStyle(.secondary)
                    Spacer()
                    Button("Stop") { aiTask?.cancel(); aiBusy = false }
                        .padding(.horizontal, 10).frame(height: 26)
                        .buttonStyle(MenuRowStyle(fill: field, hover: field, radius: 8))
                } else if !aiOutput.isEmpty {
                    Spacer()
                    Button("Discard") { closeComposer() }
                        .padding(.horizontal, 12).frame(height: 28)
                        .buttonStyle(MenuRowStyle(fill: field, hover: field, radius: 999))
                    Button("Try Again") { runComposer() }
                        .padding(.horizontal, 12).frame(height: 28)
                        .buttonStyle(MenuRowStyle(fill: field, hover: field, radius: 999))
                    Button { keepAIOutput(); closeComposer() } label: {
                        Text("Keep \(shortcutLabel("generate"))").fontWeight(.semibold).foregroundStyle(.white)
                            .padding(.horizontal, 14).frame(height: 28)
                            .background(accent, in: .capsule)
                    }
                }
            }
            .font(.system(size: 12.5))
        }
        .font(.system(size: 13))
        .buttonStyle(.plain)
        .padding(.vertical, 12).padding(.horizontal, 14)
        .background(glassStrong, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(aiGradient, lineWidth: 1.5))
        .shadow(color: Color.purple.opacity(colorScheme == .dark ? 0.22 : 0.13), radius: 12)
    }

    private func composerChip(_ label: String, value: Binding<String>, options: [String]) -> some View {
        Menu {
            Picker(label, selection: value) { ForEach(options, id: \.self) { Text($0).tag($0) } }.pickerStyle(.inline)
        } label: {
            Text("\(label): \(value.wrappedValue)").font(.system(size: 11.5)).padding(.horizontal, 9).frame(height: 24)
                .background(field, in: .capsule)
        }
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// Frame of a reviewed rewrite in the ZStack, outset 14pt around the column.
    private func reviewFrame(_ review: AIReview, geometry: GeometryProxy, columnWidth: CGFloat) -> CGRect? {
        _ = scrollTick
        guard let textView, let window = textView.window, let content = window.contentView,
              NSMaxRange(review.range) <= (textView.string as NSString).length, review.range.length > 0 else { return nil }
        let first = window.convertFromScreen(textView.firstRect(forCharacterRange: NSRange(location: review.range.location, length: 1), actualRange: nil))
        let last = window.convertFromScreen(textView.firstRect(forCharacterRange: NSRange(location: NSMaxRange(review.range) - 1, length: 1), actualRange: nil))
        let top = content.bounds.height - first.maxY
        let bottom = content.bounds.height - last.minY
        let left = (geometry.size.width - columnWidth) / 2
        return CGRect(x: left - 14, y: top - 8, width: columnWidth + 28, height: max(bottom - top, 20) + 16)
    }

    private func reviewCapsule(_ review: AIReview) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "apple.intelligence").symbolRenderingMode(.multicolor).padding(.leading, 12)
            let parts = review.title.components(separatedBy: " · ")
            Text(parts[0]).fontWeight(.semibold)
            if parts.count > 1 { Text("· \(parts[1])").foregroundStyle(.secondary).padding(.trailing, 6) }
            Rectangle().fill(rule).frame(width: 1, height: 18).padding(.horizontal, 4)
            Button("Try Again") { retryReview() }.padding(.horizontal, 10)
            Button(review.comparing ? "Show Result" : "Compare") { compareReview() }.padding(.horizontal, 10)
            Button("Discard Rewrite") { revertReview() }.padding(.horizontal, 10)
            Button { acceptReview() } label: {
                HStack(spacing: 8) {
                    Text("Accept").fontWeight(.semibold)
                    Text(shortcutLabel("generate")).opacity(0.8)
                }
                .foregroundStyle(.white).padding(.horizontal, 14).frame(height: 32)
                .background(accent, in: .capsule)
            }
        }
        .font(.system(size: 13))
        .buttonStyle(.plain)
        .padding(3).frame(height: 38)
        .background(glassStrong, in: .capsule)
        .chromeGlass(in: .capsule)
        .fixedSize()
    }

    /// Replaces the selection with finished output in place, as one undo step, and starts the review.
    private func applyReview() {
        guard let textView, case .replaceSelection(let range) = aiPlacement else { return }
        let source = textView.string as NSString
        guard NSMaxRange(range) <= source.length, source.substring(with: range) == aiSelectionSource else {
            aiError = "The selection changed while writing. Generate again to avoid replacing newer edits."
            return
        }
        let result = aiOutput
        replaceText(in: range, with: result, undoable: true)
        review = AIReview(range: NSRange(location: range.location, length: (result as NSString).length),
                          original: aiSelectionSource, result: result, title: reviewTitle, action: lastAIAction)
        aiOutput = ""
        showWritingMenu = false
        formatBarVisible = false
    }

    private func replaceText(in range: NSRange, with text: String, undoable: Bool) {
        guard let textView else { return }
        aiEdit.active = true
        if !undoable { textView.undoManager?.disableUndoRegistration() }
        textView.insertText(text, replacementRange: range)
        if !undoable { textView.undoManager?.enableUndoRegistration() }
        aiEdit.active = false
    }

    private func compareReview() {
        guard var current = review else { return }
        current.comparing.toggle()
        let shown = current.comparing ? current.original : current.result
        replaceText(in: current.range, with: shown, undoable: false)
        current.range.length = (shown as NSString).length
        review = current
    }

    private func acceptReview() {
        guard let current = review else { return }
        if current.comparing { compareReview() }
        review = nil
        stampAIGenerated()
    }

    private func revertReview() {
        guard var current = review else { return }
        if current.comparing { compareReview(); current = review ?? current }
        replaceText(in: current.range, with: current.original, undoable: true)
        review = nil
    }

    private func retryReview() {
        guard let current = review else { return }
        revertReview()
        reviewTitle = current.title
        generate(action: current.action, placement: .replaceSelection(NSRange(location: current.range.location, length: (current.original as NSString).length)))
    }

    /// Opens the document panel with a frontmatter suggestion once a new document has enough text to summarize.
    private func offerTitleTagsIfNeeded() {
        guard suggestTitleTags, isNewDocument, !offeredTitleTags, aiAvailability == .available, !aiBusy, aiOutput.isEmpty,
              !document.text.hasPrefix("---\n"), wordCount >= 50 else { return }
        offeredTitleTags = true
        showAI = true
        generate(action: "Suggest a clear title and up to five short tags for this document.", placement: .frontmatter)
    }

    private var toneInstruction: String {
        generationTone == "Match document" ? "Match the tone and voice of the document."
            : "Unless the request names another tone, write in a \(generationTone.lowercased()) tone."
    }

    private func generate(action: String, placement: AIPlacement = .atCaret) {
        guard aiAvailability == .available, !action.isEmpty else { return }
        aiTask?.cancel()
        aiOutput = ""
        aiError = nil
        aiBusy = true
        aiInsertion = selectedRange.location
        aiPlacement = placement
        lastAIAction = action
        let text = document.text as NSString
        let source: String
        let prompt: String
        switch placement {
        case .replaceSelection(let range) where NSMaxRange(range) <= text.length:
            source = text.substring(with: range)
            let section = AIContext.section(around: range, in: document.text)
            prompt = useSectionContext && section != range
                ? "\(action)\n\nSurrounding section, for context only:\n\(text.substring(with: section))\n\nSelection:\n\(source)"
                : "\(action)\n\nSelection:\n\(source)"
        case .atCaret where useSectionContext:
            source = document.text
            let caret = min(selectedRange.location, text.length)
            let section = AIContext.section(around: NSRange(location: caret, length: 0), in: document.text)
            let before = text.substring(with: NSRange(location: section.location, length: caret - section.location))
            let after = text.substring(with: NSRange(location: caret, length: NSMaxRange(section) - caret))
            prompt = "\(action)\n\nSection text before the caret:\n\(before)\n\nSection text after the caret:\n\(after)"
        default:
            source = document.text
            prompt = "\(action)\n\nDocument:\n\(source)"
        }
        aiSelectionSource = source
        aiSuggestion = nil
        // OKF documents also get a type (when missing) and a one-sentence description.
        let okf = placement == .frontmatter && (concept != nil || knowledge != nil)
        let knownTypes = Array(Set(knowledge?.bundle.concepts.compactMap(\.concept?.type) ?? [])).sorted()
        let needsType = okf && concept == nil
        let conceptPrompt = "Suggest a clear title, a one-sentence description and up to five short tags for this knowledge document."
            + (needsType ? " Also name its type, the kind of knowledge it captures." : "")
            + (needsType && !knownTypes.isEmpty ? " Prefer one of these types when one fits: \(knownTypes.joined(separator: ", "))." : "")
            + "\n\nDocument:\n\(FrontmatterBlock.body(of: document.text))"
        let instructions = "You edit Markdown. Keep the response grounded in the supplied text. \(toneInstruction) Return only the requested Markdown content."
        aiTask = Task {
            do {
                let session = LanguageModelSession(instructions: instructions)
                if okf {
                    let content = try await session.respond(to: conceptPrompt, generating: SuggestedConcept.self).content
                    let suggestion = FrontmatterSuggestion(title: content.title, tags: content.tags, type: needsType ? content.type : nil, description: content.description)
                    if !Task.isCancelled { aiSuggestion = suggestion; aiOutput = suggestion.preview }
                } else if placement == .frontmatter {
                    let content = try await session.respond(to: prompt, generating: SuggestedFrontmatter.self).content
                    let suggestion = FrontmatterSuggestion(title: content.title, tags: content.tags)
                    if !Task.isCancelled { aiSuggestion = suggestion; aiOutput = suggestion.preview }
                } else {
                    for try await snapshot in session.streamResponse(to: prompt) {
                        if Task.isCancelled { break }
                        aiOutput = snapshot.content
                    }
                }
            } catch {
                if !Task.isCancelled { aiError = error.localizedDescription }
            }
            aiBusy = false
            // Selection edits land in place and wait for review (2c).
            if case .replaceSelection = placement, !Task.isCancelled, aiError == nil, !aiOutput.isEmpty { applyReview() }
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
        if aiPlacement == .frontmatter, let aiSuggestion {
            // Merged key by key, so dates, trust stamps and other keys survive.
            aiEdit.active = true
            editFrontmatter(quiet: true) { aiSuggestion.merged(into: $0) }
            aiEdit.active = false
        } else {
            let edit = aiPlacement.edit(source: source as String, output: aiOutput, caret: aiInsertion)
            textView.undoManager?.beginUndoGrouping()
            aiEdit.active = true
            textView.insertText(edit.text, replacementRange: edit.range)
            aiEdit.active = false
            stampAIGenerated()
            textView.undoManager?.endUndoGrouping()
        }
        aiSuggestion = nil
        aiOutput = ""
        showAI = false
        showWritingMenu = false
    }

    private func copyAll(medium: Bool = false) {
        let source = document.text
        if medium {
            let mdx = MarkdownTextView.isMDX(fileURL)
            // The notice waits for the pasteboard write, after the HTML renders off the main thread.
            Task { showCopyNotice(.medium, copied: await DocumentExport.copyForMedium(source, mdx: mdx)) }
        } else {
            showCopyNotice(.markdown, copied: DocumentExport.copyAll(source))
        }
    }

    /// Shows the copy result briefly over the page and announces it to VoiceOver; editing carries on underneath.
    private func showCopyNotice(_ kind: CopyNotice.Kind, copied: Bool) {
        let notice = CopyNotice(kind: kind, failed: !copied)
        copyNoticeTask?.cancel()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { copyNotice = notice }
        AccessibilityNotification.Announcement(notice.message).post()
        copyNoticeTask = Task {
            try? await Task.sleep(for: .seconds(notice.failed ? 3 : 1.8))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.25)) { copyNotice = nil }
        }
    }

    private func exportHTML() { export(.html) }

    private func exportPDF() { export(.pdf) }

    /// Writes the document as a self-contained HTML page or a paginated PDF of that page.
    private func export(_ format: DocumentExport.Format) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format == .html ? .html : .pdf]
        panel.nameFieldStringValue = title + (format == .html ? ".html" : ".pdf")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let context = DocumentExport.Context(source: document.text, documentURL: fileURL, bundleRoot: bundleRoot, destination: url, fallbackTitle: title, baseDirectory: reportBase)
        exportTask?.cancel()
        exportTask = Task {
            do {
                switch format {
                case .html: try await DocumentExport.writeHTML(context)
                case .pdf: try await DocumentExport.writePDF(context)
                }
            } catch {
                if !Task.isCancelled { NSAlert(error: error).runModal() }
            }
        }
    }

    private func slashMenu(query: String) -> some View {
        let entries = slashEntries(query)
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
                                .background(index == slashSelection ? accent : .clear, in: .rect(cornerRadius: 11))
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
        .chromeGlass(in: .rect(cornerRadius: 18))
    }

    private func handleSlashKey(_ key: SlashKey, _ context: SlashContext) -> Bool {
        let entries = slashEntries(context.query)
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

    /// Slash entries, with /write only while generation at the caret is on and available.
    private func slashEntries(_ query: String) -> [SlashEntry] {
        SlashEntry.matching(query).filter { $0.title != "Write" || (generateAtCaret && aiAvailability == .available) }
    }

    private func insertSlash(_ entry: SlashEntry, context: SlashContext) {
        guard let textView else { return }
        entry.apply(to: textView, context: context)
        slashQuery = nil
        if entry.title == "Write" { openComposer() }
    }

    private func wrap(_ prefix: String, suffix: String? = nil) {
        guard let textView else { return }
        chromeVisible = true
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

    /// Restyles every block the selection touches as one undoable edit.
    private func applyBlockStyle(_ style: String) {
        guard let textView else { return }
        let source = textView.string as NSString
        var range = source.lineRange(for: textView.selectedRange())
        var lines = source.substring(with: range)
        // Keep the trailing newline outside the edit so the next block stays put.
        if lines.hasSuffix("\n") { lines.removeLast(); range.length -= 1 }
        textView.insertText(BlockStyle.apply(style, to: lines), replacementRange: range)
        chromeVisible = true
    }

    private func toggleWritingMenu() {
        guard selectedRange.length > 0 else { return }
        formatBarVisible = true
        showBlockMenu = false
        showWritingMenu.toggle()
        showAI = false
        if showWritingMenu { aiTask?.cancel(); aiBusy = false; aiOutput = ""; aiError = nil }
    }

    private func zoom(by step: Double) {
        proseSize = min(max(proseSize + step, Double(EditorTheme.proseSizes.lowerBound)), Double(EditorTheme.proseSizes.upperBound))
    }

    private func toggleLens() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) { markdownLens.toggle() }
        chromeVisible = true
        lastLens = markdownLens ? "Markdown" : "Rendered"
        rememberDocumentLens()
    }

    /// Per-document lens (extended attribute) when remembered, else the Settings default.
    private func initialLens() -> Bool {
        if fileURL == nil, document.report != nil { return false }
        if rememberLens, let fileURL, let stored = LensMemory.read(fileURL) { return stored }
        return (defaultLens == "Last used" ? lastLens : defaultLens) == "Markdown"
    }

    private func rememberDocumentLens() {
        guard rememberLens, let fileURL else { return }
        LensMemory.write(markdownLens, to: fileURL)
    }

    /// Mirrors tags once typing pauses, so editing `tags:` writes Finder tags once rather than per keystroke.
    private func mirrorTagsAfterTyping() {
        tagsTask?.cancel()
        tagsTask = Task {
            try? await Task.sleep(for: .milliseconds(750))
            if !Task.isCancelled { mirrorTags() }
        }
    }

    private func mirrorTags() {
        tagsTask?.cancel()
        guard let fileURL else { return }
        let tags = Frontmatter.parse(document.text)?.tags ?? []
        FinderTags.sync(fileURL, previous: mirroredTags, current: tags)
        mirroredTags = tags
    }

    // MARK: Knowledge (OKF)

    @ViewBuilder private var knowledgeMenu: some View {
        if let concept {
            Button("Mark Verified") { markVerified() }
            Picker("Status", selection: Binding(get: { concept.status.name }, set: { setStatus(OKFStatus($0)) })) {
                Text("Draft").tag("draft")
                Text("Stable").tag("stable")
                Text("Deprecated").tag("deprecated")
            }
        } else {
            Button("Make Concept…") { makeConcept() }
        }
        Divider()
        Button("Add Log Entry…") {
            guard let fileURL else { return }
            Knowledge.addLogEntry(for: fileURL, title: concept?.title ?? title, bundleRoot: bundleRoot)
            refreshKnowledge()
        }.disabled(fileURL == nil)
        Button("Rebuild Index") {
            guard let fileURL else { return }
            Task {
                await Knowledge.rebuildIndex(for: fileURL, bundleRoot: bundleRoot ?? fileURL.deletingLastPathComponent())
                refreshKnowledge()
            }
        }.disabled(fileURL == nil)
        Button("Show Bundle") { if !sidebarOpen { toggleSidebar() } }
        Button("Open Bundle Folder…") { BundleAccess.chooseAndOpen() }
    }

    /// Appends a `human:` verification stamp for Settings › Knowledge's ID.
    private func markVerified() {
        editFrontmatter { yaml in try OKFEditing.addingVerification(OKFStamp(by: Knowledge.actor, at: Date()), to: yaml) }
    }

    private func setStatus(_ status: OKFStatus) {
        editFrontmatter { OKFEditing.settingStatus(status, in: $0) }
    }

    /// Adds a `type`, offering the types already used in the bundle.
    private func makeConcept() {
        let used = Dictionary(grouping: knowledge?.bundle.concepts.compactMap(\.concept?.type) ?? [], by: { $0 })
            .sorted { $0.value.count > $1.value.count }.map(\.key)
        let alert = NSAlert()
        alert.messageText = "Make Concept"
        alert.informativeText = "An OKF concept needs a type, such as Metric, Playbook or Reference."
        let field = NSComboBox(frame: NSRect(x: 0, y: 0, width: 260, height: 26))
        field.addItems(withObjectValues: used.isEmpty ? ["Reference", "Playbook", "Metric"] : used)
        field.stringValue = used.first ?? "Reference"
        alert.accessoryView = field
        alert.addButton(withTitle: "Make Concept")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let type = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !type.isEmpty else { return }
        let entry = "type: \(OKFEditing.scalar(type))"
        // `type` leads the block, as in the spec's examples.
        editFrontmatter { yaml in OKFEditing.hasKey("type", in: yaml) ? OKFEditing.setting("type", to: entry, in: yaml) : entry + "\n" + yaml }
    }

    /// Records Apple Intelligence as the producer in an OKF concept's `generated`, once AI text is kept (§5.2).
    private func stampAIGenerated() {
        guard recordAIGenerated, concept != nil else { return }
        stampGenerated(by: Knowledge.aiActor)
    }

    /// After a pause in typing, records the person as the producer when the body changed (§5.2, §7).
    private func scheduleHumanStamp() {
        guard recordHumanGenerated, concept != nil else { return }
        humanStampTask?.cancel()
        humanStampTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let concept, FrontmatterBlock.body(of: document.text) != stampedBody else { return }
            // Once a day is enough: `at` marks the last meaningful change, not every keystroke.
            let me = Knowledge.actor
            if concept.generated?.by == me, let at = concept.generated?.at, Calendar.current.isDateInToday(at) {
                stampedBody = FrontmatterBlock.body(of: document.text)
                return
            }
            stampGenerated(by: me)
        }
    }

    private func stampGenerated(by actor: OKFActor) {
        let entry = "generated: " + OKFEditing.render(OKFStamp(by: actor, at: Date()))
        editFrontmatter(quiet: true) { OKFEditing.setting("generated", to: entry, in: $0) }
        stampedBody = FrontmatterBlock.body(of: textView?.string ?? document.text)
    }

    /// After Rename or Move To, offers to update links in the bundle that pointed at the old location (§6).
    private func offerToUpdateLinks(movedFrom old: URL, to new: URL) {
        guard let state = knowledge, OKFBundle.contains(state.bundle.root, old) else { return }
        let root = state.bundle.root
        let others = state.bundle.backlinks(to: old).filter { OKFBundle.key($0.url) != OKFBundle.key(old) }
        let ownText = textView?.string ?? document.text
        let ownUpdated = OKFEditing.retargetingLinks(in: ownText, document: old, root: root, movedFrom: old, to: new)
        guard !others.isEmpty || ownUpdated != ownText else { return }
        let alert = NSAlert()
        alert.messageText = "Update links to “\(new.lastPathComponent)”?"
        let count = others.count + (ownUpdated != ownText ? 1 : 0)
        alert.informativeText = "\(count) \(count == 1 ? "document links" : "documents link") to this file’s old location. Markify can point them at the new one."
        alert.addButton(withTitle: "Update Links")
        alert.addButton(withTitle: "Don’t Update")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if ownUpdated != ownText, let textView, textView.string == ownText {
            textView.insertText(ownUpdated, replacementRange: NSRange(location: 0, length: (ownText as NSString).length))
        }
        retargetTask?.cancel()
        retargetTask = Task {
            let work = Task.detached(priority: .userInitiated) {
                Knowledge.retargetFiles(others.map(\.url), root: root, movedFrom: old, to: new)
            }
            let failed = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            guard !Task.isCancelled else { return }
            if !failed.isEmpty {
                let alert = NSAlert()
                alert.messageText = "Some links couldn’t be updated."
                alert.informativeText = failed.map(\.path).joined(separator: "\n")
                alert.runModal()
            }
            refreshKnowledge()
        }
    }

    /// Rewrites the frontmatter YAML as one undoable edit, creating the block when missing, and keeps the caret in place.
    /// Quiet edits skip YAML they can't read instead of alerting.
    private func editFrontmatter(quiet: Bool = false, _ transform: (String) throws -> String) {
        guard let textView else { return }
        let block = FrontmatterBlock.locate(in: textView.string)
        let range = block.map { NSRange(location: $0.yamlRange.lowerBound, length: $0.yamlRange.count) } ?? NSRange(location: 0, length: 0)
        let replacement: String
        do {
            let yaml = try transform(block?.yaml ?? "")
            guard yaml != block?.yaml else { return }
            replacement = block == nil ? "---\n" + yaml + "---\n" : yaml
        } catch {
            guard !quiet else { return }
            let alert = NSAlert()
            alert.messageText = "The frontmatter couldn’t be updated."
            alert.informativeText = String(describing: error)
            alert.runModal()
            return
        }
        let selection = textView.selectedRange()
        textView.insertText(replacement, replacementRange: range)
        let delta = (replacement as NSString).length - range.length
        textView.setSelectedRange(selection.location >= NSMaxRange(range) ? NSRange(location: selection.location + delta, length: selection.length) : selection)
    }

    /// Names an untitled document's first save panel and fills its tags from the frontmatter, and starts it in the library when Settings asks.
    private func prepareSavePanel(_ window: NSWindow?) {
        guard fileURL == nil, let window, window === textView?.window else { return }
        DispatchQueue.main.async {
            guard let panel = window.attachedSheet as? NSSavePanel else { return }
            if let suggestedName, panel.nameFieldStringValue.hasPrefix("Untitled") { panel.nameFieldStringValue = suggestedName }
            if panel.tagNames?.isEmpty ?? true, let tags = Frontmatter.parse(document.text)?.tags, !tags.isEmpty { panel.tagNames = tags }
            guard newDocumentLocation == "Library" else { return }
            let folder = libraryFolder ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("Markify")
            guard let folder else { return }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            panel.directoryURL = folder
        }
    }
    private func toggleSidebar() {
        if !sidebarOpen { linksOpen = false }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.32)) { sidebarOpen.toggle() }
        chromeVisible = true
    }
    private func updateReading() {
        guard let position = (textView as? MarkdownTextView)?.readingPosition, position != reading else { return }
        reading = position
    }

    private func toggleLinks() {
        if !linksOpen { sidebarOpen = false }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.32)) { linksOpen.toggle() }
        chromeVisible = true
    }
    private func openFind(_ field: FindField) {
        showFind = true
        // The panel is inserted by this update, so focus its field on the next turn.
        DispatchQueue.main.async { findFocus = field }
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
        // Blocks start on a line of their own; inline math goes where the slash was typed.
        if title != "Inline math", let lastContent = prefix.lastIndex(where: { !$0.isWhitespace }) {
            let trailing = prefix[prefix.index(after: lastContent)...].utf16.count
            range.location -= trailing
            range.length += trailing
            inserted = "\n" + insertion
        }
        // `---` right under a line of text would make that line a setext heading, so a divider gets a blank line first.
        if title == "Divider" {
            let above = inserted.hasPrefix("\n") ? prefix
                : line.location > 0 ? source.substring(with: source.lineRange(for: NSRange(location: line.location - 1, length: 0))) : ""
            if !above.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { inserted = "\n" + inserted }
        }
        editor.insertText(inserted, replacementRange: range)
        let leading = inserted.hasPrefix("\n") ? 1 : 0
        let caret: (Int, Int)? = switch title {
        case "Table": (2, 6)
        case "Code block": (4, 0)
        case "Math": (3, 0)
        case "Inline math": (1, 1)
        case "Mermaid": (22, 7)
        case "Image": (2, 0)
        case "Frontmatter": (11, 0)
        case "Concept": (10, 0)
        default: nil
        }
        if let caret {
            editor.setSelectedRange(NSRange(location: range.location + leading + caret.0, length: caret.1))
        }
    }

    static let all: [Self] = [
        .init(title: "Write", symbol: "apple.intelligence", shortcut: "⌘↩", insertion: ""),
        .init(title: "Table", symbol: "tablecells", shortcut: "| — |", insertion: "| Column | Column |\n| --- | --- |\n|  |  |"),
        .init(title: "Task list", symbol: "checklist", shortcut: "- [ ]", insertion: "- [ ] "),
        .init(title: "Code block", symbol: "curlybraces", shortcut: "```", insertion: "```\n\n```"),
        .init(title: "Callout", symbol: "info.circle", shortcut: "> [!NOTE]", insertion: "> [!NOTE]\n> "),
        .init(title: "Math", symbol: "sum", shortcut: "$$", insertion: "$$\n\n$$"),
        .init(title: "Inline math", symbol: "x.squareroot", shortcut: "$…$", insertion: "$x$"),
        .init(title: "Mermaid", symbol: "flowchart", shortcut: "```mermaid", insertion: "```mermaid\ngraph TD\n  A --> B\n```"),
        .init(title: "Image", symbol: "photo", shortcut: "![]()", insertion: "![]()"),
        .init(title: "Heading 1", symbol: "textformat", shortcut: "#", insertion: "# "),
        .init(title: "Heading 2", symbol: "textformat", shortcut: "##", insertion: "## "),
        .init(title: "Heading 3", symbol: "textformat", shortcut: "###", insertion: "### "),
        .init(title: "Bullet", symbol: "list.bullet", shortcut: "-", insertion: "- "),
        .init(title: "Numbered", symbol: "list.number", shortcut: "1.", insertion: "1. "),
        .init(title: "Quote", symbol: "text.quote", shortcut: ">", insertion: "> "),
        .init(title: "Divider", symbol: "minus", shortcut: "---", insertion: "---"),
        .init(title: "Footnote", symbol: "textformat.superscript", shortcut: "[^1]", insertion: "[^1]: "),
        .init(title: "Frontmatter", symbol: "tag", shortcut: "---", insertion: "---\ntags: []\ndate: \n---"),
        .init(title: "Concept", symbol: "books.vertical", shortcut: "OKF", insertion: "---\ntype: \ntitle: \ndescription: \ntags: []\nstatus: draft\n---")
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

struct AIReview {
    var range: NSRange
    let original: String
    let result: String
    let title: String
    let action: String
    var comparing = false
}

/// The result of Copy All as Markdown, Copy All for Medium or a code block's copy button, shown briefly over the page.
struct CopyNotice: Equatable {
    enum Kind { case markdown, medium, code }

    let kind: Kind
    let failed: Bool

    var message: String {
        switch (kind, failed) {
        case (.markdown, false): String(localized: "Copied as Markdown")
        case (.medium, false): String(localized: "Copied for Medium")
        case (.code, false): String(localized: "Copied code")
        case (.markdown, true): String(localized: "Couldn’t copy as Markdown")
        case (.medium, true): String(localized: "Couldn’t copy for Medium")
        case (.code, true): String(localized: "Couldn’t copy code")
        }
    }
}

/// Marks edits Markify makes for AI results, so they aren't mistaken for typing.
final class AIEditGuard {
    var active = false
}

struct BlockStyle: Identifiable {
    let name: String
    let section: String
    let prefix: String
    let font: Font
    var id: String { name }

    static let all: [Self] = [
        .init(name: "Title", section: "Text", prefix: "#", font: .system(size: 20, weight: .bold, design: .serif)),
        .init(name: "Heading", section: "Text", prefix: "##", font: .system(size: 16, weight: .bold, design: .serif)),
        .init(name: "Subheading", section: "Text", prefix: "###", font: .system(size: 14, weight: .semibold, design: .serif)),
        .init(name: "Body", section: "Text", prefix: "", font: .system(size: 14, design: .serif)),
        .init(name: "Quote", section: "Text", prefix: ">", font: .system(size: 14, design: .serif).italic()),
        .init(name: "Code block", section: "Text", prefix: "```", font: .system(size: 12.5, design: .monospaced)),
        .init(name: "Callout", section: "Text", prefix: "> [!NOTE]", font: .system(size: 13)),
        .init(name: "Bulleted", section: "Lists", prefix: "-", font: .system(size: 13)),
        .init(name: "Numbered", section: "Lists", prefix: "1.", font: .system(size: 13)),
        .init(name: "Task", section: "Lists", prefix: "- [ ]", font: .system(size: 13)),
    ]

    /// Rewrites each non-empty line with the style's prefix, replacing any block prefix it had.
    static func apply(_ style: String, to lines: String) -> String {
        let pattern = #"^[ \t]*(#{1,6} |[-*+] \[[ xX]\] |[-*+] |[0-9]+[.)] |> \[![A-Za-z]+\][ \t]*|> )"#
        let stripped = lines.components(separatedBy: "\n").map { $0.replacingOccurrences(of: pattern, with: "", options: .regularExpression) }
        if style == "Code block" { return "```\n" + stripped.joined(separator: "\n") + "\n```" }
        var number = 0
        let styled = stripped.enumerated().map { index, line -> String in
            guard !line.isEmpty || style == "Callout" else { return line }
            switch style {
            case "Title": return "# " + line
            case "Heading": return "## " + line
            case "Subheading": return "### " + line
            case "Quote": return "> " + line
            case "Callout": return (index == 0 ? "> [!NOTE]\n> " : "> ") + line
            case "Bulleted": return "- " + line
            case "Numbered": number += 1; return "\(number). " + line
            case "Task": return "- [ ] " + line
            default: return line
            }
        }
        return styled.joined(separator: "\n")
    }
}

enum AIContext {
    /// The source range from the heading above `range` to the next heading after it, or the whole document without headings.
    static func section(around range: NSRange, in source: String) -> NSRange {
        let ns = source as NSString
        guard let regex = try? NSRegularExpression(pattern: #"(?m)^#{1,6}[ \t]"#) else { return NSRange(location: 0, length: ns.length) }
        let starts = regex.matches(in: source, range: NSRange(location: 0, length: ns.length)).map(\.range.location)
        let start = starts.last { $0 <= range.location } ?? 0
        let end = starts.first { $0 > max(start, NSMaxRange(range) - 1) } ?? ns.length
        return NSRange(location: start, length: max(end, NSMaxRange(range)) - start)
    }
}

/// Stores the lens a document was last shown in as an extended attribute, so the Markdown file stays clean.
enum LensMemory {
    static let attribute = "com.markify.lens"

    static func read(_ url: URL) -> Bool? {
        var buffer = [UInt8](repeating: 0, count: 16)
        let count = getxattr(url.path, attribute, &buffer, buffer.count, 0, 0)
        guard count > 0 else { return nil }
        switch String(decoding: buffer.prefix(count), as: UTF8.self) {
        case "markdown": return true
        case "rendered": return false
        default: return nil
        }
    }

    static func write(_ markdown: Bool, to url: URL) {
        let value = Array((markdown ? "markdown" : "rendered").utf8)
        _ = setxattr(url.path, attribute, value, value.count, 0, 0)
    }
}

/// Mirrors frontmatter `tags` onto the file's Finder tags, leaving tags added in Finder alone.
enum FinderTags {
    /// Finder tags after swapping the previously mirrored frontmatter tags for the current ones.
    static func merge(finder: [String], previous: [String], current: [String]) -> [String] {
        func same(_ a: String, _ b: String) -> Bool { a.caseInsensitiveCompare(b) == .orderedSame }
        var result = finder.filter { tag in !previous.contains { same($0, tag) } }
        for tag in current where !result.contains(where: { same($0, tag) }) { result.append(tag) }
        return result
    }

    /// Tag writes go through Spotlight (`mds`) and wait for its reply, so they run here, in order, off the main thread.
    private static let queue = DispatchQueue(label: "com.stephanepaquet.Markify.FinderTags", qos: .utility)

    static func sync(_ url: URL, previous: [String], current: [String]) {
        queue.async { write(url, previous: previous, current: current) }
    }

    private static func write(_ url: URL, previous: [String], current: [String]) {
        var url = url
        let finder = (try? url.resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []
        let merged = merge(finder: finder, previous: previous, current: current)
        guard merged != finder else { return }
        var values = URLResourceValues()
        values.tagNames = merged
        try? url.setResourceValues(values)
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
}

@Generable
struct SuggestedConcept {
    @Guide(description: "A concise title for the document") var title: String
    @Guide(description: "The kind of knowledge the document captures, as a short noun phrase such as Metric, Playbook, Reference or API Endpoint") var type: String
    @Guide(description: "One sentence summarizing the document") var description: String
    @Guide(description: "At most five short topic tags") var tags: [String]
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

struct LibraryNote: Identifiable {
    let url: URL
    let title: String
    let preview: String
    let folder: String
    var id: URL { url }

    static func path(of url: URL, in root: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
            .dropFirst(root.standardizedFileURL.resolvingSymlinksInPath().pathComponents.count).joined(separator: "/")
    }
}

final class DocumentWindowView: NSView {
    var text: Binding<String>?
    var tabBarInset: Binding<CGFloat>?
    private var layoutObservation: NSKeyValueObservation?
    private var fullScreenObservers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layoutObservation = nil
        fullScreenObservers.forEach(NotificationCenter.default.removeObserver)
        fullScreenObservers = []
        guard let window else { return }
        // The tab bar shows and hides with tabs, and full screen hides the titlebar but keeps the tab bar;
        // both change the content layout rect.
        layoutObservation = window.observe(\.contentLayoutRect) { [weak self] _, _ in
            DispatchQueue.main.async { self?.updateTabBarInset() }
        }
        fullScreenObservers = [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification].map {
            NotificationCenter.default.addObserver(forName: $0, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateTabBarInset() }
            }
        }
        updateTabBarInset()
    }

    /// While a tab bar shows, the top controls (normally 14pt from the top, beside the traffic lights)
    /// move to 8pt below the window chrome: the titlebar and tab bar in a window, the tab bar alone in
    /// full screen. The content layout rect's top inset covers both; it exceeds the bare titlebar
    /// (32pt in a window, none in full screen) only when a tab bar shows.
    func updateTabBarInset() {
        guard let window, let contentView = window.contentView else { return }
        let chrome = contentView.bounds.maxY - window.contentLayoutRect.maxY
        let titlebar = NSWindow.frameRect(forContentRect: .zero, styleMask: window.styleMask.subtracting(.fullSizeContentView)).height
        let inset = chrome > titlebar + 1 ? (chrome + 8 - 14).rounded() : 0
        if tabBarInset?.wrappedValue != inset { tabBarInset?.wrappedValue = inset }
    }
    lazy var fileRefresh = DocumentFileRefresh(
        readText: { [weak self] in self?.text?.wrappedValue ?? "" },
        writeText: { [weak self] in self?.text?.wrappedValue = $0 }
    )
    var isActive = true
    func watchDocument() {
        guard isActive else { return }
        guard let window, let document = NSDocumentController.shared.document(for: window) else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.watchDocument() }
            return
        }
        guard !MarkifyAppDelegate.replaceStartupDocument(with: document) else { return }
        fileRefresh.watch(window)
    }
}

private struct WindowConfiguration: NSViewRepresentable {
    @Binding var text: String
    /// The window title stays empty so the titlebar shows nothing; tabs still need a name (#82).
    let tabTitle: String
    @Binding var tabBarInset: CGFloat
    func makeNSView(context: Context) -> NSView {
        let view = DocumentWindowView()
        view.text = $text
        view.tabBarInset = $tabBarInset
        DispatchQueue.main.async {
            view.watchDocument()
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.title = ""
            window.styleMask.insert(.fullSizeContentView)
            // Settings › On launch decides which documents reopen, not system window restoration.
            window.isRestorable = false
        }
        return view
    }
    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        (nsView as? DocumentWindowView)?.isActive = false
        (nsView as? DocumentWindowView)?.fileRefresh.stop()
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? DocumentWindowView)?.text = $text
        (nsView as? DocumentWindowView)?.tabBarInset = $tabBarInset
        DispatchQueue.main.async {
            (nsView as? DocumentWindowView)?.watchDocument()
            nsView.window?.titleVisibility = .hidden
            nsView.window?.titlebarAppearsTransparent = true
            nsView.window?.title = ""
            if nsView.window?.tab.title != tabTitle { nsView.window?.tab.title = tabTitle }
        }
    }
}

extension View {
    /// A sidebar row for a file: a click opens it and a drag carries its URL, so dropping it into the page inserts a link.
    /// Not a `Button`, which tracks the mouse itself on macOS and never lets `onDrag` start.
    func sidebarRow(_ url: URL, open: @escaping () -> Void) -> some View {
        contentShape(.rect)
            .onTapGesture(perform: open)
            .onDrag { NSItemProvider(object: url as NSURL) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, open)
    }
}
