import MarkifyMarkdown
import SwiftUI

/// Colors for the Contents and Links pane, from the Inspector design's light and dark tokens. The glass itself is the system's.
struct InspectorStyle {
    let dark: Bool
    let accent: Color

    private func gray(_ white: Double, _ opacity: Double = 1) -> Color { Color(white: white, opacity: opacity) }
    private static func hex(_ value: UInt32, _ opacity: Double = 1) -> Color {
        Color(red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255, blue: Double(value & 0xff) / 255, opacity: opacity)
    }

    var text: Color { dark ? Self.hex(0xf5f5f7) : Self.hex(0x1d1d1f) }
    var muted: Color { dark ? Self.hex(0x98989d) : Self.hex(0x6e6e73) }
    var faint: Color { dark ? Self.hex(0x6e6e73) : Self.hex(0xaeaeb2) }
    var accentSoft: Color { accent.opacity(dark ? 0.18 : 0.12) }
    var segmentBackground: Color { dark ? gray(0, 0.22) : gray(0, 0.05) }
    var segmentRing: Color { dark ? gray(1, 0.08) : gray(0, 0.06) }
    var segmentOn: Color { dark ? gray(1, 0.16) : .white }
    var fieldBackground: Color { dark ? gray(0, 0.22) : .white }
    var fieldRing: Color { dark ? gray(1, 0.1) : gray(0, 0.12) }
    var hover: Color { dark ? gray(1, 0.06) : gray(0, 0.04) }
    var guide: Color { gray(dark ? 1 : 0, 0.1) }
    var hairline: Color { gray(dark ? 1 : 0, 0.08) }
    var track: Color { dark ? gray(1, 0.1) : gray(0, 0.08) }
    var buttonBackground: Color { dark ? gray(1, 0.1) : gray(0, 0.05) }
    var buttonRing: Color { dark ? gray(1, 0.1) : gray(0, 0.08) }
    var tile: Color { dark ? gray(1, 0.08) : .white }
    var tileRing: Color { gray(dark ? 1 : 0, 0.1) }
    var red: Color { dark ? Self.hex(0xff6961) : Self.hex(0xd70015) }
    var redSoft: Color { dark ? Self.hex(0xff453a, 0.16) : Self.hex(0xff3b30, 0.1) }
    var summaryBackground: Color { dark ? Self.hex(0x2c2c30) : .white }
    static let intelligence = hex(0xbf5af2)
    static let intelligenceEdge = LinearGradient(colors: [hex(0xff9f0a), hex(0xff375f), hex(0xbf5af2), hex(0x0a84ff)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing)
    static let mono = Font.system(size: 11, design: .monospaced)
}

extension View {
    /// A selected segment: raised fill with the design's soft shadow.
    func inspectorSegment(_ on: Bool, style: InspectorStyle, radius: CGFloat) -> some View {
        background {
            if on {
                RoundedRectangle(cornerRadius: radius).fill(style.segmentOn)
                    .shadow(color: .black.opacity(style.dark ? 0.3 : 0.12), radius: style.dark ? 1 : 1.5, y: 1)
                    .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(style.dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 0.5))
            }
        }
    }

    func inspectorRing(_ color: Color, radius: CGFloat) -> some View {
        overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(color, lineWidth: 0.5))
    }
}

/// The right pane: Contents (the outline) and Links. It slides over the page.
struct DocumentInspector: View {
    enum Tab: String { case contents, links }

    let headings: [DocumentHeading]
    let links: [DocumentLink]
    let documentURL: URL?
    let bundleRoot: URL?
    let baseDirectory: URL?
    let readingOffset: Int
    let readingProgress: Double
    let accent: Color
    let jump: (NSRange) -> Void
    /// Whether the document already has a table of contents, which the button then updates.
    let hasTableOfContents: Bool
    let insertTableOfContents: (_ depth: Int) -> Void
    let fixLink: (_ occurrences: [DocumentLink], _ old: String, _ new: String) -> Void
    let follow: (DocumentLink) -> Void

