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
        let image = NSImage(size: NSSize(width: 640, height: 660))
        image.lockFocus()
        defer { image.unlockFocus() }
        editor.layoutSubtreeIfNeeded()
        // The first paint lays the text out; later paints, as when scrolling, reuse that layout.
        editor.drawOverlays(editor.visibleRect)
        let elapsed = ContinuousClock().measure { editor.drawOverlays(editor.visibleRect) }
        // Measured at 13 ms for 3,780 lines.
        #expect(elapsed < .milliseconds(50), "drawOverlays took \(elapsed)")
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
}
