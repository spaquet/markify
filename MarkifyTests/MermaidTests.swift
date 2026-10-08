import AppKit
import PDFKit
import Testing
@testable import Markify

@MainActor struct MermaidTests {
    @Test func engineRecoverySettlesExportsAndCanRenderAgain() async {
        let renderer = MermaidRenderer()
        let pending = Task { await renderer.svg(for: "graph TD\n A --> B") }
        await Task.yield()
        renderer.recover("Injected engine failure")
        #expect(await pending.value == nil)
        let svg = await renderer.svg(for: "graph TD\n A --> C")
        #expect(svg?.contains("<svg") == true)
        renderer.recover("Test complete")
    }

    @Test func obsoleteDiagramVersionsLeaveTheQueue() {
        let renderer = MermaidRenderer()
        let owner = NSObject()
        for index in 0..<20 { _ = renderer.state(of: "graph TD\n A --> B\(index)", dark: false, owner: owner, onChange: {}) }
        renderer.release(owner: owner, keeping: ["false:graph TD\n A --> B19"])
        #expect(renderer.pendingCount <= 2)
        renderer.release(owner: owner)
        renderer.recover("Test complete")
        #expect(renderer.pendingCount == 0)
    }

    /// Waits for the shared renderer to settle a diagram.
    func render(_ source: String, dark: Bool = false, renderer: MermaidRenderer = .shared) async -> MermaidRenderer.State {
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

    @Test func diagramsRenderOffline() async {
        guard case .rendered(let image) = await render("graph TD\n  A[Write] --> B[Render]") else { Issue.record("not rendered"); return }
        #expect(image.size.width > 20 && image.size.height > 20)
    }

    @Test func diagramTypesRenderInBothThemesAndExport() async throws {
        let renderer = MermaidRenderer()
        defer { renderer.recover("Test complete") }
        let sources = [
            "flowchart LR\n subgraph Editing\n A[Draft] --> B{Ready?}\n end\n B -->|Yes| C[Publish]\n B -->|No| A",
            "---\ntitle: Publishing\nconfig:\n  flowchart:\n    curve: linear\n---\nflowchart TD\n A[\"Draft<br/>Café\"] --> B[\"**Publish**\"]",
            "sequenceDiagram\n autonumber\n participant A as Alice\n participant B as Bob\n A->>+B: Hello\n alt Available\n B-->>-A: Hi\n else Busy\n Note over A,B: Try later\n end",
            "classDiagram\n Animal <|-- Duck\n Animal : +int age\n Duck : +swim()",
            "stateDiagram-v2\n [*] --> Draft\n Draft --> Published\n Published --> [*]",
            "erDiagram\n CUSTOMER ||--o{ ORDER : places\n CUSTOMER {\n int id PK\n string name\n }",
            "gantt\n title Release\n dateFormat YYYY-MM-DD\n section Work\n Draft :a1, 2026-10-01, 2d\n Review :after a1, 1d",
            "pie title Notes\n \"Draft\" : 3\n \"Published\" : 7",
            "journey\n title Publishing\n section Writing\n Draft: 5: Author\n Review: 3: Editor",
            "gitGraph\n commit\n branch draft\n checkout draft\n commit\n checkout main\n merge draft",
            "mindmap\n root((Notes))\n  Draft\n  Published",
            "timeline\n title Releases\n 2026 : Markify",
            "quadrantChart\n title Priorities\n x-axis Low effort --> High effort\n y-axis Low value --> High value\n Draft: [0.3, 0.6]",
            "xychart-beta\n x-axis [Jan, Feb, Mar]\n y-axis \"Notes\" 0 --> 10\n bar [3, 5, 8]",
            "block-beta\n columns 2\n A[\"Draft\"] B[\"Publish\"]\n A --> B",
            "sankey-beta\n Draft,Review,5\n Review,Publish,3",
            "requirementDiagram\n requirement publishing {\n id: 1\n text: save notes\n risk: low\n verifymethod: test\n }\n element editor {\n type: application\n }\n editor - satisfies -> publishing",
            "packet-beta\n 0-7: \"Header\"\n 8-15: \"Data\"",
            "architecture-beta\n group app(cloud)[App]\n service editor(server)[Editor] in app\n service disk(disk)[Notes] in app\n editor:R -- L:disk",
            "kanban\n draft[Draft]\n  note[Write a note]\n published[Published]\n  guide[User guide]",
            "C4Context\n title Publishing\n Person(author, \"Author\", \"Writes notes\")\n System(editor, \"Markify\", \"Markdown editor\")\n Rel(author, editor, \"Uses\")"
        ]
        for source in sources {
            for dark in [false, true] {
                let state = await render(source, dark: dark, renderer: renderer)
                guard case .rendered(let image) = state else {
                    Issue.record("Failed to render \(source) (dark: \(dark)): \(state)")
                    continue
                }
                #expect(image.size.width > 20 && image.size.height > 20, "Unexpected size \(image.size) for \(source) (dark: \(dark))")
            }
            let svg = try #require(await renderer.svg(for: source), "No SVG for \(source)")
            #expect(svg.contains("<svg"))
            #expect(svg.contains("</svg>"))
            renderer.release(owner: renderer)
        }
    }

    /// A full cache evicts the least recently drawn diagram instead of refusing the new one.
    @Test func fullCacheEvictsTheLeastRecentlyDrawnDiagram() async {
        let renderer = MermaidRenderer()
        defer { renderer.recover("Test complete") }
        let first = "graph TD\n A --> B", second = "graph TD\n C --> D", third = "graph TD\n E --> F"
        guard case .rendered(let image) = await render(first, renderer: renderer),
              case .rendered(let secondImage) = await render(second, renderer: renderer) else { Issue.record("not rendered"); return }
        renderer.memoryBudget = MermaidRenderer.cost(of: image) + MermaidRenderer.cost(of: secondImage)
        _ = renderer.cached(first, dark: false)
        guard case .rendered = await render(third, renderer: renderer) else { Issue.record("refused"); return }
        guard case .evicted(let size) = renderer.state(of: second, dark: false, onChange: {}) else { Issue.record("not evicted"); return }
        #expect(size == secondImage.size)
        guard case .rendered = renderer.state(of: first, dark: false, onChange: {}) else { Issue.record("recent diagram evicted"); return }

        // Drawing the evicted diagram renders it again, at the same size, and evicts the next oldest.
        let restored: MermaidRenderer.State = await withCheckedContinuation { continuation in
            var resumed = false
            _ = renderer.state(of: second, dark: false) {
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: renderer.cached(second, dark: false) ?? .rendering)
            }
            _ = renderer.cached(second, dark: false)
        }
        guard case .rendered(let again) = restored else { Issue.record("not rendered again: \(restored)"); return }
        #expect(again.size == secondImage.size)
        guard case .evicted = renderer.state(of: first, dark: false, onChange: {}) else { Issue.record("oldest kept"); return }
    }

