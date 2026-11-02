import AppKit
import MarkifyMarkdown

extension MarkdownTextView {
    func detailsIsOpen(_ section: MarkdownModel.Details) -> Bool {
        detailsOpen[section.range.location] ?? section.initiallyOpen
    }

    func isInClosedDetails(_ location: Int) -> Bool {
        rendered && model.details.contains { !detailsIsOpen($0) && NSLocationInRange(location, $0.body) }
    }

    @discardableResult func revealDetails(containing range: NSRange) -> Bool {
        guard rendered else { return false }
        var changed = false
        for section in model.details where !detailsIsOpen(section) {
            if NSLocationInRange(range.location, section.body) || NSIntersectionRange(range, section.body).length > 0 {
                detailsOpen[section.range.location] = true
                changed = true
            }
        }
        return changed
    }

    func toggleDetails(_ section: MarkdownModel.Details) {
        // Folding changes layout below this summary. Anchor its source position, rather
        // than a raw scroll offset that can move as TextKit replaces estimated heights.
        settleLayout(through: section.summary.location)
        let clip = enclosingScrollView?.contentView
        let offset = clip.map { detailsRect(section).minY - $0.bounds.minY }
        let version = textVersion
        let open = detailsIsOpen(section)
        if open, NSLocationInRange(selectedRange().location, section.body) || NSIntersectionRange(selectedRange(), section.body).length > 0 {
            setSelectedRange(NSRange(location: section.summary.location, length: 0))
        }
        detailsOpen[section.range.location] = !open
        restyle?()
        refreshTables()
        let keepSummary = { [weak self, weak clip] in
            guard let self, let clip, let offset, self.textVersion == version,
                  self.detailsIsOpen(section) == !open else { return }
            self.settleLayout(through: NSMaxRange(section.range))
            var bounds = clip.bounds
            bounds.origin.y = self.detailsRect(section).minY - offset
            clip.scroll(to: clip.constrainBoundsRect(bounds).origin)
            self.enclosingScrollView?.reflectScrolledClipView(clip)
        }
        keepSummary()
        // Styling queues table overlay work. Restore the same anchor after that layout
        // settles too, without restoring a stale anchor after another toggle or edit.
        DispatchQueue.main.async(execute: keepSummary)
        needsDisplay = true
    }

    func updateDetailsAccessibility() {
        let sections = rendered ? model.details.filter { !isInClosedDetails($0.summary.location) } : []
        setAccessibilityCustomActions(sections.map { section in
            let title = (string as NSString).substring(with: section.summary)
            let name = detailsIsOpen(section)
                ? String(localized: "Collapse \(title)") : String(localized: "Expand \(title)")
            return NSAccessibilityCustomAction(name: name) { [weak self] in
                guard let self else { return false }
                self.toggleDetails(section)
                return true
            }
        })
    }

    func detailsRect(_ section: MarkdownModel.Details) -> NSRect {
        let line = textRect(NSRange(location: section.summary.location, length: max(1, section.summary.length)))
        return NSRect(x: max(0, line.minX - 22), y: line.minY, width: 20, height: max(20, line.height))
    }

    func drawDetails(anchoredIn range: NSRange) {
        for section in model.details where NSLocationInRange(section.summary.location, range) && !isInClosedDetails(section.summary.location) {
            Self.drawDisclosure(in: detailsRect(section), open: detailsIsOpen(section))
        }
    }

    static func drawDisclosure(in rect: NSRect, open: Bool) {
        NSColor.secondaryLabelColor.setFill()
        let path = NSBezierPath()
        if open {
            path.move(to: NSPoint(x: rect.midX - 5, y: rect.midY - 3))
            path.line(to: NSPoint(x: rect.midX + 5, y: rect.midY - 3))
            path.line(to: NSPoint(x: rect.midX, y: rect.midY + 3))
        } else {
            path.move(to: NSPoint(x: rect.midX - 3, y: rect.midY - 5))
            path.line(to: NSPoint(x: rect.midX + 3, y: rect.midY))
            path.line(to: NSPoint(x: rect.midX - 3, y: rect.midY + 5))
        }
        path.close()
        path.fill()
    }
}

extension NativeEditor {
    func styleDetails(_ model: MarkdownModel, editor: NSTextView, storage: NSTextStorage, base: NSFont, paragraph: NSParagraphStyle, marker: (NSRange, NSMutableAttributedString) -> Void) {
        let source = model.source as NSString
        func collapse(_ range: NSRange) {
            guard range.length > 0 else { return }
            let style = NSMutableParagraphStyle()
            style.minimumLineHeight = 0.01
            style.maximumLineHeight = 0.01
            style.lineBreakMode = .byClipping
            storage.setAttributes([.font: NSFont.systemFont(ofSize: 1), .foregroundColor: NSColor.clear, .paragraphStyle: style], range: range)
        }
        // Inner sections first, then collapsed ancestors override all their descendants.
        for section in model.details.reversed() {
            let summaryLine = source.lineRange(for: section.summary)
            collapse(NSRange(location: section.range.location, length: max(0, summaryLine.location - section.range.location)))
            let open = (editor as? MarkdownTextView)?.detailsIsOpen(section) ?? section.initiallyOpen
            let end = open ? NSMaxRange(section.body) : NSMaxRange(summaryLine)
            collapse(NSRange(location: end, length: max(0, NSMaxRange(section.range) - end)))
            let style = paragraph.mutableCopy() as! NSMutableParagraphStyle
            style.firstLineHeadIndent = 22
            style.headIndent = 22
            storage.addAttribute(.paragraphStyle, value: style, range: summaryLine)
            storage.addAttributes([.font: base, .foregroundColor: NSColor.labelColor], range: section.summary)
            if !open { marker(NSIntersectionRange(section.body, summaryLine), storage) }
            // Hide tag advances on the summary line, just like other rendered markers.
            for range in [NSRange(location: max(summaryLine.location, section.range.location), length: section.summary.location - max(summaryLine.location, section.range.location)),
                          NSRange(location: NSMaxRange(section.summary), length: min(NSMaxRange(summaryLine), section.body.location) - NSMaxRange(section.summary))] {
                marker(range, storage)
            }
        }
    }
}
