import AppKit
import Foundation
import Testing
@testable import Markify

/// Spike: every Mermaid block in these files must compile with Ondine, keep no CSS variables, and rasterize in
/// NSImage in both themes. Output goes to Spike/out: PNG, SVG and report.txt per file.
@MainActor struct OndineSpikeTests {
    nonisolated static let files: [String] = {
        let fixtures = "MarkifyTests/Fixtures/"
        return [
            "render-stress-test-2.md",
            fixtures + "render-stress-test.md",
            fixtures + "mermaid-extra.md",
            fixtures + "mermaid-invalid.md",
        ]
    }()

    nonisolated static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    /// Every per-type example file, named by Ondine's diagram pages.
    nonisolated static var ondineFiles: [String] {
        let folder = root.appendingPathComponent("MarkifyTests/Fixtures/ondine-diagrams", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasSuffix(".md") }.sorted().map { "MarkifyTests/Fixtures/ondine-diagrams/" + $0 }
    }

    @Test(arguments: files)
    func fixturesRasterizeInBothThemes(_ file: String) throws {
        try check(file, expectFailure: file.hasSuffix("mermaid-invalid.md"))
    }

    @Test(arguments: ondineFiles)
    func ondineDiagramTypesRasterizeInBothThemes(_ file: String) throws {
        try check(file, expectFailure: false)
    }

    func check(_ file: String, expectFailure: Bool) throws {
        let root = Self.root
        let text = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
        let name = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
        let output = root.appendingPathComponent("Spike/out/\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let pattern = try NSRegularExpression(pattern: "^```mermaid[^\\n]*\\n(.*?)^```", options: [.dotMatchesLineSeparators, .anchorsMatchLines])
        let matches = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
        #expect(!matches.isEmpty, "\(file) has no mermaid blocks")
        var report = "\(file): \(matches.count) blocks\n"
        defer { try? report.write(to: output.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8) }
        for (index, match) in matches.enumerated() {
            let source = (text as NSString).substring(with: match.range(at: 1))
            for dark in [false, true] {
                let label = "\(name) #\(index) \(dark ? "dark" : "light")"
                let svg: String
                do {
                    svg = try OndineMermaid.render(source, dark: dark).get()
                } catch {
                    report += "\(expectFailure ? "OK  " : "FAIL") compile \(label): \(error.localizedDescription)\n"
                    if !expectFailure { Issue.record("\(label) failed to compile: \(error.localizedDescription)") }
                    continue
                }
                if expectFailure {
                    report += "FAIL expected failure \(label)\n"
                    Issue.record("\(label) compiled but should fail")
                    continue
                }
                let suffix = dark ? "dark" : "light"
                try svg.write(to: output.appendingPathComponent("\(index)-\(suffix).svg"), atomically: true, encoding: .utf8)
                if svg.contains("var(") {
                    let leftover = svg.components(separatedBy: "var(").dropFirst().prefix(3).map { String($0.prefix(60)) }
                    report += "FAIL var \(label): \(leftover)\n"
                    Issue.record("\(label) keeps a CSS variable")
                }
                guard let image = NSImage(data: Data(svg.utf8)) else {
                    report += "FAIL image \(label)\n"
                    Issue.record("\(label) is not an image")
                    continue
                }
                let size = image.size
                guard let rep = NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
                ) else { continue }
                rep.size = size
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                if dark {
                    NSColor(calibratedWhite: 0.118, alpha: 1).setFill()
                    NSRect(origin: .zero, size: size).fill()
                }
                image.draw(in: NSRect(origin: .zero, size: size))
                NSGraphicsContext.restoreGraphicsState()
                if let png = rep.representation(using: .png, properties: [:]) {
                    try png.write(to: output.appendingPathComponent("\(index)-\(suffix).png"))
                }
                report += "OK   \(label) \(Int(size.width))x\(Int(size.height))\n"
            }
        }
    }

    @Test func rendererUsesOndineWhenTheFlagIsOn() async {
        UserDefaults.standard.set(true, forKey: "ondineMermaid")
        defer { UserDefaults.standard.removeObject(forKey: "ondineMermaid") }
        let svg = await MermaidRenderer().svg(for: "flowchart LR\n A[Write] --> B[Render]")
        #expect(svg?.contains("ondine") == true)
        #expect(svg?.contains("var(") == false)
    }
}
