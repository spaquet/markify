import AppKit
import MarkifyMarkdown
import WebKit

/// HTML and PDF export. Both read the source through `MarkdownHTML`, the same reading as the editor's model, so
/// what exports is what the Rendered lens shows: callouts, tasks, tables, footnotes, math as vector SVG and Mermaid
/// diagrams as SVG. The HTML is one self-contained file; the PDF is that page printed across paper-sized pages.
@MainActor enum DocumentExport {
    struct Context {
        let source: String
        /// The document's own file, used to resolve relative images and links; nil for an unsaved document.
        let documentURL: URL?
        let bundleRoot: URL?
        /// Where the export is written; relative links are rewritten to work from there.
        let destination: URL
        let fallbackTitle: String
        var baseDirectory: URL? = nil
    }

    enum Format { case html, pdf }

    /// HTML clipboard content lets browser editors paste the rendered Markdown directly.
    nonisolated static func mediumHTML(_ source: String, mdx: Bool = false) -> String {
        var options = MarkdownHTML.Options()
        options.codeLabels = false
        return "<html><head><meta charset=\"utf-8\"></head><body>"
            + MarkdownHTML.render(source, mdx: mdx, options: options).body + "</body></html>"
    }

    static func copyAll(_ source: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(source, forType: .string)
    }

    static func copyForMedium(_ source: String, mdx: Bool = false,
                              to pasteboard: NSPasteboard = .general) async {
        let html = await Task.detached(priority: .userInitiated) {
            mediumHTML(source, mdx: mdx)
        }.value
        copyAll(source, to: pasteboard)
        pasteboard.setString(html, forType: .html)
    }

    /// A complete HTML page for the document.
    static func page(_ context: Context, for format: Format) async -> String {
        let mdx = MarkdownTextView.isMDX(context.documentURL)
        // Mermaid renders asynchronously in its web view, so diagrams are ready before the synchronous render.
        var diagrams: [String: String] = [:]
        let scan = Task.detached(priority: .userInitiated) { () -> [String] in
            guard !Task.isCancelled else { return [] }
            return MarkdownModel(context.source, mdx: mdx).spans.compactMap { span -> String? in
                guard case .codeBlock(let language?, true) = span.kind, language.lowercased() == "mermaid" else { return nil }
                return (context.source as NSString).substring(with: span.content)
            }
        }
        let diagramSources = await withTaskCancellationHandler { await scan.value } onCancel: { scan.cancel() }
        for code in diagramSources {
            guard !Task.isCancelled else { return "" }
            let key = code.trimmingCharacters(in: .whitespacesAndNewlines)
            if diagrams[key] == nil, let svg = await MermaidRenderer.shared.svg(for: code) { diagrams[key] = svg }
        }
        let remote = UserDefaults.standard.object(forKey: "loadRemoteImages") as? Bool ?? true
        let pdf = format == .pdf
        // Math outlines, code colors and embedded images take a while on long documents; the main thread stays free.
        let renderedDiagrams = diagrams
        let work = Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled else { return "" }
            return render(context, diagrams: renderedDiagrams, pdf: pdf, remoteImages: remote)
        }
        return await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
    }

    /// The page from already-rendered diagrams, on any thread.
    nonisolated static func render(_ context: Context, diagrams: [String: String], pdf: Bool, remoteImages: Bool) -> String {
        MarkdownPage.html(shared(context),
            math: { latex, display in MathSVG.render(latex, display: display) },
            diagram: { language, code in
                language.lowercased() == "mermaid" ? diagrams[code.trimmingCharacters(in: .whitespacesAndNewlines)] : nil
            },
            highlight: { code, _ in highlighted(code) }, pdf: pdf, remoteImages: remoteImages)
    }

    static func writeHTML(_ context: Context) async throws {
        let html = await page(context, for: .html)
        try Task.checkCancellation()
        let write = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            try html.write(to: context.destination, atomically: true, encoding: .utf8)
        }
        try await withTaskCancellationHandler { try await write.value } onCancel: { write.cancel() }
    }

    static func writePDF(_ context: Context) async throws {
        let html = await page(context, for: .pdf)
        try Task.checkCancellation()
        try await PDFPrinter().print(html, to: context.destination)
    }

    // MARK: Images and links

    /// A local image as a data URI, so the page stands alone; remote and data sources stay as written.
    nonisolated static func imageSource(_ source: String, context: Context) -> String {
        MarkdownPage.imageSource(source, context: shared(context))
    }

    /// Relative and bundle-absolute links rewritten to reach the same file from where the export lands.
    nonisolated static func linkTarget(_ destination: String, context: Context) -> String {
        MarkdownPage.linkTarget(destination, context: shared(context))
    }

    nonisolated private static func shared(_ context: Context) -> MarkdownPage.Context {
        .init(source: context.source, documentURL: context.documentURL, bundleRoot: context.bundleRoot,
              destination: context.destination, fallbackTitle: context.fallbackTitle, baseDirectory: context.baseDirectory)
    }

    // MARK: Code

    /// Code with the editor's token colors as spans; a later token wins where they overlap, as in the editor.
    nonisolated static func highlighted(_ code: String) -> String {
        let units = Array(code.utf16)
        var kinds = [CodeToken?](repeating: nil, count: units.count)
        for (range, kind) in CodeToken.tokens(in: code) {
            for index in range.location..<NSMaxRange(range) { kinds[index] = kind }
        }
        var html = ""
        var start = 0
        while start < units.count {
            var end = start + 1
            while end < units.count, kinds[end] == kinds[start] { end += 1 }
            let text = MarkdownHTML.escape(String(utf16CodeUnits: Array(units[start..<end]), count: end - start))
            html += kinds[start].map { "<span class=\"tok-\($0.rawValue)\">\(text)</span>" } ?? text
            start = end
        }
        return html
    }

}

