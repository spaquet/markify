import AppKit
import CoreText
import MarkifyMarkdown
import SwaTex
import SwaTexRender

/// LaTeX to self-contained SVG with glyph outlines, sized in `em` so it follows the surrounding text.
enum MathSVG {
    private static let unit = 20.0

    static func render(_ latex: String, display: Bool) -> String? {
        guard let list = try? SwaTexEngine.displayList(for: latex, style: display ? .display : .text, color: .black) else { return nil }
        let svg = renderToSVG(list, SVGOptions(fontSize: unit, padding: 0, embedGlyphs: true, glyphProvider: Glyphs()))
        guard let open = svg.range(of: ">") else { return nil }
        let width = format(list.width), height = format(list.height + list.depth), viewBox = "0 0 \(format(list.width * unit)) \(format((list.height + list.depth) * unit))"
        let label = MarkdownHTML.escape(latex)
        let header = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"\(viewBox)\" width=\"\(width)em\" height=\"\(height)em\""
            + " style=\"vertical-align:-\(format(list.depth))em\" role=\"img\" aria-label=\"\(label)\"><title>\(label)</title>"
        return header + svg[open.upperBound...].replacingOccurrences(of: "rgba(0,0,0,1)", with: "currentColor")
    }

    private static func format(_ value: Double) -> String { String(format: "%.4g", value) }

    /// KaTeX glyphs as outlines from the fonts SwaTexRender bundles, so the SVG needs no web fonts.
    private struct Glyphs: SVGStandaloneGlyphProvider {
        func standaloneGlyph(x: Float, y: Float, glyphEm: Float, font: String, charCode: UInt32) -> SVGStandaloneGlyph? {
            guard let outline = Outlines.shared.outline(font: font, charCode: charCode, size: glyphEm), !outline.isEmpty else { return nil }
            let px = Double(x), py = Double(y)
            var d = ""
            d.reserveCapacity(outline.count * 16)
            func point(_ p: CGPoint) {
                appendNumber(px + p.x, to: &d)
                d += " "
                appendNumber(py - p.y, to: &d)
            }
            for element in outline {
                switch element.type {
                case .moveToPoint: d += "M"; point(element.points[0])
                case .addLineToPoint: d += "L"; point(element.points[0])
                case .addQuadCurveToPoint: d += "Q"; point(element.points[0]); d += " "; point(element.points[1])
                case .addCurveToPoint: d += "C"; point(element.points[0]); d += " "; point(element.points[1]); d += " "; point(element.points[2])
                case .closeSubpath: d += "Z"
                @unknown default: break
                }
            }
            return .path(d)
        }
    }

    /// A number with at most two decimals and no trailing zeros. `String(format:)` per point dominated export time.
    static func appendNumber(_ value: Double, to string: inout String) {
        var hundredths = Int((value * 100).rounded())
        if hundredths < 0 { string += "-"; hundredths = -hundredths }
        string += String(hundredths / 100)
        let fraction = hundredths % 100
        guard fraction != 0 else { return }
        string += fraction < 10 ? ".0" : "."
        string += String(fraction % 10 == 0 ? fraction / 10 : fraction)
    }

    /// Glyph outlines by font, character and size. A document repeats the same few glyphs, so each is read from
    /// its font once; export builds pages off the main thread, so the cache is locked.
    private final class Outlines: @unchecked Sendable {
        struct Element { let type: CGPathElementType; let points: [CGPoint] }
        private struct Key: Hashable { let font: String; let charCode: UInt32; let size: Float }

        static let shared = Outlines()
        private let lock = NSLock()
        private var outlines: [Key: [Element]] = [:]

        func outline(font: String, charCode: UInt32, size: Float) -> [Element]? {
            let key = Key(font: font, charCode: charCode, size: size)
            if let cached = lock.withLock({ outlines[key] }) { return cached }
            guard let id = FontId(rawValue: font) else { return nil }
            let ctFont = KaTeXFontProvider.shared.font(for: id, size: CGFloat(size))
            var characters = Array(String(Character(id.ttfGlyphScalar(forDisplayCharCode: charCode))).utf16)
            var glyphs = [CGGlyph](repeating: 0, count: characters.count)
            guard CTFontGetGlyphsForCharacters(ctFont, &characters, &glyphs, characters.count), glyphs[0] != 0,
                  let path = CTFontCreatePathForGlyph(ctFont, glyphs[0], nil) else { return nil }
            var elements: [Element] = []
            path.applyWithBlock { element in
                let count = switch element.pointee.type {
                case .moveToPoint, .addLineToPoint: 1
                case .addQuadCurveToPoint: 2
                case .addCurveToPoint: 3
                default: 0
                }
                elements.append(Element(type: element.pointee.type, points: Array(UnsafeBufferPointer(start: element.pointee.points, count: count))))
            }
            lock.withLock { outlines[key] = elements }
            return elements
        }
    }
}