    @AppStorage("documentPanelTab") private var tab = Tab.contents
    @State private var local = LocalLinkStatuses()
    @Environment(\.colorScheme) private var colorScheme
    private var style: InspectorStyle { InspectorStyle(dark: colorScheme == .dark, accent: accent) }

    var body: some View {
        let entries = LinkEntry.entries(links, document: documentURL, root: bundleRoot, baseDirectory: baseDirectory)
        VStack(spacing: 0) {
            Color.clear.frame(height: 48)
            InspectorTabs(tab: $tab, contents: headings.count, links: entries.count, style: style)
                .padding(.horizontal, 14).padding(.top, 6)
            switch tab {
            case .contents:
                ContentsTab(headings: headings, readingOffset: readingOffset, readingProgress: readingProgress, style: style,
                            jump: jump, hasTableOfContents: hasTableOfContents, insertTableOfContents: insertTableOfContents)
            case .links:
                LinksTab(entries: entries, headings: headings, documentURL: documentURL, style: style,
                         jump: jump, fixLink: fixLink, follow: follow)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(style.text)
        .frame(width: 356)
        .frame(maxHeight: .infinity)
        .chromeGlass(in: .rect(cornerRadius: 24))
        // Links are checked while the pane is open, whichever tab shows.
        .background(LinkChecking(entries: entries, headings: headings, documentURL: documentURL))
        .environment(local)
    }
}

/// The Contents | Links switch, drawn as in the design with each tab's count.
struct InspectorTabs: View {
    @Binding var tab: DocumentInspector.Tab
    let contents: Int
    let links: Int
    let style: InspectorStyle

    var body: some View {
        HStack(spacing: 0) {
            segment(.contents, "Contents", contents)
            segment(.links, "Links", links)
        }
        .padding(2)
        .frame(height: 32)
        .background(style.segmentBackground, in: .capsule)
        .inspectorRing(style.segmentRing, radius: 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Show")
    }

    private func segment(_ value: DocumentInspector.Tab, _ label: String, _ count: Int) -> some View {
        let on = tab == value
        return Button { withAnimation(.easeOut(duration: 0.18)) { tab = value } } label: {
            HStack(spacing: 6) {
                Text(label).fontWeight(on ? .semibold : .medium)
                Text("\(count)").font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(style.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .inspectorSegment(on, style: style, radius: 14)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label), \(count)")
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

// MARK: - Contents

struct ContentsTab: View {
    let headings: [DocumentHeading]
    let readingOffset: Int
    let readingProgress: Double
    let style: InspectorStyle
    let jump: (NSRange) -> Void
    let hasTableOfContents: Bool
    let insertTableOfContents: (_ depth: Int) -> Void

    @AppStorage("contentsDepth") private var depth = 3
    @State private var query = ""
    @State private var collapsed: Set<String> = []
    @State private var hovered: String?

    var body: some View {
        let rows = DocumentOutline.rows(headings, depth: depth, query: query, collapsed: collapsed)
        let active = DocumentOutline.active(headings, at: readingOffset)
        let ancestors = active.map { DocumentOutline.ancestors(of: $0, in: headings) } ?? []
        let top = headings.map(\.level).min() ?? 1
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                filterField
                depthControl
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            outlineRow(row, on: row.index == active, ancestor: ancestors.contains(row.index), top: top).id(row.id)
                        }
                        if rows.isEmpty {
                            Text(headings.isEmpty ? "No headings" : query.isEmpty ? "No headings at this depth" : "No headings match “\(query.trimmingCharacters(in: .whitespaces))”")
                                .font(.system(size: 12.5)).foregroundStyle(style.muted).multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity).padding(.horizontal, 12).padding(.vertical, 24)
                        }
                    }
                    .padding(.horizontal, 8).padding(.top, 4).padding(.bottom, 8)
                }
                .scrollIndicators(.automatic)
                .onChange(of: active) { _, index in
                    guard let index, rows.contains(where: { $0.index == index }) else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(headings[index].id) }
                }
            }
            footer(active: active)
        }
    }

