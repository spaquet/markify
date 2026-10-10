import AppKit
import SwiftUI
import Testing
@testable import Markify

/// Typing restyles only what changed, so TextKit keeps the layout of the rest of the document.
@MainActor struct IncrementalStyleTests {
    @Test func renderRefreshLeavesUnchangedTextUntouched() throws {
        let host = NSHostingView(rootView: Self.native(Self.source))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        func editor(in view: NSView) -> MarkdownTextView? {
            if let editor = view as? MarkdownTextView { return editor }
            return view.subviews.lazy.compactMap { editor(in: $0) }.first
        }
        let editor = try #require(editor(in: host))
        let storage = try #require(editor.textStorage)
        var edited: [NSRange] = []
        let watched = ObjectIdentifier(storage)
        let observer = NotificationCenter.default.addObserver(forName: NSTextStorage.didProcessEditingNotification, object: nil, queue: nil) { notification in
            guard let changed = notification.object as? NSTextStorage, ObjectIdentifier(changed) == watched else { return }
            let range = changed.editedRange
            MainActor.assumeIsolated { edited.append(range) }
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
            editor.stopObserving()
            window.contentView = nil
        }
        editor.restyle?()
        #expect(edited.isEmpty)
        #expect(editor.string == Self.source)
    }

    @Test func paragraphFastPathMatchesFullStylingAcrossInlineAndBlockChanges() {
        for insertion in ["text", "**bold** ", "[web](https://example.com) ", "\n", "## ", "[ref]: https://example.com\n"] {
            let editor = MarkdownTextView(usingTextLayoutManager: true)
            editor.string = "# Title\n\nParagraph with *emphasis*.\n\nTail.\n"
            Self.native(editor.string).style(editor)
            let end = (editor.string as NSString).range(of: "Tail.").location
            editor.textStorage!.replaceCharacters(in: NSRange(location: end, length: 0), with: insertion)
            Self.native(editor.string).style(editor, incremental: true)
            let incremental = NSAttributedString(attributedString: editor.textStorage!)
            Self.native(editor.string).style(editor)
            #expect(incremental.isEqual(to: editor.textStorage!), "inserting \(insertion)")
        }
    }

    /// Every kind of block that shows an asset, beside plain text the partial pass must leave alone.
    static let assetFixture = "# Title\n\nPlain paragraph with **bold**.\n\n![Alt](pic.png)\n\n"
        + "Inline ![chip](pic.png) and <img src=\"https://example.com/a.png\" width=\"40\"> here.\n\n"
        + "<div><img src=\"inline.png\"></div>\n\n```mermaid\ngraph TD; A-->B\n```\n\n"
        + "- item\n  ![in list](list.png)\n- second\n\n> [!NOTE]\n> callout ![c](c.png)\n\n"
        + "| A | B |\n| --- | --- |\n| ![t](t.png) | 2 |\n\n<!-- toc -->\n- [Title](#title)\n<!-- /toc -->\n\n"
        + String(repeating: "Tail paragraph with *emphasis*.\n\n", count: 20)

    /// Attribute values per character. Colors compare by their sRGB components under the editor's appearance: dynamic
    /// colors are new objects on every pass, so object identity would report differences that are not there.
    static func canonical(_ text: NSAttributedString, appearance: NSAppearance) -> [[String: String]] {
        func describe(_ value: Any) -> String {
            if let color = value as? NSColor {
                var components = "\(color)"
                appearance.performAsCurrentDrawingAppearance {
                    if let srgb = color.usingColorSpace(.sRGB) {
                        components = "\(srgb.redComponent) \(srgb.greenComponent) \(srgb.blueComponent) \(srgb.alphaComponent)"
                    }
                }
                return components
            }
            if let fill = value as? MarkdownBlockFill {
                return "fill(\(describe(fill.color)) \(fill.radius) \(fill.padding) \(fill.first) \(fill.last))"
            }
            return "\(value)"
        }
        var result: [[String: String]] = []
        var location = 0
        while location < text.length {
            var range = NSRange()
            let attributes = text.attributes(at: location, effectiveRange: &range)
            let described = Dictionary(attributes.map { ($0.key.rawValue, describe($0.value)) }, uniquingKeysWith: { first, _ in first })
            result += Array(repeating: described, count: NSMaxRange(range) - location)
            location = NSMaxRange(range)
        }
        return result
    }

    /// Restyling one asset's blocks gives the same attributes as a full pass, so an asset that loads never leaves a
    /// block styled differently from the rest of the document.
    @Test(arguments: [false, true]) func assetRestyleMatchesAFullPass(markdownLens: Bool) {
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.string = Self.assetFixture
        Self.native(editor.string, markdownLens: markdownLens).style(editor)
        let appearance = editor.effectiveAppearance
        let full = Self.canonical(editor.textStorage!, appearance: appearance)
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let model = editor.model
        let keys = Set(model.spans.flatMap { editor.assetKeys($0, model: model, dark: dark) })
        #expect(keys.count >= 6, "fixture shows \(keys.count) assets")
        for key in keys.sorted() {
            editor.requestAssetRestyle(key)
            Self.native(editor.string, markdownLens: markdownLens).style(editor, incremental: true)
            #expect(Self.canonical(editor.textStorage!, appearance: appearance) == full, "restyling \(key)")
            if !markdownLens, let scope = editor.assetScope([key], model: model, dark: dark, extra: []) {
                #expect(scope.length < (editor.string as NSString).length, "\(key) restyles only its blocks")
            }
        }
        editor.requestAssetRestyle(nil)
        editor.requestAssetRestyle("image:unrelated")
        Self.native(editor.string, markdownLens: markdownLens).style(editor, incremental: true)
        #expect(Self.canonical(editor.textStorage!, appearance: appearance) == full, "a full pass after an unrelated asset")
        editor.stopObserving()
    }

