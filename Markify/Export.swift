import AppKit
import MarkifyMarkdown
import NaturalLanguage
import OKFKit
import SwaTex
import SwaTexRender
import UniformTypeIdentifiers
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
    }

    enum Format { case html, pdf }

    /// A complete HTML page for the document.
    static func page(_ context: Context, for format: Format) async -> String {
        let mdx = MarkdownTextView.isMDX(context.documentURL)
        // Mermaid renders asynchronously in its web view, so diagrams are ready before the synchronous render.
        var diagrams: [String: String] = [:]
        for span in MarkdownModel(context.source, mdx: mdx).spans {
            guard case .codeBlock(let language?, true) = span.kind, language.lowercased() == "mermaid" else { continue }
            let code = (context.source as NSString).substring(with: span.content)
            let key = code.trimmingCharacters(in: .whitespacesAndNewlines)
            if diagrams[key] == nil, let svg = await MermaidRenderer.shared.svg(for: code) { diagrams[key] = svg }
        }
        let options = MarkdownHTML.Options(
            math: { latex, display in MathSVG.render(latex, display: display) },
            diagram: { language, code in
                language.lowercased() == "mermaid" ? diagrams[code.trimmingCharacters(in: .whitespacesAndNewlines)] : nil
            },
            image: { imageSource($0, context: context) },
            link: { linkTarget($0, context: context) },
            highlight: { code, _ in highlighted(code) })
        let result = MarkdownHTML.render(context.source, mdx: mdx, options: options)
        let frontmatter = Frontmatter.parse(context.source)
        let title = frontmatter?.title ?? result.firstHeading ?? context.fallbackTitle
        let language = NLLanguageRecognizer.dominantLanguage(for: context.source)?.rawValue ?? "en"

        var head = "<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
        head += "<meta name=\"generator\" content=\"Markify\">\n<meta name=\"color-scheme\" content=\"light dark\">\n"
        if format == .pdf {
            // The PDF is printed from this page: no scripts from raw HTML, and remote images only when Settings allows them.
            let remote = UserDefaults.standard.object(forKey: "loadRemoteImages") as? Bool ?? true
            head += "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'; img-src data:\(remote ? " https: http:" : ""); font-src data:\">\n"
        }
        head += "<title>\(MarkdownHTML.escape(title))</title>\n<style>\n\(stylesheet)</style>\n"

        var body = ""
        if let frontmatter, frontmatter.displayDate != nil || !frontmatter.tags.isEmpty {
            body += "<header class=\"meta\">"
            if let date = frontmatter.displayDate { body += "<span class=\"chip date\">\(MarkdownHTML.escape(date))</span>" }
            for tag in frontmatter.tags { body += "<span class=\"chip\">\(MarkdownHTML.escape(tag))</span>" }
            body += "</header>\n"
        }
        body += result.body
        return "<!doctype html>\n<html lang=\"\(language)\">\n<head>\n\(head)</head>\n<body>\n<main>\n<article>\n\(body)</article>\n</main>\n</body>\n</html>\n"
    }

    static func writeHTML(_ context: Context) async throws {
        try await page(context, for: .html).write(to: context.destination, atomically: true, encoding: .utf8)
    }

    static func writePDF(_ context: Context) async throws {
        let html = await page(context, for: .pdf)
        try await PDFPrinter().print(html, to: context.destination)
    }

    // MARK: Images and links

    /// A local image as a data URI, so the page stands alone; remote and data sources stay as written.
    static func imageSource(_ source: String, context: Context) -> String {
        guard let url = localURL(source, context: context) else { return source }
        guard let data = try? Data(contentsOf: url), data.count < 25_000_000,
              let type = UTType(filenameExtension: url.pathExtension.lowercased())?.preferredMIMEType else {
            return relative(url, from: context.destination)
        }
        return "data:\(type);base64,\(data.base64EncodedString())"
    }

    /// Relative and bundle-absolute links rewritten to reach the same file from where the export lands.
    static func linkTarget(_ destination: String, context: Context) -> String {
        guard !destination.hasPrefix("#"), context.documentURL != nil || destination.hasPrefix("/") else { return destination }
        let split = destination.firstIndex { $0 == "#" || $0 == "?" }
        let path = String(destination[..<(split ?? destination.endIndex)])
        let suffix = split.map { String(destination[$0...]) } ?? ""
        guard !path.isEmpty, let url = localURL(path, context: context) else { return destination }
        return relative(url, from: context.destination) + suffix
    }

    /// The file a path in the document names, or nil for URLs with a scheme.
    private static func localURL(_ path: String, context: Context) -> URL? {
        guard !path.isEmpty, URL(string: path)?.scheme == nil || path.hasPrefix("/") else { return nil }
        let decoded = path.removingPercentEncoding ?? path
        if decoded.hasPrefix("/"), let root = context.bundleRoot { return root.appendingPathComponent(String(decoded.dropFirst())).standardizedFileURL }
        return MarkdownTextView.imageURL(path, document: context.documentURL)
    }

    private static func relative(_ url: URL, from destination: URL) -> String {
        let path = OKFLinks.relativePath(to: url, from: destination.deletingLastPathComponent())
        return path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
    }

    // MARK: Code

    /// Code with the editor's token colors as spans; a later token wins where they overlap, as in the editor.
    static func highlighted(_ code: String) -> String {
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

    // MARK: Style

    static let stylesheet = """
    :root{--page:#FCFBF9;--ink:#1D1D1F;--ink2:#6E6E73;--rule:rgba(0,0,0,.1);--field:rgba(0,0,0,.05);--code:#F3F1ED;
      --accent:#0A64D6;--tip:#248A3D;--warning:#C93400;--important:#8944AB;
      --kw:#AD3DA4;--typ:#3F6E74;--lit:#C41A16;--com:#6E737A;color-scheme:light dark}
    @media (prefers-color-scheme:dark){:root{--page:#1E1E20;--ink:#F2F2F7;--ink2:#A1A1A6;--rule:rgba(255,255,255,.14);
      --field:rgba(255,255,255,.08);--code:#2A2A2D;--accent:#4C97FF;--tip:#4CD964;--warning:#FF9F0A;--important:#DA8FFF;
      --kw:#FF7AB2;--typ:#78C2B3;--lit:#D9C97C;--com:#98A1AB}}
    *{box-sizing:border-box}
    html{-webkit-text-size-adjust:100%}
    body{margin:0;background:var(--page);color:var(--ink);font:18px/1.6 ui-serif,"New York",Charter,Georgia,serif;-webkit-font-smoothing:antialiased}
    main{max-width:44rem;margin:0 auto;padding:4rem 1.5rem 6rem}
    h1,h2,h3,h4,h5,h6{line-height:1.2;margin:1.8em 0 .5em;font-weight:700;text-wrap:balance}
    h1{font-size:2.2em;margin-top:0}h2{font-size:1.55em}h3{font-size:1.25em}h4,h5,h6{font-size:1em}
    p,ul,ol,pre,blockquote,.table,.callout,figure,.math.display{margin:0 0 1em}
    a{color:var(--accent);text-underline-offset:.15em}
    strong{font-weight:700}
    del{color:var(--ink2)}
    hr{border:0;border-top:1px solid var(--rule);margin:2em 0}
    img{max-width:100%;height:auto;border-radius:8px;vertical-align:middle}
    p.image{text-align:center}
    code,pre{font-family:ui-monospace,"SF Mono",Menlo,monospace;font-size:.82em}
    :not(pre)>code{background:var(--field);padding:.1em .35em;border-radius:5px}
    pre{position:relative;background:var(--code);border-radius:12px;padding:1em 1.15em;overflow-x:auto;line-height:1.5;white-space:pre-wrap;word-wrap:break-word}
    pre code{font-size:1em}
    .code-label{position:absolute;top:.45em;right:.8em;font:600 11px -apple-system,system-ui,sans-serif;color:var(--ink2);text-transform:lowercase}
    .tok-keyword{color:var(--kw)}.tok-type{color:var(--typ)}.tok-literal{color:var(--lit)}.tok-comment{color:var(--com)}
    pre.mdx{background:none;border:1px dashed var(--rule);color:var(--ink2)}
    blockquote{margin-left:0;padding-left:1em;border-left:3px solid var(--rule);color:var(--ink2)}
    .callout{--c:var(--accent);border-radius:12px;padding:.9em 1.15em;background:color-mix(in srgb,var(--c) 8%,transparent);border-left:3px solid var(--c)}
    .callout-tip{--c:var(--tip)}.callout-warning{--c:var(--warning)}.callout-important{--c:var(--important)}
    .callout>:last-child{margin-bottom:0}
    .callout-title{font:600 .78em -apple-system,system-ui,sans-serif;color:var(--c);margin-bottom:.4em}
    ul,ol{padding-left:1.6em}
    li>ul,li>ol{margin:.25em 0 0}
    li{margin:.2em 0}
    li.task{list-style:none}
    li.task>input{margin:0 .45em 0 -1.35em;width:.9em;vertical-align:.05em;accent-color:var(--accent)}
    .table{overflow-x:auto}
    table{border-collapse:collapse;font:15px/1.45 -apple-system,system-ui,sans-serif;min-width:50%}
    th,td{border-bottom:1px solid var(--rule);padding:.5em .8em;text-align:left;vertical-align:top}
    th{font-weight:600;border-bottom-width:2px}
    .math.display{display:block;text-align:center;overflow-x:auto}
    .math svg{display:inline-block}
    figure.diagram{margin:0 0 1em;text-align:center}
    figure.diagram svg{max-width:100%;height:auto;background:#fff;border-radius:10px;padding:8px}
    .meta{display:flex;flex-wrap:wrap;gap:6px;margin-bottom:1.5em;font:500 12.5px -apple-system,system-ui,sans-serif}
    .chip{background:var(--field);color:var(--ink2);border-radius:999px;padding:3px 10px}
    .footnote-ref a{text-decoration:none;font:600 .7em -apple-system,system-ui,sans-serif;padding:0 .15em}
    .footnotes{margin-top:3em;padding-top:1em;border-top:1px solid var(--rule);font:14px/1.5 -apple-system,system-ui,sans-serif;color:var(--ink2)}
    .footnotes ol{padding-left:1.4em}
    .footnote-back{text-decoration:none}
    .visually-hidden{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0);white-space:nowrap}
    @media print{
      :root{--page:#fff;--ink:#000;--ink2:#555;--code:#F4F3F0}
      body{font-size:11.5pt}
      main{max-width:none;padding:0}
      *{-webkit-print-color-adjust:exact;print-color-adjust:exact}
      h1,h2,h3,h4,h5,h6{break-after:avoid}
      pre,blockquote,.callout,figure,.math.display,tr,img{break-inside:avoid}
      pre{white-space:pre-wrap}
      a{color:inherit;text-decoration-color:var(--rule)}
      figure.diagram svg{padding:0}
    }

    """
}

