import Foundation

/// The private helper reads referenced images and opens referenced Markdown files, never arbitrary contents.
@objc protocol PreviewImageProtocol {
    func images(for document: URL, reply: @escaping @Sendable ([String: String]) -> Void)
    func openMarkdown(_ target: URL, from document: URL, reply: @escaping @Sendable (String?) -> Void)
}
