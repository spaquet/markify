import Foundation

/// The private helper returns only images referenced by a Markdown document, never arbitrary file contents.
@objc protocol PreviewImageProtocol {
    func images(for document: URL, reply: @escaping @Sendable ([String: String]) -> Void)
}
