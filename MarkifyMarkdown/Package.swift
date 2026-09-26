// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MarkifyMarkdown",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MarkifyMarkdown", targets: ["MarkifyMarkdown"])],
    dependencies: [.package(url: "https://github.com/swiftlang/swift-markdown", from: "0.8.0")],
    targets: [
        .target(name: "MarkifyMarkdown", dependencies: [.product(name: "Markdown", package: "swift-markdown")]),
        .testTarget(name: "MarkifyMarkdownTests", dependencies: ["MarkifyMarkdown"])
    ]
)
