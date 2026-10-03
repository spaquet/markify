import AppKit
import Testing
@testable import Markify

/// Rendered-lens decorations are drawn by `MarkdownLayoutFragment` from attributes `NativeEditor.style` sets.
@MainActor struct LayoutFragmentTests {
    static func makeEditor(_ source: String, markdownLens: Bool = false, fileURL: URL? = nil) -> (NSWindow, MarkdownTextView) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 1200), styleMask: [.titled], backing: .buffered, defer: false)
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.frame = scroll.bounds
        editor.isVerticallyResizable = true
        editor.textContainer?.widthTracksTextView = true
        editor.textContainerInset = NSSize(width: 0, height: 40)
        scroll.documentView = editor
        window.contentView = scroll
        editor.string = source
        editor.documentURL = fileURL
        editor.rendered = !markdownLens
        NativeEditor(text: .constant(source), fileURL: fileURL, columnWidth: 640, markdownLens: markdownLens, findQuery: "", matchCase: false,
                     selectedRange: .constant(NSRange(location: 0, length: 0)),
                     textView: .constant(nil), onType: {}, onSlash: { _ in }, onSlashKey: { _, _ in false }, onSelectionRect: { _ in })
            .style(editor)
        if let manager = editor.textLayoutManager { manager.ensureLayout(for: manager.documentRange) }
        return (window, editor)
    }

    @Test func paragraphsLayOutAsMarkdownFragments() {
        let (window, editor) = Self.makeEditor("# Title\n\nBody text.\n")
        _ = window
        let manager = editor.textLayoutManager!
        var fragments: [NSTextLayoutFragment] = []
        manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: []) { fragments.append($0); return true }
        #expect(!fragments.isEmpty)
        #expect(fragments.allSatisfy { $0 is MarkdownLayoutFragment })
        #expect((fragments.first as? MarkdownLayoutFragment)?.documentRange?.location == 0)
    }

    @Test(arguments: [CGFloat(18), CGFloat(24)]) func caretFontFollowsVisibleTextAfterSelectionAndRestyling(proseSize: CGFloat) throws {
        let source = "# Title\n## Subtitle\nBody `code`\n"
        let (window, editor) = Self.makeEditor(source)
        _ = window
        editor.isRichText = false
        for markdownLens in [false, true] {
            let native = NativeEditor(text: .constant(source), fileURL: nil, columnWidth: 640, markdownLens: markdownLens, findQuery: "", matchCase: false,
                                      selectedRange: .constant(NSRange(location: 0, length: 0)), textView: .constant(nil),
                                      onType: {}, onSlash: { _ in }, onSlashKey: { _, _ in false }, onSelectionRect: { _ in }, theme: EditorTheme(proseSize: proseSize))
            let coordinator = native.makeCoordinator()
            coordinator.editor = editor
            editor.delegate = coordinator
            native.style(editor)
            let ns = source as NSString
            for (location, size) in [(0, markdownLens ? 14 : 36), (ns.range(of: "Title").location + 5, markdownLens ? 16 : 36),
                                     (ns.range(of: "Subtitle").location + 2, markdownLens ? 16 : 22),
                                     (ns.range(of: "Body").location + 2, markdownLens ? 14 : 18),
                                     (ns.range(of: "code").location + 2, markdownLens ? 14 : 15), (ns.length, markdownLens ? 14 : 18)] {
                editor.setSelectedRange(NSRange(location: location, length: 0))
                coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: editor))
                #expect((editor.typingAttributes[.font] as? NSFont)?.pointSize == CGFloat(size) * native.theme.scale)
                native.style(editor)
                #expect((editor.typingAttributes[.font] as? NSFont)?.pointSize == CGFloat(size) * native.theme.scale)
            }
        }
        #expect(editor.string == source)
    }

    @Test(arguments: [CGFloat(18), CGFloat(24)]) func emptyDocumentCaretMatchesPlaceholder(proseSize: CGFloat) throws {
        let (window, editor) = Self.makeEditor("")
        _ = window
        editor.isRichText = false
        for markdownLens in [false, true] {
            let native = NativeEditor(text: .constant(""), fileURL: nil, columnWidth: 640, markdownLens: markdownLens, findQuery: "", matchCase: false,
                                      selectedRange: .constant(NSRange(location: 0, length: 0)), textView: .constant(nil),
                                      onType: {}, onSlash: { _ in }, onSlashKey: { _, _ in false }, onSelectionRect: { _ in }, theme: EditorTheme(proseSize: proseSize))
            let coordinator = native.makeCoordinator()
            coordinator.editor = editor
            editor.string = ""
            native.style(editor)
            #expect(editor.typingAttributes[.font] as? NSFont == native.theme.prose(36, bold: true))
            coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: editor))
            #expect(editor.typingAttributes[.font] as? NSFont == native.theme.prose(36, bold: true))
            #expect(editor.string.isEmpty)
            editor.string = "Body"
            native.style(editor)
            #expect(editor.typingAttributes[.font] as? NSFont == (markdownLens ? native.theme.mono(14) : native.theme.prose(18)))
            editor.string = ""
            native.style(editor)
            #expect(editor.typingAttributes[.font] as? NSFont == native.theme.prose(36, bold: true))
        }
    }

    @Test(arguments: ["", "Intro\n\n"]) func blockImageDrawsFromDocumentFolder(prefix: String) throws {
        let source = prefix + "![Hero](docs/images/og-image.jpg)\n"
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let (window, editor) = Self.makeEditor(source, fileURL: root.appendingPathComponent("README.md"))
        _ = window
        let fragment = try #require(Self.fragment(editor, at: (prefix as NSString).length))
        let (rep, _) = Self.render(fragment)
        #expect(Self.inked(rep, in: CGRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh)) > 20_000)
    }

    @Test func htmlBlockDrawsLocalImageWithoutChangingSource() throws {
        let source = """
        <p align="center">
          <a href="https://spaquet.github.io/markify/"><img src="docs/images/og-image.jpg" alt="Markify — One page, two lenses" width="100%"></a>
        </p>

        # <img src="docs/images/app-icon.png" alt="" width="36" align="top"> Markify
        """
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let (window, editor) = Self.makeEditor(source, fileURL: root.appendingPathComponent("README.md"))
        _ = window
        #expect(editor.string == source)
        let html = try #require(editor.htmlBlocks[0])
        #expect(html.text.size().height > 100)
        #expect(!editor.inlineHTMLImages.isEmpty)
        let fragment = try #require(Self.fragment(editor, at: 0))
        let (rep, _) = Self.render(fragment)
        #expect(Self.inked(rep, in: CGRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh)) > 20_000)
    }

    static func fragment(_ editor: MarkdownTextView, at location: Int) -> MarkdownLayoutFragment? {
        let manager = editor.textLayoutManager!
        guard let content = manager.textContentManager,
              let textLocation = content.location(content.documentRange.location, offsetBy: location) else { return nil }
        return manager.textLayoutFragment(for: textLocation) as? MarkdownLayoutFragment
    }

    /// Draws one fragment into a bitmap and returns it, with the draw origin used.
    static func render(_ fragment: MarkdownLayoutFragment) -> (NSBitmapImageRep, CGPoint) {
        let surface = fragment.renderingSurfaceBounds
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ceil(surface.width)), pixelsHigh: Int(ceil(surface.height)),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
        // Flip so y grows downward, as TextKit draws fragments.
        context.translateBy(x: 0, y: surface.height)
        context.scaleBy(x: 1, y: -1)
        let point = CGPoint(x: -surface.minX, y: -surface.minY)
        fragment.draw(at: point, in: context)
        return (rep, point)
    }

    /// Opaque pixels inside `rect` (in draw coordinates, y down).
    static func inked(_ rep: NSBitmapImageRep, in rect: CGRect) -> Int {
        var count = 0
        for x in Int(rect.minX)..<Int(rect.maxX) {
            for y in Int(rect.minY)..<Int(rect.maxY) where x >= 0 && y >= 0 && x < rep.pixelsWide && y < rep.pixelsHigh {
                if (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.2 { count += 1 }
            }
        }
        return count
    }

    @Test func styleMarksListDecorations() {
        let source = "- bullet\n- [x] done\n\n3. three\n4. four\n"
        let (window, editor) = Self.makeEditor(source)
        _ = window
        let storage = editor.textStorage!
        let ns = source as NSString
        #expect(storage.attribute(.markifyBullet, at: 0, effectiveRange: nil) is NSFont)
        #expect(storage.attribute(.markifyTaskBox, at: ns.range(of: "- [x]").location, effectiveRange: nil) as? Bool == true)
        #expect(storage.attribute(.markifyListNumber, at: ns.range(of: "3.").location, effectiveRange: nil) as? String == "3.")
        #expect(storage.attribute(.markifyListNumber, at: ns.range(of: "4.").location, effectiveRange: nil) as? String == "4.")
        // The Markdown lens shows the syntax itself.
        let (window2, markdown) = Self.makeEditor(source, markdownLens: true)
        _ = window2
        #expect(markdown.textStorage!.attribute(.markifyBullet, at: 0, effectiveRange: nil) == nil)
    }

    @Test func fragmentDrawsTheCheckboxWhereClicksLand() {
        let source = "Intro\n\n- [x] done\n"
        let (window, editor) = Self.makeEditor(source)
        _ = window
        let marker = (source as NSString).range(of: "- [x]").location
        let fragment = Self.fragment(editor, at: marker)!
        let (rep, point) = Self.render(fragment)
        let markerRect = fragment.rect(for: NSRange(location: marker, length: 1), at: point)!
        let box = MarkdownLayoutFragment.checkboxRect(marker: markerRect)
        #expect(Self.inked(rep, in: box.insetBy(dx: 4, dy: 4)) > 60, "the checked box is filled")
        // The click rect is the drawn rect, moved from fragment to view coordinates.
        let offset = CGPoint(x: fragment.layoutFragmentFrame.minX - point.x + editor.textContainerOrigin.x,
                             y: fragment.layoutFragmentFrame.minY - point.y + editor.textContainerOrigin.y)
        let viewBox = MarkdownLayoutFragment.checkboxRect(marker: editor.textRect(NSRange(location: marker, length: 1)))
        #expect(abs(viewBox.minX - (box.minX + offset.x)) < 0.5 && abs(viewBox.minY - (box.minY + offset.y)) < 0.5)
    }

    @Test func fragmentDrawsBulletsAndCountedNumbers() {
        let source = "- bullet\n\n7. seven\n9. nine\n"
        let (window, editor) = Self.makeEditor(source)
        _ = window
        let ns = source as NSString
        for needle in ["-", "9."] {
            let location = ns.range(of: needle).location
            let fragment = Self.fragment(editor, at: location)!
            let (rep, point) = Self.render(fragment)
            let rect = fragment.rect(for: NSRange(location: location, length: needle.count), at: point)!
            // The source glyphs are clear, so any ink over them is the drawn bullet or number ("8." for the second item).
            #expect(Self.inked(rep, in: rect.insetBy(dx: -2, dy: 0)) > 10, "\(needle) is drawn")
        }
    }

    @Test func codeBlocksDrawOneRoundedBoxWithPadding() {
        let source = "Intro\n\n```swift\nlet a = 1\nlet b = 2\n```\n\nAfter\n"
        let (window, editor) = Self.makeEditor(source)
        _ = window
        let ns = source as NSString
        let firstLine = Self.fragment(editor, at: ns.range(of: "let a").location)!
        let secondLine = Self.fragment(editor, at: ns.range(of: "let b").location)!
        #expect(firstLine !== secondLine)
        let (rep, point) = Self.render(firstLine)
        // The box starts at the column's left edge, left of the indented code, and its top padding is filled.
        let text = firstLine.rect(for: NSRange(location: ns.range(of: "let a").location, length: 1), at: point)!
        #expect(text.minX - (point.x - firstLine.layoutFragmentFrame.minX) >= 17, "code sits inside the box's horizontal padding")
        #expect(Self.inked(rep, in: CGRect(x: point.x - firstLine.layoutFragmentFrame.minX + 30, y: point.y + 4, width: 40, height: 6)) > 100, "top padding is filled")
        // The first line rounds its top corners: the very corner pixel stays empty.
        #expect(Self.inked(rep, in: CGRect(x: point.x - firstLine.layoutFragmentFrame.minX, y: point.y, width: 2, height: 2)) == 0)
        // Text after the block is outside it.
        let after = Self.fragment(editor, at: ns.range(of: "After").location)!
        #expect(editor.textStorage!.attribute(.markifyBlockFill, at: ns.range(of: "After").location, effectiveRange: nil) == nil)
        _ = after
    }

    @Test func selectedCodeStaysVisibleThroughTheFill() {
        let source = "```\nselected words here\n```\n"
        let (window, editor) = Self.makeEditor(source)
        _ = window
        let word = (source as NSString).range(of: "words")
        editor.setSelectedRange(word)
        let fragment = Self.fragment(editor, at: word.location)!
        let (rep, point) = Self.render(fragment)
        let rect = fragment.rect(for: word, at: point)!
        // Under the selection the fill is cut out; only the glyphs themselves are inked.
        let total = Int(rect.width) * Int(rect.height)
        #expect(Self.inked(rep, in: rect) < total / 2)
        let beside = rect.offsetBy(dx: rect.width + 60, dy: 0)
        #expect(Self.inked(rep, in: beside) > Int(beside.width * beside.height) * 3 / 4, "unselected code keeps its fill")
    }

    /// The parse is cached by text version; edits made the way the app makes them must invalidate it.
    @Test func modelFollowsEveryKindOfEdit() {
        let (window, editor) = Self.makeEditor("First\n")
        _ = window
        #expect(editor.model.tables.isEmpty)
        editor.string = "| a | b |\n| - | - |\n| 1 | 2 |\n"
        #expect(editor.model.tables.count == 1, "setting the string")
        editor.insertText("\n# Heading\n", replacementRange: NSRange(location: (editor.string as NSString).length, length: 0))
        #expect(editor.model.spans.contains { if case .heading = $0.kind { true } else { false } }, "typing")
        editor.textStorage?.replaceCharacters(in: NSRange(location: 0, length: (editor.string as NSString).length), with: "Plain\n")
        #expect(editor.model.tables.isEmpty, "editing the storage directly")
    }
}