    private var filterField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .medium)).foregroundStyle(style.muted)
            TextField("Filter headings", text: $query)
                .textFieldStyle(.plain).font(.system(size: 12.5))
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(style.muted) }
                    .buttonStyle(.plain).accessibilityLabel("Clear filter")
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(style.fieldBackground, in: .rect(cornerRadius: 8))
        .inspectorRing(style.fieldRing, radius: 8)
    }

    private var depthControl: some View {
        HStack(spacing: 0) {
            ForEach([(1, "H1"), (2, "H2"), (3, "H3"), (6, "All")], id: \.0) { value, label in
                let on = depth == value
                Button { depth = value } label: {
                    Text(label).font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(on ? style.text : style.muted)
                        .padding(.horizontal, 4).frame(minWidth: 26, maxHeight: .infinity)
                        .inspectorSegment(on, style: style, radius: 6)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(value == 6 ? "All levels" : "Down to heading level \(value)")
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .padding(2)
        .frame(height: 28)
        .background(style.segmentBackground, in: .rect(cornerRadius: 8))
        .inspectorRing(style.segmentRing, radius: 8)
        .help("Heading depth")
    }

    private func outlineRow(_ row: DocumentOutline.Row, on: Bool, ancestor: Bool, top: Int) -> some View {
        let heading = row.heading
        let relative = heading.level - top
        let size: CGFloat = relative == 0 ? 13.5 : relative == 1 ? 13 : 12.5
        let weight: Font.Weight = relative == 0 ? .bold : relative == 1 ? .semibold : .regular
        let color = on ? style.accent : ancestor || relative < 2 ? style.text : style.muted
        return Button { jump(NSRange(location: heading.range.location, length: 0)) } label: {
            HStack(spacing: 0) {
                ForEach(0..<row.indent, id: \.self) { guide in
                    Rectangle().fill(.clear).frame(width: 16, height: 30)
                        .overlay(alignment: .trailing) {
                            Rectangle().fill(guide == row.indent - 1 && (on || ancestor) ? style.accent : style.guide).frame(width: 1)
                        }
                }
                Group {
                    if row.hasChildren {
                        Button { toggle(heading.anchor) } label: {
                            Image(systemName: "arrowtriangle.right.fill").font(.system(size: 7)).foregroundStyle(style.muted)
                                .rotationEffect(.degrees(row.collapsed ? 0 : 90))
                                .frame(width: 20, height: 30).contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(row.collapsed ? "Expand \(heading.title)" : "Collapse \(heading.title)")
                    } else {
                        Color.clear.frame(width: 20, height: 30)
                    }
                }
                Text(heading.title.isEmpty ? "Untitled" : heading.title)
                    .font(.system(size: size, weight: weight))
                    .foregroundStyle(heading.title.isEmpty ? style.faint : color)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if on { Text("L\(heading.line)").font(InspectorStyle.mono).foregroundStyle(style.faint) }
            }
            .padding(.trailing, 8)
            .frame(height: 30)
            .background(on ? style.accentSoft : hovered == heading.id ? style.hover : .clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? heading.id : hovered == heading.id ? nil : hovered }
        .help(heading.title)
        .accessibilityLabel(heading.title.isEmpty ? "Untitled" : heading.title)
        .accessibilityValue(on ? "Reading" : "")
        .accessibilityHint("Heading level \(heading.level), line \(heading.line). Moves the caret to this heading.")
    }

    private func toggle(_ anchor: String) {
        withAnimation(.easeOut(duration: 0.18)) {
            if collapsed.contains(anchor) { collapsed.remove(anchor) } else { collapsed.insert(anchor) }
        }
    }

    private func footer(active: Int?) -> some View {
        let percent = Int((min(max(readingProgress, 0), 1) * 100).rounded())
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text("Reading \(Text(active.map { headings[$0].title } ?? "—").foregroundStyle(style.text).fontWeight(.medium))")
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(percent)%").monospacedDigit()
            }
            .font(.system(size: 11.5)).foregroundStyle(style.muted)
            Capsule().fill(style.track).frame(height: 3)
                .overlay(alignment: .leading) {
                    GeometryReader { geometry in
                        Capsule().fill(style.accent).frame(width: geometry.size.width * CGFloat(percent) / 100)
                            .animation(.easeOut(duration: 0.3), value: percent)
                    }
                }
                .accessibilityElement().accessibilityLabel("Reading progress").accessibilityValue("\(percent) percent")
            Button { insertTableOfContents(depth) } label: {
                Text(hasTableOfContents ? "Update Table of Contents" : "Insert Table of Contents").fontWeight(.medium)
                    .frame(maxWidth: .infinity).frame(height: 28)
                    .background(style.buttonBackground, in: .capsule)
                    .inspectorRing(style.buttonRing, radius: 14)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .disabled(headings.isEmpty)
            .help(hasTableOfContents ? "Rebuilds the document's table of contents with the headings shown at this depth"
                  : "Inserts a table of contents at the caret, with the headings shown at this depth; it then updates itself")
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 16)
        .overlay(alignment: .top) { Rectangle().fill(style.hairline).frame(height: 0.5) }
    }
}

// MARK: - Links

/// One destination in the Links pane, with every place the document links to it.
struct LinkEntry: Identifiable {
    let group: DocumentLinkGroup
    let target: LinkTarget
    /// The summary cache key: the destination without its `#section`, so a file's summary serves all its sections.
    let summaryKey: String
    var id: String { group.id }
    var first: DocumentLink { group.first }

    /// One entry per destination and section, in first-occurrence order: `other.md#a` and `other.md#b` can differ in health.
    @MainActor static func entries(_ links: [DocumentLink], document: URL?, root: URL?, baseDirectory: URL?) -> [Self] {
        var entries: [Self] = []
        var indices: [String: Int] = [:]
        for link in links {
            guard let target = LinkTarget.of(link.destination, document: document, root: root, baseDirectory: baseDirectory) else { continue }
            let summaryKey = LinkSummaryStore.key(link.destination, from: document, root: root, baseDirectory: baseDirectory) ?? link.destination
            let id = switch target {
            case let .file(_, fragment?): summaryKey + "#" + fragment
            default: summaryKey
            }
            if let index = indices[id] {
                var group = entries[index].group
                group.occurrences.append(link)
                entries[index] = Self(group: group, target: entries[index].target, summaryKey: summaryKey)
            } else {
                indices[id] = entries.count
                entries.append(Self(group: DocumentLinkGroup(id: id, occurrences: [link]), target: target, summaryKey: summaryKey))
            }
        }
        return entries
    }

    var displayDestination: String {
        guard case let .web(url) = target else { return first.destination }
        return url.absoluteString.replacingOccurrences(of: "^https?://", with: "", options: .regularExpression)
    }
}

/// Results of the local checks for the window, shared by the pane's tabs.
@MainActor @Observable final class LocalLinkStatuses {
    var statuses: [String: LinkStatus] = [:]
    var checking = false
    var checked: Date?
    var token = 0
}

/// Runs local checks off the main thread as the document changes, and web checks for links not checked in the last day.
struct LinkChecking: View {
    let entries: [LinkEntry]
    let headings: [DocumentHeading]
    let documentURL: URL?
    @Environment(LocalLinkStatuses.self) private var local

    private struct LocalInput: Equatable {
        let targets: [String: LinkTarget]
        let anchors: Set<String>
        let token: Int
    }

    var body: some View {
        let input = LocalInput(targets: Dictionary(entries.map { ($0.id, $0.target) }, uniquingKeysWith: { a, _ in a }),
                               anchors: Set(headings.map(\.anchor)), token: local.token)
        let web = entries.compactMap { entry -> URL? in if case let .web(url) = entry.target { url } else { nil } }
        Color.clear
            .task(id: input) {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                local.checking = true
                let texts = OpenTexts.snapshot(except: documentURL)
                let result = await Task.detached(priority: .utility) {
                    input.targets.mapValues { LocalLinkCheck.status(of: $0, anchors: input.anchors, openTexts: texts) }
                }.value
                guard !Task.isCancelled else { return }
                local.statuses = result
                local.checking = false
                local.checked = .now
            }
            .task(id: web) {
                // Opening the pane checks at once; edits wait until typing pauses.
                if local.checked != nil { try? await Task.sleep(for: .seconds(2)) }
                guard !Task.isCancelled else { return }
                await WebLinkChecks.shared.check(web, force: false)
            }
    }
}

/// The text of documents open in editors, which may be newer than the files on disk.
@MainActor enum OpenTexts {
    static func snapshot(except document: URL? = nil) -> [URL: String] {
        var texts: [URL: String] = [:]
        for editor in MarkdownTextView.openEditors.allObjects {
            guard let url = editor.documentURL?.standardizedFileURL, url != document?.standardizedFileURL else { continue }
            texts[url] = editor.string
        }
        return texts
    }
}

struct LinksTab: View {
    let entries: [LinkEntry]
    let headings: [DocumentHeading]
    let documentURL: URL?
    let style: InspectorStyle
    let jump: (NSRange) -> Void
    let fixLink: (_ occurrences: [DocumentLink], _ old: String, _ new: String) -> Void
    let follow: (DocumentLink) -> Void

    enum Filter: String { case all, anchor, file, web, broken }

    @Environment(LocalLinkStatuses.self) private var local
    @State private var filter = Filter.all
    @State private var summarizer = LinkSummarizer()

    private func status(_ entry: LinkEntry) -> LinkStatus {
        if case let .web(url) = entry.target { return WebLinkChecks.shared.status(of: url) }
        return local.statuses[entry.id] ?? .unknown
    }

    var body: some View {
        let statuses = Dictionary(entries.map { ($0.id, status($0)) }, uniquingKeysWith: { a, _ in a })
        let broken = entries.filter { statuses[$0.id]?.reason != nil }
        let shown = entries.filter { entry in
            switch filter {
            case .all: true
            case .broken: statuses[entry.id]?.reason != nil
            default: entry.target.kind.rawValue == filter.rawValue
            }
        }
        VStack(spacing: 0) {
            FlowLayout(spacing: 6) {
                chip(.all, "All", entries.count)
                chip(.anchor, "Document", entries.filter { $0.target.kind == .anchor }.count)
                chip(.file, "Files", entries.filter { $0.target.kind == .file }.count)
                chip(.web, "Web", entries.filter { $0.target.kind == .web }.count)
                chip(.broken, "Broken", broken.count)
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach([(LinkTarget.Kind.anchor, "In this document"), (.file, "Files"), (.web, "Web")], id: \.0) { kind, title in
                        let items = shown.filter { $0.target.kind == kind }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(style.muted)
                                    .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 4)
                                    .accessibilityAddTraits(.isHeader)
                                ForEach(items) { entry in
                                    LinkRow(entry: entry, status: statuses[entry.id] ?? .unknown, headings: headings, style: style,
                                            summarizer: summarizer, jump: jump, fixLink: fixLink, follow: follow, recheck: { recheck(entry) })
                                }
                            }
                        }
                    }
                    if shown.isEmpty {
                        Text(entries.isEmpty ? "Links in this document appear here." : filter == .broken ? "No broken links" : "No links of this kind")
                            .font(.system(size: 12.5)).foregroundStyle(style.muted)
                            .frame(maxWidth: .infinity).padding(.horizontal, 12).padding(.vertical, 24)
                    }
                }
                .padding(.horizontal, 8).padding(.top, 2).padding(.bottom, 8)
            }
            footer(brokenCount: broken.count)
        }
        .task(id: entries.map(\.id)) {
            let files = entries.compactMap { entry -> (key: String, url: URL)? in
                guard case let .file(url?, _) = entry.target, LinkSummarizer.canSummarize(entry.target) else { return nil }
                return (entry.summaryKey, url)
            }
            summarizer.checkStaleness(files, openTexts: OpenTexts.snapshot())
        }
    }

    private func chip(_ value: Filter, _ label: String, _ count: Int) -> some View {
        let on = filter == value
        return Button { filter = value } label: {
            HStack(spacing: 5) {
                if value == .broken { Circle().fill(style.red).frame(width: 6, height: 6) }
                Text(label).font(.system(size: 12, weight: .medium))
                Text("\(count)").font(.system(size: 11)).monospacedDigit().foregroundStyle(on ? Color.white.opacity(0.75) : style.muted)
            }
            .foregroundStyle(on ? Color.white : style.text)
            .padding(.horizontal, 9).frame(height: 24)
            .background(on ? style.accent : style.buttonBackground, in: .capsule)
            .inspectorRing(on ? .clear : style.buttonRing, radius: 12)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label), \(count)")
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    private func recheck(_ entry: LinkEntry) {
        if case let .web(url) = entry.target { Task { await WebLinkChecks.shared.check([url], force: true) } }
        else { local.token += 1 }
    }

    private func footer(brokenCount: Int) -> some View {
        let web = entries.compactMap { entry -> URL? in if case let .web(url) = entry.target { url } else { nil } }
        let checking = local.checking || web.contains { WebLinkChecks.shared.inFlight.contains(WebLinkChecks.key($0)) }
        let dates = web.compactMap { WebLinkChecks.shared.date(of: $0) } + [local.checked].compactMap { $0 }
        return HStack(spacing: 10) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(checking ? "Checking \(entries.count) \(entries.count == 1 ? "link" : "links")…"
                     : dates.min().map { "\(brokenCount == 0 ? "No broken links" : "\(brokenCount) broken") · checked \(Self.ago($0, now: context.date))" }
                     ?? "Not checked yet")
            }
            .font(.system(size: 11.5)).lineSpacing(2).foregroundStyle(style.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                local.token += 1
                Task { await WebLinkChecks.shared.check(web, force: true) }
            } label: {
                Text(checking ? "Checking…" : "Check Links").fontWeight(.medium)
                    .padding(.horizontal, 14).frame(height: 28)
                    .background(style.buttonBackground, in: .capsule)
                    .inspectorRing(style.buttonRing, radius: 14)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .disabled(checking || entries.isEmpty)
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 16)
        .overlay(alignment: .top) { Rectangle().fill(style.hairline).frame(height: 0.5) }
    }

    static func ago(_ date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3600)) h ago" }
        return date.formatted(.relative(presentation: .numeric, unitsStyle: .wide))
    }
}