    @Test func invalidDiagramsReportMermaidsMessage() async {
        guard case .failed(let message) = await render("graph TD\n  A -->") else { Issue.record("did not fail"); return }
        #expect(message.contains("Parse error"))
    }

    @Test func largeDiagramsScaleToTheColumn() {
        #expect(MarkdownTextView.fitted(NSSize(width: 1216, height: 400), width: 640) == NSSize(width: 608, height: 200))
        #expect(MarkdownTextView.fitted(NSSize(width: 300, height: 100), width: 640) == NSSize(width: 300, height: 100))
    }

    /// Diagrams are kept as PDF: full size, sharp at any width, with labels as text and a clear background.
    @Test func diagramsRenderAsVectors() async throws {
        let renderer = MermaidRenderer()
        defer { renderer.recover("Test complete") }
        let nodes = (0..<30).map { "  N\($0)[Node \($0) with a fairly long label] --> M\($0)[Another long label \($0)]" }
        for dark in [false, true] {
            guard case .rendered(let image) = await render("flowchart LR\n" + nodes.joined(separator: "\n"), dark: dark, renderer: renderer) else {
                Issue.record("not rendered (dark: \(dark))"); continue
            }
            let pdf = try #require(image.representations.first as? NSPDFImageRep)
            #expect(image.size.width * image.size.height > 524_288, "\(image.size)")
            #expect(MermaidRenderer.cost(of: image) < 1_000_000, "\(MermaidRenderer.cost(of: image)) bytes")
            // Mermaid draws flowchart labels in <foreignObject>; they must survive into the PDF.
            let text = try #require(PDFDocument(data: pdf.pdfRepresentation)?.string)
            #expect(text.contains("Node 29 with a") && text.contains("label 29"))
            let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1216, pixelsHigh: 1216, bitsPerSample: 8, samplesPerPixel: 4,
                                                       hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            let clock = ContinuousClock()
            let elapsed = clock.measure { image.draw(in: NSRect(x: 0, y: 0, width: 1216, height: 1216)) }
            NSGraphicsContext.restoreGraphicsState()
            // Mermaid pads the diagram, so the corners show the background.
            #expect(bitmap.colorAt(x: 0, y: 0)?.alphaComponent == 0, "The page background is painted (dark: \(dark))")
            #expect(bitmap.colorAt(x: 1215, y: 1215)?.alphaComponent == 0, "The page background is painted (dark: \(dark))")
            #expect(elapsed < .milliseconds(50), "Drawing took \(elapsed)")
        }
    }
}
