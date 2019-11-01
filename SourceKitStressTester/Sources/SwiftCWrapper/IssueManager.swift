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

/// Keeps track of the detected failures and their status (expected/unexpected)
/// across multiple wrapper invocations
public struct IssueManager {
  let activeConfig: String
  let expectedIssuesFile: URL
  let resultsFile: URL
  let encoder: JSONEncoder

  /// - parameters:
  ///   - expectedFailuresFile: the URL of a JSON file describing the
  ///   expected failures
  ///   - resultsFile: the URL of the file to use to store failures across
  ///   multiple invocations
  init(activeConfig: String, expectedIssuesFile: URL, resultsFile: URL) {
    self.activeConfig = activeConfig
    self.expectedIssuesFile = expectedIssuesFile
    self.resultsFile = resultsFile
    self.encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
  }

  /// Updates this instance's backing resultsFile to account for the files
  /// processed by this invocation of the wrapper, and the issue it detected,
  /// if any.
  ///
  /// - parameters:
  ///   - for: the set of files processed
  ///   - issue: the detected issue, if any
  func update(for files: Set<String>, issue: StressTesterIssue?) throws -> ExpectedIssue? {
    let failureSpecs = try getIssueSpecifications(applicableTo: files)
    var state = try getCurrentState()

    var matchingSpec: ExpectedIssue? = nil
    let added = files.subtracting(state.processedFiles)
    state.unmatchedExpectedIssues.append(contentsOf: failureSpecs.filter { spec in
      added.contains {spec.isApplicable(toPath: $0)}
    })
    state.processedFiles.formUnion(files)
    if let issue = issue {
      if let match = failureSpecs.first(where: {$0.matches(issue)}) {
        state.expectedIssues[match.issueUrl, default: []].append(issue)
        state.expectedIssueMessages[match.issueUrl, default: []].append(String(describing: issue))
        state.unmatchedExpectedIssues.removeAll(where: {$0 == match})
        matchingSpec = match
      } else {
        let xfail = ExpectedIssue(matching: issue, issueUrl: "<issue url>",
                                  config: activeConfig)
        let json = try encoder.encode(xfail)
        state.issues.append(issue)
        state.issueMessages.append("""
          \(String(describing: issue))
          Add the following entry to the expected failures JSON file to mark it as expected:
          \(String(data: json, encoding: .utf8)!)"
          """)
      }
    }

    let data = try encoder.encode(state)
    FileManager.default.createFile(atPath: resultsFile.path, contents: data)
    return matchingSpec
  }

  private func getIssueSpecifications(applicableTo files: Set<String>) throws -> [ExpectedIssue] {
    let data = try Data(contentsOf: expectedIssuesFile)
    return try JSONDecoder().decode([ExpectedIssue].self, from: data)
      .filter { spec in
        spec.applicableConfigs.contains(activeConfig) &&
          files.contains { spec.isApplicable(toPath: $0) }
    }
  }

  private func getCurrentState() throws -> IssueManagerState {
    guard FileManager.default.fileExists(atPath: resultsFile.path) else {
      return IssueManagerState()
    }
    let data = try Data(contentsOf: resultsFile)
    return try JSONDecoder().decode(IssueManagerState.self, from: data)
  }
}

/// Holds the state of the IssueManager that will be serialized across
/// invocations
fileprivate struct IssueManagerState: Codable {
  var expectedIssues = Dictionary<String, [StressTesterIssue]>()
  var expectedIssueMessages = Dictionary<String, [String]>()
  var issues = [StressTesterIssue]()
  var issueMessages = [String]()

  var processedFiles = Set<String>()
  var unmatchedExpectedIssues = [ExpectedIssue]()
}

extension DocumentModification {
  /// A String with enough information to unique identify the modified state of
  /// a document in comparison to other modifications produced by the stress
  /// tester.
  var summaryCode: String {
    return "\(mode)-\(content.count)"
  }
}

extension StressTesterIssue: Codable {
  private enum CodingKeys: String, CodingKey {
    case kind, sourceKitError, status, file, arguments
  }
  private enum BaseMessage: String, Codable {
    case failed, errored
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(BaseMessage.self, forKey: .kind) {
    case .failed:
      let sourceKitError = try container.decode(SourceKitError.self, forKey: .sourceKitError)
      self = .failed(sourceKitError)
    case .errored:
      let status = try container.decode(Int32.self, forKey: .status)
      let file = try container.decode(String.self, forKey: .file)
      let arguments = try container.decode(String.self, forKey: .arguments)
      self = .errored(status: status, file: file, arguments: arguments)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .failed(let sourceKitError):
      try container.encode(BaseMessage.failed, forKey: .kind)
      try container.encode(sourceKitError, forKey: .sourceKitError)
    case .errored(let status, let file, let arguments):
      try container.encode(BaseMessage.errored, forKey: .kind)
      try container.encode(status, forKey: .status)
      try container.encode(file, forKey: .file)
      try container.encode(arguments, forKey: .arguments)
    }
  }
}
