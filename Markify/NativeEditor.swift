import AppKit
import MarkifyMarkdown
import OKFKit
import SwaTex
import SwaTexRender
import SwiftUI

enum SlashKey { case up, down, insert, dismiss }

struct SlashContext {
    let range: NSRange
    let query: String

    static func detect(in text: String, selection: NSRange) -> Self? {
        guard selection.length == 0 else { return nil }
        let source = text as NSString
        guard selection.location <= source.length else { return nil }
        let line = source.lineRange(for: NSRange(location: selection.location, length: 0))
        let prefix = source.substring(with: NSRange(location: line.location, length: selection.location - line.location)) as NSString
        guard let slash = (0..<prefix.length).reversed().first(where: { prefix.character(at: $0) == 47 }) else { return nil }
        if slash > 0, !(UnicodeScalar(prefix.character(at: slash - 1)).map(CharacterSet.whitespaces.contains) ?? false) { return nil }
        let query = prefix.substring(from: slash + 1)
        guard !query.isEmpty || slash + 1 == prefix.length,
              !query.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) }) else { return nil }
        return Self(range: NSRange(location: line.location + slash, length: prefix.length - slash), query: query)
    }
}

struct NativeEditor: NSViewRepresentable {
    @Binding var text: String
    let fileURL: URL?
    let columnWidth: CGFloat
    let markdownLens: Bool
    let findQuery: String
    let matchCase: Bool
    @Binding var selectedRange: NSRange
    @Binding var textView: NSTextView?
    let onType: () -> Void
    let onSlash: (String?) -> Void
    let onSlashKey: (SlashKey, SlashContext) -> Bool
    let onSelectionRect: (CGRect) -> Void
    var theme = EditorTheme()
    /// The find match the selection sits on, drawn with the stronger highlight.
    var currentMatch: NSRange? = nil
    /// The OKF bundle root that `/…` links resolve against.
    var bundleRoot: URL? = nil
    /// Bundle-absolute paths offered while typing a link destination.
    var linkTargets: [String] = []

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.documentURL = fileURL
        editor.bundleRoot = bundleRoot
        editor.linkTargets = linkTargets
        editor.columnWidth = columnWidth
        editor.rendered = !markdownLens
        editor.theme = theme
        editor.registerForDraggedTypes([.fileURL])
        editor.isRichText = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.drawsBackground = false
        editor.textContainerInset = NSSize(width: 0, height: 40)
        editor.textContainer?.widthTracksTextView = true
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.delegate = context.coordinator
        editor.onSlashKey = { [weak coordinator = context.coordinator] key, slash in
            coordinator?.handleSlashKey(key, slash) ?? false
        }
        editor.string = text
        editor.writingToolsBehavior = .complete
        editor.allowedWritingToolsResultOptions = [.plainText, .richText, .table, .list]
        scroll.documentView = editor
        context.coordinator.editor = editor
        DispatchQueue.main.async {
            textView = editor
            editor.window?.makeFirstResponder(editor)
        }
        style(editor)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? NSTextView else { return }
        (editor as? MarkdownTextView)?.documentURL = fileURL
        (editor as? MarkdownTextView)?.bundleRoot = bundleRoot
        (editor as? MarkdownTextView)?.linkTargets = linkTargets
        (editor as? MarkdownTextView)?.columnWidth = columnWidth
        (editor as? MarkdownTextView)?.rendered = !markdownLens
        (editor as? MarkdownTextView)?.theme = theme
        context.coordinator.parent = self
        // A render can still carry text the editor pushed a keystroke ago; replaying it would drop the newer typing.
        let echo = context.coordinator.pushedText.contains(text)
        if editor.string == text || !echo { context.coordinator.pushedText.removeAll() }
        let sourceChanged = editor.string != text && !echo
        let styleChanged = context.coordinator.lastLens != markdownLens || context.coordinator.lastQuery != findQuery || context.coordinator.lastMatchCase != matchCase
            || context.coordinator.lastTheme != theme || context.coordinator.lastCurrentMatch != currentMatch
        if sourceChanged || styleChanged {
            let topOffset = editor.characterIndexForInsertion(at: NSPoint(x: 0, y: scroll.contentView.bounds.minY))
            let anchor = SourceAnchor(source: editor.string, selection: editor.selectedRange(), topOffset: topOffset)
            let before = editor.firstRect(forCharacterRange: anchor.topLine, actualRange: nil)
            context.coordinator.isUpdating = true
            if sourceChanged { editor.string = text }
            style(editor)
            editor.setSelectedRange(anchor.selection(in: editor.string))
            context.coordinator.isUpdating = false
            editor.layoutSubtreeIfNeeded()
            let after = editor.firstRect(forCharacterRange: anchor.topLine, actualRange: nil)
            let newY = max(0, scroll.contentView.bounds.minY + before.minY - after.minY)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: newY))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        context.coordinator.lastLens = markdownLens
        context.coordinator.lastQuery = findQuery
        context.coordinator.lastMatchCase = matchCase
        context.coordinator.lastTheme = theme
        context.coordinator.lastCurrentMatch = currentMatch
    }

    func style(_ editor: NSTextView) {
        guard let storage = editor.textStorage else { return }
        let source = editor.string as NSString
        let whole = NSRange(location: 0, length: source.length)
        let primary = NSColor.labelColor
        let dim = NSColor.tertiaryLabelColor
        let accent = theme.accent
        let base = markdownLens ? theme.mono(14) : theme.prose(18)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = (markdownLens ? 10 : 11) * theme.scale
        editor.typingAttributes = [.font: base, .foregroundColor: primary, .paragraphStyle: paragraph]
        guard whole.length > 0 else { return }
        storage.beginEditing()
        storage.setAttributes([.font: base, .foregroundColor: primary, .paragraphStyle: paragraph], range: whole)

        func matches(_ pattern: String, _ apply: (NSTextCheckingResult) -> Void) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return }
            regex.enumerateMatches(in: editor.string, range: whole) { match, _, _ in if let match { apply(match) } }
        }
        func marker(_ range: NSRange) {
            guard range.location != NSNotFound, range.length > 0 else { return }
            storage.addAttributes([.foregroundColor: markdownLens ? dim : NSColor.clear,
                                   .font: markdownLens ? theme.mono(14) : NSFont.systemFont(ofSize: 1)], range: range)
            // Even at 1pt the hidden marker keeps a sliver of advance; kern it back so text starts on the column edge.
            if !markdownLens {
                let width = storage.attributedSubstring(from: range).size().width
                storage.addAttribute(.kern, value: -width, range: NSRange(location: NSMaxRange(range) - 1, length: 1))
            }
        }
        let model = (editor as? MarkdownTextView)?.model ?? MarkdownModel(editor.string)
        let secondary = NSColor.secondaryLabelColor
        var hidden: [NSRange] = []
        /// Link and image destinations in the Markdown lens, colored after their dimmed markers.
        var destinations: [NSRange] = []
        /// Markers are styled after every font, since the hidden ones measure their own width.
        func hide(_ ranges: [NSRange]) { hidden += ranges }
        func adding(bold: Bool = false, italic: Bool = false, to range: NSRange) {
            guard range.length > 0 else { return }
            storage.enumerateAttribute(.font, in: range) { value, segment, _ in
                guard var font = value as? NSFont else { return }
                if bold { font = theme.adding(.bold, to: font) }
                if italic { font = theme.adding(.italic, to: font) }
                storage.addAttribute(.font, value: font, range: segment)
            }
        }
        let definitions = model.spans.compactMap { span -> (label: String, text: String, span: MarkdownModel.Span)? in
            guard case .footnoteDefinition(let label, _) = span.kind else { return nil }
            return (label, source.substring(with: span.content), span)
        }

        // Blocks: fonts and fills that inline styles then build on.
        for span in model.spans {
            switch span.kind {
            case .heading(let level, _):
                let size: CGFloat = markdownLens ? 16 : (level == 1 ? 36 : level == 2 ? 22 : 19)
                storage.addAttribute(.font, value: markdownLens ? theme.mono(size, weight: .bold) : theme.prose(size, bold: true), range: span.content)
                hide(span.markers)
            case .blockQuote:
                hide(span.markers)
            case .callout(let type, let token):
                let color = Callout.color(type, accent: accent)
                let name = NSRange(location: token.location + 2, length: token.length - 3)
                guard !markdownLens else { storage.addAttribute(.foregroundColor, value: color, range: name); continue }
                storage.addAttributes([.backgroundColor: NSColor.calloutFill(color), .font: theme.ui(15)], range: span.range)
                // The type token is hidden; MarkdownTextView draws its title ("Note") in its place.
                storage.addAttributes([.foregroundColor: NSColor.clear, .font: theme.ui(13, weight: .semibold)], range: token)
            case .listItem(let item):
                let spaced = NSMaxRange(item.checkbox ?? item.marker) < source.length && [32, 9].contains(source.character(at: NSMaxRange(item.checkbox ?? item.marker)))
                let prefix = NSRange(location: item.marker.location, length: NSMaxRange(item.checkbox ?? item.marker) - item.marker.location + (spaced ? 1 : 0))
                if markdownLens {
                    hide([prefix])
                } else if let box = item.checkbox {
                    // The checkbox is drawn over the hidden `- [ ] `; the item's first line takes the task style.
                    storage.addAttributes([.foregroundColor: NSColor.clear, .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)], range: prefix)
                    let line = source.lineRange(for: NSRange(location: box.location, length: 0))
                    var end = NSMaxRange(line)
                    while end > NSMaxRange(prefix), [10, 13].contains(source.character(at: end - 1)) { end -= 1 }
                    let text = NSRange(location: NSMaxRange(prefix), length: max(0, end - NSMaxRange(prefix)))
                    storage.addAttribute(.font, value: theme.ui(17), range: text)
                    if item.checked { storage.addAttributes([.foregroundColor: dim, .strikethroughStyle: NSUnderlineStyle.single.rawValue], range: text) }
                } else if item.ordered {
                    storage.addAttribute(.foregroundColor, value: secondary, range: item.marker)
                } else {
                    // A bullet is drawn over the hidden marker, which keeps its width.
                    storage.addAttributes([.foregroundColor: NSColor.clear, .font: theme.mono(18)], range: prefix)
                }
            case .codeBlock:
                storage.addAttributes([.font: theme.mono(markdownLens ? 14 : 13.5), .backgroundColor: NSColor.codeFill], range: span.content)
                hide(span.markers)
                let code = source.substring(with: span.content)
                let colors: [(String, CodeToken)] = [
                    (#"\b(func|let|var|if|else|return|class|struct|import|guard|private|def|const|function|for|while|in|true|false|nil|null)\b"#, .keyword),
                    (#"\b[A-Z][A-Za-z0-9_]*\b"#, .type),
                    (#""[^"\n]*"|\b[0-9]+(\.[0-9]+)?\b"#, .literal),
                    (#"(//|#)[^\n]*"#, .comment)
                ]
                for (pattern, kind) in colors {
                    guard let color = theme.code(kind), let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                    for token in regex.matches(in: code, range: NSRange(location: 0, length: (code as NSString).length)) {
                        storage.addAttribute(.foregroundColor, value: color, range: NSRange(location: span.content.location + token.range.location, length: token.range.length))
                    }
                }
            case .htmlBlock:
                storage.addAttribute(.foregroundColor, value: dim, range: span.range)
            case .footnoteDefinition(_, let label):
                storage.addAttributes([.font: markdownLens ? base : theme.ui(13), .foregroundColor: markdownLens ? dim : secondary], range: span.range)
                storage.addAttributes([.foregroundColor: accent, .font: markdownLens ? base : theme.ui(13, weight: .semibold)], range: label)
                guard !markdownLens else { continue }
                // The `:` stays visible after the number, as in the design's footnotes section.
                hide([span.markers[0], NSRange(location: span.markers[1].location, length: 1)])
                if span.range.location == definitions.first?.span.range.location {
                    let style = (storage.attribute(.paragraphStyle, at: span.range.location, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                    style.paragraphSpacingBefore = 26 * theme.scale
                    storage.addAttribute(.paragraphStyle, value: style, range: source.paragraphRange(for: span.range))
                }
            case .thematicBreak, .frontmatter, .mathBlock:
                hide(span.markers)
            default:
                break
            }
        }
        if markdownLens {
            // Table syntax: the separator row and the pipes around cells.
            for table in model.tables {
                for row in table.rows {
                    var location = row.start
                    for cell in row.cells + [NSRange(location: row.end, length: 0)] {
                        let gap = NSRange(location: location, length: cell.location - location)
                        if gap.length > 0, row.separator || source.substring(with: gap).contains("|") { storage.addAttribute(.foregroundColor, value: dim, range: gap) }
                        if row.separator { storage.addAttribute(.foregroundColor, value: dim, range: cell) }
                        location = NSMaxRange(cell)
                    }
                }
            }
        }

        // Inline styles, layered over the block fonts.
        // OKF footnote labels key into `sources` (§5.1).
        let sources = Dictionary(((try? OKFConcept.parse(source: editor.string)?.get())?.sources ?? []).compactMap { source in source.id.map { ($0, source) } },
                                 uniquingKeysWith: { first, _ in first })
        for span in model.spans {
            switch span.kind {
            case .strong:
                adding(bold: true, to: span.content)
                hide(span.markers)
            case .emphasis:
                adding(italic: true, to: span.content)
                hide(span.markers)
            case .strikethrough:
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: span.content)
                hide(span.markers)
            case .inlineCode:
                storage.addAttribute(.font, value: theme.mono(markdownLens ? 14 : 15), range: span.content)
                hide(span.markers)
            case .inlineMath:
                if !markdownLens { storage.addAttribute(.font, value: theme.prose(18, italic: true), range: span.content) }
                hide(span.markers)
            case .escape:
                hide(span.markers)
            case .link, .image(_, false):
                // The design keeps link text in ink in the Markdown lens and colors only the destination.
                if !markdownLens { storage.addAttribute(.foregroundColor, value: accent, range: span.content) }
                hide(span.markers)
                if markdownLens, let tail = span.markers.last, tail.length > 3 { destinations.append(NSRange(location: tail.location + 2, length: tail.length - 3)) }
            case .image(_, true):
                guard !markdownLens else {
                    hide(span.markers)
                    if let tail = span.markers.last, tail.length > 3 { destinations.append(NSRange(location: tail.location + 2, length: tail.length - 3)) }
                    continue
                }
                hide([span.range])
                let style = NSMutableParagraphStyle()
                style.alignment = .center
                style.paragraphSpacingBefore = 270
                style.paragraphSpacing = 34
                storage.addAttribute(.paragraphStyle, value: style, range: span.range)
            case .footnoteReference(let label):
                storage.addAttribute(.foregroundColor, value: accent, range: markdownLens ? span.range : span.content)
                guard !markdownLens else { continue }
                storage.addAttributes([.font: theme.ui(11, weight: .semibold), .baselineOffset: 7 * theme.scale], range: span.content)
                let cited = sources[label].map { source in
                    "Source: " + [source.title, source.resource, source.author?.displayName].compactMap { $0 }.joined(separator: " · ")
                }
                let tip = [definitions.first(where: { $0.label == label })?.text, cited].compactMap { $0 }.joined(separator: "\n\n")
                if !tip.isEmpty { storage.addAttribute(.toolTip, value: tip, range: span.content) }
                hide(span.markers)
            default:
                break
            }
        }

        for range in hidden { marker(range) }
        for range in destinations { storage.addAttribute(.foregroundColor, value: accent, range: range) }
        if !markdownLens {
            // A block image's caption shows its alt text under the drawn image.
            for span in model.spans { if case .image(_, true) = span.kind { storage.addAttributes([.font: theme.ui(13), .foregroundColor: secondary], range: span.content) } }
        }

        // Hanging indent: wrapped lines of a list item align with its text, not its marker.
        for span in model.spans {
            guard case .listItem(let item) = span.kind else { continue }
            let line = source.lineRange(for: NSRange(location: item.marker.location, length: 0))
            var end = NSMaxRange(item.checkbox ?? item.marker)
            if end < source.length, [32, 9].contains(source.character(at: end)) { end += 1 }
            let style = paragraph.mutableCopy() as! NSMutableParagraphStyle
            style.headIndent = storage.attributedSubstring(from: NSRange(location: line.location, length: end - line.location)).size().width
            storage.addAttribute(.paragraphStyle, value: style, range: line)
        }
        let lists = MarkdownList.scan(model)
        for lazy in lists.lazyLines {
            guard let owner = storage.attribute(.paragraphStyle, at: lazy.item, effectiveRange: nil) as? NSParagraphStyle,
                  let style = owner.mutableCopy() as? NSMutableParagraphStyle else { continue }
            style.firstLineHeadIndent = owner.headIndent
            storage.addAttribute(.paragraphStyle, value: style, range: source.paragraphRange(for: lazy.line))
        }
        if !markdownLens {
            // The file keeps its written numbers; MarkdownTextView draws each item's counted number over them.
            // Tabular digits padded to the list's widest number keep item text in one column.
            let font = NSFont(descriptor: base.fontDescriptor.addingAttributes([.featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector]]]), size: base.pointSize) ?? base
            let digit = ("0" as NSString).size(withAttributes: [.font: font]).width
            let numbers = lists.numbers
            let widest = Dictionary(numbers.map { ($0.list, $0.value.count) }, uniquingKeysWith: max)
            for number in numbers {
                // Hide digits and delimiter; pad the space after them so the text starts past the widest number.
                storage.addAttributes([.foregroundColor: NSColor.clear, .font: font], range: NSRange(location: number.range.location, length: number.range.length + 1))
                let pad = CGFloat((widest[number.list] ?? 1) - number.range.length) * digit
                if pad != 0 { storage.addAttribute(.kern, value: pad, range: NSRange(location: NSMaxRange(number.range) + 1, length: 1)) }
            }
            for table in model.tables {
                for row in table.rows {
                    let rowStyle = NSMutableParagraphStyle()
                    rowStyle.minimumLineHeight = row.separator ? 2 : 40
                    rowStyle.maximumLineHeight = row.separator ? 2 : 40
                    storage.addAttributes([.font: NSFont.systemFont(ofSize: 1),
                                           .foregroundColor: NSColor.clear,
                                           .paragraphStyle: rowStyle],
                                          range: NSRange(location: row.start, length: row.end - row.start))
                }
            }
            for span in model.spans where span.kind == .mathBlock {
                let style = NSMutableParagraphStyle()
                style.alignment = .center
                style.minimumLineHeight = 80
                storage.addAttributes([.font: NSFont.systemFont(ofSize: 1), .foregroundColor: NSColor.clear], range: span.range)
                storage.addAttribute(.paragraphStyle, value: style, range: NSRange(location: span.range.location, length: min(2, span.range.length)))
            }
        }
        if let frontmatter = model.spans.first(where: { $0.kind == .frontmatter }) {
            if markdownLens {
                matches("(?m)^([A-Za-z_][A-Za-z0-9_-]*):") { match in
                    if NSLocationInRange(match.range.location, frontmatter.content) {
                        storage.addAttribute(.foregroundColor, value: CodeToken.type.color, range: match.range(at: 1))
                    }
                }
            } else {
                // The YAML collapses to one chip row that MarkdownTextView draws; the source stays untouched.
                let hidden = NSMutableParagraphStyle()
                hidden.minimumLineHeight = 0.01
                hidden.maximumLineHeight = 0.01
                storage.addAttributes([.font: NSFont.systemFont(ofSize: 1), .foregroundColor: NSColor.clear, .paragraphStyle: hidden], range: frontmatter.range)
                let row = NSMutableParagraphStyle()
                row.minimumLineHeight = 24 * theme.scale
                row.maximumLineHeight = 24 * theme.scale
                row.paragraphSpacing = 20 * theme.scale
                storage.addAttribute(.paragraphStyle, value: row, range: source.lineRange(for: NSRange(location: frontmatter.range.location, length: 0)))
            }
        }
        if !findQuery.isEmpty {
            let options: NSRegularExpression.Options = matchCase ? [] : [.caseInsensitive]
            if let regex = try? NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: findQuery), options: options) {
                for match in regex.matches(in: editor.string, range: whole) {
                    var visible = true
                    if !markdownLens {
                        storage.enumerateAttribute(.foregroundColor, in: match.range) { value, _, stop in
                            if let color = value as? NSColor, color.alphaComponent == 0 { visible = false; stop.pointee = true }
                        }
                    }
                    if visible { storage.addAttribute(.backgroundColor, value: match.range == currentMatch ? NSColor.findCurrent : NSColor.findMatch, range: match.range) }
                }
            }
        }
        storage.endEditing()
        if let editor = editor as? MarkdownTextView {
            editor.refreshDecorations()
            DispatchQueue.main.async { [weak editor] in editor?.refreshTables() }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeEditor
        weak var editor: NSTextView?
        var lastLens = false
        var lastQuery = ""
        var lastMatchCase = false
        var lastTheme = EditorTheme()
        var lastCurrentMatch: NSRange?
        var isCreatingTitle = false
        /// Text sent to the binding that SwiftUI has not yet handed back.
        var pushedText: [String] = []
        /// True while updateNSView edits the text view, when SwiftUI state must not be written.
        var isUpdating = false
        var dismissedSlashLocation: Int?
        init(_ parent: NativeEditor) { self.parent = parent }
        @MainActor func handleSlashKey(_ key: SlashKey, _ slash: SlashContext) -> Bool {
            guard dismissedSlashLocation != slash.range.location else { return false }
            if key == .dismiss {
                dismissedSlashLocation = slash.range.location
                parent.onSlash(nil)
                return true
            }
            return parent.onSlashKey(key, slash)
        }
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            if !isCreatingTitle, textView.string.isEmpty,
               let replacementString, !replacementString.isEmpty,
               !replacementString.hasPrefix("/"),
               !replacementString.contains("\n") {
                isCreatingTitle = true
                textView.insertText("# " + replacementString, replacementRange: affectedCharRange)
                isCreatingTitle = false
                return false
            }
            return true
        }
        func textDidChange(_ notification: Notification) {
            guard let editor else { return }
            pushedText.append(editor.string)
            if pushedText.count > 32 { pushedText.removeFirst() }
            parent.text = editor.string
            if (editor as? MarkdownTextView)?.isRenumbering != true { parent.onType() }
            let slash = SlashContext.detect(in: editor.string, selection: editor.selectedRange())
            if slash?.range.location != dismissedSlashLocation { dismissedSlashLocation = nil }
            parent.onSlash(dismissedSlashLocation == nil ? slash?.query : nil)
            parent.style(editor)
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let editor else { return }
            if isUpdating {
                DispatchQueue.main.async { [weak self] in self?.textViewDidChangeSelection(notification) }
                return
            }
            parent.selectedRange = editor.selectedRange()
            let slash = SlashContext.detect(in: editor.string, selection: editor.selectedRange())
            parent.onSlash(slash?.range.location == dismissedSlashLocation ? nil : slash?.query)
            if let window = editor.window {
                let selection = editor.selectedRange()
                let position = editor.firstRect(forCharacterRange: NSRange(location: selection.location, length: max(1, selection.length)), actualRange: nil)
                let contentRect = window.convertFromScreen(position)
                parent.onSelectionRect(CGRect(x: contentRect.minX, y: window.contentView!.bounds.height - contentRect.maxY, width: contentRect.width, height: contentRect.height))
            }
        }
    }
}

