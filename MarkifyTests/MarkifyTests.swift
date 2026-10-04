import AppKit
import MarkifyMarkdown
import OKFKit
import SwiftUI
import Testing
@testable import Markify

struct MarkifyTests {
    @Test @MainActor func externalFilePromptsWaitUntilVersionBrowsingEnds() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("original".utf8).write(to: url)
        let document = RefreshTestDocument()
        document.fileURL = url
        document.fileType = "net.daringfireball.markdown"
        var notifications = 0
        let refresh = DocumentFileRefresh(refreshSearch: {}, choose: { _, complete in
            notifications += 1
            complete(.reload)
        })
        defer { refresh.stop() }
        refresh.watch(document)
        document.browsing = true
        try Data("external".utf8).write(to: url, options: .atomic)
        refresh.refresh()
        #expect(notifications == 0)
        #expect(document.text == "original")
        document.browsing = false
        document.viewing = true
        refresh.refresh()
        #expect(notifications == 0)
        document.viewing = false
        refresh.refresh()
        for _ in 0..<100 {
            if document.text == "external" { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(notifications == 1)
        #expect(document.text == "external")
        #expect(try Data(contentsOf: url) == Data("external".utf8))
    }

    @Test @MainActor func externalFileRefreshReloadsCleanDocumentsAndPreservesEdits() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("original".utf8).write(to: url)
        let document = RefreshTestDocument()
        document.fileURL = url
        document.fileType = "net.daringfireball.markdown"
        var searchRefreshes = 0
        var choice = DocumentFileRefresh.Choice.reload
        var notifications = 0
        let refresh = DocumentFileRefresh(refreshSearch: { searchRefreshes += 1 }, choose: { _, complete in
            notifications += 1
            complete(choice)
        })
        refresh.watch(document)
        refresh.refresh()
        try await Task.sleep(for: .milliseconds(100))
        #expect(document.reloads == 0)
        #expect(searchRefreshes == 0)
        try Data("external".utf8).write(to: url, options: .atomic)
        refresh.refresh()
        try await Task.sleep(for: .milliseconds(100))
        #expect(document.text == "external")
        #expect(document.reloads == 1)
        #expect(searchRefreshes == 1)
        choice = .keep
        document.text = "local edits"
        document.updateChangeCount(.changeDone)
        try Data("another external edit".utf8).write(to: url)
        refresh.refresh()
        try await Task.sleep(for: .milliseconds(100))
        #expect(document.text == "local edits")
        #expect(document.reloads == 1)
        #expect(searchRefreshes == 2)
        #expect(notifications == 2)
        refresh.refresh()
        try await Task.sleep(for: .milliseconds(100))
        #expect(notifications == 2)
        // An unrelated folder event or local typing is not an external change.
        document.text = "more local edits"
        refresh.refresh()
        try await Task.sleep(for: .milliseconds(100))
        #expect(notifications == 2)
        try Data(document.text.utf8).write(to: url)
        refresh.refresh()
        try await Task.sleep(for: .milliseconds(100))
        #expect(notifications == 2)
    }

