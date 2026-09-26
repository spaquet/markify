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
    /// `CGFloat` beside `markifyListNumber`: how far right to draw it, so a list's numbers align on their last digit.
    static let markifyListNumberOffset = NSAttributedString.Key("MarkifyListNumberOffset")
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

    /// Markers sit in the text's left margin, a checkbox is taller than a hidden 10pt marker,
    /// and block decorations span the column, so the drawing surface spans the container's width.
    override var renderingSurfaceBounds: CGRect {
        // Also the paragraph spacing around the lines: block images, the footnotes rule and a diagram's error draw there.
        var bounds = super.renderingSurfaceBounds.union(CGRect(origin: .zero, size: layoutFragmentFrame.size))
        if let width = textLayoutManager?.textContainer?.size.width {
            bounds.origin.x = -layoutFragmentFrame.minX
            bounds.size.width = max(bounds.width, width)
        }
        return bounds
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        super.draw(at: point, in: context)
        guard let storage = textStorage, let range = documentRange, range.length > 0,
              NSMaxRange(range) <= storage.length, let view = textView else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        storage.enumerateAttributes(in: range) { attributes, run, _ in
            if attributes[.markifyBullet] != nil, let rect = self.rect(for: run, at: point) {
                let dot = NSAttributedString(string: "•", attributes: [.font: view.theme.ui(18), .foregroundColor: NSColor.secondaryLabelColor])
                let size = dot.size()
                dot.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
            }
            if let label = attributes[.markifyListNumber] as? String, let rect = self.rect(for: run, at: point) {
                let font = attributes[.font] as? NSFont ?? .systemFont(ofSize: 18)
                let offset = attributes[.markifyListNumberOffset] as? CGFloat ?? 0
                NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])
                    .draw(at: NSPoint(x: rect.minX + offset, y: rect.minY))
            }
            if let checked = attributes[.markifyTaskBox] as? Bool, let marker = self.rect(for: run, at: point) {
                Self.drawCheckbox(in: Self.checkboxRect(marker: marker), checked: checked, accent: view.theme.accent)
            }
        }
        // Block and inline decorations are drawn by the view in its own coordinates.
        context.translateBy(x: point.x - layoutFragmentFrame.minX - view.textContainerOrigin.x,
                            y: point.y - layoutFragmentFrame.minY - view.textContainerOrigin.y)
        view.drawDecorations(anchoredIn: range)
    }

    /// The first line segment of `run`, in the coordinates `draw(at:in:)` draws in.
    /// The same segments give `MarkdownTextView.textRect`, so drawing and hit-testing agree.
    func rect(for run: NSRange, at point: CGPoint) -> CGRect? {
        guard let manager = textLayoutManager, let content = manager.textContentManager,
              let start = content.location(content.documentRange.location, offsetBy: run.location),
              let end = content.location(start, offsetBy: max(run.length, 1)),
              let range = NSTextRange(location: start, end: end) else { return nil }
        var first: CGRect?
        manager.enumerateTextSegments(in: range, type: .standard, options: []) { _, frame, _, _ in
            first = frame
            return false
        }
        return first?.offsetBy(dx: point.x - layoutFragmentFrame.minX, dy: point.y - layoutFragmentFrame.minY)
    }

    // MARK: Task checkbox

    /// The checkbox square for a task whose hidden marker starts at `marker`; shared by drawing and clicks.
    static func checkboxRect(marker: CGRect) -> CGRect {
        CGRect(x: marker.minX + 2, y: marker.midY - 9, width: 18, height: 18)
    }

    static func drawCheckbox(in rect: CGRect, checked: Bool, accent: NSColor) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        if checked {
            accent.setFill()
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

/// Makes every paragraph of a `MarkdownTextView` lay out as a `MarkdownLayoutFragment`.
final class MarkdownLayoutDelegate: NSObject, NSTextLayoutManagerDelegate {
    func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: any NSTextLocation,
                           in textElement: NSTextElement) -> NSTextLayoutFragment {
        MarkdownLayoutFragment(textElement: textElement, range: textElement.elementRange)
    }
}