final class MarkdownTextView: NSTextView {
    var documentURL: URL?
    var bundleRoot: URL?
    var linkTargets: [String] = []
    private var isCompletingLink = false
    var columnWidth: CGFloat = 640
    var rendered = true
    var theme = EditorTheme() { didSet { if theme != oldValue { mathCache = [:]; refreshDecorations() } } }
    var onSlashKey: ((SlashKey, SlashContext) -> Bool)?
    private var imageCache: [URL: NSImage] = [:]
    private var mathCache: [String: NSImage] = [:]
    private var tableOverlays: [Int: TableRowView] = [:]
    private var modelCache: MarkdownModel?

    /// The parsed source, shared by styling, drawing and clicks until the text changes.
    var model: MarkdownModel {
        if let modelCache, modelCache.source == string { return modelCache }
        let model = MarkdownModel(string)
        modelCache = model
        return model
    }

    func refreshTables() {
        guard let window else { return }
        let rows: [(MarkdownTable.Row, Bool)] = rendered ? MarkdownTable.blocks(in: model).flatMap { table in
            table.rows.enumerated().compactMap { index, row in row.separator ? nil : (row, index == 0) }
        } : []
        for (index, (row, header)) in rows.enumerated() {
            let screen = firstRect(forCharacterRange: NSRange(location: row.start, length: 1), actualRange: nil)
            let line = convert(window.convertFromScreen(screen), from: nil)
            let overlay = tableOverlays[index] ?? TableRowView()
            if overlay.superview == nil { addSubview(overlay) }
            tableOverlays[index] = overlay
            overlay.frame = NSRect(x: 0, y: line.minY, width: columnWidth, height: 40)
            overlay.update(cells: row.cells, source: string, header: header,
                           onEdit: { [weak self] range, value in
                               self?.replaceTableCell(range, with: value) ?? range
                           },
                           onFocus: { [weak self] range in
                               self?.setSelectedRange(NSRange(location: range.location, length: 0))
                           },
                           onTab: { [weak self] range, backward in
                               guard let self else { return }
                               self.setSelectedRange(range)
                               if self.navigateTable(backward: backward) {
                                   DispatchQueue.main.async { [weak self] in
                                       self?.refreshTables()
                                       self?.focusTableCell()
                                   }
                               }
                           })
        }
        for index in tableOverlays.keys.filter({ $0 >= rows.count }) {
            tableOverlays[index]?.removeFromSuperview()
            tableOverlays[index] = nil
        }
    }

