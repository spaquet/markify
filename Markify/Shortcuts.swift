import AppKit
import SwiftUI

/// Keyboard shortcuts the user can change in Settings › Shortcuts.
/// A shortcut is stored as space-separated modifiers then a key, e.g. "cmd shift x" or "cmd return".
enum Shortcuts {
    struct Action: Identifiable {
        let id: String
        let title: String
        let section: String
        let key: String
    }

    static let storageKey = "shortcuts"
    static let sections = ["Editor", "Formatting", "Tables", "Apple Intelligence"]

    static let actions: [Action] = [
        .init(id: "toggleMarkdown", title: "Toggle Markdown", section: "Editor", key: "cmd /"),
        .init(id: "library", title: "Library", section: "Editor", key: "ctrl cmd s"),
        .init(id: "find", title: "Find", section: "Editor", key: "cmd f"),
        .init(id: "replace", title: "Replace", section: "Editor", key: "opt cmd f"),
        .init(id: "findNext", title: "Find Next", section: "Editor", key: "cmd g"),
        .init(id: "findPrevious", title: "Find Previous", section: "Editor", key: "shift cmd g"),
        .init(id: "zoomIn", title: "Zoom In", section: "Editor", key: "cmd ="),
        .init(id: "zoomOut", title: "Zoom Out", section: "Editor", key: "cmd -"),
        .init(id: "actualSize", title: "Actual Size", section: "Editor", key: "cmd 0"),
        .init(id: "bold", title: "Bold", section: "Formatting", key: "cmd b"),
        .init(id: "italic", title: "Italic", section: "Formatting", key: "cmd i"),
        .init(id: "strikethrough", title: "Strikethrough", section: "Formatting", key: "shift cmd x"),
        .init(id: "code", title: "Inline Code", section: "Formatting", key: "cmd e"),
        .init(id: "link", title: "Link", section: "Formatting", key: "cmd k"),
        .init(id: "body", title: "Body", section: "Formatting", key: "opt cmd 0"),
        .init(id: "title", title: "Title", section: "Formatting", key: "opt cmd 1"),
        .init(id: "heading", title: "Heading", section: "Formatting", key: "opt cmd 2"),
        .init(id: "subheading", title: "Subheading", section: "Formatting", key: "opt cmd 3"),
        .init(id: "insertRowAbove", title: "Insert Row Above", section: "Tables", key: "opt cmd up"),
        .init(id: "insertRowBelow", title: "Insert Row Below", section: "Tables", key: "opt cmd down"),
        .init(id: "insertColumnLeft", title: "Insert Column Left", section: "Tables", key: "opt cmd left"),
        .init(id: "insertColumnRight", title: "Insert Column Right", section: "Tables", key: "opt cmd right"),
        .init(id: "deleteRow", title: "Delete Row", section: "Tables", key: "opt cmd delete"),
        .init(id: "deleteColumn", title: "Delete Column", section: "Tables", key: "shift opt cmd delete"),
        .init(id: "writingTools", title: "Writing Tools", section: "Apple Intelligence", key: "shift cmd w"),
        .init(id: "generate", title: "Generate / Continue", section: "Apple Intelligence", key: "cmd return"),
    ]

    static func overrides(_ stored: String) -> [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(stored.utf8))) ?? [:]
    }

    static func encode(_ overrides: [String: String]) -> String {
        (try? JSONEncoder().encode(overrides)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    static func key(_ id: String, stored: String) -> String {
        overrides(stored)[id] ?? actions.first { $0.id == id }?.key ?? ""
    }

    static func keyboardShortcut(_ id: String, stored: String) -> KeyboardShortcut? {
        let parts = key(id, stored: stored).split(separator: " ").map(String.init)
        guard let key = parts.last else { return nil }
        var modifiers: EventModifiers = []
        for part in parts.dropLast() {
            switch part {
            case "cmd": modifiers.insert(.command)
            case "shift": modifiers.insert(.shift)
            case "opt": modifiers.insert(.option)
            case "ctrl": modifiers.insert(.control)
            default: break
            }
        }
        let equivalent: KeyEquivalent = switch key {
        case "return": .return
        case "delete": .delete
        case "up": .upArrow
        case "down": .downArrow
        case "left": .leftArrow
        case "right": .rightArrow
        default: KeyEquivalent(Character(key))
        }
        return KeyboardShortcut(equivalent, modifiers: modifiers)
    }

    /// Keys named by a word, with their glyph and key code.
    private static let namedKeys: [(name: String, glyph: String, code: UInt16)] = [
        ("return", "↩", 36), ("return", "↩", 76), ("delete", "⌫", 51),
        ("up", "↑", 126), ("down", "↓", 125), ("left", "←", 123), ("right", "→", 124),
    ]

    /// Menu-style glyphs, e.g. "⇧⌘X".
    static func display(_ spec: String) -> String {
        let parts = spec.split(separator: " ").map(String.init)
        guard let key = parts.last else { return "None" }
        let symbols = [("ctrl", "⌃"), ("opt", "⌥"), ("shift", "⇧"), ("cmd", "⌘")]
        let modifiers = symbols.filter { parts.dropLast().contains($0.0) }.map(\.1).joined()
        return modifiers + (namedKeys.first { $0.name == key }?.glyph ?? key.uppercased())
    }

    /// The shortcut a key press records, or nil unless it uses ⌘ or ⌃.
    static func spec(from event: NSEvent) -> String? {
        let flags = event.modifierFlags
        guard flags.contains(.command) || flags.contains(.control) else { return nil }
        let key: String
        if let named = namedKeys.first(where: { $0.code == event.keyCode }) { key = named.name }
        else if let character = event.charactersIgnoringModifiers?.lowercased().first, !character.isWhitespace { key = String(character) }
        else { return nil }
        let names: [(NSEvent.ModifierFlags, String)] = [(.control, "ctrl"), (.option, "opt"), (.shift, "shift"), (.command, "cmd")]
        return (names.filter { flags.contains($0.0) }.map(\.1) + [key]).joined(separator: " ")
    }
}
