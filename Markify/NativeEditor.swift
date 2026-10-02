import AppKit
import MarkifyMarkdown
import OKFKit
import SwaTex
import SwaTexRender
import SwiftUI
import UniformTypeIdentifiers

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
    @AppStorage("loadRemoteImages") private var loadRemoteImages = true
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
    var baseDirectory: URL? = nil
    var onWritingToolsBegin: () -> Void = {}
    var onWritingToolsEnd: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        MarkdownTextView.openEditors.add(editor)
        editor.documentURL = fileURL
        editor.baseDirectory = baseDirectory
        editor.bundleRoot = bundleRoot
        editor.linkTargets = linkTargets
        editor.columnWidth = columnWidth
        editor.rendered = !markdownLens
        editor.theme = theme
        editor.loadRemoteImages = loadRemoteImages
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
        editor.restyle = { [weak coordinator = context.coordinator, weak editor] in
            guard let coordinator, let editor else { return }
            coordinator.parent.style(editor)
        }
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
        (editor as? MarkdownTextView)?.baseDirectory = baseDirectory
        (editor as? MarkdownTextView)?.bundleRoot = bundleRoot
        (editor as? MarkdownTextView)?.linkTargets = linkTargets
        (editor as? MarkdownTextView)?.columnWidth = columnWidth
        (editor as? MarkdownTextView)?.rendered = !markdownLens
        (editor as? MarkdownTextView)?.theme = theme
        context.coordinator.parent = self
        (editor as? MarkdownTextView)?.loadRemoteImages = loadRemoteImages
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

    /// Styles both lenses from the model. `incremental` (typing) styles a copy and applies only the attributes that
    /// changed: resetting the whole storage makes TextKit 2 discard the layout of every line, and the lines above the
    /// page fall back to estimated heights, so the visible text blanks and jumps on each keystroke.
    func style(_ editor: NSTextView, incremental: Bool = false) {
        guard let live = editor.textStorage else { return }
        let storage = incremental ? NSTextStorage(attributedString: live) : live
        // HTML blocks are imported through WebKit, which spins the run loop: an image or diagram arriving then
        // asks for a restyle in the middle of this pass. It runs once this pass is done instead of inside it.
        let styling = editor as? MarkdownTextView
        if let styling, styling.isStyling { styling.restyleAfterStyling = true; return }
        styling?.isStyling = true
        defer {
            styling?.isStyling = false
            if styling?.restyleAfterStyling == true {
                styling?.restyleAfterStyling = false
                DispatchQueue.main.async { [weak styling] in styling?.restyle?() }
            }
        }
        let source = editor.string as NSString
        let whole = NSRange(location: 0, length: source.length)
        let primary = NSColor.labelColor
        let dim = NSColor.tertiaryLabelColor
        let accent = theme.accent
        let base = markdownLens ? theme.mono(14) : theme.prose(18)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = (markdownLens ? 10 : 11) * theme.scale
        editor.typingAttributes = [.font: base, .foregroundColor: primary, .paragraphStyle: paragraph]
        guard whole.length > 0 else {
            updateTypingFont(editor)
            return
        }
        storage.beginEditing()
        storage.setAttributes([.font: base, .foregroundColor: primary, .paragraphStyle: paragraph], range: whole)

        func matches(_ pattern: String, _ apply: (NSTextCheckingResult) -> Void) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return }
            regex.enumerateMatches(in: editor.string, range: whole) { match, _, _ in if let match { apply(match) } }
        }
        /// Even at 1pt hidden text keeps a sliver of advance. TextKit caps a negative kern near its own glyph's advance,
        /// so each character cancels its own width and text after a hidden marker starts where it should.
        func collapse(_ range: NSRange) {
            var index = range.location
            while index < NSMaxRange(range) {
                let character = source.rangeOfComposedCharacterSequence(at: index)
                storage.addAttribute(.kern, value: -MarkdownTextView.hiddenAdvance(source.substring(with: character)), range: character)
                index = NSMaxRange(character)
            }
        }
        func marker(_ range: NSRange) {
            guard range.location != NSNotFound, range.length > 0 else { return }
            storage.addAttributes([.foregroundColor: markdownLens ? dim : NSColor.clear,
                                   .font: markdownLens ? theme.mono(14) : NSFont.systemFont(ofSize: 1)], range: range)
            if !markdownLens { collapse(range) }
        }
        let model = (editor as? MarkdownTextView)?.model ?? MarkdownModel(editor.string, mdx: MarkdownTextView.isMDX(fileURL))
        let secondary = NSColor.secondaryLabelColor
        var hidden: [NSRange] = []
        /// Link and image destinations in the Markdown lens, colored after their dimmed markers.
        var destinations: [NSRange] = []
        var chips: [MarkdownModel.Span] = []
        /// Inline math typeset in the Rendered lens: the span, the font around it and the formula's width.
        var formulas: [(span: MarkdownModel.Span, font: NSFont, width: CGFloat)] = []
        /// Mermaid blocks shown as diagrams in the Rendered lens, with the height their image needs.
        var diagrams: [(span: MarkdownModel.Span, height: CGFloat)] = []
        /// Mermaid blocks that failed to render: shown as code with room below for mermaid's message.
        var failedDiagrams: [MarkdownModel.Span] = []
        /// Code blocks and callouts in the Rendered lens: the lines they cover and the rounded box drawn behind them.
        var boxes: [(range: NSRange, fill: MarkdownBlockFill)] = []
        let textView = editor as? MarkdownTextView
        textView?.inlineFormulas = [:]
        textView?.htmlBlocks = [:]
        textView?.inlineHTMLImages = [:]
        textView?.styledEditedFormula = textView?.editedFormula
        let dark = editor.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
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

        // A table of contents Markify keeps is drawn as a Contents card in the Rendered lens; its parts are styled below.
        let tableOfContents = markdownLens ? nil : TableOfContentsBlock.find(in: model)
        func inTableOfContents(_ location: Int, body: Bool = false) -> Bool {
            tableOfContents.map { NSLocationInRange(location, body ? $0.body : $0.range) } ?? false
        }

        // Blocks: fonts and fills that inline styles then build on.
        for span in model.spans {
            switch span.kind {
            case .htmlBlock where inTableOfContents(span.range.location),
                 .listItem where inTableOfContents(span.range.location, body: true):
                continue
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
                storage.addAttribute(.font, value: theme.ui(15), range: span.range)
                boxes.append((span.range, MarkdownBlockFill(color: NSColor.calloutFill(color), radius: 14 * theme.scale, padding: NSSize(width: 18, height: 14))))
                // The type token is hidden; MarkdownTextView draws its title ("Note") in its place.
                storage.addAttributes([.foregroundColor: NSColor.clear, .font: theme.ui(13, weight: .semibold)], range: token)
            case .listItem(let item):
                let spaced = NSMaxRange(item.checkbox ?? item.marker) < source.length && [32, 9].contains(source.character(at: NSMaxRange(item.checkbox ?? item.marker)))
                let prefix = NSRange(location: item.marker.location, length: NSMaxRange(item.checkbox ?? item.marker) - item.marker.location + (spaced ? 1 : 0))
                if markdownLens {
                    hide([prefix])
                } else if let box = item.checkbox {
                    // MarkdownLayoutFragment draws the checkbox over the hidden `- [ ] `; the item's first line takes the task style.
                    storage.addAttributes([.foregroundColor: NSColor.clear, .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)], range: prefix)
                    storage.addAttributes([.markifyTaskBox: item.checked, .markifyTaskAccent: theme.accent], range: NSRange(location: item.marker.location, length: 1))
                    let line = source.lineRange(for: NSRange(location: box.location, length: 0))
                    var end = NSMaxRange(line)
                    while end > NSMaxRange(prefix), [10, 13].contains(source.character(at: end - 1)) { end -= 1 }
                    let text = NSRange(location: NSMaxRange(prefix), length: max(0, end - NSMaxRange(prefix)))
                    storage.addAttribute(.font, value: theme.ui(17), range: text)
                    if item.checked { storage.addAttributes([.foregroundColor: dim, .strikethroughStyle: NSUnderlineStyle.single.rawValue], range: text) }
                } else if item.ordered {
                    storage.addAttribute(.foregroundColor, value: secondary, range: item.marker)
                } else {
                    // MarkdownLayoutFragment draws a bullet over the hidden marker, which keeps its width.
                    storage.addAttributes([.foregroundColor: NSColor.clear, .font: theme.mono(18)], range: prefix)
                    storage.addAttribute(.markifyBullet, value: theme.ui(18), range: item.marker)
                }
            case .codeBlock(let language?, true) where !markdownLens && textView != nil && language.lowercased() == "mermaid":
                if let height = diagramHeight(span, source: source, dark: dark, textView: textView) {
                    diagrams.append((span, height))
                    continue
                }
                failedDiagrams.append(span)
                fallthrough
            case .codeBlock:
                if markdownLens {
                    storage.addAttributes([.font: theme.mono(14), .backgroundColor: NSColor.codeFill], range: span.content)
                } else {
                    storage.addAttribute(.font, value: theme.mono(13.5), range: span.content)
                    if span.content.length > 0 { boxes.append((span.content, MarkdownBlockFill(color: .codeFill, radius: 12 * theme.scale, padding: NSSize(width: 18, height: 16)))) }
                }
                hide(span.markers)
                let code = source.substring(with: span.content)
                for (token, kind) in CodeToken.tokens(in: code) {
                    guard let color = theme.code(kind) else { continue }
                    storage.addAttribute(.foregroundColor, value: color, range: NSRange(location: span.content.location + token.location, length: token.length))
                }
            case .htmlBlock where !markdownLens && textView != nil:
                if let rendered = textView?.renderHTML(source.substring(with: span.range), width: columnWidth) {
                    textView?.htmlBlocks[span.range.location] = rendered
                    storage.addAttributes([.font: NSFont.systemFont(ofSize: 1), .foregroundColor: NSColor.clear], range: span.range)
                    let collapsed = NSMutableParagraphStyle()
                    collapsed.minimumLineHeight = 0.01
                    collapsed.maximumLineHeight = 0.01
                    storage.addAttribute(.paragraphStyle, value: collapsed, range: span.range)
                    let first = NSMutableParagraphStyle()
                    first.minimumLineHeight = rendered.height
                    first.maximumLineHeight = rendered.height
                    first.paragraphSpacing = 12 * theme.scale
                    storage.addAttribute(.paragraphStyle, value: first, range: source.lineRange(for: NSRange(location: span.range.location, length: 0)))
                } else {
                    storage.addAttribute(.foregroundColor, value: dim, range: span.range)
                }
            case .htmlBlock, .mdxBlock:
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
                let font = storage.attribute(.font, at: span.content.location, effectiveRange: nil) as? NSFont ?? theme.prose(18)
                // Typeset unless the caret is in it: then the LaTeX shows, to be edited in place.
                if !markdownLens, let textView, !textView.isEditing(span),
                   let formula = InlineFormula(latex: source.substring(with: span.content), size: font.pointSize, dark: dark) {
                    textView.inlineFormulas[span.range.location] = formula
                    formulas.append((span, font, formula.width))
                    hide([span.range])
                } else if !markdownLens, let textView, textView.isEditing(span) {
                    // Being edited: the LaTeX and its dimmed dollars, so it's clear where the formula ends.
                    storage.addAttribute(.font, value: theme.prose(18, italic: true), range: span.content)
                    storage.addAttribute(.foregroundColor, value: dim, range: span.range)
                    storage.addAttribute(.foregroundColor, value: primary, range: span.content)
                } else {
                    if !markdownLens { storage.addAttribute(.font, value: theme.prose(18, italic: true), range: span.content) }
                    hide(span.markers)
                }
            case .escape:
                hide(span.markers)
            case .inlineHTML where !markdownLens:
                if source.substring(with: span.range).lowercased().hasPrefix("<img"),
                   let path = MarkdownTextView.htmlAttribute("src", in: source.substring(with: span.range)) {
                    let width = CGFloat(Double(MarkdownTextView.htmlAttribute("width", in: source.substring(with: span.range)) ?? "") ?? 24)
                    let font = storage.attribute(.font, at: span.range.location, effectiveRange: nil) as? NSFont ?? base
                    textView?.inlineHTMLImages[span.range.location] = (path, width * theme.scale, font)
                }
                hide([span.range])
            case .image(_, false) where !markdownLens:
                // Drawn as a chip by MarkdownTextView; the alt text keeps its width but not its ink.
                storage.addAttributes([.font: theme.ui(11.5, weight: .medium), .foregroundColor: NSColor.clear], range: span.content)
                chips.append(span)
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
                // TextKit ignores paragraphSpacingBefore on the document's first paragraph.
                if span.range.location == 0 {
                    style.minimumLineHeight = 290
                    style.maximumLineHeight = 290
                } else {
                    style.paragraphSpacingBefore = 270
                }
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
        if let textView {
            for (location, image) in textView.inlineHTMLImages {
                let first = source.rangeOfComposedCharacterSequence(at: location)
                let advance = (source.substring(with: first) as NSString).size(withAttributes: [.font: image.font]).width
                storage.addAttributes([.font: image.font, .foregroundColor: NSColor.clear, .kern: image.width - advance], range: first)
            }
        }
        // An inline image reads as a chip: its hidden `![` leaves room for the photo symbol, its hidden destination for the end padding.
        // A kern on the first character of a run is applied in full, so the room goes there.
        for span in chips {
            let opening = NSRange(location: span.range.location, length: span.content.location - span.range.location)
            let closing = NSRange(location: NSMaxRange(span.content), length: NSMaxRange(span.range) - NSMaxRange(span.content))
            for (range, room) in [(opening, MarkdownTextView.chipLead), (closing, MarkdownTextView.chipTrail)] where range.length > 0 {
                storage.addAttributes([.foregroundColor: NSColor.clear, .font: NSFont.systemFont(ofSize: 1)], range: range)
                collapse(range)
                let first = source.rangeOfComposedCharacterSequence(at: range.location)
                let kern = storage.attribute(.kern, at: first.location, effectiveRange: nil) as? CGFloat ?? 0
                storage.addAttribute(.kern, value: kern + room * theme.scale, range: first)
            }
        }
        // A typeset formula's hidden source leaves room for it on its opening `$`, which keeps the text's font so a line
        // holding only a formula keeps its height and baseline.
        for formula in formulas {
            let first = source.rangeOfComposedCharacterSequence(at: formula.span.range.location)
            let advance = (source.substring(with: first) as NSString).size(withAttributes: [.font: formula.font]).width
            storage.addAttributes([.font: formula.font, .foregroundColor: NSColor.clear, .kern: formula.width - advance], range: first)
        }
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
            // The file keeps its written numbers; MarkdownLayoutFragment draws each item's counted number over them.
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
                storage.addAttributes([.markifyListNumber: number.value + source.substring(with: NSRange(location: NSMaxRange(number.range), length: 1)),
                                       .markifyListNumberOffset: CGFloat((widest[number.list] ?? 1) - number.value.count) * digit], range: number.range)
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
            if let toc = tableOfContents {
                let scale = theme.scale
                // The opening comment's line holds the card's title, which the line's fragment draws in its place.
                storage.addAttributes([.foregroundColor: NSColor.clear, .font: theme.ui(11, weight: .semibold)], range: toc.opening)
                storage.addAttribute(.markifyTitle, value: NSAttributedString(string: "CONTENTS", attributes: [
                    .font: theme.ui(11, weight: .semibold), .kern: 0.7 * scale, .foregroundColor: NSColor.secondaryLabelColor]),
                                     range: NSRange(location: toc.opening.location, length: 1))
                let title = NSMutableParagraphStyle()
                title.paragraphSpacing = 6 * scale
                storage.addAttribute(.paragraphStyle, value: title, range: source.lineRange(for: NSRange(location: toc.opening.location, length: 0)))
                // The closing comment takes no room.
                let collapsed = NSMutableParagraphStyle()
                collapsed.minimumLineHeight = 0.01
                collapsed.maximumLineHeight = 0.01
                storage.addAttributes([.font: NSFont.systemFont(ofSize: 1), .foregroundColor: NSColor.clear, .paragraphStyle: collapsed],
                                      range: source.lineRange(for: NSRange(location: toc.closing.location, length: 0)))
                // Entries: no bullets, indented by level with a hairline per enclosing level; the top level semibold in ink.
                let step = 16 * scale
                let origin = (editor.textContainer?.lineFragmentPadding ?? 0) + 18 * scale
                func level(_ line: NSRange) -> Int {
                    var spaces = 0
                    while spaces < line.length, source.character(at: line.location + spaces) == 32 { spaces += 1 }
                    return min(spaces / 2, 5)
                }
                for span in model.spans {
                    guard case .listItem(let item) = span.kind, NSLocationInRange(item.marker.location, toc.body) else { continue }
                    let line = source.lineRange(for: NSRange(location: item.marker.location, length: 0))
                    var end = NSMaxRange(item.marker)
                    if end < source.length, [32, 9].contains(source.character(at: end)) { end += 1 }
                    marker(NSRange(location: line.location, length: end - line.location))
                    let depth = level(line)
                    let style = NSMutableParagraphStyle()
                    style.firstLineHeadIndent = CGFloat(depth) * step
                    style.headIndent = style.firstLineHeadIndent
                    style.paragraphSpacing = 3 * scale
                    storage.addAttribute(.paragraphStyle, value: style, range: line)
                    if depth > 0 { storage.addAttribute(.markifyGuides, value: MarkdownGuides(count: depth, origin: origin, step: step, color: .separatorColor), range: line) }
                }
                for span in model.spans where NSLocationInRange(span.range.location, toc.body) {
                    guard case .link = span.kind else { continue }
                    let top = level(source.lineRange(for: span.range)) == 0
                    storage.addAttributes([.font: top ? theme.ui(15, weight: .semibold) : theme.ui(14), .foregroundColor: top ? primary : secondary], range: span.content)
                }
                boxes.append((toc.range, MarkdownBlockFill(color: .codeFill, radius: 14 * scale, padding: NSSize(width: 18, height: 14))))
            }
            // A box's lines share one rounded fill with padding around the text, as the design's code blocks and callouts.
            for box in boxes {
                let lines = source.lineRange(for: box.range)
                var line = source.lineRange(for: NSRange(location: lines.location, length: 0))
                while line.length > 0 {
                    let first = line.location == lines.location
                    let last = NSMaxRange(line) >= NSMaxRange(lines)
                    let style = (storage.attribute(.paragraphStyle, at: line.location, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                    style.headIndent += box.fill.padding.width * theme.scale
                    style.firstLineHeadIndent += box.fill.padding.width * theme.scale
                    style.tailIndent = -box.fill.padding.width * theme.scale
                    if first { style.paragraphSpacingBefore = box.fill.padding.height * theme.scale }
                    if last { style.paragraphSpacing = box.fill.padding.height * theme.scale }
                    storage.addAttributes([.paragraphStyle: style, .markifyBlockFill: box.fill.edge(first: first, last: last)], range: line)
                    guard !last, NSMaxRange(line) < source.length else { break }
                    line = source.lineRange(for: NSRange(location: NSMaxRange(line), length: 0))
                }
            }
            // A diagram's source collapses to one line as tall as the drawn diagram.
            for diagram in diagrams {
                let collapsed = NSMutableParagraphStyle()
                collapsed.minimumLineHeight = 0.01
                collapsed.maximumLineHeight = 0.01
                storage.addAttributes([.font: NSFont.systemFont(ofSize: 1), .foregroundColor: NSColor.clear, .paragraphStyle: collapsed], range: diagram.span.range)
                let first = NSMutableParagraphStyle()
                first.minimumLineHeight = diagram.height
                first.maximumLineHeight = diagram.height
                first.paragraphSpacing = 16 * theme.scale
                storage.addAttribute(.paragraphStyle, value: first, range: source.lineRange(for: NSRange(location: diagram.span.range.location, length: 0)))
            }
            for span in failedDiagrams {
                let last = source.lineRange(for: NSRange(location: max(span.range.location, NSMaxRange(span.range) - 1), length: 0))
                let style = (storage.attribute(.paragraphStyle, at: last.location, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                style.paragraphSpacing = MarkdownTextView.diagramErrorHeight * theme.scale
                storage.addAttribute(.paragraphStyle, value: style, range: last)
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
        if storage !== live { Self.applyChangedAttributes(from: storage, to: live) }
        updateTypingFont(editor)
        if let editor = editor as? MarkdownTextView {
            editor.forgetImages()
            DispatchQueue.main.async { [weak editor] in editor?.refreshTables() }
        }
    }

    /// Copies `styled`'s attributes onto `live` only where they differ, so TextKit keeps the layout of unchanged text.
    static func applyChangedAttributes(from styled: NSAttributedString, to live: NSTextStorage) {
        let length = min(styled.length, live.length)
        var location = 0
        live.beginEditing()
        while location < length {
            var new = NSRange(), old = NSRange()
            let attributes = styled.attributes(at: location, effectiveRange: &new)
            let current = live.attributes(at: location, effectiveRange: &old)
            let end = min(NSMaxRange(new), NSMaxRange(old), length)
            if !(attributes as NSDictionary).isEqual(to: current) {
                live.setAttributes(attributes, range: NSRange(location: location, length: end - location))
            }
            location = end
        }
        live.endEditing()
    }

    /// Plain-text NSTextView sizes its caret from the typing font, which must follow our styled text.
    func updateTypingFont(_ editor: NSTextView) {
        let base = markdownLens ? theme.mono(14) : theme.prose(18)
        // The empty-document overlay shows a title in both lenses.
        var font = editor.string.isEmpty ? theme.prose(36, bold: true) : base
        if let storage = editor.textStorage, storage.length > 0 {
            let source = editor.string as NSString
            let location = min(editor.selectedRange().location, source.length)
            let line = source.lineRange(for: NSRange(location: location, length: 0))
            let anchor = max(line.location, location - 1)
            var nearest = Int.max
            storage.enumerateAttributes(in: line) { attributes, range, _ in
                guard let candidate = attributes[.font] as? NSFont,
                      (attributes[.foregroundColor] as? NSColor)?.alphaComponent != 0,
                      !source.substring(with: range).trimmingCharacters(in: .newlines).isEmpty else { return }
                let distance = max(range.location - anchor, anchor - (NSMaxRange(range) - 1), 0)
                if distance < nearest { nearest = distance; font = candidate }
            }
        }
        editor.typingAttributes[.font] = font
    }

    /// The height a Mermaid block takes as a diagram, or nil when it failed and shows as code with the error below.
    func diagramHeight(_ span: MarkdownModel.Span, source: NSString, dark: Bool, textView: MarkdownTextView?) -> CGFloat? {
        let diagram = source.substring(with: span.content)
        let state = MermaidRenderer.shared.state(of: diagram, dark: dark) { [weak textView] in textView?.restyle?() }
        switch state {
        case .rendering: return MarkdownTextView.diagramPadding * 2 + 88
        case .rendered(let image): return MarkdownTextView.fitted(image.size, width: columnWidth).height + MarkdownTextView.diagramPadding * 2
        case .failed: return nil
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
        private var writingToolsOriginalBody: String?
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
            if writingToolsOriginalBody == nil, (editor as? MarkdownTextView)?.isRenumbering != true { parent.onType() }
            let slash = SlashContext.detect(in: editor.string, selection: editor.selectedRange())
            if slash?.range.location != dismissedSlashLocation { dismissedSlashLocation = nil }
            parent.onSlash(dismissedSlashLocation == nil ? slash?.query : nil)
            parent.style(editor, incremental: true)
        }
        func textViewWritingToolsWillBegin(_ textView: NSTextView) {
            writingToolsOriginalBody = FrontmatterBlock.body(of: textView.string)
            parent.onWritingToolsBegin()
        }
        func textViewWritingToolsDidEnd(_ textView: NSTextView) {
            guard let original = writingToolsOriginalBody else { return }
            writingToolsOriginalBody = nil
            parent.onWritingToolsEnd(FrontmatterBlock.body(of: textView.string) != original)
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
            // Moving into a typeset formula shows its LaTeX; moving out typesets it again.
            if let markdown = editor as? MarkdownTextView, markdown.rendered, markdown.editedFormula != markdown.styledEditedFormula {
                parent.style(editor, incremental: true)
            }
            parent.updateTypingFont(editor)
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
    static let openEditors = NSHashTable<MarkdownTextView>.weakObjects()
    /// Held strongly: the layout manager keeps its delegate weakly.
    private let layoutDelegate = MarkdownLayoutDelegate()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        observeEdits()
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        observeEdits()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        observeEdits()
    }

    var documentURL: URL?
    var baseDirectory: URL?
    var bundleRoot: URL?
    var linkTargets: [String] = []
    private var isCompletingLink = false
    var columnWidth: CGFloat = 640
    var rendered = true
    /// A theme change restyles the text, which redraws its fragments; renders made with the old one are dropped.
    var theme = EditorTheme() { didSet { if theme != oldValue { mathCache = [:] } } }
    var loadRemoteImages = true {
        didSet { if loadRemoteImages != oldValue { remoteImageLoaded() } }
    }
    var onSlashKey: ((SlashKey, SlashContext) -> Bool)?
    /// Restyles the text, for results that arrive later, such as a rendered diagram.
    var restyle: (() -> Void)?
    /// True during a style pass; a restyle asked for meanwhile sets `restyleAfterStyling` and runs after it.
    var isStyling = false
    var restyleAfterStyling = false
    /// Local images by URL; `nil` for a file that could not be read.
    private var imageCache: [URL: NSImage?] = [:]

    /// Forgets local images, so files added or changed since show on the next paint.
    func forgetImages() { imageCache.removeAll() }
    private var mathCache: [String: NSImage] = [:]
    private(set) var tableOverlays: [Int: TableRowView] = [:]
    private var modelCache: (version: Int, model: MarkdownModel)?
    /// Bumped whenever the characters change (not their attributes), so caches check validity without comparing the text.
    private(set) var textVersion = 0
    private var editingObserver: NSObjectProtocol?

    private func observeEdits() {
        textLayoutManager?.delegate = layoutDelegate
        // Any storage: TextKit 2 may give the view a different storage than the one it has during init.
        editingObserver = NotificationCenter.default.addObserver(forName: NSTextStorage.didProcessEditingNotification, object: nil, queue: nil) { [weak self] notification in
            guard let storage = notification.object as? NSTextStorage, storage.editedMask.contains(.editedCharacters) else { return }
            let edited = ObjectIdentifier(storage)
            MainActor.assumeIsolated {
                guard let self, let current = self.textStorage, ObjectIdentifier(current) == edited else { return }
                self.textVersion += 1
                self.scheduleTableOfContentsUpdate()
            }
        }
    }

    /// The parsed source, shared by styling, drawing and clicks until the text changes.
    var model: MarkdownModel {
        let mdx = Self.isMDX(documentURL)
        if let modelCache, modelCache.version == textVersion, modelCache.model.mdx == mdx { return modelCache.model }
        let model = MarkdownModel(string, mdx: mdx)
        modelCache = (textVersion, model)
        return model
    }

    func refreshTables() {
        guard window != nil else { return }
        let rows: [(MarkdownTable.Row, Bool)] = rendered ? MarkdownTable.blocks(in: model).flatMap { table in
            table.rows.enumerated().compactMap { index, row in row.separator ? nil : (row, index == 0) }
        } : []
        if let last = rows.last { settleLayout(through: last.0.end) }
        for (index, (row, header)) in rows.enumerated() {
            let line = textRect(NSRange(location: row.start, length: 1))
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
        closeImagePreview()
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

    /// Where table commands act: the cell being edited in the Rendered lens, or the caret.
    var tableLocation: Int {
        tableOverlays.values.flatMap(\.fields).first { $0.currentEditor() != nil }?.sourceRange.location ?? selectedRange().location
    }

    func tableChange(_ edit: MarkdownTable.Edit, at location: Int) -> MarkdownTable.Change? {
        MarkdownTable.containing(model, location: location)?.change(edit, in: string, at: location)
    }

    /// Applies a row or column edit as one undoable change and moves to the cell it leaves the caret in.
    @discardableResult
    func editTable(_ edit: MarkdownTable.Edit, at location: Int? = nil) -> Bool {
        let location = location ?? tableLocation
        guard let table = MarkdownTable.containing(model, location: location), let change = table.change(edit, in: string, at: location),
              let storage = textStorage else { return false }
        // The table stays where it is on screen. Restyling after the edit re-estimates the layout above it, and taking focus
        // back from a cell, selecting the new cell and refocusing it scroll, often to the top of the document (as ticking
        // a task did, issue #8), so the page is anchored on the table's first line rather than on a scroll offset.
        let start = table.rows[0].start
        let clip = enclosingScrollView?.contentView
        let offset = clip.map { textRect(NSRange(location: start, length: 1)).minY - $0.bounds.minY }
        func keepPage() {
            guard let clip, let offset else { return }
            clip.scroll(to: NSPoint(x: clip.bounds.minX, y: max(0, textRect(NSRange(location: start, length: 1)).minY - offset)))
            enclosingScrollView?.reflectScrolledClipView(clip)
        }
        // A cell field would keep showing its old text over what is now another cell.
        if window?.firstResponder !== self { window?.makeFirstResponder(self) }
        breakUndoCoalescing()
        guard shouldChangeText(in: change.range, replacementString: change.replacement) else { return false }
        storage.replaceCharacters(in: change.range, with: change.replacement)
        didChangeText()
        undoManager?.setActionName(edit.title)
        if let rows = model.tables.first(where: { $0.rows.first?.start == start })?.rows,
           rows.indices.contains(change.row), rows[change.row].cells.indices.contains(change.column) {
            setSelectedRange(rows[change.row].cells[change.column])
        }
        keepPage()
        // Scroll only when the cell the caret moved to is out of sight, such as a row added below the fold.
        func revealCell() {
            guard window != nil else { return }
            let cell = textRect(selectedRange())
            if !visibleRect.contains(cell) { scrollToVisible(cell.insetBy(dx: 0, dy: -12)) }
        }
        revealCell()
        if rendered {
            DispatchQueue.main.async { [weak self] in
                self?.refreshTables()
                self?.focusTableCell()
                keepPage()
                revealCell()
            }
        }
        return true
    }

    private struct TableCommand {
        let edit: MarkdownTable.Edit
        let location: Int
    }

    /// Row and column commands for the table at `location`, or none outside a table.
    func tableMenuItems(at location: Int) -> [NSMenuItem] {
        guard MarkdownTable.containing(model, location: location) != nil else { return [] }
        let groups: [[MarkdownTable.Edit]] = [[.insertRowAbove, .insertRowBelow], [.insertColumnLeft, .insertColumnRight], [.deleteRow, .deleteColumn]]
        return groups.enumerated().flatMap { index, edits in
            (index > 0 ? [NSMenuItem.separator()] : []) + edits.map { edit in
                let item = NSMenuItem(title: edit.title, action: #selector(tableMenuAction(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = TableCommand(edit: edit, location: location)
                return item
            }
        }
    }

    @objc private func tableMenuAction(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? TableCommand else { return }
        editTable(command.edit, at: command.location)
    }

    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(tableMenuAction(_:)) {
            guard let command = item.representedObject as? TableCommand else { return false }
            return tableChange(command.edit, at: command.location) != nil
        }
        return super.validateMenuItem(item)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event)
        let location = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
        let items = tableMenuItems(at: location)
        guard let menu, !items.isEmpty else { return menu }
        for (index, item) in (items + [.separator()]).enumerated() { menu.insertItem(item, at: index) }
        return menu
    }

    /// Task items in the Rendered lens, at any depth.
    private func tasks(in spans: [MarkdownModel.Span]? = nil) -> [MarkdownModel.ListItem] {
        guard rendered else { return [] }
        return (spans ?? model.spans).compactMap { span in
            if case .listItem(let item) = span.kind, item.checkbox != nil { item } else { nil }
        }
    }

    private func checkboxRect(for item: MarkdownModel.ListItem) -> NSRect? {
        guard window != nil else { return nil }
        return MarkdownLayoutFragment.checkboxRect(marker: textRect(NSRange(location: item.marker.location, length: 1)))
    }

    private var clipObservers: [NSObjectProtocol] = []

    /// Overlays placed while outside the visible area are not painted when it grows to include them.
    private func visibleAreaChanged() {
        for overlay in tableOverlays.values where overlay.frame.intersects(visibleRect) { overlay.needsDisplay = true }
    }

    /// Table overlays need a window to place themselves; the first style pass can run before the view has one.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in self?.refreshTables() }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        clipObservers.forEach(NotificationCenter.default.removeObserver)
        clipObservers = []
        guard let clip = superview as? NSClipView else { return }
        clip.postsBoundsChangedNotifications = true
        clip.postsFrameChangedNotifications = true
        // Scrolling moves the visible area; resizing the window grows it without a bounds change.
        clipObservers = [NSView.boundsDidChangeNotification, NSView.frameDidChangeNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: clip, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.visibleAreaChanged() }
            }
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let reflows = newSize.width != frame.width
        super.setFrameSize(newSize)
        // A new width rewraps the text above a table, moving its rows.
        if reflows, !tableOverlays.isEmpty { DispatchQueue.main.async { [weak self] in self?.refreshTables() } }
    }

    /// Selects `range` and scrolls its first line near the top of the page, even when it is already on screen,
    /// so a jump from the Contents or Links pane always lands in the same place.
    func reveal(_ range: NSRange) {
        setSelectedRange(range)
        window?.makeFirstResponder(self)
        guard let scroll = enclosingScrollView else { return scrollRangeToVisible(range) }
        let clip = scroll.contentView
        let top = convert(textRect(range), to: clip).minY - 24
        var bounds = clip.bounds
        bounds.origin.y = max(0, top)
        clip.scroll(to: clip.constrainBoundsRect(bounds).origin)
        scroll.reflectScrolledClipView(clip)
    }

    /// Moves to the heading whose anchor (as export writes it) is `anchor`. Returns false when there is none.
    @discardableResult
    func revealAnchor(_ anchor: String) -> Bool {
        guard let heading = DocumentHeading.extract(from: model).first(where: { $0.anchor == anchor }) else { return false }
        reveal(NSRange(location: heading.range.location, length: 0))
        return true
    }

    /// The `#anchor` of the Contents card entry under `point`, in the Rendered lens.
    func tableOfContentsLink(at point: NSPoint) -> String? {
        guard rendered, let toc = TableOfContentsBlock.find(in: model) else { return nil }
        let index = characterIndexForInsertion(at: point)
        guard NSLocationInRange(index, toc.body) else { return nil }
        let link = model.spans.first { span in
            guard case .link = span.kind, NSLocationInRange(index, span.range) || index == NSMaxRange(span.range) else { return false }
            return textRect(span.content).insetBy(dx: -4, dy: -3).contains(point)
        }
        guard let link, case let .link(destination) = link.kind, destination.hasPrefix("#") else { return nil }
        return destination
    }

    private var tableOfContentsUpdate: Task<Void, Never>?

    /// Keeps a `<!-- toc -->` block in step with the headings, a moment after typing pauses. The document is scanned
    /// off the main thread; the new list is applied only if the text hasn't changed since. Undo and redo don't
    /// trigger it, so undoing an update sticks until the next edit.
    private func scheduleTableOfContentsUpdate() {
        guard undoManager?.isUndoing != true, undoManager?.isRedoing != true else { return }
        tableOfContentsUpdate?.cancel()
        let version = textVersion
        let source = string
        let mdx = Self.isMDX(documentURL)
        tableOfContentsUpdate = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            let change = await Task.detached(priority: .utility) { () -> (range: NSRange, text: String)? in
                guard (source as NSString).range(of: "toc", options: .caseInsensitive).location != NSNotFound else { return nil }
                let model = MarkdownModel(source, mdx: mdx)
                guard let toc = TableOfContentsBlock.find(in: model) else { return nil }
                let text = TableOfContentsBlock.text(DocumentHeading.extract(from: model), depth: toc.depth)
                return (source as NSString).substring(with: toc.range) == text ? nil : (toc.range, text)
            }.value
            guard let self, !Task.isCancelled, self.textVersion == version, let change else { return }
            self.replaceTableOfContents(change.range, with: change.text, automatic: true)
        }
    }

    /// Rewrites the table of contents for the current headings, as one undo step. Skips the automatic update while the
    /// caret is inside the block; `depth` (from the pane) also changes how deep it goes. Returns false when there is
    /// no table of contents or nothing changed.
    @discardableResult
    func updateTableOfContents(depth: Int? = nil) -> Bool {
        guard (string as NSString).range(of: "toc", options: .caseInsensitive).location != NSNotFound else { return false }
        let model = self.model
        guard let toc = TableOfContentsBlock.find(in: model) else { return false }
        let replacement = TableOfContentsBlock.text(DocumentHeading.extract(from: model), depth: depth ?? toc.depth)
        guard (string as NSString).substring(with: toc.range) != replacement else { return false }
        return replaceTableOfContents(toc.range, with: replacement, automatic: depth == nil)
    }

    /// Swaps in a new table of contents as one undo step, keeping the caret on its text. An automatic update leaves
    /// the block alone while the caret or selection is in it.
    @discardableResult
    private func replaceTableOfContents(_ range: NSRange, with replacement: String, automatic: Bool) -> Bool {
        guard let storage = textStorage, NSMaxRange(range) <= storage.length else { return false }
        if automatic, selectedRanges.contains(where: { NSIntersectionRange($0.rangeValue, range).length > 0 || NSLocationInRange($0.rangeValue.location, range) }) {
            return false
        }
        let selection = selectedRange()
        let delta = (replacement as NSString).length - range.length
        breakUndoCoalescing()
        guard shouldChangeText(in: range, replacementString: replacement) else { return false }
        storage.replaceCharacters(in: range, with: replacement)
        didChangeText()
        undoManager?.setActionName("Update Table of Contents")
        if selection.location >= NSMaxRange(range) {
            setSelectedRange(NSRange(location: selection.location + delta, length: selection.length))
        }
        return true
    }

    /// The source offset at the reading line, a quarter down the page (at most 120pt), and how far through the document
    /// the page is scrolled, from 0 to 1.
    var readingPosition: (offset: Int, progress: Double) {
        guard let scroll = enclosingScrollView, let manager = textLayoutManager, let content = manager.textContentManager else { return (0, 0) }
        let visible = scroll.contentView.bounds
        let y = visible.minY + min(120, visible.height * 0.25) - textContainerOrigin.y
        let offset: Int
        if let fragment = manager.textLayoutFragment(for: CGPoint(x: 0, y: max(0, y))) {
            offset = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
        } else {
            offset = y <= 0 ? 0 : (string as NSString).length
        }
        let scrollable = bounds.height - visible.height
        return (offset, scrollable > 1 ? min(max(visible.minY / scrollable, 0), 1) : 1)
    }

    /// Inserts `block` at the caret as its own block, with blank lines around it, as one undo step.
    func insertBlock(_ block: String) {
        let text = string as NSString
        let range = selectedRange()
        var before = ""
        if range.location > 0, text.character(at: range.location - 1) != 0x0A { before = "\n\n" }
        else if range.location > 1, text.character(at: range.location - 2) != 0x0A { before = "\n" }
        let end = NSMaxRange(range)
        let after = end < text.length && text.character(at: end) != 0x0A ? "\n\n" : "\n"
        window?.makeFirstResponder(self)
        insertText(before + block + after, replacementRange: range)
    }

    /// Changes a link's destination from `old` to `new` in every link range given (or in its reference definition),
    /// as one undo step. Returns how many places changed.
    @discardableResult
    func replaceLinkDestination(_ old: String, with new: String, in links: [NSRange]) -> Int {
        let text = string as NSString
        var targets: [NSRange] = []
        for link in links where NSMaxRange(link) <= text.length {
            // The destination is the last copy of it inside the link: `[text](old)`, `<old>`.
            let found = text.range(of: old, options: .backwards, range: link)
            if found.location != NSNotFound { targets.append(found); continue }
            // A reference link: its definition holds the destination.
            let escaped = NSRegularExpression.escapedPattern(for: old)
            if let definition = try? NSRegularExpression(pattern: "^ {0,3}\\[[^\\]]+\\]:[ \\t]*<?(\(escaped))>?", options: .anchorsMatchLines),
               let match = definition.firstMatch(in: string, range: NSRange(location: 0, length: text.length)) {
                targets.append(match.range(at: 1))
            }
        }
        let unique = Set(targets.map { NSStringFromRange($0) }).map(NSRangeFromString).sorted { $0.location > $1.location }
        guard !unique.isEmpty, let storage = textStorage else { return 0 }
        window?.makeFirstResponder(self)
        breakUndoCoalescing()
        undoManager?.beginUndoGrouping()
        var changed = 0
        for range in unique where shouldChangeText(in: range, replacementString: new) {
            storage.replaceCharacters(in: range, with: new)
            didChangeText()
            changed += 1
        }
        undoManager?.setActionName("Fix Link")
        undoManager?.endUndoGrouping()
        return changed
    }

    /// The frame of the first line segment of `range`, in this view's coordinates.
    /// `firstRect(forCharacterRange:)` answers only for text inside the viewport, and overlays also sit on text
    /// above or below it, so this asks TextKit 2's layout manager, laying the range out first.
    func textRect(_ range: NSRange) -> NSRect {
        let length = (string as NSString).length
        var range = range
        if range.length == 0, range.location < length { range.length = 1 }
        guard let manager = textLayoutManager, let content = manager.textContentManager,
              let start = content.location(content.documentRange.location, offsetBy: min(range.location, length)),
              let end = content.location(start, offsetBy: min(range.length, length - min(range.location, length))),
              let textRange = NSTextRange(location: start, end: end) else { return .zero }
        manager.ensureLayout(for: textRange)
        var first: CGRect?
        manager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
            first = frame
            return false
        }
        guard let frame = first else { return .zero }
        return frame.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }

    /// TextKit 2 places text it has not laid out yet at estimated positions, and moves it once layout catches up.
    /// Lays out everything up to `location` so positions read for overlays are the ones the text settles at.
    func settleLayout(through location: Int) {
        guard let manager = textLayoutManager, let content = manager.textContentManager,
              let end = content.location(content.documentRange.location, offsetBy: min(location, (string as NSString).length)),
              let range = NSTextRange(location: content.documentRange.location, end: end) else { return }
        manager.ensureLayout(for: range)
        // The viewport keeps drawing text where it first estimated it until it lays out again.
        manager.textViewportLayoutController.layoutViewport()
    }

    /// Draws bullets, list numbers, checkboxes, images, math and chips; `dirtyRect` is in this view's coordinates.
    private var anchorCache: (version: Int, mdx: Bool, anchors: [(location: Int, span: MarkdownModel.Span)])?

    struct HTMLBlockRender {
        let text: NSAttributedString
        let scale: CGFloat
        let height: CGFloat
    }
    var htmlBlocks: [Int: HTMLBlockRender] = [:]
    /// Rendered HTML blocks by width, accent and final HTML (images inlined), so unchanged blocks skip WebKit.
    private var htmlRenderCache: [String: HTMLBlockRender] = [:]
    var inlineHTMLImages: [Int: (path: String, width: CGFloat, font: NSFont)] = [:]

    static func htmlAttribute(_ name: String, in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "(?<=\\s)" + NSRegularExpression.escapedPattern(for: name) + #"\s*=\s*(["'])(.*?)\1"#, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: (html as NSString).length)) else { return nil }
        return (html as NSString).substring(with: match.range(at: 2))
    }

    func renderHTML(_ raw: String, width: CGFloat) -> HTMLBlockRender? {
        let imageTag = try? NSRegularExpression(pattern: #"<img\b[^>]*>"#, options: .caseInsensitive)
        let html = NSMutableString(string: raw)
        for match in (imageTag?.matches(in: raw, range: NSRange(location: 0, length: (raw as NSString).length)) ?? []).reversed() {
            let tag = (raw as NSString).substring(with: match.range)
            guard let path = Self.htmlAttribute("src", in: tag) else { continue }
            let replacement: String
            switch image(for: path) {
            case .image where ["http", "https"].contains(Self.imageURL(path, document: documentURL, baseDirectory: baseDirectory).scheme?.lowercased() ?? ""):
                // The downloaded bytes, not a TIFF of the decoded image: a screenshot as TIFF is megabytes of HTML.
                replacement = RemoteImages.shared.dataURI(of: Self.imageURL(path, document: documentURL, baseDirectory: baseDirectory)) ?? ""
            case .image:
                let url = Self.imageURL(path, document: documentURL, baseDirectory: baseDirectory)
                if let data = try? Data(contentsOf: url),
                   let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType {
                    replacement = "data:\(mime);base64," + data.base64EncodedString()
                } else {
                    replacement = ""
                }
            case .placeholder(let message):
                html.replaceCharacters(in: match.range, with: "<span>\(MarkdownHTML.escape(message))</span>")
                continue
            }
            let updated = tag.replacingOccurrences(of: path, with: replacement)
            html.replaceCharacters(in: match.range, with: updated)
        }
        // Importing HTML goes through WebKit and is slow; a restyle reuses every block whose HTML, images included, is unchanged.
        let key = "\(width)|\(theme.accent)|\(html)"
        if let cached = htmlRenderCache[key] { return cached }
        guard let parsed = try? NSAttributedString(data: Data((html as String).utf8), options: [.documentType: NSAttributedString.DocumentType.html,
                                                                                               .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil),
              parsed.length > 0 else { return nil }
        let text = NSMutableAttributedString(attributedString: parsed)
        let all = NSRange(location: 0, length: text.length)
        text.addAttribute(.foregroundColor, value: NSColor.labelColor, range: all)
        var links: [NSRange] = []
        text.enumerateAttribute(.link, in: all) { link, range, _ in if link != nil { links.append(range) } }
        for range in links { text.addAttribute(.foregroundColor, value: theme.accent, range: range) }
        let size = text.size()
        let scale = min(1, width / max(size.width, 1))
        let render = HTMLBlockRender(text: text, scale: scale, height: max(20, ceil(size.height * scale)))
        if htmlRenderCache.count >= 64 { htmlRenderCache.removeAll() }
        htmlRenderCache[key] = render
        return render
    }

    /// Where each decoration is drawn from, sorted: the character whose layout fragment draws it.
    private var decorationAnchors: [(location: Int, span: MarkdownModel.Span)] {
        let model = self.model
        if let anchorCache, anchorCache.version == textVersion, anchorCache.mdx == model.mdx { return anchorCache.anchors }
        var anchors: [(location: Int, span: MarkdownModel.Span)] = []
        var firstFootnote = true
        for span in model.spans {
            switch span.kind {
            case .image(_, true): anchors.append((span.content.location, span))
            case .image(_, false), .mathBlock, .inlineMath, .frontmatter: anchors.append((span.range.location, span))
            case .htmlBlock, .inlineHTML: anchors.append((span.range.location, span))
            case .callout(_, let token): anchors.append((token.location, span))
            case .codeBlock(let language?, true):
                anchors.append((span.range.location, span))
                if span.content.length > 0 { anchors.append((span.content.location, span)) }
                anchors.append((max(span.range.location, NSMaxRange(span.range) - 1), span))
                _ = language
            case .footnoteDefinition where firstFootnote:
                firstFootnote = false
                anchors.append((span.range.location, span))
            default: break
            }
        }
        anchors.sort { $0.location < $1.location }
        anchorCache = (textVersion, model.mdx, anchors)
        return anchors
    }

    /// Spans the current fragment draws for, and the text whose decorations it owns.
    private var drawingSpans: [MarkdownModel.Span] = []
    private var anchorRange = NSRange(location: 0, length: 0)

    /// Draws the decorations anchored in `range` — images, math, diagrams, callout titles, code labels, the footnotes rule,
    /// frontmatter and image chips — in this view's coordinates. `MarkdownLayoutFragment` calls it for the text it lays out,
    /// with its context moved to view coordinates, so each decoration is drawn by exactly one fragment.
    func drawDecorations(anchoredIn range: NSRange) {
        guard rendered else { return }
        anchorRange = range
        let anchors = decorationAnchors
        // Binary search for the first anchor in range; anchors are sorted by location.
        var low = 0, high = anchors.count
        while low < high {
            let middle = (low + high) / 2
            if anchors[middle].location < range.location { low = middle + 1 } else { high = middle }
        }
        var spans: [MarkdownModel.Span] = []
        while low < anchors.count, anchors[low].location < NSMaxRange(range) {
            if spans.last != anchors[low].span { spans.append(anchors[low].span) }
            low += 1
        }
        guard !spans.isEmpty else { return }
        drawingSpans = spans
        defer { drawingSpans = [] }
        drawImages(in: .infinite)
        drawHTML()
        drawMath(in: .infinite)
        drawInlineMath()
        drawDiagrams(in: .infinite)
        drawDecorations(in: .infinite)
    }

    private func drawImages(in dirtyRect: NSRect) {
        guard window != nil else { return }
        for span in drawingSpans {
            guard case .image(let path, true) = span.kind, NSLocationInRange(span.content.location, anchorRange) else { continue }
            let caption = textRect(span.content)
            let y = span.range.location == 0 ? caption.minY + 8 : caption.minY - 268
            let rect = NSRect(x: 0, y: y, width: columnWidth, height: 260)
            guard rect.intersects(dirtyRect) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14).addClip()
            NSColor.quaternaryLabelColor.withAlphaComponent(0.08).setFill()
            rect.fill()
            switch image(for: path) {
            case .image(let image):
                let ratio = min(rect.width / image.size.width, rect.height / image.size.height)
                let size = NSSize(width: image.size.width * ratio, height: image.size.height * ratio)
                image.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
            case .placeholder(let text):
                let label = NSAttributedString(string: text, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor])
                label.draw(at: NSPoint(x: rect.midX - label.size().width / 2, y: rect.midY - label.size().height / 2))
            }
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func drawHTML() {
        guard window != nil, let context = NSGraphicsContext.current?.cgContext else { return }
        for span in drawingSpans where NSLocationInRange(span.range.location, anchorRange) {
            switch span.kind {
            case .htmlBlock:
                guard let rendered = htmlBlocks[span.range.location] else { continue }
                let line = textRect(NSRange(location: span.range.location, length: 1))
                context.saveGState()
                context.translateBy(x: 0, y: line.minY)
                context.scaleBy(x: rendered.scale, y: rendered.scale)
                rendered.text.draw(at: .zero)
                context.restoreGState()
            case .inlineHTML:
                guard let image = inlineHTMLImages[span.range.location] else { continue }
                let line = textRect(NSRange(location: span.range.location, length: 1))
                let height = min(image.width, line.height)
                switch self.image(for: image.path) {
                case .image(let bitmap):
                    bitmap.draw(in: NSRect(x: line.minX, y: line.minY, width: image.width, height: height))
                case .placeholder:
                    break
                }
            default:
                break
            }
        }
    }

    enum ImageContent {
        case image(NSImage)
        /// What to show instead: the file name, or the host of a remote image that is off, loading or unavailable.
        case placeholder(String)
    }

    /// The image an `![](path)` shows: a file beside the document, or a remote image when Settings allows it.
    func image(for path: String) -> ImageContent {
        let resolved = Self.imageURL(path, document: documentURL, baseDirectory: baseDirectory)
        if baseDirectory?.isFileURL == false && resolved.isFileURL { return .placeholder("Local image unavailable in a web document") }
        if ["http", "https"].contains(resolved.scheme?.lowercased() ?? "") {
            let remote = resolved
            let host = remote.host() ?? path
            guard loadRemoteImages else { return .placeholder("Remote image — \(host)") }
            switch RemoteImages.shared.state(of: remote, onChange: { [weak self] in self?.scheduleRemoteRestyle() }) {
            case .loaded(let image): return .image(image)
            case .loading: return .placeholder("Loading image — \(host)")
            case .failed: return .placeholder("Image unavailable — \(host)")
            }
        }
        let url = Self.imageURL(path, document: documentURL, baseDirectory: baseDirectory)
        if let cached = imageCache[url] {
            return cached.map(ImageContent.image) ?? .placeholder("Image unavailable — \(url.lastPathComponent)")
        }
        // Misses are remembered too, so painting never touches the disk; restyling forgets them.
        let image = NSImage(contentsOf: url)
        imageCache[url] = .some(image)
        return image.map(ImageContent.image) ?? .placeholder("Image unavailable — \(url.lastPathComponent)")
    }

    private func remoteImageLoaded() {
        // Fragments draw images; restyling lays them out again with the loaded image.
        restyle?()
        if let previewSpan { showImagePreview(for: previewSpan, force: true) }
    }

    private var remoteRestyleScheduled = false
    /// Every style pass asks again for each image still loading, so one arrival can carry many callbacks,
    /// and several images arrive together: they share one restyle on the next turn of the run loop.
    private func scheduleRemoteRestyle() {
        guard !remoteRestyleScheduled else { return }
        remoteRestyleScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            remoteRestyleScheduled = false
            remoteImageLoaded()
        }
    }

    static let diagramPadding: CGFloat = 16
    static let diagramErrorHeight: CGFloat = 48

    /// A diagram's size inside the code container, scaled down to fit the column.
    static func fitted(_ size: NSSize, width: CGFloat) -> NSSize {
        let room = width - diagramPadding * 2
        let scale = size.width > room ? room / size.width : 1
        return NSSize(width: size.width * scale, height: size.height * scale)
    }

    /// Mermaid blocks: the rendered diagram in the code container, a placeholder while it renders,
    /// or mermaid's message under the source when it cannot be parsed.
    private func drawDiagrams(in dirtyRect: NSRect) {
        guard window != nil else { return }
        let source = string as NSString
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        func rect(_ range: NSRange) -> NSRect { textRect(range) }
        for span in drawingSpans {
            guard case .codeBlock(let language?, true) = span.kind, language.lowercased() == "mermaid",
                  let state = MermaidRenderer.shared.cached(source.substring(with: span.content), dark: dark) else { continue }
            let label = NSAttributedString(string: "mermaid", attributes: [.font: theme.ui(11, weight: .medium), .foregroundColor: NSColor.tertiaryLabelColor])
            if case .failed(let message) = state {
                // The message belongs to the closing fence's line, the label to the first line of code.
                if span.content.length > 0, NSLocationInRange(span.content.location, anchorRange) {
                    let body = rect(NSRange(location: span.content.location, length: 1))
                    label.draw(at: NSPoint(x: columnWidth - label.size().width - 12, y: body.minY - 12 * theme.scale))
                }
                guard NSLocationInRange(max(span.range.location, NSMaxRange(span.range) - 1), anchorRange) else { continue }
                let last = rect(NSRange(location: max(span.range.location, NSMaxRange(span.range) - 1), length: 1))
                let body = span.content.length > 0 ? rect(NSRange(location: span.content.location, length: 1)).minX : last.minX
                let text = NSAttributedString(string: message, attributes: [.font: theme.ui(12), .foregroundColor: NSColor.systemRed])
                // Drawn in the paragraph spacing reserved under the closing fence.
                let frame = NSRect(x: body, y: last.maxY + 4, width: columnWidth - body, height: (Self.diagramErrorHeight - 8) * theme.scale)
                guard frame.intersects(dirtyRect) else { continue }
                text.draw(with: frame, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
                continue
            }
            guard NSLocationInRange(span.range.location, anchorRange) else { continue }
            let line = rect(NSRange(location: span.range.location, length: 1))
            let container = NSRect(x: 0, y: line.minY, width: columnWidth, height: line.height)
            guard container.intersects(dirtyRect) else { continue }
            NSColor.codeFill.setFill()
            NSBezierPath(roundedRect: container, xRadius: 12, yRadius: 12).fill()
            label.draw(at: NSPoint(x: columnWidth - label.size().width - 12, y: container.minY + 8))
            switch state {
            case .rendered(let image):
                let size = Self.fitted(image.size, width: columnWidth)
                image.draw(in: NSRect(x: container.midX - size.width / 2, y: container.midY - size.height / 2, width: size.width, height: size.height))
            default:
                let text = NSAttributedString(string: "Rendering diagram…", attributes: [.font: theme.ui(12), .foregroundColor: NSColor.secondaryLabelColor])
                text.draw(at: NSPoint(x: container.midX - text.size().width / 2, y: container.midY - text.size().height / 2))
            }
        }
    }

    /// Resolves an image destination against the document's folder; inserted paths are percent-encoded.
    static func imageURL(_ path: String, document: URL?, baseDirectory: URL? = nil) -> URL {
        if let baseDirectory, !baseDirectory.isFileURL,
           let remote = URL(string: path, relativeTo: baseDirectory)?.absoluteURL { return remote }
        if let absolute = URL(string: path), absolute.scheme != nil { return absolute }
        let base = document?.deletingLastPathComponent() ?? baseDirectory ?? URL(fileURLWithPath: "/")
        return URL(fileURLWithPath: path.removingPercentEncoding ?? path, relativeTo: base).standardizedFileURL
    }

    private func drawMath(in dirtyRect: NSRect) {
        guard window != nil else { return }
        let source = string as NSString
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        for span in drawingSpans where span.kind == .mathBlock && NSLocationInRange(span.range.location, anchorRange) {
            let line = textRect(NSRange(location: span.range.location, length: 1))
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

    /// Inline formulas typeset by the last style pass, by their span's location; a formula being edited has none.
    var inlineFormulas: [Int: InlineFormula] = [:]
    /// The formula the last style pass showed as source, so a selection change restyles only when it changes.
    var styledEditedFormula: Int?

    /// True while the caret or selection touches `span`, so its source shows for editing.
    func isEditing(_ span: MarkdownModel.Span) -> Bool {
        let selection = selectedRange()
        return selection.location <= NSMaxRange(span.range) && NSMaxRange(selection) >= span.range.location
    }

    /// The inline math span the caret is in, if any; entering or leaving one restyles it.
    var editedFormula: Int? {
        model.spans.first { $0.kind == .inlineMath && isEditing($0) }?.range.location
    }

    /// Inline formulas sit on the text's baseline, in the room their hidden source leaves.
    private func drawInlineMath() {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        for span in drawingSpans where span.kind == .inlineMath && NSLocationInRange(span.range.location, anchorRange) {
            guard let formula = inlineFormulas[span.range.location], let baseline = baselineY(at: span.range.location) else { continue }
            let x = textRect(NSRange(location: span.range.location, length: 1)).minX
            formula.draw(in: context, x: x, baseline: baseline)
        }
    }

    /// The baseline of the line holding `location`, in view coordinates.
    func baselineY(at location: Int) -> CGFloat? {
        guard let manager = textLayoutManager, let content = manager.textContentManager,
              let target = content.location(content.documentRange.location, offsetBy: location),
              let fragment = manager.textLayoutFragment(for: target) else { return nil }
        let offset = content.offset(from: fragment.rangeInElement.location, to: target)
        let line = fragment.textLineFragments.first { NSLocationInRange(offset, $0.characterRange) } ?? fragment.textLineFragments.last
        guard let line else { return nil }
        return fragment.layoutFragmentFrame.minY + line.typographicBounds.minY + line.glyphOrigin.y + textContainerOrigin.y
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
        guard window != nil else { return }
        func rect(_ range: NSRange) -> NSRect { textRect(range) }

        for span in drawingSpans {
            switch span.kind {
            case .callout(let type, let range):
                guard NSLocationInRange(range.location, anchorRange) else { continue }
                let token = rect(range)
                guard token.intersects(dirtyRect.insetBy(dx: 0, dy: -20)) else { continue }
                let title = NSAttributedString(string: type.capitalized, attributes: [
                    .font: theme.ui(13, weight: .semibold), .foregroundColor: Callout.color(type, accent: theme.accent)])
                title.draw(at: NSPoint(x: token.minX, y: token.maxY - title.size().height))
            case .image(let path, false):
                guard NSLocationInRange(span.range.location, anchorRange),
                      let frame = inlineImageChipFrame(span), frame.intersects(dirtyRect) else { continue }
                NSColor.labelColor.withAlphaComponent(0.06).setFill()
                NSBezierPath(roundedRect: frame, xRadius: frame.height / 2, yRadius: frame.height / 2).fill()
                let symbol = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 11 * theme.scale, weight: .medium).applying(.init(hierarchicalColor: .secondaryLabelColor)))
                if let symbol {
                    symbol.draw(in: NSRect(x: frame.minX + 9 * theme.scale, y: frame.midY - symbol.size.height / 2, width: symbol.size.width, height: symbol.size.height))
                }
                let alt = (string as NSString).substring(with: span.content)
                let text = NSAttributedString(string: alt.isEmpty ? (path as NSString).lastPathComponent : alt,
                                              attributes: [.font: theme.ui(11.5, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor])
                if !alt.isEmpty { text.draw(at: NSPoint(x: rect(span.content).minX, y: frame.midY - text.size().height / 2)) }
            case .codeBlock(let language?, true) where span.content.length > 0 && language.lowercased() != "mermaid":
                guard NSLocationInRange(span.content.location, anchorRange) else { continue }
                let line = rect(NSRange(location: span.content.location, length: 1))
                guard line.intersects(dirtyRect.insetBy(dx: 0, dy: -20)) else { continue }
                let label = NSAttributedString(string: language, attributes: [
                    .font: theme.ui(11, weight: .medium), .foregroundColor: NSColor.tertiaryLabelColor])
                // In the box's top padding, right-aligned.
                label.draw(at: NSPoint(x: columnWidth - label.size().width - 12, y: line.minY - 12 * theme.scale))
            default:
                break
            }
        }
        if let first = drawingSpans.first(where: { if case .footnoteDefinition = $0.kind { true } else { false } }),
           NSLocationInRange(first.range.location, anchorRange),
           first.range.location == model.spans.first(where: { if case .footnoteDefinition = $0.kind { true } else { false } })?.range.location {
            let line = rect(NSRange(location: first.range.location, length: 1))
            let y = line.minY - 12 * theme.scale
            if dirtyRect.minY <= y, y <= dirtyRect.maxY {
                NSColor.separatorColor.setFill()
                NSRect(x: 0, y: y, width: columnWidth, height: 1).fill()
            }
        }
        if let frontmatter = Frontmatter.parse(string), NSLocationInRange(frontmatter.range.location, anchorRange) {
            for (chip, frame) in frontmatterChips(frontmatter) where frame.intersects(dirtyRect) {
                if let fill = chip.fill {
                    fill.setFill()
                    NSBezierPath(roundedRect: frame, xRadius: frame.height / 2, yRadius: frame.height / 2).fill()
                }
                chip.text.draw(at: NSPoint(x: frame.minX + (chip.fill != nil ? 9 : 0), y: frame.midY - chip.text.size().height / 2))
            }
        }
    }

    static func isMDX(_ url: URL?) -> Bool { url?.pathExtension.lowercased() == "mdx" }

    static let chipLead: CGFloat = 26
    static let chipTrail: CGFloat = 9

    private static var hiddenAdvances: [String: CGFloat] = [:]

    /// The advance of a character in the 1pt font hidden markers use.
    static func hiddenAdvance(_ character: String) -> CGFloat {
        if let advance = hiddenAdvances[character] { return advance }
        let advance = (character as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 1)]).width
        hiddenAdvances[character] = advance
        return advance
    }

    /// The capsule an inline image is drawn as, on the line where it starts.
    func inlineImageChipFrame(_ span: MarkdownModel.Span) -> NSRect? {
        guard rendered, window != nil else { return nil }
        func rect(_ range: NSRange) -> NSRect { textRect(range) }
        let whole = rect(span.range)
        let height = ("Ag" as NSString).size(withAttributes: [.font: theme.ui(11.5, weight: .medium)]).height + 6
        return NSRect(x: whole.minX, y: whole.midY - height / 2, width: whole.width, height: height)
    }

    private var hoverArea: NSTrackingArea?
    private var previewPopover: NSPopover?
    private var previewSpan: MarkdownModel.Span?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        let hit = model.spans.first { span in
            guard case .image(_, false) = span.kind else { return false }
            return inlineImageChipFrame(span)?.contains(point) == true
        }
        if let hit { showImagePreview(for: hit) } else { closeImagePreview() }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        closeImagePreview()
    }

    /// Hovering an inline image chip previews the image in a popover.
    private func showImagePreview(for span: MarkdownModel.Span, force: Bool = false) {
        guard case .image(let path, false) = span.kind, let frame = inlineImageChipFrame(span) else { return }
        if !force, previewPopover?.isShown == true, previewSpan?.range == span.range { return }
        closeImagePreview()
        let content: NSView
        switch image(for: path) {
        case .image(let image):
            let scale = min(1, 320 / max(image.size.width, 1), 240 / max(image.size.height, 1))
            let view = NSImageView(frame: NSRect(x: 0, y: 0, width: image.size.width * scale, height: image.size.height * scale))
            view.image = image
            view.imageScaling = .scaleProportionallyUpOrDown
            content = view
        case .placeholder(let text):
            let label = NSTextField(labelWithString: text)
            label.textColor = .secondaryLabelColor
            label.sizeToFit()
            content = label
        }
        let container = NSView(frame: content.frame.insetBy(dx: -8, dy: -8).offsetBy(dx: 8, dy: 8))
        content.frame.origin = NSPoint(x: 8, y: 8)
        container.addSubview(content)
        let controller = NSViewController()
        controller.view = container
        let popover = NSPopover()
        popover.contentViewController = controller
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.show(relativeTo: frame, of: self, preferredEdge: .maxY)
        previewPopover = popover
        previewSpan = span
    }

    private func closeImagePreview() {
        previewPopover?.close()
        previewPopover = nil
        previewSpan = nil
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
        guard window != nil else { return [] }
        let line = textRect(NSRange(location: frontmatter.range.location, length: 1))
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
        closeImagePreview()
        let point = convert(event.locationInWindow, from: nil)
        if rendered, let frontmatter = Frontmatter.parse(string),
           let hit = frontmatterChips(frontmatter).first(where: { $0.frame.contains(point) }) {
            if let link = hit.chip.link { return Knowledge.follow(link, title: nil, from: documentURL, bundleRoot: bundleRoot, baseDirectory: baseDirectory) }
            return editFrontmatter(frontmatter, at: hit.frame)
        }
        if event.modifierFlags.contains(.command), followFootnote(at: characterIndexForInsertion(at: point)) { return }
        // In the Rendered lens, a click on a Contents card entry goes to its heading, as in a book's contents.
        if rendered, !event.modifierFlags.contains(.shift), let link = tableOfContentsLink(at: point) {
            if !revealAnchor(LinkTarget.fragment(link) ?? "") { NSSound.beep() }
            return
        }
        // ⌘-click follows a link, resolving `/…` against the OKF bundle root.
        if event.modifierFlags.contains(.command), let link = OKFLinks.link(at: characterIndexForInsertion(at: point), in: string) {
            // A link to a heading in this document moves there.
            if link.target.hasPrefix("#") {
                if !revealAnchor(LinkTarget.fragment(link.target) ?? "") { NSSound.beep() }
                return
            }
            return Knowledge.follow(link.target, title: link.text, from: documentURL, bundleRoot: bundleRoot, baseDirectory: baseDirectory)
        }
        for item in tasks() {
            guard let rect = checkboxRect(for: item), rect.contains(point), let box = item.checkbox else { continue }
            toggleTask(box: box, checked: item.checked)
            return
        }
        super.mouseDown(with: event)
    }

    /// Flips a task's `[ ]`/`[x]` as one undoable edit. The caret and the page stay put: `insertText` would move the
    /// caret to the box and scroll to wherever the caret was before the click (issue #8).
    private func toggleTask(box: NSRange, checked: Bool) {
        let range = NSRange(location: box.location + 1, length: 1)
        let mark = checked ? " " : "x"
        let selection = selectedRange()
        let clip = enclosingScrollView?.contentView
        let origin = clip?.bounds.origin
        guard shouldChangeText(in: range, replacementString: mark) else { return }
        textStorage?.replaceCharacters(in: range, with: mark)
        didChangeText()
        setSelectedRange(selection)
        if let clip, let origin {
            clip.scroll(to: origin)
            enclosingScrollView?.reflectScrolledClipView(clip)
        }
    }

    /// The reference a footnote jump left from, so ⌘-clicking the definition returns to it.
    private var footnoteOrigin: (label: String, location: Int)?

    /// ⌘-click on a footnote reference selects its definition; on a definition's label, the reference it was reached from.
    /// Returns false when `index` is on neither.
    func followFootnote(at index: Int) -> Bool {
        let spans = model.spans
        func hit(_ range: NSRange) -> Bool { range.location <= index && index <= NSMaxRange(range) }
        func reveal(_ range: NSRange) {
            setSelectedRange(range)
            scrollRangeToVisible(range)
            showFindIndicator(for: range)
        }
        for span in spans {
            switch span.kind {
            case .footnoteReference(let label) where hit(span.range):
                let definition = spans.lazy.compactMap { span -> NSRange? in
                    if case .footnoteDefinition(label, let labelRange) = span.kind { labelRange } else { nil }
                }.first
                guard let definition else { NSSound.beep(); return true }
                footnoteOrigin = (label, span.range.location)
                reveal(definition)
                return true
            case .footnoteDefinition(let label, let labelRange) where hit(NSRange(location: span.range.location, length: NSMaxRange(labelRange) + 2 - span.range.location)):
                let references = spans.filter { $0.kind == .footnoteReference(label: label) }
                guard let first = references.first else { NSSound.beep(); return true }
                // Edits since the jump can move the reference; fall back to the first one.
                let origin = references.first { footnoteOrigin?.label == label && $0.range.location == footnoteOrigin?.location }
                reveal((origin ?? first).content)
                return true
            default:
                continue
            }
        }
        return false
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
    static let noteExtensions = ["md", "mdx", "markdown"]

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = NSURL(from: sender.draggingPasteboard) as URL?, url.isFileURL else { return super.performDragOperation(sender) }
        if Self.noteExtensions.contains(url.pathExtension.lowercased()) {
            // A note dropped from the sidebar or Finder becomes a link to it where it lands.
            let title = (try? String(contentsOf: url, encoding: .utf8)).map { Self.noteTitle($0, url: url) } ?? url.deletingPathExtension().lastPathComponent
            let location = characterIndexForInsertion(at: convert(sender.draggingLocation, from: nil))
            insertText(Self.noteLink(to: url, title: title, from: documentURL, bundleRoot: bundleRoot, baseDirectory: baseDirectory), replacementRange: NSRange(location: location, length: 0))
            return true
        }
        guard Self.imageExtensions.contains(url.pathExtension.lowercased()) else { return super.performDragOperation(sender) }
        return insertImage(url)
    }

    /// A note's title: its frontmatter `title`, else its first `# ` heading, else its file name.
    static func noteTitle(_ source: String, url: URL) -> String {
        let lines = FrontmatterBlock.body(of: source).split(separator: "\n", omittingEmptySubsequences: true)
        return Frontmatter.parse(source)?.title ?? lines.first { $0.hasPrefix("# ") }.map { String($0.dropFirst(2)) }
            ?? url.deletingPathExtension().lastPathComponent
    }

    /// A portable Markdown link to another note: relative to this document, bundle-absolute when both sit in its OKF bundle,
    /// and absolute while the document is unsaved, as dropped images are.
    static func noteLink(to target: URL, title: String, from document: URL?, bundleRoot: URL?, baseDirectory: URL? = nil) -> String {
        let path: String
        if let document {
            if let bundleRoot, OKFLinks.bundlePath(of: document, root: bundleRoot) != nil, let inBundle = OKFLinks.bundlePath(of: target, root: bundleRoot) {
                path = inBundle
            } else {
                path = OKFLinks.relativePath(to: target, from: document.deletingLastPathComponent())
            }
        } else if let baseDirectory {
            path = OKFLinks.relativePath(to: target, from: baseDirectory)
        } else {
            path = target.path
        }
        let text = title.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
        return "[\(text)](\(path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path))"
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

/// Remote images for the Rendered lens, fetched once per URL and shared by every window.
@MainActor final class RemoteImages {
    static let shared = RemoteImages()
    enum State { case loading, loaded(NSImage), failed }
    private var states: [URL: State] = [:]
    private var waiting: [URL: [() -> Void]] = [:]
    /// Each loaded image's bytes as a data URI, for HTML blocks.
    private var dataURIs: [URL: String] = [:]

    func dataURI(of url: URL) -> String? { dataURIs[url] }

    /// The image's state, starting a download on first request; `onChange` runs once when it settles.
    func state(of url: URL, onChange: @escaping () -> Void) -> State {
        if let state = states[url] {
            if case .loading = state { waiting[url, default: []].append(onChange) }
            return state
        }
        states[url] = .loading
        waiting[url] = [onChange]
        Task {
            let response = try? await URLSession.shared.data(from: url)
            let ok = (response?.1 as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? true
            states[url] = ok ? response.flatMap { NSImage(data: $0.0) }.map { .loaded($0) } ?? .failed : .failed
            if case .loaded = states[url], let response {
                let mime = response.1.mimeType.flatMap { $0.hasPrefix("image/") ? $0 : nil } ?? "application/octet-stream"
                dataURIs[url] = "data:\(mime);base64," + response.0.base64EncodedString()
            }
            waiting.removeValue(forKey: url)?.forEach { $0() }
        }
        return .loading
    }
}

final class TableRowView: NSView {
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

final class TableCellField: NSTextField, NSTextFieldDelegate {
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

    /// The editor's row and column commands for this cell.
    private var tableItems: [NSMenuItem] {
        var view = superview
        while let current = view, !(current is MarkdownTextView) { view = current.superview }
        return (view as? MarkdownTextView)?.tableMenuItems(at: sourceRange.location) ?? []
    }

    // Right-click on a cell that isn't being edited.
    override func menu(for event: NSEvent) -> NSMenu? {
        let items = tableItems
        guard !items.isEmpty else { return super.menu(for: event) }
        let menu = NSMenu()
        items.forEach(menu.addItem)
        return menu
    }

    // Right-click in the cell being edited: the field editor asks its delegate, this field.
    @objc(textView:menu:forEvent:atIndex:) func textView(_ textView: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
        let items = tableItems
        guard !items.isEmpty else { return menu }
        for (index, item) in (items + [.separator()]).enumerated() { menu.insertItem(item, at: index) }
        return menu
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

    enum Edit: String, CaseIterable {
        case insertRowAbove, insertRowBelow, insertColumnLeft, insertColumnRight, deleteRow, deleteColumn

        var title: String {
            switch self {
            case .insertRowAbove: "Insert Row Above"
            case .insertRowBelow: "Insert Row Below"
            case .insertColumnLeft: "Insert Column Left"
            case .insertColumnRight: "Insert Column Right"
            case .deleteRow: "Delete Row"
            case .deleteColumn: "Delete Column"
            }
        }
    }

    /// A table edit as the smallest source replacement, and the cell (row index counting the delimiter row, column) the caret moves to.
    struct Change: Equatable {
        let range: NSRange
        let replacement: String
        let row: Int
        let column: Int
    }

    /// One row's line split at its unescaped pipes, keeping every character so an untouched row rebuilds exactly.
    private struct Line {
        /// Up to and including the leading pipe; empty when the row has none.
        var lead: String
        /// The text between pipes, padding included.
        var cells: [String]
        /// From the closing pipe on; empty when the row has none.
        var trail: String

        init(_ text: NSString) {
            // The same bounds as `MarkdownModel.cells(in:)`.
            var bounds: [Int] = []
            for index in 0..<text.length where text.character(at: index) == 124 {
                if index == 0 || text.character(at: index - 1) != 92 { bounds.append(index) }
            }
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if !trimmed.hasPrefix("|") { bounds.insert(-1, at: 0) }
            if !trimmed.hasSuffix("|") || bounds.count < 2 { bounds.append(text.length) }
            lead = text.substring(to: bounds[0] + 1)
            cells = zip(bounds, bounds.dropFirst()).map { text.substring(with: NSRange(location: $0 + 1, length: $1 - $0 - 1)) }
            trail = text.substring(from: bounds[bounds.count - 1])
        }

        init(indent: String, cells: [String]) {
            lead = indent + "|"
            self.cells = cells
            trail = "|"
        }

        var text: String {
            // A row of one cell needs a pipe to stay a table row.
            if cells.count == 1, !lead.hasSuffix("|"), !trail.hasPrefix("|") { return lead + "|" + cells[0] + "|" + trail }
            return lead + cells.joined(separator: "|") + trail
        }

        var indent: String { String(lead.prefix { $0 == " " || $0 == "\t" }) }
    }

    /// The source change for `edit` with the caret at `location`. Nil when the edit would leave no table:
    /// deleting the header of a table without body rows, or its only column.
    ///
    /// GFM tables start with a header row and a delimiter row, and have no footer. A new row above the header becomes
    /// the header and the old header the first body row; a new row below the header goes under the delimiter; deleting
    /// the header promotes the first body row. The delimiter row acts as the header.
    func change(_ edit: Edit, in source: String, at location: Int) -> Change? {
        let text = source as NSString
        let start = rows[0].start, end = rows[rows.count - 1].end
        let newline = rows.count > 1 ? text.substring(with: NSRange(location: rows[0].end, length: rows[1].start - rows[0].end)) : "\n"
        var lines = rows.map { Line(text.substring(with: NSRange(location: $0.start, length: $0.end - $0.start)) as NSString) }
        let columns = rows[0].cells.count
        let at = current == 1 ? 0 : current
        let column = rows[current].cells.firstIndex { location <= NSMaxRange($0) } ?? max(rows[current].cells.count - 1, 0)
        let empty = "  "
        let blank = Line(indent: lines[at].indent, cells: Array(repeating: empty, count: columns))
        func padded(_ line: Line, to count: Int) -> Line {
            var line = line
            while line.cells.count < count { line.cells.append(empty) }
            return line
        }
        var target = (row: at, column: column)
        switch edit {
        case .insertRowAbove where at == 0:
            lines[0] = padded(lines[0], to: columns)
            lines.insert(blank, at: 0)
            lines.swapAt(1, 2)
        case .insertRowAbove:
            lines.insert(blank, at: at)
        case .insertRowBelow:
            target.row = max(at + 1, 2)
            lines.insert(blank, at: target.row)
        case .deleteRow where at == 0:
            guard lines.count > 2 else { return nil }
            lines[0] = padded(lines.remove(at: 2), to: columns)
        case .deleteRow:
            lines.remove(at: at)
            target.row = at < lines.count ? at : at - 1
            if target.row == 1 { target.row = 0 }
        case .insertColumnLeft, .insertColumnRight:
            let index = edit == .insertColumnLeft ? column : column + 1
            target.column = index
            for row in lines.indices {
                lines[row] = padded(lines[row], to: index)
                let delimiter = row == 1
                let spaced = lines[row].cells.first?.hasPrefix(" ") ?? true
                lines[row].cells.insert(delimiter ? (spaced ? " --- " : "---") : empty, at: index)
            }
        case .deleteColumn:
            guard columns > 1 else { return nil }
            for row in lines.indices where column < lines[row].cells.count { lines[row].cells.remove(at: column) }
            target.column = min(column, columns - 2)
        }
        // Replace only what changed, so the rest of the table keeps its place in the undo history.
        let old = text.substring(with: NSRange(location: start, length: end - start)) as NSString
        let new = lines.map(\.text).joined(separator: newline) as NSString
        var prefix = 0
        while prefix < old.length, prefix < new.length, old.character(at: prefix) == new.character(at: prefix) { prefix += 1 }
        var suffix = 0
        while suffix < old.length - prefix, suffix < new.length - prefix,
              old.character(at: old.length - 1 - suffix) == new.character(at: new.length - 1 - suffix) { suffix += 1 }
        return Change(range: NSRange(location: start + prefix, length: old.length - prefix - suffix),
                      replacement: new.substring(with: NSRange(location: prefix, length: new.length - prefix - suffix)),
                      row: target.row, column: target.column)
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

/// An inline `$…$` formula typeset with SwaTex at the size of the text around it, drawn as vectors so it stays sharp
/// at any zoom and in PDF.
struct InlineFormula {
    let list: DisplayList
    let options: RenderOptions
    let metrics: RenderMetrics

    var width: CGFloat { metrics.width }

    init?(latex: String, size: CGFloat, dark: Bool) {
        let latex = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !latex.isEmpty, let list = try? SwaTexEngine.displayList(for: latex, style: .text, color: dark ? .white : .black) else { return nil }
        self.list = list
        options = RenderOptions(fontSize: size, padding: 1)
        metrics = DisplayListRenderer.metrics(for: list, options: options)
    }

    /// Draws with the formula's baseline at `baseline` in a flipped context.
    func draw(in context: CGContext, x: CGFloat, baseline: CGFloat) {
        context.saveGState()
        context.translateBy(x: x, y: baseline - metrics.baseline + metrics.height)
        context.scaleBy(x: 1, y: -1)
        DisplayListRenderer.draw(list, in: context, options: options)
        context.restoreGState()
    }
}