    /// Writes a cell edit into the Markdown source and returns the cell's new range,
    /// so the next keystroke lands correctly before the overlays re-layout.
    func replaceTableCell(_ range: NSRange, with value: String) -> NSRange {
        insertText(value, replacementRange: range)
        return NSRange(location: range.location, length: (value as NSString).length)
    }

    private func focusTableCell() {
        let selection = selectedRange()
        for overlay in tableOverlays.values {
            if let field = overlay.fields.first(where: { $0.sourceRange == selection || $0.sourceRange.location == selection.location }) {
                window?.makeFirstResponder(field)
                field.selectText(nil)
                return
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        if rendered, event.keyCode == 48,
           event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
           navigateTable(backward: event.modifierFlags.contains(.shift)) { return }
        let key: SlashKey?
        switch event.keyCode {
        case 125: key = .down
        case 126: key = .up
        case 36, 76: key = .insert
        case 53: key = .dismiss
        default: key = nil
        }
        if event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
           let key, let slash = SlashContext.detect(in: string, selection: selectedRange()),
           onSlashKey?(key, slash) == true { return }
        if key == .insert, event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
           continueList() { return }
        super.keyDown(with: event)
    }

    private(set) var isRenumbering = false
    private var pendingEdit: (before: MarkdownList.Scan, range: NSRange, length: Int)?

    override func shouldChangeText(inRanges affectedRanges: [NSValue], replacementStrings: [String]?) -> Bool {
        guard super.shouldChangeText(inRanges: affectedRanges, replacementStrings: replacementStrings) else { return false }
        if !isRenumbering {
            // Remember list structure so a list that loses its first item keeps its start number.
            if affectedRanges.count == 1, let replacement = replacementStrings?.first {
                pendingEdit = (MarkdownList.scan(model), affectedRanges[0].rangeValue, (replacement as NSString).length)
            } else { pendingEdit = nil }
        }
        return true
    }

    /// Keeps ordered lists counting up after any edit, in the same undo group as the edit.
    override func didChangeText() {
        super.didChangeText()
        guard !isRenumbering, !(undoManager?.isUndoing ?? false), !(undoManager?.isRedoing ?? false) else { return }
        // Typing `](` or `](/` offers the bundle's concepts.
        if !isCompletingLink, !linkTargets.isEmpty, let range = linkTargetRange, selectedRange().location > 0,
           ["(", "/"].contains((string as NSString).substring(with: NSRange(location: selectedRange().location - 1, length: 1))),
           range.length <= 1 {
            DispatchQueue.main.async { [weak self] in self?.complete(nil) }
        }
        let edit = pendingEdit
        pendingEdit = nil
        renumberLists(MarkdownList.renumbering(model, previous: edit?.before, edit: edit?.range ?? NSRange(location: 0, length: 0), length: edit?.length ?? 0))
    }

    /// Applies list number fixes as one undoable edit, keeping the caret on its text.
    private func renumberLists(_ fixes: [(range: NSRange, value: String)]) {
        guard !isRenumbering, !fixes.isEmpty, let storage = textStorage else { return }
        isRenumbering = true
        defer { isRenumbering = false }
        guard shouldChangeText(inRanges: fixes.map { NSValue(range: $0.range) }, replacementStrings: fixes.map(\.value)) else { return }
        var selection = selectedRange()
        storage.beginEditing()
        for fix in fixes.reversed() {
            storage.replaceCharacters(in: fix.range, with: fix.value)
            if NSMaxRange(fix.range) <= selection.location { selection.location += (fix.value as NSString).length - fix.range.length }
        }
        storage.endEditing()
        didChangeText()
        setSelectedRange(selection)
    }

    /// Return inside a list item starts the next item; Return on an empty item ends the list.
    func continueList() -> Bool {
        let selection = selectedRange()
        guard selection.length == 0 else { return false }
        let source = string as NSString
        let line = source.lineRange(for: NSRange(location: selection.location, length: 0))
        // The innermost item whose marker is on this line, with the caret past its marker.
        let items = model.spans.compactMap { span -> MarkdownModel.ListItem? in
            guard case .listItem(let item) = span.kind, NSLocationInRange(item.marker.location, line) else { return nil }
            return item
        }
        guard let item = items.last else { return false }
        var end = NSMaxRange(item.checkbox ?? item.marker)
        var checkbox = item.checkbox != nil
        // An empty task item has no content for GFM to hang its checkbox on, so read the box from the text.
        if !checkbox, let box = try? NSRegularExpression(pattern: #"[ \t]\[[ xX]\](?=[ \t]|$)"#).firstMatch(in: string, options: .anchored, range: NSRange(location: end, length: NSMaxRange(line) - end)) {
            end = NSMaxRange(box.range)
            checkbox = true
        }
        guard end < NSMaxRange(line), [32, 9].contains(source.character(at: end)) else { return false }
        end += 1
        guard selection.location >= end else { return false }
        let rest = source.substring(with: NSRange(location: end, length: NSMaxRange(line) - end)).trimmingCharacters(in: .whitespacesAndNewlines)
        if rest.isEmpty {
            insertText("", replacementRange: NSRange(location: line.location, length: end - line.location))
            return true
        }
        let indent = source.substring(with: NSRange(location: line.location, length: item.marker.location - line.location))
        let marker = source.substring(with: item.marker)
        let next: String
        if let digits = item.digits {
            next = "\((Int(source.substring(with: digits)) ?? 0) + 1)\(marker.suffix(1)) "
        } else {
            next = marker + (checkbox ? " [ ]" : "") + " "
        }
        insertText("\n" + indent + next, replacementRange: selection)
        return true
    }

    func navigateTable(backward: Bool) -> Bool {
        guard let table = MarkdownTable.containing(model, location: selectedRange().location),
              let move = table.move(from: selectedRange().location, backward: backward) else { return false }
        switch move {
        case .select(let range): setSelectedRange(range)
        case .addRow(let replacement, let at, let caret):
            insertText(replacement, replacementRange: NSRange(location: at, length: 0))
            setSelectedRange(NSRange(location: at + caret, length: 0))
        }
        scrollRangeToVisible(selectedRange())
        return true
    }

    /// Task items in the Rendered lens, at any depth.
    private func tasks() -> [MarkdownModel.ListItem] {
        guard rendered else { return [] }
        return model.spans.compactMap { span in
            if case .listItem(let item) = span.kind, item.checkbox != nil { item } else { nil }
        }
    }

    private func checkboxRect(for item: MarkdownModel.ListItem) -> NSRect? {
        guard let window else { return nil }
        let screen = firstRect(forCharacterRange: NSRange(location: item.marker.location, length: 1), actualRange: nil)
        let local = convert(window.convertFromScreen(screen), from: nil)
        return NSRect(x: local.minX + 2, y: local.midY - 9, width: 18, height: 18)
    }

    /// TextKit 2 repaints edited text in its own fragment views without calling draw(_:) here,
    /// so rendered decorations live in a pass-through view kept over the visible area.
    private lazy var decorations = DecorationView(host: self)
    private var clipObserver: NSObjectProtocol?

    func refreshDecorations() {
        guard superview != nil else { return }
        if decorations.superview !== self { addSubview(decorations) }
        if decorations.frame != visibleRect { decorations.frame = visibleRect }
        decorations.needsDisplay = true
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if let clipObserver { NotificationCenter.default.removeObserver(clipObserver) }
        clipObserver = nil
        guard let clip = superview as? NSClipView else { return }
        clip.postsBoundsChangedNotifications = true
        clipObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDecorations() }
        }
        refreshDecorations()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        refreshDecorations()
    }