// MARK: - Math

/// LaTeX to self-contained SVG with glyph outlines, sized in `em` so it follows the surrounding text.
enum MathSVG {
    private static let unit = 20.0

    static func render(_ latex: String, display: Bool) -> String? {
        guard let list = try? SwaTexEngine.displayList(for: latex, style: display ? .display : .text, color: .black) else { return nil }
        let svg = renderToSVG(list, SVGOptions(fontSize: unit, padding: 0, embedGlyphs: true, glyphProvider: Glyphs()))
        guard let open = svg.range(of: ">") else { return nil }
        let width = format(list.width), height = format(list.height + list.depth), viewBox = "0 0 \(format(list.width * unit)) \(format((list.height + list.depth) * unit))"
        let label = MarkdownHTML.escape(latex)
        let header = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"\(viewBox)\" width=\"\(width)em\" height=\"\(height)em\""
            + " style=\"vertical-align:-\(format(list.depth))em\" role=\"img\" aria-label=\"\(label)\"><title>\(label)</title>"
        return header + svg[open.upperBound...].replacingOccurrences(of: "rgba(0,0,0,1)", with: "currentColor")
    }

    private static func format(_ value: Double) -> String { String(format: "%.4g", value) }

    /// KaTeX glyphs as outlines from the fonts SwaTexRender bundles, so the SVG needs no web fonts.
    private struct Glyphs: SVGStandaloneGlyphProvider {
        func standaloneGlyph(x: Float, y: Float, glyphEm: Float, font: String, charCode: UInt32) -> SVGStandaloneGlyph? {
            guard let id = FontId(rawValue: font) else { return nil }
            let ctFont = KaTeXFontProvider.shared.font(for: id, size: CGFloat(glyphEm))
            var characters = Array(String(Character(id.ttfGlyphScalar(forDisplayCharCode: charCode))).utf16)
            var glyphs = [CGGlyph](repeating: 0, count: characters.count)
            guard CTFontGetGlyphsForCharacters(ctFont, &characters, &glyphs, characters.count), glyphs[0] != 0,
                  let path = CTFontCreatePathForGlyph(ctFont, glyphs[0], nil) else { return nil }
            let px = CGFloat(x), py = CGFloat(y)
            func point(_ p: CGPoint) -> String { "\(String(format: "%.2f", px + p.x)) \(String(format: "%.2f", py - p.y))" }
            var d = ""
            path.applyWithBlock { element in
                let points = element.pointee.points
                switch element.pointee.type {
                case .moveToPoint: d += "M\(point(points[0]))"
                case .addLineToPoint: d += "L\(point(points[0]))"
                case .addQuadCurveToPoint: d += "Q\(point(points[0])) \(point(points[1]))"
                case .addCurveToPoint: d += "C\(point(points[0])) \(point(points[1])) \(point(points[2]))"
                case .closeSubpath: d += "Z"
                @unknown default: break
                }
            }
            return d.isEmpty ? nil : .path(d)
        }
    }
}

