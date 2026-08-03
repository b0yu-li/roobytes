// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Roobytes",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Roobytes", targets: ["Roobytes"]),
        .library(name: "RoobytesCore", targets: ["RoobytesCore"]),
        .executable(name: "RoobytesCoreTests", targets: ["RoobytesCoreTests"]),
    ],
    targets: [
        .target(
            name: "RoobytesObjC",
            path: "Sources/RoobytesObjC",
            publicHeadersPath: "include"
        ),
        .target(
            name: "RoobytesCore",
            dependencies: ["RoobytesObjC"],
            path: "Sources/Roobytes"
        ),
        .executableTarget(
            name: "Roobytes",
            dependencies: ["RoobytesCore"],
            path: "Sources/RoobytesApp"
        ),
        // Executable harness (not SPM testTarget) — CLT has no XCTest / Testing modules.
        .executableTarget(
            name: "RoobytesCoreTests",
            dependencies: ["RoobytesCore"],
            path: "Tests/RoobytesCoreTests"
        ),
    ]
)