    /// Draws bullets, list numbers, checkboxes, images, math and chips; `dirtyRect` is in this view's coordinates.
    fileprivate func drawOverlays(_ dirtyRect: NSRect) {
        if rendered { drawImages(in: dirtyRect) }
        if rendered { drawMath(in: dirtyRect) }
        if rendered { drawDecorations(in: dirtyRect) }
        if rendered, let window {
            let source = string as NSString
            let numbers = MarkdownList.scan(model).numbers
            let widest = Dictionary(numbers.map { ($0.list, $0.value.count) }, uniquingKeysWith: max)
            for item in numbers {
                // Glyphs before the padded space keep reliable positions, so measure from the first digit.
                let screen = firstRect(forCharacterRange: item.range, actualRange: nil)
                let rect = convert(window.convertFromScreen(screen), from: nil)
                guard rect.intersects(dirtyRect) else { continue }
                let font = textStorage?.attribute(.font, at: item.range.location, effectiveRange: nil) as? NSFont ?? .systemFont(ofSize: 18)
                let digit = ("0" as NSString).size(withAttributes: [.font: font]).width
                let label = item.value + source.substring(with: NSRange(location: NSMaxRange(item.range), length: 1))
                let number = NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])
                number.draw(at: NSPoint(x: rect.minX + CGFloat((widest[item.list] ?? 1) - item.value.count) * digit, y: rect.minY))
            }
        }
        if rendered, let window {
            let dot = NSAttributedString(string: "•", attributes: [.font: theme.ui(18), .foregroundColor: NSColor.secondaryLabelColor])
            for span in model.spans {
                guard case .listItem(let item) = span.kind, !item.ordered, item.checkbox == nil else { continue }
                let screen = firstRect(forCharacterRange: item.marker, actualRange: nil)
                let rect = convert(window.convertFromScreen(screen), from: nil)
                guard rect.intersects(dirtyRect) else { continue }
                dot.draw(at: NSPoint(x: rect.midX - dot.size().width / 2, y: rect.midY - dot.size().height / 2))
            }
        }
        for item in tasks() {
            guard let rect = checkboxRect(for: item), rect.intersects(dirtyRect) else { continue }
            let checked = item.checked
            let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
            if checked {
                theme.accent.setFill()
                path.fill()
                let check = NSAttributedString(string: "✓", attributes: [.font: NSFont.boldSystemFont(ofSize: 13), .foregroundColor: NSColor.white])
                check.draw(at: NSPoint(x: rect.minX + 3, y: rect.minY + 1))
            } else {
                NSColor.tertiaryLabelColor.setStroke()
                path.lineWidth = 1.5
                path.stroke()
            }
        }
    }

    private func drawImages(in dirtyRect: NSRect) {
        guard let window else { return }
        for span in model.spans {
            guard case .image(let path, true) = span.kind else { continue }
            let screen = firstRect(forCharacterRange: span.content, actualRange: nil)
            let caption = convert(window.convertFromScreen(screen), from: nil)
            let rect = NSRect(x: 0, y: caption.minY - 268, width: columnWidth, height: 260)
            guard rect.intersects(dirtyRect) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14).addClip()
            NSColor.quaternaryLabelColor.withAlphaComponent(0.08).setFill()
            rect.fill()
            let url = Self.imageURL(path, document: documentURL)
            if let image = imageCache[url] ?? NSImage(contentsOf: url) {
                imageCache[url] = image
                let ratio = min(rect.width / image.size.width, rect.height / image.size.height)
                let size = NSSize(width: image.size.width * ratio, height: image.size.height * ratio)
                let frame = NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
                image.draw(in: frame)
            } else {
                let label = "image — \(url.lastPathComponent)" as NSString
                label.draw(at: NSPoint(x: rect.midX - 90, y: rect.midY - 8), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor])
            }
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    /// Resolves an image destination against the document's folder; inserted paths are percent-encoded.
    static func imageURL(_ path: String, document: URL?) -> URL {
        let base = document?.deletingLastPathComponent() ?? URL(fileURLWithPath: "/")
        return URL(fileURLWithPath: path.removingPercentEncoding ?? path, relativeTo: base).standardizedFileURL
    }

    private func drawMath(in dirtyRect: NSRect) {
        guard let window else { return }
        let source = string as NSString
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        for span in model.spans where span.kind == .mathBlock {
            let screen = firstRect(forCharacterRange: NSRange(location: span.range.location, length: 1), actualRange: nil)
            let line = convert(window.convertFromScreen(screen), from: nil)
            let rect = NSRect(x: 0, y: line.midY - 40, width: columnWidth, height: 80)
            guard rect.intersects(dirtyRect) else { continue }
            let latex = source.substring(with: span.content).trimmingCharacters(in: .whitespacesAndNewlines)
            let key = "\(dark):\(latex)"
            if let image = mathCache[key] ?? renderMath(latex, dark: dark) {
                mathCache[key] = image
                let frame = NSRect(x: rect.midX - image.size.width / 2, y: rect.midY - image.size.height / 2,
                                   width: image.size.width, height: image.size.height)
                image.draw(in: frame)
            } else {
                (latex as NSString).draw(at: NSPoint(x: rect.minX, y: rect.midY - 11),
                                         withAttributes: [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.secondaryLabelColor])
            }
        }
    }

    func renderMath(_ latex: String, dark: Bool) -> NSImage? {
        guard let list = try? SwaTexEngine.displayList(for: latex, style: .display, color: dark ? .white : .black),
              let data = ImageRenderer.png(for: list, options: RenderOptions(fontSize: 22 * theme.scale, padding: 2)),
              let image = NSImage(data: data) else { return nil }
        image.size = NSSize(width: image.size.width / 2, height: image.size.height / 2)
        return image
    }

    /// Callout titles, code language labels, the footnotes rule and the frontmatter chip row.
    private func drawDecorations(in dirtyRect: NSRect) {
        guard let window else { return }
        func rect(_ range: NSRange) -> NSRect { convert(window.convertFromScreen(firstRect(forCharacterRange: range, actualRange: nil)), from: nil) }

        for span in model.spans {
            switch span.kind {
            case .callout(let type, let range):
                let token = rect(range)
                guard token.intersects(dirtyRect.insetBy(dx: 0, dy: -20)) else { continue }
                let title = NSAttributedString(string: type.capitalized, attributes: [
                    .font: theme.ui(13, weight: .semibold), .foregroundColor: Callout.color(type, accent: theme.accent)])
                title.draw(at: NSPoint(x: token.minX, y: token.maxY - title.size().height))
            case .codeBlock(let language?, true) where span.content.length > 0:
                let line = rect(NSRange(location: span.content.location, length: 1))
                guard line.intersects(dirtyRect.insetBy(dx: 0, dy: -20)) else { continue }
                let label = NSAttributedString(string: language, attributes: [
                    .font: theme.ui(11, weight: .medium), .foregroundColor: NSColor.tertiaryLabelColor])
                label.draw(at: NSPoint(x: columnWidth - label.size().width - 12, y: line.minY + 2))
            default:
                break
            }
        }
        if let first = model.spans.first(where: { if case .footnoteDefinition = $0.kind { true } else { false } }) {
            let line = rect(NSRange(location: first.range.location, length: 1))
            let y = line.minY - 12 * theme.scale
            if dirtyRect.minY <= y, y <= dirtyRect.maxY {
                NSColor.separatorColor.setFill()
                NSRect(x: 0, y: y, width: columnWidth, height: 1).fill()
            }
        }
        if let frontmatter = Frontmatter.parse(string) {
            for (chip, frame) in frontmatterChips(frontmatter) where frame.intersects(dirtyRect) {
                if let fill = chip.fill {
                    fill.setFill()
                    NSBezierPath(roundedRect: frame, xRadius: frame.height / 2, yRadius: frame.height / 2).fill()
                }
                chip.text.draw(at: NSPoint(x: frame.minX + (chip.fill != nil ? 9 : 0), y: frame.midY - chip.text.size().height / 2))
            }
        }
    }

    /// One item in the frontmatter row: a capsule when it has a fill, plain text otherwise; `link` makes it follow a destination.
    struct FrontmatterChip {
        let text: NSAttributedString
        let fill: NSColor?
        var link: String? = nil
    }

    /// The OKF reading of the frontmatter, reparsed only when the YAML changes.
    private func okfConcept(_ frontmatter: Frontmatter) -> OKFConcept? {
        let yaml = (string as NSString).substring(with: frontmatter.body)
        if let cached = conceptCache, cached.yaml == yaml { return cached.concept }
        let concept = (try? OKFConcept(yaml: yaml)).flatMap { $0.isConcept ? $0 : nil }
        conceptCache = (yaml, concept)
        return concept
    }
    private var conceptCache: (yaml: String, concept: OKFConcept?)?

    /// Type, status, staleness and trust badges for an OKF concept, ahead of the tags.
    private func okfChips(_ concept: OKFConcept) -> [FrontmatterChip] {
        let font = theme.ui(11.5, weight: .medium)
        func chip(_ text: String, _ color: NSColor, filled: Bool = true) -> FrontmatterChip {
            FrontmatterChip(text: NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color]),
                            fill: filled ? color.withAlphaComponent(0.13) : nil)
        }
        var chips = [chip(concept.type ?? "", theme.accent)]
        switch concept.status {
        case .stable: break
        case .draft: chips.append(chip("Draft", .systemOrange))
        case .deprecated: chips.append(chip("Deprecated", .systemRed))
        case .other(let raw): chips.append(chip(raw, .secondaryLabelColor))
        }
        if concept.isStale() { chips.append(chip("Stale", .systemOrange)) }
        switch concept.trustTier {
        case .humanReviewed: chips.append(chip("✓ Reviewed", .systemGreen))
        case .machineConfirmed: chips.append(chip("Machine-confirmed", .secondaryLabelColor))
        case .unverified: chips.append(chip("Unverified", .tertiaryLabelColor, filled: false))
        }
        return chips
    }

    /// Chip layout for the frontmatter row: OKF badges, tags as capsules, the date as plain text, then the OKF resource link.
    private func frontmatterChips(_ frontmatter: Frontmatter) -> [(chip: FrontmatterChip, frame: NSRect)] {
        guard let window else { return [] }
        let screen = firstRect(forCharacterRange: NSRange(location: frontmatter.range.location, length: 1), actualRange: nil)
        let line = convert(window.convertFromScreen(screen), from: nil)
        let font = theme.ui(11.5, weight: .medium)
        let tagFill = NSColor.labelColor.withAlphaComponent(0.06)
        let concept = okfConcept(frontmatter)
        var items = concept.map(okfChips) ?? []
        items += frontmatter.tags.map { FrontmatterChip(text: NSAttributedString(string: $0, attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]), fill: tagFill) }
        if let date = frontmatter.displayDate {
            items.append(FrontmatterChip(text: NSAttributedString(string: date, attributes: [.font: theme.ui(11.5), .foregroundColor: NSColor.secondaryLabelColor]), fill: nil))
        }
        if let resource = concept?.resource {
            let label = URL(string: resource)?.host() ?? (resource as NSString).lastPathComponent
            items.append(FrontmatterChip(text: NSAttributedString(string: "↗ " + label, attributes: [.font: theme.ui(11.5), .foregroundColor: theme.accent]), fill: nil, link: resource))
        }
        if items.isEmpty {
            items.append(FrontmatterChip(text: NSAttributedString(string: "Frontmatter", attributes: [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]), fill: tagFill))
        }
        var x: CGFloat = 0
        return items.compactMap { item in
            let width = item.text.size().width + (item.fill != nil ? 18 : 0)
            // Chips past the column edge are dropped rather than drawn outside it.
            guard x + width <= columnWidth || x == 0 else { return nil }
            let height = item.text.size().height + 6
            let frame = NSRect(x: x, y: line.midY - height / 2, width: width, height: height)
            x += width + 6
            return (item, frame)
        }
    }

    /// Edits the frontmatter YAML in a small popover, writing it back to the source as one undoable change.
    private func editFrontmatter(_ frontmatter: Frontmatter, at frame: NSRect) {
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 280, height: 120))
        editor.isRichText = false
        editor.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        editor.textContainerInset = NSSize(width: 8, height: 8)
        editor.string = (string as NSString).substring(with: frontmatter.body)
        let scroll = NSScrollView(frame: editor.frame)
        scroll.documentView = editor
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        editor.drawsBackground = false
        let controller = NSViewController()
        controller.view = scroll
        let popover = NSPopover()
        popover.contentViewController = controller
        popover.behavior = .transient
        let body = frontmatter.body
        let original = editor.string
        frontmatterPopoverClose = NotificationCenter.default.addObserver(forName: NSPopover.didCloseNotification, object: popover, queue: .main) { [weak self, weak editor] _ in
            MainActor.assumeIsolated {
                guard let self, let editor else { return }
                if let token = self.frontmatterPopoverClose { NotificationCenter.default.removeObserver(token) }
                self.frontmatterPopoverClose = nil
                if editor.string != original, NSMaxRange(body) <= (self.string as NSString).length {
                    self.insertText(editor.string, replacementRange: body)
                }
            }
        }
        popover.show(relativeTo: frame, of: self, preferredEdge: .maxY)
        popover.contentViewController?.view.window?.makeFirstResponder(editor)
    }
    private var frontmatterPopoverClose: NSObjectProtocol?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if rendered, let frontmatter = Frontmatter.parse(string),
           let hit = frontmatterChips(frontmatter).first(where: { $0.frame.contains(point) }) {
            if let link = hit.chip.link { return Knowledge.follow(link, title: nil, from: documentURL, bundleRoot: bundleRoot) }
            return editFrontmatter(frontmatter, at: hit.frame)
        }
        // ⌘-click follows a link, resolving `/…` against the OKF bundle root.
        if event.modifierFlags.contains(.command), let link = OKFLinks.link(at: characterIndexForInsertion(at: point), in: string) {
            return Knowledge.follow(link.target, title: link.text, from: documentURL, bundleRoot: bundleRoot)
        }
        for item in tasks() {
            guard let rect = checkboxRect(for: item), rect.contains(point), let box = item.checkbox else { continue }
            insertText(item.checked ? " " : "x", replacementRange: NSRange(location: box.location + 1, length: 1))
            return
        }
        super.mouseDown(with: event)
    }

    /// The partial destination between `](` and the caret, when the caret is inside one.
    private var linkTargetRange: NSRange? {
        let selection = selectedRange()
        guard selection.length == 0 else { return nil }
        let source = string as NSString
        let line = source.lineRange(for: NSRange(location: selection.location, length: 0))
        let prefix = source.substring(with: NSRange(location: line.location, length: selection.location - line.location))
        guard let match = try? NSRegularExpression(pattern: #"\]\((/?[^)\s]*)$"#).firstMatch(in: prefix, range: NSRange(location: 0, length: (prefix as NSString).length)) else { return nil }
        let partial = match.range(at: 1)
        let value = (prefix as NSString).substring(with: partial)
        guard value.isEmpty || value.hasPrefix("/") else { return nil }
        return NSRange(location: line.location + partial.location, length: partial.length)
    }

    override var rangeForUserCompletion: NSRange {
        (linkTargets.isEmpty ? nil : linkTargetRange) ?? super.rangeForUserCompletion
    }

    override func completions(forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String]? {
        guard !linkTargets.isEmpty, let range = linkTargetRange, range == charRange else {
            return super.completions(forPartialWordRange: charRange, indexOfSelectedItem: index)
        }
        let partial = (string as NSString).substring(with: range)
        let matches = linkTargets.filter { partial.isEmpty || partial == "/" || $0.localizedCaseInsensitiveContains(partial) }
        return Array(matches.prefix(40)).map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0 }
    }

    override func insertCompletion(_ word: String, forPartialWordRange charRange: NSRange, movement: Int, isFinal flag: Bool) {
        isCompletingLink = true
        super.insertCompletion(word, forPartialWordRange: charRange, movement: movement, isFinal: flag)
        isCompletingLink = false
    }

    static let imageExtensions = ["png", "jpg", "jpeg", "gif", "heic", "webp"]

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let imageURL = NSURL(from: sender.draggingPasteboard) as URL?,
              Self.imageExtensions.contains(imageURL.pathExtension.lowercased()) else {
            return super.performDragOperation(sender)
        }
        return insertImage(imageURL)
    }

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if let url = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?.first,
           Self.imageExtensions.contains(url.pathExtension.lowercased()) {
            _ = insertImage(url)
        } else if documentURL != nil, pasteboard.string(forType: .string) == nil,
                  let image = NSImage(pasteboard: pasteboard), let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: ".")
            _ = insertImage(data: png, name: "Pasted image \(stamp).png")
        } else {
            super.paste(sender)
        }
    }

    /// Settings › Save pasted images to: a folder name beside the document, or "" for the document's own folder.
    private var imageFolder: String {
        (UserDefaults.standard.string(forKey: "imageFolder") ?? "./assets").replacingOccurrences(of: "./", with: "")
    }

    private func insertImage(_ imageURL: URL) -> Bool {
        guard documentURL != nil else {
            insertText("![\(imageURL.deletingPathExtension().lastPathComponent)](\(imageURL.path))", replacementRange: selectedRange())
            return true
        }
        return insertImage(data: nil, name: imageURL.lastPathComponent, copying: imageURL)
    }

    /// Copies an image beside the document (numbering name collisions) and links it with a relative path.
    private func insertImage(data: Data?, name: String, copying source: URL? = nil) -> Bool {
        guard let documentURL else { return false }
        do {
            var folder = documentURL.deletingLastPathComponent()
            if !imageFolder.isEmpty { folder.appendPathComponent(imageFolder, isDirectory: true) }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let stem = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            var target = folder.appendingPathComponent(name)
            var number = 2
            while FileManager.default.fileExists(atPath: target.path) {
                target = folder.appendingPathComponent("\(stem)-\(number).\(ext)")
                number += 1
            }
            if let source { try FileManager.default.copyItem(at: source, to: target) } else { try data?.write(to: target) }
            let path = (imageFolder.isEmpty ? "" : imageFolder + "/") + target.lastPathComponent
            let link = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
            insertText("![\(stem)](\(link))", replacementRange: selectedRange())
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }
}