    /// Heading edits take the paragraph path, and must match a full pass: level changes, markers added and removed,
    /// Unicode in headings, paragraphs that become headings and back, and a setext underline that must fall back.
    @Test func headingEditsMatchAFullPass() {
        let source = "# Title\n\nParagraph with *emphasis*.\n\n## Part\n\nTail with **bold**.\n\n"
        let edits: [(name: String, anchor: String, offset: Int, delete: Int, insert: String)] = [
            ("level down", "## Part", 0, 0, "#"),
            ("level up", "## Part", 0, 1, ""),
            ("heading to paragraph", "# Title", 0, 2, ""),
            ("paragraph to heading", "Paragraph with", 0, 0, "# "),
            ("paragraph after heading", "Tail", 0, 0, "## "),
            ("accented character in heading", "Part", 4, 0, "é"),
            ("heading text replaced", "Part", 0, 4, "Heading 日本"),
            ("setext underline", "Paragraph with *emphasis*.", 26, 0, "\n==="),
            ("line break after heading", "## Part", 7, 0, "\n\nExtra"),
        ]
        for edit in edits {
            let editor = MarkdownTextView(usingTextLayoutManager: true)
            editor.string = source
            Self.native(source).style(editor)
            let anchor = (editor.string as NSString).range(of: edit.anchor)
            let location = anchor.location + edit.offset
            editor.textStorage!.replaceCharacters(in: NSRange(location: location, length: edit.delete), with: edit.insert)
            Self.native(editor.string).style(editor, incremental: true)
            let incremental = NSAttributedString(attributedString: editor.textStorage!)
            Self.native(editor.string).style(editor)
            #expect(incremental.isEqual(to: editor.textStorage!), "\(edit.name)")
            editor.stopObserving()
        }
    }

    static let source = "# Title\n\n<!-- toc -->\n- [Title](#title)\n  - [Part](#part)\n<!-- /toc -->\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n\n"
        + String(repeating: "Paragraph with **bold** and [a link](https://example.com).\n\n", count: 40) + "## Part\n\nLast line.\n"

    static func native(_ text: String, markdownLens: Bool = false, findQuery: String = "") -> NativeEditor {
        NativeEditor(text: .constant(text), fileURL: nil, columnWidth: 640, markdownLens: markdownLens, findQuery: findQuery, matchCase: false,
                     selectedRange: .constant(NSRange(location: 0, length: 0)),
                     textView: .constant(nil), onType: {}, onSlash: { _ in }, onSlashKey: { _, _ in false }, onSelectionRect: { _ in })
    }

    @Test func incrementalStylingMatchesAFullPass() {
        let (window, editor) = LayoutFragmentTests.makeEditor(Self.source)
        _ = window
        let end = (editor.string as NSString).range(of: "Last line.").location
        editor.textStorage!.replaceCharacters(in: NSRange(location: end, length: 0), with: "More **text** ")
        Self.native(editor.string).style(editor, incremental: true)
        let incremental = NSAttributedString(attributedString: editor.textStorage!)
        Self.native(editor.string).style(editor)
        #expect(incremental.isEqual(to: editor.textStorage!))
        #expect(editor.string.contains("More **text** Last line."))
    }

    @Test func typingLeavesTheLinesAboveUntouched() {
        let (window, editor) = LayoutFragmentTests.makeEditor(Self.source)
        _ = window
        let storage = editor.textStorage!
        let end = (editor.string as NSString).range(of: "Last line.").location
        storage.replaceCharacters(in: NSRange(location: end, length: 0), with: "x")
        var edited: [NSRange] = []
        let watched = ObjectIdentifier(storage)
        let observer = NotificationCenter.default.addObserver(forName: NSTextStorage.didProcessEditingNotification, object: nil, queue: nil) { notification in
            guard let changed = notification.object as? NSTextStorage, ObjectIdentifier(changed) == watched else { return }
            let range = changed.editedRange
            MainActor.assumeIsolated { edited.append(range) }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        Self.native(editor.string).style(editor, incremental: true)
        // Only the edited paragraph's runs may change; the table of contents and the text above keep their layout.
        let lastParagraph = (editor.string as NSString).paragraphRange(for: NSRange(location: end, length: 0))
        #expect(edited.allSatisfy { $0.location == NSNotFound || $0.location >= lastParagraph.location - 1 })
        // A full pass, by contrast, touches the whole document (and is what the observer would catch).
        edited = []
        Self.native(editor.string).style(editor)
        #expect(edited.contains { $0.location == 0 })
    }

    /// The page doesn't move while typing below a table of contents and a table: the document keeps its height and
    /// the scroll position stays, as in an editor.
    @Test func typingKeepsThePageStill() {
        let source = Self.source + String(repeating: "Line below the caret with some words.\n\n", count: 60)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.frame = scroll.bounds
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainerInset = NSSize(width: 0, height: 40)
        scroll.documentView = editor
        window.contentView = scroll
        editor.string = source
        Self.native(source).style(editor)
        window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: (source as NSString).range(of: "Line below").location - 1, length: 0))
        editor.scrollRangeToVisible(editor.selectedRange())
        editor.refreshTables()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let top = scroll.contentView.bounds.minY
        let height = editor.frame.height
        for key in "abcdef" {
            editor.insertText(String(key), replacementRange: editor.selectedRange())
            Self.native(editor.string).style(editor, incremental: true)
            editor.refreshTables()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            #expect(scroll.contentView.bounds.minY == top)
            #expect(editor.frame.height == height)
        }
    }
}
