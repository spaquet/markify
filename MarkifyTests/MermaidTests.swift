import AppKit
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
    func render(_ source: String) async -> MermaidRenderer.State {
        await withCheckedContinuation { continuation in
            var resumed = false
            let state = MermaidRenderer.shared.state(of: source, dark: false) {
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: MermaidRenderer.shared.cached(source, dark: false) ?? .rendering)
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

    @Test func invalidDiagramsReportMermaidsMessage() async {
        guard case .failed(let message) = await render("graph TD\n  A -->") else { Issue.record("did not fail"); return }
        #expect(message.contains("Parse error"))
    }

    @Test func largeDiagramsScaleToTheColumn() {
        #expect(MarkdownTextView.fitted(NSSize(width: 1216, height: 400), width: 640) == NSSize(width: 608, height: 200))
        #expect(MarkdownTextView.fitted(NSSize(width: 300, height: 100), width: 640) == NSSize(width: 300, height: 100))
    }
}