private final class DecorationView: NSView {
    private weak var host: MarkdownTextView?

    init(host: MarkdownTextView) {
        self.host = host
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("Decorations are created in code") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        // Shift into the text view's coordinates so the host can draw as if on itself.
        NSGraphicsContext.current?.cgContext.translateBy(x: -frame.minX, y: -frame.minY)
        host?.drawOverlays(dirtyRect.offsetBy(dx: frame.minX, dy: frame.minY))
    }
}

private final class TableRowView: NSView {
    override var isFlipped: Bool { true }
    var fields: [TableCellField] = []
    private var header = false

    func update(cells: [NSRange], source: String, header: Bool,
                onEdit: @escaping (NSRange, String) -> NSRange,
                onFocus: @escaping (NSRange) -> Void,
                onTab: @escaping (NSRange, Bool) -> Void) {
        self.header = header
        while fields.count < cells.count {
            let field = TableCellField(frame: .zero)
            addSubview(field)
            fields.append(field)
        }
        while fields.count > cells.count { fields.removeLast().removeFromSuperview() }
        let width = bounds.width / CGFloat(max(cells.count, 1))
        for (index, range) in cells.enumerated() {
            let field = fields[index]
            field.frame = NSRect(x: width * CGFloat(index) + 14, y: (bounds.height - 20) / 2, width: width - 28, height: 20)
            field.sourceRange = range
            if field.currentEditor() == nil { field.stringValue = (source as NSString).substring(with: range) }
            field.font = .systemFont(ofSize: header ? 12.5 : 14, weight: header ? .semibold : .regular)
            field.textColor = header ? .secondaryLabelColor : .labelColor
            field.onEdit = onEdit
            field.onFocus = onFocus
            field.onTab = onTab
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if header {
            NSColor.labelColor.withAlphaComponent(0.04).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).fill()
        }
        NSColor.separatorColor.setStroke()
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        outline.lineWidth = 1
        outline.stroke()
        if fields.count > 1 {
            let width = bounds.width / CGFloat(fields.count)
            for index in 1..<fields.count {
                let x = width * CGFloat(index)
                NSBezierPath.strokeLine(from: NSPoint(x: x, y: 0), to: NSPoint(x: x, y: bounds.height))
            }
        }
    }
}

