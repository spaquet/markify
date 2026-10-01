import Foundation
import MarkifyMarkdown
import Quartz
import UniformTypeIdentifiers
import AppKit
import WebKit

// Quick Look calls preparation on the main thread; its Objective-C protocol predates actor annotations.
@MainActor final class PreviewProvider: NSViewController, @preconcurrency QLPreviewingController, WKNavigationDelegate {
    // about:blank fragment navigation is unreliable across WebKit versions.
    private static let pageURL = URL(string: "https://markify.invalid/preview")!
    private var document: URL?
    private let webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        return WKWebView(frame: .zero, configuration: configuration)
    }()
    private let message = NSTextField(wrappingLabelWithString: "")

    override func loadView() {
        webView.navigationDelegate = self
        message.isSelectable = true
        message.isHidden = true
        message.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        let stack = NSStackView(views: [webView, message])
        stack.orientation = .vertical
        stack.alignment = .leading
        webView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        message.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        view = stack
        preferredContentSize = CGSize(width: 800, height: 1000)
    }

    func preparePreviewOfFile(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        document = url
        loadViewIfNeeded()
        Task {
            do {
                let html = try await html(for: url)
                webView.loadHTMLString(html, baseURL: Self.pageURL)
                completionHandler(nil)
            } catch { completionHandler(error) }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        // The only navigation inside the preview is its own page and fragment anchors.
        if url.absoluteString.split(separator: "#", maxSplits: 1).first == Substring(Self.pageURL.absoluteString) {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        guard action.navigationType == .linkActivated else { return }
        if let file = PreviewLinks.fileToOpen(url), let document {
            showMessage("Opening \(file.lastPathComponent)…", error: false)
            Task {
                let failure = await PreviewImageClient.openMarkdown(file, from: document)
                showMessage(failure ?? "Opened \(file.lastPathComponent) in Markify.", error: failure != nil)
            }
        } else if ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
            if !NSWorkspace.shared.open(url) { showMessage("Unable to open \(url.absoluteString).", error: true) }
        } else { showMessage("This link cannot be opened from the preview.", error: true) }
    }

    private func showMessage(_ text: String, error: Bool) {
        message.stringValue = text
        message.textColor = error ? .systemRed : .secondaryLabelColor
        message.isHidden = false
        NSAccessibility.post(element: message, notification: .valueChanged)
    }

    private func html(for file: URL) async throws -> String {
        let source = try String(contentsOf: file, encoding: .utf8)
        let images = await PreviewImageClient.images(for: file)
        let mdx = file.pathExtension.lowercased() == "mdx"
        var diagrams: [String: String] = [:]
        for span in MarkdownModel(source, mdx: mdx).spans {
            guard case .codeBlock(let language?, true) = span.kind, language.lowercased() == "mermaid" else { continue }
            let code = (source as NSString).substring(with: span.content)
            let key = code.trimmingCharacters(in: .whitespacesAndNewlines)
            if diagrams[key] == nil, let svg = await MermaidRenderer.shared.svg(for: code) { diagrams[key] = svg }
        }
        let options = MarkdownHTML.Options(
            math: { MathSVG.render($0, display: $1) },
            diagram: { language, code in
                language.lowercased() == "mermaid" ? diagrams[code.trimmingCharacters(in: .whitespacesAndNewlines)] : nil
            },
            image: { path in
                URL(string: path)?.scheme?.lowercased() == "https" ? path : images[path] ?? ""
            },
            link: { PreviewLinks.target($0, relativeTo: file) })
        let body = MarkdownHTML.render(source, mdx: mdx, options: options)
        let title = body.firstHeading ?? file.deletingPathExtension().lastPathComponent
        self.title = title
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data: https:; style-src 'unsafe-inline'; font-src data:">
        <title>\(MarkdownHTML.escape(title))</title><style>\(Self.style)</style></head>
        <body><main>\(body.body)</main></body></html>
        """
        return html
    }

    private static let style = """
    :root{color-scheme:light dark;--page:#FCFBF9;--ink:#1D1D1F;--muted:#6E6E73;--rule:#DDD;--code:#F3F1ED;--accent:#0A64D6}
    @media(prefers-color-scheme:dark){:root{--page:#1E1E20;--ink:#F2F2F7;--muted:#A1A1A6;--rule:#444;--code:#2A2A2D;--accent:#4C97FF}}
    *{box-sizing:border-box}body{margin:0;background:var(--page);color:var(--ink);font:18px/1.6 ui-serif,"New York",Georgia,serif}
    main{max-width:44rem;margin:auto;padding:2rem 2rem 4rem}h1,h2,h3,h4,h5,h6{line-height:1.2;margin:1.5em 0 .5em}h1{margin-top:0;font-size:2em}h2{font-size:1.5em}
    a{color:var(--accent)}img,svg{max-width:100%;height:auto}img{border-radius:8px}p.image,figure.diagram{text-align:center}
    pre,code{font:0.85em/1.5 ui-monospace,"SF Mono",Menlo,monospace}pre{background:var(--code);padding:1em;border-radius:10px;white-space:pre-wrap;overflow-wrap:anywhere}pre code{font-size:1em}
    :not(pre)>code{background:var(--code);padding:.1em .3em;border-radius:4px}pre.mdx{border:1px dashed var(--rule);background:none;color:var(--muted)}
    blockquote{margin-left:0;padding-left:1em;border-left:3px solid var(--rule)}.callout{border-left:3px solid var(--accent);background:var(--code);border-radius:8px;padding:.6em 1em}
    .callout-title{font-weight:bold}.table{overflow-x:auto}table{border-collapse:collapse;width:100%;font:15px/1.5 system-ui,sans-serif}td,th{padding:.5em;border-bottom:1px solid var(--rule);text-align:left}
    li.task{list-style:none}li.task>input{margin-left:-1.4em}.math.display{display:block;text-align:center;overflow-x:auto}.footnotes{border-top:1px solid var(--rule);color:var(--muted);font-size:.8em}
    hr{border:0;border-top:1px solid var(--rule)}
    """
}
