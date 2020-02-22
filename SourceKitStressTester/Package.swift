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
      name: "Common",
      dependencies: ["SwiftToolsSupport-auto"]
    ),
    .target(
      name: "StressTester",
      dependencies: ["Common", "SwiftToolsSupport-auto", "SwiftSyntax", "SwiftSourceKit"],
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

    .testTarget(
      name: "StressTesterToolTests",
      dependencies: ["StressTester"],
      swiftSettings: [.unsafeFlags(["-Fsystem", sourcekitSearchPath])],
      // SwiftPM does not get the rpath for XCTests in multiroot packages right (rdar://56793593)
      // Add the correct rpath here
      linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../../../",
                                     "-Xlinker", "-F", "-Xlinker", sourcekitSearchPath])]
    ),
    .testTarget(
      name: "SwiftCWrapperToolTests",
      dependencies: ["SwiftCWrapper"],
      // SwiftPM does not get the rpath for XCTests in multiroot packages right (rdar://56793593)
      // Add the correct rpath here
      linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../../../"])]
    )
  ]
)

if getenv("SWIFTCI_USE_LOCAL_DEPS") == nil {
  // Building standalone.
  package.dependencies += [
    .package(url: "https://github.com/apple/swift-tools-support-core.git", .branch("master")),
    .package(url: "https://github.com/apple/swift-syntax.git", .branch("master")),
  ]
} else {
  package.dependencies += [
    .package(path: "../../swiftpm/TSC"),
    .package(path: "../../swift-syntax"),
  ]
}
