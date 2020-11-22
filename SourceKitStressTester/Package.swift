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
  // The environment variable is only specified once we build the stress tester.
  sourcekitSearchPath = ""
}

let package = Package(
  name: "SourceKitStressTester",
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
      swiftSettings: [.unsafeFlags(["-Fsystem", sourcekitSearchPath])],
      linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", sourcekitSearchPath,
                                     "-Xlinker", "-F", "-Xlinker", sourcekitSearchPath])]
    ),
    .target(
      name: "Common"
    ),
    .target(
      name: "StressTester",
      dependencies: ["Common", "ArgumentParser", "SwiftSyntax", "SwiftSourceKit"],
      swiftSettings: [.unsafeFlags(["-Fsystem", sourcekitSearchPath])],
      linkerSettings: [.unsafeFlags(["-Xlinker", "-F", "-Xlinker", sourcekitSearchPath])]
    ),
    .target(
      name: "SwiftCWrapper",
      dependencies: ["Common", "SwiftToolsSupport-auto"]
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
    .package(url: "https://github.com/apple/swift-argument-parser.git", .exact("0.3.0")),
    .package(url: "https://github.com/apple/swift-syntax.git", .branch("main")),
  ]
} else {
  package.dependencies += [
    .package(path: "../../swift-tools-support-core"),
    .package(path: "../../swift-argument-parser"),
    .package(path: "../../swift-syntax"),
  ]
}
