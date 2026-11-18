import AppKit
import Testing
@testable import Markify

@MainActor struct LensSwitchTests {
    /// Switching lenses back and forth must leave the reading position where it was (the page used to creep each cycle).
    @Test func repeatedLensSwitchesDoNotMoveThePage() {
        var source = "# Title\n\n"
        for part in 0..<12 {
            source += "## Part \(part)\n\n" + String(repeating: "Some **bold** prose that wraps across a few lines of the column. ", count: 8)
                + "\n\n```sh\nrun --part \(part)\nrun --again\n```\n\n"
        }
        let (window, editor) = LayoutFragmentTests.makeEditor(source)
        _ = window
        let scroll = editor.enclosingScrollView!
        scroll.frame = NSRect(x: 0, y: 0, width: 980, height: 700)
        let heading = (source as NSString).range(of: "## Part 6").location
        editor.settleLayout(through: heading)
        let clip = scroll.contentView
        clip.scroll(to: NSPoint(x: 0, y: editor.textRect(NSRange(location: heading, length: 0)).minY - 300))
        scroll.reflectScrolledClipView(clip)

        func headingY(markdownLens: Bool) -> CGFloat {
            let native = NativeEditor(text: .constant(source), fileURL: nil, columnWidth: 640, markdownLens: markdownLens, findQuery: "", matchCase: false,
                                      selectedRange: .constant(NSRange(location: 0, length: 0)), textView: .constant(nil),
                                      onType: {}, onSlash: { _ in }, onSlashKey: { _, _ in false }, onSelectionRect: { _ in })
            editor.rendered = !markdownLens
            editor.preservingTopLine { _ in native.style(editor) }
            return editor.textRect(NSRange(location: heading, length: 0)).minY - clip.bounds.minY
        }
        let markdown = headingY(markdownLens: true), rendered = headingY(markdownLens: false)
        for _ in 0..<4 {
            #expect(abs(headingY(markdownLens: true) - markdown) < 1)
            #expect(abs(headingY(markdownLens: false) - rendered) < 1)
        }
    }
}