    @Test @MainActor func externalFilePollingDetectsAtomicSavesAndDeletionOfText() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("original".utf8).write(to: url)
        let document = RefreshTestDocument()
        document.fileURL = url
        document.fileType = "net.daringfireball.markdown"
        var notifications = 0
        let refresh = DocumentFileRefresh(choose: { _, complete in notifications += 1; complete(.reload) })
        refresh.watch(document)
        for text in ["added text\noriginal", "updated text", ""] {
            try Data(text.utf8).write(to: url, options: .atomic)
            for _ in 0..<40 {
                if document.text == text { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            #expect(document.text == text)
        }
        #expect(notifications == 3)
    }

    @Test func externalFileMergePreservesBothVersionsAndMarksConflicts() throws {
        let base = "one\ntwo\nthree\n"
        #expect(try DocumentFileRefresh.merge(local: "ONE\ntwo\nthree\n", base: base,
                                             external: "one\ntwo\nTHREE\n") == "ONE\ntwo\nTHREE\n")
        #expect(try DocumentFileRefresh.merge(local: base, base: base, external: "one\nthree\n") == "one\nthree\n")
        let conflict = try DocumentFileRefresh.merge(local: "mine\n", base: "original\n", external: "theirs\n")
        #expect(conflict.contains("<<<<<<< My Changes"))
        #expect(conflict.contains("mine\n"))
        #expect(conflict.contains("theirs\n"))
        #expect(conflict.contains(">>>>>>> External Changes"))
    }

    @Test @MainActor func externalFileMergeUpdatesEditorBindingAndCanBeUndone() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        defer { try? FileManager.default.removeItem(at: url) }
        let base = "one\ntwo\nthree\n"
        try Data(base.utf8).write(to: url)
        let document = RefreshTestDocument()
        document.text = base
        document.fileURL = url
        document.fileType = "net.daringfireball.markdown"
        let undo = try #require(document.undoManager)
        undo.groupsByEvent = false // SwiftUI documents manage their own undo groups.
        var editorText = base
        let refresh = DocumentFileRefresh(readText: { editorText }, writeText: { editorText = $0 },
                                          choose: { _, complete in complete(.merge) })
        refresh.watch(document)
        editorText = "ONE\ntwo\nthree\n"
        document.updateChangeCount(.changeDone)
        try Data("one\ntwo\nTHREE\n".utf8).write(to: url)
        refresh.refresh()
        for _ in 0..<100 {
            if editorText == "ONE\ntwo\nTHREE\n" { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(editorText == "ONE\ntwo\nTHREE\n")
        #expect(document.reloads == 0)
        #expect(try String(contentsOf: url, encoding: .utf8) == "one\ntwo\nTHREE\n")
        #expect(undo.groupingLevel == 0)
        undo.undo()
        #expect(editorText == "ONE\ntwo\nthree\n")
    }

    @Test func linksPanelUsesMarkdownLinksInSourceOrder() {
        let source = "[first](a.md) [again][one] <https://example.com> ![image](skip.png)\n\n[one]: a.md\n"
        let links = DocumentLink.extract(from: MarkdownModel(source))
        #expect(links.map(\.destination) == ["a.md", "a.md", "https://example.com"])
        #expect(links.map(\.range.location) == links.map(\.range.location).sorted())
    }

    @Test func contentsListsLevelOneAndTwoHeadingsInSourceOrder() {
        let source = """
        ---
        title: Front
        ---
        ## Before
        # Intro *with* `code`
        ### Skipped
        Setext
        ======
        ## [Linked](a.md) <b>part</b>
        ## Before

        ```
        # not a heading
        ```
        """
        let headings = DocumentHeading.extract(from: MarkdownModel(source))
        #expect(headings.map(\.title) == ["Before", "Intro with code", "Skipped", "Setext", "Linked part", "Before"])
        #expect(headings.map(\.level) == [2, 1, 3, 1, 2, 2])
        #expect(headings.map(\.line) == [4, 5, 6, 7, 9, 10])
        // Repeated titles stay separate entries with export's numbered anchors, each jumping to its own heading text.
        #expect(headings.map(\.anchor) == ["before", "intro-with-code", "skipped", "setext", "linked-part", "before-1"])
        let ns = source as NSString
        #expect(headings.map { ns.substring(with: NSRange(location: $0.range.location, length: 5)) } == ["Befor", "Intro", "Skipp", "Setex", "[Link", "Befor"])
        #expect(DocumentHeading.extract(from: MarkdownModel("Just text.\n")).isEmpty)
    }

    @Test @MainActor func linkSummaryCacheSurvivesReloadAndDetectsTargetChanges() throws {
        let location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: location) }
        let document = URL(fileURLWithPath: "/tmp/notes/current.md")
        let key = try #require(LinkSummaryStore.key("other.md", from: document, root: nil))
        let source = "# Original"
        let saved = LinkSummary(text: "Original summary", fingerprint: LinkSummaryStore.fingerprint(source), date: .now)
        let store = LinkSummaryStore(location: location)
        try store.save(saved, for: key)
        #expect(LinkSummaryStore(location: location).entries[key] == saved)
        #expect(!LinkSummaryStore.isStale(saved, source: source))
        #expect(LinkSummaryStore.isStale(saved, source: "# Changed"))
        #expect(LinkSummaryStore.key("other.md#section", from: document, root: nil) == key)
    }

    @Test @MainActor func linksPanelGroupsResolvedDestinationsAndTracksSourceLines() throws {
        let file = URL(fileURLWithPath: "/tmp/notes/current.md")
        let source = "🌻 [first](other%20note.md) [same](./other%20note.md#part)\r\n\r\n[alias][note]\n[web](https://EXAMPLE.com:443/page#one)\n[again](https://example.com/page#two)\n[distinct](https://example.com/page?q=1)\n\n[note]: other%20note.md\n"
        func groups(_ source: String) -> [DocumentLinkGroup] {
            DocumentLinkGroup.group(DocumentLink.extract(from: MarkdownModel(source)), from: file, root: nil)
        }
        let original = groups(source)
        #expect(original.count == 3)
        #expect(original[0].occurrences.map(\.text) == ["first", "same", "alias"])
        #expect(original[0].lines.map(\.line) == [1, 3])
        #expect(original[1].lines.map(\.line) == [4, 5])
        #expect(original[2].lines.map(\.line) == [6])
        for link in original[0].occurrences {
            #expect((source as NSString).substring(with: link.range).hasPrefix("["))
        }
        let edited = groups("Inserted\n" + source)
        #expect(edited[0].id == original[0].id)
        #expect(edited[0].lines.map(\.line) == [2, 4])
        let report = DocumentLinkGroup.group(DocumentLink.extract(from: MarkdownModel("[a](other.md) [b](./other.md)")),
            from: nil, root: nil, baseDirectory: file.deletingLastPathComponent())
        #expect(report.count == 1)
    }

    @Test @MainActor func linksPanelTextCopiesOnlyTheSelectedRangeAndCannotBeEdited() throws {
        let text = "Summary café 🌻\nA second sentence to select."
        let host = NSHostingView(rootView: SelectableLinkText(text: text).frame(width: 250))
        host.frame = NSRect(x: 0, y: 0, width: 250, height: 100)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        func textView(in view: NSView) -> NSTextView? {
            if let text = view as? NSTextView { return text }
            return view.subviews.lazy.compactMap { textView(in: $0) }.first
        }
        let view = try #require(textView(in: host))
        #expect(!view.isEditable)
        #expect(view.isSelectable)
        #expect(view.string == text)
        window.makeFirstResponder(view)
        let range = (text as NSString).range(of: "café 🌻")
        view.setSelectedRange(range)
        #expect(view.selectedRange() == range)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.declareTypes([.string], owner: nil)
        #expect(view.writeSelection(to: pasteboard, types: view.writablePasteboardTypes))
        #expect(pasteboard.string(forType: .string) == "café 🌻")
        view.selectAll(nil)
        pasteboard.declareTypes([.string], owner: nil)
        #expect(view.writeSelection(to: pasteboard, types: view.writablePasteboardTypes))
        #expect(pasteboard.string(forType: .string) == text)
    }

    @Test func libraryListsSupportedFilesInSubfolders() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("Projects/Notes")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Empty"), withIntermediateDirectories: true)
        for path in ["home.md", "Projects/plan.markdown", "Projects/Notes/page.mdx", "Projects/Notes/skip.txt", ".hidden.md"] {
            try "# Note".write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8)
        }
        let domain = "markifylibrarytest" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let worker = SpotlightWorker(name: domain, domain: domain, persistenceKey: nil)
        let contents = try await worker.refresh(folders: [SearchFolder(path: root.path, bookmark: Data(), kind: "Library")],
                                                options: SearchOptions(), rebuild: true) { _ in }
        #expect(Set(contents.notes.map { $0.url.lastPathComponent }) == ["home.md", "plan.markdown", "page.mdx"])
        #expect(Set(contents.subfolders.map(\.lastPathComponent)) == ["Projects", "Notes", "Empty"])
        #expect(LibraryNote.path(of: nested, in: root) == "Projects/Notes")
        try await worker.delete()
    }

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

    @Test @MainActor func inlineMathSlashEntryStaysInTheLine() {
        let editor = NSTextView(usingTextLayoutManager: true)
        editor.string = "Area is /inl"
        let context = SlashContext.detect(in: editor.string, selection: NSRange(location: 12, length: 0))!
        SlashEntry.matching("inl")[0].apply(to: editor, context: context)
        #expect(editor.string == "Area is $x$")
        #expect((editor.string as NSString).substring(with: editor.selectedRange()) == "x")
        #expect(SlashEntry.matching("math").map(\.title) == ["Math", "Inline math"])
    }

    @Test @MainActor func mermaidSlashEntryInsertsAStarterGraph() {
        let editor = NSTextView(usingTextLayoutManager: true)
        editor.string = "/merm"
        let context = SlashContext.detect(in: editor.string, selection: NSRange(location: 5, length: 0))!
        SlashEntry.matching("merm")[0].apply(to: editor, context: context)
        #expect(editor.string == "```mermaid\ngraph TD\n  A --> B\n```")
        #expect((editor.string as NSString).substring(with: editor.selectedRange()) == "A --> B")
    }

    @Test @MainActor func dividerNeverMakesASetextHeading() {
        let divider = SlashEntry.all.first { $0.title == "Divider" }!
        for (source, expected) in [("Para /div", "Para\n\n---"), ("Para\n/div", "Para\n\n---"), ("Para\n\n/div", "Para\n\n---"), ("/div", "---")] {
            let editor = NSTextView(usingTextLayoutManager: true)
            editor.string = source
            let context = SlashContext.detect(in: source, selection: NSRange(location: (source as NSString).length, length: 0))!
            divider.apply(to: editor, context: context)
            #expect(editor.string == expected, "\(source)")
        }
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

    /// Applies `edit` with the caret on the first `cell` text, returning the new source and the selected cell's text.
    @MainActor private func tableEdit(_ edit: MarkdownTable.Edit, in source: String, at cell: String) -> (applied: Bool, text: String, selected: String) {
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.string = source
        let applied = editor.editTable(edit, at: (source as NSString).range(of: cell).location)
        return (applied, editor.string, (editor.string as NSString).substring(with: editor.selectedRange()))
    }

    @Test @MainActor func tableRowsInsertAroundTheHeaderAndBody() {
        let table = "Intro\n\n| A | B |\n| --- | :-: |\n| C | D |\n| E | F |\n\nAfter"
        let cases: [(MarkdownTable.Edit, String, String)] = [
            (.insertRowAbove, "C", "| A | B |\n| --- | :-: |\n|  |  |\n| C | D |\n| E | F |"),
            (.insertRowBelow, "F", "| A | B |\n| --- | :-: |\n| C | D |\n| E | F |\n|  |  |"),
            // A row above the header becomes the header; the old header moves under the delimiter.
            (.insertRowAbove, "A", "|  |  |\n| --- | :-: |\n| A | B |\n| C | D |\n| E | F |"),
            (.insertRowBelow, "B", "| A | B |\n| --- | :-: |\n|  |  |\n| C | D |\n| E | F |"),
            // The delimiter row acts as the header.
            (.insertRowBelow, ":-:", "| A | B |\n| --- | :-: |\n|  |  |\n| C | D |\n| E | F |"),
        ]
        for (edit, cell, expected) in cases {
            let result = tableEdit(edit, in: table, at: cell)
            #expect(result.applied)
            #expect(result.text == "Intro\n\n" + expected + "\n\nAfter", "\(edit) at \(cell)")
            #expect(result.selected == "", "\(edit) at \(cell) moves into the new row")
            #expect(MarkdownTable.blocks(in: result.text).map(\.rows.count) == [expected.split(separator: "\n").count])
        }
    }

    @Test @MainActor func tableRowsDeleteAndPromoteTheFirstBodyRow() {
        let table = "| A | B |\n| --- | :-: |\n| C | D |\n| E | F |"
        let header = tableEdit(.deleteRow, in: table, at: "B")
        #expect(header.text == "| C | D |\n| --- | :-: |\n| E | F |")
        #expect(header.selected == "D")
        let last = tableEdit(.deleteRow, in: table, at: "E")
        #expect(last.text == "| A | B |\n| --- | :-: |\n| C | D |")
        #expect(last.selected == "C")
        let only = tableEdit(.deleteRow, in: "| A | B |\n| --- | --- |\n| C | D |", at: "C")
        #expect(only.text == "| A | B |\n| --- | --- |")
        #expect(only.selected == "A")
        // A header with no body row to promote stays.
        let alone = tableEdit(.deleteRow, in: "| A | B |\n| --- | --- |", at: "A")
        #expect(!alone.applied)
        #expect(alone.text == "| A | B |\n| --- | --- |")
    }

    @Test @MainActor func tableColumnsInsertAndDeleteAtTheEdges() {
        let table = "| A | B |\n| --- | :-: |\n| C | D |"
        let first = tableEdit(.insertColumnLeft, in: table, at: "A")
        #expect(first.text == "|  | A | B |\n| --- | --- | :-: |\n|  | C | D |")
        #expect(first.selected == "")
        let last = tableEdit(.insertColumnRight, in: table, at: "D")
        #expect(last.text == "| A | B |  |\n| --- | :-: | --- |\n| C | D |  |")
        let middle = tableEdit(.insertColumnRight, in: table, at: "A")
        #expect(middle.text == "| A |  | B |\n| --- | --- | :-: |\n| C |  | D |")
        let deleted = tableEdit(.deleteColumn, in: table, at: "A")
        #expect(deleted.text == "| B |\n| :-: |\n| D |")
        #expect(deleted.selected == "B")
        let deletedLast = tableEdit(.deleteColumn, in: table, at: "D")
        #expect(deletedLast.text == "| A |\n| --- |\n| C |")
        #expect(deletedLast.selected == "C")
        #expect(!tableEdit(.deleteColumn, in: "| A |\n| --- |\n| C |", at: "A").applied)
    }

    @Test @MainActor func tableEditsKeepTheSourceStyle() {
        // No outer pipes: a table left with one column gains them, or it would stop being a table.
        let bare = tableEdit(.deleteColumn, in: "A | B\n--- | ---\nC | D", at: "B")
        #expect(bare.text == "|A |\n|--- |\n|C |")
        #expect(MarkdownTable.blocks(in: bare.text).count == 1)
        let unpadded = tableEdit(.insertColumnRight, in: "|A|B|\n|---|---|\n|C|D|", at: "B")
        #expect(unpadded.text == "|A|B|  |\n|---|---|---|\n|C|D|  |")
        // Escaped pipes stay inside their cell; a short row is padded to reach the new column.
        let escaped = tableEdit(.insertColumnRight, in: "| a \\| b | c |\n| --- | --- |\n| d |", at: "c")
        #expect(escaped.text == "| a \\| b | c |  |\n| --- | --- | --- |\n| d |  |  |")
        let crlf = tableEdit(.insertRowBelow, in: "| A |\r\n| --- |\r\n| C |", at: "C")
        #expect(crlf.text == "| A |\r\n| --- |\r\n| C |\r\n|  |")
    }

    @Test @MainActor func tableMenuOffersEditsOnlyInsideATable() {
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.string = "Text\n\n| A |\n| --- |\n| C |"
        #expect(editor.tableMenuItems(at: 1).isEmpty)
        let items = editor.tableMenuItems(at: (editor.string as NSString).range(of: "C").location)
        #expect(items.filter { !$0.isSeparatorItem }.map(\.title) == MarkdownTable.Edit.allCases.map(\.title))
        let enabled = items.filter { !$0.isSeparatorItem && editor.validateMenuItem($0) }.map(\.title)
        #expect(enabled == ["Insert Row Above", "Insert Row Below", "Insert Column Left", "Insert Column Right", "Delete Row"])
    }

    @Test func tableShortcutsUseArrowAndDeleteKeys() {
        #expect(Shortcuts.display("opt cmd up") == "⌥⌘↑")
        #expect(Shortcuts.display("shift opt cmd delete") == "⌥⇧⌘⌫")
        #expect(Shortcuts.keyboardShortcut("insertColumnLeft", stored: "") == KeyboardShortcut(.leftArrow, modifiers: [.option, .command]))
        #expect(Set(MarkdownTable.Edit.allCases.map(\.rawValue)).isSubset(of: Shortcuts.actions.map(\.id)))
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
        // List syntax inside a code block is code, not a list.
        editor.string = "```\n- item\n```"
        editor.setSelectedRange(NSRange(location: 10, length: 0))
        #expect(!editor.continueList())
        // Nested and quoted items continue at their own depth.
        editor.string = "- a\n  1) b"
        editor.setSelectedRange(NSRange(location: 10, length: 0))
        #expect(editor.continueList())
        #expect(editor.string == "- a\n  1) b\n  2) ")
        editor.string = "> - quoted"
        editor.setSelectedRange(NSRange(location: 10, length: 0))
        #expect(editor.continueList())
        #expect(editor.string == "> - quoted\n> - ")
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

    @Test func shortcutReassignmentComparesModifierSets() {
        let spec = "opt shift cmd delete"
        let moved = Shortcuts.assigning(spec, to: "bold", stored: "")
        #expect(Shortcuts.keyboardShortcut("deleteColumn", stored: moved) == nil)
        #expect(Shortcuts.keyboardShortcut("bold", stored: moved) == Shortcuts.keyboardShortcut("deleteColumn", stored: ""))
        let restored = Shortcuts.assigning(spec, to: "deleteColumn", stored: moved)
        #expect(Shortcuts.overrides(restored)["deleteColumn"] == nil)
        #expect(Shortcuts.keyboardShortcut("bold", stored: restored) == nil)
        let legacy = Shortcuts.encode(["italic": "cmd shift opt delete", "deleteColumn": ""])
        #expect(Shortcuts.keyboardShortcut("italic", stored: Shortcuts.assigning(spec, to: "bold", stored: legacy)) == nil)
    }

    @Test @MainActor func remoteImageSettingRefreshesCachedRendering() {
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        let source = "<img src=\"https://example.com/settings.png\">"
        editor.string = source
        let native = NativeEditor(text: .constant(source), fileURL: nil, columnWidth: 640, markdownLens: false,
            findQuery: "", matchCase: false, selectedRange: .constant(NSRange(location: 0, length: 0)),
            textView: .constant(editor), onType: {}, onSlash: { _ in }, onSlashKey: { _, _ in false }, onSelectionRect: { _ in })
        editor.htmlBlocks[0] = .init(text: NSAttributedString(string: "Previously loaded image"), scale: 1, height: 20)
        var refreshes = 0
        editor.restyle = {
            refreshes += 1
            // HTML images are cached during styling rather than resolved at each paint.
            if !editor.loadRemoteImages {
                native.style(editor)
            }
        }
        defer { editor.restyle = nil }
        editor.loadRemoteImages = false
        #expect(refreshes == 1)
        #expect(editor.htmlBlocks[0]?.text.string.contains("Remote image") == true)
        #expect(editor.htmlBlocks[0]?.text.string.contains("example.com") == true)
        guard case .placeholder(let message) = editor.image(for: "https://example.com/settings.png") else {
            Issue.record("Disabled remote images must show a placeholder")
            return
        }
        #expect(message == "Remote image — example.com")
        editor.loadRemoteImages = false
        #expect(refreshes == 1)
        editor.loadRemoteImages = true
        #expect(refreshes == 2)
        #expect(editor.string == source)
    }

    @Test @MainActor func htmlBlocksDecodeUTF8AndRestylesWaitForTheCurrentPass() {
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        let source = "<p align=\"center\">Markify — one page</p>\n"
        editor.string = source
        let native = NativeEditor(text: .constant(source), fileURL: nil, columnWidth: 640, markdownLens: false,
            findQuery: "", matchCase: false, selectedRange: .constant(NSRange(location: 0, length: 0)),
            textView: .constant(editor), onType: {}, onSlash: { _ in }, onSlashKey: { _, _ in false }, onSelectionRect: { _ in })
        native.style(editor)
        #expect(editor.htmlBlocks[0]?.text.string.contains("Markify — one page") == true)
        // A restyle asked for while a pass runs (WebKit's HTML import spins the run loop) waits for it.
        editor.isStyling = true
        editor.htmlBlocks = [:]
        native.style(editor)
        #expect(editor.htmlBlocks.isEmpty)
        #expect(editor.restyleAfterStyling)
        editor.isStyling = false
        #expect(editor.string == source)
    }

    @Test @MainActor func systemWritingToolsOnlyReportsRetainedBodyEdits() {
        let original = "---\ntype: note\n---\nOriginal body"
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.string = original
        var humanEdits = 0
        var starts = 0
        var results: [Bool] = []
        let native = NativeEditor(text: .constant(original), fileURL: nil, columnWidth: 640, markdownLens: false,
            findQuery: "", matchCase: false, selectedRange: .constant(NSRange(location: 0, length: 0)),
            textView: .constant(editor), onType: { humanEdits += 1 }, onSlash: { _ in },
            onSlashKey: { _, _ in false }, onSelectionRect: { _ in },
            onWritingToolsBegin: { starts += 1 }, onWritingToolsEnd: { results.append($0) })
        let coordinator = native.makeCoordinator()
        coordinator.editor = editor
        func change(_ text: String) {
            editor.string = text
            coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
        }
        coordinator.textViewWritingToolsWillBegin(editor)
        change(original + " rewritten")
        #expect(humanEdits == 0)
        coordinator.textViewWritingToolsDidEnd(editor)
        #expect(results == [true])
        coordinator.textViewWritingToolsWillBegin(editor)
        change(original)
        change(original + " rewritten") // Discard the proposed edit.
        coordinator.textViewWritingToolsDidEnd(editor)
        coordinator.textViewWritingToolsWillBegin(editor)
        change(editor.string.replacingOccurrences(of: "type: note", with: "type: concept"))
        coordinator.textViewWritingToolsDidEnd(editor)
        coordinator.textViewWritingToolsWillBegin(editor)
        coordinator.textViewWritingToolsDidEnd(editor) // Opening and closing without editing.
        #expect(starts == 4)
        #expect(results == [true, false, false, false])
        #expect(humanEdits == 0)
        change(original + " typed")
        #expect(humanEdits == 1)
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

    @Test @MainActor func footnotesJumpToTheirDefinitionAndBack() {
        let editor = MarkdownTextView(usingTextLayoutManager: true)
        editor.string = "One[^a] and two[^a] and lost[^x].\n\n[^a]: The note.\n"
        let ns = editor.string as NSString
        let second = ns.range(of: "two[^a]").location + 3
        #expect(editor.followFootnote(at: second + 2))
        #expect(editor.selectedRange() == NSRange(location: ns.range(of: "[^a]:").location + 2, length: 1))
        // Back from the definition to the reference the jump came from, not the first one.
        #expect(editor.followFootnote(at: ns.range(of: "[^a]:").location + 1))
        #expect(editor.selectedRange() == NSRange(location: second + 2, length: 1))
        #expect(editor.followFootnote(at: ns.range(of: "[^x]").location + 2))
        #expect(!editor.followFootnote(at: 1))
    }

    @Test @MainActor func droppedNotesBecomePortableLinks() {
        let library = URL(fileURLWithPath: "/tmp/lib")
        let note = library.appendingPathComponent("notes/Other note.md")
        let document = library.appendingPathComponent("drafts/today.md")
        #expect(MarkdownTextView.noteLink(to: note, title: "Other", from: document, bundleRoot: nil) == "[Other](../notes/Other%20note.md)")
        #expect(MarkdownTextView.noteLink(to: note, title: "Other", from: library.appendingPathComponent("notes/a.md"), bundleRoot: nil) == "[Other](Other%20note.md)")
        #expect(MarkdownTextView.noteLink(to: note, title: "Other", from: document, bundleRoot: library) == "[Other](/notes/Other%20note.md)")
        // A target outside the document's bundle stays relative.
        #expect(MarkdownTextView.noteLink(to: URL(fileURLWithPath: "/tmp/elsewhere/x.md"), title: "X", from: document, bundleRoot: library) == "[X](../../elsewhere/x.md)")
        #expect(MarkdownTextView.noteLink(to: note, title: "A [draft]", from: nil, bundleRoot: nil) == "[A \\[draft\\]](/tmp/lib/notes/Other%20note.md)")
        #expect(MarkdownTextView.noteTitle("---\ntitle: Front\n---\n# Heading\n", url: note) == "Front")
        #expect(MarkdownTextView.noteTitle("Intro\n# Heading\n", url: note) == "Heading")
        #expect(MarkdownTextView.noteTitle("No heading", url: note) == "Other note")
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

@MainActor private final class RefreshTestDocument: NSDocument {
    var text = "original"
    var reloads = 0
    var browsing = false
    var viewing = false
    override var isBrowsingVersions: Bool { browsing }
    override var isInViewingMode: Bool { viewing }
    override func fileWrapper(ofType typeName: String) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
    override func revert(toContentsOf url: URL, ofType typeName: String) throws {
        text = try String(contentsOf: url, encoding: .utf8)
        reloads += 1
        updateChangeCount(.changeCleared)
    }
}
