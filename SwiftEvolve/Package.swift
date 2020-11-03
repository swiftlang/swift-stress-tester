// swift-tools-version:5.1

import PackageDescription

#if os(Linux)
import Glibc
#else
import Darwin.C
#endif

let sourcekitSearchPath: String
if let sourcekitSearchPathPointer = getenv("SWIFT_STRESS_TESTER_SOURCEKIT_SEARCHPATH") {
    sourcekitSearchPath = String(cString: sourcekitSearchPathPointer)
} else {
    // We cannot fatalError or otherwise fail here because SwiftSyntax parses
    // this package manifest while not specifying the 
    // SWIFT_STRESS_TESTER_SOURCEKIT_SEARCHPATH enviornment variable in the 
    // unified build.
    // The environment variable is only specified once we build SwiftEvolve.
    sourcekitSearchPath = ""
}

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
            dependencies: ["SwiftEvolve"]
        ),
        .target(
            name: "SwiftEvolve",
            dependencies: ["SwiftToolsSupport-auto", "SwiftSyntax"],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", sourcekitSearchPath])]
        ),
        .testTarget(
            name: "SwiftEvolveTests",
            dependencies: ["SwiftEvolve"],
            swiftSettings: [.unsafeFlags(["-Fsystem", sourcekitSearchPath])],
            // SwiftPM does not get the rpath for XCTests in multiroot packages right (rdar://56793593)
            // Add the correct rpath here
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../../../"])]
        )
    ]
)

if getenv("SWIFTCI_USE_LOCAL_DEPS") == nil {
    // Building standalone.
    package.dependencies += [
        .package(url: "https://github.com/apple/swift-tools-support-core.git", .branch("main")),
        .package(url: "https://github.com/apple/swift-syntax.git", .branch("main")),
    ]
} else {
    package.dependencies += [
        .package(path: "../../swiftpm/swift-tools-support-core"),
        .package(path: "../../swift-syntax"),
    ]
}
