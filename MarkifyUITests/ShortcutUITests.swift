import XCTest

/// Presses each default shortcut from Settings › Shortcuts in a new document and checks its effect.
@MainActor
final class ShortcutUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += [
            "-startup", "New document", "-didShowWelcome", "YES", "-shortcuts", "",
            "-defaultLens", "Rendered", "-rememberLens", "NO",
        ]
        app.launch()
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "No editor window")
        editor.click()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    private var editor: XCUIElement { app.textViews.firstMatch }
    private var text: String { editor.value as? String ?? "" }

    /// Replaces the whole document with `source`.
    private func reset(_ source: String) {
        editor.typeKey("a", modifierFlags: .command)
        editor.typeKey(.delete, modifierFlags: [])
        editor.typeText(source)
        // Typing into an empty document starts a title; drop it.
        if !source.hasPrefix("# "), text.hasPrefix("# ") {
            editor.typeKey(.upArrow, modifierFlags: .command)
            editor.typeKey(.forwardDelete, modifierFlags: [])
            editor.typeKey(.forwardDelete, modifierFlags: [])
        }
    }

    private func selectAll() { editor.typeKey("a", modifierFlags: .command) }

    func testInlineFormatting() {
        let cases: [(String, XCUIElement.KeyModifierFlags, String)] = [
            ("b", .command, "**word**"),
            ("i", .command, "*word*"),
            ("x", [.command, .shift], "~~word~~"),
            ("e", .command, "`word`"),
            ("k", .command, "[word](url)"),
        ]
        for (key, modifiers, expected) in cases {
            reset("word")
            selectAll()
            editor.typeKey(key, modifierFlags: modifiers)
            XCTAssertEqual(text, expected, "\(modifiers.rawValue) \(key)")
            editor.typeKey("z", modifierFlags: .command)
            XCTAssertEqual(text, "word", "⌘Z after \(key)")
        }
    }

    func testBlockStyles() {
        let cases: [(String, String)] = [("1", "# word"), ("2", "## word"), ("3", "### word"), ("0", "word")]
        reset("word")
        for (key, expected) in cases {
            editor.typeKey(key, modifierFlags: [.command, .option])
            XCTAssertEqual(text, expected, "⌥⌘\(key)")
        }
    }

    func testLensAndLibrary() {
        let lens = app.buttons["Show Markdown"].firstMatch
        XCTAssertFalse(lens.isSelected)
        editor.typeKey("/", modifierFlags: .command)
        XCTAssertTrue(lens.isSelected, "⌘/ should switch to the Markdown lens")
        editor.typeKey("/", modifierFlags: .command)
        XCTAssertFalse(lens.isSelected, "⌘/ should switch back")

        XCTAssertTrue(app.buttons["Show Library"].exists)
        editor.typeKey("s", modifierFlags: [.command, .control])
        XCTAssertTrue(app.buttons["Hide Library"].waitForExistence(timeout: 2), "⌃⌘S should open the library")
        editor.typeKey("s", modifierFlags: [.command, .control])
        XCTAssertTrue(app.buttons["Show Library"].waitForExistence(timeout: 2), "⌃⌘S should close the library")
    }

    func testFind() {
        reset("hello one\nhello two\nhello three")
        editor.typeKey("f", modifierFlags: .command)
        let find = app.textFields["Find"].firstMatch
        XCTAssertTrue(find.waitForExistence(timeout: 2), "⌘F should show the find panel")
        XCTAssertTrue(find.value(forKey: "hasKeyboardFocus") as? Bool ?? false, "⌘F should focus the Find field")
        find.typeText("hello")
        XCTAssertTrue(app.staticTexts["3 found"].exists || app.staticTexts["1 of 3"].exists)

        editor.click()
        editor.typeKey("g", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["1 of 3"].waitForExistence(timeout: 2), "⌘G should select a match")
        editor.typeKey("g", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["2 of 3"].waitForExistence(timeout: 2), "⌘G should move to the next match")
        editor.typeKey("g", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.staticTexts["1 of 3"].waitForExistence(timeout: 2), "⇧⌘G should move to the previous match")

        editor.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(find.exists, "Esc should close the find panel")
        editor.typeKey("f", modifierFlags: [.command, .option])
        let replace = app.textFields["Replace"].firstMatch
        XCTAssertTrue(replace.waitForExistence(timeout: 2), "⌥⌘F should show the replace field")
        XCTAssertTrue(replace.value(forKey: "hasKeyboardFocus") as? Bool ?? false, "⌥⌘F should focus the Replace field")
    }

    func testZoom() {
        reset(Array(repeating: "A line of text to measure zoom.", count: 40).joined(separator: "\n"))
        // The scroller thumb shrinks as the text grows taller.
        let thumb = app.scrollViews.containing(.textView, identifier: nil).firstMatch.scrollBars.firstMatch.valueIndicators.firstMatch
        editor.typeKey("0", modifierFlags: .command)
        let base = thumb.frame.height
        editor.typeKey("=", modifierFlags: .command)
        editor.typeKey("=", modifierFlags: .command)
        XCTAssertLessThan(thumb.frame.height, base, "⌘= should zoom in")
        editor.typeKey("0", modifierFlags: .command)
        XCTAssertEqual(thumb.frame.height, base, accuracy: 1, "⌘0 should restore")
        editor.typeKey("-", modifierFlags: .command)
        XCTAssertGreaterThan(thumb.frame.height, base, "⌘- should zoom out")
        editor.typeKey("0", modifierFlags: .command)
    }

    func testSlashMenu() {
        reset("")
        editor.typeText("/")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Task list'")).firstMatch.waitForExistence(timeout: 2), "/ should open the block menu")
    }

    func testAppleIntelligence() throws {
        try XCTSkipUnless(app.buttons["Apple Intelligence"].exists, "Apple Intelligence not on this Mac")
        reset("A sentence to rewrite.")
        selectAll()
        editor.typeKey("w", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.descendants(matching: .any)["Key Points"].waitForExistence(timeout: 2), "⇧⌘W should open the Writing Tools menu")

        editor.typeKey(.escape, modifierFlags: [])
        reset("")
        editor.typeKey(.return, modifierFlags: .command)
        XCTAssertTrue(app.textFields["Describe what to write, or press ↩ to continue"].waitForExistence(timeout: 2), "⌘↩ should open the composer")
    }
}
