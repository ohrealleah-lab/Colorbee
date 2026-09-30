// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ColorbeeCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ColorbeeCore", targets: ["ColorbeeCore"]),
    ],
    targets: [
        .target(name: "ColorbeeCore"),
        .testTarget(name: "ColorbeeCoreTests", dependencies: ["ColorbeeCore"]),
    ]
)
