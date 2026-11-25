// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyLocCore",
    platforms: [
        .iOS("26.0"),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "MyLocCore",
            targets: ["MyLocCore"]
        ),
    ],
    targets: [
        .target(
            name: "MyLocCore",
            path: "Sources/MyLocCore"
        ),
        .testTarget(
            name: "MyLocCoreTests",
            dependencies: ["MyLocCore"],
            path: "Tests/MyLocCoreTests"
        ),
    ]
)