// MARK: - PDF

/// Prints an HTML page to a paginated PDF with WebKit, on the paper size and margins of the default print setup.
@MainActor final class PDFPrinter: NSObject, WKNavigationDelegate {
    private var loaded: CheckedContinuation<Void, Error>?
    private var printed: CheckedContinuation<Void, Error>?
    private var deadline: Task<Void, Never>?
    private var webView: WKWebView?
    private var temporaryURL: URL?
    // ponytail: AppKit has no public print cancellation. Keep one native job alive until its callback,
    // even if our wait expires; this caps abandoned jobs and keeps the delegate valid.
    private static var activePrint: PDFPrinter?

    func print(_ html: String, to url: URL) async throws {
        try Task.checkCancellation()
        guard Self.activePrint == nil else { throw CocoaError(.fileWriteUnknown) }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("markify-export-\(UUID().uuidString).pdf")
        temporaryURL = temporary
        defer {
            if Self.activePrint !== self {
                try? FileManager.default.removeItem(at: temporary)
                temporaryURL = nil
            }
        }
        try await withTaskCancellationHandler {
            try await performPrint(html, temporary: temporary)
            try Task.checkCancellation()
            // A cancelled native print can only write its temporary file, never the chosen destination.
            let write = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                let data = try Data(contentsOf: temporary)
                try Task.checkCancellation()
                try data.write(to: url, options: .atomic)
            }
            try await withTaskCancellationHandler { try await write.value } onCancel: { write.cancel() }
        } onCancel: {
            Task { @MainActor in self.fail(CancellationError()) }
        }
    }

    private func performPrint(_ html: String, temporary: URL) async throws {
        var completed = false
        defer {
            deadline?.cancel()
            deadline = nil
            webView?.stopLoading()
            webView?.navigationDelegate = nil
            webView = nil
            if !completed, Self.activePrint !== self {
                try? FileManager.default.removeItem(at: temporary)
            }
        }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = temporary
        info.topMargin = 54; info.bottomMargin = 54; info.leftMargin = 60; info.rightMargin = 60
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false

        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: info.paperSize.height), configuration: configuration)
        self.webView = webView
        webView.navigationDelegate = self
        // Printing needs the view in a window; this one never appears on screen.
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: width, height: info.paperSize.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = webView
        defer { window.contentView = nil }

        try await withCheckedThrowingContinuation { continuation in
            loaded = continuation
            armDeadline(seconds: 30)
            webView.loadHTMLString(html, baseURL: nil)
        }
        try Task.checkCancellation()
        guard Self.activePrint == nil else { throw CocoaError(.fileWriteUnknown) }
        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.view?.frame = webView.bounds
        try await withCheckedThrowingContinuation { continuation in
            printed = continuation
            Self.activePrint = self
            armDeadline(seconds: 60)
            operation.runModal(for: window, delegate: self, didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
        }
        guard FileManager.default.fileExists(atPath: temporary.path) else { throw CocoaError(.fileWriteUnknown) }
        completed = true
    }

    private func armDeadline(seconds: Double) {
        deadline?.cancel()
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            self?.fail(URLError(.timedOut))
        }
    }

    func fail(_ error: Error) {
        deadline?.cancel()
        deadline = nil
        webView?.stopLoading()
        let loading = loaded, printing = printed
        loaded = nil
        printed = nil
        loading?.resume(throwing: error)
        printing?.resume(throwing: error)
    }

    /// AppKit calls this on the print operation's own thread.
    @objc nonisolated private func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        Task { @MainActor in
            let continuation = printed
            printed = nil
            if Self.activePrint === self { Self.activePrint = nil }
            if success { continuation?.resume() }
            else { continuation?.resume(throwing: CocoaError(.fileWriteUnknown)) }
            if continuation == nil, let temporaryURL { try? FileManager.default.removeItem(at: temporaryURL) }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded?.resume()
        loaded = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { fail(CocoaError(.fileReadUnknown)) }

    /// Only the page itself loads; links in the PDF stay links but are never followed here.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        navigationAction.navigationType == .other ? .allow : .cancel
    }
}
