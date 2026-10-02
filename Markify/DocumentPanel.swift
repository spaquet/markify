import MarkifyMarkdown
import SwiftUI

/// A level 1 or 2 heading for the Contents list. `range` is the heading's text in source offsets.
struct DocumentHeading: Identifiable, Equatable {
    let range: NSRange
    let title: String
    let level: Int
    /// A level 2 heading under a level 1 heading, drawn indented beneath its section.
    let nested: Bool
    var id: Int { range.location }

    static func extract(from model: MarkdownModel) -> [Self] {
        let source = model.source as NSString
        // Inline syntax inside a heading (emphasis markers, link destinations, inline HTML) stays out of its title.
        var hidden = IndexSet()
        for span in model.spans {
            if case .heading = span.kind { continue }
            if case .inlineHTML = span.kind { hidden.insert(integersIn: span.range.location..<NSMaxRange(span.range)) }
            for marker in span.markers { hidden.insert(integersIn: marker.location..<NSMaxRange(marker)) }
        }
        var underSection = false
        return model.spans
            .compactMap { span -> (span: MarkdownModel.Span, level: Int)? in
                guard case let .heading(level, _) = span.kind, level <= 2 else { return nil }
                return (span, level)
            }
            .sorted { $0.span.range.location < $1.span.range.location }
            .map { span, level in
                let content = span.content
                var text = ""
                for piece in IndexSet(integersIn: content.location..<NSMaxRange(content)).subtracting(hidden).rangeView {
                    text += source.substring(with: NSRange(location: piece.lowerBound, length: piece.count))
                }
                if level == 1 { underSection = true }
                return Self(range: content, title: text.split(whereSeparator: \.isWhitespace).joined(separator: " "),
                            level: level, nested: level == 2 && underSection)
            }
    }
}

/// The right pane: the document's Contents (level 1 and 2 headings) or its Links, one at a time.
struct DocumentPanel<Links: View>: View {
    enum Tab: String { case contents, links }

    let headings: [DocumentHeading]
    let jump: (NSRange) -> Void
    @ViewBuilder let links: Links
    @AppStorage("documentPanelTab") private var tab = Tab.contents

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Show", selection: $tab) {
                Text("Contents").tag(Tab.contents)
                Text("Links").tag(Tab.links)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            switch tab {
            case .contents: ContentsList(headings: headings, jump: jump)
            case .links: links
            }
        }
        .padding(.horizontal, 14).padding(.top, 54).padding(.bottom, 12)
        .frame(width: 300).frame(maxHeight: .infinity)
        .chromeGlass(in: .rect(cornerRadius: 20))
    }
}

struct ContentsList: View {
    let headings: [DocumentHeading]
    let jump: (NSRange) -> Void
    @State private var hovered: Int?

    var body: some View {
        if headings.isEmpty {
            ContentUnavailableView("No headings", systemImage: "list.bullet.indent",
                                   description: Text("Level 1 and 2 headings in this document appear here."))
                .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(headings) { heading in
                        Button { jump(NSRange(location: heading.range.location, length: 0)) } label: {
                            Text(heading.title.isEmpty ? "Untitled" : heading.title)
                                .font(.system(size: 13, weight: heading.level == 1 ? .semibold : .regular))
                                .foregroundStyle(heading.title.isEmpty ? .tertiary : heading.level == 1 ? .primary : .secondary)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, heading.nested ? 14 : 0)
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(hovered == heading.id ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 8))
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .onHover { hovered = $0 ? heading.id : hovered == heading.id ? nil : hovered }
                        .help(heading.title)
                        .accessibilityLabel(heading.title.isEmpty ? "Untitled" : heading.title)
                        .accessibilityHint("Heading level \(heading.level). Moves the caret to this heading.")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.scrollIndicators(.never)
        }
    }
}