// MARK: - PDF

/// Prints an HTML page to a paginated PDF with WebKit, on the paper size and margins of the default print setup.
@MainActor final class PDFPrinter: NSObject, WKNavigationDelegate {
    private var loaded: CheckedContinuation<Void, Error>?
    private var printed: CheckedContinuation<Bool, Never>?

    func print(_ html: String, to url: URL) async throws {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        info.topMargin = 54; info.bottomMargin = 54; info.leftMargin = 60; info.rightMargin = 60
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false

        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: info.paperSize.height), configuration: configuration)
        webView.navigationDelegate = self
        // Printing needs the view in a window; this one never appears on screen.
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: width, height: info.paperSize.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = webView
        defer { window.contentView = nil }

        try await withCheckedThrowingContinuation { continuation in
            loaded = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }
        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.view?.frame = webView.bounds
        let success = await withCheckedContinuation { continuation in
            printed = continuation
            operation.runModal(for: window, delegate: self, didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
        }
        guard success, FileManager.default.fileExists(atPath: url.path) else { throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path]) }
    }

    /// AppKit calls this on the print operation's own thread.
    @objc nonisolated private func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        Task { @MainActor in
            printed?.resume(returning: success)
            printed = nil
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded?.resume()
        loaded = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loaded?.resume(throwing: error)
        loaded = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loaded?.resume(throwing: error)
        loaded = nil
    }

    /// Only the page itself loads; links in the PDF stay links but are never followed here.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        navigationAction.navigationType == .other ? .allow : .cancel
    }
}
