// swift-tools-version:5.1

import PackageDescription
#if os(Linux)
import Glibc
#else
import Darwin.C
#endif

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
      name: "Common",
      dependencies: ["TSCUtility"]
    ),
    .target(
      name: "StressTester",
      dependencies: ["Common", "TSCUtility", "SwiftSyntax"]
    ),
    .target(
      name: "SwiftCWrapper",
      dependencies: ["Common", "TSCUtility"]
    ),

    .target(
      name: "sk-stress-test",
      dependencies: ["StressTester"]
    ),
    .target(
      name: "sk-swiftc-wrapper",
      dependencies: ["SwiftCWrapper"]
    ),

    .testTarget(
      name: "StressTesterToolTests",
      dependencies: ["StressTester"],
      // SwiftPM does not get the rpath for XCTests in multiroot packages right (rdar://56793593)
      // Add the correct rpath here
      linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../../../"])]
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
    .package(url: "https://github.com/apple/swift-package-manager.git", .branch("master")),
    .package(url: "https://github.com/apple/swift-syntax.git", .branch("master")),
  ]
} else {
  package.dependencies += [
    .package(path: "../../swiftpm"),
    .package(path: "../../swift-syntax"),
  ]
}