/// Inline `$…$` math is typeset in the Rendered lens and shows its LaTeX while the caret is in it.
@MainActor struct InlineMathTests {
    static let source = "Energy $E = mc^2$ today.\n\n$x^2$\n\nPlain line.\n"

    @Test func formulasAreTypesetInTheRoomTheirSourceLeaves() throws {
        let (window, editor) = LayoutFragmentTests.makeEditor(Self.source)
        _ = window
        let ns = Self.source as NSString
        let span = ns.range(of: "$E = mc^2$")
        let formula = try #require(editor.inlineFormulas[span.location], "The formula is typeset")
        // The LaTeX is hidden and the text after it starts where the formula ends.
        let storage = editor.textStorage!
        #expect(storage.attribute(.foregroundColor, at: ns.range(of: "^2").location, effectiveRange: nil) as? NSColor == .clear)
        let start = editor.textRect(NSRange(location: span.location, length: 1)).minX
        let after = editor.textRect(NSRange(location: NSMaxRange(span), length: 1)).minX
        #expect(abs(after - start - formula.width) < 2, "Room for the formula: \(after - start) vs \(formula.width)")

        // It sits on the line's baseline and draws ink in its room.
        let baseline = try #require(editor.baselineY(at: span.location))
        let text = editor.textRect(NSRange(location: 0, length: 6))
        #expect(baseline > text.minY && baseline < text.maxY)
        let fragment = try #require(LayoutFragmentTests.fragment(editor, at: span.location))
        let (rep, point) = LayoutFragmentTests.render(fragment)
        let shift = CGPoint(x: point.x - fragment.layoutFragmentFrame.minX - editor.textContainerOrigin.x,
                            y: point.y - fragment.layoutFragmentFrame.minY - editor.textContainerOrigin.y)
        let room = CGRect(x: start + shift.x + 1, y: baseline - formula.metrics.baseline + shift.y, width: formula.width - 2, height: formula.metrics.height)
        #expect(LayoutFragmentTests.inked(rep, in: room) > 40, "The formula is drawn")

        // A line holding only a formula keeps the text's height.
        let alone = ns.range(of: "$x^2$")
        let plain = ns.range(of: "Plain line.")
        #expect(abs(editor.textRect(NSRange(location: alone.location, length: 1)).height - editor.textRect(NSRange(location: plain.location, length: 1)).height) < 2)
    }

