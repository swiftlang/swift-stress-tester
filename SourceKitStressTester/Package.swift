// swift-tools-version:5.3

import PackageDescription
import Foundation

/// Return the value of the configuration parameter with the given `name` either
/// from the environment variables or, if that doesn't exist, from a
/// `Package-config.json` file located next to `Package.swift`, like the following:
/// ```
/// {
///   "SWIFT_STRESS_TESTER_SOURCEKIT_SEARCHPATH": "/path/to/lib/with/sourcekitd.framework",
///   "SWIFT_STRESS_TESTER_SWIFTSYNTAX_SEARCHPATH": "/path/to/folder/with/SwiftSyntax.framework"
/// }
/// ```
/// If none of these exist, return `nil`.
func getConfigParam(_ name: String) -> String? {
  if let envValue = ProcessInfo.processInfo.environment[name] {
    return envValue
  }

  let configFile = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Package-config.json")

  let configData: Data
  do {
    configData = try Data(contentsOf: configFile)
  } catch {
    // Config file not found. That's fine. Return `nil` without complaining.
    return nil
  }
  do {
    let config = try JSONDecoder().decode([String: String].self, from: configData)
    return config[name]
  } catch {
    // We couldn't parse the Package-config.json, probably malformatted JSON.
    // Print the error, which shows up as a warning in Xcode.
    print("Loading Package-config.json failed with error: \(error)")
    return nil
  }
}

// MARK: - Configuration options variables

/// Path to the directory containing sourcekitd.framework.
/// Required for a successful build.
/// We can't fatalError if the environment variable is not set because
/// SwiftSyntax parses this package manifest while not specifying the
/// `SWIFT_STRESS_TESTER_SOURCEKIT_SEARCHPATH` enviornment variable in the
/// unified build.
/// The environment variable is only specified once we build the stress tester.
let sourceKitSearchPath: String? = getConfigParam("SWIFT_STRESS_TESTER_SOURCEKIT_SEARCHPATH")

/// Path to a directory containing SwiftSyntax.framework and SwiftParser.framework.
/// Optional. If not specified, SwiftSyntax will be built from source.
let swiftSyntaxSearchPath: String? = getConfigParam("SWIFT_STRESS_TESTER_SWIFTSYNTAX_SEARCHPATH")

/// If specified expect swift-tools-support-core, swift-argument-parser and swift-syntax
/// to be checked out next to swift-stresss-tester.
let useLocalDependencies = getConfigParam("SWIFTCI_USE_LOCAL_DEPS") != nil

// MARK: - Conditional build settings

var stressTesterTargetDependencies: [Target.Dependency] = [
  "Common",
  .product(name: "ArgumentParser", package: "swift-argument-parser"),
  "SwiftSourceKit",
  .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
]

// Unsafe Swift/Linker settings that all targets linking against sourcekitd need to include
var sourceKitSwiftSettings: [String] = []
var sourceKitLinkerSettings: [String] = []
if let sourceKitSearchPath = sourceKitSearchPath {
  sourceKitSwiftSettings = ["-Fsystem", sourceKitSearchPath]
  sourceKitLinkerSettings = ["-Xlinker", "-F", "-Xlinker", sourceKitSearchPath,
                             "-Xlinker", "-rpath", "-Xlinker", sourceKitSearchPath]

}

// Unsafe Swift/Linker settings that all targets linking against SwiftSyntax need to include
var swiftSyntaxSwiftSettings: [String] = []
var swiftSyntaxLinkerSettings: [String] = []

// If we have a SwiftSyntax search path look for it in that directory.
// Otherwise, add SwiftSyntax as a SwiftPM dependency.
if let swiftSyntaxSearchPath = swiftSyntaxSearchPath {
  swiftSyntaxSwiftSettings = ["-F", swiftSyntaxSearchPath]
  swiftSyntaxLinkerSettings = ["-Xlinker", "-F", "-Xlinker", swiftSyntaxSearchPath,
                               "-Xlinker", "-rpath", "-Xlinker", swiftSyntaxSearchPath]
} else {
  stressTesterTargetDependencies += [
    .product(name: "SwiftDiagnostics", package: "swift-syntax"),
    .product(name: "SwiftParser", package: "swift-syntax"),
    .product(name: "SwiftParserDiagnostics", package: "swift-syntax"),
    .product(name: "SwiftSyntax", package: "swift-syntax"),
    .product(name: "SwiftOperators", package: "swift-syntax"),
  ]
}

// MARK: - Package description

let package = Package(
  name: "SourceKitStressTester",
  platforms: [.macOS(.v11)],
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
      swiftSettings: [.unsafeFlags(sourceKitSwiftSettings)],
      linkerSettings: [.unsafeFlags(sourceKitLinkerSettings)]
    ),
    .target(
      name: "Common"
    ),
    .target(
      name: "StressTester",
      dependencies: stressTesterTargetDependencies,
      swiftSettings: [.unsafeFlags(sourceKitSwiftSettings + swiftSyntaxSwiftSettings)],
      linkerSettings: [.unsafeFlags(sourceKitLinkerSettings + swiftSyntaxLinkerSettings)]
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
      swiftSettings: [.unsafeFlags(sourceKitSwiftSettings + swiftSyntaxSwiftSettings)],
      linkerSettings: [.unsafeFlags(sourceKitLinkerSettings + swiftSyntaxLinkerSettings)]
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
      swiftSettings: [.unsafeFlags(sourceKitSwiftSettings)],
      linkerSettings: [.unsafeFlags(sourceKitLinkerSettings)]
    ),
    .testTarget(
      name: "SwiftCWrapperToolTests",
      dependencies: ["SwiftCWrapper", "TestHelpers"]
    )
  ]
)

if !useLocalDependencies {
  // Building standalone.
  package.dependencies += [
    .package(url: "https://github.com/apple/swift-tools-support-core.git", .branch("main")),
    .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMinor(from: "1.0.1")),
  ]
  if swiftSyntaxSearchPath == nil {
    package.dependencies.append(.package(url: "https://github.com/apple/swift-syntax.git", .branch("main")))
  }
} else {
  package.dependencies += [
    .package(path: "../../swift-tools-support-core"),
    .package(path: "../../swift-argument-parser"),
  ]
  if swiftSyntaxSearchPath == nil {
    package.dependencies.append(.package(path: "../../swift-syntax"))
  }
}
