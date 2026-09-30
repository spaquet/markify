import Foundation
import Testing

struct QuickLookTests {
    @Test func previewExtensionIsBundled() throws {
        let plugins = try #require(Bundle.main.builtInPlugInsURL)
        let bundle = try #require(Bundle(url: plugins.appendingPathComponent("MarkifyQuickLook.appex")))
        let info = try #require(bundle.infoDictionary?["NSExtension"] as? [String: Any])
        let attributes = try #require(info["NSExtensionAttributes"] as? [String: Any])
        #expect(info["NSExtensionPointIdentifier"] as? String == "com.apple.quicklook.preview")
        #expect(attributes["QLIsDataBasedPreview"] as? Bool == true)
        #expect(Set(attributes["QLSupportedContentTypes"] as? [String] ?? []) == ["net.daringfireball.markdown", "com.mdx"])
        #expect(bundle.url(forResource: "mermaid", withExtension: "html") != nil)
        #expect(bundle.url(forResource: "mermaid.min", withExtension: "js") != nil)
        let helper = bundle.bundleURL.appendingPathComponent("Contents/XPCServices/PreviewImages.xpc")
        #expect(Bundle(url: helper)?.bundleIdentifier == "com.stephanepaquet.Markify.PreviewImages")
    }
}