private final class TableCellField: NSTextField, NSTextFieldDelegate {
    var sourceRange = NSRange(location: 0, length: 0)
    var onEdit: ((NSRange, String) -> NSRange)?
    var onFocus: ((NSRange) -> Void)?
    var onTab: ((NSRange, Bool) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        delegate = self
    }
    required init?(coder: NSCoder) { fatalError("Table cells are created in code") }

    func controlTextDidChange(_ obj: Notification) {
        if let range = onEdit?(sourceRange, stringValue) { sourceRange = range }
    }
    func controlTextDidBeginEditing(_ obj: Notification) { onFocus?(sourceRange) }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertTab(_:)) { onTab?(sourceRange, false); return true }
        if selector == #selector(NSResponder.insertBacktab(_:)) { onTab?(sourceRange, true); return true }
        return false
    }
}

enum MarkdownList {
    struct Scan {
        /// Number replacements that make each ordered list count up from its start, tagged with their list.
        var fixes: [(range: NSRange, value: String, list: Int)] = []
        /// Digits of every ordered item with the number it displays, tagged with its list.
        var numbers: [(range: NSRange, value: String, list: Int)] = []
        /// Source span of each ordered list, from its first item to its last line.
        var spans: [NSRange] = []
        /// Unindented lines that continue the item above them (CommonMark lazy continuation).
        var lazyLines: [(line: NSRange, item: Int)] = []
        /// Line start of every ordered item, mapped to whether it heads its list and that list's start.
        var ordered: [Int: (head: Bool, start: Int)] = [:]
    }

