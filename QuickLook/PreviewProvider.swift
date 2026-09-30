import Foundation
import MarkifyMarkdown
import Quartz
import UniformTypeIdentifiers

final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let file = request.fileURL
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
            link: { Self.link($0, relativeTo: file) })
        let body = MarkdownHTML.render(source, mdx: mdx, options: options)
        let title = body.firstHeading ?? file.deletingPathExtension().lastPathComponent
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data: https:; style-src 'unsafe-inline'; font-src data:">
        <title>\(MarkdownHTML.escape(title))</title><style>\(Self.style)</style></head>
        <body><main>\(body.body)</main></body></html>
        """
        let reply = QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 800, height: 1000)) { _ in Data(html.utf8) }
        reply.title = title
        return reply
    }

    private static func link(_ destination: String, relativeTo file: URL) -> String {
        if destination.hasPrefix("#") { return destination }
        if let scheme = URL(string: destination)?.scheme {
            return ["http", "https", "mailto"].contains(scheme.lowercased()) ? destination : "#"
        }
        let split = destination.firstIndex { $0 == "#" || $0 == "?" }
        let path = String(destination[..<(split ?? destination.endIndex)])
        let suffix = split.map { String(destination[$0...]) } ?? ""
        return (localURL(path, relativeTo: file)?.absoluteString ?? "#") + suffix
    }

    private static func localURL(_ path: String, relativeTo file: URL) -> URL? {
        guard !path.isEmpty, URL(string: path)?.scheme == nil else { return nil }
        let decoded = path.removingPercentEncoding ?? path
        return URL(fileURLWithPath: decoded, relativeTo: file.deletingLastPathComponent()).standardizedFileURL
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
