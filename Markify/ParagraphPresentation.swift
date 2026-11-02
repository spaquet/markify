import AppKit
import MarkifyMarkdown

/// Supplies transient styled paragraphs to TextKit. Source storage keeps baseline attributes
/// and contextual block styling; ordinary prose never acquires a document-wide run array.
/// TextKit owns the returned elements. We retain only one reusable paragraph-sized scratch view.
@MainActor final class ParagraphPresentation: NSObject, @preconcurrency NSTextContentStorageDelegate {
    private weak var editor: MarkdownTextView?
    private var index: MarkdownModel.ParagraphStyles?
    private var version: Int?
    private var mdx: Bool?
    private var native: NativeEditor?
    private let scratch = NSTextView()
    var baseAttributes: [NSAttributedString.Key: Any] = [:]

    init(editor: MarkdownTextView) {
        self.editor = editor
    }

    func configure(_ native: NativeEditor, model: MarkdownModel) {
        guard let editor else { return }
        if version != editor.textVersion || mdx != model.mdx || index == nil {
            index = MarkdownModel.ParagraphStyles(model)
            version = editor.textVersion
            mdx = model.mdx
        }
        // Keep presentation settings, not the document's SwiftUI bindings or callbacks: a
        // textView binding can itself hold this editor and would close an ownership cycle.
        self.native = NativeEditor(text: .constant(""), fileURL: nil, columnWidth: native.columnWidth,
                                   markdownLens: native.markdownLens, findQuery: native.findQuery, matchCase: native.matchCase,
                                   selectedRange: .constant(NSRange(location: 0, length: 0)), textView: .constant(nil),
                                   onType: {}, onSlash: { _ in }, onSlashKey: { _, _ in false }, onSelectionRect: { _ in },
                                   theme: native.theme, currentMatch: native.currentMatch)
        scratch.appearance = editor.effectiveAppearance
    }

    var eagerSpans: [MarkdownModel.Span]? { index?.eagerSpans }

    func attributedParagraph(_ range: NSRange) -> NSAttributedString? {
        guard let editor, version == editor.textVersion, let model = index?.paragraph(range), var native else { return nil }
        return autoreleasepool {
            scratch.string = model.source
            native.currentMatch = native.currentMatch.flatMap { match in
                guard match.location >= range.location, NSMaxRange(match) <= NSMaxRange(range) else { return nil }
                return NSRange(location: match.location - range.location, length: match.length)
            }
            native.style(scratch, using: model)
            return scratch.textStorage.map { NSAttributedString(attributedString: $0) }
        }
    }

    func textContentStorage(_ textContentStorage: NSTextContentStorage, textParagraphWith range: NSRange) -> NSTextParagraph? {
        attributedParagraph(range).map { NSTextParagraph(attributedString: $0) }
    }
}
