import AppKit
import Foundation
import Testing
@testable import Markify

/// Every Mermaid block in these files must render through Ondine in both themes, or fail for the invalid file.
/// PNG and report.txt land in build/diagram-tests/<file>/ for review.
@MainActor struct DiagramRenderTests {
    nonisolated static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    nonisolated static let files: [String] = {
        let fixtures = "MarkifyTests/Fixtures/"
        return [
            "render-stress-test-2.md",
            fixtures + "render-stress-test.md",
            fixtures + "mermaid-extra.md",
            fixtures + "mermaid-invalid.md",
        ]
    }()

    /// Every per-type example file, named by Ondine's diagram pages.
    nonisolated static var ondineFiles: [String] {
        let folder = root.appendingPathComponent("MarkifyTests/Fixtures/ondine-diagrams", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasSuffix(".md") }.sorted().map { "MarkifyTests/Fixtures/ondine-diagrams/" + $0 }
    }

    @Test(arguments: files)
    func fixturesRenderThroughOndine(_ file: String) async throws {
        try await check(file, expectFailure: file.hasSuffix("mermaid-invalid.md"))
    }

    @Test(arguments: ondineFiles)
    func ondineDiagramTypesRenderThroughOndine(_ file: String) async throws {
        try await check(file, expectFailure: false)
    }

    func check(_ file: String, expectFailure: Bool) async throws {
        let text = try String(contentsOf: Self.root.appendingPathComponent(file), encoding: .utf8)
        let name = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
        let output = Self.root.appendingPathComponent("build/diagram-tests/\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let pattern = try NSRegularExpression(pattern: "^```mermaid[^\\n]*\\n(.*?)^```", options: [.dotMatchesLineSeparators, .anchorsMatchLines])
        let matches = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
        #expect(!matches.isEmpty, "\(file) has no mermaid blocks")
        var report = "\(file): \(matches.count) blocks\n"
        defer { try? report.write(to: output.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8) }
        let renderer = MermaidRenderer(disk: nil)
        defer { renderer.recover("Test complete") }
        for (index, match) in matches.enumerated() {
            let source = (text as NSString).substring(with: match.range(at: 1))
            for dark in [false, true] {
                let label = "\(name) #\(index) \(dark ? "dark" : "light")"
                let state = await settle(source, dark: dark, renderer: renderer)
                switch state {
                case .rendered(let image):
                    if expectFailure {
                        report += "FAIL rendered \(label)\n"
                        Issue.record("\(label) rendered but should fail")
                    } else {
                        report += "OK   \(label) \(Int(image.size.width))x\(Int(image.size.height))\n"
                        try writePNG(image, dark: dark, to: output.appendingPathComponent("\(index)-\(dark ? "dark" : "light").png"))
                    }
                case .failed(let message):
                    report += "\(expectFailure ? "OK  " : "FAIL") failed \(label): \(message)\n"
                    if !expectFailure { Issue.record("\(label) failed: \(message)") }
                default:
                    report += "FAIL unsettled \(label)\n"
                    Issue.record("\(label) did not settle")
                }
            }
        }
    }

    /// Waits for the renderer to settle a diagram.
    func settle(_ source: String, dark: Bool, renderer: MermaidRenderer) async -> MermaidRenderer.State {
        await withCheckedContinuation { continuation in
            var resumed = false
            let state = renderer.state(of: source, dark: dark) {
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: renderer.cached(source, dark: dark) ?? .rendering)
            }
            if case .rendering = state { return }
            resumed = true
            continuation.resume(returning: state)
        }
    }

    func writePNG(_ image: NSImage, dark: Bool, to url: URL) throws {
        let size = image.size
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return }
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
            try png.write(to: url)
        }
    }

    /// Ondine's message is shown to the writer, so it must not carry Rust's debug format.
    @Test func ondineErrorsAreMessagesNotDebugOutput() async throws {
        guard case .failure(let error) = await OndineMermaid.compileInBackground("flowchart LR\n A -->") else {
            Issue.record("invalid source compiled")
            return
        }
        #expect(!error.message.isEmpty)
        #expect(!error.message.contains("Error {"))
        #expect(!error.message.contains("snippet:"))
    }

    @Test func exportSVGComesFromOndine() async {
        let svg = await MermaidRenderer(disk: nil).svg(for: "flowchart LR\n A[Write] --> B[Render]")
        #expect(svg?.contains("ondine-flowchart") == true)
    }
}
