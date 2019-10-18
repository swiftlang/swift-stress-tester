// swift-tools-version:4.2

import PackageDescription

let package = Package(
  name: "SourceKitStressTester",
  products: [
    .executable(name: "sk-stress-test", targets: ["sk-stress-test"]),
    .executable(name: "sk-swiftc-wrapper", targets: ["sk-swiftc-wrapper"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-package-manager.git", .exact("0.3.0")),
    // FIXME: We should depend on master once master contains all the degybed files
    .package(url: "https://github.com/apple/swift-syntax.git", .branch("master-gen")),

  ],
  targets: [
    .target(
      name: "Common",
      dependencies: ["Utility"]),
    .target(
      name: "StressTester",
      dependencies: ["Common", "Utility", "SwiftSyntax"]),
    .target(
      name: "SwiftCWrapper",
      dependencies: ["Common", "Utility"]),

    .target(
      name: "sk-stress-test",
      dependencies: ["StressTester"]),
    .target(
      name: "sk-swiftc-wrapper",
      dependencies: ["SwiftCWrapper"]),

    .testTarget(
        name: "StressTesterToolTests",
        dependencies: ["StressTester"]),
    .testTarget(
      name: "SwiftCWrapperToolTests",
      dependencies: ["SwiftCWrapper"])
  ]
)
