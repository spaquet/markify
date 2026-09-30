// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MarkifyCLI",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../MarkifyMarkdown"), .package(path: "../OKFKit")],
    targets: [
        .executableTarget(name: "markify", dependencies: ["MarkifyMarkdown", "OKFKit"]),
        .testTarget(name: "MarkifyCLITests", dependencies: ["markify", "MarkifyMarkdown"])
    ]
)
