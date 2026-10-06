import AppKit
import CryptoKit
import PDFKit
import Testing
@testable import Markify

@MainActor struct ExportTests {
    let folder: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MarkifyExport-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url.appendingPathComponent("assets"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: url.appendingPathComponent("out"), withIntermediateDirectories: true)
        return url
    }()

    func context(_ source: String, to name: String = "out/doc.html") -> DocumentExport.Context {
        .init(source: source, documentURL: folder.appendingPathComponent("doc.md"), bundleRoot: nil,
              destination: folder.appendingPathComponent(name), fallbackTitle: "Doc")
    }

    @Test func copyAllPreservesSourceAndAddsHTMLForMedium() async {
        let source = "# Café 👋\n\n**Bold** and [link](https://example.com).\n\n```swift\nlet x = 1 < 2\n```\n"
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        await DocumentExport.copyForMedium(source, to: pasteboard)
        #expect(pasteboard.string(forType: .string) == source)
        let html = pasteboard.string(forType: .html) ?? ""
        #expect(html.contains("<h1") && html.contains("Café 👋"))
        #expect(html.contains("<strong>Bold</strong>"))
        #expect(html.contains("href=\"https://example.com\""))
        #expect(html.contains("let x = 1 &lt; 2"))
        #expect(!html.contains("code-label"))
        DocumentExport.copyAll(source, to: pasteboard)
        #expect(pasteboard.string(forType: .string) == source)
        #expect(pasteboard.string(forType: .html) == nil)
    }

    @Test func pageIsCompleteAndTitled() async {
        let page = await DocumentExport.page(context("---\ntitle: Frontmatter Title\ntags: [a, b]\n---\n# Heading\n\nText.\n"), for: .html)
        #expect(page.hasPrefix("<!doctype html>"))
        #expect(page.contains("<html lang=\"en\">"))
        #expect(page.contains("<title>Frontmatter Title</title>"))
        #expect(page.contains("<span class=\"chip\">a</span><span class=\"chip\">b</span>"))
        #expect(page.contains("<main>") && page.contains("prefers-color-scheme:dark") && page.contains("@media print"))
        #expect(!page.contains("Content-Security-Policy"))
    }

    @Test func mathIsVectorSVGInTextColor() {
        let svg = MathSVG.render("\\frac{a}{b}", display: true) ?? ""
        #expect(svg.hasPrefix("<svg"))
        #expect(svg.contains("<path d=\"M"))
        #expect(svg.contains("currentColor"))
        #expect(!svg.contains("<text"))
        #expect(svg.contains("aria-label=\"\\frac{a}{b}\""))
    }

    @Test func mathOutlineNumbersHaveAtMostTwoDecimals() {
        func number(_ value: Double) -> String { var string = ""; MathSVG.appendNumber(value, to: &string); return string }
        #expect(number(7) == "7")
        #expect(number(3.14159) == "3.14")
        #expect(number(10.1) == "10.1")
        #expect(number(0.07) == "0.07")
        #expect(number(-2.5) == "-2.5")
        #expect(number(-0.004) == "0")
    }

    /// MARKIFY-5 (#57): a math-heavy export blocked the main thread. The page now builds off it, and outlines are cached.
    @Test func mathHeavyPageBuildsOffTheMainThread() async {
        let source = (1...300).map { "Term $x_{\($0)}^2 + \\sqrt{y_{\($0)}}$ and\n\n$$\\int_0^{\($0)} \\frac{a}{b} \\, dx$$\n" }.joined(separator: "\n")
        let export = context(source)
        let start = ContinuousClock.now
        let page = await DocumentExport.page(export, for: .html)
        let elapsed = ContinuousClock.now - start
        #expect(page.components(separatedBy: "<svg").count - 1 == 600)
        // Shared CI runners render alongside the other tests; allow headroom for CPU contention.
        #expect(elapsed < .seconds(30), "Math-heavy export took \(elapsed)")
        let detached = await Task.detached {
            DocumentExport.render(export, diagrams: [:], pdf: false, remoteImages: true)
        }.value
        #expect(detached == page)
    }

    @Test func localImagesAreEmbedded() throws {
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in NSColor.red.setFill(); rect.fill(); return true }
        let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        try png.write(to: folder.appendingPathComponent("assets/my pic.png"))
        #expect(DocumentExport.imageSource("assets/my%20pic.png", context: context("")).hasPrefix("data:image/png;base64,"))
        #expect(DocumentExport.imageSource("https://example.com/a.png", context: context("")) == "https://example.com/a.png")
        // A missing file keeps a path that works from the export's folder.
        #expect(DocumentExport.imageSource("assets/missing.png", context: context("")) == "../assets/missing.png")
    }

    @Test func relativeLinksFollowTheExport() {
        let c = context("")
        #expect(DocumentExport.linkTarget("notes/other.md#part", context: c) == "../notes/other.md#part")
        #expect(DocumentExport.linkTarget("#section", context: c) == "#section")
        #expect(DocumentExport.linkTarget("https://example.com", context: c) == "https://example.com")
        #expect(DocumentExport.linkTarget("mailto:a@b.c", context: c) == "mailto:a@b.c")
    }

    @Test func codeIsEscapedAndColored() {
        let html = DocumentExport.highlighted("let a = \"<b>\" // note")
        #expect(html.contains("<span class=\"tok-keyword\">let</span>"))
        #expect(html.contains("<span class=\"tok-literal\">&quot;&lt;b&gt;&quot;</span>"))
        #expect(html.contains("<span class=\"tok-comment\">// note</span>"))
    }

    @Test func diagramsExportAsSVG() async {
        let source = "```mermaid\nflowchart TD\n  A --> B\n```\n\n~~~MERMAID\nsequenceDiagram\n Alice->>Bob: Hello\n~~~\n"
        for format in [DocumentExport.Format.html, .pdf] {
            let page = await DocumentExport.page(context(source), for: format)
            #expect(page.components(separatedBy: "<figure class=\"diagram\"><svg").count == 3)
            #expect(!page.contains("<code class=\"language-"))
        }
    }

    @Test func pdfIsPaginated() async throws {
        let long = (1...80).map { "## Section \($0)\n\nParagraph \($0) with $x^\($0)$ math and **bold** text.\n" }.joined(separator: "\n")
        let c = context("# Long\n\n" + long, to: "out/doc.pdf")
        let page = await DocumentExport.page(c, for: .pdf)
        #expect(page.contains("Content-Security-Policy"))
        try await DocumentExport.writePDF(c)
        let pdf = try #require(PDFDocument(url: c.destination))
        #expect(pdf.pageCount > 2)
        #expect(pdf.string?.contains("Section 80") == true)
        let size = pdf.page(at: 0)?.bounds(for: .mediaBox).size ?? .zero
        #expect(size == NSPrintInfo.shared.paperSize)
    }

    @Test func cancelledPDFLeavesTheDestinationUntouched() async throws {
        let destination = folder.appendingPathComponent("out/cancelled.pdf")
        try Data("existing".utf8).write(to: destination)
        let printer = PDFPrinter()
        let job = Task { try await printer.print("<html><body>Cancelled export</body></html>", to: destination) }
        // Yield until the navigation wait has been installed, then cancel it.
        await Task.yield()
        job.cancel()
        do { try await job.value; Issue.record("Cancelled PDF export succeeded") }
        catch { #expect(error is CancellationError) }
        #expect(try Data(contentsOf: destination) == Data("existing".utf8))
        // Failure after cancellation cannot resume the continuation a second time.
        printer.fail(URLError(.timedOut))
    }

    @Test func fixtureExportsCleanly() async throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/editor-fixture.md")
        let page = await DocumentExport.page(context(try String(contentsOf: url, encoding: .utf8)), for: .html)
        #expect(!page.contains("\u{E000}") && !page.contains("\u{E002}"))
        #expect(!page.contains("$$"))
    }
}

