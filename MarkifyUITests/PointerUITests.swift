import XCTest
import AppKit

/// Pointer interactions that unit tests can't reach: hovering an inline image chip and dropping a note into the page.
@MainActor
final class PointerUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    private func launch(showingWelcome: Bool = false) {
        app.launchArguments += [
            "-startup", "New document", "-didShowWelcome", showingWelcome ? "NO" : "YES",
            "-defaultLens", "Rendered", "-rememberLens", "NO", "-SUEnableAutomaticChecks", "NO", "-ApplePersistenceIgnoreState", "YES",
        ]
        app.launch()
    }

    private var editor: XCUIElement { app.windows.firstMatch.textViews.firstMatch }
    private var text: String { editor.value as? String ?? "" }

    /// Replaces the document with `source` through the pasteboard, so no typing rule rewrites it.
    private func replace(with source: String) {
        editor.click()
        editor.typeKey("a", modifierFlags: .command)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(source, forType: .string)
        editor.typeKey("v", modifierFlags: .command)
        XCTAssertEqual(text, source)
    }

    /// Drags with real mouse events, which need the runner to be allowed to post events.
    /// XCUITest's own drags never start the drag session SwiftUI's `onDrag` needs, though a person's drag does.
    private func drag(from start: CGPoint, to end: CGPoint) {
        func post(_ type: CGEventType, _ point: CGPoint) {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        post(.mouseMoved, start)
        usleep(200_000)
        post(.leftMouseDown, start)
        usleep(300_000)
        for step in 1...40 {
            let t = Double(step) / 40
            post(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
            usleep(25_000)
        }
        usleep(400_000)
        post(.leftMouseUp, end)
    }

    func testHoveringInlineImageChipShowsPreview() {
        launch()
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "No editor window")
        // Rows of chips, so the middle of the page is on one; an image alone on a line would be a block instead.
        let row = Array(repeating: "![a chip to hover](missing-image.png)", count: 4).joined(separator: " ")
        replace(with: "Chips\n\n" + Array(repeating: row, count: 12).joined(separator: "\n\n"))

        let popover = app.popovers.firstMatch
        var hovered = false
        for dy in stride(from: 0.0, through: 0.2, by: 0.02) {
            editor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4 + dy)).hover()
            if popover.waitForExistence(timeout: 0.5) { hovered = true; break }
        }
        XCTAssertTrue(hovered, "Hovering an inline image chip should show its preview")
        XCTAssertTrue(popover.staticTexts["image — missing-image.png"].exists, "A missing image previews as its placeholder")

        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01)).hover()
        XCTAssertTrue(popover.waitForNonExistence(timeout: 2), "Leaving the chip should close the preview")
    }

    func testDroppingNoteFromSidebarInsertsLink() throws {
        // Asks once; allow MarkifyUITests-Runner in System Settings › Privacy & Security › Accessibility.
        try XCTSkipUnless(CGPreflightPostEventAccess() || CGRequestPostEventAccess(),
                          "The test runner may not post mouse events; allow it under Privacy & Security › Accessibility")
        // The first launch opens the Welcome note, which lists it among open files and in the library.
        launch(showingWelcome: true)
        XCTAssertTrue(app.windows["Welcome to Markify.md"].waitForExistence(timeout: 10), "The Welcome note should open")
        app.typeKey("n", modifierFlags: .command)
        let window = app.windows.matching(NSPredicate(format: "title != 'Welcome to Markify.md'")).firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "⌘N should open a new document: \(app.windows.allElementsBoundByIndex.map(\.title))")
        let page = window.textViews.firstMatch
        page.click()

        page.typeKey("s", modifierFlags: [.command, .control])
        let note = window.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Welcome to Markify'")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5), "The library should list the Welcome note")
        drag(from: CGPoint(x: note.frame.midX, y: note.frame.midY),
             to: CGPoint(x: page.frame.minX + page.frame.width * 0.7, y: page.frame.minY + 120))

        // Text in an empty document starts its title, so the link lands after "# ".
        let value = page.value as? String ?? ""
        XCTAssertTrue(value.contains("[Welcome to Markify]("), "Dropping a note should insert a link titled by its heading, got \(value)")
        XCTAssertTrue(value.hasSuffix("/Welcome%20to%20Markify.md)"), "An unsaved document links to the note's absolute path, got \(value)")
    }
}
