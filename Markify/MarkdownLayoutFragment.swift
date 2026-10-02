import AppKit

// Rendered-lens decorations are drawn by the layout fragment of the paragraph they belong to, so they move with the
// text through layout, scrolling and resizing. `NativeEditor.style` marks what to draw with these attributes;
// `MarkdownLayoutFragment` reads them in its own range. The attributes carry everything the fragment needs (fonts,
// colors, zoomed sizes): TextKit calls `draw(at:in:)` outside the main actor, so it never reads the view's state. The pattern follows nodes-app/swift-markdown-engine
// (Apache-2.0); this is Markify's own implementation.

extension NSAttributedString.Key {
    /// `NSFont` on a bullet marker whose glyph is hidden; the fragment draws a `•` in that font in its place.
    static let markifyBullet = NSAttributedString.Key("MarkifyBullet")
    /// `String` on the digits of an ordered item: the counted number to draw with its delimiter.
    static let markifyListNumber = NSAttributedString.Key("MarkifyListNumber")
    /// `CGFloat` beside `markifyListNumber`: how far right to draw it, so a list's numbers align on their last digit.
    static let markifyListNumberOffset = NSAttributedString.Key("MarkifyListNumberOffset")
    /// `Bool` (checked) on a task's hidden marker; the fragment draws the checkbox.
    static let markifyTaskBox = NSAttributedString.Key("MarkifyTaskBox")
    /// `NSColor` beside `markifyTaskBox`: the fill of a checked box.
    static let markifyTaskAccent = NSAttributedString.Key("MarkifyTaskAccent")
    /// `MarkdownBlockFill` on each line of a code block or callout; the fragment paints its slice of the rounded box.
    static let markifyBlockFill = NSAttributedString.Key("MarkifyBlockFill")
    /// `MarkdownGuides` on a table of contents line; the fragment draws a vertical line for each level above it.
    static let markifyGuides = NSAttributedString.Key("MarkifyGuides")
}

/// Tree guides on an indented table of contents entry: one hairline per enclosing level, the full height of the line,
/// so consecutive entries join into continuous lines.
final class MarkdownGuides: NSObject {
    let count: Int
    /// Where the top level's text starts, and the indent per level, zoom included.
    let origin: CGFloat
    let step: CGFloat
    let color: NSColor

    init(count: Int, origin: CGFloat, step: CGFloat, color: NSColor) {
        self.count = count
        self.origin = origin
        self.step = step
        self.color = color
    }

    /// The x of each guide in the text container: just inside the start of each enclosing level's text.
    var positions: [CGFloat] { (0..<count).map { origin + CGFloat($0) * step + 4 } }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? MarkdownGuides else { return false }
        return count == other.count && origin == other.origin && step == other.step && color == other.color
    }

    override var hash: Int { count ^ step.hashValue }
}

/// A rounded box behind a block's lines. Each line's fragment paints its slice: the first rounds the top corners,
/// the last the bottom ones, and the paragraph spacing they add is the box's vertical padding.
final class MarkdownBlockFill: NSObject {
    let color: NSColor
    /// Corner radius, zoom included.
    let radius: CGFloat
    /// Horizontal and vertical space between the box and its text, before zoom.
    let padding: NSSize
    let first: Bool
    let last: Bool

    init(color: NSColor, radius: CGFloat, padding: NSSize, first: Bool = true, last: Bool = true) {
        self.color = color
        self.radius = radius
        self.padding = padding
        self.first = first
        self.last = last
    }

    func edge(first: Bool, last: Bool) -> MarkdownBlockFill {
        MarkdownBlockFill(color: color, radius: radius, padding: padding, first: first, last: last)
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? MarkdownBlockFill else { return false }
        return color == other.color && radius == other.radius && padding == other.padding && first == other.first && last == other.last
    }

