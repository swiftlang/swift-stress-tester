//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

public struct SwiftCWrapperTool {
  let arguments: [String]
  let environment: [String: String]

  public init(arguments: [String] = CommandLine.arguments, environment: [String: String] = ProcessInfo.processInfo.environment) {
    self.arguments = arguments
    self.environment = environment
  }

  public func run() throws -> Int32 {
    let swiftcEnv = EnvOption("SK_STRESS_SWIFTC", type: String.self)
    let stressTesterEnv = EnvOption("SK_STRESS_TEST", type: String.self)
    let ignoreFailuresEnv = EnvOption("SK_STRESS_SILENT", type: Bool.self)
    let astBuildLimitEnv = EnvOption("SK_STRESS_AST_BUILD_LIMIT", type: Int.self)

    // FailureManager params
    let expectedFailuresPathEnv = EnvOption("SK_XFAILS_PATH", type: String.self)
    let outputPathEnv = EnvOption("SK_STRESS_OUTPUT", type: String.self)
    let activeConfigEnv = EnvOption("SK_STRESS_ACTIVE_CONFIG", type: String.self)

    guard let swiftc = (try swiftcEnv.get(from: environment) ?? getDefaultSwiftCPath()) else {
      throw EnvOptionError.noFallback(key: swiftcEnv.key, target: "swiftc")
    }
    guard let stressTester = (try stressTesterEnv.get(from: environment) ?? defaultStressTesterPath) else {
      throw EnvOptionError.noFallback(key: stressTesterEnv.key, target: "sk-stress-test")
    }
    let ignoreFailures = try ignoreFailuresEnv.get(from: environment) ?? false
    let astBuildLimit = try astBuildLimitEnv.get(from: environment)

    var failureManager: FailureManager? = nil
    if let expectedFailuresPath = try expectedFailuresPathEnv.get(from: environment),
      let outputPath = try outputPathEnv.get(from: environment),
      let activeConfig = try activeConfigEnv.get(from: environment) {
      failureManager = FailureManager(
        activeConfig: activeConfig,
        expectedFailuresFile: URL(fileURLWithPath: expectedFailuresPath, isDirectory: false),
        resultsFile: URL(fileURLWithPath: outputPath, isDirectory: false)
      )
    }

    let wrapper = SwiftCWrapper(swiftcArgs: Array(arguments.dropFirst()),
                                swiftcPath: swiftc,
                                stressTesterPath: stressTester,
                                astBuildLimit: astBuildLimit,
                                ignoreFailures: ignoreFailures,
                                failureManager: failureManager,
                                failFast: true)
    return try wrapper.run()
  }

  var defaultStressTesterPath: String? {
    let wrapperPath = URL(fileURLWithPath: arguments[0])
      .deletingLastPathComponent()
      .appendingPathComponent("sk-stress-test")
      .path

    guard FileManager.default.isExecutableFile(atPath: wrapperPath) else { return nil }
    return wrapperPath
  }

  func getDefaultSwiftCPath(for toolchain: String? = nil) -> String? {
    var args = ["-f", "swiftc"]
    if let toolchain = toolchain {
      args += ["--toolchain", toolchain]
    }
    let result = ProcessRunner(launchPath: "/usr/bin/xcrun", arguments: args).run()
    guard result.status == EXIT_SUCCESS else { return nil }

    return String(data: result.stdout, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

struct EnvOption<T: LosslessStringConvertible> {
  let key: String
  let type: T.Type

  init(_ key: String, type: T.Type) {
    self.key = key
    self.type = type
  }

  func get(from environment: [String: String]) throws -> T? {
    guard let value = environment[key] else {
      return nil
    }
    guard let typed = type.init(value) else {
      throw EnvOptionError.typeMismatch(key: key, value: value, expectedType: type)
    }
    return typed
  }
}

public enum EnvOptionError: Swift.Error, CustomStringConvertible {
  case typeMismatch(key: String, value: String, expectedType: Any.Type)
  case noFallback(key: String, target: String)

  public var description: String {
    switch self {
    case .typeMismatch(let key, let value, let expectedType):
      return "environment variable '\(key)' should have a value of type '\(expectedType)'; given '\(value)'"
    case .noFallback(let key, let target):
      return "couldn't locate \(target); please set environment variable \(key) to its path"
    }
  }
}