    /// Reads the list structure from the parsed model. `start` picks a list's start number from its head's line location and written number.
    static func scan(_ text: String, start: @escaping (Int, Int) -> Int = { $1 }) -> Scan {
        scan(MarkdownModel(text), start: start)
    }

    static func scan(_ model: MarkdownModel, start: @escaping (Int, Int) -> Int = { $1 }) -> Scan {
        let source = model.source as NSString
        func lineStart(_ location: Int) -> Int { source.lineRange(for: NSRange(location: location, length: 0)).location }
        var result = Scan()
        for list in model.lists where list.ordered {
            guard let head = list.items.first else { continue }
            let id = result.spans.count
            let headLine = lineStart(head.marker.location)
            let first = start(headLine, list.start)
            result.spans.append(NSRange(location: headLine, length: NSMaxRange(list.range) - headLine))
            for (index, item) in list.items.enumerated() {
                guard let digits = item.digits else { continue }
                let expected = first + index
                result.ordered[lineStart(item.marker.location)] = (index == 0, first)
                result.numbers.append((digits, "\(expected)", id))
                if Int(source.substring(with: digits)) != expected { result.fixes.append((digits, "\(expected)", id)) }
            }
        }
        result.numbers.sort { $0.range.location < $1.range.location }
        result.fixes.sort { $0.range.location < $1.range.location }
        // An unindented line inside an item's range continues it lazily; nested items come later and claim their own lines.
        var lazy: [Int: (line: NSRange, item: Int)] = [:]
        for span in model.spans {
            guard case .listItem(let item) = span.kind else { continue }
            let owner = lineStart(item.marker.location)
            var line = source.lineRange(for: NSRange(location: owner, length: 0))
            while NSMaxRange(line) < NSMaxRange(span.range) {
                line = source.lineRange(for: NSRange(location: NSMaxRange(line), length: 0))
                guard line.length > 0 else { break }
                let first = source.character(at: line.location)
                if ![32, 9, 10, 13].contains(first) { lazy[line.location] = (line, owner) }
            }
        }
        result.lazyLines = lazy.values.sorted { $0.line.location < $1.line.location }
        return result
    }

