// swift-tools-version: 6.0
import PackageDescription

// Builds Markify's help from help/*.md into the app's Help Book and the website. See scripts/build-help.sh.
let package = Package(
    name: "HelpBuilder",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../MarkifyMarkdown")],
    targets: [
        .executableTarget(name: "HelpBuilder", dependencies: [.product(name: "MarkifyMarkdown", package: "MarkifyMarkdown")])
    ]
)
