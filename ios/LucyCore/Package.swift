// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LucyCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "LucyCore", targets: ["LucyCore"])],
    targets: [
        .target(name: "LucyCore"),
        .testTarget(name: "LucyCoreTests", dependencies: ["LucyCore"]),
    ]
)
