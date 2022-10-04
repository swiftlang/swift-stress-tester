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
import Common

struct ParsedMessages {
  fileprivate(set) var sourceKitErrors: [SourceKitError] = []
  fileprivate(set) var sourceKitResponses: [SourceKitResponseData] = []
}

final class StressTestOperation: Operation {
  enum Status {
    /// Indicates the operation is still pending
    case unexecuted
    /// Indicates the operation was cancelled
    case cancelled
    /// Indicates the operation was executed and no issues were found
    case passed
    /// Indicates the operation was executed and issues were found
    case failed(sourceKitError: [SourceKitError])
    /// Indicates the operation was executed, but the stress tester itself failed
    case errored(status: Int32)

    var name: String {
      switch self {
      case .unexecuted:
        return "unexecuted"
      case .cancelled:
        return "cancelled"
      case .passed:
        return "passed"
      case .failed:
        return "failed"
      case .errored:
        return "errored"
      }
    }

    var isPassed: Bool {
      if case .passed = self {
        return true
      }
      return false
    }
  }

  let file: String
  let args: [String]
  var status: Status = .unexecuted
  var responses = [SourceKitResponseData]()

  private let part: (Int, of: Int)
  private let mode: RewriteMode
  private let process: ProcessRunner

  init(file: String, rewriteMode: RewriteMode, requests: Set<RequestKind>,
       conformingMethodTypes: [String]?, limit: Int?, part: (Int, of: Int),
       offsetFilter: Int?,
       reportResponses: Bool, compilerArgs: [String], executable: String,
       swiftc: String, extraCodeCompleteOptions: [String],
       requestDurationsOutputFile: URL?) {
    var stressTesterArgs = ["--format", "json", "--rewrite-mode", rewriteMode.rawValue]
    if let offsetFilter = offsetFilter {
      stressTesterArgs += ["--offset-filter", String(offsetFilter)]
    } else {
      stressTesterArgs += ["--page", "\(part.0)/\(part.of)"]
    }
    if let limit = limit {
      stressTesterArgs += ["--limit", String(limit)]
    }
    if let requestDurationsOutputFile = requestDurationsOutputFile {
      stressTesterArgs += ["--request-durations-output-file", requestDurationsOutputFile.path]
    }
    stressTesterArgs += requests.flatMap { ["--request", $0.rawValue] }
    if let types = conformingMethodTypes {
      stressTesterArgs += types.flatMap { ["--type-list-item", $0] }
    }
    if reportResponses {
      stressTesterArgs += ["--report-responses"]
    }
    stressTesterArgs += extraCodeCompleteOptions.flatMap { ["--extra-code-complete-options", $0] }
    stressTesterArgs += ["--swiftc", swiftc]
    stressTesterArgs.append(file)
    stressTesterArgs.append("--")
    stressTesterArgs.append(contentsOf: compilerArgs)

    self.file = file
    self.args = stressTesterArgs
    self.part = part
    self.mode = rewriteMode
    self.process = ProcessRunner(launchPath: executable,
                                 arguments: stressTesterArgs)
  }

  var summary: String {
    return "rewrite \(mode.rawValue) \(part.0)/\(part.of)"
  }

  override func main() {
    guard !isCancelled else {
      status = .cancelled
      return
    }

    let result = process.run()
    if isCancelled {
      status = .cancelled
    } else if let parsed = parseMessages(result.stdout) {
      if result.status == EXIT_SUCCESS {
        status = .passed
        self.responses = parsed.sourceKitResponses
      } else if !parsed.sourceKitErrors.isEmpty {
        status = .failed(sourceKitError: parsed.sourceKitErrors)
        self.responses = parsed.sourceKitResponses
      } else {
        // A non-successful exit code with no error produced-> stress tester failure
        status = .errored(status: result.status)
      }
    } else {
      // Non-empty unparseable output -> treat this as a stress tester failure
      status = .errored(status: result.status)
    }
  }

  /// Parses the given data as a sequence of newline-separated, JSON-encoded `StressTesterMessage`s.
  ///
  /// - returns: A tuple of the detected `SourceKitError` (if one was produced) and a possibly-empty list of `SourceKitReponseData`s. If the input data was non-empty and couldn't be parsed, or if more than one detected error was produced, returns nil.
  private func parseMessages(_ data: Data) -> ParsedMessages? {
    let terminator = UInt8(ascii: "\n")
    var parsed = ParsedMessages()

    for data in data.split(separator: terminator, omittingEmptySubsequences: true) {
      guard let message = StressTesterMessage(from: data) else { return nil }
      switch message {
      case .detected(let error):
        parsed.sourceKitErrors.append(error)
      case .produced(let responseData):
        parsed.sourceKitResponses.append(responseData)
      }
    }
    return parsed
  }

  override func cancel() {
    super.cancel()
    process.terminate()
  }
}
