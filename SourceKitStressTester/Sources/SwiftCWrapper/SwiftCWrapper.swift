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

import Common
import Foundation
import func Utility.createProgressBar
import Basic

struct SwiftCWrapper {
  let arguments: [String]
  let swiftcPath: String
  let stressTesterPath: String
  let astBuildLimit: Int?
  let ignoreFailures: Bool
  let machineReadable: Bool
  let failFast: Bool

  init(swiftcArgs: [String], swiftcPath: String, stressTesterPath: String, astBuildLimit: Int?, ignoreFailures: Bool, machineReadable: Bool, failFast: Bool) {
    self.arguments = swiftcArgs
    self.swiftcPath = swiftcPath
    self.stressTesterPath = stressTesterPath
    self.astBuildLimit = astBuildLimit
    self.ignoreFailures = ignoreFailures
    self.machineReadable = machineReadable
    self.failFast = failFast
  }

  var swiftFiles: [String] {
    let dependencyPaths = ["/.build/checkouts/", "/Pods/", "/Carthage/Checkouts"]
    return arguments
      .filter { argument in
        argument.hasSuffix(".swift") && dependencyPaths.allSatisfy {!argument.contains($0)}
      }
      .sorted()
  }

  func run() -> Int32 {
    // Execute the compiler
    let swiftcResult = ProcessRunner(launchPath: swiftcPath, arguments: arguments).run(capturingOutput: false)
    guard swiftcResult.status == EXIT_SUCCESS else { return swiftcResult.status }

    let startTime = Date()

    // Determine the list of stress testing operations to perform
    let operations = swiftFiles.flatMap { file -> [StressTestOperation] in
      // Split large files into multiple parts to improve load balancing
      let sizeInBytes = try! FileManager.default.attributesOfItem(atPath: file)[.size]! as! UInt64
      let partCount = max(Int(sizeInBytes / 1000), 1)
      let modes: [RewriteMode] = [.none, .concurrent, .insideOut]
      return modes.flatMap { mode in
        (1...partCount).map { part in
          StressTestOperation(file: file, rewriteMode: mode, limit: astBuildLimit, part: (part, of: partCount), compilerArgs: arguments, executable: stressTesterPath)
        }
      }
    }

    // Run the operations, reporting progress
    let progress = createProgressBar(forStream: stderrStream, header: "Stress testing SourceKit...")
    progress.update(percent: 0, text: "Scheduling \(operations.count) operations")
    let queue = FailFastOperationQueue(operations: operations) { operation, completed, total -> Bool in
      let message = "\(operation.file) (\(operation.summary)): \(operation.status.name)"
      progress.update(percent: completed * 100 / total, text: message)
      return operation.status.isPassed
    }
    queue.waitUntilFinished()
    progress.complete(success: operations.allSatisfy {$0.status.isPassed})

    defer { stderrStream.flush() }

    let elapsedSeconds = -startTime.timeIntervalSinceNow
    stderrStream <<< "Runtime: \(elapsedSeconds.formatted() ?? String(elapsedSeconds))\n"

    // Report the list of processed files and the first failure (if any)
    var result = WrapperResult()
    for operation in operations where result.error == nil {
      switch operation.status {
      case .cancelled:
        fatalError("cancelled operation before failed operation")
      case .unexecuted:
        fatalError("unterminated operation")
      case .failed(let error):
        result.error = error
        fallthrough
      case .passed:
        result.processedFiles.insert(operation.file)
      }
    }

    if machineReadable {
      try! stderrStream <<< "[stress-tester]" <<< JSONEncoder().encode(result) <<< "\n"
      if let error = result.error {
        stderrStream <<< String(describing: error) <<< "\n"
      }
    } else {
      stderrStream <<< String(describing: result) <<< "\n"
    }

    if result.passed {
      return EXIT_SUCCESS
    }
    return ignoreFailures ? swiftcResult.status : EXIT_FAILURE
  }
}

struct WrapperResult: Codable, CustomStringConvertible {
  var processedFiles: Set<String> = []
  var error: SourceKitError? = nil

  var passed: Bool {
    return error == nil
  }

  var description: String {
    var output = ""
    if !processedFiles.isEmpty {
      output += """
        Processed files:
          \(processedFiles.sorted().joined(separator: "\n  "))\n
        """
    }
    if let error = error {
      output += "Detected failure: \(error)\n"
    } else {
      output += "No failures detected."
    }

    return output
  }
}

struct SwiftFile: Comparable {
  let file: URL

  init?(_ path: String) {
    self.file = URL(fileURLWithPath: path, isDirectory: false)
    guard isSwiftFile && isProjectFile else { return nil }
  }

  var isSwiftFile: Bool {
    return file.pathExtension == "swift"
  }

  var isProjectFile: Bool {
    let dependencyPaths = ["/.build/checkouts/", "/Pods/", "/Carthage/Checkouts"]
    return dependencyPaths.allSatisfy {!file.path.contains($0)}
  }

  static func < (lhs: SwiftFile, rhs: SwiftFile) -> Bool {
    return lhs.file.path < rhs.file.path
  }
}

fileprivate extension TimeInterval {
  func formatted() -> String? {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.hour, .minute, .second]
    formatter.allowsFractionalUnits = true
    formatter.maximumUnitCount = 3
    formatter.unitsStyle = .abbreviated

    return formatter.string(from: self)
  }
}
