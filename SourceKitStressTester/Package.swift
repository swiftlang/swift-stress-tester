// swift-tools-version:4.2

import PackageDescription

let package = Package(
  name: "SourceKitStressTester",
  products: [
    .executable(name: "sk-stress-test", targets: ["StressTester"]),
    .executable(name: "sk-swiftc-wrapper", targets: ["SwiftCWrapper"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-package-manager.git", from: "0.1.0")
  ],
  targets: [
    .target(
      name: "StressTester",
      dependencies: ["Utility"]),
    .target(
      name: "SwiftCWrapper",
      dependencies: []),
  ]
)