    /// Fixes for the lists an edit touched, after replacing `edit` in `previous` with `length` characters.
    /// Lists elsewhere keep their written numbers; the rendered lens shows them counted instead.
    /// A list whose head was removed keeps the start it had; a head that already led its list keeps its own number.
    static func renumbering(_ text: String, previous: Scan?, edit: NSRange, length: Int) -> [(range: NSRange, value: String)] {
        renumbering(MarkdownModel(text), previous: previous, edit: edit, length: length)
    }

    static func renumbering(_ model: MarkdownModel, previous: Scan?, edit: NSRange, length: Int) -> [(range: NSRange, value: String)] {
        let result = scan(model) { location, written in
            guard let previous else { return written }
            let old: Int
            if location < edit.location { old = location }
            else if location >= edit.location + length { old = location - length + edit.length }
            else { return written }
            guard let before = previous.ordered[old], !before.head else { return written }
            return before.start
        }
        let end = edit.location + length
        return result.fixes.filter { fix in
            let span = result.spans[fix.list]
            return span.location <= end && edit.location <= NSMaxRange(span)
        }.map { ($0.range, $0.value) }
    }
}

struct MarkdownTable {
    typealias Row = MarkdownModel.Table.Row

    enum Move {
        case select(NSRange)
        case addRow(String, at: Int, caret: Int)
    }

    let rows: [Row]
    let current: Int

    static func containing(_ text: String, location: Int) -> Self? {
        containing(MarkdownModel(text), location: location)
    }

    /// The GFM table whose rows cover `location`, with the row it is on.
    static func containing(_ model: MarkdownModel, location: Int) -> Self? {
        for table in model.tables {
            if let index = table.rows.firstIndex(where: { $0.start <= location && location <= $0.end }) { return Self(rows: table.rows, current: index) }
        }
        return nil
    }

    static func blocks(in text: String) -> [Self] { blocks(in: MarkdownModel(text)) }

    static func blocks(in model: MarkdownModel) -> [Self] {
        model.tables.map { Self(rows: $0.rows, current: 0) }
    }

    func move(from location: Int, backward: Bool) -> Move? {
        let row = rows[current]
        let cell = row.cells.firstIndex(where: { location <= NSMaxRange($0) }) ?? row.cells.count - 1
        if backward {
            if !row.separator, cell > 0 { return .select(row.cells[cell - 1]) }
            guard let previous = rows[..<current].last(where: { !$0.separator }) else { return .select(row.cells[0]) }
            return .select(previous.cells.last!)
        }
        if !row.separator, cell + 1 < row.cells.count { return .select(row.cells[cell + 1]) }
        if current + 1 < rows.count, let next = rows[(current + 1)...].first(where: { !$0.separator }) {
            return .select(next.cells[0])
        }
        return .addRow("\n|" + String(repeating: "  |", count: row.cells.count), at: row.end, caret: 3)
    }
}

struct SourceAnchor {
    let selection: NSRange
    let topLine: NSRange

    init(source: String, selection: NSRange, topOffset: Int) {
        self.selection = selection
        let string = source as NSString
        topLine = string.lineRange(for: NSRange(location: min(topOffset, string.length), length: 0))
    }

    func selection(in source: String) -> NSRange {
        let count = (source as NSString).length
        let start = min(selection.location, count)
        return NSRange(location: start, length: min(selection.length, count - start))
    }
}

enum Callout {
    static func color(_ type: String, accent: NSColor) -> NSColor {
        switch type.uppercased() {
        case "TIP": .systemGreen
        case "WARNING": .systemOrange
        case "IMPORTANT": .systemPurple
        default: accent
        }
    }
}

/// YAML frontmatter at the top of a document, read for the rendered chip row.
struct Frontmatter {
    /// The whole block, fences included, plus its trailing newline.
    let range: NSRange
    /// The YAML between the fences.
    let body: NSRange
    let title: String?
    let tags: [String]
    let date: String?

    var displayDate: String? {
        guard let date else { return nil }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let parsed = parser.date(from: String(date.prefix(10))) else { return date.isEmpty ? nil : date }
        return parsed.formatted(date: .abbreviated, time: .omitted)
    }

    static func parse(_ source: String) -> Self? {
        let ns = source as NSString
        guard source.hasPrefix("---\n"), let regex = try? NSRegularExpression(pattern: #"(?m)^---[ \t]*$"#) else { return nil }
        let fences = regex.matches(in: source, range: NSRange(location: 4, length: ns.length - 4))
        guard let close = fences.first?.range else { return nil }
        var end = NSMaxRange(close)
        if end < ns.length, ns.character(at: end) == 10 { end += 1 }
        let body = NSRange(location: 4, length: max(0, close.location - 4))
        let yaml = ns.substring(with: body)
        var tags: [String] = []
        var title: String?
        var date: String?
        var inTagList = false
        for line in yaml.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if inTagList, trimmed.hasPrefix("- ") {
                tags.append(clean(String(trimmed.dropFirst(2))))
                continue
            }
            inTagList = false
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = trimmed[..<colon].lowercased()
            let value = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if key == "tags" {
                if value.isEmpty { inTagList = true }
                else { tags = value.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).split(separator: ",").map { clean(String($0)) } }
            } else if key == "date" {
                date = clean(value)
            } else if key == "title" {
                title = clean(value)
            }
        }
        return Self(range: NSRange(location: 0, length: end), body: body, title: title.flatMap { $0.isEmpty ? nil : $0 },
                    tags: tags.filter { !$0.isEmpty }, date: date)
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }
}
