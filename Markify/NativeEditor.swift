import AppKit
import Markdown
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

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.documentURL = fileURL
        editor.columnWidth = columnWidth
        editor.rendered = !markdownLens
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
        (editor as? MarkdownTextView)?.columnWidth = columnWidth
        (editor as? MarkdownTextView)?.rendered = !markdownLens
        context.coordinator.parent = self
        let sourceChanged = editor.string != text
        let styleChanged = context.coordinator.lastLens != markdownLens || context.coordinator.lastQuery != findQuery || context.coordinator.lastMatchCase != matchCase
        if sourceChanged || styleChanged {
            let topOffset = editor.characterIndexForInsertion(at: NSPoint(x: 0, y: scroll.contentView.bounds.minY))
            let anchor = SourceAnchor(source: editor.string, selection: editor.selectedRange(), topOffset: topOffset)
            let before = editor.firstRect(forCharacterRange: anchor.topLine, actualRange: nil)
            if sourceChanged { editor.string = text }
            style(editor)
            editor.setSelectedRange(anchor.selection(in: editor.string))
            editor.layoutSubtreeIfNeeded()
            let after = editor.firstRect(forCharacterRange: anchor.topLine, actualRange: nil)
            let newY = max(0, scroll.contentView.bounds.minY + before.minY - after.minY)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: newY))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        context.coordinator.lastLens = markdownLens
        context.coordinator.lastQuery = findQuery
        context.coordinator.lastMatchCase = matchCase
    }

    func style(_ editor: NSTextView) {
        guard let storage = editor.textStorage else { return }
        let source = editor.string as NSString
        let whole = NSRange(location: 0, length: source.length)
        guard whole.length > 0 else { return }
        let primary = NSColor.labelColor
        let dim = NSColor.tertiaryLabelColor
        let base = markdownLens ? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular) : NSFont(name: "NewYork-Regular", size: 18) ?? NSFont.systemFont(ofSize: 18)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = markdownLens ? 10 : 11
        storage.beginEditing()
        storage.setAttributes([.font: base, .foregroundColor: primary, .paragraphStyle: paragraph], range: whole)

        func matches(_ pattern: String, _ apply: (NSTextCheckingResult) -> Void) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return }
            regex.enumerateMatches(in: editor.string, range: whole) { match, _, _ in if let match { apply(match) } }
        }
        func marker(_ range: NSRange) {
            guard range.location != NSNotFound, range.length > 0 else { return }
            storage.addAttributes([.foregroundColor: markdownLens ? dim : NSColor.clear,
                                   .font: markdownLens ? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular) : NSFont.systemFont(ofSize: 1)], range: range)
        }
        let map = MarkdownSourceMap(editor.string)
        let parsed = Markdown.Document(parsing: editor.string)
        for child in parsed.children {
            guard let heading = child as? Markdown.Heading,
                  let sourceRange = heading.range,
                  let range = map.range(sourceRange),
                  let match = try? NSRegularExpression(pattern: "^(#{1,6})[ \\t]+([^\\n]+)").firstMatch(in: editor.string, range: range) else { continue }
            let level = heading.level
            let size: CGFloat = markdownLens ? 16 : (level == 1 ? 36 : level == 2 ? 22 : 19)
            let font = markdownLens ? NSFont.monospacedSystemFont(ofSize: size, weight: .bold) : (NSFont(name: "NewYork-Bold", size: size) ?? NSFont.boldSystemFont(ofSize: size))
            storage.addAttribute(.font, value: font, range: match.range(at: 2))
            marker(NSRange(location: match.range.location, length: match.range(at: 2).location - match.range.location))
        }
        matches("(?m)^(?:[ \\t]*)(>[ \\t]?)") { match in marker(match.range(at: 1)) }
        matches("(?m)^[ \\t]*([-*+] )(?!\\[[ xX]\\] )") { match in
            if markdownLens { marker(match.range(at: 1)) }
            else { storage.addAttributes([.foregroundColor: NSColor.clear, .font: NSFont.monospacedSystemFont(ofSize: 18, weight: .regular)], range: match.range(at: 1)) }
        }
        matches("(?m)^[ \\t]*([0-9]+\\.) ") { match in
            if markdownLens { marker(match.range(at: 1)) }
            else { storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: match.range(at: 1)) }
        }
        matches("(\\*\\*|__)([^\\n]+?)\\1") { match in
            storage.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: markdownLens ? 14 : 18), range: match.range(at: 2))
            marker(match.range(at: 1))
            marker(NSRange(location: NSMaxRange(match.range) - match.range(at: 1).length, length: match.range(at: 1).length))
        }
        matches("(?<!\\*)\\*([^*\\n]+)\\*(?!\\*)") { match in
            storage.addAttribute(.font, value: NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask), range: match.range(at: 1))
            marker(NSRange(location: match.range.location, length: 1))
            marker(NSRange(location: NSMaxRange(match.range) - 1, length: 1))
        }
        matches("`([^`\\n]+)`") { match in
            storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: markdownLens ? 14 : 15, weight: .regular), range: match.range(at: 1))
            marker(NSRange(location: match.range.location, length: 1))
            marker(NSRange(location: NSMaxRange(match.range) - 1, length: 1))
        }
        matches("(?m)^(```.*|\\$\\$|---)[ \\t]*$") { marker($0.range) }
        matches("(?m)^> \\[!(NOTE|TIP|WARNING|IMPORTANT)\\].*(?:\\n>[^\\n]*)*") { match in
            guard !markdownLens else { return }
            storage.addAttributes([.backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.08),
                                   .font: NSFont.systemFont(ofSize: 15)], range: match.range)
            storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: match.range(at: 1))
            marker(NSRange(location: match.range.location, length: 2))
        }
        matches("(?m)^[-*+] \\[([xX ])\\] ([^\\n]+)") { match in
            guard !markdownLens else { return }
            storage.addAttributes([.foregroundColor: NSColor.clear,
                                   .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)],
                                  range: NSRange(location: match.range.location, length: match.range(at: 2).location - match.range.location))
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 17), range: match.range(at: 2))
            if (source.substring(with: match.range(at: 1))).lowercased() == "x" {
                storage.addAttributes([.foregroundColor: dim, .strikethroughStyle: NSUnderlineStyle.single.rawValue], range: match.range(at: 2))
            }
        }
        // Hanging indent: wrapped lines of a list item align with its text, not its marker.
        matches("(?m)^[ \\t]*(?:[-*+] \\[[ xX]\\] |[-*+] |[0-9]+[.)] )") { match in
            let style = paragraph.mutableCopy() as! NSMutableParagraphStyle
            style.headIndent = storage.attributedSubstring(from: match.range).size().width
            storage.addAttribute(.paragraphStyle, value: style, range: source.paragraphRange(for: match.range))
        }
        if !markdownLens {
            for table in MarkdownTable.blocks(in: editor.string) {
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
        }
        matches("(?m)^\\[\\^[^]\\n]+\\]:.*$") { match in
            storage.addAttributes([.font: NSFont.systemFont(ofSize: 13), .foregroundColor: dim], range: match.range)
        }
        matches("(?ms)^```([a-zA-Z0-9_+-]*)[^\\n]*\\n(.*?)\\n```[ \\t]*$") { match in
            let body = match.range(at: 2)
            storage.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: markdownLens ? 14 : 13.5, weight: .regular),
                                   .backgroundColor: NSColor.textBackgroundColor.blended(withFraction: 0.06, of: .gray) ?? NSColor.textBackgroundColor], range: body)
            if !markdownLens {
                marker(NSRange(location: match.range.location, length: body.location - match.range.location))
                marker(NSRange(location: NSMaxRange(body), length: NSMaxRange(match.range) - NSMaxRange(body)))
            }
            let code = source.substring(with: body)
            let colors: [(String, NSColor)] = [
                (#"\b(func|let|var|if|else|return|class|struct|import|guard|private)\b"#, NSColor.systemPurple),
                (#"\b[A-Z][A-Za-z0-9_]*\b"#, NSColor.systemTeal),
                (#""[^"\n]*""#, NSColor.systemRed),
                (#"//[^\n]*"#, NSColor.secondaryLabelColor)
            ]
            for (pattern, color) in colors {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                for token in regex.matches(in: code, range: NSRange(location: 0, length: (code as NSString).length)) {
                    storage.addAttribute(.foregroundColor, value: color, range: NSRange(location: body.location + token.range.location, length: token.range.length))
                }
            }
        }
        matches("(?ms)^\\$\\$[ \\t]*\\n?(.*?)\\n?\\$\\$[ \\t]*$") { match in
            guard !markdownLens else { return }
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            style.minimumLineHeight = 80
            storage.addAttributes([.font: NSFont.systemFont(ofSize: 1), .foregroundColor: NSColor.clear], range: match.range)
            storage.addAttribute(.paragraphStyle, value: style, range: NSRange(location: match.range.location, length: min(2, match.range.length)))
        }
        matches("(?<!\\$)\\$([^$\\n]+)\\$(?!\\$)") { match in
            guard !markdownLens else { return }
            storage.addAttribute(.font, value: NSFont(name: "NewYork-Italic", size: 18) ?? base, range: match.range(at: 1))
            marker(NSRange(location: match.range.location, length: 1))
            marker(NSRange(location: NSMaxRange(match.range) - 1, length: 1))
        }
        matches("\\[([^]\\n]+)\\]\\(([^)\\n]+)\\)") { match in
            storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: match.range(at: 1))
            if markdownLens { storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: match.range(at: 2)) }
            else { marker(NSRange(location: match.range.location, length: match.range(at: 1).location - match.range.location)); marker(NSRange(location: NSMaxRange(match.range(at: 1)), length: NSMaxRange(match.range) - NSMaxRange(match.range(at: 1)))) }
        }
        matches("(?m)^!\\[([^]\\n]*)\\]\\(([^)\\n]+)\\)[ \\t]*$") { match in
            guard !markdownLens else { return }
            let caption = match.range(at: 1)
            marker(match.range)
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            style.paragraphSpacingBefore = 270
            style.paragraphSpacing = 34
            storage.addAttribute(.paragraphStyle, value: style, range: match.range)
            storage.addAttributes([.font: NSFont.systemFont(ofSize: 13),
                                   .foregroundColor: NSColor.secondaryLabelColor], range: caption)
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
                    if visible { storage.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.4), range: match.range) }
                }
            }
        }
        storage.endEditing()
        if let editor = editor as? MarkdownTextView {
            DispatchQueue.main.async { [weak editor] in editor?.refreshTables() }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeEditor
        weak var editor: NSTextView?
        var lastLens = false
        var lastQuery = ""
        var lastMatchCase = false
        var isCreatingTitle = false
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
            parent.text = editor.string
            parent.onType()
            let slash = SlashContext.detect(in: editor.string, selection: editor.selectedRange())
            if slash?.range.location != dismissedSlashLocation { dismissedSlashLocation = nil }
            parent.onSlash(dismissedSlashLocation == nil ? slash?.query : nil)
            parent.style(editor)
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let editor else { return }
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
    var columnWidth: CGFloat = 640
    var rendered = true
    var onSlashKey: ((SlashKey, SlashContext) -> Bool)?
    private var imageCache: [URL: NSImage] = [:]
    private var mathCache: [String: NSImage] = [:]
    private var tableOverlays: [Int: TableRowView] = [:]

    func refreshTables() {
        guard let window else { return }
        let rows: [(MarkdownTable.Row, Bool)] = rendered ? MarkdownTable.blocks(in: string).flatMap { table in
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

    private var isRenumbering = false

    /// Keeps ordered lists counting up after any edit, in the same undo group as the edit.
    override func didChangeText() {
        super.didChangeText()
        guard !isRenumbering, !(undoManager?.isUndoing ?? false), !(undoManager?.isRedoing ?? false) else { return }
        let fixes = MarkdownList.renumbering(string)
        guard !fixes.isEmpty, let storage = textStorage,
              shouldChangeText(inRanges: fixes.map { NSValue(range: $0.range) }, replacementStrings: fixes.map(\.value)) else { return }
        var selection = selectedRange()
        isRenumbering = true
        storage.beginEditing()
        for fix in fixes.reversed() {
            storage.replaceCharacters(in: fix.range, with: fix.value)
            if NSMaxRange(fix.range) <= selection.location { selection.location += (fix.value as NSString).length - fix.range.length }
        }
        storage.endEditing()
        didChangeText()
        setSelectedRange(selection)
        isRenumbering = false
    }

    /// Return inside a list item starts the next item; Return on an empty item ends the list.
    func continueList() -> Bool {
        let selection = selectedRange()
        guard selection.length == 0 else { return false }
        let source = string as NSString
        let line = source.lineRange(for: NSRange(location: selection.location, length: 0))
        let text = source.substring(with: NSRange(location: line.location, length: selection.location - line.location))
        guard let regex = try? NSRegularExpression(pattern: #"^([ \t]*)(?:([-*+])( \[[ xX]\])?|([0-9]+)([.)])) "#),
              let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) else { return false }
        let prefix = text as NSString
        if match.range.length == prefix.length, NSMaxRange(line) - selection.location <= 1 {
            insertText("", replacementRange: NSRange(location: line.location, length: match.range.length))
            return true
        }
        let indent = prefix.substring(with: match.range(at: 1))
        let next: String
        if match.range(at: 4).location != NSNotFound {
            next = "\((Int(prefix.substring(with: match.range(at: 4))) ?? 0) + 1)\(prefix.substring(with: match.range(at: 5))) "
        } else {
            next = prefix.substring(with: match.range(at: 2)) + (match.range(at: 3).location != NSNotFound ? " [ ]" : "") + " "
        }
        insertText("\n" + indent + next, replacementRange: selection)
        return true
    }

    func navigateTable(backward: Bool) -> Bool {
        guard let table = MarkdownTable.containing(string, location: selectedRange().location),
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

    private func taskMatches() -> [NSTextCheckingResult] {
        // ponytail: Scan on paint; cache task ranges if large documents make redraw slow.
        guard rendered, let regex = try? NSRegularExpression(pattern: #"(?m)^[-*+] \[([xX ])\] "#) else { return [] }
        return regex.matches(in: string, range: NSRange(location: 0, length: (string as NSString).length))
    }

    private func checkboxRect(for match: NSTextCheckingResult) -> NSRect? {
        guard let window else { return nil }
        let screen = firstRect(forCharacterRange: NSRange(location: match.range.location, length: 1), actualRange: nil)
        let local = convert(window.convertFromScreen(screen), from: nil)
        return NSRect(x: local.minX + 2, y: local.midY - 9, width: 18, height: 18)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if rendered { drawImages(in: dirtyRect) }
        if rendered { drawMath(in: dirtyRect) }
        if rendered, let window, let bullets = try? NSRegularExpression(pattern: #"(?m)^[ \t]*([-*+]) (?!\[[ xX]\] )"#) {
            let dot = NSAttributedString(string: "•", attributes: [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.secondaryLabelColor])
            for match in bullets.matches(in: string, range: NSRange(location: 0, length: (string as NSString).length)) {
                let screen = firstRect(forCharacterRange: match.range(at: 1), actualRange: nil)
                let rect = convert(window.convertFromScreen(screen), from: nil)
                guard rect.intersects(dirtyRect) else { continue }
                dot.draw(at: NSPoint(x: rect.midX - dot.size().width / 2, y: rect.midY - dot.size().height / 2))
            }
        }
        for match in taskMatches() {
            guard let rect = checkboxRect(for: match), rect.intersects(dirtyRect) else { continue }
            let checked = ((string as NSString).substring(with: match.range(at: 1))).lowercased() == "x"
            let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
            if checked {
                NSColor.controlAccentColor.setFill()
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
        guard let window,
              let regex = try? NSRegularExpression(pattern: #"(?m)^!\[([^]\n]*)\]\(([^)\n]+)\)[ \t]*$"#) else { return }
        let source = string as NSString
        for match in regex.matches(in: string, range: NSRange(location: 0, length: source.length)) {
            let screen = firstRect(forCharacterRange: match.range(at: 1), actualRange: nil)
            let caption = convert(window.convertFromScreen(screen), from: nil)
            let rect = NSRect(x: 0, y: caption.minY - 268, width: columnWidth, height: 260)
            guard rect.intersects(dirtyRect) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14).addClip()
            NSColor.quaternaryLabelColor.withAlphaComponent(0.08).setFill()
            rect.fill()
            let path = source.substring(with: match.range(at: 2))
            let base = documentURL?.deletingLastPathComponent() ?? URL(fileURLWithPath: "/")
            let url = URL(fileURLWithPath: path, relativeTo: base).standardizedFileURL
            if let image = imageCache[url] ?? NSImage(contentsOf: url) {
                imageCache[url] = image
                let ratio = min(rect.width / image.size.width, rect.height / image.size.height)
                let size = NSSize(width: image.size.width * ratio, height: image.size.height * ratio)
                let frame = NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
                image.draw(in: frame)
            } else {
                let label = "image — \(URL(fileURLWithPath: path).lastPathComponent)" as NSString
                label.draw(at: NSPoint(x: rect.midX - 90, y: rect.midY - 8), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor])
            }
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func drawMath(in dirtyRect: NSRect) {
        guard let window,
              let regex = try? NSRegularExpression(pattern: #"(?ms)^\$\$[ \t]*\n?(.*?)\n?\$\$[ \t]*$"#) else { return }
        let source = string as NSString
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        for match in regex.matches(in: string, range: NSRange(location: 0, length: source.length)) {
            let screen = firstRect(forCharacterRange: NSRange(location: match.range.location, length: 1), actualRange: nil)
            let line = convert(window.convertFromScreen(screen), from: nil)
            let rect = NSRect(x: 0, y: line.midY - 40, width: columnWidth, height: 80)
            guard rect.intersects(dirtyRect) else { continue }
            let latex = source.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
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
              let data = ImageRenderer.png(for: list, options: RenderOptions(fontSize: 22, padding: 2)),
              let image = NSImage(data: data) else { return nil }
        image.size = NSSize(width: image.size.width / 2, height: image.size.height / 2)
        return image
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for match in taskMatches() {
            guard let rect = checkboxRect(for: match), rect.contains(point) else { continue }
            let checked = ((string as NSString).substring(with: match.range(at: 1))).lowercased() == "x"
            insertText(checked ? " " : "x", replacementRange: match.range(at: 1))
            return
        }
        super.mouseDown(with: event)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let imageURL = NSURL(from: sender.draggingPasteboard) as URL?,
              ["png", "jpg", "jpeg", "gif", "heic", "webp"].contains(imageURL.pathExtension.lowercased()) else {
            return super.performDragOperation(sender)
        }
        let name = imageURL.lastPathComponent
        guard let documentURL else {
            insertText("![\(imageURL.deletingPathExtension().lastPathComponent)](\(imageURL.path))", replacementRange: selectedRange())
            return true
        }
        do {
            let folder = documentURL.deletingLastPathComponent().appendingPathComponent("assets", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var target = folder.appendingPathComponent(name)
            var number = 2
            while FileManager.default.fileExists(atPath: target.path) {
                target = folder.appendingPathComponent("\(imageURL.deletingPathExtension().lastPathComponent)-\(number).\(imageURL.pathExtension)")
                number += 1
            }
            try FileManager.default.copyItem(at: imageURL, to: target)
            insertText("![\(imageURL.deletingPathExtension().lastPathComponent)](assets/\(target.lastPathComponent))", replacementRange: selectedRange())
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
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
    /// Number fixes that make each ordered list count up from its first item.
    static func renumbering(_ text: String) -> [(range: NSRange, value: String)] {
        let source = text as NSString
        let item = try! NSRegularExpression(pattern: #"^([ \t]*)(?:([0-9]{1,9})([.)])|[-*+])[ \t]"#)
        var lists: [(indent: Int, delimiter: String, next: Int)] = []
        var fixes: [(range: NSRange, value: String)] = []
        var fenced = false
        source.enumerateSubstrings(in: NSRange(location: 0, length: source.length), options: .byLines) { line, range, _, _ in
            guard let line else { return }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { fenced.toggle(); lists.removeAll(); return }
            guard !fenced, !trimmed.isEmpty else { return }
            let indent = line.prefix { $0 == " " || $0 == "\t" }.utf16.count
            guard let match = item.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)),
                  match.range(at: 2).location != NSNotFound else {
                // A bullet or paragraph at this depth ends the ordered lists it does not nest inside.
                while let last = lists.last, last.indent >= indent { lists.removeLast() }
                return
            }
            while let last = lists.last, last.indent > indent { lists.removeLast() }
            let number = Int((line as NSString).substring(with: match.range(at: 2))) ?? 1
            let delimiter = (line as NSString).substring(with: match.range(at: 3))
            if let last = lists.last, last.indent == indent, last.delimiter == delimiter {
                if number != last.next {
                    fixes.append((NSRange(location: range.location + match.range(at: 2).location, length: match.range(at: 2).length), "\(last.next)"))
                }
                lists[lists.count - 1].next += 1
            } else {
                if lists.last?.indent == indent { lists.removeLast() }
                lists.append((indent, delimiter, number + 1))
            }
        }
        return fixes
    }
}

struct MarkdownTable {
    struct Row {
        let start: Int
        let end: Int
        let cells: [NSRange]
        let separator: Bool
    }

    enum Move {
        case select(NSRange)
        case addRow(String, at: Int, caret: Int)
    }

    let rows: [Row]
    let current: Int

    static func containing(_ text: String, location: Int) -> Self? {
        let source = text as NSString
        guard location <= source.length else { return nil }
        let separator = try! NSRegularExpression(pattern: #"^\s*\|(?:\s*:?-+:?\s*\|)+\s*$"#)
        var parsed: [Row?] = []
        var starts: [Int] = []
        var offset = 0
        while offset < source.length {
            var start = 0, end = 0, contentsEnd = 0
            source.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: offset, length: 0))
            let line = source.substring(with: NSRange(location: start, length: contentsEnd - start)) as NSString
            var pipes: [Int] = []
            // ponytail: Escaped pipes are skipped; code spans with pipes need Markdown AST cell ranges.
            for index in 0..<line.length where line.character(at: index) == 124 {
                if index == 0 || line.character(at: index - 1) != 92 { pipes.append(index) }
            }
            let trimmed = (line as String).trimmingCharacters(in: .whitespaces)
            if pipes.count >= 3, trimmed.hasPrefix("|"), trimmed.hasSuffix("|") {
                let cells = zip(pipes, pipes.dropFirst()).map { left, right -> NSRange in
                    var first = left + 1, last = right
                    while first < last, UnicodeScalar(line.character(at: first)).map(CharacterSet.whitespaces.contains) ?? false { first += 1 }
                    while last > first, UnicodeScalar(line.character(at: last - 1)).map(CharacterSet.whitespaces.contains) ?? false { last -= 1 }
                    return NSRange(location: start + first, length: last - first)
                }
                parsed.append(Row(start: start, end: contentsEnd, cells: cells,
                                  separator: separator.firstMatch(in: line as String, range: NSRange(location: 0, length: line.length)) != nil))
            } else { parsed.append(nil) }
            starts.append(start)
            offset = end
        }
        guard let index = starts.indices.first(where: { starts[$0] <= location && (parsed[$0]?.end ?? starts[$0]) >= location }),
              parsed[index] != nil else { return nil }
        var first = index, last = index
        while first > 0, parsed[first - 1] != nil { first -= 1 }
        while last + 1 < parsed.count, parsed[last + 1] != nil { last += 1 }
        let rows = parsed[first...last].compactMap { $0 }
        guard rows.contains(where: \.separator) else { return nil }
        return Self(rows: rows, current: index - first)
    }

    static func blocks(in text: String) -> [Self] {
        // ponytail: Reparse on style changes; keep an indexed table AST if large notes make this slow.
        let source = text as NSString
        var result: [Self] = []
        var offset = 0
        while offset < source.length {
            if let table = containing(text, location: offset), table.rows.first?.start == offset {
                result.append(table)
                var end = 0
                source.getLineStart(nil, end: &end, contentsEnd: nil,
                                    for: NSRange(location: table.rows.last!.start, length: 0))
                offset = end
            } else {
                var end = 0
                source.getLineStart(nil, end: &end, contentsEnd: nil, for: NSRange(location: offset, length: 0))
                offset = end
            }
        }
        return result
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

struct MarkdownSourceMap {
    let lines: [String]
    let starts: [Int]

    init(_ source: String) {
        lines = source.components(separatedBy: "\n")
        var starts = [0]
        for line in lines.dropLast() { starts.append(starts.last! + (line as NSString).length + 1) }
        self.starts = starts
    }

    func range(_ range: Markdown.SourceRange) -> NSRange? {
        func offset(_ location: Markdown.SourceLocation) -> Int? {
            let line = location.line - 1
            guard lines.indices.contains(line), location.column > 0 else { return nil }
            let bytes = Array(lines[line].utf8)
            guard location.column - 1 <= bytes.count else { return nil }
            return starts[line] + (String(decoding: bytes.prefix(location.column - 1), as: UTF8.self) as NSString).length
        }
        guard let start = offset(range.lowerBound), let end = offset(range.upperBound), end >= start else { return nil }
        return NSRange(location: start, length: end - start)
    }
}
