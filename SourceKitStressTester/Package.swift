// swift-tools-version:4.2

import PackageDescription

let package = Package(
  name: "SourceKitStressTester",
  products: [
    .executable(name: "sk-stress-test", targets: ["StressTester"]),
    .executable(name: "sk-swiftc-wrapper", targets: ["SwiftCWrapper"]),
  ],
  dependencies: [],
  targets: [
    .target(
      name: "StressTester",
      dependencies: []),
    .target(
      name: "SwiftCWrapper",
      dependencies: []),
  ]
)
