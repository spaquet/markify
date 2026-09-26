import AppKit
import Markdown
import OKFKit
import SwiftUI
import Testing
@testable import Markify

struct MarkifyTests {
    @Test @MainActor func lensStylingPreservesMarkdownSource() {
        let source = "---\ntags: [essay]\n---\n# Title\n\n**Bold** and [link](https://example.com)\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n\n$$\n\\frac{1}{2}\n$$\n"
        let editor = NSTextView(usingTextLayoutManager: true)
        editor.string = source
        for lens in [false, true] {
            NativeEditor(text: .constant(source), fileURL: nil, columnWidth: 640, markdownLens: lens, findQuery: "", matchCase: false,
                         selectedRange: .constant(NSRange(location: 0, length: 0)),
                         textView: .constant(nil), onType: {}, onSlash: { _ in }, onSlashKey: { _, _ in false }, onSelectionRect: { _ in })
                .style(editor)
            #expect(editor.string == source)
        }
    }

    @Test func sourceAnchorPreservesOffsets() {
        let source = "# Title\n\nSecond line\nThird line\n"
        let anchor = SourceAnchor(source: source, selection: NSRange(location: 17, length: 4), topOffset: 11)
        #expect(anchor.selection(in: source) == NSRange(location: 17, length: 4))
        #expect((source as NSString).substring(with: anchor.topLine) == "Second line\n")
        #expect(anchor.selection(in: "short") == NSRange(location: 5, length: 0))
    }

    @Test func markdownSourceRangesMapThroughUnicode() {
        let source = "😀 intro\n# Café\n"
        let heading = Markdown.Document(parsing: source).children.compactMap { $0 as? Markdown.Heading }.first!
        let range = MarkdownSourceMap(source).range(heading.range!)!
        #expect((source as NSString).substring(with: range) == "# Café")
    }

    @Test func slashContextAndFuzzyMenu() {
        let source = "Hello /tbl" as NSString
        let slash = SlashContext.detect(in: source as String, selection: NSRange(location: source.length, length: 0))
        #expect(slash?.range == NSRange(location: 6, length: 4))
        #expect(slash?.query == "tbl")
        #expect(SlashEntry.matching("tbl").map(\.title) == ["Table"])
        #expect(SlashContext.detect(in: "https://example.com", selection: NSRange(location: 8, length: 0)) == nil)
        #expect(SlashContext.detect(in: "/task list", selection: NSRange(location: 10, length: 0)) == nil)
    }

    @Test @MainActor func slashCanStartAnEmptyDocument() {
        let source = ""
        let view = NativeEditor(text: .constant(source), fileURL: nil, columnWidth: 640, markdownLens: false, findQuery: "", matchCase: false,
                                selectedRange: .constant(NSRange(location: 0, length: 0)), textView: .constant(nil),
                                onType: {}, onSlash: { _ in }, onSlashKey: { _, _ in false }, onSelectionRect: { _ in })
        let editor = NSTextView(usingTextLayoutManager: true)
        #expect(view.makeCoordinator().textView(editor, shouldChangeTextIn: NSRange(location: 0, length: 0), replacementString: "/"))
    }

