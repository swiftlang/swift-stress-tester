// swift-tools-version:4.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftEvolve",
    products: [
        .executable(name: "swift-evolve", targets: ["swift-evolve"]),
        .library(name: "SwiftEvolve", targets: ["SwiftEvolve"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-package-manager.git", .exact("0.3.0"))
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "swift-evolve",
            dependencies: ["SwiftEvolve"]),
        .target(
            name: "SwiftEvolve",
            dependencies: ["Utility"]),
        .testTarget(
          name: "SwiftEvolveTests",
          dependencies: ["SwiftEvolve"])
    ]
)
