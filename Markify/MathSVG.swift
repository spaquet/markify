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
            guard let id = FontId(rawValue: font) else { return nil }
            let ctFont = KaTeXFontProvider.shared.font(for: id, size: CGFloat(glyphEm))
            var characters = Array(String(Character(id.ttfGlyphScalar(forDisplayCharCode: charCode))).utf16)
            var glyphs = [CGGlyph](repeating: 0, count: characters.count)
            guard CTFontGetGlyphsForCharacters(ctFont, &characters, &glyphs, characters.count), glyphs[0] != 0,
                  let path = CTFontCreatePathForGlyph(ctFont, glyphs[0], nil) else { return nil }
            let px = CGFloat(x), py = CGFloat(y)
            func point(_ p: CGPoint) -> String { "\(String(format: "%.2f", px + p.x)) \(String(format: "%.2f", py - p.y))" }
            var d = ""
            path.applyWithBlock { element in
                let points = element.pointee.points
                switch element.pointee.type {
                case .moveToPoint: d += "M\(point(points[0]))"
                case .addLineToPoint: d += "L\(point(points[0]))"
                case .addQuadCurveToPoint: d += "Q\(point(points[0])) \(point(points[1]))"
                case .addCurveToPoint: d += "C\(point(points[0])) \(point(points[1])) \(point(points[2]))"
                case .closeSubpath: d += "Z"
                @unknown default: break
                }
            }
            return d.isEmpty ? nil : .path(d)
        }
    }
}
