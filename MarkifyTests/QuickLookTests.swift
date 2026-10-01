import Foundation
import Testing
import AppKit
import Quartz
import WebKit
import Darwin

struct QuickLookTests {
    @Test @MainActor func viewBasedPreviewRendersAndHandlesAnchorAndLocalLinkClicks() async throws {
        let plugins = try #require(Bundle.main.builtInPlugInsURL)
        let extensionURL = plugins.appendingPathComponent("MarkifyQuickLook.appex")
        let library = extensionURL.appendingPathComponent("Contents/MacOS/MarkifyQuickLook.debug.dylib")
        // Xcode's Debug extension code lives in this dylib; load the actual controller rather than a copy.
        let handle = try #require(dlopen(library.path, RTLD_NOW))
        _ = handle // Keep the Objective-C classes registered for the lifetime of the test process.
        let type = try #require(NSClassFromString("MarkifyQuickLook.PreviewProvider") as? NSViewController.Type)
        let controller = type.init(nibName: nil, bundle: nil)
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        controller.view.layoutSubtreeIfNeeded()
        let web = try #require(controller.view.subviews.compactMap { $0 as? WKWebView }.first)
        let message = try #require(controller.view.subviews.compactMap { $0 as? NSTextField }.first)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        defer { try? FileManager.default.removeItem(at: file) }
        try "# Preview\n\n[Local](missing%20note.md) [Anchor](#preview)\n\n<script>window.previewInjected = true</script>\n".write(to: file, atomically: true, encoding: .utf8)
        let preview = try #require(controller as? QLPreviewingController)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            preview.preparePreviewOfFile?(at: file) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
        let deadline = Date().addingTimeInterval(10)
        var heading: String?
        while heading != "Preview", Date() < deadline {
            heading = (try? await web.evaluateJavaScript("document.querySelector('h1')?.textContent")) as? String
            if heading != "Preview" { try await Task.sleep(for: .milliseconds(50)) }
        }
        #expect(controller.title == "Preview")
        #expect(heading == "Preview")
        #expect(try await web.evaluateJavaScript("typeof window.previewInjected") as? String == "undefined")
        #expect(web.frame.width > 0 && web.frame.height > 0)
        _ = try await web.evaluateJavaScript("document.querySelector('a[href=\"#preview\"]').click()")
        let anchorDeadline = Date().addingTimeInterval(5)
        var hash: String?
        while hash != "#preview", Date() < anchorDeadline {
            hash = (try? await web.evaluateJavaScript("window.location.hash")) as? String
            if hash != "#preview" { try await Task.sleep(for: .milliseconds(50)) }
        }
        #expect(hash == "#preview")
        _ = try await web.evaluateJavaScript("document.querySelector('a[href^=\"markify-preview:\"]').click()")
        let openDeadline = Date().addingTimeInterval(12)
        while message.stringValue.isEmpty || message.stringValue.hasPrefix("Opening "), Date() < openDeadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(!message.isHidden)
        #expect(!message.stringValue.isEmpty && !message.stringValue.hasPrefix("Opening "))
        #expect(web.url?.isFileURL != true)
        #expect(message.isSelectable)
        #expect(message.textColor == .systemRed)
    }

    @Test func previewExtensionIsBundled() throws {
        let plugins = try #require(Bundle.main.builtInPlugInsURL)
        let bundle = try #require(Bundle(url: plugins.appendingPathComponent("MarkifyQuickLook.appex")))
        let info = try #require(bundle.infoDictionary?["NSExtension"] as? [String: Any])
        let attributes = try #require(info["NSExtensionAttributes"] as? [String: Any])
        #expect(info["NSExtensionPointIdentifier"] as? String == "com.apple.quicklook.preview")
        #expect(attributes["QLIsDataBasedPreview"] as? Bool == false)
        #expect(Set(attributes["QLSupportedContentTypes"] as? [String] ?? []) == ["net.daringfireball.markdown", "com.mdx"])
        #expect(bundle.url(forResource: "mermaid", withExtension: "html") != nil)
        #expect(bundle.url(forResource: "mermaid.min", withExtension: "js") != nil)
        let helper = bundle.bundleURL.appendingPathComponent("Contents/XPCServices/PreviewImages.xpc")
        #expect(Bundle(url: helper)?.bundleIdentifier == "com.stephanepaquet.Markify.PreviewImages")
    }
}
