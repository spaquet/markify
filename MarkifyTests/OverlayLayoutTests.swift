import AppKit
import Testing
@testable import Markify

/// Overlays drawn over the text must sit on the rows and blocks they belong to, even when positions
/// are read before TextKit 2 has laid out the text above them.
@MainActor struct OverlayLayoutTests {
    static let source: String = {
        let fixture = EditorFixtureTests.source
        return String(fixture[fixture.range(of: "- bullet one")!.lowerBound...])
    }()

    func makeEditor() -> (NSWindow, MarkdownTextView) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 660), styleMask: [.titled], backing: .buffered, defer: false)
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.frame = scroll.bounds
        editor.isVerticallyResizable = true
        editor.textContainer?.widthTracksTextView = true
        editor.textContainerInset = NSSize(width: 0, height: 40)
        editor.autoresizingMask = [.width]
        scroll.documentView = editor
        window.contentView = scroll
        editor.string = Self.source
        return (window, editor)
    }

    func style(_ editor: MarkdownTextView) {
        NativeEditor(text: .constant(Self.source), fileURL: nil, columnWidth: 640, markdownLens: false, findQuery: "", matchCase: false,
                     selectedRange: .constant(NSRange(location: 0, length: 0)),
                     textView: .constant(nil), onType: {}, onSlash: { _ in }, onSlashKey: { _, _ in false }, onSelectionRect: { _ in })
            .style(editor)
    }

    /// Where a row really is once all of the text is laid out (see `textRectMatchesFirstRectInView`).
    func settledY(_ editor: MarkdownTextView, _ location: Int) -> CGFloat {
        if let manager = editor.textLayoutManager { manager.ensureLayout(for: manager.documentRange) }
        return editor.textRect(NSRange(location: location, length: 1)).minY
    }

    /// Right-clicking a cell offers the table commands, and they act on the cell being edited.
    @Test func tableCellsOfferRowAndColumnCommands() throws {
        let (window, editor) = makeEditor()
        editor.string = "| A | B |\n| --- | --- |\n| C | D |"
        editor.refreshTables()
        let field = try #require(editor.tableOverlays[1]?.fields.last)
        let event = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                     windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        #expect(field.menu(for: event)?.items.map(\.title).contains("Insert Row Above") == true)
        #expect(window.makeFirstResponder(field))
        let fieldEditor = try #require(field.currentEditor() as? NSTextView)
        #expect(fieldEditor.menu(for: event)?.items.first?.title == "Insert Row Above")
        #expect(editor.tableLocation == (editor.string as NSString).range(of: "D").location)
        #expect(editor.editTable(.insertColumnRight))
        #expect(editor.string == "| A | B |  |\n| --- | --- | --- |\n| C | D |  |")
        #expect(window.firstResponder === editor)
    }

    /// Rows below the visible area still get their real position; `firstRect` answers zero for them.
    @Test func tableOverlaysBelowTheFoldSitOnTheirRows() async throws {
        let (window, editor) = makeEditor()
        window.setContentSize(NSSize(width: 900, height: 300))
        (window.contentView as? NSScrollView)?.documentView?.setFrameSize(NSSize(width: 900, height: editor.frame.height))
        style(editor)
        editor.refreshTables()
        let rows = MarkdownTable.blocks(in: editor.model).flatMap { $0.rows.filter { !$0.separator } }
        #expect(editor.tableOverlays.count == rows.count)
        var previous = -CGFloat.infinity
        for (index, row) in rows.enumerated() {
            let overlay = editor.tableOverlays[index]?.frame.minY ?? -1
            #expect(abs(overlay - settledY(editor, row.start)) < 1, "row \(index)")
            #expect(overlay > previous, "row \(index) below the one before")
            previous = overlay
        }
    }

    /// Painting the visible part of a long note stays fast even though positions come from the layout manager.
    @Test func paintingALargeDocumentStaysFast() {
        let large = Array(repeating: EditorFixtureTests.source, count: 60).joined(separator: "\n")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 660), styleMask: [.titled], backing: .buffered, defer: false)
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.frame = scroll.bounds
        editor.isVerticallyResizable = true
        editor.textContainer?.widthTracksTextView = true
        scroll.documentView = editor
        window.contentView = scroll
        editor.string = large
        NativeEditor(text: .constant(large), fileURL: nil, columnWidth: 640, markdownLens: false, findQuery: "", matchCase: false,
                     selectedRange: .constant(NSRange(location: 0, length: 0)),
                     textView: .constant(nil), onType: {}, onSlash: { _ in }, onSlashKey: { _, _ in false }, onSelectionRect: { _ in })
            .style(editor)
        editor.layoutSubtreeIfNeeded()
        let manager = editor.textLayoutManager!
        manager.ensureLayout(for: CGRect(x: 0, y: 0, width: 640, height: 660))
        var visible: [MarkdownLayoutFragment] = []
        manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: [.ensuresLayout]) { fragment in
            guard fragment.layoutFragmentFrame.minY < 660 else { return false }
            if let fragment = fragment as? MarkdownLayoutFragment { visible.append(fragment) }
            return true
        }
        #expect(!visible.isEmpty)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 700, pixelsHigh: 700, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
        func paint() {
            for fragment in visible {
                context.saveGState()
                fragment.draw(at: fragment.layoutFragmentFrame.origin, in: context)
                context.restoreGState()
            }
        }
        // The first paint renders math and loads images; later paints, as when scrolling, reuse them.
        paint()
        let elapsed = ContinuousClock().measure { paint() }
        #expect(elapsed < .milliseconds(50), "painting the visible fragments took \(elapsed)")
    }

    /// Where `firstRect` can answer (text in view), the layout-manager rect agrees with it.
    @Test func textRectMatchesFirstRectInView() {
        let (window, editor) = makeEditor()
        window.setContentSize(NSSize(width: 980, height: 3000))
        (window.contentView as? NSScrollView)?.documentView?.setFrameSize(NSSize(width: 980, height: 3000))
        style(editor)
        editor.layoutSubtreeIfNeeded()
        if let manager = editor.textLayoutManager { manager.ensureLayout(for: manager.documentRange) }
        for span in editor.model.spans {
            let range = NSRange(location: span.range.location, length: 1)
            let screen = editor.firstRect(forCharacterRange: range, actualRange: nil)
            guard screen != .zero else { continue }
            let old = editor.convert(window.convertFromScreen(screen), from: nil)
            let new = editor.textRect(range)
            #expect(abs(old.minY - new.minY) < 1 && abs(old.minX - new.minX) < 1 && abs(old.height - new.height) < 1, "\(span.kind): \(old) vs \(new)")
        }
    }

    @Test func tableOverlaysSitOnTheirRows() {
        let (window, editor) = makeEditor()
        _ = window
        style(editor)
        editor.refreshTables()
        let rows = MarkdownTable.blocks(in: editor.model).flatMap { $0.rows.filter { !$0.separator } }
        #expect(editor.tableOverlays.count == rows.count)
        for (index, row) in rows.enumerated() {
            let overlay = editor.tableOverlays[index]?.frame.minY ?? -1
            #expect(abs(overlay - settledY(editor, row.start)) < 1, "row \(index)")
        }
    }

    /// Styling can run before the view is in a window; the overlays appear once it is.
    @Test func tablesStyledBeforeTheWindowStillGetOverlays() async throws {
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.frame = NSRect(x: 0, y: 0, width: 640, height: 800)
        editor.string = Self.source
        style(editor)
        try await Task.sleep(for: .milliseconds(50))
        #expect(editor.tableOverlays.isEmpty)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = editor
        try await Task.sleep(for: .milliseconds(50))
        #expect(editor.tableOverlays.count == 3)
    }
}

