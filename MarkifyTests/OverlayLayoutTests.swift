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

    /// A long note with a table scrolled to 200pt from the top of the window, restyled after each change as the app does.
    /// The caret was last placed at the top of the document. The coordinator is returned to keep it alive.
    func scrolledTable() throws -> (NSWindow, MarkdownTextView, NativeEditor.Coordinator, () -> CGFloat) {
        let (window, editor) = makeEditor()
        let intro = (1...300).map { "Paragraph \($0) with enough words to wrap onto a second line in the column of this window." }.joined(separator: "\n\n")
        editor.string = intro + "\n\n| A | B |\n| --- | --- |\n| C | D |\n\n" + intro
        let coordinator = NativeEditor(text: .constant(editor.string), fileURL: nil, columnWidth: 640, markdownLens: false, findQuery: "", matchCase: false,
                                       selectedRange: .constant(NSRange(location: 0, length: 0)), textView: .constant(nil),
                                       onType: {}, onSlash: { _ in }, onSlashKey: { _, _ in false }, onSelectionRect: { _ in }).makeCoordinator()
        coordinator.editor = editor
        editor.delegate = coordinator
        coordinator.parent.style(editor)
        editor.refreshTables()
        let clip = try #require(editor.enclosingScrollView?.contentView)
        let start = (editor.string as NSString).range(of: "| A |").location
        clip.scroll(to: NSPoint(x: 0, y: editor.textRect(NSRange(location: start, length: 1)).minY - 200))
        editor.enclosingScrollView?.reflectScrolledClipView(clip)
        editor.refreshTables()
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        /// Where the table's first row sits in the window.
        let onScreen = { editor.textRect(NSRange(location: start, length: 1)).minY - clip.bounds.minY }
        #expect(abs(onScreen() - 200) < 2)
        return (window, editor, coordinator, onScreen)
    }

    /// A table edit leaves the page where it was.
    @Test func tableEditsKeepThePageInPlace() async throws {
        let (window, editor, _, onScreen) = try scrolledTable()
        let before = onScreen()
        #expect(window.makeFirstResponder(try #require(editor.tableOverlays[1]?.fields.last)))
        for edit in [MarkdownTable.Edit.insertRowBelow, .insertColumnRight, .deleteColumn, .deleteRow] {
            #expect(editor.editTable(edit))
            #expect(abs(onScreen() - before) < 2, "\(edit)")
            try await Task.sleep(for: .milliseconds(50))
            #expect(abs(onScreen() - before) < 2, "\(edit) after the cell is refocused")
        }
    }

    /// Tab to the next cell, or in the last cell to add a row, leaves the page where it was.
    @Test func tableTabKeepsThePageInPlace() async throws {
        let (window, editor, _, onScreen) = try scrolledTable()
        let before = onScreen()
        for step in ["next cell", "new row"] {
            let field = try #require(editor.tableOverlays.values.flatMap(\.fields).first { $0.sourceRange.location == editor.tableLocation }
                                     ?? editor.tableOverlays[1]?.fields.first)
            #expect(window.makeFirstResponder(field))
            field.onTab?(field.sourceRange, false)
            #expect(abs(onScreen() - before) < 2, "\(step)")
            try await Task.sleep(for: .milliseconds(50))
            #expect(abs(onScreen() - before) < 2, "\(step) after the cell is refocused")
        }
        #expect(editor.string.contains("| C | D |\n|  |  |"))
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

    @Test func expandedTablesWrapAndPreserveSource() async throws {
        let (window, editor) = makeEditor()
        let source = "| ID | Request | Priority |\n| --- | --- | --- |\n| 54 | " + String(repeating: "Long cell content wraps completely. ", count: 12) + " | High |\n| 55 | Next row | Low |\n\nAfter table"
        editor.string = source
        style(editor)
        editor.refreshTables()
        let table = try #require(editor.model.tables.first)
        let row = table.rows[2]
        #expect(editor.tableIDColumn(table) == 0)
        #expect(editor.tableWidths(table)[0] < editor.tableWidths(table)[1])
        #expect(editor.tableRowHeight(row, table: table) == 43)
        editor.hoverTableRow(row.start)
        for _ in 0..<100 {
            if editor.tableOverlays[1]?.expanded == true, (editor.tableOverlays[1]?.frame.height ?? 0) > 100 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        // Let the transition finish before resizing the expanded row.
        try await Task.sleep(for: .milliseconds(300))
        let overlay = try #require(editor.tableOverlays[1])
        #expect(overlay.expanded)
        #expect(overlay.frame.height > 100)
        #expect(overlay.fields[1].maximumNumberOfLines == 0)
        #expect(overlay.fields[0].drawsBackground)
        #expect(overlay.fields[0].frame.height == 21)
        #expect(editor.tableOverlays[2]!.frame.minY >= overlay.frame.maxY - 1)
        editor.columnWidth = 400
        editor.refreshTableHeights()
        #expect(overlay.frame.height > 150)
        editor.hoverTableRow(nil)
        for _ in 0..<100 {
            if !overlay.expanded, overlay.frame.height == 43 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(overlay.frame.height == 43)
        #expect(overlay.fields[1].maximumNumberOfLines == 1)
        #expect(editor.string == source)
        withExtendedLifetime(window) {}
    }

    @Test func scatteredTablesRefreshWhenScrollingAndRowsShrink() async throws {
        let (window, editor) = makeEditor()
        let padding = String(repeating: "A paragraph above the next table.\n\n", count: 15)
        let source = (0..<20).map { index in
            padding + "| ID | Notes |\n| --- | --- |\n| \(index) | " + String(repeating: "Long content wraps. ", count: 15) + " |\n\n"
        }.joined()
        editor.string = source
        style(editor)
        editor.refreshTables()
        let tables = editor.model.tables
        #expect(tables.count == 20)
        let clip = try #require(editor.enclosingScrollView?.contentView)
        let table = tables[10]
        let header = table.rows[0]
        editor.settleLayout(through: table.rows.last!.end)
        clip.scroll(to: NSPoint(x: 0, y: editor.textRect(NSRange(location: header.start, length: 1)).minY - 100))
        editor.enclosingScrollView?.reflectScrolledClipView(clip)
        // Scrolling must create these overlays without an explicit refreshTables call.
        try await Task.sleep(for: .milliseconds(100))
        let overlay = try #require(editor.tableOverlays.values.first { $0.rowStart == header.start })
        #expect(abs(overlay.frame.minY - settledY(editor, header.start)) < 1)
        let row = table.rows[2]
        editor.hoverTableRow(row.start)
        for _ in 0..<100 {
            if editor.tableRowHeight(row, table: table) > 43 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(editor.tableRowHeight(row, table: table) > 43)
        editor.hoverTableRow(nil)
        for _ in 0..<100 {
            if editor.tableRowHeight(row, table: table) == 43 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(editor.tableRowHeight(row, table: table) == 43)
        for overlay in editor.tableOverlays.values {
            #expect(abs(overlay.frame.minY - settledY(editor, overlay.rowStart)) < 1)
        }
        #expect(editor.string == source)
        window.contentView = nil
    }

    @Test func diagramCompletionKeepsAdjacentVirtualizedTableBelowIt() async throws {
        let (window, editor) = makeEditor()
        let diagram = "flowchart TD\n" + (0..<15).map { "N\($0)[Step \($0)] --> N\($0 + 1)" }.joined(separator: "\n")
        let tableSource = "| ID | Notes |\n| --- | --- |\n| 1 | Next to the diagram |\n\n"
        let source = "```mermaid\n" + diagram + "\n```\n\n" + String(repeating: tableSource, count: 20)
        editor.string = source
        editor.restyle = { [weak editor] in
            guard let editor else { return }
            self.style(editor)
        }
        style(editor)
        editor.refreshTables()
        let firstTable = try #require(editor.model.tables.first)
        let initialY = editor.textRect(NSRange(location: firstTable.rows[0].start, length: 1)).minY
        let dark = editor.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        for _ in 0..<200 {
            if case .rendered = MermaidRenderer.shared.cached(diagram, dark: dark) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        guard case .rendered(let image) = MermaidRenderer.shared.cached(diagram, dark: dark) else {
            Issue.record("The adjacent diagram did not render")
            return
        }
        try await Task.sleep(for: .milliseconds(100))
        // The finished diagram pushes the table below the viewport; scrolling must recreate it.
        let clip = try #require(editor.enclosingScrollView?.contentView)
        clip.scroll(to: NSPoint(x: 0, y: editor.textRect(NSRange(location: firstTable.rows[0].start, length: 1)).minY - 100))
        editor.enclosingScrollView?.reflectScrolledClipView(clip)
        try await Task.sleep(for: .milliseconds(100))
        let header = try #require(editor.tableOverlays.values.first { $0.rowStart == firstTable.rows[0].start })
        #expect(header.frame.minY > initialY)
        #expect(header.frame.minY >= editor.textContainerOrigin.y + MarkdownTextView.fitted(image.size, width: editor.columnWidth).height + MarkdownTextView.diagramPadding * 2)
        for overlay in editor.tableOverlays.values {
            #expect(abs(overlay.frame.minY - settledY(editor, overlay.rowStart)) < 1)
            #expect(overlay.frame.height == 43)
        }
        #expect(editor.string == source)
        window.contentView = nil
        editor.stopObserving()
    }

    @Test func tableHoverDelayCancelsAndKeyboardEditingExpands() async throws {
        let (window, editor) = makeEditor()
        editor.string = "| Name | Notes |\n| --- | --- |\n| First | " + String(repeating: "Long content ", count: 30) + " |"
        style(editor)
        editor.refreshTables()
        let table = try #require(editor.model.tables.first)
        #expect(editor.tableIDColumn(table) == nil)
        let row = table.rows[2]
        editor.hoverTableRow(row.start)
        editor.hoverTableRow(nil)
        try await Task.sleep(for: .milliseconds(150))
        #expect(editor.tableRowHeight(row, table: table) == 43)
        let field = try #require(editor.tableOverlays[1]?.fields.last)
        #expect(window.makeFirstResponder(field))
        #expect(editor.tableRowExpanded(row))
        try await Task.sleep(for: .milliseconds(50))
        #expect(editor.tableOverlays[1]!.frame.height > 43)
    }

    @Test func tableAlignmentsReachHeadersRichCellsAndEditing() async throws {
        let (window, editor) = makeEditor()
        let source = "| ID | Left | Center | Right |\n| :---: | :--- | :---: | ---: |\n| 1 | **Draft** | $x^2$ | 1,024 |\n| 2 | Next | A / B | -42 |"
        editor.string = source
        style(editor)
        editor.refreshTables()
        let expected: [NSTextAlignment] = [.center, .left, .center, .right]
        for overlay in editor.tableOverlays.values {
            #expect(overlay.fields.map(\.alignment) == expected)
            for field in overlay.fields.dropFirst() {
                let presentation = try #require(editor.tablePresentations[field.sourceRange.location])
                let index = try #require(overlay.fields.firstIndex(of: field))
                let paragraph = try #require(presentation.reading.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
                #expect(paragraph.alignment == expected[index])
                #expect(presentation.summary.alignment == expected[index])
            }
        }
        let field = try #require(editor.tableOverlays[1]?.fields.last)
        #expect(window.makeFirstResponder(field))
        let fieldEditor = try #require(field.currentEditor() as? NSTextView)
        #expect(fieldEditor.alignment == .right)
        window.makeFirstResponder(editor)
        editor.hoverTableRow(editor.model.tables[0].rows[2].start)
        try await Task.sleep(for: .milliseconds(450))
        #expect(editor.tableOverlays[1]?.fields.map(\.alignment) == expected)
        #expect(editor.string == source)
        window.contentView = nil
    }

    @Test func stressDocumentRapidlyReversesScrollingWhileRendering() async throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/render-stress-test.md")
        let source = try String(contentsOf: fixture, encoding: .utf8)
        let (window, editor) = makeEditor()
        defer { editor.stopObserving(); window.contentView = nil }
        editor.documentURL = fixture.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("render-stress-test.md")
        editor.string = source
        editor.restyle = { [weak editor] in
            guard let editor else { return }
            IncrementalStyleTests.native(source).style(editor, incremental: true)
        }
        IncrementalStyleTests.native(source).style(editor)
        let scroll = try #require(editor.enclosingScrollView)
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 980, pixelsHigh: 660, bitsPerSample: 8,
                                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                  bytesPerRow: 0, bitsPerPixel: 0))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        var readings = Set<ObjectIdentifier>()
        var peakPresentations = 0
        // Start immediately, before diagrams finish or the document's prefix has settled.
        for _ in 0..<3 {
            for y in stride(from: 0, through: 9000, by: 450).map({ $0 }) + stride(from: 9000, through: 0, by: -900).map({ $0 }) {
                let elapsed = ContinuousClock().measure {
                    autoreleasepool {
                        scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
                        scroll.reflectScrolledClipView(scroll.contentView)
                        editor.layoutSubtreeIfNeeded()
                        editor.refreshTables()
                        NSGraphicsContext.saveGraphicsState()
                        NSGraphicsContext.current = context
                        context.cgContext.saveGState()
                        context.cgContext.translateBy(x: 0, y: -editor.visibleRect.minY)
                        editor.draw(editor.visibleRect)
                        context.cgContext.restoreGState()
                        NSGraphicsContext.restoreGraphicsState()
                    }
                }
                #expect(elapsed < .seconds(2), "Rapid scrolling stalled at \(y) for \(elapsed)")
                for presentation in editor.tablePresentations.values {
                    readings.insert(ObjectIdentifier(presentation.reading))
                }
                peakPresentations = max(peakPresentations, editor.tablePresentations.count)
                try await Task.sleep(for: .milliseconds(5))
            }
        }
        // Allow the current viewport and the bounded reuse pool, not all cells
        // created across repeated reversals. Native views may outlive a display pass.
        #expect(peakPresentations > 0)
        #expect(readings.count <= peakPresentations + 64,
                "Table reading allocations must stay bounded across repeated scrolling")
        #expect(editor.string == source)
    }

    @Test func stressDocumentScrollsAndDrawsThroughCodeBlocks() async throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/render-stress-test.md")
        let source = try String(contentsOf: fixture, encoding: .utf8)
        let (window, editor) = makeEditor()
        editor.documentURL = fixture.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("render-stress-test.md")
        editor.string = source
        editor.restyle = { [weak editor] in
            guard let editor else { return }
            self.style(editor)
        }
        style(editor)
        let manager = try #require(editor.textLayoutManager)
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 980, pixelsHigh: 660, bitsPerSample: 8,
                                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                  bytesPerRow: 0, bitsPerPixel: 0))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext)
        for heading in ["### Small alignment table", "### Connection attempt with retry and failure paths", "## 6. Code blocks and long lines", "### Python", "### JSON and an intentionally long string", "## END OF STRESS TEST"] {
            let range = (source as NSString).range(of: heading)
            try #require(range.location != NSNotFound)
            editor.settleLayout(through: NSMaxRange(range))
            editor.reveal(range)
            try await Task.sleep(for: .milliseconds(100))
            editor.refreshTables()
            manager.ensureLayout(for: editor.visibleRect)
            let elapsed = ContinuousClock().measure {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
                context.translateBy(x: 0, y: -editor.visibleRect.minY)
                editor.draw(editor.visibleRect)
                NSGraphicsContext.restoreGraphicsState()
            }
            #expect(elapsed < .seconds(2), "Drawing \(heading) stalled for \(elapsed)")
            #expect(editor.string == source)
        }
        editor.stopObserving()
        window.contentView = nil
    }

    @Test func idAndNumericColumnsHandleRaggedRows() throws {
        let (window, editor) = makeEditor()
        editor.string = "| Name | Count | id |\n| --- | --- | --- |\n| One | 2 | 54 |\n| Two |\n| Three | 12 | 55 |"
        let table = try #require(editor.model.tables.first)
        #expect(editor.tableIDColumn(table) == 2)
        let widths = editor.tableWidths(table)
        #expect(widths.count == 3)
        #expect(widths[0] > widths[1])
        #expect(widths[0] > widths[2])
        #expect(abs(widths.reduce(0, +) - editor.columnWidth) < 1)
        editor.refreshTables()
        #expect(editor.tableOverlays.count == 4)
        withExtendedLifetime(window) {}
    }

    @Test func longIDsWrapInTheirHighlightedPill() async throws {
        let (window, editor) = makeEditor()
        editor.columnWidth = 320
        editor.string = "| ID | Notes |\n| --- | --- |\n| 550e8400-e29b-41d4-a716-446655440000 | Short note |"
        style(editor)
        editor.columnWidth = 320
        editor.refreshTables()
        let field = try #require(editor.tableOverlays[1]?.fields.first)
        #expect(window.makeFirstResponder(field))
        for _ in 0..<100 {
            if field.frame.height > 21 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(field.frame.height > 21)
        #expect(field.maximumNumberOfLines == 0)
        #expect(field.drawsBackground)
        #expect(editor.tableOverlays[1]!.frame.height >= field.frame.height + 22)
    }

    @Test func tableIDBadgeFitsTheValue() throws {
        let (window, editor) = makeEditor()
        editor.string = "| ID | Notes |\n| --- | --- |\n| 4 | Note |\n| 123 | Another |"
        style(editor)
        editor.refreshTables()
        let single = try #require(editor.tableOverlays[1]?.fields.first)
        let multiple = try #require(editor.tableOverlays[2]?.fields.first)
        #expect(single.frame.width == 21)
        #expect(multiple.frame.width > single.frame.width)
        #expect(single.frame.width < editor.tableOverlays[1]!.widths[0] - 28)
        #expect(abs(single.frame.midX - editor.tableOverlays[1]!.widths[0] / 2) < 1)
        withExtendedLifetime(window) {}
    }

    @Test func tableCellsReuseMarkdownRenderingAndEditTheirSource() async throws {
        let (window, editor) = makeEditor()
        let source = "| ID | Notes |\n| --- | --- |\n| 4 | **Bold** and *italic* with `code`, ~~gone~~, [link][site] and $x^2$ |\n\n[site]: https://example.com"
        editor.string = source
        style(editor)
        editor.refreshTables()
        let field = try #require(editor.tableOverlays[1]?.fields.last)
        let presentation = try #require(editor.tablePresentations[field.sourceRange.location])
        let reading = presentation.reading
        let bold = (reading.string as NSString).range(of: "Bold")
        let font = try #require(reading.textStorage?.attribute(.font, at: bold.location, effectiveRange: nil) as? NSFont)
        #expect(font.fontDescriptor.symbolicTraits.contains(.bold))
        let marker = (reading.string as NSString).range(of: "**")
        #expect(reading.textStorage?.attribute(.foregroundColor, at: marker.location, effectiveRange: nil) as? NSColor == .clear)
        #expect(reading.inlineFormulas.count == 1)
        #expect(reading.model.spans.contains { $0.kind == .link(destination: "https://example.com") })
        presentation.beginEditing()
        #expect(field.stringValue == (source as NSString).substring(with: field.sourceRange))
        #expect(presentation.isHidden)
        #expect(editor.string == source)
        withExtendedLifetime(window) {}
    }

    /// Only the diagrams near the viewport are leased, so eviction drops the ones scrolled far away first.
    @Test func diagramLeasesFollowTheViewport() async throws {
        let (window, editor) = makeEditor()
        let top = "graph TD\n Top --> Lease", bottom = "graph TD\n Bottom --> Lease"
        editor.string = "```mermaid\n\(top)\n```\n\n" + String(repeating: "Filler paragraph for the lease test.\n\n", count: 2000)
            + "```mermaid\n\(bottom)\n```\n"
        style(editor)
        let dark = editor.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        editor.textLayoutManager?.textViewportLayoutController.layoutViewport()
        editor.leaseDiagrams()
        #expect(MermaidRenderer.shared.isLeased(top, dark: dark))
        #expect(!MermaidRenderer.shared.isLeased(bottom, dark: dark))
        editor.scrollToEndOfDocument(nil)
        editor.textLayoutManager?.textViewportLayoutController.layoutViewport()
        editor.leaseDiagrams()
        #expect(!MermaidRenderer.shared.isLeased(top, dark: dark))
        #expect(MermaidRenderer.shared.isLeased(bottom, dark: dark))
        editor.stopObserving()
        #expect(!MermaidRenderer.shared.isLeased(bottom, dark: dark))
        withExtendedLifetime(window) {}
    }

    @Test func tableMermaidUsesTheBundledRenderer() async throws {
        let (window, editor) = makeEditor()
        editor.string = "| ID | Flow |\n| --- | --- |\n| 1 | ```mermaid<br>flowchart TD<br>A[Start] --> B[End]<br>``` |"
        style(editor)
        editor.refreshTables()
        let field = try #require(editor.tableOverlays[1]?.fields.last)
        let presentation = try #require(editor.tablePresentations[field.sourceRange.location])
        let block = try #require(presentation.reading.model.spans.first { if case .codeBlock(let language?, _) = $0.kind { return language == "mermaid" }; return false })
        let code = (presentation.reading.string as NSString).substring(with: block.content)
        for _ in 0..<150 {
            if case .rendered = MermaidRenderer.shared.cached(code, dark: false) { break }
            if case .rendered = MermaidRenderer.shared.cached(code, dark: true) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let state = MermaidRenderer.shared.cached(code, dark: false) ?? MermaidRenderer.shared.cached(code, dark: true)
        guard case .rendered = state else { Issue.record("The table Mermaid did not render"); return }
        #expect(presentation.fullHeight > 43)
        #expect(editor.string.contains("<br>"))
        withExtendedLifetime(window) {}
    }

    @Test func tableImagesShowAThumbnailAndFootnotesUseTheDocument() async throws {
        let (window, editor) = makeEditor()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 80, pixelsHigh: 50, bitsPerSample: 8,
                                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        editor.string = "| ID | Image | Note |\n| --- | --- | --- |\n| 1 | ![Mockup](" + url.path + ") | Citation[^n] |\n\n[^n]: The document footnote."
        style(editor)
        editor.refreshTables()
        let fields = try #require(editor.tableOverlays[1]?.fields)
        let image = try #require(editor.tablePresentations[fields[1].sourceRange.location])
        for _ in 0..<100 where image.thumbnail.image == nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(image.thumbnail.image != nil)
        #expect(!image.thumbnail.isHidden)
        #expect(image.fullHeight > 21)
        let note = try #require(editor.tablePresentations[fields[2].sourceRange.location])
        let reference = try #require(note.reading.model.spans.first { if case .footnoteReference = $0.kind { return true }; return false })
        #expect(note.reading.textStorage?.attribute(.toolTip, at: reference.content.location, effectiveRange: nil) as? String == "The document footnote.")
        #expect(note.reading.followFootnote(at: reference.range.location))
        #expect(editor.selectedRange().location == (editor.string as NSString).range(of: "[^n]:").location + 2)
        withExtendedLifetime(window) {}
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
