import AppKit
import SwiftUI

/// Fonts, zoom and colors the editor draws with, built from Settings.
struct EditorTheme: Equatable {
    var proseFont = "New York"
    var monoFont = "SF Mono"
    var proseSize: CGFloat = 18
    var accent = NSColor.controlAccentColor
    var monochromeCode = false

    static let proseSizes: ClosedRange<CGFloat> = 14...26
    var scale: CGFloat { proseSize / 18 }

    func prose(_ size: CGFloat, bold: Bool = false, italic: Bool = false) -> NSFont {
        let size = size * scale
        var font = NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        // New York is a system design, not a font that can be looked up by name.
        if proseFont == "New York", let serif = font.fontDescriptor.withDesign(.serif), let design = NSFont(descriptor: serif, size: size) { font = design }
        return italic ? adding(.italic, to: font) : font
    }

    /// The same font with bold and/or italic added, keeping its family and size.
    func adding(_ traits: NSFontDescriptor.SymbolicTraits, to font: NSFont) -> NSFont {
        var result = font
        if traits.contains(.bold), !font.fontDescriptor.symbolicTraits.contains(.bold) {
            // Symbolic bold picks Semibold for system designs, so rebuild at the bold weight in the same design.
            let design: NSFontDescriptor.SystemDesign? = font.fontName.contains("NewYork") ? .serif
                : font.fontName.contains("Monospaced") ? .monospaced : font.fontName.hasPrefix(".SF") ? .default : nil
            if let design, let descriptor = NSFont.systemFont(ofSize: font.pointSize, weight: .bold).fontDescriptor.withDesign(design) {
                let italic = descriptor.symbolicTraits.union(font.fontDescriptor.symbolicTraits.intersection(.italic))
                result = NSFont(descriptor: descriptor.withSymbolicTraits(italic), size: font.pointSize) ?? font
            } else {
                result = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            }
        }
        if traits.contains(.italic) {
            result = NSFont(descriptor: result.fontDescriptor.withSymbolicTraits(result.fontDescriptor.symbolicTraits.union(.italic)), size: result.pointSize) ?? result
        }
        return result
    }

    func mono(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let size = size * scale
        if monoFont == "Menlo", let font = NSFont(name: weight == .bold ? "Menlo-Bold" : "Menlo-Regular", size: size) { return font }
        return .monospacedSystemFont(ofSize: size, weight: weight)
    }

    func ui(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: size * scale, weight: weight)
    }

    /// Syntax color for a code token kind, or nil when the code theme is monochrome.
    func code(_ kind: CodeToken) -> NSColor? {
        monochromeCode ? nil : kind.color
    }
}

enum CodeToken: String {
    case keyword, type, literal, comment

    private static let patterns: [(NSRegularExpression, CodeToken)] = ([
        (#"\b(func|let|var|if|else|return|class|struct|import|guard|private|def|const|function|for|while|in|true|false|nil|null)\b"#, .keyword),
        (#"\b[A-Z][A-Za-z0-9_]*\b"#, .type),
        (#""[^"\n]*"|\b[0-9]+(\.[0-9]+)?\b"#, .literal),
        (#"(//|#)[^\n]*"#, .comment)
    ] as [(String, CodeToken)]).map { (try! NSRegularExpression(pattern: $0.0), $0.1) }

    /// Token ranges in `code`, in order of kind; a later range wins where they overlap (a comment over a keyword).
    static func tokens(in code: String) -> [(NSRange, CodeToken)] {
        let whole = NSRange(location: 0, length: (code as NSString).length)
        return patterns.flatMap { regex, kind in regex.matches(in: code, range: whole).map { ($0.range, kind) } }
    }

    var color: NSColor {
        switch self {
        case .keyword: .token(light: 0xAD3DA4, dark: 0xFF7AB2)
        case .type: .token(light: 0x3F6E74, dark: 0x78C2B3)
        case .literal: .token(light: 0xC41A16, dark: 0xD9C97C)
        case .comment: .token(light: 0x8A8F96, dark: 0x7F8C98)
        }
    }
}

extension NSColor {
    /// A color that switches between light and dark hex values with the appearance.
    static func token(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: isDark ? darkAlpha : lightAlpha)
        }
    }

    static let findMatch = token(light: 0xFFD60A, dark: 0xFFD60A, lightAlpha: 0.40, darkAlpha: 0.30)
    static let findCurrent = token(light: 0xFF9F0A, dark: 0xFF9F0A, lightAlpha: 0.70, darkAlpha: 0.65)
    static let codeFill = token(light: 0xF3F1ED, dark: 0x2A2A2D)

    /// The callout fill recipe: the type's color at a low alpha.
    static func calloutFill(_ color: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            color.withAlphaComponent(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? 0.14 : 0.07)
        }
    }
}

/// Settings › Appearance › Accent color.
enum AccentChoice {
    static let all = ["Multicolor", "Blue", "Purple", "Pink", "Orange", "Green", "Graphite"]

    static func nsColor(_ name: String) -> NSColor {
        switch name {
        case "Blue": .systemBlue
        case "Purple": .systemPurple
        case "Pink": .systemPink
        case "Orange": .systemOrange
        case "Green": .systemGreen
        case "Graphite": .systemGray
        default: .controlAccentColor
        }
    }

    static func color(_ name: String) -> Color { Color(nsColor: nsColor(name)) }
}

/// Settings › Appearance › Page color.
enum PageColor {
    static func color(_ name: String, dark: Bool) -> Color {
        switch name {
        case "White": dark ? Color(red: 22/255, green: 22/255, blue: 24/255) : .white
        case "System": Color(nsColor: .textBackgroundColor)
        default: dark ? Color(red: 30/255, green: 30/255, blue: 32/255) : Color(red: 252/255, green: 251/255, blue: 249/255)
        }
    }
}

/// Liquid Glass for the floating controls, following Settings › Glass style and Reduce Transparency.
struct ChromeGlass<S: Shape>: ViewModifier {
    let shape: S
    @AppStorage("glassStyle") private var glassStyle = "System"
    @AppStorage("accentColor") private var accentColor = "Multicolor"
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.14), lineWidth: 1))
        } else {
            content.glassEffect(glass, in: shape)
        }
    }

    private var glass: Glass {
        switch glassStyle {
        case "Clear": .clear
        case "Tinted": .regular.tint(AccentChoice.color(accentColor).opacity(0.3))
        default: .regular
        }
    }
}

extension View {
    func chromeGlass(in shape: some Shape) -> some View { modifier(ChromeGlass(shape: shape)) }
}
