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
  // 1. Execute the compiler
  guard let compilerPath = getCompilerPath() else {
    log("error: Couldn't determine the swiftc executable to use. Please set SK_STRESS_SWIFTC.")
    exit(EXIT_FAILURE)
  }
  let swiftcArgs = Array(CommandLine.arguments[1...])
  let swiftc = ProcessRunner(launchPath: compilerPath, arguments: swiftcArgs)
  let swiftcStatus = swiftc.run().status
  guard swiftcStatus == EXIT_SUCCESS else { exit(swiftcStatus) }

  // 2. Execute the stress tester
  guard let stressTesterPath = getStressTesterPath() else {
    log("error: Couldn't determine the sk-stress-test executable to use. Please set SK_STRESS_TEST.")
    exit(EXIT_FAILURE)
  }
  let files = swiftcArgs.filter(isSwiftProjectFile).sorted()
  guard !files.isEmpty else { return }
  log("Stress testing \(files.count) Swift files")

  var codeCompleteLimit: Int? = nil
  if let limit = ProcessInfo.processInfo.environment["SK_STRESS_CODECOMPLETE_LIMIT"] {
    codeCompleteLimit = Int(limit)
  }

  // Split large files into multiple 'pages'
  let instances = pageLargeFiles(files, codeCompleteLimit: codeCompleteLimit).map { filePage -> ProcessRunner in
    var args = ["--page", "\(filePage.pageNumber)/\(filePage.pageCount)"]
    if let limit = codeCompleteLimit {
      args += ["--limit", String(limit)]
    }
    args += [filePage.file, "--"] + swiftcArgs
    return ProcessRunner(launchPath: stressTesterPath, arguments: args, redirectOutput: true)
  }

  // Process in parallel
  let processQueue = ProcessQueue(instances, maxWorkers: ProcessInfo.processInfo.activeProcessorCount, stopOnFailure: true)
  let (failed, results) = processQueue.run()
  for result in results {
    forward(result.stdout)
  }

  guard failed else { return }

  /// Check if we should pass on stress tester failure
  let silenceFailure = ProcessInfo.processInfo.environment["SK_STRESS_SILENT"] != nil
  guard silenceFailure else { exit(EXIT_FAILURE) }
  log("warning: sk-stress-test invocation failed but SK_STRESS_SILENT is set. Indicating success.")
}

func isSwiftProjectFile(_ argument: String) -> Bool {
  let dependencyPaths = ["/.build/checkouts/", "/Pods/", "/Carthage/Checkouts"]
  return argument.hasSuffix(".swift") && dependencyPaths.allSatisfy{ !argument.contains($0) }
}

typealias FilePage = (file: String, pageNumber: Int, pageCount: Int)

func pageLargeFiles(_ files: [String], codeCompleteLimit: Int?) -> [FilePage] {
  return files.flatMap { file -> [FilePage] in
    var pageCount = Swift.max(sizeInBytes(of: file)! / 250, 1)
    if let limit = codeCompleteLimit {
      // Aim for roughtly 25 code completion requests per page
      pageCount = Swift.min(pageCount, Swift.max(limit / 25, 1))
    }
    return (1...pageCount).map {(file, $0, pageCount)}
  }
}

func getCompilerPath() -> String? {
  // Check the environment
  if let envSwiftC = ProcessInfo.processInfo.environment["SK_STRESS_SWIFTC"] {
    return envSwiftC
  }

  // Use the selected Xcode's swiftc
  let pipe = Pipe()
  let xcrun = Process()
  var args = ["-f", "swiftc"]
  if let toolchain = ProcessInfo.processInfo.environment["TOOLCHAINS"] {
    args += ["--toolchain", toolchain]
  }
  xcrun.launchPath = "/usr/bin/xcrun"
  xcrun.arguments = args
  xcrun.standardOutput = pipe
  xcrun.launch()
  xcrun.waitUntilExit()
  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
}

func getStressTesterPath() -> String? {
  // Check the environment
  if let envStressTester = ProcessInfo.processInfo.environment["SK_STRESS_TEST"] {
    return envStressTester
  }
  // Look adjacent to the wrapper
  let wrapperPath = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent()
    .appendingPathComponent("sk-stress-test")
    .path

  guard FileManager.default.isExecutableFile(atPath: wrapperPath) else { return nil }
  return wrapperPath
}

func sizeInBytes(of path: String) -> Int? {
  let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.fileSizeKey])
  return values?.fileSize
}

/// Writes the given message to stderr prefixed with "[sk-swiftc-wrapper]" for
/// searchability.
func log(_ message: String) {
  print("[sk-swiftc-wrapper] \(message)\n")
}

func forward(_ message: String) {
  print(message, terminator: "")
}

main()
