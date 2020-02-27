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
  let stressTesterPath: String
  let astBuildLimit: Int?
  let rewriteModes: [RewriteMode]
  let requestKinds: [RequestKind]
  let conformingMethodTypes: [String]?
  let ignoreIssues: Bool
  let issueManager: IssueManager?
  let maxJobs: Int?
  let dumpResponsesPath: String?
  let failFast: Bool
  let suppressOutput: Bool

  public init(swiftcArgs: [String], swiftcPath: String, stressTesterPath: String, astBuildLimit: Int?, rewriteModes: [RewriteMode]?, requestKinds: [RequestKind]?, conformingMethodTypes: [String]?, ignoreIssues: Bool, issueManager: IssueManager?, maxJobs: Int?, dumpResponsesPath: String?, failFast: Bool, suppressOutput: Bool) {
    self.arguments = swiftcArgs
    self.swiftcPath = swiftcPath
    self.stressTesterPath = stressTesterPath
    self.astBuildLimit = astBuildLimit
    self.ignoreIssues = ignoreIssues
    self.issueManager = issueManager
    self.failFast = failFast
    self.suppressOutput = suppressOutput
    self.rewriteModes = rewriteModes ?? [.none, .concurrent, .insideOut]
    self.requestKinds = requestKinds ?? [.format, .cursorInfo, .rangeInfo, .codeComplete, .collectExpressionType]
    self.conformingMethodTypes = conformingMethodTypes
    self.maxJobs = maxJobs
    self.dumpResponsesPath = dumpResponsesPath
  }

  public var swiftFiles: [(String, size: Int)] {
    let dependencyPaths = ["/.build/checkouts/", "/Pods/", "/Carthage/Checkouts"]
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
    let swiftcResult = ProcessRunner(launchPath: swiftcPath, arguments: arguments).run(capturingOutput: false)
    guard swiftcResult.status == EXIT_SUCCESS else { return swiftcResult.status }

    let startTime = Date()

    // Determine the list of stress testing operations to perform
    let operations = swiftFiles.flatMap { (file, sizeInBytes) -> [StressTestOperation] in
      // Split large files into multiple parts to improve load balancing
      let partCount = max(Int(sizeInBytes / 1000), 1)
      return rewriteModes.flatMap { mode in
        (1...partCount).map { part in
          StressTestOperation(file: file, rewriteMode: mode, requests: requestKinds, conformingMethodTypes: conformingMethodTypes, limit: astBuildLimit, part: (part, of: partCount), reportResponses: dumpResponsesPath != nil, compilerArgs: arguments, executable: stressTesterPath)
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

    let queue = FailFastOperationQueue(operations: operations, maxWorkers: maxJobs) { index, operation, completed, total -> Bool in
      let message = "\(operation.file) (\(operation.summary)): \(operation.status.name)"
      progress?.update(step: completed, total: total, text: message)
      orderingHandler?.complete(operation.responses, at: index, setLast: !operation.status.isPassed)
      operation.responses.removeAll()
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
      case .errored(let status, let arguments):
        detectedIssue = .errored(status: status, file: operation.file, arguments: arguments.joined(separator: " "))
      case .failed(let sourceKitError):
        detectedIssue = .failed(sourceKitError)
        fallthrough
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
        stderrStream <<< json <<< "\n\n"
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

public enum RequestKind: String, CaseIterable {
  case cursorInfo = "CursorInfo"
  case rangeInfo = "RangeInfo"
  case codeComplete = "CodeComplete"
  case typeContextInfo = "TypeContextInfo"
  case conformingMethodList = "ConformingMethodList"
  case collectExpressionType = "CollectExpressionType"
  case format = "Format"
  case all = "All"
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

public enum StressTesterIssue: CustomStringConvertible {
  case failed(SourceKitError)
  case errored(status: Int32, file: String, arguments: String)

  public var description: String {
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
