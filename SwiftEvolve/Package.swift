// swift-tools-version:4.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

#if os(Linux)
import Glibc
#else
import Darwin.C
#endif

let package = Package(
    name: "SwiftEvolve",
    products: [
        .executable(name: "swift-evolve", targets: ["swift-evolve"]),
        .library(name: "SwiftEvolve", targets: ["SwiftEvolve"])
    ],
    dependencies: [
        // See dependencies added below.
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "swift-evolve",
            dependencies: ["SwiftEvolve"]),
        .target(
            name: "SwiftEvolve",
            dependencies: ["TSCUtility", "SwiftSyntax"]),
        .testTarget(
          name: "SwiftEvolveTests",
          dependencies: ["SwiftEvolve"])
    ]
)

if getenv("SWIFTCI_USE_LOCAL_DEPS") == nil {
    // Building standalone.
    package.dependencies += [
        .package(url: "https://github.com/apple/swift-package-manager.git", .branch("master")),
        .package(url: "https://github.com/apple/swift-syntax.git", .branch("master")),
    ]
} else {
    package.dependencies += [
        .package(path: "../../swiftpm"),
        .package(path: "../../swift-syntax"),
    ]
}