    @Test func theCaretInAFormulaShowsItsSource() {
        let (window, editor) = LayoutFragmentTests.makeEditor(Self.source)
        _ = window
        let span = (Self.source as NSString).range(of: "$E = mc^2$")
        editor.setSelectedRange(NSRange(location: span.location + 3, length: 0))
        #expect(editor.editedFormula == span.location)
        NativeEditor(text: .constant(Self.source), fileURL: nil, columnWidth: 640, markdownLens: false, findQuery: "", matchCase: false,
                     selectedRange: .constant(NSRange(location: 0, length: 0)),
                     textView: .constant(nil), onType: {}, onSlash: { _ in }, onSlashKey: { _, _ in false }, onSelectionRect: { _ in })
            .style(editor)
        #expect(editor.inlineFormulas[span.location] == nil, "Not typeset while edited")
        let color = editor.textStorage!.attribute(.foregroundColor, at: (Self.source as NSString).range(of: "^2").location, effectiveRange: nil) as? NSColor
        #expect(color != .clear, "The LaTeX shows")
        let dollar = editor.textStorage!.attribute(.foregroundColor, at: span.location, effectiveRange: nil) as? NSColor
        #expect(dollar == .tertiaryLabelColor, "Its dollars show, dimmed")
        #expect(editor.inlineFormulas[(Self.source as NSString).range(of: "$x^2$").location] != nil, "Other formulas stay typeset")
    }
}
