//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Common
import Foundation
import class TSCUtility.PercentProgressAnimation
import protocol TSCUtility.ProgressAnimationProtocol
import TSCBasic

public struct SwiftCWrapper {
  let arguments: [String]
  let swiftcPath: String
  let extraCodeCompleteOptions: [String]
  let stressTesterPath: String
  let astBuildLimit: Int?
  let requestDurationsOutputFile: URL?
  let rewriteModes: [RewriteMode]
  let requestKinds: Set<RequestKind>
  let conformingMethodTypes: [String]?
  let ignoreIssues: Bool
  let issueManager: IssueManager?
  let maxJobs: Int?
  let dumpResponsesPath: String?
  let failFast: Bool
  let suppressOutput: Bool

  public init(swiftcArgs: [String], swiftcPath: String,
              stressTesterPath: String, astBuildLimit: Int?,
              requestDurationsOutputFile: URL?,
              rewriteModes: [RewriteMode], requestKinds: Set<RequestKind>,
              conformingMethodTypes: [String]?,
              extraCodeCompleteOptions: [String], ignoreIssues: Bool,
              issueManager: IssueManager?, maxJobs: Int?,
              dumpResponsesPath: String?, failFast: Bool,
              suppressOutput: Bool) {
    self.arguments = swiftcArgs
    self.swiftcPath = swiftcPath
    self.stressTesterPath = stressTesterPath
    self.astBuildLimit = astBuildLimit
    self.extraCodeCompleteOptions = extraCodeCompleteOptions
    self.ignoreIssues = ignoreIssues
    self.issueManager = issueManager
    self.failFast = failFast
    self.suppressOutput = suppressOutput
    self.requestDurationsOutputFile = requestDurationsOutputFile
    self.rewriteModes = rewriteModes
    self.requestKinds = requestKinds
    self.conformingMethodTypes = conformingMethodTypes
    self.maxJobs = maxJobs
    self.dumpResponsesPath = dumpResponsesPath
  }

  public var swiftFiles: [(String, size: Int)] {
    let dependencyPaths = ["/.build/checkouts/", "/Pods/", "/Carthage/Checkouts", "/SourcePackages/checkouts/"]
    return arguments
      .flatMap { DriverFileList(at: $0)?.paths ?? [$0] }
      .filter { argument in
        // Check it looks like a Swift file path and is in the main project
        guard argument.hasSuffix(".swift") &&
            dependencyPaths.allSatisfy({ !argument.contains($0) }) else { return false }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: argument, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue
      }
      .sorted()
      .compactMap { file in
        guard let size = try? FileManager.default.attributesOfItem(atPath: file)[.size] else {
            // ignore files that couldn't be read
            return nil
        }
        return (file, size: Int(size as! UInt64))
      }
  }

