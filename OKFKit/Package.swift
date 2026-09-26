// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OKFKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "OKFKit", targets: ["OKFKit"])],
    dependencies: [.package(url: "https://github.com/jpsim/Yams.git", from: "6.2.0")],
    targets: [
        .target(name: "OKFKit", dependencies: ["Yams"]),
        .testTarget(name: "OKFKitTests", dependencies: ["OKFKit"])
    ]
)
