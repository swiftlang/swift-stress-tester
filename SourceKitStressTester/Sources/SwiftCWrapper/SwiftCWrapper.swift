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
import protocol Utility.ProgressBarProtocol
import Basic

struct SwiftCWrapper {
  let arguments: [String]
  let swiftcPath: String
  let stressTesterPath: String
  let astBuildLimit: Int?
  let ignoreIssues: Bool
  let issueManager: IssueManager?
  let failFast: Bool
  let suppressOutput: Bool

  init(swiftcArgs: [String], swiftcPath: String, stressTesterPath: String, astBuildLimit: Int?, ignoreIssues: Bool, issueManager: IssueManager?, failFast: Bool, suppressOutput: Bool) {
    self.arguments = swiftcArgs
    self.swiftcPath = swiftcPath
    self.stressTesterPath = stressTesterPath
    self.astBuildLimit = astBuildLimit
    self.ignoreIssues = ignoreIssues
    self.issueManager = issueManager
    self.failFast = failFast
    self.suppressOutput = suppressOutput
  }

  var swiftFiles: [String] {
    let dependencyPaths = ["/.build/checkouts/", "/Pods/", "/Carthage/Checkouts"]
    return arguments
      .filter { argument in
        argument.hasSuffix(".swift") && dependencyPaths.allSatisfy {!argument.contains($0)}
      }
      .sorted()
  }

  func run() throws -> Int32 {
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

    guard !operations.isEmpty else { return swiftcResult.status }

    // Run the operations, reporting progress
    let progress: ProgressBarProtocol?
    if !suppressOutput {
      progress = createProgressBar(forStream: stderrStream, header: "Stress testing SourceKit...")
      progress?.update(percent: 0, text: "Scheduling \(operations.count) operations")
    } else {
      progress = nil
    }

    let queue = FailFastOperationQueue(operations: operations) { operation, completed, total -> Bool in
      let message = "\(operation.file) (\(operation.summary)): \(operation.status.name)"
      progress?.update(percent: completed * 100 / total, text: message)
      return operation.status.isPassed
    }
    queue.waitUntilFinished()

    if !suppressOutput {
      progress?.complete(success: operations.allSatisfy {$0.status.isPassed})
      stderrStream <<< "\n"
      stderrStream.flush()

      // Report the overall runtime
      let elapsedSeconds = -startTime.timeIntervalSinceNow
      stderrStream <<< "Runtime: \(elapsedSeconds.formatted() ?? String(elapsedSeconds))\n\n"
      stderrStream.flush()
    }

    // Determine the set of processed files and the first failure (if any)
    var processedFiles = Set<String>()
    var detectedIssue: StressTesterIssue? = nil
    for operation in operations where detectedIssue == nil {
      switch operation.status {
      case .cancelled:
        fatalError("cancelled operation before failed operation")
      case .unexecuted:
        fatalError("unterminated operation")
      case .failed(let sourceKitError):
        detectedIssue = .failed(sourceKitError)
        processedFiles.insert(operation.file)
      case .errored(let status, let arguments):
        detectedIssue = .errored(status: status, file: operation.file, arguments: arguments.joined(separator: " "))
      case .passed:
        processedFiles.insert(operation.file)
      }
    }

    let matchingSpec = try issueManager?.update(for: processedFiles, issue: detectedIssue)
    try report(detectedIssue, matching: matchingSpec)

    if detectedIssue == nil || matchingSpec != nil {
      return EXIT_SUCCESS
    }
    return ignoreIssues ? swiftcResult.status : EXIT_FAILURE
  }

  private func report(_ issue: StressTesterIssue?, matching xIssue: ExpectedIssue? = nil) throws {
    guard !suppressOutput else { return }
    defer { stderrStream.flush() }

    guard let issue = issue else {
      stderrStream <<< "No failures detected.\n"
      return
    }

    if let xIssue = xIssue {
      stderrStream <<< "Detected expected failure [\(xIssue.issueUrl)]: \(issue)\n\n"
    } else {
      stderrStream <<< "Detected unexpected failure: \(issue)\n\n"
      if let issueManager = issueManager {
        let xfail = ExpectedIssue(matching: issue, issueUrl: "<issue url>",
                                    config: issueManager.activeConfig)
        let json = try issueManager.encoder.encode(xfail)
        stderrStream <<< "Add the following entry to the expected failures JSON file to mark it as expected:\n"
        stderrStream <<< json <<< "\n\n"
      }
    }
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
    // TODO: make this configurable
    let dependencyPaths = ["/.build/checkouts/", "/Pods/", "/Carthage/Checkouts", "/submodules/"]
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

enum StressTesterIssue: CustomStringConvertible {
  case failed(SourceKitError)
  case errored(status: Int32, file: String, arguments: String)

  var description: String {
    switch self {
    case .failed(let error):
      return String(describing: error)
    case .errored(let status, let file, let arguments):
      return """
        sk-stress-test errored
          exit code: \(status)
          file: \(file)
          arguments: \(arguments)
        """
    }
  }
}