    override var hash: Int { radius.hashValue ^ first.hashValue ^ (last.hashValue << 1) }
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
        guard let storage = textStorage, let range = documentRange, range.length > 0,
              NSMaxRange(range) <= storage.length, let view = textView else { return super.draw(at: point, in: context) }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        if let fill = storage.attribute(.markifyBlockFill, at: range.location, effectiveRange: nil) as? MarkdownBlockFill {
            drawFill(fill, at: point)
        }
        super.draw(at: point, in: context)
        if let guides = storage.attribute(.markifyGuides, at: range.location, effectiveRange: nil) as? MarkdownGuides {
            guides.color.setFill()
            for x in guides.positions {
                NSRect(x: point.x - layoutFragmentFrame.minX + x, y: point.y, width: 1, height: layoutFragmentFrame.height).fill()
            }
        }
        storage.enumerateAttributes(in: range) { attributes, run, _ in
            if let font = attributes[.markifyBullet] as? NSFont, let rect = self.rect(for: run, at: point) {
                let dot = NSAttributedString(string: "•", attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])
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
                Self.drawCheckbox(in: Self.checkboxRect(marker: marker), checked: checked,
                                  accent: attributes[.markifyTaskAccent] as? NSColor ?? .controlAccentColor)
            }
        }
        // Block and inline decorations are drawn by the view in its own coordinates, from its caches of images and
        // renders. NSTextView draws its fragments on the main thread inside its own draw(_:); off it, skip them.
        guard Thread.isMainThread else { return }
        let origin = MainActor.assumeIsolated { view.textContainerOrigin }
        context.translateBy(x: point.x - layoutFragmentFrame.minX - origin.x, y: point.y - layoutFragmentFrame.minY - origin.y)
        MainActor.assumeIsolated { view.drawDecorations(anchoredIn: range) }
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

    // MARK: Block fill

    /// This line's slice of a block's rounded box, across the column and the fragment's full height,
    /// leaving any selected text uncovered so its highlight, drawn underneath, stays visible.
    private func drawFill(_ fill: MarkdownBlockFill, at point: CGPoint) {
        let width = textLayoutManager?.textContainer?.size.width ?? layoutFragmentFrame.width
        let box = CGRect(x: point.x - layoutFragmentFrame.minX, y: point.y, width: width, height: layoutFragmentFrame.height)
        let radius = min(fill.radius, box.height / 2, box.width / 2)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: box.minX, y: box.midY))
        path.appendArc(from: NSPoint(x: box.minX, y: box.minY), to: NSPoint(x: box.midX, y: box.minY), radius: fill.first ? radius : 0)
        path.appendArc(from: NSPoint(x: box.maxX, y: box.minY), to: NSPoint(x: box.maxX, y: box.midY), radius: fill.first ? radius : 0)
        path.appendArc(from: NSPoint(x: box.maxX, y: box.maxY), to: NSPoint(x: box.midX, y: box.maxY), radius: fill.last ? radius : 0)
        path.appendArc(from: NSPoint(x: box.minX, y: box.maxY), to: NSPoint(x: box.minX, y: box.midY), radius: fill.last ? radius : 0)
        path.close()
        for selected in selectionRects(at: point) {
            path.append(NSBezierPath(rect: selected.intersection(box)))
        }
        path.windingRule = .evenOdd
        fill.color.setFill()
        path.fill()
    }

    /// Selected text in this fragment, in draw coordinates.
    private func selectionRects(at point: CGPoint) -> [CGRect] {
        guard let manager = textLayoutManager else { return [] }
        var rects: [CGRect] = []
        for selection in manager.textSelections {
            for selected in selection.textRanges where !selected.isEmpty {
                guard let overlap = selected.intersection(rangeInElement), !overlap.isEmpty else { continue }
                manager.enumerateTextSegments(in: overlap, type: .selection, options: []) { _, frame, _, _ in
                    rects.append(frame.offsetBy(dx: point.x - self.layoutFragmentFrame.minX, dy: point.y - self.layoutFragmentFrame.minY))
                    return true
                }
            }
        }
        return rects
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
