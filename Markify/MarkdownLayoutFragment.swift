import AppKit

// Rendered-lens decorations are drawn by the layout fragment of the paragraph they belong to, so they move with the
// text through layout, scrolling and resizing. `NativeEditor.style` marks what to draw with these attributes;
// `MarkdownLayoutFragment` reads them in its own range. The pattern follows nodes-app/swift-markdown-engine
// (Apache-2.0); this is Markify's own implementation.

extension NSAttributedString.Key {
    /// `true` on a bullet marker whose glyph is hidden; the fragment draws a `•` in its place.
    static let markifyBullet = NSAttributedString.Key("MarkifyBullet")
    /// `String` on the digits of an ordered item: the counted number to draw with its delimiter.
    static let markifyListNumber = NSAttributedString.Key("MarkifyListNumber")
    /// `Bool` (checked) on a task's hidden marker; the fragment draws the checkbox.
    static let markifyTaskBox = NSAttributedString.Key("MarkifyTaskBox")
}

final class MarkdownLayoutFragment: NSTextLayoutFragment {
    /// The text view this fragment draws for, which supplies images, renders and theme.
    var textView: MarkdownTextView? { textLayoutManager?.textContainer?.textView as? MarkdownTextView }

    /// This fragment's text as a range of the document.
    var documentRange: NSRange? {
        guard let content = textLayoutManager?.textContentManager else { return nil }
        let start = content.offset(from: content.documentRange.location, to: rangeInElement.location)
        let end = content.offset(from: content.documentRange.location, to: rangeInElement.endLocation)
        guard start != NSNotFound, end != NSNotFound, end >= start else { return nil }
        return NSRange(location: start, length: end - start)
    }

    var textStorage: NSTextStorage? { (textLayoutManager?.textContentManager as? NSTextContentStorage)?.textStorage }

    override func draw(at point: CGPoint, in context: CGContext) {
        super.draw(at: point, in: context)
    }
}

/// Makes every paragraph of a `MarkdownTextView` lay out as a `MarkdownLayoutFragment`.
final class MarkdownLayoutDelegate: NSObject, NSTextLayoutManagerDelegate {
    func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: any NSTextLocation,
                           in textElement: NSTextElement) -> NSTextLayoutFragment {
        MarkdownLayoutFragment(textElement: textElement, range: textElement.elementRange)
    }
}
