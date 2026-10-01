import Foundation
import ImageIO
import MarkifyMarkdown
import Security
import UniformTypeIdentifiers
import AppKit

enum PreviewImages {
    static func load(from document: URL) -> [String: String] {
        // ponytail: previews cap source at 2 MB and 128 images / 50 MB; stream image replies if larger previews are needed.
        guard document.isFileURL, ["md", "markdown", "mdx"].contains(document.pathExtension.lowercased()),
              let data = read(document, limit: 2_000_000), let source = String(data: data, encoding: .utf8) else { return [:] }
        var images: [String: String] = [:]
        var visited: Set<String> = []
        var remaining = 50_000_000
        _ = MarkdownHTML.render(source, mdx: document.pathExtension.lowercased() == "mdx", options: .init(image: { path in
            guard visited.count < 128, visited.insert(path).inserted, URL(string: path)?.scheme == nil else { return "" }
            let url = URL(fileURLWithPath: path.removingPercentEncoding ?? path,
                          relativeTo: document.deletingLastPathComponent()).resolvingSymlinksInPath()
            guard let data = read(url, limit: min(25_000_000, remaining)), let mime = mime(data, at: url) else { return "" }
            remaining -= data.count
            images[path] = "data:\(mime);base64,\(data.base64EncodedString())"
            return ""
        }))
        return images
    }

    private static func mime(_ data: Data, at url: URL) -> String? {
        if let image = CGImageSourceCreateWithData(data as CFData, nil), let identifier = CGImageSourceGetType(image) {
            return UTType(identifier as String)?.preferredMIMEType
        }
        if url.pathExtension.lowercased() == "svg",
           let xml = try? XMLDocument(data: data, options: .nodeLoadExternalEntitiesNever), xml.rootElement()?.localName == "svg" {
            return "image/svg+xml"
        }
        return nil
    }

    static func read(_ url: URL, limit: Int) -> Data? {
        guard limit > 0,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, let size = values.fileSize, size <= limit,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: limit + 1), data.count <= limit else { return nil }
        return data
    }
}

final class PreviewImageService: NSObject, NSXPCListenerDelegate, PreviewImageProtocol {
    private let clientRequirement: String? = {
        // The service is inside the preview extension. Its designated requirement also works for ad hoc builds.
        let client = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var code: SecStaticCode?
        var requirement: SecRequirement?
        var text: CFString?
        guard SecStaticCodeCreateWithPath(client as CFURL, [], &code) == errSecSuccess, let code,
              SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess, let requirement,
              SecRequirementCopyString(requirement, [], &text) == errSecSuccess else { return nil }
        return text as String?
    }()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard let clientRequirement else { return false }
        connection.setCodeSigningRequirement(clientRequirement)
        connection.exportedInterface = NSXPCInterface(with: PreviewImageProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func images(for document: URL, reply: @escaping @Sendable ([String: String]) -> Void) {
        reply(PreviewImages.load(from: document))
    }

    func openMarkdown(_ target: URL, from document: URL, reply: @escaping @Sendable (String?) -> Void) {
        do {
            guard document.isFileURL, ["md", "markdown", "mdx"].contains(document.pathExtension.lowercased()),
                  let data = PreviewImages.read(document, limit: 2_000_000),
                  let source = String(data: data, encoding: .utf8) else {
                throw CocoaError(.fileReadNoPermission, userInfo: [NSFilePathErrorKey: document.path])
            }
            let file = try PreviewLinks.referencedMarkdown(target, in: source, from: document)
            let values = try file.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { throw CocoaError(.fileReadUnsupportedScheme, userInfo: [NSFilePathErrorKey: file.path]) }
            // Check readability here so the preview can explain missing or inaccessible destinations.
            let handle = try FileHandle(forReadingFrom: file)
            try handle.close()
            let app = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            DispatchQueue.main.async {
                NSWorkspace.shared.open([file], withApplicationAt: app, configuration: .init()) { _, error in
                    reply(error?.localizedDescription)
                }
            }
        } catch { reply("Unable to open \(target.lastPathComponent): \(error.localizedDescription)") }
    }
}
