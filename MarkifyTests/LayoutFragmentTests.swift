import AppKit
import Testing
@testable import Markify

/// Rendered-lens decorations are drawn by `MarkdownLayoutFragment` from attributes `NativeEditor.style` sets.
@MainActor struct LayoutFragmentTests {
    static func makeEditor(_ source: String, markdownLens: Bool = false) -> (NSWindow, MarkdownTextView) {
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
        editor.rendered = !markdownLens
        NativeEditor(text: .constant(source), fileURL: nil, columnWidth: 640, markdownLens: markdownLens, findQuery: "", matchCase: false,
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
}
