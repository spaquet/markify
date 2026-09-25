import AppKit
import Markdown
import SwiftUI

struct NativeEditor: NSViewRepresentable {
    @Binding var text: String
    let fileURL: URL?
    let markdownLens: Bool
    let findQuery: String
    let matchCase: Bool
    @Binding var selectedRange: NSRange
    @Binding var textView: NSTextView?
    let onType: () -> Void
    let onSlash: (String?) -> Void
    let onSelectionRect: (CGRect) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.documentURL = fileURL
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
        matches("(?m)^(?:[ \\t]*)([-*+] |[0-9]+\\. |>[ \\t]?|[-*+] \\[ ?[xX]?\\] )") { match in marker(match.range(at: 1)) }
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
        matches("(?m)^\\|[^\\n]+\\|$") { match in
            guard !markdownLens else { return }
            storage.addAttributes([.font: NSFont.systemFont(ofSize: 14), .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.06)], range: match.range)
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
            let body = match.range(at: 1)
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            storage.addAttributes([.font: NSFont(name: "NewYork-Italic", size: 22) ?? NSFont.systemFont(ofSize: 22),
                                   .paragraphStyle: style], range: body)
            marker(NSRange(location: match.range.location, length: body.location - match.range.location))
            marker(NSRange(location: NSMaxRange(body), length: NSMaxRange(match.range) - NSMaxRange(body)))
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
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeEditor
        weak var editor: NSTextView?
        var lastLens = false
        var lastQuery = ""
        var lastMatchCase = false
        var isCreatingTitle = false
        init(_ parent: NativeEditor) { self.parent = parent }
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            if !isCreatingTitle, textView.string.isEmpty,
               let replacementString, !replacementString.isEmpty,
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
            let source = editor.string as NSString
            let caret = editor.selectedRange().location
            let line = source.lineRange(for: NSRange(location: min(caret, source.length), length: 0))
            let before = source.substring(with: NSRange(location: line.location, length: max(0, caret - line.location)))
            if before.hasPrefix("/") && !before.contains(" ") { parent.onSlash(String(before.dropFirst())) }
            else { parent.onSlash(nil) }
            parent.style(editor)
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let editor else { return }
            parent.selectedRange = editor.selectedRange()
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
    var rendered = true
    private var imageCache: [URL: NSImage] = [:]

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
            let rect = NSRect(x: 0, y: caption.minY - 268, width: bounds.width, height: 260)
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
