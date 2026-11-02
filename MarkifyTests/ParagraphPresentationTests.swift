import AppKit
import MarkifyMarkdown
import Testing
@testable import Markify

@MainActor struct ParagraphPresentationTests {
    private func native(_ source: String, markdown: Bool = false, query: String = "") -> NativeEditor {
        NativeEditor(text: .constant(source), fileURL: nil, columnWidth: 640, markdownLens: markdown,
                     findQuery: query, matchCase: false, selectedRange: .constant(NSRange(location: 0, length: 0)),
                     textView: .constant(nil), onType: {}, onSlash: { _ in }, onSlashKey: { _, _ in false }, onSelectionRect: { _ in })
    }

    private func presented(_ editor: MarkdownTextView) throws -> NSAttributedString {
        let content = try #require(editor.textLayoutManager?.textContentManager as? NSTextContentStorage)
        let output = NSMutableAttributedString(string: "")
        content.enumerateTextElements(from: content.documentRange.location, options: []) { element in
            if let paragraph = element as? NSTextParagraph { output.append(paragraph.attributedString) }
            return true
        }
        return output
    }

    /// Code-token colors use fresh dynamic NSColor providers on each style pass. Compare
    /// their resolved appearance, rather than the identity of those provider objects.
    private func resolved(_ text: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
            var normalized = attributes
            for (key, value) in attributes {
                if let color = value as? NSColor { normalized[key] = color.usingColorSpace(.deviceRGB) ?? color }
                if let fill = value as? MarkdownBlockFill {
                    normalized[key] = MarkdownBlockFill(color: fill.color.usingColorSpace(.deviceRGB) ?? fill.color,
                                                        radius: fill.radius, padding: fill.padding, first: fill.first, last: fill.last)
                }
            }
            result.setAttributes(normalized, range: range)
        }
        return result
    }

    @Test(arguments: [false, true]) func textKitParagraphsMatchMaterializedStyles(markdown: Bool) throws {
        let source = "---\ntitle: Test\n---\n\n# Title **bold**\n\n***nested*** ~~strike~~ `code` \\*escape [link][ref] 👩🏽‍💻\n\n- **list**\n  continuation\n\n> quote *text*\n\n```swift\nlet x = 1\n```\n\n| **cell** | two |\n| --- | --- |\n| a | b |\n\n[ref]: other.md\n"
        let eager = MarkdownTextView(usingTextLayoutManager: true)
        eager.string = source
        let lazy = MarkdownTextView(usingTextLayoutManager: true)
        lazy.installParagraphPresentation()
        lazy.string = source
        let style = native(source, markdown: markdown)
        style.style(eager)
        style.style(lazy)
        let output = try presented(lazy)
        #expect(output.string == source)
        let expected = try #require(eager.textStorage)
        #expect(resolved(output).isEqual(to: resolved(expected)))
        #expect(lazy.string == source)
    }

    @Test(arguments: [false, true]) func plainListItemsMatchMaterializedStyles(markdown: Bool) throws {
        let source = "# List\n\n- **bullet** with [link](https://example.com)\n- [x] done *task*\n- `code` item\n\n1. ordered stays eager\n2. second\n\n- parent\n  - nested stays eager\n"
        let eager = MarkdownTextView(usingTextLayoutManager: true)
        eager.string = source
        let lazy = MarkdownTextView(usingTextLayoutManager: true)
        lazy.installParagraphPresentation()
        lazy.string = source
        let style = native(source, markdown: markdown)
        style.style(eager)
        style.style(lazy)
        let output = try presented(lazy)
        #expect(output.string == source)
        let expected = try #require(eager.textStorage)
        #expect(resolved(output).isEqual(to: resolved(expected)))
    }

    @Test func distantParagraphsDoNotMaterializeSourceAttributes() throws {
        let source = "# Title\n\n" + String(repeating: "Paragraph **bold** *italic* [link](https://example.com).\n\n", count: 1000)
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.installParagraphPresentation()
        editor.string = source
        native(source).style(editor)
        let storage = try #require(editor.textStorage)
        func runs() -> Int {
            var count = 0
            storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { _, _, _ in count += 1 }
            return count
        }
        let before = runs()
        #expect(before <= 2)
        // Force real TextKit content enumeration through the full document and repeat it.
        // Presentation may be requested anywhere without turning source into a styled copy.
        for _ in 0..<2 { #expect(try presented(editor).string == source) }
        #expect(runs() == before)
        #expect(editor.string == source)
    }

    @Test func teardownReleasesParagraphPresentation() {
        weak var released: ParagraphPresentation?
        autoreleasepool {
            let editor = MarkdownTextView(usingTextLayoutManager: true)
            editor.installParagraphPresentation()
            released = editor.paragraphPresentation
            editor.string = "**bold**\n"
            native(editor.string).style(editor)
            // AppKit may retain a view until its display transaction drains; the document's
            // explicit teardown must release the provider and its semantic snapshot now.
            editor.stopObserving()
        }
        #expect(released == nil)
    }

    @Test(arguments: [false, true]) func typingFontAndFindUsePresentedAttributes(markdown: Bool) throws {
        let source = "# Heading\n\n**bold** [visible](hidden-destination)\n"
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.installParagraphPresentation()
        editor.string = source
        editor.rendered = !markdown
        let style = native(source, markdown: markdown, query: "hidden-destination")
        style.style(editor)
        editor.setSelectedRange(NSRange(location: 5, length: 0))
        style.updateTypingFont(editor)
        #expect((editor.typingAttributes[.font] as? NSFont)?.pointSize == (markdown ? 16 : 36))
        let hidden = (source as NSString).range(of: "hidden-destination")
        #expect(editor.isVisible(hidden) == markdown)
        #expect(editor.isVisible((source as NSString).range(of: "visible")))
        #expect(style.findMatches(in: editor, storage: try #require(editor.textStorage), within: NSRange(location: 0, length: (source as NSString).length)).isEmpty == !markdown)
    }

    @Test func editingAndLensChangesReplaceParagraphPresentation() throws {
        let source = "# Title\n\n**bold** and text\n"
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.installParagraphPresentation()
        editor.string = source
        native(source).style(editor)
        let storage = try #require(editor.textStorage)
        let range = (source as NSString).range(of: "bold")
        storage.replaceCharacters(in: range, with: "changed 👩🏽‍💻")
        let changed = editor.string
        native(changed).style(editor, incremental: true)
        for markdown in [false, true, false] {
            let style = native(changed, markdown: markdown)
            style.style(editor)
            let eager = MarkdownTextView(usingTextLayoutManager: true)
            eager.string = changed
            style.style(eager)
            let expected = try #require(eager.textStorage)
            #expect(try resolved(presented(editor)).isEqual(to: resolved(expected)))
        }
        #expect(editor.string == changed)
    }

    @Test func incrementalFindChecksNewContextualStylesBeforeTheyReachLiveStorage() {
        let source = "- [visible](hidden-destination)\n"
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.installParagraphPresentation()
        editor.string = source
        native(source, query: "hidden-destination").style(editor, incremental: true)
        #expect(editor.findHighlights.isEmpty)
        #expect(!editor.isVisible((source as NSString).range(of: "hidden-destination")))
    }

    @Test func markerGeometryMatchesEagerLayout() throws {
        let source = "# Title\n\n[visible](https://example.com/é👩🏽‍💻) after **bold**\n"
        let (window, editor) = LayoutFragmentTests.makeEditor(source)
        window.isReleasedWhenClosed = false
        defer {
            editor.stopObserving()
            (window.contentView as? NSScrollView)?.documentView = nil
            window.contentView = nil
            window.close()
        }
        let after = (source as NSString).range(of: "after")
        let before = editor.textRect(after)
        #expect(before.width > 0)
        editor.installParagraphPresentation()
        native(source).style(editor)
        let manager = try #require(editor.textLayoutManager)
        manager.ensureLayout(for: manager.documentRange)
        let lazy = editor.textRect(after)
        #expect(lazy.width > 0)
        #expect(abs(before.minX - lazy.minX) < 1)
        #expect(abs(before.minY - lazy.minY) < 1)
        #expect(abs(before.width - lazy.width) < 1)
    }

    @Test func typingUndoAndRedoKeepSourceCoordinates() throws {
        let source = "# Title\n\n**bold** text\n"
        let (window, editor) = LayoutFragmentTests.makeEditor(source)
        window.isReleasedWhenClosed = false
        defer {
            editor.stopObserving()
            (window.contentView as? NSScrollView)?.documentView = nil
            window.contentView = nil
            window.close()
        }
        editor.installParagraphPresentation()
        editor.allowsUndo = true
        editor.isRichText = false
        window.makeFirstResponder(editor)
        let style = native(source)
        let coordinator = style.makeCoordinator()
        coordinator.editor = editor
        editor.delegate = coordinator
        style.style(editor)
        let undo = try #require(editor.undoManager)
        undo.groupsByEvent = false
        let location = (source as NSString).range(of: "text").location
        undo.beginUndoGrouping()
        editor.insertText("é👩🏽‍💻 ", replacementRange: NSRange(location: location, length: 0))
        undo.endUndoGrouping()
        let edited = editor.string
        #expect(edited.contains("é👩🏽‍💻 text"))
        #expect(try presented(editor).string == edited)
        undo.undo()
        #expect(editor.string == source)
        #expect(try presented(editor).string == source)
        undo.redo()
        #expect(editor.string == edited)
        #expect(try presented(editor).string == editor.string)
    }

    @Test(arguments: ["render-stress-test.md", "render-stress-test-2.md"])
    func stressDocumentParagraphsPreserveTheExistingAppearance(file: String) throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
        let model = MarkdownModel(source)
        let index = MarkdownModel.ParagraphStyles(model)
        let ns = source as NSString
        // Compare eligible paragraphs against their existing full-document styles. Contextual
        // blocks retain their old path; no diagram or image is rendered for this comparison.
        for markdown in [false, true] {
            let eager = NSTextView(usingTextLayoutManager: true)
            eager.string = source
            let style = native(source, markdown: markdown)
            style.style(eager, using: model)
            let lazy = MarkdownTextView(usingTextLayoutManager: true)
            lazy.installParagraphPresentation()
            lazy.string = source
            let presentation = try #require(lazy.paragraphPresentation)
            presentation.configure(style, model: model)
            var location = 0, compared = 0
            while location < ns.length {
                let range = ns.paragraphRange(for: NSRange(location: location, length: 0))
                if index.paragraph(range) != nil {
                    let actual = try #require(presentation.attributedParagraph(range))
                    let expected = try #require(eager.textStorage).attributedSubstring(from: range)
                    #expect(resolved(actual).isEqual(to: resolved(expected)), "\(file), paragraph at \(location), Markdown lens: \(markdown)")
                    compared += 1
                }
                location = NSMaxRange(range)
            }
            #expect(compared > 0)
            #expect(lazy.string == source)
        }
    }
}
