// swift-tools-version:5.3

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
  // The environment variable is only specified once we build the stress tester.
  sourcekitSearchPath = ""
}

let package = Package(
  name: "SourceKitStressTester",
  platforms: [.macOS(.v10_12)],
  products: [
    .executable(name: "sk-stress-test", targets: ["sk-stress-test"]),
    .executable(name: "sk-swiftc-wrapper", targets: ["sk-swiftc-wrapper"]),
  ],
  dependencies: [
    // See dependencies added below.
  ],
  targets: [
    .target(
      name: "SwiftSourceKit",
      dependencies: [],
      exclude: [
        "UIDs.swift.gyb"
      ],
      swiftSettings: [.unsafeFlags(["-Fsystem", sourcekitSearchPath])],
      linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", sourcekitSearchPath,
                                     "-Xlinker", "-F", "-Xlinker", sourcekitSearchPath])]
    ),
    .target(
      name: "Common"
    ),
    .target(
      name: "StressTester",
      dependencies: [
        "Common",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftSyntaxParser", package: "swift-syntax"),
        "SwiftSourceKit",
        .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core")
      ],
      swiftSettings: [.unsafeFlags(["-Fsystem", sourcekitSearchPath])],
      linkerSettings: [.unsafeFlags(["-Xlinker", "-F", "-Xlinker", sourcekitSearchPath])]
    ),
    .target(
      name: "SwiftCWrapper",
      dependencies: [
        "Common",
        .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core")
      ]
    ),

    .target(
      name: "sk-stress-test",
      dependencies: ["StressTester"],
      swiftSettings: [.unsafeFlags(["-Fsystem", sourcekitSearchPath])],
      linkerSettings: [.unsafeFlags(["-Xlinker", "-F", "-Xlinker", sourcekitSearchPath])]
    ),
    .target(
      name: "sk-swiftc-wrapper",
      dependencies: ["SwiftCWrapper"]
    ),

    .target(
      name: "TestHelpers"
    ),
    .testTarget(
      name: "StressTesterToolTests",
      dependencies: ["StressTester", "TestHelpers"],
      swiftSettings: [.unsafeFlags(["-Fsystem", sourcekitSearchPath])],
      linkerSettings: [.unsafeFlags(["-Xlinker", "-F", "-Xlinker", sourcekitSearchPath])]
    ),
    .testTarget(
      name: "SwiftCWrapperToolTests",
      dependencies: ["SwiftCWrapper", "TestHelpers"]
    )
  ]
)

if getenv("SWIFTCI_USE_LOCAL_DEPS") == nil {
  // Building standalone.
  package.dependencies += [
    .package(url: "https://github.com/apple/swift-tools-support-core.git", .branch("main")),
    .package(url: "https://github.com/apple/swift-argument-parser.git", .exact("0.4.3")),
    .package(url: "https://github.com/apple/swift-syntax.git", .branch("main")),
  ]
} else {
  package.dependencies += [
    .package(path: "../../swift-tools-support-core"),
    .package(path: "../../swift-argument-parser"),
    .package(path: "../../swift-syntax"),
  ]
}