/// Issue #8: ticking a task must not move the page.
@MainActor struct TaskToggleScrollTests {
    /// A document window supplies the undo manager in the app; a bare test window has none.
    @MainActor final class Undo: NSObject, NSTextViewDelegate {
        let manager = UndoManager()
        func undoManager(for view: NSTextView) -> UndoManager? { manager }
    }

    static let source = (1...80).map { "Paragraph \($0) with enough words to fill a line of the page." }.joined(separator: "\n\n")
        + "\n\n- [ ] Far down task\n- [x] Done task\n"

    @Test func tickingATaskKeepsThePagePosition() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 660), styleMask: [.titled], backing: .buffered, defer: false)
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.frame = scroll.bounds
        editor.isVerticallyResizable = true
        editor.textContainer?.widthTracksTextView = true
        editor.textContainerInset = NSSize(width: 0, height: 40)
        editor.autoresizingMask = [.width]
        scroll.documentView = editor
        window.contentView = scroll
        editor.string = Self.source
        let undoDelegate = Undo()
        editor.delegate = undoDelegate
        editor.allowsUndo = true
        NativeEditor(text: .constant(Self.source), fileURL: nil, columnWidth: 640, markdownLens: false, findQuery: "", matchCase: false,
                     selectedRange: .constant(NSRange(location: 0, length: 0)),
                     textView: .constant(nil), onType: {}, onSlash: { _ in }, onSlashKey: { _, _ in false }, onSelectionRect: { _ in })
            .style(editor)
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        if let manager = editor.textLayoutManager { manager.ensureLayout(for: manager.documentRange) }
        editor.layoutSubtreeIfNeeded()

        let task = (Self.source as NSString).range(of: "- [ ] Far down task")
        editor.scrollRangeToVisible(task)
        let before = scroll.contentView.bounds.origin.y
        #expect(before > 500, "The task sits far below the top")

        let marker = editor.textRect(NSRange(location: task.location, length: 1))
        let box = MarkdownLayoutFragment.checkboxRect(marker: marker)
        let point = editor.convert(NSPoint(x: box.midX, y: box.midY), to: nil)
        let click = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
                                                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        editor.mouseDown(with: click)
        editor.layoutSubtreeIfNeeded()

        #expect(editor.string.contains("- [x] Far down task"), "The click ticks the task")
        #expect(abs(scroll.contentView.bounds.origin.y - before) < 1, "The page stays where it was")
        #expect(editor.selectedRange() == NSRange(location: 0, length: 0), "The caret stays where it was")

        // Undo groups close at the end of the event; undoing inside it would undo nothing.
        let undo = try #require(editor.undoManager)
        if undo.groupingLevel > 0 { undo.endUndoGrouping() }
        #expect(undo.canUndo, "Ticking is undoable")
        undo.undo()
        #expect(editor.string.contains("- [ ] Far down task"), "Undo unticks the task")
        withExtendedLifetime(undoDelegate) {}
    }
}