    @Test @MainActor func slashReturnRoutesToSelectedCommand() {
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.string = "/tab"
        editor.setSelectedRange(NSRange(location: 4, length: 0))
        var handled: SlashContext?
        editor.onSlashKey = { key, context in
            if key == .insert { handled = context; return true }
            return false
        }
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                     windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
                                     isARepeat: false, keyCode: 36)!
        editor.keyDown(with: event)
        #expect(handled?.query == "tab")
    }

    @Test @MainActor func slashInsertionStartsABlockAndPlacesCaret() {
        let editor = NSTextView(usingTextLayoutManager: true)
        editor.string = "Hello /tab"
        let context = SlashContext.detect(in: editor.string, selection: NSRange(location: 10, length: 0))!
        SlashEntry.matching("tab")[0].apply(to: editor, context: context)
        #expect(editor.string == "Hello\n| Column | Column |\n| --- | --- |\n|  |  |")
        #expect((editor.string as NSString).substring(with: editor.selectedRange()) == "Column")
    }

    @Test @MainActor func tableTabMovesCellsAndAddsRow() {
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.string = "| A | B |\n| --- | --- |\n| C | D |"
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        #expect(editor.navigateTable(backward: false))
        #expect((editor.string as NSString).substring(with: editor.selectedRange()) == "B")
        #expect(editor.navigateTable(backward: false))
        #expect((editor.string as NSString).substring(with: editor.selectedRange()) == "C")
        #expect(editor.navigateTable(backward: false))
        #expect((editor.string as NSString).substring(with: editor.selectedRange()) == "D")
        #expect(editor.navigateTable(backward: false))
        #expect(editor.string.hasSuffix("\n|  |  |"))
    }

    @Test @MainActor func tableCellEditsTrackTheirSourceRange() {
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.string = "| A | B |\n| --- | --- |\n| C | D |"
        var cell = NSRange(location: 2, length: 1)
        for value in ["Al", "Alp", "Alpha"] { cell = editor.replaceTableCell(cell, with: value) }
        #expect(editor.string == "| Alpha | B |\n| --- | --- |\n| C | D |")
        #expect((editor.string as NSString).substring(with: cell) == "Alpha")
    }

    @Test func orderedListsRenumberFromTheirStart() {
        let text = "1. a\n3. b\n   1. nested\n   5. nested\n7. c\n\nText\n\n4. new\n9. list\n- bullet\n1. after\n```\n1. code\n1. code\n```"
        var fixed = text as NSString
        for fix in MarkdownList.scan(text).fixes.reversed() { fixed = fixed.replacingCharacters(in: fix.range, with: fix.value) as NSString }
        #expect(fixed as String == "1. a\n2. b\n   1. nested\n   2. nested\n3. c\n\nText\n\n4. new\n5. list\n- bullet\n1. after\n```\n1. code\n1. code\n```")
    }

    @Test func lazyContinuationLinesStayInTheirList() {
        let scan = MarkdownList.scan("1. a\nwrapped text\n5. b\n\n# Heading\n9. new")
        #expect(scan.fixes.map(\.value) == ["2"])
        #expect(scan.lazyLines.map(\.item) == [0])
        #expect(MarkdownList.scan("1. a\n---\n5. b").fixes.isEmpty)
    }

    @Test @MainActor func removingTheFirstItemKeepsTheListStart() {
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.string = "1. a\n2. b\n3. c"
        editor.insertText("", replacementRange: NSRange(location: 0, length: 5))
        #expect(editor.string == "1. b\n2. c")
        editor.string = "Intro\n\n4. a\n5. b"
        editor.insertText("!", replacementRange: NSRange(location: 11, length: 0))
        #expect(editor.string == "Intro\n\n4. a!\n5. b")
    }

    @Test @MainActor func undoRestoresTheEditAndItsRenumbering() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: true)
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.allowsUndo = true
        window.contentView = editor
        let undo = try #require(editor.undoManager)
        undo.groupsByEvent = false
        editor.string = "1. a\n2. b\n3. c"
        undo.beginUndoGrouping()
        editor.insertText("", replacementRange: NSRange(location: 0, length: 5))
        undo.endUndoGrouping()
        #expect(editor.string == "1. b\n2. c")
        undo.undo()
        #expect(editor.string == "1. a\n2. b\n3. c")
    }

    @Test @MainActor func editsRenumberOnlyTheListTheyTouch() {
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.string = "1. a\n1. b\n\nText\n\n1. x\n1. y"
        editor.insertText("!", replacementRange: NSRange(location: 4, length: 0))
        #expect(editor.string == "1. a!\n2. b\n\nText\n\n1. x\n1. y")
    }

    @Test @MainActor func renderedLensDrawsCountedNumbersOverTheSource() {
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        let source = Array(repeating: "1. item", count: 10).joined(separator: "\n")
        editor.string = source
        NativeEditor(text: .constant(source), fileURL: nil, columnWidth: 640, markdownLens: false, findQuery: "", matchCase: false,
                     selectedRange: .constant(NSRange(location: 0, length: 0)),
                     textView: .constant(nil), onType: {}, onSlash: { _ in }, onSlashKey: { _, _ in false }, onSelectionRect: { _ in })
            .style(editor)
        let storage = try! #require(editor.textStorage)
        #expect(editor.string == source)
        #expect(MarkdownList.scan(source).numbers.map(\.value) == (1...10).map(String.init))
        #expect(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .clear)
        #expect(storage.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor == .clear)
        // One digit is written but "10" is drawn, so every marker reserves room for two digits.
        #expect((storage.attribute(.kern, at: 2, effectiveRange: nil) as? CGFloat ?? 0) > 0)
    }

    @Test @MainActor func editingAListKeepsItNumbered() {
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.string = "1. a\n2. b\n3. c"
        editor.insertText("", replacementRange: NSRange(location: 5, length: 5))
        #expect(editor.string == "1. a\n2. c")
        editor.setSelectedRange(NSRange(location: 4, length: 0))
        #expect(editor.continueList())
        #expect(editor.string == "1. a\n2. \n3. c")
        #expect(editor.selectedRange().location == 8)
    }

    @Test @MainActor func returnContinuesAndEndsLists() {
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.string = "1. First"
        editor.setSelectedRange(NSRange(location: 8, length: 0))
        #expect(editor.continueList())
        #expect(editor.string == "1. First\n2. ")
        #expect(editor.continueList())
        #expect(editor.string == "1. First\n")
        editor.string = "- [x] Done"
        editor.setSelectedRange(NSRange(location: 10, length: 0))
        #expect(editor.continueList())
        #expect(editor.string == "- [x] Done\n- [ ] ")
        editor.string = "Plain"
        editor.setSelectedRange(NSRange(location: 5, length: 0))
        #expect(!editor.continueList())
    }

    @Test @MainActor func displayMathRendersLocally() {
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        let image = editor.renderMath(#"\frac{1}{2}"#, dark: false)
        #expect(image?.size.width ?? 0 > 0)
        #expect(image?.size.height ?? 0 > 0)
        #expect(image?.size.width ?? 0 < 100)
    }

    @Test func aiAcceptanceKeepsOneFrontmatterBlock() {
        let source = "---\ntags: [old]\n---\n# Title\n"
        let replacement = "---\ntitle: New\ntags: [new]\n---\n"
        let edit = AIPlacement.frontmatter.edit(source: source, output: replacement, caret: 0)
        let result = (source as NSString).replacingCharacters(in: edit.range, with: edit.text)
        #expect(result == replacement + "# Title\n")
        let summary = AIPlacement.atTop.edit(source: source, output: "Summary", caret: 0)
        #expect(summary.range.location == edit.range.length)
    }

    @Test func sectionContextSpansHeadingToNextHeading() {
        let source = "Intro\n# One\nAlpha beta\n## Two\nGamma\n"
        let ns = source as NSString
        let caret = NSRange(location: ns.range(of: "beta").location, length: 0)
        #expect(ns.substring(with: AIContext.section(around: caret, in: source)) == "# One\nAlpha beta\n")
        let intro = AIContext.section(around: NSRange(location: 2, length: 0), in: source)
        #expect(ns.substring(with: intro) == "Intro\n")
        let spanning = AIContext.section(around: NSRange(location: ns.range(of: "beta").location, length: 12), in: source)
        #expect(ns.substring(with: spanning) == "# One\nAlpha beta\n## Two\nGamma\n")
        #expect(AIContext.section(around: NSRange(location: 1, length: 0), in: "plain") == NSRange(location: 0, length: 5))
    }

    @Test func lensMemoryRoundTripsExtendedAttribute() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        try "# Note\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(LensMemory.read(url) == nil)
        LensMemory.write(true, to: url)
        #expect(LensMemory.read(url) == true)
        LensMemory.write(false, to: url)
        #expect(LensMemory.read(url) == false)
        #expect(try String(contentsOf: url, encoding: .utf8) == "# Note\n")
    }

    @Test func frontmatterParsesTagsAndDate() {
        let inline = Frontmatter.parse("---\ntags: [essay, \"editor\"]\ndate: 2026-09-25\n---\n# Title\n")
        #expect(inline?.tags == ["essay", "editor"])
        #expect(inline?.date == "2026-09-25")
        #expect(inline?.range == NSRange(location: 0, length: 49))
        let list = Frontmatter.parse("---\ntags:\n  - one\n  - two\n---\n")
        #expect(list?.tags == ["one", "two"])
        #expect(Frontmatter.parse("# No frontmatter\n") == nil)
        #expect(Frontmatter.parse("---\nunclosed: yes\n") == nil)
    }

    @Test func blockStyleRestylesEveryLine() {
        #expect(BlockStyle.apply("Heading", to: "# Old\n- item") == "## Old\n## item")
        #expect(BlockStyle.apply("Numbered", to: "a\n\nb") == "1. a\n\n2. b")
        #expect(BlockStyle.apply("Body", to: "- [x] done\n> quote") == "done\nquote")
        #expect(BlockStyle.apply("Callout", to: "one\ntwo") == "> [!NOTE]\n> one\n> two")
        #expect(BlockStyle.apply("Code block", to: "## x") == "```\nx\n```")
    }

    @Test func shortcutsParseDisplayAndOverride() {
        #expect(Shortcuts.display("shift cmd x") == "⇧⌘X")
        #expect(Shortcuts.display("cmd return") == "⌘↩")
        #expect(Shortcuts.keyboardShortcut("bold", stored: "") == KeyboardShortcut("b", modifiers: .command))
        let stored = Shortcuts.encode(["bold": "ctrl cmd b", "italic": ""])
        #expect(Shortcuts.keyboardShortcut("bold", stored: stored) == KeyboardShortcut("b", modifiers: [.control, .command]))
        #expect(Shortcuts.keyboardShortcut("italic", stored: stored) == nil)
        #expect(Set(Shortcuts.actions.map(\.key)).count == Shortcuts.actions.count)
    }

    @Test func footnoteDefinitionsKeepLabelAndText() {
        let notes = Footnote.definitions(in: "Body[^1]\n\n[^1]: The note.\n[^two]: Second\n")
        #expect(notes.map(\.label) == ["1", "two"])
        #expect(notes.first?.text == "The note.")
    }

    @Test func frontmatterReadsTitle() {
        let parsed = Frontmatter.parse("---\ntitle: \"Bug: Bullets\"\ntags: [\"bug\",\"dark mode\"]\n---\nBody\n")
        #expect(parsed?.title == "Bug: Bullets")
        #expect(parsed?.tags == ["bug", "dark mode"])
        #expect(Frontmatter.parse("---\ntags: [a]\n---\n")?.title == nil)
    }

    @Test func finderTagsSwapMirroredTagsAndKeepOthers() {
        #expect(FinderTags.merge(finder: ["Red", "old"], previous: ["old"], current: ["new"]) == ["Red", "new"])
        #expect(FinderTags.merge(finder: ["Bug"], previous: [], current: ["bug", "ui"]) == ["Bug", "ui"])
        #expect(FinderTags.merge(finder: [], previous: ["a"], current: []) == [])
    }

    @Test func conceptCacheOnlyReadsTypedFrontmatter() {
        let cache = ConceptCache()
        #expect(cache.concept(in: "---\ntags: [a]\n---\nNote") == nil)
        #expect(cache.concept(in: "---\ntype: Metric\nstatus: draft\n---\nBody")?.status == .draft)
        #expect(cache.concept(in: "---\ntype: Metric\nstatus: draft\n---\nEdited body")?.type == "Metric")
        #expect(cache.concept(in: "Plain") == nil)
    }

    @Test @MainActor func frontmatterSuggestionMergesKeyByKey() {
        let yaml = "# keep me\ndate: 2026-09-01\ntitle: Old\nverified: { by: human:ana, at: 2026-06-25T09:00:00Z }\n"
        let plain = FrontmatterSuggestion(title: "Revenue: FY", tags: ["finance", "yes"])
        #expect(plain.merged(into: yaml) == "# keep me\ndate: 2026-09-01\ntitle: \"Revenue: FY\"\nverified: { by: human:ana, at: 2026-06-25T09:00:00Z }\ntags: [finance, \"yes\"]\n")
        let okf = FrontmatterSuggestion(title: "Revenue", tags: [], type: "Metric", description: "Recognized revenue.")
        #expect(okf.merged(into: "tags: [a]\n") == "type: Metric\ntags: [a]\ntitle: Revenue\ndescription: Recognized revenue.\n")
        #expect(okf.merged(into: "type: Playbook\n").hasPrefix("type: Playbook\n"))
        #expect(okf.preview == "type: Metric\ntitle: Revenue\ndescription: Recognized revenue.")
        #expect(Knowledge.aiActor.description.hasPrefix("apple-intelligence/macos-"))
    }

    @Test @MainActor func linkDestinationsCompleteFromBundle() {
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.linkTargets = ["/tables/orders.md", "/tables/Customer List.md", "/playbooks/freshness.md"]
        editor.string = "See [orders](/tab"
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        let range = editor.rangeForUserCompletion
        #expect((editor.string as NSString).substring(with: range) == "/tab")
        var index = 0
        #expect(editor.completions(forPartialWordRange: range, indexOfSelectedItem: &index) == ["/tables/orders.md", "/tables/Customer%20List.md"])
        editor.string = "See [peer](./pro"
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        let relative = editor.rangeForUserCompletion
        #expect(editor.completions(forPartialWordRange: relative, indexOfSelectedItem: &index)?.contains("/tables/orders.md") != true)
    }

    @Test @MainActor func footnotesShowTheirSource() {
        let source = "---\ntype: Metric\nsources:\n  - { id: pol, title: Revenue policy, resource: https://wiki/p }\n---\nClaim.[^pol]\n\n[^pol]: Policy\n"
        let editor = NSTextView(usingTextLayoutManager: true)
        editor.string = source
        NativeEditor(text: .constant(source), fileURL: nil, columnWidth: 640, markdownLens: false, findQuery: "", matchCase: false,
                     selectedRange: .constant(NSRange(location: 0, length: 0)),
                     textView: .constant(nil), onType: {}, onSlash: { _ in }, onSlashKey: { _, _ in false }, onSelectionRect: { _ in })
            .style(editor)
        let label = (source as NSString).range(of: "pol]\n").location
        let tip = editor.textStorage?.attribute(.toolTip, at: label, effectiveRange: nil) as? String
        #expect(tip == "Policy\n\nSource: Revenue policy · https://wiki/p")
    }

    @Test @MainActor func knowledgeIssuesTrackUnsavedText() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("okf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "---\nokf_version: \"0.2\"\n---\n".write(to: root.appendingPathComponent("index.md"), atomically: true, encoding: .utf8)
        try "---\ntype: Metric\n---\n".write(to: root.appendingPathComponent("orders.md"), atomically: true, encoding: .utf8)
        let file = root.appendingPathComponent("revenue.md")
        #expect(Knowledge.root(for: file, text: "Plain note", boundary: nil).map(OKFBundle.key) == OKFBundle.key(root))
        #expect(Knowledge.root(for: file, text: "---\ntype: Metric\n---\n", boundary: nil) != nil)
        let issues = Knowledge.issues(text: "---\ntype: Metric\n---\nSee [orders](/orders.md) and [later](/later.md).", fileURL: file, root: root)
        #expect(issues.map(\.message) == ["Links to /later.md, which does not exist yet."])
        #expect(Knowledge.issues(text: "No frontmatter", fileURL: file, root: root).first?.severity == .error)
    }
}
