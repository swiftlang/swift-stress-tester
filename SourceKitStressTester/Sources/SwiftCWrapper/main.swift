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

func main() {
  // Execute the compiler
  guard let compilerPath = getCompilerPath() else {
    log("error: Couldn't determine the swiftc executable to use. Please set SK_STRESS_SWIFTC.")
    exit(EXIT_FAILURE)
  }
  let swiftcArgs = Array(CommandLine.arguments[1...])
  let swiftcStatus = execute(path: compilerPath, args: swiftcArgs)
  guard swiftcStatus == EXIT_SUCCESS else { exit(swiftcStatus) }

  // Execute the stress tester
  guard let stressTesterPath = getStressTesterPath() else {
    log("error: Couldn't determine the sk-stress-test executable to use. Please set SK_STRESS_TEST.")
    exit(EXIT_FAILURE)
  }
  let swiftFiles = Array(swiftcArgs.filter { $0.hasSuffix(".swift") })
  let testerArgs = swiftFiles + ["--"] + swiftcArgs
  let testerStatus = execute(path: stressTesterPath, args: testerArgs)
  guard testerStatus != EXIT_SUCCESS else { return }

  /// Check if we should pass on stress tester failure
  let silenceFailure = ProcessInfo.processInfo.environment["SK_STRESS_SILENT"] != nil
  guard silenceFailure else { exit(testerStatus) }
  log("warning: sk-stress-test invocation failed with exit code \(testerStatus) but SK_STRESS_SILENT is set. Indicating success.")
}

func getCompilerPath() -> String? {
  // Check the environment
  if let envSwiftC = ProcessInfo.processInfo.environment["SK_STRESS_SWIFTC"] {
    return envSwiftC
  }

  // Use the selected Xcode's swiftc
  let pipe = Pipe()
  let xcrun = Process()
  xcrun.launchPath = "xcrun"
  xcrun.arguments = ["-f", "swiftc"]
  xcrun.standardOutput = pipe
  do {
    try xcrun.run()
  } catch {
    return nil
  }
  xcrun.waitUntilExit()
  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  return String(data: data, encoding: .utf8)
}

func getStressTesterPath() -> String? {
  // Check the environment
  if let envStressTester = ProcessInfo.processInfo.environment["SK_STRESS_TEST"] {
    return envStressTester
  }
  // Look adjacent to the wrapper
  let wrapperPath = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent()
    .appendingPathComponent("sk-stress-tester")
    .path

  guard FileManager.default.isExecutableFile(atPath: wrapperPath) else { return nil }
  return wrapperPath
}

/// Launches the executable at path with the provided arguments and waits for it
/// to complete, returning its termination status.
func execute(path: String, args: [String]) -> Int32 {
  let process = Process()
  process.launchPath = path
  process.arguments = args

  process.standardOutput = FileHandle.standardOutput
  process.standardError = FileHandle.standardError
  process.standardInput = FileHandle.standardInput
  process.environment = ProcessInfo.processInfo.environment
  process.currentDirectoryPath = FileManager.default.currentDirectoryPath

  do {
    try process.run()
  } catch {
    log("error: Failed to run process: \(path) \(args.joined(separator: " "))")
    return EXIT_FAILURE
  }

  process.waitUntilExit()
  return process.terminationStatus
}

/// Writes the given message to stderr prefixed with "[sk-swiftc-wrapper]" for
/// searchability.
func log(_ message: String) {
  var standardError = FileHandle.standardError
  print("[sk-swiftc-wrapper] \(message)\n", to: &standardError)
}

// Allow standardError/standardOutput to be passed as a target to print
extension FileHandle : TextOutputStream {
  public func write(_ string: String) {
    guard let data = string.data(using: .utf8) else { return }
    self.write(data)
  }
}

main()
