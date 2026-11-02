import AppKit
import Darwin
import MarkifyMarkdown
import Testing
@testable import Markify

/// Manual diagnostics, excluded from normal test runs. See PERFORMANCE_AUDIT_2.5.0.md for commands and limits.
@MainActor struct PerformanceAuditTests {
    /// A separate test-host audit: navigate in process so an unavailable external
    /// accessibility tree cannot silently turn a scroll measurement into an idle one.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MARKIFY_PERFORMANCE_AUDIT"] == "1"))
    func measureParagraphNavigation() async throws {
        struct Sample: Codable {
            let bytes: Int
            let position: String
            let footprintMiB: Double
            let sourceAttributeRuns: Int
            let viewportStart: Int
            let viewportEnd: Int
        }
        func footprint() throws -> Double {
            var info = task_vm_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                }
            }
            try #require(result == KERN_SUCCESS)
            return Double(info.phys_footprint) / 1_048_576
        }
        var samples: [Sample] = []
        for name in ["1m", "5m"] {
            let url = URL(fileURLWithPath: "/private/tmp/markify-memory-prose-\(name).md")
            let source = try String(contentsOf: url, encoding: .utf8)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 660),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let scroll = NSScrollView(frame: window.contentView!.bounds)
            let editor = MarkdownTextView(usingTextLayoutManager: true)
            editor.installParagraphPresentation()
            editor.frame = scroll.bounds
            editor.isRichText = false
            editor.isVerticallyResizable = true
            editor.textContainer?.widthTracksTextView = true
            editor.textContainerInset = NSSize(width: 0, height: 40)
            editor.documentURL = url
            editor.string = source
            scroll.documentView = editor
            window.contentView = scroll
            defer {
                editor.stopObserving()
                scroll.documentView = nil
                window.contentView = nil
                window.close()
            }
            NativeEditor(text: .constant(source), fileURL: url, columnWidth: 640, markdownLens: false,
                         findQuery: "", matchCase: false, selectedRange: .constant(NSRange(location: 0, length: 0)),
                         textView: .constant(nil), onType: {}, onSlash: { _ in }, onSlashKey: { _, _ in false }, onSelectionRect: { _ in })
                .style(editor)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(editor)
            let storage = try #require(editor.textStorage)
            let length = storage.length
            func record(_ position: String, expectedOffset: Int) throws {
                var runs = 0
                storage.enumerateAttributes(in: NSRange(location: 0, length: length)) { _, _, _ in runs += 1 }
                let manager = try #require(editor.textLayoutManager)
                let content = try #require(manager.textContentManager)
                let viewport = try #require(manager.textViewportLayoutController.viewportRange)
                let start = content.offset(from: content.documentRange.location, to: viewport.location)
                let end = content.offset(from: content.documentRange.location, to: viewport.endLocation)
                #expect(start <= expectedOffset && expectedOffset <= end, "Requested source position must actually reach the viewport")
                samples.append(Sample(bytes: source.utf8.count, position: position,
                                      footprintMiB: try footprint(), sourceAttributeRuns: runs,
                                      viewportStart: start, viewportEnd: end))
                #expect(editor.string.isSameText(as: source))
                #expect(runs <= 2)
            }
            try await Task.sleep(for: .seconds(2))
            try record("initial", expectedOffset: 0)
            for cycle in 1...3 {
                for (position, offset) in [("middle", length / 2), ("end", length - 1), ("start", 0)] {
                    let range = NSRange(location: offset, length: 0)
                    editor.setSelectedRange(range)
                    editor.scrollRangeToVisible(range)
                    window.layoutIfNeeded()
                    try await Task.sleep(for: .milliseconds(500))
                    try record("\(cycle)-\(position)", expectedOffset: offset)
                }
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(samples).write(to: URL(fileURLWithPath: "/private/tmp/markify-paragraph-navigation.json"), options: .atomic)
    }

    private final class AuditDocument: NSDocument {
        var text = ""
        override func fileWrapper(ofType typeName: String) throws -> FileWrapper {
            FileWrapper(regularFileWithContents: Data(text.utf8))
        }
    }
    struct Measurement: Codable {
        let workload: String
        let bytes: Int
        let operation: String
        let milliseconds: [Double]
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MARKIFY_PERFORMANCE_AUDIT"] == "1"))
    func measureEditorWork() throws {
        var results: [Measurement] = []
        let output = URL(fileURLWithPath: "/private/tmp/markify-performance-audit.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        func measure(_ workload: String, _ source: String, _ operation: String, repeats: Int = 3, _ work: () -> Void) {
            try? "\(workload): \(operation)".write(toFile: "/private/tmp/markify-performance-audit-current.txt", atomically: true, encoding: .utf8)
            let times = (0..<repeats).map { _ in
                let start = ContinuousClock.now
                work()
                let duration = (ContinuousClock.now - start).components
                return Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15
            }
            results.append(Measurement(workload: workload, bytes: source.utf8.count, operation: operation, milliseconds: times))
            // Preserve completed workloads if the host fails during a later operation.
            try? encoder.encode(results).write(to: output, options: .atomic)
        }
        func editor(_ source: String) -> MarkdownTextView {
            let view = MarkdownTextView(usingTextLayoutManager: true)
            view.frame = NSRect(x: 0, y: 0, width: 640, height: 600)
            view.columnWidth = 640
            view.string = source
            return view
        }

        for count in [100, 1000, 5000] {
            let source = "# Title\n\n" + String(repeating: "Paragraph with **bold**, *emphasis*, and [a link](https://example.com).\n\n", count: count)
            let view = editor(source)
            measure("prose-\(count)", source, "parse") { _ = MarkdownModel(source) }
            measure("prose-\(count)", source, "full-style") { IncrementalStyleTests.native(view.string).style(view) }
            measure("prose-\(count)", source, "edit-and-incremental-style") {
                view.textStorage!.replaceCharacters(in: NSRange(location: (view.string as NSString).length, length: 0), with: "x")
                IncrementalStyleTests.native(view.string).style(view, incremental: true)
            }
            var words = 0
            measure("prose-\(count)", source, "word-count") { words = view.string.split(whereSeparator: \.isWhitespace).count }
            let currentSource = view.string // ContentView reads its String binding, rather than NSTextView.string on every access.
            measure("prose-\(count)", source, "word-count-cached-cold") { words = DocumentDerivedData().wordCount(in: currentSource) }
            let derived = DocumentDerivedData()
            _ = derived.wordCount(in: currentSource)
            measure("prose-\(count)", source, "word-count-cached-warm") { words = derived.wordCount(in: currentSource) }
            #expect(words > count)
            #expect(view.string == source + "xxx")
        }

        for count in [100, 500, 1500] {
            let source = String(repeating: "**bold** [link](https://example.com) ", count: count)
            measure("long-line-\(count)", source, "parse") { _ = MarkdownModel(source) }
            let math = String(repeating: "Formula $x^2 + y^2$ here.\n\n", count: count)
            measure("inline-math-\(count)", math, "parse") { _ = MarkdownModel(math) }
            let view = editor(math)
            IncrementalStyleTests.native(math).style(view)
            measure("inline-math-\(count)", math, "warm-style") { IncrementalStyleTests.native(math).style(view) }
        }

        for count in [50, 200, 500] {
            let source = "# Table\n\n| ID | Description | Value |\n| --- | --- | --- |\n"
                + (0..<count).map { "| \($0) | **Cell** with [link](https://example.com) | \($0) |\n" }.joined() + "\nTail.\n"
            let view = editor(source)
            let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = view
            IncrementalStyleTests.native(source).style(view)
            measure("table-\(count)", source, "initial-overlays", repeats: 1) { view.refreshTables() }
            measure("table-\(count)", source, "unchanged-overlays") { view.refreshTables() }
            measure("table-\(count)", source, "edit-style-and-overlays") {
                view.textStorage!.replaceCharacters(in: NSRange(location: (view.string as NSString).length, length: 0), with: "x")
                IncrementalStyleTests.native(view.string).style(view, incremental: true)
                view.refreshTables()
            }
            #expect(view.tableOverlays.count < count + 1)
            window.contentView = nil
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("markify-audit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = String(repeating: "Unchanged file on disk.\n", count: 50_000)
        let file = directory.appendingPathComponent("poll.md")
        try source.write(to: file, atomically: true, encoding: .utf8)
        let document = AuditDocument()
        document.text = source
        document.fileURL = file
        document.fileType = "net.daringfireball.markdown"
        let refresh = DocumentFileRefresh(refreshSearch: {}, readText: { source })
        refresh.watch(document)
        defer { refresh.stop() }
        measure("poll-unchanged-local", source, "refresh", repeats: 10) { refresh.refresh() }

        try encoder.encode(results).write(to: output, options: .atomic)
        print("Performance audit measurements: \(output.path)")
    }

    /// Additional 2.5 workloads; kept separate so historical measurements remain comparable.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MARKIFY_PERFORMANCE_AUDIT"] == "1"))
    func measureEditingFallbacks() throws {
        var results: [Measurement] = []
        func measure(_ name: String, _ source: String, _ operation: String, _ work: () -> Void) {
            let times = (0..<3).map { _ in
                let start = ContinuousClock.now
                work()
                let duration = (ContinuousClock.now - start).components
                return Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15
            }
            results.append(Measurement(workload: name, bytes: source.utf8.count, operation: operation, milliseconds: times))
        }
        for count in [1000, 5000] {
            for unicode in [false, true] {
                let source = "# Title\n\n" + String(repeating: unicode
                    ? "Café — **résumé**, *日本語*, and [a link](https://example.com). 😀\n\n"
                    : "Paragraph with **bold**, *emphasis*, and [a link](https://example.com).\n\n", count: count)
                let name = "\(unicode ? "unicode" : "prose")-\(count)"
                let view = MarkdownTextView(usingTextLayoutManager: true)
                view.string = source
                let native = IncrementalStyleTests.native(source)
                let markdown = IncrementalStyleTests.native(source, markdownLens: true)
                let find = IncrementalStyleTests.native(source, findQuery: "link")
                native.style(view)
                measure(name, source, "unchanged-incremental-restyle") { native.style(view, incremental: true) }
                measure(name, source, "lens-style-roundtrip") {
                    markdown.style(view)
                    native.style(view)
                }
                // A heading edit forces the full-document fallback; length stays constant across samples.
                measure(name, source, "heading-edit-and-style") {
                    view.textStorage!.replaceCharacters(in: NSRange(location: 2, length: 1), with: "T")
                    native.style(view, incremental: true)
                }
                measure(name, source, "find-full-style") { find.style(view) }
                // Moving the current match between two matches: only the highlights change.
                let firstLink = (source as NSString).range(of: "link")
                var currentIsFirst = false
                measure(name, source, "find-highlight-move") {
                    var moved = find
                    moved.currentMatch = currentIsFirst ? nil : firstLink
                    currentIsFirst.toggle()
                    moved.updateFindHighlights(view)
                }
                #expect(view.string.isSameText(as: source))
                let copy = String(decoding: Array(source.utf8), as: UTF8.self)
                measure(name, source, "literal-equality-independent-copy") { #expect(source.isSameText(as: copy)) }
                // An image at the top of the same document: an asset finishing restyles its block, or everything without a key.
                let withImage = "![Pic](pic.png)\n\n" + source
                let imageView = MarkdownTextView(usingTextLayoutManager: true)
                imageView.string = withImage
                let imageNative = IncrementalStyleTests.native(withImage)
                imageNative.style(imageView)
                let model = imageView.model
                let key = model.spans.lazy.flatMap { imageView.assetKeys($0, model: model, dark: false) }.first ?? ""
                measure(name, withImage, "asset-full-restyle") { imageNative.style(imageView, incremental: true) }
                measure(name, withImage, "asset-block-restyle") {
                    imageView.requestAssetRestyle(key)
                    imageNative.style(imageView, incremental: true)
                }
                imageView.stopObserving()
                view.stopObserving()
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(results).write(to: URL(fileURLWithPath: "/private/tmp/markify-performance-fallbacks.json"), options: .atomic)
    }

    // Run in a separate test host so cold WebKit timing does not include the table/prose workloads.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MARKIFY_PERFORMANCE_AUDIT"] == "1"))
    func measureHTMLImport() async throws {
        let html = "<div><h2>HTML block</h2><p>Text with <b>bold</b> and a <a href='https://example.com'>link</a>.</p></div>\n\n"
        let view = MarkdownTextView(usingTextLayoutManager: true)
        view.columnWidth = 640
        view.string = html
        let start = ContinuousClock.now
        IncrementalStyleTests.native(html).style(view)
        func elapsed() -> Double {
            let duration = (ContinuousClock.now - start).components
            return Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15
        }
        let submitted = elapsed()
        let span = try #require(view.model.spans.first { $0.kind == .htmlBlock })
        let raw = (html as NSString).substring(with: span.range)
        while view.renderHTML(raw, width: 640) == nil, ContinuousClock.now - start < .seconds(10) {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(view.renderHTML(raw, width: 640) != nil)
        let results = [
            Measurement(workload: "html-cold", bytes: html.utf8.count, operation: "style-submission", milliseconds: [submitted]),
            Measurement(workload: "html-cold", bytes: html.utf8.count, operation: "style-to-import-completion", milliseconds: [elapsed()])
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(results).write(to: URL(fileURLWithPath: "/private/tmp/markify-performance-html-audit.json"), options: .atomic)
        view.stopObserving()
    }
}
