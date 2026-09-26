import AppKit
import WebKit

/// Renders fenced `mermaid` blocks to images with the bundled Mermaid, in one offscreen web view shared by every window.
/// The page allows no network access or navigation; a diagram is rendered once per source and appearance.
@MainActor final class MermaidRenderer: NSObject, WKNavigationDelegate {
    static let shared = MermaidRenderer()

    enum State {
        case rendering
        case rendered(NSImage)
        /// Mermaid's message for a diagram it cannot parse.
        case failed(String)
    }

    private var states: [String: State] = [:]
    private var waiting: [String: [() -> Void]] = [:]
    private var queue: [(key: String, source: String, dark: Bool)] = []
    /// Exports waiting for a diagram's SVG; they share the web view, so one render runs at a time.
    private var svgJobs: [(source: String, id: String, done: (String?) -> Void)] = []
    private var svgCount = 0
    private var busy = false
    private var ready = false
    private var webView: WKWebView?
    private var window: NSWindow?

    /// The diagram's state, starting a render on first request; `onChange` runs once when it settles.
    func state(of source: String, dark: Bool, onChange: @escaping () -> Void) -> State {
        let key = "\(dark):\(source)"
        if let state = states[key] {
            if case .rendering = state { waiting[key, default: []].append(onChange) }
            return state
        }
        // Each edit of a diagram renders anew; drop settled renders before the cache grows large.
        if states.count > 64 { states = states.filter { if case .rendering = $0.value { true } else { false } } }
        states[key] = .rendering
        waiting[key] = [onChange]
        queue.append((key, source, dark))
        start()
        return .rendering
    }

    /// The settled state without starting a render.
    func cached(_ source: String, dark: Bool) -> State? { states["\(dark):\(source)"] }

    /// The diagram as SVG markup in the light theme, for export; nil when Mermaid cannot render it.
    func svg(for source: String) async -> String? {
        await withCheckedContinuation { continuation in
            svgCount += 1
            svgJobs.append((source, "markify-diagram-\(svgCount)", { continuation.resume(returning: $0) }))
            start()
        }
    }

    private func start() {
        guard let page = Bundle.main.url(forResource: "mermaid", withExtension: "html") else {
            finishAll(.failed("Mermaid is missing from this build."))
            return
        }
        if webView == nil {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
            view.navigationDelegate = self
            view.setValue(false, forKey: "drawsBackground")
            // Snapshots need the view in a window; this one never appears on screen.
            let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 800, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = view
            self.window = window
            webView = view
            view.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
            return
        }
        guard ready, !busy else { return }
        if !svgJobs.isEmpty {
            busy = true
            let job = svgJobs.removeFirst()
            Task { await renderSVG(job) }
            return
        }
        guard !queue.isEmpty else { return }
        busy = true
        let next = queue.removeFirst()
        Task { await render(next) }
    }

    private func renderSVG(_ job: (source: String, id: String, done: (String?) -> Void)) async {
        let svg = try? await webView?.callAsyncJavaScript("""
            mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: 'default' });
            const { svg } = await mermaid.render(id, source);
            return svg;
            """, arguments: ["source": job.source, "id": job.id], contentWorld: .page) as? String
        job.done(svg)
        busy = false
        start()
    }

    private func render(_ job: (key: String, source: String, dark: Bool)) async {
        guard let webView else { return }
        let state: State
        do {
            let result = try await webView.callAsyncJavaScript("""
                mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: dark ? 'dark' : 'default' });
                const { svg } = await mermaid.render('diagram' + Date.now(), source);
                const box = document.getElementById('diagram');
                box.innerHTML = svg;
                const rect = box.getBoundingClientRect();
                return [rect.width, rect.height];
                """, arguments: ["source": job.source, "dark": job.dark], contentWorld: .page) as? [Double] ?? []
            let size = NSSize(width: ceil(result.first ?? 0), height: ceil(result.last ?? 0))
            guard size.width > 0, size.height > 0 else { throw CocoaError(.featureUnsupported) }
            // The snapshot covers only what the view shows, so fit the view to the diagram first.
            webView.setFrameSize(NSSize(width: max(size.width, 1), height: max(size.height, 1)))
            window?.setContentSize(webView.frame.size)
            let configuration = WKSnapshotConfiguration()
            configuration.rect = NSRect(origin: .zero, size: size)
            configuration.afterScreenUpdates = true
            state = .rendered(try await webView.takeSnapshot(configuration: configuration))
        } catch {
            let message = (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
            state = .failed(message.replacingOccurrences(of: "Error: ", with: ""))
        }
        finish(job.key, state)
        busy = false
        start()
    }

    private func finish(_ key: String, _ state: State) {
        states[key] = state
        waiting.removeValue(forKey: key)?.forEach { $0() }
    }

    private func finishAll(_ state: State) {
        for job in queue { finish(job.key, state) }
        queue.removeAll()
        svgJobs.forEach { $0.done(nil) }
        svgJobs.removeAll()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        start()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishAll(.failed(error.localizedDescription))
    }

    /// Only the bundled page loads; links inside diagrams go nowhere.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        navigationAction.request.url?.isFileURL == true && navigationAction.navigationType == .other ? .allow : .cancel
    }
}
