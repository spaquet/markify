import AppKit
import MarkifyMarkdown
import Testing
@testable import Markify

@MainActor struct BackgroundParseTests {
    private func native(_ source: String) -> NativeEditor {
        NativeEditor(text: .constant(source), fileURL: nil, columnWidth: 640, markdownLens: false,
                     findQuery: "", matchCase: false, selectedRange: .constant(NSRange(location: 0, length: 0)),
                     textView: .constant(nil), onType: {}, onSlash: { _ in }, onSlashKey: { _, _ in false }, onSelectionRect: { _ in })
    }

    @Test func largeDocumentIsParsedOffTheMainThreadBeforeStyling() async throws {
        let source = "# Title\n\n" + String(repeating: "Paragraph **bold** *italic* [link](https://example.com).\n\n", count: 2000)
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.string = source
        #expect(editor.needsBackgroundParse)

        // Styling returns without parsing: the model is not built on the caller's thread.
        native(source).style(editor)
        #expect(editor.needsBackgroundParse)

        for _ in 0..<500 where editor.needsBackgroundParse { try await Task.sleep(for: .milliseconds(20)) }
        #expect(!editor.needsBackgroundParse)
        #expect(editor.model.spans.contains { if case .strong = $0.kind { true } else { false } })
    }

    @Test func inspectorWaitsForBackgroundParseInsteadOfParsingOnCaller() async throws {
        let source = "# Title\n\n" + String(repeating: "Paragraph **bold** *italic* [link](https://example.com).\n\n", count: 2001)
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.string = source
        let derived = DocumentDerivedData()

        // Nil while the parse is pending, and the editor's cache stays cold: the caller did not parse.
        #expect(derived.inspectorModel(in: source, mdx: false, editor: editor) == nil)
        #expect(editor.needsBackgroundParse)

        for _ in 0..<500 where editor.needsBackgroundParse { try await Task.sleep(for: .milliseconds(20)) }
        #expect(derived.inspectorModel(in: source, mdx: false, editor: editor) != nil)
    }

    @Test func modelReadsDuringBackgroundParseDoNotParseAgain() async throws {
        let source = "# Title\n\n" + String(repeating: "Paragraph **bold** *italic* [link](https://example.com).\n\n", count: 2002)
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.string = source

        // Drawing and clicks read the model while the parse runs: they see no spans and leave the cache cold.
        #expect(editor.model.spans.isEmpty)
        #expect(editor.needsBackgroundParse)

        for _ in 0..<500 where editor.needsBackgroundParse { try await Task.sleep(for: .milliseconds(20)) }
        #expect(!editor.model.spans.isEmpty)
    }

    @Test func identicalTextSetDuringParseKeepsTheResult() async throws {
        let source = "# Title\n\n" + String(repeating: "Paragraph **bold** *italic* [link](https://example.com).\n\n", count: 2003)
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.string = source
        _ = editor.model                 // starts the background parse
        editor.string = source           // same text, new version: must not drop the parse's result

        for _ in 0..<500 where editor.needsBackgroundParse { try await Task.sleep(for: .milliseconds(20)) }
        #expect(!editor.needsBackgroundParse)
    }

    @Test func secondEditorOfSameTextReusesTheParse() async throws {
        let source = "# Title\n\n" + String(repeating: "Paragraph **bold** *italic* [link](https://example.com).\n\n", count: 2004)
        let first = MarkdownTextView(usingTextLayoutManager: true)
        first.string = source
        _ = first.model
        for _ in 0..<500 where first.needsBackgroundParse { try await Task.sleep(for: .milliseconds(20)) }

        // A second editor with the same text takes the first editor's model: no parse of its own is needed.
        let second = MarkdownTextView(usingTextLayoutManager: true)
        second.string = source
        #expect(second.needsBackgroundParse)
        _ = second.model
        #expect(!second.needsBackgroundParse)
        #expect(second.model.spans.count == first.model.spans.count)
    }

    @Test func smallDocumentStillParsesSynchronously() {
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.string = "# Title\n\nSmall **bold** text.\n"
        #expect(!editor.needsBackgroundParse)
    }
}
