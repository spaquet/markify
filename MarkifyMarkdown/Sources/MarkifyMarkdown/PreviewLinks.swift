import Foundation

/// Local links in Quick Look use filesystem paths, without OKF bundle-root semantics.
public enum PreviewLinks {
    public static func target(_ destination: String, relativeTo document: URL) -> String {
        if destination.hasPrefix("#") { return destination }
        if let scheme = URL(string: destination)?.scheme, scheme.lowercased() != "file" {
            return ["http", "https", "mailto"].contains(scheme.lowercased()) ? destination : "#"
        }
        guard let url = localURL(destination, relativeTo: document) else { return "#" }
        // WebKit blocks file: navigation from an inline HTML page before calling its delegate.
        // This private scheme reaches the delegate, which cancels navigation and asks the trusted helper.
        var request = URLComponents()
        request.scheme = "markify-preview"
        request.host = "open"
        request.queryItems = [URLQueryItem(name: "file", value: url.absoluteString)]
        return request.url!.absoluteString
    }

    public static func fileToOpen(_ request: URL) -> URL? {
        guard let parts = URLComponents(url: request, resolvingAgainstBaseURL: false),
              parts.scheme == "markify-preview", parts.host == "open", parts.path.isEmpty,
              parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil,
              let items = parts.queryItems, items.count == 1, items[0].name == "file",
              let value = items[0].value, URL(string: value)?.isFileURL == true else { return nil }
        return localURL(value, relativeTo: URL(fileURLWithPath: "/"))
    }

    public static func localURL(_ destination: String, relativeTo document: URL) -> URL? {
        let path = String(destination.prefix { $0 != "#" && $0 != "?" })
        guard !path.isEmpty else { return nil }
        if let url = URL(string: path), let scheme = url.scheme {
            guard scheme.lowercased() == "file", url.host == nil || url.host == "" || url.host == "localhost",
                  let decoded = URLComponents(string: path)?.percentEncodedPath.removingPercentEncoding,
                  !decoded.contains("\0") else { return nil }
            return URL(fileURLWithPath: decoded).standardizedFileURL
        }
        guard let decoded = path.removingPercentEncoding, !decoded.contains("\0") else { return nil }
        return URL(fileURLWithPath: decoded, relativeTo: document.deletingLastPathComponent()).standardizedFileURL
    }

    /// The trusted helper may open only Markdown files actually linked by the previewed source.
    public static func referencedMarkdown(_ requested: URL, in source: String, from document: URL) throws -> URL {
        guard requested.isFileURL, let target = localURL(requested.absoluteString, relativeTo: document),
              ["md", "markdown", "mdx"].contains(target.pathExtension.lowercased()) else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        var referenced = false
        _ = MarkdownHTML.render(source, mdx: document.pathExtension.lowercased() == "mdx", options: .init(link: { destination in
            if localURL(destination, relativeTo: document) == target { referenced = true }
            return destination
        }))
        guard referenced else { throw CocoaError(.fileReadNoPermission) }
        return target
    }
}
