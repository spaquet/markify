import AppKit
import WebKit

/// Renders fenced `mermaid` blocks to images with the bundled Mermaid, in one offscreen web view shared by every window.
/// The page allows no network access or navigation; a diagram is rendered once per source and appearance.
@MainActor final class MermaidRenderer: NSObject, WKNavigationDelegate {
    static let shared = MermaidRenderer()

    enum State {
        case rendering
        case rendered(NSImage)
        /// Rendered at this size, but its image was dropped to stay within the memory budget; drawing it renders it again.
        case evicted(NSSize)
        /// Mermaid's message for a diagram it cannot parse.
        case failed(String)
    }

    private var states: [String: State] = [:]
    private var waiting: [String: [ObjectIdentifier: () -> Void]] = [:]
    private var queue: [(key: String, source: String, dark: Bool)] = []
    /// Exports waiting for a diagram's SVG; they share the web view, so one render runs at a time.
    private var svgJobs: [(source: String, id: String, done: (String?) -> Void)] = []
    private var svgCount = 0
    private var busy = false
    private var ready = false
    private var webView: WKWebView?
    private var window: NSWindow?
    private var generation = UUID()
    private var deadline: DispatchWorkItem?
    private var currentRaster: String?
    private var currentSVG: (source: String, id: String, done: (String?) -> Void)?
    private var costs: [String: Int] = [:]
    /// When each diagram was last drawn, on a counter; the least recently drawn are evicted first.
    private var lastUsed: [String: Int] = [:]
    private var clock = 0
    /// The bytes rendered diagrams may hold together, shared by every window.
    var memoryBudget = 32_000_000
    var pendingCount: Int { queue.count + svgJobs.count + (busy ? 1 : 0) }

    /// The diagram's state, starting a render on first request; `onChange` runs once when it settles.
    func state(of source: String, dark: Bool, owner: AnyObject? = nil, onChange: @escaping () -> Void) -> State {
        let key = "\(dark):\(source)"
        guard source.utf8.count <= 64_000 else { return .failed("Diagram exceeds the 64 KB limit.") }
        let consumer = ObjectIdentifier(owner ?? self)
        if let state = states[key] {
            waiting[key, default: [:]][consumer] = onChange
            return state
        }
        guard pendingCount < 32 else { return .failed("Too many diagrams are waiting to render.") }
        // Renders requested without an owner are never released; drop the settled ones before the cache grows large.
        if states.count >= 64 {
            let renderer = ObjectIdentifier(self)
            for old in Array(states.keys) where old != currentRaster && waiting[old, default: [:]].keys.allSatisfy({ $0 == renderer }) {
                if case .rendering = states[old] { continue }
                states[old] = nil; costs[old] = nil; waiting[old] = nil; lastUsed[old] = nil
            }
        }
        clock += 1
        lastUsed[key] = clock
        states[key] = .rendering
        waiting[key] = [consumer: onChange]
        queue.append((key, source, dark))
        start()
        return .rendering
    }

    /// The settled state for drawing; it marks the diagram as recently drawn and renders an evicted one again.
    func cached(_ source: String, dark: Bool) -> State? {
        let key = "\(dark):\(source)"
        guard let state = states[key] else { return nil }
        clock += 1
        lastUsed[key] = clock
        if case .evicted = state, currentRaster != key, !queue.contains(where: { $0.key == key }), pendingCount < 32 {
            queue.append((key, source, dark))
            start()
        }
        return state
    }

