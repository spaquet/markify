import Foundation
import NaturalLanguage
import UniformTypeIdentifiers

/// The HTML page and local path rules shared by the app and command-line export.
public enum MarkdownPage {
    public struct Context {
        public let source: String
        public let documentURL: URL?
        public let bundleRoot: URL?
        public let destination: URL
        public let fallbackTitle: String
        public let baseDirectory: URL?

        public init(source: String, documentURL: URL?, bundleRoot: URL? = nil, destination: URL, fallbackTitle: String, baseDirectory: URL? = nil) {
            self.source = source
            self.documentURL = documentURL
            self.bundleRoot = bundleRoot
            self.destination = destination
            self.fallbackTitle = fallbackTitle
            self.baseDirectory = baseDirectory
        }
    }

    public static func html(_ context: Context, math: @escaping (String, Bool) -> String? = { _, _ in nil },
                            diagram: @escaping (String, String) -> String? = { _, _ in nil },
                            highlight: @escaping (String, String?) -> String? = { _, _ in nil },
                            pdf: Bool = false, remoteImages: Bool = true) -> String {
        let options = MarkdownHTML.Options(math: math, diagram: diagram,
            image: { imageSource($0, context: context) }, link: { linkTarget($0, context: context) }, highlight: highlight)
        let result = MarkdownHTML.render(context.source, mdx: context.documentURL?.pathExtension.lowercased() == "mdx", options: options)
        let metadata = metadata(context.source)
        let title = metadata.title ?? result.firstHeading ?? context.fallbackTitle
        let language = NLLanguageRecognizer.dominantLanguage(for: context.source)?.rawValue ?? "en"
        var body = ""
        if metadata.date != nil || !metadata.tags.isEmpty {
            body += "<header class=\"meta\">"
            if let date = metadata.date { body += "<span class=\"chip date\">\(MarkdownHTML.escape(date))</span>" }
            for tag in metadata.tags { body += "<span class=\"chip\">\(MarkdownHTML.escape(tag))</span>" }
            body += "</header>\n"
        }
        body += result.body
        var head = "<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n<meta name=\"generator\" content=\"Markify\">\n<meta name=\"color-scheme\" content=\"light dark\">\n"
        if pdf {
            head += "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'; img-src data:\(remoteImages ? " https: http:" : ""); font-src data:\">\n"
        }
        head += "<title>\(MarkdownHTML.escape(title))</title>\n<style>\n\(stylesheet)</style>\n"
        return "<!doctype html>\n<html lang=\"\(language)\">\n<head>\n\(head)</head>\n<body>\n<main>\n<article>\n\(body)</article>\n</main>\n</body>\n</html>\n"
    }

    public static func imageSource(_ source: String, context: Context) -> String {
        if let base = context.baseDirectory, !base.isFileURL {
            return URL(string: source, relativeTo: base)?.absoluteURL.absoluteString ?? source
        }
        guard let url = localURL(source, context: context) else { return source }
        let extensionName = url.pathExtension.lowercased()
        let mime = UTType(filenameExtension: extensionName)?.preferredMIMEType ?? [
            "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif",
            "webp": "image/webp", "svg": "image/svg+xml", "tif": "image/tiff", "tiff": "image/tiff",
            "heic": "image/heic"
        ][extensionName]
        guard let data = try? Data(contentsOf: url), data.count < 25_000_000,
              let type = mime else {
            return relative(url, from: context.destination)
        }
        return "data:\(type);base64,\(data.base64EncodedString())"
    }

    public static func linkTarget(_ destination: String, context: Context) -> String {
        if !destination.hasPrefix("#"), let base = context.baseDirectory, !base.isFileURL {
            return URL(string: destination, relativeTo: base)?.absoluteURL.absoluteString ?? destination
        }
        guard !destination.hasPrefix("#"), context.documentURL != nil || context.baseDirectory != nil || destination.hasPrefix("/") else { return destination }
        let split = destination.firstIndex { $0 == "#" || $0 == "?" }
        let path = String(destination[..<(split ?? destination.endIndex)])
        let suffix = split.map { String(destination[$0...]) } ?? ""
        guard !path.isEmpty, let url = localURL(path, context: context) else { return destination }
        return relative(url, from: context.destination) + suffix
    }

    private static func localURL(_ path: String, context: Context) -> URL? {
        guard !path.isEmpty, URL(string: path)?.scheme == nil || path.hasPrefix("/") else { return nil }
        let decoded = path.removingPercentEncoding ?? path
        if decoded.hasPrefix("/"), let root = context.bundleRoot {
            return root.appendingPathComponent(String(decoded.dropFirst())).standardizedFileURL
        }
        return URL(fileURLWithPath: decoded, relativeTo: context.documentURL?.deletingLastPathComponent() ?? context.baseDirectory ?? URL(fileURLWithPath: "/")).standardizedFileURL
    }

    private static func relative(_ url: URL, from destination: URL) -> String {
        let from = destination.deletingLastPathComponent().standardizedFileURL.pathComponents
        let to = url.standardizedFileURL.pathComponents
        var shared = 0
        while shared < min(from.count, to.count), from[shared] == to[shared] { shared += 1 }
        let path = (Array(repeating: "..", count: from.count - shared) + to.dropFirst(shared)).joined(separator: "/")
        return path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
    }

    private static func metadata(_ source: String) -> (title: String?, tags: [String], date: String?) {
        let ns = source as NSString
        guard source.hasPrefix("---\n"), let fence = try? NSRegularExpression(pattern: #"(?m)^---[ \t]*$"#),
              let close = fence.firstMatch(in: source, range: NSRange(location: 4, length: ns.length - 4)) else {
            return (nil, [], nil)
        }
        var title: String?
        var tags: [String] = []
        var date: String?
        var inTagList = false
        for line in ns.substring(with: NSRange(location: 4, length: close.range.location - 4)).components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if inTagList, trimmed.hasPrefix("- ") { tags.append(clean(String(trimmed.dropFirst(2)))); continue }
            inTagList = false
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = trimmed[..<colon].lowercased()
            let value = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            switch key {
            case "title": title = clean(value)
            case "date": date = clean(value)
            case "tags":
                if value.isEmpty { inTagList = true }
                else { tags = value.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).split(separator: ",").map { clean(String($0)) } }
            default: break
            }
        }
        if let date {
            let parser = DateFormatter()
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.dateFormat = "yyyy-MM-dd"
            if let parsed = parser.date(from: String(date.prefix(10))) {
                return (title?.isEmpty == true ? nil : title, tags.filter { !$0.isEmpty }, parsed.formatted(date: .abbreviated, time: .omitted))
            }
        }
        return (title?.isEmpty == true ? nil : title, tags.filter { !$0.isEmpty }, date?.isEmpty == true ? nil : date)
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    public static let stylesheet = """
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
