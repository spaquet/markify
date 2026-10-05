import AppKit
import MarkifyMarkdown
import Testing
@testable import Markify

/// Manual diagnostics, excluded from normal test runs. See PERFORMANCE_AUDIT.md for the command and limits.
@MainActor struct PerformanceAuditTests {
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