struct LinkRow: View {
    let entry: LinkEntry
    let status: LinkStatus
    let headings: [DocumentHeading]
    let style: InspectorStyle
    let summarizer: LinkSummarizer
    let jump: (NSRange) -> Void
    let fixLink: (_ occurrences: [DocumentLink], _ old: String, _ new: String) -> Void
    let follow: (DocumentLink) -> Void
    let recheck: () -> Void

    @State private var hovered = false
    @State private var next = 0
    @State private var fixing = false
    @State private var summaryOpen = false

    private var broken: String? { status.reason }
    private var occurrences: [DocumentLink] { entry.group.occurrences }
    private var target: DocumentLink { occurrences[next % occurrences.count] }
    private var canSummarize: Bool { broken == nil && LinkSummarizer.available && LinkSummarizer.canSummarize(entry.target) }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: goToNext) {
                HStack(spacing: 10) {
                    tile
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(entry.first.text.isEmpty ? entry.first.destination : entry.first.text)
                                .fontWeight(.medium).lineLimit(1).truncationMode(.tail)
                            if occurrences.count > 1 {
                                Text("×\(occurrences.count)").font(.system(size: 11)).foregroundStyle(style.muted).fixedSize()
                            }
                        }
                        Text(entry.displayDestination).font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(broken == nil ? style.muted : style.red).lineLimit(1).truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if hovered || fixing { actions } else { meta }
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .frame(minHeight: 44)
                .background(hovered || summaryOpen ? style.hover : .clear, in: .rect(cornerRadius: 10))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 }
            .help(goToHelp)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("Goes to the link in the document.")
            .accessibilityActions {
                if broken != nil { Button("Fix Link…") { fixing = true } }
                else if entry.target.kind != .anchor { Button(entry.target.kind == .web ? "Open in Browser" : "Open File", action: open) }
                if canSummarize { Button(summaryOpen ? "Hide Summary" : "Summarize", action: toggleSummary) }
            }
            if summaryOpen {
                SummaryCard(key: entry.summaryKey, target: entry.target, summarizer: summarizer, style: style)
                    .padding(.leading, 46).padding(.trailing, 8).padding(.top, 2).padding(.bottom, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var tile: some View {
        let symbol = switch entry.target.kind {
        case .anchor: "number"
        case .file: "doc.text"
        case .web: "globe"
        }
        return Image(systemName: symbol).font(.system(size: 12, weight: .bold))
            .foregroundStyle(broken != nil ? style.red : entry.target.kind == .anchor ? style.accent : style.text)
            .frame(width: 28, height: 28)
            .background(broken != nil ? style.redSoft : style.tile, in: .rect(cornerRadius: 8))
            .inspectorRing(style.tileRing, radius: 8)
            .shadow(color: style.dark ? .clear : .black.opacity(0.05), radius: 1, y: 1)
    }

    private var meta: some View {
        HStack(spacing: 6) {
            if let broken {
                Text(broken).font(.system(size: 11, weight: .semibold)).foregroundStyle(style.red)
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .background(style.redSoft, in: .capsule).fixedSize()
            }
            Text("L\(entry.first.line)").font(InspectorStyle.mono).foregroundStyle(style.faint).fixedSize()
        }
    }

    private var actions: some View {
        HStack(spacing: 2) {
            action("arrow.uturn.backward", goToHelp, color: style.text, perform: goToNext)
            if broken != nil {
                action("pencil", "Fix link…", color: style.red) { fixing = true }
                    .popover(isPresented: $fixing, arrowEdge: .bottom) {
                        FixLinkPopover(entry: entry, reason: broken ?? "", headings: headings) { replacement in
                            fixing = false
                            fixLink(occurrences, entry.first.destination, replacement)
                        } cancel: { fixing = false }
                    }
            } else {
                if entry.target.kind != .anchor {
                    action("arrow.up.right", entry.target.kind == .web ? "Open in browser" : "Open file", color: style.text, perform: open)
                }
                if canSummarize {
                    action("sparkle", summaryOpen ? "Hide summary" : "Summarize", color: InspectorStyle.intelligence, active: summaryOpen, perform: toggleSummary)
                }
            }
        }
    }

    private func action(_ symbol: String, _ help: String, color: Color, active: Bool = false, perform: @escaping () -> Void) -> some View {
        ActionButton(symbol: symbol, color: color, active: active, style: style, perform: perform).help(help).accessibilityLabel(help)
    }

    private var goToHelp: String {
        let line = target.line
        return occurrences.count > 1 ? "Go to line \(line) (\(next % occurrences.count + 1) of \(occurrences.count))" : "Go to line \(line)"
    }

    private var accessibilityLabel: String {
        var label = "\(entry.first.text.isEmpty ? entry.first.destination : entry.first.text), \(entry.displayDestination), line \(entry.first.line)"
        if occurrences.count > 1 { label += ", \(occurrences.count) times" }
        if let broken { label += ", broken: \(broken)" }
        return label
    }

    private func goToNext() {
        jump(target.range)
        next = (next + 1) % occurrences.count
        recheck()
    }

    private func open() {
        follow(entry.first)
    }

    private func toggleSummary() {
        recheck()
        withAnimation(.easeOut(duration: 0.18)) { summaryOpen.toggle() }
        if summaryOpen, summarizer.store.entries[entry.summaryKey] == nil {
            summarizer.summarize(entry.target, key: entry.summaryKey, openTexts: OpenTexts.snapshot())
        }
    }
}

private struct ActionButton: View {
    let symbol: String
    let color: Color
    let active: Bool
    let style: InspectorStyle
    let perform: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: perform) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(active || hovered ? style.buttonBackground : .clear, in: .rect(cornerRadius: 7))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

/// The on-device summary under a link, with its date, staleness, refresh and errors.
struct SummaryCard: View {
    let key: String
    let target: LinkTarget
    let summarizer: LinkSummarizer
    let style: InspectorStyle

    var body: some View {
        let saved = summarizer.store.entries[key]
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").foregroundStyle(InspectorStyle.intelligence)
                Text("Summary")
                Spacer()
                Text("On-device").fontWeight(.medium)
            }
            .font(.system(size: 11, weight: .semibold)).foregroundStyle(style.muted)
            if let saved {
                SelectableLinkText(text: saved.text, font: .systemFont(ofSize: 12.5), color: NSColor(style.text))
            }
            if summarizer.busy.contains(key) {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Summarizing…") }
                    .font(.system(size: 12)).foregroundStyle(style.muted)
            } else if let error = summarizer.errors[key] {
                SelectableLinkText(text: error, font: .systemFont(ofSize: 11), color: NSColor(style.red))
            }
            if let saved, !summarizer.busy.contains(key) {
                HStack(spacing: 6) {
                    Text("Generated \(saved.date.formatted(date: .abbreviated, time: .shortened))\(summarizer.stale.contains(key) ? " · Source changed" : "")")
                    Spacer()
                    Button("Refresh") { summarizer.summarize(target, key: key, openTexts: OpenTexts.snapshot()) }
                        .buttonStyle(.plain).foregroundStyle(style.accent)
                }
                .font(.system(size: 11)).foregroundStyle(style.muted)
            } else if saved == nil, !summarizer.busy.contains(key), summarizer.errors[key] != nil {
                Button("Try Again") { summarizer.summarize(target, key: key, openTexts: OpenTexts.snapshot()) }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(style.accent)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(style.summaryBackground, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(InspectorStyle.intelligenceEdge, lineWidth: 1))
    }
}

/// Edits a broken link's destination, offering nearby headings or files. Every occurrence changes in one undo step.
struct FixLinkPopover: View {
    let entry: LinkEntry
    let reason: String
    let headings: [DocumentHeading]
    let replace: (String) -> Void
    let cancel: () -> Void

    @State private var destination = ""
    @State private var suggestions: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Fix Link").font(.headline)
            Text(reason).font(.system(size: 11.5)).foregroundStyle(.secondary)
            TextField("Destination", text: $destination)
                .font(.system(size: 12, design: .monospaced))
                .onSubmit(confirm)
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Suggestions").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button { destination = suggestion } label: {
                            Text(suggestion).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3).contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel).keyboardShortcut(.cancelAction)
                Button(entry.group.occurrences.count > 1 ? "Replace All \(entry.group.occurrences.count)" : "Replace", action: confirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(destination.trimmingCharacters(in: .whitespaces).isEmpty || destination == entry.first.destination)
            }
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { destination = entry.first.destination }
        .task { suggestions = await Self.suggestions(for: entry, headings: headings) }
    }

    private func confirm() {
        let value = destination.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, value != entry.first.destination else { return }
        replace(value)
    }

    static func suggestions(for entry: LinkEntry, headings: [DocumentHeading]) async -> [String] {
        let destination = entry.first.destination
        switch entry.target {
        case let .anchor(fragment):
            return LinkSuggestions.ranked(headings.map(\.anchor), near: fragment).map { "#" + $0 }
        case let .file(url?, fragment):
            let open = OpenTexts.snapshot()
            return await Task.detached(priority: .userInitiated) {
                var isDirectory: ObjCBool = false
                if open[url.standardizedFileURL] != nil || FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), let fragment {
                    // The file is there; its heading is not.
                    guard let text = open[url.standardizedFileURL] ?? (try? String(contentsOf: url, encoding: .utf8)) else { return [] }
                    let path = String(destination.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0])
                    let anchors = DocumentHeading.extract(from: MarkdownModel(text)).map(\.anchor)
                    return LinkSuggestions.ranked(anchors, near: fragment).map { path + "#" + $0 }
                }
                return LinkSuggestions.files(replacing: destination, missing: url)
            }.value
        default:
            return []
        }
    }
}

/// Lays out chips left to right, wrapping to new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += line + spacing; line = 0 }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}