@MainActor struct WelcomeTourTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MarkifyWelcome-\(UUID().uuidString)")

    @Test func installsTheTourWithItsImage() throws {
        let target = try MarkifyAppDelegate.installWelcome(in: folder)
        #expect(try String(contentsOf: target, encoding: .utf8).contains("# Welcome to Markify"))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("assets/welcome-lenses.webp").path))
    }

    @Test func replacesAnUntouchedOldTourButNotAnEditedOne() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent("Welcome to Markify.md")
        let old = "---\ntags: [essay, editor]\n"
        try old.write(to: target, atomically: true, encoding: .utf8)
        _ = try MarkifyAppDelegate.installWelcome(in: folder)
        #expect(try String(contentsOf: target, encoding: .utf8) == old, "An edited tour is kept")

        // A tour shipped with an earlier version, byte for byte, is replaced.
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/welcome-1.60.md")
        try FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: fixture, to: target)
        _ = try MarkifyAppDelegate.installWelcome(in: folder)
        #expect(try String(contentsOf: target, encoding: .utf8).contains("# Welcome to Markify"))

        let shipped = try #require(Bundle.main.url(forResource: "Welcome", withExtension: "md"))
        let current = try Data(contentsOf: shipped)
        #expect(!MarkifyAppDelegate.previousWelcomes.contains(SHA256.hash(data: current).map { String(format: "%02x", $0) }.joined()),
                "The current tour's hash must not be listed as a previous one")
    }
}