  func run() throws -> Int32 {
    // Execute the compiler
    let swiftcResult = ProcessRunner(launchPath: swiftcPath, arguments: arguments)
      .run(captureStdout: false, captureStderr: false)
    guard swiftcResult.status == EXIT_SUCCESS else { return swiftcResult.status }

    let startTime = Date()

    // Determine the list of stress testing operations to perform
    let operations = swiftFiles.flatMap { (file, sizeInBytes) -> [StressTestOperation] in
      if let fileFilter = ProcessInfo.processInfo.environment["SK_STRESS_FILE_FILTER"] {
        if !fileFilter.split(separator: ",").contains(where: { file.contains($0) }) {
          return []
        }
      }
      // Split large files into multiple parts to improve load balancing
      let partCount = max(Int(sizeInBytes / 1000), 1)
      return rewriteModes.flatMap { (mode) -> [StressTestOperation] in
        // CodePointWidth.swift in swift-power-assert produces a lot of
        // expressions that are bogus and take very long to type check, causing
        // the stress tester to time out. Skip it for now until the underlying
        // issue is fixed.
        // https://github.com/apple/swift/issues/66785
        if file.contains("CodePointWidth.swift") && (mode == .insideOut || mode == .concurrent) {
          return []
        }
        return (1...partCount).map { part in
          StressTestOperation(file: file, rewriteMode: mode,
                              requests: requestKinds,
                              conformingMethodTypes: conformingMethodTypes,
                              limit: astBuildLimit,
                              part: (part, of: partCount),
                              offsetFilter: ProcessInfo.processInfo.environment["SK_OFFSET_FILTER"].flatMap { Int($0) },
                              reportResponses: dumpResponsesPath != nil,
                              compilerArgs: arguments,
                              executable: stressTesterPath,
                              swiftc: swiftcPath,
                              extraCodeCompleteOptions: extraCodeCompleteOptions,
                              requestDurationsOutputFile: requestDurationsOutputFile)
        }
      }
    }

    guard !operations.isEmpty else { return swiftcResult.status }

    // Run the operations, reporting progress
    let progress: ProgressAnimationProtocol?
    if !suppressOutput {
      progress = PercentProgressAnimation(stream: stderrStream, header: "Stress testing SourceKit...")
      progress?.update(step: 0, total: operations.count, text: "Scheduling \(operations.count) operations")
    } else {
      progress = nil
    }

    // Write out response data once it's received and all preceding operations are complete
    var orderingHandler: OrderingBuffer<[SourceKitResponseData]>? = nil
    var seenResponses = Set<UInt64>()
    if let dumpResponsesPath = dumpResponsesPath {
      orderingHandler = OrderingBuffer(itemCount: operations.count) { responses in
        self.writeResponseData(responses, to: dumpResponsesPath, seenResponses: &seenResponses)
      }
    }

    let queue = StressTesterOperationQueue(operations: operations, maxWorkers: maxJobs) { index, operation, completed, total -> Bool in
      let message = "\(operation.file) (\(operation.summary)): \(operation.status.name)"
      progress?.update(step: completed, total: total, text: message)
      orderingHandler?.complete(operation.responses, at: index, setLast: !operation.status.isPassed)
      operation.responses.removeAll()
      // We can control whether to stop scheduling new operations here. As long
      // as we return `true`, the stress tester continues to schedule new
      // test operations. To stop at the first failure, return
      // `operation.status.isPassed`.
      return true
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
    var detectedIssues: [StressTesterIssue] = []
    for operation in operations {
      switch operation.status {
      case .cancelled:
        fatalError("cancelled operation before failed operation")
      case .unexecuted:
        fatalError("unterminated operation")
      case .errored(let status):
        detectedIssues.append(.errored(status: status, file: operation.file,
                                 arguments: escapeArgs(operation.args)))
      case .failed(let sourceKitErrors):
        for sourceKitError in sourceKitErrors {
          detectedIssues.append(.failed(sourceKitError: sourceKitError,
                                  arguments: escapeArgs(operation.args)))
        }
        fallthrough
      case .passed:
        processedFiles.insert(operation.file)
      }
    }

    var hasUnexpectedIssue = false
    for detectedIssue in detectedIssues {
      let matchingSpec = try issueManager?.update(for: processedFiles, issue: detectedIssue)
      if issueManager == nil || matchingSpec != nil {
        hasUnexpectedIssue = true
      }
      try report(detectedIssue, matching: matchingSpec)
    }

    if hasUnexpectedIssue {
      return ignoreIssues ? swiftcResult.status : EXIT_FAILURE
    } else {
      return EXIT_SUCCESS
    }
  }

  private func writeResponseData(_ responses: [SourceKitResponseData], to path: String, seenResponses: inout Set<UInt64>) {
    // Only write the first of identical responses
    let data = responses
      .map { response -> String in
        let results = response.results.map { result in
          let hash = result.stableHash
          if !seenResponses.insert(hash).inserted {
            return "See <\(hash)>.\n"
          }
          return "<\(hash)> \(result)\n"
        }.joined()
        return """
          \(response.request)"
          \(results)

          """
      }
      .joined()
      .data(using: .utf8)!

    if let fileHandle = FileHandle(forWritingAtPath: path) {
      defer { fileHandle.closeFile() }
      fileHandle.seekToEndOfFile()
      fileHandle.write(data)
    } else {
      FileManager.default.createFile(atPath: path, contents: data)
    }
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
        stderrStream <<< String(data: json, encoding: .utf8)! <<< "\n\n"
      }
    }
  }
}

private struct OrderingBuffer<T> {
  private var items: [T?]
  private var nextItemIndex: Int
  private var endIndex: Int? = nil
  private let completionHandler: (T) -> ()

  init(itemCount: Int, completionHandler: @escaping (T) -> ()) {
    items = Array.init(repeating: nil, count: itemCount)
    nextItemIndex = items.startIndex
    self.completionHandler = completionHandler
  }

  mutating func complete(_ item: T, at index: Int, setLast: Bool) {
    precondition(index < items.endIndex && items[index] == nil && nextItemIndex < items.endIndex)
    items[index] = item
    if setLast && (endIndex == nil || (index + 1) < endIndex!) {
      endIndex = index + 1
    }
    while nextItemIndex < (endIndex ?? items.endIndex), let nextItem = items[nextItemIndex] {
      completionHandler(nextItem)
      nextItemIndex += 1
    }
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

public enum StressTesterIssue: CustomStringConvertible {
  case failed(sourceKitError: SourceKitError, arguments: String)
  case errored(status: Int32, file: String, arguments: String)

  public var description: String {
    switch self {
    case .failed(let sourceKitError, let arguments):
      return String(describing: sourceKitError) +
        "\n\nReproduce with:\nsk-stress-test \(arguments)\n"
    case .errored(let status, _, let arguments):
      return """
        sk-stress-test errored with exit code \(status). Reproduce with:
        sk-stress-test \(arguments)\n
        """
    }
  }

  /// Returns `true`if this issue represents a soft `SourceKitError`.
  public var isSoftError: Bool {
    switch self {
    case .failed(sourceKitError: let sourceKitError, arguments: _):
      return sourceKitError.isSoft
    case .errored:
      return false
    }
  }
}
