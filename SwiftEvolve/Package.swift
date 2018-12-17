// swift-tools-version:4.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftEvolve",
    products: [
        .executable(name: "swift-evolve", targets: ["SwiftEvolve"]),
        .library(name: "SwiftEvolveKit", targets: ["SwiftEvolveKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-package-manager.git", from: "0.2.0"),
        .package(path: "../../swift-syntax"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "SwiftEvolve",
            dependencies: ["SwiftEvolveKit", "SwiftSyntax", "Utility"]),
        .target(
            name: "SwiftEvolveKit",
            dependencies: ["SwiftSyntax"]),
        .testTarget(
            name: "SwiftEvolveTests",
            dependencies: ["SwiftEvolve"]),
        .testTarget(
          name: "SwiftEvolveKitTests",
          dependencies: ["SwiftEvolveKit"])
    ]
)