    /// The diagram as SVG markup in the light theme, for export; nil when Mermaid cannot render it.
    func svg(for source: String) async -> String? {
        guard !Task.isCancelled, source.utf8.count <= 64_000, pendingCount < 32 else { return nil }
        svgCount += 1
        let id = "markify-diagram-\(svgCount)"
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                svgJobs.append((source, id, { continuation.resume(returning: $0) }))
                start()
            }
        } onCancel: {
            Task { @MainActor in self.cancelSVG(id) }
        }
    }

    private func cancelSVG(_ id: String) {
        if let index = svgJobs.firstIndex(where: { $0.id == id }) { svgJobs.remove(at: index).done(nil) }
        if currentSVG?.id == id { currentSVG?.done(nil); currentSVG = nil }
    }

    func release(owner: AnyObject, keeping sources: Set<String> = []) {
        let consumer = ObjectIdentifier(owner)
        for key in Array(waiting.keys) where !sources.contains(key) {
            waiting[key]?.removeValue(forKey: consumer)
            guard waiting[key]?.isEmpty == true else { continue }
            waiting[key] = nil
            queue.removeAll { $0.key == key }
            if key != currentRaster { states[key] = nil; costs[key] = nil; lastUsed[key] = nil }
        }
    }

    private func armDeadline() {
        deadline?.cancel()
        let token = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == token else { return }
            self.recover("Diagram rendering timed out.")
        }
        deadline = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
    }

    /// Invalidates late callbacks before settling every waiting export and editor request.
    func recover(_ message: String) {
        generation = UUID()
        deadline?.cancel()
        deadline = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        window?.contentView = nil
        webView = nil; window = nil; ready = false; busy = false
        if let key = currentRaster { finish(key, .failed(message)) }
        currentRaster = nil
        currentSVG?.done(nil)
        currentSVG = nil
        finishAll(.failed(message))
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
            // Rendering needs the view in a window; this one never appears on screen.
            let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 800, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = view
            self.window = window
            webView = view
            armDeadline()
            view.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
            return
        }
        guard ready, !busy else { return }
        if !svgJobs.isEmpty {
            busy = true
            let job = svgJobs.removeFirst()
            currentSVG = job
            armDeadline()
            renderSVG(job)
            return
        }
        guard !queue.isEmpty else { return }
        busy = true
        let next = queue.removeFirst()
        currentRaster = next.key
        armDeadline()
        render(next)
    }

    private func renderSVG(_ job: (source: String, id: String, done: (String?) -> Void)) {
        let token = generation
        webView?.callAsyncJavaScript("""
            mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: 'default' });
            const { svg } = await mermaid.render(id, source);
            return svg;
            """, arguments: ["source": job.source, "id": job.id], in: nil, in: .page) { [weak self] result in
                guard let self, self.generation == token else { return }
                let svg = (try? result.get()) as? String
                let current = self.currentSVG
                self.currentSVG = nil
                current?.done(svg.flatMap { $0.utf8.count <= 1_000_000 ? $0 : nil })
                self.completed()
            }
    }

    private func render(_ job: (key: String, source: String, dark: Bool)) {
        let token = generation
        // Diagrams that fill their container (gantt) otherwise take the previous diagram's width.
        webView?.setFrameSize(NSSize(width: 800, height: 600))
        window?.setContentSize(NSSize(width: 800, height: 600))
        webView?.callAsyncJavaScript("""
            mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: dark ? 'dark' : 'default' });
            const { svg } = await mermaid.render('diagram' + Date.now(), source);
            const box = document.getElementById('diagram');
            box.innerHTML = svg;
            // Responsive SVGs otherwise inherit the previous diagram's width.
            const drawing = box.querySelector('svg');
            const bounds = drawing.viewBox.baseVal;
            if (bounds.width > 0 && bounds.height > 0) {
                drawing.style.maxWidth = 'none';
                drawing.style.width = bounds.width + 'px';
                drawing.style.height = bounds.height + 'px';
            }
            const rect = box.getBoundingClientRect();
            return [rect.width, rect.height];
            """, arguments: ["source": job.source, "dark": job.dark], in: nil, in: .page) { [weak self] result in
                guard let self, self.generation == token else { return }
                do {
                    let dimensions = try result.get() as? [Double] ?? []
                    let size = NSSize(width: ceil(dimensions.first ?? 0), height: ceil(dimensions.last ?? 0))
                    guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
                          size.width <= 4096, size.height <= 4096, size.width * size.height <= 4_194_304,
                          let view = self.webView else { throw CocoaError(.featureUnsupported) }
                    view.setFrameSize(size)
                    self.window?.setContentSize(size)
                    let configuration = WKPDFConfiguration()
                    configuration.rect = NSRect(origin: .zero, size: size)
                    // A PDF keeps the diagram as vectors: sharp at any column width, and a fraction of a bitmap's memory.
                    view.createPDF(configuration: configuration) { [weak self] result in
                        guard let self, self.generation == token else { return }
                        switch result {
                        case .success(let data):
                            self.finish(job.key, Self.image(pdf: data, size: size).map(State.rendered) ?? .failed("Diagram PDF could not be read."))
                        case .failure(let error):
                            self.finish(job.key, .failed(error.localizedDescription))
                        }
                        self.currentRaster = nil
                        self.completed()
                    }
                } catch {
                    let message = (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
                    self.finish(job.key, .failed(String(message.prefix(2000)).replacingOccurrences(of: "Error: ", with: "")))
                    self.currentRaster = nil
                    self.completed()
                }
            }
    }

    private func completed() {
        deadline?.cancel()
        deadline = nil
        busy = false
        start()
    }

    private func finish(_ key: String, _ state: State) {
        // Released while rendering: nobody draws it, so it holds no memory.
        guard waiting[key] != nil else { states[key] = nil; costs[key] = nil; lastUsed[key] = nil; return }
        if case .rendered(let image) = state {
            costs[key] = Self.cost(of: image)
            clock += 1
            lastUsed[key] = clock
            evict(sparing: key)
        }
        states[key] = state
        waiting[key]?.values.forEach { $0() }
    }

    /// The diagram's PDF as an image of its rendered size. It is drawn from the vectors each time, so it holds no bitmap.
    static func image(pdf data: Data, size: NSSize) -> NSImage? {
        guard let representation = NSPDFImageRep(data: data) else { return nil }
        let image = NSImage(size: size)
        image.addRepresentation(representation)
        image.cacheMode = .never
        return image
    }

    /// The bytes an image holds: its PDF data, or its pixels.
    static func cost(of image: NSImage) -> Int {
        if let pdf = image.representations.lazy.compactMap({ $0 as? NSPDFImageRep }).first { return pdf.pdfRepresentation.count }
        guard let bitmap = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 0 }
        return bitmap.bytesPerRow * bitmap.height
    }

    /// Drops the least recently drawn images until the cache fits its budget. A new render is never refused:
    /// evicted diagrams keep their size, so layout stays put, and render again when they are drawn.
    private func evict(sparing key: String) {
        var total = costs.values.reduce(0, +)
        for old in costs.keys.sorted(by: { lastUsed[$0, default: 0] < lastUsed[$1, default: 0] }) {
            guard total > memoryBudget else { return }
            guard old != key, case .rendered(let image) = states[old] else { continue }
            states[old] = .evicted(image.size)
            total -= costs.removeValue(forKey: old) ?? 0
        }
    }

    private func finishAll(_ state: State) {
        for job in queue { finish(job.key, state) }
        queue.removeAll()
        svgJobs.forEach { $0.done(nil) }
        svgJobs.removeAll()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard self.webView === webView else { return }
        deadline?.cancel()
        ready = true
        start()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        recover(error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        recover(error.localizedDescription)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        recover("The diagram renderer stopped. Edit the diagram to retry.")
    }

    /// Only the bundled page loads; links inside diagrams go nowhere.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        navigationAction.request.url?.isFileURL == true && navigationAction.navigationType == .other ? .allow : .cancel
    }
}
